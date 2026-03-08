// UI/RowingDeskCanvas.swift v1.1.0
/**
 * Infinite canvas for multi-widget analysis layout.
 *
 * - Pan via drag on background (updates SessionDocument.canvas.panOffset)
 * - Zoom via magnification gesture (updates SessionDocument.canvas.zoomLevel)
 * - Widgets rendered as WidgetContainer instances from SessionDocument.canvas.widgets
 * - Widget palette sidebar for adding new widget types
 * - Inspector for selected widget configuration
 *
 * --- Revision History ---
 * v1.1.0 - 2026-03-08 - Full DataContext + SessionDocument integration.
 * v1.0.0 - 2026-03-08 - Placeholder scaffolding.
 */

import SwiftUI

/// Main infinite canvas with pan, zoom, and draggable widgets.
public struct RowingDeskCanvas: View {
    @ObservedObject var dataContext: DataContext
    @ObservedObject var playheadController: PlayheadController

    @State private var selectedWidgetID: UUID?
    @State private var showWidgetPalette = false

    // Live pan/zoom state (committed to sessionDocument on gesture end)
    @GestureState private var livePanDelta = CGSize.zero
    @GestureState private var liveMagnification: CGFloat = 1.0

    private var canvas: CanvasState {
        dataContext.sessionDocument?.canvas ?? CanvasState()
    }

    private var effectiveZoom: CGFloat {
        CGFloat(canvas.zoomLevel) * liveMagnification
    }

    private var effectivePan: CGPoint {
        CGPoint(
            x: canvas.panOffset.x + livePanDelta.width,
            y: canvas.panOffset.y + livePanDelta.height
        )
    }

    public var body: some View {
        HStack(spacing: 0) {
            // ── Canvas area ──────────────────────────────────────────
            GeometryReader { geo in
                ZStack {
                    // Background + grid
                    Color.gray.opacity(0.08)
                        .ignoresSafeArea()

                    canvasGrid(size: geo.size)

                    // Widget layer
                    ForEach(canvas.widgets.filter { $0.isVisible }) { widget in
                        WidgetContainer(
                            state: widget,
                            content: widgetContent(for: widget),
                            isSelected: selectedWidgetID == widget.id,
                            onMove:            { newPos   in commitMove(id: widget.id, to: newPos) },
                            onResize:          { newSize  in commitResize(id: widget.id, to: newSize) },
                            onDelete:          { deleteWidget(id: widget.id) },
                            onToggleVisibility: { toggleVisibility(id: widget.id) }
                        )
                        .onTapGesture { selectedWidgetID = widget.id }
                    }
                }
                .scaleEffect(effectiveZoom, anchor: .topLeading)
                .offset(x: effectivePan.x, y: effectivePan.y)
                // Pan gesture on background
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .updating($livePanDelta) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            commitPan(delta: value.translation)
                        }
                        .simultaneously(with: TapGesture().onEnded { selectedWidgetID = nil })
                )
                // Zoom gesture
                .gesture(
                    MagnificationGesture()
                        .updating($liveMagnification) { value, state, _ in
                            state = max(0.25, min(4.0, value))
                        }
                        .onEnded { value in
                            commitZoom(factor: value)
                        }
                )
            }

            // ── Right sidebar ─────────────────────────────────────────
            VStack(spacing: 0) {
                sidebarHeader
                Divider()
                if showWidgetPalette {
                    widgetPalette
                    Divider()
                }
                inspectorPanel
            }
            .frame(width: 260)
            .background(Color.gray.opacity(0.05))
        }
    }

    // MARK: - Sidebar

    private var sidebarHeader: some View {
        HStack {
            Text("Widgets")
                .font(.headline)
            Spacer()
            Button {
                showWidgetPalette.toggle()
            } label: {
                Image(systemName: showWidgetPalette ? "minus.circle" : "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }

    private var widgetPalette: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(WidgetType.allCases, id: \.self) { type in
                    Button {
                        addWidget(type: type)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: type.icon)
                                .frame(width: 20)
                                .foregroundColor(.accentColor)
                            Text(type.displayName)
                                .font(.callout)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .frame(maxHeight: 280)
    }

    @ViewBuilder
    private var inspectorPanel: some View {
        if let id = selectedWidgetID,
           let widget = canvas.widgets.first(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Inspector")
                        .font(.headline)
                        .padding(.horizontal)

                    Divider()

                    inspectorRow("Type", widget.type?.displayName ?? widget.widgetType)
                    inspectorRow("Position", String(format: "(%.0f, %.0f)", widget.position.x, widget.position.y))
                    inspectorRow("Size", String(format: "%.0f × %.0f", widget.size.width, widget.size.height))

                    if !widget.metricIDs.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Metrics")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                            ForEach(widget.metricIDs, id: \.self) { metric in
                                Text(metric)
                                    .font(.caption)
                                    .monospaced()
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(4)
                                    .padding(.horizontal)
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.vertical)
            }
        } else {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "cursorarrow.click")
                    .font(.system(size: 28))
                    .foregroundColor(.gray)
                Text("Select a widget")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
    }

    private func inspectorRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .monospaced()
        }
        .padding(.horizontal)
    }

    // MARK: - Widget content factory

    private func widgetContent(for widget: WidgetState) -> AnyView {
        switch widget.type {
        case .lineChart, .multiLineChart:
            let metricID = widget.metricIDs.first ?? dataContext.selectedMetric
            let ts = dataContext.timestamps ?? []
            let vals = dataContext.values(for: metricID) ?? []
            let dur = dataContext.sessionDurationMs
            let viewport = dur > 0 ? (0.0...dur) : (0.0...1.0)
            return AnyView(
                LineChartWidget(
                    timestamps: ts,
                    values: vals,
                    playheadTimeMs: playheadController.currentTimeMs,
                    viewportMs: viewport
                )
            )
        case .metricCard:
            return AnyView(metricCardContent(widget))
        default:
            return AnyView(placeholderContent(widget))
        }
    }

    private func metricCardContent(_ widget: WidgetState) -> some View {
        let metricID = widget.metricIDs.first ?? dataContext.selectedMetric
        let values = dataContext.values(for: metricID) ?? []
        let current = values.isEmpty ? Float.nan : values[min(Int(playheadController.currentTimeMs / 5), values.count - 1)]
        return VStack(spacing: 4) {
            Text(metricID.components(separatedBy: "_").last ?? metricID)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(current.isNaN ? "--" : String(format: "%.2f", current))
                .font(.title)
                .fontWeight(.bold)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholderContent(_ widget: WidgetState) -> some View {
        VStack {
            Image(systemName: widget.type?.icon ?? "square.dashed")
                .font(.system(size: 28))
                .foregroundColor(.gray)
            Text(widget.type?.displayName ?? widget.widgetType)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Coming soon")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Canvas mutations

    private func addWidget(type: WidgetType) {
        // Place new widget near centre of current view, offset slightly from last
        let offset = CGFloat(canvas.widgets.count) * 24
        let pos = CGPoint(
            x: 120 + offset - effectivePan.x,
            y: 100 + offset - effectivePan.y
        )
        let newWidget = WidgetState.make(type: type, position: pos)
        mutateCanvas { $0.widgets.append(newWidget) }
        selectedWidgetID = newWidget.id
        showWidgetPalette = false
    }

    private func commitMove(id: UUID, to newPos: CGPoint) {
        mutateCanvas { canvas in
            if let i = canvas.widgets.firstIndex(where: { $0.id == id }) {
                canvas.widgets[i].position = newPos
            }
        }
    }

    private func commitResize(id: UUID, to newSize: CGSize) {
        mutateCanvas { canvas in
            if let i = canvas.widgets.firstIndex(where: { $0.id == id }) {
                canvas.widgets[i].size = newSize
            }
        }
    }

    private func deleteWidget(id: UUID) {
        mutateCanvas { $0.widgets.removeAll { $0.id == id } }
        if selectedWidgetID == id { selectedWidgetID = nil }
    }

    private func toggleVisibility(id: UUID) {
        mutateCanvas { canvas in
            if let i = canvas.widgets.firstIndex(where: { $0.id == id }) {
                let current = canvas.widgets[i].isVisible
                canvas.widgets[i].configuration["isVisible"] = AnyCodable(!current)
            }
        }
    }

    private func commitPan(delta: CGSize) {
        mutateCanvas { canvas in
            canvas.panOffset = CGPoint(
                x: canvas.panOffset.x + delta.width,
                y: canvas.panOffset.y + delta.height
            )
        }
    }

    private func commitZoom(factor: CGFloat) {
        mutateCanvas { canvas in
            canvas.zoomLevel = max(0.25, min(4.0, canvas.zoomLevel * Double(factor)))
        }
    }

    /// Single mutation point — modifies sessionDocument.canvas and persists async.
    private func mutateCanvas(_ mutation: (inout CanvasState) -> Void) {
        guard dataContext.sessionDocument != nil else { return }
        mutation(&dataContext.sessionDocument!.canvas)
        Task {
            guard let doc = dataContext.sessionDocument else { return }
            if let store = try? SessionStore() {
                try? await store.save(doc)
            }
        }
    }

    // MARK: - Grid

    private func canvasGrid(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let spacing: CGFloat = 50
            let offsetX = effectivePan.x.truncatingRemainder(dividingBy: spacing)
            let offsetY = effectivePan.y.truncatingRemainder(dividingBy: spacing)
            var x = offsetX
            while x < canvasSize.width {
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: canvasSize.height))
                context.stroke(p, with: .color(Color.gray.opacity(0.12)))
                x += spacing
            }
            var y = offsetY
            while y < canvasSize.height {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: canvasSize.width, y: y))
                context.stroke(p, with: .color(Color.gray.opacity(0.12)))
                y += spacing
            }
        }
    }
}

#Preview {
    let dataContext = DataContext()
    let playheadController = PlayheadController()
    return RowingDeskCanvas(dataContext: dataContext, playheadController: playheadController)
}
