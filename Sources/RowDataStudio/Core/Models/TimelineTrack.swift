//
// TimelineTrack.swift
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
public struct TimelineTrack: Codable, Sendable, Hashable, Identifiable {
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
    public var displayName: String?

    // === New: NLE behavior ===
    /// Widget that created this track. nil if manually pinned or orphaned.
    public var linkedWidgetID: UUID?

    /// Metric key for sparkline rendering (e.g. "fus_cal_ts_vel_inertial").
    public var metricID: String?

    /// Pinned tracks persist even when their linked widget is removed.
    public var isPinned: Bool

    /// Visibility toggle (hide sparkline without removing track).
    public var isVisible: Bool

    /// Audio mute state (only meaningful for .audio stream type).
    public var isMuted: Bool

    /// Audio solo state (only meaningful for .audio stream type).
    public var isSolo: Bool

    public init(
        id: UUID = UUID(),
        sourceID: UUID,
        stream: StreamType,
        offset: TimeInterval = 0.0,
        displayName: String? = nil,
        linkedWidgetID: UUID? = nil,
        metricID: String? = nil,
        isPinned: Bool = false,
        isVisible: Bool = true,
        isMuted: Bool = false,
        isSolo: Bool = false
    ) {
        self.id = id
        self.sourceID = sourceID
        self.stream = stream
        self.offset = offset
        self.displayName = displayName
        self.linkedWidgetID = linkedWidgetID
        self.metricID = metricID
        self.isPinned = isPinned
        self.isVisible = isVisible
        self.isMuted = isMuted
        self.isSolo = isSolo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceID = try container.decode(UUID.self, forKey: .sourceID)
        stream = try container.decode(StreamType.self, forKey: .stream)
        offset = try container.decode(TimeInterval.self, forKey: .offset)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        // New fields with defaults for backward compat
        linkedWidgetID = try container.decodeIfPresent(UUID.self, forKey: .linkedWidgetID)
        metricID = try container.decodeIfPresent(String.self, forKey: .metricID)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        isSolo = try container.decodeIfPresent(Bool.self, forKey: .isSolo) ?? false
    }
}
