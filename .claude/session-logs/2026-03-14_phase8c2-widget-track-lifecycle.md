# Phase 8c.2 — Widget ↔ Track Lifecycle

**Date:** 2026-03-14  
**Status:** ✅ COMPLETED  
**Tests:** 11/11 passing (TrackLifecycleTests.swift)  
**Build:** `swift build` clean (no warnings)

## Acceptance Criteria

- [x] `mutateCanvas` rinominato a `mutateSession` (renamed from existing `mutateWidgets`)
- [x] Aggiunta widget → track automatiche create in timeline
- [x] Rimozione widget → track non-pinned rimosse  
- [x] Track pinned sopravvivono alla rimozione widget
- [x] Radar e MetricCard non creano track (0 tracks each)
- [x] 4+ test (11 tests written)

## Files Changed

### TimelineTrack.swift v1.1.0
- Added `TimelineTrack.virtual(stream:linkedWidgetID:metricID:displayName:)` factory
- Creates synthetic track with `sourceID = UUID()` (no real DataSource reference)
- Used when widgets auto-generate timeline entries

### RowingDeskCanvas.swift v2.3.0
- Renamed `mutateWidgets(inout [WidgetState])` → `mutateSession(inout SessionDocument)` 
- Updated all call sites (`commitMove`, `commitResize`, `toggleVisibility`, `handleWidgetSelection`, `toggleTier`)
- `addWidget`: Creates tracks via `Self.tracks(for:)`, appends to both canvas + timeline
- `deleteWidget`: Removes widget + non-pinned linked tracks; pinned tracks persist
- `nonisolated static func streamType(for metricID: String) -> StreamType`
  - Parses metric ID prefix (gps_, imu_, fit_, fus_)
  - Returns appropriate StreamType or .speed (fallback)
- `nonisolated static func tracks(for widget: WidgetState) -> [TimelineTrack]`
  - Video → 1 track (.video)
  - Map → 1 track (.gps)
  - LineChart/MultiLineChart/StrokeTable → 1 per metricID
  - MetricCard/EmpowerRadar → 0 tracks (derived/KPI)

### TimelineTrackRow.swift (renamed from TimelineTrack.swift)
- Fixed pre-existing build error: two files named `TimelineTrack.swift` caused SPM "multiple producers" conflict
- Renamed UI view file to match component name
- Updated calls in TimelineView.swift

### TrackLifecycleTests.swift [NEW]
```
✓ addMultiLineChartCreatesTrackPerMetric
✓ deleteWidgetRemovesLinkedTracks
✓ deleteWidgetPreservesPinnedTrack
✓ addMetricCardCreatesNoTracks
✓ addEmpowerRadarCreatesNoTracks
✓ addVideoWidgetCreatesOneVideoTrack
✓ addMapWidgetCreatesOneGPSTrack
✓ streamTypeGPS
✓ streamTypeIMUAccel
✓ streamTypeIMUGyro
✓ streamTypeFusedVelocity
```

## Design Notes

**Synthetic track sourceID:** Widget-generated tracks use `sourceID = UUID()` because they have no real DataSource backing. The `linkedWidgetID` is the authoritative reference. When a DataSource is later assigned to a widget's data, the sourceID can be updated during 8c.3-8c.4 rendering.

**Track pinning:** Non-pinned tracks are garbage-collected when their widget is removed. Pinned tracks survive, allowing users to keep timeline annotations (e.g., "Interesting sequence here") even after dismissing the analysis widget.

**StreamType inference:** Metric ID prefixes (gps_, imu_, fit_, fus_) are sufficient to classify stream types. This avoids requiring per-widget source assignment at add-time.

## Pre-existing Issues

- `MultiLineChartWidgetTests.swift` has 2 test failures (unrelated to 8c.2):
  - `MultiLineChartWidget` removed `targetPointCount` property in commit e81f6ec  
  - Tests reference a removed member — must be fixed separately

## Next: 8c.3

Timeline track rendering redesign:
- Replace old `TimelineTrackRow` view with model-driven component
- Add sparklines, color dots, pin/mute/eye icons
- Drag-to-reorder tracks
- Playhead styling (orange accent + glow)

---

Completed by: Claude Haiku 4.5  
Model: claude-haiku-4-5-20251001 (switched via /model for speed)
