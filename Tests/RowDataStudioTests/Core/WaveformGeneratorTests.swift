// Tests/RowDataStudioTests/Core/WaveformGeneratorTests.swift
/**
 * Unit tests for WaveformGenerator and WaveformPeaks.
 * All tests operate on synthetic Float32 buffers — no real video file required.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-14 - Initial implementation (Phase 8c.6).
 */

import Foundation
import Testing
@testable import RowDataStudio

@Suite("WaveformGenerator")
struct WaveformGeneratorTests {

    // MARK: - Helpers

    /// Generates a synthetic sine-wave buffer: `count` Float32 samples, amplitude ±1.
    private func sineBuffer(count: Int, frequency: Float = 440, sampleRate: Float = 48_000) -> ContiguousArray<Float> {
        var buf = ContiguousArray<Float>(repeating: 0, count: count)
        for i in 0..<count {
            buf[i] = sin(2 * .pi * frequency * Float(i) / sampleRate)
        }
        return buf
    }

    // MARK: - Level 0 bin count

    @Test("Level 0 has correct number of bins for exact multiple")
    func level0BinCountExact() {
        // 1024 samples / 256 samples/bin = 4 bins (no tail)
        let samples = sineBuffer(count: 1_024)
        let peaks = WaveformGenerator.build(from: samples, sampleRate: 48_000)

        #expect(peaks.levels.count == WaveformPeaks.samplesPerBin.count)
        #expect(peaks.levels[0].count == 4)
    }

    @Test("Level 0 has ceil bins when sample count is not a multiple of 256")
    func level0BinCountWithTail() {
        // 300 samples → 1 full bin (256) + 1 tail bin (44) = 2 bins
        let samples = sineBuffer(count: 300)
        let peaks = WaveformGenerator.build(from: samples, sampleRate: 48_000)

        #expect(peaks.levels[0].count == 2)
    }

    // MARK: - Level 0 min/max correctness

    @Test("Level 0 min is <= 0 and max >= 0 for sine wave")
    func level0MinMaxSineWave() {
        // Sine wave amplitude ±1: each 256-sample bin should span both sides
        let samples = sineBuffer(count: 256 * 10)
        let peaks = WaveformGenerator.build(from: samples, sampleRate: 48_000)

        for pair in peaks.levels[0] {
            #expect(pair.min <= 0)
            #expect(pair.max >= 0)
            #expect(pair.min <= pair.max)
        }
    }

    @Test("Level 0 max is ~1.0 for a full-amplitude sine wave bin")
    func level0MaxApproxOne() {
        // A 256-sample sine at 440 Hz / 48000 Hz: peak will be < 1.0 but > 0.9
        let samples = sineBuffer(count: 256)
        let peaks = WaveformGenerator.build(from: samples, sampleRate: 48_000)

        #expect(peaks.levels[0][0].max > 0.9)
        #expect(peaks.levels[0][0].max <= 1.0)
    }

    // MARK: - Level derivation

    @Test("Level 1 count is ¼ of level 0 count (for exact multiples of 4)")
    func levelDerivationCount() {
        // 4096 samples / 256 = 16 bins at L0; 16 / 4 = 4 bins at L1
        let samples = sineBuffer(count: 4_096)
        let peaks = WaveformGenerator.build(from: samples, sampleRate: 48_000)

        #expect(peaks.levels[0].count == 16)
        #expect(peaks.levels[1].count == 4)
    }

    @Test("Level 1 min is <= minimum of its 4 source bins")
    func levelDerivationMinIsMinOfMins() {
        // Build directly with a known L0 to verify L1 derivation logic
        let samples = sineBuffer(count: 256 * 4)  // exactly 4 L0 bins
        let peaks = WaveformGenerator.build(from: samples, sampleRate: 48_000)

        let l0 = peaks.levels[0]
        let l1 = peaks.levels[1]
        #expect(l1.count == 1)

        let expectedMin = min(l0[0].min, l0[1].min, l0[2].min, l0[3].min)
        let expectedMax = max(l0[0].max, l0[1].max, l0[2].max, l0[3].max)
        #expect(abs(l1[0].min - expectedMin) < 1e-6)
        #expect(abs(l1[0].max - expectedMax) < 1e-6)
    }

    // MARK: - WaveformPeaks metadata

    @Test("WaveformPeaks stores correct sampleRate and totalSamples")
    func waveformPeaksMetadata() {
        let samples = sineBuffer(count: 10_000)
        let peaks = WaveformGenerator.build(from: samples, sampleRate: 44_100)

        #expect(peaks.sampleRate   == 44_100)
        #expect(peaks.totalSamples == 10_000)
    }

    // MARK: - peaksForViewport

    @Test("peaksForViewport selects level 0 (finest) when zoomed in")
    func viewportSelectsLevel0WhenZoomedIn() {
        // 10 sec of audio at 48kHz = 480_000 samples
        let samples = sineBuffer(count: 480_000)
        let peaks = WaveformGenerator.build(from: samples, sampleRate: 48_000)

        // Viewport: 1 second = 1000 ms, 800 pixels wide
        // visibleSamples = 48_000, samplesPerPixel = 60
        // Level 0 (256 spb) > 60 → don't pick; stays at 0
        let result = peaks.peaksForViewport(viewportMs: 0...1_000, widthPixels: 800)

        #expect(result.levelIndex == 0)
        #expect(!result.peaks.isEmpty)
    }

    @Test("peaksForViewport selects coarser level when zoomed out")
    func viewportSelectsCoarserLevelWhenZoomedOut() {
        // 10 min at 48kHz = 28_800_000 samples
        let samples = ContiguousArray<Float>(repeating: 0.5, count: 28_800_000)
        let peaks = WaveformGenerator.build(from: samples, sampleRate: 48_000)

        // Viewport: full 10 min = 600_000 ms, 1200 pixels wide
        // visibleSamples = 28_800_000, samplesPerPixel = 24_000
        // Level 3 (16384 spb ≤ 24000) → should pick level 3
        let result = peaks.peaksForViewport(viewportMs: 0...600_000, widthPixels: 1_200)

        #expect(result.levelIndex >= 3)
    }

    @Test("peaksForViewport clips to visible time range")
    func viewportClipsToRange() {
        // 10 sec at 48kHz = 480_000 samples → 1875 L0 bins
        let samples = sineBuffer(count: 480_000)
        let peaks = WaveformGenerator.build(from: samples, sampleRate: 48_000)

        // Full viewport → all L0 bins
        let fullResult = peaks.peaksForViewport(viewportMs: 0...10_000, widthPixels: 2_000)
        // Half viewport → ~half the bins
        let halfResult = peaks.peaksForViewport(viewportMs: 0...5_000, widthPixels: 2_000)

        #expect(halfResult.peaks.count < fullResult.peaks.count)
    }

    // MARK: - PeakPair Codable round-trip

    @Test("PeakPair Codable round-trip")
    func peakPairRoundTrip() throws {
        let pair = PeakPair(min: -0.75, max: 0.85)
        let data = try JSONEncoder().encode(pair)
        let decoded = try JSONDecoder().decode(PeakPair.self, from: data)

        #expect(abs(decoded.min - pair.min) < 1e-6)
        #expect(abs(decoded.max - pair.max) < 1e-6)
    }

    @Test("WaveformPeaks Codable round-trip preserves all levels")
    func waveformPeaksRoundTrip() throws {
        let samples = sineBuffer(count: 4_096)
        let original = WaveformGenerator.build(from: samples, sampleRate: 48_000)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WaveformPeaks.self, from: data)

        #expect(decoded.sampleRate    == original.sampleRate)
        #expect(decoded.totalSamples  == original.totalSamples)
        #expect(decoded.levels.count  == original.levels.count)
        #expect(decoded.levels[0].count == original.levels[0].count)
    }
}
