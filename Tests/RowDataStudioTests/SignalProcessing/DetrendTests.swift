// SignalProcessing/DetrendTests.swift v1.0.0
/**
 * Tests for baseline removal (detrending).
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Foundation
import Testing
@testable import RowDataStudio

@Suite("DSP Detrend")
struct DetrendTests {

    @Test("Detrend removes constant offset")
    func removesConstant() {
        // Signal = oscillation + constant offset
        var signal = ContiguousArray<Float>(repeating: 0, count: 200)
        for i in 0..<200 {
            let osc = Float(sin(Double(i) * 0.1)) * 2.0  // fast oscillation
            signal[i] = osc + 100.0  // large constant offset
        }
        let result = DSP.detrend(signal, windowSize: 51)

        // After detrending, mean should be near zero
        let resultMean = DSP.mean(result)
        #expect(abs(resultMean) < 1.0,
                "Detrended signal mean should be near zero, got \(resultMean)")
    }

    @Test("Detrend removes slow drift")
    func removesSlowDrift() {
        // Signal = fast oscillation + slow linear drift
        var signal = ContiguousArray<Float>(repeating: 0, count: 500)
        for i in 0..<500 {
            let osc = Float(sin(Double(i) * 0.5)) * 3.0  // fast
            let drift = Float(i) * 0.1  // slow linear drift
            signal[i] = osc + drift
        }
        let result = DSP.detrend(signal, windowSize: 101)

        // The oscillation should be preserved but drift removed
        // Standard deviation should be roughly the oscillation amplitude
        let std = DSP.standardDeviation(result)
        #expect(std > 1.0, "Oscillation should be preserved")
        #expect(std < 5.0, "Drift should be removed")
    }

    @Test("Detrend output has same length as input")
    func sameLength() {
        let signal: ContiguousArray<Float> = ContiguousArray(repeating: 5.0, count: 100)
        let result = DSP.detrend(signal, windowSize: 11)
        #expect(result.count == signal.count)
    }

    @Test("Detrend of constant signal is near zero")
    func constantSignal() {
        let signal: ContiguousArray<Float> = ContiguousArray(repeating: 42.0, count: 100)
        let result = DSP.detrend(signal, windowSize: 11)
        for v in result {
            #expect(abs(v) < 1e-3,
                    "Detrended constant should be ~0, got \(v)")
        }
    }
}
