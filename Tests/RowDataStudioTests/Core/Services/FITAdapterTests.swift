// Core/Services/FITAdapterTests.swift v1.0.0
/**
 * Tests for FIT SDK adapter conversion logic.
 * Tests Haversine semicircle conversion and FIT epoch handling.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Foundation
import Testing
@testable import RowDataStudio

@Suite("FITAdapter")
struct FITAdapterTests {

    @Test("FIT epoch offset is correct")
    func fitEpochOffset() {
        // Garmin FIT epoch: Dec 31 1989 00:00:00 UTC
        // Unix epoch: Jan 1 1970 00:00:00 UTC
        // Difference: 631065600 seconds
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 1989
        components.month = 12
        components.day = 31
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        let fitEpoch = calendar.date(from: components)!
        let offset = fitEpoch.timeIntervalSince1970
        #expect(abs(offset - 631065600) < 1,
                "FIT epoch offset should be 631065600, got \(offset)")
    }

    @Test("Semicircles conversion is consistent with Haversine")
    func semicirclesConsistency() {
        // 45° N ≈ 536870912 semicircles
        let semicircles: Int32 = 536_870_912
        let deg = Haversine.semicirclesToDegrees(semicircles)
        #expect(abs(deg - 45.0) < 0.01)

        // Round-trip: converting back should be close
        let backToSC = Int32(deg / 180.0 * 2_147_483_648.0)
        #expect(abs(Int64(backToSC) - Int64(semicircles)) < 2)
    }

    @Test("FITTimeSeries handles NaN correctly")
    func fitTimeSeriesNaN() {
        // Create a FITTimeSeries with some NaN values
        let ts = FITTimeSeries(
            timestampsMs: ContiguousArray([1000.0, 2000.0, 3000.0]),
            speed: ContiguousArray([Float(4.0), .nan, Float(4.2)]),
            latitude: ContiguousArray([45.0, .nan, 45.001]),
            longitude: ContiguousArray([12.0, .nan, 12.0]),
            heartRate: ContiguousArray([Float(155), .nan, Float(158)]),
            cadence: ContiguousArray([Float.nan, .nan, .nan]),
            power: ContiguousArray([Float.nan, .nan, .nan]),
            distance: ContiguousArray([Float(0), Float(4), Float(8)])
        )

        #expect(ts.speed.count == 3)
        #expect(ts.speed[1].isNaN)
        #expect(!ts.speed[0].isNaN)
        #expect(ts.heartRate[1].isNaN)
    }
}
