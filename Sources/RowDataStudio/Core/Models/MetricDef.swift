//
// MetricDef.swift
// RowData Studio
//
// Metric definition registry for sensor and derived channels.
// Defines metadata, units, aggregation modes, and transform pipelines.
//
// Version: 1.0.0 (2026-03-01)
// Revision History:
//   2026-03-01: Initial implementation (Phase 1: Data Models)
//
// Source: docs/architecture/data-models.md §MetricDef
//

import Foundation

/// Aggregation mode for per-stroke statistics.
public enum AggregationMode: String, Codable, Sendable {
    /// Average over stroke duration
    case avg
    /// Delta between stroke start and end (interpolated)
    case deltaInterpolated
    /// Maximum value during stroke
    case max
    /// Minimum value during stroke
    case min
    /// Snapshot at nearest sample (typically stroke end)
    case snapshotNearest
}

/// Transform stage applied to a metric (e.g., smoothing, detrending).
public struct MetricTransform: Codable, Sendable, Hashable {
    /// Transform type identifier (e.g., "gaussian", "detrend", "integrate")
    public let type: String
    /// Transform parameters as JSON-compatible dictionary
    public let parameters: [String: Double]?

    public init(type: String, parameters: [String: Double]? = nil) {
        self.type = type
        self.parameters = parameters
    }
}

/// Metric definition: describes a sensor channel or derived quantity.
///
/// Naming convention: `FAMILY_SOURCE_TYPE_NAME_MODIFIER`
/// Examples:
/// - `imu_raw_ts_acc_surge` (IMU, raw, time-series, acceleration, surge axis)
/// - `fus_cal_ts_vel_inertial` (fusion, calibrated, time-series, velocity, inertial frame)
/// - `phys_ext_ts_hr` (physiological, external FIT, time-series, heart rate)
public struct MetricDef: Codable, Sendable, Hashable {
    /// Unique identifier (follows naming convention)
    public let id: String
    /// Human-readable display name
    public let name: String
    /// Source family (e.g., "imu", "gps", "phys", "mech", "fus")
    public let source: String
    /// Unit string (e.g., "m/s^2", "bpm", "spm", "deg/s")
    public let unit: String?
    /// Optional formula or buffer reference for computed metrics
    public let formula: String?
    /// IDs of required metrics for computed metrics
    public let requirements: [String]
    /// Category (e.g., "kinematics", "physiological", "biomechanical")
    public let category: String
    /// Recommended sampling frequency in Hz (if applicable)
    public let recommendedSamplingHz: Double?
    /// Transform pipeline stages
    public let transforms: [MetricTransform]?
    /// How to aggregate this metric per-stroke
    public let aggregationMode: AggregationMode

    public init(
        id: String,
        name: String,
        source: String,
        unit: String? = nil,
        formula: String? = nil,
        requirements: [String] = [],
        category: String,
        recommendedSamplingHz: Double? = nil,
        transforms: [MetricTransform]? = nil,
        aggregationMode: AggregationMode
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.unit = unit
        self.formula = formula
        self.requirements = requirements
        self.category = category
        self.recommendedSamplingHz = recommendedSamplingHz
        self.transforms = transforms
        self.aggregationMode = aggregationMode
    }
}
