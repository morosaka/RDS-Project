// SignalProcessing/LTTBTests.swift v1.0.0
/**
 * Tests for LTTB downsampling algorithm.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Foundation
import Testing
@testable import RowDataStudio

@Suite("DSP LTTB Downsampling")
struct LTTBTests {

    @Test("LTTB preserves first and last endpoints")
    func preservesEndpoints() {
        let ts = ContiguousArray<Double>((0..<100).map { Double($0) })
        var vals = ContiguousArray<Float>(repeating: 0, count: 100)
        for i in 0..<100 { vals[i] = Float(i) }

        let indices = DSP.lttbDownsample(timestamps: ts, values: vals, targetCount: 10)
        #expect(indices.first == 0, "First index must be 0")
        #expect(indices.last == 99, "Last index must be n-1")
    }

    @Test("LTTB returns correct number of points")
    func correctCount() {
        let ts = ContiguousArray<Double>((0..<1000).map { Double($0) })
        let vals = ContiguousArray<Float>((0..<1000).map { Float(sin(Double($0) * 0.01)) })

        let indices = DSP.lttbDownsample(timestamps: ts, values: vals, targetCount: 50)
        #expect(indices.count == 50)
    }

    @Test("LTTB returns all indices when target >= input length")
    func targetLargerThanInput() {
        let ts: ContiguousArray<Double> = [0, 1, 2, 3, 4]
        let vals: ContiguousArray<Float> = [0, 1, 2, 3, 4]

        let indices = DSP.lttbDownsample(timestamps: ts, values: vals, targetCount: 10)
        #expect(indices.count == 5)
        #expect(indices == [0, 1, 2, 3, 4])
    }

    @Test("LTTB with targetCount 2 returns only endpoints")
    func targetTwoEndpoints() {
        let ts = ContiguousArray<Double>((0..<50).map { Double($0) })
        let vals = ContiguousArray<Float>((0..<50).map { Float($0) })

        let indices = DSP.lttbDownsample(timestamps: ts, values: vals, targetCount: 2)
        #expect(indices.count == 2)
        #expect(indices == [0, 49])
    }

    @Test("LTTB captures peak in spike signal")
    func capturesSpike() {
        // Flat signal with a sharp spike at index 50
        let n = 100
        let ts = ContiguousArray<Double>((0..<n).map { Double($0) })
        var vals = ContiguousArray<Float>(repeating: 0, count: n)
        vals[50] = 100.0

        let indices = DSP.lttbDownsample(timestamps: ts, values: vals, targetCount: 10)
        // The spike should be selected
        #expect(indices.contains(50),
                "LTTB should select the spike at index 50, got indices: \(indices)")
    }

    @Test("LTTB indices are strictly ascending")
    func indicesAscending() {
        let ts = ContiguousArray<Double>((0..<500).map { Double($0) })
        let vals = ContiguousArray<Float>((0..<500).map { Float(sin(Double($0) * 0.05)) })

        let indices = DSP.lttbDownsample(timestamps: ts, values: vals, targetCount: 30)
        for i in 1..<indices.count {
            #expect(indices[i] > indices[i - 1],
                    "Indices must be strictly ascending at position \(i)")
        }
    }

    @Test("LTTB with empty input returns empty")
    func emptyInput() {
        let ts: ContiguousArray<Double> = []
        let vals: ContiguousArray<Float> = []
        let indices = DSP.lttbDownsample(timestamps: ts, values: vals, targetCount: 10)
        #expect(indices.isEmpty)
    }
}
