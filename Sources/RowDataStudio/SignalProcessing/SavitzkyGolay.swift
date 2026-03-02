// SignalProcessing/SavitzkyGolay.swift v1.0.0
/**
 * Savitzky-Golay polynomial smoothing filter.
 * Preserves higher-order features (derivatives) better than moving average.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Accelerate

extension DSP {

    /// Applies Savitzky-Golay polynomial smoothing filter.
    ///
    /// Performs least-squares polynomial fitting over a sliding window.
    /// Preserves higher moments (derivatives) better than moving average.
    ///
    /// - Parameters:
    ///   - signal: Input signal.
    ///   - windowSize: Window size (forced to odd). Must be > order.
    ///   - order: Polynomial order (typically 2-4).
    /// - Returns: Smoothed signal of the same length.
    public static func savitzkyGolay(
        _ signal: ContiguousArray<Float>,
        windowSize: Int,
        order: Int
    ) -> ContiguousArray<Float> {
        let n = signal.count
        guard n > 0 else { return signal }

        let w = windowSize | 1  // Force odd
        guard w >= order + 1 else { return signal }
        guard w <= n else { return signal }

        let halfW = w / 2
        let coefficients = savitzkyGolayCoefficients(windowSize: w, order: order)
        let padded = reflectPad(signal, padSize: halfW)

        let outputLen = padded.count - w + 1
        var output = [Float](repeating: 0, count: outputLen)

        // vDSP_conv reverses the kernel internally. SG smoothing coefficients for
        // the 0th derivative are symmetric, so reversal is a no-op.
        padded.withUnsafeBufferPointer { paddedBuf in
            coefficients.withUnsafeBufferPointer { coeffBuf in
                output.withUnsafeMutableBufferPointer { outputBuf in
                    vDSP_conv(
                        paddedBuf.baseAddress!, 1,
                        coeffBuf.baseAddress!, 1,
                        outputBuf.baseAddress!, 1,
                        vDSP_Length(outputLen),
                        vDSP_Length(w)
                    )
                }
            }
        }

        return ContiguousArray(output)
    }

    /// Computes Savitzky-Golay convolution coefficients via pseudoinverse of the Vandermonde matrix.
    ///
    /// For a window of size `w` and polynomial order `p`:
    /// 1. Build Vandermonde matrix J (w × (p+1))
    /// 2. Compute (J^T J)^{-1} J^T
    /// 3. First row gives the smoothing coefficients
    static func savitzkyGolayCoefficients(windowSize w: Int, order: Int) -> [Float] {
        let m = w / 2        // half-window
        let p = order + 1    // number of polynomial terms

        // Build Vandermonde matrix J (w x p), row-major
        var J = [Float](repeating: 0, count: w * p)
        for i in 0..<w {
            let x = Float(i - m)
            var xPow: Float = 1
            for j in 0..<p {
                J[i * p + j] = xPow
                xPow *= x
            }
        }

        // Compute J^T * J (p x p)
        var JtJ = [Float](repeating: 0, count: p * p)
        for i in 0..<p {
            for j in 0..<p {
                var sum: Float = 0
                for k in 0..<w {
                    sum += J[k * p + i] * J[k * p + j]
                }
                JtJ[i * p + j] = sum
            }
        }

        // Invert JtJ via Gauss-Jordan elimination
        var inv = [Float](repeating: 0, count: p * p)
        for i in 0..<p { inv[i * p + i] = 1 }
        var mat = JtJ

        for col in 0..<p {
            let pivot = mat[col * p + col]
            if abs(pivot) < 1e-10 {
                // Degenerate: fall back to uniform kernel
                return [Float](repeating: 1.0 / Float(w), count: w)
            }
            let invPivot = 1.0 / pivot
            for j in 0..<p {
                mat[col * p + j] *= invPivot
                inv[col * p + j] *= invPivot
            }
            for row in 0..<p where row != col {
                let factor = mat[row * p + col]
                for j in 0..<p {
                    mat[row * p + j] -= factor * mat[col * p + j]
                    inv[row * p + j] -= factor * inv[col * p + j]
                }
            }
        }

        // Compute coefficients = first row of (JtJ)^{-1} * J^T
        // coefficients[k] = sum_j inv[0][j] * J[k][j]
        var coefficients = [Float](repeating: 0, count: w)
        for k in 0..<w {
            var sum: Float = 0
            for j in 0..<p {
                sum += inv[j] * J[k * p + j]
            }
            coefficients[k] = sum
        }

        return coefficients
    }
}
