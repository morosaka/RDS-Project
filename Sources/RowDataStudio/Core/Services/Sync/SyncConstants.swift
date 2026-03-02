// Core/Services/Sync/SyncConstants.swift v1.0.0
/**
 * Calibrated constants for synchronization pipeline.
 * Production-verified in RowDataLab v2.6.0 on real rowing data.
 * DO NOT MODIFY without experimental validation.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Foundation

/// Calibrated constants for the sync pipeline.
///
/// All values verified against production RowDataLab v2.6.0.
/// Source: `docs/specs/sync-pipeline.md`
public enum SyncConstants {

    // MARK: - Step 1: SignMatch (IMU-GPS internal alignment)

    /// Resampling step for uniform grid (milliseconds)
    public static let resampleStepMs: Double = 20.0

    /// Analysis window around GPS speed peak (± milliseconds)
    public static let searchWindowMs: Double = 20_000.0

    /// Maximum lag search range (± milliseconds)
    public static let maxLagMs: Double = 2_500.0

    /// Minimum score for accepting SignMatch result
    public static let scoreThreshold: Double = 0.15

    /// Gaussian smoothing sigma for GPS speed in SignMatch
    public static let gpsSmoothSigma: Float = 8.0

    /// Slope binarization threshold (m/s per step)
    public static let slopeThreshold: Double = 0.02

    // MARK: - Step 3A: GpsSpeedCorrelator

    /// Search range for FIT-GPMF speed correlation (± milliseconds)
    public static let speedCorrSearchRangeMs: Double = 300_000.0

    /// Resampling step for speed correlation (milliseconds, 1 Hz)
    public static let speedCorrResampleStepMs: Double = 1_000.0

    /// Minimum separation between correlation peaks (milliseconds)
    public static let speedCorrMinPeakSeparationMs: Double = 30_000.0

    /// Confidence thresholds for speed correlator
    public static let speedCorrHighConfidence: Double = 2.5
    public static let speedCorrMediumConfidence: Double = 1.5

    // MARK: - Step 3B: GpsTrackCorrelator

    /// Coarse scan range (± milliseconds)
    public static let trackCorrCoarseRangeMs: Double = 300_000.0

    /// Coarse scan step (milliseconds)
    public static let trackCorrCoarseStepMs: Double = 1_000.0

    /// Fine scan range around coarse minimum (± milliseconds)
    public static let trackCorrFineRangeMs: Double = 5_000.0

    /// Fine scan step (milliseconds)
    public static let trackCorrFineStepMs: Double = 100.0

    /// Maximum time difference for matching GPS pairs (milliseconds)
    public static let trackCorrMaxTimeDiffMs: Double = 2_000.0

    // MARK: - Cross-Validation

    /// Consistent agreement threshold (seconds)
    public static let crossValConsistentS: Double = 2.0

    /// Close agreement threshold (seconds)
    public static let crossValCloseS: Double = 10.0

    // MARK: - General

    /// Standard gravity (m/s²)
    public static let standardGravity: Double = 9.80665
}
