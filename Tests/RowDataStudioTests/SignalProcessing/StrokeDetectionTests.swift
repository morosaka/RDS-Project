// SignalProcessing/StrokeDetectionTests.swift v1.0.0
/**
 * Tests for stroke detection state machine.
 * Uses synthetic rowing-like velocity signals.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Foundation
import Testing
@testable import RowDataStudio

@Suite("DSP Stroke Detection")
struct StrokeDetectionTests {

    /// Generates a synthetic rowing velocity signal.
    ///
    /// Simulates a velocity pattern with periodic strokes (sinusoidal).
    /// Each stroke cycle has a drive phase (fast) and recovery phase (slow).
    ///
    /// - Parameters:
    ///   - sampleRate: Hz (default 200)
    ///   - durationS: Signal duration in seconds
    ///   - strokeRateSPM: Strokes per minute
    ///   - baseSpeed: Mean boat speed in m/s
    ///   - amplitude: Velocity oscillation amplitude
    /// - Returns: Tuple of (timestamps in ms, velocity in m/s)
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

            // Sinusoidal velocity oscillation centered on base speed
            let phase = 2.0 * Double.pi * strokeFreqHz * tS
            velocity[i] = baseSpeed + amplitude * Float(sin(phase))
        }

        return (timestamps, velocity)
    }

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

        // Average stroke rate should be near 30 SPM
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
}
