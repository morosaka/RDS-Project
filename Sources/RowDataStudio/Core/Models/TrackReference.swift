//
// TrackReference.swift
// RowData Studio
//
// Timeline track reference with sync offset.
// Links a data stream from a DataSource to the session timeline.
//
// Version: 1.0.0 (2026-03-01)
// Revision History:
//   2026-03-01: Initial implementation (Phase 1: Data Models)
//
// Source: docs/architecture/data-models.md §SessionDocument.timeline.tracks
//

import Foundation

/// Stream type identifier for timeline tracks.
public enum StreamType: String, Codable, Sendable {
    // Video streams
    case video
    case audio

    // GPMF sensor streams
    case accl
    case gyro
    case grav
    case cori
    case gps

    // FIT streams
    case speed
    case hr
    case cadence
    case power
    case temperature

    // CSV streams (NK Empower)
    case force
    case angle
    case work

    // Fused/derived streams
    case fusedVelocity
    case fusedPitch
    case fusedRoll
}

/// Timeline track reference.
///
/// Represents a data stream from a specific DataSource, positioned on the session timeline
/// with a sync offset. Multiple tracks can reference the same source (e.g., video + audio).
public struct TrackReference: Codable, Sendable, Hashable {
    /// Unique track identifier
    public let id: UUID

    /// ID of the source DataSource
    public let sourceID: UUID

    /// Stream type
    public let stream: StreamType

    /// Sync offset in seconds (relative to timeline zero)
    ///
    /// Positive offset: stream starts after timeline zero
    /// Negative offset: stream starts before timeline zero
    public let offset: TimeInterval

    /// Optional display name override
    public let displayName: String?

    public init(
        id: UUID = UUID(),
        sourceID: UUID,
        stream: StreamType,
        offset: TimeInterval = 0.0,
        displayName: String? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        self.stream = stream
        self.offset = offset
        self.displayName = displayName
    }
}
