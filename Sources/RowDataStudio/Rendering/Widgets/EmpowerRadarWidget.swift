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
    /// Plain `let` — NOT @ObservedObject. Only child proxy observes the playhead.
    let playheadController: PlayheadController
    let axes: [Axis]

    public init(
        fusionResult: FusionResult?,
        playheadController: PlayheadController,
        axes: [Axis] = Self.defaultAxes
    ) {
        self.fusionResult = fusionResult
        self.playheadController = playheadController
        self.axes = axes
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

    public var body: some View {
        EmpowerPlayheadProxy(
            fusionResult: fusionResult,
            playheadController: playheadController,
            axes: axes
        )
    }
}

// MARK: - EmpowerPlayheadProxy (60fps child)

/// Only this struct subscribes to PlayheadController — the heavy radar Canvas
/// and geometry calculations are isolated here at an appropriate granularity.
///
/// **Perf note:**
/// - `averageMetrics` is session-wide; cached in @State, computed once off-thread.
/// - Stroke lookup uses a pre-sorted array + binary search O(log n) instead of O(n²).
private struct EmpowerPlayheadProxy: View {
    typealias Axis = EmpowerRadarWidget.Axis

    let fusionResult: FusionResult?
    @ObservedObject var playheadController: PlayheadController
    let axes: [Axis]

    /// Session-wide averages — computed once when fusionResult changes, never per-frame.
    @State private var cachedAverages: [String: Double] = [:]
    /// Strokes sorted by startTimeMs for O(log n) binary search.
    @State private var sortedStrokes: [(startMs: Double, stat: PerStrokeStat)] = []

    /// Cache key: invalidated only when fusionResult content changes.
    private var fusionKey: String {
        guard let r = fusionResult else { return "nil" }
        return "\(r.perStrokeStats.count):\(r.strokes.count)"
    }

    /// O(log n) binary search for current stroke at playhead position.
    private var currentStroke: PerStrokeStat? {
        guard !sortedStrokes.isEmpty else { return nil }
        let t = playheadController.currentTimeMs
        var lo = 0, hi = sortedStrokes.count - 1
        var result: PerStrokeStat? = nil
        while lo <= hi {
            let mid = (lo + hi) / 2
            if sortedStrokes[mid].startMs <= t {
                result = sortedStrokes[mid].stat
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return result
    }

    var body: some View {
        Group {
            if currentStroke != nil || !cachedAverages.isEmpty {
                radarCanvas
            } else {
                noDataPlaceholder
            }
        }
        // Re-run only when fusionResult changes — NOT on every playhead tick.
        .task(id: fusionKey) {
            let r = fusionResult
            let result = await Task.detached(priority: .userInitiated) { () -> ([String: Double], [(Double, PerStrokeStat)]) in
                guard let r else { return ([:], []) }
                // 1. Build index: strokeIndex → startTimeMs
                var startByIndex = [Int: Double]()
                startByIndex.reserveCapacity(r.strokes.count)
                for s in r.strokes { startByIndex[s.index] = s.startTime * 1000 }
                // 2. Sort perStrokeStats by startTime for binary search
                let sorted: [(Double, PerStrokeStat)] = r.perStrokeStats
                    .compactMap { stat -> (Double, PerStrokeStat)? in
                        guard let t = startByIndex[stat.strokeIndex] else { return nil }
                        return (t, stat)
                    }
                    .sorted { $0.0 < $1.0 }
                // 3. Compute session averages (O(n), done once)
                var sums = [String: Double](); var counts = [String: Int]()
                for stat in r.perStrokeStats {
                    for (k, v) in stat.metrics { sums[k, default: 0] += v; counts[k, default: 0] += 1 }
                }
                let avgs = sums.reduce(into: [String: Double]()) { acc, pair in
                    acc[pair.key] = pair.value / Double(counts[pair.key] ?? 1)
                }
                return (avgs, sorted)
            }.value
            guard !Task.isCancelled else { return }
            cachedAverages = result.0
            sortedStrokes  = result.1.map { ($0.0, $0.1) }
        }
    }

    // MARK: - Radar

    fileprivate var radarCanvas: some View {
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

                // Average polygon (gray fill — uses session-wide cache, never recomputed per-frame)
                if !cachedAverages.isEmpty {
                    let avgValues = axes.map { axis -> Double in
                        let v = cachedAverages[axis.key] ?? 0
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
    let pc = PlayheadController()
    EmpowerRadarWidget(fusionResult: nil, playheadController: pc)
        .frame(width: 320, height: 320)
        .background(Color(nsColor: .windowBackgroundColor))
}
