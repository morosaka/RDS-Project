// Core/Services/Sync/GpsTrackCorrelator.swift v1.0.0
/**
 * Step 3B: FIT-GPMF alignment via GPS track Haversine distance minimization.
 * Two-phase search: coarse (1s steps) then fine (100ms steps).
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Foundation

/// Step 3B: GPS track correlator for FIT-GPMF alignment.
///
/// Finds the temporal offset that minimizes the average Haversine distance
/// between GPS positions from GPMF and FIT at matching timestamps.
///
/// **Algorithm:**
/// 1. Coarse: scan ±300s at 1s steps → find minimum distance
/// 2. Fine: scan ±5s around coarse minimum at 100ms steps
///
/// Source: `docs/specs/sync-pipeline.md` §Step 3B
public struct GpsTrackCorrelator {

    /// Track correlator result.
    public struct Result: Sendable {
        /// Offset in milliseconds (positive = FIT starts after GPMF)
        public let offsetMs: Double
        /// Average Haversine distance at best offset (meters)
        public let avgDistanceM: Double
        /// Average distance at zero offset for comparison (meters)
        public let zeroOffsetDistanceM: Double
        /// Improvement ratio (zeroOffset / bestOffset)
        public let improvementRatio: Double
    }

    /// Estimates FIT-GPMF temporal offset via GPS track distance minimization.
    ///
    /// - Parameters:
    ///   - gpmfTimestampsMs: GPMF GPS timestamps (ms, relative to file start)
    ///   - gpmfLat: GPMF latitudes (degrees)
    ///   - gpmfLon: GPMF longitudes (degrees)
    ///   - fitTimestampsMs: FIT record timestamps (ms, Unix epoch)
    ///   - fitLat: FIT latitudes (degrees)
    ///   - fitLon: FIT longitudes (degrees)
    /// - Returns: Track correlation result, or nil if insufficient data.
    public static func correlate(
        gpmfTimestampsMs: ContiguousArray<Double>,
        gpmfLat: ContiguousArray<Double>,
        gpmfLon: ContiguousArray<Double>,
        fitTimestampsMs: ContiguousArray<Double>,
        fitLat: ContiguousArray<Double>,
        fitLon: ContiguousArray<Double>
    ) -> Result? {
        guard gpmfLat.count >= 5, fitLat.count >= 5 else { return nil }

        // Phase 1: Coarse scan
        let coarseResult = scan(
            gpmfTimestampsMs: gpmfTimestampsMs, gpmfLat: gpmfLat, gpmfLon: gpmfLon,
            fitTimestampsMs: fitTimestampsMs, fitLat: fitLat, fitLon: fitLon,
            rangeMs: SyncConstants.trackCorrCoarseRangeMs,
            stepMs: SyncConstants.trackCorrCoarseStepMs
        )
        guard let coarse = coarseResult else { return nil }

        // Phase 2: Fine scan around coarse minimum
        let fineResult = scan(
            gpmfTimestampsMs: gpmfTimestampsMs, gpmfLat: gpmfLat, gpmfLon: gpmfLon,
            fitTimestampsMs: fitTimestampsMs, fitLat: fitLat, fitLon: fitLon,
            rangeMs: SyncConstants.trackCorrFineRangeMs,
            stepMs: SyncConstants.trackCorrFineStepMs,
            centerOffsetMs: coarse.offsetMs
        )
        let best = fineResult ?? coarse

        // Distance at zero offset for comparison
        let zeroDistance = averageDistance(
            gpmfTimestampsMs: gpmfTimestampsMs, gpmfLat: gpmfLat, gpmfLon: gpmfLon,
            fitTimestampsMs: fitTimestampsMs, fitLat: fitLat, fitLon: fitLon,
            offsetMs: 0
        ) ?? best.avgDistanceM

        let improvement = best.avgDistanceM > 0
            ? zeroDistance / best.avgDistanceM
            : 1.0

        return Result(
            offsetMs: best.offsetMs,
            avgDistanceM: best.avgDistanceM,
            zeroOffsetDistanceM: zeroDistance,
            improvementRatio: improvement
        )
    }

    // MARK: - Private

    private struct ScanResult {
        let offsetMs: Double
        let avgDistanceM: Double
    }

    /// Scans a range of offsets and returns the one with minimum average distance.
    private static func scan(
        gpmfTimestampsMs: ContiguousArray<Double>,
        gpmfLat: ContiguousArray<Double>,
        gpmfLon: ContiguousArray<Double>,
        fitTimestampsMs: ContiguousArray<Double>,
        fitLat: ContiguousArray<Double>,
        fitLon: ContiguousArray<Double>,
        rangeMs: Double,
        stepMs: Double,
        centerOffsetMs: Double = 0
    ) -> ScanResult? {
        var bestOffset = 0.0
        var bestDistance = Double.infinity

        let startOffset = centerOffsetMs - rangeMs
        let endOffset = centerOffsetMs + rangeMs
        var offset = startOffset

        while offset <= endOffset {
            if let dist = averageDistance(
                gpmfTimestampsMs: gpmfTimestampsMs, gpmfLat: gpmfLat, gpmfLon: gpmfLon,
                fitTimestampsMs: fitTimestampsMs, fitLat: fitLat, fitLon: fitLon,
                offsetMs: offset
            ) {
                if dist < bestDistance {
                    bestDistance = dist
                    bestOffset = offset
                }
            }
            offset += stepMs
        }

        guard bestDistance.isFinite else { return nil }
        return ScanResult(offsetMs: bestOffset, avgDistanceM: bestDistance)
    }

    /// Computes average Haversine distance between matched GPS pairs at a given offset.
    private static func averageDistance(
        gpmfTimestampsMs: ContiguousArray<Double>,
        gpmfLat: ContiguousArray<Double>,
        gpmfLon: ContiguousArray<Double>,
        fitTimestampsMs: ContiguousArray<Double>,
        fitLat: ContiguousArray<Double>,
        fitLon: ContiguousArray<Double>,
        offsetMs: Double
    ) -> Double? {
        var totalDistance = 0.0
        var pairCount = 0
        let maxTimeDiff = SyncConstants.trackCorrMaxTimeDiffMs

        // For each GPMF point, find the nearest FIT point with the applied offset
        var fitIdx = 0
        for i in 0..<gpmfTimestampsMs.count {
            let gpmfT = gpmfTimestampsMs[i]
            guard !gpmfLat[i].isNaN, !gpmfLon[i].isNaN else { continue }

            // Target time in FIT timeline = GPMF time + offset
            let targetFitT = gpmfT + offsetMs

            // Advance FIT index to nearest
            while fitIdx < fitTimestampsMs.count - 1 &&
                  fitTimestampsMs[fitIdx + 1] < targetFitT {
                fitIdx += 1
            }

            // Check nearest (fitIdx and fitIdx+1)
            var bestFitIdx = fitIdx
            if fitIdx + 1 < fitTimestampsMs.count {
                if abs(fitTimestampsMs[fitIdx + 1] - targetFitT) < abs(fitTimestampsMs[fitIdx] - targetFitT) {
                    bestFitIdx = fitIdx + 1
                }
            }

            let timeDiff = abs(fitTimestampsMs[bestFitIdx] - targetFitT)
            guard timeDiff <= maxTimeDiff else { continue }
            guard !fitLat[bestFitIdx].isNaN, !fitLon[bestFitIdx].isNaN else { continue }

            let dist = Haversine.distance(
                lat1: gpmfLat[i], lon1: gpmfLon[i],
                lat2: fitLat[bestFitIdx], lon2: fitLon[bestFitIdx]
            )
            totalDistance += dist
            pairCount += 1
        }

        guard pairCount >= 3 else { return nil }
        return totalDistance / Double(pairCount)
    }
}
