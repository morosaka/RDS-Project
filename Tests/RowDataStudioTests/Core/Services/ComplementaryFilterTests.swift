// Core/Services/ComplementaryFilterTests.swift v1.0.0
/**
 * Tests for complementary filter (IMU-GPS velocity fusion).
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Foundation
import Testing
@testable import RowDataStudio

@Suite("ComplementaryFilter")
struct ComplementaryFilterTests {

    @Test("Zero acceleration with constant GPS returns GPS speed")
    func zeroAccelConstantGps() {
        let n = 1000
        let accel = ContiguousArray<Float>(repeating: 0, count: n)
        let gps = ContiguousArray<Float>(repeating: 5.0, count: n)

        let result = ComplementaryFilter.fuse(
            accelMps2: accel, gpsSpeed: gps, initialVelocity: 5.0
        )

        #expect(result.count == n)
        // Should converge to GPS speed
        #expect(abs(result[n - 1] - 5.0) < 0.1,
                "Should converge to GPS speed, got \(result[n - 1])")
    }

    @Test("Step input converges to new GPS speed")
    func stepInputConverges() {
        let n = 2000  // 10 seconds at 200 Hz
        let accel = ContiguousArray<Float>(repeating: 0, count: n)

        // GPS jumps from 3.0 to 5.0 at sample 500
        var gps = ContiguousArray<Float>(repeating: 3.0, count: n)
        for i in 500..<n { gps[i] = 5.0 }

        let result = ComplementaryFilter.fuse(
            accelMps2: accel, gpsSpeed: gps, initialVelocity: 3.0
        )

        // After the step, velocity should gradually converge toward 5.0
        // At α=0.999, convergence to 95% takes ~5s (1000 samples)
        #expect(result[n - 1] > 4.0,
                "Should converge toward 5.0 m/s, got \(result[n - 1])")
    }

    @Test("Pure IMU integration without GPS")
    func pureImuIntegration() {
        let n = 200  // 1 second
        // Constant acceleration of 1 m/s² → velocity should increase by ~1 m/s
        let accel = ContiguousArray<Float>(repeating: 1.0, count: n)
        let gps = ContiguousArray<Float>(repeating: .nan, count: n)  // No GPS

        let result = ComplementaryFilter.fuse(
            accelMps2: accel, gpsSpeed: gps, initialVelocity: 0
        )

        // After 1s at 1 m/s², velocity ≈ 1 m/s
        #expect(abs(result[n - 1] - 1.0) < 0.1,
                "Expected ~1.0 m/s after 1s at 1 m/s², got \(result[n - 1])")
    }

    @Test("Empty input returns empty")
    func emptyInput() {
        let result = ComplementaryFilter.fuse(
            accelMps2: ContiguousArray<Float>(),
            gpsSpeed: ContiguousArray<Float>()
        )
        #expect(result.isEmpty)
    }

    @Test("Convergence time estimation")
    func convergenceTimeEstimation() {
        let t = ComplementaryFilter.convergenceTime(alpha: 0.999, tolerance: 0.05)
        // log(0.05)/log(0.999) ≈ 2996 samples / 200 Hz ≈ 14.98s
        #expect(abs(t - 14.98) < 1.0,
                "Expected ~15s convergence, got \(t)s")
    }

    @Test("NaN acceleration holds velocity")
    func nanAccelHoldsVelocity() {
        let n = 100
        var accel = ContiguousArray<Float>(repeating: 0, count: n)
        let gps = ContiguousArray<Float>(repeating: 4.0, count: n)

        // Insert NaN gap
        for i in 30..<60 { accel[i] = .nan }

        let result = ComplementaryFilter.fuse(
            accelMps2: accel, gpsSpeed: gps, initialVelocity: 4.0
        )

        // During NaN gap, velocity should be held
        for i in 30..<60 {
            #expect(!result[i].isNaN, "Velocity should not be NaN during gap")
        }
    }
}
