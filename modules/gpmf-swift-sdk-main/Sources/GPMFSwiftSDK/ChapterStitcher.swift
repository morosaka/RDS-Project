import Foundation

/// Stitches consecutive chapter files from the same GoPro continuous recording
/// into a single `TelemetryData` with a unified timeline.
///
/// ## What this is for
///
/// GoPro splits long continuous recordings into ~4 GB chapter files named:
/// ```
/// GX[CC][NNNN].MP4
///    ^^  ^^^^
///    |   Session ID — same for all chapters of one recording
///    Chapter number — 01, 02, 03, ... increments with each split
/// ```
/// `ChapterStitcher` handles **only this case**: same session ID, consecutive
/// chapter numbers, one uninterrupted recording split purely by file size.
///
/// ## What this is NOT for
///
/// - Different sessions (different NNNN) — temporal gaps may exist between them.
/// - Multiple start/stop recording events — even if NNNN were somehow identical,
///   the TSMP validation would catch incoherence.
///
/// Multi-session management is the responsibility of the consuming application.
///
/// ## Timeline model
///
/// The stitched `TelemetryData` uses a unified relative timeline where 0.0 is
/// the start of the first chapter. Timestamps from chapter N are offset by the
/// cumulative duration of all preceding chapters.
///
/// ## Validation
///
/// Before any extraction, `stitch(_:)` validates:
/// 1. All filenames match `[A-Z]{2}[0-9]{6}.MP4` (GoPro chapter format)
/// 2. All files share the same session ID (NNNN)
/// 3. Chapter numbers (CC) form a consecutive, gap-free sequence
///
/// After extraction, TSMP coherence is validated between each consecutive pair:
/// - The first TSMP of chapter N+1 must be strictly greater than the last TSMP
///   of chapter N (TSMP is cumulative from recording start)
/// - The gap must be physically plausible (< 200 000 samples ≈ < 17 min at 200 Hz)
///
/// Failures throw descriptive `GPMFError` cases.
public struct ChapterStitcher {

    private init() {}

    // MARK: - Public API

    /// Stitches GoPro chapter files into a unified `TelemetryData`.
    ///
    /// - Parameters:
    ///   - urls: Chapter file URLs in any order; sorted by chapter number internally.
    ///   - streams: Optional filter to extract only specific sensor streams.
    ///     Pass `nil` (default) to extract all available streams.
    ///     Forwarded to `GPMFExtractor.extract(from:streams:)`.
    /// - Returns: `TelemetryData` with a unified timeline starting at 0.0.
    /// - Throws:
    ///   - `GPMFError.unrecognizedChapterFilename` — a URL does not match GoPro naming
    ///   - `GPMFError.mixedSessionIDs` — files come from different recording sessions
    ///   - `GPMFError.nonConsecutiveChapters` — chapter numbers have gaps
    ///   - `GPMFError.tsmpIncoherence` — TSMP is not monotonically increasing across a boundary
    ///   - Any `GPMFError` from the underlying `GPMFExtractor`
    public static func stitch(_ urls: [URL], streams: StreamFilter? = nil) throws -> TelemetryData {
        guard !urls.isEmpty else {
            throw GPMFError.invalidMP4Structure("ChapterStitcher: no files provided")
        }

        // 1. Parse filenames and validate chapter sequence
        let sorted = try parseAndSortChapters(urls)

        // 2. Extract each chapter (forwarding stream filter)
        var extractions: [TelemetryData] = []
        extractions.reserveCapacity(sorted.count)
        for chap in sorted {
            extractions.append(try GPMFExtractor.extract(from: chap.url, streams: streams))
        }

        // 3. Validate TSMP coherence between consecutive chapters
        for i in 1..<extractions.count {
            try validateTSMP(
                prev: extractions[i - 1],
                current: extractions[i],
                chapterIndex: i
            )
        }

        // 4. Offset timestamps and concatenate
        return stitch(extractions)
    }

    // MARK: - Chapter Info (internal for testability)

    struct ChapterInfo {
        let url: URL
        let prefix: String      // 2-letter camera prefix, e.g. "GX"
        let chapterNumber: Int  // CC, 1-based
        let sessionID: String   // NNNN, 4 digits
    }

    // MARK: - Parsing & Validation

    private static func parseAndSortChapters(_ urls: [URL]) throws -> [ChapterInfo] {
        // Parse every filename
        var chapters: [ChapterInfo] = []
        for url in urls {
            guard let info = parseChapterInfo(url) else {
                throw GPMFError.unrecognizedChapterFilename(url.lastPathComponent)
            }
            chapters.append(info)
        }

        // All files must share one session ID
        let sessionIDs = Set(chapters.map(\.sessionID))
        if sessionIDs.count > 1 {
            throw GPMFError.mixedSessionIDs(Array(sessionIDs).sorted())
        }

        // Sort ascending by chapter number
        chapters.sort { $0.chapterNumber < $1.chapterNumber }

        // Chapter numbers must be consecutive (no gaps)
        let numbers = chapters.map(\.chapterNumber)
        for i in 1..<numbers.count where numbers[i] != numbers[i - 1] + 1 {
            throw GPMFError.nonConsecutiveChapters(numbers)
        }

        return chapters
    }

    /// Parses a GoPro chapter filename.
    ///
    /// Expected base-name format: `[A-Z]{2}[0-9]{2}[0-9]{4}`
    /// (2 uppercase letters + 2-digit chapter + 4-digit session, 8 characters total)
    ///
    /// Examples: `GX040246`, `GH010246`, `GL020135`
    ///
    /// - Returns: Parsed `ChapterInfo`, or `nil` if the name does not match.
    static func parseChapterInfo(_ url: URL) -> ChapterInfo? {
        let ext = url.pathExtension.uppercased()
        guard ext == "MP4" else { return nil }

        let base = url.deletingPathExtension().lastPathComponent
        let chars = Array(base)
        guard chars.count == 8 else { return nil }

        // Characters 0-1: uppercase letters (camera prefix)
        guard chars[0].isLetter && chars[0].isUppercase,
              chars[1].isLetter && chars[1].isUppercase else { return nil }

        // Characters 2-3: chapter number (CC)
        let ccStr   = String(chars[2...3])
        // Characters 4-7: session ID (NNNN)
        let nnnnStr = String(chars[4...7])

        guard let chapter = Int(ccStr), chapter >= 1,
              Int(nnnnStr) != nil else { return nil }

        return ChapterInfo(
            url: url,
            prefix: String(chars[0...1]),
            chapterNumber: chapter,
            sessionID: nnnnStr
        )
    }

    // MARK: - TSMP Coherence Validation

    /// Validates that the TSMP counter is monotonically increasing across a chapter
    /// boundary. A decreasing or implausibly large jump indicates the files are
    /// NOT from the same continuous recording session.
    ///
    /// - Parameters:
    ///   - prev: Extraction result for chapter N.
    ///   - current: Extraction result for chapter N+1.
    ///   - chapterIndex: 1-based index of the chapter pair (1 = ch1→ch2).
    private static func validateTSMP(
        prev: TelemetryData,
        current: TelemetryData,
        chapterIndex: Int
    ) throws {
        for (stream, prevBounds) in prev._tsmpByStream {
            guard let curBounds = current._tsmpByStream[stream] else {
                continue  // stream absent in next chapter — not an error (stream may end)
            }

            let prevLast  = prevBounds.last
            let curFirst  = curBounds.first

            // TSMP must strictly increase and the gap must be physically plausible.
            // A gap of 200 000 samples at 200 Hz = ~17 min: well beyond what fits in a
            // single payload flush cycle, so any gap this large is suspect.
            let coherent = curFirst > prevLast && (curFirst &- prevLast) < 200_000
            guard coherent else {
                throw GPMFError.tsmpIncoherence(stream: stream, betweenChapters: chapterIndex)
            }
        }
    }

    // MARK: - Timeline Stitching

    /// Offsets all timestamps in each chapter and concatenates reading arrays.
    private static func stitch(_ extractions: [TelemetryData]) -> TelemetryData {
        var combined = TelemetryData()
        var timeOffset: TimeInterval = 0

        for (i, t) in extractions.enumerated() {
            let off = timeOffset

            if i == 0 {
                // Device metadata always comes from chapter 1
                combined.deviceName       = t.deviceName
                combined.cameraModel      = t.cameraModel
                combined.orin             = t.orin
                combined.deviceID         = t.deviceID
                combined.firstGPSU        = t.firstGPSU  // relativeTime already correct (ch1 starts at 0)
                combined.firstGPS9Time    = t.firstGPS9Time
                combined.mp4CreationTime  = t.mp4CreationTime
            }

            // Always update last GPS observations — later chapters have more
            // converged GPS receivers and are therefore more reliable.
            // GPSU relativeTime must be offset by cumulative chapter durations.
            if let last = t.lastGPSU {
                combined.lastGPSU = GPSTimestampObservation(
                    value: last.value,
                    relativeTime: last.relativeTime + off
                )
            }
            // GPS9Timestamp is absolute (days+seconds), no relative offset needed.
            if let last = t.lastGPS9Time {
                combined.lastGPS9Time = last
            }

            // Append timestamp-offset copies of every reading array
            combined.accelReadings       += t.accelReadings.map       { offsetSensor($0, by: off) }
            combined.gyroReadings        += t.gyroReadings.map        { offsetSensor($0, by: off) }
            combined.magnetReadings      += t.magnetReadings.map      { offsetSensor($0, by: off) }
            combined.gravityReadings     += t.gravityReadings.map     { offsetSensor($0, by: off) }
            combined.gpsReadings         += t.gpsReadings.map         { offsetGPS($0, by: off) }
            combined.orientationReadings += t.orientationReadings.map { offsetOrientation($0, by: off) }
            combined.temperatureReadings += t.temperatureReadings.map { offsetTemperature($0, by: off) }
            combined.exposureReadings    += t.exposureReadings.map    { offsetExposure($0, by: off) }

            // Accumulate streamInfo: merge sticky metadata from each chapter,
            // summing sampleCount. sampleRate is recomputed after the loop.
            for (key, info) in t.streamInfo {
                if var existing = combined.streamInfo[key] {
                    existing.sampleCount += info.sampleCount
                    // Sticky tags: keep first non-nil from chapter 1
                    if existing.name == nil { existing.name = info.name }
                    if existing.siUnit == nil { existing.siUnit = info.siUnit }
                    if existing.displayUnit == nil { existing.displayUnit = info.displayUnit }
                    combined.streamInfo[key] = existing
                } else {
                    combined.streamInfo[key] = info
                }
            }

            timeOffset += t.duration
        }

        combined.duration = timeOffset

        // Recompute sampleRate for each stream using the total stitched duration
        if combined.duration > 0 {
            for key in combined.streamInfo.keys {
                combined.streamInfo[key]!.sampleRate =
                    Double(combined.streamInfo[key]!.sampleCount) / combined.duration
            }
        }

        return combined
    }

    // MARK: - Timestamp Offset Helpers

    private static func offsetSensor(_ r: SensorReading, by dt: TimeInterval) -> SensorReading {
        SensorReading(timestamp: r.timestamp + dt, xCam: r.xCam, yCam: r.yCam, zCam: r.zCam)
    }

    private static func offsetGPS(_ r: GpsReading, by dt: TimeInterval) -> GpsReading {
        GpsReading(
            timestamp:  r.timestamp + dt,
            latitude:   r.latitude,
            longitude:  r.longitude,
            altitude:   r.altitude,
            speed2d:    r.speed2d,
            speed3d:    r.speed3d,
            dop:        r.dop,
            fix:        r.fix
        )
    }

    private static func offsetOrientation(_ r: OrientationReading, by dt: TimeInterval) -> OrientationReading {
        OrientationReading(timestamp: r.timestamp + dt, w: r.w, x: r.x, y: r.y, z: r.z)
    }

    private static func offsetTemperature(_ r: TemperatureReading, by dt: TimeInterval) -> TemperatureReading {
        TemperatureReading(timestamp: r.timestamp + dt, celsius: r.celsius)
    }

    private static func offsetExposure(_ r: ExposureReading, by dt: TimeInterval) -> ExposureReading {
        ExposureReading(timestamp: r.timestamp + dt, isoGain: r.isoGain, shutterSpeed: r.shutterSpeed)
    }
}
