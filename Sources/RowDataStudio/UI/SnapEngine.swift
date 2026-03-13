// UI/SnapEngine.swift v1.0.0
/**
 * Pure magnetic snap logic for canvas widget alignment.
 * No SwiftUI or AppKit dependencies — fully unit-testable.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-13 - Initial implementation (Phase 8b.6: Magnetic Snapping).
 */

import Foundation
import CoreGraphics

/// A visual guide line rendered on the canvas when a snap event fires.
struct SnapGuide: Equatable {
    let start: CGPoint
    let end: CGPoint
}

/// Pure snap-position logic for the canvas drag system.
///
/// All methods are static and have no SwiftUI or AppKit dependencies,
/// making them fully testable with `@testable import RowDataStudio`.
enum SnapEngine {

    /// Compute the snapped position and snap guide lines for a widget being dragged.
    ///
    /// Checks all 5 snap targets per axis (left, right, centerX; top, bottom, centerY)
    /// against all other visible widget rects. X and Y axes snap independently.
    /// A candidate snap is rejected if it would cause the dragging rect to overlap the anchor.
    ///
    /// - Parameters:
    ///   - dragging: CGRect of the widget currently being dragged (origin = top-left position).
    ///   - others: CGRects of all other visible widgets.
    ///   - threshold: Maximum distance (pts) for a snap to trigger.
    /// - Returns: The (possibly snapped) top-left `CGPoint` and any active guide lines.
    static func snapPosition(
        dragging: CGRect,
        others: [CGRect],
        threshold: CGFloat
    ) -> (position: CGPoint, guides: [SnapGuide]) {

        var snappedX = dragging.minX
        var snappedY = dragging.minY
        var guides: [SnapGuide] = []
        var bestDX = threshold + 1
        var bestDY = threshold + 1

        for other in others {
            // ── Horizontal snaps (X axis) ────────────────────────────────────
            // Each pair: (dragging edge, other edge that it snaps to)
            let xPairs: [(CGFloat, CGFloat)] = [
                (dragging.minX,  other.minX),   // left ↔ left
                (dragging.minX,  other.maxX),   // left ↔ right
                (dragging.maxX,  other.maxX),   // right ↔ right
                (dragging.maxX,  other.minX),   // right ↔ left
                (dragging.midX,  other.midX),   // center ↔ center
            ]
            for (dragEdge, otherEdge) in xPairs {
                let dist = abs(dragEdge - otherEdge)
                guard dist < bestDX else { continue }
                let candidateX = snappedX + (otherEdge - dragEdge)
                let candidateRect = CGRect(x: candidateX, y: snappedY,
                                          width: dragging.width, height: dragging.height)
                guard !candidateRect.insetBy(dx: 1, dy: 1).intersects(other) else { continue }
                bestDX = dist
                snappedX = candidateX
                let guideX = otherEdge
                let minY = min(dragging.minY, other.minY) - 4
                let maxY = max(dragging.maxY, other.maxY) + 4
                // Replace previous X guide (keep only the best)
                guides.removeAll { $0.start.x == $0.end.x }
                guides.append(SnapGuide(
                    start: CGPoint(x: guideX, y: minY),
                    end:   CGPoint(x: guideX, y: maxY)
                ))
            }

            // ── Vertical snaps (Y axis) ───────────────────────────────────────
            let yPairs: [(CGFloat, CGFloat)] = [
                (dragging.minY,  other.minY),
                (dragging.minY,  other.maxY),
                (dragging.maxY,  other.maxY),
                (dragging.maxY,  other.minY),
                (dragging.midY,  other.midY),
            ]
            for (dragEdge, otherEdge) in yPairs {
                let dist = abs(dragEdge - otherEdge)
                guard dist < bestDY else { continue }
                let candidateY = snappedY + (otherEdge - dragEdge)
                let candidateRect = CGRect(x: snappedX, y: candidateY,
                                          width: dragging.width, height: dragging.height)
                guard !candidateRect.insetBy(dx: 1, dy: 1).intersects(other) else { continue }
                bestDY = dist
                snappedY = candidateY
                let guideY = otherEdge
                let minX = min(dragging.minX, other.minX) - 4
                let maxX = max(dragging.maxX, other.maxX) + 4
                guides.removeAll { $0.start.y == $0.end.y }
                guides.append(SnapGuide(
                    start: CGPoint(x: minX, y: guideY),
                    end:   CGPoint(x: maxX, y: guideY)
                ))
            }
        }

        return (CGPoint(x: snappedX, y: snappedY), guides)
    }
}
