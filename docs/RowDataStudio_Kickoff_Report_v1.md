# Project Kickoff Report v1.1

**Date:** 2026-02-27
**Author:** Mauro Sacca + Claude (Opus 4.6)
**Status:** DRAFT — integrated with RDL codebase v0.32.0 knowledge

**Changelog:**
- v1.0 (2026-02-27): Initial version from structured interview
- v1.1 (2026-02-27): Integration of algorithms, constants, architectural patterns from
  RowDataLab codebase analysis. Added sections 8.4-8.6 (nomenclature, FusionEngine, signal processing).
  Detailed synchronization pipeline (7.2). Added SoA pattern (6.4). Appendix C constants.
- v1.2 (2026-02-28): Section 8.2.1 rewritten. Refers to `Visualization_Architecture_Proposal.md`
  for modern greenfield Swift/SwiftUI architecture (vs RDL TypeScript patterns). Hybrid
  architecture: Composable SwiftUI Canvas + Transform Pipeline, eliminates code duplication.

---

## 1. Project Identity

### Name

The project evolves from **RowDataLab** (RDL), the existing TypeScript web app. For the new
Apple native incarnation, distinct identities are needed.

**Evaluated options:**

| Name | Acronym | Pros | Cons |
|------|-------|-----|--------|
| RowData Studio | RDS | Professional, evokes creative environment (like "Final Cut Studio"). Clear connection to RDL brand | "Studio" is a very common suffix |
| RowData Forge | RDF | Evokes transformation (raw data → insight). Unique, memorable | Less immediate for non-technical users |
| RowData Desk | RDD | Recalls the "Rowing Desk" (canvas) concept emerged in design. Evokes workstation | Could sound too "office" |
| Cadenza | — | Elegant, Italian, the cadence and rhythm of the stroke. Short, memorable, international | Loses the "data" connection in the name. Risk of confusion with music apps |
| Voga | — | Italian for "rowing/stroke". Short, distinctive, strong | Little recognized outside Italy |

**Recommendation:** A single name for the product, with pricing tiers (Free / Pro) instead
of separate names for MVP and extended version. Two names create brand confusion.

Suggestion: **Cadenza** as a consumer brand, **RowData Studio** as a professional/technical brand.
The final choice is the product owner's.

---

## 2. Executive Summary

A native Apple tool (macOS + iPadOS + iOS) for deep analysis of rowing sessions,
integrating video tracks (including multi-camera), GPMF telemetry data from
GoPro, and biometric/instrumental data from FIT files (NK SpeedCoach, Garmin, Apple Watch).

**Unique Value Proposition (USP):** No product on the market integrates multi-angle video,
high-frequency IMU (200Hz), GPS, and biometric data in a single interactive
analysis environment with an infinite canvas. Existing solutions (CrewNerd, NK LiNK, Strava) offer
only a subset of these capabilities, never integrated.

**This project is born from the fourth iteration** of a journey that has included two
Python versions and one TypeScript version. Each iteration has produced increasing quality and performance, and
above all, a mature understanding of domain issues. The lessons learned
(documented in Vision 3.0 and related Critical Analysis) directly inform the
architectural choices of this version.

---

## 3. Users and Personas

### Primary (MVP)

| Persona | Description | Platform | Main Need |
|---------|-------------|-------------|---------------------|
| **Advanced Athlete** | Evolved amateur or competitor analyzing their own sessions | iPad, Mac | Review video+data, identify technical issues in the movement |
| **Coach** | Club/federation coach with teams up to ~20 athletes | Mac (analysis), iPad (field) | Analyze multiple sessions, compare athletes, produce reports |

### Secondary (post-MVP)

| Persona | Description | Platform | Main Need |
|---------|-------------|-------------|---------------------|
| **In-boat Athlete** | Simplified module for real-time feedback during training | iPhone, Apple Watch | Live data equivalent to NK stroke counter / CrewNerd |
| **Field Coach** | Real-time remote monitoring from the motorboat | iPad, iPhone | HR, sync, power, live video of the crew |
| **Federal Technician** | Multi-session deep analysis over long periods | Mac | Technical progression over time, longitudinal comparisons |

---

## 4. Platform Strategy

### Technology choice: Native Swift (SwiftUI + UIKit/AppKit)

**Rationale verified during the interview:**

- **AVFoundation** — indispensable for video, only available natively
- **Metal/VideoToolbox** — high-performance canvas rendering, HW encoding
- **Hardware Integration** — Bluetooth LE for sensors, Apple Watch, GoPro WiFi
- **App Store** — natural distribution path for iOS/macOS
- **4K video performance** — impossible to achieve with cross-platform frameworks

**Alternatives considered and discarded:**

| Alternative | Reason for rejection |
|-------------|---------------------|
| Flutter/React Native | Insufficient video performance, no AVFoundation, no Metal |
| Electron | Excessive resource consumption for heavy video manipulation |
| Web app (as RDL) | Limits reached in the previous version — technical ceiling of the platform |

### Platform targets

| Platform | Priority | Role |
|-------------|----------|-------|
| **macOS** | MVP | Deep analysis, large screens, long work sessions |
| **iPadOS** | MVP | Field/office flexibility, touch for canvas |
| **iOS (iPhone)** | Post-MVP | In-boat athlete module, facilitated ingest |
| **watchOS** | Post-MVP | HR/movement acquisition, companion for boat module |

SwiftUI with multi-target (`#if os(macOS)` / `#if os(iOS)`) allows for a single codebase
with platform adaptations. Desktop and tablet UI share 90%+ of the code.

---

## 5. Product Definition

### MVP Tier — Simplified Flow

Corresponds to the features already implemented in RDL (TS), evolved in a native environment
with improved UX.

**IN SCOPE for MVP:**

1. **Manual Ingest** — import of MP4 (GoPro) and FIT (NK/Garmin/Apple Watch) files
2. **Full Parsing** — GPMF SDK (already developed), FIT SDK (already developed)
3. **Video Triage** — rapid review, ROI selection, physical trim + telemetry sidecar
4. **Multi-track Timeline** — independent tracks (video, audio, accl, gyro, gps, hr, cadence...)
5. **Semi-automatic Synchronization** — GPS-based with ACCL/Speed correction, visual confirmation
6. **Infinite Canvas ("Rowing Desk")** — positionable widgets (video, charts, map, metrics)
7. **Synchronized Playhead** — single temporal source of truth, all widgets react
8. **ROI (Region of Interest)** — marking, saving, navigating significant segments
9. **Comparison** — overlay and side-by-side curves across sessions/athletes/moments
10. **Export** — reports (PDF), video with HUD overlay, telemetry CSV, GPX path

**OUT OF SCOPE for MVP:**

- Real-time streaming (augmented flow)
- In-boat athlete module (iPhone/Watch)
- Remote coach monitoring
- Pose estimation / computer vision
- AI/LLM integration
- Digital twin / physiological models
- Cloud sync / sharing
- Multi-language (English only initially)

### PRO Tier — Augmented Flow (post-MVP)

- Direct acquisition from GoPro (if SDK available)
- Direct acquisition from Apple Watch (companion app)
- Real-time streaming boat iPhone → coach iPad
- Cloud storage for archive offload
- Longitudinal multi-session comparison
- Advanced stroke analysis algorithms

---

## 6. Data Architecture

### 6.1 Fundamental Principle: non-destructive editing

Source files (MP4, FIT) are never modified. Every operation (trim, sync,
annotation) is a virtual reference. Physical changes occur only in the
explicit "export/triage" phase to free up disk space.

### 6.2 The Session Document

Fundamental work unit. A JSON/Codable document describing an analysis session.

```
SessionDocument
├── metadata
│   ├── id: UUID
│   ├── title: String
│   ├── date: Date
│   ├── athletes: [Athlete]
│   └── notes: String
│
├── sources: [DataSource]
│   ├── DataSource(type: .goProVideo, url: URL, role: .primary)
│   ├── DataSource(type: .goProVideo, url: URL, role: .secondary)
│   ├── DataSource(type: .sidecar,    url: URL, linkedTo: sourceID)
│   ├── DataSource(type: .fitFile,    url: URL, device: "NK SpeedCoach")
│   └── DataSource(type: .fitFile,    url: URL, device: "Garmin 965")
│
├── timeline
│   ├── duration: TimeInterval
│   ├── absoluteOrigin: Date?          ← best-effort (from GPS back-computation)
│   ├── trimRange: ClosedRange<TimeInterval>?
│   └── tracks: [TrackReference]
│       ├── TrackRef(source: goProID, stream: .video,  offset: 0.0)
│       ├── TrackRef(source: goProID, stream: .audio,  offset: 0.0)
│       ├── TrackRef(source: sidecar, stream: .accl,   offset: 0.0)
│       ├── TrackRef(source: sidecar, stream: .gyro,   offset: 0.0)
│       ├── TrackRef(source: sidecar, stream: .gps,    offset: 0.0)
│       ├── TrackRef(source: sidecar, stream: .grav,   offset: 0.0)
│       ├── TrackRef(source: fitNK,   stream: .speed,  offset: -2.3)  ← sync offset
│       ├── TrackRef(source: fitNK,   stream: .hr,     offset: -2.3)
│       └── TrackRef(source: fitGarmin,stream: .hr,     offset: -1.8)
│
├── regions: [ROI]
│   ├── ROI(name: "Sprint 1000m", range: 120.0...385.0, tags: ["drill"])
│   ├── ROI(name: "Technical Error", range: 512.0...518.0, tags: ["issue"])
│   └── ROI(name: "Steady state", range: 600.0...900.0, tags: ["pace"])
│
├── canvas: CanvasState
│   ├── widgets: [Widget]             ← positions, sizes, config for each widget
│   └── layouts: [SavedLayout]        ← named recallable layouts
│
└── syncState
    ├── gpmfToVideo: SyncResult       ← result of ACCL↔GPS alignment
    ├── fitToVideo: [SyncResult]      ← result for each FIT file
    └── manualAdjustments: [Adjustment]
```

### 6.3 The Telemetry Sidecar Format

Generated during triage (physical video trim). Contains extracted GPMF data
for the selected time range.

**Format: Codable → compressed JSON (gzip) or MessagePack**

```swift
struct TelemetrySidecar: Codable, Sendable {
    // Identity
    let version: Int = 1
    let sourceFileHash: String           // SHA256 of original MP4 (for validation)
    let sourceFileName: String           // original name (e.g. "GX030230.MP4")

    // Timing
    let originalDuration: TimeInterval   // total duration of source file
    let trimRange: ClosedRange<TimeInterval>  // extracted range
    let absoluteOrigin: Date?            // best-effort (from GPS back-computation)

    // Device Metadata
    let deviceName: String?              // e.g. "HERO10 Black"
    let deviceID: UInt32?
    let orin: String?                    // e.g. "ZXY"

    // GPS timestamps (raw, for future synchronization)
    let firstGPSU: GPSTimestampObservation?
    let lastGPSU: GPSTimestampObservation?
    let firstGPS9Time: GPS9Timestamp?
    let lastGPS9Time: GPS9Timestamp?
    let mp4CreationTime: Date?

    // Stream info
    let streamInfo: [String: StreamInfoData]

    // Sensory data (timestamps already re-based to 0.0 = trim start)
    let accelReadings: [SensorReading]?
    let gyroReadings: [SensorReading]?
    let gpsReadings: [GpsReading]?
    let gravityReadings: [SensorReading]?
    let orientationReadings: [OrientationReading]?
    let temperatureReadings: [TemperatureReading]?
}
```

**Estimated sizes for a 5-minute trim (300s):**

| Stream | Freq | Samples | Bytes/sample | Total |
|--------|------|---------|--------------|--------|
| ACCL   | 200Hz | 60,000 | 32 (ts+xyz) | 1.9 MB |
| GYRO   | 200Hz | 60,000 | 32           | 1.9 MB |
| GPS    | 10Hz  | 3,000  | 48           | 0.1 MB |
| GRAV   | 60Hz  | 18,000 | 32           | 0.6 MB |
| CORI   | 60Hz  | 18,000 | 40           | 0.7 MB |
| **Total (JSON gzip)** | | | | **~2-3 MB** |

Comparison: the trimmed video for the same 5 minutes takes ~300 MB (HEVC) or ~600 MB (H.264).
The sidecar is negligible compared to the video (~1%).

**Naming convention:**
```
GX030230_trim_120s_385s.mp4           ← trimmed video
GX030230_trim_120s_385s.telemetry     ← telemetry sidecar
```

The pair (video + sidecar) is atomic: they are always created, moved, and deleted together.

### 6.4 In-Memory Data Model: Structure of Arrays (from RDL)

For high-performance analysis, sensory data in memory uses the
**Structure of Arrays (SoA)** pattern instead of the classic Array of Structs (AoS).

**Why SoA:**
- AoS: `[{t,ax,ay,az,gx,gy,gz,...}, {t,ax,ay,az,...}, ...]` → 40+ fields per object,
  iterating on a single field (e.g. all `ax`) jumps in memory → cache miss
- SoA: `{ timestamp: [t0,t1,...], ax: [v0,v1,...], ay: [...], ... }` → all `ax` values
  are contiguous → optimal cache line, SIMD-friendly

**RDL Implementation (TypedArray):**
```
SensorDataBuffers
├── size: Int                          // total samples (= ACCL frames, ~140k for 711s)
├── timestamp: Float64Array            // relative time in ms (Float64 for precision)
├── imu_raw_ts_acc_surge: Float32Array // ACCL surge axis corrected for tilt bias
├── imu_flt_ts_acc_surge: Float32Array // filtered ACCL (gaussian sigma=4)
├── imu_raw_ts_acc_sway: Float32Array  // ACCL sway axis
├── imu_raw_ts_acc_heave: Float32Array // ACCL heave axis
├── imu_raw_ts_gyro_pitch/roll/yaw: Float32Array
├── imu_raw_ts_grav_x/y/z: Float32Array
├── fus_cal_ts_pitch/roll: Float32Array      // from atan2 on gravity
├── fus_cal_ts_vel_inertial: Float32Array    // velocity from complementary filter
├── gps_gpmf_ts_lat/lon: Float64Array        // GPS (Float64 for coordinates)
├── gps_gpmf_ts_speed: Float32Array
├── phys_ext_ts_hr: Float32Array             // HR from FIT
├── mech_ext_ts_cadence/power: Float32Array  // from FIT
├── gps_ext_ts_speed: Float32Array           // speed from FIT
├── strokeIndex: Int32Array                  // stroke index per sample
├── strokePhase: Float32Array                // 0=recovery, 1=drive
├── mech_fus_str_rate/speed/power/...: Float32Array  // per-stroke metrics
└── dynamic: Map<String, Float32Array>       // custom developer FIT fields
```

**→ Swift Port:** `ContiguousArray<Float>` for Float32, `ContiguousArray<Double>` for Float64.
Or `UnsafeMutableBufferPointer<Float>` for zero-copy with Accelerate/vDSP.
NaN fields indicate "missing data" (GPS not synced, HR not available).

**PlaybackContext Pattern (from RDL):**
The playhead (temporal position) is an observable value that guides all UI updates.
In RDL: `PlaybackContext` with `currentTime`, `isPlaying`, `playbackRate`.
→ Validates our `@Observable TimeInterval` design.

Source RDL: `metrics/metrics-engine.ts`, `services/FusionEngine.ts`

### 6.5 Triage Workflow

```
                    INGEST                           TRIAGE                        ANALYSIS
                    ─────                            ──────                        ───────

SD Card GoPro ─→ Copy MP4 to disk ─→ Rapid review ─→ Mark ROI ─→ Export trim ─→ SessionDocument
                                         (2x/4x/8x)     (in/out)     ┌─ clip.mp4
FIT from NK ───→ Copy FIT to disk ─┐                               ├─ clip.telemetry
FIT from Watch ─→ Copy FIT to disk ─┤                               └─ original FIT (copy)
                                     │
                                     └─────────────────────────────────→ SessionDocument
                                                                        (uses trimmed files)

                    After confirmation:
                    Delete original MP4s ← frees up 27+ GB
                    Keep clips + sidecar + FIT ← ~3 GB
```

Critical steps in triage:

1. The app opens original MP4 files (GoPro chapters, potentially stitched)
2. Playback at accelerated speed with overlaid ACCL/Speed charts
3. User marks IN and OUT points for each ROI
4. For each ROI:
   a. `AVAssetExportSession` (Passthrough) → produces `clip.mp4` (video+audio)
   b. `GPMFExtractor` + temporal slice → produces `clip.telemetry` (sidecar)
5. Source files can be deleted

**Experimentally verified constraint (2026-02-27):**
AVFoundation Passthrough does not preserve the GPMF track. Test performed on GH011121.MP4
(HERO10, H.264) and GX040246.MP4 (HERO10, HEVC): the trimmed file contains only
video and audio tracks. The sidecar is therefore the only option.

---

## 7. Synchronization Model

### 7.1 Available Temporal Sources

| Source | Origin | Present in | Reliability | Use |
|----------|---------|-------------|--------------|-----|
| `stts` (sample timing) | MP4 atom | Video, GPMF | Authoritative for relative timing | Master clock for timeline |
| `GPSU` / `GPS9` | GPS satellite | GPMF | Medium (improves with convergence) | Absolute time, cross-device sync |
| `mp4CreationTime` | Camera RTC | MP4 mvhd | Low (drift, manual setting) | Fallback, approximate sorting |
| `tmcd` (timecode) | Camera RTC | MP4 tmcd track | Low (same clock as mp4Creation) | No use — redundant |
| FIT Timestamp | Device clock | FIT file | Medium-high (Garmin syncs NTP/GPS) | FIT↔Video sync |

**Experimentally verified (2026-02-27):** The `tmcd` track contains a single
frame number derived from the camera's RTC. It adds no information beyond
`mp4CreationTime`. It is not worth parsing.

### 7.2 Synchronization Pipeline (from RDL — production-verified algorithms)

The pipeline was developed and validated in RDL v2.6.0. Each step has specific
constants calibrated on real rowing data with GoPro HERO10, NK SpeedCoach, and Garmin.

```
STEP 0: Tilt Bias Estimation
  The IMU surge axis (Y) includes both kinematic acceleration and a static
  gravity component (projection due to camera tilt).
  Method:
    avgImuSurge = average(accelReadings.y)
    avgGpsAccel = (gpsSpeed[last] - gpsSpeed[first]) / session_duration
    tiltBiasMps2 = avgImuSurge - avgGpsAccel
    tiltBiasG = tiltBiasMps2 / 9.80665
  This correction is applied to all ACCL samples before fusion.
  Source RDL: services/FusionEngine.ts (STEP 0)

STEP 1: GPMF Internal Alignment (SignMatchStrategy)
  GPS has ~200-300ms lag compared to IMU due to receiver processing.
  Algorithm: Slope-Sign Consensus
    1. Find GPS speed peak → center analysis window (±20s)
    2. Resample GPS speed and integrated ACCL on uniform 20ms grid
    3. Smooth GPS with gaussianSmooth(sigma=8)
    4. Calculate slopes (delta between consecutive samples)
    5. Binarize slopes with ±0.02 threshold → sign vectors {-1, 0, +1}
    6. Cross-correlate binary vectors on ±2500ms window (125 steps)
    7. Score = sum of products (agreement) / count (non-zero pairs only)
    8. Accept if bestScore > 0.15 (consensus threshold)
  Verified constants:
    RESAMPLE_STEP = 20 ms
    WIN_SIZE_MS = 20000 (±20s around peak)
    MAX_LAG_MS = 2500 (search range)
    THRESHOLD = 0.15 (acceptance threshold)
    GPS_SMOOTHING = 8 (gaussian kernel)
    SLOPE_THRESHOLD = 0.02 (slope binarization)
  Output: lagMs (typically 100-400ms), applied to GPS readings
  Source RDL: services/sync/SignMatchStrategy.ts

STEP 2: GPMF ↔ Video Alignment
  GPMF timestamps are already relative to the MP4 file (derived from stts/mdhd)
  → intrinsic alignment, offset = 0. No calculation needed.

STEP 3: FIT ↔ GPMF Alignment (two complementary strategies)

  Strategy A — GpsSpeedCorrelator (speed cross-correlation):
    1. Extract GPS speed series from GPMF (speed3d, 10Hz)
    2. Extract GPS speed series from FIT (enhanced_speed, ~1Hz)
    3. Resample both at 1Hz with linear interpolation
    4. Normalize (mean=0, std=1)
    5. Cross-correlate normalized on ±300s window at 1s steps
    6. Find peak and second peak (minimum 30s separation)
    7. Confidence = peak/secondPeak (HIGH ≥2.5, MEDIUM ≥1.5, LOW <1.5)
  Verified constants:
    SEARCH_RANGE_MS = 300000 (±300s)
    RESAMPLE_STEP_MS = 1000 (1 Hz)
    MIN_PEAK_SEPARATION = 30000 (30s between peaks)
  Source RDL: services/sync/GpsSpeedCorrelator.ts

  Strategy B — GpsTrackCorrelator (Haversine distance minimization):
    1. Extract GPS positions from GPMF (lat/lon, 10Hz)
    2. Extract GPS positions from FIT (semicircles → degrees)
    3. Coarse phase: scan ±300s at 1s steps
       For each offset, calculate average Haversine distance between temporal pairs
    4. Fine phase: scan ±5s at 100ms steps around coarse minimum
    5. Confidence based on: absolute distance + improvement ratio vs offset=0
    6. Cross-validation: compare offset with Strategy A (CONSISTENT <2s, CLOSE <10s)
  Verified constants:
    COARSE_RANGE_MS = 300000, COARSE_STEP_MS = 1000
    FINE_RANGE_MS = 5000, FINE_STEP_MS = 100
    MAX_TIME_DIFF_MS = 2000 (tolerance for matching pairs)
  Source RDL: services/sync/GpsTrackCorrelator.ts

  Both strategies are executed and results cross-validated.
  If they agree (<2s difference) → HIGH confidence.
  If they disagree → request visual confirmation from the user.

  Fallback: manual alignment (drag on timeline) — never needed in RDL
  with real data, but always available as a safety net.

STEP 4: FIT Diagnostic Tools (validation, not synchronization)
  - FitGapAnalyzer: identifies temporal gaps in FIT records
  - FitKinematicAnalyzer: verifies kinematic consistency (speed, distance, cadence)
  - FitTrackGeometryAnalyzer: validates GPS track geometry (distances, bearing)
  Source RDL: services/sync/FitGapAnalyzer.ts, FitKinematicAnalyzer.ts, FitTrackGeometryAnalyzer.ts
```

### 7.3 Multi-camera Synchronization

Two GoPros (boat + motorboat) do not share any clock.

Best available method:
- GPS back-computation (`lastGPSU - relativeTime`) for each camera
- Offset is the difference between the two absolute origins
- Precision: ~1-5 seconds (limited by GPS convergence)
- Manual refinement on visual reference (oar entry splash, etc.)

This is an "good enough" alignment for multi-angle synchronization.
Frame precision is not necessary (it's not film production).

---

## 8. The Analysis Experience

### 8.1 Typical Workflow (from interview)

1. **Skip warm-up** — chapter 1 typically skipped
2. **Scan technical drills** — chapters 2-3, fast review
3. **Drill analysis** — heart of the session
    - ACCL + Speed + HR charts in the foreground
    - Synchronized video at the playhead
    - Identify anomalies: check, bounce, slowdowns
    - Correlate video gesture ↔ accelerometric signature
4. **ROI Marking** — 3-5 regions, 5-10 minutes total selected
5. **Comparison** — metric overlay between ROIs, sessions, athletes
6. **Export** — report + video with HUD for archive

**Typical time:** 30-40 minutes for 1 hour of training (with experience).

### 8.2 "Rowing Desk" Canvas

Evolution of the RDL Whiteboard. An infinite sheet (inspired by Apple Freeform)
where the user arranges widgets connected to the timeline.

**Planned widget types for MVP:**

| Widget | Description | Input |
|--------|-------------|-------|
| Video Player | Video frame with optional HUD overlay | Video track |
| Line Chart | Temporal line chart (ACCL, Speed, HR) | Any numerical track |
| Map | GPS map with track and current position | GPS track |
| Metric Card | Large instantaneous value (HR, Speed, Stroke Rate) | Any track |
| Comparison Overlay | Overlay of 2+ aligned curves | Multiple tracks |
| Table | Data table for ROI (mean, max, min, dev) | Tracks + ROI |

**Every widget:**
- Freely positionable and resizable (drag & drop)
- Connected to the global playhead
- Configurable (scale, color, unit, visible range)
- Activatable/deactivatable without deleting it

**Playhead interaction:**
- Scrub on any chart → updates all widgets
- Play/Pause on video → updates all widgets
- Click on map → updates all widgets
- The playhead is a single `@Observable TimeInterval`

#### 8.2.1 Visualization Architecture

**Reference**: [`Visualization_Architecture_Proposal.md`](Visualization_Architecture_Proposal.md)

RDL developed a mature visualization system with 14+ "Lens" types (widgets) that
validated key architectural patterns in production. These patterns (LTTB downsampling,
dual-layer rendering, viewport culling, adaptive smoothing) were confirmed as
necessary to handle 200Hz of data at 60fps.

**For RDS (greenfield Swift/SwiftUI project)**, a modern architectural proposal was developed that:

- **Does not replicate** the RDL Config → Transform → Render pattern (specific to TypeScript/web)
- **Leverages** the native Apple ecosystem (SwiftUI Canvas, Accelerate, automatic Metal)
- **Eliminates duplication** between widgets via Composable Transform Pipelines
- **Maintains validated patterns** (LTTB, dual-layer, viewport culling, adaptive smoothing)

**Recommended Architecture: SwiftUI Canvas + Hybrid Transform Pipeline**

```swift
// Reuseable Transform Pipeline across all widgets
TransformPipeline(stages: [
    ViewportCull(timeRange: viewport),      // Pattern from RDL
    LTTBDownsample(targetPoints: 2000),     // Pattern from RDL (Swift/Accelerate port)
    AdaptiveSmooth(zoomLevel: currentZoom)  // Pattern from RDL (SMA/Gaussian/Savitzky-Golay)
])

// Native SwiftUI rendering (automatic Metal-backed via .drawingGroup())
Canvas { context, size in
    context.stroke(path, with: .color(config.color))
}
.drawingGroup()
```

**Key benefits vs RDL pattern**:
- Zero code duplication (smoothing/LTTB written once, reused by 14+ widgets)
- Simpler testing (data transforms = pure functions)
- Automatic Metal (no custom shaders as hypothesized in kickoff v1.0)
- Superior maintainability (SwiftUI declarative code)

For full details, critical analysis, concrete Swift code, and verification plan,
consult the dedicated document.

### 8.3 Key Metrics (from interview)

**Indispensable:**
- Filtered ACCL (low-pass 4Hz) — stroke signature, check, bounce (surge, sway, heave)
- Speed (GPS + ACCL derivative) — speed trend, efficiency
- HR — cardiovascular load, thresholds
- Stroke Rate — stroke frequency (derived from ACCL + present in FIT files - Cadence/SPM)
- Stroke length — distance per stroke (present in FIT files - TotalDistance stroke n - Totaldistance Stroke n-1)

**Useful:**
- GYRO — rotations, hull roll
- Overlay comparisons — same metric at different times/sessions
- Per-stroke analysis (stroke segmentation) with aggregate statistics (stroke duration, stroke length, stroke rate, stroke power)

**To explore:**
- Alternative statistical representations (distribution, wavelet, spectral)

### 8.4 Metric Nomenclature System (from RDL)

RDL developed a formal naming system to manage 30+ derived metrics without ambiguity. This system should be brought into RDS as it avoids confusion between metrics with similar names but different sources (e.g. "speed" from GPS vs "speed" from FIT vs "velocity" from fusion).

**Pattern:** `[FAMILY]_[SOURCE]_[TYPE]_[NAME]_[MODIFIER]`

| Segment | Values | Meaning |
|----------|--------|-------------|
| FAMILY | `imu`, `gps`, `phys`, `mech`, `fus` | Physical domain of the metric |
| SOURCE | `raw`, `gpmf`, `ext`, `cal`, `fus` | Data source (raw=raw, ext=external/FIT, cal=calibrated, fus=fusion) |
| TYPE | `ts`, `str`, `evt` | Temporal domain (ts=time-series, str=per-stroke, evt=event) |
| NAME | `acc`, `gyro`, `speed`, `hr`, `vel`, ... | Physical quantity |
| MODIFIER | `surge`, `sway`, `heave`, `pitch`, `roll`, `yaw`, `peak`, `avg` | Axis or aggregation |

**Concrete examples from RDL:**

```
imu_raw_ts_acc_surge      → Raw accelerometer, surge axis (advancement), time-series
imu_flt_ts_acc_surge      → Filtered accelerometer, surge axis
gps_gpmf_ts_speed         → GPS speed from GoPro GPMF, time-series
gps_ext_ts_speed          → GPS speed from external FIT (NK/Garmin)
fus_cal_ts_vel_inertial   → IMU+GPS fusion velocity (complementary filter), calibrated
phys_ext_ts_hr            → Heart rate from external device (FIT)
mech_fus_str_rate         → Derived stroke rate, per-stroke aggregation
mech_fus_str_efficiency   → Efficiency index, per-stroke
```

**MetricDef interface (to bring into Swift as a Codable struct):**

```
MetricDef
├── id: String          // e.g. "imu_raw_ts_acc_surge"
├── name: String        // e.g. "Surge Acceleration"
├── source: String      // e.g. "imu"
├── unit: String?       // e.g. "m/s²", "bpm", "spm"
├── formula: String?    // e.g. "imu_raw_ts_acc_surge" (buffer reference)
├── requirements: [String]  // necessary dependencies
├── category: String    // e.g. "kinematics", "physiological"
├── recommendedSamplingHz: Double?
├── transforms: [MetricTransform]?  // optional pipeline (smooth, derive, ...)
└── aggregationMode: AggregationMode  // AVG, DELTA_INTERPOLATED, MAX, MIN, SNAPSHOT_NEAREST
```

Source RDL: `metrics/metrics-index.ts`, `metrics/metrics-engine.ts`

### 8.5 FusionEngine — Data Processing Pipeline (from RDL v2.6.0)

The computational heart of RDL. Transforms raw multi-source data into
analyzable buffers with derived metrics and stroke segmentation.

**Complete Pipeline (6 steps, rigorous order):**

```
Input: TelemetryData (GPMF) + ParsedFitData (FIT) + Config
                                     │
    STEP 0: Tilt Bias ──────────────┤  avgImuSurge - avgGpsAccel → bias in G
                                     │
    STEP 1: Auto-Sync ─────────────┤  SignMatchStrategy → lagMs (GPS→IMU offset)
                                     │
    STEP 1.5: Physics Prep ────────┤  ACCL_Y → G units - tiltBias, gaussian(sigma=4)
                                     │
    STEP 2: Fusion Loop ───────────┤  For each ACCL sample (200Hz):
            │                       │   a) Populate IMU raw/filtered
            │                       │   b) Interpolate GYRO, GRAV on ACCL timestamp
            │                       │   c) Calculate pitch/roll from gravity
            │                       │   d) Synchronize GPS (with applied lag)
            │                       │   e) Synchronize FIT records (HR, cadence, power)
            │                       │   f) Complementary Filter: vel = α·(vel + acc·dt) + (1-α)·gps_speed
            │                       │      with α = 0.999 (heavy IMU trust)
            │                       │
    STEP 3: Stroke Detection ──────┤  State machine on detrended velocity:
            │                       │   1. Smooth velocity (zero-phase, 15 samples)
            │                       │   2. Adaptive baseline (~6s window)
            │                       │   3. Detrend: velDet = smooth - baseline
            │                       │   4. Dynamic thresholds from P95/P05 (H_UP, H_DN, REARM)
            │                       │   5. State machine: SEEK_VALLEY → SEEK_PEAK → validate
            │                       │   6. Validation: swing ratio, timing, ACCL pattern
            │                       │
    STEP 4: Per-Stroke Aggregation ┤  For each detected stroke:
                                     │   strokeRate = 60000 / duration_ms (SPM)
                                     │   distance = speedAvg * duration_s
                                     │   efficiency = avg(speed / |totalAccMagnitude| + 0.1)
                                     │   + speedAvg, speedMax, powerAvg, accelPeak, accelMin
                                     │   + driveTime, recoveryTime, rhythmRatio
                                     │
Output: FusionResult
├── buffers: SensorDataBuffers     (SoA, 40+ channels Float32/Float64)
├── diagnostics: FusionDiagnostics (tiltBias, lagMs, syncConfidence)
├── strokes: [StrokeEvent]         (timestamps and indices for each stroke)
└── perStrokeMetrics: [PerStrokeStat]  (aggregate statistics per stroke)
```

**Key Data Models (to bring into Swift):**

```swift
// StrokeEvent — a single detected stroke
struct StrokeEvent {
    let index: Int
    let startTime: TimeInterval    // Catch (start of pull phase)
    let endTime: TimeInterval      // Next catch
    let duration: TimeInterval     // ms
    let startIdx: Int              // index in SoA buffer
    let endIdx: Int
    // Phase analysis
    var finishTime: TimeInterval?  // Finish pull / start recovery
    var driveDuration: TimeInterval?
    var recoveryDuration: TimeInterval?
    var rhythmRatio: Double?       // Drive / Total (typically 0.35-0.45)
}

// PerStrokeStat — aggregate statistics for a stroke
struct PerStrokeStat {
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
```

Source RDL: `services/FusionEngine.ts`, `common/mathUtils.ts`, `gpmf-utility/types.ts`

### 8.6 Signal Processing Library (to bring into Swift)

RDL has accumulated a mature library of signal processing functions in
`common/mathUtils.ts` (v3.4.0, ~1000 lines). These functions are the foundation
of all analysis and must be brought into Swift using the `Accelerate` framework
(vDSP) for native performance.

**Core Functions (MVP priority):**

| RDL Function | Description | Swift/Accelerate Equivalent |
|-------------|-------------|------------------------------|
| `detrend(signal, windowSize)` | Removes baseline (moving average) | `vDSP.subtract` + rolling mean |
| `integrate(values, dt)` | Cumulative integration (trap. rule) | Loop with `vDSP.add` |
| `derivative(values, dt)` | Numerical derivative (finite difference) | `vDSP.subtract` + scale |
| `gaussianSmooth(signal, sigma)` | Convolution with gaussian kernel | `vDSP.convolve` |
| `savitzkyGolay(signal, window, order)` | Polynomial filter (preserves derivatives) | Custom implementation |
| `simpleMovingAverage(signal, window)` | Simple moving average | `vDSP.slidingMean` |
| `exponentialMovingAverage(signal, alpha)` | EMA with decay | O(n) loop |
| `zeroPhaseSmooth(signal, halfWin)` | Forward+backward for zero phase shift | Two vDSP passes |
| `calculateCorrelation(a, b)` | Normalized cross-correlation | `vDSP.crossCorrelation` |

**Detection Functions (MVP priority):**

| RDL Function | Description | Notes for port |
|-------------|-------------|---------------|
| `detectStrokes(timestamps, vel, acc)` | Stroke detection state machine | Direct port, logic-heavy |
| `detectZeroCrossings(signal)` | Finds zero crossings | Simple loop |
| `detectLocalMinima(signal)` | Finds local minima | Loop with 3-point comparison |

**Statistical Functions:**

| RDL Function | Description | Swift Equivalent |
|-------------|-------------|-------------------|
| `mean(values)` | Arithmetic mean | `vDSP.mean` |
| `median(values)` | Median | Sort + middle index |
| `standardDeviation(values)` | Standard deviation | `vDSP.standardDeviation` |
| `getQuantile(sorted, q)` | Percentile (P5, P95, ...) | Interpolation on sorted array |

**Search and Interpolation Functions:**

| RDL Function | Description | Swift Equivalent |
|-------------|-------------|-------------------|
| `binarySearchFloor(arr, target)` | Index of value ≤ target | `Collection.partitioningIndex` |
| `interpolateAt(series, targetTime)` | Linear interpolation at arbitrary time | Direct port |
| `getNearestValue(series, time)` | Nearest value by timestamp | Binary search + comparison |

**Architectural Note:** In RDL these functions accept `NumericArray = number[] | Float32Array | Float64Array`.
In Swift, the equivalent pattern is to use generics with `AccelerateBuffer` protocol or `UnsafeBufferPointer<Float>`.
The `Accelerate` framework provides SIMD hardware acceleration on Apple Silicon.

Source RDL: `common/mathUtils.ts`

---

## 9. Module Map

```
RowingSuperApp/
├── modules/
│   ├── gpmf-swift-sdk/          ← COMPLETED (222 tests, 0 failures)
│   │   GPMFExtractor, ChapterStitcher, SessionGrouper, StreamFilter
│   │
│   ├── fit-swift-sdk/           ← COMPLETED (separate)
│   │   FIT file parsing
│   │
│   ├── video-engine/            ← TO DEVELOP (MVP)
│   │   AVFoundation wrapper: playback, trim, export, HUD overlay
│   │
│   ├── sync-engine/             ← TO DEVELOP (MVP)
│   │   RDL port: SignMatchStrategy (internal), GpsSpeedCorrelator +
│   │   GpsTrackCorrelator (external FIT↔GPMF), cross-validation
│   │
│   ├── sidecar/                 ← TO DEVELOP (MVP)
│   │   TelemetrySidecar: serialization, slicing, validation
│   │
│   ├── fusion-engine/           ← TO DEVELOP (MVP)
│   │   RDL FusionEngine v2.6.0 port: tilt bias, sync, complementary
│   │   filter, SoA buffers, stroke detection, per-stroke aggregation
│   │
│   ├── signal-processing/       ← TO DEVELOP (MVP)
│   │   RDL mathUtils.ts port via Accelerate/vDSP: detrend, gaussianSmooth,
│   │   savitzkyGolay, crossCorrelation, detectStrokes, detectZeroCrossings
│   │
```
