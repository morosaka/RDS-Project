// UI/Timeline/TimelineRuler.swift v1.0.0
/**
 * Adaptive timeline ruler with tick marks and labels.
 * Tick intervals scale based on viewport duration.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 7).
 */

import SwiftUI

public struct TimelineRuler: View {
    let viewportMs: ClosedRange<Double>
    let width: CGFloat

    public init(viewportMs: ClosedRange<Double>, width: CGFloat) {
        self.viewportMs = viewportMs
        self.width = width
    }

    // Compute tick intervals: (minor, major) in milliseconds
    static func tickInterval(for durationMs: Double) -> (minor: Double, major: Double) {
        switch durationMs {
        case ..<30_000:  // < 30s
            return (1_000, 5_000)  // 1s minor, 5s major
        case ..<300_000:  // < 5 min
            return (5_000, 30_000)  // 5s minor, 30s major
        case ..<1_800_000:  // < 30 min
            return (30_000, 300_000)  // 30s minor, 5min major
        default:  // >= 30 min
            return (300_000, 1_800_000)  // 5min minor, 30min major
        }
    }

    // Generate tick marks and optional labels for current viewport
    func ticks() -> [(x: CGFloat, label: String?, isMinor: Bool)] {
        let durationMs = viewportMs.upperBound - viewportMs.lowerBound
        let (minorIntervalMs, majorIntervalMs) = Self.tickInterval(for: durationMs)

        var result: [(x: CGFloat, label: String?, isMinor: Bool)] = []

        // Start at first major tick >= lowerBound
        let startMs = (viewportMs.lowerBound / majorIntervalMs).rounded(.up) * majorIntervalMs

        var currentMs = startMs
        while currentMs <= viewportMs.upperBound {
            let x = xPosition(for: currentMs)
            if x >= 0 && x <= width {
                let isMajor = currentMs.truncatingRemainder(dividingBy: majorIntervalMs) < 1
                let label = isMajor ? formatLabel(currentMs) : nil
                result.append((x: x, label: label, isMinor: !isMajor))
            }
            currentMs += minorIntervalMs
        }

        return result
    }

    private func xPosition(for ms: Double) -> CGFloat {
        let durationMs = viewportMs.upperBound - viewportMs.lowerBound
        if durationMs <= 0 { return 0 }
        let normalized = (ms - viewportMs.lowerBound) / durationMs
        return CGFloat(normalized) * width
    }

    private func formatLabel(_ ms: Double) -> String {
        let totalSeconds = Int(ms / 1000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    public var body: some View {
        Canvas { context, size in
            let tickMarks = ticks()

            for (x, label, isMinor) in tickMarks {
                // Draw tick line
                let tickHeight = isMinor ? 4.0 : 8.0
                let path = Path(
                    roundedRect: CGRect(
                        x: x - 0.5,
                        y: size.height - tickHeight,
                        width: 1,
                        height: tickHeight
                    ),
                    cornerRadius: 0.5
                )
                context.fill(path, with: .color(.secondary.opacity(0.6)))

                // Draw label for major ticks
                if let label = label, !isMinor {
                    let text = Text(label)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                    context.draw(
                        text,
                        at: CGPoint(x: x, y: size.height - 14),
                        anchor: .topLeading
                    )
                }
            }
        }
        .frame(height: 28)
        .background(Color(white: 0.10)) // Fixed dark background — app never follows system appearance
    }
}
