// Rendering/Transforms/TransformStage.swift v1.0.0
/**
 * Protocol for a single stage in the rendering transform pipeline.
 * Stages are pure functions: same input → same output, no side effects.
 * --- Revision History ---
 * v1.0.0 - 2026-03-07 - Initial implementation (Phase 4: Rendering + MVP).
 */

/// A single processing stage in the rendering transform pipeline.
///
/// Stages are pure, composable transforms applied in sequence by `TransformPipeline`.
/// All stages are `Sendable` so pipelines can be built on any thread and passed
/// to SwiftUI Canvas drawing closures safely.
///
/// Source: `docs/architecture/visualization.md` §Transform Pipelines
public protocol TransformStage: Sendable {

    /// Applies this stage's transform to the input data.
    ///
    /// - Parameters:
    ///   - timestamps: Input timestamps in milliseconds (zero-based, same scale as `SensorDataBuffers`).
    ///   - values: Input values parallel to timestamps. May contain NaN for missing data.
    /// - Returns: Transformed (timestamps, values) pair. May be shorter than input.
    func apply(
        timestamps: ContiguousArray<Double>,
        values: ContiguousArray<Float>
    ) -> (timestamps: ContiguousArray<Double>, values: ContiguousArray<Float>)
}
