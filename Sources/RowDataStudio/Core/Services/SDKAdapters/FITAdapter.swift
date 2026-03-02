// Core/Services/SDKAdapters/FITAdapter.swift v1.0.0
/**
 * Adapter layer: FIT SDK → app-layer types.
 * Converts FitMessages.recordMesgs (non-Codable, non-Sendable) to lightweight
 * Codable/Sendable time series for sync and fusion.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Foundation
import FITSwiftSDK

// MARK: - Intermediate Time Series

/// Lightweight FIT record time series for sync and fusion.
///
/// All timestamps are Unix epoch seconds (Double).
/// GPS coordinates are already converted from semicircles to degrees.
public struct FITTimeSeries: Sendable, Codable {
    /// Timestamps in milliseconds (Unix epoch based)
    public let timestampsMs: ContiguousArray<Double>
    /// GPS speed in m/s (enhanced_speed)
    public let speed: ContiguousArray<Float>
    /// Latitude in degrees (WGS84)
    public let latitude: ContiguousArray<Double>
    /// Longitude in degrees (WGS84)
    public let longitude: ContiguousArray<Double>
    /// Heart rate in bpm (NaN if unavailable)
    public let heartRate: ContiguousArray<Float>
    /// Cadence in rpm (NaN if unavailable)
    public let cadence: ContiguousArray<Float>
    /// Power in watts (NaN if unavailable)
    public let power: ContiguousArray<Float>
    /// Distance in meters (cumulative, NaN if unavailable)
    public let distance: ContiguousArray<Float>
}

// MARK: - FITAdapter

/// Adapter: FIT SDK → app-layer types.
///
/// All SDK parsing is confined to this adapter. Downstream code never
/// imports FITSwiftSDK directly.
public struct FITAdapter {

    /// Decodes a FIT file and returns structured messages.
    ///
    /// - Parameter url: Path to the .fit file.
    /// - Returns: Decoded FitMessages containing all message types.
    /// - Throws: FIT decoder errors.
    public static func decode(from url: URL) throws -> FitMessages {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw FITAdapterError.fileNotReadable(url)
        }
        let stream = FITSwiftSDK.InputStream(data: data)
        let decoder = Decoder(stream: stream)
        let listener = FitListener()
        decoder.addMesgListener(listener)
        try decoder.read()
        return listener.fitMessages
    }

    /// Converts FitMessages record messages to a lightweight time series.
    ///
    /// - Parameter messages: Decoded FIT messages.
    /// - Returns: FITTimeSeries with all fields converted to standard units.
    public static func toTimeSeries(from messages: FitMessages) -> FITTimeSeries {
        let records = messages.recordMesgs
        let n = records.count

        var timestampsMs = ContiguousArray<Double>(repeating: .nan, count: n)
        var speed = ContiguousArray<Float>(repeating: .nan, count: n)
        var latitude = ContiguousArray<Double>(repeating: .nan, count: n)
        var longitude = ContiguousArray<Double>(repeating: .nan, count: n)
        var heartRate = ContiguousArray<Float>(repeating: .nan, count: n)
        var cadence = ContiguousArray<Float>(repeating: .nan, count: n)
        var power = ContiguousArray<Float>(repeating: .nan, count: n)
        var distance = ContiguousArray<Float>(repeating: .nan, count: n)

        for i in 0..<n {
            let record = records[i]

            // Timestamp: FIT epoch → Unix epoch (ms)
            if let dt = record.getTimestamp() {
                let unixS = TimeInterval(dt.timestamp) + TimeInterval(DateTime.unixEpochToFITEpoch)
                timestampsMs[i] = unixS * 1000.0
            }

            // GPS speed (enhanced_speed preferred, fallback to speed)
            if let s = record.getEnhancedSpeed() {
                speed[i] = Float(s)
            } else if let s = record.getSpeed() {
                speed[i] = Float(s)
            }

            // GPS position (semicircles → degrees)
            if let lat = record.getPositionLat() {
                latitude[i] = Haversine.semicirclesToDegrees(lat)
            }
            if let lon = record.getPositionLong() {
                longitude[i] = Haversine.semicirclesToDegrees(lon)
            }

            // Physiological metrics
            if let hr = record.getHeartRate() {
                heartRate[i] = Float(hr)
            }
            if let cad = record.getCadence() {
                cadence[i] = Float(cad)
            }
            if let pwr = record.getPower() {
                power[i] = Float(pwr)
            }
            if let dist = record.getDistance() {
                distance[i] = Float(dist)
            }
        }

        return FITTimeSeries(
            timestampsMs: timestampsMs,
            speed: speed,
            latitude: latitude,
            longitude: longitude,
            heartRate: heartRate,
            cadence: cadence,
            power: power,
            distance: distance
        )
    }

    /// Returns the absolute start time of the FIT recording (Unix epoch seconds).
    ///
    /// Uses the first valid record timestamp.
    public static func absoluteStartTime(from messages: FitMessages) -> Date? {
        for record in messages.recordMesgs {
            if let dt = record.getTimestamp() {
                return dt.date
            }
        }
        return nil
    }
}

// MARK: - Errors

/// FIT adapter errors.
public enum FITAdapterError: Error, Sendable {
    case fileNotReadable(URL)
}
