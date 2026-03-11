// UI/SessionDetailView.swift v1.1.0
/**
 * Session detail view with metadata, data sources, and action buttons.
 *
 * Displays:
 * - Session name, creation date, duration
 * - List of data sources (video, FIT, CSV)
 * - Open session button to load into canvas
 *
 * --- Revision History ---
 * v1.1.0 - 2026-03-11 - Connect data pipeline: openSession() now calls FileImportHelper.process()
 *                        to populate DataContext.buffers before navigating to canvas.
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 5: Session Management).
 */

import SwiftUI

/// Displays detailed information about a session.
public struct SessionDetailView: View {
    public init(session: SessionDocument) {
        self.session = session
    }
    
    let session: SessionDocument
    @Environment(\.dismiss) var dismiss
    @State private var openInCanvas = false
    @State private var isProcessing = false
    @State private var processingError: String?
    @StateObject private var dataContext = DataContext()
    @StateObject private var playheadController = PlayheadController()

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.metadata.title)
                        .font(.title2)
                        .fontWeight(.semibold)

                    HStack(spacing: 16) {
                        Label(formattedDate(session.metadata.date), systemImage: "calendar")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Label(formattedDuration(session.timeline.duration), systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.15))
                .cornerRadius(8)

                // Data Sources
                VStack(alignment: .leading, spacing: 12) {
                    Text("Data Sources")
                        .font(.headline)

                    if session.sources.isEmpty {
                        Text("No data sources")
                            .font(.body)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(session.sources, id: \.id) { source in
                            dataSourceRow(source)
                        }
                    }
                }
                .padding()

                // Canvas State
                VStack(alignment: .leading, spacing: 12) {
                    Text("Canvas Layout")
                        .font(.headline)

                    HStack(spacing: 16) {
                        Label(
                            "\(session.canvas.widgets.count) widget\(session.canvas.widgets.count == 1 ? "" : "s")",
                            systemImage: "square.grid.2x2"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)

                        Spacer()
                    }
                }
                .padding()

                // Empower data (if available)
                if session.empowerData != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Empower Data")
                            .font(.headline)

                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("NK Biomechanics Available")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }
                    .padding()
                }

                // Processing error
                if let error = processingError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: { Task { await openSession() } }) {
                        if isProcessing {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Processing data...")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor.opacity(0.5))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        } else {
                            Label("Open Session", systemImage: "arrow.right")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                    .disabled(isProcessing)

                    Button(action: { exportSession() }) {
                        Label("Export Data", systemImage: "arrow.up.doc")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(8)
                    }
                    .disabled(isProcessing)
                }
                .padding()

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Session Details")
        .navigationDestination(isPresented: $openInCanvas) {
            RowingDeskCanvas(
                dataContext: dataContext,
                playheadController: playheadController
            )
        }
    }

    @ViewBuilder
    private func dataSourceRow(_ source: DataSource) -> some View {
        HStack(spacing: 12) {
            Image(systemName: sourceIcon(source))
                .frame(width: 24)
                .font(.body)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(sourceName(source))
                    .font(.body)
                    .fontWeight(.semibold)

                Text(source.url.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if let device = sourceDevice(source) {
                    Text(device)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(8)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(6)
    }

    private func sourceIcon(_ source: DataSource) -> String {
        switch source {
        case .goProVideo:
            return "video.fill"
        case .fitFile:
            return "heart.fill"
        case .csvFile:
            return "tablecells"
        case .sidecar:
            return "archivebox.fill"
        }
    }

    private func sourceName(_ source: DataSource) -> String {
        switch source {
        case .goProVideo:
            return "GoPro Video"
        case .fitFile:
            return "FIT File"
        case .csvFile:
            return "CSV Data"
        case .sidecar:
            return "Telemetry Sidecar"
        }
    }

    private func sourceDevice(_ source: DataSource) -> String? {
        switch source {
        case .fitFile(_, _, let device):
            return device
        case .csvFile(_, _, let device):
            return device
        default:
            return nil
        }
    }


    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func openSession() async {
        isProcessing = true
        processingError = nil

        // 1. Set the session document (provides widget layout + source URLs)
        dataContext.sessionDocument = session

        // 2. Extract video URL (required for GPMF telemetry)
        guard let videoSource = session.sources.first(where: {
            if case .goProVideo = $0 { return true }
            return false
        }) else {
            // No video source — open canvas anyway (may have FIT/CSV only)
            isProcessing = false
            openInCanvas = true
            return
        }

        // 3. Extract optional FIT URL
        let fitURL: URL? = session.sources.compactMap { source -> URL? in
            if case .fitFile(_, let url, _) = source { return url }
            return nil
        }.first

        // 4. Run the full processing pipeline (GPMF → FIT → Sync → Fusion)
        do {
            try await FileImportHelper.process(
                videoURL: videoSource.url,
                fitURL: fitURL,
                dataContext: dataContext,
                playhead: playheadController
            )
        } catch {
            processingError = error.localizedDescription
            // Still allow opening canvas — video will work, data widgets will show empty
        }

        isProcessing = false
        openInCanvas = true
    }

    private func exportSession() {
        // Phase 8: Export functionality (CSV, PDF, GPX)
        print("Export session: \(session.metadata.title)")
    }
}

#Preview {
    let mockSession = SessionDocument(
        metadata: SessionMetadata(
            title: "Venice Row 2026-03-08",
            date: Date()
        ),
        sources: [
            .goProVideo(id: UUID(), url: URL(fileURLWithPath: "/tmp/GX030230.MP4"), role: .primary),
            .fitFile(id: UUID(), url: URL(fileURLWithPath: "/tmp/session.fit"), device: "NK SpeedCoach")
        ],
        timeline: Timeline(duration: 385)
    )

    return NavigationStack {
        SessionDetailView(session: mockSession)
    }
}
