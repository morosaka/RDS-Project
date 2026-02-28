import Foundation

/// Errors produced by the GPMFSwiftSDK.
public enum GPMFError: Error, Sendable, Equatable {

    // MARK: MP4 Parsing

    /// The MP4 file could not be opened for reading.
    case fileOpenFailed(String)

    /// A required MP4 atom was not found.
    case atomNotFound(String)

    /// The MP4 structure is malformed or truncated.
    case invalidMP4Structure(String)

    /// No GPMF metadata track found in the MP4 file.
    case noMetadataTrack

    // MARK: GPMF Decoding

    /// The GPMF payload is too small to contain a valid KLV header.
    ///
    /// - Note: Currently, the decoder returns an empty node array rather than throwing
    ///   when the payload is undersized. This case is reserved for a future strict-mode
    ///   decoder that surfaces truncation errors to the caller.
    case payloadTooSmall

    /// A GPMF KLV entry has an invalid or unsupported structure.
    case invalidKLV(String)

    /// An unsupported GPMF value type was encountered.
    ///
    /// - Note: Currently, unsupported types are silently skipped by the decoder.
    ///   This case is reserved for a future strict-mode decoder.
    case unsupportedValueType(UInt8)

    // MARK: Data Extraction

    /// The ORIN string is missing or malformed.
    ///
    /// - Note: Currently, `ORINMapper` returns `nil` on invalid ORIN and falls back
    ///   to the unmapped raw channel order. This case is reserved for future strict
    ///   validation that propagates ORIN errors to the caller.
    case invalidORIN(String)

    /// Expected stream data (e.g. SCAL) is missing.
    ///
    /// - Note: Currently, missing metadata causes the extractor to use safe defaults
    ///   (e.g., `SCAL = [1.0]`). This case is reserved for future strict extraction.
    case missingStreamMetadata(String)

    /// A read operation attempted to access beyond available data.
    ///
    /// - Note: Currently, `InputStream` and `GPMFDecoder` return `nil`/empty rather
    ///   than throwing on out-of-bounds reads. This case is reserved for a future
    ///   throwing read path.
    case readBeyondEnd

    // MARK: Chapter Stitching

    /// A filename does not match the GoPro chapter pattern `[A-Z]{2}[0-9]{6}.MP4`.
    case unrecognizedChapterFilename(String)

    /// Chapter files have different session IDs (NNNN) — they are from different recordings.
    case mixedSessionIDs([String])

    /// Chapter numbers (CC) are not consecutive — one or more chapters are missing.
    case nonConsecutiveChapters([Int])

    /// TSMP (cumulative sample count) is incoherent between consecutive chapters,
    /// suggesting the files are not from the same continuous recording session.
    /// `stream` is the FourCC key, `betweenChapters` is the 1-based index of the
    /// chapter pair where the mismatch was detected (e.g. 1 = between ch1 and ch2).
    case tsmpIncoherence(stream: String, betweenChapters: Int)
}
