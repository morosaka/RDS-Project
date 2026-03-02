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
//   2026-03-02: Replace GPMF SDK types with Codable-compatible representations
//
// Source: docs/architecture/data-models.md §TelemetrySidecar
//
// CRITICAL: This file is atomically linked to its source video.
// Naming: GX030230_trim_120s_385s.telemetry (matches video filename)
// Always create, move, and delete sidecar + video together.
//

import Foundation

// MARK: - Codable GPS Timestamp Types

/// Codable representation of a GPSU timestamp observation.
///
/// Mirrors GPMFSwiftSDK.GPSTimestampObservation but with Codable conformance.
/// Conversion from SDK types will be done in GPMFAdapter (Phase 3).
public struct GPSTimestampRecord: Codable, Sendable, Hashable {
    /// The GPSU string value in "yymmddhhmmss.sss" format
    public let value: String
    /// Relative time within the file when this GPSU was observed (seconds from file start)
    public let relativeTime: TimeInterval
    /// Parsed UTC date, if successfully parsed
    public let parsedDate: Date?

    public init(value: String, relativeTime: TimeInterval, parsedDate: Date? = nil) {
        self.value = value
        self.relativeTime = relativeTime
        self.parsedDate = parsedDate
    }
}

/// Codable representation of a GPS9 timestamp.
///
/// Mirrors GPMFSwiftSDK.GPS9Timestamp but with Codable conformance.
public struct GPS9TimestampRecord: Codable, Sendable, Hashable {
    /// Days elapsed since January 1, 2000
    public let daysSince2000: UInt32
    /// Seconds since midnight UTC, with millisecond precision
    public let secondsSinceMidnight: Double

    public init(daysSince2000: UInt32, secondsSinceMidnight: Double) {
        self.daysSince2000 = daysSince2000
        self.secondsSinceMidnight = secondsSinceMidnight
    }
}

// MARK: - TelemetrySidecar

/// Telemetry sidecar: cached GPMF extraction for trimmed video.
///
/// Format: Codable -> gzipped JSON or MessagePack
/// Size: ~2-3 MB for 5-minute trim (1% of video size)
///
/// This sidecar is generated during video triage/trim operations.
/// It eliminates the need to re-parse the MP4 GPMF track on every session load.
public struct TelemetrySidecar: Codable, Sendable, Hashable {
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
    public let firstGPSU: GPSTimestampRecord?

    /// Last GPS timestamp observation (higher accuracy per GPMF timing model)
    public let lastGPSU: GPSTimestampRecord?

    /// First GPS9 timestamp (if available)
    public let firstGPS9Time: GPS9TimestampRecord?

    /// Last GPS9 timestamp (if available)
    public let lastGPS9Time: GPS9TimestampRecord?

    /// MP4 creation time from file metadata
    public let mp4CreationTime: Date?

    // MARK: - Stream Info

    /// Stream metadata (e.g., "ACCL": "200Hz", "GPS5": "18Hz")
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
        firstGPSU: GPSTimestampRecord? = nil,
        lastGPSU: GPSTimestampRecord? = nil,
        firstGPS9Time: GPS9TimestampRecord? = nil,
        lastGPS9Time: GPS9TimestampRecord? = nil,
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
