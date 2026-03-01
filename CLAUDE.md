# CLAUDE.md - RowData Studio AI Assistant Guide

## Project Overview

**RowData Studio** (RDS) is a native Apple rowing performance analysis tool for macOS, iPadOS, and iOS. It integrates multi-camera video, high-frequency GoPro GPMF telemetry (IMU 200Hz, GPS 10-18Hz), biometric FIT data (NK SpeedCoach, Garmin, Apple Watch), and biomechanical force/angle data (NK Empower Oarlock CSV) in a unified reactive analysis environment with an infinite canvas interface ("Rowing Desk"). All processing happens on-device with no backend dependencies.

**Project Status:** Early development phase. Core Swift SDKs completed (GPMF parser, FIT parser). Application architecture defined (see `docs/`). Implementation in progress.

**Evolution:** This is the fourth iteration of the rowing analysis platform. Previous versions: Python v1-v2, TypeScript/React web (RowDataLab). Each iteration has refined domain understanding and architectural patterns.

## Quick Reference

```bash
# SDK Development (Swift Package Manager)
swift build                    # Build all targets
swift test                     # Run all tests
swift test --filter GPMFTests  # Run specific test suite

# When Xcode project exists:
# xcodebuild -scheme RowDataStudio -destination 'platform=macOS' build
# xcodebuild test -scheme RowDataStudio
```

**Documentation:** See `docs/RowDataStudio_Kickoff_Report_v1.md` for complete technical specifications.

## Tech Stack

| Layer              | Technology                                    |
|--------------------|-----------------------------------------------|
| Language           | Swift 6.0                                     |
| UI Framework       | SwiftUI (iOS 15+, macOS 12+) + UIKit/AppKit   |
| Video              | AVFoundation (playback, trim, export)         |
| Rendering          | SwiftUI Canvas API + Metal (via `.drawingGroup()`) |
| Signal Processing  | Accelerate framework (vDSP, BLAS)             |
| Concurrency        | Swift Structured Concurrency (`async`/`await`) |
| Observation        | Swift Observation (`@Observable`)             |
| Data Persistence   | SQLite (GRDB.swift), DuckDB (OLAP, planned)   |
| Testing            | Swift Testing framework + XCTest              |
| Module System      | Swift Package Manager (SPM)                   |

**No SwiftLint or SwiftFormat configured yet.** No CI/CD pipelines exist.

## Architecture

### Core Principles (from Vision Documents)

1. **Non-Destructive Editing** - Source files (MP4, FIT) never modified. All operations (trim, sync, annotation) are virtual references stored in SessionDocument.
2. **Structure of Arrays (SoA)** - High-frequency sensor data stored as `ContiguousArray<Float>` for cache efficiency and Accelerate/vDSP compatibility.
3. **Transform Pipelines** - Composable data transforms (ViewportCull → LTTBDownsample → AdaptiveSmooth) shared across all visualizations. Zero code duplication.
4. **Scale-Aware Processing** - Three temporal scales: HF (200Hz IMU), MF (1Hz FIT), LF (per-stroke aggregates).
5. **Video Sync Is Sacred** - Frame-accurate alignment between video, telemetry, and playhead maintained at all times.
6. **Offline-First** - Full functionality without network. On-device processing only.

### Visualization Architecture

**Reference:** `docs/Visualization_Architecture_Proposal.md`

**Recommended approach:** SwiftUI Canvas + Composable Transform Pipeline

```swift
// Reusable transform pipeline
TransformPipeline(stages: [
    ViewportCull(timeRange: viewport),
    LTTBDownsample(targetPoints: 2000),        // Largest-Triangle-Three-Buckets
    AdaptiveSmooth(zoomLevel: currentZoom)     // SMA/Gaussian/Savitzky-Golay
])

// SwiftUI Canvas rendering (automatic Metal via .drawingGroup())
Canvas { context, size in
    context.stroke(path, with: .color(config.color))
}
.drawingGroup()
```

### Data Architecture

**SessionDocument (Codable):**
- **metadata**: id, title, date, athletes, notes
- **sources**: DataSource[] (GoPro MP4, FIT files, sidecar telemetry, NK Empower CSV)
- **timeline**: duration, trimRange, tracks[] with temporal offsets
- **regions**: ROI[] (marked regions of interest)
- **canvas**: CanvasState (widget positions, layouts)
- **syncState**: Sync results from fusion engine
- **empowerData**: NKEmpowerSession? (optional, 13 biomechanical metrics per-stroke)
- **empowerSyncOffset**: TimeInterval? (GPS-based alignment with video)

**TelemetrySidecar (compressed JSON/MessagePack):**
- Generated during video triage (physical trim)
- Contains GPMF data extracted from trimmed time range
- Naming: `GX030230_trim_120s_385s.telemetry` (paired with `.mp4`)
- Size: ~2-3 MB for 5 minutes (vs ~300 MB video)

**In-Memory SoA Buffers:**
```swift
struct SensorDataBuffers {
    let size: Int                              // Total samples
    var timestamp: ContiguousArray<Double>     // Relative time (ms)
    var imu_raw_ts_acc_surge: ContiguousArray<Float>
    var imu_flt_ts_acc_surge: ContiguousArray<Float>  // Gaussian filtered
    var gps_gpmf_ts_speed: ContiguousArray<Float>
    var phys_ext_ts_hr: ContiguousArray<Float>        // From FIT
    var strokeIndex: ContiguousArray<Int32>           // Per-sample stroke number
    // ... 40+ channels total
}
```

### Synchronization Pipeline

**Reference:** `docs/RowDataStudio_Kickoff_Report_v1.md` § 7.2

Production-verified algorithms from RowDataLab v2.6.0:

**STEP 0: Tilt Bias Estimation**
- IMU surge axis includes gravity component due to camera tilt
- `tiltBias = avg(accelSurge) - (gpsSpeed[last] - gpsSpeed[first]) / duration`
- Applied to all ACCL samples before fusion

**STEP 1: GPMF Internal Alignment (SignMatchStrategy)**
- GPS has ~200-300ms lag vs IMU (receiver processing delay)
- Cross-correlate binarized slopes (±0.02 threshold) of GPS speed and integrated ACCL
- Search window: ±2500ms at 20ms resolution
- Acceptance threshold: score > 0.15

**STEP 2: GPMF ↔ Video Alignment**
- GPMF timestamps already relative to MP4 (from `stts` atom)
- Intrinsic alignment, offset = 0

**STEP 3: FIT ↔ GPMF Alignment**
- **Strategy A (GpsSpeedCorrelator):** Cross-correlate GPS speed series (1Hz resampled)
- **Strategy B (GpsTrackCorrelator):** Minimize Haversine distance between GPS tracks
- Both strategies executed and cross-validated
- High confidence if agreement <2s, else request user confirmation

### Fusion Engine

**Reference:** `docs/RowDataStudio_Kickoff_Report_v1.md` § 8.5

Six-step pipeline (rigorous order):
1. Tilt bias calculation
2. GPS-IMU auto-sync (SignMatch)
3. Physics prep (Gaussian smooth sigma=4)
4. Fusion loop (200Hz iteration with complementary filter α=0.999)
5. Stroke detection (state machine on detrended velocity)
6. Per-stroke aggregation (rate, distance, efficiency, power)

**Key Outputs:**
- `FusionResult.buffers`: SoA with 40+ channels
- `FusionResult.strokes`: Array of StrokeEvent
- `FusionResult.perStrokeMetrics`: Per-stroke statistics

## Directory Structure

```
RowDataStudio/                      # Root
├── docs/                           # Design documentation
│   ├── RowDataStudio_Kickoff_Report_v1.md
│   ├── Visualization_Architecture_Proposal.md
│   └── RowData_Vision_4_0_Proposal.md
├── modules/                        # Swift Package modules
│   ├── gpmf-swift-sdk-main/        # COMPLETED: GoPro GPMF parser (222 tests)
│   ├── fit-swift-sdk-main/         # COMPLETED: FIT file parser
│   └── csv-swift-sdk-main/         # TO CREATE: Generic CSV parser + profiles (NK Empower, Garmin, Peach, etc.)
│       ├── Sources/CSVSwiftSDK/
│       │   ├── CSVParser.swift     # Generic RFC 4180 CSV parser
│       │   └── Profiles/           # Vendor-specific parsers
│       │       ├── NKEmpowerProfile.swift
│       │       ├── NKSpeedCoachProfile.swift
│       │       ├── GarminProfile.swift
│       │       └── PeachPowerLineProfile.swift
│       └── Tests/
├── app/                            # Main application (TO CREATE)
│   ├── Core/
│   │   ├── Models/                 # SessionDocument, DataSource, ROI
│   │   ├── Persistence/            # GRDB integration, SessionStore
│   │   └── Services/               # FusionEngine, SyncEngine
│   ├── Rendering/
│   │   ├── Transforms/             # ViewportCull, LTTBDownsample, AdaptiveSmooth
│   │   ├── Widgets/                # 14+ widget types (LineChart, Map, Video, etc.)
│   │   └── PlayheadController.swift
│   ├── SignalProcessing/           # vDSP wrappers (port from RDL mathUtils)
│   │   ├── LTTB.swift
│   │   ├── GaussianSmooth.swift
│   │   ├── SavitzkyGolay.swift
│   │   └── StrokeDetection.swift
│   ├── UI/
│   │   ├── RowingDeskCanvas.swift  # Infinite canvas
│   │   ├── Timeline/
│   │   ├── VideoPlayer/
│   │   └── Inspector/
│   └── App.swift
└── CLAUDE.md                       # This file
```

## File Header Convention (MANDATORY)

Every Swift file must begin with a versioned docblock:

```swift
// Module/FileName.swift v1.0.0
/**
 * Brief description of the module.
 * --- Revision History ---
 * v1.0.0 - 2026-02-28 - Initial implementation.
 * v1.1.0 - 2026-03-01 - FEATURE: Added support for X.
 * v1.1.1 - 2026-03-02 - FIX: Corrected edge case in Y.
 */
```

**Category prefixes:** `ARCHITECTURE`, `FEATURE`, `REFACTOR`, `FIX`, `PERFORMANCE`, `CLEANUP`, `MAINTENANCE`

## Versioning Policy

App version tracked in `Info.plist` (CFBundleShortVersionString).
Semantic versioning: **X.Y.Z**
- **Z**: Patch/bugfix
- **Y**: New feature or algorithm
- **X**: Major (only on explicit instruction)

## Commit Message Convention

Conventional commits with lowercase type prefix:

```
feat: Add LTTB downsampling transform for charts
fix: Prevent GPS sync failure on missing GPSU timestamps
refactor: Extract stroke detection into separate module
docs: Update fusion engine architecture documentation
chore: Bump version to 0.2.0
test: Add integration tests for FusionEngine
```

## Code Conventions

### Swift Patterns

- **Property Wrappers**: `@Observable` for state, `@Environment` for shared context
- **Async/Await**: All I/O operations (file parsing, video loading) use structured concurrency
- **Result Types**: Use `Result<T, Error>` for operations that can fail
- **Codable**: All persistence models conform to `Codable`
- **Value Types**: Prefer `struct` over `class` unless reference semantics required
- **Type Safety**: Use enums with associated values for state machines (e.g., SyncState)

### Constants

Group constants in enum namespaces:

```swift
enum TimeConstants {
    static let garminEpochOffset: TimeInterval = 631065600
    static let msPerSecond: Double = 1000.0
    static let gpsuConvergenceThreshold: TimeInterval = 300.0
}
```

### Metric Nomenclature

Pattern: `[FAMILY]_[SOURCE]_[TYPE]_[NAME]_[MODIFIER]`

| Segment  | Values                              | Meaning                          |
|----------|-------------------------------------|----------------------------------|
| FAMILY   | `imu`, `gps`, `phys`, `mech`, `fus` | Physical domain                  |
| SOURCE   | `raw`, `gpmf`, `ext`, `cal`, `fus`  | Data source                      |
| TYPE     | `ts`, `str`, `evt`                  | Temporal domain (time-series, stroke, event) |
| NAME     | `acc`, `gyro`, `speed`, `hr`, `vel` | Physical quantity                |
| MODIFIER | `surge`, `sway`, `heave`, `peak`    | Axis or aggregation              |

**Examples:**
- `imu_raw_ts_acc_surge` - Raw IMU surge acceleration (time-series)
- `gps_gpmf_ts_speed` - GPS speed from GoPro GPMF
- `fus_cal_ts_vel_inertial` - Fused inertial velocity (IMU + GPS complementary filter)
- `mech_fus_str_rate` - Stroke rate (per-stroke metric from FusionEngine)
- `mech_ext_str_force_peak` - Peak oarlock force (per-stroke from NK Empower CSV)
- `mech_ext_str_angle_catch` - Catch angle in degrees (NK Empower CSV)
- `mech_ext_str_work` - Work per stroke in Joules (NK Empower CSV)

### File Output Nomenclature

Pattern: `RDS_[YYYYMMDD]_[HHMM]_[Description].ext`

Example: `RDS_20260228_1430_Session_Export.json`

## Testing

### Framework

- **Swift Testing** (primary): `@Test`, `@Suite`, `#expect()`
- **XCTest** (compatibility): For existing test suites in SDK modules

### Test Patterns

```swift
import Testing

@Suite("Fusion Engine")
struct FusionEngineTests {
    @Test("Tilt bias calculation with known data")
    func testTiltBiasCalculation() {
        let samples = createMockAccelSamples()
        let gpsSpeed = createMockGPSSpeed()

        let bias = FusionEngine.calculateTiltBias(samples, gpsSpeed)

        #expect(abs(bias - 0.15) < 0.01)  // Known good value ±0.01G
    }
}
```

**Conventions:**
- Factory helpers: `create*`, `mock*` prefix
- Constants: `MOCK_*` prefix
- Floating-point: Use `abs(a - b) < epsilon` or `#expect(a, accuracy: epsilon)`
- Snapshot testing: Consider `swift-snapshot-testing` for UI

### Coverage Targets

- **Core logic** (FusionEngine, SyncEngine, StrokeDetection): >90%
- **Signal processing** (LTTB, smoothing): >85%
- **UI widgets**: Snapshot tests for visual regression

## Safe Deprecation Protocol

When removing or superseding files:

1. **Hollow out** - Remove functional logic
2. **Annotate** - Add deprecation header with pointer to replacement
3. **Stub** - Leave minimal structure to prevent import breakage

```swift
// Legacy/OldModule.swift v2.0.0 (DEPRECATED)
/**
 * ⚠️ DEPRECATED: Use NewModule.swift instead.
 * This file is retained only for import compatibility.
 */
```

## Key Domain Context

- **Sport:** Competitive rowing (sweep, sculling)
- **Users:** Elite athletes, coaches, data engineers
- **Hardware:**
  - **Video/IMU/GPS:** GoPro HERO10+ (GPMF format @ 200Hz IMU, 10-18Hz GPS)
  - **Biometric:** NK SpeedCoach GPS 2, Garmin devices, Apple Watch (FIT format @ 1Hz)
  - **Biomechanical:** NK Empower Oarlock (CSV export, 13 per-stroke metrics @ 50Hz sampling)
- **Data Rates:** 200Hz IMU (ACCL/GYRO), 10-18Hz GPS, 1Hz FIT metrics, per-stroke Empower (LF)
- **Temporal Scales:** HF (200Hz), MF (1Hz), LF (per-stroke ~0.3-0.5 Hz)
- **Privacy:** All processing on-device, no cloud uploads
- **Storage:** SQLite for session metadata, DuckDB for OLAP analytics (planned)

## Signal Processing Library (to implement via Accelerate)

**Reference:** RowDataLab `common/mathUtils.ts` (mature, production-tested)

Priority functions to port:

| Function                       | Swift/Accelerate Implementation    |
|--------------------------------|------------------------------------|
| `detrend(signal, windowSize)`  | `vDSP.subtract` + rolling mean     |
| `gaussianSmooth(signal, sigma)`| `vDSP.convolve` with Gaussian kernel|
| `savitzkyGolay(window, order)` | Custom polynomial filter           |
| `zeroPhaseSmooth(signal, win)` | Forward + backward vDSP pass       |
| `calculateCorrelation(a, b)`   | `vDSP.crossCorrelation`            |
| `detectStrokes(vel, acc)`      | State machine (logic-heavy)        |
| `mean(values)`                 | `vDSP.mean`                        |
| `standardDeviation(values)`    | `vDSP.standardDeviation`           |

## Editing Guidelines for AI Assistants

1. **Read before editing** - Always use Read tool before modifying files
2. **Surgical edits** - Change only what is requested; preserve structure
3. **Increment version** - Update file header and revision history on every change
4. **Update app version** - When adding features, bump `Info.plist` version
5. **No placeholders** - Implement complete, working solutions (no TODOs or stubs)
6. **English only** - All code, comments, UI labels in English
7. **Respect architecture** - Follow Transform Pipeline, SoA, and separation of concerns
8. **Test critical logic** - Add tests for parsers, fusion, signal processing, metrics
9. **SwiftUI Canvas** - High-frequency visualization uses SwiftUI Canvas + `.drawingGroup()`, not manual Metal (unless profiling proves necessary)
10. **No feature creep** - Only implement explicit requirements

## Critical Files (when created)

| File                          | Purpose                                    |
|-------------------------------|--------------------------------------------|
| `app/Core/Models/SessionDocument.swift` | Main session data model |
| `app/Core/Services/FusionEngine.swift`  | Sensor fusion coordinator |
| `app/Rendering/PlayheadController.swift`| Global playhead state |
| `app/SignalProcessing/LTTB.swift`       | Downsampling algorithm |
| `app/UI/RowingDeskCanvas.swift`         | Infinite canvas UI |
| `modules/gpmf-swift-sdk-main/`          | GoPro GPMF parser |
| `modules/fit-swift-sdk-main/`           | FIT file parser |
| `modules/csv-swift-sdk-main/`           | Generic CSV parser + vendor profiles |
| `modules/csv-swift-sdk-main/Profiles/NKEmpowerProfile.swift` | NK Empower 13 biomechanical metrics |

## Important Notes

- **Platform targets:** macOS 12+, iOS 15+, iPadOS 15+
- **Minimum device:** iPhone 13 (A15 Bionic) for performance headroom
- **Video constraints:** AVFoundation Passthrough export does NOT preserve GPMF track (validated experimentally). Always generate sidecar during trim.
- **Multi-camera sync:** GPS back-computation provides ~1-5s precision (sufficient for rowing, not film production)
- **FIT timestamp reliability:** Garmin devices sync to NTP/GPS (medium-high reliability). NK SpeedCoach reliability varies.
- **NK Empower constraints:**
  - FIT files from SpeedCoach **DO NOT** contain Empower Oarlock data
  - CSV export from NK LiNK Logbook is the **only** source for force/angle metrics
  - 13 per-stroke metrics: catch/finish angles, slip, wash, force (peak/avg), power (peak/avg), work, stroke/effective length
  - Sync via GPS track correlation (same strategy as FIT ↔ GPMF alignment)

---

**For complete technical specifications, consult:**
- `docs/RowDataStudio_Kickoff_Report_v1.md` - Full architecture, sync algorithms, data models
- `docs/Visualization_Architecture_Proposal.md` - SwiftUI Canvas architecture, transform pipelines
- `docs/RowData_Vision_4_0_Proposal.md` - Strategic vision, roadmap, business model
- `docs/Empower_Oarlock_Integration_Proposal.md` - NK Empower CSV integration, parser implementation, biomechanical widgets
