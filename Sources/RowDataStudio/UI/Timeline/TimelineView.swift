// UI/Timeline/TimelineView.swift v1.0.0
/**
 * Multi-track timeline display with ruler, data source tracks, and playhead.
 * Supports scrubbing via drag on ruler and zoom via MagnificationGesture.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 7).
 */

import SwiftUI

public struct TimelineView: View {
    @ObservedObject var playheadController: PlayheadController
    let sessionDocument: SessionDocument?
    @Binding var viewportMs: ClosedRange<Double>

    @GestureState private var magnificationState: CGFloat = 1.0

    public init(
        playheadController: PlayheadController,
        sessionDocument: SessionDocument?,
        viewportMs: Binding<ClosedRange<Double>>
    ) {
        self.playheadController = playheadController
        self.sessionDocument = sessionDocument
        self._viewportMs = viewportMs
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Timeline ruler with scrub drag gesture
            GeometryReader { geo in
                TimelineRuler(
                    viewportMs: viewportMs,
                    width: geo.size.width - 80
                )
                .gesture(
                    DragGesture()
                        .onChanged { drag in
                            let offsetPx = drag.location.x
                            let durationMs = viewportMs.upperBound - viewportMs.lowerBound
                            let normalizedX = offsetPx / (geo.size.width - 80)
                            let timeMs = viewportMs.lowerBound + normalizedX * durationMs
                            playheadController.seek(to: timeMs)
                        }
                )
            }
            .frame(height: 28)

            // Data source tracks
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    if let doc = sessionDocument {
                        ForEach(doc.sources, id: \.id) { source in
                            timelineTrackForSource(source, doc: doc)
                        }
                    }
                }
            }

            Spacer()
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { geo in
                // Playhead line (red vertical)
                let totalWidth = geo.size.width - 80
                let durationMs = viewportMs.upperBound - viewportMs.lowerBound
                let normalizedPos = durationMs > 0
                    ? (playheadController.currentTimeMs - viewportMs.lowerBound) / durationMs
                    : 0
                let xPos = CGFloat(normalizedPos) * totalWidth

                if normalizedPos >= 0 && normalizedPos <= 1 {
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(.red)
                            .frame(width: 1)
                    }
                    .position(x: xPos, y: 14)  // y = ruler height
                }
            }
        }
        .gesture(
            MagnificationGesture()
                .onChanged { scale in
                    let centerMs = (viewportMs.lowerBound + viewportMs.upperBound) / 2
                    let halfDuration = (viewportMs.upperBound - viewportMs.lowerBound) / 2
                    let newHalfDuration = halfDuration / scale

                    // Clamp to reasonable zoom levels
                    let minDuration = 5_000.0  // 5 seconds min
                    let maxDuration = sessionDocument?.timeline.duration ?? 60  // session duration max
                    let clampedDuration = min(
                        max(newHalfDuration * 2, minDuration),
                        maxDuration * 1000
                    )
                    let clampedHalf = clampedDuration / 2

                    viewportMs = (centerMs - clampedHalf)...(centerMs + clampedHalf)
                }
        )
    }

    @ViewBuilder
    private func timelineTrackForSource(_ source: DataSource, doc: SessionDocument) -> some View {
        switch source {
        case .goProVideo(_, _, let role):
            TimelineTrack(
                label: "Video (\(role.rawValue))",
                color: .blue,
                isVideoTrack: true,
                viewportMs: viewportMs,
                durationMs: doc.timeline.duration * 1000
            )
        case .fitFile(_, _, let device):
            TimelineTrack(
                label: "FIT (\(device ?? "Unknown"))",
                color: .green,
                isVideoTrack: false,
                viewportMs: viewportMs,
                durationMs: doc.timeline.duration * 1000
            )
        case .csvFile(_, _, let device):
            TimelineTrack(
                label: "CSV (\(device ?? "Unknown"))",
                color: .orange,
                isVideoTrack: false,
                viewportMs: viewportMs,
                durationMs: doc.timeline.duration * 1000
            )
        case .sidecar:
            EmptyView()
        }
    }
}
