// Rendering/ViewportCullTests.swift v1.0.0
/**
 * Tests for ViewportCull time-range filtering stage.
 * --- Revision History ---
 * v1.0.0 - 2026-03-07 - Initial implementation (Phase 4: Rendering + MVP).
 */

import Foundation
import Testing
@testable import RowDataStudio

@Suite("ViewportCull")
struct ViewportCullTests {

    // MARK: - Basic Filtering

    @Test("Passes only samples within range")
    func filtersToRange() {
        let ts: ContiguousArray<Double> = [0, 100, 200, 300, 400, 500]
        let vals: ContiguousArray<Float> = [1, 2, 3, 4, 5, 6]
        let cull = ViewportCull(startMs: 100, endMs: 400)

        let (outTs, outVals) = cull.apply(timestamps: ts, values: vals)

        #expect(outTs.allSatisfy { $0 >= 100 && $0 <= 400 })
        #expect(outVals.count == outTs.count)
        #expect(outTs.contains(100))
        #expect(outTs.contains(400))
        #expect(!outTs.contains(500))
    }

    @Test("Empty input returns empty output")
    func emptyInput() {
        let cull = ViewportCull(startMs: 0, endMs: 1000)
        let (outTs, outVals) = cull.apply(
            timestamps: ContiguousArray<Double>(),
            values: ContiguousArray<Float>()
        )
        #expect(outTs.isEmpty)
        #expect(outVals.isEmpty)
    }

    @Test("Range larger than data passes everything")
    func rangeCoversAll() {
        let ts: ContiguousArray<Double> = [100, 200, 300]
        let vals: ContiguousArray<Float> = [1, 2, 3]
        let cull = ViewportCull(startMs: 0, endMs: 10_000)

        let (outTs, outVals) = cull.apply(timestamps: ts, values: vals)
        #expect(outTs.count == 3)
        #expect(outVals.count == 3)
    }

    @Test("Range entirely before data returns empty")
    func rangeBeforeData() {
        let ts: ContiguousArray<Double> = [5000, 6000, 7000]
        let vals: ContiguousArray<Float> = [1, 2, 3]
        let cull = ViewportCull(startMs: 0, endMs: 1000)

        let (outTs, outVals) = cull.apply(timestamps: ts, values: vals)
        #expect(outTs.isEmpty)
        #expect(outVals.isEmpty)
    }

    @Test("Range entirely after data returns empty")
    func rangeAfterData() {
        let ts: ContiguousArray<Double> = [0, 100, 200]
        let vals: ContiguousArray<Float> = [1, 2, 3]
        let cull = ViewportCull(startMs: 5000, endMs: 10_000)

        let (outTs, outVals) = cull.apply(timestamps: ts, values: vals)
        #expect(outTs.isEmpty)
        #expect(outVals.isEmpty)
    }

    // MARK: - Boundary Inclusion

    @Test("Output timestamps and values arrays are same length")
    func parallelArrays() {
        let ts: ContiguousArray<Double> = [0, 50, 100, 150, 200, 250, 300]
        let vals: ContiguousArray<Float> = [10, 20, 30, 40, 50, 60, 70]
        let cull = ViewportCull(startMs: 75, endMs: 225)

        let (outTs, outVals) = cull.apply(timestamps: ts, values: vals)
        #expect(outTs.count == outVals.count)
    }

    @Test("Single-point range returns that point")
    func singlePointRange() {
        let ts: ContiguousArray<Double> = [100, 200, 300]
        let vals: ContiguousArray<Float> = [1, 2, 3]
        let cull = ViewportCull(startMs: 200, endMs: 200)

        let (outTs, outVals) = cull.apply(timestamps: ts, values: vals)
        #expect(outTs.count >= 1)
        #expect(outTs.contains(200))
        _ = outVals
    }
}
