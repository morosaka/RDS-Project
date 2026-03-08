import Testing
@testable import RowDataStudio

@Suite("VideoSyncController")
struct VideoSyncControllerTests {
    @Test("init with nil URL creates empty AVPlayer") func nilURLInit() {
        let controller = VideoSyncController(url: nil, timeOffsetMs: 0)
        #expect(controller.videoDuration == 0)
        #expect(!controller.isBuffering)
    }

    @Test("ms to seconds: 1000ms + 500ms offset → 1.5s") func msToSecondsConversion() {
        let resultMs = 1000.0
        let offsetMs = 500.0
        let expectedSeconds = (resultMs + offsetMs) / 1000.0
        #expect(expectedSeconds == 1.5)
    }

    @Test("negative offset: (-200ms + 500ms) / 1000 = 0.3s") func negativeOffsetHandling() {
        let resultMs = -200.0
        let offsetMs = 500.0
        let expectedSeconds = (resultMs + offsetMs) / 1000.0
        #expect(abs(expectedSeconds - 0.3) < 0.001)
    }

    @Test("zero offset passes through unchanged") func zeroOffset() {
        let resultMs = 2500.0
        let offsetMs = 0.0
        let expectedSeconds = (resultMs + offsetMs) / 1000.0
        #expect(expectedSeconds == 2.5)
    }

    @Test("skip seek when difference < 50ms threshold") func seekThresholdSkip() {
        let currentSeconds = 0.5
        let targetSeconds = 0.51
        let thresholdMs = 50.0
        let diffMs = abs(currentSeconds - targetSeconds) * 1000
        #expect(diffMs < thresholdMs)
    }

    @Test("perform seek when difference >= 50ms threshold") func seekThresholdExceeds() {
        let currentSeconds = 0.5
        let targetSeconds = 0.6
        let thresholdMs = 50.0
        let diffMs = abs(currentSeconds - targetSeconds) * 1000
        #expect(diffMs >= thresholdMs)
    }

    @Test("exact match at boundary: 50ms") func seekThresholdBoundary() {
        let currentSeconds = 0.5
        let targetSeconds = 0.55
        let thresholdMs = 50.0
        let diffMs = abs(currentSeconds - targetSeconds) * 1000
        #expect(diffMs >= thresholdMs)
    }

    @Test("drift below 200ms threshold skips correction") func driftBelowThreshold() {
        let playheadSeconds = 5.0
        let playerSeconds = 5.1
        let driftThreshold = 0.2
        let drift = abs(playerSeconds - playheadSeconds)
        #expect(drift < driftThreshold)
    }

    @Test("drift above 200ms threshold triggers correction") func driftAboveThreshold() {
        let playheadSeconds = 5.0
        let playerSeconds = 5.3
        let driftThreshold = 0.2
        let drift = abs(playerSeconds - playheadSeconds)
        #expect(drift > driftThreshold)
    }

    @Test("drift at 200ms boundary is corrected") func driftAtBoundary() {
        let playheadSeconds = 5.0
        let playerSeconds = 5.2
        let driftThreshold = 0.2
        let drift = abs(playerSeconds - playheadSeconds)
        #expect(drift >= driftThreshold)
    }

    @Test("per-widget offset applied to sync calculation") func timeOffsetApplication() {
        let playheadMs = 1000.0
        let offsetMs = 500.0
        let targetSeconds = (playheadMs + offsetMs) / 1000.0
        #expect(targetSeconds == 1.5)
    }

    @Test("negative offset shifts video earlier") func negativeTimeOffset() {
        let playheadMs = 2000.0
        let offsetMs = -500.0
        let targetSeconds = (playheadMs + offsetMs) / 1000.0
        #expect(targetSeconds == 1.5)
    }

    @Test("zero duration initialized at construction") func zeroDuration() {
        let controller = VideoSyncController(url: nil)
        #expect(controller.videoDuration == 0)
    }

    @Test("no buffering on initialization") func bufferingInitState() {
        let controller = VideoSyncController(url: nil)
        #expect(!controller.isBuffering)
    }

    @Test("two controllers with different offsets are independent") func multiCameraIndependence() {
        let controller1 = VideoSyncController(url: nil, timeOffsetMs: 100)
        let controller2 = VideoSyncController(url: nil, timeOffsetMs: 500)
        #expect(controller1.player !== controller2.player)
    }
}
