// Core/Models/WaveformPeaks.swift v1.0.0
/**
 * Multi-resolution peak envelope for audio waveform rendering.
 *
 * WaveformPeaks stores a 5-level pyramid of min/max peak pairs extracted from
 * an audio track. Lower levels (index 0) are finest resolution (256 samples/bin);
 * higher levels (index 4) are coarsest (65536 samples/bin). Each level is 4× coarser
 * than the previous, derived by taking the min-of-mins / max-of-maxes of 4 consecutive bins.
 *
 * The `peaksForViewport` method selects the optimal level for a given viewport width,
 * returning the slice of visible PeakPairs at approximately 1 bin per pixel.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-14 - Initial implementation (Phase 8c.6).
 */

import Foundation

// MARK: - PeakPair

/// A min/max amplitude pair for a single waveform bin.
public struct PeakPair: Codable, Sendable, Hashable {
    /// Minimum sample amplitude in this bin (negative for audio).
    public let min: Float
    /// Maximum sample amplitude in this bin.
    public let max: Float

    public init(min: Float, max: Float) {
        self.min = min
        self.max = max
    }
}

// MARK: - WaveformPeaks

/// Multi-resolution peak envelope for audio waveform rendering.
public struct WaveformPeaks: Codable, Sendable {

    /// Source audio sample rate in Hz (e.g. 48000).
    public let sampleRate: Int

    /// Total number of audio samples in the source.
    public let totalSamples: Int

    /// Peak pyramid. `levels[0]` = finest (256 samples/bin), `levels[4]` = coarsest (65536 samples/bin).
    public let levels: [[PeakPair]]

    /// Samples per bin for each pyramid level.
    /// levels[0] → 256,  levels[1] → 1024,  levels[2] → 4096,
    /// levels[3] → 16384,  levels[4] → 65536
    public static let samplesPerBin: [Int] = [256, 1_024, 4_096, 16_384, 65_536]

    public init(sampleRate: Int, totalSamples: Int, levels: [[PeakPair]]) {
        self.sampleRate   = sampleRate
        self.totalSamples = totalSamples
        self.levels       = levels
    }
}

// MARK: - Viewport selection

extension WaveformPeaks {

    /// Select the optimal pyramid level for the given viewport and return the visible slice.
    ///
    /// Chooses the coarsest level (fewest bins) that still provides ≥1 bin per pixel,
    /// then clips to the visible time range.
    ///
    /// - Parameters:
    ///   - viewportMs: Visible time range in milliseconds.
    ///   - widthPixels: Target render width in pixels (usually the view's width in points).
    /// - Returns: `levelIndex` (0 = finest) and `peaks` (visible slice of that level).
    public func peaksForViewport(
        viewportMs: ClosedRange<Double>,
        widthPixels: Int
    ) -> (levelIndex: Int, peaks: ArraySlice<PeakPair>) {
        guard !levels.isEmpty, widthPixels > 0, sampleRate > 0 else {
            return (0, [][...])
        }

        let visibleMs      = viewportMs.upperBound - viewportMs.lowerBound
        let visibleSamples = max(1, Int(visibleMs / 1_000.0 * Double(sampleRate)))
        let samplesPerPixel = max(1, visibleSamples / widthPixels)

        // Pick the coarsest level whose bin size ≤ samplesPerPixel.
        // This gives roughly ≥1 bin per pixel (crisp rendering without wasted overdraw).
        var levelIndex = 0
        for (i, spb) in WaveformPeaks.samplesPerBin.enumerated() where i < levels.count {
            if spb <= samplesPerPixel {
                levelIndex = i
            }
        }

        let spb    = WaveformPeaks.samplesPerBin[levelIndex]
        let level  = levels[levelIndex]

        // Clip to visible time range
        let startSample = max(0, Int(viewportMs.lowerBound / 1_000.0 * Double(sampleRate)))
        let endSample   = min(totalSamples, Int(viewportMs.upperBound / 1_000.0 * Double(sampleRate)))
        let startBin    = startSample / spb
        let endBin      = min(level.count, endSample / spb + 1)

        guard startBin < endBin, startBin < level.count else {
            return (levelIndex, [][...])
        }

        return (levelIndex, level[startBin..<endBin])
    }
}
