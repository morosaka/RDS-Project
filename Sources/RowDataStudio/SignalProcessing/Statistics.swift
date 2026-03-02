// SignalProcessing/Statistics.swift v1.0.0
/**
 * Statistical functions: mean, median, standard deviation, quantile.
 * All functions are NaN-aware (filter NaN before computing).
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Foundation

extension DSP {

    /// Computes the arithmetic mean, ignoring NaN values.
    ///
    /// - Returns: Mean of valid values, or `.nan` if all values are NaN or array is empty.
    public static func mean(_ values: ContiguousArray<Float>) -> Float {
        guard !values.isEmpty else { return .nan }
        var sum: Float = 0
        var count: Int = 0
        for v in values {
            if !v.isNaN {
                sum += v
                count += 1
            }
        }
        return count > 0 ? sum / Float(count) : .nan
    }

    /// Computes the median, ignoring NaN values.
    ///
    /// - Returns: Median of valid values, or `.nan` if all values are NaN or array is empty.
    public static func median(_ values: ContiguousArray<Float>) -> Float {
        let valid = values.filter { !$0.isNaN }
        guard !valid.isEmpty else { return .nan }
        let sorted = valid.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        } else {
            return sorted[mid]
        }
    }

    /// Computes the sample standard deviation (Bessel-corrected, n-1), ignoring NaN values.
    ///
    /// - Returns: Sample standard deviation, or `.nan` if fewer than 2 valid values.
    public static func standardDeviation(_ values: ContiguousArray<Float>) -> Float {
        let valid = values.filter { !$0.isNaN }
        guard valid.count > 1 else { return .nan }
        var sum: Float = 0
        for v in valid { sum += v }
        let m = sum / Float(valid.count)
        var sumSq: Float = 0
        for v in valid {
            let d = v - m
            sumSq += d * d
        }
        return sqrt(sumSq / Float(valid.count - 1))
    }

    /// Computes the q-th quantile (0.0 to 1.0), ignoring NaN values.
    ///
    /// Uses linear interpolation between neighboring ranks.
    ///
    /// - Parameters:
    ///   - values: Input values.
    ///   - q: Quantile in [0, 1]. E.g., 0.5 = median, 0.95 = P95.
    /// - Returns: Interpolated quantile value, or `.nan` if no valid values.
    public static func quantile(_ values: ContiguousArray<Float>, q: Float) -> Float {
        precondition(q >= 0 && q <= 1, "Quantile must be in [0, 1]")
        let valid = values.filter { !$0.isNaN }
        guard !valid.isEmpty else { return .nan }
        let sorted = valid.sorted()
        if sorted.count == 1 { return sorted[0] }

        let pos = q * Float(sorted.count - 1)
        let lo = Int(floor(pos))
        let hi = Int(ceil(pos))
        if lo == hi { return sorted[lo] }
        let frac = pos - Float(lo)
        return sorted[lo] * (1 - frac) + sorted[hi] * frac
    }
}
