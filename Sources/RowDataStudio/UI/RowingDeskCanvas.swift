// UI/RowingDeskCanvas.swift v2.4.0
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
 * v2.4.0 - 2026-03-14 - Add AudioTrackWidget routing: .audio case in tracks(for:) and
 *                        widgetContent(for:) (Phase 8c.7: AudioTrackWidget).
 * v2.3.0 - 2026-03-13 - Widget↔Track lifecycle: mutateSession replaces mutateWidgets;
 *                        addWidget creates TimelineTrack entries; deleteWidget removes
 *                        non-pinned linked tracks. streamType(for:) + tracks(for:)
 *                        utilities (Phase 8c.2: Widget↔Track Lifecycle).
 * v2.2.0 - 2026-03-13 - Magnetic snapping in commitMove via SnapEngine; snap guide overlay
 *                        (Phase 8b.6: Magnetic Snapping).
 * v2.1.0 - 2026-03-12 - LineChart default → gps_gpmf_ts_speed (pure GPS, no fusion).
 *                        MultiLineChart default → ACCL-Y + inertial velocity from ACCL-Y
 *                        (bypasses fusion for comb-artifact investigation).
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
    /// Live pinch scale multiplier (in-flight only; discarded after gesture ends).
    /// Multiplied with `canvasZoom` in scaleEffect so child widgets can intercept
    /// the gesture before the canvas does (SwiftUI child-gesture priority).
    @GestureState private var liveZoomScale: Double = 1.0
    /// Debounce task for persisting zoom/pan to model.
    @State private var positionSaveTask: Task<Void, Never>?
    /// Debounce task for persisting widget mutations to disk.
    @State private var widgetSaveTask: Task<Void, Never>?

    // ── Magnetic snapping ────────────────────────────────────────────────────
    /// Active snap guide lines shown briefly after a widget drag ends with a snap.
    @State private var snapGuides: [SnapGuide] = []
    /// Task that clears `snapGuides` after a short delay.
    @State private var snapGuideClearTask: Task<Void, Never>?

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
                    RDS.Colors.canvasBackground.ignoresSafeArea()

                    // Grid: only re-evals when canvasPan changes (not during zoom animation)
                    CanvasGrid(pan: canvasPan, liveDelta: livePanDelta, size: geo.size)
                        .equatable()

                    // Widget layer: only re-evals when widgets/selection change (not during animation)
                    CanvasWidgetLayer(
                        dataContext: dataContext,
                        playheadController: playheadController,
                        selectedWidgetIDs: selectedWidgetIDs,
                        isFocusModeActive: isFocusModeActive,
                        onMove:             { id, pos  in commitMove(id: id, to: pos) },
                        onResize:           { id, size in commitResize(id: id, to: size) },
                        onDelete:           { id in deleteWidget(id: id) },
                        onToggleVisibility: { id in toggleVisibility(id: id) },
                        onSelect:           { id in handleWidgetSelection(id: id) },
                        onTierToggle:       { id in toggleTier(id: id) },
                        onFocusSelection:   { toggleFocusMode() }
                    )
                    .equatable()

                    // Snap guide overlay — accent dashed lines, auto-clears after 600ms
                    if !snapGuides.isEmpty {
                        Canvas { context, _ in
                            for guide in snapGuides {
                                var path = Path()
                                path.move(to: guide.start)
                                path.addLine(to: guide.end)
                                context.stroke(path,
                                               with: .color(RDS.Colors.accent.opacity(0.7)),
                                               style: StrokeStyle(lineWidth: 1, dash: [4, 2]))
                            }
                        }
                        .allowsHitTesting(false)
                    }
                }
                .scaleEffect(canvasZoom * liveZoomScale, anchor: .topLeading)
                .offset(
                    x: canvasPan.x + livePanDelta.width,
                    y: canvasPan.y + livePanDelta.height
                )
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
                // Canvas pinch-to-zoom. SwiftUI child-gesture priority means a widget's own
                // MagnificationGesture (e.g. LineChartWidget X-axis zoom) fires first when the
                // user pinches over that widget; this gesture fires on the canvas background.
                .gesture(
                    MagnificationGesture()
                        .updating($liveZoomScale) { value, state, _ in
                            state = value
                        }
                        .onEnded { value in
                            canvasZoom = max(RDS.Layout.canvasZoomMin,
                                             min(RDS.Layout.canvasZoomMax, canvasZoom * value))
                            schedulePositionSave()
                        }
                )
                .onTapGesture { selectedWidgetIDs = [] }
            }

            // ── Sidebar: only re-evals when selection/palette visibility changes ──
            CanvasSidebar(
                dataContext: dataContext,
                selectedWidgetIDs: selectedWidgetIDs,
                showWidgetPalette: showWidgetPalette,
                onTogglePalette: { showWidgetPalette.toggle() },
                onAddWidget:     { type in addWidget(type: type) }
            )
            .equatable()
            .frame(width: 260)
            .background(Color.gray.opacity(0.05))
        }
        .onAppear {
            if let canvas = dataContext.sessionDocument?.canvas {
                canvasZoom = canvas.zoomLevel
                canvasPan  = canvas.panOffset
            }
            setupEventMonitor()
        }
        .onDisappear { teardownEventMonitor() }
    }


    // Sidebar and grid are now CanvasSidebar / CanvasGrid structs (Equatable, below).
    // They are NOT methods on RowingDeskCanvas to prevent re-evaluation during animation.

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Canvas mutations (widget layout only — NOT zoom/pan)
    // ─────────────────────────────────────────────────────────────────────────


    private func addWidget(type: WidgetType) {
        let offset = CGFloat(widgets.count) * 24
        // Use local canvasPan (not sessionDocument) — avoids reading @Published model
        let pos = CGPoint(x: 120 + offset - canvasPan.x, y: 100 + offset - canvasPan.y)
        let newWidget = WidgetState.make(type: type, position: pos)
        let newTracks = Self.tracks(for: newWidget)
        mutateSession { doc in
            doc.canvas.widgets.append(newWidget)
            doc.timeline.tracks.append(contentsOf: newTracks)
        }
        selectedWidgetIDs = [newWidget.id]
        showWidgetPalette = false
    }

    private func commitMove(id: UUID, to newPos: CGPoint) {
        // Apply magnetic snap before committing position.
        let snapped: CGPoint
        let guides: [SnapGuide]
        if let moving = widgets.first(where: { $0.id == id }) {
            let draggingRect = CGRect(origin: newPos, size: moving.size)
            let otherRects = widgets.filter { $0.id != id && $0.isVisible }
                                    .map { CGRect(origin: $0.position, size: $0.size) }
            (snapped, guides) = SnapEngine.snapPosition(
                dragging: draggingRect,
                others: otherRects,
                threshold: RDS.Layout.snapThreshold
            )
        } else {
            snapped = newPos
            guides = []
        }
        // Show snap guides briefly then clear.
        snapGuideClearTask?.cancel()
        snapGuides = guides
        if !guides.isEmpty {
            snapGuideClearTask = Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { snapGuides = [] }
            }
        }
        mutateSession { doc in
            if let i = doc.canvas.widgets.firstIndex(where: { $0.id == id }) {
                doc.canvas.widgets[i].position = snapped
            }
        }
    }

    private func commitResize(id: UUID, to newSize: CGSize) {
        mutateSession { doc in
            if let i = doc.canvas.widgets.firstIndex(where: { $0.id == id }) {
                doc.canvas.widgets[i].size = newSize
            }
        }
    }

    private func deleteWidget(id: UUID) {
        mutateSession { doc in
            doc.canvas.widgets.removeAll { $0.id == id }
            // Remove non-pinned tracks whose widget was deleted; pinned tracks survive.
            doc.timeline.tracks.removeAll { !$0.isPinned && $0.linkedWidgetID == id }
        }
        selectedWidgetIDs.remove(id)
    }

    private func toggleVisibility(id: UUID) {
        mutateSession { doc in
            if let i = doc.canvas.widgets.firstIndex(where: { $0.id == id }) {
                let current = doc.canvas.widgets[i].isVisible
                doc.canvas.widgets[i].configuration["isVisible"] = AnyCodable(!current)
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
        mutateSession { doc in
            if let idx = doc.canvas.widgets.firstIndex(where: { $0.id == id }) {
                doc.canvas.widgets[idx].zIndex = nextZIndex
                nextZIndex += 1
            }
        }
    }

    private func toggleTier(id: UUID) {
        mutateSession { doc in
            guard let i = doc.canvas.widgets.firstIndex(where: { $0.id == id }) else { return }
            let isPrimary = doc.canvas.widgets[i].isPrimaryTier
            let newPrimary = !isPrimary
            doc.canvas.widgets[i].configuration["isPrimaryTier"] = AnyCodable(newPrimary)
            let defaultSize = doc.canvas.widgets[i].type?.defaultSize ?? CGSize(width: 400, height: 300)
            doc.canvas.widgets[i].size = newPrimary
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
    // MARK: - NSEvent monitor (spacebar + F + Esc)
    // Canvas pinch-to-zoom is now handled by the SwiftUI MagnificationGesture
    // on the canvas ZStack, so .magnify events are NOT consumed here. This allows
    // child widget gestures (e.g. LineChartWidget X-axis zoom) to fire first.
    // ─────────────────────────────────────────────────────────────────────────

    private func setupEventMonitor() {
        let pc = playheadController
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [self] event in
            switch event.type {
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

    /// Mutate the session document (canvas + timeline) and debounce disk write.
    ///
    /// This is the ONLY path that writes to `sessionDocument`. Replaces the old
    /// `mutateWidgets` which only reached `canvas.widgets`.
    private func mutateSession(_ mutation: (inout SessionDocument) -> Void) {
        guard dataContext.sessionDocument != nil else { return }
        mutation(&dataContext.sessionDocument!)
        widgetSaveTask?.cancel()
        widgetSaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let doc = dataContext.sessionDocument else { return }
            if let store = try? SessionStore() { try? await store.save(doc) }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Track lifecycle utilities
    // `internal` (not private) so TrackLifecycleTests can call them directly.
    // ─────────────────────────────────────────────────────────────────────────

    /// Infers the `StreamType` from a metric ID string by parsing its family prefix.
    nonisolated static func streamType(for metricID: String) -> StreamType {
        if metricID.hasPrefix("gps_") { return .gps }
        if metricID.hasPrefix("imu_") {
            if metricID.contains("acc") { return .accl }
            if metricID.contains("gyro") { return .gyro }
        }
        if metricID.hasPrefix("fit_") {
            if metricID.contains("hr") || metricID.contains("heart") { return .hr }
            if metricID.contains("cad") { return .cadence }
            if metricID.contains("power") { return .power }
            if metricID.contains("temp") { return .temperature }
            if metricID.contains("speed") || metricID.contains("vel") { return .speed }
        }
        if metricID.hasPrefix("fus_") {
            if metricID.contains("vel") { return .fusedVelocity }
            if metricID.contains("pitch") { return .fusedPitch }
            if metricID.contains("roll") { return .fusedRoll }
        }
        return .speed   // default fallback
    }

    /// Returns the `TimelineTrack` entries to create when `widget` is added to the canvas.
    ///
    /// Widget type → track count:
    /// - `.video`                      → 1 (stream: `.video`)
    /// - `.map`                        → 1 (stream: `.gps`)
    /// - `.lineChart`                  → 1 per metricID
    /// - `.multiLineChart`             → N per metricID
    /// - `.strokeTable`                → 1 per metricID
    /// - `.empowerRadar`, `.metricCard`→ 0 (derived / KPI, no timeline track needed)
    nonisolated static func tracks(for widget: WidgetState) -> [TimelineTrack] {
        guard let type = widget.type else { return [] }
        switch type {
        case .video:
            return [.virtual(stream: .video, linkedWidgetID: widget.id, displayName: "Video")]
        case .map:
            return [.virtual(stream: .gps, linkedWidgetID: widget.id, displayName: "GPS Track")]
        case .lineChart, .multiLineChart, .strokeTable:
            return widget.metricIDs.map { metricID in
                    .virtual(stream: streamType(for: metricID),
                             linkedWidgetID: widget.id,
                             metricID: metricID,
                             displayName: metricID)
            }
        case .empowerRadar, .metricCard:
            return []   // Derived / per-stroke KPI — no timeline track
        case .audio:
            return [.virtual(stream: .audio, linkedWidgetID: widget.id, displayName: "Audio")]
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

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - CanvasWidgetLayer
//
// CRITICAL DESIGN CONSTRAINT: This struct must NOT receive canvasZoom or canvasPan
// as parameters. If it did, every animation frame would call this body, which
// invokes widgetContent(for:) for every widget — running expensive pipeline code.
//
// Transforms (.scaleEffect, .offset) are applied from OUTSIDE by RowingDeskCanvas.
// SwiftUI applies those as render-level transforms without re-evaluating this body.
// ─────────────────────────────────────────────────────────────────────────────
private struct CanvasWidgetLayer: View, Equatable {

    // MARK: - Equatable (used by .equatable() in RowingDeskCanvas.body)
    //
    // Closures are NEVER equal across SwiftUI body calls (Swift doesn't compare function
    // references). Without a custom ==, SwiftUI would always consider CanvasWidgetLayer
    // "changed" and re-evaluate its body on every animation frame.
    //
    // We only compare the props that should actually trigger a body re-eval.
    // Closures are intentionally excluded — they are functionally stable.
    nonisolated static func == (lhs: CanvasWidgetLayer, rhs: CanvasWidgetLayer) -> Bool {
        lhs.selectedWidgetIDs == rhs.selectedWidgetIDs &&
        lhs.isFocusModeActive == rhs.isFocusModeActive
        // dataContext: @ObservedObject — SwiftUI handles this separately
    }

    @ObservedObject var dataContext: DataContext
    let playheadController: PlayheadController
    let selectedWidgetIDs: Set<UUID>
    let isFocusModeActive: Bool

    // Widget interaction callbacks (UUID-parameterized)
    let onMove:             (UUID, CGPoint) -> Void
    let onResize:           (UUID, CGSize)  -> Void
    let onDelete:           (UUID)          -> Void
    let onToggleVisibility: (UUID)          -> Void
    let onSelect:           (UUID)          -> Void
    let onTierToggle:       (UUID)          -> Void
    let onFocusSelection:   ()              -> Void

    private var widgets: [WidgetState] {
        dataContext.sessionDocument?.canvas.widgets ?? []
    }

    var body: some View {
        ForEach(widgets.filter { $0.isVisible }) { widget in
            WidgetContainer(
                state: widget,
                content: { widgetContent(for: widget) },
                isSelected: selectedWidgetIDs.contains(widget.id),
                onMove:             { pos  in onMove(widget.id, pos) },
                onResize:           { size in onResize(widget.id, size) },
                onDelete:           { onDelete(widget.id) },
                onToggleVisibility: { onToggleVisibility(widget.id) },
                onSelect:           { onSelect(widget.id) },
                onTierToggle:       { onTierToggle(widget.id) }
            )
            .opacity(isFocusModeActive && !selectedWidgetIDs.contains(widget.id) ? RDS.Layout.focusDimOpacity : 1.0)
            .allowsHitTesting(!(isFocusModeActive && !selectedWidgetIDs.contains(widget.id)))
            .contextMenu {
                if selectedWidgetIDs.count >= 2 {
                    Button("Focus Selection") { onFocusSelection() }
                }
            }
        }
    }

    // MARK: - Widget content factory
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
            // Default: raw ACCL-Y (surge) only — unprocessed IMU signal for artifact debugging.
            let defaultIDs = ["imu_raw_ts_acc_surge"]
            let ids = widget.metricIDs.isEmpty ? defaultIDs : widget.metricIDs
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
            EmpowerRadarWidget(fusionResult: dataContext.fusionResult,
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

        case .audio:
            // Peaks are loaded by FileImportHelper into dataContext.waveformPeaks.
            // Shows placeholder until the .waveform.gz sidecar is generated and loaded.
            AudioTrackWidget(state: widget,
                             dataContext: dataContext,
                             playheadController: playheadController,
                             waveformPeaks: dataContext.waveformPeaks,
                             viewportMs: viewport)

        case .none:
            VStack {
                Image(systemName: widget.type?.icon ?? "square.dashed")
                    .font(.system(size: 28)).foregroundColor(.gray)
                Text(widget.type?.displayName ?? widget.widgetType)
                    .font(.caption).foregroundColor(.secondary)
                Text("Coming soon").font(.caption2).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - CanvasGrid
// ─────────────────────────────────────────────────────────────────────────────

/// Background dot grid. Only re-evaluates when pan changes (not during zoom animation).
private struct CanvasGrid: View, Equatable {
    let pan: CGPoint
    let liveDelta: CGSize
    let size: CGSize

    nonisolated static func == (lhs: CanvasGrid, rhs: CanvasGrid) -> Bool {
        lhs.pan == rhs.pan && lhs.liveDelta == rhs.liveDelta && lhs.size == rhs.size
    }

    var body: some View {
        Canvas { context, canvasSize in
            let spacing: CGFloat = 50
            let offsetX = pan.x.truncatingRemainder(dividingBy: spacing)
            let offsetY = pan.y.truncatingRemainder(dividingBy: spacing)
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

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - CanvasSidebar
// ─────────────────────────────────────────────────────────────────────────────

/// Right-side widget panel. Only re-evaluates when the selected widget or
/// palette visibility changes — never during zoom/pan animation.
private struct CanvasSidebar: View, Equatable {
    @ObservedObject var dataContext: DataContext
    let selectedWidgetIDs: Set<UUID>
    let showWidgetPalette: Bool
    let onTogglePalette: () -> Void
    let onAddWidget: (WidgetType) -> Void

    nonisolated static func == (lhs: CanvasSidebar, rhs: CanvasSidebar) -> Bool {
        lhs.selectedWidgetIDs == rhs.selectedWidgetIDs &&
        lhs.showWidgetPalette == rhs.showWidgetPalette
        // dataContext: @ObservedObject — handled by SwiftUI separately
    }

    private var widgets: [WidgetState] {
        dataContext.sessionDocument?.canvas.widgets ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Widgets").font(.headline)
                Spacer()
                Button(action: onTogglePalette) {
                    Image(systemName: showWidgetPalette ? "minus.circle" : "plus.circle.fill")
                        .font(.title2).foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            Divider()

            // Palette (conditionally shown)
            if showWidgetPalette {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(WidgetType.allCases, id: \.self) { type in
                            Button { onAddWidget(type) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: type.icon).frame(width: 20).foregroundColor(.accentColor)
                                    Text(type.displayName).font(.callout)
                                    Spacer()
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Color.gray.opacity(0.08)).cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 280)
                Divider()
            }

            // Inspector
            inspectorPanel
        }
    }

    @ViewBuilder
    private var inspectorPanel: some View {
        if let id = selectedWidgetIDs.first, selectedWidgetIDs.count == 1,
           let widget = widgets.first(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Inspector").font(.headline).padding(.horizontal)
                    Divider()
                    row("Type",     widget.type?.displayName ?? widget.widgetType)
                    row("Position", String(format: "(%.0f, %.0f)", widget.position.x, widget.position.y))
                    row("Size",     String(format: "%.0f × %.0f", widget.size.width, widget.size.height))
                    if !widget.metricIDs.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Metrics").font(.caption).foregroundColor(.secondary).padding(.horizontal)
                            ForEach(widget.metricIDs, id: \.self) { m in
                                Text(m).font(.caption).monospaced()
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.accentColor.opacity(0.1)).cornerRadius(4)
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

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.caption).monospaced()
        }
        .padding(.horizontal)
    }
}

#Preview {
    let dataContext = DataContext()
    let playheadController = PlayheadController()
    return RowingDeskCanvas(dataContext: dataContext, playheadController: playheadController)
}
