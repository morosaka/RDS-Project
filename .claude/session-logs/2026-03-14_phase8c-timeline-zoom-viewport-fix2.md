# Phase 8c — Bug Fix Round 2: Timeline Zoom Crash (Compounding) + Viewport Default
**Date:** 2026-03-14
**Status:** Complete
**Complexity:** M

---

## Root Causes (v2.3.0 fixes were insufficient)

### Bug 1: Timeline Zoom Crash — Compounding (NOT just clamping)

**Why v2.3 fix was insufficient:**
`MagnificationGesture.onChanged` fires with CUMULATIVE scale from gesture start.
The v2.3 fix clamped the center/bounds but still applied the cumulative scale to the
already-mutated `viewportMs` on every call. Result: scale compounds exponentially.

Example (viewport = 0...60_000, zoom gesture fires 5x at scale=1.3):
- Call 1: half = 30_000 / 1.3 = 23_077 → viewportMs ≈ 6_923...53_077
- Call 2: half = 23_077 / 1.3 = 17_752 → viewportMs ≈ 12_248...47_752  ← already applied once!
- Call 5: half ≈ 7_875 → viewportMs zoomed in 5x in a single gesture

After ~20 calls: viewport collapses to minDuration (5s), then further compounding with
inverse scale (zoom-out) can push centerMs to negative values before clamping catches it,
or trigger invalid range construction in edge cases.

**Fix (v2.4.0):** Capture `viewportMs` snapshot at gesture start via `@GestureState`.
Always apply cumulative scale to the snapshot — not the live state.

```swift
@GestureState private var zoomBaseViewport: ClosedRange<Double>? = nil

private var zoomGesture: some Gesture {
    MagnificationGesture()
        .updating($zoomBaseViewport) { _, state, _ in
            if state == nil { state = viewportMs }  // capture once at gesture start
        }
        .onChanged { scale in
            let base = zoomBaseViewport ?? viewportMs  // always use snapshot
            // ... apply scale to base, not viewportMs ...
        }
}
```

`@GestureState` resets to nil automatically when gesture ends — no cleanup needed.

---

### Bug 2: Timeline Viewport Default = 1 Minute (NOT 711s)

**Why v2.5 fix was insufficient:**
`RowingDeskCanvas.onAppear` read `sessionDocument?.timeline.duration` (seconds) × 1000.
But `SessionDocument.timeline.duration` is **never written by FileImportHelper**.
FileImportHelper sets `dataContext.sessionDurationMs` (ms) — a different property.
`sessionDocument.timeline.duration` remains 0 from session creation → viewport stays 0...60_000.

The `.onChange(of: dataContext.sessionDurationMs)` ALSO failed because:
Canvas appears AFTER `FileImportHelper.process()` completes (openInCanvas = true is set
at the end of `openSession()`). So `sessionDurationMs` is already set to the correct value
when the view appears. `.onChange` only fires on VALUE CHANGE — not on initial registration.
The value doesn't change after view appears → `.onChange` never fires.

**Fix:** In `.onAppear`, prefer `dataContext.sessionDurationMs` (always in ms, set by pipeline):

```swift
let durMs: Double
if dataContext.sessionDurationMs > 0 {
    durMs = dataContext.sessionDurationMs
} else if let dur = dataContext.sessionDocument?.timeline.duration, dur > 0 {
    durMs = dur * 1_000
} else {
    durMs = 0
}
if durMs > 0 { viewportMs = 0...durMs }
```

---

## Files Changed

| File | Version | Changes |
|------|---------|---------|
| `Sources/RowDataStudio/UI/Timeline/TimelineView.swift` | v2.3.0 → v2.4.0 | @GestureState base viewport snapshot; guard maxDuration >= minDuration |
| `Sources/RowDataStudio/UI/RowingDeskCanvas.swift` | v2.5.0 (unchanged version) | onAppear: prefer sessionDurationMs over sessionDocument.timeline.duration |

---

## Key Pattern: MagnificationGesture on macOS

`onChanged { scale in }` — scale is CUMULATIVE from gesture start, NOT incremental.
WRONG: apply scale to `viewportMs` (already mutated) → exponential compounding
CORRECT: apply scale to snapshot captured at gesture start via `@GestureState`

Same principle applies to any state that is mutated inside `.onChanged`.

---

## Test Results

```
✔ Build clean — no errors
✔ 380 tests passed (all suites)
```
