// SignalProcessing/GaussianSmoothTests.swift v1.0.0
/**
 * Tests for Gaussian smoothing and kernel generation.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 2: Signal Processing).
 */

import Testing
@testable import RowDataStudio

@Suite("DSP Gaussian Smoothing")
struct GaussianSmoothTests {

    // MARK: - Kernel Generation

    @Test("Gaussian kernel has correct length")
    func kernelLength() {
        let kernel = DSP.gaussianKernel(sigma: 2.0)
        // radius = ceil(2 * 3) = 6, size = 13
        #expect(kernel.count == 13)
    }

    @Test("Gaussian kernel sums to 1.0")
    func kernelSumsToOne() {
        let kernel = DSP.gaussianKernel(sigma: 3.0)
        let sum = kernel.reduce(0, +)
        #expect(abs(sum - 1.0) < 1e-5)
    }

    @Test("Gaussian kernel is symmetric")
    func kernelSymmetric() {
        let kernel = DSP.gaussianKernel(sigma: 2.0)
        for i in 0..<kernel.count / 2 {
            #expect(abs(kernel[i] - kernel[kernel.count - 1 - i]) < 1e-6)
        }
    }

    @Test("Gaussian kernel peak is at center")
    func kernelPeakAtCenter() {
        let kernel = DSP.gaussianKernel(sigma: 2.0)
        let center = kernel.count / 2
        let maxVal = kernel.max()!
        #expect(abs(kernel[center] - maxVal) < 1e-6)
    }

    // MARK: - Smoothing

    @Test("Gaussian smooth preserves constant signal")
    func smoothConstant() {
        let signal: ContiguousArray<Float> = ContiguousArray(repeating: 5.0, count: 100)
        let result = DSP.gaussianSmooth(signal, sigma: 3.0)
        #expect(result.count == signal.count)
        for v in result {
            #expect(abs(v - 5.0) < 1e-4)
        }
    }

    @Test("Gaussian smooth reduces noise")
    func smoothReducesNoise() {
        // Create a signal with a known mean and added noise
        var signal = ContiguousArray<Float>(repeating: 10.0, count: 200)
        // Add alternating noise
        for i in stride(from: 0, to: 200, by: 2) {
            signal[i] += 2.0
            signal[i + 1] -= 2.0
        }
        let result = DSP.gaussianSmooth(signal, sigma: 4.0)

        // Standard deviation should decrease after smoothing
        let inputStd = DSP.standardDeviation(signal)
        let outputStd = DSP.standardDeviation(result)
        #expect(outputStd < inputStd)
    }

    @Test("Gaussian smooth output has same length as input")
    func smoothSameLength() {
        let signal: ContiguousArray<Float> = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        let result = DSP.gaussianSmooth(signal, sigma: 1.0)
        #expect(result.count == signal.count)
    }

    @Test("Gaussian smooth of single element returns unchanged")
    func smoothSingleElement() {
        let signal: ContiguousArray<Float> = [42.0]
        let result = DSP.gaussianSmooth(signal, sigma: 2.0)
        #expect(result.count == 1)
        #expect(abs(result[0] - 42.0) < 1e-6)
    }
}
