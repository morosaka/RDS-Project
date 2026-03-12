// UI/Timeline/TimelineTrack.swift v1.0.0
/**
 * Single track row in a timeline display.
 * Shows label, color indicator, and optional fill bar for duration.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 7).
 */

import SwiftUI

public struct TimelineTrack: View {
    let label: String
    let color: Color
    let isVideoTrack: Bool
    let viewportMs: ClosedRange<Double>
    let durationMs: Double  // Track duration for fill bar

    public init(
        label: String,
        color: Color,
        isVideoTrack: Bool,
        viewportMs: ClosedRange<Double>,
        durationMs: Double
    ) {
        self.label = label
        self.color = color
        self.isVideoTrack = isVideoTrack
        self.viewportMs = viewportMs
        self.durationMs = durationMs
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Label (fixed width)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
                .truncationMode(.tail)

            // Track bar
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(white: 0.14)) // Fixed dark — app never follows system appearance

                // Fill (video = checkerboard pattern placeholder, data = solid bar)
                if isVideoTrack {
                    // Checkerboard pattern for video
                    Canvas { context, size in
                        let cellSize: CGFloat = 4
                        var y: CGFloat = 0
                        while y < size.height {
                            var x: CGFloat = 0
                            var alternate = (Int(y / cellSize) % 2 == 0)
                            while x < size.width {
                                if alternate {
                                    let rect = CGRect(
                                        x: x,
                                        y: y,
                                        width: cellSize,
                                        height: cellSize
                                    )
                                    context.fill(
                                        Path(roundedRect: rect, cornerRadius: 0),
                                        with: .color(color.opacity(0.3))
                                    )
                                }
                                x += cellSize
                                alternate.toggle()
                            }
                            y += cellSize
                        }
                    }
                } else {
                    // Solid bar for data
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .opacity(0.4)
                }
            }
            .frame(height: 32)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}
