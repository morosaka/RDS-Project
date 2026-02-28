import Foundation

/// High-level API for extracting telemetry data from a single GoPro MP4 file.
///
/// ## Design Principle
///
/// This extractor processes **one MP4 file at a time**. It does NOT perform
/// chapter stitching or multi-session concatenation. The consuming application
/// is responsible for:
/// - Grouping chapter files (same continuous recording split at ~4 GB)
/// - Detecting and handling temporal gaps between separate recordings
/// - Aligning GPMF timestamps with other data sources (e.g. FIT files)
///
/// ## Timing
///
/// All sensor reading timestamps are **relative** to the start of the file
/// (0.0 = first sample), derived from the MP4 `stts` + `mdhd` timescale.
///
/// Absolute time sources (GPSU, GPS9, mvhd creation_time) are exposed raw
/// in `TelemetryData` without any implicit interpretation. See the
/// documentation on `TelemetryData` for details and caveats.
///
/// ## Usage
///
/// ```swift
/// let telemetry = try GPMFExtractor.extract(from: fileURL)
///
/// // Relative timing (authoritative)
/// for r in telemetry.accelReadings {
///     print("\(r.timestamp)s: x=\(r.xCam) y=\(r.yCam) z=\(r.zCam)")
/// }
///
/// // Absolute time sources (use with caution)
/// if let gpsu = telemetry.firstGPSU {
///     print("GPSU (satellite, ~1Hz): \(gpsu)")
/// }
/// if let gps9 = telemetry.firstGPS9Time, let date = gps9.date {
///     print("GPS9 (satellite, ms): \(date)")
/// }
/// if let created = telemetry.mp4CreationTime {
///     print("mvhd (camera RTC): \(created)")
/// }
/// ```
public final class GPMFExtractor {

    private init() {}

    // MARK: - Public API

    /// Extracts telemetry from a single GoPro MP4 file.
    ///
    /// - Parameters:
    ///   - url: Path to the .MP4 file.
    ///   - streams: Optional filter to extract only specific sensor streams.
    ///     Pass `nil` (default) to extract all available streams.
    ///     Device metadata, absolute timestamps, and timing information are
    ///     always extracted regardless of this filter.
    /// - Returns: Populated `TelemetryData` with sensor readings in the GPMF Camera Frame
    ///   and raw absolute timestamp sources.
    public static func extract(from url: URL, streams: StreamFilter? = nil) throws -> TelemetryData {
        let parser = try MP4TrackParser(url: url)
        let result = try parser.extractTimedPayloadsWithMetadata()
        var telemetry = processPayloads(result.payloads, streams: streams)
        telemetry.mp4CreationTime = result.mp4CreationTime
        return telemetry
    }

    // MARK: - Payload Processing

    private static func processPayloads(_ payloads: [TimedPayload], streams: StreamFilter? = nil) -> TelemetryData {
        var telemetry = TelemetryData()

        // Track sticky metadata across payloads
        var orinString: String?
        var gpsFix: UInt32?
        var gpsDop: Double?

        // Accumulate per-stream sticky metadata (STNM, SIUN, UNIT) across payloads.
        // Keyed by primary sensor FourCC. Values are captured on first occurrence
        // and remain sticky across subsequent payloads (GPMF sticky tag semantics).
        var stickyStreamMeta: [String: (name: String?, siUnit: String?, displayUnit: String?)] = [:]

        for payload in payloads {
            let nodes = GPMFDecoder.decode(data: payload.data)

            for devc in nodes where devc.key == GPMFKey.devc.rawValue {
                guard let children = devc.children else { continue }

                // Extract device-level metadata
                if let dvnm = children.first(where: { $0.key == GPMFKey.dvnm.rawValue }) {
                    telemetry.deviceName = telemetry.deviceName ?? GPMFDecoder.readString(from: dvnm)
                }

                // Extract device ID (DVID) — device-level tag, first occurrence wins
                if telemetry.deviceID == nil,
                   let dvidNode = children.first(where: { $0.key == GPMFKey.dvid.rawValue }) {
                    let vals = GPMFDecoder.readDoubles(from: dvidNode)
                    if let v = vals.first, v >= 0 { telemetry.deviceID = UInt32(v) }
                }

                // Process each stream
                for strm in children where strm.key == GPMFKey.strm.rawValue {
                    guard let streamChildren = strm.children else { continue }

                    // Read sticky metadata for this stream
                    let streamMeta = extractStreamMetadata(streamChildren)

                    // Track ORIN globally
                    if let orin = streamMeta.orin { orinString = orin }
                    if let fix = streamMeta.gpsFix { gpsFix = fix }
                    if let dop = streamMeta.gpsDop { gpsDop = dop }

                    // Extract GPSU — capture first and last observations with
                    // their relative file positions. The last observation is more
                    // reliable because the GPS receiver has had more convergence time
                    // for the leap-second correction.
                    if let gpsu = streamMeta.gpsu {
                        let obs = GPSTimestampObservation(
                            value: gpsu,
                            relativeTime: payload.time
                        )
                        if telemetry.firstGPSU == nil {
                            telemetry.firstGPSU = obs
                        }
                        telemetry.lastGPSU = obs
                    }

                    // Identify ALL sensor FourCCs present in this stream.
                    // On HERO10, ACCL/GYRO streams also contain a TMPC node (companion
                    // temperature). We need to track metadata for each sensor independently.
                    let streamSensorKeys = streamChildren
                        .map(\.key)
                        .filter { Self.sensorKeys.contains($0) }

                    // Track TSMP for each sensor stream (used by ChapterStitcher for
                    // cross-chapter coherence validation).
                    // A single STRM may contain multiple sensor keys (e.g. TMPC+ACCL on
                    // HERO10). TSMP applies to all of them (same cumulative count).
                    if let tsmp = streamMeta.tsmp {
                        for pk in streamSensorKeys {
                            if var bounds = telemetry._tsmpByStream[pk] {
                                bounds.last = tsmp
                                telemetry._tsmpByStream[pk] = bounds
                            } else {
                                telemetry._tsmpByStream[pk] = TelemetryData.TSMPBounds(first: tsmp, last: tsmp)
                            }
                        }
                    }

                    // Accumulate sticky stream metadata (STNM, SIUN, UNIT).
                    // On HERO10, ACCL/GYRO streams contain a companion TMPC node, so a
                    // single STRM may contain multiple sensor keys. The STNM/SIUN/UNIT
                    // tags describe the stream's primary sensor (the LAST sensor key in
                    // the children list), NOT companion sensors that appear earlier.
                    //
                    // For multi-sensor STRMs: metadata goes ONLY to the last sensor key.
                    // For single-sensor STRMs: metadata goes to that sensor key.
                    // All sensors get registered in stickyStreamMeta (ensures they appear
                    // in streamInfo) but only the primary gets the descriptive metadata.
                    let primarySensorKey = streamSensorKeys.last
                    for pk in streamSensorKeys {
                        var existing = stickyStreamMeta[pk] ?? (name: nil, siUnit: nil, displayUnit: nil)
                        if pk == primarySensorKey {
                            if existing.name == nil, let n = streamMeta.stnm { existing.name = n }
                            if existing.siUnit == nil, let u = streamMeta.siun { existing.siUnit = u }
                            if existing.displayUnit == nil, let u = streamMeta.unit { existing.displayUnit = u }
                        }
                        stickyStreamMeta[pk] = existing
                    }

                    // Process sensor data nodes
                    for node in streamChildren {
                        let payloadStartTime = payload.time
                        let payloadDuration = payload.duration

                        switch node.key {
                        case GPMFKey.accl.rawValue:
                            guard streams == nil || streams!.shouldExtract(.accl) else { break }
                            let readings = extractIMUReadings(
                                node: node, scales: streamMeta.scales,
                                orin: orinString,
                                startTime: payloadStartTime, duration: payloadDuration
                            )
                            telemetry.accelReadings.append(contentsOf: readings)

                        case GPMFKey.gyro.rawValue:
                            guard streams == nil || streams!.shouldExtract(.gyro) else { break }
                            let readings = extractIMUReadings(
                                node: node, scales: streamMeta.scales,
                                orin: orinString,
                                startTime: payloadStartTime, duration: payloadDuration
                            )
                            telemetry.gyroReadings.append(contentsOf: readings)

                        case GPMFKey.magn.rawValue:
                            guard streams == nil || streams!.shouldExtract(.magn) else { break }
                            let readings = extractIMUReadings(
                                node: node, scales: streamMeta.scales,
                                orin: nil,  // magnetometer uses its own orientation
                                startTime: payloadStartTime, duration: payloadDuration
                            )
                            telemetry.magnetReadings.append(contentsOf: readings)

                        case GPMFKey.grav.rawValue:
                            guard streams == nil || streams!.shouldExtract(.grav) else { break }
                            let readings = extractIMUReadings(
                                node: node, scales: streamMeta.scales,
                                orin: nil,
                                startTime: payloadStartTime, duration: payloadDuration
                            )
                            telemetry.gravityReadings.append(contentsOf: readings)

                        case GPMFKey.cori.rawValue:
                            guard streams == nil || streams!.shouldExtract(.cori) else { break }
                            let readings = extractOrientationReadings(
                                node: node, scales: streamMeta.scales,
                                startTime: payloadStartTime, duration: payloadDuration
                            )
                            telemetry.orientationReadings.append(contentsOf: readings)

                        case GPMFKey.gps5.rawValue:
                            guard streams == nil || streams!.shouldExtract(.gps5) else { break }
                            let readings = extractGPS5Readings(
                                node: node, scales: streamMeta.scales,
                                dop: gpsDop, fix: gpsFix,
                                startTime: payloadStartTime, duration: payloadDuration
                            )
                            telemetry.gpsReadings.append(contentsOf: readings)

                        case GPMFKey.gps9.rawValue:
                            // GPS9 timestamps are always extracted (metadata, not sensor data)
                            // because the consuming application needs firstGPS9Time/lastGPS9Time
                            // for absolute timing regardless of which streams are selected.
                            let (readings, firstTimestamp, lastTimestamp) = extractGPS9Readings(
                                node: node, scales: streamMeta.scales,
                                startTime: payloadStartTime, duration: payloadDuration
                            )
                            if let ts = firstTimestamp, telemetry.firstGPS9Time == nil {
                                telemetry.firstGPS9Time = ts
                            }
                            if let ts = lastTimestamp {
                                telemetry.lastGPS9Time = ts
                            }
                            // Only append sensor readings if not filtered out
                            if streams == nil || streams!.shouldExtract(.gps9) {
                                telemetry.gpsReadings.append(contentsOf: readings)
                            }

                        case GPMFKey.tmpc.rawValue:
                            guard streams == nil || streams!.shouldExtract(.tmpc) else { break }
                            // TMPC is always GPMF type 'f' (32-bit float) already in °C.
                            // When TMPC is a companion sensor in an ACCL/GYRO STRM (HERO10),
                            // the STRM's SCAL applies to the primary sensor (ACCL/GYRO),
                            // NOT to TMPC. Always use scale=1.0 for temperature.
                            let readings = extractTemperatureReadings(
                                node: node, scales: [1.0],
                                startTime: payloadStartTime, duration: payloadDuration
                            )
                            telemetry.temperatureReadings.append(contentsOf: readings)

                        case GPMFKey.minf.rawValue:
                            // Always extracted — device metadata, not sensor data
                            telemetry.cameraModel = telemetry.cameraModel ?? GPMFDecoder.readString(from: node)

                        default:
                            break
                        }
                    }
                }
            }
        }

        telemetry.orin = orinString

        // Compute total duration from last payload
        if let last = payloads.last {
            telemetry.duration = last.time + last.duration
        }

        // Build streamInfo from accumulated sticky metadata + reading counts.
        // sampleRate = readingsCount / duration (not TSMP-based, because TSMP
        // is absent on ACCL/GYRO streams on HERO10).
        let readingCounts: [(String, Int)] = [
            (GPMFKey.accl.rawValue, telemetry.accelReadings.count),
            (GPMFKey.gyro.rawValue, telemetry.gyroReadings.count),
            (GPMFKey.magn.rawValue, telemetry.magnetReadings.count),
            (GPMFKey.gps5.rawValue, telemetry.gpsReadings.count),   // GPS5 or GPS9 → same array
            (GPMFKey.gps9.rawValue, 0),  // sentinel — handled below
            (GPMFKey.tmpc.rawValue, telemetry.temperatureReadings.count),
            (GPMFKey.cori.rawValue, telemetry.orientationReadings.count),
            (GPMFKey.grav.rawValue, telemetry.gravityReadings.count),
        ]

        for (key, count) in readingCounts {
            // GPS9 readings go into the same gpsReadings array as GPS5.
            // If stickyStreamMeta has GPS9 (not GPS5), use the gpsReadings count.
            let effectiveCount: Int
            if key == GPMFKey.gps9.rawValue {
                if stickyStreamMeta[key] != nil && stickyStreamMeta[GPMFKey.gps5.rawValue] == nil {
                    effectiveCount = telemetry.gpsReadings.count
                } else {
                    continue  // GPS5 already handled, skip GPS9 entry
                }
            } else if key == GPMFKey.gps5.rawValue && stickyStreamMeta[key] == nil {
                continue  // No GPS5 stream — GPS9 (if present) will handle it
            } else {
                effectiveCount = count
            }

            guard effectiveCount > 0, let meta = stickyStreamMeta[key] else { continue }

            let rate = telemetry.duration > 0 ? Double(effectiveCount) / telemetry.duration : 0
            telemetry.streamInfo[key] = StreamInfo(
                name: meta.name,
                siUnit: meta.siUnit,
                displayUnit: meta.displayUnit,
                sampleCount: effectiveCount,
                sampleRate: rate
            )
        }

        return telemetry
    }

    // MARK: - Stream Metadata

    private struct StreamMetadata {
        var scales: [Double] = [1.0]
        var siun: String?
        var stnm: String?
        var unit: String?
        var orin: String?
        var gpsFix: UInt32?
        var gpsDop: Double?
        var gpsu: String?
        /// Cumulative sample count for this stream since recording start (TSMP tag).
        var tsmp: UInt32?
    }

    /// FourCC keys that identify primary sensor data nodes (for TSMP stream association).
    private static let sensorKeys: Set<String> = [
        GPMFKey.accl.rawValue, GPMFKey.gyro.rawValue, GPMFKey.magn.rawValue,
        GPMFKey.gps5.rawValue, GPMFKey.gps9.rawValue, GPMFKey.tmpc.rawValue,
        GPMFKey.cori.rawValue, GPMFKey.grav.rawValue,
    ]

    private static func extractStreamMetadata(_ children: [GpmfNode]) -> StreamMetadata {
        var meta = StreamMetadata()

        for node in children {
            switch node.key {
            case GPMFKey.scal.rawValue:
                let vals = GPMFDecoder.readDoubles(from: node)
                if !vals.isEmpty { meta.scales = vals }

            case GPMFKey.siun.rawValue:
                meta.siun = GPMFDecoder.readString(from: node)

            case GPMFKey.unit.rawValue:
                meta.unit = GPMFDecoder.readString(from: node)

            case GPMFKey.stnm.rawValue:
                meta.stnm = GPMFDecoder.readString(from: node)

            case GPMFKey.orin.rawValue:
                meta.orin = GPMFDecoder.readString(from: node)

            case GPMFKey.gpsf.rawValue:
                let vals = GPMFDecoder.readDoubles(from: node)
                if let v = vals.first { meta.gpsFix = UInt32(v) }

            case GPMFKey.gpsp.rawValue:
                let vals = GPMFDecoder.readDoubles(from: node)
                if let v = vals.first { meta.gpsDop = v / 100.0 }  // GPSP is DOP × 100

            case GPMFKey.gpsu.rawValue:
                meta.gpsu = GPMFDecoder.readString(from: node)

            case GPMFKey.tsmp.rawValue:
                // TSMP is the cumulative sample count for this stream since record start.
                // Typically stored as L (uint32) or J (uint64); read as Double then cast.
                let vals = GPMFDecoder.readDoubles(from: node)
                if let v = vals.first, v >= 0 { meta.tsmp = UInt32(v) }

            default:
                break
            }
        }

        return meta
    }

    // MARK: - IMU Extraction (3-axis with ORIN)

    private static func extractIMUReadings(
        node: GpmfNode,
        scales: [Double],
        orin: String?,
        startTime: TimeInterval,
        duration: TimeInterval
    ) -> [SensorReading] {
        let rawValues = GPMFDecoder.readDoubles(from: node)
        guard let axisCount = node.elementsPerSample, axisCount >= 3 else { return [] }

        let sampleCount = node.repeatCount
        guard sampleCount > 0 else { return [] }

        // Apply SCAL: per-axis if available, otherwise single scale for all
        var scaled = [Double](repeating: 0, count: rawValues.count)
        for i in 0..<rawValues.count {
            let axisIndex = i % axisCount
            let scale = axisIndex < scales.count ? scales[axisIndex] : (scales.first ?? 1.0)
            scaled[i] = scale != 0 ? rawValues[i] / scale : rawValues[i]
        }

        // Build timestamps: linearly distributed within payload duration
        var timestamps = [TimeInterval](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            timestamps[i] = startTime + (Double(i) / Double(sampleCount)) * duration
        }

        // Apply ORIN mapping (only first 3 axes per sample)
        let mapper = ORINMapper(orin: orin)
        var threeAxisValues = [Double]()
        threeAxisValues.reserveCapacity(sampleCount * 3)
        for i in 0..<sampleCount {
            let base = i * axisCount
            guard base + 2 < scaled.count else { break }
            threeAxisValues.append(scaled[base])
            threeAxisValues.append(scaled[base + 1])
            threeAxisValues.append(scaled[base + 2])
        }

        return mapper.mapToReadings(values: threeAxisValues, timestamps: timestamps)
    }

    // MARK: - Orientation Extraction (Quaternion)

    private static func extractOrientationReadings(
        node: GpmfNode,
        scales: [Double],
        startTime: TimeInterval,
        duration: TimeInterval
    ) -> [OrientationReading] {
        let rawValues = GPMFDecoder.readDoubles(from: node)
        guard let axisCount = node.elementsPerSample, axisCount >= 4 else { return [] }

        let sampleCount = node.repeatCount
        guard sampleCount > 0 else { return [] }

        var readings = [OrientationReading]()
        readings.reserveCapacity(sampleCount)

        for i in 0..<sampleCount {
            let base = i * axisCount
            guard base + 3 < rawValues.count else { break }
            let scale = scales.first ?? 1.0
            let t = startTime + (Double(i) / Double(sampleCount)) * duration
            readings.append(OrientationReading(
                timestamp: t,
                w: scale != 0 ? rawValues[base] / scale : rawValues[base],
                x: scale != 0 ? rawValues[base + 1] / scale : rawValues[base + 1],
                y: scale != 0 ? rawValues[base + 2] / scale : rawValues[base + 2],
                z: scale != 0 ? rawValues[base + 3] / scale : rawValues[base + 3]
            ))
        }

        return readings
    }

    // MARK: - GPS5 Extraction

    private static func extractGPS5Readings(
        node: GpmfNode,
        scales: [Double],
        dop: Double?,
        fix: UInt32?,
        startTime: TimeInterval,
        duration: TimeInterval
    ) -> [GpsReading] {
        let rawValues = GPMFDecoder.readDoubles(from: node)
        guard let fieldCount = node.elementsPerSample, fieldCount >= 5 else { return [] }

        let sampleCount = node.repeatCount
        guard sampleCount > 0 else { return [] }

        var readings = [GpsReading]()
        readings.reserveCapacity(sampleCount)

        for i in 0..<sampleCount {
            let base = i * fieldCount
            guard base + 4 < rawValues.count else { break }
            let t = startTime + (Double(i) / Double(sampleCount)) * duration

            func scaled(_ fieldIndex: Int) -> Double {
                let raw = rawValues[base + fieldIndex]
                let s = fieldIndex < scales.count ? scales[fieldIndex] : (scales.first ?? 1.0)
                return s != 0 ? raw / s : raw
            }

            readings.append(GpsReading(
                timestamp: t,
                latitude: scaled(0),
                longitude: scaled(1),
                altitude: scaled(2),
                speed2d: scaled(3),
                speed3d: scaled(4),
                dop: dop,
                fix: fix
            ))
        }

        return readings
    }

    // MARK: - GPS9 Extraction (HERO11+)

    /// Extracts GPS9 readings and returns both first and last valid GPS9 timestamps.
    ///
    /// GPS9 fields: [lat, lon, alt, speed2d, speed3d, daysSince2000, secsSinceMidnight, DOP, fix]
    ///
    /// Both first and last timestamps are captured because GPS accuracy improves
    /// over time as the receiver converges on the leap-second correction.
    /// The last timestamp is generally more reliable.
    private static func extractGPS9Readings(
        node: GpmfNode,
        scales: [Double],
        startTime: TimeInterval,
        duration: TimeInterval
    ) -> (readings: [GpsReading], firstTimestamp: GPS9Timestamp?, lastTimestamp: GPS9Timestamp?) {
        let rawValues = GPMFDecoder.readDoubles(from: node)
        guard let fieldCount = node.elementsPerSample, fieldCount >= 9 else { return ([], nil, nil) }

        let sampleCount = node.repeatCount
        guard sampleCount > 0 else { return ([], nil, nil) }

        var readings = [GpsReading]()
        readings.reserveCapacity(sampleCount)
        var firstTimestamp: GPS9Timestamp?
        var lastTimestamp: GPS9Timestamp?

        for i in 0..<sampleCount {
            let base = i * fieldCount
            guard base + 8 < rawValues.count else { break }
            let t = startTime + (Double(i) / Double(sampleCount)) * duration

            func scaled(_ fieldIndex: Int) -> Double {
                let raw = rawValues[base + fieldIndex]
                let s = fieldIndex < scales.count ? scales[fieldIndex] : (scales.first ?? 1.0)
                return s != 0 ? raw / s : raw
            }

            let fix = UInt32(scaled(8))
            let dop = scaled(7)

            // Extract GPS9 embedded time (fields 5 and 6)
            if fix >= 2 {
                let days = UInt32(scaled(5))
                let secs = scaled(6)
                if days > 0 {
                    let ts = GPS9Timestamp(daysSince2000: days, secondsSinceMidnight: secs)
                    if firstTimestamp == nil {
                        firstTimestamp = ts
                    }
                    lastTimestamp = ts
                }
            }

            readings.append(GpsReading(
                timestamp: t,
                latitude: scaled(0),
                longitude: scaled(1),
                altitude: scaled(2),
                speed2d: scaled(3),
                speed3d: scaled(4),
                dop: dop > 0 ? dop : nil,
                fix: fix
            ))
        }

        return (readings, firstTimestamp, lastTimestamp)
    }

    // MARK: - Temperature Extraction

    private static func extractTemperatureReadings(
        node: GpmfNode,
        scales: [Double],
        startTime: TimeInterval,
        duration: TimeInterval
    ) -> [TemperatureReading] {
        let rawValues = GPMFDecoder.readDoubles(from: node)
        let sampleCount = node.repeatCount
        guard sampleCount > 0 else { return [] }

        let scale = scales.first ?? 1.0

        var readings = [TemperatureReading]()
        readings.reserveCapacity(sampleCount)

        for i in 0..<sampleCount where i < rawValues.count {
            let t = startTime + (Double(i) / Double(sampleCount)) * duration
            let celsius = scale != 0 ? rawValues[i] / scale : rawValues[i]
            readings.append(TemperatureReading(timestamp: t, celsius: celsius))
        }

        return readings
    }
}
