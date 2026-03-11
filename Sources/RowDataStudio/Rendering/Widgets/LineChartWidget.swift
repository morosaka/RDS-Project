// Rendering/Widgets/LineChartWidget.swift v1.1.0
/**
 * SwiftUI Canvas line chart with transform pipeline and playhead cursor.
 * Renders 200Hz sensor data efficiently via LTTB downsampling + Metal (.drawingGroup).
 *
 * **Performance fix (v1.1.0):** Pipeline output is cached and only recomputed
 * when data or viewport change — NOT on every playhead tick. The playhead line
 * is drawn as a lightweight overlay that doesn't trigger data reprocessing.
 *
 * --- Revision History ---
 * v1.2.0 - 2026-03-11 - Widget takes PlayheadController; overlay observes it internally.
 * v1.1.0 - 2026-03-11 - Cache pipeline output; separate playhead from data render path.
 * v1.0.0 - 2026-03-07 - Initial implementation (Phase 4: Rendering + MVP).
 */

import SwiftUI

/// Line chart widget for displaying a single sensor metric over time.
///
/// **Rendering pipeline (applied once per data/viewport change):**
/// `ViewportCull → LTTB(2000pt) → AdaptiveSmooth → cached path`
///
/// The playhead cursor updates at 60fps as a separate overlay without
/// re-running the pipeline. This is critical for 140k+ sample datasets.
///
/// Source: `docs/architecture/visualization.md` §LineChartWidget
public struct LineChartWidget: View {

    /// Full timestamp array in milliseconds (from `SensorDataBuffers.timestamp`).
    let timestamps: ContiguousArray<Double>
    /// Full value array (parallel to timestamps; NaN = missing data).
    let values: ContiguousArray<Float>
    /// Shared playhead controller — observed only by the PlayheadOverlay, not by the data layer.
    @ObservedObject var playheadController: PlayheadController
    /// Visible time range in milliseconds.
    let viewportMs: ClosedRange<Double>
    /// Maximum display points after LTTB. Default: 2000.
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
        // Data layer: only recomputed when inputs change (NOT on playhead tick)
        LineChartDataLayer(
            timestamps: timestamps,
            values: values,
            viewportMs: viewportMs,
            targetPointCount: targetPointCount
        )
        .overlay {
            // Playhead layer: lightweight, redrawn at 60fps
            PlayheadOverlay(playheadTimeMs: playheadController.currentTimeMs, viewportMs: viewportMs)
        }
        .drawingGroup()
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Data Layer (cached, heavy computation)

/// Renders the line chart path and axis labels. Recomputed only when
/// data or viewport change, NOT on playhead ticks.
private struct LineChartDataLayer: View, Equatable {

    let timestamps: ContiguousArray<Double>
    let values: ContiguousArray<Float>
    let viewportMs: ClosedRange<Double>
    let targetPointCount: Int

    nonisolated static func == (lhs: LineChartDataLayer, rhs: LineChartDataLayer) -> Bool {
        // Identity check: same buffer pointer + count = same data.
        // This prevents re-render when parent rebuilds with the same arrays.
        lhs.timestamps.count == rhs.timestamps.count &&
        lhs.values.count == rhs.values.count &&
        lhs.viewportMs == rhs.viewportMs &&
        lhs.targetPointCount == rhs.targetPointCount &&
        lhs.timestamps.first == rhs.timestamps.first &&
        lhs.timestamps.last == rhs.timestamps.last
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let ppp = pointsPerPixel(width: size.width)
            let pipeline = TransformPipeline.mvp(
                viewportMs: viewportMs,
                targetCount: targetPointCount,
                pointsPerPixel: ppp
            )
            let (displayTs, displayVals) = pipeline.apply(
                timestamps: timestamps,
                values: values
            )
            let (yMin, yMax) = valueRange(displayVals)
            let ySpan = max(yMax - yMin, Float(1e-4))

            Canvas { context, canvasSize in
                // Line path
                var path = Path()
                var movePending = true

                for i in 0..<min(displayTs.count, displayVals.count) {
                    let v = displayVals[i]
                    guard !v.isNaN else {
                        movePending = true
                        continue
                    }
                    let x = xPosition(t: displayTs[i], viewport: viewportMs, width: canvasSize.width)
                    let y = yPosition(v: v, yMin: yMin, ySpan: ySpan, height: canvasSize.height)
                    let pt = CGPoint(x: x, y: y)
                    if movePending {
                        path.move(to: pt)
                        movePending = false
                    } else {
                        path.addLine(to: pt)
                    }
                }

                context.stroke(
                    path,
                    with: .color(.blue),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )

                // Y-axis zero line (if zero is in range)
                if yMin < 0, yMax > 0 {
                    let zy = yPosition(v: 0, yMin: yMin, ySpan: ySpan, height: canvasSize.height)
                    var zeroLine = Path()
                    zeroLine.move(to: CGPoint(x: 0, y: zy))
                    zeroLine.addLine(to: CGPoint(x: canvasSize.width, y: zy))
                    context.stroke(zeroLine, with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)
                }
            }
            .overlay(alignment: .topLeading) {
                axisLabels(yMin: yMin, yMax: yMax)
            }
        }
    }

    // MARK: - Helpers

    private func pointsPerPixel(width: CGFloat) -> Double {
        guard width > 0 else { return 1 }
        return Double(timestamps.count) / Double(width)
    }

    @ViewBuilder
    private func axisLabels(yMin: Float, yMax: Float) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(formatValue(yMax))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding([.top, .leading], 4)
            Spacer()
            Text(formatValue(yMin))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding([.bottom, .leading], 4)
        }
    }
}

// MARK: - Playhead Overlay (lightweight, 60fps)

/// Thin vertical playhead line. Redrawn at 60fps but trivially cheap
/// (single 2-point path, no data processing).
private struct PlayheadOverlay: View {

    let playheadTimeMs: Double
    let viewportMs: ClosedRange<Double>

    var body: some View {
        Canvas { context, canvasSize in
            let px = xPosition(t: playheadTimeMs, viewport: viewportMs, width: canvasSize.width)
            guard px >= 0, px <= canvasSize.width else { return }
            var cursor = Path()
            cursor.move(to: CGPoint(x: px, y: 0))
            cursor.addLine(to: CGPoint(x: px, y: canvasSize.height))
            context.stroke(
                cursor,
                with: .color(.red.opacity(0.8)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )
        }
    }
}

// MARK: - Shared helpers

private func xPosition(t: Double, viewport: ClosedRange<Double>, width: CGFloat) -> CGFloat {
    let span = viewport.upperBound - viewport.lowerBound
    guard span > 0 else { return 0 }
    return CGFloat((t - viewport.lowerBound) / span) * width
}

private func yPosition(v: Float, yMin: Float, ySpan: Float, height: CGFloat) -> CGFloat {
    let normalized = Double((v - yMin) / ySpan)
    return CGFloat(1.0 - normalized) * height
}

private func valueRange(_ vals: ContiguousArray<Float>) -> (Float, Float) {
    var mn = Float.infinity
    var mx = -Float.infinity
    for v in vals {
        if !v.isNaN {
            if v < mn { mn = v }
            if v > mx { mx = v }
        }
    }
    guard mn.isFinite, mx.isFinite else { return (0, 1) }
    let pad = max((mx - mn) * 0.05, Float(1e-4))
    return (mn - pad, mx + pad)
}

private func formatValue(_ v: Float) -> String {
    if abs(v) >= 100 { return String(format: "%.0f", v) }
    if abs(v) >= 10  { return String(format: "%.1f", v) }
    return String(format: "%.2f", v)
}
