---
date: 2026-03-08 17:00
scope: Phase 6 — Canvas & Widgets (+ Phase 5 UI Views)
status: completed
---

## Summary

Completed Phase 6 (Canvas & Widgets) in full, including the Phase 5 UI views that had been deferred.
Total test count: 262 (from 207 at start of session). All 262 tests pass. Build clean.

## Changes

### Phase 5 UI Views (deferred, now complete)

- **SessionRow.swift** v1.0.0: List row component. Displays title, date, duration, source count badge.
- **SessionListView.swift** v1.0.0: Loads sessions from `SessionStore`, shows sorted list. Navigation via `@State var selectedSessionID: UUID?` (SessionDocument is not Hashable due to NKEmpowerSession). `#if os(macOS)` UIColor alias here only.
- **SessionDetailView.swift** v1.0.0: Session metadata, data sources, canvas widget count, Empower data indicator, "Open Session" / "Export Data" buttons. Opens `RowingDeskCanvas` via `navigationDestination`.
- **ImportView.swift** v1.0.0: File picker + drag-and-drop import. Calls `FileImporter.import(from:)` async, creates `SessionDocument`, saves via `SessionStore`.

### Phase 6 Core Infrastructure

- **DataContext.swift** v1.2.0: Added `@Published var sessionDocument: SessionDocument?` — live link between SessionStore data and canvas rendering.
- **WidgetProtocol.swift** v1.1.0:
  - `WidgetType` enum: 7 cases, `rawValue` = WidgetState.widgetType string for Codable persistence.
    - `.lineChart`, `.multiLineChart`, `.strokeTable`, `.metricCard`, `.map`, `.empowerRadar`, `.video`
    - Each has `.displayName`, `.icon` (SF Symbol), `.defaultSize: CGSize`
  - `WidgetState` extension: `.type: WidgetType?`, `.metricIDs: [String]`, `.title: String`, `.isVisible: Bool`, `.make(type:position:metricIDs:title:) -> WidgetState`
  - `AnalysisWidget` protocol: `var state`, `var dataContext`, `var playheadController`
  - **No WidgetConfig** — pre-existing `WidgetState` in `CanvasState.swift` already covers all needs.
- **WidgetContainer.swift** v1.1.0:
  - Wraps any widget content with drag-to-move, resize handle (bottom-right), selection highlight.
  - Uses `@GestureState` for live preview during gesture (committed to model only on `onEnded`).
  - `content: AnyView` (not generic closure) for ergonomic use in `ForEach`.
  - Header bar: icon from `state.type?.icon`, title from `state.title`, visibility toggle, delete button.
  - `.zIndex(isSelected ? 1000 : Double(state.zIndex))` for selection elevation.

### Phase 6 Widget Implementations

- **LineChartWidget.swift** v1.0.0 (Phase 4, no changes): Single metric line chart with LTTB pipeline.
- **MultiLineChartWidget.swift** v1.0.0:
  - `MetricSeries` struct: `id: UUID`, `label`, `timestamps`, `values`, `color`.
  - Overlays multiple series on shared Y-axis (global min/max across all series).
  - Legend strip at bottom with colored line segments.
  - Static `palette: [Color]` (6 colors), `series(from:metricIDs:)` factory method on DataContext.
  - `.drawingGroup()` + per-series Canvas paths.
- **StrokeTableWidget.swift** v1.0.0:
  - Columns: #, Rate (SPM), Dist (m), AvgV (m/s), PeakV (m/s), HR (bpm).
  - `LazyVStack` inside `ScrollViewReader` for virtualization + auto-scroll to active row.
  - Active row: last stroke whose `startTime * 1000 ≤ playheadTimeMs`.
  - Empty state placeholder with icon.
- **MapWidget.swift** v1.0.0:
  - GPS track polyline drawn as Canvas overlay on `Map(coordinateRegion:)`.
  - Playhead position as `MapAnnotation` red dot.
  - `fitRegionToTrack()` on appear: fits MKCoordinateRegion to track bounding box × 1.3 padding.
  - GPS data from `DataContext.buffers.dynamic["gps_gpmf_ts_lat"]` / `"..._lon"`.
  - No-data placeholder when buffers empty.
- **EmpowerRadarWidget.swift** v1.0.0:
  - Spider chart with 6 NK Empower axes: Avg Force, Peak Force, Work, Catch Angle, Finish Angle, Slip.
  - Background rings at 0.25/0.5/0.75/1.0 radius; axis spokes drawn first.
  - Current stroke (accent, 0.25 opacity fill) + session average (gray, 0.12 fill) overlaid.
  - Axis labels positioned with `ZStack` + `.position(x:y:)` relative to center.
  - `Axis` struct: `label`, `key`, `referenceMax`, `inverted` (lower=better, e.g. slip).
  - `defaultAxes` static property with rowing-typical reference maxima.
  - No-data placeholder when both `currentStroke` and `averageMetrics` are empty.
- **MetricCardWidget.swift** v1.0.0:
  - Binary-search timestamp indexing for O(log n) playhead lookup.
  - Shows trend % vs session mean with up/down arrow.
  - `formatValue()` adaptive precision (0/1/2 decimal places by magnitude).

### Canvas Orchestrator

- **RowingDeskCanvas.swift** v1.2.0:
  - Widget factory `widgetContent(for:) -> AnyView` wired to all 7 widget types (was placeholder for 5/7).
  - `.lineChart` → `LineChartWidget`
  - `.multiLineChart` → `MultiLineChartWidget.series(from:metricIDs:)`
  - `.metricCard` → `MetricCardWidget`
  - `.strokeTable` → `StrokeTableWidget` with `fusionResult.strokes.map { $0.startTime * 1000 }`
  - `.map` → `MapWidget` reading `buffers.dynamic` lat/lon
  - `.empowerRadar` → `EmpowerRadarWidget` with per-playhead active stroke + averaged metrics
  - `.video` → placeholder (Phase 7)
  - `mutateCanvas(_:)`: single mutation point, auto-saves async via `SessionStore`.
  - Pan: `DragGesture` + `@GestureState livePanDelta`, committed on `onEnded`.
  - Zoom: `MagnificationGesture` + `@GestureState liveMagnification`, clamped 0.25–4.0.
  - Sidebar (260pt): widget palette (collapsible) + inspector (position, size, metrics).
  - `canvasGrid(size:)`: SwiftUI `Canvas { context, size in }` with 50pt grid lines.

### Tests (40 new tests, 262 total)

**WidgetProtocolTests.swift** (16 tests):
- `WidgetType`: all 7 cases, raw values, display names non-empty, icons non-empty, default sizes positive, round-trip rawValue, unknown returns nil.
- `WidgetState` extension: `make()` factory (widgetType, size, metricIDs, title, title fallback, position), `type` computed property, `type nil` for unknown string, `isVisible` default true, `isVisible false`, `metricIDs` empty/multiple.

**StrokeTableWidgetTests.swift** (9 tests):
- Widget init with empty start times, strokes array preserved, stroke rate precision, nil distance handling, distance formatting, HR rounding, stroke index zero-padding, empty strokes, start times count mismatch graceful.

**MultiLineChartWidgetTests.swift** (15 tests):
- `MetricSeries`: basic storage, unique IDs.
- Palette: 6 colors, `series(from:metricIDs:)` empty DC returns empty, unknown metric key returns empty, palette wraparound at index 6.
- Widget init: series count stored, empty series valid, default targetPointCount 1500, custom targetPointCount stored.

## Decisions Made

1. **No WidgetConfig type**: Pre-existing `WidgetState` in `CanvasState.swift` fully covers widget data. Adding a separate `WidgetConfig` would be duplication. Extending `WidgetState` with convenience computed properties is the right pattern.
2. **`AnyView` for widget content**: `WidgetContainer` uses `content: AnyView` rather than a generic `<Content: View>` parameter. Avoids complex type erasure in `ForEach` and makes the factory pattern in `RowingDeskCanvas` ergonomic.
3. **`@GestureState` for live gesture preview**: Never mutate the model during gesture updating — only on `onEnded`. `@GestureState` auto-resets to initial value when gesture ends, ensuring clean state.
4. **MapKit GPS track as Canvas overlay**: `Map(coordinateRegion:)` doesn't support `MKPolyline` in SwiftUI on macOS 13. Canvas overlay converts GPS coords to screen proportional coordinates using `region.span`. Works well for rowing distances (< 3km).
5. **Radar spider chart via Canvas polygon**: SwiftUI Canvas `Path` + `context.fill/stroke` for full control over radar geometry. Avoids external chart libraries.
6. **SessionDocument not Hashable**: `NKEmpowerSession` is `Codable+Sendable` but not `Hashable/Equatable` (contains `[NKEmpowerStroke]` which is also not `Hashable`). Workaround: `@State var selectedSessionID: UUID?` + `navigationDestination(isPresented:)`.

## Bugs Fixed

- `Color(.systemGray5/.systemGray6)` → `Color.gray.opacity(0.15)` (NSColor has no systemGray5/6)
- `Color.tertiary` → `.secondary` (tertiary label doesn't conform to `Color`)
- `.offset(CGPoint)` → `.offset(x: y:)` (offset takes two named params, not CGPoint)
- `navigationBarTitleDisplayMode` → removed (macOS API doesn't have it)
- `try SessionStore()` (init throws) vs `SessionStore()` (must handle error)
- `try await FileImporter.import(from:)` (async) — must be awaited
- `NavigationLink(value:)` requires Hashable on value type → replaced with UUID-based `@State`
- `Canvas { context in }` → `Canvas { context, size in }` (needs 2 params)
- `mapValues { $0 / Double(counts[$0.hashValue] ?? 1) }` — `$0` in mapValues is the Double value, not the key. Fixed with `reduce(into:)` that has access to both key and value.
- `UIColor` duplicate declaration when added to multiple files — keep `#if os(macOS) typealias UIColor = NSColor #endif` only in `SessionListView.swift`.

## Architecture Notes

- Canvas mutations follow single-entry pattern via `mutateCanvas(_:)`, which guarantees consistent async persistence.
- Widget factory evaluates data lazily per widget type — no unnecessary `DataContext` reads for invisible widgets.
- All new widget types have empty-state placeholders — canvas renders gracefully before any data is loaded.
- `MetricSeries.id` is a new UUID per init — series in `ForEach` are stable within a render pass but regenerated on `DataContext` changes (acceptable for chart rendering).

## Open Questions / Blockers

None. Phase 6 is complete and fully tested.

## Next Steps (Phase 7)

**Phase 7: Video Integration**

Goal: synchronized video playback tied to the PlayheadController.

Files to create:
- `Sources/RowDataStudio/Rendering/Widgets/VideoWidget.swift` — AVPlayer in canvas widget
- `Sources/RowDataStudio/Core/Services/VideoSyncController.swift` — bidirectional AVPlayer ↔ PlayheadController sync
- `Sources/RowDataStudio/UI/VideoPlayer/VideoPlayerView.swift` — AVKit SwiftUI wrapper
- `Sources/RowDataStudio/UI/VideoPlayer/VideoTrimView.swift` — visual trim interface
- `Sources/RowDataStudio/UI/Timeline/TimelineView.swift` — multi-track timeline
- `Sources/RowDataStudio/UI/Timeline/TimelineTrack.swift` — individual track
- `Sources/RowDataStudio/UI/Timeline/TimelineRuler.swift` — time ruler

Key implementation notes:
- `addPeriodicTimeObserver(forInterval:queue:using:)` at 1/60s for video → playhead sync
- Bidirectional: video play updates playhead; timeline scrub seeks video
- Multi-camera: multiple `VideoWidget` instances with independent offset values, same `PlayheadController`
- AVFoundation passthrough does NOT preserve GPMF track — always generate sidecar before trim (Phase 5 `SidecarGenerator` already handles this)
- `AVPlayerItem` + `AVPlayer` wrapped in `@MainActor` class to bridge with SwiftUI

## Test Results

```
Test run with 262 tests in 42 suites passed after 0.415 seconds.
✔ Suite "WidgetType" passed
✔ Suite "WidgetState extensions" passed
✔ Suite "StrokeTableWidget" passed
✔ Suite "MetricSeries" passed
✔ Suite "MultiLineChartWidget palette" passed
✔ Suite "MultiLineChartWidget init" passed
(+ all 42 prior suites)
```

## Build Status

- `swift build` completes with no warnings or errors
- All 3 SDK modules compile (GPMF, FIT, CSV)
- App target links cleanly with MapKit
- Test target: 262 tests, 42 suites, 0 failures
