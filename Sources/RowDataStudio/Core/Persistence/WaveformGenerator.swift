// Core/Persistence/WaveformGenerator.swift v1.0.0
/**
 * Audio waveform peak-envelope generator.
 *
 * Extracts the audio track from a GoPro MP4, reads Float32 samples via AVFoundation,
 * builds a 5-level min/max peak pyramid using vDSP, compresses the result as
 * lz4-compressed JSON, and writes a `.waveform.gz` sidecar alongside the video.
 *
 * The `build(from:sampleRate:)` static method is the pure computation kernel —
 * it is exposed separately so it can be tested without a real video file.
 *
 * Pipeline:
 *   AVAsset → AVAssetReaderTrackOutput (mono Float32) →
 *   ContiguousArray<Float> →
 *   Level 0: vDSP_minv/vDSP_maxv per 256-sample bin →
 *   Levels 1–4: min-of-mins / max-of-maxes over groups of 4 →
 *   JSONEncoder → lz4 → .waveform.gz
 *
 * Naming convention: `{videoBasename}.waveform.gz` (next to `.telemetry.gz`)
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-14 - Initial implementation (Phase 8c.6).
 */

import Foundation
import AVFoundation
import Accelerate

// MARK: - Errors

public enum WaveformGeneratorError: LocalizedError {
    case fileNotFound(URL)
    case noAudioTrack
    case readerSetupFailed(Error)
    case readFailed(Error)
    case compressionFailed(Error)
    case writeFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):        return "Video file not found: \(url.lastPathComponent)"
        case .noAudioTrack:                 return "Video has no audio track"
        case .readerSetupFailed(let e):     return "AVAssetReader setup failed: \(e.localizedDescription)"
        case .readFailed(let e):            return "Audio read failed: \(e.localizedDescription)"
        case .compressionFailed(let e):     return "Compression failed: \(e.localizedDescription)"
        case .writeFailed(let e):           return "Sidecar write failed: \(e.localizedDescription)"
        }
    }
}

// MARK: - WaveformGenerator

/// Generates and persists audio waveform peak sidecars.
public struct WaveformGenerator {

    // MARK: - Public API

    /// Generate a waveform sidecar from a video file's audio track.
    ///
    /// Reads audio on a background thread, builds the peak pyramid, and writes
    /// `{videoBasename}.waveform.gz` to `outputDir`.
    ///
    /// - Parameters:
    ///   - videoURL:   URL of the GoPro MP4 (or any video with an audio track).
    ///   - outputDir:  Directory where the `.waveform.gz` file is written.
    /// - Returns:      URL of the written sidecar file.
    public static func generate(from videoURL: URL, outputDir: URL) async throws -> URL {
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw WaveformGeneratorError.fileNotFound(videoURL)
        }

        // Read audio samples and derive sample rate on a background thread
        let (samples, sampleRate) = try await Task.detached(priority: .utility) {
            try readAudioSamples(from: videoURL)
        }.value

        // Build peak pyramid
        let peaks = build(from: samples, sampleRate: sampleRate)

        // Encode + compress + write
        let fileURL = outputDir
            .appendingPathComponent(videoURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("waveform.gz")

        try persist(peaks, to: fileURL)
        return fileURL
    }

    // MARK: - Pure kernel (exposed for testing)

    /// Build a 5-level peak pyramid from raw Float32 samples.
    ///
    /// Uses `vDSP_minv` / `vDSP_maxv` for level 0 (256 samples/bin).
    /// Levels 1–4 are derived by taking the min-of-mins / max-of-maxes
    /// of every 4 consecutive bins from the previous level.
    ///
    /// - Parameters:
    ///   - samples:    Audio samples (mono Float32, any sample rate).
    ///   - sampleRate: Samples per second (used for `WaveformPeaks.sampleRate`).
    /// - Returns: `WaveformPeaks` with 5 pyramid levels.
    public static func build(
        from samples: ContiguousArray<Float>,
        sampleRate: Int
    ) -> WaveformPeaks {
        let level0 = buildLevel0(samples: samples)
        var pyramid: [[PeakPair]] = [level0]

        var prevLevel = level0
        for _ in 1..<WaveformPeaks.samplesPerBin.count {
            let next = deriveLevel(from: prevLevel)
            pyramid.append(next)
            prevLevel = next
        }

        return WaveformPeaks(
            sampleRate:   sampleRate,
            totalSamples: samples.count,
            levels:       pyramid
        )
    }

    // MARK: - Persistence

    /// Load a waveform sidecar from disk.
    public static func load(from fileURL: URL) throws -> WaveformPeaks {
        let compressed = try Data(contentsOf: fileURL)
        let jsonData: Data
        do {
            jsonData = try (compressed as NSData).decompressed(using: .lz4) as Data
        } catch {
            throw WaveformGeneratorError.compressionFailed(error)
        }
        return try JSONDecoder().decode(WaveformPeaks.self, from: jsonData)
    }

    // MARK: - Private: peak computation

    /// Build level 0: 256 samples/bin using vDSP min/max.
    private static func buildLevel0(samples: ContiguousArray<Float>) -> [PeakPair] {
        let binSize = WaveformPeaks.samplesPerBin[0]    // 256
        let numBins = samples.count / binSize
        guard numBins > 0 else {
            // Fewer samples than one bin — return single pair covering all samples
            guard !samples.isEmpty else { return [] }
            var mn: Float = 0, mx: Float = 0
            samples.withUnsafeBufferPointer { ptr in
                vDSP_minv(ptr.baseAddress!, 1, &mn, vDSP_Length(samples.count))
                vDSP_maxv(ptr.baseAddress!, 1, &mx, vDSP_Length(samples.count))
            }
            return [PeakPair(min: mn, max: mx)]
        }

        var result = [PeakPair]()
        result.reserveCapacity(numBins + 1)

        samples.withUnsafeBufferPointer { ptr in
            let base = ptr.baseAddress!

            for i in 0..<numBins {
                var mn: Float = 0
                var mx: Float = 0
                vDSP_minv(base + i * binSize, 1, &mn, vDSP_Length(binSize))
                vDSP_maxv(base + i * binSize, 1, &mx, vDSP_Length(binSize))
                result.append(PeakPair(min: mn, max: mx))
            }

            // Tail samples (< binSize)
            let tailStart = numBins * binSize
            let tailCount = samples.count - tailStart
            if tailCount > 0 {
                var mn: Float = 0
                var mx: Float = 0
                vDSP_minv(base + tailStart, 1, &mn, vDSP_Length(tailCount))
                vDSP_maxv(base + tailStart, 1, &mx, vDSP_Length(tailCount))
                result.append(PeakPair(min: mn, max: mx))
            }
        }

        return result
    }

    /// Derive the next coarser level: groups of 4 bins → one bin (min-of-mins, max-of-maxes).
    private static func deriveLevel(from prev: [PeakPair]) -> [PeakPair] {
        guard !prev.isEmpty else { return [] }
        var result = [PeakPair]()
        result.reserveCapacity(prev.count / 4 + 1)

        var i = 0
        while i + 3 < prev.count {
            let mn = min(prev[i].min, prev[i+1].min, prev[i+2].min, prev[i+3].min)
            let mx = max(prev[i].max, prev[i+1].max, prev[i+2].max, prev[i+3].max)
            result.append(PeakPair(min: mn, max: mx))
            i += 4
        }
        // Partial tail (1–3 bins)
        if i < prev.count {
            let tail = prev[i...]
            let mn = tail.map(\.min).min() ?? 0
            let mx = tail.map(\.max).max() ?? 0
            result.append(PeakPair(min: mn, max: mx))
        }
        return result
    }

    // MARK: - Private: file I/O

    private static func persist(_ peaks: WaveformPeaks, to fileURL: URL) throws {
        let jsonData: Data
        do { jsonData = try JSONEncoder().encode(peaks) }
        catch { throw WaveformGeneratorError.compressionFailed(error) }

        let compressed: Data
        do { compressed = try (jsonData as NSData).compressed(using: .lz4) as Data }
        catch { throw WaveformGeneratorError.compressionFailed(error) }

        do { try compressed.write(to: fileURL, options: .atomic) }
        catch { throw WaveformGeneratorError.writeFailed(error) }
    }

    // MARK: - Private: AVFoundation audio extraction

    /// Returns (samples, sampleRate) by reading the first audio track of the video.
    private static func readAudioSamples(from videoURL: URL) throws -> (ContiguousArray<Float>, Int) {
        let asset = AVAsset(url: videoURL)

        // Load audio tracks synchronously (legacy sync API for background-thread use)
        let semaphore = DispatchSemaphore(value: 0)
        var audioTracks: [AVAssetTrack] = []
        asset.loadTracks(withMediaType: .audio) { tracks, _ in
            audioTracks = tracks ?? []
            semaphore.signal()
        }
        semaphore.wait()

        guard let audioTrack = audioTracks.first else {
            throw WaveformGeneratorError.noAudioTrack
        }

        // Target: mono Float32 at native rate
        let outputSettings: [String: Any] = [
            AVFormatIDKey:              kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey:     32,
            AVLinearPCMIsFloatKey:      true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey:  false,
            AVNumberOfChannelsKey:      1
        ]

        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) }
        catch { throw WaveformGeneratorError.readerSetupFailed(error) }

        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(output)

        guard reader.startReading() else {
            throw WaveformGeneratorError.readFailed(
                reader.error ?? NSError(domain: "WaveformGenerator", code: -1)
            )
        }

        // Detect sample rate from the track's format description
        var detectedSampleRate = 48_000
        if let fmtDesc = audioTrack.formatDescriptions.first {
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(
                fmtDesc as! CMAudioFormatDescription
            )?.pointee
            if let sr = asbd?.mSampleRate, sr > 0 {
                detectedSampleRate = Int(sr)
            }
        }

        var samples = ContiguousArray<Float>()
        samples.reserveCapacity(detectedSampleRate * 600)  // ~10 min at detected rate

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            var totalLength = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(
                blockBuffer, atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &totalLength,
                dataPointerOut: &dataPointer
            )
            guard let rawPtr = dataPointer, totalLength > 0 else { continue }
            let floatCount = totalLength / MemoryLayout<Float>.size
            rawPtr.withMemoryRebound(to: Float.self, capacity: floatCount) { floatPtr in
                samples.append(contentsOf: UnsafeBufferPointer(start: floatPtr, count: floatCount))
            }
        }

        return (samples, detectedSampleRate)
    }
}
