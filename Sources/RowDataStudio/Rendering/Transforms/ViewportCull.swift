// Rendering/Transforms/ViewportCull.swift v1.0.0
/**
 * TransformStage: filters data to visible time range.
 * Uses binary search for O(log n) range start, then linear scan.
 * --- Revision History ---
 * v1.0.0 - 2026-03-07 - Initial implementation (Phase 4: Rendering + MVP).
 */

import Foundation

/// Filters input data to the visible time range (viewport).
///
/// Discards all samples outside `range` to reduce the working set
/// before LTTB downsampling. Includes one sample before the viewport
/// start when available, ensuring visual continuity at the left edge.
///
/// **Complexity:** O(log n + k) where k = samples in viewport.
public struct ViewportCull: TransformStage {

    /// Visible time range in milliseconds (same scale as `SensorDataBuffers.timestamp`).
    public let range: ClosedRange<Double>

    public init(range: ClosedRange<Double>) {
        self.range = range
    }

    public init(startMs: Double, endMs: Double) {
        self.range = startMs...endMs
    }

    public func apply(
        timestamps: ContiguousArray<Double>,
        values: ContiguousArray<Float>
    ) -> (timestamps: ContiguousArray<Double>, values: ContiguousArray<Float>) {
        guard !timestamps.isEmpty else { return (timestamps, values) }

        // Early exit when there is no overlap between data and viewport.
        guard timestamps.last! >= range.lowerBound,
              timestamps.first! <= range.upperBound else {
            return (ContiguousArray(), ContiguousArray())
        }

        // Binary search for the first index at or just before viewport start.
        // Include this point for visual continuity at the left chart edge.
        let floorIdx = DSP.binarySearchFloor(timestamps, target: range.lowerBound)
        let startIdx = max(floorIdx, 0)

        var outTs = ContiguousArray<Double>()
        var outVals = ContiguousArray<Float>()

        for i in startIdx..<timestamps.count {
            let t = timestamps[i]
            if t > range.upperBound { break }
            outTs.append(t)
            outVals.append(values[i])
        }

        return (outTs, outVals)
    }
}
