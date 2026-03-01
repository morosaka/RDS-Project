//
// SessionDocumentTests.swift
// RowData Studio Tests
//
// Tests for SessionDocument: Codable roundtrip, equality, accessors.
//
// Version: 1.0.0 (2026-03-01)
// Revision History:
//   2026-03-01: Initial implementation (Phase 1: Data Models)
//

import Testing
import Foundation
@testable import RowDataStudio

@Suite("SessionDocument Tests")
struct SessionDocumentTests {

    @Test("SessionDocument Codable roundtrip")
    func codableRoundtrip() throws {
        // Create a complex session document
        let metadata = SessionMetadata(
            title: "Test Session",
            date: Date(timeIntervalSince1970: 1709337600),  // Fixed date for reproducibility
            athletes: [
                Athlete(name: "Alice", seat: "Stroke", side: "Port"),
                Athlete(name: "Bob", seat: "Bow", side: "Starboard")
            ],
            notes: "Morning practice"
        )

        let videoID = UUID()
        let fitID = UUID()

        let sources: [DataSource] = [
            .goProVideo(id: videoID, url: URL(fileURLWithPath: "/path/to/video.mp4"), role: .primary),
            .fitFile(id: fitID, url: URL(fileURLWithPath: "/path/to/data.fit"), device: "NK SpeedCoach")
        ]

        let timeline = Timeline(
            duration: 600.0,
            absoluteOrigin: Date(timeIntervalSince1970: 1709338200),
            tracks: [
                TrackReference(sourceID: videoID, stream: .video, offset: 0.0),
                TrackReference(sourceID: fitID, stream: .hr, offset: -2.3)
            ]
        )

        let regions = [
            ROI(name: "Sprint", range: 120.0...385.0, tags: ["drill"], color: "#FF5733")
        ]

        let syncState = SyncState(
            gpmfToVideo: SyncResult(offset: 0.0, confidence: 0.95, strategy: .signMatch),
            fitToVideo: [
                fitID: SyncResult(offset: -2.3, confidence: 0.88, strategy: .gpsSpeedCorrelator)
            ]
        )

        let document = SessionDocument(
            metadata: metadata,
            sources: sources,
            timeline: timeline,
            regions: regions,
            syncState: syncState
        )

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(document)

        // Decode from JSON
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SessionDocument.self, from: jsonData)

        // Verify equality
        #expect(decoded == document)
        #expect(decoded.metadata.title == "Test Session")
        #expect(decoded.sources.count == 2)
        #expect(decoded.timeline.duration == 600.0)
        #expect(decoded.regions.count == 1)
        #expect(decoded.syncState.fitToVideo.count == 1)
    }

    @Test("SessionDocument primary video accessor")
    func primaryVideoAccessor() throws {
        let primaryID = UUID()
        let secondaryID = UUID()

        let document = SessionDocument(
            metadata: SessionMetadata(title: "Multi-Camera"),
            sources: [
                .goProVideo(id: secondaryID, url: URL(fileURLWithPath: "/secondary.mp4"), role: .secondary),
                .goProVideo(id: primaryID, url: URL(fileURLWithPath: "/primary.mp4"), role: .primary)
            ],
            timeline: Timeline(duration: 300.0)
        )

        let primary = document.primaryVideo
        #expect(primary != nil)

        if case .goProVideo(let id, _, let role) = primary! {
            #expect(id == primaryID)
            #expect(role == .primary)
        } else {
            Issue.record("Expected goProVideo")
        }
    }

    @Test("SessionDocument FIT sources accessor")
    func fitSourcesAccessor() throws {
        let fit1 = UUID()
        let fit2 = UUID()

        let document = SessionDocument(
            metadata: SessionMetadata(title: "Multi-Device"),
            sources: [
                .goProVideo(id: UUID(), url: URL(fileURLWithPath: "/video.mp4"), role: .primary),
                .fitFile(id: fit1, url: URL(fileURLWithPath: "/nk.fit"), device: "NK SpeedCoach"),
                .fitFile(id: fit2, url: URL(fileURLWithPath: "/garmin.fit"), device: "Garmin 965")
            ],
            timeline: Timeline(duration: 300.0)
        )

        let fitSources = document.fitSources
        #expect(fitSources.count == 2)
    }

    @Test("SessionDocument source lookup by ID")
    func sourceLookup() throws {
        let targetID = UUID()

        let document = SessionDocument(
            metadata: SessionMetadata(title: "Lookup Test"),
            sources: [
                .goProVideo(id: UUID(), url: URL(fileURLWithPath: "/video.mp4"), role: .primary),
                .fitFile(id: targetID, url: URL(fileURLWithPath: "/data.fit"), device: "NK SpeedCoach")
            ],
            timeline: Timeline(duration: 300.0)
        )

        let found = document.source(withID: targetID)
        #expect(found != nil)
        #expect(found?.id == targetID)

        let notFound = document.source(withID: UUID())
        #expect(notFound == nil)
    }
}
