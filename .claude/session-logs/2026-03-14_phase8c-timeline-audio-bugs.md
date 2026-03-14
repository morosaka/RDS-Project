# Phase 8c — Bug Fixes: Timeline Zoom Crash, Viewport Default, Audio Widget Zoom
**Date:** 2026-03-14
**Status:** Complete
**Complexity:** M

---

## Bugs Fixed

### Bug 1: Timeline Zoom Crash (#0 Range requires lowerBound <= upperBound)

**Cause:** `TimelineView.zoomGesture` computed viewport center once at gesture start, but never
clamped it to valid bounds. Extreme zoom scales (pinch way out) could push centerMs outside
[clampedHalf, maxDuration - clampedHalf], creating inverted ranges where lowerBound > upperBound.

**Example:** Session 711s, initial viewport 0...60_000ms, user pinches with scale=0.1 (extreme zoom out):
- centerMs = 30_000 (center of initial viewport)
- newHalf = 30_000 / 0.1 = 300_000
- clampedHalf = 300_000
- Attempted viewport = (30_000 - 300_000)...(...) = (-270_000)...(...) ❌

**Fix:** Clamp centerMs AFTER computing clampedHalf:

```swift
let clampedCenter = max(clampedHalf, min(maxDuration - clampedHalf, centerMs))
viewportMs = (clampedCenter - clampedHalf)...(clampedCenter + clampedHalf)
```

---

### Bug 2: Timeline Default Viewport = 1 Minute (not full session)

**Cause:** `RowingDeskCanvas` initializes `viewportMs = 0...60_000` (hardcoded 1 minute).
When session duration is 711s, timeline only shows first 60s. Rest of session invisible.

**Fix:** Already handled by existing `.onAppear` + `.onChange` logic in RowingDeskCanvas (v2.5):

```swift
.onAppear {
    if let dur = dataContext.sessionDocument?.timeline.duration, dur > 0 {
        viewportMs = 0...(dur * 1_000)  // Full session range on load
    }
}
.onChange(of: dataContext.sessionDurationMs) { newDur in
    guard newDur > 0 else { return }
    viewportMs = 0...newDur
}
```

Viewport now auto-resets to full session duration when data arrives.

---

### Bug 3: AudioTrackWidget Not Zoomable (No X-Axis Zoom)

**Cause:** `AudioTrackWidget` receives `viewportMs` as a read-only `let` parameter. Unlike
`LineChartWidget` which has local X-zoom via `@State private var localViewportMs`, the audio
widget had no zoom capability. Widget-level zoom changes were not possible.

**Fix:** Add same three-layer zoom pattern as LineChartWidget:

1. **Add local zoom state** (line 48):
```swift
@State private var localViewportMs: ClosedRange<Double>? = nil
private var effectiveViewportMs: ClosedRange<Double> { localViewportMs ?? viewportMs }
private var isLocalZoom: Bool { localViewportMs != nil }
```

2. **Add MagnificationGesture** to waveformArea:
```swift
.gesture(
    MagnificationGesture()
        .onChanged { value in
            let base = localViewportMs ?? viewportMs
            let globalSpan = viewportMs.upperBound - viewportMs.lowerBound
            localViewportMs = LocalZoomMath.applyXZoom(
                local: base,
                magnification: Double(value),
                globalSpan: globalSpan
            )
        }
)
```

3. **Double-tap reset:**
```swift
.onTapGesture(count: 2) {
    localViewportMs = nil
}
```

4. **Update waveform rendering to use effectiveViewportMs** (not viewportMs):
   - `waveformCanvas(peaks:size:)` → uses `effectiveViewportMs`
   - `playheadOverlay(width:height:)` → uses `effectiveViewportMs`

---

## Architecture: Three-Layer Zoom Model

| Layer | Widget | Control | Scope |
|-------|--------|---------|-------|
| 1 | RowingDeskCanvas | Pinch on canvas background | Pan + zoom all widgets |
| 2 | RowingDeskCanvas.TimelineView | Timeline zoom gesture | Temporal range (all widgets follow) |
| 3 | LineChartWidget, AudioTrackWidget | MagnificationGesture + double-tap reset | Independent X-axis zoom per widget |

---

## Files Changed

| File | Version | Changes |
|------|---------|---------|
| `Sources/RowDataStudio/UI/Timeline/TimelineView.swift` | v2.2.0 → v2.3.0 | Fix zoom crash: clamp viewport center bounds |
| `Sources/RowDataStudio/Rendering/Widgets/AudioTrackWidget.swift` | v1.0.0 → v1.1.0 | Add MagnificationGesture, localViewportMs, double-tap reset |
| `Sources/RowDataStudio/UI/RowingDeskCanvas.swift` | v2.5.0 (unchanged) | Existing .onAppear/.onChange handle viewport sync ✓ |

---

## Test Results

```
✔ Build clean — no errors
✔ 380 tests passed (all suites)
```

All three bugs fixed. Timeline zoom now safe, audio widget zoomable, viewport synced to session duration.
