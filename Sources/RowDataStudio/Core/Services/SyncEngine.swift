// Core/Services/SyncEngine.swift v1.0.0
/**
 * Orchestrates the 4-step synchronization pipeline.
 * Steps: TiltBias → SignMatch → (Video, no-op) → FIT-GPMF (Speed + Track).
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Foundation

/// Orchestrates the multi-step synchronization pipeline.
///
/// **Pipeline:**
/// - Step 0: Tilt bias estimation (IMU gravity component)
/// - Step 1: SignMatch (internal GPMF IMU-GPS alignment)
/// - Step 2: Video-GPMF alignment (intrinsic, offset=0, no-op)
/// - Step 3: FIT-GPMF alignment (speed correlation + track correlation + cross-validation)
///
/// Source: `docs/specs/sync-pipeline.md`
public struct SyncEngine {

    /// Complete sync pipeline output.
    public struct Output: Sendable {
        /// Step 0: Tilt bias result
        public let tiltBias: TiltBiasEstimator.Result?

        /// Step 1: SignMatch result (IMU-GPS lag)
        public let signMatch: SignMatchStrategy.Result?

        /// Step 3A: GPS speed correlation result
        public let speedCorrelation: GpsSpeedCorrelator.Result?

        /// Step 3B: GPS track correlation result
        public let trackCorrelation: GpsTrackCorrelator.Result?

        /// Cross-validated FIT-GPMF sync result
        public let fitGpmfSync: SyncResult

        /// Diagnostic warnings
        public let warnings: [String]
    }

    /// Runs the full sync pipeline.
    ///
    /// - Parameters:
    ///   - gpmfGps: GPMF GPS time series (from GPMFAdapter)
    ///   - gpmfAccel: GPMF accelerometer time series (from GPMFAdapter)
    ///   - fitTimeSeries: FIT time series (from FITAdapter)
    /// - Returns: Complete sync output with cross-validated result.
    public static func synchronize(
        gpmfGps: GPMFGpsTimeSeries,
        gpmfAccel: GPMFAccelTimeSeries,
        fitTimeSeries: FITTimeSeries
    ) -> Output {
        var warnings: [String] = []

        // STEP 0: Tilt bias
        let tiltBias = TiltBiasEstimator.estimate(
            accelSurgeMps2: gpmfAccel.surgeMps2,
            gpsSpeedMs: gpmfGps.speed,
            gpsTimestampsMs: gpmfGps.timestampsMs
        )
        if tiltBias == nil {
            warnings.append("Step 0: Tilt bias estimation failed (insufficient data)")
        }

        // STEP 1: SignMatch (IMU-GPS internal lag)
        // Apply tilt bias correction before SignMatch
        var correctedAccel = gpmfAccel.surgeMps2
        if let bias = tiltBias {
            let biasF = Float(bias.biasMps2)
            for i in 0..<correctedAccel.count {
                correctedAccel[i] -= biasF
            }
        }

        let signMatch = SignMatchStrategy.estimateLag(
            accelTimestampsMs: gpmfAccel.timestampsMs,
            accelSurgeMps2: correctedAccel,
            gpsTimestampsMs: gpmfGps.timestampsMs,
            gpsSpeed: gpmfGps.speed
        )
        if let sm = signMatch, !sm.accepted {
            warnings.append("Step 1: SignMatch score (\(String(format: "%.3f", sm.score))) below threshold")
        } else if signMatch == nil {
            warnings.append("Step 1: SignMatch failed (insufficient data)")
        }

        // STEP 2: Video-GPMF (intrinsic, offset=0, no-op)
        // GPMF timestamps are already relative to MP4 file

        // STEP 3A: GPS Speed Correlation
        let speedResult = GpsSpeedCorrelator.correlate(
            gpmfTimestampsMs: gpmfGps.timestampsMs,
            gpmfSpeed: gpmfGps.speed,
            fitTimestampsMs: fitTimeSeries.timestampsMs,
            fitSpeed: fitTimeSeries.speed
        )
        if speedResult == nil {
            warnings.append("Step 3A: GPS speed correlation failed (insufficient data)")
        }

        // STEP 3B: GPS Track Correlation
        let trackResult = GpsTrackCorrelator.correlate(
            gpmfTimestampsMs: gpmfGps.timestampsMs,
            gpmfLat: gpmfGps.latitude,
            gpmfLon: gpmfGps.longitude,
            fitTimestampsMs: fitTimeSeries.timestampsMs,
            fitLat: fitTimeSeries.latitude,
            fitLon: fitTimeSeries.longitude
        )
        if trackResult == nil {
            warnings.append("Step 3B: GPS track correlation failed (insufficient data)")
        }

        // Cross-validation
        let fitGpmfSync = crossValidate(
            speed: speedResult,
            track: trackResult,
            warnings: &warnings
        )

        return Output(
            tiltBias: tiltBias,
            signMatch: signMatch,
            speedCorrelation: speedResult,
            trackCorrelation: trackResult,
            fitGpmfSync: fitGpmfSync,
            warnings: warnings
        )
    }

    // MARK: - Cross-Validation

    /// Cross-validates speed and track correlation results.
    private static func crossValidate(
        speed: GpsSpeedCorrelator.Result?,
        track: GpsTrackCorrelator.Result?,
        warnings: inout [String]
    ) -> SyncResult {
        // Both available: cross-validate
        if let s = speed, let t = track {
            let diffS = abs(s.offsetMs - t.offsetMs) / 1000.0  // seconds
            let confidence: Double
            let strategy: SyncStrategy
            let offset: TimeInterval

            if diffS < SyncConstants.crossValConsistentS {
                // Consistent: average of both
                confidence = 1.0
                offset = (s.offsetMs + t.offsetMs) / 2.0 / 1000.0
                strategy = .gpsSpeedCorrelator  // primary
            } else if diffS < SyncConstants.crossValCloseS {
                // Close: prefer higher-confidence result
                confidence = 0.7
                if s.confidence == .high {
                    offset = s.offsetMs / 1000.0
                    strategy = .gpsSpeedCorrelator
                } else {
                    offset = t.offsetMs / 1000.0
                    strategy = .gpsTrackCorrelator
                }
                warnings.append("Cross-validation: results close but not consistent (\(String(format: "%.1f", diffS))s difference)")
            } else {
                // Disagreement: prefer speed correlator if high confidence
                confidence = 0.3
                if s.confidence != .low {
                    offset = s.offsetMs / 1000.0
                    strategy = .gpsSpeedCorrelator
                } else {
                    offset = t.offsetMs / 1000.0
                    strategy = .gpsTrackCorrelator
                }
                warnings.append("Cross-validation: strategies disagree (\(String(format: "%.1f", diffS))s). Manual verification recommended.")
            }

            return SyncResult(
                offset: offset,
                confidence: confidence,
                strategy: strategy,
                correlationScore: s.peakCorrelation,
                searchWindowMs: Int(SyncConstants.speedCorrSearchRangeMs),
                diagnosticMessage: "Speed offset: \(String(format: "%.0f", s.offsetMs))ms, Track offset: \(String(format: "%.0f", t.offsetMs))ms"
            )
        }

        // Only speed available
        if let s = speed {
            let confidence: Double = s.confidence == .high ? 0.8 : s.confidence == .medium ? 0.5 : 0.2
            return SyncResult(
                offset: s.offsetMs / 1000.0,
                confidence: confidence,
                strategy: .gpsSpeedCorrelator,
                correlationScore: s.peakCorrelation,
                searchWindowMs: Int(SyncConstants.speedCorrSearchRangeMs),
                diagnosticMessage: "Speed-only sync (track correlation unavailable)"
            )
        }

        // Only track available
        if let t = track {
            return SyncResult(
                offset: t.offsetMs / 1000.0,
                confidence: 0.5,
                strategy: .gpsTrackCorrelator,
                diagnosticMessage: "Track-only sync (speed correlation unavailable)"
            )
        }

        // Neither available
        warnings.append("No automatic sync possible. Manual alignment required.")
        return SyncResult(
            offset: 0,
            confidence: 0,
            strategy: .none,
            diagnosticMessage: "No sync strategies succeeded"
        )
    }
}
