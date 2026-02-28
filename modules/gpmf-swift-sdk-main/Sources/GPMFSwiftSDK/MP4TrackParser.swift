import Foundation

/// A timed GPMF payload extracted from the MP4 metadata track.
public struct TimedPayload: Sendable {
    /// Payload start time relative to track start (seconds).
    public let time: TimeInterval
    /// Payload duration (seconds).
    public let duration: TimeInterval
    /// Raw GPMF binary data.
    public let data: Data
}

/// Parses an MP4 file to extract timed GPMF payloads from the metadata track.
///
/// Navigates the MP4 atom hierarchy:
/// `moov → trak → mdia → hdlr(meta) → minf → stbl → {stsz, stco/co64, stts, stsc, mdhd}`
///
/// Supports both 32-bit (`stco`) and 64-bit (`co64`) chunk offsets, and uses
/// `stsc` (sample-to-chunk) + `stts` (sample-to-time) for correct timing.
final class MP4TrackParser {

    // MARK: - Properties

    private let fileHandle: FileHandle
    private let fileSize: UInt64

    // MARK: - Init

    init(url: URL) throws {
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw GPMFError.fileOpenFailed(url.path)
        }
        self.fileHandle = try FileHandle(forReadingFrom: url)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        self.fileSize = attrs[.size] as? UInt64 ?? 0
    }

    deinit {
        try? fileHandle.close()
    }

    // MARK: - Public API

    /// Result of MP4 parsing: timed payloads + file-level metadata.
    struct MP4ParseResult {
        let payloads: [TimedPayload]
        /// Creation time from the `mvhd` atom (camera internal RTC / filesystem clock).
        /// WARNING: This is NOT satellite time. See TelemetryData.mp4CreationTime docs.
        let mp4CreationTime: Date?
    }

    /// Extracts all GPMF payloads with timing from the MP4 metadata track,
    /// plus file-level metadata from `mvhd`.
    func extractTimedPayloadsWithMetadata() throws -> MP4ParseResult {
        // 1. Find 'moov' atom at file level
        guard let moov = findAtomInFile(name: "moov", start: 0, end: fileSize) else {
            throw GPMFError.atomNotFound("moov")
        }
        let moovData = try readFromFile(at: moov.offset, length: Int(moov.size))

        // 2. Extract mp4 creation time from mvhd (file-level, not track-level)
        let creationTime = readMvhdCreationTime(moovData: moovData, moovSize: Int(moov.size))

        // 3. Scan trak atoms inside moov
        var offset = 8  // skip moov header
        let moovEnd = Int(moov.size)

        while offset < moovEnd - 8 {
            guard let trak = findAtomInData(moovData, name: "trak", start: offset, end: moovEnd) else {
                break
            }
            if let payloads = try extractFromTrack(moovData: moovData, trakOffset: trak.offset, trakSize: trak.size) {
                return MP4ParseResult(payloads: payloads, mp4CreationTime: creationTime)
            }
            offset = trak.offset + trak.size
        }

        throw GPMFError.noMetadataTrack
    }

    /// Convenience: extracts only the timed payloads (without file-level metadata).
    func extractTimedPayloads() throws -> [TimedPayload] {
        try extractTimedPayloadsWithMetadata().payloads
    }

    // MARK: - Track Extraction

    private func extractFromTrack(moovData: Data, trakOffset: Int, trakSize: Int) throws -> [TimedPayload]? {
        let trakEnd = trakOffset + trakSize

        // trak → mdia
        guard let mdia = findAtomInData(moovData, name: "mdia", start: trakOffset + 8, end: trakEnd) else { return nil }
        let mdiaEnd = mdia.offset + mdia.size

        // mdia → hdlr — check handler type
        guard isMetadataTrack(moovData: moovData, mdiaOffset: mdia.offset, mdiaEnd: mdiaEnd) else { return nil }

        // mdia → mdhd — read timescale
        let timescale = readTimescale(moovData: moovData, mdiaOffset: mdia.offset, mdiaEnd: mdiaEnd)

        // mdia → minf → stbl
        guard let minf = findAtomInData(moovData, name: "minf", start: mdia.offset + 8, end: mdiaEnd),
              let stbl = findAtomInData(moovData, name: "stbl", start: minf.offset + 8, end: minf.offset + minf.size)
        else { return nil }
        let stblEnd = stbl.offset + stbl.size

        // stsz — sample sizes
        guard let stsz = findAtomInData(moovData, name: "stsz", start: stbl.offset + 8, end: stblEnd) else {
            return nil
        }
        let sampleSizes = parseStsz(moovData, atomOffset: stsz.offset, atomSize: stsz.size)
        guard !sampleSizes.isEmpty else { return nil }

        // stco or co64 — chunk offsets
        let chunkOffsets: [UInt64]
        if let co64 = findAtomInData(moovData, name: "co64", start: stbl.offset + 8, end: stblEnd) {
            chunkOffsets = parseCo64(moovData, atomOffset: co64.offset, atomSize: co64.size)
        } else if let stco = findAtomInData(moovData, name: "stco", start: stbl.offset + 8, end: stblEnd) {
            chunkOffsets = parseStco(moovData, atomOffset: stco.offset, atomSize: stco.size)
        } else {
            return nil
        }
        guard !chunkOffsets.isEmpty else { return nil }

        // stsc — sample-to-chunk mapping
        let stscEntries: [StscEntry]
        if let stsc = findAtomInData(moovData, name: "stsc", start: stbl.offset + 8, end: stblEnd) {
            stscEntries = parseStsc(moovData, atomOffset: stsc.offset, atomSize: stsc.size)
        } else {
            // Default: 1 sample per chunk
            stscEntries = [StscEntry(firstChunk: 1, samplesPerChunk: 1, sampleDescriptionIndex: 1)]
        }

        // stts — sample-to-time (durations)
        let sttsEntries: [SttsEntry]
        if let stts = findAtomInData(moovData, name: "stts", start: stbl.offset + 8, end: stblEnd) {
            sttsEntries = parseStts(moovData, atomOffset: stts.offset, atomSize: stts.size)
        } else {
            sttsEntries = []
        }

        // Build sample table: for each sample → (fileOffset, size, time, duration)
        let sampleTable = buildSampleTable(
            sampleSizes: sampleSizes,
            chunkOffsets: chunkOffsets,
            stscEntries: stscEntries,
            sttsEntries: sttsEntries,
            timescale: timescale
        )

        // Read each sample payload from disk
        var payloads: [TimedPayload] = []
        payloads.reserveCapacity(sampleTable.count)

        for entry in sampleTable {
            do {
                let data = try readFromFile(at: entry.fileOffset, length: entry.size)
                payloads.append(TimedPayload(time: entry.time, duration: entry.duration, data: data))
            } catch {
                break  // file truncated or corrupt
            }
        }

        return payloads
    }

    // MARK: - Handler Detection

    private func isMetadataTrack(moovData: Data, mdiaOffset: Int, mdiaEnd: Int) -> Bool {
        // Check hdlr for 'meta' handler type
        guard let hdlr = findAtomInData(moovData, name: "hdlr", start: mdiaOffset + 8, end: mdiaEnd) else {
            return false
        }
        // hdlr layout: [8 header][4 version/flags][4 predefined][4 handler_type]...
        let handlerTypeOffset = hdlr.offset + 16
        guard handlerTypeOffset + 4 <= moovData.count else { return false }
        let htBytes = moovData[moovData.startIndex + handlerTypeOffset ..< moovData.startIndex + handlerTypeOffset + 4]
        let handlerType = String(data: Data(htBytes), encoding: .ascii)

        if handlerType == GPMF.HANDLER_SUBTYPE { return true }

        // Fallback: check stsd for 'gpmd' format
        guard let minf = findAtomInData(moovData, name: "minf", start: mdiaOffset + 8, end: mdiaEnd),
              let stbl = findAtomInData(moovData, name: "stbl", start: minf.offset + 8, end: minf.offset + minf.size),
              let stsd = findAtomInData(moovData, name: "stsd", start: stbl.offset + 8, end: stbl.offset + stbl.size)
        else { return false }

        // stsd layout: [8 header][4 version/flags][4 entry_count][entry: 4 size, 4 format...]
        let formatOffset = stsd.offset + 20
        guard formatOffset + 4 <= moovData.count else { return false }
        let fmtBytes = moovData[moovData.startIndex + formatOffset ..< moovData.startIndex + formatOffset + 4]
        let format = String(data: Data(fmtBytes), encoding: .ascii)
        return format == GPMF.SAMPLE_FORMAT
    }

    // MARK: - mvhd Creation Time

    /// MP4 epoch: seconds between 1904-01-01 and 1970-01-01.
    private static let mp4EpochOffset: TimeInterval = 2_082_844_800

    /// Reads creation_time from the `mvhd` (Movie Header) atom.
    ///
    /// `mvhd` is a direct child of `moov`. Its creation_time field is the camera's
    /// internal RTC value at the moment of recording — NOT satellite-derived.
    ///
    /// Layout:
    /// - v0: [8 header][1 version][3 flags][4 creation_time][4 modification_time][4 timescale][4 duration]
    /// - v1: [8 header][1 version][3 flags][8 creation_time][8 modification_time][4 timescale][8 duration]
    ///
    /// creation_time is seconds since 1904-01-01T00:00:00 UTC (MP4 epoch).
    private func readMvhdCreationTime(moovData: Data, moovSize: Int) -> Date? {
        guard let mvhd = findAtomInData(moovData, name: "mvhd", start: 8, end: moovSize) else {
            return nil
        }
        let versionOffset = mvhd.offset + 8
        guard versionOffset < moovData.count else { return nil }
        let version = moovData[moovData.startIndex + versionOffset]

        let creationTimeSeconds: UInt64
        if version == 0 {
            // v0: creation_time is 4 bytes at offset 12 from atom start
            let ctOffset = mvhd.offset + 12
            guard ctOffset + 4 <= moovData.count else { return nil }
            creationTimeSeconds = UInt64(readUInt32BE(moovData, at: ctOffset))
        } else {
            // v1: creation_time is 8 bytes at offset 12 from atom start
            let ctOffset = mvhd.offset + 12
            guard ctOffset + 8 <= moovData.count else { return nil }
            creationTimeSeconds = readUInt64BE(moovData, at: ctOffset)
        }

        // Convert from MP4 epoch (1904) to Unix epoch (1970)
        guard creationTimeSeconds > 0 else { return nil }
        let unixTimestamp = Double(creationTimeSeconds) - Self.mp4EpochOffset
        guard unixTimestamp > 0 else { return nil }  // sanity check
        return Date(timeIntervalSince1970: unixTimestamp)
    }

    // MARK: - Timescale (mdhd)

    private func readTimescale(moovData: Data, mdiaOffset: Int, mdiaEnd: Int) -> UInt32 {
        guard let mdhd = findAtomInData(moovData, name: "mdhd", start: mdiaOffset + 8, end: mdiaEnd) else {
            return 1000  // sensible default
        }
        // mdhd: [8 header][1 version][3 flags]...
        let versionOffset = mdhd.offset + 8
        guard versionOffset < moovData.count else { return 1000 }
        let version = moovData[moovData.startIndex + versionOffset]

        let timescaleOffset: Int
        if version == 0 {
            // v0: [4 creation][4 modification][4 timescale][4 duration]
            timescaleOffset = mdhd.offset + 20
        } else {
            // v1: [8 creation][8 modification][4 timescale][8 duration]
            timescaleOffset = mdhd.offset + 28
        }
        guard timescaleOffset + 4 <= moovData.count else { return 1000 }
        return readUInt32BE(moovData, at: timescaleOffset)
    }

    // MARK: - Sample Table Construction

    private struct SampleTableEntry {
        let fileOffset: UInt64
        let size: Int
        let time: TimeInterval
        let duration: TimeInterval
    }

    private func buildSampleTable(
        sampleSizes: [UInt32],
        chunkOffsets: [UInt64],
        stscEntries: [StscEntry],
        sttsEntries: [SttsEntry],
        timescale: UInt32
    ) -> [SampleTableEntry] {

        let totalSamples = sampleSizes.count
        var entries: [SampleTableEntry] = []
        entries.reserveCapacity(totalSamples)

        // 1. Map each sample to its file offset using stsc + chunk offsets
        var sampleFileOffsets = [UInt64](repeating: 0, count: totalSamples)
        var sampleIndex = 0
        let chunkCount = chunkOffsets.count

        for chunkIndex in 0..<chunkCount {
            let samplesInChunk = samplesPerChunk(forChunkIndex: chunkIndex, stscEntries: stscEntries)
            var offsetInChunk: UInt64 = 0
            for _ in 0..<samplesInChunk {
                guard sampleIndex < totalSamples else { break }
                sampleFileOffsets[sampleIndex] = chunkOffsets[chunkIndex] + offsetInChunk
                offsetInChunk += UInt64(sampleSizes[sampleIndex])
                sampleIndex += 1
            }
        }

        // 2. Compute time for each sample using stts
        let ts = Double(max(timescale, 1))
        var sampleTimes = [TimeInterval](repeating: 0, count: totalSamples)
        var sampleDurations = [TimeInterval](repeating: 0, count: totalSamples)

        if !sttsEntries.isEmpty {
            var si = 0
            var currentTime: UInt64 = 0
            for entry in sttsEntries {
                for _ in 0..<entry.sampleCount {
                    guard si < totalSamples else { break }
                    sampleTimes[si] = Double(currentTime) / ts
                    sampleDurations[si] = Double(entry.sampleDelta) / ts
                    currentTime += UInt64(entry.sampleDelta)
                    si += 1
                }
            }
        } else {
            // Fallback: assume equal spacing, estimate 1 second per sample
            for si in 0..<totalSamples {
                sampleTimes[si] = Double(si)
                sampleDurations[si] = 1.0
            }
        }

        // 3. Build final table
        let count = min(sampleIndex, totalSamples)
        for i in 0..<count {
            entries.append(SampleTableEntry(
                fileOffset: sampleFileOffsets[i],
                size: Int(sampleSizes[i]),
                time: sampleTimes[i],
                duration: sampleDurations[i]
            ))
        }

        return entries
    }

    /// Returns how many samples belong to the chunk at `chunkIndex` (0-based).
    private func samplesPerChunk(forChunkIndex chunkIndex: Int, stscEntries: [StscEntry]) -> Int {
        // stsc entries use 1-based chunk numbers
        let chunkNumber = chunkIndex + 1
        var samplesPerChunk = 1
        for entry in stscEntries {
            if Int(entry.firstChunk) <= chunkNumber {
                samplesPerChunk = Int(entry.samplesPerChunk)
            } else {
                break
            }
        }
        return samplesPerChunk
    }

    // MARK: - Atom Parsing Helpers

    private struct StscEntry {
        let firstChunk: UInt32      // 1-based
        let samplesPerChunk: UInt32
        let sampleDescriptionIndex: UInt32
    }

    private struct SttsEntry {
        let sampleCount: UInt32
        let sampleDelta: UInt32
    }

    private func parseStsz(_ data: Data, atomOffset: Int, atomSize: Int) -> [UInt32] {
        // [8 header][4 ver/flags][4 sample_size][4 sample_count][entries...]
        let base = atomOffset + 8   // skip atom header
        guard base + 12 <= atomOffset + atomSize else { return [] }
        let defaultSize = readUInt32BE(data, at: base + 4)
        let count = Int(readUInt32BE(data, at: base + 8))

        if defaultSize != 0 {
            return [UInt32](repeating: defaultSize, count: count)
        }
        var sizes = [UInt32]()
        sizes.reserveCapacity(count)
        for i in 0..<count {
            let off = base + 12 + (i * 4)
            guard off + 4 <= atomOffset + atomSize else { break }
            sizes.append(readUInt32BE(data, at: off))
        }
        return sizes
    }

    private func parseStco(_ data: Data, atomOffset: Int, atomSize: Int) -> [UInt64] {
        let base = atomOffset + 8
        guard base + 8 <= atomOffset + atomSize else { return [] }
        let count = Int(readUInt32BE(data, at: base + 4))
        var offsets = [UInt64]()
        offsets.reserveCapacity(count)
        for i in 0..<count {
            let off = base + 8 + (i * 4)
            guard off + 4 <= atomOffset + atomSize else { break }
            offsets.append(UInt64(readUInt32BE(data, at: off)))
        }
        return offsets
    }

    private func parseCo64(_ data: Data, atomOffset: Int, atomSize: Int) -> [UInt64] {
        let base = atomOffset + 8
        guard base + 8 <= atomOffset + atomSize else { return [] }
        let count = Int(readUInt32BE(data, at: base + 4))
        var offsets = [UInt64]()
        offsets.reserveCapacity(count)
        for i in 0..<count {
            let off = base + 8 + (i * 8)
            guard off + 8 <= atomOffset + atomSize else { break }
            offsets.append(readUInt64BE(data, at: off))
        }
        return offsets
    }

    private func parseStsc(_ data: Data, atomOffset: Int, atomSize: Int) -> [StscEntry] {
        let base = atomOffset + 8
        guard base + 8 <= atomOffset + atomSize else { return [] }
        let count = Int(readUInt32BE(data, at: base + 4))
        var entries = [StscEntry]()
        entries.reserveCapacity(count)
        for i in 0..<count {
            let off = base + 8 + (i * 12)
            guard off + 12 <= atomOffset + atomSize else { break }
            entries.append(StscEntry(
                firstChunk: readUInt32BE(data, at: off),
                samplesPerChunk: readUInt32BE(data, at: off + 4),
                sampleDescriptionIndex: readUInt32BE(data, at: off + 8)
            ))
        }
        return entries
    }

    private func parseStts(_ data: Data, atomOffset: Int, atomSize: Int) -> [SttsEntry] {
        let base = atomOffset + 8
        guard base + 8 <= atomOffset + atomSize else { return [] }
        let count = Int(readUInt32BE(data, at: base + 4))
        var entries = [SttsEntry]()
        entries.reserveCapacity(count)
        for i in 0..<count {
            let off = base + 8 + (i * 8)
            guard off + 8 <= atomOffset + atomSize else { break }
            entries.append(SttsEntry(
                sampleCount: readUInt32BE(data, at: off),
                sampleDelta: readUInt32BE(data, at: off + 4)
            ))
        }
        return entries
    }

    // MARK: - Atom Search

    /// Finds an atom in the file by reading from disk.
    private func findAtomInFile(name: String, start: UInt64, end: UInt64) -> (offset: UInt64, size: UInt64)? {
        var current = start
        while current + 8 <= end {
            guard let header = try? readFromFile(at: current, length: 8) else { break }
            var size = UInt64(readUInt32BE(header, at: 0))
            let atomName = String(data: header[4..<8], encoding: .ascii)

            if size == 1 {
                // 64-bit extended size
                guard let extHeader = try? readFromFile(at: current + 8, length: 8) else { break }
                size = readUInt64BE(extHeader, at: 0)
            }
            guard size >= 8 else { break }

            if atomName == name {
                return (current, size)
            }
            current += size
        }
        return nil
    }

    /// Finds an atom within an in-memory Data buffer.
    private func findAtomInData(_ data: Data, name: String, start: Int, end: Int) -> (offset: Int, size: Int)? {
        var current = start
        while current + 8 <= end {
            let size = Int(readUInt32BE(data, at: current))
            guard size >= 8, current + size <= end else { break }
            let nameStart = data.startIndex + current + 4
            let atomName = String(data: data[nameStart..<nameStart + 4], encoding: .ascii)
            if atomName == name {
                return (current, size)
            }
            current += size
        }
        return nil
    }

    // MARK: - Low-Level I/O

    private func readFromFile(at offset: UInt64, length: Int) throws -> Data {
        try fileHandle.seek(toOffset: offset)
        guard let data = try fileHandle.read(upToCount: length), data.count == length else {
            throw GPMFError.invalidMP4Structure("Read failed at offset \(offset), length \(length)")
        }
        return data
    }

    private func readUInt32BE(_ data: Data, at localOffset: Int) -> UInt32 {
        let start = data.startIndex + localOffset
        // loadUnaligned: MP4 atom fields sit at arbitrary byte offsets within the
        // moovData buffer, which is not guaranteed to be 4-byte aligned on ARM64.
        return data[start..<start + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian
    }

    private func readUInt64BE(_ data: Data, at localOffset: Int) -> UInt64 {
        let start = data.startIndex + localOffset
        return data[start..<start + 8].withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.bigEndian
    }
}
