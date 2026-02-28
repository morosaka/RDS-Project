import XCTest
@testable import GPMFSwiftSDK

// MARK: - Unit Tests (no real files needed)

final class SessionGrouperUnitTests: XCTestCase {

    // MARK: Helpers

    /// Creates a dummy file URL with the given filename (no actual file created).
    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name)")
    }

    // MARK: Basic Grouping

    func test_group_singleFile() {
        let groups = SessionGrouper.group([url("GH011121.MP4")])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].prefix, "GH")
        XCTAssertEqual(groups[0].sessionID, "1121")
        XCTAssertEqual(groups[0].chapterURLs.count, 1)
    }

    func test_group_multipleChapters_sameSession() {
        let groups = SessionGrouper.group([
            url("GH011122.MP4"),
            url("GH021122.MP4"),
        ])
        XCTAssertEqual(groups.count, 1, "Same session ID should produce one group")
        XCTAssertEqual(groups[0].sessionID, "1122")
        XCTAssertEqual(groups[0].chapterURLs.count, 2)
        // Chapter 01 should be first
        XCTAssertTrue(groups[0].chapterURLs[0].lastPathComponent.hasPrefix("GH01"))
        XCTAssertTrue(groups[0].chapterURLs[1].lastPathComponent.hasPrefix("GH02"))
    }

    func test_group_multipleSessions_samePrefix() {
        let groups = SessionGrouper.group([
            url("GH011121.MP4"),
            url("GH011122.MP4"),
            url("GH021122.MP4"),
        ])
        XCTAssertEqual(groups.count, 2, "Two different session IDs")
        // Sorted by sessionID: 1121 < 1122
        XCTAssertEqual(groups[0].sessionID, "1121")
        XCTAssertEqual(groups[1].sessionID, "1122")
        XCTAssertEqual(groups[0].chapterURLs.count, 1)
        XCTAssertEqual(groups[1].chapterURLs.count, 2)
    }

    func test_group_mixedPrefixes() {
        let groups = SessionGrouper.group([
            url("GH011121.MP4"),
            url("GX010225.MP4"),
        ])
        XCTAssertEqual(groups.count, 2)
        // Sorted by prefix: GH < GX
        XCTAssertEqual(groups[0].prefix, "GH")
        XCTAssertEqual(groups[1].prefix, "GX")
    }

    func test_group_prefixGrouping_sameSessionDifferentPrefix() {
        // Same sessionID but different prefix = different cameras = separate groups
        let groups = SessionGrouper.group([
            url("GH011122.MP4"),
            url("GX011122.MP4"),
        ])
        XCTAssertEqual(groups.count, 2, "Different prefix = different group even with same sessionID")
        XCTAssertEqual(groups[0].prefix, "GH")
        XCTAssertEqual(groups[1].prefix, "GX")
        XCTAssertEqual(groups[0].sessionID, "1122")
        XCTAssertEqual(groups[1].sessionID, "1122")
    }

    // MARK: Sorting

    func test_group_chaptersOutOfOrder_sorted() {
        // Input chapters in reverse order
        let groups = SessionGrouper.group([
            url("GH031122.MP4"),
            url("GH011122.MP4"),
            url("GH021122.MP4"),
        ])
        XCTAssertEqual(groups.count, 1)
        let names = groups[0].chapterURLs.map(\.lastPathComponent)
        XCTAssertEqual(names, ["GH011122.MP4", "GH021122.MP4", "GH031122.MP4"])
    }

    func test_group_sessionIDsSortedAscending() {
        let groups = SessionGrouper.group([
            url("GH011125.MP4"),
            url("GH011121.MP4"),
            url("GH011123.MP4"),
        ])
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.map(\.sessionID), ["1121", "1123", "1125"])
    }

    func test_group_mixedPrefixes_sortedByPrefixThenSession() {
        let groups = SessionGrouper.group([
            url("GX010225.MP4"),
            url("GH011125.MP4"),
            url("GH011121.MP4"),
        ])
        XCTAssertEqual(groups.count, 3)
        // GH < GX alphabetically, then within GH sorted by session
        XCTAssertEqual(groups[0].prefix, "GH")
        XCTAssertEqual(groups[0].sessionID, "1121")
        XCTAssertEqual(groups[1].prefix, "GH")
        XCTAssertEqual(groups[1].sessionID, "1125")
        XCTAssertEqual(groups[2].prefix, "GX")
        XCTAssertEqual(groups[2].sessionID, "0225")
    }

    // MARK: Filtering / Edge Cases

    func test_group_nonGoProFiles_skipped() {
        let groups = SessionGrouper.group([
            url("SpdCoach 2561703 20251201 0300PM.fit"),
            url("notes.txt"),
            url("random_video.mp4"),
        ])
        XCTAssertEqual(groups.count, 0, "Non-GoPro files should be silently skipped")
    }

    func test_group_emptyInput_returnsEmpty() {
        let groups = SessionGrouper.group([])
        XCTAssertEqual(groups.count, 0)
    }

    func test_group_mp4CaseInsensitive() {
        let groups = SessionGrouper.group([url("GH011121.mp4")])
        XCTAssertEqual(groups.count, 1, "Lowercase .mp4 extension should be accepted")
    }

    func test_group_mixedValidAndInvalid() {
        let groups = SessionGrouper.group([
            url("GH011121.MP4"),        // valid
            url("random.fit"),          // invalid
            url("GX010225.MP4"),        // valid
            url("notes.txt"),           // invalid
        ])
        XCTAssertEqual(groups.count, 2, "Only valid GoPro files should be grouped")
    }

    func test_group_chapterURLsMatchInput() {
        let input = [url("GH011121.MP4")]
        let groups = SessionGrouper.group(input)
        XCTAssertEqual(groups[0].chapterURLs[0], input[0])
    }
}

// MARK: - Integration Tests (real files from "20251201 max" directory)

final class SessionGrouperIntegrationTests: XCTestCase {

    // One-time setup: scan the directory for all files
    private nonisolated(unsafe) static var allURLs: [URL] = []
    private nonisolated(unsafe) static var mp4URLs: [URL] = []
    private nonisolated(unsafe) static var directoryFound = false

    override class func setUp() {
        super.setUp()
        let thisFile = URL(fileURLWithPath: #filePath)
        let dirURL = thisFile
            .deletingLastPathComponent()
            .appendingPathComponent("TestData/20251201 max")

        directoryFound = FileManager.default.fileExists(atPath: dirURL.path)
        guard directoryFound else { return }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []

        allURLs = contents
        mp4URLs = contents.filter { $0.pathExtension.uppercased() == "MP4" }
    }

    private func requireDirectory() throws {
        try XCTSkipUnless(
            Self.directoryFound,
            "TestData/20251201 max/ not found — integration test skipped"
        )
    }

    // MARK: Grouping Tests

    func test_group_realSession_groupCount() throws {
        try requireDirectory()
        let groups = SessionGrouper.group(Self.allURLs)
        // 5 GH sessions: 1121 (1 ch), 1122 (2 ch), 1123 (2 ch), 1124 (2 ch), 1125 (1 ch)
        XCTAssertEqual(groups.count, 5,
                       "Expected 5 sessions from GH camera (1121-1125)")
    }

    func test_group_realSession_allPrefixesAreGH() throws {
        try requireDirectory()
        let groups = SessionGrouper.group(Self.allURLs)
        let prefixes = Set(groups.map(\.prefix))
        XCTAssertEqual(prefixes, ["GH"], "All files in this training session are from GH camera")
    }

    func test_group_realSession_sessionIDsAreComplete() throws {
        try requireDirectory()
        let groups = SessionGrouper.group(Self.allURLs)
        let sessionIDs = groups.map(\.sessionID)
        XCTAssertEqual(sessionIDs, ["1121", "1122", "1123", "1124", "1125"],
                       "Sessions should be sorted ascending by session ID")
    }

    func test_group_realSession_session1122_has2chapters() throws {
        try requireDirectory()
        let groups = SessionGrouper.group(Self.allURLs)
        let s1122 = groups.first { $0.sessionID == "1122" && $0.prefix == "GH" }
        XCTAssertNotNil(s1122, "Session 1122 should exist")
        XCTAssertEqual(s1122?.chapterURLs.count, 2, "Session 1122 has 2 chapter files")
        // Verify correct order
        let names = s1122!.chapterURLs.map(\.lastPathComponent)
        XCTAssertEqual(names[0], "GH011122.MP4")
        XCTAssertEqual(names[1], "GH021122.MP4")
    }

    func test_group_realSession_session1121_has1chapter() throws {
        try requireDirectory()
        let groups = SessionGrouper.group(Self.allURLs)
        let s1121 = groups.first { $0.sessionID == "1121" && $0.prefix == "GH" }
        XCTAssertNotNil(s1121)
        XCTAssertEqual(s1121?.chapterURLs.count, 1, "Session 1121 is a single-chapter recording")
    }

    func test_group_realSession_fitFilesExcluded() throws {
        try requireDirectory()
        let groups = SessionGrouper.group(Self.allURLs)
        let allGroupedURLs = groups.flatMap(\.chapterURLs)
        let fitURLs = allGroupedURLs.filter { $0.pathExtension.lowercased() == "fit" }
        XCTAssertEqual(fitURLs.count, 0, "FIT files should not appear in any group")
    }

    func test_group_realSession_allMP4sAccountedFor() throws {
        try requireDirectory()
        let groups = SessionGrouper.group(Self.allURLs)
        let totalGroupedURLs = groups.reduce(0) { $0 + $1.chapterURLs.count }
        XCTAssertEqual(totalGroupedURLs, Self.mp4URLs.count,
                       "All GoPro MP4 files should be in groups (none skipped)")
        // Verify exact count: 8 GoPro files
        // 1121(1) + 1122(2) + 1123(2) + 1124(2) + 1125(1) = 8
        XCTAssertEqual(totalGroupedURLs, 8)
    }

    // MARK: Extraction Test (smallest file only)

    // NOTE: The 2-letter prefix (GH, GX, GL) depends on firmware and video settings,
    // NOT on camera model or encoding format. Both GH and GX prefixes have been
    // observed on HERO10 Black cameras recording in HEVC.
    func test_extractAll_session1121_metadata() throws {
        try requireDirectory()

        // Extract only session 1121 (734 MB — smallest, fastest)
        let groups = SessionGrouper.group(Self.allURLs)
        guard let s1121 = groups.first(where: { $0.sessionID == "1121" && $0.prefix == "GH" }) else {
            XCTFail("Session 1121 not found")
            return
        }

        let extractions = try SessionGrouper.extractAll(s1121.chapterURLs)
        XCTAssertEqual(extractions.count, 1)

        let ext = extractions[0]
        XCTAssertEqual(ext.prefix, "GH")
        XCTAssertEqual(ext.sessionID, "1121")
        XCTAssertEqual(ext.chapterCount, 1)

        let t = ext.telemetry

        // Telemetry validation
        XCTAssertNotNil(t.deviceName, "DVNM should be present")
        XCTAssertGreaterThan(t.duration, 10, "Recording should be at least 10 seconds")
        XCTAssertGreaterThan(t.accelReadings.count, 0, "ACCL data should be present")
        XCTAssertGreaterThan(t.gyroReadings.count, 0, "GYRO data should be present")

        // Diagnostic output
        print("""
        ┌─ GH011121.MP4 Extraction Report ─────────────────────────────
        │ Device name   : \(t.deviceName ?? "(nil)")
        │ Camera model  : \(t.cameraModel ?? "(nil)")
        │ ORIN          : \(t.orin ?? "(nil)")
        │ Duration      : \(String(format: "%.3f", t.duration)) s
        │ ACCL samples  : \(t.accelReadings.count)
        │ GYRO samples  : \(t.gyroReadings.count)
        │ GPS  samples  : \(t.gpsReadings.count)
        │ TMPC samples  : \(t.temperatureReadings.count)
        │ CORI samples  : \(t.orientationReadings.count)
        │ GRAV samples  : \(t.gravityReadings.count)
        │ firstGPSU     : \(t.firstGPSU?.value ?? "(nil)")
        │ firstGPS9Time : \(t.firstGPS9Time?.date.map { "\($0)" } ?? "(nil)")
        │ mp4Created    : \(t.mp4CreationTime.map { "\($0)" } ?? "(nil)")
        └──────────────────────────────────────────────────────────────
        """)
    }
}

// MARK: - Integration Tests (real files from "20251211 mau" directory)
//
// This test class serves two purposes:
// 1. Verifies that the GX prefix is also used by HERO10 Black (proving the prefix
//    is firmware/settings dependent, NOT camera model or encoding format specific)
// 2. Provides a multi-chapter integration test: 5 consecutive chapters from session 0230,
//    exercising ChapterStitcher with real HERO10 data across chapter boundaries

final class SessionGrouperMauIntegrationTests: XCTestCase {

    // One-time setup: scan the "20251211 mau" directory
    private nonisolated(unsafe) static var allURLs: [URL] = []
    private nonisolated(unsafe) static var mp4URLs: [URL] = []
    private nonisolated(unsafe) static var directoryFound = false

    override class func setUp() {
        super.setUp()
        let thisFile = URL(fileURLWithPath: #filePath)
        let dirURL = thisFile
            .deletingLastPathComponent()
            .appendingPathComponent("TestData/20251211 mau")

        directoryFound = FileManager.default.fileExists(atPath: dirURL.path)
        guard directoryFound else { return }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []

        allURLs = contents
        mp4URLs = contents.filter { $0.pathExtension.uppercased() == "MP4" }
    }

    private func requireDirectory() throws {
        try XCTSkipUnless(
            Self.directoryFound,
            "TestData/20251211 mau/ not found — integration test skipped"
        )
    }

    // MARK: Grouping Tests

    func test_group_mauSession_groupCount() throws {
        try requireDirectory()
        let groups = SessionGrouper.group(Self.allURLs)
        // 1 GX session (0230) with 5 chapters
        XCTAssertEqual(groups.count, 1,
                       "Expected 1 session from GX camera (0230)")
    }

    func test_group_mauSession_prefixIsGX() throws {
        try requireDirectory()
        let groups = SessionGrouper.group(Self.allURLs)
        XCTAssertEqual(groups[0].prefix, "GX",
                       "All files in 20251211 mau/ use GX prefix")
    }

    func test_group_mauSession_sessionIDIs0230() throws {
        try requireDirectory()
        let groups = SessionGrouper.group(Self.allURLs)
        XCTAssertEqual(groups[0].sessionID, "0230")
    }

    func test_group_mauSession_has5chapters() throws {
        try requireDirectory()
        let groups = SessionGrouper.group(Self.allURLs)
        XCTAssertEqual(groups[0].chapterURLs.count, 5,
                       "Session 0230 has 5 chapter files (GX01-GX05)")
        // Verify correct chapter order
        let names = groups[0].chapterURLs.map(\.lastPathComponent)
        XCTAssertEqual(names, [
            "GX010230.MP4", "GX020230.MP4", "GX030230.MP4",
            "GX040230.MP4", "GX050230.MP4"
        ])
    }

    func test_group_mauSession_fitFilesExcluded() throws {
        try requireDirectory()
        let groups = SessionGrouper.group(Self.allURLs)
        let allGroupedURLs = groups.flatMap(\.chapterURLs)
        let fitURLs = allGroupedURLs.filter { $0.pathExtension.lowercased() == "fit" }
        XCTAssertEqual(fitURLs.count, 0, "FIT files should not appear in any group")
    }

    func test_group_mauSession_allMP4sAccountedFor() throws {
        try requireDirectory()
        let groups = SessionGrouper.group(Self.allURLs)
        let totalGrouped = groups.reduce(0) { $0 + $1.chapterURLs.count }
        XCTAssertEqual(totalGrouped, Self.mp4URLs.count,
                       "All GoPro MP4 files should be in groups")
        XCTAssertEqual(totalGrouped, 5)
    }

    // MARK: Prefix Verification (GX prefix on HERO10 Black)

    /// Extracts only GX010230.MP4 (first chapter, ~3.7 GB) to verify the device name.
    /// This proves that the GX prefix is NOT exclusively tied to a specific encoding
    /// format or camera generation — both GH and GX are used by HERO10 Black.
    func test_extractSingleChapter_gxPrefixIsHero10() throws {
        try requireDirectory()
        let groups = SessionGrouper.group(Self.allURLs)
        guard let session = groups.first else {
            XCTFail("No session found in 20251211 mau/")
            return
        }

        // Extract only the first chapter to verify device name (faster than all 5)
        let firstChapter = [session.chapterURLs[0]]
        let extractions = try SessionGrouper.extractAll(firstChapter)
        XCTAssertEqual(extractions.count, 1)

        let ext = extractions[0]
        XCTAssertEqual(ext.prefix, "GX")
        XCTAssertEqual(ext.sessionID, "0230")

        let t = ext.telemetry

        // CRITICAL ASSERTION: GX prefix file is also HERO10 Black
        // This proves the prefix is firmware/settings dependent, not model-specific
        XCTAssertNotNil(t.deviceName, "DVNM should be present")
        if let name = t.deviceName {
            XCTAssertTrue(name.contains("HERO10"),
                          "GX010230.MP4 should be from a HERO10 camera, got: \(name)")
        }

        // Basic telemetry sanity checks
        XCTAssertGreaterThan(t.duration, 10, "Recording should be at least 10 seconds")
        XCTAssertGreaterThan(t.accelReadings.count, 0, "ACCL data should be present")
        XCTAssertGreaterThan(t.gyroReadings.count, 0, "GYRO data should be present")

        // Diagnostic output
        print("""
        ┌─ GX010230.MP4 Extraction Report (Prefix Verification) ──────
        │ Device name   : \(t.deviceName ?? "(nil)")
        │ Camera model  : \(t.cameraModel ?? "(nil)")
        │ ORIN          : \(t.orin ?? "(nil)")
        │ Duration      : \(String(format: "%.3f", t.duration)) s
        │ ACCL samples  : \(t.accelReadings.count)
        │ GYRO samples  : \(t.gyroReadings.count)
        │ GPS  samples  : \(t.gpsReadings.count)
        │ TMPC samples  : \(t.temperatureReadings.count)
        │ CORI samples  : \(t.orientationReadings.count)
        │ GRAV samples  : \(t.gravityReadings.count)
        │ firstGPSU     : \(t.firstGPSU?.value ?? "(nil)")
        │ firstGPS9Time : \(t.firstGPS9Time?.date.map { "\($0)" } ?? "(nil)")
        │ mp4Created    : \(t.mp4CreationTime.map { "\($0)" } ?? "(nil)")
        │
        │ ⚡ PREFIX FINDING: GX prefix → \(t.deviceName ?? "?")
        │   (Confirms prefix is firmware/settings dependent, not model-specific)
        └──────────────────────────────────────────────────────────────
        """)
    }

    // MARK: Multi-Chapter Stitching (5 chapters)

    /// Extracts all 5 chapters of session 0230 via ChapterStitcher, exercising
    /// multi-chapter stitching with real HERO10 data. This is the first test that
    /// validates stitching across more than 2 chapter boundaries.
    func test_extractAll_mauSession_multiChapterStitch() throws {
        try requireDirectory()
        let groups = SessionGrouper.group(Self.allURLs)
        guard let session = groups.first else {
            XCTFail("No session found in 20251211 mau/")
            return
        }

        // Stitch all 5 chapters (total ~17 GB of MP4 data)
        let extractions = try SessionGrouper.extractAll(session.chapterURLs)
        XCTAssertEqual(extractions.count, 1)

        let ext = extractions[0]
        XCTAssertEqual(ext.prefix, "GX")
        XCTAssertEqual(ext.sessionID, "0230")
        XCTAssertEqual(ext.chapterCount, 5, "All 5 chapters should be stitched")

        let t = ext.telemetry

        // Stitched telemetry should have substantial data from all 5 chapters
        // Each chapter is ~3.7 GB ≈ ~12 min each → total ~60 min
        XCTAssertGreaterThan(t.duration, 3000,
                             "5 chapters should produce > 50 min of data")

        // Sensor arrays should be much larger than a single chapter
        XCTAssertGreaterThan(t.accelReadings.count, 100_000,
                             "5 chapters × ~200 Hz × ~12 min should produce many ACCL samples")
        XCTAssertGreaterThan(t.gyroReadings.count, 100_000,
                             "GYRO should have similar count to ACCL")

        // Timeline must start at 0.0 and be monotonically increasing
        if let firstAccel = t.accelReadings.first,
           let lastAccel = t.accelReadings.last {
            XCTAssertEqual(firstAccel.timestamp, 0.0, accuracy: 0.01,
                           "Stitched timeline should start at 0.0")
            XCTAssertGreaterThan(lastAccel.timestamp, 3000,
                                 "Last ACCL timestamp should be > 50 min")
        }

        // Verify GPS data is present (HERO10 has GPS5)
        XCTAssertGreaterThan(t.gpsReadings.count, 0, "GPS5 data should be present")
        XCTAssertNotNil(t.firstGPSU, "GPSU should be present on HERO10")

        // Diagnostic output
        let accelRate = t.duration > 0 ? Double(t.accelReadings.count) / t.duration : 0
        let gyroRate  = t.duration > 0 ? Double(t.gyroReadings.count) / t.duration : 0
        let gpsRate   = t.duration > 0 ? Double(t.gpsReadings.count) / t.duration : 0

        // StreamInfo must be populated after 5-chapter stitch
        XCTAssertFalse(t.streamInfo.isEmpty,
                       "streamInfo should be populated after multi-chapter stitch")

        // sampleCount in streamInfo must match the actual reading array counts
        if let accl = t.streamInfo["ACCL"] {
            XCTAssertEqual(accl.sampleCount, t.accelReadings.count,
                           "ACCL streamInfo.sampleCount must match accelReadings.count after stitch")
        }
        if let gyro = t.streamInfo["GYRO"] {
            XCTAssertEqual(gyro.sampleCount, t.gyroReadings.count,
                           "GYRO streamInfo.sampleCount must match gyroReadings.count after stitch")
        }

        // sampleRate should still be ~200 Hz after stitching
        if let accl = t.streamInfo["ACCL"] {
            XCTAssertGreaterThan(accl.sampleRate, 150,
                                 "ACCL rate after stitch should be ~200 Hz, got \(accl.sampleRate)")
            XCTAssertLessThan(accl.sampleRate, 250,
                              "ACCL rate after stitch should be ~200 Hz, got \(accl.sampleRate)")
        }

        // Diagnostic output (updated with StreamInfo)
        var streamReport = ""
        for (key, info) in t.streamInfo.sorted(by: { $0.key < $1.key }) {
            streamReport += "│ \(key): \(info.sampleCount) samples, "
            streamReport += "\(String(format: "%.1f", info.sampleRate)) Hz"
            if let name = info.name { streamReport += ", \"\(name)\"" }
            streamReport += "\n"
        }

        print("""
        ┌─ GX__0230 Multi-Chapter Stitch Report (5 chapters) ─────────
        │ Device name   : \(t.deviceName ?? "(nil)")
        │ Camera model  : \(t.cameraModel ?? "(nil)")
        │ ORIN          : \(t.orin ?? "(nil)")
        │ Duration      : \(String(format: "%.3f", t.duration)) s (\(String(format: "%.1f", t.duration / 60)) min)
        │ Chapters      : \(ext.chapterCount)
        │ ACCL samples  : \(t.accelReadings.count) (\(String(format: "%.1f", accelRate)) Hz)
        │ GYRO samples  : \(t.gyroReadings.count) (\(String(format: "%.1f", gyroRate)) Hz)
        │ GPS  samples  : \(t.gpsReadings.count) (\(String(format: "%.1f", gpsRate)) Hz)
        │ TMPC samples  : \(t.temperatureReadings.count)
        │ CORI samples  : \(t.orientationReadings.count)
        │ GRAV samples  : \(t.gravityReadings.count)
        │ firstGPSU     : \(t.firstGPSU?.value ?? "(nil)")
        │ mp4Created    : \(t.mp4CreationTime.map { "\($0)" } ?? "(nil)")
        │ Timeline      : \(String(format: "%.3f", t.accelReadings.first?.timestamp ?? -1)) → \(String(format: "%.3f", t.accelReadings.last?.timestamp ?? -1)) s
        │ deviceID      : \(t.deviceID.map(String.init) ?? "(nil)")
        \(streamReport)└──────────────────────────────────────────────────────────────
        """)
    }
}
