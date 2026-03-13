// Rendering/Widgets/LocalZoomMath.swift v1.0.0
/**
 * Pure zoom math for local widget X-axis temporal zoom.
 * No SwiftUI or AppKit dependencies — fully unit-testable.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-13 - Initial implementation (Phase 8b.5: Three-Layer Zoom Model).
 */

import Foundation

/// Pure static helpers for local widget temporal zoom (Layer 3 of the three-layer zoom model).
///
/// Layer 1 = canvas zoom (scale all widgets uniformly).
/// Layer 2 = global temporal zoom (timeline → viewportMs shared by all widgets).
/// Layer 3 = local temporal zoom (per-widget viewport override, does not affect siblings).
enum LocalZoomMath {

    /// Minimum visible time span: 1 second.
    static let minSpanMs: Double = 1_000.0

    /// Apply a magnification factor centred on the current viewport midpoint.
    ///
    /// - Parameters:
    ///   - local: The current local (or global) viewport in milliseconds.
    ///   - magnification: Gesture magnification value (>1 = zoom in, <1 = zoom out).
    ///   - globalSpan: Maximum allowed span (= global viewportMs span).
    /// - Returns: New viewport clamped to `[minSpanMs, globalSpan]`.
    static func applyXZoom(
        local: ClosedRange<Double>,
        magnification: Double,
        globalSpan: Double
    ) -> ClosedRange<Double> {
        guard magnification > 0 else { return local }
        let center = (local.lowerBound + local.upperBound) / 2.0
        let currentSpan = local.upperBound - local.lowerBound
        let newSpan = (currentSpan / magnification).clamped(to: minSpanMs...max(minSpanMs, globalSpan))
        let half = newSpan / 2.0
        return (center - half)...(center + half)
    }
}

// MARK: - Comparable+clamped

extension Comparable {
    /// Returns the value clamped to the given closed range.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
