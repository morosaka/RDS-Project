// Rendering/Transforms/AdaptiveSmooth.swift v1.0.0
/**
 * TransformStage: zoom-dependent smoothing strategy selector.
 * Heavier smoothing at low zoom (many points/pixel); none at high zoom.
 * --- Revision History ---
 * v1.0.0 - 2026-03-07 - Initial implementation (Phase 4: Rendering + MVP).
 */

/// Applies a zoom-appropriate smoothing filter to the data.
///
/// At high zoom (few points per pixel), smoothing is unnecessary and skipped.
/// At medium zoom, a light Gaussian filter removes high-frequency noise.
/// At low zoom (many points per pixel), a moving average provides fast aggregation.
///
/// Smoothing is applied AFTER LTTB, so the input is already ≤ 2000 points.
public struct AdaptiveSmooth: TransformStage {

    /// Smoothing strategy applied by this stage.
    public enum Strategy: Sendable {
        /// No smoothing (high zoom: < 2 points/pixel).
        case none
        /// Gaussian smooth with given σ (medium zoom: 2–10 points/pixel).
        case gaussian(sigma: Float)
        /// Simple moving average with given window (low zoom: ≥ 10 points/pixel).
        case movingAverage(windowSize: Int)
    }

    public let strategy: Strategy

    public init(strategy: Strategy) {
        self.strategy = strategy
    }

    /// Selects the appropriate strategy based on current zoom level.
    ///
    /// - Parameter pointsPerPixel: Data points per horizontal screen pixel.
    ///   Values > 1 indicate more data than pixels (downsampled territory).
    /// - Returns: Configured `AdaptiveSmooth` stage.
    public static func forZoom(pointsPerPixel: Double) -> AdaptiveSmooth {
        switch pointsPerPixel {
        case ..<2.0:
            return AdaptiveSmooth(strategy: .none)
        case 2.0..<10.0:
            return AdaptiveSmooth(strategy: .gaussian(sigma: 2.0))
        default:
            // Window size: ~1/5 of points-per-pixel, minimum 3, always odd
            let w = max(3, Int(pointsPerPixel / 5.0)) | 1
            return AdaptiveSmooth(strategy: .movingAverage(windowSize: w))
        }
    }

    public func apply(
        timestamps: ContiguousArray<Double>,
        values: ContiguousArray<Float>
    ) -> (timestamps: ContiguousArray<Double>, values: ContiguousArray<Float>) {
        switch strategy {
        case .none:
            return (timestamps, values)
        case .gaussian(let sigma):
            return (timestamps, DSP.gaussianSmooth(values, sigma: sigma))
        case .movingAverage(let w):
            return (timestamps, DSP.simpleMovingAverage(values, windowSize: w))
        }
    }
}
