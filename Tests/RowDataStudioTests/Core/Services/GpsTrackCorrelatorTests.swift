// Core/Services/GpsTrackCorrelatorTests.swift v1.0.0
/**
 * Tests for GPS track Haversine distance minimization (Step 3B).
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Foundation
import Testing
@testable import RowDataStudio

@Suite("GpsTrackCorrelator")
struct GpsTrackCorrelatorTests {

    /// Generates synthetic GPS track data on compatible timescales with a known offset.
    private static func syntheticTrackPair(
        durationS: Double = 300,
        gpmfRate: Double = 10,
        fitRate: Double = 1,
        offsetMs: Double = 3000
    ) -> (
        gpmfTs: ContiguousArray<Double>,
        gpmfLat: ContiguousArray<Double>,
        gpmfLon: ContiguousArray<Double>,
        fitTs: ContiguousArray<Double>,
        fitLat: ContiguousArray<Double>,
        fitLon: ContiguousArray<Double>
    ) {
        let gpmfN = Int(durationS * gpmfRate)
        let fitN = Int(durationS * fitRate)

        // Simulate a rowing course (straight line heading north)
        let baseLat = 45.432
        let baseLon = 12.337
        let speedDegPerS = 4.0 / 111_000.0  // ~4 m/s → degrees/s

        func position(tS: Double) -> (lat: Double, lon: Double) {
            let lat = baseLat + speedDegPerS * tS
            let lon = baseLon + speedDegPerS * 0.1 * sin(2.0 * .pi * 0.05 * tS)
            return (lat, lon)
        }

        // GPMF timestamps (relative, 0-based)
        var gpmfTs = ContiguousArray<Double>(repeating: 0, count: gpmfN)
        var gpmfLat = ContiguousArray<Double>(repeating: 0, count: gpmfN)
        var gpmfLon = ContiguousArray<Double>(repeating: 0, count: gpmfN)
        for i in 0..<gpmfN {
            let tMs = Double(i) / gpmfRate * 1000.0
            gpmfTs[i] = tMs
            let (lat, lon) = position(tS: tMs / 1000.0)
            gpmfLat[i] = lat
            gpmfLon[i] = lon
        }

        // FIT timestamps: same timescale shifted by offsetMs
        var fitTs = ContiguousArray<Double>(repeating: 0, count: fitN)
        var fitLat = ContiguousArray<Double>(repeating: 0, count: fitN)
        var fitLon = ContiguousArray<Double>(repeating: 0, count: fitN)
        for i in 0..<fitN {
            let tMs = Double(i) / fitRate * 1000.0
            fitTs[i] = tMs + offsetMs
            let (lat, lon) = position(tS: tMs / 1000.0)
            fitLat[i] = lat
            fitLon[i] = lon
        }

        return (gpmfTs, gpmfLat, gpmfLon, fitTs, fitLat, fitLon)
    }

    @Test("Finds offset in synthetic track data")
    func findsOffset() {
        let (gpmfTs, gpmfLat, gpmfLon, fitTs, fitLat, fitLon) = Self.syntheticTrackPair(
            durationS: 300, offsetMs: 3000
        )

        let result = GpsTrackCorrelator.correlate(
            gpmfTimestampsMs: gpmfTs,
            gpmfLat: gpmfLat, gpmfLon: gpmfLon,
            fitTimestampsMs: fitTs,
            fitLat: fitLat, fitLon: fitLon
        )

        #expect(result != nil, "Should find offset in synthetic track data")
        if let r = result {
            #expect(abs(r.offsetMs - 3000) < 10_000,
                    "Expected offset ~3000ms, got \(r.offsetMs)ms")
        }
    }

    @Test("Returns nil for insufficient data")
    func insufficientData() {
        let gpmfTs: ContiguousArray<Double> = [0, 100]
        let gpmfLat: ContiguousArray<Double> = [45.0, 45.001]
        let gpmfLon: ContiguousArray<Double> = [12.0, 12.0]
        let fitTs: ContiguousArray<Double> = [0, 1000]
        let fitLat: ContiguousArray<Double> = [45.0, 45.001]
        let fitLon: ContiguousArray<Double> = [12.0, 12.0]

        let result = GpsTrackCorrelator.correlate(
            gpmfTimestampsMs: gpmfTs,
            gpmfLat: gpmfLat, gpmfLon: gpmfLon,
            fitTimestampsMs: fitTs,
            fitLat: fitLat, fitLon: fitLon
        )
        #expect(result == nil)
    }

    @Test("Best offset has lower distance than zero offset")
    func bestOffsetImprovesDistance() {
        let (gpmfTs, gpmfLat, gpmfLon, fitTs, fitLat, fitLon) = Self.syntheticTrackPair(
            durationS: 300, offsetMs: 10_000
        )

        let result = GpsTrackCorrelator.correlate(
            gpmfTimestampsMs: gpmfTs,
            gpmfLat: gpmfLat, gpmfLon: gpmfLon,
            fitTimestampsMs: fitTs,
            fitLat: fitLat, fitLon: fitLon
        )

        #expect(result != nil, "Should produce result for synthetic data")
        if let r = result {
            #expect(r.avgDistanceM <= r.zeroOffsetDistanceM,
                    "Best offset should have lower distance than zero offset")
        }
    }
}
