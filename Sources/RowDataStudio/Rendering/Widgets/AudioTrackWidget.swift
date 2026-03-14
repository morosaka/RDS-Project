// Rendering/Widgets/AudioTrackWidget.swift v1.0.0
/**
 * Audio waveform widget for the infinite canvas.
 *
 * Renders a multi-resolution peak envelope (WaveformPeaks) using SwiftUI Canvas,
 * displays a playhead cursor, and provides volume/mute controls (UI state only;
 * AVAudioPlayerNode playback is post-MVP and wired in a later phase).
 *
 * The widget calls `WaveformPeaks.peaksForViewport` to select the optimal pyramid
 * level for the current zoom, giving roughly 1 bin per pixel with no overdraw.
 *
 * When `waveformPeaks` is nil (sidecar not yet generated), a placeholder is shown.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-14 - Initial implementation (Phase 8c.7).
 */

import SwiftUI

// MARK: - AudioTrackWidget

/// Canvas widget that renders an audio waveform peak envelope.
public struct AudioTrackWidget: View, AnalysisWidget {

    // MARK: - AnalysisWidget conformance

    public let state: WidgetState
    public let dataContext: DataContext
    /// Observed so the playhead cursor re-renders on every tick.
    @ObservedObject public var playheadController: PlayheadController

    // MARK: - Input

    /// Pre-computed peak pyramid from the audio sidecar (nil until generated).
    let waveformPeaks: WaveformPeaks?

    /// Visible time range in milliseconds — drives pyramid level selection.
    let viewportMs: ClosedRange<Double>

    // MARK: - Local UI state (not persisted; resets on widget re-creation)

    /// Playback volume: 0 (silent) → 1 (full). Affects waveform opacity.
    @State private var volume: Double = 1.0

    /// When true the waveform is rendered in a muted colour and the
    /// volume slider is disabled.
    @State private var isMuted: Bool = false

    // MARK: - Layout constants

    private let controlBarHeight: CGFloat = 28

    // MARK: - Init

    public init(
        state: WidgetState,
        dataContext: DataContext,
        playheadController: PlayheadController,
        waveformPeaks: WaveformPeaks?,
        viewportMs: ClosedRange<Double>
    ) {
        self.state               = state
        self.dataContext         = dataContext
        self.playheadController  = playheadController
        self.waveformPeaks       = waveformPeaks
        self.viewportMs          = viewportMs
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            waveformArea
            controlBar
        }
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Waveform area

    @ViewBuilder
    private var waveformArea: some View {
        GeometryReader { geo in
            ZStack {
                if let peaks = waveformPeaks {
                    waveformCanvas(peaks: peaks, size: geo.size)
                } else {
                    placeholderView
                }
                playheadOverlay(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    /// Renders peak bins as vertical lines using SwiftUI Canvas (GPU-composited).
    private func waveformCanvas(peaks: WaveformPeaks, size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let result   = peaks.peaksForViewport(viewportMs: viewportMs, widthPixels: Int(canvasSize.width))
            let slice    = result.peaks
            guard !slice.isEmpty else { return }

            let midY  = canvasSize.height / 2
            let scale = midY * 0.9
            let binW  = canvasSize.width / CGFloat(slice.count)

            // Muted → grey; audible → accent with volume-driven opacity
            let color: Color = isMuted
                ? Color(white: 0.30)
                : RDS.Colors.accent.opacity(0.35 + 0.65 * volume)

            for (i, pair) in slice.enumerated() {
                let x    = (CGFloat(i) + 0.5) * binW
                let yTop = midY - CGFloat(pair.max) * scale
                let yBot = midY - CGFloat(pair.min) * scale

                var path = Path()
                path.move(to: CGPoint(x: x, y: yTop))
                path.addLine(to: CGPoint(x: x, y: yBot))
                context.stroke(path, with: .color(color),
                               lineWidth: max(1.0, binW - 0.5))
            }
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 4) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 18))
                .foregroundColor(Color(white: 0.35))
            Text("No audio data")
                .font(.caption2)
                .foregroundColor(Color(white: 0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Playhead overlay

    @ViewBuilder
    private func playheadOverlay(width: CGFloat, height: CGFloat) -> some View {
        let durationMs = viewportMs.upperBound - viewportMs.lowerBound
        if durationMs > 0 {
            let t          = playheadController.currentTimeMs
            let normalized = (t - viewportMs.lowerBound) / durationMs
            if normalized >= 0 && normalized <= 1 {
                let x = CGFloat(normalized) * width
                Rectangle()
                    .fill(RDS.Colors.accent)
                    .frame(width: 1.5, height: height)
                    .shadow(color: RDS.Colors.accent.opacity(0.45), radius: 4, x: 0, y: 0)
                    .position(x: x, y: height / 2)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 8) {
            // Mute toggle
            Button {
                isMuted.toggle()
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11))
                    .foregroundColor(isMuted ? Color(white: 0.45) : RDS.Colors.accent)
            }
            .buttonStyle(.plain)
            .help(isMuted ? "Unmute" : "Mute")

            // Volume slider
            Slider(value: $volume, in: 0...1)
                .disabled(isMuted)
                .tint(RDS.Colors.accent)

            // Level readout
            Text(isMuted ? "–∞" : String(format: "%.0f%%", volume * 100))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(white: 0.50))
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: controlBarHeight)
        .background(Color(white: 0.12))
    }
}
