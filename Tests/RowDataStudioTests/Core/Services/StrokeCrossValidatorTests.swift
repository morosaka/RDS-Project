// Core/Services/StrokeCrossValidatorTests.swift v1.0.0
/**
 * Tests for NK Empower stroke cross-validation.
 * --- Revision History ---
 * v1.0.0 - 2026-03-03 - Initial implementation.
 */

import Foundation
import Testing
import CSVSwiftSDK
@testable import RowDataStudio

@Suite("StrokeCrossValidator")
struct StrokeCrossValidatorTests {

    // MARK: - Helpers

    /// Creates a synthetic StrokeEvent array.
    private static func makeStrokes(
        count: Int,
        startTime: Double = 10.0,
        strokeRateSPM: Double = 28.0
    ) -> [StrokeEvent] {
        let period = 60.0 / strokeRateSPM
        return (0..<count).map { i in
            let start = startTime + Double(i) * period
            return StrokeEvent(
                index: i,
                startTime: start,
                endTime: start + period,
                startIndex: i * 400,
                endIndex: (i + 1) * 400,
                isValid: true
            )
        }
    }

    /// Creates a synthetic NKEmpowerSession with matching stroke count and rate.
    private static func makeEmpowerSession(
        count: Int,
        startTime: Double = 10.0,
        strokeRateSPM: Double = 28.0
    ) -> NKEmpowerSession {
        let period = 60.0 / strokeRateSPM
        let strokes = (0..<count).map { i in
            NKEmpowerStroke(
                strokeNumber: i + 1,
                elapsedTime: startTime + Double(i) * period,
                distance: Double(i) * 10.0,
                split: 120.0,
                strokeRate: strokeRateSPM,
                catchAngle: -55.0,
                finishAngle: 35.0,
                slip: 2.0,
                wash: 3.0,
                maxForce: 450.0,
                avgForce: 280.0,
                maxForceAngle: -10.0,
                peakPower: 600.0,
                avgPower: 350.0,
                work: 750.0,
                strokeLength: 90.0,
                effectiveLength: 85.0
            )
        }
        return NKEmpowerSession(strokes: strokes)
    }

    // MARK: - Count Match

    @Test("Matching stroke counts report countMatch = true")
    func matchingCounts() {
        let detected = Self.makeStrokes(count: 50, strokeRateSPM: 28)
        let empower = Self.makeEmpowerSession(count: 50, strokeRateSPM: 28)

        let result = StrokeCrossValidator.validate(
            detectedStrokes: detected,
            empowerSession: empower
        )

        #expect(result.countMatch)
        #expect(result.detectedCount == 50)
        #expect(result.referenceCount == 50)
        #expect(result.warnings.isEmpty)
    }

    @Test("Mismatched stroke counts report countMatch = false")
    func mismatchedCounts() {
        let detected = Self.makeStrokes(count: 50, strokeRateSPM: 28)
        let empower = Self.makeEmpowerSession(count: 35, strokeRateSPM: 28)

        let result = StrokeCrossValidator.validate(
            detectedStrokes: detected,
            empowerSession: empower
        )

        #expect(!result.countMatch)
        #expect(result.warnings.contains(where: { $0.contains("count mismatch") }))
    }

    @Test("Small count difference within 10% tolerance is accepted")
    func smallCountDifferenceAccepted() {
        let detected = Self.makeStrokes(count: 48, strokeRateSPM: 28)
        let empower = Self.makeEmpowerSession(count: 50, strokeRateSPM: 28)

        let result = StrokeCrossValidator.validate(
            detectedStrokes: detected,
            empowerSession: empower
        )

        #expect(result.countMatch, "2/50 difference should be within 10% tolerance")
    }

    // MARK: - Rate Agreement

    @Test("Matching rates produce high agreement")
    func matchingRates() {
        let detected = Self.makeStrokes(count: 30, strokeRateSPM: 28)
        let empower = Self.makeEmpowerSession(count: 30, strokeRateSPM: 28)

        let result = StrokeCrossValidator.validate(
            detectedStrokes: detected,
            empowerSession: empower
        )

        if let agreement = result.rateAgreement {
            #expect(agreement > 0.8, "Matching rates should have high agreement, got \(agreement)")
        }
        if let avgDiff = result.avgRateDifferenceSPM {
            #expect(avgDiff < 2.0, "Matching rates should have low avg difference, got \(avgDiff)")
        }
    }

    @Test("Mismatched rates produce low agreement and warning")
    func mismatchedRates() {
        // Detected at 28 SPM, Empower at 34 SPM
        let detected = Self.makeStrokes(count: 30, strokeRateSPM: 28)
        let empower = Self.makeEmpowerSession(count: 30, strokeRateSPM: 34)

        let result = StrokeCrossValidator.validate(
            detectedStrokes: detected,
            empowerSession: empower
        )

        if let agreement = result.rateAgreement {
            #expect(agreement < 0.5, "Different rates should have low agreement, got \(agreement)")
        }
    }

    // MARK: - Edge Cases

    @Test("Empty detected strokes returns clean result")
    func emptyDetected() {
        let empower = Self.makeEmpowerSession(count: 50, strokeRateSPM: 28)

        let result = StrokeCrossValidator.validate(
            detectedStrokes: [],
            empowerSession: empower
        )

        #expect(result.detectedCount == 0)
        #expect(result.referenceCount == 50)
        #expect(!result.countMatch)
        #expect(result.avgRateDifferenceSPM == nil)
        #expect(result.rateAgreement == nil)
    }

    @Test("Empty empower session returns clean result")
    func emptyEmpower() {
        let detected = Self.makeStrokes(count: 50, strokeRateSPM: 28)
        let empower = NKEmpowerSession(strokes: [])

        let result = StrokeCrossValidator.validate(
            detectedStrokes: detected,
            empowerSession: empower
        )

        #expect(result.referenceCount == 0)
        #expect(result.avgRateDifferenceSPM == nil)
    }

    @Test("ValidationResult is Codable")
    func validationResultCodable() throws {
        let detected = Self.makeStrokes(count: 20, strokeRateSPM: 28)
        let empower = Self.makeEmpowerSession(count: 20, strokeRateSPM: 28)

        let result = StrokeCrossValidator.validate(
            detectedStrokes: detected,
            empowerSession: empower
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(result)
        let decoded = try JSONDecoder().decode(
            StrokeCrossValidator.ValidationResult.self, from: data
        )

        #expect(decoded.detectedCount == result.detectedCount)
        #expect(decoded.referenceCount == result.referenceCount)
        #expect(decoded.countMatch == result.countMatch)
    }
}
