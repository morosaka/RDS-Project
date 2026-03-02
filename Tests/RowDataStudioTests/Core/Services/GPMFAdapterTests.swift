// Core/Services/GPMFAdapterTests.swift v1.0.0
/**
 * Tests for GPMF SDK adapter layer.
 * Tests intermediate types and conversion logic (no SDK TelemetryData construction
 * since its properties are `public internal(set)`).
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Foundation
import Testing
@testable import RowDataStudio

@Suite("GPMFAdapter")
struct GPMFAdapterTests {

    @Test("GPMFGpsTimeSeries holds correct values")
    func gpsTimeSeriesValues() {
        let gps = GPMFGpsTimeSeries(
            timestampsMs: ContiguousArray([0.0, 1000.0, 2000.0]),
            speed: ContiguousArray([Float(3.9), Float(4.0), Float(4.2)]),
            latitude: ContiguousArray([45.43, 45.431, 45.432]),
            longitude: ContiguousArray([12.34, 12.34, 12.34])
        )

        #expect(gps.timestampsMs.count == 3)
        #expect(abs(gps.speed[0] - 3.9) < 0.01)
        #expect(abs(gps.latitude[0] - 45.43) < 0.0001)
    }

    @Test("GPMFAccelTimeSeries holds correct values")
    func accelTimeSeriesValues() {
        let accel = GPMFAccelTimeSeries(
            timestampsMs: ContiguousArray([0.0, 5.0, 10.0]),
            surgeMps2: ContiguousArray([Float(9.81), Float(9.82), Float(9.80)])
        )

        #expect(accel.timestampsMs.count == 3)
        #expect(abs(accel.surgeMps2[0] - 9.81) < 0.01)
        #expect(abs(accel.timestampsMs[1] - 5.0) < 0.001)
    }

    @Test("SensorDataBuffers initialized with NaN for GPS channels")
    func sensorDataBuffersGpsNaN() {
        let buffers = SensorDataBuffers(size: 10)

        // All GPS channels should be NaN
        for i in 0..<10 {
            #expect(buffers.gps_gpmf_ts_speed[i].isNaN)
            #expect(buffers.gps_gpmf_ts_lat[i].isNaN)
            #expect(buffers.gps_gpmf_ts_lon[i].isNaN)
        }
    }

    @Test("GPSTimestampRecord is Codable")
    func gpsTimestampRecordCodable() throws {
        let record = GPSTimestampRecord(
            value: "260302120530.500",
            relativeTime: 45.3,
            parsedDate: Date(timeIntervalSince1970: 1_000_000)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(record)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(GPSTimestampRecord.self, from: data)

        #expect(decoded.value == record.value)
        #expect(abs(decoded.relativeTime - record.relativeTime) < 0.001)
    }

    @Test("GPS9TimestampRecord is Codable")
    func gps9TimestampRecordCodable() throws {
        let record = GPS9TimestampRecord(
            daysSince2000: 9557,
            secondsSinceMidnight: 43230.500
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(record)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(GPS9TimestampRecord.self, from: data)

        #expect(decoded.daysSince2000 == 9557)
        #expect(abs(decoded.secondsSinceMidnight - 43230.500) < 0.001)
    }
}
