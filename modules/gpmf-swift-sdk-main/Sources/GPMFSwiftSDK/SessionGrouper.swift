import Foundation

/// Groups an unordered collection of GoPro MP4 files by recording session,
/// ready for chapter stitching and extraction.
///
/// ## What this solves
///
/// A real training session often produces a mixed bag of files:
/// - Multiple recording sessions (separate start/stop events) from the same camera
/// - Chapter splits within long recordings (GoPro splits at ~4 GB)
/// - Files from different cameras (different prefix: GH, GX, GL)
/// - Non-GoPro files in the same directory (FIT files, etc.)
///
/// `SessionGrouper` takes all these URLs and returns organized groups — one per
/// recording session — sorted and ready for extraction.
///
/// ## Design principle: organizer, not gatekeeper
///
/// `group()` **never throws**. Non-GoPro files are silently skipped (tolerant reader).
/// The consuming application applies domain-specific filtering on the returned groups
/// (e.g., "only GH sessions", "only sessions 1121–1125").
///
/// ## Usage
///
/// ```swift
/// // Pure grouping (no file I/O)
/// let groups = SessionGrouper.group(allURLs)
/// // → [SessionGroup] sorted by prefix, then session ID
///
/// // Filter by camera prefix
/// let ghSessions = groups.filter { $0.prefix == "GH" }
///
/// // Extract each group
/// for group in ghSessions {
///     let telemetry = try ChapterStitcher.stitch(group.chapterURLs)
/// }
///
/// // Or one-shot: group + stitch everything
/// let sessions = try SessionGrouper.extractAll(allURLs)
/// ```
///
/// ## Sorting
///
/// Groups are sorted by prefix (alphabetical), then by session ID (string ascending).
/// Within the same prefix, GoPro increments session IDs chronologically on the same
/// SD card, so this order is chronological for same-camera files.
/// Cross-camera ordering requires absolute timestamps and is the app's responsibility.
public struct SessionGrouper {

    private init() {}

    // MARK: - Public API

    /// Groups GoPro MP4 URLs by `(prefix, sessionID)`.
    ///
    /// - Non-GoPro files (FIT, txt, non-standard MP4 names) are silently skipped.
    /// - Chapters within each group are sorted by chapter number (ascending).
    /// - Groups are sorted by prefix (alphabetical), then session ID (ascending).
    /// - Never throws — returns an empty array if no valid GoPro files are found.
    ///
    /// - Parameter urls: File URLs in any order, potentially mixed with non-GoPro files.
    /// - Returns: Sorted array of `SessionGroup`, one per distinct `(prefix, sessionID)` pair.
    public static func group(_ urls: [URL]) -> [SessionGroup] {
        // 1. Parse all URLs, silently skip non-GoPro files
        let parsed = urls.compactMap { ChapterStitcher.parseChapterInfo($0) }
        guard !parsed.isEmpty else { return [] }

        // 2. Group by (prefix, sessionID)
        let grouped = Dictionary(grouping: parsed) { GroupKey(prefix: $0.prefix, sessionID: $0.sessionID) }

        // 3. Build SessionGroup for each group, sorting chapters within
        var groups: [SessionGroup] = grouped.map { key, chapters in
            let sortedURLs = chapters
                .sorted { $0.chapterNumber < $1.chapterNumber }
                .map(\.url)
            return SessionGroup(
                prefix: key.prefix,
                sessionID: key.sessionID,
                chapterURLs: sortedURLs
            )
        }

        // 4. Sort groups: primary by prefix, secondary by sessionID
        groups.sort { lhs, rhs in
            if lhs.prefix != rhs.prefix { return lhs.prefix < rhs.prefix }
            return lhs.sessionID < rhs.sessionID
        }

        return groups
    }

    /// Groups and extracts all sessions in one call.
    ///
    /// Pipeline:
    /// 1. Groups URLs via `group(_:)` (non-GoPro files silently skipped)
    /// 2. For each group, stitches chapters via `ChapterStitcher.stitch(_:streams:)`
    /// 3. Returns extractions in the same order as `group(_:)` output
    ///
    /// - Parameters:
    ///   - urls: File URLs in any order.
    ///   - streams: Optional filter to extract only specific sensor streams.
    ///     Pass `nil` (default) to extract all available streams.
    ///     Forwarded to `ChapterStitcher.stitch(_:streams:)`.
    /// - Returns: Array of `SessionExtraction`, one per recording session.
    /// - Throws: Any `GPMFError` from `ChapterStitcher` or `GPMFExtractor` on the
    ///   first group that fails. Use `group(_:)` + manual extraction for partial results.
    public static func extractAll(_ urls: [URL], streams: StreamFilter? = nil) throws -> [SessionExtraction] {
        let groups = group(urls)

        var results: [SessionExtraction] = []
        results.reserveCapacity(groups.count)

        for g in groups {
            let telemetry = try ChapterStitcher.stitch(g.chapterURLs, streams: streams)
            results.append(SessionExtraction(
                prefix: g.prefix,
                sessionID: g.sessionID,
                chapterCount: g.chapterURLs.count,
                telemetry: telemetry
            ))
        }

        return results
    }

    // MARK: - Internal Types

    /// Hashable key for dictionary grouping.
    private struct GroupKey: Hashable {
        let prefix: String
        let sessionID: String
    }
}

// MARK: - Public Output Types

/// A group of GoPro chapter files from the same recording session.
///
/// All files share the same `prefix` and `sessionID`. Chapter URLs are sorted
/// by chapter number (ascending), ready to be passed to `ChapterStitcher.stitch(_:)`.
public struct SessionGroup: Sendable {

    /// Camera prefix (e.g. "GH", "GX", "GL"). Depends on firmware and video settings,
    /// NOT on camera model or encoding format.
    public let prefix: String

    /// 4-digit session ID from the filename (e.g. "1122").
    /// Increments chronologically on the same SD card.
    public let sessionID: String

    /// Chapter file URLs, sorted by chapter number (ascending).
    /// Single-chapter sessions have exactly one URL.
    public let chapterURLs: [URL]
}

/// Result of extracting a single recording session (one or more chapter files).
public struct SessionExtraction: Sendable {

    /// Camera prefix (e.g. "GH", "GX", "GL").
    public let prefix: String

    /// 4-digit session ID from the filename.
    public let sessionID: String

    /// Number of chapter files that were stitched (1 = no chapter split).
    public let chapterCount: Int

    /// Stitched telemetry data with unified timeline starting at 0.0.
    public let telemetry: TelemetryData
}
