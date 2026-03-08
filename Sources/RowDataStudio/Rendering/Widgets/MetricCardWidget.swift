// Rendering/Widgets/MetricCardWidget.swift v1.0.0
/**
 * Compact KPI card widget displaying a single current metric value.
 *
 * Shows the metric value at the current playhead time with label,
 * unit, and optional trend indicator (vs session average).
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-08 - Extracted from RowingDeskCanvas inline implementation (Phase 6).
 */

import SwiftUI

/// Compact KPI card for displaying a single metric at the current playhead.
///
/// Samples `values[sampleIndex]` where `sampleIndex` is derived from
/// `playheadTimeMs` and the array's assumed uniform sample rate.
///
/// **Trend indicator:** compares the current value to the session mean
/// and shows an up/down arrow with percentage difference.
///
/// Usage:
/// ```swift
/// MetricCardWidget(
///     label: "Velocity",
///     unit: "m/s",
///     values: dataContext.values(for: "fus_cal_ts_vel_inertial") ?? [],
///     timestamps: dataContext.timestamps ?? [],
///     playheadTimeMs: playheadController.currentTimeMs
/// )
/// ```
public struct MetricCardWidget: View {

    let label: String
    let unit: String
    let values: ContiguousArray<Float>
    let timestamps: ContiguousArray<Double>
    let playheadTimeMs: Double
    var showTrend: Bool = true

    public init(
        label: String,
        unit: String,
        values: ContiguousArray<Float>,
        timestamps: ContiguousArray<Double>,
        playheadTimeMs: Double,
        showTrend: Bool = true
    ) {
        self.label = label
        self.unit = unit
        self.values = values
        self.timestamps = timestamps
        self.playheadTimeMs = playheadTimeMs
        self.showTrend = showTrend
    }

    private var currentIndex: Int {
        guard !timestamps.isEmpty else { return 0 }
        // Binary-search for nearest timestamp
        var lo = 0, hi = timestamps.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if timestamps[mid] < playheadTimeMs { lo = mid + 1 }
            else { hi = mid }
        }
        return lo
    }

    private var currentValue: Float? {
        guard !values.isEmpty else { return nil }
        let v = values[min(currentIndex, values.count - 1)]
        return v.isNaN ? nil : v
    }

    private var sessionMean: Float? {
        guard !values.isEmpty else { return nil }
        var sum: Float = 0
        var count = 0
        for v in values where !v.isNaN {
            sum += v; count += 1
        }
        guard count > 0 else { return nil }
        return sum / Float(count)
    }

    private var trendPercent: Double? {
        guard showTrend,
              let cur = currentValue,
              let mean = sessionMean,
              mean != 0 else { return nil }
        return Double((cur - mean) / abs(mean)) * 100
    }

    public var body: some View {
        VStack(spacing: 6) {
            // Label
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // Value
            if let v = currentValue {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(formatValue(v))
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("--")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Trend vs mean
            if let trend = trendPercent {
                HStack(spacing: 2) {
                    Image(systemName: trend >= 0 ? "arrow.up" : "arrow.down")
                        .font(.caption2)
                    Text(String(format: "%.1f%%", abs(trend)))
                        .font(.caption2)
                        .monospaced()
                }
                .foregroundStyle(trendColor(trend))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
    }

    // MARK: - Helpers

    private func formatValue(_ v: Float) -> String {
        if abs(v) >= 1000 { return String(format: "%.0f", v) }
        if abs(v) >= 100  { return String(format: "%.1f", v) }
        return String(format: "%.2f", v)
    }

    private func trendColor(_ trend: Double) -> Color {
        // Positive trend = above average = neutral/green for velocity, depends on metric
        // Default: blue for above, dimmed for below
        trend >= 0 ? .blue : .secondary
    }
}

#Preview {
    let ts: ContiguousArray<Double> = ContiguousArray((0..<500).map { Double($0) * 100 })
    let vals: ContiguousArray<Float> = ContiguousArray((0..<500).map { Float.init(sin(Double($0) * 0.05)) * 0.5 + 3.8 })

    return MetricCardWidget(
        label: "Velocity",
        unit: "m/s",
        values: vals,
        timestamps: ts,
        playheadTimeMs: 25_000
    )
    .frame(width: 200, height: 120)
    .background(Color(nsColor: .windowBackgroundColor))
    .cornerRadius(8)
    .shadow(radius: 2)
}
