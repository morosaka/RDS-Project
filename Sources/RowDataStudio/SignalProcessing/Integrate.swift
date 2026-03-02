// SignalProcessing/Integrate.swift v1.0.0
/**
 * Cumulative trapezoidal integration.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Foundation

extension DSP {

    /// Cumulative trapezoidal integration.
    ///
    /// Computes the running integral of the signal using the trapezoidal rule:
    /// `result[i] = result[i-1] + (signal[i-1] + signal[i]) * dt / 2`
    ///
    /// - Parameters:
    ///   - signal: Input signal (e.g., acceleration → velocity).
    ///   - dt: Time step between samples (seconds).
    /// - Returns: Integrated signal. First value is 0. Same length as input.
    public static func integrate(
        _ signal: ContiguousArray<Float>,
        dt: Float
    ) -> ContiguousArray<Float> {
        let n = signal.count
        guard n > 1, dt > 0 else {
            return ContiguousArray<Float>(repeating: 0, count: max(n, 0))
        }

        var output = ContiguousArray<Float>(repeating: 0, count: n)
        let halfDt = dt * 0.5

        for i in 1..<n {
            output[i] = output[i - 1] + (signal[i - 1] + signal[i]) * halfDt
        }

        return output
    }
}
