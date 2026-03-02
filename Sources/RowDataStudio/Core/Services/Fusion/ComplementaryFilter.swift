// Core/Services/Fusion/ComplementaryFilter.swift v1.0.0
/**
 * Complementary filter: fuses IMU acceleration with GPS speed.
 * Heavy IMU trust (α=0.999) with gradual GPS correction.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Foundation

/// Complementary filter for IMU-GPS velocity fusion.
///
/// Combines high-frequency IMU integration with low-frequency GPS correction.
///
/// **Formula (per sample at 200 Hz):**
/// ```
/// vel = α * (vel + acc * dt) + (1 - α) * gpsSpeed
/// α = 0.999 → 99.9% IMU trust, 0.1% GPS correction
/// ```
///
/// When GPS is unavailable (NaN), pure IMU integration is used.
///
/// Source: `docs/specs/fusion-engine.md` §Step 2
public struct ComplementaryFilter {

    /// Filter state (accumulated velocity).
    public struct State: Sendable {
        /// Current fused velocity (m/s)
        public var velocity: Double
        /// Number of samples processed
        public var sampleCount: Int

        public init(velocity: Double = 0, sampleCount: Int = 0) {
            self.velocity = velocity
            self.sampleCount = sampleCount
        }
    }

    /// Processes an entire acceleration series with GPS speed updates.
    ///
    /// - Parameters:
    ///   - accelMps2: Surge acceleration (m/s², tilt-bias corrected, filtered)
    ///   - gpsSpeed: GPS speed interpolated onto IMU timeline (m/s, NaN = unavailable)
    ///   - dt: Sample interval (seconds, default = 1/200)
    ///   - alpha: Filter coefficient (default = 0.999)
    ///   - initialVelocity: Starting velocity (m/s)
    /// - Returns: Fused velocity series (same length as input).
    public static func fuse(
        accelMps2: ContiguousArray<Float>,
        gpsSpeed: ContiguousArray<Float>,
        dt: Double = FusionConstants.imuDt,
        alpha: Double = FusionConstants.complementaryAlpha,
        initialVelocity: Double = 0
    ) -> ContiguousArray<Float> {
        let n = accelMps2.count
        guard n > 0 else { return ContiguousArray<Float>() }

        var result = ContiguousArray<Float>(repeating: .nan, count: n)
        var vel = initialVelocity

        for i in 0..<n {
            let acc = Double(accelMps2[i])
            let gps = Double(gpsSpeed[i])

            if acc.isNaN {
                // No IMU data — hold previous velocity
                result[i] = Float(vel)
                continue
            }

            // IMU integration
            let imuVel = vel + acc * dt

            if !gps.isNaN {
                // GPS available: apply complementary correction
                vel = alpha * imuVel + (1.0 - alpha) * gps
            } else {
                // GPS unavailable: pure IMU integration
                vel = imuVel
            }

            result[i] = Float(vel)
        }

        return result
    }

    /// Estimates convergence time: how many seconds until the filter
    /// velocity is within `tolerance` of GPS speed after a step change.
    ///
    /// Useful for diagnostics. At α=0.999, convergence to within 5% takes ~5s.
    ///
    /// - Parameters:
    ///   - alpha: Filter coefficient
    ///   - tolerance: Fractional tolerance (e.g., 0.05 = 5%)
    ///   - sampleRate: Sample rate in Hz
    /// - Returns: Convergence time in seconds.
    public static func convergenceTime(
        alpha: Double = FusionConstants.complementaryAlpha,
        tolerance: Double = 0.05,
        sampleRate: Double = FusionConstants.imuSampleRate
    ) -> Double {
        // After n samples: error = α^n * initial_error
        // Solve for n: α^n = tolerance → n = log(tolerance) / log(α)
        guard alpha > 0, alpha < 1 else { return .infinity }
        let nSamples = log(tolerance) / log(alpha)
        return nSamples / sampleRate
    }
}
