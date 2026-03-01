//
// DataSource.swift
// RowData Studio
//
// Data source types for SessionDocument: video, telemetry sidecar, FIT, CSV.
// Each source has type-specific metadata and URL reference.
//
// Version: 1.0.0 (2026-03-01)
// Revision History:
//   2026-03-01: Initial implementation (Phase 1: Data Models)
//
// Source: docs/architecture/data-models.md §SessionDocument
//

import Foundation

/// Video role in multi-camera sessions.
public enum VideoRole: String, Codable, Sendable {
    case primary
    case secondary
    case tertiary
}

/// Data source type with associated metadata.
///
/// Represents a file that contributes data to the session (video, telemetry, FIT, CSV).
/// All file URLs are persistent bookmarks to handle sandboxing on macOS.
public enum DataSource: Codable, Sendable, Hashable {
    /// GoPro video file (MP4/LRV)
    case goProVideo(id: UUID, url: URL, role: VideoRole)

    /// Telemetry sidecar (extracted GPMF cache)
    case sidecar(id: UUID, url: URL, linkedTo: UUID)

    /// FIT file (Garmin, NK SpeedCoach, Apple Watch export)
    case fitFile(id: UUID, url: URL, device: String?)

    /// CSV file (NK Empower, NK SpeedCoach, CrewNerd)
    case csvFile(id: UUID, url: URL, device: String?)

    public var id: UUID {
        switch self {
        case .goProVideo(let id, _, _): return id
        case .sidecar(let id, _, _): return id
        case .fitFile(let id, _, _): return id
        case .csvFile(let id, _, _): return id
        }
    }

    public var url: URL {
        switch self {
        case .goProVideo(_, let url, _): return url
        case .sidecar(_, let url, _): return url
        case .fitFile(_, let url, _): return url
        case .csvFile(_, let url, _): return url
        }
    }

    public var typeName: String {
        switch self {
        case .goProVideo: return "GoPro Video"
        case .sidecar: return "Telemetry Sidecar"
        case .fitFile: return "FIT File"
        case .csvFile: return "CSV File"
        }
    }
}
