// Sources/CSVSwiftSDK/Profiles/CrewNerdProfile.swift v1.0.0
/**
 * CrewNerd Apple Watch/iPhone CSV Profile Parser
 * --- Revision History ---
 * v1.0.0 - 2026-03-01 - Initial implementation.
 */

import Foundation

/// A parsed CrewNerd session containing time-series telemetry data.
public struct CrewNerdSession: Codable, Sendable {
    public let samples: [TelemetrySample]

    public init(samples: [TelemetrySample]) {
        self.samples = samples
    }

    /// Total session duration in seconds.
    public var duration: TimeInterval {
        guard let last = samples.last else { return 0.0 }
        return last.practiceElapsedTime
    }

    /// Total distance covered in meters.
    public var totalDistance: Double {
        samples.last?.distance ?? 0.0
    }

    /// Total strokes recorded.
    public var totalStrokes: Int {
        samples.last?.strokes ?? 0
    }
}

/// A single telemetry sample from CrewNerd export.
/// Samples are recorded at approximately 1Hz.
public struct TelemetrySample: Codable, Sendable {
    /// Elapsed time in format "H:M:S.mmm" (e.g., "0:0:1.145")
    public let time: String

    /// Cumulative distance in meters
    public let distance: Double

    /// Instantaneous speed in m/s
    public let speed: Double

    /// Instantaneous pace per 500m in format "M:SS.s" (e.g., "15:49.2")
    public let pace: String

    /// Average speed since start in m/s
    public let avgSpeed: Double

    /// Average pace per 500m in format "M:SS.s"
    public let avgPace: String

    /// Cumulative stroke count
    public let strokes: Int

    /// Stroke rate in strokes per minute (SPM)
    public let strokeRate: Double

    /// GPS latitude in decimal degrees
    public let latitude: Double

    /// GPS longitude in decimal degrees
    public let longitude: Double

    /// Check metric (meaning TBD, typically 0)
    public let check: Int

    /// Bounce metric (meaning TBD, typically 0)
    public let bounce: Int

    /// Heart rate in beats per minute (BPM), 0 when not available
    public let heartRate: Int

    /// Practice elapsed time in seconds (monotonic)
    public let practiceElapsedTime: TimeInterval

    /// Meters per stroke (distance/stroke ratio)
    public let metersPerStroke: Double

    public init(time: String, distance: Double, speed: Double, pace: String, avgSpeed: Double, avgPace: String, strokes: Int, strokeRate: Double, latitude: Double, longitude: Double, check: Int, bounce: Int, heartRate: Int, practiceElapsedTime: TimeInterval, metersPerStroke: Double) {
        self.time = time
        self.distance = distance
        self.speed = speed
        self.pace = pace
        self.avgSpeed = avgSpeed
        self.avgPace = avgPace
        self.strokes = strokes
        self.strokeRate = strokeRate
        self.latitude = latitude
        self.longitude = longitude
        self.check = check
        self.bounce = bounce
        self.heartRate = heartRate
        self.practiceElapsedTime = practiceElapsedTime
        self.metersPerStroke = metersPerStroke
    }
}

/// Errors occurring during CrewNerd profile parsing.
public enum CrewNerdParseError: Error, Equatable {
    case invalidFormat(String)
    case missingHeader
    case invalidData(row: Int, reason: String)
    case fileNotFound
}

/// Main parser entry point for CrewNerd CSV files.
public struct CrewNerdParser {

    /// Parses a CrewNerd CSV file.
    /// - Parameter csvString: The raw CSV contents exported from CrewNerd app.
    /// - Returns: A parsed session containing all telemetry samples.
    /// - Throws: `CrewNerdParseError` when parsing fails.
    public static func parse(_ csvString: String) throws -> CrewNerdSession {
        // Use generic CSV parser
        let csv = try CSV<Enumerated>(string: csvString, delimiter: .comma, loadColumns: false)

        guard csv.header.count == 15 else {
            throw CrewNerdParseError.missingHeader
        }

        // Validate expected header
        let expectedHeaders = [
            "Time", "Distance (m)", "Speed (m/s)", "Pace (/500m)",
            "Avg Speed (m/s)", "Avg Pace (/500m)", "Strokes", "Stroke Rate (SPM)",
            "Lat", "Lon", "Check", "Bounce", "HR (BPM)",
            "Practice Elapsed Time (s)", "m/str"
        ]

        guard csv.header == expectedHeaders else {
            throw CrewNerdParseError.invalidFormat("Header mismatch. Expected CrewNerd format.")
        }

        var samples: [TelemetrySample] = []

        for (rowIndex, row) in csv.rows.enumerated() {
            guard row.count == 15 else {
                throw CrewNerdParseError.invalidData(
                    row: rowIndex + 2,
                    reason: "Expected 15 columns, found \(row.count)"
                )
            }

            do {
                let sample = TelemetrySample(
                    time: row[0],
                    distance: try parseDouble(row[1], field: "Distance", row: rowIndex + 2),
                    speed: try parseDouble(row[2], field: "Speed", row: rowIndex + 2),
                    pace: row[3],
                    avgSpeed: try parseDouble(row[4], field: "Avg Speed", row: rowIndex + 2),
                    avgPace: row[5],
                    strokes: try parseInt(row[6], field: "Strokes", row: rowIndex + 2),
                    strokeRate: try parseDouble(row[7], field: "Stroke Rate", row: rowIndex + 2),
                    latitude: try parseDouble(row[8], field: "Lat", row: rowIndex + 2),
                    longitude: try parseDouble(row[9], field: "Lon", row: rowIndex + 2),
                    check: try parseInt(row[10], field: "Check", row: rowIndex + 2),
                    bounce: try parseInt(row[11], field: "Bounce", row: rowIndex + 2),
                    heartRate: try parseInt(row[12], field: "HR", row: rowIndex + 2),
                    practiceElapsedTime: try parseDouble(row[13], field: "Practice Elapsed Time", row: rowIndex + 2),
                    metersPerStroke: try parseDouble(row[14], field: "m/str", row: rowIndex + 2)
                )
                samples.append(sample)
            } catch {
                // Re-throw with row context
                throw error
            }
        }

        return CrewNerdSession(samples: samples)
    }

    // MARK: - Helper Methods

    private static func parseDouble(_ string: String, field: String, row: Int) throws -> Double {
        guard let value = Double(string) else {
            throw CrewNerdParseError.invalidData(
                row: row,
                reason: "Invalid double for \(field): '\(string)'"
            )
        }
        return value
    }

    private static func parseInt(_ string: String, field: String, row: Int) throws -> Int {
        guard let value = Int(string) else {
            throw CrewNerdParseError.invalidData(
                row: row,
                reason: "Invalid integer for \(field): '\(string)'"
            )
        }
        return value
    }
}
