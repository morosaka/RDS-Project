// Rendering/Widgets/VideoWidget.swift v1.1.0
/**
 * Canvas widget for synchronized video playback.
 * Owns a VideoSyncController bound to the shared PlayheadController.
 * Displays video frame, buffering spinner, and playback controls.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 7).
 */

import SwiftUI

public struct VideoWidget: View {
    let url: URL?
    let timeOffsetMs: Double
    @ObservedObject var playheadController: PlayheadController

    @StateObject private var syncController: VideoSyncController

    public init(
        url: URL?,
        timeOffsetMs: Double = 0,
        playheadController: PlayheadController
    ) {
        self.url = url
        self.timeOffsetMs = timeOffsetMs
        self.playheadController = playheadController
        _syncController = StateObject(
            wrappedValue: VideoSyncController(url: url, timeOffsetMs: timeOffsetMs)
        )
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background: black for video widget
            Color.black

            // Video player
            if url != nil {
                VideoPlayerView(player: syncController.player)
            } else {
                // No-video fallback
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No video source")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }

            // Buffering indicator (centered)
            if syncController.isBuffering {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            // Bottom control strip with playback info
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 4) {
                    // Seek slider (playhead)
                    Slider(
                        value: Binding(
                            get: { playheadController.currentTimeMs },
                            set: { playheadController.seek(to: $0) }
                        ),
                        in: 0...max(playheadController.duration, 1)
                    )
                    .tint(.white)
                    .padding(.horizontal, 8)

                    HStack(spacing: 8) {
                        // Play/Pause button with spacebar shortcut
                        Button(action: togglePlayback) {
                            Image(
                                systemName: playheadController.isPlaying
                                    ? "pause.fill"
                                    : "play.fill"
                            )
                            .foregroundColor(.white)
                            .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .help(playheadController.isPlaying ? "Pause (space)" : "Play (space)")

                        // Current time
                        Text(formatTime(playheadController.currentTimeMs / 1000))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white)

                        Spacer()

                        // Duration label
                        Text(formatTime(syncController.videoDuration))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)

                        // Time offset indicator (if non-zero)
                        if abs(timeOffsetMs) > 1 {
                            Text(String(format: "Δ%.1fs", timeOffsetMs / 1000))
                                .font(.caption2)
                                .foregroundColor(.yellow)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                }
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .task {
            syncController.bind(to: playheadController)
        }
        .onDisappear {
            syncController.unbind()
        }
    }

    private func togglePlayback() {
        if playheadController.isPlaying {
            playheadController.pause()
        } else {
            playheadController.play()
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let hours = Int(clamped) / 3600
        let minutes = (Int(clamped) % 3600) / 60
        let secs = Int(clamped) % 60
        let frac = Int((clamped.truncatingRemainder(dividingBy: 1)) * 10)

        if hours > 0 {
            return String(format: "%d:%02d:%02d.%d", hours, minutes, secs, frac)
        } else {
            return String(format: "%d:%02d.%d", minutes, secs, frac)
        }
    }
}
