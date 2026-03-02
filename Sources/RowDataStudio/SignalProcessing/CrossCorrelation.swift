// SignalProcessing/CrossCorrelation.swift v1.0.0
/**
 * Normalized cross-correlation and Pearson correlation.
 * Used by SignMatch and GpsSpeedCorrelator in the sync pipeline.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Foundation

extension DSP {

    /// Computes normalized sliding cross-correlation between two signals.
    ///
    /// For each lag position, computes the Pearson correlation between a window
    /// of signal `a` and the entirety of signal `b`. The peak of the output
    /// indicates the optimal alignment (used by sync pipeline).
    ///
    /// - Parameters:
    ///   - a: Reference signal (typically longer).
    ///   - b: Pattern signal to match.
    /// - Returns: Normalized correlation values in [-1, 1]. Length = `a.count - b.count + 1`.
    ///   Returns empty array if `b` is longer than `a` or either is empty.
    public static func crossCorrelation(
        _ a: ContiguousArray<Float>,
        _ b: ContiguousArray<Float>
    ) -> ContiguousArray<Float> {
        let na = a.count
        let nb = b.count
        guard na >= nb, nb > 0 else { return ContiguousArray() }

        let outputLen = na - nb + 1
        var output = ContiguousArray<Float>(repeating: 0, count: outputLen)

        // Precompute b statistics (constant across all lags)
        var sumB: Float = 0
        var sumB2: Float = 0
        var countB: Float = 0
        for v in b {
            if !v.isNaN {
                sumB += v
                sumB2 += v * v
                countB += 1
            }
        }
        guard countB > 1 else {
            return ContiguousArray(repeating: .nan, count: outputLen)
        }
        let meanB = sumB / countB
        let varB = sumB2 / countB - meanB * meanB
        guard varB > 1e-10 else {
            return ContiguousArray(repeating: .nan, count: outputLen)
        }
        let stdB = sqrt(varB)

        // Compute correlation for each lag
        for lag in 0..<outputLen {
            var sumA: Float = 0
            var sumA2: Float = 0
            var sumAB: Float = 0
            var count: Float = 0

            for j in 0..<nb {
                let va = a[lag + j]
                let vb = b[j]
                if !va.isNaN && !vb.isNaN {
                    sumA += va
                    sumA2 += va * va
                    sumAB += va * vb
                    count += 1
                }
            }

            guard count > 1 else {
                output[lag] = .nan
                continue
            }

            let meanA = sumA / count
            let varA = sumA2 / count - meanA * meanA
            guard varA > 1e-10 else {
                output[lag] = .nan
                continue
            }
            let stdA = sqrt(varA)

            let cov = sumAB / count - meanA * meanB
            output[lag] = cov / (stdA * stdB)
        }

        return output
    }

    /// Computes Pearson correlation coefficient between two equal-length signals.
    ///
    /// NaN values are excluded pairwise.
    ///
    /// - Returns: Correlation in [-1, 1], or `.nan` if undefined.
    public static func pearsonCorrelation(
        _ a: ContiguousArray<Float>,
        _ b: ContiguousArray<Float>
    ) -> Float {
        guard a.count == b.count, !a.isEmpty else { return .nan }

        var sumA: Float = 0
        var sumB: Float = 0
        var sumA2: Float = 0
        var sumB2: Float = 0
        var sumAB: Float = 0
        var count: Float = 0

        for i in 0..<a.count {
            let va = a[i]
            let vb = b[i]
            if !va.isNaN && !vb.isNaN {
                sumA += va
                sumB += vb
                sumA2 += va * va
                sumB2 += vb * vb
                sumAB += va * vb
                count += 1
            }
        }

        guard count > 1 else { return .nan }

        let meanA = sumA / count
        let meanB = sumB / count
        let varA = sumA2 / count - meanA * meanA
        let varB = sumB2 / count - meanB * meanB
        guard varA > 1e-10, varB > 1e-10 else { return .nan }

        let cov = sumAB / count - meanA * meanB
        return cov / (sqrt(varA) * sqrt(varB))
    }
}
