//
// StrokeEvent.swift
// RowData Studio
//
// Detected stroke event with timing, indices, and kinematic features.
// Output of stroke detection algorithm in fusion engine.
//
// Version: 1.0.0 (2026-03-01)
// Revision History:
//   2026-03-01: Initial implementation (Phase 1: Data Models)
//
// Source: docs/specs/fusion-engine.md §Stroke Detection
//

import Foundation

/// Detected rowing stroke event.
///
/// Represents a single stroke cycle (catch → finish → recovery → catch).
/// Contains timing boundaries, buffer indices, and basic kinematic features.
public struct StrokeEvent: Codable, Sendable, Hashable {
    /// Stroke index (sequential, 0-based)
    public let index: Int

    /// Start time (catch, in seconds relative to session timeline)
    public let startTime: TimeInterval

    /// End time (next catch, in seconds relative to session timeline)
    public let endTime: TimeInterval

    /// Start index in SensorDataBuffers
    public let startIndex: Int

    /// End index in SensorDataBuffers
    public let endIndex: Int

    /// Stroke duration in seconds
    public var duration: TimeInterval {
        endTime - startTime
    }

    /// Stroke rate in strokes per minute
    public var strokeRate: Double {
        guard duration > 0 else { return 0.0 }
        return 60.0 / duration
    }

    /// Peak velocity during drive phase (m/s), if available
    public let peakVelocity: Double?

    /// Minimum velocity during recovery phase (m/s), if available
    public let minVelocity: Double?

    /// Validity flag (false for partial strokes at session boundaries)
    public let isValid: Bool

    public init(
        index: Int,
        startTime: TimeInterval,
        endTime: TimeInterval,
        startIndex: Int,
        endIndex: Int,
        peakVelocity: Double? = nil,
        minVelocity: Double? = nil,
        isValid: Bool = true
    ) {
        self.index = index
        self.startTime = startTime
        self.endTime = endTime
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.peakVelocity = peakVelocity
        self.minVelocity = minVelocity
        self.isValid = isValid
    }
}
