// Core/Services/Fusion/FusionConstants.swift v1.1.0
/**
 * Calibrated constants for fusion engine pipeline.
 * Production-verified in RowDataLab v2.6.0 on real rowing data.
 * DO NOT MODIFY without experimental validation.
 * --- Revision History ---
 * v1.1.0 - 2026-03-03 - Add multi-validated stroke detection constants.
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

    // MARK: Step 3 — Dynamic Thresholds

    /// Fraction of detRange (P95-P05) for up/down thresholds
    public static let strokeDetThresholdFraction: Float = 0.20

    /// Safety floor: fraction of P95 for threshold minimum
    public static let strokeDetThresholdFloorFraction: Float = 0.06

    /// Fraction of detRange for rearm threshold
    public static let strokeDetRearmFraction: Float = 0.08

    /// Safety floor: fraction of P95 for rearm minimum
    public static let strokeDetRearmFloorFraction: Float = 0.02

    // MARK: Step 3 — Swing Ratio Validation

    /// Minimum swing ratio (floor)
    public static let strokeDetSwingRatioFloor: Float = 0.06

    /// Maximum swing ratio (ceiling)
    public static let strokeDetSwingRatioCeil: Float = 0.18

    /// Scaling factor for swing ratio from range ratio
    public static let strokeDetSwingRatioScale: Float = 0.35

    // MARK: Step 3 — Adaptive Timing

    /// Reject candidates closer than this fraction of estimated period
    public static let strokeDetTimingRejectFraction: Double = 0.45

    /// Default estimated stroke period (ms) when history is insufficient
    public static let strokeDetDefaultPeriodMs: Double = 1200.0

    /// Number of recent periods to keep for rolling median
    public static let strokeDetMaxPeriodHistoryCount: Int = 7

    /// Minimum stroke period for history recording (ms)
    public static let strokeDetMinPeriodHistoryMs: Double = 500.0

    /// Maximum stroke period for history recording (ms)
    public static let strokeDetMaxPeriodHistoryMs: Double = 6000.0

    /// Minimum physiological stroke duration (seconds)
    public static let strokeDetMinStrokeDurS: Double = 0.8

    /// Maximum physiological stroke duration (seconds)
    public static let strokeDetMaxStrokeDurS: Double = 5.0

    // MARK: Step 3 — Acceleration Pattern Validation

    /// Pre-catch search window (ms before catch)
    public static let strokeDetAccelPreWindowMs: Double = 250.0

    /// Post-catch search window (ms after catch)
    public static let strokeDetAccelPostWindowMs: Double = 300.0

    /// Pre-catch minimum acceleration (G) — must be below this (negative)
    public static let strokeDetAccelPreMinG: Float = -0.03

    /// Post-catch minimum acceleration (G) — must be above this (positive)
    public static let strokeDetAccelPostMinG: Float = 0.03

    /// Minimum amplitude (postMax - preMin) in G for valid catch pattern
    public static let strokeDetAccelMinAmplitudeG: Float = 0.08

    // MARK: Step 3 — Cross-Validation

    /// Tolerance for FIT cadence agreement (SPM)
    public static let strokeDetCadenceToleranceSPM: Double = 3.0

    /// Epsilon for floating-point comparisons
    public static let strokeDetEps: Float = 0.01

    // MARK: - Step 4: Per-Stroke Aggregation

    /// Efficiency denominator offset (prevents division by near-zero)
    public static let efficiencyDenominatorOffset: Double = 0.1

    // MARK: - General

    /// Algorithm version tag
    public static let algorithmVersion: String = "1.1.0"
}
