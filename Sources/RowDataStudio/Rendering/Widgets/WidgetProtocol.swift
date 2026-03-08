// Rendering/Widgets/WidgetProtocol.swift v1.0.0
/**
 * Protocol for all analysis widgets in the infinite canvas.
 *
 * Defines required properties and data binding interface.
 * Each widget type (LineChart, StrokeTable, etc.) conforms to this protocol.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 6: Canvas & Widgets).
 */

import SwiftUI

/// Base protocol for all analysis widgets.
public protocol AnalysisWidget: View, Identifiable, Hashable {
    /// Unique widget identifier
    var id: UUID { get }

    /// User-facing widget title
    var title: String { get set }

    /// Widget type identifier (for persistence + UI)
    var type: WidgetType { get }

    /// Canvas position (top-left corner in 1-based coordinates)
    var position: CGPoint { get set }

    /// Canvas size (width, height in pixels)
    var size: CGSize { get set }

    /// Which metric(s) this widget displays
    var metricIDs: [String] { get set }

    /// Data context (shared sensor buffers, fusion results)
    var dataContext: DataContext { get }

    /// Playhead controller (current position in timeline)
    var playheadController: PlayheadController { get }

    /// Is widget currently selected (for editing)
    var isSelected: Bool { get set }

    /// Visibility toggle
    var isVisible: Bool { get set }
}

/// Widget type enumeration (for type-based routing and persistence).
public enum WidgetType: String, Codable, Sendable, Hashable {
    case lineChart
    case multiLineChart
    case strokeTable
    case metricCard
    case map
    case empowerRadar
    case video

    public var displayName: String {
        switch self {
        case .lineChart:
            return "Line Chart"
        case .multiLineChart:
            return "Multi-Line Chart"
        case .strokeTable:
            return "Stroke Table"
        case .metricCard:
            return "Metric Card"
        case .map:
            return "GPS Track"
        case .empowerRadar:
            return "Empower Radar"
        case .video:
            return "Video Player"
        }
    }

    public var icon: String {
        switch self {
        case .lineChart:
            return "chart.line"
        case .multiLineChart:
            return "chart.line.uptrend.xyaxis"
        case .strokeTable:
            return "tablecells"
        case .metricCard:
            return "rectanglerounded.inset.filled"
        case .map:
            return "map"
        case .empowerRadar:
            return "radar"
        case .video:
            return "video.fill"
        }
    }
}

/// Configuration state for a widget (persisted in SessionDocument.canvas).
public struct WidgetConfig: Codable, Sendable, Hashable {
    /// Widget type
    public let type: WidgetType

    /// Unique ID
    public let id: UUID

    /// Display title
    public var title: String

    /// Canvas position
    public var position: CGPoint

    /// Canvas size
    public var size: CGSize

    /// Which metrics to display
    public var metricIDs: [String]

    /// Visibility toggle
    public var isVisible: Bool

    public init(
        type: WidgetType,
        id: UUID = UUID(),
        title: String,
        position: CGPoint = CGPoint(x: 0, y: 0),
        size: CGSize = CGSize(width: 400, height: 300),
        metricIDs: [String] = [],
        isVisible: Bool = true
    ) {
        self.type = type
        self.id = id
        self.title = title
        self.position = position
        self.size = size
        self.metricIDs = metricIDs
        self.isVisible = isVisible
    }
}
