# Phase 8c.1 — Timeline Data Model

**Date:** 2026-03-13  
**Status:** ✅ COMPLETED  
**Tests:** 2/2 passing (TimelineTrackTests.swift)  
**Build:** `swift build` clean

## Summary

Replaced deprecated `TrackReference` with enhanced `TimelineTrack` model to support NLE (Non-Linear Editor) timeline behavior. Added fields for widget linking, pinning, visibility, and audio control.

## Acceptance Criteria

- [x] TimelineTrack con campi NLE (linkedWidgetID, metricID, isPinned, isVisible, isMuted, isSolo)
- [x] Backward compatibility nel decoder (default values per nuovi campi)
- [x] Roundtrip Codable per persistenza JSON
- [x] SessionDocument aggiornato per usare TimelineTrack
- [x] 2+ test

## Files Changed

### TimelineTrack.swift v1.0.0 (created 2026-03-01, updated 2026-03-13)
- Replaced `TrackReference` with `TimelineTrack`
- Added `StreamType` enum (video, audio, accl, gyro, grav, cori, gps, speed, hr, cadence, power, temperature, force, angle, work, fusedVelocity, fusedPitch, fusedRoll)
- Core fields:
  - `id: UUID` (unique track identifier)
  - `sourceID: UUID` (DataSource reference)
  - `stream: StreamType` (semantic classification)
  - `offset: TimeInterval` (sync offset relative to timeline zero)
  - `displayName: String?` (optional override)
  
- **NLE fields** (new):
  - `linkedWidgetID: UUID?` — widget that created this track (nil if manually pinned/orphaned)
  - `metricID: String?` — metric key for sparkline rendering
  - `isPinned: Bool` — pinned tracks persist when their linked widget is removed
  - `isVisible: Bool` — visibility toggle (hide without removing)
  - `isMuted: Bool` — audio mute state (only for .audio stream)
  - `isSolo: Bool` — audio solo state (only for .audio stream)

- **Backward Compatibility**: Custom `init(from:)` decoder with default values for all NLE fields (allows loading old SessionDocuments without linkedWidgetID, etc.)

### SessionDocument.swift v1.0.1
- Updated `Timeline.tracks: [TimelineTrack]` field type
- (Note: TimelineTrack replaces TrackReference which was deleted)

### TimelineTrackTests.swift [NEW]
```
✓ backwardCompatDecoder — old JSON (no NLE fields) decodes with defaults
✓ codableRoundtripNLE — new JSON with all NLE fields round-trips correctly
```

## Design Notes

**Backward Compatibility:** JSON documents saved before 8c.1 lack linkedWidgetID, metricID, etc. The custom decoder provides sensible defaults (nil for pointers, false/true for booleans) so old sessions load without corruption.

**NLE Semantics:**
- `linkedWidgetID`: Establishes the widget→track relationship. When a widget is deleted (8c.2), tracks with matching linkedWidgetID are removed unless `isPinned=true`.
- `metricID`: Enables timeline sparklines to display the metric associated with a track (e.g., "gps_gpmf_ts_speed" for GPS track).
- `isPinned`: User-created annotations survive widget deletion; only non-pinned auto-tracks are garbage-collected.
- `isMuted`, `isSolo`: Audio mixing controls in the timeline (future UI phase).

## Dependency Chain

8c.1 (this task) → 8c.2 (Widget↔Track Lifecycle) → 8c.3 (Timeline Track Rendering)

---

Completed by: Claude (initial Phase 1)  
Extended by: Claude Haiku 4.5 (Phase 8 NLE fields)
