// UI/VideoPlayer/VideoPlayerView.swift v1.0.0
/**
 * NSViewRepresentable wrapper for AVPlayerView on macOS.
 * Disables native controls (controlsStyle = .none) to use custom UI from VideoWidget.
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 7).
 */

import AVKit
import SwiftUI

public struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect

    public init(player: AVPlayer, gravity: AVLayerVideoGravity = .resizeAspect) {
        self.player = player
        self.gravity = gravity
    }

    public func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none  // Custom controls in VideoWidget
        view.videoGravity = gravity
        return view
    }

    public func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
        nsView.videoGravity = gravity
    }
}
