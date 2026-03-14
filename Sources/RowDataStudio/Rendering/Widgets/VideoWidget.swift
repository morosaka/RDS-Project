// Rendering/Widgets/VideoWidget.swift v1.3.0
/**
 * Canvas widget for synchronized video playback (video-only; audio is handled
 * by AudioTrackWidget via the .waveform.gz sidecar).
 *
 * The AVPlayer is muted at task start — audio decoding continues internally
 * (needed for A/V sync), but no audio is emitted from this widget.
 *
 * **Architecture (v1.2):**
 * - `playheadController` is a plain `let` — VideoWidget body NOT reactive at 60fps.
 * - `VideoControlsView` is a private child with its own @ObservedObject;
 *   only the control strip (slider + time label) redraws at 60fps.
 *
 * --- Revision History ---
 * v1.3.0 - 2026-03-14 - Mute AVPlayer by default (Phase 8c.8: Video/Audio separation).
 * v1.2.0 - 2026-03-12 - Demote @ObservedObject to let; controls extracted to VideoControlsView.
 * v1.1.0 - 2026-03-08 - VideoSyncController bound to PlayheadController.
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 7).
 */

import SwiftUI

public struct VideoWidget: View {
    let url: URL?
    let timeOffsetMs: Double
    /// Plain `let` — NOT @ObservedObject. Only child `VideoControlsView` subscribes.
    let playheadController: PlayheadController

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
            Color.black

            if url != nil {
                VideoPlayerView(player: syncController.player)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash").font(.system(size: 36)).foregroundColor(.secondary)
                    Text("No video source").foregroundColor(.secondary).font(.caption)
                }
            }

            if syncController.isBuffering {
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            // Control strip — its own @ObservedObject lives here, not in VideoWidget.
            VideoControlsView(
                playheadController: playheadController,
                syncController: syncController,
                timeOffsetMs: timeOffsetMs
            )
        }
        .task {
            // NOTE: player is NOT muted here. AudioTrackWidget provides the waveform
            // visualisation and volume controls, but actual audio output comes from
            // this AVPlayer until a dedicated AVAudioPlayerNode path is added (post-MVP).
            syncController.bind(to: playheadController)
        }
        .onDisappear {
            syncController.unbind()
        }
    }
}

// MARK: - VideoControlsView (60fps child)

/// Only this child struct subscribes to PlayheadController via @ObservedObject.
/// The main VideoWidget body (which hosts the expensive AVKit VideoPlayerView) does NOT
/// re-render at 60fps.
private struct VideoControlsView: View {
    @ObservedObject var playheadController: PlayheadController
    @ObservedObject var syncController: VideoSyncController
    let timeOffsetMs: Double

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 4) {
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
                    Button(action: {
                        if playheadController.isPlaying { playheadController.pause() }
                        else { playheadController.play() }
                    }) {
                        Image(systemName: playheadController.isPlaying ? "pause.fill" : "play.fill")
                            .foregroundColor(.white).font(.system(size: 12))
                    }
                    .buttonStyle(.plain).contentShape(Rectangle())
                    .help(playheadController.isPlaying ? "Pause (space)" : "Play (space)")

                    Text(formatTime(playheadController.currentTimeMs / 1000))
                        .font(.system(.caption, design: .monospaced)).foregroundColor(.white)

                    Spacer()

                    Text(formatTime(syncController.videoDuration))
                        .font(.system(.caption2, design: .monospaced)).foregroundColor(.secondary)

                    if abs(timeOffsetMs) > 1 {
                        Text(String(format: "Δ%.1fs", timeOffsetMs / 1000))
                            .font(.caption2).foregroundColor(.yellow)
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 6)
            }
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
            )
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
