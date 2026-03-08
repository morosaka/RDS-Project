// UI/WidgetContainer.swift v1.1.0
/**
 * Draggable/resizable widget frame container.
 *
 * Wraps any analysis widget content and provides:
 * - Drag-to-move (updates WidgetState.position)
 * - Resize handle (bottom-right corner, updates WidgetState.size)
 * - Selection highlight border
 * - Header bar with title, visibility toggle, delete
 *
 * --- Revision History ---
 * v1.1.0 - 2026-03-08 - Switch from WidgetConfig to WidgetState (real model).
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 6: Canvas & Widgets).
 */

import SwiftUI

/// Container view for draggable/resizable widgets on the canvas.
public struct WidgetContainer: View {
    let state: WidgetState
    let content: AnyView
    let isSelected: Bool
    let onMove: (CGPoint) -> Void
    let onResize: (CGSize) -> Void
    let onDelete: () -> Void
    let onToggleVisibility: () -> Void

    @GestureState private var dragState = CGSize.zero
    @GestureState private var resizeState = CGSize.zero

    private var livePosition: CGPoint {
        CGPoint(
            x: state.position.x + dragState.width,
            y: state.position.y + dragState.height
        )
    }

    private var liveSize: CGSize {
        CGSize(
            width: max(200, state.size.width + resizeState.width),
            height: max(150, state.size.height + resizeState.height)
        )
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // Header bar
                HStack(spacing: 8) {
                    Image(systemName: state.type?.icon ?? "square")
                        .font(.caption)
                        .foregroundColor(.accentColor)

                    Text(state.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Spacer()

                    Button(action: onToggleVisibility) {
                        Image(systemName: state.isVisible ? "eye.fill" : "eye.slash.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.12))

                // Widget content
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: liveSize.width, height: liveSize.height)
            .background(Color.white.opacity(0.85))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 2)
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.12 : 0.05), radius: isSelected ? 6 : 2)

            // Resize handle
            Image(systemName: "arrow.down.right")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .padding(6)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(4)
                .padding(4)
                .gesture(
                    DragGesture()
                        .updating($resizeState) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            let newSize = CGSize(
                                width: max(200, self.state.size.width + value.translation.width),
                                height: max(150, self.state.size.height + value.translation.height)
                            )
                            onResize(newSize)
                        }
                )
        }
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
        .zIndex(isSelected ? 1000 : Double(state.zIndex))
    }
}

#Preview {
    let state = WidgetState.make(
        type: .lineChart,
        position: CGPoint(x: 300, y: 200),
        metricIDs: ["fus_cal_ts_vel_inertial"]
    )

    return ZStack {
        Color.gray.opacity(0.1).ignoresSafeArea()
        WidgetContainer(
            state: state,
            content: AnyView(
                VStack {
                    Text("Velocity Chart")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
            ),
            isSelected: true,
            onMove: { _ in },
            onResize: { _ in },
            onDelete: {},
            onToggleVisibility: {}
        )
    }
}
