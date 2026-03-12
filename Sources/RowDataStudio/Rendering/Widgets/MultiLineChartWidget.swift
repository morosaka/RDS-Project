// Rendering/Widgets/MultiLineChartWidget.swift v1.3.0
/**
 * Multi-series line chart widget for metric overlay comparison.
 *
 * **Architecture (v1.3):**
 * - Per-series pipeline (ViewportCull → LTTB → AdaptiveSmooth) runs OFF the main thread
 *   via `.task(id:)`. Body draws exclusively from @State cache.
 * - MultiLinePlayheadOverlay has its own @ObservedObject; parent widget is plain `let`.
 *
 * --- Revision History ---
 * v1.3.0 - 2026-03-12 - Pipeline moved off main thread; @State result cache.
 * v1.2.0 - 2026-03-11 - Widget takes PlayheadController as let; overlay observes internally.
 * v1.1.0 - 2026-03-11 - Cache pipeline output; separate playhead from data render path.
 * v1.0.0 - 2026-03-08 - Initial implementation.
 */

import SwiftUI

/// A series descriptor binding a metric label to its time/value arrays.
public struct MetricSeries: Identifiable, Sendable {
    public let id: UUID
    public let label: String
    public let timestamps: ContiguousArray<Double>
    public let values: ContiguousArray<Float>
    public let color: Color

    public init(
        label: String,
        timestamps: ContiguousArray<Double>,
        values: ContiguousArray<Float>,
        color: Color
    ) {
        self.id = UUID()
        self.label = label
        self.timestamps = timestamps
        self.values = values
        self.color = color
    }
}

/// Overlay line chart displaying multiple sensor metrics simultaneously.
/// The data layer recomputes off-thread; the playhead redraws at 60fps via its own child.
public struct MultiLineChartWidget: View {

    let series: [MetricSeries]
    /// Plain `let` — NOT @ObservedObject. Only child `MultiLinePlayheadOverlay` subscribes.
    let playheadController: PlayheadController
    let viewportMs: ClosedRange<Double>
    var targetPointCount: Int = 1500

    public init(
        series: [MetricSeries],
        playheadController: PlayheadController,
        viewportMs: ClosedRange<Double>,
        targetPointCount: Int = 1500
    ) {
        self.series = series
        self.playheadController = playheadController
        self.viewportMs = viewportMs
        self.targetPointCount = targetPointCount
    }

    public var body: some View {
        MultiLineDataLayer(
            series: series,
            viewportMs: viewportMs,
            targetPointCount: targetPointCount
        )
        .overlay {
            // @ObservedObject lives here exclusively — widget parent NOT reactive at 60fps.
            MultiLinePlayheadOverlay(playheadController: playheadController, viewportMs: viewportMs)
        }
        .background(Color(white: 0.10)) // Fixed dark background — app never follows system appearance
    }
}

// MARK: - Data Layer (async pipeline cache)

/// Caches per-series LTTB output in @State. Pipeline runs off main thread via .task(id:).
private struct MultiLineDataLayer: View, Equatable {

    let series: [MetricSeries]
    let viewportMs: ClosedRange<Double>
    let targetPointCount: Int

    // Cached display data — only recomputed when inputs change.
    @State private var displaySeries: [(label: String, color: Color, ts: ContiguousArray<Double>, vals: ContiguousArray<Float>)] = []
    @State private var yRange: (min: Float, max: Float) = (0, 1)

    nonisolated static func == (lhs: MultiLineDataLayer, rhs: MultiLineDataLayer) -> Bool {
        guard lhs.series.count == rhs.series.count,
              lhs.viewportMs == rhs.viewportMs,
              lhs.targetPointCount == rhs.targetPointCount else { return false }
        for (l, r) in zip(lhs.series, rhs.series) {
            if l.timestamps.count != r.timestamps.count ||
               l.values.count != r.values.count ||
               l.label != r.label { return false }
        }
        return true
    }

    private var pipelineKey: String {
        let counts = series.map { "\($0.timestamps.count):\($0.values.count)" }.joined(separator: ",")
        return "\(counts):\(viewportMs.lowerBound):\(viewportMs.upperBound):\(targetPointCount)"
    }

    var body: some View {
        let (yMin, yMax) = yRange
        let ySpan = max(yMax - yMin, Float(1e-4))

        ZStack(alignment: .bottom) {
            Canvas { context, canvasSize in
                guard !displaySeries.isEmpty else { return }
                for item in displaySeries {
                    var path = Path()
                    var movePending = true
                    for i in 0..<min(item.ts.count, item.vals.count) {
                        let v = item.vals[i]
                        guard !v.isNaN else { movePending = true; continue }
                        let x = linXPos(t: item.ts[i], viewport: viewportMs, width: canvasSize.width)
                        let y = linYPos(v: v, yMin: yMin, ySpan: ySpan, height: canvasSize.height)
                        let pt = CGPoint(x: x, y: y)
                        if movePending { path.move(to: pt); movePending = false }
                        else { path.addLine(to: pt) }
                    }
                    context.stroke(path, with: .color(item.color),
                                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
            .overlay(alignment: .topLeading) {
                multiLineAxisLabels(yMin: yMin, yMax: yMax)
            }

            if !series.isEmpty {
                multiLineLegendStrip(series: series)
            }
        }
        .task(id: pipelineKey) {
            // Copy value types for Sendable safety before entering Task.detached.
            let inputSeries = series, vp = viewportMs, tc = targetPointCount
            let result = await Task.detached(priority: .userInitiated) { () -> (
                [(label: String, color: Color, ts: ContiguousArray<Double>, vals: ContiguousArray<Float>)],
                Float, Float
            ) in
                let pipeline = TransformPipeline.mvp(viewportMs: vp, targetCount: tc, pointsPerPixel: 1.0)
                var display: [(label: String, color: Color, ts: ContiguousArray<Double>, vals: ContiguousArray<Float>)] = []
                for s in inputSeries {
                    let (dts, dvals) = pipeline.apply(timestamps: s.timestamps, values: s.values)
                    display.append((s.label, s.color, dts, dvals))
                }
                let (mn, mx) = multiLineGlobalYRange(display.map(\.vals))
                return (display, mn, mx)
            }.value
            guard !Task.isCancelled else { return }
            displaySeries = result.0
            yRange = (result.1, result.2)
        }
    }
}

// MARK: - Playhead Overlay (60fps child)

/// Only this child struct subscribes to PlayheadController via @ObservedObject.
private struct MultiLinePlayheadOverlay: View {
    @ObservedObject var playheadController: PlayheadController
    let viewportMs: ClosedRange<Double>

    var body: some View {
        Canvas { context, canvasSize in
            let px = linXPos(t: playheadController.currentTimeMs, viewport: viewportMs, width: canvasSize.width)
            guard px >= 0, px <= canvasSize.width else { return }
            var cursor = Path()
            cursor.move(to: CGPoint(x: px, y: 0))
            cursor.addLine(to: CGPoint(x: px, y: canvasSize.height))
            context.stroke(cursor, with: .color(.red.opacity(0.8)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }
}

// MARK: - Legend + Axis

@ViewBuilder
private func multiLineLegendStrip(series: [MetricSeries]) -> some View {
    HStack(spacing: 12) {
        ForEach(series) { s in
            HStack(spacing: 4) {
                Rectangle().fill(s.color).frame(width: 14, height: 2)
                Text(s.label).font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }
    .padding(.horizontal, 6).padding(.vertical, 3)
    .background(Color.gray.opacity(0.06)).cornerRadius(4)
    .padding(.bottom, 4)
}

@ViewBuilder
private func multiLineAxisLabels(yMin: Float, yMax: Float) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        Text(multiLineFormatValue(yMax)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).padding([.top, .leading], 4)
        Spacer()
        Text(multiLineFormatValue(yMin)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).padding([.bottom, .leading], 4)
    }
}

// MARK: - Shared helpers

private func linXPos(t: Double, viewport: ClosedRange<Double>, width: CGFloat) -> CGFloat {
    let span = viewport.upperBound - viewport.lowerBound
    guard span > 0 else { return 0 }
    return CGFloat((t - viewport.lowerBound) / span) * width
}

private func linYPos(v: Float, yMin: Float, ySpan: Float, height: CGFloat) -> CGFloat {
    CGFloat(1.0 - Double((v - yMin) / ySpan)) * height
}

private func multiLineGlobalYRange(_ allVals: [ContiguousArray<Float>]) -> (Float, Float) {
    var mn = Float.infinity, mx = -Float.infinity
    for vals in allVals {
        for v in vals where !v.isNaN {
            if v < mn { mn = v }
            if v > mx { mx = v }
        }
    }
    guard mn.isFinite, mx.isFinite else { return (0, 1) }
    let pad = max((mx - mn) * 0.05, Float(1e-4))
    return (mn - pad, mx + pad)
}

private func multiLineFormatValue(_ v: Float) -> String {
    if abs(v) >= 100 { return String(format: "%.0f", v) }
    if abs(v) >= 10  { return String(format: "%.1f", v) }
    return String(format: "%.2f", v)
}

// MARK: - Default palette

public extension MultiLineChartWidget {
    static let palette: [Color] = [.blue, .red, .green, .orange, .purple, .teal]

    static func series(from dataContext: DataContext, metricIDs: [String]) -> [MetricSeries] {
        let ts = dataContext.timestamps ?? []
        return metricIDs.enumerated().compactMap { idx, key in
            guard let vals = dataContext.values(for: key) else { return nil }
            return MetricSeries(
                label: key.components(separatedBy: "_").last ?? key,
                timestamps: ts, values: vals,
                color: palette[idx % palette.count]
            )
        }
    }
}

#Preview {
    let n = 500
    let ts: ContiguousArray<Double> = ContiguousArray((0..<n).map { Double($0) * 100 })
    let vel: ContiguousArray<Float>  = ContiguousArray((0..<n).map { Float(sin(Double($0) * 0.05)) * 2 + 4 })
    let hr: ContiguousArray<Float>   = ContiguousArray((0..<n).map { Float(cos(Double($0) * 0.03)) * 5 + 145 })
    let pc = PlayheadController()
    MultiLineChartWidget(
        series: [
            MetricSeries(label: "Velocity", timestamps: ts, values: vel, color: .blue),
            MetricSeries(label: "HR",       timestamps: ts, values: hr,  color: .red)
        ],
        playheadController: pc,
        viewportMs: 0...50_000
    )
    .frame(width: 480, height: 280)
}
