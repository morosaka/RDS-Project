// Tests/RowDataStudioTests/Rendering/LocalZoomTests.swift v1.0.0
/**
 * Tests for LocalZoomMath pure zoom helpers.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-13 - Initial implementation (Phase 8b.5: Three-Layer Zoom Model).
 */

import Testing
@testable import RowDataStudio

@Suite struct LocalZoomTests {

    // MARK: - Basic zoom-in

    @Test func zoomIn2xHalvesSpan() {
        let viewport = 0.0...10_000.0  // 10 seconds
        let result = LocalZoomMath.applyXZoom(local: viewport, magnification: 2.0, globalSpan: 10_000)
        let span = result.upperBound - result.lowerBound
        #expect(abs(span - 5_000.0) < 1.0)       // span halved
        #expect(abs(result.lowerBound - 2_500.0) < 1.0)
        #expect(abs(result.upperBound - 7_500.0) < 1.0)
    }

    // MARK: - Clamp to minSpan

    @Test func zoomInClampsToMinSpan() {
        let viewport = 0.0...2_000.0
        let result = LocalZoomMath.applyXZoom(local: viewport, magnification: 100.0, globalSpan: 10_000)
        let span = result.upperBound - result.lowerBound
        #expect(span >= LocalZoomMath.minSpanMs)
    }

    // MARK: - Clamp to globalSpan

    @Test func zoomOutClampsToGlobalSpan() {
        let viewport = 0.0...10_000.0
        let result = LocalZoomMath.applyXZoom(local: viewport, magnification: 0.1, globalSpan: 10_000)
        let span = result.upperBound - result.lowerBound
        #expect(span <= 10_000.0 + 1.0)   // small float tolerance
    }

    // MARK: - Center preservation

    @Test func zoomPreservesCenter() {
        let viewport = 2_000.0...8_000.0  // center at 5000
        let result = LocalZoomMath.applyXZoom(local: viewport, magnification: 2.0, globalSpan: 20_000)
        let center = (result.lowerBound + result.upperBound) / 2.0
        #expect(abs(center - 5_000.0) < 1.0)
    }

    // MARK: - Identity (magnification = 1)

    @Test func zoomIdentityReturnsSameSpan() {
        let viewport = 1_000.0...9_000.0
        let result = LocalZoomMath.applyXZoom(local: viewport, magnification: 1.0, globalSpan: 10_000)
        let originalSpan = viewport.upperBound - viewport.lowerBound
        let resultSpan = result.upperBound - result.lowerBound
        #expect(abs(resultSpan - originalSpan) < 1.0)
    }

    // MARK: - Invalid magnification guard

    @Test func zeroMagnificationReturnsOriginal() {
        let viewport = 0.0...10_000.0
        let result = LocalZoomMath.applyXZoom(local: viewport, magnification: 0.0, globalSpan: 10_000)
        // Should return original (guard against divide by zero)
        #expect(result.lowerBound == viewport.lowerBound)
        #expect(result.upperBound == viewport.upperBound)
    }
}
