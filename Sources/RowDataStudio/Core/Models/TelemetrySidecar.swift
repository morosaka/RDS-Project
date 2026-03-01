//
// TelemetrySidecar.swift
// RowData Studio
//
// Compact telemetry sidecar: extracted GPMF data cache for trimmed video.
// Replaces need to re-parse MP4 on every session load.
//
// Version: 1.0.0 (2026-03-01)
// Revision History:
//   2026-03-01: Initial implementation (Phase 1: Data Models)
//
// Source: docs/architecture/data-models.md §TelemetrySidecar
//
// CRITICAL: This file is atomically linked to its source video.
// Naming: GX030230_trim_120s_385s.telemetry (matches video filename)
// Always create, move, and delete sidecar + video together.
//

import Foundation
import GPMFSwiftSDK

/// Telemetry sidecar: cached GPMF extraction for trimmed video.
///
/// Format: Codable -> gzipped JSON or MessagePack
/// Size: ~2-3 MB for 5-minute trim (1% of video size)
///
/// This sidecar is generated during video triage/trim operations.
/// It eliminates the need to re-parse the MP4 GPMF track on every session load.
public struct TelemetrySidecar: Codable, Sendable {
    /// Sidecar format version (for future migration)
    public let version: Int

    /// SHA256 hash of original source MP4 file
    public let sourceFileHash: String

    /// Original MP4 filename (e.g., "GX030230.MP4")
    public let sourceFileName: String

    // MARK: - Timing

    /// Duration of original untrimmed video (seconds)
    public let originalDuration: TimeInterval

    /// Time range extracted from original video (in original timeline)
    public let trimRange: ClosedRange<TimeInterval>

    /// Absolute UTC origin (GPS back-computation), if available
    ///
    /// Computed from GPS timestamps. May be nil if GPS unavailable.
    /// Accuracy: ±1-5 seconds (sufficient for rowing multi-camera sync).
    public let absoluteOrigin: Date?

    // MARK: - Device Metadata

    /// GoPro device name (e.g., "HERO10 Black")
    public let deviceName: String?

    /// GoPro device ID
    public let deviceID: UInt32?

    /// Camera orientation (e.g., "ZXY")
    public let orin: String?

    // MARK: - GPS Timestamps (for sync diagnostics)

    /// First GPS timestamp observation
    public let firstGPSU: GPSTimestampObservation?

    /// Last GPS timestamp observation
    public let lastGPSU: GPSTimestampObservation?

    /// First GPS9 timestamp (if available)
    public let firstGPS9Time: GPS9Timestamp?

    /// Last GPS9 timestamp (if available)
    public let lastGPS9Time: GPS9Timestamp?

    /// MP4 creation time from file metadata
    public let mp4CreationTime: Date?

    // MARK: - Stream Info

    /// Stream metadata (e.g., ACCL: 200Hz, GPS: 18Hz)
    /// Stored as JSON-compatible dictionary for now
    public let streamInfo: [String: String]

    // MARK: - Sensor Data (timestamps re-based to 0.0 = trim start)
    // NOTE: Sensor data storage will be implemented in Phase 5 (Session Management)
    // when SidecarGenerator is created. For Phase 1, we define only the metadata structure.

    public init(
        version: Int = 1,
        sourceFileHash: String,
        sourceFileName: String,
        originalDuration: TimeInterval,
        trimRange: ClosedRange<TimeInterval>,
        absoluteOrigin: Date? = nil,
        deviceName: String? = nil,
        deviceID: UInt32? = nil,
        orin: String? = nil,
        firstGPSU: GPSTimestampObservation? = nil,
        lastGPSU: GPSTimestampObservation? = nil,
        firstGPS9Time: GPS9Timestamp? = nil,
        lastGPS9Time: GPS9Timestamp? = nil,
        mp4CreationTime: Date? = nil,
        streamInfo: [String: String] = [:]
    ) {
        self.version = version
        self.sourceFileHash = sourceFileHash
        self.sourceFileName = sourceFileName
        self.originalDuration = originalDuration
        self.trimRange = trimRange
        self.absoluteOrigin = absoluteOrigin
        self.deviceName = deviceName
        self.deviceID = deviceID
        self.orin = orin
        self.firstGPSU = firstGPSU
        self.lastGPSU = lastGPSU
        self.firstGPS9Time = firstGPS9Time
        self.lastGPS9Time = lastGPS9Time
        self.mp4CreationTime = mp4CreationTime
        self.streamInfo = streamInfo
    }
}
