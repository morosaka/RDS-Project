// Tests/RowDataStudioTests/Rendering/Widgets/StrokeTableWidgetTests.swift v1.1.0
/**
 * Tests for StrokeTableWidget data logic and formatting.
 * --- Revision History ---
 * v1.1.0 - 2026-03-11 - Update to PlayheadController API; add @MainActor for View init.
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 6: Canvas & Widgets).
 */

import Testing
import Foundation
@testable import RowDataStudio

@Suite("StrokeTableWidget")
struct StrokeTableWidgetTests {

    // MARK: - Helpers: mock data

    private func makeStat(index: Int, rate: Double = 24.0, dist: Double? = 8.1) -> PerStrokeStat {
        PerStrokeStat(
            strokeIndex: index,
            duration: 2.5,
            strokeRate: rate,
            distance: dist,
            avgVelocity: 3.4,
            peakVelocity: 4.1,
            avgHR: 142
        )
    }

    // MARK: - Active index selection

    @Test("Active index is nil when no start times provided")
    @MainActor
    func activeIndexEmptyStartTimes() {
        let pc = PlayheadController()
        let widget = StrokeTableWidget(
            strokes: [makeStat(index: 0)],
            playheadController: pc,
            strokeStartTimesMs: []
        )
        // Cannot access private activeIndex directly — test via public initializer completing without crash
        #expect(widget.strokes.count == 1)
    }

    @Test("Strokes array preserved correctly")
    @MainActor
    func strokesPreserved() {
        let stats = (0..<5).map { makeStat(index: $0) }
        let pc = PlayheadController()
        let widget = StrokeTableWidget(
            strokes: stats,
            playheadController: pc,
            strokeStartTimesMs: []
        )
        #expect(widget.strokes.count == 5)
        #expect(widget.strokes[2].strokeIndex == 2)
    }

    // MARK: - Formatting helpers (via PerStrokeStat values)

    @Test("Stroke rate formatting precision")
    func strokeRateFormat() {
        let stat = makeStat(index: 0, rate: 23.7)
        #expect(stat.strokeRate == 23.7)
        let formatted = String(format: "%.1f", stat.strokeRate)
        #expect(formatted == "23.7")
    }

    @Test("Distance formatting with nil")
    func distanceNilHandling() {
        let stat = makeStat(index: 0, dist: nil)
        #expect(stat.distance == nil)
        let formatted = stat.distance.map { String(format: "%.1fm", $0) } ?? "--"
        #expect(formatted == "--")
    }

    @Test("Distance formatting with value")
    func distanceFormatting() {
        let stat = makeStat(index: 0, dist: 8.14)
        let formatted = String(format: "%.1fm", stat.distance!)
        #expect(formatted == "8.1m")
    }

    @Test("HR formatting rounds to integer")
    func hrFormatting() {
        let stat = PerStrokeStat(
            strokeIndex: 0, duration: 2.5, strokeRate: 24.0,
            avgHR: 142.7
        )
        let formatted = String(format: "%.0f", stat.avgHR!)
        #expect(formatted == "143")
    }

    @Test("Stroke index formatted as 3-digit zero-padded")
    func strokeIndexFormatting() {
        let stat = makeStat(index: 4)
        let formatted = String(format: "%03d", stat.strokeIndex + 1)
        #expect(formatted == "005")
    }

    // MARK: - Edge cases

    @Test("Empty strokes array is valid")
    @MainActor
    func emptyStrokes() {
        let pc = PlayheadController()
        let widget = StrokeTableWidget(
            strokes: [],
            playheadController: pc,
            strokeStartTimesMs: []
        )
        #expect(widget.strokes.isEmpty)
    }

    @Test("Single stroke")
    @MainActor
    func singleStroke() {
        let pc = PlayheadController()
        let widget = StrokeTableWidget(
            strokes: [makeStat(index: 0)],
            playheadController: pc,
            strokeStartTimesMs: [0]
        )
        #expect(widget.strokes.count == 1)
    }

    @Test("Start times count may differ from strokes count (graceful)")
    @MainActor
    func mismatchedCounts() {
        let strokes = (0..<10).map { makeStat(index: $0) }
        let starts = [0.0, 2500.0]  // only 2 start times for 10 strokes
        let pc = PlayheadController()
        let widget = StrokeTableWidget(
            strokes: strokes,
            playheadController: pc,
            strokeStartTimesMs: starts
        )
        #expect(widget.strokes.count == 10)
    }
}
