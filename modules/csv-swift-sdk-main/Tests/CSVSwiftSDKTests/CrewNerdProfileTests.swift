// Tests/CSVSwiftSDKTests/CrewNerdProfileTests.swift v1.0.0
/**
 * CrewNerd profile parser tests.
 * --- Revision History ---
 * v1.0.0 - 2026-03-01 - Initial implementation.
 */

import Testing
import Foundation
@testable import CSVSwiftSDK

@Suite("CrewNerd Profile")
struct CrewNerdProfileTests {

    @Test("Parse real CrewNerd CSV export")
    func parseRealExport() throws {
        guard let csvURL = ResourceHelper.url(
            forResource: "TestData/CN csv exported-sessions/2026-02-28-1438_Int1",
            withExtension: "csv"
        ) else {
            Issue.record("Could not find CrewNerd test file")
            return
        }

        let csvString = try String(contentsOf: csvURL, encoding: .utf8)
        let session = try CrewNerdParser.parse(csvString)

        // Verify session has telemetry samples
        #expect(session.samples.count > 0)

        // Verify first sample structure
        let firstSample = session.samples[0]
        #expect(firstSample.time.hasPrefix("0:0:"))
        #expect(firstSample.distance >= 0)
        #expect(firstSample.speed >= 0)
        #expect(firstSample.latitude > 0)
        #expect(firstSample.longitude > 0)
    }

    @Test("Verify session statistics")
    func sessionStatistics() throws {
        guard let csvURL = ResourceHelper.url(
            forResource: "TestData/CN csv exported-sessions/2026-02-28-1438_Int1",
            withExtension: "csv"
        ) else {
            Issue.record("Could not find CrewNerd test file")
            return
        }

        let csvString = try String(contentsOf: csvURL, encoding: .utf8)
        let session = try CrewNerdParser.parse(csvString)

        // Verify cumulative statistics make sense
        #expect(session.duration > 0)
        #expect(session.totalDistance > 0)
        #expect(session.totalStrokes >= 0)

        // Last sample should have max values
        guard let lastSample = session.samples.last else {
            Issue.record("Session has no samples")
            return
        }

        #expect(lastSample.distance == session.totalDistance)
        #expect(lastSample.practiceElapsedTime == session.duration)
        #expect(lastSample.strokes == session.totalStrokes)
    }

    @Test("Verify time-series monotonic increase")
    func monotonicIncrease() throws {
        guard let csvURL = ResourceHelper.url(
            forResource: "TestData/CN csv exported-sessions/2026-02-28-1438_Int1",
            withExtension: "csv"
        ) else {
            Issue.record("Could not find CrewNerd test file")
            return
        }

        let csvString = try String(contentsOf: csvURL, encoding: .utf8)
        let session = try CrewNerdParser.parse(csvString)

        // Verify elapsed time increases monotonically
        for i in 1..<session.samples.count {
            #expect(session.samples[i].practiceElapsedTime >= session.samples[i-1].practiceElapsedTime)
        }

        // Verify cumulative distance is non-decreasing
        for i in 1..<session.samples.count {
            #expect(session.samples[i].distance >= session.samples[i-1].distance)
        }

        // Verify cumulative strokes is non-decreasing
        for i in 1..<session.samples.count {
            #expect(session.samples[i].strokes >= session.samples[i-1].strokes)
        }
    }

    @Test("Verify GPS coordinates validity")
    func gpsCoordinatesValidity() throws {
        guard let csvURL = ResourceHelper.url(
            forResource: "TestData/CN csv exported-sessions/2026-02-28-1438_Int1",
            withExtension: "csv"
        ) else {
            Issue.record("Could not find CrewNerd test file")
            return
        }

        let csvString = try String(contentsOf: csvURL, encoding: .utf8)
        let session = try CrewNerdParser.parse(csvString)

        // Verify coordinates are in valid range
        for sample in session.samples {
            #expect(sample.latitude >= -90.0 && sample.latitude <= 90.0)
            #expect(sample.longitude >= -180.0 && sample.longitude <= 180.0)
        }

        // Verify coordinates are in Venice area (where test data was recorded)
        let firstSample = session.samples[0]
        #expect(firstSample.latitude > 42.0 && firstSample.latitude < 43.0)
        #expect(firstSample.longitude > 12.0 && firstSample.longitude < 13.0)
    }

    @Test("Verify heart rate data")
    func heartRateData() throws {
        guard let csvURL = ResourceHelper.url(
            forResource: "TestData/CN csv exported-sessions/2026-02-28-1438_Int1",
            withExtension: "csv"
        ) else {
            Issue.record("Could not find CrewNerd test file")
            return
        }

        let csvString = try String(contentsOf: csvURL, encoding: .utf8)
        let session = try CrewNerdParser.parse(csvString)

        // Verify HR values are in reasonable range (when non-zero)
        let samplesWithHR = session.samples.filter { $0.heartRate > 0 }

        if samplesWithHR.count > 0 {
            for sample in samplesWithHR {
                #expect(sample.heartRate >= 40 && sample.heartRate <= 220)  // Physiologically valid HR range
            }
        }
    }

    @Test("Verify stroke rate metrics")
    func strokeRateMetrics() throws {
        guard let csvURL = ResourceHelper.url(
            forResource: "TestData/CN csv exported-sessions/2026-02-28-1438_Int1",
            withExtension: "csv"
        ) else {
            Issue.record("Could not find CrewNerd test file")
            return
        }

        let csvString = try String(contentsOf: csvURL, encoding: .utf8)
        let session = try CrewNerdParser.parse(csvString)

        // Verify stroke rate values are reasonable (not negative, not absurdly high)
        let samplesWithSR = session.samples.filter { $0.strokeRate > 0 }

        if samplesWithSR.count > 0 {
            // Check max SR is physiologically reasonable (elite rowers max ~50 SPM)
            let maxSR = samplesWithSR.map(\.strokeRate).max() ?? 0
            #expect(maxSR <= 60.0)  // Upper bound for any rowing scenario

            // Most samples with SR > 0 should be in reasonable range (allow outliers for drills/pause)
            let reasonableSamples = samplesWithSR.filter { $0.strokeRate >= 10.0 && $0.strokeRate <= 50.0 }
            let reasonableRatio = Double(reasonableSamples.count) / Double(samplesWithSR.count)
            #expect(reasonableRatio > 0.3)  // At least 30% of non-zero SR should be in normal range
        }
    }

    @Test("Parse all three interval files")
    func parseAllIntervals() throws {
        let intervals = ["Int1", "Int2", "Int3"]

        for interval in intervals {
            guard let csvURL = ResourceHelper.url(
                forResource: "TestData/CN csv exported-sessions/2026-02-28-1438_\(interval)",
                withExtension: "csv"
            ) else {
                Issue.record("Could not find CrewNerd test file for \(interval)")
                continue
            }

            let csvString = try String(contentsOf: csvURL, encoding: .utf8)
            let session = try CrewNerdParser.parse(csvString)

            // Verify each interval has valid data
            #expect(session.samples.count > 0)
            #expect(session.duration > 0)
            #expect(session.totalDistance > 0)
        }
    }
}
