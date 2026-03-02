// Core/Services/TiltBiasEstimatorTests.swift v1.0.0
/**
 * Tests for tilt bias estimation (Step 0).
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Foundation
import Testing
@testable import RowDataStudio

@Suite("TiltBiasEstimator")
struct TiltBiasEstimatorTests {

    @Test("Estimates bias from constant tilt")
    func constantTilt() {
        // Simulate: camera tilted 3° → gravity projects ~0.51 m/s² onto surge
        // ACCL surge = kinematic(0) + sin(3°) × 9.81 ≈ 0.513 m/s²
        let n = 1000
        let tiltBiasMps2: Float = 0.513
        let accel = ContiguousArray<Float>(repeating: tiltBiasMps2, count: n)

        // GPS: constant speed (no acceleration → avgGpsAccel ≈ 0)
        let gpsSpeed = ContiguousArray<Float>(repeating: 4.0, count: 100)
        let gpsTimestamps = ContiguousArray<Double>((0..<100).map { Double($0) * 100.0 })

        let result = TiltBiasEstimator.estimate(
            accelSurgeMps2: accel,
            gpsSpeedMs: gpsSpeed,
            gpsTimestampsMs: gpsTimestamps
        )

        #expect(result != nil)
        if let r = result {
            #expect(abs(r.biasMps2 - Double(tiltBiasMps2)) < 0.01,
                    "Expected bias ~0.513 m/s², got \(r.biasMps2)")
            #expect(abs(r.biasG - Double(tiltBiasMps2) / 9.80665) < 0.001)
        }
    }

    @Test("Returns nil for empty data")
    func emptyData() {
        let result = TiltBiasEstimator.estimate(
            accelSurgeMps2: ContiguousArray<Float>(),
            gpsSpeedMs: ContiguousArray<Float>(),
            gpsTimestampsMs: ContiguousArray<Double>()
        )
        #expect(result == nil)
    }

    @Test("Returns nil for too-short GPS data")
    func tooShortGps() {
        let accel = ContiguousArray<Float>(repeating: 0.5, count: 100)
        let gpsSpeed: ContiguousArray<Float> = [4.0]
        let gpsTimestamps: ContiguousArray<Double> = [0.0]

        let result = TiltBiasEstimator.estimate(
            accelSurgeMps2: accel,
            gpsSpeedMs: gpsSpeed,
            gpsTimestampsMs: gpsTimestamps
        )
        #expect(result == nil)
    }

    @Test("Accounts for GPS-derived acceleration")
    func gpsAcceleration() {
        // Boat accelerating: GPS goes from 3 m/s to 5 m/s over 10 seconds
        // avgGpsAccel = (5-3)/10 = 0.2 m/s²
        // IMU reads 0.7 m/s² (0.5 tilt + 0.2 kinematic)
        let accel = ContiguousArray<Float>(repeating: 0.7, count: 2000)
        let gpsSpeed: ContiguousArray<Float> = [3.0, 5.0]
        let gpsTimestamps: ContiguousArray<Double> = [0.0, 10_000.0]

        let result = TiltBiasEstimator.estimate(
            accelSurgeMps2: accel,
            gpsSpeedMs: gpsSpeed,
            gpsTimestampsMs: gpsTimestamps
        )

        #expect(result != nil)
        if let r = result {
            // bias = 0.7 - 0.2 = 0.5 m/s²
            #expect(abs(r.biasMps2 - 0.5) < 0.01)
        }
    }
}
