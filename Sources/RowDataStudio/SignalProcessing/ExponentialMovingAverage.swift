// SignalProcessing/ExponentialMovingAverage.swift v1.0.0
/**
 * Exponential moving average with configurable decay factor.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Foundation

extension DSP {

    /// Computes exponential moving average (EMA) with a decay factor.
    ///
    /// `ema[0] = signal[0]`
    /// `ema[i] = alpha * signal[i] + (1 - alpha) * ema[i-1]`
    ///
    /// Higher alpha means more weight on the current value (less smoothing).
    /// NaN propagates forward once encountered.
    ///
    /// - Parameters:
    ///   - signal: Input signal.
    ///   - alpha: Smoothing factor in (0, 1]. 1.0 = no smoothing.
    /// - Returns: EMA-smoothed signal of the same length.
    public static func exponentialMovingAverage(
        _ signal: ContiguousArray<Float>,
        alpha: Float
    ) -> ContiguousArray<Float> {
        let n = signal.count
        guard n > 0, alpha > 0, alpha <= 1 else { return signal }

        var output = ContiguousArray<Float>(repeating: 0, count: n)
        output[0] = signal[0]

        let oneMinusAlpha = 1.0 - alpha
        for i in 1..<n {
            output[i] = alpha * signal[i] + oneMinusAlpha * output[i - 1]
        }

        return output
    }
}
