// Core/Services/Fusion/StrokeAggregator.swift v1.0.0
/**
 * Per-stroke metric aggregation (Step 4 of fusion pipeline).
 * Computes statistics for each stroke from fused SoA buffers.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Foundation

/// Per-stroke aggregation engine.
///
/// Computes aggregated statistics for each detected stroke event
/// from the fused SensorDataBuffers.
///
/// **Metrics computed:**
/// - strokeRate = 60.0 / duration (SPM)
/// - distance = avgSpeed × duration
/// - speedAvg, speedMax (from fused velocity)
/// - accelPeak, accelMin (from filtered surge)
/// - avgHR (from interpolated FIT heart rate)
/// - avgPitch, avgRoll (from gravity-derived angles)
///
/// Source: `docs/specs/fusion-engine.md` §Step 4
public struct StrokeAggregator {

    /// Aggregates per-stroke statistics from fused buffers.
    ///
    /// - Parameters:
    ///   - strokes: Detected stroke events.
    ///   - buffers: Fused SensorDataBuffers (all channels populated).
    /// - Returns: Per-stroke statistics array (same order as strokes).
    public static func aggregate(
        strokes: [StrokeEvent],
        buffers: SensorDataBuffers
    ) -> [PerStrokeStat] {
        strokes.map { stroke in
            aggregateStroke(stroke, buffers: buffers)
        }
    }

    // MARK: - Private

    /// Aggregates a single stroke.
    private static func aggregateStroke(
        _ stroke: StrokeEvent,
        buffers: SensorDataBuffers
    ) -> PerStrokeStat {
        let start = stroke.startIndex
        let end = min(stroke.endIndex, buffers.size - 1)
        guard end > start else {
            return PerStrokeStat(
                strokeIndex: stroke.index,
                duration: stroke.duration,
                strokeRate: stroke.strokeRate
            )
        }

        // Velocity stats
        let velocitySlice = ContiguousArray(buffers.fus_cal_ts_vel_inertial[start...end])
        let avgVelocity = Double(DSP.mean(velocitySlice))
        let peakVelocity = nanMax(velocitySlice)

        // Distance
        let distance = avgVelocity.isNaN ? nil : avgVelocity * stroke.duration

        // Acceleration stats
        let accelSlice = ContiguousArray(buffers.imu_flt_ts_acc_surge[start...end])
        let accelPeak = nanMax(accelSlice)
        let accelMin = nanMin(accelSlice)

        // Heart rate
        let hrSlice = ContiguousArray(buffers.phys_ext_ts_hr[start...end])
        let avgHR = Double(DSP.mean(hrSlice))

        // Pitch and roll
        let pitchSlice = ContiguousArray(buffers.fus_cal_ts_pitch[start...end])
        let rollSlice = ContiguousArray(buffers.fus_cal_ts_roll[start...end])
        let avgPitch = Double(DSP.mean(pitchSlice))
        let avgRoll = Double(DSP.mean(rollSlice))

        // Build dynamic metrics
        var metrics: [String: Double] = [:]
        if !accelPeak.isNaN { metrics["imu_flt_ps_acc_surge_max"] = accelPeak }
        if !accelMin.isNaN { metrics["imu_flt_ps_acc_surge_min"] = accelMin }

        return PerStrokeStat(
            strokeIndex: stroke.index,
            duration: stroke.duration,
            strokeRate: stroke.strokeRate,
            distance: distance,
            avgVelocity: avgVelocity.isNaN ? nil : avgVelocity,
            peakVelocity: peakVelocity.isNaN ? nil : peakVelocity,
            avgHR: avgHR.isNaN ? nil : avgHR,
            avgPower: nil,  // Power from FIT not yet mapped per-stroke
            avgPitch: avgPitch.isNaN ? nil : avgPitch,
            avgRoll: avgRoll.isNaN ? nil : avgRoll,
            metrics: metrics
        )
    }

    /// Returns maximum non-NaN value as Double.
    private static func nanMax(_ arr: ContiguousArray<Float>) -> Double {
        var best: Float = -.infinity
        for v in arr where !v.isNaN {
            if v > best { best = v }
        }
        return best.isInfinite ? .nan : Double(best)
    }

    /// Returns minimum non-NaN value as Double.
    private static func nanMin(_ arr: ContiguousArray<Float>) -> Double {
        var best: Float = .infinity
        for v in arr where !v.isNaN {
            if v < best { best = v }
        }
        return best.isInfinite ? .nan : Double(best)
    }
}
