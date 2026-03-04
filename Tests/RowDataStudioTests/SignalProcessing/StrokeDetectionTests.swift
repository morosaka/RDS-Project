// SignalProcessing/StrokeDetectionTests.swift v1.1.0
/**
 * Tests for multi-validated stroke detection state machine.
 * Uses synthetic rowing-like velocity and acceleration signals.
 * --- Revision History ---
 * v1.1.0 - 2026-03-03 - Expand tests for multi-validated detection: noise,
 *          low-amplitude, accel validation, adaptive timing, rearm, variable rate.
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Foundation
import Testing
@testable import RowDataStudio

@Suite("DSP Stroke Detection")
struct StrokeDetectionTests {

    // MARK: - Synthetic Signal Generators

    /// Generates a synthetic rowing velocity signal.
    ///
    /// Simulates a velocity pattern with periodic strokes (sinusoidal).
    /// Each stroke cycle has a drive phase (fast) and recovery phase (slow).
    private static func syntheticRowingSignal(
        sampleRate: Double = 200,
        durationS: Double = 30,
        strokeRateSPM: Double = 30,
        baseSpeed: Float = 4.0,
        amplitude: Float = 1.5
    ) -> (timestamps: ContiguousArray<Double>, velocity: ContiguousArray<Float>) {
        let n = Int(sampleRate * durationS)
        let strokeFreqHz = strokeRateSPM / 60.0
        var timestamps = ContiguousArray<Double>(repeating: 0, count: n)
        var velocity = ContiguousArray<Float>(repeating: 0, count: n)

        for i in 0..<n {
            let tS = Double(i) / sampleRate
            timestamps[i] = tS * 1000.0  // ms
            let phase = 2.0 * Double.pi * strokeFreqHz * tS
            velocity[i] = baseSpeed + amplitude * Float(sin(phase))
        }

        return (timestamps, velocity)
    }

    /// Generates a synthetic surge acceleration signal matching the velocity.
    ///
    /// Acceleration is the derivative of velocity: A * ω * cos(ωt), in G units.
    /// This creates the correct morphological pattern: negative before catch,
    /// positive after catch.
    private static func syntheticSurgeAccel(
        sampleRate: Double = 200,
        durationS: Double = 30,
        strokeRateSPM: Double = 30,
        velocityAmplitude: Float = 1.5
    ) -> ContiguousArray<Float> {
        let n = Int(sampleRate * durationS)
        let strokeFreqHz = strokeRateSPM / 60.0
        let omega = 2.0 * Double.pi * strokeFreqHz
        var accel = ContiguousArray<Float>(repeating: 0, count: n)

        for i in 0..<n {
            let tS = Double(i) / sampleRate
            // Derivative of sin = cos; convert m/s² to G
            let accMps2 = Float(omega) * velocityAmplitude * Float(cos(omega * tS))
            accel[i] = accMps2 / 9.80665
        }
        return accel
    }

    /// Adds deterministic pseudo-random noise to a signal.
    ///
    /// Uses a simple linear congruential generator for reproducibility.
    private static func addNoise(
        to signal: ContiguousArray<Float>,
        amplitude: Float,
        seed: UInt64 = 42
    ) -> ContiguousArray<Float> {
        var result = signal
        var state = seed
        for i in 0..<signal.count {
            // LCG: state = (a * state + c) mod m
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let normalized = Float(Int64(bitPattern: state >> 1)) / Float(Int64.max)
            result[i] += amplitude * normalized
        }
        return result
    }

    // MARK: - Basic Detection (backward-compatible, no accel)

    @Test("Detects strokes in synthetic rowing signal")
    func detectsSyntheticStrokes() {
        let (ts, vel) = Self.syntheticRowingSignal(
            durationS: 30, strokeRateSPM: 30
        )
        let strokes = DSP.detectStrokes(
            timestampsMs: ts, velocity: vel, sampleRate: 200
        )

        // 30 SPM × 30s = ~15 strokes. Allow margin for edge effects.
        #expect(strokes.count >= 8,
                "Expected >=8 strokes at 30 SPM over 30s, got \(strokes.count)")
        #expect(strokes.count <= 20,
                "Expected <=20 strokes, got \(strokes.count)")
    }

    @Test("Stroke durations are physiologically plausible")
    func strokeDurationsPlausible() {
        let (ts, vel) = Self.syntheticRowingSignal(
            durationS: 20, strokeRateSPM: 28
        )
        let strokes = DSP.detectStrokes(
            timestampsMs: ts, velocity: vel, sampleRate: 200
        )

        for stroke in strokes {
            #expect(stroke.duration >= 0.8,
                    "Stroke duration too short: \(stroke.duration)s")
            #expect(stroke.duration <= 5.0,
                    "Stroke duration too long: \(stroke.duration)s")
        }
    }

    @Test("Stroke rate matches expected rate")
    func strokeRateMatchesExpected() {
        let (ts, vel) = Self.syntheticRowingSignal(
            durationS: 30, strokeRateSPM: 30
        )
        let strokes = DSP.detectStrokes(
            timestampsMs: ts, velocity: vel, sampleRate: 200
        )

        guard !strokes.isEmpty else {
            Issue.record("No strokes detected")
            return
        }

        let avgRate = strokes.map(\.strokeRate).reduce(0, +) / Double(strokes.count)
        #expect(abs(avgRate - 30.0) < 8.0,
                "Average stroke rate should be ~30 SPM, got \(avgRate)")
    }

    @Test("Strokes are sequential and non-overlapping")
    func strokesSequential() {
        let (ts, vel) = Self.syntheticRowingSignal(durationS: 20, strokeRateSPM: 26)
        let strokes = DSP.detectStrokes(
            timestampsMs: ts, velocity: vel, sampleRate: 200
        )

        for i in 1..<strokes.count {
            #expect(strokes[i].startTime >= strokes[i - 1].endTime,
                    "Strokes should be sequential at index \(i)")
            #expect(strokes[i].startIndex > strokes[i - 1].startIndex,
                    "Stroke indices should increase at index \(i)")
        }
    }

    @Test("No strokes detected in flat signal")
    func flatSignalNoStrokes() {
        let n = 6000  // 30s at 200Hz
        let timestamps = ContiguousArray<Double>((0..<n).map { Double($0) * 5.0 })
        let velocity = ContiguousArray<Float>(repeating: 4.0, count: n)
        let strokes = DSP.detectStrokes(
            timestampsMs: timestamps, velocity: velocity, sampleRate: 200
        )
        #expect(strokes.isEmpty, "Flat signal should produce no strokes")
    }

    @Test("Too-short signal returns empty")
    func tooShortSignal() {
        let timestamps: ContiguousArray<Double> = [0, 5, 10]
        let velocity: ContiguousArray<Float> = [4, 5, 4]
        let strokes = DSP.detectStrokes(
            timestampsMs: timestamps, velocity: velocity, sampleRate: 200
        )
        #expect(strokes.isEmpty)
    }

    // MARK: - Noisy Signal Robustness

    @Test("Detects strokes in noisy signal")
    func detectsStrokesWithNoise() {
        let (ts, vel) = Self.syntheticRowingSignal(
            durationS: 30, strokeRateSPM: 28, amplitude: 1.5
        )
        let noisy = Self.addNoise(to: vel, amplitude: 0.3)

        let strokes = DSP.detectStrokes(
            timestampsMs: ts, velocity: noisy, sampleRate: 200
        )

        #expect(strokes.count >= 5,
                "Should detect strokes even with noise, got \(strokes.count)")
        #expect(strokes.count <= 20,
                "Should not over-detect with noise, got \(strokes.count)")
    }

    // MARK: - Low-Amplitude Signal (Safety Floor Test)

    @Test("Low-amplitude noise does not produce false strokes")
    func lowAmplitudeNoiseNoFalseStrokes() {
        // Pure noise with no periodic structure — should not trigger detection
        let n = 4000  // 20s at 200Hz
        let timestamps = ContiguousArray<Double>((0..<n).map { Double($0) * 5.0 })
        // Base speed with tiny random noise (no periodic component)
        var velocity = ContiguousArray<Float>(repeating: 4.0, count: n)
        velocity = Self.addNoise(to: velocity, amplitude: 0.05)

        let strokes = DSP.detectStrokes(
            timestampsMs: timestamps, velocity: velocity, sampleRate: 200
        )

        // Random noise should produce few or no strokes
        #expect(strokes.count <= 3,
                "Pure noise should not generate many strokes, got \(strokes.count)")
    }

    // MARK: - Acceleration Validation

    @Test("Accel validation accepts matching morphology")
    func accelValidationAccepts() {
        let rate: Double = 28
        let amp: Float = 1.5
        let (ts, vel) = Self.syntheticRowingSignal(
            durationS: 30, strokeRateSPM: rate, amplitude: amp
        )
        let accel = Self.syntheticSurgeAccel(
            durationS: 30, strokeRateSPM: rate, velocityAmplitude: amp
        )

        // With matching accel, detection should work
        let strokes = DSP.detectStrokes(
            timestampsMs: ts, velocity: vel, surgeAccel: accel, sampleRate: 200
        )

        #expect(strokes.count >= 5,
                "With matching accel pattern, should detect strokes, got \(strokes.count)")
    }

    @Test("Accel validation rejects flat acceleration")
    func accelValidationRejectsFlat() {
        let (ts, vel) = Self.syntheticRowingSignal(
            durationS: 20, strokeRateSPM: 28, amplitude: 1.5
        )
        // Flat acceleration — no morphological pattern
        let flatAccel = ContiguousArray<Float>(repeating: 0, count: vel.count)

        let strokesWithAccel = DSP.detectStrokes(
            timestampsMs: ts, velocity: vel, surgeAccel: flatAccel, sampleRate: 200
        )
        let strokesWithout = DSP.detectStrokes(
            timestampsMs: ts, velocity: vel, sampleRate: 200
        )

        // Flat accel should reject candidates that velocity-only would accept
        #expect(strokesWithAccel.count < strokesWithout.count,
                "Flat accel should reduce detections: \(strokesWithAccel.count) vs \(strokesWithout.count)")
    }

    // MARK: - Adaptive Timing

    @Test("Variable stroke rate is tracked by adaptive timing")
    func variableStrokeRate() {
        // Generate a signal that transitions from 20 SPM to 36 SPM
        let sampleRate: Double = 200
        let n = Int(sampleRate * 30)
        var timestamps = ContiguousArray<Double>(repeating: 0, count: n)
        var velocity = ContiguousArray<Float>(repeating: 0, count: n)

        for i in 0..<n {
            let tS = Double(i) / sampleRate
            timestamps[i] = tS * 1000.0

            // Linearly ramp stroke rate from 20 SPM to 36 SPM over 30s
            let currentSPM = 20.0 + (36.0 - 20.0) * (tS / 30.0)
            let freqHz = currentSPM / 60.0
            let phase = 2.0 * Double.pi * freqHz * tS
            velocity[i] = 4.0 + 1.5 * Float(sin(phase))
        }

        let strokes = DSP.detectStrokes(
            timestampsMs: timestamps, velocity: velocity, sampleRate: sampleRate
        )

        // Should detect strokes across the range
        #expect(strokes.count >= 5,
                "Should detect strokes across variable rate, got \(strokes.count)")

        // Early strokes should have lower rate than late strokes
        if strokes.count >= 4 {
            let earlyRate = strokes[0].strokeRate
            let lateRate = strokes[strokes.count - 1].strokeRate
            #expect(lateRate > earlyRate,
                    "Late strokes should be faster: early=\(earlyRate) late=\(lateRate)")
        }
    }

    // MARK: - Rearm Mechanism

    @Test("Rearm prevents false stroke on aborted upswing")
    func rearmPreventsAbortedUpswing() {
        // Create a signal with an aborted upswing: rises slightly then drops deep
        let sampleRate: Double = 200
        let n = Int(sampleRate * 15)
        var timestamps = ContiguousArray<Double>(repeating: 0, count: n)
        var velocity = ContiguousArray<Float>(repeating: 0, count: n)

        for i in 0..<n {
            let tS = Double(i) / sampleRate
            timestamps[i] = tS * 1000.0

            // Normal strokes except for a deliberate artifact at ~5s
            let freqHz = 30.0 / 60.0
            let phase = 2.0 * Double.pi * freqHz * tS
            var v: Float = 4.0 + 1.5 * Float(sin(phase))

            // Add a brief spike + deep drop around 5.0–5.3s
            if tS > 5.0 && tS < 5.15 {
                v += 2.0  // Artificial spike
            } else if tS >= 5.15 && tS < 5.4 {
                v -= 3.0  // Deep drop (should trigger rearm)
            }

            velocity[i] = v
        }

        let strokes = DSP.detectStrokes(
            timestampsMs: timestamps, velocity: velocity, sampleRate: sampleRate
        )

        // The artifact should not create an extra stroke; count should be reasonable
        // for 15s at 30 SPM = ~7 strokes
        #expect(strokes.count <= 10,
                "Rearm should prevent over-detection from artifacts, got \(strokes.count)")
    }

    // MARK: - Peak/Min Velocity Extraction

    @Test("Peak and min velocity are extracted correctly")
    func peakMinVelocity() {
        let (ts, vel) = Self.syntheticRowingSignal(
            durationS: 20, strokeRateSPM: 28, baseSpeed: 4.0, amplitude: 1.5
        )
        let strokes = DSP.detectStrokes(
            timestampsMs: ts, velocity: vel, sampleRate: 200
        )

        for stroke in strokes {
            if let peak = stroke.peakVelocity {
                #expect(peak > 4.0, "Peak velocity should be above base speed")
                #expect(peak <= 6.0, "Peak velocity should not exceed base + amplitude + margin")
            }
            if let minV = stroke.minVelocity {
                #expect(minV < 4.0, "Min velocity should be below base speed")
                #expect(minV >= 2.0, "Min velocity should not be below base - amplitude - margin")
            }
        }
    }
}
