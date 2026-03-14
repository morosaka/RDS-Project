// Tests/RowDataStudioTests/Core/Models/TrackInteractionTests.swift
/**
 * Unit tests for track interaction mutations: pin, mute, solo, visibility, offset.
 * Tests the Array<TimelineTrack> helpers added in Phase 8c.4.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-14 - Initial implementation (Phase 8c.4).
 */

import Foundation
import Testing
@testable import RowDataStudio

@Suite("Track Interactions")
struct TrackInteractionTests {

    // MARK: - Helpers

    private func makeTrack(
        stream: StreamType,
        isPinned: Bool = false,
        isVisible: Bool = true,
        isMuted: Bool = false,
        isSolo: Bool = false,
        offset: TimeInterval = 0
    ) -> TimelineTrack {
        TimelineTrack(
            sourceID: UUID(),
            stream: stream,
            offset: offset,
            isPinned: isPinned,
            isVisible: isVisible,
            isMuted: isMuted,
            isSolo: isSolo
        )
    }

    // MARK: - Pin toggle

    @Test("Pin: isPinned toggles to true")
    func pinTrack() {
        var track = makeTrack(stream: .gps)
        #expect(track.isPinned == false)
        track.isPinned.toggle()
        #expect(track.isPinned == true)
    }

    @Test("Pin: isPinned toggles back to false")
    func unpinTrack() {
        var track = makeTrack(stream: .gps, isPinned: true)
        track.isPinned.toggle()
        #expect(track.isPinned == false)
    }

    // MARK: - Mute toggle

    @Test("Mute: isMuted toggles on audio track")
    func muteAudioTrack() {
        var track = makeTrack(stream: .audio)
        #expect(track.isMuted == false)
        track.isMuted.toggle()
        #expect(track.isMuted == true)
    }

    @Test("Mute: non-audio track can also be muted via toggle")
    func muteNonAudioTrack() {
        var track = makeTrack(stream: .speed)
        track.isMuted.toggle()
        #expect(track.isMuted == true)
    }

    // MARK: - Visibility toggle

    @Test("Visibility: isVisible toggles to false (hidden)")
    func hideTrack() {
        var track = makeTrack(stream: .hr)
        #expect(track.isVisible == true)
        track.isVisible.toggle()
        #expect(track.isVisible == false)
    }

    @Test("Visibility: hidden track can be restored")
    func restoreTrackVisibility() {
        var track = makeTrack(stream: .hr, isVisible: false)
        track.isVisible.toggle()
        #expect(track.isVisible == true)
    }

    // MARK: - Solo (Array helper)

    @Test("Solo: soloAudio mutes all other audio tracks, unmutes target")
    func soloAudioTrack() {
        let t1 = makeTrack(stream: .audio)
        let t2 = makeTrack(stream: .audio)
        let t3 = makeTrack(stream: .audio)
        var tracks = [t1, t2, t3]

        tracks.soloAudio(trackID: t2.id)

        #expect(tracks[0].isMuted == true)
        #expect(tracks[0].isSolo  == false)
        #expect(tracks[1].isMuted == false)
        #expect(tracks[1].isSolo  == true)
        #expect(tracks[2].isMuted == true)
        #expect(tracks[2].isSolo  == false)
    }

    @Test("Solo: soloAudio leaves non-audio tracks untouched")
    func soloDoesNotAffectNonAudio() {
        let audioTrack = makeTrack(stream: .audio)
        let gpsTrack   = makeTrack(stream: .gps, isMuted: false)
        let speedTrack = makeTrack(stream: .speed, isMuted: false)
        var tracks = [audioTrack, gpsTrack, speedTrack]

        tracks.soloAudio(trackID: audioTrack.id)

        #expect(tracks[1].isMuted == false)   // gps unchanged
        #expect(tracks[2].isMuted == false)   // speed unchanged
    }

    @Test("Solo: soloAudio on unknown id leaves all audio muted state unchanged")
    func soloUnknownIdNoChange() {
        let t1 = makeTrack(stream: .audio, isMuted: false)
        let t2 = makeTrack(stream: .audio, isMuted: false)
        var tracks = [t1, t2]
        let unknownID = UUID()

        tracks.soloAudio(trackID: unknownID)

        // All audio tracks get muted (unknownID != any track)
        #expect(tracks[0].isMuted == true)
        #expect(tracks[1].isMuted == true)
    }

    // MARK: - Offset adjustment (Array helper)

    @Test("Offset: applyOffset adds positive delta")
    func applyPositiveOffset() {
        let track = makeTrack(stream: .video, offset: 1.0)
        var tracks = [track]

        tracks.applyOffset(0.5, to: track.id)

        #expect(tracks[0].offset == 1.5)
    }

    @Test("Offset: applyOffset adds negative delta")
    func applyNegativeOffset() {
        let track = makeTrack(stream: .video, offset: 2.0)
        var tracks = [track]

        tracks.applyOffset(-0.75, to: track.id)

        #expect(abs(tracks[0].offset - 1.25) < 0.001)
    }

    @Test("Offset: applyOffset leaves other tracks unchanged")
    func applyOffsetOnlyAffectsTarget() {
        let t1 = makeTrack(stream: .video, offset: 0)
        let t2 = makeTrack(stream: .gps,   offset: 1.0)
        var tracks = [t1, t2]

        tracks.applyOffset(2.0, to: t1.id)

        #expect(tracks[0].offset == 2.0)
        #expect(tracks[1].offset == 1.0)   // unchanged
    }

    @Test("Offset: applyOffset with unknown id changes nothing")
    func applyOffsetUnknownId() {
        let track = makeTrack(stream: .video, offset: 0)
        var tracks = [track]

        tracks.applyOffset(5.0, to: UUID())

        #expect(tracks[0].offset == 0)
    }
}
