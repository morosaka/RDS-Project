// UI/ImportView.swift v1.0.0
/**
 * File import interface with drag-and-drop and file picker.
 *
 * Accepts:
 * - MP4 (GoPro video)
 * - FIT (Garmin/NK/Apple Watch)
 * - CSV (NK Empower/SpeedCoach/CrewNerd)
 *
 * On successful import, creates a SessionDocument and saves to SessionStore.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 5: Session Management).
 */

import SwiftUI

/// Manages file import with drag-and-drop and file picker.
public struct ImportView: View {
    @State private var isImporting = false
    @State private var importProgress: Double = 0
    @State private var importError: String?
    @State private var selectedFiles: [URL] = []
    @State private var importedSessionID: String?
    @Environment(\.dismiss) var dismiss

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let sessionID = importedSessionID {
                    successState(sessionID)
                } else if isImporting {
                    importingState
                } else if importError != nil {
                    errorState
                } else {
                    dropZoneAndPicker
                }
            }
            .padding()
            .navigationTitle("Import Session")
        }
    }

    @ViewBuilder
    private var dropZoneAndPicker: some View {
        VStack(spacing: 20) {
            // Drop zone
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)

                Text("Drag and drop files here")
                    .font(.headline)

                Text("or use the button below")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .background(Color.gray.opacity(0.15))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                    .foregroundColor(.accentColor)
            )
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDrop(providers: providers)
            }

            Divider()
                .padding(.vertical, 8)

            // File picker button
            FilePickerButton(onSelect: handleFileSelection)

            // Supported formats info
            VStack(alignment: .leading, spacing: 8) {
                Text("Supported formats:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Label("MP4 — GoPro HERO10+", systemImage: "video.fill")
                    Label("FIT — Garmin / NK / Apple Watch", systemImage: "heart.fill")
                    Label("CSV — NK Empower / SpeedCoach", systemImage: "tablecells")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.15))
            .cornerRadius(8)

            Spacer()
        }
    }

    private var importingState: some View {
        VStack(spacing: 16) {
            ProgressView(value: importProgress)
                .frame(height: 2)

            Text("Importing session...")
                .font(.headline)

            Text(String(format: "%.0f%%", importProgress * 100))
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
    }

    @ViewBuilder
    private func successState(_ sessionID: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("Session Imported")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your session has been created successfully")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                NavigationLink(destination: SessionListView()) {
                    Label("View All Sessions", systemImage: "list.bullet")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }

                Button(action: { resetImport() }) {
                    Label("Import Another", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.15))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var errorState: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)

            Text("Import Failed")
                .font(.title2)
                .fontWeight(.semibold)

            Text(importError ?? "Unknown error")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { resetImport() }) {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }

            Spacer()
        }
    }

    // MARK: - Handlers

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadFileRepresentation(forTypeIdentifier: "public.file-url") { url, error in
                if let url = url {
                    DispatchQueue.main.async {
                        handleFileSelection([url])
                    }
                }
            }
        }
        return true
    }

    private func handleFileSelection(_ urls: [URL]) {
        selectedFiles = urls
        importSessions()
    }

    private func importSessions() {
        guard !selectedFiles.isEmpty else { return }

        isImporting = true
        importProgress = 0
        importError = nil

        Task {
            do {
                for (index, fileURL) in selectedFiles.enumerated() {
                    // Detect file type
                    let dataSource = try await FileImporter.import(from: fileURL)

                    // Create session document
                    let metadata = SessionMetadata(
                        title: fileURL.deletingPathExtension().lastPathComponent,
                        date: Date()
                    )

                    let timeline = Timeline(duration: 0)  // Will be updated later during import

                    let session = SessionDocument(
                        metadata: metadata,
                        sources: [dataSource],
                        timeline: timeline
                    )

                    // Save to store
                    let store = try SessionStore()
                    try await store.save(session)

                    importedSessionID = session.metadata.id.uuidString

                    // Update progress
                    importProgress = Double(index + 1) / Double(selectedFiles.count)
                }

                isImporting = false
            } catch {
                isImporting = false
                importError = error.localizedDescription
            }
        }
    }

    private func resetImport() {
        selectedFiles = []
        importedSessionID = nil
        importProgress = 0
        importError = nil
    }
}

// MARK: - Helper Components

struct FilePickerButton: View {
    let onSelect: ([URL]) -> Void
    @State private var showFilePicker = false

    var body: some View {
        Button(action: { showFilePicker = true }) {
            Label("Choose Files", systemImage: "folder.open")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.15))
                .foregroundColor(.primary)
                .cornerRadius(8)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.video, .data],
            allowsMultipleSelection: true,
            onCompletion: { result in
                if case let .success(urls) = result {
                    onSelect(urls)
                }
            }
        )
    }
}

// MARK: - Dashed Border Modifier

extension View {
    fileprivate func border(
        style: StrokeStyle = StrokeStyle(lineWidth: 1, dash: [5]),
        color: Color = .gray
    ) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                .foregroundColor(color)
        )
    }
}

#Preview {
    ImportView()
}
