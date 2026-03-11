// UI/SessionRow.swift v1.0.0
/**
 * Single row component for session list display.
 *
 * Displays session metadata: name, date, duration, source count.
 * Tappable to navigate to detail view.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 5: Session Management).
 */

import SwiftUI

/// Displays a single session in a list.
public struct SessionRow: View {
    public init(session: SessionDocument) {
        self.session = session
    }
    
    let session: SessionDocument

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                // Session title
                Text(session.metadata.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                // Source count badge
                Text("\(session.sources.count) source\(session.sources.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
            }

            // Metadata row: date + duration
            HStack(spacing: 12) {
                Label {
                    Text(formattedDate(session.metadata.date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } icon: {
                    Image(systemName: "calendar")
                        .font(.caption)
                }

                Label {
                    Text(formattedDuration(session.timeline.duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } icon: {
                    Image(systemName: "clock")
                        .font(.caption)
                }

                Spacer()
            }
        }
        .padding(.vertical, 8)
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
}

#Preview {
    let mockSession = SessionDocument(
        metadata: SessionMetadata(
            title: "Venice Row 2026-03-08",
            date: Date()
        ),
        sources: [
            .goProVideo(id: UUID(), url: URL(fileURLWithPath: "/tmp/GX030230.MP4"), role: .primary)
        ],
        timeline: Timeline(duration: 385)
    )

    return SessionRow(session: mockSession)
        .padding()
}
