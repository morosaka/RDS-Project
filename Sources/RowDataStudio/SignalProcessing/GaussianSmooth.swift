// SignalProcessing/GaussianSmooth.swift v1.0.0
/**
 * Gaussian smoothing via convolution with a pre-computed Gaussian kernel.
 * Uses vDSP_conv for hardware-accelerated convolution.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Accelerate

extension DSP {

    /// Applies Gaussian smoothing using convolution.
    ///
    /// Uses a Gaussian kernel truncated at 3σ. The signal is reflect-padded
    /// at boundaries to maintain output length and reduce edge artifacts.
    ///
    /// - Parameters:
    ///   - signal: Input signal.
    ///   - sigma: Standard deviation of the Gaussian kernel (in samples). Must be positive.
    /// - Returns: Smoothed signal of the same length as input.
    public static func gaussianSmooth(
        _ signal: ContiguousArray<Float>,
        sigma: Float
    ) -> ContiguousArray<Float> {
        guard signal.count > 1, sigma > 0 else { return signal }

        let kernel = gaussianKernel(sigma: sigma)
        let padSize = kernel.count / 2
        let padded = reflectPad(signal, padSize: padSize)

        // vDSP_conv output length: paddedLen - kernelLen + 1 = signal.count
        let outputLen = padded.count - kernel.count + 1
        var output = [Float](repeating: 0, count: outputLen)

        // vDSP_conv computes C[n] = sum(A[n+p] * F[P-1-p]) for p=0..P-1
        // Since Gaussian kernel is symmetric, reversal is a no-op.
        padded.withUnsafeBufferPointer { paddedBuf in
            kernel.withUnsafeBufferPointer { kernelBuf in
                output.withUnsafeMutableBufferPointer { outputBuf in
                    vDSP_conv(
                        paddedBuf.baseAddress!, 1,
                        kernelBuf.baseAddress!, 1,
                        outputBuf.baseAddress!, 1,
                        vDSP_Length(outputLen),
                        vDSP_Length(kernel.count)
                    )
                }
            }
        }

        return ContiguousArray(output)
    }
}
