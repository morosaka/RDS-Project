// SignalProcessing/IntegrateTests.swift v1.0.0
/**
 * Tests for cumulative trapezoidal integration.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Testing
@testable import RowDataStudio

@Suite("DSP Integrate")
struct IntegrateTests {

    @Test("Integration of constant yields linear ramp")
    func constantIntegration() {
        // Constant acceleration → linear velocity
        let signal: ContiguousArray<Float> = ContiguousArray(repeating: 2.0, count: 100)
        let dt: Float = 0.01  // 100 Hz
        let result = DSP.integrate(signal, dt: dt)

        #expect(result.count == 100)
        #expect(abs(result[0]) < 1e-6)  // starts at 0
        // After 99 steps: integral of 2.0 over 0.99s = 1.98
        #expect(abs(result[99] - 1.98) < 0.01)
    }

    @Test("Integration of linear yields quadratic")
    func linearIntegration() {
        // Linear signal: f(t) = t, dt = 0.1
        // Integral: t²/2
        var signal = ContiguousArray<Float>(repeating: 0, count: 11)
        for i in 0...10 {
            signal[i] = Float(i) * 0.1  // 0, 0.1, 0.2, ..., 1.0
        }
        let result = DSP.integrate(signal, dt: 0.1)

        // At t=1.0 (index 10), integral of t from 0 to 1 = 0.5
        #expect(abs(result[10] - 0.5) < 0.01)
    }

    @Test("Integration starts at zero")
    func startsAtZero() {
        let signal: ContiguousArray<Float> = [5, 10, 15, 20]
        let result = DSP.integrate(signal, dt: 1.0)
        #expect(abs(result[0]) < 1e-6)
    }

    @Test("Integration of empty returns empty")
    func emptySignal() {
        let signal: ContiguousArray<Float> = []
        let result = DSP.integrate(signal, dt: 0.01)
        #expect(result.isEmpty)
    }

    @Test("Integration of single element returns zero")
    func singleElement() {
        let signal: ContiguousArray<Float> = [42.0]
        let result = DSP.integrate(signal, dt: 0.01)
        #expect(result.count == 1)
        #expect(abs(result[0]) < 1e-6)
    }
}
