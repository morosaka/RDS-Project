// Core/Services/Sync/GpsSpeedCorrelator.swift v1.0.0
/**
 * Step 3A: FIT-GPMF alignment via GPS speed cross-correlation.
 * Finds temporal offset by correlating normalized speed series.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Foundation

/// Step 3A: GPS speed cross-correlation for FIT-GPMF alignment.
///
/// Correlates normalized GPS speed series from both sources to find
/// the temporal offset that maximizes agreement.
///
/// **Algorithm:**
/// 1. Resample GPMF GPS speed (10-18 Hz → 1 Hz) and FIT GPS speed (~1 Hz)
/// 2. Normalize both (mean=0, std=1)
/// 3. Cross-correlate on ±300s window at 1s steps
/// 4. Find peak and second peak (min 30s separation)
/// 5. Confidence = peak / secondPeak
///
/// Source: `docs/specs/sync-pipeline.md` §Step 3A
public struct GpsSpeedCorrelator {

    /// Confidence level for cross-validation.
    public enum Confidence: String, Sendable {
        case high    // peak/secondPeak >= 2.5
        case medium  // peak/secondPeak >= 1.5
        case low     // peak/secondPeak < 1.5
    }

    /// Speed correlator result.
    public struct Result: Sendable {
        /// Offset in milliseconds (positive = FIT starts after GPMF)
        public let offsetMs: Double
        /// Peak correlation value
        public let peakCorrelation: Double
        /// Confidence level
        public let confidence: Confidence
        /// Peak-to-second-peak ratio
        public let peakRatio: Double
    }

    /// Estimates FIT-GPMF temporal offset via speed cross-correlation.
    ///
    /// - Parameters:
    ///   - gpmfTimestampsMs: GPMF GPS timestamps (ms, relative to file start)
    ///   - gpmfSpeed: GPMF GPS speed (m/s)
    ///   - fitTimestampsMs: FIT record timestamps (ms, Unix epoch)
    ///   - fitSpeed: FIT GPS speed (m/s)
    /// - Returns: Correlation result, or nil if insufficient data.
    public static func correlate(
        gpmfTimestampsMs: ContiguousArray<Double>,
        gpmfSpeed: ContiguousArray<Float>,
        fitTimestampsMs: ContiguousArray<Double>,
        fitSpeed: ContiguousArray<Float>
    ) -> Result? {
        guard gpmfSpeed.count >= 10, fitSpeed.count >= 10 else { return nil }

        let step = SyncConstants.speedCorrResampleStepMs

        // Resample GPMF to 1 Hz
        let gpmfStart = gpmfTimestampsMs[0]
        let gpmfEnd = gpmfTimestampsMs[gpmfTimestampsMs.count - 1]
        let gpmfGridCount = Int((gpmfEnd - gpmfStart) / step) + 1
        guard gpmfGridCount >= 10 else { return nil }

        var gpmfResampled = ContiguousArray<Float>(repeating: .nan, count: gpmfGridCount)
        for i in 0..<gpmfGridCount {
            let t = gpmfStart + Double(i) * step
            gpmfResampled[i] = DSP.interpolateAt(
                timestamps: gpmfTimestampsMs, values: gpmfSpeed, targetTime: t
            )
        }

        // Resample FIT to 1 Hz
        let fitStart = fitTimestampsMs[0]
        let fitEnd = fitTimestampsMs[fitTimestampsMs.count - 1]
        let fitGridCount = Int((fitEnd - fitStart) / step) + 1
        guard fitGridCount >= 10 else { return nil }

        var fitResampled = ContiguousArray<Float>(repeating: .nan, count: fitGridCount)
        for i in 0..<fitGridCount {
            let t = fitStart + Double(i) * step
            fitResampled[i] = DSP.interpolateAt(
                timestamps: fitTimestampsMs, values: fitSpeed, targetTime: t
            )
        }

        // Normalize both (z-score)
        gpmfResampled = normalize(gpmfResampled)
        fitResampled = normalize(fitResampled)

        // Cross-correlate: slide FIT over GPMF
        let searchSteps = Int(SyncConstants.speedCorrSearchRangeMs / step)
        let minN = min(gpmfResampled.count, fitResampled.count)
        let minOverlap = max(minN / 3, 10)

        var scores = ContiguousArray<Double>(repeating: .nan, count: 2 * searchSteps + 1)
        var lags = ContiguousArray<Double>(repeating: 0, count: 2 * searchSteps + 1)

        for lagIdx in 0..<scores.count {
            let lag = lagIdx - searchSteps
            lags[lagIdx] = Double(lag) * step

            var sum: Double = 0
            var count = 0
            for i in 0..<minN {
                let j = i + lag
                guard j >= 0, j < fitResampled.count else { continue }
                let g = gpmfResampled[i]
                let f = fitResampled[j]
                guard !g.isNaN, !f.isNaN else { continue }
                sum += Double(g) * Double(f)
                count += 1
            }

            if count >= minOverlap {
                // Normalize by total signal length (not overlap count) to
                // favor larger overlaps — standard cross-correlation approach.
                scores[lagIdx] = sum / Double(minN)
            }
        }

        // Find peak
        var peakIdx = 0
        var peakVal = -Double.infinity
        for i in 0..<scores.count {
            if !scores[i].isNaN && scores[i] > peakVal {
                peakVal = scores[i]
                peakIdx = i
            }
        }
        guard !peakVal.isInfinite else { return nil }

        // Find second peak (min 30s separation)
        let minSepSteps = Int(SyncConstants.speedCorrMinPeakSeparationMs / step)
        var secondPeakVal = -Double.infinity
        for i in 0..<scores.count {
            if abs(i - peakIdx) >= minSepSteps && !scores[i].isNaN && scores[i] > secondPeakVal {
                secondPeakVal = scores[i]
            }
        }

        // Confidence
        let ratio: Double
        if secondPeakVal > 0 {
            ratio = peakVal / secondPeakVal
        } else {
            ratio = peakVal > 0 ? .infinity : 0
        }

        let confidence: Confidence
        if ratio >= SyncConstants.speedCorrHighConfidence {
            confidence = .high
        } else if ratio >= SyncConstants.speedCorrMediumConfidence {
            confidence = .medium
        } else {
            confidence = .low
        }

        // Offset = base timestamp difference + lag correction
        // The resampled grids start at gpmfStart and fitStart respectively.
        // A lag of L steps means gpmf[i] aligns with fit[i+L], so:
        // gpmfStart + i*step ↔ fitStart + (i+L)*step
        // offset = fitStart - gpmfStart + L*step
        let baseOffset = fitStart - gpmfStart
        return Result(
            offsetMs: baseOffset + lags[peakIdx],
            peakCorrelation: peakVal,
            confidence: confidence,
            peakRatio: ratio.isInfinite ? 999.0 : ratio
        )
    }

    // MARK: - Private Helpers

    /// Z-score normalization (mean=0, std=1). NaN-aware.
    private static func normalize(_ signal: ContiguousArray<Float>) -> ContiguousArray<Float> {
        let m = DSP.mean(signal)
        let s = DSP.standardDeviation(signal)
        guard !m.isNaN, !s.isNaN, s > 1e-10 else { return signal }

        var result = ContiguousArray<Float>(repeating: .nan, count: signal.count)
        for i in 0..<signal.count {
            if !signal[i].isNaN {
                result[i] = (signal[i] - m) / s
            }
        }
        return result
    }
}
