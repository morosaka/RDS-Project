// RowDataStudio/ContentView.swift v0.5.0
/**
 * MVP root view: file import, metric selector, line chart, playhead controls.
 * Replaced Phase 0 placeholder. Will be superseded by RowingDeskCanvas in Phase 6.
 * --- Revision History ---
 * v0.5.0 - 2026-03-07 - Replace fileImporter with NSOpenPanel (more reliable on macOS SPM builds).
 * v0.4.0 - 2026-03-07 - Phase 4 MVP: file picker + LineChartWidget + PlayheadController.
 * v0.1.0 - 2026-03-01 - Phase 0 scaffold placeholder.
 */

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// MVP analysis view: load a GoPro MP4 (+ optional FIT), process, and visualize.
///
/// **User flow:**
/// 1. "Open MP4…" → picks GoPro video → triggers full pipeline (GPMF + sync + fusion)
/// 2. (Optional) "Add FIT…" before or after opening MP4 to include FIT data
/// 3. Metric picker selects which channel to display in the chart
/// 4. Play/Pause + scrub slider drives the playhead cursor on the chart
///
/// This view is intentionally minimal. The infinite canvas and multi-widget layout
/// arrive in Phase 6 (`RowingDeskCanvas`).
public struct ContentView: View {

    @StateObject private var dataContext = DataContext()
    @StateObject private var playhead = PlayheadController()

    @State private var fitURL: URL? = nil
    @State private var isProcessing = false
    @State private var errorMessage: String? = nil
    @State private var pendingVideoURL: URL? = nil

    private let availableMetrics: [(key: String, label: String)] = [
        ("fus_cal_ts_vel_inertial", "Velocity — fused (m/s)"),
        ("gps_gpmf_ts_speed",       "GPS Speed (m/s)"),
        ("imu_raw_ts_acc_surge",    "Surge Accel — raw (m/s²)"),
        ("imu_flt_ts_acc_surge",    "Surge Accel — filtered (m/s²)"),
        ("phys_ext_ts_hr",          "Heart Rate (bpm)"),
    ]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            toolbar

            Group {
                if let timestamps = dataContext.timestamps,
                   let values = dataContext.selectedValues {
                    LineChartWidget(
                        timestamps: timestamps,
                        values: values,
                        playheadTimeMs: playhead.currentTimeMs,
                        viewportMs: 0...max(dataContext.sessionDurationMs, 1)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptyState
                }
            }

            if dataContext.buffers != nil {
                playbackControls
            }
        }
        .frame(minWidth: 900, minHeight: 520)
        .alert("Processing Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button("Open MP4…") { openVideoPanel() }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)

            Button("Add FIT…") { openFitPanel() }
                .disabled(isProcessing)

            if let fitName = fitURL?.lastPathComponent {
                Label(fitName, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .lineLimit(1)
            }

            Divider()

            Picker("Metric", selection: $dataContext.selectedMetric) {
                ForEach(availableMetrics, id: \.key) { m in
                    Text(m.label).tag(m.key)
                }
            }
            .frame(width: 240)
            .disabled(dataContext.buffers == nil)

            Spacer()

            if isProcessing {
                ProgressView()
                    .scaleEffect(0.7)
                    .padding(.trailing, 4)
                Text("Processing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let r = dataContext.fusionResult {
                sessionSummary(r)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Open a GoPro MP4 to start")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Optionally add a FIT file before opening the video.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack(spacing: 16) {
            Button {
                playhead.isPlaying ? playhead.pause() : playhead.play()
            } label: {
                Image(systemName: playhead.isPlaying ? "pause.fill" : "play.fill")
            }
            .keyboardShortcut(.space, modifiers: [])
            .buttonStyle(.plain)

            Button {
                playhead.reset()
            } label: {
                Image(systemName: "backward.end.fill")
            }
            .buttonStyle(.plain)

            Slider(
                value: Binding(
                    get: { playhead.currentTimeMs },
                    set: { playhead.seek(to: $0) }
                ),
                in: 0...max(playhead.duration, 1)
            )

            Text(formatTime(playhead.currentTimeMs))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)

            Text("/ \(formatTime(playhead.duration))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 72, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Session Summary Badge

    private func sessionSummary(_ result: FusionResult) -> some View {
        let validStrokes = result.strokes.filter(\.isValid).count
        let avgRate = result.diagnostics.avgStrokeRate.map {
            String(format: " · %.0f SPM", $0)
        } ?? ""

        return HStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg")
            Text("\(validStrokes) strokes\(avgRate)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - File Panels (NSOpenPanel — more reliable than .fileImporter on macOS SPM builds)

    private func openVideoPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open GoPro MP4"
        panel.allowedContentTypes = [.mpeg4Movie, .movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingVideoURL = url
        runProcessing(videoURL: url)
    }

    private func openFitPanel() {
        let panel = NSOpenPanel()
        panel.title = "Add FIT File"
        panel.allowedContentTypes = [UTType(filenameExtension: "fit") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        fitURL = url
        if let video = pendingVideoURL {
            runProcessing(videoURL: video)
        }
    }

    private func runProcessing(videoURL: URL) {
        guard !isProcessing else { return }
        isProcessing = true
        playhead.reset()

        Task {
            do {
                try await FileImportHelper.process(
                    videoURL: videoURL,
                    fitURL: fitURL,
                    dataContext: dataContext,
                    playhead: playhead
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isProcessing = false
        }
    }

    // MARK: - Helpers

    private func formatTime(_ ms: Double) -> String {
        let totalMs = max(0, ms)
        let totalSec = Int(totalMs / 1000)
        let m = totalSec / 60
        let s = totalSec % 60
        let tenths = Int((totalMs.truncatingRemainder(dividingBy: 1000)) / 100)
        return String(format: "%d:%02d.%d", m, s, tenths)
    }
}
