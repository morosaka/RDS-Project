// UI/SessionListView.swift v1.1.0
/**
 * Session list view with filtering, sorting, and navigation.
 *
 * Loads sessions from SessionStore, displays in list sorted by modification date.
 * Tapping a session navigates to SessionDetailView.
 * Delete action via trailing swipe.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 5: Session Management).
 */

import SwiftUI
#if os(macOS)
import AppKit
typealias UIColor = NSColor
#endif

/// Displays a list of saved sessions.
public struct SessionListView: View {
    public init() {}
    
    @State private var sessions: [SessionDocument] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedSessionID: UUID?
    @State private var showImport = false

    public var body: some View {
        NavigationStack {
            ZStack {
                if isLoading {
                    ProgressView("Loading sessions...")
                } else if sessions.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Sessions")
            .navigationDestination(isPresented: .constant(selectedSessionID != nil)) {
                if let id = selectedSessionID,
                   let session = sessions.first(where: { $0.metadata.id == id }) {
                    SessionDetailView(session: session)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showImport = true }) {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button(action: reload) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .navigationDestination(isPresented: $showImport) {
                ImportView()
            }
            .onAppear {
                reload()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.open")
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text("No Sessions")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Import a GoPro video to create a new session")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            NavigationLink(destination: ImportView()) {
                Label("Import Session", systemImage: "arrow.down.doc")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.white).opacity(0.05))
    }

    private var list: some View {
        List {
            ForEach(sessions, id: \.metadata.id) { session in
                Button(action: { selectedSessionID = session.metadata.id }) {
                    SessionRow(session: session)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        delete(session)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func reload() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let store = try SessionStore()
                let loaded = try await store.listAll()
                // Sort by modification date (newest first)
                sessions = loaded.sorted { $0.modifiedAt > $1.modifiedAt }
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func delete(_ session: SessionDocument) {
        Task {
            do {
                let store = try SessionStore()
                try await store.delete(id: session.metadata.id)
                reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    SessionListView()
}
