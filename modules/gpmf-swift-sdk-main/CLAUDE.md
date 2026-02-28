# GPMFSwiftSDK — CLAUDE.md

## Project Overview

Swift Package (SPM) for parsing GoPro GPMF (General Purpose Metadata Format) telemetry from MP4 files. Sibling SDK to `fit-swift-sdk-main/` — both live under `modules/` and share architectural conventions.

**Scope:** Single-file MP4 parsing, chapter stitching (`ChapterStitcher`), and multi-session grouping (`SessionGrouper`). Cross-camera temporal alignment is the consuming application's responsibility.

## Build & Test

```bash
swift build                          # Compiles the library
swift test                           # Requires Xcode (not just Command Line Tools)
# If swift test fails with "no such module 'XCTest'":
sudo xcode-select -s /Volumes/WDSN770/Applications/Xcode.app/Contents/Developer
```

**Platforms:** macOS 13+, iOS 15+
**Swift:** 6.0 (supports language modes v5 and v6)
**Dependencies:** None (Foundation only)

## Architecture

```
Sources/GPMFSwiftSDK/
├── GPMF.swift              Constants, GPMFKey enum (FourCC), GPMFValueType enum
├── GPMFError.swift          Structured error enum
├── GpmfNode.swift           KLV tree node (struct, Sendable)
├── InputStream.swift        Binary cursor over Data (Big Endian)
├── MP4TrackParser.swift     MP4 atom navigation, sample table construction
├── GPMFDecoder.swift        GPMF binary KLV decoder (all 17 types)
├── ORINMapper.swift         ORIN channel→camera-axis remapping
├── GPMFExtractor.swift      High-level public API (single file)
├── ChapterStitcher.swift    Chapter stitching (same recording, split at ~4 GB)
├── SessionGrouper.swift     Multi-session grouping (multiple recordings → sorted groups)
└── TelemetryModels.swift    Output data models
```

### Layer Separation

1. **Binary I/O** — `InputStream` (cursor), `MP4TrackParser` (MP4 atoms)
2. **GPMF Decode** — `GPMFDecoder` (KLV → `GpmfNode` tree)
3. **Data Extraction** — `GPMFExtractor` (tree → typed `TelemetryData`)
4. **Axis Mapping** — `ORINMapper` (raw channels → GPMF Camera Frame)
5. **Chapter Stitching** — `ChapterStitcher` (multi-file → unified `TelemetryData`)
6. **Session Grouping** — `SessionGrouper` (mixed bag → organized `[SessionGroup]`)

## Conventions (aligned with FIT SDK)

- **Naming:** PascalCase types, lowerCamelCase properties/methods
- **Access:** `public internal(set)` for output model properties
- **Errors:** Single `GPMFError` enum (not nested per-class like FIT)
- **Concurrency:** Structs are `Sendable`. Classes are not `@Sendable` — caller controls threading
- **Tests:** XCTest (not Swift Testing), `@testable import`, method names: `test_what_whenCondition()`
- **No async/await** in the SDK — purely synchronous, like FIT SDK

---

## CRITICAL: Timing Model

### Relative Timing (authoritative)

All `timestamp` values in sensor readings are **relative to the start of the file** (0.0 = first sample). They are derived from:

**`stts` (Sample-To-Time table):**
- MP4 atom in `moov → trak → mdia → minf → stbl → stts`
- Contains pairs of `(sample_count, sample_delta)` where delta is in timescale units
- Defines the duration and position of each GPMF payload in the video timeline
- This is the **master clock** — GoPro's official documentation states:
  *"Timing and indexing for use existing methods stored within the wrapping MP4"*
  (Source: github.com/gopro/gpmf-parser/docs/README.md)

**`mdhd` (Media Header) timescale:**
- MP4 atom in `moov → trak → mdia → mdhd`
- Contains the timescale (ticks per second) used to convert `stts` deltas to real seconds
- v0: `[8 header][4 ver/flags][4 creation][4 modification][4 timescale][4 duration]`
- v1: `[8 header][4 ver/flags][8 creation][8 modification][4 timescale][8 duration]`

**`TSMP` (Total Sample Count):**
- GPMF tag found per-stream inside each payload
- Cumulative counter of all samples delivered for that stream since record start
- **NOT used for timestamp derivation** but critical for:
  - Computing the actual sample rate: compare TSMP between first and last payload,
    divide by total duration from stts
  - Detecting dropped/empty payloads (via EMPT tag)
  - Validating data completeness
- A 200 Hz sensor flushed at ~1 Hz intervals might produce payloads with
  199, 202, 201 samples — TSMP tracks the true cumulative count

**Within-payload interpolation:**
- Each payload has a start time and duration from `stts`
- Individual samples within the payload are linearly interpolated:
  `sample_time = payload_start + (sample_index / sample_count) * payload_duration`
- This is an approximation — actual sensor timing has jitter (RTOS scheduling)

### Absolute Timestamps (exposed raw — NO implicit assumptions)

The SDK exposes five independent absolute time fields **without choosing between them**. Each has known limitations documented here and in the code.

#### GPS Timestamp Convergence — Why First vs Last Matters

GPS receivers need up to ~10 minutes of continuous lock to receive the leap-second
correction message. Until corrected, timestamps can be off by 2–15 seconds. The
**first** GPS observation in a recording is therefore the least reliable; the **last**
is the most reliable. The SDK captures **both** as `GPSTimestampObservation` structs,
each paired with its `relativeTime` (position in the file timeline in seconds).

**Back-computing absolute start time** from the last observation:
```swift
// Most reliable approach for a recording where GPS converged
if let last = telemetry.lastGPSU {
    let absoluteStart = parse(last.value) - last.relativeTime
    // parse() converts "yymmddhhmmss.sss" → Date
}
```

This is the consuming app's responsibility — the SDK exposes the raw data and leaves
the choice of which observation to use (and how to parse it) to the caller.

#### 1. `firstGPSU` / `lastGPSU` — GPMF Tag (GPS5 cameras, ≤HERO10)

- **Type:** `GPSTimestampObservation?` — struct pairing `value: String` + `relativeTime: TimeInterval`
- **Source:** GPS satellite signal
- **Format:** `"yymmddhhmmss.sss"` (16-byte ASCII, type `'U'`)
- **Frequency:** ~1 Hz
- **Precision:** Low (seconds level)
- **Caveats:**
  - May be offset by ~2 seconds until the GPS receiver gets the leap-second
    correction message (needs ~10 minutes of continuous GPS lock to converge)
  - From factory or after long shutdown, the default leap-second offset is 15 seconds
    (from 2012 data); correction is permanently stored once received
  - **Ambiguous position in stream:** GPSU appears AFTER ACCL/GYRO data in the
    payload — it is unclear whether it timestamps the start or end of the data block
  - David Newman (GoPro) explicitly states: *"GPSU is not a precision time, is just
    a low frequency convenience if GPS UTC time is available, not required for timing"*
    (Source: github.com/gopro/gpmf-parser/issues/131)
  - `nil` if GPS had no fix or tag not present
  - **Obsolete on HERO11+** (replaced by GPS9 embedded time)
- **ChapterStitcher:** `lastGPSU.relativeTime` is offset by the cumulative chapter
  duration when stitching, so it always refers to position in the unified timeline.

#### 2. `firstGPS9Time` / `lastGPS9Time` — GPS9 Embedded Time (HERO11+)

- **Type:** `GPS9Timestamp?` — struct with `daysSince2000: UInt32`, `secondsSinceMidnight: Double`
- **Source:** GPS satellite signal
- **Format:** Millisecond precision
- **Fields in GPS9:** `[lat, lon, alt, speed2d, speed3d, daysSince2000, secsSinceMidnight_ms, DOP, fix]`
- **Caveats:**
  - Same leap-second convergence issue as GPSU on initial GPS lock
  - Only captured when fix ≥ 2D
  - HERO12 Black does NOT have GPS at all
  - `nil` if camera uses GPS5 format or GPS had no fix
- **StreamFilter note:** GPS9 timestamps (`firstGPS9Time`, `lastGPS9Time`) are always
  extracted even when `.gps9` is filtered out, because they are metadata, not sensor data.

#### 3. `mp4CreationTime` — mvhd Atom (Camera Internal RTC)

- **Source:** Camera's internal real-time clock (battery-backed RTC)
- **Location:** MP4 `moov → mvhd` atom, `creation_time` field
- **Format:** Seconds since 1904-01-01T00:00:00 UTC (MP4 epoch)
- **Precision:** 1 second
- **Caveats:**
  - **This is filesystem time, NOT satellite time**
  - Set by user manually, or synced via USB/GoPro Quik (minute resolution only)
  - Camera internal clock drifts throughout the day
  - May be arbitrarily wrong if the user never set the clock
  - This is what you typically see as the file's "creation date" in Finder/Explorer
  - `nil` if mvhd could not be parsed

### Why This Matters (historical context)

During development of the TypeScript GPMF parser, what was assumed to be "the GPS UTC timestamp" turned out to be the filesystem save-to-disk timestamp in some code paths, causing blocking temporal incoherences. This SDK avoids that trap by:

1. **Never choosing** a "canonical" absolute timestamp
2. **Documenting every source** with its origin and limitations
3. **Exposing first + last GPS observations** so the consuming app can use the most reliable
4. **Naming everything unambiguously** (`firstGPSU`, `lastGPSU`, `firstGPS9Time`, `lastGPS9Time`, `mp4CreationTime`)

---

## TimestampedReading Protocol

All five reading types (`SensorReading`, `GpsReading`, `OrientationReading`,
`TemperatureReading`, `ExposureReading`) conform to the `TimestampedReading` protocol,
enabling generic time-based operations on any reading array.

```swift
public protocol TimestampedReading: Sendable, Equatable {
    var timestamp: TimeInterval { get }
}
```

**Array extensions** (defined on `Array where Element: TimestampedReading`):

```swift
// Closed range (inclusive both ends)
let window = telemetry.accelReadings.inTimeRange(10.0...20.0)

// Half-open range (excludes upper bound)
let segment = telemetry.gpsReadings.inTimeRange(0.0..<60.0)

// Symmetric window around a point
let burst = telemetry.accelReadings.window(around: 35.5, radius: 0.5)

// Span of the entire array as a ClosedRange
if let span = telemetry.accelReadings.timeRange {
    print("Data covers \(span.lowerBound)…\(span.upperBound) s")
}
```

These methods use linear `filter` — O(n) — which is fine for single operations.
For repeated queries, build an index in the consuming application.

---

## StreamFilter (Selective Stream Extraction)

`StreamFilter` lets the consuming application extract only the sensor streams it needs,
avoiding the CPU and memory cost of parsing high-frequency streams that will be discarded.

```swift
public struct StreamFilter: Sendable, Equatable {
    public let keys: Set<GPMFKey>
    public init(keys: Set<GPMFKey>)
    public init(_ keys: GPMFKey...)   // variadic convenience
    public static let all: StreamFilter
    internal func shouldExtract(_ key: GPMFKey) -> Bool
}
```

**Usage:**
```swift
// GPS-only: skip IMU (skips 280k+ readings at 200 Hz)
let t = try GPMFExtractor.extract(from: url, streams: StreamFilter(.gps5))

// IMU only
let t = try GPMFExtractor.extract(from: url, streams: StreamFilter(.accl, .gyro))

// Propagates through stitcher and grouper
let s = try ChapterStitcher.stitch(urls, streams: StreamFilter(.accl, .gps5))
let all = try SessionGrouper.extractAll(urls, streams: StreamFilter(.accl))
```

**Always extracted regardless of filter** (device and timing metadata):
- Device: DVNM, DVID, ORIN, MINF, `cameraModel`, `deviceName`, `deviceID`
- GPS timing: `firstGPSU`, `lastGPSU`, `firstGPS9Time`, `lastGPS9Time`
- Container: `mp4CreationTime`, `duration`
- ChapterStitcher: `_tsmpByStream` (needed for TSMP coherence validation)
- Per-stream: SCAL, STNM, SIUN, UNIT sticky metadata

**GPS9 special case:** `firstGPS9Time`/`lastGPS9Time` are always captured even when
`.gps9` is filtered out, because `extractGPS9Readings` runs to extract the timestamps
but the resulting `GpsReading` array is discarded.

**`streamInfo` follows the filter:** Only streams with `effectiveCount > 0` appear in
`streamInfo`, so the map automatically reflects which streams were actually extracted.

---

## GPMF Camera Frame (ORIN)

All IMU data (ACCL, GYRO) is remapped to the **GPMF Camera Frame** via `ORINMapper`.

**Camera point of view:** Observer behind the camera, looking forward (same direction as lens).

| Axis | Positive Direction |
|------|-------------------|
| X_cam | Left |
| Y_cam | Into the camera (towards lens) |
| Z_cam | Up |

**ORIN string:** 3 characters, each mapping a raw channel to a camera axis.
- Position = channel index (0, 1, 2)
- Character = target axis (X, Y, Z)
- Case = sign (uppercase = positive, lowercase = negative)

Example: `ORIN = "ZXY"` → ch0→+Z_cam, ch1→+X_cam, ch2→+Y_cam

**Validation tests:**
- Gravity test: stationary upright camera → z_cam ≈ ±1g, x_cam ≈ 0, y_cam ≈ 0
- Rotation test: rotate camera left/right → signal on x_cam

See `IMU_Canonical_Spec_Axes&Frames.md` in the Notion workspace for the full spec.

---

## GPMF KLV Format Summary

All data is **Big Endian**, **32-bit aligned**.

**KLV Header (8 bytes):**
```
[Key: 4 bytes ASCII][Type: 1 byte][StructSize: 1 byte][Repeat: 2 bytes BE]
```

**Payload size** = StructSize × Repeat (padded to 4-byte boundary)

**Type byte = 0x00** → nested container (children are more KLV entries)

**Supported types:** `b`(int8), `B`(uint8), `c`(char), `d`(double), `f`(float), `F`(fourCC), `G`(guid), `j`(int64), `J`(uint64), `l`(int32), `L`(uint32), `q`(Q15.16), `Q`(Q31.32), `s`(int16), `S`(uint16), `U`(UTC date), `?`(complex via TYPE)

**SCAL (scaling):** Divisor applied to raw sensor values. Can be a single value (all axes) or one per axis/field. GPS5 typically has 5 SCAL values.

**Hierarchy:** `DEVC → STRM → {STNM, SCAL, SIUN, ORIN, ...sensor data}`

---

## MP4 Structure (GoPro)

GoPro MP4 files have at minimum 4 tracks:
1. `'vide'` — Video (H.264/HEVC)
2. `'soun'` — Audio (AAC)
3. `'tmcd'` — Timecode
4. `'meta'` — GPMF Telemetry (handler subtype `'meta'`, sample format `'gpmd'`)

**Atom path to GPMF data:**
```
moov → trak → mdia → hdlr(meta) → minf → stbl → {stsd(gpmd), stsz, stco/co64, stts, stsc}
```

**Key atoms parsed:**
- `stsz` — sample sizes (one per GPMF payload)
- `stco`/`co64` — chunk offsets (file byte positions)
- `stsc` — sample-to-chunk mapping (handles multi-sample chunks)
- `stts` — sample-to-time table (duration of each payload)
- `mdhd` — media header (timescale for stts conversion)
- `mvhd` — movie header (creation_time = camera RTC)

---

## Camera-Specific Notes

| Model | ACCL/GYRO order | ORIN | GPS format | Freq (ACCL/GYRO) |
|-------|----------------|------|------------|-------------------|
| HERO5 | Z,X,Y | varies | GPS5 + GPSU | 200/400 Hz |
| HERO6/7 | Y,-X,Z | varies | GPS5 + GPSU | 200/200 Hz |
| HERO8/9/10 | via ORIN | ZXY typical | GPS5 + GPSU | 200/200 Hz |
| HERO11 | via ORIN | varies | GPS9 (embedded time) | 200/200 Hz |
| HERO12 | via ORIN | varies | NO GPS | 200/200 Hz |
| HERO13 | via ORIN | varies | GPS9 (embedded time) | 200/200 Hz |
| Fusion | -Y,X,Z | varies | GPS5 + GPSU | 200/3200 Hz |

### HERO10 Companion TMPC in ACCL/GYRO STRMs

On HERO10 Black, the GPMF STRM structure differs from the naive expectation of
"one sensor per STRM". The ACCL and GYRO streams contain a **companion TMPC node**
(sensor chip temperature) alongside the primary sensor data:

```
STRM[2]: [STMP, TSMP, STNM="Accelerometer", ORIN, SIUN="m/s²", SCAL=100, TMPC, ACCL]
STRM[3]: [STMP, TSMP, STNM="Gyroscope",     ORIN, SIUN="rad/s", SCAL=xxx, TMPC, GYRO]
```

**Implications for the SDK:**

1. **Multi-sensor STRM detection:** `GPMFExtractor` uses `streamSensorKeys` (array of ALL
   sensor FourCCs in the STRM) instead of a single `primaryKey`. This correctly handles
   both single-sensor STRMs (HERO5-9, 11-13) and multi-sensor STRMs (HERO10).

2. **Metadata assignment:** STNM/SIUN/UNIT describe the STRM's **primary** sensor (the LAST
   sensor key in the children list, per GPMF's forward-looking metadata rule). The SDK
   assigns metadata only to `streamSensorKeys.last`, leaving companion sensors without
   inherited metadata from the host STRM.

3. **SCAL isolation (bug fix):** TMPC is always GPMF type `'f'` (32-bit float, already in °C).
   The STRM's SCAL applies to the primary sensor (ACCL/GYRO), NOT to TMPC. The SDK always
   passes `scales=[1.0]` to `extractTemperatureReadings` regardless of the STRM's SCAL.
   **Before this fix**, companion TMPC values were divided by ACCL's SCAL (~100-418),
   producing physically impossible temperatures (~0.13°C instead of ~54°C).

4. **Cross-camera compatibility:** On cameras where each sensor has its own dedicated STRM
   (HERO5-9, 11-13, Fusion), `streamSensorKeys` is a single-element array. The `.last`
   heuristic degenerates to "the only element" — identical to the old single-key approach.

---

## File Naming Convention (GoPro)

```
GX[CC][NNNN].MP4
   ^^  ^^^^
   |   Session ID (recording session)
   Chapter number (01, 02, ...)
```

- **Same NNNN, incrementing CC** = chapters of one continuous recording (split at ~4 GB)
- **Different NNNN** = separate recording sessions (may have temporal gaps)
- Chapter stitching and session management are **outside SDK scope**

---

## Known Bug (Fixed) — Misaligned Pointer

### Symptom
`Fatal error: load from misaligned raw pointer` crash on ARM64 when parsing real MP4 files.

### Root cause
`withUnsafeBytes { $0.load(as: UInt32.self) }` and `.load(as: UInt64.self)` require
natural alignment (4 / 8 bytes). MP4 atom fields and GPMF payloads sit at arbitrary byte
offsets inside their parent `Data` buffers, so the slice pointer is not guaranteed aligned.

### Fix
Replaced all `.load(as: T.self)` → `.loadUnaligned(as: T.self)` (Swift 5.7+) in:
- `InputStream.swift` — `readUInt16BE`, `readUInt32BE`, `readUInt64BE`
- `MP4TrackParser.swift` — `readUInt32BE`, `readUInt64BE`

The `InputStream` methods copy the bytes first (`Data(result)`) but the new `Data`
allocation is not guaranteed 4/8-byte aligned on all platforms, so `loadUnaligned` is
the correct choice even there.

---

## Integration Test Reference Output (GX040246.MP4)

**File:** `GX040246.MP4` — HERO10 Black, chapter 04, session 0246, 3.7 GB, 711.7 s.

```
Camera model    : (nil)               ← MINF absent on HERO10; use deviceName instead
Device name     : HERO10 Black        ← from DVNM
Device ID       : 1                   ← DVID at DEVC level
ORIN            : ZXY                 ← confirmed HERO8-10 typical value
Duration        : 711.711 s           ← 11 min 51 s
ACCL samples    : 140 312  (197.1 Hz) ← nominal 200 Hz, RTOS jitter normal
GYRO samples    : 140 312  (197.1 Hz) ← identical count = same flush cadence
GPS  samples    :   7 117  (10.0 Hz)  ← GPS5 @10 Hz
TMPC samples    :   1 422  ( 2.0 Hz)  ← temperature at 2 Hz (50–55°C sensor chip temp)
CORI samples    :  42 660  (59.9 Hz)  ← frame-rate quaternions (60 fps recording)
GRAV samples    :  42 660  (59.9 Hz)  ← gravity vector at frame rate
firstGPSU.value : 260224132546.600    ← yy-mm-dd hh:mm:ss.sss = 2026-02-24 13:25:46 UTC
firstGPSU.relT  :   ~0.5 s           ← offset from file start (first GPS payload)
lastGPSU.value  : 260224134458.800    ← 2026-02-24 13:44:58 UTC (19 min later)
lastGPSU.relT   : ~710.x s           ← near end of 711 s file
firstGPS9Time   : (nil)               ← correct — HERO10 uses GPS5+GPSU, not GPS9
lastGPS9Time    : (nil)               ← correct — same reason
mp4Created      : 2026-02-24 13:50:47 ← camera RTC; 25 min AFTER firstGPSU
StreamInfo      :                     ← per-stream metadata (STNM, SIUN, sample count/rate)
  ACCL : 140312 samples @ 197.1 Hz — name="Accelerometer", siUnit="m/s²"
  GYRO : 140312 samples @ 197.1 Hz — name="Gyroscope",     siUnit="rad/s"
  GPS5 :   7117 samples @  10.0 Hz — name=nil,              siUnit=nil
  TMPC :   1422 samples @   2.0 Hz — name=nil,              siUnit=nil
  CORI :  42660 samples @  59.9 Hz — name="CameraOrientation", siUnit=nil
  GRAV :  42660 samples @  59.9 Hz — name="GravityVector",     siUnit="m/s²"
```

**Gravity axis check (stationary moments):**
`mean |xCam|=1.43, |yCam|=1.41, |zCam|=9.86 m/s²` → `zCam ≈ g` confirms ORIN=ZXY is correct.

**Timestamp gap (firstGPSU vs mp4CreationTime):**
13:25:46 vs 13:50:47 = 25-minute difference. This is exactly the temporal-incoherence
risk documented in the timing model — RTC clock is NOT satellite time.

**lastGPSU back-computation:**
`parse(lastGPSU.value) - lastGPSU.relativeTime` ≈ 13:44:58 − 710 s ≈ 13:32:48 UTC.
Still offset from firstGPSU (13:25:46) by ~7 minutes — GPS likely had not fully
converged at the start of this chapter (chapter 04, started well into a session).

---

## ChapterStitcher Architecture

`ChapterStitcher` is a static-only struct in `ChapterStitcher.swift`. Public entry point:

```swift
let stitched = try ChapterStitcher.stitch([url1, url2, url3])
// Or with stream filter:
let stitched = try ChapterStitcher.stitch([url1, url2, url3], streams: StreamFilter(.accl, .gps5))
```

**Pipeline:**
1. Parse filenames — validates `[A-Z]{2}[0-9]{6}.MP4` format, same session ID, consecutive chapter numbers
2. Extract each chapter via `GPMFExtractor.extract(from:streams:)` (stream filter forwarded)
3. Validate TSMP coherence across each consecutive boundary (`curFirst > prevLast && gap < 200_000`)
4. Offset timestamps and concatenate all reading arrays into one `TelemetryData`
5. Propagate `lastGPSU` (with accumulated offset) and `lastGPS9Time` to final result

**TSMP on HERO10 — Important Finding:**
The ACCL and GYRO streams on HERO10 do **not** carry a TSMP tag in their STRM children.
Only GPS5, CORI, GRAV, and TMPC streams include TSMP on HERO10.
`ChapterStitcher` validates using whichever streams have TSMP — GPS5 at 10 Hz is sufficient to
detect any chapter boundary gap. This is camera-firmware specific and may differ on HERO11/HERO13.

**Error cases (`GPMFError`):**
- `unrecognizedChapterFilename(String)` — filename doesn't match GoPro pattern
- `mixedSessionIDs([String])` — different NNNN across files (different recordings)
- `nonConsecutiveChapters([Int])` — chapter numbers have gaps
- `tsmpIncoherence(stream:betweenChapters:)` — TSMP not monotonically increasing

**Test coverage:**
- 15 unit tests: `parseChapterInfo` (valid GX/GH/GL, edge cases, invalid formats)
- 6 validation tests: all error cases, validation before file I/O
- 14 integration tests: single-chapter stitch ≡ direct extract, TSMP presence and bounds,
  streamInfo propagation, deviceID preservation, firstGPSU/lastGPSU propagation

---

## SessionGrouper Architecture

`SessionGrouper` is a static-only struct in `SessionGrouper.swift`. It organizes an
unordered collection of GoPro MP4 files (potentially mixed with non-GoPro files) into
sorted session groups ready for extraction.

**Design principle: organizer, not gatekeeper.** `group()` never throws. Non-GoPro files
are silently skipped. The consuming app applies domain-specific filtering on the groups.

```swift
// Pure grouping (no file I/O)
let groups = SessionGrouper.group(allURLs)
let ghOnly = groups.filter { $0.prefix == "GH" }

// One-shot: group + stitch everything
let sessions = try SessionGrouper.extractAll(ghOnly.flatMap(\.chapterURLs))

// One-shot with stream filter
let sessions = try SessionGrouper.extractAll(urls, streams: StreamFilter(.accl, .gps5))
```

**Pipeline:**
1. Parse each filename via `ChapterStitcher.parseChapterInfo()` (reused, same module)
2. Silently skip non-GoPro files (`compactMap`)
3. Group by `(prefix, sessionID)` — different prefixes = different cameras/encodings
4. Sort chapters within each group by chapter number
5. Sort groups by prefix (alphabetical), then session ID (ascending)

**Sorting rationale:** Within the same prefix, GoPro increments session IDs chronologically
on the same SD card (1121 < 1122 < 1123 = chronological). Cross-prefix ordering requires
absolute timestamps and is the app's responsibility.

**Prefix finding:** The 2-letter prefix (GH, GX, GL) depends on firmware and video
settings, **NOT on camera model or encoding format**. Empirical evidence:
- GH011121.MP4 (`20251201 max/`) → HERO10 Black, GH prefix
- GX040246.MP4 (`TestData/`)      → HERO10 Black, GX prefix
- GX010230.MP4 (`20251211 mau/`)  → HERO10 Black, GX prefix
All three are HERO10 Black cameras, yet they use different prefixes. The SDK treats
the prefix as an opaque grouping key — it does NOT infer camera model or encoding format.

**Test coverage:**
- 13 unit tests: grouping, sorting, filtering, edge cases (no real files needed)
- 8 integration tests: real `20251201 max/` training session (5 GH sessions, 8 MP4 files,
  4 FIT files excluded, extraction of session 1121)
- 8 integration tests: real `20251211 mau/` training session (1 GX session, 5 chapters,
  prefix verification, multi-chapter stitching)

---

## TODO / Future Work

- [ ] TSMP-based sample rate computation (compare TSMP across payloads)
- [ ] TYPE complex structure parsing (`'?'` type with typedef)
- [ ] TICK/TOCK aperiodic timing support
- [ ] ISOG/SHUT exposure extraction
- [x] Integration tests with real GoPro .MP4 files — HERO10 validated ✓
- [x] Chapter stitching (`ChapterStitcher`) — implemented and tested ✓
- [x] Session grouping (`SessionGrouper`) — implemented and tested ✓
- [x] Multi-chapter integration test — 5-chapter stitch of GX session 0230 (`20251211 mau/`) ✓
- [x] StreamInfo per-stream metadata (STNM, SIUN, UNIT, sample count/rate) — implemented and tested ✓
- [x] DVID (Device ID) extraction and propagation through ChapterStitcher ✓
- [x] HERO10 companion TMPC SCAL bug fix — TMPC always `scales=[1.0]` ✓
- [x] GPS Timestamp Hardening — `firstGPSU`/`lastGPSU` as `GPSTimestampObservation?` with `relativeTime`, `firstGPS9Time`/`lastGPS9Time` ✓
- [x] `TimestampedReading` protocol — `inTimeRange`, `window`, `timeRange` Array extensions on all reading types ✓
- [x] `StreamFilter` — selective stream extraction forwarded through `GPMFExtractor`, `ChapterStitcher`, `SessionGrouper` ✓
- [x] Edge case tests — decoder robustness, empty payloads, zero SCAL, ORIN fallback ✓ (52 new tests across `GPMFDecoderBinaryEdgeCaseTests`, `GpmfNodeEdgeCaseTests`, `ORINMapperEdgeCaseTests`, `StreamFilterEdgeCaseTests`, `GPMFDecoderFuzzTests`)
- [x] Fuzz tests — GPMFDecoder with random binary input (deterministic xorshift64 seeds) ✓
- [x] DocC documentation catalog (`Sources/GPMFSwiftSDK/GPMFSwiftSDK.docc/`) ✓
- [x] README with SPM quick start and minimal example ✓
- [x] UNIT tag bug fix — `extractStreamMetadata` now handles `GPMFKey.unit` so `StreamInfo.displayUnit` is populated ✓
  - Regression suite: `UNITTagRegressionTests` (4 tests) verifies key constant and decode path
- [x] Dead `GPMFError` cases documented — `payloadTooSmall`, `unsupportedValueType`, `invalidORIN`, `missingStreamMetadata`, `readBeyondEnd` carry doc comments explaining current nil-returning behaviour and future intent ✓

**Total test count: 222 tests across 19 suites, 0 failures.**

---

## Key References

- GoPro GPMF Parser: https://github.com/gopro/gpmf-parser
- GPMF Spec: https://github.com/gopro/gpmf-parser/blob/main/docs/README.md
- GPSU timing issue: https://github.com/gopro/gpmf-parser/issues/6
- Telemetry clock clarification: https://github.com/gopro/gpmf-parser/issues/131
- GPS9 (HERO11+): https://github.com/gopro/gpmf-parser/blob/main/README.md
- ORIN spec: Notion workspace → `IMU_Canonical_Spec_Axes&Frames.md`
- GPMF tech manual: Notion workspace → `IMU_GPMF_Tech_Manual.md`
