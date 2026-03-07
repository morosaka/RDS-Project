// Rendering/Widgets/LineChartWidget.swift v1.0.0
/**
 * SwiftUI Canvas line chart with transform pipeline and playhead cursor.
 * Renders 200Hz sensor data efficiently via LTTB downsampling + Metal (.drawingGroup).
 * --- Revision History ---
 * v1.0.0 - 2026-03-07 - Initial implementation (Phase 4: Rendering + MVP).
 */

import SwiftUI

/// Line chart widget for displaying a single sensor metric over time.
///
/// **Rendering pipeline (applied per-frame internally):**
/// `ViewportCull → LTTB(2000pt) → AdaptiveSmooth → Canvas path`
///
/// `.drawingGroup()` routes the Canvas through Metal automatically,
/// enabling smooth rendering of dense 200Hz data at 60fps.
///
/// **Playhead cursor:** A thin vertical line at `playheadTimeMs`, updated
/// every frame by `PlayheadController` via CVDisplayLink.
///
/// Source: `docs/architecture/visualization.md` §LineChartWidget
public struct LineChartWidget: View {

    /// Full timestamp array in milliseconds (from `SensorDataBuffers.timestamp`).
    let timestamps: ContiguousArray<Double>
    /// Full value array (parallel to timestamps; NaN = missing data).
    let values: ContiguousArray<Float>
    /// Current playhead position in milliseconds.
    let playheadTimeMs: Double
    /// Visible time range in milliseconds.
    let viewportMs: ClosedRange<Double>
    /// Maximum display points after LTTB. Default: 2000.
    var targetPointCount: Int = 2000

    public init(
        timestamps: ContiguousArray<Double>,
        values: ContiguousArray<Float>,
        playheadTimeMs: Double,
        viewportMs: ClosedRange<Double>,
        targetPointCount: Int = 2000
    ) {
        self.timestamps = timestamps
        self.values = values
        self.playheadTimeMs = playheadTimeMs
        self.viewportMs = viewportMs
        self.targetPointCount = targetPointCount
    }

    public var body: some View {
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
                // MARK: Line path
                var path = Path()
                var movePending = true

                for i in 0..<min(displayTs.count, displayVals.count) {
                    let v = displayVals[i]
                    guard !v.isNaN else {
                        movePending = true
                        continue
                    }
                    let x = xPosition(t: displayTs[i], width: canvasSize.width)
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

                // MARK: Playhead cursor
                let px = xPosition(t: playheadTimeMs, width: canvasSize.width)
                if px >= 0, px <= canvasSize.width {
                    var cursor = Path()
                    cursor.move(to: CGPoint(x: px, y: 0))
                    cursor.addLine(to: CGPoint(x: px, y: canvasSize.height))
                    context.stroke(
                        cursor,
                        with: .color(.red.opacity(0.8)),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
                }

                // MARK: Y-axis zero line (if zero is in range)
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
        .drawingGroup()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Helpers

    private func pointsPerPixel(width: CGFloat) -> Double {
        guard width > 0 else { return 1 }
        return Double(timestamps.count) / Double(width)
    }

    private func xPosition(t: Double, width: CGFloat) -> CGFloat {
        let span = viewportMs.upperBound - viewportMs.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat((t - viewportMs.lowerBound) / span) * width
    }

    private func yPosition(v: Float, yMin: Float, ySpan: Float, height: CGFloat) -> CGFloat {
        // Flip: high values at top (small y)
        let normalized = Double((v - yMin) / ySpan)
        return CGFloat(1.0 - normalized) * height
    }

    /// Computes (min, max) from non-NaN values with a small padding margin.
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

    private func formatValue(_ v: Float) -> String {
        if abs(v) >= 100 { return String(format: "%.0f", v) }
        if abs(v) >= 10  { return String(format: "%.1f", v) }
        return String(format: "%.2f", v)
    }
}
