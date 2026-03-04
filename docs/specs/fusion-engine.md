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

STEP 3: Stroke Detection ──  Multi-validated state machine:
  a) Pre-processing:
     1. Smooth velocity (zero-phase, 15 samples)
     2. Adaptive baseline (zero-phase, ~6s window) ← MUST be zero-phase
     3. Detrend: velDet = smooth - baseline
  b) Dynamic thresholds with safety floors:
     - detRange = P95 - P05
     - H_UP  = max(detRange * 0.20, P95 * 0.06)
     - H_DN  = max(detRange * 0.20, P95 * 0.06)
     - REARM = max(detRange * 0.08, P95 * 0.02)
     - SWING_MIN_RATIO = clamp(0.35 * rangeRatio, 0.06, 0.18)
  c) State machine: SEEK_VALLEY → SEEK_PEAK → validate
     - Rearm-to-valley on deep reversal (v < minVal - REARM)
  d) Multi-layer validation (ALL must pass):
     V1: Swing ratio ≥ SWING_MIN_RATIO
     V2: Adaptive timing (reject < 0.45 × rolling median period)
     V3: Accel pattern (pre-catch < -0.03g, post-catch > +0.03g,
         amplitude > 0.08g)
     V4: NK cross-validation (if Empower/SpeedCoach data available,
         stroke count and cadence must agree within tolerance)
     V5: GPS speed oscillation correlation (if GPS available)
  e) Manual correction fallback:
     If algorithmic detection is insufficient, user can manually
     adjust stroke boundaries in the UI. See §Manual Stroke Editing.

STEP 4: Per-Stroke Aggregation
  strokeRate = 60000 / duration_ms (SPM)
  distance = speedAvg * duration_s
  + speedAvg, speedMax, accelPeak, accelMin
  + avgHR, avgPitch, avgRoll
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
    let strokeIndex: Int
    let duration: TimeInterval
    let strokeRate: Double         // SPM (60/duration)
    let distance: Double?          // meters (speedAvg × duration)
    let avgVelocity: Double?
    let peakVelocity: Double?
    let avgHR: Double?             // Average HR (from FIT)
    let avgPitch: Double?
    let avgRoll: Double?
    // Dynamic metrics bag for extensibility
    let metrics: [String: Double]  // e.g. "imu_flt_ps_acc_surge_max"
    // NOTE: power, efficiencyIndex excluded (see §Design Decisions)
    // NOTE: driveTime/recoveryTime/driveRatio deferred (see §Design Decisions)
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

## Stroke Detection: Design Decisions (2026-03-03)

### Excluded from RowDataLab port

- **`powerAvg` / `powerMax`**: Derived power (F=ma × v × mass) proved too theoretical
  in practice. Without real force sensors (strain gauges, Empower), the numbers were
  never useful. Will revisit when real power data is available.
- **`efficiencyIndex`**: `speed / |accelMagnitude3D|` is a synthetic ratio with no
  physical calibration. Excluded for the same reason as power.

### Drive/Recovery phase analysis (`analyzeStrokePhases`)

The RowDataLab implementation uses zero-crossing of surge acceleration after peak
to split drive vs. recovery. This approach has a known failure mode:

> **Problem:** Some rowing signatures show acceleration oscillating below zero
> multiple times at the start of recovery (hull rebound, slide return dynamics).
> A naive first-zero-crossing detector places the finish point too early,
> corrupting `driveDuration`, `recoveryDuration`, and `rhythmRatio`.

**Decision:** `driveRatio` is an important metric to retain, but the zero-crossing
approach alone is insufficient. Possible mitigations:

1. Hysteresis band around zero (not just first crossing, but sustained crossing)
2. Use NK Empower force curve data as ground truth for finish point
3. Use video analysis (future) for visual confirmation of blade extraction
4. Manual correction UI as ultimate fallback

Implementation deferred until a more robust approach is validated.

### Multi-source validation strategy

Stroke detection accuracy is the foundation of the entire analysis.
Available cross-validation sources, in order of reliability:

| Source                  | Signal                                       | Reliability            | Availability         |
| ----------------------- | -------------------------------------------- | ---------------------- | -------------------- |
| NK Empower CSV          | Per-stroke force/angle data (pre-segmented)  | Highest (ground truth) | Optional             |
| NK SpeedCoach FIT       | Stroke rate / cadence channel                | High                   | Common               |
| GPS speed               | ~0.3-0.5 Hz oscillation correlates w/ strokes| Medium                 | Always (with GPMF)   |
| IMU surge accel         | Morphological pattern (neg→pos at catch)     | Medium                 | Always               |
| Complementary velocity  | Detrended oscillation (primary detector)     | Medium                 | Always               |

When multiple sources are available, the detection should cross-validate:

- **Empower available:** Use Empower stroke count as reference; flag mismatches
- **SpeedCoach available:** Validate detected stroke rate ≈ device cadence (±2 SPM)
- **GPS only:** Use surge accel as secondary validator (V3)

### Manual stroke editing (future)

If algorithmic detection proves insufficient for edge cases (rough water,
technical drills, start sequences), a manual correction UI is required:

- User can add/remove/adjust stroke boundaries on the timeline
- Manual edits stored as sidecar data (non-destructive)
- All downstream aggregation re-computed from corrected strokes
- Priority: implement after Phase 6 (Canvas) when timeline UI exists

---

## Source References

- **FusionEngine:** RDL `services/FusionEngine.ts`
- **Signal Processing:** RDL `common/mathUtils.ts`
- **Type Definitions:** RDL `gpmf-utility/types.ts`
- **Sync Pipeline:** `docs/specs/sync-pipeline.md` (Steps 0-1)
- **Signal Processing Library:** `docs/specs/signal-processing.md`
