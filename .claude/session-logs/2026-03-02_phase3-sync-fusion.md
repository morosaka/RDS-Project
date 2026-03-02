# Session Log: Phase 3 — Sync + Fusion Engine
**Date**: 2026-03-02
**Phase**: 3 (Sync + Fusion)
**Status**: COMPLETE

## Objective
Implement the 4-step sync pipeline and 6-step fusion engine per `docs/specs/sync-pipeline.md` and `docs/specs/fusion-engine.md`. Bridge SDK modules to app layer via adapter pattern.

## Files Created

### Source (Sources/RowDataStudio/Core/Services/) — 14 files

**Foundation:**
1. **Sync/SyncConstants.swift** — All calibrated sync constants (resample steps, search windows, thresholds)
2. **Fusion/FusionConstants.swift** — Fusion pipeline constants (Gaussian σ, complementary α, sample rates)
3. **Haversine.swift** — GPS Haversine distance + FIT semicircle→degrees conversion

**SDK Adapters:**
4. **SDKAdapters/GPMFAdapter.swift** — GPMF SDK → app types (GPMFGpsTimeSeries, GPMFAccelTimeSeries, SoA buffers, sidecar metadata)
5. **SDKAdapters/FITAdapter.swift** — FIT SDK → app types (FITTimeSeries, decode, absoluteStartTime)
6. **SDKAdapters/CSVAdapter.swift** — CSV SDK → app types (NKEmpower metrics extraction, mech_ext_ps_* keying)

**Sync Strategies:**
7. **Sync/TiltBiasEstimator.swift** — Step 0: avgIMU − avgGPS → bias (m/s², G)
8. **Sync/SignMatchStrategy.swift** — Step 1: slope-sign consensus cross-correlation (±2.5s window)
9. **Sync/GpsSpeedCorrelator.swift** — Step 3A: z-scored speed cross-correlation (±300s, 1Hz grid)
10. **Sync/GpsTrackCorrelator.swift** — Step 3B: Haversine track distance minimization (coarse+fine)

**Orchestrators:**
11. **SyncEngine.swift** — 4-step sync orchestrator with cross-validation protocol
12. **Fusion/ComplementaryFilter.swift** — α=0.999 IMU-GPS velocity fusion filter
13. **Fusion/StrokeAggregator.swift** — Per-stroke metric aggregation (velocity, distance, HR, pitch, roll)
14. **FusionEngine.swift** — 6-step fusion pipeline (physics prep → pitch/roll → GPS interp → FIT sync → complementary filter → stroke detection → aggregation)

### Tests (Tests/RowDataStudioTests/Core/Services/) — 11 files
1. **HaversineTests.swift** — 6 tests: distance calculations, semicircles conversion, edge cases
2. **TiltBiasEstimatorTests.swift** — 4 tests: constant tilt, empty data, GPS acceleration, zero bias
3. **SignMatchStrategyTests.swift** — 3 tests: synthetic lag, insufficient data, score validation
4. **GpsSpeedCorrelatorTests.swift** — 3 tests: known offset, insufficient data, zero offset
5. **GpsTrackCorrelatorTests.swift** — 3 tests: known offset, insufficient data, distance improvement
6. **ComplementaryFilterTests.swift** — 6 tests: zero accel, step convergence, pure IMU, empty, convergence time, NaN
7. **StrokeAggregatorTests.swift** — 4 tests: valid stroke, empty, NaN channels, multiple strokes
8. **SyncEngineTests.swift** — 3 tests: full pipeline, tilt bias estimation, warnings on failure
9. **FusionEngineTests.swift** — 6 tests: produces strokes, diagnostics, pitch/roll, velocity, empty buffers
10. **GPMFAdapterTests.swift** — 5 tests: intermediate type values, SoA NaN, Codable roundtrips
11. **FITAdapterTests.swift** — 3 tests: FIT epoch offset, semicircles consistency, NaN handling

## Test Summary
- **New tests**: 46 (across 11 test files)
- **Total project tests**: 148 (27 suites)
- **All passing**: Yes

## Architecture Decisions

### SDK Adapter Pattern
- GPMF SDK types (SensorReading, GPSTimestampObservation) are NOT Codable/Sendable
- Created Codable mirror types: `GPMFGpsTimeSeries`, `GPMFAccelTimeSeries`
- FIT SDK has custom `FITSwiftSDK.InputStream(data:)` — NOT Foundation's InputStream
- FIT SDK uses `decoder.addMesgListener(listener)` pattern (not event-based)
- CSVAdapter is thin: NKEmpowerSession already Codable+Sendable

### Sync Cross-Validation
- Speed + Track correlators independently estimate FIT-GPMF offset
- Cross-validation: <2s difference = consistent (1.0 confidence), <10s = close (0.7), >10s = disagree (0.3)
- Final SyncResult uses speed correlator offset (more reliable) with cross-validated confidence

### GPS Speed Correlator Fixes
- Standard cross-correlation must normalize by total signal length (not overlap count) to prevent small-overlap score inflation
- Returned offset must include base timestamp difference: `offset = (fitStart - gpmfStart) + lag * step`
- Minimum overlap threshold (30% of shorter signal) prevents extreme-lag spurious peaks

### Complementary Filter
- α = 0.999 (GPS-dominant at 200 Hz: 95% convergence in ~15s)
- NaN GPS → pure IMU integration; NaN ACCL → hold velocity
- Initial velocity seeded from first valid GPS speed

## Lessons Learned
- FIT SDK InputStream is `FITSwiftSDK.InputStream(data: Data)`, not Foundation's `InputStream(url:)`
- FIT SDK decode: `decoder.addMesgListener(listener)` then `decoder.read()` → `listener.fitMessages`
- TelemetryData properties are `public internal(set)` → tests cannot construct with custom sensor data; test intermediate types instead
- Cross-correlation normalization: dividing by overlap count (not signal length) allows small overlaps at periodic lags to produce falsely high scores
- Cross-correlation offset: must add base timestamp difference when resampled grids have different origins
- Periodic test signals are poor for cross-correlation testing — autocorrelation at period multiples creates ambiguity

## Phase 3 Stats
- **14 source files** created
- **11 test files** created
- **46 new tests** (148 total project)
- **0 failing tests**
- **Next phase**: Phase 4 (MVP UI)
