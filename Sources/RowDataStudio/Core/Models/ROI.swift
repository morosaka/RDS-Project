//
// ROI.swift
// RowData Studio
//
// Region of Interest: time range marker on the session timeline.
// Used for analysis focus, comparison, and export.
//
// Version: 1.0.0 (2026-03-01)
// Revision History:
//   2026-03-01: Initial implementation (Phase 1: Data Models)
//
// Source: docs/architecture/data-models.md §SessionDocument.regions
//

import Foundation

/// Region of Interest (ROI) on the session timeline.
///
/// Represents a marked time range for focused analysis, comparison, or export.
/// Examples: "Sprint 1000m", "Steady state", "Technical error", "Race piece".
public struct ROI: Codable, Sendable, Hashable, Identifiable {
    /// Unique identifier
    public let id: UUID

    /// Display name
    public var name: String

    /// Time range (in seconds, relative to session timeline zero)
    public var range: ClosedRange<TimeInterval>

    /// Optional tags for categorization (e.g., "drill", "issue", "pace", "race")
    public var tags: [String]

    /// Optional color for visual distinction (hex string, e.g., "#FF5733")
    public var color: String?

    /// Optional notes
    public var notes: String?

    public init(
        id: UUID = UUID(),
        name: String,
        range: ClosedRange<TimeInterval>,
        tags: [String] = [],
        color: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.range = range
        self.tags = tags
        self.color = color
        self.notes = notes
    }
}

// Note: ClosedRange is already Codable in Swift standard library.
