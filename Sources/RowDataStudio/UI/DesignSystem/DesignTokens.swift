// UI/DesignSystem/DesignTokens.swift v1.1.0
/**
 * RowData Studio Design System tokens.
 * Source of truth per tutti i valori visual.
 *
 * --- Revision History ---
 * v1.1.0 - 2026-03-14 - Add StreamType.symbolName for timeline track icons (Phase 8c.3).
 * v1.0.0 - 2026-03-11 - Initial implementation (Phase 8a.1).
 */

import SwiftUI

public enum RDS {
    
    // MARK: - Colors
    
    public enum Colors {
        /// Canvas background. Pure black per XDR.
        public static let canvasBackground = Color(red: 0, green: 0, blue: 0) // #000000
        
        /// Widget surface. Near-opaque dark.
        public static let widgetSurface = Color(red: 0.051, green: 0.051, blue: 0.051) // #0D0D0D
        public static let widgetSurfaceGradientTop = Color(red: 0.039, green: 0.039, blue: 0.039) // #0A0A0A
        public static let widgetSurfaceGradientBottom = Color(red: 0.078, green: 0.078, blue: 0.078) // #141414
        
        /// Elevated surface (widget surface with slight lift)
        public static let elevatedSurface = Color(red: 0.173, green: 0.173, blue: 0.180) // #2C2C2E
        
        /// Text
        public static let textPrimary = Color.white    // #FFFFFF
        public static let textSecondary = Color(red: 0.557, green: 0.557, blue: 0.576) // #8E8E93
        
        /// Accent — Vibrant Orange/Amber.
        public static let accent = Color(red: 1.0, green: 0.624, blue: 0.039) // #FF9F0A
        
        /// Widget border glow (resting state)
        public static let widgetBorderGlow = Color(red: 1.0, green: 0.624, blue: 0.039).opacity(0.12)
        
        /// Widget border glow (selected state)
        public static let widgetBorderSelected = Color(red: 1.0, green: 0.624, blue: 0.039).opacity(0.5)
    }
    
    // MARK: - Semantic Metric Colors
    
    public enum MetricColors {
        public static let speed    = Color(red: 0.039, green: 0.518, blue: 1.0)   // #0A84FF
        public static let heartRate = Color(red: 1.0, green: 0.271, blue: 0.227)  // #FF453A
        public static let strokeRate = Color(red: 0.749, green: 0.353, blue: 0.949) // #BF5AF2
        public static let power    = Color(red: 0.188, green: 0.820, blue: 0.345) // #30D158
        public static let gps      = Color(red: 0.392, green: 0.824, blue: 1.0)   // #64D2FF
        public static let imu      = Color(red: 1.0, green: 0.839, blue: 0.039)   // #FFD60A
    }
    
    // MARK: - Typography
    
    public enum Typography {
        public static let dataValue = Font.system(.body, design: .monospaced)
        public static let dataValueSmall = Font.system(.caption, design: .monospaced)
        public static let dataValueLarge = Font.system(.title2, design: .monospaced)
        public static let uiHeader = Font.system(.headline, design: .default)
        public static let uiLabel = Font.system(.subheadline, design: .default)
        public static let widgetTitle = Font.system(.caption, design: .default).weight(.semibold)
        public static let timelineRuler = Font.system(.caption2, design: .monospaced)
    }
    
    // MARK: - Spring Animations
    
    public enum Springs {
        public static let widgetDrag = Animation.spring(response: 0.35, dampingFraction: 0.80)
        public static let panelShowHide = Animation.spring(response: 0.40, dampingFraction: 0.90)
        public static let focusModeZoom = Animation.spring(response: 0.50, dampingFraction: 0.85)
        public static let snapToGrid = Animation.spring(response: 0.25, dampingFraction: 0.75)
        public static let valuePulse = Animation.spring(response: 0.15, dampingFraction: 1.00)
    }
    
    // MARK: - Layout
    
    public enum Layout {
        public static let widgetCornerRadius: CGFloat = 8
        public static let widgetBorderWidth: CGFloat = 0.5
        public static let snapThreshold: CGFloat = 8
        public static let resizeHitZone: CGFloat = 5
        public static let minWidgetWidth: CGFloat = 200
        public static let minWidgetHeight: CGFloat = 150
        public static let canvasZoomMin: Double = 0.25
        public static let canvasZoomMax: Double = 4.0
        public static let focusDimOpacity: Double = 0.30
    }
}

extension StreamType {
    public var semanticColor: Color {
        switch self {
        case .speed:                   return RDS.MetricColors.speed
        case .hr:                      return RDS.MetricColors.heartRate
        case .cadence:                 return RDS.MetricColors.strokeRate
        case .power, .force, .work:    return RDS.MetricColors.power
        case .gps:                     return RDS.MetricColors.gps
        case .accl, .gyro, .grav, .cori: return RDS.MetricColors.imu
        case .video:                   return RDS.Colors.accent
        case .audio:                   return .white
        case .angle:                   return RDS.MetricColors.power
        case .temperature:             return RDS.MetricColors.imu
        case .fusedVelocity:           return RDS.MetricColors.speed
        case .fusedPitch, .fusedRoll:  return RDS.MetricColors.imu
        }
    }

    /// SF Symbol name for timeline track header icon.
    public var symbolName: String {
        switch self {
        case .video:                    return "video.fill"
        case .audio:                    return "waveform"
        case .gps:                      return "location.fill"
        case .accl:                     return "move.3d"
        case .gyro:                     return "rotate.3d"
        case .grav, .cori:              return "gyroscope"
        case .speed, .fusedVelocity:    return "speedometer"
        case .hr:                       return "heart.fill"
        case .cadence:                  return "metronome.fill"
        case .power:                    return "bolt.fill"
        case .temperature:              return "thermometer.medium"
        case .force:                    return "arrow.up.right"
        case .angle:                    return "angle"
        case .work:                     return "chart.bar.fill"
        case .fusedPitch:               return "arrow.up.and.down.circle"
        case .fusedRoll:                return "arrow.left.and.right.circle"
        }
    }
}
