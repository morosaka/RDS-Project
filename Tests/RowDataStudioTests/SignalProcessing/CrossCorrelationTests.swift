// SignalProcessing/CrossCorrelationTests.swift v1.0.0
/**
 * Tests for normalized cross-correlation and Pearson correlation.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Foundation
import Testing
@testable import RowDataStudio

@Suite("DSP Cross-Correlation")
struct CrossCorrelationTests {

    // MARK: - Pearson Correlation

    @Test("Pearson correlation of identical signals is 1.0")
    func pearsonIdentical() {
        let a: ContiguousArray<Float> = [1, 2, 3, 4, 5]
        let b: ContiguousArray<Float> = [1, 2, 3, 4, 5]
        let r = DSP.pearsonCorrelation(a, b)
        #expect(abs(r - 1.0) < 1e-5)
    }

    @Test("Pearson correlation of negated signal is -1.0")
    func pearsonNegated() {
        let a: ContiguousArray<Float> = [1, 2, 3, 4, 5]
        let b: ContiguousArray<Float> = [-1, -2, -3, -4, -5]
        let r = DSP.pearsonCorrelation(a, b)
        #expect(abs(r - (-1.0)) < 1e-5)
    }

    @Test("Pearson correlation of uncorrelated signals is near 0")
    func pearsonUncorrelated() {
        // Sine and cosine are uncorrelated over a full period
        var a = ContiguousArray<Float>(repeating: 0, count: 1000)
        var b = ContiguousArray<Float>(repeating: 0, count: 1000)
        for i in 0..<1000 {
            let t = Double(i) / 1000.0 * 2.0 * .pi
            a[i] = Float(sin(t))
            b[i] = Float(cos(t))
        }
        let r = DSP.pearsonCorrelation(a, b)
        #expect(abs(r) < 0.05, "Sin/cos should be uncorrelated, got \(r)")
    }

    @Test("Pearson correlation ignores NaN pairwise")
    func pearsonIgnoresNaN() {
        let a: ContiguousArray<Float> = [1, .nan, 3, 4, 5]
        let b: ContiguousArray<Float> = [1, 2, .nan, 4, 5]
        let r = DSP.pearsonCorrelation(a, b)
        // Only indices 0, 3, 4 contribute → r of [1,4,5] vs [1,4,5] = 1.0
        #expect(abs(r - 1.0) < 1e-5)
    }

    @Test("Pearson correlation of empty is NaN")
    func pearsonEmpty() {
        let a: ContiguousArray<Float> = []
        let b: ContiguousArray<Float> = []
        #expect(DSP.pearsonCorrelation(a, b).isNaN)
    }

    // MARK: - Cross-Correlation

    @Test("Cross-correlation finds correct lag for shifted signal")
    func crossCorrFindsLag() {
        // Create a reference signal with varying content (sine wave + trend)
        let n = 100
        var reference = ContiguousArray<Float>(repeating: 0, count: n)
        for i in 0..<n {
            reference[i] = Float(sin(Double(i) * 0.3)) + Float(i) * 0.01
        }

        // Extract a pattern from a known offset
        let offset = 30
        let patternLen = 20
        let pattern = ContiguousArray<Float>(reference[offset..<(offset + patternLen)])

        let corr = DSP.crossCorrelation(reference, pattern)
        #expect(corr.count == n - patternLen + 1)

        // Peak should be at the embedding offset (exact match → correlation ≈ 1.0)
        let peakIdx = corr.enumerated()
            .filter { !$0.element.isNaN }
            .max(by: { $0.element < $1.element })!.offset
        #expect(peakIdx == offset)
    }

    @Test("Cross-correlation of signal with itself peaks at lag 0")
    func crossCorrSelfPeak() {
        let signal: ContiguousArray<Float> = [1, 3, 2, 5, 4, 6, 3, 2]
        let corr = DSP.crossCorrelation(signal, signal)
        #expect(corr.count == 1)
        #expect(abs(corr[0] - 1.0) < 1e-4, "Self-correlation should be 1.0")
    }

    @Test("Cross-correlation returns empty when b longer than a")
    func crossCorrBLonger() {
        let a: ContiguousArray<Float> = [1, 2]
        let b: ContiguousArray<Float> = [1, 2, 3, 4]
        let corr = DSP.crossCorrelation(a, b)
        #expect(corr.isEmpty)
    }
}
