//
// SensorDataBuffersTests.swift
// RowData Studio Tests
//
// Tests for SensorDataBuffers: SoA construction, NaN handling, Codable.
//
// Version: 1.0.0 (2026-03-01)
// Revision History:
//   2026-03-01: Initial implementation (Phase 1: Data Models)
//

import Testing
import Foundation
@testable import RowDataStudio

/// Creates a JSON encoder that supports NaN and Infinity values.
private func nanSafeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.nonConformingFloatEncodingStrategy = .convertToString(
        positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
    )
    return encoder
}

/// Creates a JSON decoder that supports NaN and Infinity values.
private func nanSafeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.nonConformingFloatDecodingStrategy = .convertFromString(
        positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
    )
    return decoder
}

@Suite("SensorDataBuffers Tests")
struct SensorDataBuffersTests {

    @Test("SensorDataBuffers initialization with NaN")
    func initializationWithNaN() throws {
        let buffers = SensorDataBuffers(size: 100)

        #expect(buffers.size == 100)
        #expect(buffers.timestamp.count == 100)
        #expect(buffers.imu_raw_ts_acc_surge.count == 100)

        // Verify NaN initialization
        #expect(buffers.timestamp[0].isNaN)
        #expect(buffers.imu_raw_ts_acc_surge[0].isNaN)
        #expect(buffers.fus_cal_ts_vel_inertial[50].isNaN)
        #expect(buffers.gps_gpmf_ts_lat[99].isNaN)

        // Stroke index should be -1 (not NaN)
        #expect(buffers.strokeIndex[0] == -1)
        #expect(buffers.strokeIndex[99] == -1)
    }

    @Test("SensorDataBuffers data assignment")
    func dataAssignment() throws {
        let buffers = SensorDataBuffers(size: 10)

        // Assign some test data
        for i in 0..<10 {
            buffers.timestamp[i] = Double(i) * 5.0  // 0, 5, 10, 15, ...
            buffers.imu_raw_ts_acc_surge[i] = Float(i) * 0.1
            buffers.strokeIndex[i] = Int32(i / 3)
        }

        #expect(buffers.timestamp[5] == 25.0)
        #expect(buffers.imu_raw_ts_acc_surge[7] == 0.7)
        #expect(buffers.strokeIndex[8] == 2)
    }

    @Test("SensorDataBuffers Codable roundtrip")
    func codableRoundtrip() throws {
        let buffers = SensorDataBuffers(size: 5)

        // Populate with test data
        buffers.timestamp = ContiguousArray([0.0, 5.0, 10.0, 15.0, 20.0])
        buffers.imu_raw_ts_acc_surge = ContiguousArray([0.1, 0.2, 0.3, 0.4, 0.5])
        buffers.fus_cal_ts_vel_inertial = ContiguousArray([2.5, 2.6, 2.7, 2.8, 2.9])
        buffers.gps_gpmf_ts_lat = ContiguousArray([45.5, 45.501, 45.502, 45.503, 45.504])
        buffers.strokeIndex = ContiguousArray([0, 0, 1, 1, 2])

        // Add dynamic channel
        buffers.dynamic["test_metric"] = ContiguousArray([1.0, 2.0, 3.0, 4.0, 5.0])

        // Encode (NaN-safe because default-initialized channels contain NaN)
        let jsonData = try nanSafeEncoder().encode(buffers)

        // Decode
        let decoded = try nanSafeDecoder().decode(SensorDataBuffers.self, from: jsonData)

        // Verify
        #expect(decoded.size == 5)
        #expect(decoded.timestamp[2] == 10.0)
        #expect(decoded.imu_raw_ts_acc_surge[3] == 0.4)
        #expect(decoded.fus_cal_ts_vel_inertial[4] == 2.9)
        #expect(decoded.gps_gpmf_ts_lat[1] == 45.501)
        #expect(decoded.strokeIndex[4] == 2)
        #expect(decoded.dynamic["test_metric"]?[2] == 3.0)
    }

    @Test("SensorDataBuffers NaN preservation in Codable")
    func nanPreservationCodable() throws {
        let buffers = SensorDataBuffers(size: 3)

        // Mix of valid data and NaN
        buffers.timestamp = ContiguousArray([0.0, 5.0, 10.0])
        buffers.imu_raw_ts_acc_surge = ContiguousArray([0.1, .nan, 0.3])
        buffers.gps_gpmf_ts_speed = ContiguousArray([2.5, 2.6, .nan])

        // Encode and decode with NaN-safe strategies
        let jsonData = try nanSafeEncoder().encode(buffers)
        let decoded = try nanSafeDecoder().decode(SensorDataBuffers.self, from: jsonData)

        // Verify NaN preserved
        #expect(decoded.imu_raw_ts_acc_surge[0] == 0.1)
        #expect(decoded.imu_raw_ts_acc_surge[1].isNaN)
        #expect(decoded.imu_raw_ts_acc_surge[2] == 0.3)
        #expect(decoded.gps_gpmf_ts_speed[2].isNaN)
    }

    @Test("SensorDataBuffers empty initialization")
    func emptyInitialization() throws {
        let buffers = SensorDataBuffers(size: 0)

        #expect(buffers.size == 0)
        #expect(buffers.timestamp.isEmpty)
        #expect(buffers.imu_raw_ts_acc_surge.isEmpty)
        #expect(buffers.dynamic.isEmpty)
    }

    @Test("SensorDataBuffers large size")
    func largeSize() throws {
        // Simulate 5 minutes at 200Hz
        let size = 200 * 60 * 5  // 60,000 samples
        let buffers = SensorDataBuffers(size: size)

        #expect(buffers.size == size)
        #expect(buffers.timestamp.count == size)
        #expect(buffers.imu_raw_ts_acc_surge.count == size)

        // Spot check NaN initialization
        #expect(buffers.timestamp[size/2].isNaN)
        #expect(buffers.strokeIndex[size-1] == -1)
    }
}
