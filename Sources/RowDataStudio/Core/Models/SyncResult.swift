//
// SyncResult.swift
// RowData Studio
//
// Synchronization result: offset, confidence, and diagnostic info.
// Output of SyncEngine strategies (SignMatch, GPS correlators, manual).
//
// Version: 1.0.0 (2026-03-01)
// Revision History:
//   2026-03-01: Initial implementation (Phase 1: Data Models)
//
// Source: docs/architecture/data-models.md §SessionDocument.syncState
//         docs/specs/sync-pipeline.md
//

import Foundation

/// Synchronization strategy identifier.
public enum SyncStrategy: String, Codable, Sendable {
    /// Step 1: ACCL-GPS signature matching (internal GPMF alignment)
    case signMatch
    /// Step 3A: GPS speed series cross-correlation
    case gpsSpeedCorrelator
    /// Step 3B: GPS track Haversine distance minimization
    case gpsTrackCorrelator
    /// Manual adjustment by user
    case manual
    /// No sync performed
    case none
}

/// Synchronization result.
///
/// Contains the computed offset, confidence level, and diagnostic metadata
/// from the sync pipeline. Used to align external data sources (FIT, CSV) to
/// the session timeline (anchored to GoPro video/telemetry).
public struct SyncResult: Codable, Sendable, Hashable {
    /// Sync offset in seconds
    ///
    /// Positive: external stream starts after timeline zero
    /// Negative: external stream starts before timeline zero
    public let offset: TimeInterval

    /// Confidence level (0.0 = no confidence, 1.0 = perfect match)
    public let confidence: Double

    /// Strategy used to compute the offset
    public let strategy: SyncStrategy

    /// Correlation score (for correlation-based strategies)
    public let correlationScore: Double?

    /// Search window range (in milliseconds) for diagnostic purposes
    public let searchWindowMs: Int?

    /// Timestamp when sync was computed
    public let timestamp: Date

    /// Optional human-readable diagnostic message
    public let diagnosticMessage: String?

    public init(
        offset: TimeInterval,
        confidence: Double,
        strategy: SyncStrategy,
        correlationScore: Double? = nil,
        searchWindowMs: Int? = nil,
        timestamp: Date = Date(),
        diagnosticMessage: String? = nil
    ) {
        self.offset = offset
        self.confidence = confidence
        self.strategy = strategy
        self.correlationScore = correlationScore
        self.searchWindowMs = searchWindowMs
        self.timestamp = timestamp
        self.diagnosticMessage = diagnosticMessage
    }
}
