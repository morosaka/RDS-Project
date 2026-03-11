// UI/RowingDeskCanvas.swift v1.2.0
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
 * v1.5.0 - 2026-03-11 - Decouple playheadController: `let` instead of `@ObservedObject`.
 *                        Widgets observe playhead internally; canvas no longer redraws at 60fps.
 * v1.4.0 - 2026-03-08 - Pinch/zoom and spacebar via NSEvent monitor (bypasses SwiftUI responder chain).
 * v1.3.0 - 2026-03-08 - Fix zoom: SimultaneousGesture attempt (insufficient for SPM executables).
 * v1.2.0 - 2026-03-08 - Wire all widget types to real implementations.
 * v1.1.0 - 2026-03-08 - Full DataContext + SessionDocument integration.
 * v1.0.0 - 2026-03-08 - Placeholder scaffolding.
 */

import AppKit
import SwiftUI

/// Main infinite canvas with pan, zoom, and draggable widgets.
public struct RowingDeskCanvas: View {
    @ObservedObject var dataContext: DataContext
    /// Plain `let` — NOT @ObservedObject. The canvas must NOT subscribe to
    /// playheadController's 60fps currentTimeMs updates. Each widget that
    /// needs the playhead observes it internally via its own @ObservedObject.
    let playheadController: PlayheadController

    @State private var selectedWidgetIDs: Set<UUID> = []
    @State private var showWidgetPalette = false
    @State private var eventMonitor: Any?
    // Fix 3: debounce disk persistence — only write ~0.5s after last mutation
    @State private var saveDebounceTask: Task<Void, Never>?

    // 8b.2 Z-Ordering
    @State private var nextZIndex: Int = 1

    // 8b.4 Focus Mode
    @State private var isFocusModeActive: Bool = false
    @State private var preFocusZoomLevel: Double = 1.0
    @State private var preFocusPanOffset: CGPoint = .zero

    // Live pan state (committed to sessionDocument on gesture end)
    @GestureState private var livePanDelta = CGSize.zero

    private var canvas: CanvasState {
        dataContext.sessionDocument?.canvas ?? CanvasState()
    }

    private var effectiveZoom: CGFloat {
        CGFloat(canvas.zoomLevel)
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
                    RDS.Colors.canvasBackground
                        .ignoresSafeArea()

                    canvasGrid(size: geo.size)

                    // Widget layer
                    ForEach(canvas.widgets.filter { $0.isVisible }) { widget in
                        WidgetContainer(
                            state: widget,
                            content: { widgetContent(for: widget) },
                            isSelected: selectedWidgetIDs.contains(widget.id),
                            onMove:             { newPos  in commitMove(id: widget.id, to: newPos) },
                            onResize:           { newSize in commitResize(id: widget.id, to: newSize) },
                            onDelete:           { deleteWidget(id: widget.id) },
                            onToggleVisibility: { toggleVisibility(id: widget.id) },
                            onSelect:           { handleWidgetSelection(id: widget.id) },
                            onTierToggle:       { toggleTier(id: widget.id) }
                        )
                        .opacity(isFocusModeActive && !selectedWidgetIDs.contains(widget.id) ? RDS.Layout.focusDimOpacity : 1.0)
                        .allowsHitTesting(!(isFocusModeActive && !selectedWidgetIDs.contains(widget.id)))
                        .contextMenu {
                            if selectedWidgetIDs.count >= 2 {
                                Button("Focus Selection") { toggleFocusMode() }
                            }
                        }
                    }
                }
                .scaleEffect(effectiveZoom, anchor: .topLeading)
                .offset(x: effectivePan.x, y: effectivePan.y)
                // Pan via SwiftUI DragGesture. Zoom and spacebar handled by
                // NSEvent monitor (setupEventMonitor) — bypasses SwiftUI
                // responder chain limitations in SPM executables.
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .updating($livePanDelta) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            commitPan(delta: value.translation)
                        }
                )
                .onTapGesture { selectedWidgetIDs = [] }
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
        .onAppear { setupEventMonitor() }
        .onDisappear { teardownEventMonitor() }
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
        if let id = selectedWidgetIDs.first, selectedWidgetIDs.count == 1,
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
        } else if selectedWidgetIDs.count > 1 {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "square.dashed.inset.filled")
                    .font(.system(size: 28))
                    .foregroundColor(.gray)
                Text("\(selectedWidgetIDs.count) widgets selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
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
    // @ViewBuilder preserves concrete type identity — NO AnyView, NO type erasure.
    // SwiftUI can diff the view tree properly, only recomputing on real data changes.
    @ViewBuilder
    private func widgetContent(for widget: WidgetState) -> some View {
        let ts = dataContext.timestamps ?? []
        let dur = dataContext.sessionDurationMs
        let viewport: ClosedRange<Double> = dur > 0 ? (0.0...dur) : (0.0...1.0)
        // NOTE: We do NOT read playheadController.currentTimeMs here.
        // Widgets observe playheadController internally, so the canvas body is NOT
        // invalidated at 60fps — only the tiny child overlays re-render.

        switch widget.type {
        case .lineChart:
            let metricID = widget.metricIDs.first ?? dataContext.selectedMetric
            let vals = dataContext.values(for: metricID) ?? []
            LineChartWidget(
                timestamps: ts, values: vals,
                playheadController: playheadController, viewportMs: viewport
            )

        case .multiLineChart:
            let ids = widget.metricIDs.isEmpty ? [dataContext.selectedMetric] : widget.metricIDs
            let series = MultiLineChartWidget.series(from: dataContext, metricIDs: ids)
            MultiLineChartWidget(
                series: series, playheadController: playheadController, viewportMs: viewport
            )

        case .metricCard:
            let metricID = widget.metricIDs.first ?? dataContext.selectedMetric
            let values = dataContext.values(for: metricID) ?? []
            let label = metricID.components(separatedBy: "_").last ?? metricID
            MetricCardWidget(
                label: label, unit: "",
                values: values, timestamps: ts,
                playheadController: playheadController
            )

        case .strokeTable:
            let strokes = dataContext.fusionResult?.perStrokeStats ?? []
            let startTimes = dataContext.fusionResult?.strokes.map { $0.startTime * 1000 } ?? []
            StrokeTableWidget(
                strokes: strokes,
                playheadController: playheadController,
                strokeStartTimesMs: startTimes
            )

        case .map:
            let lats: ContiguousArray<Float> = dataContext.buffers.map {
                ContiguousArray($0.gps_gpmf_ts_lat.map { Float($0) })
            } ?? []
            let lons: ContiguousArray<Float> = dataContext.buffers.map {
                ContiguousArray($0.gps_gpmf_ts_lon.map { Float($0) })
            } ?? []
            MapWidget(
                latitudes: lats, longitudes: lons,
                timestamps: ts, playheadController: playheadController
            )

        case .empowerRadar:
            EmpowerRadarWidget(
                currentStroke: nil,
                averageMetrics: [:],
                fusionResult: dataContext.fusionResult,
                playheadController: playheadController
            )

        case .video:
            let sourceIDStr = widget.configuration["sourceID"]?.value as? String
            let sourceID = sourceIDStr.flatMap { UUID(uuidString: $0) }
            let videoURL: URL? = {
                if let id = sourceID,
                   let src = dataContext.sessionDocument?.source(withID: id),
                   case .goProVideo(_, let url, _) = src { return url }
                if let primary = dataContext.sessionDocument?.primaryVideo,
                   case .goProVideo(_, let url, _) = primary { return url }
                return nil
            }()
            let offsetMs = widget.configuration["timeOffsetMs"]?.value as? Double ?? 0.0
            VideoWidget(url: videoURL, timeOffsetMs: offsetMs, playheadController: playheadController)

        case .none:
            placeholderContent(widget)
        }
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
        selectedWidgetIDs = [newWidget.id]
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
        selectedWidgetIDs.remove(id)
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
            canvas.zoomLevel = max(RDS.Layout.canvasZoomMin, min(RDS.Layout.canvasZoomMax, canvas.zoomLevel * Double(factor)))
        }
    }

    private func handleWidgetSelection(id: UUID) {
        let isCmdPressed = NSEvent.modifierFlags.contains(.command)
        if isCmdPressed {
            if selectedWidgetIDs.contains(id) {
                selectedWidgetIDs.remove(id)
            } else {
                selectedWidgetIDs.insert(id)
            }
        } else {
            selectedWidgetIDs = [id]
        }
        
        mutateCanvas { canvas in
            if let idx = canvas.widgets.firstIndex(where: { $0.id == id }) {
                canvas.widgets[idx].zIndex = nextZIndex
                nextZIndex += 1
            }
        }
    }

    private func toggleTier(id: UUID) {
        mutateCanvas { canvas in
            guard let i = canvas.widgets.firstIndex(where: { $0.id == id }) else { return }
            let isPrimary = canvas.widgets[i].isPrimaryTier
            let newPrimary = !isPrimary
            canvas.widgets[i].configuration["isPrimaryTier"] = AnyCodable(newPrimary)
            
            let defaultSize = canvas.widgets[i].type?.defaultSize ?? CGSize(width: 400, height: 300)
            
            withAnimation(RDS.Springs.snapToGrid) {
                if newPrimary {
                    canvas.widgets[i].size = defaultSize
                } else {
                    canvas.widgets[i].size = CGSize(width: defaultSize.width * 0.5, height: defaultSize.height * 0.5)
                }
            }
        }
    }

    private func toggleFocusMode() {
        if isFocusModeActive {
            withAnimation(RDS.Springs.focusModeZoom) {
                isFocusModeActive = false
                mutateCanvas { canvas in
                    canvas.zoomLevel = preFocusZoomLevel
                    canvas.panOffset = preFocusPanOffset
                }
            }
        } else {
            if selectedWidgetIDs.isEmpty { return }
            
            preFocusZoomLevel = canvas.zoomLevel
            preFocusPanOffset = canvas.panOffset
            
            let selectedWidgets = canvas.widgets.filter { selectedWidgetIDs.contains($0.id) }
            var minX: CGFloat = .infinity
            var minY: CGFloat = .infinity
            var maxX: CGFloat = -.infinity
            var maxY: CGFloat = -.infinity
            
            for w in selectedWidgets {
                minX = min(minX, w.position.x)
                minY = min(minY, w.position.y)
                maxX = max(maxX, w.position.x + w.size.width)
                maxY = max(maxY, w.position.y + w.size.height)
            }
            let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            let padding: CGFloat = 20
            
            let viewportWidth: CGFloat = 1024
            let viewportHeight: CGFloat = 768
            
            let scaleX = viewportWidth / (rect.width + padding * 2)
            let scaleY = viewportHeight / (rect.height + padding * 2)
            let targetZoom = max(RDS.Layout.canvasZoomMin, min(RDS.Layout.canvasZoomMax, Double(min(scaleX, scaleY))))
            
            let centerX = rect.midX
            let centerY = rect.midY
            
            let targetPanX = (viewportWidth / 2) - (centerX * CGFloat(targetZoom))
            let targetPanY = (viewportHeight / 2) - (centerY * CGFloat(targetZoom))
            
            withAnimation(RDS.Springs.focusModeZoom) {
                isFocusModeActive = true
                mutateCanvas { canvas in
                    canvas.zoomLevel = targetZoom
                    canvas.panOffset = CGPoint(x: targetPanX, y: targetPanY)
                }
            }
        }
    }

    // MARK: - NSEvent monitor (zoom + spacebar)

    private func setupEventMonitor() {
        // Capture reference types directly — avoids struct-copy stale-capture issue.
        let dc = dataContext
        let pc = playheadController

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .keyDown]) { event in
            switch event.type {
            case .magnify:
                let factor = max(0.25, min(4.0, 1.0 + event.magnification))
                if dc.sessionDocument != nil {
                    dc.sessionDocument!.canvas.zoomLevel = max(
                        RDS.Layout.canvasZoomMin, min(RDS.Layout.canvasZoomMax, dc.sessionDocument!.canvas.zoomLevel * Double(factor))
                    )
                }
                return nil

            case .keyDown where event.keyCode == 49:  // Spacebar
                if pc.isPlaying { pc.pause() } else { pc.play() }
                return nil

            case .keyDown where event.keyCode == 3: // 3 = f
                Task { @MainActor in self.toggleFocusMode() }
                return nil

            case .keyDown where event.keyCode == 53: // 53 = Esc
                Task { @MainActor in
                    if self.isFocusModeActive {
                        self.toggleFocusMode()
                    } else if !self.selectedWidgetIDs.isEmpty {
                        self.selectedWidgetIDs = []
                    }
                }
                return nil

            default:
                return event
            }
        }
    }

    private func teardownEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    /// Single mutation point — modifies sessionDocument.canvas and debounces disk persistence.
    /// Disk write is deferred 0.5s after the last mutation to avoid per-frame I/O.
    private func mutateCanvas(_ mutation: (inout CanvasState) -> Void) {
        guard dataContext.sessionDocument != nil else { return }
        mutation(&dataContext.sessionDocument!.canvas)
        // Cancel previous pending save, schedule a new one.
        saveDebounceTask?.cancel()
        let doc = dataContext.sessionDocument
        saveDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 s
            guard !Task.isCancelled, let doc else { return }
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
