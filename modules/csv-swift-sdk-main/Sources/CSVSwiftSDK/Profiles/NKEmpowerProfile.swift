// Sources/CSVSwiftSDK/Profiles/NKEmpowerProfile.swift v1.0.0
/**
 * NK Empower Oarlock CSV Profile Parser
 * --- Revision History ---
 * v1.0.0 - 2026-03-01 - Initial implementation.
 */

import Foundation

/// A parsed session containing NK Empower stroke data.
public struct NKEmpowerSession: Codable, Sendable {
    public let strokes: [StrokeData]
    
    public init(strokes: [StrokeData]) {
        self.strokes = strokes
    }
}

/// A single standardized stroke from the NK Empower logbook.
public struct StrokeData: Codable, Sendable {
    public let strokeNumber: Int
    public let elapsedTime: TimeInterval
    public let distance: Double
    public let split: TimeInterval
    public let strokeRate: Double

    // Empower metrics (13 total)
    public let catchAngle: Double
    public let finishAngle: Double
    public let slip: Double
    public let wash: Double
    public let maxForce: Double
    public let avgForce: Double
    public let maxForceAngle: Double
    public let peakPower: Double
    public let avgPower: Double
    public let work: Double
    public let strokeLength: Double
    public let effectiveLength: Double
    
    public init(strokeNumber: Int, elapsedTime: TimeInterval, distance: Double, split: TimeInterval, strokeRate: Double, catchAngle: Double, finishAngle: Double, slip: Double, wash: Double, maxForce: Double, avgForce: Double, maxForceAngle: Double, peakPower: Double, avgPower: Double, work: Double, strokeLength: Double, effectiveLength: Double) {
        self.strokeNumber = strokeNumber
        self.elapsedTime = elapsedTime
        self.distance = distance
        self.split = split
        self.strokeRate = strokeRate
        self.catchAngle = catchAngle
        self.finishAngle = finishAngle
        self.slip = slip
        self.wash = wash
        self.maxForce = maxForce
        self.avgForce = avgForce
        self.maxForceAngle = maxForceAngle
        self.peakPower = peakPower
        self.avgPower = avgPower
        self.work = work
        self.strokeLength = strokeLength
        self.effectiveLength = effectiveLength
    }
}

/// Errors occurring during NK Empower profile parsing.
public enum NKParserError: Error, Equatable {
    case missingEmpowerColumns
    case invalidDataFormat
    case fileNotFound
    case parsingError(String)
}

/// Main parser entry point for NK Empower CSV files.
public struct NKEmpowerParser {
    
    /// Parses an NK Empower CSV string.
    /// - Parameter csvString: The raw CSV contents.
    /// - Returns: A parsed session containing stroke data.
    public static func parse(_ csvString: String) throws -> NKEmpowerSession {
        // Implementation will reside here, leveraging generic CSVParser.
        // For standardization MVP, this provides the public interface wrapper.
        // It will be expanded during full implementation.
        throw NKParserError.parsingError("Parser implementation pending")
    }
}
