// Rendering/Widgets/EmpowerRadarWidget.swift v1.0.0
/**
 * NK Empower Oarlock biomechanical radar (spider) chart widget.
 *
 * Renders 6 key per-stroke biomechanical metrics as a radar chart
 * normalized to a reference baseline. Metric values come from
 * PerStrokeStat.metrics (dynamic dict) indexed by NK Empower metric IDs.
 *
 * Displayed metrics:
 *   - mech_ext_ps_force_avg  (average force, N)
 *   - mech_ext_ps_force_max  (peak force, N)
 *   - mech_ext_ps_work       (work per stroke, J)
 *   - mech_ext_ps_angle_catch (catch angle, deg)
 *   - mech_ext_ps_angle_finish (finish angle, deg)
 *   - mech_ext_ps_slip       (slip angle, deg — inverted: less = better)
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 6: Canvas & Widgets).
 */

import SwiftUI

/// Radar/spider chart for NK Empower per-stroke biomechanical metrics.
///
/// Each axis is normalized 0→1 relative to a configurable reference.
/// The current stroke (at playhead) is shown in accent color; optional
/// session average overlay shown in gray.
///
/// Falls back to a "No Empower Data" placeholder when no metrics are present.
public struct EmpowerRadarWidget: View {

    /// Radar axis definition: label, metric key, reference maximum value.
    public struct Axis: Identifiable {
        public let id = UUID()
        public let label: String
        public let key: String
        public let referenceMax: Double
        public let inverted: Bool  // true = lower is better (e.g. slip)

        public init(label: String, key: String, referenceMax: Double, inverted: Bool = false) {
            self.label = label
            self.key = key
            self.referenceMax = referenceMax
            self.inverted = inverted
        }
    }

    let fusionResult: FusionResult?
    @ObservedObject var playheadController: PlayheadController
    let axes: [Axis]

    /// Convenience init for canvas factory — computes active stroke from fusionResult + playhead.
    public init(
        currentStroke: PerStrokeStat?,
        averageMetrics: [String: Double],
        fusionResult: FusionResult?,
        playheadController: PlayheadController,
        axes: [Axis] = Self.defaultAxes
    ) {
        self.fusionResult = fusionResult
        self.playheadController = playheadController
        self.axes = axes
    }

    private var currentStroke: PerStrokeStat? {
        guard let r = fusionResult else { return nil }
        let playheadMs = playheadController.currentTimeMs
        return r.perStrokeStats.last(where: { stat in
            guard let stroke = r.strokes.first(where: { $0.index == stat.strokeIndex }) else { return false }
            return stroke.startTime * 1000 <= playheadMs
        })
    }

    private var averageMetrics: [String: Double] {
        guard let r = fusionResult else { return [:] }
        var sums = [String: Double](); var counts = [String: Int]()
        for stat in r.perStrokeStats {
            for (k, v) in stat.metrics {
                sums[k, default: 0] += v; counts[k, default: 0] += 1
            }
        }
        return sums.reduce(into: [String: Double]()) { acc, pair in
            acc[pair.key] = pair.value / Double(counts[pair.key] ?? 1)
        }
    }

    /// Default NK Empower axes with rowing-typical reference maxima.
    public static let defaultAxes: [Axis] = [
        Axis(label: "Avg Force",    key: "mech_ext_ps_force_avg",    referenceMax: 300),
        Axis(label: "Peak Force",   key: "mech_ext_ps_force_max",    referenceMax: 500),
        Axis(label: "Work",         key: "mech_ext_ps_work",         referenceMax: 600),
        Axis(label: "Catch Angle",  key: "mech_ext_ps_angle_catch",  referenceMax: 75),
        Axis(label: "Finish Angle", key: "mech_ext_ps_angle_finish", referenceMax: 45),
        Axis(label: "Slip",         key: "mech_ext_ps_slip",         referenceMax: 15,  inverted: true),
    ]

    private var hasData: Bool {
        currentStroke != nil || !averageMetrics.isEmpty
    }

    public var body: some View {
        if hasData {
            radarView
        } else {
            noDataPlaceholder
        }
    }

    // MARK: - Radar

    private var radarView: some View {
        GeometryReader { geo in
            let size = geo.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.38

            Canvas { context, canvasSize in
                let n = axes.count
                guard n >= 3 else { return }

                // Background rings
                for ring in [0.25, 0.5, 0.75, 1.0] {
                    let ringPath = polygonPath(n: n, center: center, radius: radius * ring)
                    context.stroke(ringPath, with: .color(.gray.opacity(0.15)), lineWidth: 0.5)
                }

                // Axis spokes
                for i in 0..<n {
                    let angle = axisAngle(index: i, total: n)
                    let tip = CGPoint(
                        x: center.x + radius * cos(angle),
                        y: center.y + radius * sin(angle)
                    )
                    var spoke = Path()
                    spoke.move(to: center)
                    spoke.addLine(to: tip)
                    context.stroke(spoke, with: .color(.gray.opacity(0.2)), lineWidth: 0.5)
                }

                // Average polygon (gray fill)
                if !averageMetrics.isEmpty {
                    let avgValues = axes.map { axis -> Double in
                        let v = averageMetrics[axis.key] ?? 0
                        return normalizedValue(v, axis: axis)
                    }
                    let avgPath = dataPolygon(values: avgValues, n: n, center: center, radius: radius)
                    context.fill(avgPath, with: .color(.gray.opacity(0.12)))
                    context.stroke(avgPath, with: .color(.gray.opacity(0.5)), lineWidth: 1)
                }

                // Current stroke polygon (accent fill)
                if let stroke = currentStroke {
                    let currValues = axes.map { axis -> Double in
                        let v = stroke.metrics[axis.key] ?? 0
                        return normalizedValue(v, axis: axis)
                    }
                    let currPath = dataPolygon(values: currValues, n: n, center: center, radius: radius)
                    context.fill(currPath, with: .color(.accentColor.opacity(0.25)))
                    context.stroke(currPath, with: .color(.accentColor), lineWidth: 2)
                }
            }
            .overlay {
                axisLabels(center: center, radius: radius, size: size)
            }
        }
    }

    // MARK: - Geometry helpers

    private func axisAngle(index: Int, total: Int) -> Double {
        // Start at top (−π/2), distribute evenly clockwise
        return (Double(index) / Double(total)) * 2 * .pi - .pi / 2
    }

    private func polygonPath(n: Int, center: CGPoint, radius: Double) -> Path {
        var path = Path()
        for i in 0..<n {
            let angle = axisAngle(index: i, total: n)
            let pt = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            if i == 0 { path.move(to: pt) }
            else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }

    private func dataPolygon(values: [Double], n: Int, center: CGPoint, radius: Double) -> Path {
        var path = Path()
        for i in 0..<n {
            let angle = axisAngle(index: i, total: n)
            let r = radius * max(0, min(1, values[i]))
            let pt = CGPoint(
                x: center.x + r * cos(angle),
                y: center.y + r * sin(angle)
            )
            if i == 0 { path.move(to: pt) }
            else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }

    private func normalizedValue(_ v: Double, axis: Axis) -> Double {
        let n = v / axis.referenceMax
        return axis.inverted ? max(0, 1 - n) : max(0, min(1, n))
    }

    // MARK: - Axis labels

    @ViewBuilder
    private func axisLabels(center: CGPoint, radius: Double, size: CGSize) -> some View {
        let n = axes.count
        let labelRadius = radius + 22

        ZStack {
            ForEach(Array(axes.enumerated()), id: \.offset) { i, axis in
                let angle = axisAngle(index: i, total: n)
                let x = center.x + labelRadius * cos(angle)
                let y = center.y + labelRadius * sin(angle)

                Text(axis.label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize()
                    .position(x: x, y: y)
            }
        }
    }

    // MARK: - No data placeholder

    private var noDataPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No Empower Data")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Import NK Empower CSV to enable biomechanical analysis")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.05))
    }
}

#Preview {
    let stroke = PerStrokeStat(
        strokeIndex: 5,
        duration: 2.4,
        strokeRate: 24.0,
        metrics: [
            "mech_ext_ps_force_avg":    210,
            "mech_ext_ps_force_max":    380,
            "mech_ext_ps_work":         420,
            "mech_ext_ps_angle_catch":  62,
            "mech_ext_ps_angle_finish": 38,
            "mech_ext_ps_slip":         6.5
        ]
    )
    let avg: [String: Double] = [
        "mech_ext_ps_force_avg":    190,
        "mech_ext_ps_force_max":    350,
        "mech_ext_ps_work":         390,
        "mech_ext_ps_angle_catch":  58,
        "mech_ext_ps_angle_finish": 35,
        "mech_ext_ps_slip":         8.0
    ]

    let pc = PlayheadController()
    EmpowerRadarWidget(currentStroke: stroke, averageMetrics: avg, fusionResult: nil, playheadController: pc)
        .frame(width: 320, height: 320)
        .background(Color(nsColor: .windowBackgroundColor))
}
