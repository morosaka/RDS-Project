// Rendering/TransformPipelineTests.swift v1.0.0
/**
 * Tests for TransformPipeline composition and stage chaining.
 * --- Revision History ---
 * v1.0.0 - 2026-03-07 - Initial implementation (Phase 4: Rendering + MVP).
 */

import Foundation
import Testing
@testable import RowDataStudio

@Suite("TransformPipeline")
struct TransformPipelineTests {

    // MARK: - Empty Pipeline

    @Test("Empty pipeline returns input unchanged")
    func emptyPipeline() {
        let ts: ContiguousArray<Double> = [0, 100, 200, 300]
        let vals: ContiguousArray<Float> = [1, 2, 3, 4]
        let pipeline = TransformPipeline()

        let (outTs, outVals) = pipeline.apply(timestamps: ts, values: vals)
        #expect(outTs == ts)
        #expect(outVals == vals)
    }

    @Test("Empty pipeline with empty input returns empty arrays")
    func emptyPipelineEmptyInput() {
        let pipeline = TransformPipeline()
        let (outTs, outVals) = pipeline.apply(
            timestamps: ContiguousArray<Double>(),
            values: ContiguousArray<Float>()
        )
        #expect(outTs.isEmpty)
        #expect(outVals.isEmpty)
    }

    // MARK: - Stage Composition

    @Test("Pipeline applies stages in sequence")
    func stagesAppliedInOrder() {
        // Two ViewportCull stages with different ranges — second range narrows the first.
        // Range 1: 0…300 passes all 5 points
        // Range 2: 100…200 narrows to points at 100, 200
        let ts: ContiguousArray<Double> = [0, 100, 200, 300, 400]
        let vals: ContiguousArray<Float> = [1, 2, 3, 4, 5]

        let pipeline = TransformPipeline(stages: [
            ViewportCull(startMs: 0, endMs: 300),
            ViewportCull(startMs: 100, endMs: 200)
        ])
        let (outTs, outVals) = pipeline.apply(timestamps: ts, values: vals)

        #expect(outTs.allSatisfy { $0 >= 100 && $0 <= 200 })
        #expect(outVals.count == outTs.count)
    }

    @Test("appending() returns new pipeline without mutating original")
    func appendingImmutability() {
        let base = TransformPipeline(stages: [ViewportCull(startMs: 0, endMs: 1000)])
        let extended = base.appending(LTTBTransform(targetCount: 10))

        // Original pipeline untouched — apply to single-point input gives same result
        let ts: ContiguousArray<Double> = [500]
        let vals: ContiguousArray<Float> = [1]

        let (baseOut, _) = base.apply(timestamps: ts, values: vals)
        let (extOut, _) = extended.apply(timestamps: ts, values: vals)

        // Both should contain the single point (no reduction needed)
        #expect(baseOut.count == 1)
        #expect(extOut.count == 1)
    }

    // MARK: - MVP Factory

    @Test("mvp() pipeline produces output within targetCount")
    func mvpPipelineCountBound() {
        // 10,000 point signal over 100,000ms
        let n = 10_000
        let ts = ContiguousArray<Double>((0..<n).map { Double($0) * 10.0 })
        let vals = ContiguousArray<Float>((0..<n).map { Float(sin(Double($0) * 0.01)) })

        let pipeline = TransformPipeline.mvp(
            viewportMs: 0...100_000,
            targetCount: 200,
            pointsPerPixel: 1.0
        )
        let (outTs, outVals) = pipeline.apply(timestamps: ts, values: vals)

        #expect(outTs.count <= 200)
        #expect(outVals.count == outTs.count)
    }

    @Test("mvp() pipeline passes through small datasets unchanged by LTTB")
    func mvpPassThroughSmallData() {
        // 5 points, target 2000 — LTTB should pass through
        let ts: ContiguousArray<Double> = [0, 1000, 2000, 3000, 4000]
        let vals: ContiguousArray<Float> = [1, 2, 3, 2, 1]

        let pipeline = TransformPipeline.mvp(
            viewportMs: 0...4000,
            targetCount: 2000,
            pointsPerPixel: 0.5
        )
        let (outTs, outVals) = pipeline.apply(timestamps: ts, values: vals)

        #expect(outTs.count == 5)
        #expect(outVals.count == 5)
    }
}
