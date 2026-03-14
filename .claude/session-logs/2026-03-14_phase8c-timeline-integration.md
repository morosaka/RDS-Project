# Phase 8c — Timeline Integration Bug Fix
**Date:** 2026-03-14
**Status:** Complete
**Complexity:** S

---

## Objective

Fix missing timeline in live app. `TimelineView` (Phase 8c.3-5) was implemented but never
integrated into the main `RowingDeskCanvas` layout. The NLE timeline was not visible when
opening a session.

---

## Root Cause

`RowingDeskCanvas.body` consisted of:
```swift
HStack(spacing: 0) {
    GeometryReader { canvas... }      // canvas + widgets
    CanvasSidebar { ... }             // right sidebar 260pt
}
```

The `TimelineView` existed as a standalone component but was never included in the hierarchy.

---

## Fix

**`Sources/RowDataStudio/UI/RowingDeskCanvas.swift` v2.4.0 → v2.5.0**

### 1. Add `@State var viewportMs` (line 73)

```swift
@State private var viewportMs: ClosedRange<Double> = 0...60_000
```

Initialized to 1-minute default. Updated on `.onAppear` and `.onChange(of: sessionDurationMs)`.

### 2. Wrap layout in `VStack`

```swift
VStack(spacing: 0) {
    HStack(spacing: 0) {
        // Canvas + sidebar (unchanged)
    }   // end HStack

    Divider().background(Color(white: 0.12))

    TimelineView(
        playheadController: playheadController,
        sessionDocument:    dataContext.sessionDocument,
        viewportMs:         $viewportMs,
        onMoveTracks:       { ... },
        onPinTrack:         { ... },
        onMuteTrack:        { ... },
        onSoloTrack:        { ... },
        onToggleTrackVisibility: { ... },
        onOffsetTrack:      { ... },
        onAddCue:           { ... },
        onDeleteCue:        { ... },
        onSeekToCue:        { ... },
        onRenameCue:        { ... }
    )
    .frame(height: 220)
}   // end VStack
```

### 3. Wire all 10 callbacks to `mutateSession`

- **Track mutations:** `onMoveTracks`, `onPinTrack`, `onMuteTrack`, `onSoloTrack`, `onToggleTrackVisibility`, `onOffsetTrack`
  - Use built-in `TimelineTrack` array extensions: `.move()`, `.soloAudio(trackID:)`, `.applyOffset(_:to:)`
  - Toggle fields directly: `isPinned`, `isMuted`, `isVisible`

- **Cue mutations:** `onAddCue`, `onDeleteCue`, `onSeekToCue`, `onRenameCue`
  - Create new `CueMarker` at playhead position with auto-numbered label ("Cue 1", "Cue 2", …)
  - Seek playhead via `playheadController.seek(to:)`

### 4. Update viewport on session load

```swift
.onAppear {
    if let dur = dataContext.sessionDocument?.timeline.duration, dur > 0 {
        viewportMs = 0...(dur * 1_000)
    }
}
.onChange(of: dataContext.sessionDurationMs) { newDur in
    guard newDur > 0 else { return }
    viewportMs = 0...newDur
}
```

---

## Architecture Notes

**Layout hierarchy now:**
```
VStack
├─ HStack (canvas + sidebar)
│  ├─ Canvas (GeometryReader)
│  │  ├─ CanvasGrid
│  │  ├─ CanvasWidgetLayer (infinite canvas, widgets)
│  │  └─ Snap guides overlay
│  └─ CanvasSidebar (widget palette + inspector, 260pt)
├─ Divider
└─ TimelineView (NLE timeline, 220pt)
```

**Data flow:**
- `dataContext.sessionDocument.timeline.tracks` ← user drags, mutes, pins tracks
- `dataContext.sessionDocument.cueMarkers` ← user creates/renames bookmarks
- Both persisted by `mutateSession` 0.5s debounce

**Gesture priority:** Canvas pinch-to-zoom (HStack level) vs. widget-level zooms work
correctly because SwiftUI gives child gestures priority (established in Phase 8c bugfixes).

---

## Test Results

```
✔ Build clean — no errors
✔ 380 tests passed (all suites)
```

Timeline now visible when opening a session. Full track + cue editing functional.
