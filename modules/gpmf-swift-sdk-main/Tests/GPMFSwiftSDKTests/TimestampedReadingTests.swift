import XCTest
@testable import GPMFSwiftSDK

// MARK: - Unit Tests (no real files needed)

final class TimestampedReadingTests: XCTestCase {

    // MARK: - Protocol Conformance

    /// Verifies that a generic function accepting TimestampedReading works with all types.
    private func firstTimestamp<T: TimestampedReading>(_ readings: [T]) -> TimeInterval? {
        readings.first?.timestamp
    }

    func test_sensorReading_conformsToTimestampedReading() {
        let r = SensorReading(timestamp: 1.5, xCam: 0, yCam: 0, zCam: 9.81)
        XCTAssertEqual(firstTimestamp([r]), 1.5)
    }

    func test_gpsReading_conformsToTimestampedReading() {
        let r = GpsReading(timestamp: 2.0, latitude: 45, longitude: 9, altitude: 100,
                           speed2d: 0, speed3d: 0)
        XCTAssertEqual(firstTimestamp([r]), 2.0)
    }

    func test_orientationReading_conformsToTimestampedReading() {
        let r = OrientationReading(timestamp: 3.0, w: 1, x: 0, y: 0, z: 0)
        XCTAssertEqual(firstTimestamp([r]), 3.0)
    }

    func test_temperatureReading_conformsToTimestampedReading() {
        let r = TemperatureReading(timestamp: 4.0, celsius: 54.2)
        XCTAssertEqual(firstTimestamp([r]), 4.0)
    }

    func test_exposureReading_conformsToTimestampedReading() {
        let r = ExposureReading(timestamp: 5.0, isoGain: 100, shutterSpeed: 0.001)
        XCTAssertEqual(firstTimestamp([r]), 5.0)
    }

    // MARK: - inTimeRange (ClosedRange)

    private func makeSensorReadings(_ timestamps: [Double]) -> [SensorReading] {
        timestamps.map { SensorReading(timestamp: $0, xCam: 0, yCam: 0, zCam: 0) }
    }

    func test_inTimeRange_closedRange_filtersCorrectly() {
        let readings = makeSensorReadings([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        let filtered = readings.inTimeRange(3.0...7.0)
        XCTAssertEqual(filtered.count, 5)
        XCTAssertEqual(filtered.first?.timestamp, 3.0)
        XCTAssertEqual(filtered.last?.timestamp, 7.0)
    }

    func test_inTimeRange_closedRange_includesBoundaries() {
        let readings = makeSensorReadings([1.0, 2.0, 3.0])
        let filtered = readings.inTimeRange(1.0...3.0)
        XCTAssertEqual(filtered.count, 3, "Closed range must include both boundaries")
    }

    func test_inTimeRange_noMatchingReadings_returnsEmpty() {
        let readings = makeSensorReadings([0, 1, 2])
        let filtered = readings.inTimeRange(10.0...20.0)
        XCTAssertTrue(filtered.isEmpty)
    }

    func test_inTimeRange_emptyArray_returnsEmpty() {
        let empty: [SensorReading] = []
        let filtered = empty.inTimeRange(0.0...10.0)
        XCTAssertTrue(filtered.isEmpty)
    }

    // MARK: - inTimeRange (Range — half-open)

    func test_inTimeRange_halfOpenRange_excludesUpperBound() {
        let readings = makeSensorReadings([1.0, 2.0, 3.0])
        let filtered = readings.inTimeRange(1.0..<3.0)
        XCTAssertEqual(filtered.count, 2, "Half-open range must exclude upper bound")
        XCTAssertEqual(filtered.last?.timestamp, 2.0)
    }

    // MARK: - window(around:radius:)

    func test_window_returnsCorrectSubset() {
        let readings = makeSensorReadings([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        let windowed = readings.window(around: 5.0, radius: 2.0)
        // Should include timestamps 3, 4, 5, 6, 7
        XCTAssertEqual(windowed.count, 5)
        XCTAssertEqual(windowed.first?.timestamp, 3.0)
        XCTAssertEqual(windowed.last?.timestamp, 7.0)
    }

    func test_window_zeroRadius_returnsOnlyExactMatch() {
        let readings = makeSensorReadings([1.0, 2.0, 3.0])
        let windowed = readings.window(around: 2.0, radius: 0)
        XCTAssertEqual(windowed.count, 1)
        XCTAssertEqual(windowed.first?.timestamp, 2.0)
    }

    func test_window_noMatch_returnsEmpty() {
        let readings = makeSensorReadings([1.0, 2.0, 3.0])
        let windowed = readings.window(around: 100.0, radius: 1.0)
        XCTAssertTrue(windowed.isEmpty)
    }

    // MARK: - timeRange

    func test_timeRange_returnsFirstToLastTimestamp() {
        let readings = makeSensorReadings([1.5, 3.0, 7.2])
        let range = readings.timeRange
        XCTAssertNotNil(range)
        XCTAssertEqual(range!.lowerBound, 1.5)
        XCTAssertEqual(range!.upperBound, 7.2)
    }

    func test_timeRange_emptyArray_returnsNil() {
        let empty: [SensorReading] = []
        XCTAssertNil(empty.timeRange)
    }

    func test_timeRange_singleElement_returnsPointRange() {
        let readings = makeSensorReadings([5.0])
        let range = readings.timeRange
        XCTAssertNotNil(range)
        XCTAssertEqual(range!.lowerBound, 5.0)
        XCTAssertEqual(range!.upperBound, 5.0)
    }

    // MARK: - Generic function works with all types

    func test_genericFunction_worksWithAnySensorType() {
        // Verify the same generic function works across all conforming types
        let sensor = [SensorReading(timestamp: 1, xCam: 0, yCam: 0, zCam: 0)]
        let gps = [GpsReading(timestamp: 2, latitude: 0, longitude: 0, altitude: 0, speed2d: 0, speed3d: 0)]
        let orient = [OrientationReading(timestamp: 3, w: 1, x: 0, y: 0, z: 0)]
        let temp = [TemperatureReading(timestamp: 4, celsius: 50)]
        let expo = [ExposureReading(timestamp: 5)]

        XCTAssertEqual(sensor.timeRange?.lowerBound, 1)
        XCTAssertEqual(gps.timeRange?.lowerBound, 2)
        XCTAssertEqual(orient.timeRange?.lowerBound, 3)
        XCTAssertEqual(temp.timeRange?.lowerBound, 4)
        XCTAssertEqual(expo.timeRange?.lowerBound, 5)
    }
}

// MARK: - Integration Tests (require real GX040246.MP4)

final class TimestampedReadingIntegrationTests: XCTestCase {

    private nonisolated(unsafe) static var telemetry: TelemetryData?
    private nonisolated(unsafe) static var testFileFound = false

    override class func setUp() {
        super.setUp()
        let thisFile = URL(fileURLWithPath: #filePath)
        let fileURL = thisFile
            .deletingLastPathComponent()
            .appendingPathComponent("TestData/GX040246.MP4")

        testFileFound = FileManager.default.fileExists(atPath: fileURL.path)
        guard testFileFound else { return }

        telemetry = try? GPMFExtractor.extract(from: fileURL)
    }

    private func requireFile() throws {
        try XCTSkipUnless(
            Self.testFileFound,
            "GX040246.MP4 not found in TestData/ — integration test skipped"
        )
    }

    private var t: TelemetryData { Self.telemetry! }

    func test_accelReadings_inTimeRange_returnsSubset() throws {
        try requireFile()
        // 10s..20s window should return ~200Hz * 10s ≈ 2000 readings
        let filtered = t.accelReadings.inTimeRange(10.0...20.0)
        XCTAssertGreaterThan(filtered.count, 1500,
            "Expected ~2000 ACCL readings in 10s window, got \(filtered.count)")
        XCTAssertLessThan(filtered.count, 2500,
            "Expected ~2000 ACCL readings in 10s window, got \(filtered.count)")
        // All timestamps must be within the range
        for r in filtered {
            XCTAssertGreaterThanOrEqual(r.timestamp, 10.0)
            XCTAssertLessThanOrEqual(r.timestamp, 20.0)
        }
    }

    func test_gpsReadings_window_returnsExpectedCount() throws {
        try requireFile()
        guard !t.gpsReadings.isEmpty else {
            throw XCTSkip("No GPS data")
        }
        // GPS at ~10 Hz: a 5s window (radius=2.5) should return ~50 readings
        let mid = t.duration / 2
        let windowed = t.gpsReadings.window(around: mid, radius: 2.5)
        XCTAssertGreaterThan(windowed.count, 30,
            "Expected ~50 GPS readings in 5s window, got \(windowed.count)")
        XCTAssertLessThan(windowed.count, 80,
            "Expected ~50 GPS readings in 5s window, got \(windowed.count)")
    }

    func test_accelReadings_timeRange_coversFullDuration() throws {
        try requireFile()
        guard let range = t.accelReadings.timeRange else {
            XCTFail("accelReadings.timeRange should not be nil")
            return
        }
        // Should start near 0 and end near duration
        XCTAssertLessThan(range.lowerBound, 1.0, "ACCL timeRange should start near 0")
        XCTAssertGreaterThan(range.upperBound, t.duration - 2.0,
            "ACCL timeRange should end near duration")
    }
}
