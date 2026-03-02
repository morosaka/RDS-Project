# Session Log: Phase 2 — Signal Processing Library
**Date**: 2026-03-02
**Phase**: 2 (Signal Processing)
**Status**: COMPLETE

## Objective
Port RDL's `common/mathUtils.ts` to Swift using Accelerate/vDSP for native performance.

## Files Created

### Source (Sources/RowDataStudio/SignalProcessing/) — 14 files
1. **DSP.swift** — Namespace enum, gaussianKernel(), reflectPad() utility
2. **Statistics.swift** — mean, median, standardDeviation, quantile (NaN-aware)
3. **Search.swift** — binarySearchFloor (Float+Double), interpolateAt, getNearestValue
4. **GaussianSmooth.swift** — vDSP_conv with Gaussian kernel, reflect padding
5. **SimpleMovingAverage.swift** — vDSP_conv with uniform kernel, reflect padding
6. **ExponentialMovingAverage.swift** — O(n) loop, alpha decay
7. **SavitzkyGolay.swift** — Polynomial filter, Vandermonde pseudoinverse for coefficients
8. **ZeroPhaseSmooth.swift** — Forward + backward SMA pass
9. **Detrend.swift** — Baseline removal via vDSP_vsub(signal - SMA baseline)
10. **Integrate.swift** — Cumulative trapezoidal integration
11. **Derivative.swift** — Central finite difference (forward/backward at boundaries)
12. **CrossCorrelation.swift** — Sliding normalized Pearson + single-pair Pearson
13. **StrokeDetection.swift** — State machine: smooth→detrend→P95/P05 thresholds→SEEK_VALLEY→SEEK_PEAK
14. **LTTB.swift** — Largest Triangle Three Buckets downsampling (Steinarsson)

### Tests (Tests/RowDataStudioTests/SignalProcessing/) — 11 files
1. **StatisticsTests.swift** — 12 tests: mean, median, stddev, quantile + NaN + edge cases
2. **SearchTests.swift** — 11 tests: binary search, interpolation, nearest value
3. **GaussianSmoothTests.swift** — 8 tests: kernel, smoothing, constant, noise reduction
4. **SavitzkyGolayTests.swift** — 5 tests: constant, linear, noise, length, window
5. **ZeroPhaseSmoothTests.swift** — 5 tests: constant, length, peak position, noise, single
6. **DetrendTests.swift** — 4 tests: constant offset, slow drift, length, constant signal
7. **IntegrateTests.swift** — 5 tests: constant→linear, linear→quadratic, zero, empty, single
8. **DerivativeTests.swift** — 5 tests: linear, quadratic, constant, length, boundaries
9. **CrossCorrelationTests.swift** — 8 tests: Pearson (identical, negated, uncorrelated, NaN, empty), cross-corr (lag, self, empty)
10. **StrokeDetectionTests.swift** — 6 tests: synthetic strokes, duration, rate, sequential, flat, short
11. **LTTBTests.swift** — 7 tests: endpoints, count, overflow, minimum, spike, ascending, empty

## Test Results
- **103 tests total** (25 Phase 0+1 + 78 Phase 2) — ALL PASS
- 16 test suites, all green

## Architecture Decisions
- **DSP enum namespace** with extensions per file — clean, discoverable API
- **ContiguousArray<Float>** for all inputs/outputs — matches SoA buffer type
- **vDSP_conv** for convolution-based functions (Gaussian, SMA, SG) — hardware-accelerated
- **Reflect padding** for same-length output with minimal edge artifacts
- **NaN-aware statistics** (filter NaN) vs **NaN-propagating smoothing** (IEEE 754)
- **StrokeDetection** returns existing Phase 1 `StrokeEvent` model (timestamps converted ms→s)
- **CrossCorrelation** uses NaN-aware Pearson per lag window (not raw vDSP, handles sparse data)

## Issues Encountered & Resolved
1. `sin`/`cos` not in scope in test files → Added `import Foundation`
2. Sample stddev test expected 2.0 but actual √(32/7) ≈ 2.138 → Fixed expected value
3. Cross-correlation lag test with sparse (mostly-zero) signal → NaN at most lags, max() confused → Used rich signal (sine+trend) as reference

## Key Implementation Details
- **vDSP_conv** reverses the kernel internally (correlation, not convolution). Symmetric kernels (Gaussian, SMA, SG smoothing coefficients) are unaffected.
- **vDSP_vsub(B, IB, A, IA, C, IC, N)** computes C = A - B (B parameter comes first, counterintuitive).
- **SavitzkyGolay coefficients**: Vandermonde matrix → J^T*J → Gauss-Jordan inverse → first row of pseudoinverse. Falls back to uniform kernel on degenerate matrix.
- **StrokeDetection** two-pass approach: (1) collect catch/finish indices via state machine, (2) construct StrokeEvents between consecutive catches with validation (0.8-5.0s duration).
