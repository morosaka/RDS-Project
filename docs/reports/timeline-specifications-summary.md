# Report: Timeline (NLE-Style) - Specifications & Implementation Status

**Date:** 2026-03-14
**Project:** RowData Studio
**Status:** Phase 8c (NLE Timeline & Audio) - Review of Task 8c.1-8

## 1. Vision & Architecture Overview

The Timeline is defined in `docs/vision/UI_UX_Vision_e_Specifiche_v2.md` (§4) as a **multi-track NLE timeline** (Non-Linear Editor), deeply integrated with the spatial canvas.

### Core Philosophy

- **Symmetry**: The canvas and timeline are synchronized views of the same data. Adding/removing a widget automatically manages the corresponding tracks.
- **Granularity (1:1)**: 1 metric = 1 track. A source file (e.g., MP4) is decomposed into independent tracks (Video track + Audio track).
- **Decoupling**: Video and Audio are treated as independent streams, allowing for flexible reordering, muting, and independent sync offsets.

---

## 2. Specification vs. Implementation Status

| Feature | Specification (Vision v2) | Implementation Status (Current) | Code Reference |
| ------- | ------------------------- | ------------------------------- | -------------- |
| **Multi-Track List** | Multi-track NLE style | ✅ **Complete** (v2.2.0) | `TimelineView.swift` |
| **Track Lifecycle** | Linked to widgets, Pin to keep | ✅ **Complete** | `TimelineTrack.swift` (`virtual()`, `isPinned`) |
| **Track Header** | Name, Color dot, Pin, Mute, Eye | ✅ **Complete** | `TimelineTrackRow.swift` |
| **A/V Decoupling** | Separate Video/Audio tracks | ✅ **Complete** | Phase 8c.8 / `VideoWidget` bugfix |
| **Sparklines** | Miniature waveforms/curves | 🟡 **Partial** | Rendering logic exists, DataContext wiring in progress |
| **Cue Track** | Dedicated bottom track for markers | ✅ **Complete** | `CueTrackView.swift` |
| **Marker Add (M)** | Keyboard shortcut 'M' for cues | ✅ **Complete** (macOS 14+) | `CueKeyPressModifier` |
| **Sync Offset** | Drag to time-shift tracks | ✅ **Implemented** | `onOffsetTrack` callback in `TimelineView` |
| **Ruler/Scrub** | Click-to-seek, drag-to-scrub ruler | ✅ **Complete** | `TimelineRuler.swift` |
| **Zoom/Scroll** | Pinch-to-zoom temporal scale | ✅ **Complete** | `MagnificationGesture` in `TimelineView` |

---

## 3. Technical Implementation Details

### Model-Driven Synchronization

The timeline is driven by the `SessionDocument.timeline.tracks` array.

- **`TimelineTrack` Model**: Includes `linkedWidgetID` for back-references and `isPinned` for persistence.
- **Virtual Tracks**: The `TimelineTrack.virtual()` factory allows the application to generate tracks on the fly when widgets are added to the canvas.

### Rendering Architecture (v2.0 Redesign)

The rendering path was optimized in Phase 8c.3 to handle high-density track lists:

- **Lazy Rendering**: Uses `LazyVStack` within a `ScrollView` for efficient track display.
- **Playhead System**: A unified `PlayheadController` drives the 60fps vertical line, which features an orange accent glow to distinguish it from static UI elements.
- **Cue Layering**: `CueTrackView` uses a `Canvas` layer for non-interactive pin lines and a SwiftUI overlay for interactive labels (double-tap to rename, context menu to delete).

---

## 4. Notable Implementation Notes (from Logs/Brain)

- **Audio/Video Separation**: As of Phase 8c.8, audio has been successfully stripped from `VideoWidget` (muted output) to allow `AudioTrackWidget` to handle visualization. Actual audio playback remains tied to the video's AVPlayer path for MVP A/V sync stability (Log 8c bugfixes).
- **Playhead Priority**: The playhead is non-magnetic to ensure consistent 60fps performance without being slowed down by snap-to-peak calculations on dense 200Hz data (Open Brain memory).
- **Keyboard Shortcuts**: Integration with native macOS 14+ `.onKeyPress` for the 'M' shortcut (Add Cue) follows the "Keyboard-First" interaction philosophy.

---

## 5. Summary of Functional Gaps

- **Sparkline Data Wiring**: While the `TimelineTrackRow` is ready to render sparklines, the active wiring to the high-performance `DataContext` pipelines (similar to chart widgets) is the primary focus of Phase 8c.4-8.
- **Magnetic Snapping**: Track dragging follows reordering rules, but "Magnetic Snapping" for sync offsets (snapping to video frames or stroke boundaries) is a post-MVP or secondary target.
