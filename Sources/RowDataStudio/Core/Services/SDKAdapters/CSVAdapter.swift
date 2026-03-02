// Core/Services/SDKAdapters/CSVAdapter.swift v1.0.0
/**
 * Adapter layer: CSV SDK → app-layer types.
 * Thin wrapper — NKEmpowerSession is already Codable+Sendable.
 * Provides per-stroke metric extraction into dynamic SoA channels.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Foundation
import CSVSwiftSDK

/// Adapter: CSV SDK → app-layer types.
///
/// NKEmpowerSession is already Codable+Sendable, so this adapter is thin.
/// Primary role: extracting per-stroke biomechanical metrics into dynamic
/// channels on SensorDataBuffers and PerStrokeStat dictionaries.
public struct CSVAdapter {

    /// Parses an NK Empower CSV string.
    ///
    /// - Parameter csvString: Raw CSV content.
    /// - Returns: Parsed NKEmpowerSession.
    /// - Throws: CSV parsing errors.
    public static func parseEmpower(_ csvString: String) throws -> NKEmpowerSession {
        try NKEmpowerParser.parse(csvString)
    }

    /// Extracts per-stroke Empower metrics into a dictionary keyed by metric ID.
    ///
    /// Returns one array per metric, indexed by stroke number (0-based).
    /// Metric IDs follow convention: `mech_ext_ps_{name}`.
    ///
    /// - Parameter session: Parsed NK Empower session.
    /// - Returns: Dictionary of metric ID → values array.
    public static func empowerMetrics(
        from session: NKEmpowerSession
    ) -> [String: ContiguousArray<Float>] {
        let strokes = session.strokes
        let n = strokes.count

        var metrics: [String: ContiguousArray<Float>] = [:]

        // Pre-allocate all 13 biomechanical channels
        let keys = [
            "mech_ext_ps_catch_angle",
            "mech_ext_ps_finish_angle",
            "mech_ext_ps_slip",
            "mech_ext_ps_wash",
            "mech_ext_ps_max_force",
            "mech_ext_ps_avg_force",
            "mech_ext_ps_max_force_angle",
            "mech_ext_ps_peak_power",
            "mech_ext_ps_avg_power",
            "mech_ext_ps_work",
            "mech_ext_ps_stroke_length",
            "mech_ext_ps_effective_length",
            "mech_ext_ps_stroke_rate",
        ]
        for key in keys {
            metrics[key] = ContiguousArray<Float>(repeating: .nan, count: n)
        }

        for i in 0..<n {
            let s = strokes[i]
            metrics["mech_ext_ps_catch_angle"]![i] = Float(s.catchAngle)
            metrics["mech_ext_ps_finish_angle"]![i] = Float(s.finishAngle)
            metrics["mech_ext_ps_slip"]![i] = Float(s.slip)
            metrics["mech_ext_ps_wash"]![i] = Float(s.wash)
            metrics["mech_ext_ps_max_force"]![i] = Float(s.maxForce)
            metrics["mech_ext_ps_avg_force"]![i] = Float(s.avgForce)
            metrics["mech_ext_ps_max_force_angle"]![i] = Float(s.maxForceAngle)
            metrics["mech_ext_ps_peak_power"]![i] = Float(s.peakPower)
            metrics["mech_ext_ps_avg_power"]![i] = Float(s.avgPower)
            metrics["mech_ext_ps_work"]![i] = Float(s.work)
            metrics["mech_ext_ps_stroke_length"]![i] = Float(s.strokeLength)
            metrics["mech_ext_ps_effective_length"]![i] = Float(s.effectiveLength)
            metrics["mech_ext_ps_stroke_rate"]![i] = Float(s.strokeRate)
        }

        return metrics
    }

    /// Extracts per-stroke elapsed time and distance from Empower data.
    ///
    /// - Parameter session: Parsed NK Empower session.
    /// - Returns: Tuple of (elapsed time in seconds, distance in meters).
    public static func empowerTimeline(
        from session: NKEmpowerSession
    ) -> (elapsedTimeS: ContiguousArray<Double>, distanceM: ContiguousArray<Double>) {
        let strokes = session.strokes
        let n = strokes.count

        var elapsed = ContiguousArray<Double>(repeating: 0, count: n)
        var distance = ContiguousArray<Double>(repeating: 0, count: n)

        for i in 0..<n {
            elapsed[i] = strokes[i].elapsedTime
            distance[i] = strokes[i].distance
        }

        return (elapsed, distance)
    }
}
