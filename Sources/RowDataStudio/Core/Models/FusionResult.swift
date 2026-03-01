//
// FusionResult.swift
// RowData Studio
//
// Fusion engine output container: strokes, per-stroke stats, diagnostics.
// Complete result of the 6-step fusion pipeline.
//
// Version: 1.0.0 (2026-03-01)
// Revision History:
//   2026-03-01: Initial implementation (Phase 1: Data Models)
//
// Source: docs/specs/fusion-engine.md
//

import Foundation

/// Fusion engine output.
///
/// Contains all results from the fusion pipeline:
/// - Detected stroke events
/// - Per-stroke aggregated statistics
/// - Diagnostic metrics
/// - Processing metadata
public struct FusionResult: Codable, Sendable, Hashable {
    /// Detected stroke events (ordered by time)
    public let strokes: [StrokeEvent]

    /// Per-stroke aggregated statistics (ordered by strokeIndex)
    public let perStrokeStats: [PerStrokeStat]

    /// Diagnostic metrics
    public let diagnostics: FusionDiagnostics

    /// Processing timestamp
    public let timestamp: Date

    /// Duration of fusion processing (seconds)
    public let processingDuration: TimeInterval

    /// Version of fusion algorithm used
    public let algorithmVersion: String

    public init(
        strokes: [StrokeEvent],
        perStrokeStats: [PerStrokeStat],
        diagnostics: FusionDiagnostics,
        timestamp: Date = Date(),
        processingDuration: TimeInterval = 0.0,
        algorithmVersion: String = "1.0.0"
    ) {
        self.strokes = strokes
        self.perStrokeStats = perStrokeStats
        self.diagnostics = diagnostics
        self.timestamp = timestamp
        self.processingDuration = processingDuration
        self.algorithmVersion = algorithmVersion
    }
}
