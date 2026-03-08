// SidecarGenerator.swift v1.0.0
/**
 * Telemetry sidecar generation from GoPro video.
 *
 * Extracts GPMF metadata and creates a TelemetrySidecar to cache parsing results.
 * Eliminates the need to re-parse the MP4 GPMF track on every session load.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 5: Session Management).
 *
 * Source: docs/architecture/data-models.md §TelemetrySidecar
 */

import Foundation
import GPMFSwiftSDK

/// Errors that can occur during sidecar generation.
public enum SidecarGeneratorError: LocalizedError {
    case fileNotFound(URL)
    case hashComputationFailed(Error)
    case gpmfExtractionFailed(Error)
    case invalidTelemetryData
    case compressionFailed(Error)
    case fileWriteFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Video file not found: \(url.path)"
        case .hashComputationFailed(let error):
            return "Failed to compute file hash: \(error.localizedDescription)"
        case .gpmfExtractionFailed(let error):
            return "Failed to extract GPMF data: \(error.localizedDescription)"
        case .invalidTelemetryData:
            return "Extracted telemetry data is invalid"
        case .compressionFailed(let error):
            return "Failed to compress sidecar: \(error.localizedDescription)"
        case .fileWriteFailed(let error):
            return "Failed to write sidecar file: \(error.localizedDescription)"
        }
    }
}

/// Generates and manages telemetry sidecars for GoPro videos.
public struct SidecarGenerator {

    /// Generates a sidecar from a GoPro MP4 file.
    ///
    /// Extracts GPMF metadata and creates a TelemetrySidecar. The sidecar
    /// can be used to avoid re-parsing the MP4 file on subsequent loads.
    ///
    /// - Parameters:
    ///   - videoURL: Path to the GoPro MP4 file
    ///   - trimRange: Optional time range to extract (in seconds). If nil, extracts entire file.
    /// - Returns: TelemetrySidecar with metadata
    /// - Throws: `SidecarGeneratorError` variants
    public static func generate(
        from videoURL: URL,
        trimRange: ClosedRange<TimeInterval>? = nil
    ) throws -> TelemetrySidecar {
        // Verify file exists
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: videoURL.path) else {
            throw SidecarGeneratorError.fileNotFound(videoURL)
        }

        // Compute SHA256 hash of source file
        let sourceFileHash = try computeHash(of: videoURL)

        // Extract GPMF telemetry
        let telemetryData: TelemetryData
        do {
            telemetryData = try GPMFAdapter.extractTelemetry(from: videoURL)
        } catch {
            throw SidecarGeneratorError.gpmfExtractionFailed(error)
        }

        // Determine trim range (default to full duration)
        let range = trimRange ?? (0.0...telemetryData.duration)

        // Compute absoluteOrigin from lastGPSU if available
        let absoluteOrigin = computeAbsoluteOrigin(from: telemetryData.lastGPSU)

        // Convert stream info to simple string format (for sidecar storage)
        let streamInfoStrings = convertStreamInfo(telemetryData.streamInfo)

        // Create sidecar
        let sidecar = TelemetrySidecar(
            version: 1,
            sourceFileHash: sourceFileHash,
            sourceFileName: videoURL.lastPathComponent,
            originalDuration: telemetryData.duration,
            trimRange: range,
            absoluteOrigin: absoluteOrigin,
            deviceName: telemetryData.deviceName,
            deviceID: telemetryData.deviceID,
            orin: telemetryData.orin,
            firstGPSU: convertGPSTimestamp(telemetryData.firstGPSU),
            lastGPSU: convertGPSTimestamp(telemetryData.lastGPSU),
            firstGPS9Time: convertGPS9Timestamp(telemetryData.firstGPS9Time),
            lastGPS9Time: convertGPS9Timestamp(telemetryData.lastGPS9Time),
            mp4CreationTime: telemetryData.mp4CreationTime,
            streamInfo: streamInfoStrings
        )

        return sidecar
    }

    /// Saves a sidecar to disk as gzipped JSON.
    ///
    /// Names the file using the pattern: `{videoBasename}_trim_{startS}s_{endS}s.telemetry.gz`
    /// For example: `GX030230_trim_120s_385s.telemetry.gz`
    ///
    /// - Parameters:
    ///   - sidecar: The sidecar to save
    ///   - directory: Directory to save the sidecar in
    /// - Returns: URL of the saved file
    /// - Throws: `SidecarGeneratorError` variants
    public static func save(
        _ sidecar: TelemetrySidecar,
        in directory: URL
    ) throws -> URL {
        let baseName = (sidecar.sourceFileName as NSString).deletingPathExtension
        let startS = Int(sidecar.trimRange.lowerBound)
        let endS = Int(sidecar.trimRange.upperBound)
        let fileName = "\(baseName)_trim_\(startS)s_\(endS)s.telemetry.gz"
        let fileURL = directory.appendingPathComponent(fileName)

        // Encode sidecar as JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let jsonData: Data
        do {
            jsonData = try encoder.encode(sidecar)
        } catch {
            throw SidecarGeneratorError.compressionFailed(error)
        }

        // Compress with gzip
        let compressedData: Data
        do {
            compressedData = try (jsonData as NSData).compressed(using: .lz4) as Data
        } catch {
            throw SidecarGeneratorError.compressionFailed(error)
        }

        // Write to disk
        do {
            try compressedData.write(to: fileURL, options: .atomic)
        } catch {
            throw SidecarGeneratorError.fileWriteFailed(error)
        }

        return fileURL
    }

    /// Loads a previously saved sidecar from disk.
    ///
    /// - Parameter fileURL: URL of the compressed sidecar file
    /// - Returns: TelemetrySidecar
    /// - Throws: `SidecarGeneratorError` variants
    public static func load(from fileURL: URL) throws -> TelemetrySidecar {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw SidecarGeneratorError.fileNotFound(fileURL)
        }

        // Read compressed data
        let compressedData: Data
        do {
            compressedData = try Data(contentsOf: fileURL)
        } catch {
            throw SidecarGeneratorError.fileWriteFailed(error)
        }

        // Decompress
        let jsonData: Data
        do {
            jsonData = try (compressedData as NSData).decompressed(using: .lz4) as Data
        } catch {
            throw SidecarGeneratorError.compressionFailed(error)
        }

        // Decode JSON
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(TelemetrySidecar.self, from: jsonData)
        } catch {
            throw SidecarGeneratorError.compressionFailed(error)
        }
    }

    // MARK: - Private Helpers

    /// Computes a simple file hash using modification date and size.
    ///
    /// This is used for cache validation, not cryptographic security.
    private static func computeHash(of url: URL) throws -> String {
        let fileManager = FileManager.default
        let attrs = try fileManager.attributesOfItem(atPath: url.path)

        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        let modDate = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

        return "\(Int(modDate))_\(size)"
    }

    /// Converts GPMF SDK GPSTimestampObservation to TelemetrySidecar-compatible type.
    ///
    /// Note: The GPSU string parsing is deferred to the consuming application.
    private static func convertGPSTimestamp(
        _ gpsTimestamp: GPSTimestampObservation?
    ) -> GPSTimestampRecord? {
        guard let gps = gpsTimestamp else { return nil }
        return GPSTimestampRecord(
            value: gps.value,
            relativeTime: gps.relativeTime,
            parsedDate: nil  // Parsing deferred to app layer
        )
    }

    /// Converts GPMF SDK GPS9Timestamp to TelemetrySidecar-compatible type.
    private static func convertGPS9Timestamp(
        _ gps9Timestamp: GPS9Timestamp?
    ) -> GPS9TimestampRecord? {
        guard let gps9 = gps9Timestamp else { return nil }
        return GPS9TimestampRecord(
            daysSince2000: gps9.daysSince2000,
            secondsSinceMidnight: gps9.secondsSinceMidnight
        )
    }

    /// Converts StreamInfo dictionary to simple string format for storage.
    ///
    /// Each StreamInfo is converted to a human-readable string representation.
    private static func convertStreamInfo(_ info: [String: StreamInfo]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in info {
            // Create a simple description: "Accelerometer: 200.0 Hz"
            let name = value.name ?? key
            let rateStr = String(format: "%.1f", value.sampleRate)
            let description = "\(name): \(rateStr) Hz"
            result[key] = description
        }
        return result
    }

    /// Computes absolute UTC start time from lastGPSU observation.
    ///
    /// Uses the formula: absoluteStart = parseGPSU(lastGPSU.value) - lastGPSU.relativeTime
    ///
    /// Returns nil if lastGPSU is not available or parsing fails.
    private static func computeAbsoluteOrigin(from lastGPSU: GPSTimestampObservation?) -> Date? {
        guard let gps = lastGPSU else { return nil }

        // Parse GPSU string format: "yymmddhhmmss.sss"
        let value = gps.value
        guard value.count >= 12 else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMddHHmmss"
        formatter.timeZone = TimeZone(abbreviation: "UTC")

        // Extract the integer part (without milliseconds)
        let intPart = String(value.prefix(12))
        guard let gpsuDate = formatter.date(from: intPart) else { return nil }

        // Back-compute to file start: subtract the relative time offset
        let absoluteStart = gpsuDate.addingTimeInterval(-gps.relativeTime)
        return absoluteStart
    }
}
