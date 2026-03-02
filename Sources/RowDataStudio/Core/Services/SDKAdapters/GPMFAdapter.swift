// Core/Services/SDKAdapters/GPMFAdapter.swift v1.0.0
/**
 * Adapter layer: GPMF SDK → app-layer types.
 * Converts TelemetryData (AoS, Double, non-Codable) → SensorDataBuffers (SoA, Float).
 * Also produces TelemetrySidecar metadata and intermediate time series for sync.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Foundation
import GPMFSwiftSDK

// MARK: - Intermediate Time Series

/// Lightweight intermediate representation of GPMF GPS data for sync strategies.
///
/// Used by GpsSpeedCorrelator and GpsTrackCorrelator before full fusion.
public struct GPMFGpsTimeSeries: Sendable {
    /// Timestamps in milliseconds (relative to file start)
    public let timestampsMs: ContiguousArray<Double>
    /// GPS speed in m/s (speed3d)
    public let speed: ContiguousArray<Float>
    /// Latitude in degrees
    public let latitude: ContiguousArray<Double>
    /// Longitude in degrees
    public let longitude: ContiguousArray<Double>
}

/// Lightweight intermediate representation of GPMF ACCL data for sync.
public struct GPMFAccelTimeSeries: Sendable {
    /// Timestamps in milliseconds (relative to file start)
    public let timestampsMs: ContiguousArray<Double>
    /// Surge acceleration (Y camera axis, m/s²)
    public let surgeMps2: ContiguousArray<Float>
}

// MARK: - GPMFAdapter

/// Adapter: GPMF SDK → app-layer types.
///
/// All SDK parsing is confined to this adapter. Downstream code never
/// imports GPMFSwiftSDK directly.
public struct GPMFAdapter {

    /// Extracts telemetry from a GoPro MP4 file.
    ///
    /// - Parameter url: Path to the MP4 file.
    /// - Returns: Raw `TelemetryData` from the GPMF SDK.
    /// - Throws: GPMF extraction errors.
    public static func extractTelemetry(from url: URL) throws -> TelemetryData {
        try GPMFExtractor.extract(from: url)
    }

    // MARK: - GPS Time Series (for sync)

    /// Extracts GPS time series for sync strategies.
    ///
    /// Lightweight extraction — only GPS readings, no IMU conversion.
    public static func gpsTimeSeries(from telemetry: TelemetryData) -> GPMFGpsTimeSeries {
        let readings = telemetry.gpsReadings
        let n = readings.count

        var timestampsMs = ContiguousArray<Double>(repeating: 0, count: n)
        var speed = ContiguousArray<Float>(repeating: 0, count: n)
        var latitude = ContiguousArray<Double>(repeating: 0, count: n)
        var longitude = ContiguousArray<Double>(repeating: 0, count: n)

        for i in 0..<n {
            let r = readings[i]
            timestampsMs[i] = r.timestamp * 1000.0
            speed[i] = Float(r.speed3d)
            latitude[i] = r.latitude
            longitude[i] = r.longitude
        }

        return GPMFGpsTimeSeries(
            timestampsMs: timestampsMs,
            speed: speed,
            latitude: latitude,
            longitude: longitude
        )
    }

    // MARK: - ACCL Time Series (for sync)

    /// Extracts surge acceleration time series for sync strategies.
    public static func accelTimeSeries(from telemetry: TelemetryData) -> GPMFAccelTimeSeries {
        let readings = telemetry.accelReadings
        let n = readings.count

        var timestampsMs = ContiguousArray<Double>(repeating: 0, count: n)
        var surgeMps2 = ContiguousArray<Float>(repeating: 0, count: n)

        for i in 0..<n {
            let r = readings[i]
            timestampsMs[i] = r.timestamp * 1000.0
            surgeMps2[i] = Float(r.yCam)  // Y = surge (into camera → forward)
        }

        return GPMFAccelTimeSeries(timestampsMs: timestampsMs, surgeMps2: surgeMps2)
    }

    // MARK: - Full SoA Conversion (for fusion)

    /// Converts full telemetry to SensorDataBuffers.
    ///
    /// Populates IMU raw channels (ACCL, GYRO, GRAV) at native 200 Hz.
    /// GPS channels are interpolated onto the IMU timeline during fusion (Step 2).
    ///
    /// - Parameter telemetry: Raw GPMF telemetry data.
    /// - Returns: SensorDataBuffers with IMU channels populated and GPS left as NaN.
    public static func toSensorDataBuffers(from telemetry: TelemetryData) -> SensorDataBuffers {
        let accel = telemetry.accelReadings
        let gyro = telemetry.gyroReadings
        let gravity = telemetry.gravityReadings
        let n = accel.count

        let buffers = SensorDataBuffers(size: n)

        // Timestamps (ACCL is the master clock at 200 Hz)
        for i in 0..<n {
            buffers.timestamp[i] = accel[i].timestamp * 1000.0  // s → ms
        }

        // ACCL → raw surge/sway/heave
        for i in 0..<n {
            buffers.imu_raw_ts_acc_surge[i] = Float(accel[i].yCam)
            buffers.imu_raw_ts_acc_sway[i] = Float(accel[i].xCam)
            buffers.imu_raw_ts_acc_heave[i] = Float(accel[i].zCam)
        }

        // GYRO → raw pitch/roll/yaw (interpolated to ACCL timestamps)
        populateInterpolated(
            source: gyro, target: buffers, accelTimestamps: accel,
            assignX: { b, i, v in b.imu_raw_ts_gyro_roll[i] = v },
            assignY: { b, i, v in b.imu_raw_ts_gyro_pitch[i] = v },
            assignZ: { b, i, v in b.imu_raw_ts_gyro_yaw[i] = v }
        )

        // GRAV → gravity vector
        populateInterpolated(
            source: gravity, target: buffers, accelTimestamps: accel,
            assignX: { b, i, v in b.imu_raw_ts_grav_x[i] = v },
            assignY: { b, i, v in b.imu_raw_ts_grav_y[i] = v },
            assignZ: { b, i, v in b.imu_raw_ts_grav_z[i] = v }
        )

        // GPS channels remain NaN — populated during fusion loop (Step 2)

        return buffers
    }

    // MARK: - Sidecar Metadata

    /// Creates TelemetrySidecar metadata from telemetry.
    ///
    /// - Parameters:
    ///   - telemetry: Raw GPMF telemetry data.
    ///   - sourceFileHash: SHA256 hash of the source MP4.
    ///   - sourceFileName: Original MP4 filename.
    ///   - trimRange: Time range extracted from original video.
    /// - Returns: TelemetrySidecar with metadata populated.
    public static func buildSidecarMetadata(
        from telemetry: TelemetryData,
        sourceFileHash: String,
        sourceFileName: String,
        trimRange: ClosedRange<TimeInterval>
    ) -> TelemetrySidecar {
        // Convert SDK GPS timestamps to Codable mirror types
        let firstGPSU = telemetry.firstGPSU.map {
            GPSTimestampRecord(value: $0.value, relativeTime: $0.relativeTime)
        }
        let lastGPSU = telemetry.lastGPSU.map {
            GPSTimestampRecord(value: $0.value, relativeTime: $0.relativeTime)
        }
        let firstGPS9 = telemetry.firstGPS9Time.map {
            GPS9TimestampRecord(daysSince2000: $0.daysSince2000, secondsSinceMidnight: $0.secondsSinceMidnight)
        }
        let lastGPS9 = telemetry.lastGPS9Time.map {
            GPS9TimestampRecord(daysSince2000: $0.daysSince2000, secondsSinceMidnight: $0.secondsSinceMidnight)
        }

        // Convert StreamInfo to [String: String]
        var streamInfoDict: [String: String] = [:]
        for (key, info) in telemetry.streamInfo {
            streamInfoDict[key] = "\(Int(info.sampleRate))Hz (\(info.sampleCount) samples)"
        }

        return TelemetrySidecar(
            sourceFileHash: sourceFileHash,
            sourceFileName: sourceFileName,
            originalDuration: telemetry.duration,
            trimRange: trimRange,
            absoluteOrigin: nil,  // Computed later from GPS back-computation
            deviceName: telemetry.deviceName,
            deviceID: telemetry.deviceID,
            orin: telemetry.orin,
            firstGPSU: firstGPSU,
            lastGPSU: lastGPSU,
            firstGPS9Time: firstGPS9,
            lastGPS9Time: lastGPS9,
            mp4CreationTime: telemetry.mp4CreationTime,
            streamInfo: streamInfoDict
        )
    }

    // MARK: - Private Helpers

    /// Interpolates a secondary sensor stream onto ACCL timestamps using nearest-neighbor.
    private static func populateInterpolated(
        source: [SensorReading],
        target: SensorDataBuffers,
        accelTimestamps: [SensorReading],
        assignX: (SensorDataBuffers, Int, Float) -> Void,
        assignY: (SensorDataBuffers, Int, Float) -> Void,
        assignZ: (SensorDataBuffers, Int, Float) -> Void
    ) {
        guard !source.isEmpty else { return }

        var srcIdx = 0
        for i in 0..<accelTimestamps.count {
            let t = accelTimestamps[i].timestamp

            // Advance source index to nearest sample
            while srcIdx < source.count - 1 &&
                  abs(source[srcIdx + 1].timestamp - t) < abs(source[srcIdx].timestamp - t) {
                srcIdx += 1
            }

            assignX(target, i, Float(source[srcIdx].xCam))
            assignY(target, i, Float(source[srcIdx].yCam))
            assignZ(target, i, Float(source[srcIdx].zCam))
        }
    }
}
