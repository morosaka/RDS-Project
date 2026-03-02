// Core/Services/HaversineTests.swift v1.0.0
/**
 * Tests for Haversine distance and semicircle conversion.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Testing
@testable import RowDataStudio

@Suite("Haversine Distance")
struct HaversineTests {

    @Test("Distance between same point is 0")
    func samePoint() {
        let d = Haversine.distance(lat1: 45.0, lon1: 9.0, lat2: 45.0, lon2: 9.0)
        #expect(d < 0.01, "Same point should have zero distance")
    }

    @Test("Known distance: London to Paris ~343 km")
    func londonToParis() {
        // London: 51.5074° N, 0.1278° W
        // Paris: 48.8566° N, 2.3522° E
        let d = Haversine.distance(
            lat1: 51.5074, lon1: -0.1278,
            lat2: 48.8566, lon2: 2.3522
        )
        // Expected ~343 km, allow 5 km tolerance
        #expect(abs(d - 343_000) < 5_000,
                "London-Paris should be ~343 km, got \(d / 1000) km")
    }

    @Test("Small distance: ~100 meters at rowing venue")
    func smallDistance() {
        // Two points ~100m apart on a rowing course
        let d = Haversine.distance(
            lat1: 45.43220, lon1: 12.33650,
            lat2: 45.43310, lon2: 12.33650
        )
        // ~100m (0.0009° lat ≈ 100m)
        #expect(d > 50 && d < 200,
                "Expected ~100m, got \(d)m")
    }

    @Test("Antipodal points: ~20,000 km")
    func antipodalPoints() {
        let d = Haversine.distance(lat1: 0, lon1: 0, lat2: 0, lon2: 180)
        // Half circumference ≈ 20,015 km
        #expect(abs(d - 20_015_000) < 100_000,
                "Antipodal should be ~20,015 km, got \(d / 1000) km")
    }

    @Test("Semicircles to degrees conversion")
    func semicirclesToDegrees() {
        // Max positive Int32: 2^31 - 1 ≈ 180°
        let deg = Haversine.semicirclesToDegrees(Int32.max)
        #expect(abs(deg - 180.0) < 0.001)

        // Zero
        #expect(Haversine.semicirclesToDegrees(0) == 0)

        // Negative (southern hemisphere)
        let negDeg = Haversine.semicirclesToDegrees(Int32.min)
        #expect(abs(negDeg - (-180.0)) < 0.001)
    }

    @Test("Typical GPS semicircle values")
    func typicalSemicircles() {
        // 45° N ≈ 536870912 semicircles
        let semicircles: Int32 = 536_870_912
        let deg = Haversine.semicirclesToDegrees(semicircles)
        #expect(abs(deg - 45.0) < 0.01,
                "Expected ~45°, got \(deg)")
    }
}
