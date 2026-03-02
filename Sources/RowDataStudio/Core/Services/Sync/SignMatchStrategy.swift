// Core/Services/Sync/SignMatchStrategy.swift v1.0.0
/**
 * Step 1: GPMF internal alignment (IMU-GPS lag estimation).
 * Uses slope-sign consensus cross-correlation to find GPS receiver delay.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Foundation

/// Step 1: SignMatch strategy for IMU-GPS internal alignment.
///
/// GPS readings have ~200-300ms lag compared to IMU due to receiver processing.
/// This strategy estimates the lag by comparing slope-sign consensus between
/// integrated ACCL and GPS speed on a uniform time grid.
///
/// **Algorithm:**
/// 1. Find GPS speed peak → center analysis window (±20s)
/// 2. Resample GPS speed and integrated ACCL on uniform 20ms grid
/// 3. Smooth GPS with Gaussian (σ=8)
/// 4. Calculate slopes (consecutive deltas)
/// 5. Binarize slopes with ±0.02 threshold → sign vectors {-1, 0, +1}
/// 6. Cross-correlate binary vectors on ±2500ms window (125 steps)
/// 7. Score = agreement / non-zero pair count
/// 8. Accept if bestScore > 0.15
///
/// Source: `docs/specs/sync-pipeline.md` §Step 1
public struct SignMatchStrategy {

    /// SignMatch result.
    public struct Result: Sendable {
        /// Estimated lag in milliseconds (GPS behind IMU)
        public let lagMs: Double
        /// Best consensus score (0.0–1.0)
        public let score: Double
        /// Whether the result meets the acceptance threshold
        public let accepted: Bool
    }

    /// Estimates IMU-GPS lag using slope-sign consensus.
    ///
    /// - Parameters:
    ///   - accelTimestampsMs: ACCL timestamps (ms)
    ///   - accelSurgeMps2: Surge acceleration (m/s², tilt-bias corrected)
    ///   - gpsTimestampsMs: GPS timestamps (ms)
    ///   - gpsSpeed: GPS speed (m/s)
    /// - Returns: SignMatch result, or nil if insufficient data.
    public static func estimateLag(
        accelTimestampsMs: ContiguousArray<Double>,
        accelSurgeMps2: ContiguousArray<Float>,
        gpsTimestampsMs: ContiguousArray<Double>,
        gpsSpeed: ContiguousArray<Float>
    ) -> Result? {
        guard gpsSpeed.count >= 10, accelSurgeMps2.count >= 100 else { return nil }

        // 1. Find GPS speed peak → center window
        var peakIdx = 0
        var peakVal: Float = -.infinity
        for i in 0..<gpsSpeed.count {
            if gpsSpeed[i] > peakVal && !gpsSpeed[i].isNaN {
                peakVal = gpsSpeed[i]
                peakIdx = i
            }
        }
        let peakTimeMs = gpsTimestampsMs[peakIdx]
        let winStart = peakTimeMs - SyncConstants.searchWindowMs
        let winEnd = peakTimeMs + SyncConstants.searchWindowMs

        // 2. Resample both signals on uniform 20ms grid
        let step = SyncConstants.resampleStepMs
        let gridStart = max(
            accelTimestampsMs.first ?? 0,
            gpsTimestampsMs.first ?? 0,
            winStart
        )
        let gridEnd = min(
            accelTimestampsMs.last ?? 0,
            gpsTimestampsMs.last ?? 0,
            winEnd
        )
        guard gridEnd > gridStart else { return nil }

        let gridCount = Int((gridEnd - gridStart) / step) + 1
        guard gridCount >= 20 else { return nil }

        // Integrate ACCL to get velocity estimate (cumulative trapezoidal)
        let accelIntegrated = DSP.integrate(accelSurgeMps2, dt: Float(step / 1000.0))

        // Resample GPS speed onto grid
        var gpsResampled = ContiguousArray<Float>(repeating: .nan, count: gridCount)
        for i in 0..<gridCount {
            let t = gridStart + Double(i) * step
            gpsResampled[i] = DSP.interpolateAt(
                timestamps: gpsTimestampsMs,
                values: gpsSpeed,
                targetTime: t
            )
        }

        // Resample ACCL-integrated velocity onto grid
        var acclResampled = ContiguousArray<Float>(repeating: .nan, count: gridCount)
        for i in 0..<gridCount {
            let t = gridStart + Double(i) * step
            acclResampled[i] = DSP.interpolateAt(
                timestamps: accelTimestampsMs,
                values: accelIntegrated,
                targetTime: t
            )
        }

        // 3. Smooth GPS
        gpsResampled = DSP.gaussianSmooth(gpsResampled, sigma: SyncConstants.gpsSmoothSigma)

        // 4. Calculate slopes
        let gpsSlopes = slopes(gpsResampled)
        let acclSlopes = slopes(acclResampled)

        // 5. Binarize slopes
        let threshold = SyncConstants.slopeThreshold
        let gpsSigns = binarize(gpsSlopes, threshold: Float(threshold))
        let acclSigns = binarize(acclSlopes, threshold: Float(threshold))

        // 6. Cross-correlate on ±2500ms window
        let maxLagSteps = Int(SyncConstants.maxLagMs / step)
        var bestScore = -Double.infinity
        var bestLag = 0

        for lag in -maxLagSteps...maxLagSteps {
            var agreement = 0
            var count = 0

            for i in 0..<gpsSigns.count {
                let j = i + lag
                guard j >= 0, j < acclSigns.count else { continue }
                let g = gpsSigns[i]
                let a = acclSigns[j]
                if g != 0 || a != 0 {
                    count += 1
                    if g == a { agreement += 1 }
                }
            }

            if count > 0 {
                let score = Double(agreement) / Double(count)
                if score > bestScore {
                    bestScore = score
                    bestLag = lag
                }
            }
        }

        let lagMs = Double(bestLag) * step
        let accepted = bestScore >= SyncConstants.scoreThreshold

        return Result(lagMs: lagMs, score: bestScore, accepted: accepted)
    }

    // MARK: - Private Helpers

    /// Computes consecutive differences (slopes).
    private static func slopes(_ signal: ContiguousArray<Float>) -> ContiguousArray<Float> {
        guard signal.count >= 2 else { return ContiguousArray<Float>() }
        var result = ContiguousArray<Float>(repeating: 0, count: signal.count - 1)
        for i in 0..<result.count {
            result[i] = signal[i + 1] - signal[i]
        }
        return result
    }

    /// Binarizes slopes into sign vectors {-1, 0, +1}.
    private static func binarize(
        _ slopes: ContiguousArray<Float>,
        threshold: Float
    ) -> ContiguousArray<Int8> {
        var signs = ContiguousArray<Int8>(repeating: 0, count: slopes.count)
        for i in 0..<slopes.count {
            if slopes[i] > threshold {
                signs[i] = 1
            } else if slopes[i] < -threshold {
                signs[i] = -1
            }
        }
        return signs
    }
}
