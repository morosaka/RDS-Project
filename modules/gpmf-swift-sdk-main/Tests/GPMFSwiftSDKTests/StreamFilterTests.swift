import XCTest
import Foundation
@testable import GPMFSwiftSDK

// MARK: - Unit Tests (no real files needed)

final class StreamFilterUnitTests: XCTestCase {

    // MARK: - Init & Properties

    func test_init_variadic_setsKeys() {
        let f = StreamFilter(.accl, .gyro)
        XCTAssertEqual(f.keys, [.accl, .gyro])
    }

    func test_init_set_setsKeys() {
        let f = StreamFilter(keys: [.gps5, .tmpc])
        XCTAssertEqual(f.keys, [.gps5, .tmpc])
    }

    func test_init_singleKey() {
        let f = StreamFilter(.accl)
        XCTAssertEqual(f.keys.count, 1)
        XCTAssertTrue(f.keys.contains(.accl))
    }

    // MARK: - shouldExtract

    func test_shouldExtract_returnsTrue_forIncludedKey() {
        let f = StreamFilter(.accl, .gyro)
        XCTAssertTrue(f.shouldExtract(.accl))
        XCTAssertTrue(f.shouldExtract(.gyro))
    }

    func test_shouldExtract_returnsFalse_forExcludedKey() {
        let f = StreamFilter(.accl)
        XCTAssertFalse(f.shouldExtract(.gyro))
        XCTAssertFalse(f.shouldExtract(.gps5))
        XCTAssertFalse(f.shouldExtract(.tmpc))
    }

    // MARK: - .all

    func test_all_containsAllSensorKeys() {
        let all = StreamFilter.all
        XCTAssertTrue(all.shouldExtract(.accl))
        XCTAssertTrue(all.shouldExtract(.gyro))
        XCTAssertTrue(all.shouldExtract(.magn))
        XCTAssertTrue(all.shouldExtract(.gps5))
        XCTAssertTrue(all.shouldExtract(.gps9))
        XCTAssertTrue(all.shouldExtract(.tmpc))
        XCTAssertTrue(all.shouldExtract(.cori))
        XCTAssertTrue(all.shouldExtract(.grav))
    }

    func test_all_doesNotContainMetadataKeys() {
        let all = StreamFilter.all
        // Metadata keys should NOT be in the filter — they are always extracted
        XCTAssertFalse(all.shouldExtract(.dvnm))
        XCTAssertFalse(all.shouldExtract(.scal))
        XCTAssertFalse(all.shouldExtract(.gpsu))
        XCTAssertFalse(all.shouldExtract(.tsmp))
    }

    // MARK: - Equatable

    func test_equatable_sameKeys_areEqual() {
        let a = StreamFilter(.accl, .gyro)
        let b = StreamFilter(.gyro, .accl)  // different order, same set
        XCTAssertEqual(a, b)
    }

    func test_equatable_differentKeys_areNotEqual() {
        let a = StreamFilter(.accl)
        let b = StreamFilter(.gyro)
        XCTAssertNotEqual(a, b)
    }

    func test_equatable_all_equalsExplicitSet() {
        let explicit = StreamFilter(keys: [.accl, .gyro, .magn, .gps5, .gps9, .tmpc, .cori, .grav])
        XCTAssertEqual(StreamFilter.all, explicit)
    }
}

// MARK: - Integration Tests (require GX040246.MP4)

final class StreamFilterIntegrationTests: XCTestCase {

    // Extract once for the class
    private nonisolated(unsafe) static var unfilteredTelemetry: TelemetryData?
    private nonisolated(unsafe) static var testFileFound = false
    private nonisolated(unsafe) static var testFileURL: URL?

    override class func setUp() {
        super.setUp()

        let thisFile = URL(fileURLWithPath: #filePath)
        let fileURL = thisFile
            .deletingLastPathComponent()
            .appendingPathComponent("TestData/GX040246.MP4")

        testFileFound = FileManager.default.fileExists(atPath: fileURL.path)
        guard testFileFound else { return }

        testFileURL = fileURL
        unfilteredTelemetry = try? GPMFExtractor.extract(from: fileURL)
    }

    private func requireFile() throws {
        try XCTSkipUnless(
            Self.testFileFound,
            "GX040246.MP4 not found in TestData/ — integration test skipped"
        )
    }

    private var fileURL: URL { Self.testFileURL! }
    private var unfiltered: TelemetryData { Self.unfilteredTelemetry! }

    // MARK: - Single-stream filter: ACCL only

    func test_filter_acclOnly_populatesAccel() throws {
        try requireFile()
        let t = try GPMFExtractor.extract(from: fileURL, streams: StreamFilter(.accl))
        XCTAssertGreaterThan(t.accelReadings.count, 100_000,
            "ACCL should be populated when requested")
    }

    func test_filter_acclOnly_leavesOtherStreamsEmpty() throws {
        try requireFile()
        let t = try GPMFExtractor.extract(from: fileURL, streams: StreamFilter(.accl))
        XCTAssertTrue(t.gyroReadings.isEmpty, "GYRO should be empty when only ACCL requested")
        XCTAssertTrue(t.gpsReadings.isEmpty, "GPS should be empty when only ACCL requested")
        XCTAssertTrue(t.temperatureReadings.isEmpty, "TMPC should be empty when only ACCL requested")
        XCTAssertTrue(t.orientationReadings.isEmpty, "CORI should be empty when only ACCL requested")
        XCTAssertTrue(t.gravityReadings.isEmpty, "GRAV should be empty when only ACCL requested")
    }

    // MARK: - Multi-stream filter: ACCL + GYRO

    func test_filter_acclAndGyro_populatesBoth() throws {
        try requireFile()
        let t = try GPMFExtractor.extract(from: fileURL, streams: StreamFilter(.accl, .gyro))
        XCTAssertGreaterThan(t.accelReadings.count, 100_000,
            "ACCL should be populated")
        XCTAssertGreaterThan(t.gyroReadings.count, 100_000,
            "GYRO should be populated")
    }

    func test_filter_acclAndGyro_leavesGPSEmpty() throws {
        try requireFile()
        let t = try GPMFExtractor.extract(from: fileURL, streams: StreamFilter(.accl, .gyro))
        XCTAssertTrue(t.gpsReadings.isEmpty, "GPS should be empty when only ACCL+GYRO requested")
    }

    // MARK: - GPS-only filter

    func test_filter_gps5Only_populatesGPS() throws {
        try requireFile()
        let t = try GPMFExtractor.extract(from: fileURL, streams: StreamFilter(.gps5))
        XCTAssertGreaterThan(t.gpsReadings.count, 5000,
            "GPS should be populated when GPS5 requested")
    }

    func test_filter_gps5Only_leavesIMUEmpty() throws {
        try requireFile()
        let t = try GPMFExtractor.extract(from: fileURL, streams: StreamFilter(.gps5))
        XCTAssertTrue(t.accelReadings.isEmpty, "ACCL should be empty when only GPS5 requested")
        XCTAssertTrue(t.gyroReadings.isEmpty, "GYRO should be empty when only GPS5 requested")
    }

    // MARK: - Nil filter ≡ unfiltered

    func test_filter_nil_matchesUnfilteredExtract() throws {
        try requireFile()
        let filtered = try GPMFExtractor.extract(from: fileURL, streams: nil)
        XCTAssertEqual(filtered.accelReadings.count, unfiltered.accelReadings.count,
            "nil filter must produce identical ACCL count to unfiltered")
        XCTAssertEqual(filtered.gyroReadings.count, unfiltered.gyroReadings.count,
            "nil filter must produce identical GYRO count to unfiltered")
        XCTAssertEqual(filtered.gpsReadings.count, unfiltered.gpsReadings.count,
            "nil filter must produce identical GPS count to unfiltered")
        XCTAssertEqual(filtered.temperatureReadings.count, unfiltered.temperatureReadings.count,
            "nil filter must produce identical TMPC count to unfiltered")
        XCTAssertEqual(filtered.orientationReadings.count, unfiltered.orientationReadings.count,
            "nil filter must produce identical CORI count to unfiltered")
        XCTAssertEqual(filtered.gravityReadings.count, unfiltered.gravityReadings.count,
            "nil filter must produce identical GRAV count to unfiltered")
    }

    // MARK: - Device metadata always present

    func test_filter_acclOnly_deviceMetadataPresent() throws {
        try requireFile()
        let t = try GPMFExtractor.extract(from: fileURL, streams: StreamFilter(.accl))
        XCTAssertNotNil(t.deviceName, "deviceName must be present regardless of filter")
        XCTAssertNotNil(t.orin, "orin must be present regardless of filter")
        XCTAssertNotNil(t.deviceID, "deviceID must be present regardless of filter")
    }

    // MARK: - GPS timestamp observations always captured

    func test_filter_acclOnly_gpsuAlwaysCaptured() throws {
        try requireFile()
        let t = try GPMFExtractor.extract(from: fileURL, streams: StreamFilter(.accl))
        XCTAssertNotNil(t.firstGPSU,
            "firstGPSU must be captured even when GPS5 is filtered out")
        XCTAssertNotNil(t.lastGPSU,
            "lastGPSU must be captured even when GPS5 is filtered out")
    }

    // MARK: - TSMP always tracked

    func test_filter_acclOnly_tsmpAlwaysTracked() throws {
        try requireFile()
        let t = try GPMFExtractor.extract(from: fileURL, streams: StreamFilter(.accl))
        XCTAssertFalse(t._tsmpByStream.isEmpty,
            "TSMP must be tracked regardless of filter (ChapterStitcher dependency)")
    }

    // MARK: - Duration unchanged by filter

    func test_filter_anyFilter_durationUnchanged() throws {
        try requireFile()
        let t = try GPMFExtractor.extract(from: fileURL, streams: StreamFilter(.accl))
        XCTAssertEqual(t.duration, unfiltered.duration, accuracy: 0.001,
            "Duration must be identical regardless of filter")
    }

    // MARK: - mp4CreationTime always present

    func test_filter_anyFilter_mp4CreationTimePresent() throws {
        try requireFile()
        let t = try GPMFExtractor.extract(from: fileURL, streams: StreamFilter(.accl))
        XCTAssertNotNil(t.mp4CreationTime,
            "mp4CreationTime must be present regardless of filter")
    }

    // MARK: - streamInfo only for requested streams

    func test_filter_acclOnly_streamInfoOnlyContainsACCL() throws {
        try requireFile()
        let t = try GPMFExtractor.extract(from: fileURL, streams: StreamFilter(.accl))
        XCTAssertNotNil(t.streamInfo[GPMFKey.accl.rawValue],
            "streamInfo should contain ACCL when requested")
        XCTAssertNil(t.streamInfo[GPMFKey.gyro.rawValue],
            "streamInfo should NOT contain GYRO when only ACCL requested")
        XCTAssertNil(t.streamInfo[GPMFKey.gps5.rawValue],
            "streamInfo should NOT contain GPS5 when only ACCL requested")
    }

    func test_filter_acclAndGyro_streamInfoContainsBoth() throws {
        try requireFile()
        let t = try GPMFExtractor.extract(from: fileURL, streams: StreamFilter(.accl, .gyro))
        XCTAssertNotNil(t.streamInfo[GPMFKey.accl.rawValue],
            "streamInfo should contain ACCL")
        XCTAssertNotNil(t.streamInfo[GPMFKey.gyro.rawValue],
            "streamInfo should contain GYRO")
        // GPS and others should not be present
        XCTAssertNil(t.streamInfo[GPMFKey.gps5.rawValue],
            "streamInfo should NOT contain GPS5 when only ACCL+GYRO requested")
    }

    // MARK: - Stitch with filter propagates correctly

    func test_stitch_withFilter_propagatesCorrectly() throws {
        try requireFile()
        let t = try ChapterStitcher.stitch([fileURL], streams: StreamFilter(.accl))
        XCTAssertGreaterThan(t.accelReadings.count, 100_000,
            "Stitch with ACCL filter should populate ACCL")
        XCTAssertTrue(t.gyroReadings.isEmpty,
            "Stitch with ACCL filter should leave GYRO empty")
        XCTAssertNotNil(t.deviceName,
            "Device metadata must be preserved through filtered stitch")
    }

    // MARK: - .all filter ≡ unfiltered

    func test_filter_all_matchesUnfilteredExtract() throws {
        try requireFile()
        let t = try GPMFExtractor.extract(from: fileURL, streams: .all)
        XCTAssertEqual(t.accelReadings.count, unfiltered.accelReadings.count,
            ".all filter must produce identical ACCL count")
        XCTAssertEqual(t.gyroReadings.count, unfiltered.gyroReadings.count,
            ".all filter must produce identical GYRO count")
        XCTAssertEqual(t.gpsReadings.count, unfiltered.gpsReadings.count,
            ".all filter must produce identical GPS count")
    }
}
