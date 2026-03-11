// UI/RowingDeskCanvas.swift v2.0.0
/**
 * Infinite canvas for multi-widget analysis layout.
 *
 * **Architecture (v2.0):** Canvas render state (zoom, pan) lives as local `@State` on this
 * view — NOT inside `dataContext.sessionDocument`. This is the critical invariant that
 * prevents SwiftUI from re-evaluating `body` on every animation frame.
 *
 * - `canvasZoom` / `canvasPan`: `@State`, animated directly. Persisted to sessionDocument
 *   with a 0.5s debounce only after the gesture/animation completes.
 * - Widget layout (position, size): written to sessionDocument only on drag END.
 * - Playhead: `let` (not @ObservedObject). Child views observe it internally.
 *
 * --- Revision History ---
 * v2.0.0 - 2026-03-11 - ARCH FIX: Decouple zoom/pan from @Published sessionDocument.
 *                        All animations now target @State; body no longer re-evaluates
 *                        on every animation frame. Fixes 1.25s/frame sluggishness.
 * v1.5.0 - 2026-03-11 - Decouple playheadController: `let` instead of `@ObservedObject`.
 */

import AppKit
import SwiftUI

/// Main infinite canvas with pan, zoom, and draggable widgets.
public struct RowingDeskCanvas: View {
    @ObservedObject var dataContext: DataContext
    /// Plain `let` — NOT @ObservedObject. Canvas must NOT subscribe to 60fps ticks.
    let playheadController: PlayheadController

    // ── Selection & UI state ────────────────────────────────────────────────
    @State private var selectedWidgetIDs: Set<UUID> = []
    @State private var showWidgetPalette = false
    @State private var eventMonitor: Any?

    // ── Z-ordering ──────────────────────────────────────────────────────────
    @State private var nextZIndex: Int = 1

    // ── Focus mode ──────────────────────────────────────────────────────────
    @State private var isFocusModeActive: Bool = false
    @State private var preFocusZoom: Double = 1.0
    @State private var preFocusPan: CGPoint = .zero

    // ── RENDER STATE (local @State — NEVER stored in @Published model during animations) ──
    /// Current canvas zoom level. Animated directly; written to sessionDocument at rest.
    @State private var canvasZoom: Double = 1.0
    /// Current canvas pan offset. Animated directly; written to sessionDocument at rest.
    @State private var canvasPan: CGPoint = .zero
    /// Live drag delta (in-flight only; discarded after gesture ends).
    @GestureState private var livePanDelta = CGSize.zero
    /// Debounce task for persisting zoom/pan to model.
    @State private var positionSaveTask: Task<Void, Never>?
    /// Debounce task for persisting widget mutations to disk.
    @State private var widgetSaveTask: Task<Void, Never>?

    // ── Convenience accessor (READ ONLY — never write through this) ─────────
    /// Returns the current canvas widget list. Does NOT trigger body re-evals by itself.
    private var widgets: [WidgetState] {
        dataContext.sessionDocument?.canvas.widgets ?? []
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Body
    // ─────────────────────────────────────────────────────────────────────────

    public var body: some View {
        HStack(spacing: 0) {
            // ── Canvas area ──────────────────────────────────────────────────
            GeometryReader { geo in
                ZStack {
                    // Background + grid (grid reads canvasPan via local state — cheap)
                    RDS.Colors.canvasBackground.ignoresSafeArea()
                    canvasGrid(size: geo.size)

                    // Widget layer — re-evaluated only when widgets array or selection changes,
                    // NOT when canvasZoom/canvasPan change (those are handled by scaleEffect/offset).
                    ForEach(widgets.filter { $0.isVisible }) { widget in
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
                // ── Transforms applied to the canvas (local @State — no body re-eval) ──
                .scaleEffect(canvasZoom, anchor: .topLeading)
                .offset(
                    x: canvasPan.x + livePanDelta.width,
                    y: canvasPan.y + livePanDelta.height
                )
                // ── Background pan gesture ───────────────────────────────────
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .updating($livePanDelta) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            canvasPan = CGPoint(
                                x: canvasPan.x + value.translation.width,
                                y: canvasPan.y + value.translation.height
                            )
                            schedulePositionSave()
                        }
                )
                .onTapGesture { selectedWidgetIDs = [] }
            }

            // ── Right sidebar ────────────────────────────────────────────────
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
        .onAppear {
            // Sync local render state from persisted model on first load.
            if let canvas = dataContext.sessionDocument?.canvas {
                canvasZoom = canvas.zoomLevel
                canvasPan = canvas.panOffset
            }
            setupEventMonitor()
        }
        .onDisappear { teardownEventMonitor() }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Sidebar
    // ─────────────────────────────────────────────────────────────────────────

    private var sidebarHeader: some View {
        HStack {
            Text("Widgets").font(.headline)
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
                    Button { addWidget(type: type) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: type.icon)
                                .frame(width: 20)
                                .foregroundColor(.accentColor)
                            Text(type.displayName).font(.callout)
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
           let widget = widgets.first(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Inspector").font(.headline).padding(.horizontal)
                    Divider()
                    inspectorRow("Type",     widget.type?.displayName ?? widget.widgetType)
                    inspectorRow("Position", String(format: "(%.0f, %.0f)", widget.position.x, widget.position.y))
                    inspectorRow("Size",     String(format: "%.0f × %.0f", widget.size.width, widget.size.height))
                    if !widget.metricIDs.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Metrics").font(.caption).foregroundColor(.secondary).padding(.horizontal)
                            ForEach(widget.metricIDs, id: \.self) { metric in
                                Text(metric)
                                    .font(.caption).monospaced()
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(4).padding(.horizontal)
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
                Image(systemName: "square.dashed.inset.filled").font(.system(size: 28)).foregroundColor(.gray)
                Text("\(selectedWidgetIDs.count) widgets selected").font(.caption).foregroundColor(.secondary)
                Spacer()
            }
        } else {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "cursorarrow.click").font(.system(size: 28)).foregroundColor(.gray)
                Text("Select a widget").font(.caption).foregroundColor(.secondary)
                Spacer()
            }
        }
    }

    private func inspectorRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.caption).monospaced()
        }
        .padding(.horizontal)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Widget content factory
    // @ViewBuilder: no AnyView, no type erasure. Body only called when widget data changes.
    // ─────────────────────────────────────────────────────────────────────────

    @ViewBuilder
    private func widgetContent(for widget: WidgetState) -> some View {
        let ts = dataContext.timestamps ?? []
        let dur = dataContext.sessionDurationMs
        let viewport: ClosedRange<Double> = dur > 0 ? (0.0...dur) : (0.0...1.0)

        switch widget.type {
        case .lineChart:
            let metricID = widget.metricIDs.first ?? dataContext.selectedMetric
            let vals = dataContext.values(for: metricID) ?? []
            LineChartWidget(timestamps: ts, values: vals,
                            playheadController: playheadController, viewportMs: viewport)

        case .multiLineChart:
            let ids = widget.metricIDs.isEmpty ? [dataContext.selectedMetric] : widget.metricIDs
            let series = MultiLineChartWidget.series(from: dataContext, metricIDs: ids)
            MultiLineChartWidget(series: series, playheadController: playheadController, viewportMs: viewport)

        case .metricCard:
            let metricID = widget.metricIDs.first ?? dataContext.selectedMetric
            let values = dataContext.values(for: metricID) ?? []
            let label = metricID.components(separatedBy: "_").last ?? metricID
            MetricCardWidget(label: label, unit: "",
                             values: values, timestamps: ts,
                             playheadController: playheadController)

        case .strokeTable:
            let strokes = dataContext.fusionResult?.perStrokeStats ?? []
            let startTimes = dataContext.fusionResult?.strokes.map { $0.startTime * 1000 } ?? []
            StrokeTableWidget(strokes: strokes, playheadController: playheadController,
                              strokeStartTimesMs: startTimes)

        case .map:
            let lats: ContiguousArray<Float> = dataContext.buffers.map {
                ContiguousArray($0.gps_gpmf_ts_lat.map { Float($0) })
            } ?? []
            let lons: ContiguousArray<Float> = dataContext.buffers.map {
                ContiguousArray($0.gps_gpmf_ts_lon.map { Float($0) })
            } ?? []
            MapWidget(latitudes: lats, longitudes: lons,
                      timestamps: ts, playheadController: playheadController)

        case .empowerRadar:
            EmpowerRadarWidget(currentStroke: nil, averageMetrics: [:],
                               fusionResult: dataContext.fusionResult,
                               playheadController: playheadController)

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
                .font(.system(size: 28)).foregroundColor(.gray)
            Text(widget.type?.displayName ?? widget.widgetType)
                .font(.caption).foregroundColor(.secondary)
            Text("Coming soon").font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Canvas mutations (widget layout only — NOT zoom/pan)
    // ─────────────────────────────────────────────────────────────────────────

    private func addWidget(type: WidgetType) {
        let offset = CGFloat(widgets.count) * 24
        // Use local canvasPan (not sessionDocument) — avoids reading @Published model
        let pos = CGPoint(x: 120 + offset - canvasPan.x, y: 100 + offset - canvasPan.y)
        let newWidget = WidgetState.make(type: type, position: pos)
        mutateWidgets { $0.append(newWidget) }
        selectedWidgetIDs = [newWidget.id]
        showWidgetPalette = false
    }

    private func commitMove(id: UUID, to newPos: CGPoint) {
        mutateWidgets { widgets in
            if let i = widgets.firstIndex(where: { $0.id == id }) {
                widgets[i].position = newPos
            }
        }
    }

    private func commitResize(id: UUID, to newSize: CGSize) {
        mutateWidgets { widgets in
            if let i = widgets.firstIndex(where: { $0.id == id }) {
                widgets[i].size = newSize
            }
        }
    }

    private func deleteWidget(id: UUID) {
        mutateWidgets { $0.removeAll { $0.id == id } }
        selectedWidgetIDs.remove(id)
    }

    private func toggleVisibility(id: UUID) {
        mutateWidgets { widgets in
            if let i = widgets.firstIndex(where: { $0.id == id }) {
                let current = widgets[i].isVisible
                widgets[i].configuration["isVisible"] = AnyCodable(!current)
            }
        }
    }

    private func handleWidgetSelection(id: UUID) {
        let isCmdPressed = NSEvent.modifierFlags.contains(.command)
        if isCmdPressed {
            if selectedWidgetIDs.contains(id) { selectedWidgetIDs.remove(id) }
            else { selectedWidgetIDs.insert(id) }
        } else {
            selectedWidgetIDs = [id]
        }
        mutateWidgets { widgets in
            if let idx = widgets.firstIndex(where: { $0.id == id }) {
                widgets[idx].zIndex = nextZIndex
                nextZIndex += 1
            }
        }
    }

    private func toggleTier(id: UUID) {
        mutateWidgets { widgets in
            guard let i = widgets.firstIndex(where: { $0.id == id }) else { return }
            let isPrimary = widgets[i].isPrimaryTier
            let newPrimary = !isPrimary
            widgets[i].configuration["isPrimaryTier"] = AnyCodable(newPrimary)
            let defaultSize = widgets[i].type?.defaultSize ?? CGSize(width: 400, height: 300)
            widgets[i].size = newPrimary
                ? defaultSize
                : CGSize(width: defaultSize.width * 0.5, height: defaultSize.height * 0.5)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Focus Mode
    // Animates canvasZoom and canvasPan (@State) — NOT sessionDocument.
    // ─────────────────────────────────────────────────────────────────────────

    private func toggleFocusMode() {
        if isFocusModeActive {
            withAnimation(RDS.Springs.focusModeZoom) {
                isFocusModeActive = false
                canvasZoom = preFocusZoom     // ← @State: cheap, local
                canvasPan  = preFocusPan      // ← @State: cheap, local
            }
            schedulePositionSave()
        } else {
            guard !selectedWidgetIDs.isEmpty else { return }
            preFocusZoom = canvasZoom
            preFocusPan  = canvasPan

            let selected = widgets.filter { selectedWidgetIDs.contains($0.id) }
            var minX: CGFloat = .infinity, minY: CGFloat = .infinity
            var maxX: CGFloat = -.infinity, maxY: CGFloat = -.infinity
            for w in selected {
                minX = min(minX, w.position.x);    minY = min(minY, w.position.y)
                maxX = max(maxX, w.position.x + w.size.width)
                maxY = max(maxY, w.position.y + w.size.height)
            }
            let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            let padding: CGFloat = 20
            let vpW: CGFloat = 1024, vpH: CGFloat = 768
            let scaleX = vpW / (rect.width  + padding * 2)
            let scaleY = vpH / (rect.height + padding * 2)
            let targetZoom = max(RDS.Layout.canvasZoomMin,
                                 min(RDS.Layout.canvasZoomMax, Double(min(scaleX, scaleY))))
            let targetPan = CGPoint(
                x: (vpW / 2) - (rect.midX * CGFloat(targetZoom)),
                y: (vpH / 2) - (rect.midY * CGFloat(targetZoom))
            )

            withAnimation(RDS.Springs.focusModeZoom) {
                isFocusModeActive = true
                canvasZoom = targetZoom   // ← @State only — body NOT re-evaluated per frame
                canvasPan  = targetPan    // ← @State only
            }
            schedulePositionSave()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - NSEvent monitor (zoom + spacebar + F + Esc)
    // ─────────────────────────────────────────────────────────────────────────

    private func setupEventMonitor() {
        let pc = playheadController
        // NOTE: We need to capture zoom/pan as mutable @State. We do this via MainActor closures.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .keyDown]) { [self] event in
            switch event.type {
            case .magnify:
                // Update @State directly on MainActor — no sessionDocument write during gesture.
                let factor = 1.0 + event.magnification
                Task { @MainActor in
                    canvasZoom = max(RDS.Layout.canvasZoomMin,
                                     min(RDS.Layout.canvasZoomMax, canvasZoom * factor))
                    schedulePositionSave()
                }
                return nil

            case .keyDown where event.keyCode == 49:  // Space
                if pc.isPlaying { pc.pause() } else { pc.play() }
                return nil

            case .keyDown where event.keyCode == 3:   // F
                Task { @MainActor in toggleFocusMode() }
                return nil

            case .keyDown where event.keyCode == 53:  // Esc
                Task { @MainActor in
                    if isFocusModeActive { toggleFocusMode() }
                    else if !selectedWidgetIDs.isEmpty { selectedWidgetIDs = [] }
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

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Persistence helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// Persist current canvasZoom/canvasPan to sessionDocument 0.5s after last call.
    /// Safe to call during/after gestures and animations.
    private func schedulePositionSave() {
        positionSaveTask?.cancel()
        let zoom = canvasZoom
        let pan  = canvasPan
        positionSaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                dataContext.sessionDocument?.canvas.zoomLevel = zoom
                dataContext.sessionDocument?.canvas.panOffset  = pan
            }
            if let doc = dataContext.sessionDocument, let store = try? SessionStore() {
                try? await store.save(doc)
            }
        }
    }

    /// Mutate *widget* layout (position, size, visibility, tier) and debounce disk write.
    /// This is the ONLY path that writes to sessionDocument.canvas.widgets.
    private func mutateWidgets(_ mutation: (inout [WidgetState]) -> Void) {
        guard dataContext.sessionDocument != nil else { return }
        mutation(&dataContext.sessionDocument!.canvas.widgets)
        widgetSaveTask?.cancel()
        widgetSaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let doc = dataContext.sessionDocument else { return }
            if let store = try? SessionStore() { try? await store.save(doc) }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Grid (uses local canvasPan — no model read)
    // ─────────────────────────────────────────────────────────────────────────

    private func canvasGrid(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let spacing: CGFloat = 50
            let offsetX = canvasPan.x.truncatingRemainder(dividingBy: spacing)
            let offsetY = canvasPan.y.truncatingRemainder(dividingBy: spacing)
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
