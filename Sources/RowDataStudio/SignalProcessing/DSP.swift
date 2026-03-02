// SignalProcessing/DSP.swift v1.0.0
/**
 * Signal processing namespace with shared utilities.
 * Port of RowDataLab common/mathUtils.ts to Swift/Accelerate.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Accelerate
import Foundation

/// Signal processing namespace.
///
/// All signal processing functions are organized as static methods on this enum
/// or its extensions (one per file). Input/output types use `ContiguousArray<Float>`
/// to match the SoA buffer layout in `SensorDataBuffers`.
///
/// **NaN convention:** `Float.nan` indicates missing data. All functions propagate
/// NaN through IEEE 754 arithmetic. Statistical functions filter NaN before computing.
public enum DSP {

    /// Standard gravity constant (m/s²).
    public static let gravity: Float = 9.80665

    // MARK: - Kernel Generation

    /// Generates a normalized Gaussian kernel truncated at 3σ.
    ///
    /// The kernel has odd length `2 * ceil(3 * sigma) + 1` and sums to 1.0.
    ///
    /// - Parameter sigma: Standard deviation in samples. Must be positive.
    /// - Returns: Normalized Gaussian kernel.
    public static func gaussianKernel(sigma: Float) -> [Float] {
        precondition(sigma > 0, "Sigma must be positive")
        let radius = Int(ceil(sigma * 3))
        let size = 2 * radius + 1
        var kernel = [Float](repeating: 0, count: size)
        let twoSigmaSq: Float = 2.0 * sigma * sigma

        for i in 0..<size {
            let x = Float(i - radius)
            kernel[i] = exp(-(x * x) / twoSigmaSq)
        }

        // Normalize so kernel sums to 1.0
        var sum: Float = 0
        vDSP_sve(kernel, 1, &sum, vDSP_Length(size))
        var invSum = 1.0 / sum
        var normalized = [Float](repeating: 0, count: size)
        vDSP_vsmul(kernel, 1, &invSum, &normalized, 1, vDSP_Length(size))

        return normalized
    }

    // MARK: - Array Utilities

    /// Pads a signal with reflected values at boundaries.
    ///
    /// Used before convolution to maintain output length and reduce edge artifacts.
    /// Reflection: for `[a, b, c, d, e]` with pad 2 → `[c, b, a, b, c, d, e, d, c]`.
    ///
    /// - Parameters:
    ///   - signal: Input signal.
    ///   - padSize: Number of samples to add on each side.
    /// - Returns: Padded signal of length `signal.count + 2 * padSize`.
    static func reflectPad(_ signal: ContiguousArray<Float>, padSize: Int) -> [Float] {
        let n = signal.count
        guard n > 0, padSize > 0 else { return Array(signal) }

        var padded = [Float](repeating: 0, count: n + 2 * padSize)

        // Left padding (reflected from start boundary)
        for i in 0..<padSize {
            let srcIdx = min(padSize - i, n - 1)
            padded[i] = signal[srcIdx]
        }

        // Center (original signal)
        for i in 0..<n {
            padded[padSize + i] = signal[i]
        }

        // Right padding (reflected from end boundary)
        for i in 0..<padSize {
            let srcIdx = max(n - 2 - i, 0)
            padded[padSize + n + i] = signal[srcIdx]
        }

        return padded
    }
}
