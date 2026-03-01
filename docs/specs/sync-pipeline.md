# Synchronization Pipeline Specification

**Status:** Canonical executable spec
**Source:** Kickoff Report v1.2, Section 7.2
**Validation:** Production-verified in RowDataLab v2.6.0 on real rowing data (GoPro HERO10, NK SpeedCoach, Garmin)

---

## Available Temporal Sources

| Source | Origin | Present in | Reliability | Use |
|--------|--------|------------|-------------|-----|
| `stts` (sample timing) | MP4 atom | Video, GPMF | Authoritative (relative) | Master clock for timeline |
| `GPSU` / `GPS9` | GPS satellite | GPMF | Medium (improves with convergence) | Absolute time, cross-device sync |
| `mp4CreationTime` | Camera RTC | MP4 mvhd | Low (drift, manual setting) | Fallback, approximate sorting |
| `tmcd` (timecode) | Camera RTC | MP4 tmcd track | Low (redundant with mp4Creation) | Not worth parsing |
| FIT Timestamp | Device clock | FIT file | Medium-high (Garmin syncs NTP/GPS) | FIT-to-Video sync |

**Experimentally verified (2026-02-27):** The `tmcd` track contains a single frame number derived from the camera's RTC. It adds no information beyond `mp4CreationTime`.

---

## STEP 0: Tilt Bias Estimation

The IMU surge axis (Y) includes both kinematic acceleration and a static gravity component (projection due to camera tilt).

**Method:**
```
avgImuSurge = average(accelReadings.y)
avgGpsAccel = (gpsSpeed[last] - gpsSpeed[first]) / session_duration
tiltBiasMps2 = avgImuSurge - avgGpsAccel
tiltBiasG = tiltBiasMps2 / 9.80665
```

This correction is applied to all ACCL samples before fusion.

**Source RDL:** `services/FusionEngine.ts` (STEP 0)

---

## STEP 1: GPMF Internal Alignment (SignMatchStrategy)

GPS has ~200-300ms lag compared to IMU due to receiver processing.

**Algorithm: Slope-Sign Consensus**
1. Find GPS speed peak -> center analysis window (+/-20s)
2. Resample GPS speed and integrated ACCL on uniform 20ms grid
3. Smooth GPS with gaussianSmooth(sigma=8)
4. Calculate slopes (delta between consecutive samples)
5. Binarize slopes with +/-0.02 threshold -> sign vectors {-1, 0, +1}
6. Cross-correlate binary vectors on +/-2500ms window (125 steps)
7. Score = sum of products (agreement) / count (non-zero pairs only)
8. Accept if bestScore > 0.15 (consensus threshold)

**Verified Constants:**
| Constant | Value | Unit |
|----------|-------|------|
| RESAMPLE_STEP | 20 | ms |
| WIN_SIZE_MS | 20000 | ms (+/-20s around peak) |
| MAX_LAG_MS | 2500 | ms (search range) |
| THRESHOLD | 0.15 | acceptance threshold |
| GPS_SMOOTHING | 8 | gaussian kernel sigma |
| SLOPE_THRESHOLD | 0.02 | slope binarization |

**Output:** lagMs (typically 100-400ms), applied to GPS readings

**Source RDL:** `services/sync/SignMatchStrategy.ts`

---

## STEP 2: GPMF <-> Video Alignment

GPMF timestamps are already relative to the MP4 file (derived from stts/mdhd). Intrinsic alignment, offset = 0. No calculation needed.

---

## STEP 3: FIT <-> GPMF Alignment (two complementary strategies)

### Strategy A: GpsSpeedCorrelator (speed cross-correlation)

1. Extract GPS speed series from GPMF (speed3d, 10Hz)
2. Extract GPS speed series from FIT (enhanced_speed, ~1Hz)
3. Resample both at 1Hz with linear interpolation
4. Normalize (mean=0, std=1)
5. Cross-correlate normalized on +/-300s window at 1s steps
6. Find peak and second peak (minimum 30s separation)
7. Confidence = peak/secondPeak (HIGH >=2.5, MEDIUM >=1.5, LOW <1.5)

**Verified Constants:**
| Constant | Value | Unit |
|----------|-------|------|
| SEARCH_RANGE_MS | 300000 | ms (+/-300s) |
| RESAMPLE_STEP_MS | 1000 | ms (1 Hz) |
| MIN_PEAK_SEPARATION | 30000 | ms (30s between peaks) |

**Source RDL:** `services/sync/GpsSpeedCorrelator.ts`

### Strategy B: GpsTrackCorrelator (Haversine distance minimization)

1. Extract GPS positions from GPMF (lat/lon, 10Hz)
2. Extract GPS positions from FIT (semicircles -> degrees)
3. Coarse phase: scan +/-300s at 1s steps. For each offset, calculate average Haversine distance between temporal pairs
4. Fine phase: scan +/-5s at 100ms steps around coarse minimum
5. Confidence based on: absolute distance + improvement ratio vs offset=0
6. Cross-validation: compare offset with Strategy A (CONSISTENT <2s, CLOSE <10s)

**Verified Constants:**
| Constant | Value | Unit |
|----------|-------|------|
| COARSE_RANGE_MS | 300000 | ms |
| COARSE_STEP_MS | 1000 | ms |
| FINE_RANGE_MS | 5000 | ms |
| FINE_STEP_MS | 100 | ms |
| MAX_TIME_DIFF_MS | 2000 | ms (tolerance for matching pairs) |

**Source RDL:** `services/sync/GpsTrackCorrelator.ts`

### Cross-Validation Protocol

Both strategies are executed and results cross-validated:
- Agreement <2s difference -> **HIGH** confidence
- Agreement <10s difference -> **MEDIUM** confidence (CLOSE)
- Disagreement >10s -> request visual confirmation from user

Fallback: manual alignment (drag on timeline) -- never needed in RDL with real data, but always available.

---

## STEP 4: FIT Diagnostic Tools (validation, not synchronization)

- **FitGapAnalyzer**: identifies temporal gaps in FIT records
- **FitKinematicAnalyzer**: verifies kinematic consistency (speed, distance, cadence)
- **FitTrackGeometryAnalyzer**: validates GPS track geometry (distances, bearing)

**Source RDL:** `services/sync/FitGapAnalyzer.ts`, `FitKinematicAnalyzer.ts`, `FitTrackGeometryAnalyzer.ts`

---

## Multi-Camera Synchronization

Two GoPros (boat + motorboat) do not share any clock.

**Method:** GPS back-computation (`lastGPSU - relativeTime`) for each camera. Offset = difference between the two absolute origins.

**Precision:** ~1-5 seconds (limited by GPS convergence). Manual refinement on visual reference (oar entry splash, etc.).

This is "good enough" for multi-angle synchronization. Frame precision is not necessary for rowing analysis.
