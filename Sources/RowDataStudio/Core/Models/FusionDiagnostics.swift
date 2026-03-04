//
// FusionDiagnostics.swift
// RowData Studio
//
// Fusion engine diagnostic output: tilt bias, lag, confidence metrics.
// Used for quality assessment and troubleshooting.
//
// Version: 1.1.0 (2026-03-03)
// Revision History:
//   2026-03-03: Add cadenceAgreement for FIT cross-validation.
//   2026-03-01: Initial implementation (Phase 1: Data Models)
//
// Source: docs/specs/fusion-engine.md §Diagnostics
//

import Foundation

/// Fusion engine diagnostic metrics.
///
/// Contains quality metrics and diagnostic information from the fusion pipeline.
/// Helps assess data quality and identify potential issues.
public struct FusionDiagnostics: Codable, Sendable, Hashable {
    /// Tilt bias estimate (degrees)
    ///
    /// Estimated gravitational bias from Step 0 (TiltBiasEstimator).
    /// Expected range: -5° to +5° for typical rowing.
    public let tiltBias: Double?

    /// Complementary filter convergence time (seconds)
    ///
    /// Time required for IMU-GPS filter to converge to stable velocity.
    /// Typical: 5-10 seconds.
    public let convergenceTime: TimeInterval?

    /// GPS quality score (0.0 = poor, 1.0 = excellent)
    ///
    /// Based on GPS sample count, HDOP/VDOP, and update frequency.
    public let gpsQuality: Double?

    /// IMU quality score (0.0 = poor, 1.0 = excellent)
    ///
    /// Based on sample count, noise level, and consistency.
    public let imuQuality: Double?

    /// Number of detected strokes (valid + invalid)
    public let strokeCount: Int?

    /// Number of valid strokes (excluding partial strokes)
    public let validStrokeCount: Int?

    /// Average stroke rate for the session (spm)
    public let avgStrokeRate: Double?

    /// Sync lag between IMU and GPS (milliseconds)
    ///
    /// From SignMatch correlation peak. Expected: <100ms.
    public let imuGpsLagMs: Double?

    /// Fraction of detected strokes whose rate agrees with FIT cadence (0.0–1.0)
    ///
    /// Computed by comparing `StrokeEvent.strokeRate` against interpolated
    /// FIT cadence at each stroke's midpoint. Agreement threshold: ±3 SPM.
    /// `nil` if no FIT cadence data available.
    public let cadenceAgreement: Double?

    /// Timestamp when diagnostics were computed
    public let timestamp: Date

    /// Optional warnings or error messages
    public let warnings: [String]

    public init(
        tiltBias: Double? = nil,
        convergenceTime: TimeInterval? = nil,
        gpsQuality: Double? = nil,
        imuQuality: Double? = nil,
        strokeCount: Int? = nil,
        validStrokeCount: Int? = nil,
        avgStrokeRate: Double? = nil,
        imuGpsLagMs: Double? = nil,
        cadenceAgreement: Double? = nil,
        timestamp: Date = Date(),
        warnings: [String] = []
    ) {
        self.tiltBias = tiltBias
        self.convergenceTime = convergenceTime
        self.gpsQuality = gpsQuality
        self.imuQuality = imuQuality
        self.strokeCount = strokeCount
        self.validStrokeCount = validStrokeCount
        self.avgStrokeRate = avgStrokeRate
        self.imuGpsLagMs = imuGpsLagMs
        self.cadenceAgreement = cadenceAgreement
        self.timestamp = timestamp
        self.warnings = warnings
    }
}
