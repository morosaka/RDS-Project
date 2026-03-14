# Phase 8c — Bug Fixes: Audio Output + Chart X-Axis Zoom
**Date:** 2026-03-14
**Status:** Complete
**Complexity:** S

---

## Objective

Fix two regressions discovered during real-file testing after Phase 8c.7–8c.8:
1. **Audio missing** — VideoWidget was silenced by Phase 8c.8's muting line, but AudioTrackWidget has no AVAudioPlayerNode yet.
2. **Chart X-axis zoom broken** — NSEvent monitor consumed all `.magnify` events at window level, blocking SwiftUI `MagnificationGesture` on child widgets (LineChartWidget).

---

## Bug 1 — Audio Missing

### Root Cause

Phase 8c.8 added `syncController.player.isMuted = true` to `VideoWidget.swift`'s `.task` block.
The assumption was that `AudioTrackWidget` would own audio output. However, `AudioTrackWidget`
has no `AVAudioPlayerNode` / `AVAudioEngine` — it only renders the waveform visualisation.
Result: muting VideoWidget's AVPlayer silenced all audio with no replacement path.

### Fix

**`Sources/RowDataStudio/Rendering/Widgets/VideoWidget.swift` v1.3.0 (modified)**

Removed `syncController.player.isMuted = true`. Final `.task` block:

```swift
.task {
    // NOTE: player is NOT muted here. AudioTrackWidget provides the waveform
    // visualisation and volume controls, but actual audio output comes from
    // this AVPlayer until a dedicated AVAudioPlayerNode path is added (post-MVP).
    syncController.bind(to: playheadController)
}
```

### Architecture Note

| Widget | Audio Role (Phase 8c) |
|---|---|
| `VideoWidget` | Audio output via AVPlayer (unmuted) |
| `AudioTrackWidget` | Waveform visualisation + volume UI only (no own playback) |
| `AVAudioPlayerNode` | **Post-MVP** — true audio separation |

The `isMuted` line from 8c.8 was premature. It should be restored only once
`AudioTrackWidget` is wired to an `AVAudioPlayerNode` + `AVAudioEngine`.

---

## Bug 2 — Chart X-Axis Zoom Not Working

### Root Cause

`RowingDeskCanvas` used `NSEvent.addLocalMonitorForEvents(matching: [.magnify, .keyDown])` to
intercept trackpad events. The monitor returned `nil` for `.magnify` events — consuming them
at the window level before SwiftUI could dispatch them to child views.

SwiftUI's `MagnificationGesture` on `LineChartWidget` never received the events.

### Fix

**`Sources/RowDataStudio/UI/RowingDeskCanvas.swift` v2.4.0 (modified)**

Three changes:

1. **Remove `.magnify` from NSEvent monitor** — now handles only `.keyDown`:
```swift
eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { ... }
```

2. **Add `@GestureState` for live canvas zoom feedback**:
```swift
@GestureState private var liveZoomScale: Double = 1.0
```

3. **Add SwiftUI `MagnificationGesture` to canvas ZStack** + update `scaleEffect`:
```swift
// scaleEffect: multiply canvasZoom by live gesture factor
.scaleEffect(canvasZoom * liveZoomScale, anchor: .topLeading)

// Gesture on ZStack background:
.gesture(
    MagnificationGesture()
        .updating($liveZoomScale) { value, state, _ in state = value }
        .onEnded { value in
            canvasZoom = max(RDS.Layout.canvasZoomMin,
                             min(RDS.Layout.canvasZoomMax, canvasZoom * value))
            schedulePositionSave()
        }
)
```

### Why This Works: SwiftUI Gesture Priority

SwiftUI dispatches gestures **child-before-parent**. When the user pinches over
`LineChartWidget`, its `MagnificationGesture` fires first (chart X-axis zoom).
When the user pinches on the canvas background, the canvas `MagnificationGesture`
fires (canvas zoom). No explicit disambiguation needed.

`@GestureState` provides smooth live feedback (`scaleEffect` updates on every
touch event) without writing to `@State` mid-gesture. It auto-resets to `1.0`
when the gesture ends, after `canvasZoom` has been committed.

---

## Files Changed

| File | Change |
|---|---|
| `Sources/RowDataStudio/Rendering/Widgets/VideoWidget.swift` | Remove `player.isMuted = true` |
| `Sources/RowDataStudio/UI/RowingDeskCanvas.swift` | Remove `.magnify` from NSEvent monitor; add `@GestureState liveZoomScale`; add canvas `MagnificationGesture`; update `scaleEffect` |

---

## Test Results

```
Build: clean — no errors
Tests: all passing (no new tests added; fixes restore correct behavior verified by build + real-file test)
```
