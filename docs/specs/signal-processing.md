# Signal Processing Library Specification

**Status:** Canonical executable spec
**Source:** RowDataLab `common/mathUtils.ts` v3.4.0 (~1000 lines)
**Target:** Swift port using the Accelerate framework (vDSP) for native performance

---

## Overview

RDL has a mature, production-tested signal processing library that is the foundation of all
analysis. These functions must be ported to Swift using `Accelerate` (vDSP) for SIMD
hardware acceleration on Apple Silicon.

---

## Core Functions (MVP Priority)

| RDL Function | Description | Swift/Accelerate Approach |
| ------------ | ----------- | ------------------------- |
| `detrend(signal, windowSize)` | Removes baseline (moving average) | `vDSP.subtract` + rolling mean |
| `integrate(values, dt)` | Cumulative integration (trapezoidal) | Loop with `vDSP.add` |
| `derivative(values, dt)` | Numerical derivative (finite difference) | `vDSP.subtract` + scale |
| `gaussianSmooth(signal, sigma)` | Convolution with Gaussian kernel | `vDSP.convolve` |
| `savitzkyGolay(signal, window, order)` | Polynomial filter (preserves derivatives) | Custom implementation |
| `simpleMovingAverage(signal, window)` | Simple moving average | `vDSP.slidingMean` |
| `exponentialMovingAverage(signal, alpha)` | EMA with decay | O(n) loop |
| `zeroPhaseSmooth(signal, halfWin)` | Forward + backward for zero phase shift | Two vDSP passes |
| `calculateCorrelation(a, b)` | Normalized cross-correlation | `vDSP.crossCorrelation` |

## Detection Functions (MVP Priority)

| RDL Function | Description | Port Notes |
| ------------ | ----------- | ---------- |
| `detectStrokes(timestamps, vel, acc)` | Stroke detection state machine | Direct port, logic-heavy (not vDSP) |
| `detectZeroCrossings(signal)` | Finds zero crossings | Simple loop |
| `detectLocalMinima(signal)` | Finds local minima | Loop with 3-point comparison |

## Statistical Functions

| RDL Function | Description | Swift Approach |
| ------------ | ----------- | -------------- |
| `mean(values)` | Arithmetic mean | `vDSP.mean` |
| `median(values)` | Median | Sort + middle index |
| `standardDeviation(values)` | Standard deviation | `vDSP.standardDeviation` |
| `getQuantile(sorted, q)` | Percentile (P5, P95, ...) | Interpolation on sorted array |

## Search and Interpolation Functions

| RDL Function | Description | Swift Approach |
| ------------ | ----------- | -------------- |
| `binarySearchFloor(arr, target)` | Index of value <= target | `Collection.partitioningIndex` |
| `interpolateAt(series, targetTime)` | Linear interpolation at arbitrary time | Direct port |
| `getNearestValue(series, time)` | Nearest value by timestamp | Binary search + comparison |

---

## Architectural Notes

**RDL generics:** In RDL these functions accept `NumericArray = number[] | Float32Array | Float64Array`.

**Swift equivalent:** Use generics with `AccelerateBuffer` protocol or `UnsafeBufferPointer<Float>`.
The `Accelerate` framework provides SIMD hardware acceleration on Apple Silicon.

**Input/Output pattern:** Functions should accept `ContiguousArray<Float>` (matching SoA buffer type)
and return `ContiguousArray<Float>`. Use `UnsafeMutableBufferPointer<Float>` for in-place operations
where performance is critical.

**NaN convention:** NaN indicates "missing data" (GPS not synced, HR not available). All functions
must propagate NaN correctly (vDSP handles this natively).

---

## Source Reference

RDL: `common/mathUtils.ts`
