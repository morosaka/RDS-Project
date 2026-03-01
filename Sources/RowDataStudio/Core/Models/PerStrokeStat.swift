//
// PerStrokeStat.swift
// RowData Studio
//
// Per-stroke aggregated statistics.
// Computed from SensorDataBuffers for each StrokeEvent using MetricDef aggregation modes.
//
// Version: 1.0.0 (2026-03-01)
// Revision History:
//   2026-03-01: Initial implementation (Phase 1: Data Models)
//
// Source: docs/specs/fusion-engine.md §Step 6: Per-Stroke Aggregation
//

import Foundation

/// Per-stroke aggregated statistics.
///
/// Contains aggregated metrics for a single stroke cycle.
/// All metrics are computed according to their respective MetricDef.aggregationMode.
public struct PerStrokeStat: Codable, Sendable, Hashable {
    /// Stroke index (matches StrokeEvent.index)
    public let strokeIndex: Int

    /// Stroke duration in seconds
    public let duration: TimeInterval

    /// Stroke rate in strokes per minute
    public let strokeRate: Double

    /// Distance traveled during stroke (meters), if available
    public let distance: Double?

    /// Average velocity (m/s), if available
    public let avgVelocity: Double?

    /// Peak velocity (m/s), if available
    public let peakVelocity: Double?

    /// Average heart rate (bpm), if available
    public let avgHR: Double?

    /// Average power (watts), if available
    public let avgPower: Double?

    /// Average pitch (degrees), if available
    public let avgPitch: Double?

    /// Average roll (degrees), if available
    public let avgRoll: Double?

    /// Dynamic metrics: metricID → aggregated value
    ///
    /// Contains all other metrics from MetricDef registry, aggregated per their mode.
    /// Examples: "mech_ext_ps_force_avg", "mech_ext_ps_angle_max", etc.
    public let metrics: [String: Double]

    public init(
        strokeIndex: Int,
        duration: TimeInterval,
        strokeRate: Double,
        distance: Double? = nil,
        avgVelocity: Double? = nil,
        peakVelocity: Double? = nil,
        avgHR: Double? = nil,
        avgPower: Double? = nil,
        avgPitch: Double? = nil,
        avgRoll: Double? = nil,
        metrics: [String: Double] = [:]
    ) {
        self.strokeIndex = strokeIndex
        self.duration = duration
        self.strokeRate = strokeRate
        self.distance = distance
        self.avgVelocity = avgVelocity
        self.peakVelocity = peakVelocity
        self.avgHR = avgHR
        self.avgPower = avgPower
        self.avgPitch = avgPitch
        self.avgRoll = avgRoll
        self.metrics = metrics
    }
}
