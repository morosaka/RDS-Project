// Tests/RowDataStudioTests/Core/Persistence/SessionStoreTests.swift v1.0.0
/**
 * Tests for SessionStore persistence layer.
 * --- Revision History ---
 * v1.0.0 - 2026-03-08 - Initial test suite (Phase 5: Session Management).
 */

import Foundation
import Testing

@testable import RowDataStudio

@Suite("SessionStore")
struct SessionStoreTests {

    @Test("Save and load session document")
    func saveAndLoadSession() async throws {
        let store = try SessionStore()

        // Create a test session
        let metadata = SessionMetadata(title: "Test Session", date: Date())
        let timeline = Timeline(duration: 300.0)
        let doc = SessionDocument(metadata: metadata, timeline: timeline)

        // Save the session
        try await store.save(doc)

        // Load it back
        let loaded = try await store.load(id: doc.metadata.id)

        // Verify content matches
        #expect(loaded.metadata.title == "Test Session")
        #expect(loaded.timeline.duration == 300.0)
        #expect(loaded.metadata.id == doc.metadata.id)
    }

    @Test("Session not found throws error")
    func sessionNotFound() async throws {
        let store = try SessionStore()
        let fakeID = UUID()

        do {
            _ = try await store.load(id: fakeID)
            #expect(Bool(false), "Expected SessionStoreError.sessionNotFound")
        } catch let error as SessionStoreError {
            guard case .sessionNotFound = error else {
                #expect(Bool(false), "Wrong error type")
                return
            }
        }
    }

    @Test("Check session existence")
    func sessionExists() async throws {
        let store = try SessionStore()

        // Create and save a session
        let doc = SessionDocument(
            metadata: SessionMetadata(title: "Exist Test"),
            timeline: Timeline(duration: 100.0)
        )
        try await store.save(doc)

        // Verify it exists
        let exists = try await store.exists(id: doc.metadata.id)
        #expect(exists == true)
    }

    @Test("Delete session")
    func deleteSession() async throws {
        let store = try SessionStore()

        // Create and save a session
        let doc = SessionDocument(
            metadata: SessionMetadata(title: "Delete Test"),
            timeline: Timeline(duration: 100.0)
        )
        try await store.save(doc)

        // Delete it
        try await store.delete(id: doc.metadata.id)

        // Verify it's gone
        let exists = try await store.exists(id: doc.metadata.id)
        #expect(exists == false)
    }
}
