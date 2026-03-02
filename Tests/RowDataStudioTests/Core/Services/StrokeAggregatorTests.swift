// Core/Services/StrokeAggregatorTests.swift v1.0.0
/**
 * Tests for per-stroke metric aggregation.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Foundation
import Testing
@testable import RowDataStudio

@Suite("StrokeAggregator")
struct StrokeAggregatorTests {

    /// Creates a simple SensorDataBuffers with known values for testing.
    private static func testBuffers(size: Int) -> SensorDataBuffers {
        let buffers = SensorDataBuffers(size: size)
        for i in 0..<size {
            buffers.timestamp[i] = Double(i) * 5.0  // 200 Hz → 5ms interval
            buffers.fus_cal_ts_vel_inertial[i] = 4.0 + Float(i % 10) * 0.1  // 4.0–4.9
            buffers.imu_flt_ts_acc_surge[i] = Float(sin(Double(i) * 0.1))
            buffers.fus_cal_ts_pitch[i] = 2.0
            buffers.fus_cal_ts_roll[i] = -1.5
            buffers.phys_ext_ts_hr[i] = 160.0
        }
        return buffers
    }

    @Test("Aggregates stroke with valid data")
    func aggregatesValidStroke() {
        let buffers = Self.testBuffers(size: 1000)
        let stroke = StrokeEvent(
            index: 0,
            startTime: 0.5,   // 500ms
            endTime: 2.5,     // 2500ms
            startIndex: 100,
            endIndex: 500
        )

        let stats = StrokeAggregator.aggregate(strokes: [stroke], buffers: buffers)

        #expect(stats.count == 1)
        let s = stats[0]
        #expect(s.strokeIndex == 0)
        #expect(s.duration == 2.0)
        #expect(abs(s.strokeRate - 30.0) < 0.1, "Expected ~30 SPM")
        #expect(s.avgVelocity != nil)
        #expect(s.peakVelocity != nil)
        #expect(s.avgHR != nil)
        #expect(abs(s.avgHR! - 160.0) < 0.1)
        #expect(abs(s.avgPitch! - 2.0) < 0.1)
        #expect(abs(s.avgRoll! - (-1.5)) < 0.1)
    }

    @Test("Handles empty strokes list")
    func emptyStrokes() {
        let buffers = Self.testBuffers(size: 100)
        let stats = StrokeAggregator.aggregate(strokes: [], buffers: buffers)
        #expect(stats.isEmpty)
    }

    @Test("Handles NaN channels gracefully")
    func nanChannels() {
        let buffers = SensorDataBuffers(size: 200)
        for i in 0..<200 {
            buffers.timestamp[i] = Double(i) * 5.0
            buffers.fus_cal_ts_vel_inertial[i] = 4.0
        }
        // HR left as NaN

        let stroke = StrokeEvent(
            index: 0, startTime: 0, endTime: 1.0,
            startIndex: 0, endIndex: 199
        )

        let stats = StrokeAggregator.aggregate(strokes: [stroke], buffers: buffers)
        #expect(stats.count == 1)
        #expect(stats[0].avgHR == nil, "NaN HR should produce nil")
    }

    @Test("Multiple strokes are aggregated independently")
    func multipleStrokes() {
        let buffers = Self.testBuffers(size: 2000)
        let strokes = [
            StrokeEvent(index: 0, startTime: 0, endTime: 2.0, startIndex: 0, endIndex: 399),
            StrokeEvent(index: 1, startTime: 2.0, endTime: 4.0, startIndex: 400, endIndex: 799),
            StrokeEvent(index: 2, startTime: 4.0, endTime: 6.0, startIndex: 800, endIndex: 1199),
        ]

        let stats = StrokeAggregator.aggregate(strokes: strokes, buffers: buffers)
        #expect(stats.count == 3)
        #expect(stats[0].strokeIndex == 0)
        #expect(stats[1].strokeIndex == 1)
        #expect(stats[2].strokeIndex == 2)
    }
}
