# Data Models Specification

**Status:** Canonical executable spec
**Source:** Kickoff Report v1.2, Sections 6.2-6.4 and 8.4

---

## Fundamental Principle: Non-Destructive Editing

Source files (MP4, FIT, CSV) are never modified. Every operation (trim, sync, annotation) is a
virtual reference. Physical changes occur only in the explicit "export/triage" phase to free disk space.

---

## SessionDocument (Codable)

The fundamental work unit. A JSON/Codable document describing an analysis session.

```text
SessionDocument
|-- metadata
|   |-- id: UUID
|   |-- title: String
|   |-- date: Date
|   |-- athletes: [Athlete]
|   +-- notes: String
|
|-- sources: [DataSource]
|   |-- DataSource(type: .goProVideo, url: URL, role: .primary)
|   |-- DataSource(type: .goProVideo, url: URL, role: .secondary)
|   |-- DataSource(type: .sidecar,    url: URL, linkedTo: sourceID)
|   |-- DataSource(type: .fitFile,    url: URL, device: "NK SpeedCoach")
|   |-- DataSource(type: .csvFile,    url: URL, device: "NK Empower")
|   +-- DataSource(type: .fitFile,    url: URL, device: "Garmin 965")
|
|-- timeline
|   |-- duration: TimeInterval
|   |-- absoluteOrigin: Date?          <-- best-effort (GPS back-computation)
|   |-- trimRange: ClosedRange<TimeInterval>?
|   +-- tracks: [TrackReference]
|       |-- TrackRef(source: goProID, stream: .video,  offset: 0.0)
|       |-- TrackRef(source: goProID, stream: .audio,  offset: 0.0)
|       |-- TrackRef(source: sidecar, stream: .accl,   offset: 0.0)
|       |-- TrackRef(source: sidecar, stream: .gyro,   offset: 0.0)
|       |-- TrackRef(source: sidecar, stream: .gps,    offset: 0.0)
|       |-- TrackRef(source: fitNK,   stream: .speed,  offset: -2.3)  <-- sync offset
|       +-- TrackRef(source: fitNK,   stream: .hr,     offset: -2.3)
|
|-- regions: [ROI]
|   |-- ROI(name: "Sprint 1000m", range: 120.0...385.0, tags: ["drill"])
|   |-- ROI(name: "Technical Error", range: 512.0...518.0, tags: ["issue"])
|   +-- ROI(name: "Steady state", range: 600.0...900.0, tags: ["pace"])
|
|-- canvas: CanvasState
|   |-- widgets: [Widget]             <-- positions, sizes, config per widget
|   +-- layouts: [SavedLayout]        <-- named recallable layouts
|
|-- empowerData: NKEmpowerSession?    <-- optional, from CSV SDK
|-- empowerSyncOffset: TimeInterval?  <-- GPS-based alignment with video
|
+-- syncState
    |-- gpmfToVideo: SyncResult       <-- result of ACCL-GPS alignment
    |-- fitToVideo: [SyncResult]      <-- result for each FIT file
    +-- manualAdjustments: [Adjustment]
```

---

## TelemetrySidecar (Codable)

Generated during triage (physical video trim). Contains extracted GPMF data for the selected time range.

**Format:** Codable -> compressed JSON (gzip) or MessagePack

```swift
struct TelemetrySidecar: Codable, Sendable {
    // Identity
    let version: Int = 1
    let sourceFileHash: String           // SHA256 of original MP4
    let sourceFileName: String           // e.g. "GX030230.MP4"

    // Timing
    let originalDuration: TimeInterval
    let trimRange: ClosedRange<TimeInterval>
    let absoluteOrigin: Date?            // GPS back-computation

    // Device Metadata
    let deviceName: String?              // e.g. "HERO10 Black"
    let deviceID: UInt32?
    let orin: String?                    // e.g. "ZXY"

    // GPS timestamps (raw, for synchronization)
    let firstGPSU: GPSTimestampObservation?
    let lastGPSU: GPSTimestampObservation?
    let firstGPS9Time: GPS9Timestamp?
    let lastGPS9Time: GPS9Timestamp?
    let mp4CreationTime: Date?

    // Stream info
    let streamInfo: [String: StreamInfoData]

    // Sensor data (timestamps re-based to 0.0 = trim start)
    let accelReadings: [SensorReading]?
    let gyroReadings: [SensorReading]?
    let gpsReadings: [GpsReading]?
    let gravityReadings: [SensorReading]?
    let orientationReadings: [OrientationReading]?
    let temperatureReadings: [TemperatureReading]?
}
```

**Size Estimates (5-minute trim, 300s):**

| Stream | Freq | Samples | Bytes/sample | Total |
| ------ | ---- | ------- | ------------ | ----- |
| ACCL | 200Hz | 60,000 | 32 | 1.9 MB |
| GYRO | 200Hz | 60,000 | 32 | 1.9 MB |
| GPS | 10Hz | 3,000 | 48 | 0.1 MB |
| GRAV | 60Hz | 18,000 | 32 | 0.6 MB |
| CORI | 60Hz | 18,000 | 40 | 0.7 MB |
| **Total (JSON gzip)** | | | | **~2-3 MB** |

Comparison: trimmed video = ~300 MB (HEVC). Sidecar is ~1% of video size.

**Naming Convention:**

```text
GX030230_trim_120s_385s.mp4           <-- trimmed video
GX030230_trim_120s_385s.telemetry     <-- telemetry sidecar
```

The pair (video + sidecar) is atomic: always created, moved, and deleted together.

---

## In-Memory SoA Buffers

For high-performance analysis, sensor data in memory uses **Structure of Arrays (SoA)** instead of Array of Structs (AoS).

**Why SoA:**

- AoS: iterating on one field (e.g. all acc_x) causes cache misses (jumps over 40+ fields per struct)
- SoA: all values of one field are contiguous -> optimal cache line, SIMD-friendly, Accelerate-compatible

```text
SensorDataBuffers
|-- size: Int                              // total samples (~140k for 711s)
|-- timestamp: ContiguousArray<Double>     // relative time in ms (Float64)
|-- imu_raw_ts_acc_surge: ContiguousArray<Float>
|-- imu_flt_ts_acc_surge: ContiguousArray<Float>   // gaussian(sigma=4)
|-- imu_raw_ts_acc_sway: ContiguousArray<Float>
|-- imu_raw_ts_acc_heave: ContiguousArray<Float>
|-- imu_raw_ts_gyro_pitch/roll/yaw: ContiguousArray<Float>
|-- imu_raw_ts_grav_x/y/z: ContiguousArray<Float>
|-- fus_cal_ts_pitch/roll: ContiguousArray<Float>   // from atan2 on gravity
|-- fus_cal_ts_vel_inertial: ContiguousArray<Float> // complementary filter
|-- gps_gpmf_ts_lat/lon: ContiguousArray<Double>    // Float64 for coordinates
|-- gps_gpmf_ts_speed: ContiguousArray<Float>
|-- phys_ext_ts_hr: ContiguousArray<Float>           // HR from FIT
|-- mech_ext_ts_cadence/power: ContiguousArray<Float>
|-- gps_ext_ts_speed: ContiguousArray<Float>         // speed from FIT
|-- strokeIndex: ContiguousArray<Int32>              // stroke index per sample
|-- strokePhase: ContiguousArray<Float>              // 0=recovery, 1=drive
+-- dynamic: [String: ContiguousArray<Float>]        // custom fields
```

**NaN convention:** NaN indicates "missing data" (GPS not synced, HR not available).

**Swift types:** `ContiguousArray<Float>` for Float32, `ContiguousArray<Double>` for Float64. Use `UnsafeMutableBufferPointer<Float>` for zero-copy Accelerate/vDSP operations.

---

## MetricDef (Metric Definition Registry)

```swift
struct MetricDef: Codable, Sendable {
    let id: String              // e.g. "imu_raw_ts_acc_surge"
    let name: String            // e.g. "Surge Acceleration"
    let source: String          // e.g. "imu"
    let unit: String?           // e.g. "m/s^2", "bpm", "spm"
    let formula: String?        // buffer reference
    let requirements: [String]  // necessary dependencies
    let category: String        // e.g. "kinematics", "physiological"
    let recommendedSamplingHz: Double?
    let transforms: [MetricTransform]?
    let aggregationMode: AggregationMode
}

enum AggregationMode: String, Codable, Sendable {
    case avg
    case deltaInterpolated
    case max
    case min
    case snapshotNearest
}
```

**Naming convention:** See `.claude/CONVENTIONS.md` for the `FAMILY_SOURCE_TYPE_NAME_MODIFIER` pattern.

---

## Source References

- **SessionDocument:** RDL session model + Kickoff Report 6.2
- **TelemetrySidecar:** Kickoff Report 6.3
- **SoA Buffers:** RDL `services/FusionEngine.ts` + Kickoff Report 6.4
- **MetricDef:** RDL `metrics/metrics-index.ts` + Kickoff Report 8.4
