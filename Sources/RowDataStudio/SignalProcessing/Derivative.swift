// SignalProcessing/Derivative.swift v1.0.0
/**
 * Numerical derivative using finite differences.
 * Central difference for interior, forward/backward at boundaries.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Foundation

extension DSP {

    /// Numerical derivative using central finite differences.
    ///
    /// Uses forward difference at the first point, backward difference at the last,
    /// and central difference `(f[i+1] - f[i-1]) / (2*dt)` for interior points.
    ///
    /// - Parameters:
    ///   - signal: Input signal (e.g., velocity → acceleration).
    ///   - dt: Time step between samples (seconds).
    /// - Returns: Derivative signal. Same length as input.
    public static func derivative(
        _ signal: ContiguousArray<Float>,
        dt: Float
    ) -> ContiguousArray<Float> {
        let n = signal.count
        guard n > 1, dt > 0 else {
            return ContiguousArray<Float>(repeating: 0, count: max(n, 0))
        }

        var output = ContiguousArray<Float>(repeating: 0, count: n)
        let inv2Dt = 1.0 / (2.0 * dt)
        let invDt = 1.0 / dt

        // Forward difference at start
        output[0] = (signal[1] - signal[0]) * invDt

        // Central difference for interior points
        for i in 1..<(n - 1) {
            output[i] = (signal[i + 1] - signal[i - 1]) * inv2Dt
        }

        // Backward difference at end
        output[n - 1] = (signal[n - 1] - signal[n - 2]) * invDt

        return output
    }
}
