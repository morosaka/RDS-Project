//
// CanvasState.swift
// RowData Studio
//
// Infinite canvas state: widget positions, sizes, and saved layouts.
// Persisted in SessionDocument for workspace restoration.
//
// Version: 1.0.0 (2026-03-01)
// Revision History:
//   2026-03-01: Initial implementation (Phase 1: Data Models)
//
// Source: docs/architecture/data-models.md §SessionDocument.canvas
//         docs/architecture/visualization.md
//

import Foundation
import CoreGraphics

/// Widget position and configuration.
public struct WidgetState: Codable, Sendable, Hashable, Identifiable {
    /// Unique widget instance identifier
    public let id: UUID

    /// Widget type identifier (e.g., "lineChart", "strokeTable", "map")
    public let widgetType: String

    /// Position on infinite canvas (x, y in points)
    public var position: CGPoint

    /// Size (width, height in points)
    public var size: CGSize

    /// Z-index for stacking order
    public var zIndex: Int

    /// Widget-specific configuration (JSON-compatible)
    ///
    /// Examples:
    /// - LineChart: `["metricID": "fus_cal_ts_vel_inertial", "color": "#FF5733"]`
    /// - StrokeTable: `["columns": ["strokeRate", "avgVelocity", "avgHR"]]`
    public var configuration: [String: AnyCodable]

    public init(
        id: UUID = UUID(),
        widgetType: String,
        position: CGPoint,
        size: CGSize,
        zIndex: Int = 0,
        configuration: [String: AnyCodable] = [:]
    ) {
        self.id = id
        self.widgetType = widgetType
        self.position = position
        self.size = size
        self.zIndex = zIndex
        self.configuration = configuration
    }
}

/// Saved canvas layout.
public struct SavedLayout: Codable, Sendable, Hashable, Identifiable {
    /// Unique layout identifier
    public let id: UUID

    /// Layout name (e.g., "Stroke Analysis", "Biomechanics", "Multi-Camera")
    public var name: String

    /// Widget configurations for this layout
    public var widgets: [WidgetState]

    /// Creation timestamp
    public let createdAt: Date

    /// Last modified timestamp
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        widgets: [WidgetState],
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.widgets = widgets
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

/// Canvas state: current widgets and saved layouts.
public struct CanvasState: Codable, Sendable, Hashable {
    /// Current active widgets on canvas
    public var widgets: [WidgetState]

    /// Saved layouts for quick recall
    public var layouts: [SavedLayout]

    /// Canvas zoom level (1.0 = 100%)
    public var zoomLevel: Double

    /// Canvas pan offset (x, y in points)
    public var panOffset: CGPoint

    public init(
        widgets: [WidgetState] = [],
        layouts: [SavedLayout] = [],
        zoomLevel: Double = 1.0,
        panOffset: CGPoint = .zero
    ) {
        self.widgets = widgets
        self.layouts = layouts
        self.zoomLevel = zoomLevel
        self.panOffset = panOffset
    }
}

/// Type-erased Codable wrapper for widget configuration values.
///
/// **Thread safety**: @unchecked Sendable because we only store Sendable types
/// (Bool, Int, Double, String, Array, Dictionary) but the compiler can't verify this.
public struct AnyCodable: Codable, @unchecked Sendable, Hashable {
    public let value: Any

    public init<T>(_ value: T) where T: Codable {
        self.value = value
    }

    // Internal init for recursive array/dict construction
    private init(wrapping value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported type in AnyCodable"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable(wrapping: $0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable(wrapping: $0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Unsupported type in AnyCodable"
                )
            )
        }
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        // Simplified equality - only compares JSON representation
        guard let lhsData = try? JSONEncoder().encode(lhs),
              let rhsData = try? JSONEncoder().encode(rhs) else {
            return false
        }
        return lhsData == rhsData
    }

    public func hash(into hasher: inout Hasher) {
        // Simplified hashing - uses JSON representation
        if let data = try? JSONEncoder().encode(self) {
            hasher.combine(data)
        }
    }
}

// Note: CGPoint and CGSize are already Codable on macOS 10.9+
// No custom conformance needed.
