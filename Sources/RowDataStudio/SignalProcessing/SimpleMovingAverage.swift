// SignalProcessing/SimpleMovingAverage.swift v1.0.0
/**
 * Simple moving average using convolution with a uniform kernel.
 * Uses vDSP_conv for hardware-accelerated computation.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Accelerate

extension DSP {

    /// Computes a centered simple moving average.
    ///
    /// Uses convolution with a uniform kernel `[1/w, 1/w, ..., 1/w]`.
    /// Signal is reflect-padded at boundaries for same-length output.
    /// NaN propagates through convolution (IEEE 754).
    ///
    /// - Parameters:
    ///   - signal: Input signal.
    ///   - windowSize: Window size (forced to odd if even). Must be >= 1.
    /// - Returns: Smoothed signal of the same length.
    public static func simpleMovingAverage(
        _ signal: ContiguousArray<Float>,
        windowSize: Int
    ) -> ContiguousArray<Float> {
        let n = signal.count
        guard n > 0, windowSize > 1 else { return signal }

        let w = windowSize | 1  // Force odd
        let halfW = w / 2
        guard n > 1 else { return signal }

        let kernel = [Float](repeating: 1.0 / Float(w), count: w)
        let padded = reflectPad(signal, padSize: halfW)

        let outputLen = padded.count - w + 1
        var output = [Float](repeating: 0, count: outputLen)

        padded.withUnsafeBufferPointer { paddedBuf in
            kernel.withUnsafeBufferPointer { kernelBuf in
                output.withUnsafeMutableBufferPointer { outputBuf in
                    vDSP_conv(
                        paddedBuf.baseAddress!, 1,
                        kernelBuf.baseAddress!, 1,
                        outputBuf.baseAddress!, 1,
                        vDSP_Length(outputLen),
                        vDSP_Length(w)
                    )
                }
            }
        }

        return ContiguousArray(output)
    }
}
