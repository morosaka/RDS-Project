import XCTest
import Foundation
@testable import GPMFSwiftSDK

// MARK: - Unit Tests (no real files required)

final class ChapterStitcherFilenameTests: XCTestCase {

    // MARK: - parseChapterInfo — valid filenames

    func test_parseChapterInfo_validGX() {
        let url = URL(fileURLWithPath: "/any/path/GX040246.MP4")
        let info = ChapterStitcher.parseChapterInfo(url)
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.prefix, "GX")
        XCTAssertEqual(info?.chapterNumber, 4)
        XCTAssertEqual(info?.sessionID, "0246")
    }

    func test_parseChapterInfo_validGH() {
        let info = ChapterStitcher.parseChapterInfo(URL(fileURLWithPath: "/GH010246.MP4"))
        XCTAssertEqual(info?.prefix, "GH")
        XCTAssertEqual(info?.chapterNumber, 1)
        XCTAssertEqual(info?.sessionID, "0246")
    }

    func test_parseChapterInfo_validGL() {
        let info = ChapterStitcher.parseChapterInfo(URL(fileURLWithPath: "/GL020135.MP4"))
        XCTAssertEqual(info?.chapterNumber, 2)
        XCTAssertEqual(info?.sessionID, "0135")
    }

    func test_parseChapterInfo_lowercaseExtension() {
        // .mp4 lowercase should be accepted
        let info = ChapterStitcher.parseChapterInfo(URL(fileURLWithPath: "/GX040246.mp4"))
        XCTAssertNotNil(info, ".mp4 lowercase extension should be accepted")
    }

    func test_parseChapterInfo_chapterNumber1() {
        let info = ChapterStitcher.parseChapterInfo(URL(fileURLWithPath: "/GX010001.MP4"))
        XCTAssertEqual(info?.chapterNumber, 1)
        XCTAssertEqual(info?.sessionID, "0001")
    }

    // MARK: - parseChapterInfo — invalid filenames

    func test_parseChapterInfo_wrongExtension() {
        XCTAssertNil(ChapterStitcher.parseChapterInfo(URL(fileURLWithPath: "/GX040246.MOV")))
        XCTAssertNil(ChapterStitcher.parseChapterInfo(URL(fileURLWithPath: "/GX040246.AVI")))
    }

    func test_parseChapterInfo_wrongLength_tooShort() {
        // 7 chars base name instead of 8
        XCTAssertNil(ChapterStitcher.parseChapterInfo(URL(fileURLWithPath: "/GX04246.MP4")))
    }

    func test_parseChapterInfo_wrongLength_tooLong() {
        XCTAssertNil(ChapterStitcher.parseChapterInfo(URL(fileURLWithPath: "/GX0402460.MP4")))
    }

    func test_parseChapterInfo_numericPrefix() {
        // First character must be a letter
        XCTAssertNil(ChapterStitcher.parseChapterInfo(URL(fileURLWithPath: "/1X040246.MP4")))
        XCTAssertNil(ChapterStitcher.parseChapterInfo(URL(fileURLWithPath: "/12040246.MP4")))
    }

    func test_parseChapterInfo_lowercasePrefix() {
        // Prefix must be uppercase
        XCTAssertNil(ChapterStitcher.parseChapterInfo(URL(fileURLWithPath: "/gx040246.MP4")))
    }

    func test_parseChapterInfo_nonNumericChapter() {
        // CC must be digits
        XCTAssertNil(ChapterStitcher.parseChapterInfo(URL(fileURLWithPath: "/GXAB0246.MP4")))
    }

    func test_parseChapterInfo_nonNumericSession() {
        // NNNN must be digits
        XCTAssertNil(ChapterStitcher.parseChapterInfo(URL(fileURLWithPath: "/GX04ABCD.MP4")))
    }

    func test_parseChapterInfo_chapterZero_isInvalid() {
        // Chapter 0 is not a valid GoPro chapter number (they start at 01)
        XCTAssertNil(ChapterStitcher.parseChapterInfo(URL(fileURLWithPath: "/GX000246.MP4")))
    }

    func test_parseChapterInfo_randomFilename() {
        XCTAssertNil(ChapterStitcher.parseChapterInfo(URL(fileURLWithPath: "/random_video.MP4")))
        XCTAssertNil(ChapterStitcher.parseChapterInfo(URL(fileURLWithPath: "/myrecording.MP4")))
    }

    // MARK: - Sorting

    func test_parseChapterInfo_preservesOrder_forSorting() {
        let info03 = ChapterStitcher.parseChapterInfo(URL(fileURLWithPath: "/GX030246.MP4"))!
        let info01 = ChapterStitcher.parseChapterInfo(URL(fileURLWithPath: "/GX010246.MP4"))!
        XCTAssertGreaterThan(info03.chapterNumber, info01.chapterNumber,
                             "Chapter 3 should sort after chapter 1")
    }
}

// MARK: - Validation Error Tests (no real files needed — validation runs before extraction)

final class ChapterStitcherValidationTests: XCTestCase {

    func test_stitch_emptyArray_throws() {
        XCTAssertThrowsError(try ChapterStitcher.stitch([])) { error in
            guard case GPMFError.invalidMP4Structure = error else {
                XCTFail("Expected invalidMP4Structure, got \(error)")
                return
            }
        }
    }

    func test_stitch_unrecognizedFilename_throws() {
        let urls = [URL(fileURLWithPath: "/tmp/random_video.MP4")]
        XCTAssertThrowsError(try ChapterStitcher.stitch(urls)) { error in
            guard case GPMFError.unrecognizedChapterFilename(let name) = error else {
                XCTFail("Expected unrecognizedChapterFilename, got \(error)")
                return
            }
            XCTAssertEqual(name, "random_video.MP4")
        }
    }

    func test_stitch_mixedSessionIDs_throws() {
        let urls = [
            URL(fileURLWithPath: "/tmp/GX010246.MP4"),  // session 0246
            URL(fileURLWithPath: "/tmp/GX020247.MP4"),  // session 0247 ← different
        ]
        XCTAssertThrowsError(try ChapterStitcher.stitch(urls)) { error in
            guard case GPMFError.mixedSessionIDs(let ids) = error else {
                XCTFail("Expected mixedSessionIDs, got \(error)")
                return
            }
            XCTAssertTrue(ids.contains("0246"))
            XCTAssertTrue(ids.contains("0247"))
        }
    }

    func test_stitch_nonConsecutiveChapters_throws() {
        // GX01 + GX03 — chapter 2 is missing
        let urls = [
            URL(fileURLWithPath: "/tmp/GX010246.MP4"),
            URL(fileURLWithPath: "/tmp/GX030246.MP4"),
        ]
        XCTAssertThrowsError(try ChapterStitcher.stitch(urls)) { error in
            guard case GPMFError.nonConsecutiveChapters(let nums) = error else {
                XCTFail("Expected nonConsecutiveChapters, got \(error)")
                return
            }
            XCTAssertEqual(nums, [1, 3])
        }
    }

    func test_stitch_singleMixedSessionFile_throws() {
        // Even with one "bad" file in the list
        let urls = [
            URL(fileURLWithPath: "/tmp/GX010246.MP4"),
            URL(fileURLWithPath: "/tmp/GX020246.MP4"),
            URL(fileURLWithPath: "/tmp/GX030999.MP4"),  // different session
        ]
        XCTAssertThrowsError(try ChapterStitcher.stitch(urls)) { error in
            guard case GPMFError.mixedSessionIDs = error else {
                XCTFail("Expected mixedSessionIDs, got \(error)")
                return
            }
        }
    }

    func test_stitch_validatesBeforeExtraction() {
        // Mixed sessions are detected BEFORE attempting to open files,
        // so non-existent paths should still raise the validation error.
        let nonExistentURLs = [
            URL(fileURLWithPath: "/does/not/exist/GX010246.MP4"),
            URL(fileURLWithPath: "/does/not/exist/GX020999.MP4"),  // different session
        ]
        XCTAssertThrowsError(try ChapterStitcher.stitch(nonExistentURLs)) { error in
            // Must be a validation error, NOT a file-not-found error
            guard case GPMFError.mixedSessionIDs = error else {
                XCTFail("Expected mixedSessionIDs before any file I/O, got \(error)")
                return
            }
        }
    }
}

// MARK: - Integration Test (requires GX040246.MP4)

final class ChapterStitcherIntegrationTests: XCTestCase {

    // Extract once for the class
    private nonisolated(unsafe) static var singleExtracted: TelemetryData?
    private nonisolated(unsafe) static var singleStitched: TelemetryData?
    private nonisolated(unsafe) static var testFileFound = false

    override class func setUp() {
        super.setUp()
        let thisFile = URL(fileURLWithPath: #filePath)
        let fileURL = thisFile
            .deletingLastPathComponent()
            .appendingPathComponent("TestData/GX040246.MP4")

        testFileFound = FileManager.default.fileExists(atPath: fileURL.path)
        guard testFileFound else { return }

        singleExtracted = try? GPMFExtractor.extract(from: fileURL)
        singleStitched  = try? ChapterStitcher.stitch([fileURL])
    }

    private func requireFile() throws {
        try XCTSkipUnless(
            Self.testFileFound,
            "GX040246.MP4 not found in TestData/ — integration test skipped"
        )
    }

    // MARK: - Single-chapter stitch must equal direct extract

    func test_stitch_singleChapter_durationMatchesExtract() throws {
        try requireFile()
        guard let ext = Self.singleExtracted, let sti = Self.singleStitched else {
            return XCTFail("Extraction or stitch failed")
        }
        XCTAssertEqual(sti.duration, ext.duration, accuracy: 0.001)
    }

    func test_stitch_singleChapter_accelCountMatchesExtract() throws {
        try requireFile()
        guard let ext = Self.singleExtracted, let sti = Self.singleStitched else { return }
        XCTAssertEqual(sti.accelReadings.count, ext.accelReadings.count)
    }

    func test_stitch_singleChapter_gyroCountMatchesExtract() throws {
        try requireFile()
        guard let ext = Self.singleExtracted, let sti = Self.singleStitched else { return }
        XCTAssertEqual(sti.gyroReadings.count, ext.gyroReadings.count)
    }

    func test_stitch_singleChapter_gpsCountMatchesExtract() throws {
        try requireFile()
        guard let ext = Self.singleExtracted, let sti = Self.singleStitched else { return }
        XCTAssertEqual(sti.gpsReadings.count, ext.gpsReadings.count)
    }

    func test_stitch_singleChapter_metadataMatchesExtract() throws {
        try requireFile()
        guard let ext = Self.singleExtracted, let sti = Self.singleStitched else { return }
        XCTAssertEqual(sti.deviceName, ext.deviceName)
        XCTAssertEqual(sti.orin, ext.orin)
        XCTAssertEqual(sti.firstGPSU, ext.firstGPSU)
        XCTAssertEqual(sti.mp4CreationTime, ext.mp4CreationTime)
    }

    func test_stitch_singleChapter_timestampsAreIdentical() throws {
        try requireFile()
        guard let ext = Self.singleExtracted, let sti = Self.singleStitched else { return }
        // For a single-chapter stitch, timestamps must be unchanged (offset = 0.0)
        for i in 0..<min(100, ext.accelReadings.count) {
            XCTAssertEqual(sti.accelReadings[i].timestamp,
                           ext.accelReadings[i].timestamp,
                           accuracy: 1e-9,
                           "ACCL[\(i)] timestamp mismatch")
        }
    }

    // MARK: - TSMP was collected from the file

    func test_tsmpByStream_isPresentAfterExtraction() throws {
        try requireFile()
        guard let ext = Self.singleExtracted else { return }
        XCTAssertFalse(ext._tsmpByStream.isEmpty,
                       "TSMP should be populated for a real HERO10 file")
    }

    // NOTE: On HERO10, the ACCL and GYRO streams do NOT carry a TSMP tag.
    // Only GPS5, CORI, GRAV, and TMPC streams include TSMP on this camera.
    // ChapterStitcher uses whichever streams DO carry TSMP for coherence validation,
    // so this is sufficient — GPS5 at 10 Hz clearly detects any chapter boundary gap.
    func test_tsmpByStream_gps5IsPresent() throws {
        try requireFile()
        guard let ext = Self.singleExtracted else { return }
        let gps5 = ext._tsmpByStream[GPMFKey.gps5.rawValue]
        XCTAssertNotNil(gps5, "TSMP for GPS5 stream should be present on HERO10")
        if let b = gps5 {
            XCTAssertGreaterThan(b.last, b.first, "TSMP.last must be > TSMP.first")
            XCTAssertGreaterThan(b.last, 0, "TSMP.last must be > 0")
        }
    }

    func test_tsmpByStream_lastIsGreaterThanFirst() throws {
        try requireFile()
        guard let ext = Self.singleExtracted else { return }
        for (stream, bounds) in ext._tsmpByStream {
            XCTAssertGreaterThanOrEqual(bounds.last, bounds.first,
                                        "TSMP.last < TSMP.first for stream \(stream)")
        }
    }

    // MARK: - StreamInfo & DVID propagation

    func test_stitch_singleChapter_streamInfoMatchesExtract() throws {
        try requireFile()
        guard let ext = Self.singleExtracted, let sti = Self.singleStitched else { return }
        // Same keys
        XCTAssertEqual(Set(sti.streamInfo.keys), Set(ext.streamInfo.keys),
                       "Stitched streamInfo keys must match direct extract")
        // Same sample counts
        for (key, extInfo) in ext.streamInfo {
            guard let stiInfo = sti.streamInfo[key] else {
                XCTFail("Missing streamInfo for \(key) in stitched result")
                continue
            }
            XCTAssertEqual(stiInfo.sampleCount, extInfo.sampleCount,
                           "\(key) sampleCount mismatch: stitch=\(stiInfo.sampleCount) vs extract=\(extInfo.sampleCount)")
            XCTAssertEqual(stiInfo.sampleRate, extInfo.sampleRate, accuracy: 0.1,
                           "\(key) sampleRate mismatch")
            XCTAssertEqual(stiInfo.name, extInfo.name, "\(key) name mismatch")
            XCTAssertEqual(stiInfo.siUnit, extInfo.siUnit, "\(key) siUnit mismatch")
        }
    }

    func test_stitch_singleChapter_deviceIDMatchesExtract() throws {
        try requireFile()
        guard let ext = Self.singleExtracted, let sti = Self.singleStitched else { return }
        XCTAssertEqual(sti.deviceID, ext.deviceID,
                       "deviceID must be preserved through single-chapter stitch")
    }

    // MARK: - GPS Timestamp Observation propagation

    func test_stitch_singleChapter_firstGPSU_matchesExtract() throws {
        try requireFile()
        guard let ext = Self.singleExtracted, let sti = Self.singleStitched else { return }
        XCTAssertEqual(sti.firstGPSU, ext.firstGPSU,
                       "firstGPSU must be preserved through single-chapter stitch")
    }

    func test_stitch_singleChapter_lastGPSU_matchesExtract() throws {
        try requireFile()
        guard let ext = Self.singleExtracted, let sti = Self.singleStitched else { return }
        XCTAssertEqual(sti.lastGPSU, ext.lastGPSU,
                       "lastGPSU must be preserved through single-chapter stitch")
    }

    func test_stitch_singleChapter_lastGPSU_relativeTimeUnchanged() throws {
        try requireFile()
        guard let ext = Self.singleExtracted, let sti = Self.singleStitched else { return }
        guard let extLast = ext.lastGPSU, let stiLast = sti.lastGPSU else {
            throw XCTSkip("No lastGPSU available")
        }
        // Single chapter: offset = 0, so relativeTime must be identical
        XCTAssertEqual(stiLast.relativeTime, extLast.relativeTime, accuracy: 1e-9,
                       "Single-chapter stitch should not change lastGPSU.relativeTime")
    }
}
