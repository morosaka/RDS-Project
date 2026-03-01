//
// SensorDataBuffers.swift
// RowData Studio
//
// Structure-of-Arrays (SoA) sensor data buffers for high-performance analysis.
// Cache-friendly, SIMD-compatible, Accelerate/vDSP-optimized.
//
// Version: 1.0.0 (2026-03-01)
// Revision History:
//   2026-03-01: Initial implementation (Phase 1: Data Models)
//
// Source: docs/architecture/data-models.md §In-Memory SoA Buffers
//
// CRITICAL DESIGN DECISIONS:
// - SoA (Structure of Arrays) instead of AoS for cache efficiency
// - ContiguousArray<Float> for zero-copy Accelerate interop
// - NaN sentinel for missing data (GPS not synced, HR unavailable)
// - final class (reference semantics) for shared access across widgets
// - @unchecked Sendable: access must be confined to single task/actor
//

import Foundation

/// In-memory sensor data buffers (Structure of Arrays).
///
/// All sensor channels are stored as parallel arrays for optimal cache locality
/// and SIMD/Accelerate performance. Missing data uses Float.nan sentinel.
///
/// **MVP channels (~15)**: IMU (raw + filtered), GPS, fused pitch/roll/velocity,
/// stroke indices. Additional channels added incrementally in later phases.
///
/// **Thread safety**: @unchecked Sendable. Access must be confined to a single
/// task or protected by external synchronization.
public final class SensorDataBuffers: @unchecked Sendable {
    /// Total sample count (all arrays have this length)
    public let size: Int

    // MARK: - Timestamps

    /// Relative timestamps in milliseconds (Float64 for precision)
    ///
    /// Zero-based: first sample at t=0.0, subsequent samples at their relative time.
    public var timestamp: ContiguousArray<Double>

    // MARK: - IMU Raw (200 Hz)

    /// Raw surge acceleration (longitudinal, m/s²)
    public var imu_raw_ts_acc_surge: ContiguousArray<Float>

    /// Raw sway acceleration (lateral, m/s²)
    public var imu_raw_ts_acc_sway: ContiguousArray<Float>

    /// Raw heave acceleration (vertical, m/s²)
    public var imu_raw_ts_acc_heave: ContiguousArray<Float>

    /// Raw pitch angular velocity (deg/s)
    public var imu_raw_ts_gyro_pitch: ContiguousArray<Float>

    /// Raw roll angular velocity (deg/s)
    public var imu_raw_ts_gyro_roll: ContiguousArray<Float>

    /// Raw yaw angular velocity (deg/s)
    public var imu_raw_ts_gyro_yaw: ContiguousArray<Float>

    /// Gravity vector X component
    public var imu_raw_ts_grav_x: ContiguousArray<Float>

    /// Gravity vector Y component
    public var imu_raw_ts_grav_y: ContiguousArray<Float>

    /// Gravity vector Z component
    public var imu_raw_ts_grav_z: ContiguousArray<Float>

    // MARK: - IMU Filtered

    /// Filtered surge acceleration (Gaussian σ=4, m/s²)
    public var imu_flt_ts_acc_surge: ContiguousArray<Float>

    // MARK: - Fused Calibrated

    /// Fused pitch angle from gravity (degrees)
    public var fus_cal_ts_pitch: ContiguousArray<Float>

    /// Fused roll angle from gravity (degrees)
    public var fus_cal_ts_roll: ContiguousArray<Float>

    /// Fused velocity (complementary filter, m/s)
    public var fus_cal_ts_vel_inertial: ContiguousArray<Float>

    // MARK: - GPS (10-18 Hz, Float64 for coordinates)

    /// GPS latitude (degrees, WGS84)
    public var gps_gpmf_ts_lat: ContiguousArray<Double>

    /// GPS longitude (degrees, WGS84)
    public var gps_gpmf_ts_lon: ContiguousArray<Double>

    /// GPS speed (m/s)
    public var gps_gpmf_ts_speed: ContiguousArray<Float>

    // MARK: - Physiological (from FIT, ~1 Hz)

    /// Heart rate (bpm)
    public var phys_ext_ts_hr: ContiguousArray<Float>

    // MARK: - Stroke Detection

    /// Stroke index (0-based, -1 for no stroke)
    public var strokeIndex: ContiguousArray<Int32>

    /// Stroke phase (0.0 = recovery, 1.0 = drive)
    public var strokePhase: ContiguousArray<Float>

    // MARK: - Dynamic Channels

    /// Dynamic/custom metrics (added incrementally)
    ///
    /// Examples: "mech_ext_ps_force_avg", "gps_ext_ts_cadence"
    public var dynamic: [String: ContiguousArray<Float>]

    // MARK: - Initialization

    public init(size: Int) {
        self.size = size

        // Initialize all arrays with NaN (missing data sentinel)
        self.timestamp = ContiguousArray(repeating: .nan, count: size)
        self.imu_raw_ts_acc_surge = ContiguousArray(repeating: .nan, count: size)
        self.imu_raw_ts_acc_sway = ContiguousArray(repeating: .nan, count: size)
        self.imu_raw_ts_acc_heave = ContiguousArray(repeating: .nan, count: size)
        self.imu_raw_ts_gyro_pitch = ContiguousArray(repeating: .nan, count: size)
        self.imu_raw_ts_gyro_roll = ContiguousArray(repeating: .nan, count: size)
        self.imu_raw_ts_gyro_yaw = ContiguousArray(repeating: .nan, count: size)
        self.imu_raw_ts_grav_x = ContiguousArray(repeating: .nan, count: size)
        self.imu_raw_ts_grav_y = ContiguousArray(repeating: .nan, count: size)
        self.imu_raw_ts_grav_z = ContiguousArray(repeating: .nan, count: size)
        self.imu_flt_ts_acc_surge = ContiguousArray(repeating: .nan, count: size)
        self.fus_cal_ts_pitch = ContiguousArray(repeating: .nan, count: size)
        self.fus_cal_ts_roll = ContiguousArray(repeating: .nan, count: size)
        self.fus_cal_ts_vel_inertial = ContiguousArray(repeating: .nan, count: size)
        self.gps_gpmf_ts_lat = ContiguousArray(repeating: .nan, count: size)
        self.gps_gpmf_ts_lon = ContiguousArray(repeating: .nan, count: size)
        self.gps_gpmf_ts_speed = ContiguousArray(repeating: .nan, count: size)
        self.phys_ext_ts_hr = ContiguousArray(repeating: .nan, count: size)
        self.strokeIndex = ContiguousArray(repeating: -1, count: size)
        self.strokePhase = ContiguousArray(repeating: .nan, count: size)
        self.dynamic = [:]
    }
}

// MARK: - Codable

extension SensorDataBuffers: Codable {
    enum CodingKeys: String, CodingKey {
        case size
        case timestamp
        case imu_raw_ts_acc_surge, imu_raw_ts_acc_sway, imu_raw_ts_acc_heave
        case imu_raw_ts_gyro_pitch, imu_raw_ts_gyro_roll, imu_raw_ts_gyro_yaw
        case imu_raw_ts_grav_x, imu_raw_ts_grav_y, imu_raw_ts_grav_z
        case imu_flt_ts_acc_surge
        case fus_cal_ts_pitch, fus_cal_ts_roll, fus_cal_ts_vel_inertial
        case gps_gpmf_ts_lat, gps_gpmf_ts_lon, gps_gpmf_ts_speed
        case phys_ext_ts_hr
        case strokeIndex, strokePhase
        case dynamic
    }

    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let size = try container.decode(Int.self, forKey: .size)

        self.init(size: size)

        // Decode all arrays (ContiguousArray not directly Codable, use Array)
        self.timestamp = ContiguousArray(try container.decode([Double].self, forKey: .timestamp))
        self.imu_raw_ts_acc_surge = ContiguousArray(try container.decode([Float].self, forKey: .imu_raw_ts_acc_surge))
        self.imu_raw_ts_acc_sway = ContiguousArray(try container.decode([Float].self, forKey: .imu_raw_ts_acc_sway))
        self.imu_raw_ts_acc_heave = ContiguousArray(try container.decode([Float].self, forKey: .imu_raw_ts_acc_heave))
        self.imu_raw_ts_gyro_pitch = ContiguousArray(try container.decode([Float].self, forKey: .imu_raw_ts_gyro_pitch))
        self.imu_raw_ts_gyro_roll = ContiguousArray(try container.decode([Float].self, forKey: .imu_raw_ts_gyro_roll))
        self.imu_raw_ts_gyro_yaw = ContiguousArray(try container.decode([Float].self, forKey: .imu_raw_ts_gyro_yaw))
        self.imu_raw_ts_grav_x = ContiguousArray(try container.decode([Float].self, forKey: .imu_raw_ts_grav_x))
        self.imu_raw_ts_grav_y = ContiguousArray(try container.decode([Float].self, forKey: .imu_raw_ts_grav_y))
        self.imu_raw_ts_grav_z = ContiguousArray(try container.decode([Float].self, forKey: .imu_raw_ts_grav_z))
        self.imu_flt_ts_acc_surge = ContiguousArray(try container.decode([Float].self, forKey: .imu_flt_ts_acc_surge))
        self.fus_cal_ts_pitch = ContiguousArray(try container.decode([Float].self, forKey: .fus_cal_ts_pitch))
        self.fus_cal_ts_roll = ContiguousArray(try container.decode([Float].self, forKey: .fus_cal_ts_roll))
        self.fus_cal_ts_vel_inertial = ContiguousArray(try container.decode([Float].self, forKey: .fus_cal_ts_vel_inertial))
        self.gps_gpmf_ts_lat = ContiguousArray(try container.decode([Double].self, forKey: .gps_gpmf_ts_lat))
        self.gps_gpmf_ts_lon = ContiguousArray(try container.decode([Double].self, forKey: .gps_gpmf_ts_lon))
        self.gps_gpmf_ts_speed = ContiguousArray(try container.decode([Float].self, forKey: .gps_gpmf_ts_speed))
        self.phys_ext_ts_hr = ContiguousArray(try container.decode([Float].self, forKey: .phys_ext_ts_hr))
        self.strokeIndex = ContiguousArray(try container.decode([Int32].self, forKey: .strokeIndex))
        self.strokePhase = ContiguousArray(try container.decode([Float].self, forKey: .strokePhase))

        // Decode dynamic channels
        let dynamicArrays = try container.decode([String: [Float]].self, forKey: .dynamic)
        self.dynamic = dynamicArrays.mapValues { ContiguousArray($0) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(size, forKey: .size)
        try container.encode(Array(timestamp), forKey: .timestamp)
        try container.encode(Array(imu_raw_ts_acc_surge), forKey: .imu_raw_ts_acc_surge)
        try container.encode(Array(imu_raw_ts_acc_sway), forKey: .imu_raw_ts_acc_sway)
        try container.encode(Array(imu_raw_ts_acc_heave), forKey: .imu_raw_ts_acc_heave)
        try container.encode(Array(imu_raw_ts_gyro_pitch), forKey: .imu_raw_ts_gyro_pitch)
        try container.encode(Array(imu_raw_ts_gyro_roll), forKey: .imu_raw_ts_gyro_roll)
        try container.encode(Array(imu_raw_ts_gyro_yaw), forKey: .imu_raw_ts_gyro_yaw)
        try container.encode(Array(imu_raw_ts_grav_x), forKey: .imu_raw_ts_grav_x)
        try container.encode(Array(imu_raw_ts_grav_y), forKey: .imu_raw_ts_grav_y)
        try container.encode(Array(imu_raw_ts_grav_z), forKey: .imu_raw_ts_grav_z)
        try container.encode(Array(imu_flt_ts_acc_surge), forKey: .imu_flt_ts_acc_surge)
        try container.encode(Array(fus_cal_ts_pitch), forKey: .fus_cal_ts_pitch)
        try container.encode(Array(fus_cal_ts_roll), forKey: .fus_cal_ts_roll)
        try container.encode(Array(fus_cal_ts_vel_inertial), forKey: .fus_cal_ts_vel_inertial)
        try container.encode(Array(gps_gpmf_ts_lat), forKey: .gps_gpmf_ts_lat)
        try container.encode(Array(gps_gpmf_ts_lon), forKey: .gps_gpmf_ts_lon)
        try container.encode(Array(gps_gpmf_ts_speed), forKey: .gps_gpmf_ts_speed)
        try container.encode(Array(phys_ext_ts_hr), forKey: .phys_ext_ts_hr)
        try container.encode(Array(strokeIndex), forKey: .strokeIndex)
        try container.encode(Array(strokePhase), forKey: .strokePhase)

        // Encode dynamic channels
        let dynamicArrays = dynamic.mapValues { Array($0) }
        try container.encode(dynamicArrays, forKey: .dynamic)
    }
}
