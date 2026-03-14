// UI/Timeline/TimelineView.swift v2.3.0
/**
 * Multi-track NLE timeline: ruler, track list from SessionDocument.timeline.tracks,
 * cue track, playhead, scrub drag, and viewport zoom.
 *
 * Track iteration is model-driven (doc.timeline.tracks), not source-driven.
 * Drag-to-reorder mutates track order via the `onMoveTracks` callback.
 * Playhead renders in RDS.Colors.accent (orange) with a soft glow.
 * Shortcut M creates a cue at the current playhead position (macOS 14+).
 *
 * **Zoom gesture fix (v2.3):** Clamp viewport center to prevent negative/inverted bounds
 * when pinching to extreme scales. Ensures viewport always stays within [0, sessionDurationMs].
 *
 * --- Revision History ---
 * v2.3.0 - 2026-03-14 - Fix zoom gesture crash: clamp center to prevent negative bounds.
 * v2.2.0 - 2026-03-14 - Add CueTrackView at bottom, cue callbacks, shortcut M (Phase 8c.5).
 * v2.1.0 - 2026-03-14 - Add onSoloTrack + onOffsetTrack callbacks (Phase 8c.4).
 * v2.0.0 - 2026-03-14 - NLE redesign: model-driven track list, drag-to-reorder,
 *                        orange playhead with glow, track action callbacks (Phase 8c.3).
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 7).
 */

import SwiftUI

public struct TimelineView: View {

    // MARK: - Input

    @ObservedObject var playheadController: PlayheadController
    let sessionDocument: SessionDocument?
    @Binding var viewportMs: ClosedRange<Double>

    // Track callbacks
    let onMoveTracks: ((IndexSet, Int) -> Void)?
    let onPinTrack: ((UUID) -> Void)?
    let onMuteTrack: ((UUID) -> Void)?
    let onSoloTrack: ((UUID) -> Void)?
    let onToggleTrackVisibility: ((UUID) -> Void)?
    let onOffsetTrack: ((UUID, TimeInterval) -> Void)?

    // Cue callbacks
    let onAddCue: (() -> Void)?
    let onDeleteCue: ((UUID) -> Void)?
    let onSeekToCue: ((Double) -> Void)?
    let onRenameCue: ((UUID, String) -> Void)?

    // MARK: - Init

    public init(
        playheadController: PlayheadController,
        sessionDocument: SessionDocument?,
        viewportMs: Binding<ClosedRange<Double>>,
        onMoveTracks: ((IndexSet, Int) -> Void)? = nil,
        onPinTrack: ((UUID) -> Void)? = nil,
        onMuteTrack: ((UUID) -> Void)? = nil,
        onSoloTrack: ((UUID) -> Void)? = nil,
        onToggleTrackVisibility: ((UUID) -> Void)? = nil,
        onOffsetTrack: ((UUID, TimeInterval) -> Void)? = nil,
        onAddCue: (() -> Void)? = nil,
        onDeleteCue: ((UUID) -> Void)? = nil,
        onSeekToCue: ((Double) -> Void)? = nil,
        onRenameCue: ((UUID, String) -> Void)? = nil
    ) {
        self.playheadController = playheadController
        self.sessionDocument = sessionDocument
        self._viewportMs = viewportMs
        self.onMoveTracks = onMoveTracks
        self.onPinTrack = onPinTrack
        self.onMuteTrack = onMuteTrack
        self.onSoloTrack = onSoloTrack
        self.onToggleTrackVisibility = onToggleTrackVisibility
        self.onOffsetTrack = onOffsetTrack
        self.onAddCue = onAddCue
        self.onDeleteCue = onDeleteCue
        self.onSeekToCue = onSeekToCue
        self.onRenameCue = onRenameCue
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // Ruler with scrub drag
            GeometryReader { geo in
                let contentWidth = geo.size.width - 80

                TimelineRuler(
                    viewportMs: viewportMs,
                    width: contentWidth
                )
                .gesture(
                    DragGesture()
                        .onChanged { drag in
                            let normalizedX = drag.location.x / contentWidth
                            let durationMs  = viewportMs.upperBound - viewportMs.lowerBound
                            let timeMs      = viewportMs.lowerBound + normalizedX * durationMs
                            playheadController.seek(to: timeMs)
                        }
                )
            }
            .frame(height: 28)

            // Track list — model-driven from timeline.tracks
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    if let doc = sessionDocument {
                        let tracks    = doc.timeline.tracks
                        let durationMs = doc.timeline.duration * 1_000

                        ForEach(tracks) { track in
                            TimelineTrackRow(
                                track: track,
                                viewportMs: viewportMs,
                                sessionDurationMs: durationMs,
                                sparklineData: nil,
                                onPin: { onPinTrack?(track.id) },
                                onMute: { onMuteTrack?(track.id) },
                                onSolo: { onSoloTrack?(track.id) },
                                onToggleVisibility: { onToggleTrackVisibility?(track.id) },
                                onOffsetDrag: { delta in onOffsetTrack?(track.id, delta) }
                            )
                        }
                        .onMove { source, destination in
                            onMoveTracks?(source, destination)
                        }
                    }
                }
            }

            // Cue track — fixed at the bottom, outside the scroll view
            if let doc = sessionDocument {
                Divider()
                    .background(Color(white: 0.15))

                CueTrackView(
                    cueMarkers: doc.cueMarkers,
                    viewportMs: viewportMs,
                    onAddCue: { onAddCue?() },
                    onDeleteCue: { id in onDeleteCue?(id) },
                    onSeekToCue: { timeMs in
                        onSeekToCue?(timeMs)
                        playheadController.seek(to: timeMs)
                    },
                    onRenameCue: { id, label in onRenameCue?(id, label) }
                )
            }

            Spacer()
        }
        .overlay(alignment: .topLeading) {
            playheadOverlay
        }
        .gesture(zoomGesture)
        .modifier(CueKeyPressModifier(onAddCue: onAddCue))
    }

    // MARK: - Playhead overlay

    @ViewBuilder
    private var playheadOverlay: some View {
        GeometryReader { geo in
            let contentWidth  = geo.size.width - 80
            let durationMs    = viewportMs.upperBound - viewportMs.lowerBound
            let normalizedPos = durationMs > 0
                ? (playheadController.currentTimeMs - viewportMs.lowerBound) / durationMs
                : 0

            if normalizedPos >= 0 && normalizedPos <= 1 {
                let xPos = 80 + CGFloat(normalizedPos) * contentWidth

                Rectangle()
                    .fill(RDS.Colors.accent)
                    .frame(width: 2)
                    .shadow(color: RDS.Colors.accent.opacity(0.4), radius: 6, x: 0, y: 0)
                    .frame(maxHeight: .infinity)
                    .position(x: xPos, y: geo.size.height / 2)
            }
        }
    }

    // MARK: - Zoom gesture

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                let centerMs     = (viewportMs.lowerBound + viewportMs.upperBound) / 2
                let halfDuration = (viewportMs.upperBound - viewportMs.lowerBound) / 2
                let newHalf      = halfDuration / scale
                let minDuration  = 5_000.0
                let maxDuration  = (sessionDocument?.timeline.duration ?? 60) * 1_000
                let clamped      = min(max(newHalf * 2, minDuration), maxDuration)
                let clampedHalf  = clamped / 2
                // Clamp center to ensure viewport bounds stay within [0, maxDuration]
                let clampedCenter = max(clampedHalf, min(maxDuration - clampedHalf, centerMs))
                viewportMs = (clampedCenter - clampedHalf)...(clampedCenter + clampedHalf)
            }
    }
}

// MARK: - Keyboard shortcut modifier

/// Wraps `.onKeyPress("m")` behind an availability check (macOS 14+).
private struct CueKeyPressModifier: ViewModifier {
    let onAddCue: (() -> Void)?

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.onKeyPress("m") {
                onAddCue?()
                return .handled
            }
        } else {
            content
        }
    }
}
