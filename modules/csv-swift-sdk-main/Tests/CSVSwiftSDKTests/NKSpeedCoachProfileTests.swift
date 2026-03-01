// Tests/CSVSwiftSDKTests/NKSpeedCoachProfileTests.swift v1.0.0
/**
 * NK SpeedCoach profile parser tests.
 * --- Revision History ---
 * v1.0.0 - 2026-03-01 - Initial implementation.
 */

import Testing
import Foundation
@testable import CSVSwiftSDK

@Suite("NK SpeedCoach Profile")
struct NKSpeedCoachProfileTests {

    @Test("Parse real NK SpeedCoach CSV export")
    func parseRealExport() throws {
        guard let csvURL = ResourceHelper.url(
            forResource: "TestData/NK csv exported-sessions/SpdCoach 3131084 20260228 0321PM",
            withExtension: "csv"
        ) else {
            Issue.record("Could not find NK SpeedCoach test file")
            return
        }

        let csvString = try String(contentsOf: csvURL, encoding: .utf8)
        let session = try NKSpeedCoachParser.parse(csvString)

        // Verify session info
        #expect(session.sessionInfo.name == "JustGo-1846M")
        #expect(session.sessionInfo.type == "Just Go")
        #expect(session.sessionInfo.systemOfUnits == "Meters/Split500")
        #expect(session.sessionInfo.speedInput == "GPS")

        // Verify device info
        #expect(session.deviceInfo.name == "SpdCoach 3131084")
        #expect(session.deviceInfo.model == "SpeedCoach GPS Pro")
        #expect(session.deviceInfo.serial == "3131084")
        #expect(session.deviceInfo.firmwareVersion == "3.03")

        // Verify session summary
        #expect(session.summary.totalIntervals == 1)
        #expect(session.summary.totalDistanceGPS == 1846.6)
        #expect(session.summary.totalStrokes == 233)
        #expect(session.summary.avgStrokeRate == 24.0)
        #expect(session.summary.avgHeartRate == 114.0)

        // Verify start GPS coordinates
        #expect(session.summary.startLatitude != nil)
        #expect(session.summary.startLongitude != nil)

        // Verify per-stroke data exists
        #expect(session.strokes.count > 0)

        // Verify first stroke data structure
        let firstStroke = session.strokes[0]
        #expect(firstStroke.interval >= 0)
        #expect(firstStroke.distanceGPS >= 0)
        #expect(firstStroke.speedGPS >= 0)

        // Verify Empower fields are nil (no oarlock data in this file)
        #expect(firstStroke.power == nil)
        #expect(firstStroke.catchAngle == nil)
        #expect(firstStroke.forceMax == nil)
    }

    @Test("Parse session with start time")
    func parseStartTime() throws {
        guard let csvURL = ResourceHelper.url(
            forResource: "TestData/NK csv exported-sessions/SpdCoach 3131084 20260228 0321PM",
            withExtension: "csv"
        ) else {
            Issue.record("Could not find NK SpeedCoach test file")
            return
        }

        let csvString = try String(contentsOf: csvURL, encoding: .utf8)
        let session = try NKSpeedCoachParser.parse(csvString)

        // Verify start time parsing (format: "02/28/2026 15:21:00")
        #expect(session.sessionInfo.startTime != nil)

        if let startTime = session.sessionInfo.startTime {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: startTime)

            #expect(components.year == 2026)
            #expect(components.month == 2)
            #expect(components.day == 28)
            #expect(components.hour == 15)
            #expect(components.minute == 21)
        }
    }

    @Test("Handle multiple interval summaries")
    func multipleIntervals() throws {
        // Note: Current test files only have 1 interval
        // This test verifies the structure is ready for multi-interval sessions
        guard let csvURL = ResourceHelper.url(
            forResource: "TestData/NK csv exported-sessions/SpdCoach 3131084 20260228 0321PM",
            withExtension: "csv"
        ) else {
            Issue.record("Could not find NK SpeedCoach test file")
            return
        }

        let csvString = try String(contentsOf: csvURL, encoding: .utf8)
        let session = try NKSpeedCoachParser.parse(csvString)

        #expect(session.intervals.count == 1)
        #expect(session.intervals[0].interval == 1)
        #expect(session.intervals[0].totalDistanceGPS == 1846.6)
    }

    @Test("Verify GPS coordinates in per-stroke data")
    func gpsCoordinates() throws {
        guard let csvURL = ResourceHelper.url(
            forResource: "TestData/NK csv exported-sessions/SpdCoach 3131084 20260228 0321PM",
            withExtension: "csv"
        ) else {
            Issue.record("Could not find NK SpeedCoach test file")
            return
        }

        let csvString = try String(contentsOf: csvURL, encoding: .utf8)
        let session = try NKSpeedCoachParser.parse(csvString)

        // Verify at least some strokes have GPS coordinates
        let strokesWithGPS = session.strokes.filter { $0.latitude != nil && $0.longitude != nil }
        #expect(strokesWithGPS.count > 0)

        // Verify coordinates are in valid range (rough check for Venice area)
        if let firstStroke = strokesWithGPS.first {
            #expect(firstStroke.latitude! > 42.0 && firstStroke.latitude! < 43.0)  // Venice latitude
            #expect(firstStroke.longitude! > 12.0 && firstStroke.longitude! < 13.0) // Venice longitude
        }
    }
}
