// UI/WidgetContainer.swift v2.0.0
/**
 * Draggable/resizable widget frame container.
 *
 * Wraps any analysis widget content and provides:
 * - Drag-to-move (updates WidgetState.position)
 * - Resize handles (invisible edges/corners)
 * - Selection highlight border (emissive glow)
 * - Hover-materialized header bar
 *
 * --- Revision History ---
 * v2.0.0 - 2026-03-11 - Spatial Glassmorphism Redesign (Phase 8a.3).
 * v1.1.0 - 2026-03-08 - Switch from WidgetConfig to WidgetState (real model).
 */

import SwiftUI
import AppKit

/// Container view for draggable/resizable widgets on the canvas.
public struct WidgetContainer: View {
    public let state: WidgetState
    public let content: AnyView
    public let isSelected: Bool
    public let onMove: (CGPoint) -> Void
    public let onResize: (CGSize) -> Void
    public let onDelete: () -> Void
    public let onToggleVisibility: () -> Void
    public let onSelect: () -> Void
    public let onTierToggle: () -> Void

    public init(
        state: WidgetState,
        content: AnyView,
        isSelected: Bool,
        onMove: @escaping (CGPoint) -> Void,
        onResize: @escaping (CGSize) -> Void,
        onDelete: @escaping () -> Void,
        onToggleVisibility: @escaping () -> Void,
        onSelect: @escaping () -> Void = {},
        onTierToggle: @escaping () -> Void = {}
    ) {
        self.state = state
        self.content = content
        self.isSelected = isSelected
        self.onMove = onMove
        self.onResize = onResize
        self.onDelete = onDelete
        self.onToggleVisibility = onToggleVisibility
        self.onSelect = onSelect
        self.onTierToggle = onTierToggle
    }

    @GestureState private var dragState = CGSize.zero
    @GestureState private var resizeState = CGSize.zero

    @State private var isHovered = false
    @State private var isHeaderVisible = false
    @State private var headerHideTask: Task<Void, Error>? = nil

    private var livePosition: CGPoint {
        CGPoint(
            x: state.position.x + dragState.width,
            y: state.position.y + dragState.height
        )
    }

    private var liveSize: CGSize {
        CGSize(
            width: max(RDS.Layout.minWidgetWidth, state.size.width + resizeState.width),
            height: max(RDS.Layout.minWidgetHeight, state.size.height + resizeState.height)
        )
    }

    public var body: some View {
        ZStack(alignment: .top) {
            // Background
            LinearGradient(
                colors: [RDS.Colors.widgetSurfaceGradientBottom, RDS.Colors.widgetSurfaceGradientTop],
                startPoint: .bottom,
                endPoint: .top
            )
            .opacity(0.95)
            .cornerRadius(RDS.Layout.widgetCornerRadius)

            // Content
            VStack(spacing: 0) {
                // Header spacer to push content down slightly if needed, or overlay header
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Header bar (overlay so it doesn't shift content)
            if isHeaderVisible {
                headerBar
                    .transition(.opacity)
            }

            // Invisible Resize hit zones (4 edges, 4 corners)
            resizeHitZones
        }
        .frame(width: liveSize.width, height: liveSize.height)
        .overlay(
            RoundedRectangle(cornerRadius: RDS.Layout.widgetCornerRadius)
                .stroke(isSelected ? RDS.Colors.widgetBorderSelected : (state.isPrimaryTier ? RDS.Colors.widgetBorderGlow : RDS.Colors.accent.opacity(0.06)), lineWidth: RDS.Layout.widgetBorderWidth)
                .shadow(color: RDS.Colors.accent.opacity(0.08), radius: 4)
        )
        .position(livePosition)
        .gesture(
            DragGesture()
                .updating($dragState) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    let newPos = CGPoint(
                        x: self.state.position.x + value.translation.width,
                        y: self.state.position.y + value.translation.height
                    )
                    onMove(newPos)
                }
        )
        .simultaneousGesture(TapGesture().onEnded {
            onSelect()
        })
        .onHover { hovered in
            isHovered = hovered
            handleHover(hovered)
        }
        .zIndex(isSelected ? 1000 : Double(state.zIndex))
    }

    // MARK: - Header
    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: state.type?.icon ?? "square")
                .font(.caption)
                .foregroundColor(RDS.Colors.accent)

            Text(state.title)
                .font(RDS.Typography.widgetTitle)
                .foregroundColor(RDS.Colors.textPrimary)
                .lineLimit(1)

            Spacer()

            GlowButton(icon: state.isVisible ? "eye.fill" : "eye.slash.fill", action: onToggleVisibility)
            GlowButton(icon: "xmark", action: onDelete)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.6), Color.black.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .cornerRadius(RDS.Layout.widgetCornerRadius, corners: [.topLeft, .topRight])
        .onTapGesture(count: 2) {
            onTierToggle()
        }
    }

    private func handleHover(_ hovered: Bool) {
        if hovered {
            headerHideTask?.cancel()
            withAnimation(.easeIn(duration: 0.2)) {
                isHeaderVisible = true
            }
        } else {
            headerHideTask?.cancel()
            headerHideTask = Task {
                try await Task.sleep(nanoseconds: 300_000_000)
                if !Task.isCancelled {
                    await MainActor.run {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isHeaderVisible = false
                        }
                    }
                }
            }
        }
    }

    // MARK: - Resize Zones
    private var resizeHitZones: some View {
        let hitZone = RDS.Layout.resizeHitZone
        return ZStack {
            // Edges
            ResizeHandler(cursor: .resizeUpDown) { delta in resize(dx: 0, dy: -delta.height, moveY: delta.height/2) }
                .frame(height: hitZone).frame(maxHeight: .infinity, alignment: .top)
            ResizeHandler(cursor: .resizeUpDown) { delta in resize(dx: 0, dy: delta.height, moveY: delta.height/2) }
                .frame(height: hitZone).frame(maxHeight: .infinity, alignment: .bottom)
            ResizeHandler(cursor: .resizeLeftRight) { delta in resize(dx: -delta.width, dy: 0, moveX: delta.width/2) }
                .frame(width: hitZone).frame(maxWidth: .infinity, alignment: .leading)
            ResizeHandler(cursor: .resizeLeftRight) { delta in resize(dx: delta.width, dy: 0, moveX: delta.width/2) }
                .frame(width: hitZone).frame(maxWidth: .infinity, alignment: .trailing)
            
            // Corners
            ResizeHandler(cursor: .crosshair) { delta in resize(dx: -delta.width, dy: -delta.height, moveX: delta.width/2, moveY: delta.height/2) }
                .frame(width: hitZone, height: hitZone).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            ResizeHandler(cursor: .crosshair) { delta in resize(dx: delta.width, dy: -delta.height, moveX: delta.width/2, moveY: delta.height/2) }
                .frame(width: hitZone, height: hitZone).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            ResizeHandler(cursor: .crosshair) { delta in resize(dx: -delta.width, dy: delta.height, moveX: delta.width/2, moveY: delta.height/2) }
                .frame(width: hitZone, height: hitZone).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            ResizeHandler(cursor: .crosshair) { delta in resize(dx: delta.width, dy: delta.height, moveX: delta.width/2, moveY: delta.height/2) }
                .frame(width: hitZone, height: hitZone).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    private func resize(dx: CGFloat, dy: CGFloat, moveX: CGFloat = 0, moveY: CGFloat = 0) {
        let newSize = CGSize(
            width: max(RDS.Layout.minWidgetWidth, state.size.width + dx),
            height: max(RDS.Layout.minWidgetHeight, state.size.height + dy)
        )
        // If the size was clamped by minSize, we shouldn't translate the position fully.
        // For simplicity in Phase 8, we apply moveX/moveY proportionally or just pass it if unbound.
        // A robust implementation would check if bounds were exceeded. 
        let actualDx = newSize.width - state.size.width
        let actualDy = newSize.height - state.size.height
        
        let adjustedMoveX = dx != 0 ? moveX * (actualDx / dx) : 0
        let adjustedMoveY = dy != 0 ? moveY * (actualDy / dy) : 0

        let newPos = CGPoint(
            x: state.position.x + adjustedMoveX,
            y: state.position.y + adjustedMoveY
        )
        if actualDx != 0 || actualDy != 0 {
            onResize(newSize)
        }
        if adjustedMoveX != 0 || adjustedMoveY != 0 {
            onMove(newPos)
        }
    }
}

fileprivate struct ResizeHandler: View {
    let cursor: NSCursor
    let onResize: (CGSize) -> Void
    @State private var isHovering = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    if !isHovering {
                        cursor.push()
                        isHovering = true
                    }
                case .ended:
                    if isHovering {
                        cursor.pop()
                        isHovering = false
                    }
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { _ in
                        if !isHovering {
                            cursor.push()
                            isHovering = true
                        }
                    }
                    .onEnded { value in
                        onResize(value.translation)
                        if isHovering {
                            cursor.pop()
                            isHovering = false
                        }
                    }
            )
            .onDisappear {
                if isHovering {
                    cursor.pop()
                    isHovering = false
                }
            }
    }
}

// Utility to apply corner radius to specific corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape( RoundedCorner(radius: radius, corners: corners) )
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomLeft = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
    static let allCorners: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: RectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = NSBezierPath()
        
        let minX = rect.minX
        let minY = rect.minY
        let maxX = rect.maxX
        let maxY = rect.maxY
        
        // Starts at top left
        path.move(to: NSPoint(x: minX + (corners.contains(.topLeft) ? radius : 0), y: minY))
        
        // Top right
        path.line(to: NSPoint(x: maxX - (corners.contains(.topRight) ? radius : 0), y: minY))
        if corners.contains(.topRight) {
            path.appendArc(withCenter: NSPoint(x: maxX - radius, y: minY + radius), radius: radius, startAngle: 270, endAngle: 360)
        }
        
        // Bottom right
        path.line(to: NSPoint(x: maxX, y: maxY - (corners.contains(.bottomRight) ? radius : 0)))
        if corners.contains(.bottomRight) {
            path.appendArc(withCenter: NSPoint(x: maxX - radius, y: maxY - radius), radius: radius, startAngle: 0, endAngle: 90)
        }
        
        // Bottom left
        path.line(to: NSPoint(x: minX + (corners.contains(.bottomLeft) ? radius : 0), y: maxY))
        if corners.contains(.bottomLeft) {
            path.appendArc(withCenter: NSPoint(x: minX + radius, y: maxY - radius), radius: radius, startAngle: 90, endAngle: 180)
        }
        
        // Close back to top left
        path.line(to: NSPoint(x: minX, y: minY + (corners.contains(.topLeft) ? radius : 0)))
        if corners.contains(.topLeft) {
            path.appendArc(withCenter: NSPoint(x: minX + radius, y: minY + radius), radius: radius, startAngle: 180, endAngle: 270)
        }
        
        path.close()
        
        var cgPath = Path()
        // Convert NSBezierPath to SwiftUI Path
        let numElements = path.elementCount
        if numElements > 0 {
            var points = [NSPoint](repeating: NSPoint.zero, count: 3)
            for i in 0..<numElements {
                let type = path.element(at: i, associatedPoints: &points)
                switch type {
                case .moveTo:
                    cgPath.move(to: CGPoint(x: points[0].x, y: points[0].y))
                case .lineTo:
                    cgPath.addLine(to: CGPoint(x: points[0].x, y: points[0].y))
                case .curveTo:
                    cgPath.addCurve(to: CGPoint(x: points[2].x, y: points[2].y),
                                    control1: CGPoint(x: points[0].x, y: points[0].y),
                                    control2: CGPoint(x: points[1].x, y: points[1].y))
                case .closePath:
                    cgPath.closeSubpath()
                @unknown default:
                    break
                }
            }
        }
        return cgPath
    }
}
