# GPMFSwiftSDK

A pure-Swift library for parsing GoPro **GPMF** (General Purpose Metadata Format)
telemetry from MP4 files. Extracts IMU, GPS, temperature, and orientation data as
typed, time-aligned Swift value types.

**Requirements:** macOS 13+ / iOS 15+ · Swift 6.0 · Foundation only (no external
dependencies)

---

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(path: "../modules/gpmf-Swift-SDK-inprogress"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: ["GPMFSwiftSDK"]
    ),
]
```

Or via Xcode: **File → Add Package Dependencies** → paste the repository URL.

---

## Quick Start

### Extract a single file

```swift
import GPMFSwiftSDK

let url = URL(fileURLWithPath: "/path/to/GX040246.MP4")
let telemetry = try GPMFExtractor.extract(from: url)

print("Device  : \(telemetry.deviceName ?? "unknown")")
print("Duration: \(telemetry.duration) s")
print("ACCL    : \(telemetry.accelReadings.count) samples")
print("GPS     : \(telemetry.gpsReadings.count) samples")

// Relative timing (authoritative)
for r in telemetry.accelReadings.prefix(5) {
    print("\(r.timestamp)s  x=\(r.xCam)  y=\(r.yCam)  z=\(r.zCam)")
}
```

### Stitch chapter files (same continuous recording, split at ~4 GB)

```swift
// GX010230.MP4, GX020230.MP4, GX030230.MP4 → unified timeline
let chapters = [url1, url2, url3]
let stitched = try ChapterStitcher.stitch(chapters)
// stitched.accelReadings spans the full recording, timestamps start at 0.0
```

### Group and extract a session directory

```swift
let allFiles: [URL] = try FileManager.default.contentsOfDirectory(
    at: sessionDir, includingPropertiesForKeys: nil
).filter { $0.pathExtension.uppercased() == "MP4" }

// Automatically groups by session ID, ignores non-GoPro files
let sessions = try SessionGrouper.extractAll(allFiles)
for session in sessions {
    print("\(session.group.prefix)\(session.group.sessionID): \(session.telemetry.duration) s")
}
```

---

## Stream Filtering

Extract only the sensors you need to reduce CPU and memory usage:

```swift
// GPS-only: skips 280k+ IMU readings at 200 Hz
let gps = try GPMFExtractor.extract(from: url, streams: StreamFilter(.gps5))

// IMU only
let imu = try GPMFExtractor.extract(from: url, streams: StreamFilter(.accl, .gyro))

// Propagates through stitcher and grouper
let s = try ChapterStitcher.stitch(chapters, streams: StreamFilter(.accl, .gps5))
```

Device metadata, absolute timestamps, and file duration are always extracted
regardless of the filter. Only the sensor reading arrays are filtered.

---

## Time-Based Queries

All reading types conform to `TimestampedReading`, enabling generic time slicing:

```swift
// Slice a 10-second window starting at t=60 s
let window = telemetry.accelReadings.inTimeRange(60.0...70.0)

// All GPS points within 2.5 s of the midpoint
let mid = telemetry.duration / 2
let burst = telemetry.gpsReadings.window(around: mid, radius: 2.5)

// Time span of the entire accelerometer series
if let span = telemetry.accelReadings.timeRange {
    print("ACCL covers \(span.lowerBound)…\(span.upperBound) s")
}
```

---

## Absolute Timestamps

GPMF exposes three independent absolute time sources. The SDK surfaces all of them
**without choosing** — each has known limitations:

```swift
// GPS-derived, ~1 Hz (GPS5/GPSU, ≤HERO10)
// firstGPSU is LEAST reliable (GPS may not have converged yet)
// lastGPSU  is MORE reliable  (more time for leap-second convergence)
if let last = telemetry.lastGPSU {
    print("Last GPSU: \(last.value) at t=\(last.relativeTime) s")
    // Back-compute: absoluteStart = parse(last.value) - last.relativeTime
}

// GPS-embedded, ms precision (GPS9, HERO11+)
if let last = telemetry.lastGPS9Time, let date = last.date {
    print("Last GPS9: \(date)")
}

// Camera RTC (NOT satellite — may be wrong if user never set the clock)
if let created = telemetry.mp4CreationTime {
    print("mp4 RTC  : \(created)")
}
```

> **Why first vs. last matters:** GPS receivers need up to ~10 minutes of continuous
> lock to receive the leap-second correction. Until converged, timestamps can be off
> by 2–15 seconds. The last observation has had the most convergence time.

---

## GPMF Camera Frame (ORIN)

All IMU data (`ACCL`, `GYRO`, `GRAV`) is remapped to the **GPMF Camera Frame**
via the camera's `ORIN` metadata string:

| Axis | Positive Direction |
|------|-------------------|
| `xCam` | Left (from rear of camera) |
| `yCam` | Into camera (toward lens) |
| `zCam` | Up |

A stationary, upright camera should show `zCam ≈ +9.81 m/s²` (gravity).

---

## Stream Metadata

Each extracted stream reports its GPMF sticky metadata:

```swift
for (key, info) in telemetry.streamInfo.sorted(by: { $0.key < $1.key }) {
    print("\(key): \(info.sampleCount) samples @ \(info.sampleRate, specifier: "%.1f") Hz"
          + " — \(info.name ?? "no name"), \(info.siUnit ?? "no unit")")
}
// ACCL: 140312 samples @ 197.1 Hz — Accelerometer, m/s²
// GYRO: 140312 samples @ 197.1 Hz — Gyroscope, rad/s
// GPS5:   7117 samples @  10.0 Hz — (no name), (no unit)
```

---

## Architecture

```
Sources/GPMFSwiftSDK/
├── GPMF.swift              Constants, GPMFKey enum, GPMFValueType enum
├── GPMFError.swift         Structured error enum
├── GpmfNode.swift          KLV tree node (Sendable struct)
├── InputStream.swift       Binary cursor over Data (Big Endian)
├── MP4TrackParser.swift    MP4 atom navigation, sample table
├── GPMFDecoder.swift       GPMF binary KLV decoder (all 17 types)
├── ORINMapper.swift        ORIN → GPMF Camera Frame remapping
├── GPMFExtractor.swift     High-level public API (single file)
├── ChapterStitcher.swift   Chapter stitching (~4 GB chapter splits)
├── SessionGrouper.swift    Multi-session grouping and extraction
└── TelemetryModels.swift   All output data types
```

**Layer separation:**
1. **Binary I/O** — `InputStream`, `MP4TrackParser`
2. **GPMF Decode** — `GPMFDecoder` (KLV → `GpmfNode` tree)
3. **Data Extraction** — `GPMFExtractor` (tree → typed `TelemetryData`)
4. **Axis Mapping** — `ORINMapper`
5. **Chapter Stitching** — `ChapterStitcher`
6. **Session Grouping** — `SessionGrouper`

---

## Supported Cameras

| Model | GPS | IMU Freq |
|-------|-----|----------|
| HERO5 | GPS5 + GPSU | 200/400 Hz |
| HERO6/7/8/9/10 | GPS5 + GPSU | 200/200 Hz |
| HERO11/13 | GPS9 (embedded time) | 200/200 Hz |
| HERO12 | No GPS | 200/200 Hz |
| Fusion | GPS5 + GPSU | 200/3200 Hz |

ORIN-based axis remapping is applied automatically on all cameras that include
the `ORIN` tag (HERO8+).

---

## Error Handling

```swift
do {
    let t = try GPMFExtractor.extract(from: url)
} catch GPMFError.noMetadataTrack {
    print("Not a GoPro MP4 or no GPMF track found")
} catch GPMFError.unrecognizedChapterFilename(let name) {
    print("Not a GoPro chapter filename: \(name)")
} catch {
    print("Unexpected error: \(error)")
}
```

See `GPMFError` for the full list of typed error cases.

---

## References

- [GoPro GPMF Parser & Spec](https://github.com/gopro/gpmf-parser)
- [GPMF Timing model](https://github.com/gopro/gpmf-parser/issues/131)
- [GPS9 format (HERO11+)](https://github.com/gopro/gpmf-parser/blob/main/README.md)
