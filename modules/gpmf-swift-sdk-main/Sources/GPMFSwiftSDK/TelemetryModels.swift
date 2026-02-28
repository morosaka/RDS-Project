import Foundation

// MARK: - TimestampedReading Protocol

/// A reading with a relative timestamp.
///
/// All sensor reading types in the SDK conform to this protocol,
/// enabling generic time-based operations (windowing, filtering,
/// interpolation) without type erasure.
///
/// Timestamps are **relative** to the start of the recording file
/// (0.0 = first sample), derived from the MP4 container's `stts`
/// + `mdhd` timescale — the authoritative clock source.
public protocol TimestampedReading: Sendable, Equatable {
    /// Time since the start of recording (seconds).
    var timestamp: TimeInterval { get }
}

// MARK: - TimestampedReading Array Extensions

extension Array where Element: TimestampedReading {

    /// Returns all elements whose timestamp falls within `range` (inclusive bounds).
    public func inTimeRange(_ range: ClosedRange<TimeInterval>) -> [Element] {
        filter { range.contains($0.timestamp) }
    }

    /// Returns all elements whose timestamp falls within `range` (half-open).
    public func inTimeRange(_ range: Range<TimeInterval>) -> [Element] {
        filter { range.contains($0.timestamp) }
    }

    /// Returns all elements within `radius` seconds of `time`.
    public func window(around time: TimeInterval, radius: TimeInterval) -> [Element] {
        let lo = time - radius
        let hi = time + radius
        return filter { $0.timestamp >= lo && $0.timestamp <= hi }
    }

    /// The time span covered by this array, or `nil` if empty.
    ///
    /// Returns `first.timestamp ... last.timestamp`. Assumes the array
    /// is sorted by timestamp (which is the SDK's default output order).
    public var timeRange: ClosedRange<TimeInterval>? {
        guard let first = first, let last = last else { return nil }
        return first.timestamp ... last.timestamp
    }
}

// MARK: - Top-Level Result

/// All telemetry data extracted from a single GoPro MP4 file.
///
/// ## Timing Model
///
/// All `timestamp` values in sensor readings are **relative** to the start of
/// this file (0.0 = first sample). They are derived from the MP4 container's
/// `stts` (sample-to-time) table and `mdhd` timescale — the authoritative
/// clock source per GoPro's specification.
///
/// For **absolute wall-clock time**, the SDK exposes three independent sources
/// without choosing between them. See the "Absolute Timestamps" section below.
/// The consuming application is responsible for selecting and cross-validating
/// the appropriate source for its use case.
///
/// ## Chapter Files & Multi-Session
///
/// This struct represents a **single MP4 file**. Stitching of chapter files
/// (same continuous recording split at ~4 GB) or multi-session recordings
/// (separate start/stop events) is the responsibility of the consuming
/// application, which has the context to determine whether files are
/// continuous chapters or separate sessions with temporal gaps.
public struct TelemetryData: Sendable {

    // MARK: Device Info

    /// Device name from GPMF `DVNM` tag (e.g. "Camera").
    public internal(set) var deviceName: String?

    /// Camera model from GPMF `MINF` tag (e.g. "HERO10 Black").
    public internal(set) var cameraModel: String?

    /// ORIN string from the IMU stream (e.g. "ZXY").
    /// Describes channel-to-camera-axis mapping. See `ORINMapper`.
    public internal(set) var orin: String?

    /// Device ID from GPMF `DVID` tag.
    ///
    /// Identifies the physical device when multiple devices report telemetry
    /// in the same MP4 (e.g. GoPro Fusion dual-lens, external sensors).
    /// On typical single-camera GoPro files, this is often `nil` or 1.
    public internal(set) var deviceID: UInt32?

    // MARK: Sensor Data (relative timestamps)

    /// 3-axis accelerometer readings in the GPMF Camera Frame (m/s²).
    public internal(set) var accelReadings: [SensorReading] = []

    /// 3-axis gyroscope readings in the GPMF Camera Frame (rad/s).
    public internal(set) var gyroReadings: [SensorReading] = []

    /// 3-axis magnetometer readings (µT).
    public internal(set) var magnetReadings: [SensorReading] = []

    /// Camera orientation quaternions (from CORI).
    public internal(set) var orientationReadings: [OrientationReading] = []

    /// Gravity vector readings (from GRAV).
    public internal(set) var gravityReadings: [SensorReading] = []

    /// GPS fix readings (from GPS5 or GPS9).
    public internal(set) var gpsReadings: [GpsReading] = []

    /// Sensor temperature readings in °C (from TMPC).
    public internal(set) var temperatureReadings: [TemperatureReading] = []

    /// Exposure metadata per video frame.
    public internal(set) var exposureReadings: [ExposureReading] = []

    // MARK: Stream Metadata

    /// Per-stream metadata keyed by the primary GPMF FourCC
    /// (e.g. `"ACCL"`, `"GYRO"`, `"GPS5"`, `"CORI"`, `"GRAV"`, `"TMPC"`).
    ///
    /// Contains stream name (`STNM`), SI units (`SIUN`), display units (`UNIT`),
    /// sample count, and computed sample rate for each extracted sensor stream.
    ///
    /// Only streams that produced readings will have entries.
    /// The consuming application can use this to discover available streams
    /// and their characteristics without inspecting individual reading arrays.
    public internal(set) var streamInfo: [String: StreamInfo] = [:]

    // MARK: Relative Timing (authoritative)

    /// Total duration of this file's telemetry, in seconds.
    /// Derived from the MP4 container's `stts` + `mdhd` timescale.
    /// This is the authoritative relative clock.
    public internal(set) var duration: TimeInterval = 0

    // MARK: Absolute Timestamps (exposed raw — NO implicit assumptions)
    //
    // These three fields expose different time sources from the MP4/GPMF data.
    // The SDK does NOT choose between them. Each has known limitations:
    //
    // 1. firstGPSU    — satellite-derived but low-precision (~1 Hz), may have
    //                    initial offset of ~2 s until leap-second correction is
    //                    received (~10 min of GPS lock). Obsolete on HERO11+.
    //                    Position in stream is ambiguous (appears AFTER sensor data
    //                    in the payload — unclear if it marks start or end of block).
    //                    Source: github.com/gopro/gpmf-parser/issues/6
    //                    Source: github.com/gopro/gpmf-parser/issues/131
    //
    // 2. firstGPS9Time — satellite-derived with ms precision (HERO11+).
    //                    Embedded in GPS9 payload. Same leap-second convergence
    //                    caveat as GPSU on first GPS lock.
    //
    // 3. mp4CreationTime — camera's internal RTC (filesystem clock).
    //                      Set by user or synced via USB/Quik (minute resolution).
    //                      Drifts throughout the day. NOT satellite-derived.
    //                      This is what typically appears as the file's "creation date".
    //
    // The consuming application must decide which source to trust for its
    // use case (e.g., cross-validation with FIT timestamps, session alignment).

    /// First `GPSU` observation in the GPMF stream, if any.
    ///
    /// Contains both the GPSU string (`"yymmddhhmmss.sss"`, satellite-derived UTC)
    /// and the `relativeTime` at which it appeared in the file timeline.
    ///
    /// **Caveats:**
    /// - ~1 Hz, low precision
    /// - May be offset by ~2-15 seconds until GPS leap-second correction
    ///   (needs up to ~10 min of continuous lock to converge)
    /// - Ambiguous position in stream (appears after ACCL data — unclear if it marks
    ///   the start or end of the payload's time window)
    /// - Obsolete on HERO11+ (replaced by GPS9 embedded time)
    /// - `nil` if GPS had no fix or GPSU tag was not present
    ///
    /// **For best accuracy, prefer `lastGPSU`** — it has had more convergence time.
    public internal(set) var firstGPSU: GPSTimestampObservation?

    /// Last `GPSU` observation in the GPMF stream, if any.
    ///
    /// In a multi-minute recording, the last GPSU has had the most time to converge
    /// on the correct leap-second offset, making it more reliable than `firstGPSU`.
    ///
    /// **Recommended for absolute start time computation:**
    /// ```swift
    /// if let last = telemetry.lastGPSU {
    ///     let absoluteStart = parseGPSU(last.value) - last.relativeTime
    /// }
    /// ```
    ///
    /// `nil` if GPS had no fix or GPSU tag was not present.
    public internal(set) var lastGPSU: GPSTimestampObservation?

    /// GPS9 embedded time from the first sample with a valid fix, if available.
    ///
    /// Only present on HERO11+ cameras that use the GPS9 stream format.
    /// Satellite-derived with millisecond precision.
    ///
    /// **Caveats:**
    /// - May be offset until GPS leap-second correction converges (~10 min)
    /// - `nil` if camera uses GPS5 format or GPS had no fix
    ///
    /// **For best accuracy, prefer `lastGPS9Time`** — it has had more convergence time.
    public internal(set) var firstGPS9Time: GPS9Timestamp?

    /// GPS9 embedded time from the last sample with a valid fix, if available.
    ///
    /// In a multi-minute recording, the last GPS9 timestamp has had the most time
    /// to converge on the correct leap-second offset.
    ///
    /// The relative time of this observation can be obtained from
    /// `gpsReadings.last?.timestamp` (GPS9 timestamps are embedded per-sample).
    ///
    /// `nil` if camera uses GPS5 format or GPS had no fix.
    public internal(set) var lastGPS9Time: GPS9Timestamp?

    /// MP4 creation time from the `mvhd` atom (camera's internal RTC).
    ///
    /// **WARNING: This is filesystem time, NOT satellite time.**
    /// - Set by user or synced via USB/Quik (minute resolution only)
    /// - Camera internal clock drifts throughout the day
    /// - May be arbitrarily wrong if the user never set the clock
    /// - `nil` if `mvhd` could not be parsed
    public internal(set) var mp4CreationTime: Date?

    public init() {}

    // MARK: Internal — TSMP Tracking (used by ChapterStitcher)

    /// Cumulative sample-count bounds seen for each sensor stream in this file.
    ///
    /// Keyed by GPMF FourCC (e.g. `"ACCL"`, `"GYRO"`, `"GPS5"`).
    /// `first` = TSMP value from the first payload that contained data for this stream.
    /// `last`  = TSMP value from the last  payload that contained data for this stream.
    ///
    /// Used by `ChapterStitcher` to validate that consecutive chapters are
    /// truly continuous (TSMP must be monotonically increasing across the boundary).
    /// Not intended for consumption by the host application.
    internal var _tsmpByStream: [String: TSMPBounds] = [:]

    /// First and last observed TSMP values for a single sensor stream within one file.
    internal struct TSMPBounds {
        var first: UInt32
        var last: UInt32
    }
}

// MARK: - GPS Timestamp Observation

/// A GPS-derived absolute timestamp paired with its position in the file timeline.
///
/// GPS timestamps improve in accuracy over time as the receiver converges on
/// the leap-second correction (up to ~10 minutes of continuous GPS lock).
/// The `relativeTime` field anchors this observation to the file's authoritative
/// relative timeline (from the MP4 `stts` + `mdhd` timescale).
///
/// ## Recommended Usage
///
/// For best absolute timing accuracy, use the **last** observation and
/// back-compute the recording start:
/// ```swift
/// if let last = telemetry.lastGPSU {
///     let absoluteStart = parseGPSU(last.value) - last.relativeTime
/// }
/// ```
/// The last GPSU in a multi-minute recording has had the most time to converge
/// and is therefore more reliable than the first.
public struct GPSTimestampObservation: Sendable, Equatable {
    /// The GPSU string value in `"yymmddhhmmss.sss"` format.
    public let value: String
    /// Relative time within the file when this GPSU was observed (seconds from file start).
    /// Derived from the payload's position in the `stts` timeline.
    public let relativeTime: TimeInterval

    public init(value: String, relativeTime: TimeInterval) {
        self.value = value
        self.relativeTime = relativeTime
    }
}

// MARK: - GPS9 Timestamp

/// Satellite-derived timestamp from the GPS9 stream (HERO11+).
///
/// GPS9 embeds time directly in each GPS sample as two fields:
/// - `daysSince2000`: integer days since January 1, 2000
/// - `secondsSinceMidnight`: seconds since midnight with ms precision
///
/// These are GPS satellite time, subject to the same leap-second convergence
/// caveat as GPSU (may be off by ~2 s until correction message is received).
public struct GPS9Timestamp: Sendable, Equatable {
    /// Days elapsed since January 1, 2000 (GPS epoch for this field).
    public let daysSince2000: UInt32
    /// Seconds since midnight UTC, with millisecond precision.
    public let secondsSinceMidnight: Double

    public init(daysSince2000: UInt32, secondsSinceMidnight: Double) {
        self.daysSince2000 = daysSince2000
        self.secondsSinceMidnight = secondsSinceMidnight
    }

    /// Attempts to convert to a Foundation `Date`.
    ///
    /// Returns `nil` if the values produce an invalid date.
    /// The result inherits all GPS satellite time caveats (leap-second, convergence).
    public var date: Date? {
        var components = DateComponents()
        components.year = 2000
        components.month = 1
        components.day = 1 + Int(daysSince2000)
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        guard let baseDate = Calendar(identifier: .gregorian).date(from: components) else { return nil }
        return baseDate.addingTimeInterval(secondsSinceMidnight)
    }
}

// MARK: - Sensor Reading (3-axis)

/// A single 3-axis IMU sample in the GPMF Camera Frame.
///
/// After ORIN remapping:
/// - `xCam`: positive = left (from rear of camera, looking forward)
/// - `yCam`: positive = into camera (towards lens)
/// - `zCam`: positive = up
public struct SensorReading: TimestampedReading, Equatable {
    /// Time since the start of recording (seconds).
    public let timestamp: TimeInterval

    /// X-axis value in the GPMF Camera Frame.
    public let xCam: Double

    /// Y-axis value in the GPMF Camera Frame.
    public let yCam: Double

    /// Z-axis value in the GPMF Camera Frame.
    public let zCam: Double

    public init(timestamp: TimeInterval, xCam: Double, yCam: Double, zCam: Double) {
        self.timestamp = timestamp
        self.xCam = xCam
        self.yCam = yCam
        self.zCam = zCam
    }
}

// MARK: - GPS Reading

/// A single GPS sample.
public struct GpsReading: TimestampedReading, Equatable {
    public let timestamp: TimeInterval
    public let latitude: Double    // degrees
    public let longitude: Double   // degrees
    public let altitude: Double    // meters
    public let speed2d: Double     // m/s
    public let speed3d: Double     // m/s
    /// Dilution of Precision (from GPSP), or nil if unavailable.
    public let dop: Double?
    /// GPS fix type: 0=none, 2=2D, 3=3D, or nil if unavailable.
    public let fix: UInt32?

    public init(
        timestamp: TimeInterval, latitude: Double, longitude: Double,
        altitude: Double, speed2d: Double, speed3d: Double,
        dop: Double? = nil, fix: UInt32? = nil
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speed2d = speed2d
        self.speed3d = speed3d
        self.dop = dop
        self.fix = fix
    }
}

// MARK: - Orientation Reading (Quaternion)

/// Camera orientation as a quaternion (from CORI stream).
public struct OrientationReading: TimestampedReading, Equatable {
    public let timestamp: TimeInterval
    public let w: Double
    public let x: Double
    public let y: Double
    public let z: Double

    public init(timestamp: TimeInterval, w: Double, x: Double, y: Double, z: Double) {
        self.timestamp = timestamp
        self.w = w
        self.x = x
        self.y = y
        self.z = z
    }
}

// MARK: - Temperature Reading

/// Sensor temperature (from TMPC stream).
public struct TemperatureReading: TimestampedReading, Equatable {
    public let timestamp: TimeInterval
    /// Temperature in degrees Celsius.
    public let celsius: Double

    public init(timestamp: TimeInterval, celsius: Double) {
        self.timestamp = timestamp
        self.celsius = celsius
    }
}

// MARK: - Stream Info

/// Per-stream metadata for a GPMF sensor stream.
///
/// Keyed by the stream's primary sensor FourCC (e.g. `"ACCL"`, `"GYRO"`, `"GPS5"`).
/// Available on ``TelemetryData/streamInfo`` after extraction.
///
/// Contains GPMF sticky tags (`STNM`, `SIUN`, `UNIT`) that describe the stream,
/// plus computed sample count and effective sample rate.
public struct StreamInfo: Sendable, Equatable {

    /// Human-readable stream name from GPMF `STNM` tag (e.g. "Accelerometer").
    /// `nil` if `STNM` was not present in the stream.
    public internal(set) var name: String?

    /// SI units string from GPMF `SIUN` tag (e.g. "m/s²", "rad/s").
    /// `nil` if `SIUN` was not present.
    public internal(set) var siUnit: String?

    /// Display units string from GPMF `UNIT` tag.
    /// GoPro typically uses `SIUN` rather than `UNIT`, so this is often `nil`.
    public internal(set) var displayUnit: String?

    /// Total number of readings extracted for this stream.
    public internal(set) var sampleCount: Int

    /// Effective sample rate in Hz, computed as `sampleCount / duration`.
    ///
    /// This is a file-level average rate derived from the total number of
    /// extracted readings divided by the file's total telemetry duration
    /// (from `stts` + `mdhd`). Always available when `sampleCount > 0`
    /// and `duration > 0`.
    public internal(set) var sampleRate: Double

    public init(
        name: String? = nil,
        siUnit: String? = nil,
        displayUnit: String? = nil,
        sampleCount: Int = 0,
        sampleRate: Double = 0
    ) {
        self.name = name
        self.siUnit = siUnit
        self.displayUnit = displayUnit
        self.sampleCount = sampleCount
        self.sampleRate = sampleRate
    }
}

// MARK: - Exposure Reading

/// Per-frame exposure metadata.
public struct ExposureReading: TimestampedReading, Equatable {
    public let timestamp: TimeInterval
    /// ISO gain value.
    public let isoGain: Double?
    /// Shutter speed in seconds.
    public let shutterSpeed: Double?

    public init(timestamp: TimeInterval, isoGain: Double? = nil, shutterSpeed: Double? = nil) {
        self.timestamp = timestamp
        self.isoGain = isoGain
        self.shutterSpeed = shutterSpeed
    }
}

// MARK: - Stream Filter

/// Selects which sensor streams to extract from GPMF data.
///
/// Pass a `StreamFilter` to `GPMFExtractor.extract(from:streams:)`,
/// `ChapterStitcher.stitch(_:streams:)`, or `SessionGrouper.extractAll(_:streams:)`
/// to extract only the sensor data you need, reducing parsing time and memory usage.
///
/// **Always extracted regardless of filter** (device metadata, not sensor data):
/// - Device info: DVNM, DVID, ORIN, MINF
/// - GPS quality: GPSU, GPSF, GPSP
/// - Timing: TSMP (ChapterStitcher coherence validation)
/// - Stream metadata: SCAL, STNM, SIUN, UNIT
/// - Absolute timestamps: `firstGPSU`, `lastGPSU`, `firstGPS9Time`, `lastGPS9Time`
/// - Container metadata: `mp4CreationTime`, `duration`
///
/// **Filtered:** The actual sensor reading arrays (ACCL, GYRO, GPS5, etc.).
/// Reading arrays for filtered-out streams remain empty.
///
/// ## Usage
///
/// ```swift
/// // Extract only accelerometer and GPS data
/// let filter = StreamFilter(.accl, .gps5)
/// let telemetry = try GPMFExtractor.extract(from: url, streams: filter)
/// // telemetry.accelReadings → populated
/// // telemetry.gyroReadings  → empty (filtered out)
/// // telemetry.gpsReadings   → populated
///
/// // Extract everything (default, equivalent to no filter)
/// let all = try GPMFExtractor.extract(from: url)
/// ```
public struct StreamFilter: Sendable, Equatable {

    /// The set of sensor stream keys to extract.
    public let keys: Set<GPMFKey>

    /// Creates a filter for the specified sensor keys.
    public init(keys: Set<GPMFKey>) {
        self.keys = keys
    }

    /// Creates a filter for the specified sensor keys (variadic convenience).
    public init(_ keys: GPMFKey...) {
        self.keys = Set(keys)
    }

    /// A filter that extracts all supported sensor streams.
    ///
    /// Equivalent to no filter (same as passing `nil`), but useful for
    /// explicitly documenting intent.
    public static let all = StreamFilter(keys: [
        .accl, .gyro, .magn, .gps5, .gps9, .tmpc, .cori, .grav,
    ])

    /// Returns `true` if the given key should be extracted.
    internal func shouldExtract(_ key: GPMFKey) -> Bool {
        keys.contains(key)
    }
}
