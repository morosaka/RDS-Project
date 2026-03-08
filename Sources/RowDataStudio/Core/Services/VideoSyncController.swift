// Core/Services/VideoSyncController.swift v1.0.0
/**
 * Bidirectional sync controller between AVPlayer and PlayheadController.
 * PlayheadController is the source of truth for time. VideoSyncController
 * updates AVPlayer state in response to PlayheadController changes.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 7).
 */

import AVFoundation
import Combine

public final class VideoSyncController: ObservableObject, @unchecked Sendable {
    public let player: AVPlayer
    @Published public private(set) var isBuffering: Bool = false
    @Published public private(set) var videoDuration: Double = 0  // seconds

    private let timeOffsetMs: Double
    private var timeObserverToken: Any?
    private var cancellables = Set<AnyCancellable>()
    private var isSeeking = false
    private var pendingSeekMs: Double?

    private static let seekThresholdMs: Double = 50
    private static let driftThresholdSeconds: Double = 0.2

    public init(url: URL?, timeOffsetMs: Double = 0) {
        self.timeOffsetMs = timeOffsetMs

        if let url = url {
            let item = AVPlayerItem(url: url)
            self.player = AVPlayer(playerItem: item)
            setupItemObservers(item: item)
        } else {
            self.player = AVPlayer()
        }
    }

    public func bind(to playheadController: PlayheadController) {
        weak var weakPC = playheadController

        // Handle play/pause state changes
        playheadController.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                guard let self = self, let pc = weakPC else { return }
                if isPlaying {
                    // Start playback: seek to current position, then set rate
                    let targetSeconds = (pc.currentTimeMs + self.timeOffsetMs) / 1000.0
                    let targetTime = CMTime(seconds: targetSeconds, preferredTimescale: 600)
                    self.player.seek(to: targetTime) { [weak self] _ in
                        guard let self = self, let pc = weakPC, pc.isPlaying else { return }
                        DispatchQueue.main.async {
                            self.player.rate = Float(pc.playbackRate)
                        }
                    }
                } else {
                    // Pause: stop playback
                    self.player.rate = 0
                    // Seek to exact position in pause mode
                    let targetSeconds = (pc.currentTimeMs + self.timeOffsetMs) / 1000.0
                    let targetTime = CMTime(seconds: targetSeconds, preferredTimescale: 600)
                    self.player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
            .store(in: &cancellables)

        // Handle scrubbing while paused
        playheadController.$currentTimeMs
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ms in
                guard let self = self, let pc = weakPC, !pc.isPlaying else { return }
                self.seekToPlayhead(ms)
            }
            .store(in: &cancellables)

        // Periodic observer for drift correction during playback
        let interval = CMTime(value: 1, timescale: 60)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] currentTime in
            guard let self = self, let pc = weakPC, pc.isPlaying else { return }
            let expectedSeconds = (pc.currentTimeMs + self.timeOffsetMs) / 1000.0
            let drift = abs(currentTime.seconds - expectedSeconds)

            if drift > Self.driftThresholdSeconds {
                let targetTime = CMTime(seconds: expectedSeconds, preferredTimescale: 600)
                let tolerance = CMTime(seconds: 0.1, preferredTimescale: 600)
                self.player.seek(to: targetTime, toleranceBefore: tolerance, toleranceAfter: tolerance)
            }
        }
    }

    public func unbind() {
        cancellables.removeAll()
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    private func seekToPlayhead(_ playheadMs: Double) {
        let targetSeconds = (playheadMs + timeOffsetMs) / 1000.0
        let currentSeconds = player.currentTime().seconds

        // Skip seeks within threshold
        if abs(currentSeconds - targetSeconds) < (Self.seekThresholdMs / 1000.0) {
            return
        }

        // Prevent concurrent seeks
        if isSeeking {
            pendingSeekMs = playheadMs
            return
        }

        isSeeking = true
        let targetTime = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSeeking = false
                if let pending = self.pendingSeekMs {
                    self.pendingSeekMs = nil
                    self.seekToPlayhead(pending)
                }
            }
        }
    }

    private func setupItemObservers(item: AVPlayerItem) {
        // Observe duration
        item.publisher(for: \.duration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cmDuration in
                if cmDuration.isNumeric && cmDuration.seconds > 0 {
                    self?.videoDuration = cmDuration.seconds
                }
            }
            .store(in: &cancellables)

        // Observe status for loading indication
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .map { $0 == .waitingToPlayAtSpecifiedRate }
            .assign(to: &$isBuffering)
    }

    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
    }
}
