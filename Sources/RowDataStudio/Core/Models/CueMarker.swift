// Core/Models/CueMarker.swift v1.0.0
/**
 * Cue/bookmark marker on the session timeline.
 * Positioned by timeMs, carries a user-editable label and optional color override.
 *
 * CueMarkers are stored in SessionDocument.cueMarkers and rendered by CueTrackView.
 * The shortcut M creates a cue at the current playhead position.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-14 - Initial implementation (Phase 8c.5).
 */

import Foundation

/// A named bookmark on the session timeline.
public struct CueMarker: Codable, Sendable, Hashable, Identifiable {

    /// Unique identifier.
    public let id: UUID

    /// Position on the timeline in milliseconds from session zero.
    public var timeMs: Double

    /// User-editable display label.
    public var label: String

    /// Optional hex color override (e.g. `"#FF9F0A"`).
    /// If nil, the view uses `RDS.Colors.accent`.
    public var color: String?

    /// Creation timestamp (for ordering markers with identical timeMs).
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        timeMs: Double,
        label: String,
        color: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.timeMs = timeMs
        self.label = label
        self.color = color
        self.createdAt = createdAt
    }
}
