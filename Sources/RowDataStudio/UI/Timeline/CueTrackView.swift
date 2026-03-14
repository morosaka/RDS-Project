// UI/Timeline/CueTrackView.swift v1.0.0
/**
 * Cue/bookmark track row displayed at the bottom of the NLE timeline.
 *
 * Layout:
 *   [80pt header: "CUE" label + "+" button] | [content: vertical pins per cue]
 *
 * Each pin:
 *   - Vertical line + filled circle at top, rendered via Canvas
 *   - Tappable label text below the pin
 *   - Tap → seek playhead to cue.timeMs
 *   - Double-tap / double-click on label → inline editing (TextField)
 *   - Right-click / context menu → "Delete Cue"
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-14 - Initial implementation (Phase 8c.5).
 */

import SwiftUI

public struct CueTrackView: View {

    // MARK: - Input

    let cueMarkers: [CueMarker]
    let viewportMs: ClosedRange<Double>
    let onAddCue: () -> Void
    let onDeleteCue: (UUID) -> Void
    let onSeekToCue: (Double) -> Void
    let onRenameCue: (UUID, String) -> Void

    // MARK: - Local state

    @State private var editingCueID: UUID? = nil
    @State private var editingLabel: String = ""

    // MARK: - Init

    public init(
        cueMarkers: [CueMarker],
        viewportMs: ClosedRange<Double>,
        onAddCue: @escaping () -> Void = {},
        onDeleteCue: @escaping (UUID) -> Void = { _ in },
        onSeekToCue: @escaping (Double) -> Void = { _ in },
        onRenameCue: @escaping (UUID, String) -> Void = { _, _ in }
    ) {
        self.cueMarkers = cueMarkers
        self.viewportMs = viewportMs
        self.onAddCue = onAddCue
        self.onDeleteCue = onDeleteCue
        self.onSeekToCue = onSeekToCue
        self.onRenameCue = onRenameCue
    }

    // MARK: - Body

    public var body: some View {
        HStack(spacing: 0) {
            // Header
            cueHeader
                .frame(width: 80)

            // Cue content area
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    // Background
                    Rectangle()
                        .fill(Color(white: 0.05))

                    // Pin lines (Canvas layer — no interaction)
                    Canvas { context, size in
                        drawPinLines(context: context, size: size)
                    }

                    // Per-cue interactive overlays
                    ForEach(cueMarkers) { cue in
                        if isVisible(cue) {
                            cueOverlay(cue: cue, contentWidth: geo.size.width)
                        }
                    }
                }
                .clipShape(Rectangle())
            }
            .frame(height: 36)
        }
        .frame(height: 36)
        .background(RDS.Colors.canvasBackground)
    }

    // MARK: - Header (80pt)

    @ViewBuilder
    private var cueHeader: some View {
        HStack(spacing: 4) {
            Text("CUE")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(RDS.Colors.textSecondary.opacity(0.6))

            Spacer(minLength: 0)

            // Add cue button
            Button(action: onAddCue) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(RDS.Colors.accent)
            }
            .buttonStyle(.plain)
            .help("Add cue at playhead (M)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    // MARK: - Canvas pin lines

    private func drawPinLines(context: GraphicsContext, size: CGSize) {
        let viewportDuration = viewportMs.upperBound - viewportMs.lowerBound
        guard viewportDuration > 0 else { return }

        for cue in cueMarkers where isVisible(cue) {
            let x = CGFloat((cue.timeMs - viewportMs.lowerBound) / viewportDuration) * size.width

            // Vertical line
            var linePath = Path()
            linePath.move(to: CGPoint(x: x, y: 0))
            linePath.addLine(to: CGPoint(x: x, y: size.height - 14))   // leave room for label
            context.stroke(linePath, with: .color(accentColor(for: cue).opacity(0.8)), lineWidth: 1)

            // Circle at top
            let circleRect = CGRect(x: x - 4, y: 0, width: 8, height: 8)
            context.fill(Path(ellipseIn: circleRect), with: .color(accentColor(for: cue)))
        }
    }

    // MARK: - Per-cue interactive overlay

    @ViewBuilder
    private func cueOverlay(cue: CueMarker, contentWidth: CGFloat) -> some View {
        let viewportDuration = viewportMs.upperBound - viewportMs.lowerBound
        let x = viewportDuration > 0
            ? CGFloat((cue.timeMs - viewportMs.lowerBound) / viewportDuration) * contentWidth
            : 0

        if viewportDuration > 0 {
            if editingCueID == cue.id {
                // Inline label editor
                TextField("", text: $editingLabel)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(accentColor(for: cue))
                    .frame(width: 60)
                    .textFieldStyle(.plain)
                    .onSubmit { commitEdit(cue: cue) }
                    .onExitCommand { cancelEdit() }
                    .position(x: x, y: 28)
            } else {
                // Tappable label
                Text(cue.label)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(accentColor(for: cue).opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 60)
                    .position(x: x, y: 28)
                    .onTapGesture(count: 2) { beginEdit(cue: cue) }
                    .onTapGesture(count: 1) { onSeekToCue(cue.timeMs) }
                    .contextMenu {
                        Button(role: .destructive) {
                            onDeleteCue(cue.id)
                        } label: {
                            Label("Delete Cue", systemImage: "trash")
                        }
                        Button { beginEdit(cue: cue) } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                    }
            }
        }
    }

    // MARK: - Helpers

    private func isVisible(_ cue: CueMarker) -> Bool {
        cue.timeMs >= viewportMs.lowerBound && cue.timeMs <= viewportMs.upperBound
    }

    private func accentColor(for cue: CueMarker) -> Color {
        guard let hex = cue.color else { return RDS.Colors.accent }
        return Color(hex: hex) ?? RDS.Colors.accent
    }

    private func beginEdit(cue: CueMarker) {
        editingCueID = cue.id
        editingLabel = cue.label
    }

    private func commitEdit(cue: CueMarker) {
        let trimmed = editingLabel.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            onRenameCue(cue.id, trimmed)
        }
        cancelEdit()
    }

    private func cancelEdit() {
        editingCueID = nil
        editingLabel = ""
    }
}

// MARK: - Color hex initializer

private extension Color {
    /// Creates a Color from a CSS hex string (`"#RRGGBB"` or `"RRGGBB"`).
    init?(hex: String) {
        let raw = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard raw.count == 6, let value = UInt64(raw, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8)  & 0xFF) / 255
        let b = Double( value        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
