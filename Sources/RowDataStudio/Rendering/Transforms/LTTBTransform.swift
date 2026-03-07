// Rendering/Transforms/LTTBTransform.swift v1.0.0
/**
 * TransformStage: LTTB downsampling for chart rendering.
 * Wraps DSP.lttbDownsample; preserves visual features at reduced point count.
 * --- Revision History ---
 * v1.0.0 - 2026-03-07 - Initial implementation (Phase 4: Rendering + MVP).
 */

/// Downsamples input to `targetCount` points using Largest Triangle Three Buckets.
///
/// Passes data through unchanged when the point count is already ≤ `targetCount`.
/// Always preserves first and last points (endpoints).
///
/// Reference: Steinarsson (2013), "Downsampling Time Series for Visual Representation."
/// Algorithm: `DSP.lttbDownsample` in `SignalProcessing/LTTB.swift`.
public struct LTTBTransform: TransformStage {

    /// Maximum output point count. Default: 2000 (renders at Metal tile resolution).
    public let targetCount: Int

    public init(targetCount: Int = 2000) {
        self.targetCount = targetCount
    }

    public func apply(
        timestamps: ContiguousArray<Double>,
        values: ContiguousArray<Float>
    ) -> (timestamps: ContiguousArray<Double>, values: ContiguousArray<Float>) {
        guard timestamps.count > targetCount, targetCount >= 2 else {
            return (timestamps, values)
        }

        let indices = DSP.lttbDownsample(
            timestamps: timestamps,
            values: values,
            targetCount: targetCount
        )

        var outTs = ContiguousArray<Double>()
        var outVals = ContiguousArray<Float>()
        outTs.reserveCapacity(indices.count)
        outVals.reserveCapacity(indices.count)

        for idx in indices {
            outTs.append(timestamps[idx])
            outVals.append(values[idx])
        }

        return (outTs, outVals)
    }
}
