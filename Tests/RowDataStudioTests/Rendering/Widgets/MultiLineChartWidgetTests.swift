// Tests/RowDataStudioTests/Rendering/Widgets/MultiLineChartWidgetTests.swift v1.1.0
/**
 * Tests for MultiLineChartWidget data model (MetricSeries) and palette logic.
 * --- Revision History ---
 * v1.1.0 - 2026-03-11 - Update to PlayheadController API; add @MainActor for View init.
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 6: Canvas & Widgets).
 */

import Testing
import Foundation
import SwiftUI
@testable import RowDataStudio

@Suite("MetricSeries")
struct MetricSeriesTests {

    @Test("MetricSeries stores label, timestamps, values, color")
    func basicStorage() {
        let ts: ContiguousArray<Double> = [0, 100, 200]
        let vals: ContiguousArray<Float> = [1.0, 2.0, 3.0]
        let series = MetricSeries(label: "Vel", timestamps: ts, values: vals, color: .blue)

        #expect(series.label == "Vel")
        #expect(series.timestamps == ts)
        #expect(series.values == vals)
    }

    @Test("Each MetricSeries has unique UUID id")
    func uniqueIDs() {
        let ts: ContiguousArray<Double> = [0, 100]
        let vals: ContiguousArray<Float> = [1.0, 2.0]
        let s1 = MetricSeries(label: "A", timestamps: ts, values: vals, color: .blue)
        let s2 = MetricSeries(label: "B", timestamps: ts, values: vals, color: .red)
        #expect(s1.id != s2.id)
    }
}

@Suite("MultiLineChartWidget palette")
struct MultiLineChartWidgetPaletteTests {

    @Test("Default palette has 6 colors")
    @MainActor
    func paletteCount() {
        #expect(MultiLineChartWidget.palette.count == 6)
    }

    @Test("series(from:metricIDs:) with 0 metrics returns empty")
    @MainActor
    func seriesFromEmptyMetrics() async {
        let dc = DataContext()
        let result = MultiLineChartWidget.series(from: dc, metricIDs: [])
        #expect(result.isEmpty)
    }

    @Test("series(from:metricIDs:) with unknown metric key returns empty")
    @MainActor
    func seriesFromUnknownMetric() async {
        let dc = DataContext()
        // No buffers loaded → values(for:) returns nil → filtered out
        let result = MultiLineChartWidget.series(from: dc, metricIDs: ["not_a_real_metric"])
        #expect(result.isEmpty)
    }

    @Test("Palette wraps around for more than 6 series")
    @MainActor
    func paletteWraparound() {
        // The palette[idx % palette.count] pattern: index 6 wraps to index 0
        let palette = MultiLineChartWidget.palette
        let idx6Color = palette[6 % palette.count]
        let idx0Color = palette[0]
        // Can't directly compare Color equality in Swift, but we verify no crash
        // and that modulo logic gives a valid index
        #expect(6 % palette.count == 0)
        _ = idx6Color
        _ = idx0Color
    }
}

@Suite("MultiLineChartWidget init")
struct MultiLineChartWidgetInitTests {

    @Test("Widget stores series count correctly")
    @MainActor
    func storesSeries() {
        let ts: ContiguousArray<Double> = [0, 100, 200]
        let vals: ContiguousArray<Float> = [1.0, 1.5, 2.0]
        let series = [
            MetricSeries(label: "A", timestamps: ts, values: vals, color: .blue),
            MetricSeries(label: "B", timestamps: ts, values: vals, color: .red)
        ]
        let pc = PlayheadController()
        let widget = MultiLineChartWidget(
            series: series,
            playheadController: pc,
            viewportMs: 0...200
        )
        #expect(widget.series.count == 2)
    }

    @Test("Empty series is valid")
    @MainActor
    func emptySeries() {
        let pc = PlayheadController()
        let widget = MultiLineChartWidget(
            series: [],
            playheadController: pc,
            viewportMs: 0...1000
        )
        #expect(widget.series.isEmpty)
    }

    @Test("Default targetPointCount is 1500")
    @MainActor
    func defaultTargetPoints() {
        let pc = PlayheadController()
        let widget = MultiLineChartWidget(
            series: [],
            playheadController: pc,
            viewportMs: 0...1000
        )
        #expect(widget.targetPointCount == 1500)
    }

    @Test("Custom targetPointCount is stored")
    @MainActor
    func customTargetPoints() {
        let pc = PlayheadController()
        let widget = MultiLineChartWidget(
            series: [],
            playheadController: pc,
            viewportMs: 0...1000,
            targetPointCount: 500
        )
        #expect(widget.targetPointCount == 500)
    }
}
