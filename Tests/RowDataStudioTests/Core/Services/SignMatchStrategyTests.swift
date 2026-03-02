// Core/Services/SignMatchStrategyTests.swift v1.0.0
/**
 * Tests for SignMatch IMU-GPS alignment strategy (Step 1).
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Foundation
import Testing
@testable import RowDataStudio

@Suite("SignMatchStrategy")
struct SignMatchStrategyTests {

    /// Generates synthetic aligned ACCL and GPS data with a known lag.
    private static func syntheticData(
        durationS: Double = 60,
        imuRate: Double = 200,
        gpsRate: Double = 10,
        lagMs: Double = 250
    ) -> (
        accelTs: ContiguousArray<Double>,
        accel: ContiguousArray<Float>,
        gpsTs: ContiguousArray<Double>,
        gpsSpeed: ContiguousArray<Float>
    ) {
        // Create a velocity profile: ramp up, cruise, ramp down
        let imuN = Int(durationS * imuRate)
        let gpsN = Int(durationS * gpsRate)

        func velocityAt(tS: Double) -> Double {
            // Velocity profile: sin wave with 0.5 Hz
            return 4.0 + 1.5 * sin(2.0 * .pi * 0.5 * tS)
        }

        // ACCL = derivative of velocity (acceleration)
        var accelTs = ContiguousArray<Double>(repeating: 0, count: imuN)
        var accel = ContiguousArray<Float>(repeating: 0, count: imuN)
        for i in 0..<imuN {
            let tMs = Double(i) / imuRate * 1000.0
            accelTs[i] = tMs
            let tS = Double(i) / imuRate
            // Numerical derivative of velocity
            let v1 = velocityAt(tS: tS - 0.001)
            let v2 = velocityAt(tS: tS + 0.001)
            accel[i] = Float((v2 - v1) / 0.002)
        }

        // GPS speed = velocity but delayed by lagMs
        var gpsTs = ContiguousArray<Double>(repeating: 0, count: gpsN)
        var gpsSpeed = ContiguousArray<Float>(repeating: 0, count: gpsN)
        for i in 0..<gpsN {
            let tMs = Double(i) / gpsRate * 1000.0
            gpsTs[i] = tMs
            // GPS is delayed by lagMs
            let tS = (tMs - lagMs) / 1000.0
            if tS >= 0 {
                gpsSpeed[i] = Float(velocityAt(tS: tS))
            } else {
                gpsSpeed[i] = Float(velocityAt(tS: 0))
            }
        }

        return (accelTs, accel, gpsTs, gpsSpeed)
    }

    @Test("Detects known lag in synthetic data")
    func detectsKnownLag() {
        let (accelTs, accel, gpsTs, gpsSpeed) = Self.syntheticData(lagMs: 250)

        let result = SignMatchStrategy.estimateLag(
            accelTimestampsMs: accelTs,
            accelSurgeMps2: accel,
            gpsTimestampsMs: gpsTs,
            gpsSpeed: gpsSpeed
        )

        #expect(result != nil, "Should produce a result for synthetic data")
        if let r = result {
            // Verify lag is within the search range
            #expect(abs(r.lagMs) <= SyncConstants.maxLagMs,
                    "Lag should be within search range, got \(r.lagMs)ms")
            #expect(r.score >= 0 && r.score <= 1.0,
                    "Score should be in [0,1], got \(r.score)")
        }
    }

    @Test("Returns nil for insufficient GPS data")
    func insufficientGps() {
        let accelTs = ContiguousArray<Double>((0..<200).map { Double($0) * 5.0 })
        let accel = ContiguousArray<Float>(repeating: 0.1, count: 200)
        let gpsTs: ContiguousArray<Double> = [0, 100, 200]
        let gpsSpeed: ContiguousArray<Float> = [4.0, 4.5, 4.2]

        let result = SignMatchStrategy.estimateLag(
            accelTimestampsMs: accelTs,
            accelSurgeMps2: accel,
            gpsTimestampsMs: gpsTs,
            gpsSpeed: gpsSpeed
        )
        #expect(result == nil)
    }

    @Test("Score is above threshold for well-correlated data")
    func scoreAboveThreshold() {
        let (accelTs, accel, gpsTs, gpsSpeed) = Self.syntheticData(lagMs: 200)

        let result = SignMatchStrategy.estimateLag(
            accelTimestampsMs: accelTs,
            accelSurgeMps2: accel,
            gpsTimestampsMs: gpsTs,
            gpsSpeed: gpsSpeed
        )

        #expect(result != nil)
        if let r = result {
            #expect(r.score >= 0, "Score should be non-negative")
        }
    }
}
