//
// SessionDocument.swift
// RowData Studio
//
// Central session container: metadata, sources, timeline, sync state, canvas.
// The fundamental work unit. Persisted as JSON.
//
// Version: 1.1.0 (2026-03-14)
// Revision History:
//   2026-03-14: Add cueMarkers with backward-compat custom decoder (Phase 8c.5).
//   2026-03-01: Initial implementation (Phase 1: Data Models)
//
// Source: docs/architecture/data-models.md §SessionDocument
//
// CRITICAL: Source files (MP4, FIT, CSV) are NEVER modified.
// All edits (trim, sync, annotations) are virtual references.
// Physical changes occur only in explicit export/triage phase.
//

import Foundation
import CSVSwiftSDK

// MARK: - Supporting Types

/// Athlete metadata.
public struct Athlete: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var name: String
    public var seat: String?  // e.g., "Stroke", "7", "Bow"
    public var side: String?  // e.g., "Port", "Starboard" (for sweep)

    public init(
        id: UUID = UUID(),
        name: String,
        seat: String? = nil,
        side: String? = nil
    ) {
        self.id = id
        self.name = name
        self.seat = seat
        self.side = side
    }
}

/// Session metadata.
public struct SessionMetadata: Codable, Sendable, Hashable {
    public var id: UUID
    public var title: String
    public var date: Date
    public var athletes: [Athlete]
    public var notes: String

    public init(
        id: UUID = UUID(),
        title: String,
        date: Date = Date(),
        athletes: [Athlete] = [],
        notes: String = ""
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.athletes = athletes
        self.notes = notes
    }
}

/// Timeline configuration.
public struct Timeline: Codable, Sendable, Hashable {
    /// Total duration of the session (seconds)
    public var duration: TimeInterval

    /// Absolute UTC origin (GPS back-computation), if available
    ///
    /// Computed from GPS timestamps. Accuracy: ±1-5 seconds.
    /// Used for multi-camera sync and real-world timestamp correlation.
    public var absoluteOrigin: Date?

    /// Optional trim range (subset of duration for focused analysis)
    public var trimRange: ClosedRange<TimeInterval>?

    /// Timeline tracks (video, audio, sensor streams)
    public var tracks: [TimelineTrack]

    public init(
        duration: TimeInterval,
        absoluteOrigin: Date? = nil,
        trimRange: ClosedRange<TimeInterval>? = nil,
        tracks: [TimelineTrack] = []
    ) {
        self.duration = duration
        self.absoluteOrigin = absoluteOrigin
        self.trimRange = trimRange
        self.tracks = tracks
    }
}

/// Manual sync adjustment (user override).
public struct ManualAdjustment: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let sourceID: UUID
    public var offset: TimeInterval
    public var reason: String?
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        sourceID: UUID,
        offset: TimeInterval,
        reason: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.sourceID = sourceID
        self.offset = offset
        self.reason = reason
        self.timestamp = timestamp
    }
}

/// Synchronization state for all sources.
public struct SyncState: Codable, Sendable, Hashable {
    /// Result of internal GPMF sync (ACCL-GPS alignment)
    public var gpmfToVideo: SyncResult?

    /// Results for each FIT file sync to video timeline
    public var fitToVideo: [UUID: SyncResult]  // sourceID -> SyncResult

    /// Manual user adjustments
    public var manualAdjustments: [ManualAdjustment]

    public init(
        gpmfToVideo: SyncResult? = nil,
        fitToVideo: [UUID: SyncResult] = [:],
        manualAdjustments: [ManualAdjustment] = []
    ) {
        self.gpmfToVideo = gpmfToVideo
        self.fitToVideo = fitToVideo
        self.manualAdjustments = manualAdjustments
    }
}

// MARK: - SessionDocument

/// Session document: the fundamental work unit.
///
/// Contains all metadata, source references, timeline configuration, sync state,
/// and canvas layout for a single rowing session. Persisted as JSON.
///
/// **Non-destructive editing**: Source files are never modified. All operations
/// (trim, sync, annotations) are virtual references stored in this document.
public struct SessionDocument: Codable, Sendable {
    /// Session metadata (id, title, date, athletes, notes)
    public var metadata: SessionMetadata

    /// Data sources (videos, sidecars, FIT files, CSV files)
    public var sources: [DataSource]

    /// Timeline configuration
    public var timeline: Timeline

    /// Regions of interest
    public var regions: [ROI]

    /// Canvas state (widget positions & layouts)
    public var canvas: CanvasState

    /// NK Empower session data (optional, from CSV SDK)
    ///
    /// Contains per-stroke biomechanical metrics (force, angle, work).
    /// Loaded from NK LiNK Logbook CSV export.
    public var empowerData: NKEmpowerSession?

    /// Empower sync offset (GPS-based alignment with video)
    public var empowerSyncOffset: TimeInterval?

    /// Synchronization state
    public var syncState: SyncState

    /// Cue/bookmark markers on the timeline (user-created via M shortcut or + button).
    public var cueMarkers: [CueMarker]

    /// Document version (for future migration)
    public var version: Int

    /// Last modified timestamp
    public var modifiedAt: Date

    public init(
        metadata: SessionMetadata,
        sources: [DataSource] = [],
        timeline: Timeline,
        regions: [ROI] = [],
        canvas: CanvasState = CanvasState(),
        empowerData: NKEmpowerSession? = nil,
        empowerSyncOffset: TimeInterval? = nil,
        syncState: SyncState = SyncState(),
        cueMarkers: [CueMarker] = [],
        version: Int = 1,
        modifiedAt: Date = Date()
    ) {
        self.metadata = metadata
        self.sources = sources
        self.timeline = timeline
        self.regions = regions
        self.canvas = canvas
        self.empowerData = empowerData
        self.empowerSyncOffset = empowerSyncOffset
        self.syncState = syncState
        self.cueMarkers = cueMarkers
        self.version = version
        self.modifiedAt = modifiedAt
    }

    // Custom decoder: cueMarkers uses decodeIfPresent for backward compatibility
    // with documents saved before Phase 8c.5 (key absent → empty array).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        metadata          = try c.decode(SessionMetadata.self,        forKey: .metadata)
        sources           = try c.decode([DataSource].self,           forKey: .sources)
        timeline          = try c.decode(Timeline.self,               forKey: .timeline)
        regions           = try c.decode([ROI].self,                  forKey: .regions)
        canvas            = try c.decode(CanvasState.self,            forKey: .canvas)
        empowerData       = try c.decodeIfPresent(NKEmpowerSession.self,  forKey: .empowerData)
        empowerSyncOffset = try c.decodeIfPresent(TimeInterval.self,      forKey: .empowerSyncOffset)
        syncState         = try c.decode(SyncState.self,              forKey: .syncState)
        cueMarkers        = try c.decodeIfPresent([CueMarker].self,   forKey: .cueMarkers) ?? []
        version           = try c.decode(Int.self,                    forKey: .version)
        modifiedAt        = try c.decode(Date.self,                   forKey: .modifiedAt)
    }
}

// MARK: - Convenience Accessors

extension SessionDocument {
    /// Primary GoPro video source, if any
    public var primaryVideo: DataSource? {
        sources.first { source in
            if case .goProVideo(_, _, let role) = source, role == .primary {
                return true
            }
            return false
        }
    }

    /// All FIT file sources
    public var fitSources: [DataSource] {
        sources.filter { source in
            if case .fitFile = source { return true }
            return false
        }
    }

    /// All CSV file sources
    public var csvSources: [DataSource] {
        sources.filter { source in
            if case .csvFile = source { return true }
            return false
        }
    }

    /// Find source by ID
    public func source(withID id: UUID) -> DataSource? {
        sources.first { $0.id == id }
    }
}
