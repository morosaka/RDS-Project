// Core/Services/SyncEngineTests.swift v1.0.0
/**
 * Integration tests for the sync pipeline orchestrator.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Foundation
import Testing
@testable import RowDataStudio

@Suite("SyncEngine Integration")
struct SyncEngineTests {

    /// Generates a minimal synthetic dataset for sync testing.
    private static func syntheticSyncData(
        durationS: Double = 60
    ) -> (
        gpmfGps: GPMFGpsTimeSeries,
        gpmfAccel: GPMFAccelTimeSeries,
        fitTimeSeries: FITTimeSeries
    ) {
        // GPMF GPS (10 Hz)
        let gpsN = Int(durationS * 10)
        var gpsTs = ContiguousArray<Double>(repeating: 0, count: gpsN)
        var gpsSpeed = ContiguousArray<Float>(repeating: 0, count: gpsN)
        var gpsLat = ContiguousArray<Double>(repeating: 0, count: gpsN)
        var gpsLon = ContiguousArray<Double>(repeating: 0, count: gpsN)
        for i in 0..<gpsN {
            let tMs = Double(i) * 100.0
            gpsTs[i] = tMs
            gpsSpeed[i] = Float(4.0 + sin(Double(i) * 0.05))
            gpsLat[i] = 45.43 + Double(i) * 0.000001
            gpsLon[i] = 12.34
        }

        // GPMF ACCL (200 Hz)
        let accelN = Int(durationS * 200)
        var accelTs = ContiguousArray<Double>(repeating: 0, count: accelN)
        var accelSurge = ContiguousArray<Float>(repeating: 0, count: accelN)
        for i in 0..<accelN {
            accelTs[i] = Double(i) * 5.0
            accelSurge[i] = Float(0.5 + 0.3 * sin(Double(i) * 0.01))
        }

        // FIT (1 Hz)
        let fitN = Int(durationS)
        let fitEpochBase = 1_000_000_000.0
        var fitTs = ContiguousArray<Double>(repeating: 0, count: fitN)
        var fitSpeed = ContiguousArray<Float>(repeating: 0, count: fitN)
        var fitLat = ContiguousArray<Double>(repeating: 0, count: fitN)
        var fitLon = ContiguousArray<Double>(repeating: 0, count: fitN)
        let fitHR = ContiguousArray<Float>(repeating: 155, count: fitN)
        for i in 0..<fitN {
            fitTs[i] = fitEpochBase + Double(i) * 1000.0
            fitSpeed[i] = Float(4.0 + sin(Double(i) * 0.5))
            fitLat[i] = 45.43 + Double(i) * 0.00001
            fitLon[i] = 12.34
        }

        let gpmfGps = GPMFGpsTimeSeries(
            timestampsMs: gpsTs, speed: gpsSpeed,
            latitude: gpsLat, longitude: gpsLon
        )
        let gpmfAccel = GPMFAccelTimeSeries(
            timestampsMs: accelTs, surgeMps2: accelSurge
        )
        let fitTimeSeries = FITTimeSeries(
            timestampsMs: fitTs, speed: fitSpeed,
            latitude: fitLat, longitude: fitLon,
            heartRate: fitHR,
            cadence: ContiguousArray<Float>(repeating: .nan, count: fitN),
            power: ContiguousArray<Float>(repeating: .nan, count: fitN),
            distance: ContiguousArray<Float>(repeating: .nan, count: fitN)
        )

        return (gpmfGps, gpmfAccel, fitTimeSeries)
    }

    @Test("Full sync pipeline runs without crash")
    func fullPipelineRuns() {
        let (gps, accel, fit) = Self.syntheticSyncData()

        let output = SyncEngine.synchronize(
            gpmfGps: gps, gpmfAccel: accel, fitTimeSeries: fit
        )

        // Basic sanity checks
        #expect(output.fitGpmfSync.strategy != .manual,
                "Should not require manual sync on synthetic data")
    }

    @Test("Tilt bias is estimated from synthetic data")
    func tiltBiasEstimated() {
        let (gps, accel, fit) = Self.syntheticSyncData()

        let output = SyncEngine.synchronize(
            gpmfGps: gps, gpmfAccel: accel, fitTimeSeries: fit
        )

        #expect(output.tiltBias != nil, "Tilt bias should be estimated")
    }

    @Test("Warnings are populated when strategies fail")
    func warningsOnFailure() {
        // Minimal data that's too short for some strategies
        let gps = GPMFGpsTimeSeries(
            timestampsMs: ContiguousArray([0.0]),
            speed: ContiguousArray([Float(4.0)]),
            latitude: ContiguousArray([45.0]),
            longitude: ContiguousArray([12.0])
        )
        let accel = GPMFAccelTimeSeries(
            timestampsMs: ContiguousArray([0.0]),
            surgeMps2: ContiguousArray([Float(0.5)])
        )
        let fit = FITTimeSeries(
            timestampsMs: ContiguousArray([0.0]),
            speed: ContiguousArray([Float(4.0)]),
            latitude: ContiguousArray([45.0]),
            longitude: ContiguousArray([12.0]),
            heartRate: ContiguousArray([Float(155)]),
            cadence: ContiguousArray([Float.nan]),
            power: ContiguousArray([Float.nan]),
            distance: ContiguousArray([Float.nan])
        )

        let output = SyncEngine.synchronize(
            gpmfGps: gps, gpmfAccel: accel, fitTimeSeries: fit
        )

        #expect(!output.warnings.isEmpty, "Should have warnings with minimal data")
    }
}
