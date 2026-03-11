// Rendering/Widgets/StrokeTableWidget.swift v1.0.0
/**
 * Per-stroke statistics table widget.
 *
 * Displays FusionResult.perStrokeStats as a virtualized scrollable table
 * with columns: #, Rate, Distance, AvgVel, PeakVel, HR.
 * Highlights the row corresponding to the current playhead position.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 6: Canvas & Widgets).
 */

import SwiftUI

/// Scrollable per-stroke statistics table.
///
/// Reads `FusionResult.perStrokeStats` from `DataContext` and renders a
/// compact table. The active stroke row (based on playhead time) is
/// highlighted in accent color.
///
/// Column layout (fixed widths, monospaced values):
/// ```
/// #   | Rate  | Dist  | AvgV  | PeakV | HR
/// 001 | 24.1  | 8.2m  | 3.41  | 4.12  | 142
/// ```
public struct StrokeTableWidget: View {

    let strokes: [PerStrokeStat]
    @ObservedObject var playheadController: PlayheadController
    /// Parallel array: stroke start times in ms (from StrokeEvent), used for row highlighting.
    let strokeStartTimesMs: [Double]

    public init(
        strokes: [PerStrokeStat],
        playheadController: PlayheadController,
        strokeStartTimesMs: [Double]
    ) {
        self.strokes = strokes
        self.playheadController = playheadController
        self.strokeStartTimesMs = strokeStartTimesMs
    }

    private var activeIndex: Int? {
        guard !strokeStartTimesMs.isEmpty else { return nil }
        let playheadMs = playheadController.currentTimeMs
        // Find last stroke that started before or at playhead
        var result: Int? = nil
        for (i, t) in strokeStartTimesMs.enumerated() {
            if t <= playheadMs { result = i }
            else { break }
        }
        return result
    }

    public var body: some View {
        VStack(spacing: 0) {
            tableHeader
            Divider()
            if strokes.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: []) {
                            ForEach(Array(strokes.enumerated()), id: \.offset) { idx, stat in
                                tableRow(stat, index: idx, isActive: activeIndex == idx)
                                    .id(idx)
                                Divider().opacity(0.5)
                            }
                        }
                    }
                    .onChange(of: activeIndex) { newIdx in
                        if let i = newIdx {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(i, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var tableHeader: some View {
        HStack(spacing: 0) {
            headerCell("#",      width: 36)
            headerCell("Rate",   width: 52)
            headerCell("Dist",   width: 52)
            headerCell("AvgV",   width: 52)
            headerCell("PeakV",  width: 52)
            headerCell("HR",     width: 44)
        }
        .padding(.vertical, 5)
        .background(Color.gray.opacity(0.10))
    }

    private func headerCell(_ label: String, width: CGFloat) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .trailing)
            .padding(.trailing, 6)
    }

    // MARK: - Row

    private func tableRow(_ stat: PerStrokeStat, index: Int, isActive: Bool) -> some View {
        HStack(spacing: 0) {
            dataCell(String(format: "%03d", stat.strokeIndex + 1), width: 36, mono: true)
            dataCell(formatRate(stat.strokeRate),                   width: 52, mono: true)
            dataCell(formatDist(stat.distance),                     width: 52, mono: true)
            dataCell(formatVel(stat.avgVelocity),                   width: 52, mono: true)
            dataCell(formatVel(stat.peakVelocity),                  width: 52, mono: true)
            dataCell(formatHR(stat.avgHR),                          width: 44, mono: true)
        }
        .padding(.vertical, 4)
        .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
    }

    private func dataCell(_ value: String, width: CGFloat, mono: Bool) -> some View {
        Text(value)
            .font(mono ? .system(size: 11, design: .monospaced) : .system(size: 11))
            .foregroundStyle(.primary)
            .frame(width: width, alignment: .trailing)
            .padding(.trailing, 6)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tablecells.badge.ellipsis")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("No strokes detected")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Formatters

    private func formatRate(_ spm: Double) -> String {
        String(format: "%.1f", spm)
    }

    private func formatDist(_ d: Double?) -> String {
        guard let d else { return "--" }
        return String(format: "%.1fm", d)
    }

    private func formatVel(_ v: Double?) -> String {
        guard let v else { return "--" }
        return String(format: "%.2f", v)
    }

    private func formatHR(_ hr: Double?) -> String {
        guard let hr else { return "--" }
        return String(format: "%.0f", hr)
    }
}

#Preview {
    let strokes: [PerStrokeStat] = (0..<20).map { i in
        PerStrokeStat(
            strokeIndex: i,
            duration: 2.4 + Double.random(in: -0.3...0.3),
            strokeRate: 24.0 + Double.random(in: -1...1),
            distance: 8.1 + Double.random(in: -0.5...0.5),
            avgVelocity: 3.4 + Double.random(in: -0.2...0.2),
            peakVelocity: 4.1 + Double.random(in: -0.3...0.3),
            avgHR: 142 + Double.random(in: -5...5)
        )
    }
    let startTimes = (0..<20).map { Double($0) * 2500.0 }

    let pc = PlayheadController()
    StrokeTableWidget(
        strokes: strokes,
        playheadController: pc,
        strokeStartTimesMs: startTimes
    )
    .frame(width: 300, height: 360)
    .background(Color(nsColor: .windowBackgroundColor))
}
