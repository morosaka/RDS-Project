// SignalProcessing/StatisticsTests.swift v1.0.0
/**
 * Tests for DSP statistical functions: mean, median, stddev, quantile.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Testing
@testable import RowDataStudio

@Suite("DSP Statistics")
struct StatisticsTests {

    // MARK: - Mean

    @Test("Mean of simple values")
    func meanSimple() {
        let values: ContiguousArray<Float> = [1, 2, 3, 4, 5]
        let result = DSP.mean(values)
        #expect(abs(result - 3.0) < 1e-6)
    }

    @Test("Mean ignores NaN values")
    func meanIgnoresNaN() {
        let values: ContiguousArray<Float> = [1, .nan, 3, .nan, 5]
        let result = DSP.mean(values)
        #expect(abs(result - 3.0) < 1e-6)
    }

    @Test("Mean of all-NaN returns NaN")
    func meanAllNaN() {
        let values: ContiguousArray<Float> = [.nan, .nan, .nan]
        #expect(DSP.mean(values).isNaN)
    }

    @Test("Mean of empty array returns NaN")
    func meanEmpty() {
        let values: ContiguousArray<Float> = []
        #expect(DSP.mean(values).isNaN)
    }

    // MARK: - Median

    @Test("Median of odd-count values")
    func medianOdd() {
        let values: ContiguousArray<Float> = [5, 1, 3, 2, 4]
        #expect(abs(DSP.median(values) - 3.0) < 1e-6)
    }

    @Test("Median of even-count values averages middle two")
    func medianEven() {
        let values: ContiguousArray<Float> = [1, 2, 3, 4]
        #expect(abs(DSP.median(values) - 2.5) < 1e-6)
    }

    @Test("Median ignores NaN")
    func medianIgnoresNaN() {
        let values: ContiguousArray<Float> = [.nan, 1, 3, .nan, 5]
        #expect(abs(DSP.median(values) - 3.0) < 1e-6)
    }

    // MARK: - Standard Deviation

    @Test("Standard deviation of known values")
    func stddevKnown() {
        let values: ContiguousArray<Float> = [2, 4, 4, 4, 5, 5, 7, 9]
        let result = DSP.standardDeviation(values)
        // Sample stddev (n-1): sqrt(32/7) ≈ 2.138
        #expect(abs(result - 2.138) < 0.01)
    }

    @Test("Standard deviation of single value returns NaN")
    func stddevSingle() {
        let values: ContiguousArray<Float> = [42]
        #expect(DSP.standardDeviation(values).isNaN)
    }

    // MARK: - Quantile

    @Test("Quantile P50 matches median")
    func quantileP50() {
        let values: ContiguousArray<Float> = [1, 2, 3, 4, 5]
        let q50 = DSP.quantile(values, q: 0.5)
        let med = DSP.median(values)
        #expect(abs(q50 - med) < 1e-6)
    }

    @Test("Quantile P0 and P100 are min and max")
    func quantileBoundaries() {
        let values: ContiguousArray<Float> = [10, 20, 30, 40, 50]
        #expect(abs(DSP.quantile(values, q: 0.0) - 10.0) < 1e-6)
        #expect(abs(DSP.quantile(values, q: 1.0) - 50.0) < 1e-6)
    }

    @Test("Quantile interpolates between values")
    func quantileInterpolation() {
        let values: ContiguousArray<Float> = [0, 10, 20, 30]
        let q25 = DSP.quantile(values, q: 0.25)
        // pos = 0.25 * 3 = 0.75, interpolate between sorted[0]=0 and sorted[1]=10
        // result = 0 * 0.25 + 10 * 0.75 = 7.5
        #expect(abs(q25 - 7.5) < 1e-6)
    }

    @Test("Quantile of all-NaN returns NaN")
    func quantileAllNaN() {
        let values: ContiguousArray<Float> = [.nan, .nan]
        #expect(DSP.quantile(values, q: 0.5).isNaN)
    }
}
