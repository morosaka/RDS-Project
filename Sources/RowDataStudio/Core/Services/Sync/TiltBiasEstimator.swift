// Core/Services/Sync/TiltBiasEstimator.swift v1.0.0
/**
 * Step 0: Tilt bias estimation.
 * The IMU surge axis includes a static gravity component due to camera tilt.
 * Estimates bias by comparing average IMU surge vs average GPS acceleration.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Foundation

/// Step 0: Tilt bias estimator.
///
/// The camera is typically tilted ~3-5° from horizontal. This projects a small
/// gravity component onto the surge (Y) axis. We estimate this bias by comparing
/// the average IMU acceleration with the average GPS-derived acceleration over
/// the entire session.
///
/// **Algorithm:**
/// ```
/// avgImuSurge = mean(accel.y)  // m/s²
/// avgGpsAccel = (gpsSpeed[last] - gpsSpeed[first]) / sessionDuration  // m/s²
/// tiltBiasMps2 = avgImuSurge - avgGpsAccel
/// tiltBiasG = tiltBiasMps2 / 9.80665
/// ```
///
/// Source: `docs/specs/sync-pipeline.md` §Step 0
public struct TiltBiasEstimator {

    /// Result of tilt bias estimation.
    public struct Result: Sendable {
        /// Estimated tilt bias in m/s²
        public let biasMps2: Double
        /// Estimated tilt bias in G
        public let biasG: Double
        /// Average IMU surge acceleration (m/s²)
        public let avgImuSurge: Double
        /// Average GPS-derived acceleration (m/s²)
        public let avgGpsAccel: Double
    }

    /// Estimates tilt bias from GPMF accelerometer and GPS data.
    ///
    /// - Parameters:
    ///   - accelSurgeMps2: Raw surge acceleration array (m/s²)
    ///   - gpsSpeedMs: GPS speed array (m/s)
    ///   - gpsTimestampsMs: GPS timestamps in milliseconds
    /// - Returns: Tilt bias estimate, or nil if insufficient data.
    public static func estimate(
        accelSurgeMps2: ContiguousArray<Float>,
        gpsSpeedMs: ContiguousArray<Float>,
        gpsTimestampsMs: ContiguousArray<Double>
    ) -> Result? {
        guard accelSurgeMps2.count >= 2,
              gpsSpeedMs.count >= 2,
              gpsTimestampsMs.count == gpsSpeedMs.count else {
            return nil
        }

        // Average IMU surge (includes gravity component from tilt)
        let avgImuSurge = Double(DSP.mean(accelSurgeMps2))
        guard !avgImuSurge.isNaN else { return nil }

        // Average GPS-derived acceleration over session
        let firstSpeed = Double(gpsSpeedMs[0])
        let lastSpeed = Double(gpsSpeedMs[gpsSpeedMs.count - 1])
        let firstTime = gpsTimestampsMs[0]
        let lastTime = gpsTimestampsMs[gpsTimestampsMs.count - 1]
        let durationS = (lastTime - firstTime) / 1000.0

        guard durationS > 1.0 else { return nil }

        let avgGpsAccel = (lastSpeed - firstSpeed) / durationS

        // Bias = IMU average - GPS average
        let biasMps2 = avgImuSurge - avgGpsAccel
        let biasG = biasMps2 / SyncConstants.standardGravity

        return Result(
            biasMps2: biasMps2,
            biasG: biasG,
            avgImuSurge: avgImuSurge,
            avgGpsAccel: avgGpsAccel
        )
    }
}
