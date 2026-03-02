// SignalProcessing/Search.swift v1.0.0
/**
 * Search and interpolation functions: binarySearchFloor, interpolateAt, getNearestValue.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Foundation

extension DSP {

    /// Binary search for the largest index where `array[index] <= target`.
    ///
    /// Array must be sorted in ascending order.
    ///
    /// - Parameters:
    ///   - array: Sorted ascending Float array.
    ///   - target: Value to search for.
    /// - Returns: Index of the floor element, or -1 if `target < array[0]`.
    public static func binarySearchFloor(_ array: ContiguousArray<Float>, target: Float) -> Int {
        guard !array.isEmpty else { return -1 }
        if target < array[0] { return -1 }
        if target >= array[array.count - 1] { return array.count - 1 }

        var lo = 0
        var hi = array.count - 1
        while lo <= hi {
            let mid = lo + (hi - lo) / 2
            if array[mid] <= target {
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return hi
    }

    /// Binary search for the largest index where `array[index] <= target` (Double variant).
    ///
    /// Array must be sorted in ascending order.
    ///
    /// - Parameters:
    ///   - array: Sorted ascending Double array (typically timestamps).
    ///   - target: Value to search for.
    /// - Returns: Index of the floor element, or -1 if `target < array[0]`.
    public static func binarySearchFloor(_ array: ContiguousArray<Double>, target: Double) -> Int {
        guard !array.isEmpty else { return -1 }
        if target < array[0] { return -1 }
        if target >= array[array.count - 1] { return array.count - 1 }

        var lo = 0
        var hi = array.count - 1
        while lo <= hi {
            let mid = lo + (hi - lo) / 2
            if array[mid] <= target {
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return hi
    }

    /// Linear interpolation at an arbitrary timestamp.
    ///
    /// Clamps to boundary values for times outside the range.
    /// Timestamps must be sorted ascending.
    ///
    /// - Parameters:
    ///   - timestamps: Sorted ascending time values.
    ///   - values: Signal values (same length as timestamps).
    ///   - targetTime: Time at which to interpolate.
    /// - Returns: Interpolated value, or `.nan` if arrays are empty or mismatched.
    public static func interpolateAt(
        timestamps: ContiguousArray<Double>,
        values: ContiguousArray<Float>,
        targetTime: Double
    ) -> Float {
        let n = timestamps.count
        guard n > 0, n == values.count else { return .nan }
        if n == 1 || targetTime <= timestamps[0] { return values[0] }
        if targetTime >= timestamps[n - 1] { return values[n - 1] }

        // Binary search for floor index
        var lo = 0
        var hi = n - 1
        while lo < hi - 1 {
            let mid = lo + (hi - lo) / 2
            if timestamps[mid] <= targetTime {
                lo = mid
            } else {
                hi = mid
            }
        }

        let t0 = timestamps[lo]
        let t1 = timestamps[hi]
        let dt = t1 - t0
        if dt == 0 { return values[lo] }

        let frac = Float((targetTime - t0) / dt)
        return values[lo] + frac * (values[hi] - values[lo])
    }

    /// Finds the value at the nearest timestamp.
    ///
    /// Timestamps must be sorted ascending.
    ///
    /// - Parameters:
    ///   - timestamps: Sorted ascending time values.
    ///   - values: Signal values (same length as timestamps).
    ///   - time: Target time.
    /// - Returns: Value at the nearest timestamp, or `.nan` if arrays are empty or mismatched.
    public static func getNearestValue(
        timestamps: ContiguousArray<Double>,
        values: ContiguousArray<Float>,
        time: Double
    ) -> Float {
        let n = timestamps.count
        guard n > 0, n == values.count else { return .nan }
        if n == 1 { return values[0] }
        if time <= timestamps[0] { return values[0] }
        if time >= timestamps[n - 1] { return values[n - 1] }

        // Binary search for floor
        var lo = 0
        var hi = n - 1
        while lo < hi - 1 {
            let mid = lo + (hi - lo) / 2
            if timestamps[mid] <= time {
                lo = mid
            } else {
                hi = mid
            }
        }

        let distLo = abs(timestamps[lo] - time)
        let distHi = abs(timestamps[hi] - time)
        return distLo <= distHi ? values[lo] : values[hi]
    }
}
