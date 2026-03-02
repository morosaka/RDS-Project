// SignalProcessing/StrokeDetection.swift v1.0.0
/**
 * Stroke detection state machine for rowing analysis.
 * Identifies catch/finish points from detrended velocity using dynamic thresholds.
 * Source: docs/specs/fusion-engine.md §Step 3 (Stroke Detection)
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Foundation

extension DSP {

    /// Stroke detection state.
    private enum StrokeState {
        case seekValley
        case seekPeak
    }

    /// Detects strokes in a rowing velocity signal.
    ///
    /// Pipeline (from fusion-engine.md §Step 3):
    /// 1. Zero-phase smooth (15 samples)
    /// 2. Adaptive baseline (~6s window)
    /// 3. Detrend: `velDet = smoothed - baseline`
    /// 4. Dynamic thresholds from P95/P05
    /// 5. State machine: SEEK_VALLEY → SEEK_PEAK → validate
    ///
    /// Validation: stroke duration 0.8-5.0s (physiological rowing range).
    ///
    /// - Parameters:
    ///   - timestampsMs: Time values in **milliseconds** (matches SensorDataBuffers.timestamp).
    ///   - velocity: Velocity signal (m/s).
    ///   - sampleRate: Sample rate in Hz (default 200).
    /// - Returns: Array of detected stroke events (times in seconds per StrokeEvent convention).
    public static func detectStrokes(
        timestampsMs: ContiguousArray<Double>,
        velocity: ContiguousArray<Float>,
        sampleRate: Double = 200.0
    ) -> [StrokeEvent] {
        let n = velocity.count
        guard n > 100, n == timestampsMs.count else { return [] }

        // Step 1: Zero-phase smooth (15 samples = halfWindow 7)
        let smoothed = zeroPhaseSmooth(velocity, halfWindowSize: 7)

        // Step 2: Adaptive baseline (~6s window)
        let baselineWindowSamples = Int(6.0 * sampleRate) | 1
        let baseline = simpleMovingAverage(smoothed, windowSize: baselineWindowSamples)

        // Step 3: Detrend
        var detrended = ContiguousArray<Float>(repeating: 0, count: n)
        for i in 0..<n {
            detrended[i] = smoothed[i] - baseline[i]
        }

        // Step 4: Dynamic thresholds from P95/P05
        let p95 = quantile(detrended, q: 0.95)
        let p05 = quantile(detrended, q: 0.05)
        let hUp = p95 * 0.3        // Threshold to confirm upward crossing (catch → drive)
        let hDn = p05 * 0.3        // Threshold for valley confirmation
        let rearm = (hUp + hDn) * 0.5  // Rearm threshold near zero crossing

        guard !p95.isNaN, !p05.isNaN, p95 > p05 else { return [] }

        // Step 5: State machine — collect catch points (valleys) and finish points (peaks)
        var state: StrokeState = .seekValley
        var catches: [(idx: Int, peakIdx: Int?)] = []
        var currentPeakIdx: Int? = nil

        var valleyIdx = 0
        var valleyVal: Float = .infinity
        var peakIdx = 0
        var peakVal: Float = -.infinity

        for i in 1..<n {
            let v = detrended[i]

            switch state {
            case .seekValley:
                if v < valleyVal {
                    valleyVal = v
                    valleyIdx = i
                }
                if v > hUp && valleyVal < hDn {
                    // Valley confirmed → this is a catch point
                    catches.append((idx: valleyIdx, peakIdx: currentPeakIdx))
                    state = .seekPeak
                    peakVal = v
                    peakIdx = i
                }

            case .seekPeak:
                if v > peakVal {
                    peakVal = v
                    peakIdx = i
                }
                if v < rearm {
                    // Peak confirmed → record it and start looking for next valley
                    currentPeakIdx = peakIdx
                    state = .seekValley
                    valleyVal = v
                    valleyIdx = i
                    peakVal = -.infinity
                }
            }
        }

        // Construct stroke events from consecutive catches
        var strokes: [StrokeEvent] = []
        for i in 1..<catches.count {
            let catchStart = catches[i - 1]
            let catchEnd = catches[i]

            let startTimeMs = timestampsMs[catchStart.idx]
            let endTimeMs = timestampsMs[catchEnd.idx]
            let durationS = (endTimeMs - startTimeMs) / 1000.0

            // Validation: physiological stroke duration 0.8-5.0s
            guard durationS >= 0.8, durationS <= 5.0 else { continue }

            // Extract peak velocity if finish point is available
            var peak: Double? = nil
            var minVel: Double? = nil
            if let finishIdx = catchEnd.peakIdx,
               finishIdx > catchStart.idx, finishIdx < catchEnd.idx {
                // Peak velocity at the finish point
                peak = Double(velocity[finishIdx])
                // Min velocity at catch
                minVel = Double(velocity[catchEnd.idx])
            }

            let stroke = StrokeEvent(
                index: strokes.count,
                startTime: startTimeMs / 1000.0,
                endTime: endTimeMs / 1000.0,
                startIndex: catchStart.idx,
                endIndex: catchEnd.idx,
                peakVelocity: peak,
                minVelocity: minVel,
                isValid: true
            )
            strokes.append(stroke)
        }

        return strokes
    }
}
