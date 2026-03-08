// UI/WidgetContainer.swift v1.0.0
/**
 * Draggable/resizable widget frame container.
 *
 * Wraps any analysis widget and provides:
 * - Drag-to-move functionality
 * - Resize handle (bottom-right corner)
 * - Selection UI (border highlight)
 * - Visibility toggle + delete actions
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 6: Canvas & Widgets).
 */

import SwiftUI

/// Container view for draggable/resizable widgets on the canvas.
public struct WidgetContainer: View {
    let config: WidgetConfig
    let content: AnyView

    @State private var isDragging = false
    @State private var isResizing = false
    @State private var dragOffset = CGSize.zero
    @State private var resizeOffset = CGSize.zero

    var position: CGPoint {
        CGPoint(
            x: config.position.x + dragOffset.width,
            y: config.position.y + dragOffset.height
        )
    }

    var size: CGSize {
        CGSize(
            width: max(200, config.size.width + resizeOffset.width),
            height: max(150, config.size.height + resizeOffset.height)
        )
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            // Widget content
            content
                .frame(width: size.width, height: size.height)
                .background(Color(.white).opacity(0.8))
                .cornerRadius(8)
                .border(isSelected ? Color.accentColor : Color.gray.opacity(0.3), width: 2)

            // Header bar (title + actions)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: WidgetType.lineChart.icon)
                        .font(.caption)
                        .foregroundColor(.accentColor)

                    Text(config.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Spacer()

                    // Visibility toggle
                    Button(action: toggleVisibility) {
                        Image(systemName: config.isVisible ? "eye.fill" : "eye.slash.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    // Delete button
                    Button(action: deleteWidget) {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))

                Spacer()
            }
            .frame(height: 32)

            // Resize handle (bottom-right corner)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: "arrow.down.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                        .padding(4)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    isResizing = true
                                    resizeOffset = CGSize(
                                        width: value.translation.width,
                                        height: value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    isResizing = false
                                    // Persist new size
                                    let newConfig = WidgetConfig(
                                        type: config.type,
                                        id: config.id,
                                        title: config.title,
                                        position: position,
                                        size: size,
                                        metricIDs: config.metricIDs,
                                        isVisible: config.isVisible
                                    )
                                    updateWidget(newConfig)
                                }
                        )
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .position(position)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if !isResizing {
                        isDragging = true
                        dragOffset = value.translation
                    }
                }
                .onEnded { _ in
                    isDragging = false
                    // Persist new position
                    let newConfig = WidgetConfig(
                        type: config.type,
                        id: config.id,
                        title: config.title,
                        position: position,
                        size: size,
                        metricIDs: config.metricIDs,
                        isVisible: config.isVisible
                    )
                    updateWidget(newConfig)
                    dragOffset = .zero
                }
        )
        .zIndex(isDragging || isResizing ? 1000 : 0)
    }

    private var isSelected: Bool {
        false  // TODO: Integrate with canvas selection state
    }

    private func toggleVisibility() {
        let newConfig = WidgetConfig(
            type: config.type,
            id: config.id,
            title: config.title,
            position: config.position,
            size: config.size,
            metricIDs: config.metricIDs,
            isVisible: !config.isVisible
        )
        updateWidget(newConfig)
    }

    private func deleteWidget() {
        // TODO: Delete from canvas
        print("Delete widget: \(config.id)")
    }

    private func updateWidget(_ newConfig: WidgetConfig) {
        // TODO: Update SessionDocument.canvas.widgets
        print("Update widget: \(newConfig.id) at \(newConfig.position)")
    }
}

#Preview {
    WidgetContainer(
        config: WidgetConfig(
            type: .lineChart,
            title: "Velocity",
            position: CGPoint(x: 100, y: 100),
            size: CGSize(width: 400, height: 300),
            metricIDs: ["fus_cal_ts_vel_inertial"]
        ),
        content: AnyView(
            VStack {
                Text("Chart Content")
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
        )
    )
}
