// SignalProcessing/ZeroPhaseSmoothTests.swift v1.0.0
/**
 * Tests for zero-phase smoothing (forward + backward SMA).
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Testing
@testable import RowDataStudio

@Suite("DSP Zero-Phase Smooth")
struct ZeroPhaseSmoothTests {

    @Test("Zero-phase preserves constant signal")
    func preservesConstant() {
        let signal: ContiguousArray<Float> = ContiguousArray(repeating: 3.0, count: 50)
        let result = DSP.zeroPhaseSmooth(signal, halfWindowSize: 5)
        #expect(result.count == signal.count)
        for v in result {
            #expect(abs(v - 3.0) < 1e-4)
        }
    }

    @Test("Zero-phase output has same length as input")
    func sameLength() {
        let signal: ContiguousArray<Float> = ContiguousArray(repeating: 1.0, count: 100)
        let result = DSP.zeroPhaseSmooth(signal, halfWindowSize: 7)
        #expect(result.count == signal.count)
    }

    @Test("Zero-phase preserves peak position (no phase shift)")
    func preservesPeakPosition() {
        // Create signal with a sharp peak at index 50
        var signal = ContiguousArray<Float>(repeating: 0, count: 100)
        signal[50] = 10.0

        let result = DSP.zeroPhaseSmooth(signal, halfWindowSize: 3)

        // Peak should still be near index 50 (within 1 sample)
        let peakIdx = result.enumerated().max(by: { $0.element < $1.element })!.offset
        #expect(abs(peakIdx - 50) <= 1,
                "Peak should remain near original position, got \(peakIdx)")
    }

    @Test("Zero-phase reduces noise amplitude")
    func reducesNoise() {
        // Alternating noise signal
        var signal = ContiguousArray<Float>(repeating: 0, count: 200)
        for i in 0..<200 {
            signal[i] = i.isMultiple(of: 2) ? 5.0 : -5.0
        }
        let result = DSP.zeroPhaseSmooth(signal, halfWindowSize: 5)
        let inputStd = DSP.standardDeviation(signal)
        let outputStd = DSP.standardDeviation(result)
        #expect(outputStd < inputStd, "Smoothing should reduce noise")
    }

    @Test("Zero-phase of single element returns unchanged")
    func singleElement() {
        let signal: ContiguousArray<Float> = [42.0]
        let result = DSP.zeroPhaseSmooth(signal, halfWindowSize: 3)
        #expect(result.count == 1)
        #expect(abs(result[0] - 42.0) < 1e-6)
    }
}
