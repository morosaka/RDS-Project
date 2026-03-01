// Sources/CSVSwiftSDK/Profiles/NKSpeedCoachProfile.swift v1.0.0
/**
 * NK SpeedCoach GPS CSV Profile Parser
 * --- Revision History ---
 * v1.0.0 - 2026-03-01 - Initial implementation.
 */

import Foundation

/// A parsed NK SpeedCoach session containing metadata and per-stroke data.
public struct NKSpeedCoachSession: Codable, Sendable {
    public let sessionInfo: SessionInfo
    public let deviceInfo: DeviceInfo
    public let summary: SessionSummary
    public let intervals: [IntervalSummary]
    public let strokes: [NKSpeedCoachStroke]

    public init(sessionInfo: SessionInfo, deviceInfo: DeviceInfo, summary: SessionSummary, intervals: [IntervalSummary], strokes: [NKSpeedCoachStroke]) {
        self.sessionInfo = sessionInfo
        self.deviceInfo = deviceInfo
        self.summary = summary
        self.intervals = intervals
        self.strokes = strokes
    }
}

/// Session metadata from NK SpeedCoach export.
public struct SessionInfo: Codable, Sendable {
    public let name: String
    public let startTime: Date?
    public let type: String
    public let systemOfUnits: String
    public let speedInput: String

    public init(name: String, startTime: Date?, type: String, systemOfUnits: String, speedInput: String) {
        self.name = name
        self.startTime = startTime
        self.type = type
        self.systemOfUnits = systemOfUnits
        self.speedInput = speedInput
    }
}

/// Device information from NK SpeedCoach export.
public struct DeviceInfo: Codable, Sendable {
    public let name: String
    public let model: String
    public let serial: String
    public let firmwareVersion: String
    public let profileVersion: String
    public let hardwareVersion: String
    public let linkVersion: String

    public init(name: String, model: String, serial: String, firmwareVersion: String, profileVersion: String, hardwareVersion: String, linkVersion: String) {
        self.name = name
        self.model = model
        self.serial = serial
        self.firmwareVersion = firmwareVersion
        self.profileVersion = profileVersion
        self.hardwareVersion = hardwareVersion
        self.linkVersion = linkVersion
    }
}

/// Overall session summary statistics.
public struct SessionSummary: Codable, Sendable {
    public let totalIntervals: Int
    public let totalDistanceGPS: Double
    public let totalElapsedTime: TimeInterval
    public let avgSplitGPS: TimeInterval?
    public let avgSpeedGPS: Double
    public let avgStrokeRate: Double
    public let totalStrokes: Int
    public let distancePerStrokeGPS: Double
    public let avgHeartRate: Double?
    public let startLatitude: Double?
    public let startLongitude: Double?

    public init(totalIntervals: Int, totalDistanceGPS: Double, totalElapsedTime: TimeInterval, avgSplitGPS: TimeInterval?, avgSpeedGPS: Double, avgStrokeRate: Double, totalStrokes: Int, distancePerStrokeGPS: Double, avgHeartRate: Double?, startLatitude: Double?, startLongitude: Double?) {
        self.totalIntervals = totalIntervals
        self.totalDistanceGPS = totalDistanceGPS
        self.totalElapsedTime = totalElapsedTime
        self.avgSplitGPS = avgSplitGPS
        self.avgSpeedGPS = avgSpeedGPS
        self.avgStrokeRate = avgStrokeRate
        self.totalStrokes = totalStrokes
        self.distancePerStrokeGPS = distancePerStrokeGPS
        self.avgHeartRate = avgHeartRate
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
    }
}

/// Per-interval summary statistics.
public struct IntervalSummary: Codable, Sendable {
    public let interval: Int
    public let totalDistanceGPS: Double
    public let totalElapsedTime: TimeInterval
    public let avgSplitGPS: TimeInterval?
    public let avgSpeedGPS: Double
    public let avgStrokeRate: Double
    public let totalStrokes: Int
    public let distancePerStrokeGPS: Double
    public let avgHeartRate: Double?

    public init(interval: Int, totalDistanceGPS: Double, totalElapsedTime: TimeInterval, avgSplitGPS: TimeInterval?, avgSpeedGPS: Double, avgStrokeRate: Double, totalStrokes: Int, distancePerStrokeGPS: Double, avgHeartRate: Double?) {
        self.interval = interval
        self.totalDistanceGPS = totalDistanceGPS
        self.totalElapsedTime = totalElapsedTime
        self.avgSplitGPS = avgSplitGPS
        self.avgSpeedGPS = avgSpeedGPS
        self.avgStrokeRate = avgStrokeRate
        self.totalStrokes = totalStrokes
        self.distancePerStrokeGPS = distancePerStrokeGPS
        self.avgHeartRate = avgHeartRate
    }
}

/// Per-stroke data from NK SpeedCoach.
/// Note: Empower Oarlock fields (force, angle, power, work) are optional
/// and will be nil when oarlock is not connected (values are "---" in CSV).
public struct NKSpeedCoachStroke: Codable, Sendable {
    public let interval: Int
    public let distanceGPS: Double
    public let elapsedTime: TimeInterval
    public let splitGPS: TimeInterval?
    public let speedGPS: Double
    public let strokeRate: Double
    public let totalStrokes: Int
    public let distancePerStrokeGPS: Double
    public let heartRate: Double?
    public let latitude: Double?
    public let longitude: Double?

    // Empower Oarlock metrics (optional, nil when not available)
    public let power: Double?
    public let catchAngle: Double?
    public let slip: Double?
    public let finishAngle: Double?
    public let wash: Double?
    public let forceAvg: Double?
    public let work: Double?
    public let forceMax: Double?
    public let maxForceAngle: Double?

    public init(interval: Int, distanceGPS: Double, elapsedTime: TimeInterval, splitGPS: TimeInterval?, speedGPS: Double, strokeRate: Double, totalStrokes: Int, distancePerStrokeGPS: Double, heartRate: Double?, latitude: Double?, longitude: Double?, power: Double?, catchAngle: Double?, slip: Double?, finishAngle: Double?, wash: Double?, forceAvg: Double?, work: Double?, forceMax: Double?, maxForceAngle: Double?) {
        self.interval = interval
        self.distanceGPS = distanceGPS
        self.elapsedTime = elapsedTime
        self.splitGPS = splitGPS
        self.speedGPS = speedGPS
        self.strokeRate = strokeRate
        self.totalStrokes = totalStrokes
        self.distancePerStrokeGPS = distancePerStrokeGPS
        self.heartRate = heartRate
        self.latitude = latitude
        self.longitude = longitude
        self.power = power
        self.catchAngle = catchAngle
        self.slip = slip
        self.finishAngle = finishAngle
        self.wash = wash
        self.forceAvg = forceAvg
        self.work = work
        self.forceMax = forceMax
        self.maxForceAngle = maxForceAngle
    }
}

/// Errors occurring during NK SpeedCoach profile parsing.
public enum NKSpeedCoachParseError: Error, Equatable {
    case invalidFormat(String)
    case missingSection(String)
    case invalidData(String)
    case fileNotFound
}

/// Main parser entry point for NK SpeedCoach CSV files.
public struct NKSpeedCoachParser {

    /// Parses an NK SpeedCoach CSV file.
    /// - Parameter csvString: The raw CSV contents exported from NK LiNK Logbook.
    /// - Returns: A parsed session containing all metadata and per-stroke data.
    /// - Throws: `NKSpeedCoachParseError` when parsing fails.
    public static func parse(_ csvString: String) throws -> NKSpeedCoachSession {
        let lines = csvString.components(separatedBy: .newlines)

        // Parse sections
        let sessionInfo = try parseSessionInfo(from: lines)
        let deviceInfo = try parseDeviceInfo(from: lines)
        let summary = try parseSessionSummary(from: lines)
        let intervals = try parseIntervalSummaries(from: lines)
        let strokes = try parsePerNKSpeedCoachStroke(from: lines)

        return NKSpeedCoachSession(
            sessionInfo: sessionInfo,
            deviceInfo: deviceInfo,
            summary: summary,
            intervals: intervals,
            strokes: strokes
        )
    }

    // MARK: - Private Parsing Methods

    private static func parseSessionInfo(from lines: [String]) throws -> SessionInfo {
        // Find session info section (lines 0-6)
        guard lines.count > 6 else {
            throw NKSpeedCoachParseError.missingSection("Session Information")
        }

        let nameComponents = lines[2].components(separatedBy: ",")
        let startTimeComponents = lines[3].components(separatedBy: ",")
        let typeComponents = lines[4].components(separatedBy: ",")
        let unitsComponents = lines[5].components(separatedBy: ",")
        let speedComponents = lines[6].components(separatedBy: ",")

        let name = nameComponents.count > 1 ? nameComponents[1] : ""
        let type = typeComponents.count > 1 ? typeComponents[1] : ""
        let units = unitsComponents.count > 1 ? unitsComponents[1] : ""
        let speedInput = speedComponents.count > 1 ? speedComponents[1] : ""

        // Parse start time (format: "02/28/2026 15:21:00")
        let startTime: Date?
        if startTimeComponents.count > 1 {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MM/dd/yyyy HH:mm:ss"
            startTime = dateFormatter.date(from: startTimeComponents[1])
        } else {
            startTime = nil
        }

        return SessionInfo(
            name: name,
            startTime: startTime,
            type: type,
            systemOfUnits: units,
            speedInput: speedInput
        )
    }

    private static func parseDeviceInfo(from lines: [String]) throws -> DeviceInfo {
        guard lines.count > 8 else {
            throw NKSpeedCoachParseError.missingSection("Device Information")
        }

        let nameComponents = lines[2].components(separatedBy: ",")
        let modelComponents = lines[3].components(separatedBy: ",")
        let serialComponents = lines[4].components(separatedBy: ",")
        let firmwareComponents = lines[5].components(separatedBy: ",")
        let profileComponents = lines[6].components(separatedBy: ",")
        let hardwareComponents = lines[7].components(separatedBy: ",")
        let linkComponents = lines[8].components(separatedBy: ",")

        return DeviceInfo(
            name: nameComponents.count > 5 ? nameComponents[5] : "",
            model: modelComponents.count > 5 ? modelComponents[5] : "",
            serial: serialComponents.count > 5 ? serialComponents[5] : "",
            firmwareVersion: firmwareComponents.count > 5 ? firmwareComponents[5] : "",
            profileVersion: profileComponents.count > 5 ? profileComponents[5] : "",
            hardwareVersion: hardwareComponents.count > 5 ? hardwareComponents[5] : "",
            linkVersion: linkComponents.count > 5 ? linkComponents[5] : ""
        )
    }

    private static func parseSessionSummary(from lines: [String]) throws -> SessionSummary {
        // Find "Session Summary:" section
        guard let summaryIndex = lines.firstIndex(where: { $0.hasPrefix("Session Summary:") }),
              summaryIndex + 4 < lines.count else {
            throw NKSpeedCoachParseError.missingSection("Session Summary")
        }

        let dataLine = lines[summaryIndex + 4]  // +1 empty, +2 header, +3 units, +4 data
        let components = dataLine.components(separatedBy: ",")

        guard components.count >= 24 else {
            throw NKSpeedCoachParseError.invalidData("Session summary has insufficient columns")
        }

        return SessionSummary(
            totalIntervals: Int(components[0]) ?? 0,
            totalDistanceGPS: Double(components[1]) ?? 0.0,
            totalElapsedTime: parseTimeInterval(components[3]),
            avgSplitGPS: parseSplit(components[4]),
            avgSpeedGPS: Double(components[5]) ?? 0.0,
            avgStrokeRate: Double(components[8]) ?? 0.0,
            totalStrokes: Int(components[9]) ?? 0,
            distancePerStrokeGPS: Double(components[10]) ?? 0.0,
            avgHeartRate: parseOptionalDouble(components[12]),
            startLatitude: parseOptionalDouble(components[22]),
            startLongitude: parseOptionalDouble(components[23])
        )
    }

    private static func parseIntervalSummaries(from lines: [String]) throws -> [IntervalSummary] {
        guard let intervalIndex = lines.firstIndex(where: { $0.hasPrefix("Interval Summaries:") }),
              intervalIndex + 4 < lines.count else {
            return []
        }

        var intervals: [IntervalSummary] = []
        var lineIndex = intervalIndex + 4  // +1 empty, +2 header, +3 units, +4 data

        while lineIndex < lines.count && !lines[lineIndex].isEmpty {
            let components = lines[lineIndex].components(separatedBy: ",")
            guard components.count >= 24 else { break }

            let interval = IntervalSummary(
                interval: Int(components[0]) ?? 0,
                totalDistanceGPS: Double(components[1]) ?? 0.0,
                totalElapsedTime: parseTimeInterval(components[3]),
                avgSplitGPS: parseSplit(components[4]),
                avgSpeedGPS: Double(components[5]) ?? 0.0,
                avgStrokeRate: Double(components[8]) ?? 0.0,
                totalStrokes: Int(components[9]) ?? 0,
                distancePerStrokeGPS: Double(components[10]) ?? 0.0,
                avgHeartRate: parseOptionalDouble(components[12])
            )
            intervals.append(interval)
            lineIndex += 1
        }

        return intervals
    }

    private static func parsePerNKSpeedCoachStroke(from lines: [String]) throws -> [NKSpeedCoachStroke] {
        guard let strokeIndex = lines.firstIndex(where: { $0.hasPrefix("Per-Stroke Data:") }),
              strokeIndex + 4 < lines.count else {
            throw NKSpeedCoachParseError.missingSection("Per-Stroke Data")
        }

        var strokes: [NKSpeedCoachStroke] = []
        var lineIndex = strokeIndex + 4  // +1 empty, +2 header, +3 units, +4 data

        while lineIndex < lines.count && !lines[lineIndex].isEmpty {
            let components = lines[lineIndex].components(separatedBy: ",")
            guard components.count >= 24 else { break }

            let stroke = NKSpeedCoachStroke(
                interval: Int(components[0]) ?? 0,
                distanceGPS: Double(components[1]) ?? 0.0,
                elapsedTime: parseTimeInterval(components[3]),
                splitGPS: parseSplit(components[4]),
                speedGPS: Double(components[5]) ?? 0.0,
                strokeRate: Double(components[8]) ?? 0.0,
                totalStrokes: Int(components[9]) ?? 0,
                distancePerStrokeGPS: Double(components[10]) ?? 0.0,
                heartRate: parseOptionalDouble(components[12]),
                latitude: parseOptionalDouble(components[22]),
                longitude: parseOptionalDouble(components[23]),
                power: parseOptionalDouble(components[13]),
                catchAngle: parseOptionalDouble(components[14]),
                slip: parseOptionalDouble(components[15]),
                finishAngle: parseOptionalDouble(components[16]),
                wash: parseOptionalDouble(components[17]),
                forceAvg: parseOptionalDouble(components[18]),
                work: parseOptionalDouble(components[19]),
                forceMax: parseOptionalDouble(components[20]),
                maxForceAngle: parseOptionalDouble(components[21])
            )
            strokes.append(stroke)
            lineIndex += 1
        }

        return strokes
    }

    // MARK: - Helper Methods

    /// Parses time in format "HH:MM:SS.tenths" to TimeInterval (seconds).
    private static func parseTimeInterval(_ string: String) -> TimeInterval {
        let components = string.components(separatedBy: ":")
        guard components.count == 3 else { return 0.0 }

        let hours = Double(components[0]) ?? 0.0
        let minutes = Double(components[1]) ?? 0.0
        let seconds = Double(components[2]) ?? 0.0

        return hours * 3600 + minutes * 60 + seconds
    }

    /// Parses split time in format "MM:SS.tenths" to TimeInterval (seconds per 500m).
    private static func parseSplit(_ string: String) -> TimeInterval? {
        let components = string.components(separatedBy: ":")
        guard components.count == 2 else { return nil }

        let minutes = Double(components[0]) ?? 0.0
        let seconds = Double(components[1]) ?? 0.0

        return minutes * 60 + seconds
    }

    /// Parses optional double, returns nil if value is "---", "0.00", or invalid.
    private static func parseOptionalDouble(_ string: String) -> Double? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        if trimmed == "---" || trimmed.isEmpty {
            return nil
        }
        return Double(trimmed)
    }
}
