// Tests/RowDataStudioTests/UI/SnapTests.swift v1.0.0
/**
 * Tests for SnapEngine pure magnetic-snap logic.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-13 - Initial implementation (Phase 8b.6: Magnetic Snapping).
 */

import Testing
import CoreGraphics
@testable import RowDataStudio

@Suite struct SnapTests {

    // MARK: - Left-to-left edge snap

    @Test func snapsToNearbyLeftEdge() {
        // Dragging widget left edge at x=105, anchor left edge at x=100 (5pt → within 8pt threshold)
        // They are vertically offset so no overlap risk.
        let dragging = CGRect(x: 105, y: 200, width: 200, height: 100)
        let anchor   = CGRect(x: 100, y: 0,   width: 200, height: 100)
        let (pos, guides) = SnapEngine.snapPosition(dragging: dragging, others: [anchor], threshold: 8)
        #expect(pos.x == 100)          // snapped left edge to anchor left edge
        #expect(!guides.isEmpty)       // at least one guide line emitted
    }

    // MARK: - No snap beyond threshold

    @Test func noSnapBeyondThreshold() {
        // 20pt gap — exceeds threshold of 8pt
        let dragging = CGRect(x: 120, y: 200, width: 200, height: 100)
        let anchor   = CGRect(x: 100, y: 0,   width: 200, height: 100)
        let (pos, guides) = SnapEngine.snapPosition(dragging: dragging, others: [anchor], threshold: 8)
        #expect(pos.x == 120)          // no snap
        #expect(guides.isEmpty)
    }

    // MARK: - Center-X snap

    @Test func snapsToCenterX() {
        // dragging midX = 155+50 = 205, anchor midX = 100+100 = 200 → 5pt gap
        let dragging = CGRect(x: 155, y: 200, width: 100, height: 100)
        let anchor   = CGRect(x: 100, y: 0,   width: 200, height: 100)
        let (pos, guides) = SnapEngine.snapPosition(dragging: dragging, others: [anchor], threshold: 8)
        // snapped: candidateX = 155 + (200 - 205) = 150 → midX = 200
        #expect(pos.x == 150)
        #expect(!guides.isEmpty)
    }

    // MARK: - No snap when result would overlap

    @Test func noSnapWhenOverlapWouldOccur() {
        // Dragging widget nearly on top of anchor — left-to-left snap would cause overlap
        let dragging = CGRect(x: 103, y: 0, width: 200, height: 100)
        let anchor   = CGRect(x: 100, y: 0, width: 200, height: 100)
        let (pos, guides) = SnapEngine.snapPosition(dragging: dragging, others: [anchor], threshold: 8)
        // Even though edges are 3pt apart, snapping would create overlap → rejected
        #expect(pos.x == 103)
        #expect(guides.isEmpty)
    }

    // MARK: - Simultaneous X and Y snap

    @Test func snapsBothAxesSimultaneously() {
        // dragging left at x=305 (anchor right at x=300 → 5pt), top at y=105 (anchor top at y=100 → 5pt)
        let dragging = CGRect(x: 305, y: 105, width: 100, height: 100)
        let anchor   = CGRect(x: 100, y: 100, width: 200, height: 200)
        let (pos, guides) = SnapEngine.snapPosition(dragging: dragging, others: [anchor], threshold: 8)
        #expect(pos.x == 300)   // left edge of dragging snapped to right edge of anchor
        #expect(pos.y == 100)   // top of dragging snapped to top of anchor
        // Two guide lines: one vertical (X snap), one horizontal (Y snap)
        #expect(guides.count >= 1)
    }

    // MARK: - Empty others = no snap

    @Test func noSnapWithNoOtherWidgets() {
        let dragging = CGRect(x: 100, y: 100, width: 200, height: 100)
        let (pos, guides) = SnapEngine.snapPosition(dragging: dragging, others: [], threshold: 8)
        #expect(pos.x == 100)
        #expect(pos.y == 100)
        #expect(guides.isEmpty)
    }
}
