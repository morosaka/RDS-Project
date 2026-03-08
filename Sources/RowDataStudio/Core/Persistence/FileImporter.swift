// FileImporter.swift v1.0.0
/**
 * File import detection and DataSource creation.
 *
 * Detects file type (MP4, FIT, CSV) and creates appropriate DataSource instances.
 * Validates file format before import.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 5: Session Management).
 *
 * Source: docs/architecture/data-models.md §DataSource
 */

import Foundation
import CSVSwiftSDK

/// Errors that can occur during file import.
public enum FileImporterError: LocalizedError {
    case fileNotFound(URL)
    case unknownFileType(String)
    case invalidFormat(String)
    case readFailed(Error)
    case parseError(Error)
    case unsupportedFileExtension(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found: \(url.path)"
        case .unknownFileType(let ext):
            return "Unknown file type: \(ext)"
        case .invalidFormat(let detail):
            return "Invalid file format: \(detail)"
        case .readFailed(let error):
            return "Failed to read file: \(error.localizedDescription)"
        case .parseError(let error):
            return "Failed to parse file: \(error.localizedDescription)"
        case .unsupportedFileExtension(let ext):
            return "Unsupported file extension: \(ext)"
        }
    }
}

/// File import coordinator.
///
/// Detects file types and creates DataSource instances suitable for addition
/// to a SessionDocument.
public struct FileImporter {

    /// Imports a file and creates a DataSource.
    ///
    /// Automatically detects file type (MP4, FIT, CSV) and parses accordingly.
    /// Validates format before returning.
    ///
    /// - Parameter url: Path to the file to import
    /// - Returns: DataSource instance ready for addition to SessionDocument
    /// - Throws: `FileImporterError` variants
    public static func `import`(from url: URL) async throws -> DataSource {
        let fileManager = FileManager.default

        // Verify file exists
        guard fileManager.fileExists(atPath: url.path) else {
            throw FileImporterError.fileNotFound(url)
        }

        // Get file extension
        let fileExtension = url.pathExtension.lowercased()

        // Route to appropriate importer
        switch fileExtension {
        case "mp4", "mov":
            return try await importGoPro(from: url)
        case "fit":
            return try await importFIT(from: url)
        case "csv":
            return try await importCSV(from: url)
        default:
            throw FileImporterError.unsupportedFileExtension(fileExtension)
        }
    }

    /// Detects the likely file type without full parsing.
    ///
    /// Returns one of: "gopro", "fit", "csv", or "unknown"
    ///
    /// - Parameter url: Path to the file
    /// - Returns: File type descriptor
    public static func detectFileType(of url: URL) -> String {
        let fileExtension = url.pathExtension.lowercased()

        switch fileExtension {
        case "mp4", "mov":
            return "gopro"
        case "fit":
            return "fit"
        case "csv":
            return "csv"
        default:
            return "unknown"
        }
    }

    // MARK: - Private Importers

    /// Imports a GoPro MP4 file.
    private static func importGoPro(from url: URL) async throws -> DataSource {
        // Basic validation: file should be readable
        let fileManager = FileManager.default
        guard fileManager.isReadableFile(atPath: url.path) else {
            throw FileImporterError.invalidFormat("MP4 file is not readable")
        }

        // Create data source with primary role (can be changed later if secondary)
        return DataSource.goProVideo(
            id: UUID(),
            url: url,
            role: .primary
        )
    }

    /// Imports a Garmin FIT file.
    private static func importFIT(from url: URL) async throws -> DataSource {
        // Read file data
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw FileImporterError.readFailed(error)
        }

        // Validate FIT header (FIT files start with size field and ".FIT" magic bytes)
        guard data.count >= 14 else {
            throw FileImporterError.invalidFormat("FIT file is too small")
        }

        // Check for FIT magic bytes
        let magicBytes = data.subdata(in: 8..<12)
        let magicString = String(bytes: magicBytes, encoding: .ascii) ?? ""
        guard magicString == ".FIT" else {
            throw FileImporterError.invalidFormat("FIT file header invalid (expected '.FIT' magic bytes)")
        }

        // Create data source (device will be determined by FIT parser)
        return DataSource.fitFile(
            id: UUID(),
            url: url,
            device: nil
        )
    }

    /// Imports a CSV file (NK SpeedCoach, CrewNerd, or NK Empower).
    private static func importCSV(from url: URL) async throws -> DataSource {
        // Read file as string
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw FileImporterError.readFailed(error)
        }

        guard !content.isEmpty else {
            throw FileImporterError.invalidFormat("CSV file is empty")
        }

        // Detect CSV device/profile by examining header
        let device = detectCSVDevice(content)

        // Create data source
        return DataSource.csvFile(
            id: UUID(),
            url: url,
            device: device
        )
    }

    /// Detects the CSV device/vendor by examining headers.
    ///
    /// Returns one of: "nk_speedcoach", "crewnerd", "nk_empower", or nil
    private static func detectCSVDevice(_ content: String) -> String? {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).prefix(10)
        let headerText = lines.joined(separator: "\n")

        // NK SpeedCoach: contains "Session Info" or "Device Info" sections
        if headerText.contains("Session Info") || headerText.contains("Device Info") {
            return "nk_speedcoach"
        }

        // CrewNerd: contains "Time", "Distance", "Speed", "Pace" headers
        if headerText.contains("Time") && headerText.contains("Distance") && headerText.contains("Speed") {
            return "crewnerd"
        }

        // NK Empower: contains "Force" or "Angle" in headers (biomechanical metrics)
        if headerText.contains("Force") || headerText.contains("Angle") {
            return "nk_empower"
        }

        return nil
    }
}
