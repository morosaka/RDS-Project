// UI/VideoPlayer/VideoTrimView.swift v1.0.0
/**
 * Interactive trim UI for video playback range.
 * Drag handles to set in/out points. Warns if GPMF telemetry sidecar is missing.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 7).
 */

import SwiftUI

public struct VideoTrimView: View {
    @ObservedObject var playheadController: PlayheadController
    @Binding var trimRange: ClosedRange<TimeInterval>?
    let videoURL: URL?
    let sidecarExists: Bool
    @Environment(\.dismiss) var dismiss

    @State private var showSidecarWarning = false
    @GestureState private var inHandleOffset: CGFloat = 0
    @GestureState private var outHandleOffset: CGFloat = 0

    public init(
        playheadController: PlayheadController,
        trimRange: Binding<ClosedRange<TimeInterval>?>,
        videoURL: URL?,
        sidecarExists: Bool
    ) {
        self.playheadController = playheadController
        self._trimRange = trimRange
        self.videoURL = videoURL
        self.sidecarExists = sidecarExists
    }

    public var body: some View {
        VStack(spacing: 12) {
            Text("Trim Video")
                .font(.headline)

            // Sidecar warning
            if !sidecarExists {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("GPMF telemetry sidecar not generated. Video will lose sync data on trim.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(4)
            }

            // Trim strip with handles
            ZStack(alignment: .bottomLeading) {
                // Background bar
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(white: 0.14)) // Fixed dark — app never follows system appearance

                // Current trim range indicator
                if let range = trimRange {
                    let inPercent = range.lowerBound / playheadController.duration
                    let outPercent = range.upperBound / playheadController.duration
                    let inPx = inPercent * 400
                    let outPx = outPercent * 400

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue.opacity(0.3))
                        .frame(
                            width: max(0, outPx - inPx),
                            height: 40
                        )
                        .position(x: inPx + (outPx - inPx) / 2, y: 20)
                }

                // In handle
                VStack {
                    Image(systemName: "triangle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("IN")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: 20, height: 40)
                .position(
                    x: (trimRange?.lowerBound ?? 0) / playheadController.duration * 400,
                    y: 20
                )
                .gesture(
                    DragGesture()
                        .updating($inHandleOffset) { value, state, _ in
                            state = value.translation.width
                        }
                        .onEnded { value in
                            if let range = trimRange {
                                let newIn = range.lowerBound
                                    + (value.translation.width / 400) * playheadController.duration
                                if newIn >= 0 && newIn < range.upperBound {
                                    trimRange = newIn...range.upperBound
                                }
                            }
                        }
                )

                // Out handle
                VStack {
                    Text("OUT")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Image(systemName: "triangle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                }
                .frame(width: 20, height: 40)
                .position(
                    x: (trimRange?.upperBound ?? playheadController.duration)
                        / playheadController.duration * 400,
                    y: 20
                )
                .gesture(
                    DragGesture()
                        .updating($outHandleOffset) { value, state, _ in
                            state = value.translation.width
                        }
                        .onEnded { value in
                            if let range = trimRange {
                                let newOut = range.upperBound
                                    + (value.translation.width / 400) * playheadController.duration
                                if newOut > range.lowerBound
                                    && newOut <= playheadController.duration
                                {
                                    trimRange = range.lowerBound...newOut
                                }
                            }
                        }
                )
            }
            .frame(height: 40)

            // Trim range display
            if let range = trimRange {
                Text(
                    String(
                        format: "%.1fs — %.1fs (%.1fs)",
                        range.lowerBound,
                        range.upperBound,
                        range.upperBound - range.lowerBound
                    )
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }

            // Quick set buttons
            HStack(spacing: 8) {
                Button(action: setInToPlayhead) {
                    Label("Set IN", systemImage: "paperclip")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Button(action: setOutToPlayhead) {
                    Label("Set OUT", systemImage: "paperclip")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: resetTrim) {
                    Label("Reset", systemImage: "xmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
                    Text("Cancel")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(
                    action: commitTrim,
                    label: {
                        Text("Apply Trim")
                    }
                )
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding(16)
        .alert("Generate Telemetry Sidecar?", isPresented: $showSidecarWarning) {
            Button("Cancel", role: .cancel) { }
            Button("Generate Sidecar") {
                // Call SidecarGenerator if videoURL is available
                // For now, just dismiss with warning
                commitTrim()
            }
        } message: {
            Text(
                "The video will lose sync with telemetry after trimming. "
                    + "Generate a sidecar file to preserve telemetry."
            )
        }
    }

    private func setInToPlayhead() {
        let currentSecs = playheadController.currentTimeMs / 1000.0
        if let range = trimRange {
            if currentSecs < range.upperBound {
                trimRange = currentSecs...range.upperBound
            }
        } else {
            if currentSecs < playheadController.duration {
                trimRange = currentSecs...playheadController.duration
            }
        }
    }

    private func setOutToPlayhead() {
        let currentSecs = playheadController.currentTimeMs / 1000.0
        if let range = trimRange {
            if currentSecs > range.lowerBound {
                trimRange = range.lowerBound...currentSecs
            }
        } else {
            if currentSecs > 0 {
                trimRange = 0...currentSecs
            }
        }
    }

    private func resetTrim() {
        trimRange = nil
    }

    private func commitTrim() {
        if !sidecarExists {
            showSidecarWarning = true
        } else {
            dismiss()
        }
    }
}
