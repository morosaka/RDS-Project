# Report: Zoom Functions - Specifications & Implementation Status

**Date:** 2026-03-14 (Updated)
**Project:** RowData Studio
**Status:** Phase 8 (Canvas Interaction) - Review of Task 8b.5 & Phase 8c Bugfixes

## 1. Vision & Architecture Overview

The RowData Studio zoom model is built on a **Three-Layer Hierarchy**, designed to balance global session context with local data deep-dives. This is defined in `docs/vision/UI_UX_Vision_e_Specifiche_v2.md` (§6).

### The Three-Layer Zoom Model

1. **Layer 1: Canvas Zoom (Spatial)**: Uniform 2D scale of the entire workspace.
2. **Layer 2: Global Temporal Zoom (Timeline)**: Global time window (`viewportMs`) shared across all linked widgets.
3. **Layer 3: Local Data Zoom (Widget Override)**: Independent X/Y zoom within a specific widget, decoupling it from the global state.

---

## 2. Specification vs. Implementation Status

| Feature | Specification (Vision v2) | Implementation Status (Current) | Code Reference |
| ------- | ------------------------- | ------------------------------- | -------------- |
| **Canvas Zoom** | Pinch/Cmd+Scroll on empty canvas (25%-400%) | ✅ **Complete** (v2.4.0) | `RowingDeskCanvas.swift` |
| **Canvas Pan** | Two-finger drag / Middle-click drag | ✅ **Complete** | `RowingDeskCanvas.swift` |
| **Global Sync** | All widgets follow Timeline `viewportMs` | ✅ **Complete** | `TimelineView.swift` |
| **Local X-Zoom** | Pinch inside Chart widget (unlinks time) | ✅ **Fixed & Verified** (8c) | `LineChartWidget`, `MultiLineChartWidget` |
| **Local Y-Zoom** | Option+Scroll / Vertical pinch (zooms values) | ❌ **Missing** | Requires `LocalZoomMath` evolution |
| **Local Reset** | Double-tap/click inside widget to re-link | ✅ **Complete** | `LineChartWidget`, `MultiLineChartWidget` |
| **Force Global** | Shift+Pinch inside widget to zoom Timeline | ❌ **Missing** | Requires gesture refinement |
| **Visual Feedback** | Labels turn Orange when unlinked | ✅ **Complete** | `LineChartWidget`, `MultiLineChartWidget` |

---

## 3. Technical Implementation & Recent Fixes (Phase 8c)

### Performance Optimization (v2.0 Refactor)

One of the most critical architectural decisions was to **decouple zoom/pan state from the `@Published` session document** during active animation.

- **Reactive Isolation**: `canvasZoom` and `canvasPan` live as local `@State` variables to avoid 60fps re-evaluations of the entire Canvas tree.
- **Debounced Persistence**: Changes are written back to `sessionDocument` only after a 0.5s idle period.

### The "Bug 2" Fix (Log 8c)

A significant regression was fixed in Phase 8c. Initially, an `NSEvent` monitor on the Canvas was consuming `.magnify` events at the window level, preventing child widgets from receiving zoom gestures.

- **Solution**: Removed `.magnify` from `NSEvent` and implemented the Canvas-level zoom using a SwiftUI `MagnificationGesture` on the `ZStack` background.
- **Gesture Priority**: This leverages SwiftUI's "child-before-parent" priority. A pinch over a chart triggers Local Zoom (child); a pinch over empty space triggers Canvas Zoom (parent).
- **Live Feedback**: Added `@GestureState liveZoomScale` to provide smooth visual feedback during the pinch without permanent state mutation.

### Local Zoom Logic (`LocalZoomMath`)

Uses a pure math utility (`Sources/RowDataStudio/Rendering/Widgets/LocalZoomMath.swift`):

- **Centric Scaling**: Zoom is centered on the current viewport midpoint.
- **Clamping**: Enforces a `minSpanMs` (1 second) floor.

---

## 4. Video/Audio Separation & Zoom (Phase 8c.8 Updates)

Log 8c.8 and the subsequent 8c-bugfix clarified the relationship between Video and Audio widgets:

- **VideoWidget**: Renders video and provides audio output via AVPlayer (for now).
- **AudioTrackWidget**: Visualizes the waveform and provides volume UI, but does not yet handle its own playback (Post-MVP goal).
- **Zoom Impact**: Global temporal zoom (Layer 2) drives both video thumbnails and waveform alignment on the timeline.

---

## 5. Discrepancies & Recommendations

1. **Y-Axis Zoom**: Specification for manual Y-axis override (Option+Scroll) remains unimplemented. Charts currently only use auto-fit.
2. **Force Global Zoom**: `Shift+Pinch` to drive the global timeline from within a widget is not yet wired up.
3. **Video Local Zoom**: Not currently supported; video follows global sync only.
