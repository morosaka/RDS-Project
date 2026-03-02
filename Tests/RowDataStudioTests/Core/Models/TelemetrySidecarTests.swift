//
// TelemetrySidecarTests.swift
// RowData Studio Tests
//
// Tests for TelemetrySidecar: Codable roundtrip, versioning.
//
// Version: 1.0.0 (2026-03-01)
// Revision History:
//   2026-03-01: Initial implementation (Phase 1: Data Models)
//

import Testing
import Foundation
@testable import RowDataStudio

@Suite("TelemetrySidecar Tests")
struct TelemetrySidecarTests {

    @Test("TelemetrySidecar Codable roundtrip")
    func codableRoundtrip() throws {
        let sidecar = TelemetrySidecar(
            version: 1,
            sourceFileHash: "abc123def456",
            sourceFileName: "GX030230.MP4",
            originalDuration: 711.5,
            trimRange: 120.0...385.0,
            absoluteOrigin: Date(timeIntervalSince1970: 1709338200),
            deviceName: "HERO10 Black",
            deviceID: 12345678,
            orin: "ZXY",
            mp4CreationTime: Date(timeIntervalSince1970: 1709337000),
            streamInfo: [:]
        )

        // Encode
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(sidecar)

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TelemetrySidecar.self, from: jsonData)

        // Verify
        #expect(decoded.version == 1)
        #expect(decoded.sourceFileHash == "abc123def456")
        #expect(decoded.sourceFileName == "GX030230.MP4")
        #expect(decoded.originalDuration == 711.5)
        #expect(decoded.trimRange == 120.0...385.0)
        #expect(decoded.deviceName == "HERO10 Black")
        #expect(decoded.deviceID == 12345678)
        #expect(decoded.orin == "ZXY")
    }

    @Test("TelemetrySidecar minimal configuration")
    func minimalConfiguration() throws {
        let sidecar = TelemetrySidecar(
            sourceFileHash: "hash",
            sourceFileName: "test.mp4",
            originalDuration: 300.0,
            trimRange: 0.0...300.0
        )

        #expect(sidecar.version == 1)
        #expect(sidecar.deviceName == nil)
        #expect(sidecar.absoluteOrigin == nil)
        #expect(sidecar.streamInfo.isEmpty)

        // Roundtrip
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(sidecar)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TelemetrySidecar.self, from: jsonData)

        #expect(decoded.sourceFileHash == "hash")
        #expect(decoded.trimRange == 0.0...300.0)
    }

    @Test("TelemetrySidecar with stream info")
    func withStreamInfo() throws {
        let sidecar = TelemetrySidecar(
            sourceFileHash: "hash",
            sourceFileName: "test.mp4",
            originalDuration: 300.0,
            trimRange: 0.0...300.0,
            streamInfo: [
                "ACCL": "200Hz",
                "GYRO": "200Hz",
                "GPS5": "18Hz"
            ]
        )

        // Roundtrip
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(sidecar)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TelemetrySidecar.self, from: jsonData)

        #expect(decoded.streamInfo.count == 3)
        #expect(decoded.streamInfo["ACCL"] == "200Hz")
        #expect(decoded.streamInfo["GPS5"] == "18Hz")
    }

    @Test("TelemetrySidecar trim range extraction")
    func trimRangeExtraction() throws {
        let sidecar = TelemetrySidecar(
            sourceFileHash: "hash",
            sourceFileName: "GX030230.MP4",
            originalDuration: 711.5,
            trimRange: 120.0...385.0
        )

        let trimDuration = sidecar.trimRange.upperBound - sidecar.trimRange.lowerBound
        #expect(trimDuration == 265.0)
    }
}
