// Tests/RowDataStudioTests/Core/Models/CueMarkerTests.swift
/**
 * Unit tests for CueMarker model: init, Codable round-trip,
 * and SessionDocument backward-compat decode.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-14 - Initial implementation (Phase 8c.5).
 */

import Foundation
import Testing
@testable import RowDataStudio

@Suite("CueMarker")
struct CueMarkerTests {

    // MARK: - Model init

    @Test("CueMarker init stores all fields")
    func cueMarkerInit() {
        let id        = UUID()
        let created   = Date(timeIntervalSince1970: 1_000_000)
        let cue       = CueMarker(id: id, timeMs: 12_345.6, label: "Sprint Start",
                                  color: "#FF9F0A", createdAt: created)

        #expect(cue.id       == id)
        #expect(cue.timeMs   == 12_345.6)
        #expect(cue.label    == "Sprint Start")
        #expect(cue.color    == "#FF9F0A")
        #expect(cue.createdAt == created)
    }

    @Test("CueMarker default color is nil")
    func cueMarkerDefaultColor() {
        let cue = CueMarker(timeMs: 0, label: "Test")
        #expect(cue.color == nil)
    }

    // MARK: - Codable round-trip

    @Test("CueMarker Codable round-trip preserves all fields")
    func cueMarkerRoundTrip() throws {
        let original = CueMarker(
            id:        UUID(),
            timeMs:    99_000.0,
            label:     "Finish Line",
            color:     "#30D158",
            createdAt: Date(timeIntervalSince1970: 2_000_000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(CueMarker.self, from: data)

        #expect(decoded.id        == original.id)
        #expect(decoded.timeMs    == original.timeMs)
        #expect(decoded.label     == original.label)
        #expect(decoded.color     == original.color)
        #expect(decoded.createdAt == original.createdAt)
    }

    // MARK: - SessionDocument backward compat

    @Test("SessionDocument without cueMarkers key decodes to empty array")
    func sessionDocumentBackwardCompat() throws {
        // Encode a document that has cueMarkers, then strip the key to simulate
        // a pre-8c.5 document, and verify decoding falls back to [].
        var original = SessionDocument(
            metadata: SessionMetadata(title: "Legacy Session"),
            timeline: Timeline(duration: 600)
        )
        original.cueMarkers = [CueMarker(timeMs: 1000, label: "Old Cue")]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(original)

        // Strip "cueMarkers" key from the JSON dictionary
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        dict.removeValue(forKey: "cueMarkers")
        let strippedData = try JSONSerialization.data(withJSONObject: dict)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let doc = try decoder.decode(SessionDocument.self, from: strippedData)

        #expect(doc.cueMarkers.isEmpty)
        #expect(doc.metadata.title == "Legacy Session")
    }

    @Test("SessionDocument with cueMarkers round-trips correctly")
    func sessionDocumentWithCues() throws {
        let cue1 = CueMarker(timeMs: 5_000, label: "Cue 1")
        let cue2 = CueMarker(timeMs: 15_000, label: "Cue 2", color: "#FF453A")

        var doc = SessionDocument(
            metadata: SessionMetadata(title: "Cue Test"),
            timeline: Timeline(duration: 60)
        )
        doc.cueMarkers = [cue1, cue2]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(doc)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(SessionDocument.self, from: data)

        #expect(decoded.cueMarkers.count == 2)
        #expect(decoded.cueMarkers[0].label  == "Cue 1")
        #expect(decoded.cueMarkers[1].color  == "#FF453A")
    }

    @Test("CueMarker identifiable: unique ids for distinct markers")
    func cueMarkerUniqueIDs() {
        let a = CueMarker(timeMs: 1000, label: "A")
        let b = CueMarker(timeMs: 1000, label: "B")   // same time, different marker
        #expect(a.id != b.id)
    }
}
