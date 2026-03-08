// Tests/RowDataStudioTests/Core/Persistence/FileImporterTests.swift v1.0.0
/**
 * Tests for FileImporter file type detection.
 * --- Revision History ---
 * v1.0.0 - 2026-03-08 - Initial test suite (Phase 5: Session Management).
 */

import Foundation
import Testing

@testable import RowDataStudio

@Suite("FileImporter")
struct FileImporterTests {

    @Test("Detect MP4 file type")
    func detectMP4() {
        let mp4URL = URL(fileURLWithPath: "/tmp/video.mp4")
        let type = FileImporter.detectFileType(of: mp4URL)
        #expect(type == "gopro")
    }

    @Test("Detect MOV file type")
    func detectMOV() {
        let movURL = URL(fileURLWithPath: "/tmp/video.MOV")
        let type = FileImporter.detectFileType(of: movURL)
        #expect(type == "gopro")
    }

    @Test("Detect FIT file type")
    func detectFIT() {
        let fitURL = URL(fileURLWithPath: "/tmp/data.fit")
        let type = FileImporter.detectFileType(of: fitURL)
        #expect(type == "fit")
    }

    @Test("Detect CSV file type")
    func detectCSV() {
        let csvURL = URL(fileURLWithPath: "/tmp/export.csv")
        let type = FileImporter.detectFileType(of: csvURL)
        #expect(type == "csv")
    }

    @Test("Detect unknown file type")
    func detectUnknown() {
        let unknownURL = URL(fileURLWithPath: "/tmp/file.txt")
        let type = FileImporter.detectFileType(of: unknownURL)
        #expect(type == "unknown")
    }

    @Test("Case insensitive extension detection")
    func caseInsensitive() {
        #expect(FileImporter.detectFileType(of: URL(fileURLWithPath: "/tmp/test.MP4")) == "gopro")
        #expect(FileImporter.detectFileType(of: URL(fileURLWithPath: "/tmp/test.FIT")) == "fit")
        #expect(FileImporter.detectFileType(of: URL(fileURLWithPath: "/tmp/test.CSV")) == "csv")
    }
}
