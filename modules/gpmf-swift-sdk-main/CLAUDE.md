# GPMFSwiftSDK -- CLAUDE.md

## Overview

Swift Package for parsing GoPro GPMF (General Purpose Metadata Format) telemetry from MP4 files. Single-file parsing, chapter stitching, and multi-session grouping. Cross-camera temporal alignment is the consuming application's responsibility.

**Platforms:** macOS 13+, iOS 15+ | **Swift:** 6.0 (modes v5, v6) | **Dependencies:** None
**Tests:** 222 XCTest across 19 suites | **Build:** `swift build` / `swift test`

## Architecture (6 layers)

1. **Binary I/O** -- `InputStream` (cursor), `MP4TrackParser` (atom navigation)
2. **GPMF Decode** -- `GPMFDecoder` (KLV binary -> `GpmfNode` tree)
3. **Data Extraction** -- `GPMFExtractor` (tree -> typed `TelemetryData`)
4. **Axis Mapping** -- `ORINMapper` (raw channels -> GPMF Camera Frame via ORIN string)
5. **Chapter Stitching** -- `ChapterStitcher` (multi-chapter -> unified `TelemetryData`)
6. **Session Grouping** -- `SessionGrouper` (mixed files -> organized `[SessionGroup]`)

All public types are `Sendable`. The SDK is purely synchronous (no async/await). Entry points are static methods: `GPMFExtractor.extract(from:streams:)`, `ChapterStitcher.stitch(_:streams:)`, `SessionGrouper.group(_:)`.

---

## CRITICAL: Timing Model

### Relative Timing (authoritative)

All `timestamp` values are **relative to file start** (0.0 = first sample), derived from:

- **`stts`** (Sample-To-Time table): MP4 atom defining duration/position of each GPMF payload in the video timeline. This is the **master clock** per GoPro's specification.
- **`mdhd`** (Media Header): Contains the timescale (ticks/second) for converting `stts` deltas to seconds.
- **`TSMP`** (Total Sample Count): Cumulative per-stream counter. Not used for timestamps, but critical for sample rate computation, dropped-payload detection, and chapter-boundary validation.
- **Within-payload interpolation**: Samples linearly interpolated: `sample_time = payload_start + (index / count) * payload_duration`. Approximation -- actual sensor timing has RTOS jitter.

### Absolute Timestamps (exposed raw, NO implicit assumptions)

The SDK exposes five independent absolute time fields **without choosing between them**. The consuming app decides which to use.

**GPS Convergence Warning:** GPS receivers need up to ~10 minutes for leap-second correction. First observation is least reliable; last is most reliable. Both are captured as `GPSTimestampObservation` paired with their `relativeTime`.

**Back-computing absolute start:** `parse(lastGPSU.value) - lastGPSU.relativeTime` (most reliable approach).

| Field | Source | Format | Precision | Caveats |
|-------|--------|--------|-----------|---------|
| `firstGPSU` / `lastGPSU` | GPS satellite (GPMF `'U'` tag) | `"yymmddhhmmss.sss"` | Seconds | Leap-second offset until converged; obsolete on HERO11+ |
| `firstGPS9Time` / `lastGPS9Time` | GPS satellite (GPS9 embedded) | `daysSince2000` + `secsSinceMidnight` | Milliseconds | HERO11+ only; nil on GPS5 cameras; HERO12 has no GPS |
| `mp4CreationTime` | Camera RTC (`mvhd` atom) | Seconds since 1904-01-01 | 1 second | Filesystem time, NOT satellite; may drift or be unset |

**Why this matters:** During TypeScript parser development, assuming "GPS UTC timestamp" when the code actually read the RTC timestamp caused blocking temporal incoherences. This SDK avoids that by never choosing a canonical absolute timestamp, documenting every source, and naming fields unambiguously.

---

## GPMF Camera Frame (ORIN)

All IMU data (ACCL, GYRO) is remapped to the GPMF Camera Frame via `ORINMapper`.

**Camera POV:** Observer behind camera, looking through lens.
- **X_cam** = Left | **Y_cam** = Into camera (towards lens) | **Z_cam** = Up

**ORIN string:** 3 characters mapping raw channels to camera axes. Position = channel index, character = target axis (X/Y/Z), case = sign (upper = positive). Example: `"ZXY"` -> ch0=+Z, ch1=+X, ch2=+Y.

**Validation:** Stationary upright camera -> z_cam ~= +/-1g, x/y ~= 0.

---

## Camera-Specific Notes

| Model | ORIN | GPS format | ACCL/GYRO Hz | Notes |
|-------|------|------------|-------------|-------|
| HERO5 | varies | GPS5 + GPSU | 200/400 | Legacy axis order Z,X,Y |
| HERO6/7 | varies | GPS5 + GPSU | 200/200 | Axis order Y,-X,Z |
| HERO8/9/10 | ZXY typical | GPS5 + GPSU | 200/200 | Standard ORIN-based mapping |
| HERO11 | varies | GPS9 (ms precision) | 200/200 | First with embedded GPS time |
| HERO12 | varies | **NO GPS** | 200/200 | GPS hardware removed |
| HERO13 | varies | GPS9 | 200/200 | GPS restored |
| Fusion | varies | GPS5 + GPSU | 200/3200 | GYRO at 3200 Hz |

### HERO10 Companion TMPC Bug (Fixed)

HERO10 ACCL/GYRO STRMs contain a companion TMPC (temperature) node alongside the primary sensor. Key implications:

- `GPMFExtractor` uses `streamSensorKeys` array (not single key) to handle multi-sensor STRMs
- SCAL applies only to the primary sensor (ACCL/GYRO), NOT to TMPC. SDK forces `scales=[1.0]` for temperature. Before this fix, TMPC values were divided by ACCL's SCAL (~100), producing ~0.13C instead of ~54C.
- On single-sensor cameras (HERO5-9, 11-13), this degenerates to single-element array -- backward compatible.

---

## KLV Format Summary

All data: **Big Endian**, **32-bit aligned**.

**Header (8 bytes):** `[Key: 4B ASCII][Type: 1B][StructSize: 1B][Repeat: 2B BE]`
**Payload:** StructSize x Repeat bytes (padded to 4-byte boundary)
**Type 0x00:** Nested container (children are more KLV entries)
**Hierarchy:** `DEVC -> STRM -> {STNM, SCAL, SIUN, ORIN, ...sensor data}`
**SCAL:** Divisor for raw sensor values. Single value (all axes) or one per field.

---

## ChapterStitcher

Static API: `ChapterStitcher.stitch([url1, url2, url3], streams:)`

**Pipeline:** Parse filenames (validates GoPro pattern, same session, consecutive chapters) -> extract each chapter -> validate TSMP coherence across boundaries -> offset timestamps and concatenate -> propagate lastGPSU/lastGPS9Time with accumulated offset.

**HERO10 note:** ACCL/GYRO STRMs lack TSMP tags on HERO10. Validation uses GPS5 (10Hz) which is sufficient for gap detection. Camera-firmware specific.

**Errors:** `unrecognizedChapterFilename`, `mixedSessionIDs`, `nonConsecutiveChapters`, `tsmpIncoherence`

## SessionGrouper

Static API: `SessionGrouper.group(urls)` (pure grouping, no I/O, never throws)

**Pipeline:** Parse filenames -> skip non-GoPro files -> group by (prefix, sessionID) -> sort chapters within group -> sort groups by prefix then sessionID.

**Prefix note:** The 2-letter prefix (GH/GX/GL) depends on firmware settings, NOT camera model. Same HERO10 may produce GH or GX files. Prefix is an opaque grouping key.

## StreamFilter

`StreamFilter` enables selective extraction, skipping high-frequency streams (e.g., skip 280k+ IMU readings when only GPS is needed). Propagates through all entry points.

**Always extracted regardless of filter:** Device metadata (DVNM, DVID, ORIN), GPS timestamps (firstGPSU/lastGPSU/firstGPS9Time/lastGPS9Time), container metadata (mp4CreationTime, duration), per-stream SCAL/STNM/SIUN.

## Known Bug (Fixed): Misaligned Pointer

ARM64 crash from `.load(as: UInt32.self)` on unaligned MP4/GPMF data. Fix: all `.load()` replaced with `.loadUnaligned()` (Swift 5.7+) in `InputStream.swift` and `MP4TrackParser.swift`.

## Open Work

- [ ] TSMP-based sample rate computation (compare TSMP across payloads)
- [ ] TYPE complex structure parsing (`'?'` type with typedef)
- [ ] TICK/TOCK aperiodic timing support

## References

- [GPMF Parser](https://github.com/gopro/gpmf-parser) | [Spec](https://github.com/gopro/gpmf-parser/blob/main/docs/README.md)
- [GPSU timing issue #6](https://github.com/gopro/gpmf-parser/issues/6) | [Clock clarification #131](https://github.com/gopro/gpmf-parser/issues/131)
