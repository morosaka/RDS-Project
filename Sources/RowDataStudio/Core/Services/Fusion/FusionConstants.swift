// Core/Services/Fusion/FusionConstants.swift v1.0.0
/**
 * Calibrated constants for fusion engine pipeline.
 * Production-verified in RowDataLab v2.6.0 on real rowing data.
 * DO NOT MODIFY without experimental validation.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Foundation

/// Calibrated constants for the fusion engine.
///
/// All values verified against production RowDataLab v2.6.0.
/// Source: `docs/specs/fusion-engine.md`
public enum FusionConstants {

    // MARK: - Step 1.5: Physics Prep

    /// Gaussian sigma for ACCL smoothing in physics prep
    public static let physPrepGaussianSigma: Float = 4.0

    // MARK: - Step 2: Fusion Loop

    /// Complementary filter alpha (heavy IMU trust)
    ///
    /// vel = alpha * (vel + acc * dt) + (1 - alpha) * gpsSpeed
    /// 0.999 → 99.9% IMU, 0.1% GPS correction each sample
    public static let complementaryAlpha: Double = 0.999

    /// IMU sample rate (Hz)
    public static let imuSampleRate: Double = 200.0

    /// IMU sample interval (seconds)
    public static let imuDt: Double = 1.0 / 200.0

    // MARK: - Step 3: Stroke Detection

    /// Zero-phase smoothing half-window for velocity (samples)
    public static let strokeDetZeroPhaseWindow: Int = 15

    /// Baseline window for adaptive detrending (seconds)
    public static let strokeDetBaselineWindowS: Double = 6.0

    /// Swing ratio bounds for stroke validation (drive/total)
    public static let swingRatioMin: Double = 0.25
    public static let swingRatioMax: Double = 0.55

    // MARK: - Step 4: Per-Stroke Aggregation

    /// Efficiency denominator offset (prevents division by near-zero)
    public static let efficiencyDenominatorOffset: Double = 0.1

    // MARK: - General

    /// Algorithm version tag
    public static let algorithmVersion: String = "1.0.0"
}
