//
// StrokeEventTests.swift
// RowData Studio Tests
//
// Tests for StrokeEvent: computed properties, validation, Codable.
//
// Version: 1.0.0 (2026-03-01)
// Revision History:
//   2026-03-01: Initial implementation (Phase 1: Data Models)
//

import Testing
import Foundation
@testable import RowDataStudio

@Suite("StrokeEvent Tests")
struct StrokeEventTests {

    @Test("StrokeEvent duration computation")
    func durationComputation() throws {
        let stroke = StrokeEvent(
            index: 0,
            startTime: 10.0,
            endTime: 12.5,
            startIndex: 2000,
            endIndex: 2500,
            peakVelocity: 3.2,
            minVelocity: 1.8,
            isValid: true
        )

        #expect(stroke.duration == 2.5)
    }

    @Test("StrokeEvent stroke rate computation")
    func strokeRateComputation() throws {
        let stroke = StrokeEvent(
            index: 0,
            startTime: 0.0,
            endTime: 2.0,  // 2 second stroke
            startIndex: 0,
            endIndex: 400
        )

        // 60 / 2.0 = 30 spm
        #expect(stroke.strokeRate == 30.0)
    }

    @Test("StrokeEvent stroke rate edge case (zero duration)")
    func strokeRateZeroDuration() throws {
        let stroke = StrokeEvent(
            index: 0,
            startTime: 10.0,
            endTime: 10.0,  // Invalid: same start/end
            startIndex: 2000,
            endIndex: 2000
        )

        #expect(stroke.strokeRate == 0.0)
    }

    @Test("StrokeEvent typical rowing stroke (25 spm)")
    func typicalRowingStroke() throws {
        // Typical rowing: 25 spm = 2.4 seconds per stroke
        let stroke = StrokeEvent(
            index: 5,
            startTime: 12.0,
            endTime: 14.4,
            startIndex: 2400,
            endIndex: 2880,
            peakVelocity: 3.5,
            minVelocity: 1.2,
            isValid: true
        )

        #expect(stroke.duration == 2.4)
        #expect(stroke.strokeRate == 25.0)
        #expect(stroke.isValid == true)
    }

    @Test("StrokeEvent Codable roundtrip")
    func codableRoundtrip() throws {
        let stroke = StrokeEvent(
            index: 10,
            startTime: 25.5,
            endTime: 27.8,
            startIndex: 5100,
            endIndex: 5560,
            peakVelocity: 4.2,
            minVelocity: 1.5,
            isValid: true
        )

        // Encode
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(stroke)

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(StrokeEvent.self, from: jsonData)

        // Verify
        #expect(decoded == stroke)
        #expect(decoded.index == 10)
        #expect(decoded.startTime == 25.5)
        #expect(decoded.endTime == 27.8)
        #expect(decoded.peakVelocity == 4.2)
        #expect(decoded.duration == 2.3)
    }

    @Test("StrokeEvent partial stroke (invalid)")
    func partialStroke() throws {
        let stroke = StrokeEvent(
            index: 0,
            startTime: 0.0,
            endTime: 1.2,
            startIndex: 0,
            endIndex: 240,
            isValid: false  // Partial stroke at session start
        )

        #expect(stroke.isValid == false)
        #expect(stroke.duration == 1.2)
    }

    @Test("StrokeEvent array sorting")
    func arraySorting() throws {
        let strokes = [
            StrokeEvent(index: 2, startTime: 4.0, endTime: 6.0, startIndex: 800, endIndex: 1200),
            StrokeEvent(index: 0, startTime: 0.0, endTime: 2.0, startIndex: 0, endIndex: 400),
            StrokeEvent(index: 1, startTime: 2.0, endTime: 4.0, startIndex: 400, endIndex: 800)
        ]

        let sorted = strokes.sorted { $0.index < $1.index }
        #expect(sorted[0].index == 0)
        #expect(sorted[1].index == 1)
        #expect(sorted[2].index == 2)
    }
}
