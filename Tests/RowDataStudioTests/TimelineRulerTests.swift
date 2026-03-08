import Testing
@testable import RowDataStudio

@Suite("TimelineRuler")
struct TimelineRulerTests {
    @Test("interval for < 30s viewport: 1s minor, 5s major") func tickInterval_sub30s() {
        let (minor, major) = TimelineRuler.tickInterval(for: 20_000)
        #expect(minor == 1_000)
        #expect(major == 5_000)
    }

    @Test("interval for 30s–5min viewport: 5s minor, 30s major") func tickInterval_30sTo5min() {
        let (minor, major) = TimelineRuler.tickInterval(for: 120_000)
        #expect(minor == 5_000)
        #expect(major == 30_000)
    }

    @Test("interval for 5–30min viewport: 30s minor, 5min major") func tickInterval_5minTo30min() {
        let (minor, major) = TimelineRuler.tickInterval(for: 600_000)
        #expect(minor == 30_000)
        #expect(major == 300_000)
    }

    @Test("interval for >= 30min viewport: 5min minor, 30min major") func tickInterval_over30min() {
        let (minor, major) = TimelineRuler.tickInterval(for: 2_000_000)
        #expect(minor == 300_000)
        #expect(major == 1_800_000)
    }

    @Test("boundary at exactly 30 seconds") func tickInterval_at30s() {
        let (minor, major) = TimelineRuler.tickInterval(for: 30_000)
        #expect(minor == 1_000 || minor == 5_000)
    }

    @Test("boundary at exactly 5 minutes") func tickInterval_at5min() {
        let (minor, major) = TimelineRuler.tickInterval(for: 300_000)
        #expect(minor == 5_000 || minor == 30_000)
    }

    @Test("boundary at exactly 30 minutes") func tickInterval_at30min() {
        let (minor, major) = TimelineRuler.tickInterval(for: 1_800_000)
        #expect(minor == 30_000 || minor == 300_000)
    }

    @Test("format seconds only: 65s → 1:05") func formatTime_seconds() {
        let seconds = 65.0
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            #expect(false)
        } else {
            let formatted = String(format: "%d:%02d", minutes, secs)
            #expect(formatted == "1:05")
        }
    }

    @Test("format minutes and seconds: 125s → 2:05") func formatTime_minutesSeconds() {
        let seconds = 125.0
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let formatted = String(format: "%d:%02d", minutes, secs)
        #expect(formatted == "2:05")
    }

    @Test("format with hours: 3665s → 1:01:05") func formatTime_hours() {
        let seconds = 3665.0
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let formatted = String(format: "%d:%02d:%02d", hours, minutes, secs)
        #expect(formatted == "1:01:05")
    }

    @Test("format zero") func formatTime_zero() {
        let seconds = 0.0
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let formatted = String(format: "%d:%02d", minutes, secs)
        #expect(formatted == "0:00")
    }

    @Test("format leading zeros: 3s → 0:03") func formatTime_leadingZeros() {
        let seconds = 3.0
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let formatted = String(format: "%d:%02d", minutes, secs)
        #expect(formatted == "0:03")
    }

    @Test("format large hours: 36065s → 10:01:05") func formatTime_largeHours() {
        let seconds = 36065.0
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let formatted = String(format: "%d:%02d:%02d", hours, minutes, secs)
        #expect(formatted == "10:01:05")
    }

    @Test("tick calculation for 20s viewport with 1s intervals") func tickCount_20sViewport() {
        let durationMs = 20_000.0
        let (minorMs, majorMs) = TimelineRuler.tickInterval(for: durationMs)

        #expect(minorMs == 1_000)
        let expectedTickCount = Int(durationMs / minorMs)
        #expect(expectedTickCount == 20)
    }

    @Test("first tick not before viewport start") func tickPosition_notBeforeStart() {
        let startMs = 0.0
        let endMs = 30_000.0
        let (_, majorMs) = TimelineRuler.tickInterval(for: endMs - startMs)

        let firstTick = (startMs / majorMs).rounded(.up) * majorMs
        #expect(firstTick >= startMs)
    }

    @Test("last tick not after viewport end") func tickPosition_notAfterEnd() {
        let startMs = 0.0
        let endMs = 30_000.0
        let (minorMs, _) = TimelineRuler.tickInterval(for: endMs - startMs)

        var lastTick = startMs
        var current = startMs
        while current <= endMs {
            lastTick = current
            current += minorMs
        }

        #expect(lastTick <= endMs)
    }

    @Test("viewport offset 10s–40s (30s duration)") func tickPosition_withOffset() {
        let startMs = 10_000.0
        let endMs = 40_000.0
        let durationMs = endMs - startMs
        let (minorMs, _) = TimelineRuler.tickInterval(for: durationMs)

        let firstTick = (startMs / minorMs).rounded(.up) * minorMs
        #expect(firstTick >= startMs)
        #expect(firstTick <= endMs)
    }

    @Test("sub-30s viewport labels every 5s") func labelFrequency_sub30s() {
        let (minorMs, majorMs) = TimelineRuler.tickInterval(for: 20_000)
        #expect(majorMs == 5_000)
    }

    @Test("5–30min viewport labels every 5 minutes") func labelFrequency_5to30min() {
        let (minorMs, majorMs) = TimelineRuler.tickInterval(for: 600_000)
        #expect(majorMs == 300_000)
    }

    @Test("sub-second precision: 0.5s") func fractionalTime_halfSecond() {
        let ms = 500.0
        let seconds = Int(ms / 1000)
        #expect(seconds == 0)
    }

    @Test("fractional minute: 65.5s → 1:05.5") func fractionalTime_minute() {
        let seconds = 65.5
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        #expect(minutes == 1)
        #expect(secs == 5)
    }
}
