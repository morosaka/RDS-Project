// Rendering/AdaptiveSmoothTests.swift v1.0.0
/**
 * Tests for AdaptiveSmooth zoom-dependent strategy selection and output.
 * --- Revision History ---
 * v1.0.0 - 2026-03-07 - Initial implementation (Phase 4: Rendering + MVP).
 */

import Foundation
import Testing
@testable import RowDataStudio

@Suite("AdaptiveSmooth")
struct AdaptiveSmoothTests {

    // MARK: - Strategy Selection

    @Test("forZoom selects .none below 2 points/pixel")
    func strategyNoneAtHighZoom() {
        let stage = AdaptiveSmooth.forZoom(pointsPerPixel: 0.5)
        if case .none = stage.strategy { } else {
            Issue.record("Expected .none strategy, got \(stage.strategy)")
        }
    }

    @Test("forZoom selects .none at exactly 1 point/pixel")
    func strategyNoneAtOnePerPixel() {
        let stage = AdaptiveSmooth.forZoom(pointsPerPixel: 1.0)
        if case .none = stage.strategy { } else {
            Issue.record("Expected .none strategy at 1 ppp")
        }
    }

    @Test("forZoom selects .gaussian at 5 points/pixel")
    func strategyGaussianAtMediumZoom() {
        let stage = AdaptiveSmooth.forZoom(pointsPerPixel: 5.0)
        if case .gaussian(let sigma) = stage.strategy {
            #expect(sigma > 0)
        } else {
            Issue.record("Expected .gaussian strategy at 5 ppp")
        }
    }

    @Test("forZoom selects .movingAverage at 20 points/pixel")
    func strategyMovingAverageAtLowZoom() {
        let stage = AdaptiveSmooth.forZoom(pointsPerPixel: 20.0)
        if case .movingAverage(let w) = stage.strategy {
            #expect(w >= 3)
            #expect(w % 2 == 1, "Window must be odd")
        } else {
            Issue.record("Expected .movingAverage strategy at 20 ppp")
        }
    }

    @Test("forZoom moving average window grows with pointsPerPixel")
    func movingAverageWindowScales() {
        let low = AdaptiveSmooth.forZoom(pointsPerPixel: 50.0)
        let high = AdaptiveSmooth.forZoom(pointsPerPixel: 200.0)

        if case .movingAverage(let wLow) = low.strategy,
           case .movingAverage(let wHigh) = high.strategy {
            #expect(wHigh >= wLow, "Higher ppp should give larger window")
        }
    }

    // MARK: - Output Shapes

    @Test(".none strategy returns input unchanged")
    func nonePassThrough() {
        let ts: ContiguousArray<Double> = [0, 100, 200, 300]
        let vals: ContiguousArray<Float> = [1, 2, 3, 4]
        let stage = AdaptiveSmooth(strategy: .none)

        let (outTs, outVals) = stage.apply(timestamps: ts, values: vals)
        #expect(outTs == ts)
        #expect(outVals == vals)
    }

    @Test(".gaussian strategy preserves array length")
    func gaussianPreservesLength() {
        let n = 100
        let ts = ContiguousArray<Double>((0..<n).map { Double($0) })
        let vals = ContiguousArray<Float>((0..<n).map { Float($0) })
        let stage = AdaptiveSmooth(strategy: .gaussian(sigma: 2.0))

        let (outTs, outVals) = stage.apply(timestamps: ts, values: vals)
        #expect(outTs.count == n)
        #expect(outVals.count == n)
    }

    @Test(".movingAverage strategy preserves array length")
    func movingAveragePreservesLength() {
        let n = 100
        let ts = ContiguousArray<Double>((0..<n).map { Double($0) })
        let vals = ContiguousArray<Float>((0..<n).map { Float(sin(Double($0) * 0.1)) })
        let stage = AdaptiveSmooth(strategy: .movingAverage(windowSize: 7))

        let (outTs, outVals) = stage.apply(timestamps: ts, values: vals)
        #expect(outTs.count == n)
        #expect(outVals.count == n)
    }

    @Test("Smoothing reduces peak-to-peak amplitude on noisy signal")
    func smoothingReducesNoise() {
        // Alternating signal: 1, -1, 1, -1, ...
        let n = 100
        let ts = ContiguousArray<Double>((0..<n).map { Double($0) })
        let vals = ContiguousArray<Float>((0..<n).map { Float($0 % 2 == 0 ? 1 : -1) })

        let stage = AdaptiveSmooth(strategy: .gaussian(sigma: 3.0))
        let (_, smoothed) = stage.apply(timestamps: ts, values: vals)

        let maxIn  = vals.max()!
        let maxOut = smoothed.max()!
        // Smoothing should compress the amplitude
        #expect(maxOut < maxIn)
    }
}
