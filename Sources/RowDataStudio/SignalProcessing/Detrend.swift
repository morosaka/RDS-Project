// SignalProcessing/Detrend.swift v1.0.0
/**
 * Baseline removal by subtracting a moving average.
 * Used to extract oscillating components from drifting signals.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Accelerate

extension DSP {

    /// Removes baseline drift by subtracting a moving average.
    ///
    /// Used to extract oscillating components (stroke pattern) from signals
    /// with slow drift (boat speed changes, tilt bias).
    ///
    /// `output[i] = signal[i] - baseline[i]`
    ///
    /// - Parameters:
    ///   - signal: Input signal.
    ///   - windowSize: Moving average window for baseline estimation.
    /// - Returns: Detrended signal (original - baseline). Same length as input.
    public static func detrend(
        _ signal: ContiguousArray<Float>,
        windowSize: Int
    ) -> ContiguousArray<Float> {
        let n = signal.count
        guard n > 0, windowSize > 1 else { return signal }

        let baseline = simpleMovingAverage(signal, windowSize: windowSize)

        // output = signal - baseline
        var output = ContiguousArray<Float>(repeating: 0, count: n)
        signal.withUnsafeBufferPointer { sigBuf in
            baseline.withUnsafeBufferPointer { baseBuf in
                output.withUnsafeMutableBufferPointer { outBuf in
                    // vDSP_vsub(B, IB, A, IA, C, IC, N) computes C = A - B
                    vDSP_vsub(
                        baseBuf.baseAddress!, 1,
                        sigBuf.baseAddress!, 1,
                        outBuf.baseAddress!, 1,
                        vDSP_Length(n)
                    )
                }
            }
        }

        return output
    }
}
