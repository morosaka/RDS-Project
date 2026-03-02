// SignalProcessing/SearchTests.swift v1.0.0
/**
 * Tests for DSP search and interpolation functions.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Testing
@testable import RowDataStudio

@Suite("DSP Search & Interpolation")
struct SearchTests {

    // MARK: - Binary Search Floor (Float)

    @Test("Binary search finds exact match")
    func binarySearchExact() {
        let array: ContiguousArray<Float> = [1, 3, 5, 7, 9]
        #expect(DSP.binarySearchFloor(array, target: 5) == 2)
    }

    @Test("Binary search finds floor of non-exact value")
    func binarySearchFloor() {
        let array: ContiguousArray<Float> = [1, 3, 5, 7, 9]
        #expect(DSP.binarySearchFloor(array, target: 6) == 2)
    }

    @Test("Binary search returns -1 for value below minimum")
    func binarySearchBelowMin() {
        let array: ContiguousArray<Float> = [1, 3, 5, 7, 9]
        #expect(DSP.binarySearchFloor(array, target: 0) == -1)
    }

    @Test("Binary search returns last index for value above maximum")
    func binarySearchAboveMax() {
        let array: ContiguousArray<Float> = [1, 3, 5, 7, 9]
        #expect(DSP.binarySearchFloor(array, target: 100) == 4)
    }

    @Test("Binary search on empty array returns -1")
    func binarySearchEmpty() {
        let array: ContiguousArray<Float> = []
        #expect(DSP.binarySearchFloor(array, target: 5) == -1)
    }

    // MARK: - Binary Search Floor (Double)

    @Test("Binary search Double finds floor")
    func binarySearchDoubleFloor() {
        let array: ContiguousArray<Double> = [0, 100, 200, 300, 400]
        #expect(DSP.binarySearchFloor(array, target: 250) == 2)
    }

    // MARK: - Interpolation

    @Test("Interpolate at exact timestamp returns exact value")
    func interpolateExact() {
        let ts: ContiguousArray<Double> = [0, 100, 200, 300]
        let vals: ContiguousArray<Float> = [0, 10, 20, 30]
        let result = DSP.interpolateAt(timestamps: ts, values: vals, targetTime: 200)
        #expect(abs(result - 20.0) < 1e-6)
    }

    @Test("Interpolate between timestamps")
    func interpolateBetween() {
        let ts: ContiguousArray<Double> = [0, 100, 200, 300]
        let vals: ContiguousArray<Float> = [0, 10, 20, 30]
        let result = DSP.interpolateAt(timestamps: ts, values: vals, targetTime: 150)
        #expect(abs(result - 15.0) < 1e-6)
    }

    @Test("Interpolate clamps to boundaries")
    func interpolateClamp() {
        let ts: ContiguousArray<Double> = [100, 200, 300]
        let vals: ContiguousArray<Float> = [10, 20, 30]
        #expect(abs(DSP.interpolateAt(timestamps: ts, values: vals, targetTime: 0) - 10.0) < 1e-6)
        #expect(abs(DSP.interpolateAt(timestamps: ts, values: vals, targetTime: 999) - 30.0) < 1e-6)
    }

    @Test("Interpolate empty returns NaN")
    func interpolateEmpty() {
        let ts: ContiguousArray<Double> = []
        let vals: ContiguousArray<Float> = []
        #expect(DSP.interpolateAt(timestamps: ts, values: vals, targetTime: 50).isNaN)
    }

    // MARK: - Nearest Value

    @Test("Nearest value finds closest timestamp")
    func nearestValue() {
        let ts: ContiguousArray<Double> = [0, 100, 200, 300]
        let vals: ContiguousArray<Float> = [0, 10, 20, 30]
        // 180 is closer to 200 than to 100
        let result = DSP.getNearestValue(timestamps: ts, values: vals, time: 180)
        #expect(abs(result - 20.0) < 1e-6)
    }

    @Test("Nearest value at boundary")
    func nearestValueBoundary() {
        let ts: ContiguousArray<Double> = [0, 100, 200]
        let vals: ContiguousArray<Float> = [5, 10, 15]
        #expect(abs(DSP.getNearestValue(timestamps: ts, values: vals, time: -10) - 5.0) < 1e-6)
        #expect(abs(DSP.getNearestValue(timestamps: ts, values: vals, time: 999) - 15.0) < 1e-6)
    }
}
