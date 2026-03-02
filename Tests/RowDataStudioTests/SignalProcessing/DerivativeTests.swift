// SignalProcessing/DerivativeTests.swift v1.0.0
/**
 * Tests for numerical derivative (central finite differences).
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Testing
@testable import RowDataStudio

@Suite("DSP Derivative")
struct DerivativeTests {

    @Test("Derivative of linear signal is constant")
    func linearDerivative() {
        // f(t) = 3t, f'(t) = 3
        var signal = ContiguousArray<Float>(repeating: 0, count: 100)
        let dt: Float = 0.01
        for i in 0..<100 {
            signal[i] = 3.0 * Float(i) * dt
        }
        let result = DSP.derivative(signal, dt: dt)

        #expect(result.count == 100)
        // Interior points should be ~3.0
        for i in 1..<99 {
            #expect(abs(result[i] - 3.0) < 0.01,
                    "Derivative at \(i) should be ~3.0, got \(result[i])")
        }
    }

    @Test("Derivative of quadratic signal is linear")
    func quadraticDerivative() {
        // f(t) = t², f'(t) = 2t
        let dt: Float = 0.01
        var signal = ContiguousArray<Float>(repeating: 0, count: 100)
        for i in 0..<100 {
            let t = Float(i) * dt
            signal[i] = t * t
        }
        let result = DSP.derivative(signal, dt: dt)

        // At index 50 (t=0.5), derivative should be ~1.0
        #expect(abs(result[50] - 1.0) < 0.02)
    }

    @Test("Derivative of constant is zero")
    func constantDerivative() {
        let signal: ContiguousArray<Float> = ContiguousArray(repeating: 5.0, count: 50)
        let result = DSP.derivative(signal, dt: 0.01)
        for v in result {
            #expect(abs(v) < 1e-6)
        }
    }

    @Test("Derivative output has same length as input")
    func sameLength() {
        let signal: ContiguousArray<Float> = [1, 2, 3, 4, 5]
        let result = DSP.derivative(signal, dt: 1.0)
        #expect(result.count == signal.count)
    }

    @Test("Derivative uses forward/backward at boundaries")
    func boundaryDerivatives() {
        // f = [0, 1, 4, 9, 16] (t²), dt = 1
        let signal: ContiguousArray<Float> = [0, 1, 4, 9, 16]
        let result = DSP.derivative(signal, dt: 1.0)

        // Forward difference at start: (1 - 0) / 1 = 1
        #expect(abs(result[0] - 1.0) < 1e-6)
        // Backward difference at end: (16 - 9) / 1 = 7
        #expect(abs(result[4] - 7.0) < 1e-6)
        // Central difference at index 2: (9 - 1) / 2 = 4
        #expect(abs(result[2] - 4.0) < 1e-6)
    }
}
