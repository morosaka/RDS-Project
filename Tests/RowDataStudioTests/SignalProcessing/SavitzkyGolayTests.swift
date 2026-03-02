// SignalProcessing/SavitzkyGolayTests.swift v1.0.0
/**
 * Tests for Savitzky-Golay polynomial smoothing filter.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Testing
@testable import RowDataStudio

@Suite("DSP Savitzky-Golay Filter")
struct SavitzkyGolayTests {

    @Test("SG preserves constant signal")
    func preservesConstant() {
        let signal: ContiguousArray<Float> = ContiguousArray(repeating: 7.0, count: 50)
        let result = DSP.savitzkyGolay(signal, windowSize: 5, order: 2)
        #expect(result.count == signal.count)
        for v in result {
            #expect(abs(v - 7.0) < 1e-3)
        }
    }

    @Test("SG preserves linear signal with order >= 1")
    func preservesLinear() {
        // Linear signal: y = 2x + 1
        var signal = ContiguousArray<Float>(repeating: 0, count: 100)
        for i in 0..<100 {
            signal[i] = Float(2 * i + 1)
        }
        let result = DSP.savitzkyGolay(signal, windowSize: 7, order: 2)
        // Interior points should match perfectly
        for i in 10..<90 {
            #expect(abs(result[i] - signal[i]) < 0.5,
                    "SG should preserve linear trend at index \(i)")
        }
    }

    @Test("SG reduces noise while preserving shape")
    func reducesNoise() {
        // Parabola with noise
        var signal = ContiguousArray<Float>(repeating: 0, count: 100)
        for i in 0..<100 {
            let x = Float(i) - 50
            signal[i] = x * x * 0.01
        }
        // Add noise
        var noisy = signal
        for i in stride(from: 0, to: 100, by: 2) {
            noisy[i] += 1.0
        }
        let result = DSP.savitzkyGolay(noisy, windowSize: 9, order: 2)

        // Smoothed should be closer to original than noisy
        var noisyError: Float = 0
        var sgError: Float = 0
        for i in 10..<90 {
            noisyError += abs(noisy[i] - signal[i])
            sgError += abs(result[i] - signal[i])
        }
        #expect(sgError < noisyError, "SG should reduce noise")
    }

    @Test("SG output has same length as input")
    func sameLength() {
        let signal: ContiguousArray<Float> = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        let result = DSP.savitzkyGolay(signal, windowSize: 5, order: 2)
        #expect(result.count == signal.count)
    }

    @Test("SG returns input unchanged when window > signal length")
    func windowTooLarge() {
        let signal: ContiguousArray<Float> = [1, 2, 3]
        let result = DSP.savitzkyGolay(signal, windowSize: 7, order: 2)
        #expect(result.count == signal.count)
        for i in 0..<signal.count {
            #expect(abs(result[i] - signal[i]) < 1e-6)
        }
    }
}
