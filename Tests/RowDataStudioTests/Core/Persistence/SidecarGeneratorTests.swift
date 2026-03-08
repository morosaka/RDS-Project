// Tests/RowDataStudioTests/Core/Persistence/SidecarGeneratorTests.swift v1.0.0
/**
 * Tests for SidecarGenerator telemetry caching.
 * --- Revision History ---
 * v1.0.0 - 2026-03-08 - Initial test suite (Phase 5: Session Management).
 */

import Foundation
import Testing

@testable import RowDataStudio

@Suite("SidecarGenerator")
struct SidecarGeneratorTests {

    @Test("Sidecar metadata creation")
    func sidecarMetadata() {
        let sidecar = TelemetrySidecar(
            version: 1,
            sourceFileHash: "abc123",
            sourceFileName: "GX030230.MP4",
            originalDuration: 300.0,
            trimRange: 10.0...290.0,
            deviceName: "HERO10 Black",
            orin: "ZXY"
        )

        #expect(sidecar.sourceFileName == "GX030230.MP4")
        #expect(sidecar.originalDuration == 300.0)
        #expect(sidecar.trimRange.lowerBound == 10.0)
        #expect(sidecar.trimRange.upperBound == 290.0)
        #expect(sidecar.deviceName == "HERO10 Black")
        #expect(sidecar.orin == "ZXY")
    }

    @Test("Sidecar handles missing GPS data")
    func sidecarWithoutGPS() {
        let sidecar = TelemetrySidecar(
            version: 1,
            sourceFileHash: "test",
            sourceFileName: "novideo.mp4",
            originalDuration: 50.0,
            trimRange: 0.0...50.0,
            firstGPSU: nil,
            lastGPSU: nil
        )

        #expect(sidecar.firstGPSU == nil)
        #expect(sidecar.lastGPSU == nil)
    }

    @Test("Sidecar with GPS timestamp")
    func sidecarWithGPS() {
        let gpsu = GPSTimestampRecord(
            value: "260308120100.500",
            relativeTime: 100.0,
            parsedDate: nil
        )

        let sidecar = TelemetrySidecar(
            version: 1,
            sourceFileHash: "xyz",
            sourceFileName: "gps.mp4",
            originalDuration: 200.0,
            trimRange: 0.0...200.0,
            lastGPSU: gpsu
        )

        #expect(sidecar.lastGPSU?.value == "260308120100.500")
        #expect(sidecar.lastGPSU?.relativeTime == 100.0)
    }

    @Test("Sidecar stores stream info")
    func sidecarStreamInfo() {
        let streamInfo = [
            "ACCL": "Accelerometer: 200.0 Hz",
            "GYRO": "Gyroscope: 200.0 Hz",
            "GPS5": "GPS: 10.0 Hz"
        ]

        let sidecar = TelemetrySidecar(
            version: 1,
            sourceFileHash: "test",
            sourceFileName: "streams.mp4",
            originalDuration: 100.0,
            trimRange: 0.0...100.0,
            streamInfo: streamInfo
        )

        #expect(sidecar.streamInfo.count == 3)
        #expect(sidecar.streamInfo["ACCL"] == "Accelerometer: 200.0 Hz")
        #expect(sidecar.streamInfo["GYRO"] == "Gyroscope: 200.0 Hz")
    }

    @Test("Sidecar version is tracked")
    func sidecarVersion() {
        let sidecar = TelemetrySidecar(
            version: 1,
            sourceFileHash: "v1test",
            sourceFileName: "versioned.mp4",
            originalDuration: 60.0,
            trimRange: 0.0...60.0
        )

        #expect(sidecar.version == 1)
    }

    @Test("Sidecar Codable roundtrip")
    func sidecarCodable() throws {
        let original = TelemetrySidecar(
            version: 1,
            sourceFileHash: "codabletest",
            sourceFileName: "encoded.mp4",
            originalDuration: 75.0,
            trimRange: 15.0...60.0,
            deviceName: "TestCamera",
            orin: "ZXY"
        )

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        // Decode from JSON
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TelemetrySidecar.self, from: data)

        // Verify
        #expect(decoded.sourceFileHash == original.sourceFileHash)
        #expect(decoded.sourceFileName == original.sourceFileName)
        #expect(decoded.originalDuration == original.originalDuration)
        #expect(decoded.deviceName == original.deviceName)
    }
}
