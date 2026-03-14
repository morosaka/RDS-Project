// UI/Timeline/TimelineTrackRow.swift v2.1.0
/**
 * Single track row in the NLE timeline.
 * Renders a track header (color dot, name, stream icon, pin/mute/eye controls)
 * and a content area (sparkline, checkerboard for video, waveform bar for audio).
 *
 * Interactions added in v2.1.0:
 *   - Horizontal drag on content area → offset adjustment (sync nudge)
 *   - Option+click on mute button → solo this audio track
 *   - Offset preview overlay shown during drag
 *
 * --- Revision History ---
 * v2.1.0 - 2026-03-14 - Track interactions: offset drag, solo on Option+click (Phase 8c.4).
 * v2.0.0 - 2026-03-14 - Full NLE redesign: model-driven, sparklines, icon row (Phase 8c.3).
 * v1.1.0 - 2026-03-13 - Rename to TimelineTrackRow (Phase 8c.2: resolve naming conflict).
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 7).
 */

import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Single row in the NLE timeline — header + content area.
public struct TimelineTrackRow: View {

    // MARK: - Input

    let track: TimelineTrack
    let viewportMs: ClosedRange<Double>
    let sessionDurationMs: Double
    /// Optional sparkline samples (pre-downsampled, viewport-clipped). nil → solid bar.
    let sparklineData: ContiguousArray<Float>?
    let onPin: () -> Void
    let onMute: () -> Void
    let onSolo: () -> Void
    let onToggleVisibility: () -> Void
    /// Called on drag END with the total delta in seconds to apply to track.offset.
    let onOffsetDrag: (TimeInterval) -> Void

    // MARK: - Local state

    @State private var isDraggingOffset = false
    @State private var dragOffsetPreviewMs: Double = 0

    // MARK: - Init

    public init(
        track: TimelineTrack,
        viewportMs: ClosedRange<Double>,
        sessionDurationMs: Double,
        sparklineData: ContiguousArray<Float>? = nil,
        onPin: @escaping () -> Void = {},
        onMute: @escaping () -> Void = {},
        onSolo: @escaping () -> Void = {},
        onToggleVisibility: @escaping () -> Void = {},
        onOffsetDrag: @escaping (TimeInterval) -> Void = { _ in }
    ) {
        self.track = track
        self.viewportMs = viewportMs
        self.sessionDurationMs = sessionDurationMs
        self.sparklineData = sparklineData
        self.onPin = onPin
        self.onMute = onMute
        self.onSolo = onSolo
        self.onToggleVisibility = onToggleVisibility
        self.onOffsetDrag = onOffsetDrag
    }

    // MARK: - Body

    public var body: some View {
        HStack(spacing: 0) {
            trackHeader
                .frame(width: 80)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    trackContent(width: geo.size.width)
                        .opacity(track.isVisible ? 1.0 : 0.1)

                    // Offset preview overlay during drag
                    if isDraggingOffset {
                        offsetPreviewOverlay
                    }
                }
                .gesture(offsetDragGesture(contentWidth: geo.size.width))
            }
            .frame(height: 28)
        }
        .frame(height: 32)
        .background(RDS.Colors.canvasBackground)
    }

    // MARK: - Header (80pt column)

    @ViewBuilder
    private var trackHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Color dot + metric name
            HStack(spacing: 4) {
                Circle()
                    .fill(track.stream.semanticColor)
                    .frame(width: 10, height: 10)

                Text(track.displayName ?? track.stream.rawValue)
                    .font(.system(size: 9))
                    .foregroundStyle(RDS.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            // Stream icon + action buttons
            HStack(spacing: 4) {
                Image(systemName: track.stream.symbolName)
                    .font(.system(size: 8))
                    .foregroundStyle(RDS.Colors.textSecondary.opacity(0.5))

                Spacer(minLength: 0)

                // Pin
                Button(action: onPin) {
                    Image(systemName: track.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 8))
                        .foregroundStyle(
                            track.isPinned
                                ? RDS.Colors.accent
                                : RDS.Colors.textSecondary.opacity(0.4)
                        )
                }
                .buttonStyle(.plain)

                // Mute / Solo — only for audio tracks
                if track.stream == .audio {
                    Button(action: muteOrSoloAction) {
                        Image(systemName: track.isMuted ? "speaker.slash.fill" : "speaker.wave.2")
                            .font(.system(size: 8))
                            .foregroundStyle(
                                track.isMuted
                                    ? RDS.Colors.accent
                                    : (track.isSolo
                                        ? RDS.Colors.accent.opacity(0.7)
                                        : RDS.Colors.textSecondary.opacity(0.4))
                            )
                    }
                    .buttonStyle(.plain)
                }

                // Visibility toggle
                Button(action: onToggleVisibility) {
                    Image(systemName: track.isVisible ? "eye" : "eye.slash")
                        .font(.system(size: 8))
                        .foregroundStyle(
                            track.isVisible
                                ? RDS.Colors.textSecondary.opacity(0.4)
                                : RDS.Colors.accent
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    // MARK: - Mute vs Solo dispatch

    private func muteOrSoloAction() {
#if os(macOS)
        if NSEvent.modifierFlags.contains(.option) {
            onSolo()
        } else {
            onMute()
        }
#else
        onMute()
#endif
    }

    // MARK: - Content area

    @ViewBuilder
    private func trackContent(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color(white: 0.07))

            switch track.stream {
            case .video:
                checkerboardBar(color: track.stream.semanticColor)
            case .audio:
                if let data = sparklineData {
                    sparklineView(data: data, color: track.stream.semanticColor)
                } else {
                    solidBar(color: track.stream.semanticColor)
                }
            default:
                if let data = sparklineData {
                    sparklineView(data: data, color: track.stream.semanticColor)
                } else {
                    solidBar(color: track.stream.semanticColor)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    // MARK: - Offset drag

    private func offsetDragGesture(contentWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { drag in
                isDraggingOffset = true
                let viewportDuration = viewportMs.upperBound - viewportMs.lowerBound
                let msPerPoint = viewportDuration / Double(contentWidth)
                dragOffsetPreviewMs = drag.translation.width * msPerPoint
            }
            .onEnded { drag in
                let viewportDuration = viewportMs.upperBound - viewportMs.lowerBound
                let msPerPoint = viewportDuration / Double(contentWidth)
                let deltaSeconds = (drag.translation.width * msPerPoint) / 1_000
                onOffsetDrag(deltaSeconds)
                isDraggingOffset = false
                dragOffsetPreviewMs = 0
            }
    }

    @ViewBuilder
    private var offsetPreviewOverlay: some View {
        let totalOffsetMs = track.offset * 1_000 + dragOffsetPreviewMs
        let sign = totalOffsetMs >= 0 ? "+" : ""
        let label = "\(sign)\(Int(totalOffsetMs)) ms"

        Text(label)
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(RDS.Colors.accent)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .padding(.leading, 4)
    }

    // MARK: - Content primitives

    private func solidBar(color: Color) -> some View {
        color.opacity(0.35)
    }

    private func checkerboardBar(color: Color) -> some View {
        Canvas { context, size in
            let cell: CGFloat = 4
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var col = 0
                var x: CGFloat = 0
                while x < size.width {
                    if (row + col) % 2 == 0 {
                        context.fill(
                            Path(CGRect(x: x, y: y, width: cell, height: cell)),
                            with: .color(color.opacity(0.30))
                        )
                    }
                    x += cell
                    col += 1
                }
                y += cell
                row += 1
            }
        }
    }

    private func sparklineView(data: ContiguousArray<Float>, color: Color) -> some View {
        Canvas { context, size in
            guard data.count > 1 else {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color.opacity(0.35)))
                return
            }

            let minVal = Double(data.min() ?? 0)
            let maxVal = Double(data.max() ?? 1)
            let range  = maxVal - minVal > 0 ? maxVal - minVal : 1.0

            var linePath = Path()
            var fillPath = Path()

            for (i, sample) in data.enumerated() {
                let x = CGFloat(i) / CGFloat(data.count - 1) * size.width
                let normalized = (Double(sample) - minVal) / range
                let y = size.height - CGFloat(normalized) * (size.height - 2) - 1

                if i == 0 {
                    linePath.move(to: CGPoint(x: x, y: y))
                    fillPath.move(to: CGPoint(x: 0, y: size.height))
                    fillPath.addLine(to: CGPoint(x: x, y: y))
                } else {
                    linePath.addLine(to: CGPoint(x: x, y: y))
                    fillPath.addLine(to: CGPoint(x: x, y: y))
                }
            }

            fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
            fillPath.closeSubpath()

            context.fill(fillPath, with: .color(color.opacity(0.15)))
            context.stroke(linePath, with: .color(color), lineWidth: 1.0)
        }
        .frame(height: 24)
    }
}
