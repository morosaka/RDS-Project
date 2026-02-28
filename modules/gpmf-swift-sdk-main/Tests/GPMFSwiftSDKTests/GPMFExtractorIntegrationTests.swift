import XCTest
import Foundation
@testable import GPMFSwiftSDK

/// Integration tests against the real GoPro file ``GX040246.MP4``
/// (chapter 04, session 0246, GX-series camera).
///
/// ## Automatic skipping
/// Every test calls `requireFile()` first. If `GX040246.MP4` is absent from
/// `TestData/`, all tests are cleanly skipped via `XCTSkip` — no failures.
/// This keeps the suite green on CI machines that don't ship the binary fixture.
///
/// ## One-time extraction
/// `class func setUp()` extracts the telemetry exactly once for the whole
/// class, so parsing the 3.7 GB file does not repeat for every test method.
final class GPMFExtractorIntegrationTests: XCTestCase {

    // MARK: - Shared State (populated once per test-class run)

    // `nonisolated(unsafe)` suppresses Swift 6 global-actor warnings for
    // state that is safely written once in setUp() before any test runs.
    private nonisolated(unsafe) static var telemetry: TelemetryData?
    private nonisolated(unsafe) static var extractionError: Error?
    private nonisolated(unsafe) static var testFileFound = false

    override class func setUp() {
        super.setUp()

        // Locate test fixture relative to this source file (works on any machine
        // where the file has been placed; CI will skip cleanly when absent).
        let thisFile = URL(fileURLWithPath: #filePath)
        let fileURL = thisFile
            .deletingLastPathComponent()
            .appendingPathComponent("TestData/GX040246.MP4")

        testFileFound = FileManager.default.fileExists(atPath: fileURL.path)
        guard testFileFound else { return }

        do {
            telemetry = try GPMFExtractor.extract(from: fileURL)
        } catch {
            extractionError = error
        }
    }

    // MARK: - Test Helpers

    /// Skips the test if the fixture is absent; fails if extraction threw.
    private func requireFile() throws {
        try XCTSkipUnless(
            Self.testFileFound,
            "GX040246.MP4 not found in TestData/ — integration test skipped"
        )
        if let err = Self.extractionError {
            XCTFail("GPMFExtractor.extract(from:) threw: \(err)")
        }
    }

    /// Convenience accessor — safe to force-unwrap after `requireFile()`.
    private var t: TelemetryData { Self.telemetry! }

    // MARK: - Extraction

    func test_extraction_succeeds() throws {
        try requireFile()
        XCTAssertNotNil(Self.telemetry)

        // Diagnostic summary — visible with `swift test --verbose`
        let d = t
        print("""

        ┌─ GX040246.MP4 Extraction Report ──────────────────────────────
        │ Camera model  : \(d.cameraModel ?? "(nil)")
        │ Device name   : \(d.deviceName ?? "(nil)")
        │ ORIN          : \(d.orin ?? "(nil)")
        │ Duration      : \(String(format: "%.3f", d.duration)) s
        │ ACCL samples  : \(d.accelReadings.count)  (\(String(format: "%.1f", d.duration > 0 ? Double(d.accelReadings.count)/d.duration : 0)) Hz)
        │ GYRO samples  : \(d.gyroReadings.count)  (\(String(format: "%.1f", d.duration > 0 ? Double(d.gyroReadings.count)/d.duration : 0)) Hz)
        │ GPS  samples  : \(d.gpsReadings.count)
        │ TMPC samples  : \(d.temperatureReadings.count)
        │ CORI samples  : \(d.orientationReadings.count)
        │ GRAV samples  : \(d.gravityReadings.count)
        │ firstGPSU     : \(d.firstGPSU.map { "\($0.value) @ t=\(String(format: "%.3f", $0.relativeTime))s" } ?? "(nil)")
        │ lastGPSU      : \(d.lastGPSU.map { "\($0.value) @ t=\(String(format: "%.3f", $0.relativeTime))s" } ?? "(nil)")
        │ firstGPS9Time : \(d.firstGPS9Time.map { "days=\($0.daysSince2000), secs=\(String(format: "%.3f", $0.secondsSinceMidnight))" } ?? "(nil)")
        │ lastGPS9Time  : \(d.lastGPS9Time.map { "days=\($0.daysSince2000), secs=\(String(format: "%.3f", $0.secondsSinceMidnight))" } ?? "(nil)")
        │ mp4Created    : \(d.mp4CreationTime.map(String.init(describing:)) ?? "(nil)")
        └───────────────────────────────────────────────────────────────
        """)
    }

    // MARK: - Duration

    func test_duration_isPositive() throws {
        try requireFile()
        XCTAssertGreaterThan(t.duration, 0, "duration must be > 0")
    }

    func test_duration_isReasonable() throws {
        try requireFile()
        // A single GoPro chapter is < 4 GB ≈ up to ~30 min at normal bitrates.
        XCTAssertGreaterThan(t.duration,   30, "expected > 30 s per chapter, got \(t.duration)")
        XCTAssertLessThan(   t.duration, 3600, "expected < 1 h per chapter, got \(t.duration)")
    }

    // MARK: - Accelerometer (ACCL)

    func test_accelReadings_exist() throws {
        try requireFile()
        XCTAssertFalse(t.accelReadings.isEmpty, "ACCL readings must not be empty")
    }

    func test_accelSampleRate_isApproximately200Hz() throws {
        try requireFile()
        guard t.duration > 0 else { return }
        let hz = Double(t.accelReadings.count) / t.duration
        XCTAssertGreaterThan(hz, 150, "ACCL rate expected ≈ 200 Hz, got \(String(format: "%.1f", hz)) Hz")
        XCTAssertLessThan(   hz, 250, "ACCL rate expected ≈ 200 Hz, got \(String(format: "%.1f", hz)) Hz")
    }

    func test_accelTimestamps_startNearZero() throws {
        try requireFile()
        let first = t.accelReadings.first!.timestamp
        XCTAssertLessThan(first, 0.1, "First ACCL timestamp should be near 0.0, got \(first)")
    }

    func test_accelTimestamps_endNearDuration() throws {
        try requireFile()
        let last = t.accelReadings.last!.timestamp
        // Last timestamp should be within one payload duration of total duration
        XCTAssertGreaterThan(last, t.duration * 0.9,
                             "Last ACCL timestamp \(last) should be near duration \(t.duration)")
    }

    func test_accelTimestamps_areMonotonicallyNonDecreasing() throws {
        try requireFile()
        let ts = t.accelReadings.map(\.timestamp)
        for i in 1..<ts.count {
            XCTAssertGreaterThanOrEqual(
                ts[i], ts[i - 1],
                "ACCL timestamp regression at index \(i): \(ts[i-1]) → \(ts[i])"
            )
        }
    }

    func test_accelMagnitude_meanIsPhysicallyPlausible() throws {
        try requireFile()
        // For any real-world activity the mean |a| should be between 1 and 100 m/s².
        // Pure gravity alone gives ≈ 9.81 m/s². Extreme athletic motion: 20–50 m/s².
        let mags = t.accelReadings.map {
            (($0.xCam * $0.xCam) + ($0.yCam * $0.yCam) + ($0.zCam * $0.zCam)).squareRoot()
        }
        let mean = mags.reduce(0, +) / Double(mags.count)
        XCTAssertGreaterThan(mean,  1.0, "Mean |ACCL| \(mean) m/s² is unexpectedly low")
        XCTAssertLessThan(   mean, 100.0, "Mean |ACCL| \(mean) m/s² is unexpectedly high")
    }

    // MARK: - Gyroscope (GYRO)

    func test_gyroReadings_exist() throws {
        try requireFile()
        XCTAssertFalse(t.gyroReadings.isEmpty, "GYRO readings must not be empty")
    }

    func test_gyroSampleRate_isApproximately200Hz() throws {
        try requireFile()
        guard t.duration > 0 else { return }
        let hz = Double(t.gyroReadings.count) / t.duration
        XCTAssertGreaterThan(hz, 150, "GYRO rate expected ≈ 200 Hz, got \(String(format: "%.1f", hz)) Hz")
        XCTAssertLessThan(   hz, 250, "GYRO rate expected ≈ 200 Hz, got \(String(format: "%.1f", hz)) Hz")
    }

    func test_gyroTimestamps_areMonotonicallyNonDecreasing() throws {
        try requireFile()
        let ts = t.gyroReadings.map(\.timestamp)
        for i in 1..<ts.count {
            XCTAssertGreaterThanOrEqual(
                ts[i], ts[i - 1],
                "GYRO timestamp regression at index \(i): \(ts[i-1]) → \(ts[i])"
            )
        }
    }

    // MARK: - GPS

    func test_gpsReadings_exist() throws {
        try requireFile()
        // GX-prefix cameras all have GPS (except HERO12, which has no GPS at all).
        // Skip with informational message rather than fail if GPS is absent.
        try XCTSkipIf(
            t.gpsReadings.isEmpty,
            "GPS readings absent — camera may be HERO12 (no GPS) or GPS had no fix"
        )
    }

    func test_gpsCoordinates_areInValidRange() throws {
        try requireFile()
        guard !t.gpsReadings.isEmpty else {
            throw XCTSkip("No GPS readings to validate")
        }
        for (i, r) in t.gpsReadings.enumerated() {
            XCTAssertGreaterThanOrEqual(r.latitude,  -90,  "GPS[\(i)] latitude out of range: \(r.latitude)")
            XCTAssertLessThanOrEqual(   r.latitude,   90,  "GPS[\(i)] latitude out of range: \(r.latitude)")
            XCTAssertGreaterThanOrEqual(r.longitude, -180, "GPS[\(i)] longitude out of range: \(r.longitude)")
            XCTAssertLessThanOrEqual(   r.longitude,  180, "GPS[\(i)] longitude out of range: \(r.longitude)")
        }
    }

    func test_gpsSpeeds_areNonNegative() throws {
        try requireFile()
        guard !t.gpsReadings.isEmpty else {
            throw XCTSkip("No GPS readings to validate")
        }
        for (i, r) in t.gpsReadings.enumerated() {
            XCTAssertGreaterThanOrEqual(r.speed2d, 0, "GPS[\(i)] speed2d < 0: \(r.speed2d)")
            XCTAssertGreaterThanOrEqual(r.speed3d, 0, "GPS[\(i)] speed3d < 0: \(r.speed3d)")
        }
    }

    func test_gpsAltitude_isPlausible() throws {
        try requireFile()
        guard !t.gpsReadings.isEmpty else {
            throw XCTSkip("No GPS readings to validate")
        }
        // Altitude should be within reasonable terrestrial range (−500 m to 9000 m).
        for (i, r) in t.gpsReadings.enumerated() {
            XCTAssertGreaterThan(r.altitude, -500, "GPS[\(i)] altitude \(r.altitude) m below Dead Sea floor")
            XCTAssertLessThan(   r.altitude,  9000, "GPS[\(i)] altitude \(r.altitude) m above Everest")
        }
    }

    // MARK: - Temperature

    func test_temperatureReadings_exist() throws {
        try requireFile()
        XCTAssertFalse(t.temperatureReadings.isEmpty, "TMPC readings must not be empty")
    }

    func test_temperature_isInOperatingRange() throws {
        try requireFile()
        // GoPro operating temperature: 10°C to 35°C (ambient). Internal sensor
        // temperature during recording is typically 40°C to 65°C due to SoC heat.
        // Values outside 0°C..80°C indicate a SCAL misapplication bug (e.g.
        // TMPC companion values being divided by ACCL's SCAL).
        let minT = t.temperatureReadings.map(\.celsius).min()!
        let maxT = t.temperatureReadings.map(\.celsius).max()!
        XCTAssertGreaterThan(minT, 0,
            "Min TMPC \(String(format: "%.2f", minT))°C is below plausible range — possible SCAL bug")
        XCTAssertLessThan(maxT, 80,
            "Max TMPC \(String(format: "%.2f", maxT))°C is above plausible range")

        // Diagnostic
        print("TMPC: min=\(String(format: "%.2f", minT))°C, max=\(String(format: "%.2f", maxT))°C, count=\(t.temperatureReadings.count)")
    }

    // MARK: - Absolute Timestamps

    func test_mp4CreationTime_isNonNil() throws {
        try requireFile()
        XCTAssertNotNil(t.mp4CreationTime, "mvhd creation_time should be parseable")
    }

    func test_mp4CreationTime_isSane() throws {
        try requireFile()
        guard let created = t.mp4CreationTime else { return }

        // Must be after GoPro shipped its first camera (2004) and not in the future.
        var comps = DateComponents()
        comps.year = 2004; comps.month = 1; comps.day = 1
        comps.timeZone = TimeZone(identifier: "UTC")
        let gopro2004 = Calendar(identifier: .gregorian).date(from: comps)!

        XCTAssertGreaterThan(created, gopro2004, "mvhd date \(created) is before GoPro existed")
        XCTAssertLessThanOrEqual(created, Date(), "mvhd date \(created) is in the future")
    }

    // MARK: - ORIN

    func test_orin_isPresentAndValid() throws {
        try requireFile()
        guard let orin = t.orin else {
            // Pre-HERO8 cameras may lack ORIN; not a hard failure.
            throw XCTSkip("ORIN tag absent — pre-HERO8 camera or legacy firmware")
        }
        XCTAssertEqual(orin.count, 3, "ORIN must be exactly 3 characters, got '\(orin)'")
        let valid = CharacterSet(charactersIn: "XYZxyz")
        XCTAssertTrue(
            orin.unicodeScalars.allSatisfy { valid.contains($0) },
            "ORIN '\(orin)' contains invalid characters (expected X/Y/Z/x/y/z)"
        )
    }

    func test_orin_producesPlausibleGravityAxis() throws {
        try requireFile()
        guard t.orin != nil, !t.accelReadings.isEmpty else {
            throw XCTSkip("Need ORIN and ACCL to check gravity axis")
        }
        // The mean |zCam| should be the dominant component if the camera was
        // mostly upright (z_cam = up). We don't know camera orientation, but
        // at minimum the mean magnitude of the mapped vector should be reasonable.
        let meanZ = t.accelReadings.map { abs($0.zCam) }.reduce(0, +) / Double(t.accelReadings.count)
        let meanX = t.accelReadings.map { abs($0.xCam) }.reduce(0, +) / Double(t.accelReadings.count)
        let meanY = t.accelReadings.map { abs($0.yCam) }.reduce(0, +) / Double(t.accelReadings.count)
        print("ORIN gravity check — mean |xCam|=\(String(format: "%.2f", meanX)), |yCam|=\(String(format: "%.2f", meanY)), |zCam|=\(String(format: "%.2f", meanZ))")
        // At least one axis should carry most of the ~9.81 m/s² gravity signature
        let maxMean = max(meanX, meanY, meanZ)
        XCTAssertGreaterThan(maxMean, 3.0, "No single axis shows gravity dominance — ORIN may be wrong")
    }

    // MARK: - Consistency

    func test_sampleCounts_areConsistentWithDuration() throws {
        try requireFile()
        guard t.duration > 0 else { return }
        // ACCL and GYRO sample counts should agree within 5% of each other
        // on cameras where both run at the same nominal rate.
        let acclCount = t.accelReadings.count
        let gyroCount = t.gyroReadings.count
        guard acclCount > 0, gyroCount > 0 else { return }
        let ratio = Double(acclCount) / Double(gyroCount)
        XCTAssertGreaterThan(ratio, 0.8, "ACCL/GYRO count ratio \(ratio) is unexpectedly low")
        XCTAssertLessThan(   ratio, 1.2, "ACCL/GYRO count ratio \(ratio) is unexpectedly high")
    }

    func test_gpuTimestamps_doNotExceedDuration() throws {
        try requireFile()
        guard !t.gpsReadings.isEmpty else { return }
        let maxGPS = t.gpsReadings.map(\.timestamp).max()!
        XCTAssertLessThanOrEqual(
            maxGPS, t.duration + 1.0,  // +1 s tolerance for last-payload rounding
            "Last GPS timestamp \(maxGPS) exceeds file duration \(t.duration)"
        )
    }

    // MARK: - Stream Info

    func test_streamInfo_isPopulated() throws {
        try requireFile()
        XCTAssertFalse(t.streamInfo.isEmpty, "streamInfo should be populated after extraction")
    }

    func test_streamInfo_containsExpectedStreams() throws {
        try requireFile()
        // HERO10 should have at least ACCL, GYRO, GPS5, TMPC, CORI, GRAV
        let expected = ["ACCL", "GYRO", "GPS5", "TMPC", "CORI", "GRAV"]
        for key in expected {
            XCTAssertNotNil(t.streamInfo[key], "streamInfo should contain '\(key)'")
        }
    }

    func test_streamInfo_sampleCount_matchesReadingsArrayCount() throws {
        try requireFile()
        if let accl = t.streamInfo["ACCL"] {
            XCTAssertEqual(accl.sampleCount, t.accelReadings.count,
                           "ACCL streamInfo.sampleCount must match accelReadings.count")
        }
        if let gyro = t.streamInfo["GYRO"] {
            XCTAssertEqual(gyro.sampleCount, t.gyroReadings.count,
                           "GYRO streamInfo.sampleCount must match gyroReadings.count")
        }
        if let gps5 = t.streamInfo["GPS5"] {
            XCTAssertEqual(gps5.sampleCount, t.gpsReadings.count,
                           "GPS5 streamInfo.sampleCount must match gpsReadings.count")
        }
        if let tmpc = t.streamInfo["TMPC"] {
            XCTAssertEqual(tmpc.sampleCount, t.temperatureReadings.count,
                           "TMPC streamInfo.sampleCount must match temperatureReadings.count")
        }
        if let cori = t.streamInfo["CORI"] {
            XCTAssertEqual(cori.sampleCount, t.orientationReadings.count,
                           "CORI streamInfo.sampleCount must match orientationReadings.count")
        }
        if let grav = t.streamInfo["GRAV"] {
            XCTAssertEqual(grav.sampleCount, t.gravityReadings.count,
                           "GRAV streamInfo.sampleCount must match gravityReadings.count")
        }
    }

    func test_streamInfo_sampleRate_isPhysicallyPlausible() throws {
        try requireFile()
        // ACCL/GYRO ≈ 200 Hz, GPS ≈ 10 Hz, TMPC ≈ 2 Hz, CORI/GRAV ≈ 60 Hz
        if let accl = t.streamInfo["ACCL"] {
            XCTAssertGreaterThan(accl.sampleRate, 150, "ACCL rate \(accl.sampleRate) Hz too low")
            XCTAssertLessThan(accl.sampleRate, 250, "ACCL rate \(accl.sampleRate) Hz too high")
        }
        if let gyro = t.streamInfo["GYRO"] {
            XCTAssertGreaterThan(gyro.sampleRate, 150, "GYRO rate \(gyro.sampleRate) Hz too low")
            XCTAssertLessThan(gyro.sampleRate, 250, "GYRO rate \(gyro.sampleRate) Hz too high")
        }
        if let gps5 = t.streamInfo["GPS5"] {
            XCTAssertGreaterThan(gps5.sampleRate, 5, "GPS5 rate \(gps5.sampleRate) Hz too low")
            XCTAssertLessThan(gps5.sampleRate, 20, "GPS5 rate \(gps5.sampleRate) Hz too high")
        }
        if let tmpc = t.streamInfo["TMPC"] {
            XCTAssertGreaterThan(tmpc.sampleRate, 0.5, "TMPC rate \(tmpc.sampleRate) Hz too low")
            XCTAssertLessThan(tmpc.sampleRate, 5, "TMPC rate \(tmpc.sampleRate) Hz too high")
        }
        if let cori = t.streamInfo["CORI"] {
            XCTAssertGreaterThan(cori.sampleRate, 25, "CORI rate \(cori.sampleRate) Hz too low")
            XCTAssertLessThan(cori.sampleRate, 120, "CORI rate \(cori.sampleRate) Hz too high")
        }
    }

    func test_streamInfo_stnmPresent_forAtLeastOneStream() throws {
        try requireFile()
        let hasName = t.streamInfo.values.contains { $0.name != nil }
        XCTAssertTrue(hasName, "At least one stream should have a STNM name")
    }

    func test_streamInfo_siunPresent_forAtLeastOneStream() throws {
        try requireFile()
        let hasSIUN = t.streamInfo.values.contains { $0.siUnit != nil }
        XCTAssertTrue(hasSIUN, "At least one stream should have a SIUN unit string")
    }

    // MARK: - Device ID

    func test_deviceID_isNilOrValid() throws {
        try requireFile()
        // On a typical single-camera HERO10 file, deviceID is nil or a small integer.
        // We don't require it to be present — just validate range if it is.
        if let dvid = t.deviceID {
            XCTAssertLessThan(dvid, 1000, "DVID \(dvid) is unexpectedly large")
        }
    }

    // MARK: - GPS Timestamp Observations

    func test_firstGPSU_isNonNil() throws {
        try requireFile()
        // HERO10 uses GPS5+GPSU — should always have GPSU if GPS had a fix
        XCTAssertNotNil(t.firstGPSU, "firstGPSU should be present on HERO10 with GPS fix")
    }

    func test_lastGPSU_isNonNil() throws {
        try requireFile()
        XCTAssertNotNil(t.lastGPSU, "lastGPSU should be present on HERO10 with GPS fix")
    }

    func test_firstGPSU_relativeTime_isNearZero() throws {
        try requireFile()
        guard let first = t.firstGPSU else {
            throw XCTSkip("No GPSU available")
        }
        // First GPSU should appear within the first few seconds of the file.
        // GPSU runs at ~1 Hz, so the first observation is typically at t ≈ 0-2s.
        XCTAssertLessThan(first.relativeTime, 5.0,
            "firstGPSU.relativeTime \(first.relativeTime)s is too far from start")
    }

    func test_lastGPSU_relativeTime_isNearDuration() throws {
        try requireFile()
        guard let last = t.lastGPSU else {
            throw XCTSkip("No GPSU available")
        }
        // Last GPSU should be within a few seconds of the file duration.
        // GPSU runs at ~1 Hz, so the last observation is typically at t ≈ duration - 1s.
        let gap = t.duration - last.relativeTime
        XCTAssertLessThan(gap, 5.0,
            "lastGPSU.relativeTime gap from duration: \(gap)s — expected < 5s")
        XCTAssertGreaterThanOrEqual(last.relativeTime, 0,
            "lastGPSU.relativeTime must be non-negative")
    }

    func test_lastGPSU_value_matchesExpectedFormat() throws {
        try requireFile()
        guard let last = t.lastGPSU else {
            throw XCTSkip("No GPSU available")
        }
        // GPSU format: "yymmddhhmmss.sss" (16 bytes)
        // We check it's non-empty and starts with digits
        XCTAssertFalse(last.value.isEmpty, "lastGPSU value should not be empty")
        let firstChar = last.value.first!
        XCTAssertTrue(firstChar.isNumber, "GPSU value should start with a digit, got '\(firstChar)'")
    }

    func test_firstGPSU_value_equalsLegacyStringBehavior() throws {
        try requireFile()
        guard let first = t.firstGPSU else {
            throw XCTSkip("No GPSU available")
        }
        // Ensure the .value accessor returns the same string that was previously
        // exposed directly as firstGPSU: String?
        XCTAssertFalse(first.value.isEmpty)
        // On the test file GX040246, the known firstGPSU is "260224132546.600"
        XCTAssertTrue(first.value.contains("."),
            "GPSU value '\(first.value)' should contain a decimal point")
    }

    func test_lastGPSU_relativeTime_isGreaterThanFirst() throws {
        try requireFile()
        guard let first = t.firstGPSU, let last = t.lastGPSU else {
            throw XCTSkip("No GPSU available")
        }
        XCTAssertGreaterThanOrEqual(last.relativeTime, first.relativeTime,
            "lastGPSU.relativeTime should be >= firstGPSU.relativeTime")
    }

    func test_firstGPS9Time_isNil_onHero10() throws {
        try requireFile()
        // HERO10 uses GPS5+GPSU, not GPS9. Both first and last should be nil.
        XCTAssertNil(t.firstGPS9Time, "firstGPS9Time should be nil on HERO10")
        XCTAssertNil(t.lastGPS9Time, "lastGPS9Time should be nil on HERO10")
    }

    // MARK: - Extraction Report (updated with StreamInfo)

    func test_streamInfo_diagnosticReport() throws {
        try requireFile()
        var report = "\n┌─ StreamInfo Report ───────────────────────────────────────\n"
        for (key, info) in t.streamInfo.sorted(by: { $0.key < $1.key }) {
            report += "│ \(key): \(info.sampleCount) samples, "
            report += "\(String(format: "%.1f", info.sampleRate)) Hz"
            if let name = info.name { report += ", name=\"\(name)\"" }
            if let unit = info.siUnit { report += ", unit=\"\(unit)\"" }
            report += "\n"
        }
        report += "│ deviceID: \(t.deviceID.map(String.init) ?? "(nil)")\n"
        report += "└───────────────────────────────────────────────────────────"
        print(report)
    }
}
