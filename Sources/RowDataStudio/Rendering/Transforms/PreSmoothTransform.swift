// Rendering/Transforms/PreSmoothTransform.swift v1.0.0
/**
 * TransformStage: pre-LTTB noise reduction for high-frequency sensor signals.
 *
 * **Problem:** LTTB selects points that maximise triangle area — on noisy
 * high-frequency data (e.g. 200 Hz IMU) this causes a "comb" artifact because
 * the algorithm actively prefers alternating peaks and troughs.
 *
 * **Solution:** apply a Simple Moving Average (SMA) whose window is proportional
 * to the decimation ratio *before* LTTB runs. LTTB then operates on a
 * signal that preserves the macro shape but has the noise floor suppressed.
 *
 * **Window sizing:**
 *   decimationRatio = ceil(inputCount / targetCount)
 *   windowSize      = max(3, decimationRatio / 2) rounded up to next odd number
 *
 * A windowSize of 1 or 2 would have no effect, so the stage is skipped when
 * the input is already at or below targetCount (no downsampling needed).
 *
 * **Performance:** O(n) SMA runs entirely on the detached Task thread alongside
 * the rest of the TransformPipeline. It does NOT re-run at 60fps.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-12 - Initial implementation.
 */

import Foundation

/// Pre-LTTB noise-reduction stage using an adaptive Simple Moving Average.
///
/// Eliminates the comb artifact that LTTB produces on high-frequency (≥ 50 Hz)
/// noisy sensor signals. The SMA window scales with the decimation ratio so
/// it is automatically tuned to the current zoom level.
///
/// Place this stage **between** `ViewportCull` and `LTTBTransform` in the pipeline.
public struct PreSmoothTransform: TransformStage {

    /// Maximum output point count that the downstream LTTB stage will use.
    /// Used to compute the decimation ratio and thus the SMA window size.
    public let targetCount: Int

    public init(targetCount: Int) {
        self.targetCount = targetCount
    }

    public func apply(
        timestamps: ContiguousArray<Double>,
        values: ContiguousArray<Float>
    ) -> (timestamps: ContiguousArray<Double>, values: ContiguousArray<Float>) {
        let n = timestamps.count

        // No downsampling needed — skip to avoid unnecessary computation.
        guard n > targetCount, targetCount >= 2 else {
            return (timestamps, values)
        }

        // Compute decimation ratio and derive an appropriate SMA window.
        // The window covers ~half a "bucket" worth of raw samples:
        //   ratio=180 (360k pts → 2k) → window=90 (removes 200 Hz noise)
        //   ratio=4   (2k pts → 500) → window=3  (light touch)
        let decimationRatio = Int(ceil(Double(n) / Double(targetCount)))
        var windowSize = max(3, decimationRatio / 2)
        if windowSize.isMultiple(of: 2) { windowSize += 1 } // must be odd

        let smoothed = DSP.simpleMovingAverage(values, windowSize: windowSize)
        return (timestamps, smoothed)
    }
}
