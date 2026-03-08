// Rendering/Widgets/MultiLineChartWidget.swift v1.0.0
/**
 * Multi-series line chart widget for metric overlay comparison.
 *
 * Renders up to 6 metric channels simultaneously on a shared Y-axis
 * using distinct colors. Each series passes through the MVP pipeline
 * (ViewportCull → LTTB → AdaptiveSmooth) independently.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 6: Canvas & Widgets).
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
///
/// All series share the same X-axis (time) and a globally-fitted Y-axis
/// so relative amplitudes are comparable. Each series is downsampled
/// independently via LTTB to prevent rendering overload.
///
/// Usage:
/// ```swift
/// MultiLineChartWidget(
///     series: [
///         MetricSeries(label: "Velocity", timestamps: ts, values: vel, color: .blue),
///         MetricSeries(label: "HR",       timestamps: ts, values: hr,  color: .red),
///     ],
///     playheadTimeMs: playheadController.currentTimeMs,
///     viewportMs: 0...sessionDurationMs
/// )
/// ```
public struct MultiLineChartWidget: View {

    let series: [MetricSeries]
    let playheadTimeMs: Double
    let viewportMs: ClosedRange<Double>
    var targetPointCount: Int = 1500

    public init(
        series: [MetricSeries],
        playheadTimeMs: Double,
        viewportMs: ClosedRange<Double>,
        targetPointCount: Int = 1500
    ) {
        self.series = series
        self.playheadTimeMs = playheadTimeMs
        self.viewportMs = viewportMs
        self.targetPointCount = targetPointCount
    }

    public var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let pipeline = TransformPipeline.mvp(
                viewportMs: viewportMs,
                targetCount: targetPointCount,
                pointsPerPixel: pointsPerPixel(width: size.width)
            )

            // Compute per-series display data
            let displaySeries: [(series: MetricSeries,
                                 ts: ContiguousArray<Double>,
                                 vals: ContiguousArray<Float>)] = series.map { s in
                let (ts, vals) = pipeline.apply(timestamps: s.timestamps, values: s.values)
                return (s, ts, vals)
            }

            // Global Y range across all series for shared axis
            let (yMin, yMax) = globalYRange(displaySeries.map(\.vals))
            let ySpan = max(yMax - yMin, Float(1e-4))

            ZStack(alignment: .bottom) {
                Canvas { context, canvasSize in
                    // Per-series lines
                    for item in displaySeries {
                        var path = Path()
                        var movePending = true

                        for i in 0..<min(item.ts.count, item.vals.count) {
                            let v = item.vals[i]
                            guard !v.isNaN else { movePending = true; continue }
                            let x = xPos(t: item.ts[i], width: canvasSize.width)
                            let y = yPos(v: v, yMin: yMin, ySpan: ySpan, height: canvasSize.height)
                            let pt = CGPoint(x: x, y: y)
                            if movePending { path.move(to: pt); movePending = false }
                            else { path.addLine(to: pt) }
                        }

                        context.stroke(
                            path,
                            with: .color(item.series.color),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                        )
                    }

                    // Playhead
                    let px = xPos(t: playheadTimeMs, width: canvasSize.width)
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
                }
                .overlay(alignment: .topLeading) {
                    axisLabels(yMin: yMin, yMax: yMax)
                }

                // Legend strip
                if !series.isEmpty {
                    legendStrip
                }
            }
        }
        .drawingGroup()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Legend

    private var legendStrip: some View {
        HStack(spacing: 12) {
            ForEach(series) { s in
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(s.color)
                        .frame(width: 14, height: 2)
                    Text(s.label)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.gray.opacity(0.06))
        .cornerRadius(4)
        .padding(.bottom, 4)
    }

    // MARK: - Axis labels

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

    // MARK: - Helpers

    private func pointsPerPixel(width: CGFloat) -> Double {
        guard width > 0, let first = series.first, !first.timestamps.isEmpty else { return 1 }
        return Double(first.timestamps.count) / Double(width)
    }

    private func xPos(t: Double, width: CGFloat) -> CGFloat {
        let span = viewportMs.upperBound - viewportMs.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat((t - viewportMs.lowerBound) / span) * width
    }

    private func yPos(v: Float, yMin: Float, ySpan: Float, height: CGFloat) -> CGFloat {
        let normalized = Double((v - yMin) / ySpan)
        return CGFloat(1.0 - normalized) * height
    }

    private func globalYRange(_ allVals: [ContiguousArray<Float>]) -> (Float, Float) {
        var mn = Float.infinity
        var mx = -Float.infinity
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

    private func formatValue(_ v: Float) -> String {
        if abs(v) >= 100 { return String(format: "%.0f", v) }
        if abs(v) >= 10  { return String(format: "%.1f", v) }
        return String(format: "%.2f", v)
    }
}

// MARK: - Default palette

public extension MultiLineChartWidget {
    /// Standard color palette for up to 6 overlaid metrics.
    static let palette: [Color] = [.blue, .red, .green, .orange, .purple, .teal]

    /// Convenience: build series from DataContext metric keys with auto-assigned colors.
    static func series(
        from dataContext: DataContext,
        metricIDs: [String]
    ) -> [MetricSeries] {
        let ts = dataContext.timestamps ?? []
        return metricIDs.enumerated().compactMap { idx, key in
            guard let vals = dataContext.values(for: key) else { return nil }
            return MetricSeries(
                label: key.components(separatedBy: "_").last ?? key,
                timestamps: ts,
                values: vals,
                color: palette[idx % palette.count]
            )
        }
    }
}

#Preview {
    let n = 500
    let ts: ContiguousArray<Double> = ContiguousArray((0..<n).map { Double($0) * 100 })
    let vel: ContiguousArray<Float> = ContiguousArray((0..<n).map { Float.init(sin(Double($0) * 0.05)) * 2 + 4 })
    let hr:  ContiguousArray<Float> = ContiguousArray((0..<n).map { Float.init(cos(Double($0) * 0.03)) * 5 + 145 })

    return MultiLineChartWidget(
        series: [
            MetricSeries(label: "Velocity", timestamps: ts, values: vel, color: .blue),
            MetricSeries(label: "HR",       timestamps: ts, values: hr,  color: .red)
        ],
        playheadTimeMs: 15_000,
        viewportMs: 0...50_000
    )
    .frame(width: 480, height: 280)
}
