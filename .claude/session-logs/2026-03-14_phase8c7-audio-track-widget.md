# Phase 8c.7 — AudioTrackWidget
**Date:** 2026-03-14
**Status:** Complete
**Complexity:** L

---

## Objective

Implement `AudioTrackWidget`: a canvas widget that renders the audio waveform
peak pyramid from a `.waveform.gz` sidecar, displays a synchronized playhead
cursor, and exposes volume/mute controls (UI state only; AVAudioPlayerNode
playback is post-MVP).

Dependencies: 8c.6 (WaveformPeaks pyramid), 8c.2 (Widget↔Track lifecycle).

---

## Files Changed

### [NEW] `Sources/RowDataStudio/Rendering/Widgets/AudioTrackWidget.swift` v1.0.0

SwiftUI View conforming to `AnalysisWidget`. Key design decisions:

- `@ObservedObject var playheadController` — widget subscribes to 60fps ticks
  independently from the canvas, which uses `let` to avoid body re-evaluation.
- `waveformPeaks: WaveformPeaks?` — optional; widget shows a placeholder when nil
  (sidecar not yet generated or not loaded). Full DataContext wiring deferred to 8c.8.
- `viewportMs: ClosedRange<Double>` — passed from `CanvasWidgetLayer.widgetContent`,
  drives `peaksForViewport` level selection.
- **Waveform canvas**: SwiftUI `Canvas` (GPU-composited). Calls
  `peaks.peaksForViewport(viewportMs:widthPixels:)` to pick the coarsest level
  with ≥1 bin per pixel. Each bin drawn as a vertical line (min→max) with width
  `max(1.0, binWidth - 0.5)`.
- **Colour**: `RDS.Colors.accent.opacity(0.35 + 0.65 * volume)` when active;
  `Color(white: 0.30)` when muted.
- **Playhead overlay**: orange 1.5pt line, 4pt glow, `allowsHitTesting(false)`.
- **Control bar** (28pt fixed height): mute button (speaker SF Symbol),
  volume `Slider`, level readout in monospaced caption.
- **Default size**: 480 × 100 pt (wide, compact — typical NLE audio track height).

### [MODIFY] `Sources/RowDataStudio/Rendering/Widgets/WidgetProtocol.swift` v1.1.0 → v1.2.0

Added `case audio = "audio"` to `WidgetType` enum:

```swift
case audio = "audio"
```

Properties added to each switch:
- `displayName`: `"Audio Track"`
- `icon`:        `"waveform"`
- `defaultSize`: `CGSize(width: 480, height: 100)`

### [MODIFY] `Sources/RowDataStudio/UI/RowingDeskCanvas.swift` v2.3.0 → v2.4.0

Two additions:

**1. `tracks(for:)` — `.audio` case:**
```swift
case .audio:
    return [.virtual(stream: .audio, linkedWidgetID: widget.id, displayName: "Audio")]
```
Audio widget creates 1 `.audio` stream TimelineTrack (displayed in the NLE).

**2. `widgetContent(for:)` — `.audio` case:**
```swift
case .audio:
    // waveformPeaks wiring deferred to 8c.8 (DataContext integration).
    AudioTrackWidget(state: widget, dataContext: dataContext,
                     playheadController: playheadController,
                     waveformPeaks: nil, viewportMs: viewport)
```
Widget renders placeholder until 8c.8 wires DataContext → WaveformPeaks loading.

### [MODIFY] `Tests/RowDataStudioTests/Rendering/Widgets/WidgetProtocolTests.swift`

- Updated `allCasesCount` test: 7 → 8 (`#expect(WidgetType.allCases.count == 8)`)
- Added `#expect(WidgetType.audio.rawValue == "audio")` to `rawValues` test

### [NEW] `Tests/RowDataStudioTests/Rendering/Widgets/AudioTrackWidgetTests.swift`

16 tests in `@Suite("AudioTrackWidget")`:

| Test | What is verified |
|---|---|
| `audioRawValue` | `rawValue == "audio"` |
| `audioDisplayName` | `displayName == "Audio Track"` |
| `audioIcon` | `icon == "waveform"` |
| `audioDefaultSize` | 480 × 100 |
| `audioInAllCases` | `.audio ∈ allCases` |
| `audioRawValueRoundTrip` | `WidgetType(rawValue: "audio") == .audio` |
| `makeAudioWidgetType` | `ws.widgetType == "audio"`, `ws.type == .audio` |
| `makeAudioDefaultSize` | size matches `WidgetType.audio.defaultSize` |
| `makeAudioDefaultTitle` | title == "Audio Track" |
| `tracksForAudioCount` | exactly 1 track |
| `tracksForAudioStreamType` | stream == `.audio` |
| `tracksForAudioLinkedWidgetID` | links to widget ID |
| `tracksForAudioDisplayName` | `"Audio"` |
| `viewportEmptyPeaks` | empty WaveformPeaks → empty slice |
| `viewportZeroWidth` | widthPixels: 0 → empty slice |
| `viewportSelectsLevel0ForNarrow` | narrow viewport → non-empty result |

---

## Architecture Notes

### Why `waveformPeaks: nil` in the canvas factory

`CanvasWidgetLayer.widgetContent(for:)` runs on the render path (called every
SwiftUI body evaluation). Loading a sidecar from disk here would introduce I/O
latency. The correct pattern is to load the sidecar into `DataContext` once
(on session open / after generation), then pass it down. That wiring is 8c.8.

### Playhead subscription model

`AudioTrackWidget` uses `@ObservedObject var playheadController` — the same
pattern as other time-sensitive widgets. The canvas (`CanvasWidgetLayer`) passes
`playheadController` as a `let` to avoid the canvas body re-evaluating at 60fps,
but the individual widget view can subscribe independently.

### Volume opacity encoding

`opacity = 0.35 + 0.65 * volume` — ensures the waveform is always at least 35%
visible (navigation usability) while the remaining 65% is volume-proportional.
Muted state hard-codes grey regardless of volume.

---

## Test Results

```
✔ 16/16 AudioTrackWidget tests passed
✔ 9/9 WidgetType tests passed (including updated allCasesCount)
Build complete — no errors, 1 pre-existing unrelated warning
```
