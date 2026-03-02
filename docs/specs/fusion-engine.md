# FusionEngine Specification

**Status:** Canonical executable spec
**Source:** Kickoff Report v1.2, Section 8.5
**Validation:** Production-verified in RowDataLab v2.6.0

---

## Overview

The FusionEngine is the computational heart of RDS. It transforms raw multi-source data into analyzable buffers with derived metrics and stroke segmentation.

**Input:** TelemetryData (GPMF) + ParsedFitData (FIT) + Config
**Output:** FusionResult (SoA buffers, stroke events, per-stroke statistics, diagnostics)

---

## Pipeline (6 steps, rigorous order)

```text
STEP 0: Tilt Bias ──────────  avgImuSurge - avgGpsAccel -> bias in G
                               (See sync-pipeline.md STEP 0 for detail)

STEP 1: Auto-Sync ─────────  SignMatchStrategy -> lagMs (GPS->IMU offset)
                               (See sync-pipeline.md STEP 1 for detail)

STEP 1.5: Physics Prep ────  ACCL_Y -> G units - tiltBias, gaussian(sigma=4)

STEP 2: Fusion Loop ────────  For each ACCL sample (200Hz):
  a) Populate IMU raw/filtered
  b) Interpolate GYRO, GRAV on ACCL timestamp
  c) Calculate pitch/roll from gravity (atan2)
  d) Synchronize GPS (with applied lag)
  e) Synchronize FIT records (HR, cadence, power)
  f) Complementary Filter:
     vel = alpha * (vel + acc * dt) + (1 - alpha) * gps_speed
     alpha = 0.999 (heavy IMU trust)

STEP 3: Stroke Detection ──  State machine on detrended velocity:
  1. Smooth velocity (zero-phase, 15 samples)
  2. Adaptive baseline (~6s window)
  3. Detrend: velDet = smooth - baseline
  4. Dynamic thresholds from P95/P05 (H_UP, H_DN, REARM)
  5. State machine: SEEK_VALLEY -> SEEK_PEAK -> validate
  6. Validation: swing ratio, timing, ACCL pattern

STEP 4: Per-Stroke Aggregation
  strokeRate = 60000 / duration_ms (SPM)
  distance = speedAvg * duration_s
  efficiency = avg(speed / |totalAccMagnitude| + 0.1)
  + speedAvg, speedMax, powerAvg, accelPeak, accelMin
  + driveTime, recoveryTime, rhythmRatio
```

---

## Key Constants

| Constant | Value | Step | Notes |
| -------- | ----- | ---- | ----- |
| Gaussian sigma | 4 | 1.5 | Physics prep smoothing |
| Complementary alpha | 0.999 | 2 | Heavy IMU trust (GPS updates infrequent) |
| Zero-phase window | 15 samples | 3 | Velocity smoothing for stroke detection |
| Baseline window | ~6s | 3 | Adaptive detrending |
| Swing ratio bounds | 0.25-0.55 | 3 | Drive/Total validation range |

---

## Output Data Models (Swift)

```swift
/// A single detected stroke
struct StrokeEvent: Codable, Sendable {
    let index: Int
    let startTime: TimeInterval    // Catch (start of pull phase)
    let endTime: TimeInterval      // Next catch
    let duration: TimeInterval     // ms
    let startIdx: Int              // Index in SoA buffer
    let endIdx: Int
    // Phase analysis
    var finishTime: TimeInterval?  // Finish pull / start recovery
    var driveDuration: TimeInterval?
    var recoveryDuration: TimeInterval?
    var rhythmRatio: Double?       // Drive / Total (typically 0.35-0.45)
}

/// Aggregate statistics for a stroke
struct PerStrokeStat: Codable, Sendable {
    let index: Int
    let timestamp: TimeInterval    // Midpoint of the stroke
    let duration: TimeInterval
    let strokeRate: Double         // SPM (60000/duration)
    let distance: Double           // meters
    let speedAvg: Double
    let speedMax: Double
    let accelMax: Double           // Acceleration peak (force)
    let accelMin: Double           // Deceleration peak (check)
    let efficiencyIndex: Double    // avg(speed / |acc_magnitude|)
    var driveTime: TimeInterval?
    var recoveryTime: TimeInterval?
    var driveRatio: Double?        // 0.0 - 1.0
    var heartRate: Double?         // Average HR in the period
    var power: Double?             // Average power (if available)
}

/// Top-level fusion output
struct FusionResult: Sendable {
    let buffers: SensorDataBuffers     // SoA, 40+ channels
    let diagnostics: FusionDiagnostics // tiltBias, lagMs, syncConfidence
    let strokes: [StrokeEvent]
    let perStrokeMetrics: [PerStrokeStat]
}
```

---

## Source References

- **FusionEngine:** RDL `services/FusionEngine.ts`
- **Signal Processing:** RDL `common/mathUtils.ts`
- **Type Definitions:** RDL `gpmf-utility/types.ts`
- **Sync Pipeline:** `docs/specs/sync-pipeline.md` (Steps 0-1)
- **Signal Processing Library:** `docs/specs/signal-processing.md`
