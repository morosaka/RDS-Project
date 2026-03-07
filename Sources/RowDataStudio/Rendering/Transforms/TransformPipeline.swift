// Rendering/Transforms/TransformPipeline.swift v1.0.0
/**
 * Composable rendering transform chain.
 * Applies a sequence of TransformStage instances to sensor data,
 * producing display-ready (timestamps, values) arrays.
 * --- Revision History ---
 * v1.0.0 - 2026-03-07 - Initial implementation (Phase 4: Rendering + MVP).
 */

/// Composable rendering transform chain.
///
/// A pipeline is an ordered sequence of `TransformStage` instances.
/// Each stage receives the output of the previous one.
/// Pipelines are value types and `Sendable`, safe to build on any thread.
///
/// **Standard MVP pipeline:**
/// ```
/// ViewportCull → LTTBTransform(2000) → AdaptiveSmooth
/// ```
///
/// Source: `docs/architecture/visualization.md` §Transform Pipelines
public struct TransformPipeline: Sendable {

    private let stages: [any TransformStage]

    /// Creates a pipeline from an ordered list of stages.
    public init(stages: [any TransformStage] = []) {
        self.stages = stages
    }

    /// Returns a new pipeline with an additional stage appended at the end.
    public func appending(_ stage: some TransformStage) -> TransformPipeline {
        TransformPipeline(stages: stages + [stage])
    }

    /// Applies all stages in sequence and returns display-ready arrays.
    ///
    /// - Parameters:
    ///   - timestamps: Full sensor timestamps in milliseconds.
    ///   - values: Full sensor values (same length as timestamps).
    /// - Returns: Transformed arrays, typically much shorter than input.
    public func apply(
        timestamps: ContiguousArray<Double>,
        values: ContiguousArray<Float>
    ) -> (timestamps: ContiguousArray<Double>, values: ContiguousArray<Float>) {
        var current = (timestamps: timestamps, values: values)
        for stage in stages {
            current = stage.apply(timestamps: current.timestamps, values: current.values)
        }
        return current
    }

    // MARK: - Factory

    /// Builds the standard MVP pipeline: ViewportCull → LTTB → AdaptiveSmooth.
    ///
    /// - Parameters:
    ///   - viewportMs: Visible time range in milliseconds.
    ///   - targetCount: Maximum points after LTTB downsampling. Default: 2000.
    ///   - pointsPerPixel: Current zoom level (data points per screen pixel).
    /// - Returns: Ready-to-use pipeline.
    public static func mvp(
        viewportMs: ClosedRange<Double>,
        targetCount: Int = 2000,
        pointsPerPixel: Double = 1.0
    ) -> TransformPipeline {
        TransformPipeline(stages: [
            ViewportCull(range: viewportMs),
            LTTBTransform(targetCount: targetCount),
            AdaptiveSmooth.forZoom(pointsPerPixel: pointsPerPixel)
        ])
    }
}
