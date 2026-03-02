// Core/Services/GpsSpeedCorrelatorTests.swift v1.0.0
/**
 * Tests for GPS speed cross-correlation sync strategy (Step 3A).
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Foundation
import Testing
@testable import RowDataStudio

@Suite("GpsSpeedCorrelator")
struct GpsSpeedCorrelatorTests {

    /// Generates synthetic GPS speed data on compatible timescales with a known offset.
    private static func syntheticSpeedPair(
        durationS: Double = 300,
        gpmfRate: Double = 10,
        fitRate: Double = 1,
        offsetMs: Double = 5000
    ) -> (
        gpmfTs: ContiguousArray<Double>,
        gpmfSpeed: ContiguousArray<Float>,
        fitTs: ContiguousArray<Double>,
        fitSpeed: ContiguousArray<Float>
    ) {
        let gpmfN = Int(durationS * gpmfRate)
        let fitN = Int(durationS * fitRate)

        // Shared velocity profile with multiple features
        func velocity(tS: Double) -> Float {
            Float(4.0 + 1.0 * sin(2.0 * .pi * 0.1 * tS)
                  + 0.5 * sin(2.0 * .pi * 0.03 * tS))
        }

        // GPMF timestamps (relative, 0-based)
        var gpmfTs = ContiguousArray<Double>(repeating: 0, count: gpmfN)
        var gpmfSpeed = ContiguousArray<Float>(repeating: 0, count: gpmfN)
        for i in 0..<gpmfN {
            let tMs = Double(i) / gpmfRate * 1000.0
            gpmfTs[i] = tMs
            gpmfSpeed[i] = velocity(tS: tMs / 1000.0)
        }

        // FIT timestamps: same timescale but shifted by offsetMs
        var fitTs = ContiguousArray<Double>(repeating: 0, count: fitN)
        var fitSpeed = ContiguousArray<Float>(repeating: 0, count: fitN)
        for i in 0..<fitN {
            let tMs = Double(i) / fitRate * 1000.0
            fitTs[i] = tMs + offsetMs
            fitSpeed[i] = velocity(tS: tMs / 1000.0)
        }

        return (gpmfTs, gpmfSpeed, fitTs, fitSpeed)
    }

    @Test("Finds known offset in synthetic data")
    func findsKnownOffset() {
        let (gpmfTs, gpmfSpeed, fitTs, fitSpeed) = Self.syntheticSpeedPair(
            durationS: 300, offsetMs: 5000
        )

        let result = GpsSpeedCorrelator.correlate(
            gpmfTimestampsMs: gpmfTs,
            gpmfSpeed: gpmfSpeed,
            fitTimestampsMs: fitTs,
            fitSpeed: fitSpeed
        )

        #expect(result != nil, "Should find offset in synthetic data")
        if let r = result {
            #expect(abs(r.offsetMs - 5000) < 10_000,
                    "Expected offset ~5000ms, got \(r.offsetMs)ms")
        }
    }

    @Test("Returns nil for insufficient data")
    func insufficientData() {
        let gpmfTs: ContiguousArray<Double> = [0, 100]
        let gpmfSpeed: ContiguousArray<Float> = [4.0, 4.1]
        let fitTs: ContiguousArray<Double> = [0, 1000]
        let fitSpeed: ContiguousArray<Float> = [4.0, 4.1]

        let result = GpsSpeedCorrelator.correlate(
            gpmfTimestampsMs: gpmfTs,
            gpmfSpeed: gpmfSpeed,
            fitTimestampsMs: fitTs,
            fitSpeed: fitSpeed
        )
        #expect(result == nil)
    }

    @Test("Produces result for identical signals with zero offset")
    func zeroOffsetProducesResult() {
        let (gpmfTs, gpmfSpeed, fitTs, fitSpeed) = Self.syntheticSpeedPair(
            durationS: 300, offsetMs: 0
        )

        let result = GpsSpeedCorrelator.correlate(
            gpmfTimestampsMs: gpmfTs,
            gpmfSpeed: gpmfSpeed,
            fitTimestampsMs: fitTs,
            fitSpeed: fitSpeed
        )

        #expect(result != nil, "Should produce result for identical signals")
    }
}
