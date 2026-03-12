// Rendering/PlayheadController.swift v1.2.0
/**
 * Frame-accurate playback position controller.
 * Uses CVDisplayLink for frame-accurate position tracking on macOS.
 * Published updates are throttled to 30fps to halve SwiftUI re-render pressure.
 * --- Revision History ---
 * v1.2.0 - 2026-03-12 - Throttle @Published updates to 30fps (was 60fps).
 * v1.1.0 - 2026-03-07 - Switch from @Observable (macOS 14+) to ObservableObject.
 * v1.0.0 - 2026-03-07 - Initial implementation (Phase 4: Rendering + MVP).
 */

import Combine
import CoreVideo
import Foundation

/// Controls playback position for synchronized chart rendering.
///
/// `CVDisplayLink` advances `currentTimeMs` frame-accurately at the display
/// refresh rate (typically 60Hz). **Published updates are throttled to 30fps**
/// to halve SwiftUI overlay re-render pressure — imperceptible for data overlays.
///
/// **Thread safety:** `@unchecked Sendable`. The CVDisplayLink fires on a
/// private thread; mutations are always dispatched to the main thread.
public final class PlayheadController: ObservableObject, @unchecked Sendable {

    // MARK: - Published State

    /// Current playback position in milliseconds.
    @Published public private(set) var currentTimeMs: Double = 0

    /// Total session duration in milliseconds.
    @Published public var duration: Double = 0

    /// `true` while the display link is running.
    @Published public private(set) var isPlaying: Bool = false

    /// Playback speed multiplier. Default: 1.0.
    @Published public var playbackRate: Double = 1.0

    // MARK: - Private

    private var displayLink: CVDisplayLink?
    private var lastHostTime: UInt64 = 0

    /// Internal (non-published) position — advances every CVDisplayLink frame.
    private var internalTimeMs: Double = 0

    /// Host time of last @Published update. Gates SwiftUI to ≤30fps.
    private var lastPublishHostTime: UInt64 = 0

    /// Minimum host-time ticks between @Published updates ≈ 1/30 s.
    private static let minPublishIntervalTicks: UInt64 = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        // 1/30 s = 33_333_333 ns. Convert to Mach ticks: ns * denom / numer.
        let nsPerTick = Double(info.numer) / Double(info.denom)
        return UInt64(33_333_333.0 / nsPerTick)
    }()

    private static let machToMs: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000.0
    }()

    public init() {}

    deinit {
        if let link = displayLink { CVDisplayLinkStop(link) }
    }

    // MARK: - Control

    public func play() {
        guard !isPlaying, currentTimeMs < duration else { return }
        lastHostTime = 0
        lastPublishHostTime = 0
        internalTimeMs = currentTimeMs
        isPlaying = true
        startDisplayLink()
    }

    public func pause() {
        isPlaying = false
        stopDisplayLink()
    }

    public func seek(to timeMs: Double) {
        internalTimeMs = max(0, min(timeMs, duration))
        currentTimeMs = internalTimeMs
    }

    public func reset() {
        pause()
        internalTimeMs = 0
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
        CVDisplayLinkSetOutputCallback(link, { (_, now, _, _, _, ctx) -> CVReturn in
            guard let ctx else { return kCVReturnSuccess }
            let controller = Unmanaged<PlayheadController>.fromOpaque(ctx).takeUnretainedValue()
            controller.tick(hostTime: now.pointee.hostTime)
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(link)
    }

    private func stopDisplayLink() {
        if let link = displayLink { CVDisplayLinkStop(link) }
    }

    // MARK: - Tick (CVDisplayLink thread — NOT main thread)

    /// Advances internal position at CVDisplayLink rate.
    /// Only publishes to SwiftUI at ≤30fps to halve overlay re-render pressure.
    fileprivate func tick(hostTime: UInt64) {
        guard lastHostTime != 0 else {
            lastHostTime = hostTime
            lastPublishHostTime = hostTime
            return
        }

        // 1. Advance internal position every frame (frame-accurate)
        let elapsed = hostTime > lastHostTime ? hostTime - lastHostTime : 0
        let elapsedMs = Double(elapsed) * PlayheadController.machToMs * playbackRate
        lastHostTime = hostTime

        let newTime = internalTimeMs + elapsedMs
        let reachedEnd = newTime >= duration
        internalTimeMs = reachedEnd ? duration : newTime

        // 2. Gate @Published update to ≤30fps
        let sinceLastPublish = hostTime > lastPublishHostTime ? hostTime - lastPublishHostTime : 0
        guard sinceLastPublish >= PlayheadController.minPublishIntervalTicks || reachedEnd else { return }
        lastPublishHostTime = hostTime
        let publishTime = internalTimeMs

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.currentTimeMs = publishTime
            if reachedEnd { self.pause() }
        }
    }
}
