// Rendering/Widgets/WidgetProtocol.swift v1.2.0
/**
 * Protocol and type extensions for analysis widgets.
 *
 * - AnalysisWidget: base protocol for all canvas widgets
 * - WidgetType: enum-based type classification (display name, icon)
 * - WidgetState extensions: type-safe access via WidgetType
 *
 * WidgetState (position, size, config) is defined in Core/Models/CanvasState.swift.
 * This file adds the Phase 6 rendering layer on top.
 *
 * --- Revision History ---
 * v1.2.0 - 2026-03-14 - Add WidgetType.audio (Phase 8c.7: AudioTrackWidget).
 * v1.1.0 - 2026-03-08 - Remove WidgetConfig (duplicate of WidgetState); add WidgetType + WidgetState extension.
 * v1.0.0 - 2026-03-08 - Initial scaffolding (Phase 6: Canvas & Widgets).
 */

import SwiftUI

// MARK: - WidgetType

/// Typed classification of canvas widgets.
///
/// The raw value maps to `WidgetState.widgetType` string for persistence.
public enum WidgetType: String, Codable, Sendable, Hashable, CaseIterable {
    case lineChart       = "lineChart"
    case multiLineChart  = "multiLineChart"
    case strokeTable     = "strokeTable"
    case metricCard      = "metricCard"
    case map             = "map"
    case empowerRadar    = "empowerRadar"
    case video           = "video"
    case audio           = "audio"

    public var displayName: String {
        switch self {
        case .lineChart:       return "Line Chart"
        case .multiLineChart:  return "Multi-Line Chart"
        case .strokeTable:     return "Stroke Table"
        case .metricCard:      return "Metric Card"
        case .map:             return "GPS Track"
        case .empowerRadar:    return "Empower Radar"
        case .video:           return "Video Player"
        case .audio:           return "Audio Track"
        }
    }

    public var icon: String {
        switch self {
        case .lineChart:       return "chart.line.uptrend.xyaxis"
        case .multiLineChart:  return "chart.line.uptrend.xyaxis"
        case .strokeTable:     return "tablecells"
        case .metricCard:      return "rectangle.inset.filled"
        case .map:             return "map"
        case .empowerRadar:    return "dot.radiowaves.left.and.right"
        case .video:           return "video.fill"
        case .audio:           return "waveform"
        }
    }

    /// Default canvas size for this widget type.
    public var defaultSize: CGSize {
        switch self {
        case .lineChart, .multiLineChart:  return CGSize(width: 480, height: 280)
        case .strokeTable:                 return CGSize(width: 420, height: 360)
        case .metricCard:                  return CGSize(width: 200, height: 120)
        case .map:                         return CGSize(width: 400, height: 400)
        case .empowerRadar:                return CGSize(width: 320, height: 320)
        case .video:                       return CGSize(width: 560, height: 360)
        case .audio:                       return CGSize(width: 480, height: 100)
        }
    }
}

// MARK: - WidgetState Extension

extension WidgetState {
    /// Typed widget type (parsed from `widgetType` string).
    /// Returns `nil` if the string doesn't match a known type.
    public var type: WidgetType? {
        WidgetType(rawValue: widgetType)
    }

    /// Convenience: metric IDs from configuration.
    public var metricIDs: [String] {
        guard let arr = configuration["metricIDs"]?.value as? [Any] else { return [] }
        return arr.compactMap { $0 as? String }
    }

    /// Convenience: widget title from configuration (fallbacks to type display name).
    public var title: String {
        (configuration["title"]?.value as? String) ?? (type?.displayName ?? widgetType)
    }

    /// Convenience: visibility toggle from configuration.
    public var isVisible: Bool {
        (configuration["isVisible"]?.value as? Bool) ?? true
    }

    /// Widget tier. Primary = full-size, Secondary = compact.
    public var isPrimaryTier: Bool {
        (configuration["isPrimaryTier"]?.value as? Bool) ?? true
    }

    /// Creates a WidgetState for a given type at a canvas position.
    public static func make(
        type: WidgetType,
        position: CGPoint,
        metricIDs: [String] = [],
        title: String? = nil
    ) -> WidgetState {
        WidgetState(
            widgetType: type.rawValue,
            position: position,
            size: type.defaultSize,
            configuration: [
                "title": AnyCodable(title ?? type.displayName),
                "metricIDs": AnyCodable(metricIDs),
                "isVisible": AnyCodable(true)
            ]
        )
    }
}

// MARK: - AnalysisWidget Protocol

/// Base protocol for all analysis widget SwiftUI views.
///
/// Conforming types receive data from `DataContext` and react to `PlayheadController`.
/// Widget layout (position, size) is stored in `WidgetState` within `SessionDocument.canvas`.
public protocol AnalysisWidget: View {
    /// Widget configuration (position, size, type, metric IDs)
    var state: WidgetState { get }

    /// Shared data source
    var dataContext: DataContext { get }

    /// Timeline playhead
    var playheadController: PlayheadController { get }
}
