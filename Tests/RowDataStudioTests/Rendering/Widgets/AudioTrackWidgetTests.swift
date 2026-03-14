// Tests/RowDataStudioTests/Rendering/Widgets/AudioTrackWidgetTests.swift
/**
 * Unit tests for AudioTrackWidget (Phase 8c.7).
 *
 * Tests cover:
 * - WidgetType.audio enum metadata
 * - RowingDeskCanvas.tracks(for:) returns correct TimelineTrack for audio widget
 * - peaksForViewport integration (via WaveformPeaks helper)
 * - WidgetState.make(type: .audio) creates correct configuration
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-14 - Initial implementation (Phase 8c.7).
 */

import Foundation
import Testing
@testable import RowDataStudio

@Suite("AudioTrackWidget")
struct AudioTrackWidgetTests {

    // MARK: - WidgetType.audio metadata

    @Test("WidgetType.audio has correct rawValue")
    func audioRawValue() {
        #expect(WidgetType.audio.rawValue == "audio")
    }

    @Test("WidgetType.audio has correct displayName")
    func audioDisplayName() {
        #expect(WidgetType.audio.displayName == "Audio Track")
    }

    @Test("WidgetType.audio has waveform icon")
    func audioIcon() {
        #expect(WidgetType.audio.icon == "waveform")
    }

    @Test("WidgetType.audio has correct default size (480×100)")
    func audioDefaultSize() {
        let size = WidgetType.audio.defaultSize
        #expect(size.width  == 480)
        #expect(size.height == 100)
    }

    @Test("WidgetType.audio is included in allCases")
    func audioInAllCases() {
        #expect(WidgetType.allCases.contains(.audio))
    }

    @Test("WidgetType.audio round-trips via rawValue")
    func audioRawValueRoundTrip() {
        #expect(WidgetType(rawValue: "audio") == .audio)
    }

    // MARK: - WidgetState.make for audio

    @Test("make(type: .audio) stores correct widgetType string")
    func makeAudioWidgetType() {
        let ws = WidgetState.make(type: .audio, position: .zero)
        #expect(ws.widgetType == "audio")
        #expect(ws.type       == .audio)
    }

    @Test("make(type: .audio) uses the 480×100 default size")
    func makeAudioDefaultSize() {
        let ws = WidgetState.make(type: .audio, position: .zero)
        #expect(ws.size == WidgetType.audio.defaultSize)
    }

    @Test("make(type: .audio) title defaults to 'Audio Track'")
    func makeAudioDefaultTitle() {
        let ws = WidgetState.make(type: .audio, position: .zero)
        #expect(ws.title == "Audio Track")
    }

    // MARK: - Track lifecycle: RowingDeskCanvas.tracks(for:)

    @Test("tracks(for: audio widget) returns exactly 1 track")
    func tracksForAudioCount() {
        let widget = WidgetState.make(type: .audio, position: .zero)
        let tracks = RowingDeskCanvas.tracks(for: widget)
        #expect(tracks.count == 1)
    }

    @Test("tracks(for: audio widget) returns an .audio stream track")
    func tracksForAudioStreamType() {
        let widget = WidgetState.make(type: .audio, position: .zero)
        let tracks = RowingDeskCanvas.tracks(for: widget)
        #expect(tracks[0].stream == .audio)
    }

    @Test("tracks(for: audio widget) links track to widget ID")
    func tracksForAudioLinkedWidgetID() {
        let widget = WidgetState.make(type: .audio, position: .zero)
        let tracks = RowingDeskCanvas.tracks(for: widget)
        #expect(tracks[0].linkedWidgetID == widget.id)
    }

    @Test("tracks(for: audio widget) sets displayName to 'Audio'")
    func tracksForAudioDisplayName() {
        let widget = WidgetState.make(type: .audio, position: .zero)
        let tracks = RowingDeskCanvas.tracks(for: widget)
        #expect(tracks[0].displayName == "Audio")
    }

    // MARK: - WaveformPeaks viewport integration

    @Test("peaksForViewport returns empty slice when WaveformPeaks has no bins")
    func viewportEmptyPeaks() {
        let emptyPeaks = WaveformPeaks(
            sampleRate:   48_000,
            totalSamples: 0,
            levels:       [[], [], [], [], []]
        )
        let result = emptyPeaks.peaksForViewport(viewportMs: 0...10_000, widthPixels: 480)
        #expect(result.peaks.isEmpty)
    }

    @Test("peaksForViewport with zero-width returns empty slice")
    func viewportZeroWidth() {
        let samples = ContiguousArray<Float>(repeating: 0.5, count: 1_024)
        let peaks   = WaveformGenerator.build(from: samples, sampleRate: 48_000)
        let result  = peaks.peaksForViewport(viewportMs: 0...1_000, widthPixels: 0)
        #expect(result.peaks.isEmpty)
    }

    @Test("peaksForViewport selects level 0 for a narrow viewport")
    func viewportSelectsLevel0ForNarrow() {
        // 5 seconds × 256 samples/bin = 3.2 bins/s at L0
        let samples = ContiguousArray<Float>(repeating: 0.5, count: 48_000 * 5)
        let peaks   = WaveformGenerator.build(from: samples, sampleRate: 48_000)
        // 480px for 5 s → samplesPerPixel = 500; L0 (256) ≤ 500 → picks L0 or coarser
        let result  = peaks.peaksForViewport(viewportMs: 0...5_000, widthPixels: 480)
        #expect(!result.peaks.isEmpty)
    }
}
