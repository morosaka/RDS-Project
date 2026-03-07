// Rendering/PlayheadControllerTests.swift v1.0.0
/**
 * Tests for PlayheadController seek, play/pause, and state management.
 * CVDisplayLink is NOT started in tests (no display available in CI).
 * --- Revision History ---
 * v1.0.0 - 2026-03-07 - Initial implementation (Phase 4: Rendering + MVP).
 */

import Foundation
import Testing
@testable import RowDataStudio

@Suite("PlayheadController")
@MainActor
struct PlayheadControllerTests {

    // MARK: - Initial State

    @Test("Initial position is zero")
    func initialPosition() {
        let ph = PlayheadController()
        #expect(ph.currentTimeMs == 0)
    }

    @Test("Initial isPlaying is false")
    func initialNotPlaying() {
        let ph = PlayheadController()
        #expect(ph.isPlaying == false)
    }

    @Test("Initial duration is zero")
    func initialDuration() {
        let ph = PlayheadController()
        #expect(ph.duration == 0)
    }

    // MARK: - Seek

    @Test("seek() updates currentTimeMs")
    func seekUpdatesPosition() {
        let ph = PlayheadController()
        ph.duration = 10_000
        ph.seek(to: 5_000)
        #expect(ph.currentTimeMs == 5_000)
    }

    @Test("seek() clamps to zero when negative")
    func seekClampsToZero() {
        let ph = PlayheadController()
        ph.duration = 10_000
        ph.seek(to: -500)
        #expect(ph.currentTimeMs == 0)
    }

    @Test("seek() clamps to duration when exceeding it")
    func seekClampsToDuration() {
        let ph = PlayheadController()
        ph.duration = 5_000
        ph.seek(to: 99_999)
        #expect(ph.currentTimeMs == 5_000)
    }

    @Test("seek() to exact duration is valid")
    func seekToExactDuration() {
        let ph = PlayheadController()
        ph.duration = 3_000
        ph.seek(to: 3_000)
        #expect(ph.currentTimeMs == 3_000)
    }

    // MARK: - Play / Pause

    @Test("play() sets isPlaying to true")
    func playSetsFlagTrue() {
        let ph = PlayheadController()
        ph.duration = 10_000
        ph.play()
        #expect(ph.isPlaying == true)
        ph.pause()  // cleanup
    }

    @Test("pause() sets isPlaying to false")
    func pauseSetsFlagFalse() {
        let ph = PlayheadController()
        ph.duration = 10_000
        ph.play()
        ph.pause()
        #expect(ph.isPlaying == false)
    }

    @Test("play() is idempotent when already playing")
    func playIdempotent() {
        let ph = PlayheadController()
        ph.duration = 10_000
        ph.play()
        ph.play()  // second call should be a no-op
        #expect(ph.isPlaying == true)
        ph.pause()
    }

    @Test("pause() is safe when not playing")
    func pauseWhenNotPlaying() {
        let ph = PlayheadController()
        ph.pause()  // should not crash
        #expect(ph.isPlaying == false)
    }

    @Test("play() does nothing when duration is zero")
    func playDoesNothingWithZeroDuration() {
        let ph = PlayheadController()
        ph.duration = 0
        ph.play()
        // duration == 0 means currentTimeMs (0) >= duration (0), so play() returns early
        #expect(ph.isPlaying == false)
    }

    @Test("play() does nothing when at end of session")
    func playDoesNothingAtEnd() {
        let ph = PlayheadController()
        ph.duration = 5_000
        ph.seek(to: 5_000)
        ph.play()
        #expect(ph.isPlaying == false)
    }

    // MARK: - Reset

    @Test("reset() sets position to zero and stops playback")
    func resetClearsState() {
        let ph = PlayheadController()
        ph.duration = 10_000
        ph.seek(to: 3_000)
        ph.play()
        ph.reset()

        #expect(ph.currentTimeMs == 0)
        #expect(ph.isPlaying == false)
    }

    // MARK: - Duration

    @Test("Duration change does not affect currentTimeMs")
    func durationChangeKeepsPosition() {
        let ph = PlayheadController()
        ph.duration = 10_000
        ph.seek(to: 4_000)
        ph.duration = 20_000
        #expect(ph.currentTimeMs == 4_000)
    }
}
