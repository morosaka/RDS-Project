// SignalProcessing/StrokeDetection.swift v1.1.0
/**
 * Multi-validated stroke detection state machine for rowing analysis.
 * Identifies catch/finish points from detrended velocity using dynamic
 * thresholds with safety floors, swing ratio validation, adaptive timing,
 * rearm-to-valley mechanism, and acceleration pattern confirmation.
 * Source: docs/specs/fusion-engine.md §Step 3 (Stroke Detection)
 * Reference: docs/stroke_extraction_report.md (RowDataLab algorithm)
 * --- Revision History ---
 * v1.1.0 - 2026-03-03 - Multi-validated rewrite: zero-phase baseline, safety
 *          floors, swing ratio, adaptive timing, accel validation, rearm.
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Foundation

extension DSP {

    /// Stroke detection state.
    private enum StrokeState {
        case seekValley
        case seekPeak
    }

    /// Detects strokes in a rowing velocity signal with multi-layer validation.
    ///
    /// Pipeline (from fusion-engine.md §Step 3):
    /// 1. Zero-phase smooth (15 samples)
    /// 2. Adaptive baseline (zero-phase, ~6s window)
    /// 3. Detrend: `velDet = smoothed - baseline`
    /// 4. Dynamic thresholds from P95/P05 with safety floors
    /// 5. State machine: SEEK_VALLEY → SEEK_PEAK with rearm-to-valley
    /// 6. Multi-layer validation:
    ///    - V1: Swing ratio ≥ adaptive minimum
    ///    - V2: Adaptive timing (rolling median period rejection)
    ///    - V3: Acceleration pattern (pre-catch negative, post-catch positive)
    /// 7. Duration filter: physiological range 0.8–5.0s
    ///
    /// - Parameters:
    ///   - timestampsMs: Time values in **milliseconds** (matches SensorDataBuffers.timestamp).
    ///   - velocity: Velocity signal (m/s), typically `fus_cal_ts_vel_inertial`.
    ///   - surgeAccel: Filtered surge acceleration in G units (optional). When provided,
    ///     enables V3 accel pattern validation to reject wave/turbulence artifacts.
    ///   - sampleRate: Sample rate in Hz (default 200).
    /// - Returns: Array of detected stroke events (times in seconds per StrokeEvent convention).
    public static func detectStrokes(
        timestampsMs: ContiguousArray<Double>,
        velocity: ContiguousArray<Float>,
        surgeAccel: ContiguousArray<Float>? = nil,
        sampleRate: Double = 200.0
    ) -> [StrokeEvent] {
        let n = velocity.count
        guard n > 100, n == timestampsMs.count else { return [] }

        // --- Step 1: Zero-phase smooth (15 samples = halfWindow 7) ---
        let smoothed = zeroPhaseSmooth(velocity, halfWindowSize: 7)

        // --- Step 2: Adaptive baseline (zero-phase, ~6s window) ---
        // halfWindow = 3s worth of samples → full window ≈ 6s
        let baselineHalfWindow = Int(FusionConstants.strokeDetBaselineWindowS / 2.0 * sampleRate)
        let baseline = zeroPhaseSmooth(smoothed, halfWindowSize: baselineHalfWindow)

        // --- Step 3: Detrend ---
        var detrended = ContiguousArray<Float>(repeating: 0, count: n)
        for i in 0..<n {
            detrended[i] = smoothed[i] - baseline[i]
        }

        // --- Step 4: Dynamic thresholds with safety floors ---
        let p95 = quantile(detrended, q: 0.95)
        let p05 = quantile(detrended, q: 0.05)
        guard !p95.isNaN, !p05.isNaN, p95 > p05 else { return [] }

        let detRange = p95 - p05
        let eps = FusionConstants.strokeDetEps
        let rangeRatio = detRange / max(p95, eps)

        let hUp = max(
            detRange * FusionConstants.strokeDetThresholdFraction,
            p95 * FusionConstants.strokeDetThresholdFloorFraction
        )
        let hDn = max(
            detRange * FusionConstants.strokeDetThresholdFraction,
            p95 * FusionConstants.strokeDetThresholdFloorFraction
        )
        let rearmDn = max(
            detRange * FusionConstants.strokeDetRearmFraction,
            p95 * FusionConstants.strokeDetRearmFloorFraction
        )
        let swingMinRatio = max(
            FusionConstants.strokeDetSwingRatioFloor,
            min(FusionConstants.strokeDetSwingRatioCeil,
                FusionConstants.strokeDetSwingRatioScale * rangeRatio)
        )

        // --- Step 5: State machine with rearm-to-valley ---
        let canValidateAccel = surgeAccel != nil && surgeAccel!.count == n
        var candidates: [(startIdx: Int, startTime: Double, peakVal: Float, valleyVal: Float)] = []
        var state: StrokeState = .seekValley
        var candidateMin: Float = .infinity
        var candidateMinIdx: Int = -1
        var candidateMax: Float = -.infinity
        var recentPeriods: [Double] = []

        for i in 0..<n {
            let v = detrended[i]

            switch state {
            case .seekValley:
                if v < candidateMin {
                    candidateMin = v
                    candidateMinIdx = i
                }
                if v > candidateMin + hUp {
                    // Valley confirmed → transition to seek peak
                    state = .seekPeak
                    candidateMax = v
                }

            case .seekPeak:
                // Rearm-to-valley: deep reversal means the upswing was a false alarm
                if v < candidateMin - rearmDn {
                    state = .seekValley
                    candidateMin = v
                    candidateMinIdx = i
                    candidateMax = -.infinity
                    continue
                }

                if v > candidateMax {
                    candidateMax = v
                }

                if v < candidateMax - hDn {
                    // Peak confirmed → run validations

                    // V1: Swing ratio
                    let swingAbs = candidateMax - candidateMin
                    let swingRatio = swingAbs / max(abs(candidateMax), eps)
                    let isSignificant = swingRatio >= swingMinRatio

                    // V2: Adaptive timing
                    let estimatedPeriod = estimatedStrokePeriod(recentPeriods)
                    var isTimingGood = true
                    if let lastCand = candidates.last {
                        let dt = timestampsMs[candidateMinIdx] - lastCand.startTime
                        if dt < estimatedPeriod * FusionConstants.strokeDetTimingRejectFraction {
                            isTimingGood = false
                        }
                    } else {
                        // First candidate: reject if too close to signal start
                        if candidateMinIdx < 10 { isTimingGood = false }
                    }

                    // V3: Acceleration pattern
                    var passAccelPattern = true
                    if canValidateAccel, isSignificant, isTimingGood {
                        passAccelPattern = validateAccelPattern(
                            surgeAccel: surgeAccel!,
                            timestamps: timestampsMs,
                            catchIdx: candidateMinIdx,
                            signalLength: n
                        )
                    }

                    // Accept candidate if all validations pass
                    if isSignificant && isTimingGood && passAccelPattern {
                        candidates.append((
                            startIdx: candidateMinIdx,
                            startTime: timestampsMs[candidateMinIdx],
                            peakVal: candidateMax,
                            valleyVal: candidateMin
                        ))

                        // Update period history for adaptive timing
                        if let lastCand = candidates.dropLast().last {
                            let dt = timestampsMs[candidateMinIdx] - lastCand.startTime
                            if dt > FusionConstants.strokeDetMinPeriodHistoryMs
                                && dt < FusionConstants.strokeDetMaxPeriodHistoryMs {
                                recentPeriods.append(dt)
                                if recentPeriods.count > FusionConstants.strokeDetMaxPeriodHistoryCount {
                                    recentPeriods.removeFirst()
                                }
                            }
                        }
                    }

                    // Reset for next valley search
                    state = .seekValley
                    candidateMin = v
                    candidateMinIdx = i
                    candidateMax = -.infinity
                }
            }
        }

        // --- Step 6: Construct stroke events from consecutive candidates ---
        guard candidates.count >= 2 else { return [] }
        var strokes: [StrokeEvent] = []
        for i in 0..<(candidates.count - 1) {
            let current = candidates[i]
            let next = candidates[i + 1]

            let startTimeS = current.startTime / 1000.0
            let endTimeS = next.startTime / 1000.0
            let durationS = endTimeS - startTimeS

            // Duration filter: physiological stroke range
            guard durationS >= FusionConstants.strokeDetMinStrokeDurS,
                  durationS <= FusionConstants.strokeDetMaxStrokeDurS else { continue }

            // Extract peak velocity between current catch and next catch
            var peak: Double? = nil
            var minVel: Double? = nil
            let si = current.startIdx
            let ei = next.startIdx
            if ei > si {
                var maxV: Float = -.infinity
                var minV: Float = .infinity
                for j in si..<ei {
                    let vel = velocity[j]
                    if vel > maxV { maxV = vel }
                    if vel < minV { minV = vel }
                }
                if maxV > -.infinity { peak = Double(maxV) }
                if minV < .infinity { minVel = Double(minV) }
            }

            let stroke = StrokeEvent(
                index: strokes.count,
                startTime: startTimeS,
                endTime: endTimeS,
                startIndex: si,
                endIndex: ei,
                peakVelocity: peak,
                minVelocity: minVel,
                isValid: true
            )
            strokes.append(stroke)
        }

        return strokes
    }

    // MARK: - Private Helpers

    /// Estimates current stroke period from rolling history.
    /// Returns default period if history is insufficient (< 3 entries).
    private static func estimatedStrokePeriod(_ recentPeriods: [Double]) -> Double {
        guard recentPeriods.count >= 3 else {
            return FusionConstants.strokeDetDefaultPeriodMs
        }
        let sorted = recentPeriods.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        } else {
            return sorted[mid]
        }
    }

    /// Validates acceleration morphology around a candidate catch point.
    ///
    /// Checks that:
    /// - Pre-catch window has negative acceleration (deceleration before catch)
    /// - Post-catch window has positive acceleration (drive initiation)
    /// - Amplitude (postMax - preMin) exceeds minimum threshold
    private static func validateAccelPattern(
        surgeAccel: ContiguousArray<Float>,
        timestamps: ContiguousArray<Double>,
        catchIdx: Int,
        signalLength: Int
    ) -> Bool {
        let t0 = timestamps[catchIdx]

        // Find pre-catch window start
        var preStartIdx = catchIdx
        while preStartIdx > 0
                && timestamps[preStartIdx] > t0 - FusionConstants.strokeDetAccelPreWindowMs {
            preStartIdx -= 1
        }

        // Find post-catch window end
        var postEndIdx = catchIdx
        while postEndIdx < signalLength - 1
                && timestamps[postEndIdx] < t0 + FusionConstants.strokeDetAccelPostWindowMs {
            postEndIdx += 1
        }

        // Pre-catch minimum (should be negative — deceleration)
        var preMin: Float = .infinity
        for k in preStartIdx...catchIdx {
            let a = surgeAccel[k]
            if !a.isNaN && a < preMin { preMin = a }
        }

        // Post-catch maximum (should be positive — drive acceleration)
        var postMax: Float = -.infinity
        for k in catchIdx...postEndIdx {
            let a = surgeAccel[k]
            if !a.isNaN && a > postMax { postMax = a }
        }

        // All three conditions must hold
        if preMin > FusionConstants.strokeDetAccelPreMinG { return false }
        if postMax < FusionConstants.strokeDetAccelPostMinG { return false }
        if (postMax - preMin) < FusionConstants.strokeDetAccelMinAmplitudeG { return false }

        return true
    }
}
