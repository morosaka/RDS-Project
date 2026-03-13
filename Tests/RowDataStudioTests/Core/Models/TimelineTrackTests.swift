import Testing
import Foundation
@testable import RowDataStudio

@Suite("TimelineTrack Tests")
struct TimelineTrackTests {

    @Test("TimelineTrack JSON Decoder backward compatibility")
    func backwardCompatDecoder() throws {
        let json = """
        {
            "id": "A4E9A4B3-CD0B-4813-A5B0-1A2B3C4D5E6F",
            "sourceID": "F0BB3EAC-FE47-4FB0-8C84-0B99BD76DFDE",
            "stream": "video",
            "offset": 1.5,
            "displayName": "Test Video"
        }
        """

        let jsonData = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let track = try decoder.decode(TimelineTrack.self, from: jsonData)

        #expect(track.id.uuidString == "A4E9A4B3-CD0B-4813-A5B0-1A2B3C4D5E6F")
        #expect(track.sourceID.uuidString == "F0BB3EAC-FE47-4FB0-8C84-0B99BD76DFDE")
        #expect(track.stream == .video)
        #expect(track.offset == 1.5)
        #expect(track.displayName == "Test Video")

        // Test the default values for the new NLE fields
        #expect(track.linkedWidgetID == nil)
        #expect(track.metricID == nil)
        #expect(track.isPinned == false)
        #expect(track.isVisible == true)
        #expect(track.isMuted == false)
        #expect(track.isSolo == false)
    }

    @Test("TimelineTrack Codable roundtrip with new NLE fields")
    func codableRoundtripNLE() throws {
        let original = TimelineTrack(
            id: UUID(),
            sourceID: UUID(),
            stream: .audio,
            offset: -0.5,
            displayName: "GoPro Audio",
            linkedWidgetID: UUID(),
            metricID: "audio_track_1",
            isPinned: true,
            isVisible: false,
            isMuted: true,
            isSolo: true
        )

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TimelineTrack.self, from: jsonData)

        #expect(decoded.id == original.id)
        #expect(decoded.sourceID == original.sourceID)
        #expect(decoded.stream == original.stream)
        #expect(decoded.offset == original.offset)
        #expect(decoded.displayName == original.displayName)
        #expect(decoded.linkedWidgetID == original.linkedWidgetID)
        #expect(decoded.metricID == original.metricID)
        #expect(decoded.isPinned == original.isPinned)
        #expect(decoded.isVisible == original.isVisible)
        #expect(decoded.isMuted == original.isMuted)
        #expect(decoded.isSolo == original.isSolo)
    }
}
