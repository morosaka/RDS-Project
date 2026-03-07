// Rendering/LTTBTransformTests.swift v1.0.0
/**
 * Tests for LTTBTransform stage.
 * --- Revision History ---
 * v1.0.0 - 2026-03-07 - Initial implementation (Phase 4: Rendering + MVP).
 */

import Foundation
import Testing
@testable import RowDataStudio

@Suite("LTTBTransform")
struct LTTBTransformTests {

    // MARK: - Count Guarantees

    @Test("Output count equals targetCount when input exceeds target")
    func outputMatchesTarget() {
        let n = 5_000
        let ts = ContiguousArray<Double>((0..<n).map { Double($0) })
        let vals = ContiguousArray<Float>((0..<n).map { Float(sin(Double($0) * 0.01)) })
        let stage = LTTBTransform(targetCount: 100)

        let (outTs, outVals) = stage.apply(timestamps: ts, values: vals)
        #expect(outTs.count == 100)
        #expect(outVals.count == 100)
    }

    @Test("Pass-through when input count <= targetCount")
    func passThroughSmallInput() {
        let ts: ContiguousArray<Double> = [0, 1, 2, 3, 4]
        let vals: ContiguousArray<Float> = [0, 1, 0, -1, 0]
        let stage = LTTBTransform(targetCount: 2000)

        let (outTs, outVals) = stage.apply(timestamps: ts, values: vals)
        #expect(outTs.count == 5)
        #expect(outVals.count == 5)
    }

    @Test("Pass-through when input count == targetCount")
    func passThroughExactTarget() {
        let ts = ContiguousArray<Double>((0..<50).map { Double($0) })
        let vals = ContiguousArray<Float>(repeating: 1, count: 50)
        let stage = LTTBTransform(targetCount: 50)

        let (outTs, outVals) = stage.apply(timestamps: ts, values: vals)
        #expect(outTs.count == 50)
        #expect(outVals.count == 50)
    }

    // MARK: - Endpoint Preservation

    @Test("First and last timestamps are always preserved")
    func endpointsPreserved() {
        let n = 1_000
        let ts = ContiguousArray<Double>((0..<n).map { Double($0) * 5.0 })
        let vals = ContiguousArray<Float>((0..<n).map { Float($0) })
        let stage = LTTBTransform(targetCount: 50)

        let (outTs, _) = stage.apply(timestamps: ts, values: vals)
        #expect(outTs.first == ts.first)
        #expect(outTs.last == ts.last)
    }

    // MARK: - Empty Input

    @Test("Empty input returns empty output")
    func emptyInput() {
        let stage = LTTBTransform(targetCount: 100)
        let (outTs, outVals) = stage.apply(
            timestamps: ContiguousArray<Double>(),
            values: ContiguousArray<Float>()
        )
        #expect(outTs.isEmpty)
        #expect(outVals.isEmpty)
    }

    @Test("Single-element input returns single-element output")
    func singleElement() {
        let ts: ContiguousArray<Double> = [42.0]
        let vals: ContiguousArray<Float> = [3.14]
        let stage = LTTBTransform(targetCount: 100)

        let (outTs, outVals) = stage.apply(timestamps: ts, values: vals)
        #expect(outTs.count == 1)
        #expect(outVals.count == 1)
        #expect(outTs[0] == 42.0)
    }

    // MARK: - Output Validity

    @Test("Output timestamps and values are same length")
    func parallelArrayLengths() {
        let n = 3_000
        let ts = ContiguousArray<Double>((0..<n).map { Double($0) })
        let vals = ContiguousArray<Float>((0..<n).map { Float($0 % 10) })
        let stage = LTTBTransform(targetCount: 200)

        let (outTs, outVals) = stage.apply(timestamps: ts, values: vals)
        #expect(outTs.count == outVals.count)
    }
}
