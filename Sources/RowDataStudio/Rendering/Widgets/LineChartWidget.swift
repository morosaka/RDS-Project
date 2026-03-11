// Rendering/Widgets/LineChartWidget.swift v1.3.0
/**
 * Single-series line chart widget.
 *
 * **Architecture (v1.3):**
 * - TransformPipeline (ViewportCull → LTTB → AdaptiveSmooth) runs OFF the main thread
 *   via `.task(id:)`. Body never calls the pipeline directly.
 * - Cached (displayTs, displayVals) in @State — recomputed only when inputs change.
 * - PlayheadOverlay subscribes to PlayheadController internally; parent widget does NOT
 *   have @ObservedObject, so its body is not re-evaluated at 60fps.
 *
 * --- Revision History ---
 * v1.3.0 - 2026-03-12 - Pipeline moved off main thread; @State result cache; removed GeometryReader.
 * v1.2.0 - 2026-03-11 - PlayheadOverlay owns @ObservedObject, parent is plain `let`.
 * v1.1.0 - 2026-03-11 - Separated data layer (Equatable) from overlay.
 * v1.0.0 - 2026-03-07 - Initial implementation.
 */

import SwiftUI

/// Single-channel sensor line chart widget.
public struct LineChartWidget: View {

    let timestamps: ContiguousArray<Double>
    let values: ContiguousArray<Float>
    /// Plain `let` — NOT @ObservedObject. Only child `PlayheadOverlay` subscribes.
    let playheadController: PlayheadController
    let viewportMs: ClosedRange<Double>
    var targetPointCount: Int = 2000

    public init(
        timestamps: ContiguousArray<Double>,
        values: ContiguousArray<Float>,
        playheadController: PlayheadController,
        viewportMs: ClosedRange<Double>,
        targetPointCount: Int = 2000
    ) {
        self.timestamps = timestamps
        self.values = values
        self.playheadController = playheadController
        self.viewportMs = viewportMs
        self.targetPointCount = targetPointCount
    }

    public var body: some View {
        LineChartDataLayer(
            timestamps: timestamps,
            values: values,
            viewportMs: viewportMs,
            targetPointCount: targetPointCount
        )
        .overlay {
            PlayheadOverlay(playheadController: playheadController, viewportMs: viewportMs)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Data Layer (async pipeline cache)

/// Renders the chart. Pipeline output is cached in @State and computed off the main thread.
/// Body only draws from the cache — no O(n) computation here.
private struct LineChartDataLayer: View, Equatable {

    let timestamps: ContiguousArray<Double>
    let values: ContiguousArray<Float>
    let viewportMs: ClosedRange<Double>
    let targetPointCount: Int

    // Cached pipeline results — set once off-thread, never recomputed per-frame.
    @State private var displayTs: ContiguousArray<Double> = []
    @State private var displayVals: ContiguousArray<Float> = []
    @State private var yRange: (min: Float, max: Float) = (0, 1)

    nonisolated static func == (lhs: LineChartDataLayer, rhs: LineChartDataLayer) -> Bool {
        lhs.timestamps.count == rhs.timestamps.count &&
        lhs.values.count == rhs.values.count &&
        lhs.viewportMs == rhs.viewportMs &&
        lhs.targetPointCount == rhs.targetPointCount &&
        lhs.timestamps.first == rhs.timestamps.first &&
        lhs.timestamps.last == rhs.timestamps.last
    }

    /// Cache invalidation key — changes when data or viewport change.
    private var pipelineKey: String {
        "\(timestamps.count):\(values.count):\(viewportMs.lowerBound):\(viewportMs.upperBound):\(targetPointCount)"
    }

    var body: some View {
        let (yMin, yMax) = yRange
        let ySpan = max(yMax - yMin, Float(1e-4))

        Canvas { context, canvasSize in
            guard !displayTs.isEmpty else { return }
            var path = Path()
            var movePending = true

            for i in 0..<min(displayTs.count, displayVals.count) {
                let v = displayVals[i]
                guard !v.isNaN else { movePending = true; continue }
                let x = xPosition(t: displayTs[i], viewport: viewportMs, width: canvasSize.width)
                let y = yPosition(v: v, yMin: yMin, ySpan: ySpan, height: canvasSize.height)
                let pt = CGPoint(x: x, y: y)
                if movePending { path.move(to: pt); movePending = false }
                else { path.addLine(to: pt) }
            }
            context.stroke(path, with: .color(.blue),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            if yMin < 0, yMax > 0 {
                let zy = yPosition(v: 0, yMin: yMin, ySpan: ySpan, height: canvasSize.height)
                var z = Path()
                z.move(to: CGPoint(x: 0, y: zy))
                z.addLine(to: CGPoint(x: canvasSize.width, y: zy))
                context.stroke(z, with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)
            }
        }
        .overlay(alignment: .topLeading) {
            axisLabels(yMin: yMin, yMax: yMax)
        }
        // Pipeline runs off-main-thread; re-triggered only when pipelineKey changes.
        .task(id: pipelineKey) {
            let ts = timestamps, vals = values, vp = viewportMs, tc = targetPointCount
            let result = await Task.detached(priority: .userInitiated) { () -> (ContiguousArray<Double>, ContiguousArray<Float>, Float, Float) in
                let (dts, dvals) = TransformPipeline.mvp(
                    viewportMs: vp, targetCount: tc, pointsPerPixel: 1.0
                ).apply(timestamps: ts, values: vals)
                let (mn, mx) = computeValueRange(dvals)
                return (dts, dvals, mn, mx)
            }.value
            guard !Task.isCancelled else { return }
            displayTs   = result.0
            displayVals = result.1
            yRange      = (result.2, result.3)
        }
    }

    @ViewBuilder
    private func axisLabels(yMin: Float, yMax: Float) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(formatValue(yMax)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).padding([.top, .leading], 4)
            Spacer()
            Text(formatValue(yMin)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).padding([.bottom, .leading], 4)
        }
    }
}

// MARK: - File-private helpers

private func computeValueRange(_ vals: ContiguousArray<Float>) -> (Float, Float) {
    var mn = Float.infinity, mx = -Float.infinity
    for v in vals where !v.isNaN {
        if v < mn { mn = v }
        if v > mx { mx = v }
    }
    guard mn.isFinite, mx.isFinite else { return (0, 1) }
    let pad = max((mx - mn) * 0.05, Float(1e-4))
    return (mn - pad, mx + pad)
}

private func xPosition(t: Double, viewport: ClosedRange<Double>, width: CGFloat) -> CGFloat {
    let span = viewport.upperBound - viewport.lowerBound
    guard span > 0 else { return 0 }
    return CGFloat((t - viewport.lowerBound) / span) * width
}

private func yPosition(v: Float, yMin: Float, ySpan: Float, height: CGFloat) -> CGFloat {
    CGFloat(1.0 - Double((v - yMin) / ySpan)) * height
}

private func formatValue(_ v: Float) -> String {
    if abs(v) >= 1000 { return String(format: "%.0f", v) }
    if abs(v) >= 100  { return String(format: "%.1f", v) }
    return String(format: "%.2f", v)
}

// MARK: - Playhead Overlay (60fps child)

/// Only this child struct subscribes to PlayheadController.
/// Parent LineChartWidget and LineChartDataLayer do NOT re-run at 60fps.
private struct PlayheadOverlay: View {

    @ObservedObject var playheadController: PlayheadController
    let viewportMs: ClosedRange<Double>

    var body: some View {
        Canvas { context, canvasSize in
            let px = xPosition(t: playheadController.currentTimeMs, viewport: viewportMs, width: canvasSize.width)
            guard px >= 0, px <= canvasSize.width else { return }
            var cursor = Path()
            cursor.move(to: CGPoint(x: px, y: 0))
            cursor.addLine(to: CGPoint(x: px, y: canvasSize.height))
            context.stroke(cursor, with: .color(.red.opacity(0.8)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }
}

#Preview {
    let n = 500
    let ts: ContiguousArray<Double> = ContiguousArray((0..<n).map { Double($0) * 100 })
    let vals: ContiguousArray<Float> = ContiguousArray((0..<n).map { Float(sin(Double($0) * 0.05)) * 2 + 4 })
    let pc = PlayheadController()
    LineChartWidget(timestamps: ts, values: vals, playheadController: pc, viewportMs: 0...50_000)
        .frame(width: 480, height: 280)
}
