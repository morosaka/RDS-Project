// Rendering/PlayheadController.swift v1.1.0
/**
 * Frame-accurate playback position controller.
 * Uses CVDisplayLink for 60fps callbacks on macOS; ObservableObject for SwiftUI reactivity.
 * --- Revision History ---
 * v1.1.0 - 2026-03-07 - Switch from @Observable (macOS 14+) to ObservableObject (macOS 13+).
 * v1.0.0 - 2026-03-07 - Initial implementation (Phase 4: Rendering + MVP).
 */

import Combine
import CoreVideo
import Foundation

/// Controls playback position for synchronized chart rendering.
///
/// Drives the vertical playhead cursor in `LineChartWidget` at the display
/// refresh rate (typically 60 fps on macOS). Uses `CVDisplayLink` for
/// frame-accurate callbacks tied to the GPU vsync signal.
///
/// **Thread safety:** `@unchecked Sendable`. The CVDisplayLink fires on a
/// private thread; `@Published` mutations are always dispatched to the main
/// thread so SwiftUI observation works correctly.
///
/// **Usage:**
/// ```swift
/// @StateObject private var playhead = PlayheadController()
/// playhead.duration = durationMs
/// playhead.play()
/// // Bind UI to: playhead.currentTimeMs, playhead.isPlaying
/// ```
public final class PlayheadController: ObservableObject, @unchecked Sendable {

    // MARK: - Published State

    /// Current playback position in milliseconds (zero-based, matches `SensorDataBuffers.timestamp`).
    @Published public private(set) var currentTimeMs: Double = 0

    /// Total session duration in milliseconds. Set this before calling `play()`.
    @Published public var duration: Double = 0

    /// `true` while the display link is running.
    @Published public private(set) var isPlaying: Bool = false

    /// Playback speed multiplier. 1.0 = real-time. Default: 1.0.
    @Published public var playbackRate: Double = 1.0

    // MARK: - Private

    private var displayLink: CVDisplayLink?
    /// Last Mach host time seen in the display link callback; 0 = first frame.
    private var lastHostTime: UInt64 = 0

    /// Converts Mach absolute time units to milliseconds (computed once per process).
    private static let machToMs: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        // numer/denom converts ticks → nanoseconds; divide by 1e6 → milliseconds
        return Double(info.numer) / Double(info.denom) / 1_000_000.0
    }()

    public init() {}

    deinit {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
    }

    // MARK: - Control

    /// Starts playback from `currentTimeMs`.
    public func play() {
        guard !isPlaying, currentTimeMs < duration else { return }
        lastHostTime = 0
        isPlaying = true
        startDisplayLink()
    }

    /// Pauses playback, retaining `currentTimeMs`.
    public func pause() {
        isPlaying = false
        stopDisplayLink()
    }

    /// Seeks to an arbitrary position, clamped to [0, duration].
    public func seek(to timeMs: Double) {
        currentTimeMs = max(0, min(timeMs, duration))
    }

    /// Pauses and resets to the beginning.
    public func reset() {
        pause()
        currentTimeMs = 0
    }

    // MARK: - CVDisplayLink

    private func startDisplayLink() {
        if displayLink == nil {
            var link: CVDisplayLink?
            CVDisplayLinkCreateWithActiveCGDisplays(&link)
            self.displayLink = link
        }
        guard let link = displayLink else { return }

        // C-compatible callback: context is an unretained pointer to self.
        CVDisplayLinkSetOutputCallback(link, { (_, now, _, _, _, ctx) -> CVReturn in
            guard let ctx else { return kCVReturnSuccess }
            let controller = Unmanaged<PlayheadController>.fromOpaque(ctx).takeUnretainedValue()
            controller.tick(hostTime: now.pointee.hostTime)
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(self).toOpaque())

        CVDisplayLinkStart(link)
    }

    private func stopDisplayLink() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
    }

    // MARK: - Tick (called on CVDisplayLink thread)

    /// Advances `currentTimeMs` by elapsed real time × `playbackRate`.
    /// Dispatches to main thread so @Published changes propagate via Combine correctly.
    fileprivate func tick(hostTime: UInt64) {
        // Skip the first callback — establish baseline without advancing time.
        guard lastHostTime != 0 else {
            lastHostTime = hostTime
            return
        }

        let elapsed = hostTime > lastHostTime ? hostTime - lastHostTime : 0
        let elapsedMs = Double(elapsed) * PlayheadController.machToMs * playbackRate
        lastHostTime = hostTime

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let newTime = self.currentTimeMs + elapsedMs
            if newTime >= self.duration {
                self.currentTimeMs = self.duration
                self.pause()
            } else {
                self.currentTimeMs = newTime
            }
        }
    }
}
