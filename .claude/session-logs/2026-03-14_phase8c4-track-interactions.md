# Phase 8c.4 — Track Interactions

**Date:** 2026-03-14  
**Status:** ✅ COMPLETED  
**Tests:** 13/13 passing (TrackInteractionTests.swift)  
**Build:** `swift build` clean

## Acceptance Criteria

- [x] Pin/unpin funzionante con icona che cambia
- [x] Mute/unmute per track audio
- [x] Solo: mute tutte le altre audio, unmute questa (via Option+click su macOS)
- [x] Eye toggle nasconde/mostra sparkline (opacity 0.1 su content area)
- [x] Drag orizzontale modifica offset con feedback visivo (overlay ms durante drag)

## Files Changed

### TimelineTrack.swift → v1.2.0
Aggiunte due `Array<TimelineTrack>` mutations:

```swift
// Solo: muta tutte le .audio track, isola la target
mutating func soloAudio(trackID: UUID)

// Aggiunge delta (secondi) all'offset della track specificata
mutating func applyOffset(_ delta: TimeInterval, to trackID: UUID)
```

`applyOffset` costruisce un nuovo `TimelineTrack` con offset aggiornato (TimelineTrack è struct immutabile).

### TimelineTrackRow.swift → v2.1.0
**Offset drag gesture:**
- `DragGesture(minimumDistance: 4)` sul content area (via `GeometryReader`)
- `msPerPoint = viewportDuration / contentWidth` — converte px → ms
- `.onChanged`: mostra overlay `"+NNN ms"` in arancio (RDS.Colors.accent) su sfondo nero
- `.onEnded`: chiama `onOffsetDrag(deltaSeconds)` col delta totale del drag
- `@State var isDraggingOffset` e `@State var dragOffsetPreviewMs` per stato locale

**Solo (Option+click mute):**
- `muteOrSoloAction()`: su macOS controlla `NSEvent.modifierFlags.contains(.option)`
  - Option tenuto → `onSolo()`
  - Click normale → `onMute()`
  - iOS fallback: sempre `onMute()`
- `#if os(macOS)` guard per `AppKit` import

**Nuovi callback in init:**
```swift
let onSolo: () -> Void
let onOffsetDrag: (TimeInterval) -> Void
```
Tutti con default no-op per backward compat.

### TimelineView.swift → v2.1.0
Nuovi parametri (tutti opzionali, default nil):
```swift
let onSoloTrack: ((UUID) -> Void)?
let onOffsetTrack: ((UUID, TimeInterval) -> Void)?
```
Propagati a ogni `TimelineTrackRow` nel ForEach.

### MultiLineChartWidgetTests.swift — bugfix pre-existing
Rimossi 2 test obsoleti (`defaultTargetPoints`, `customTargetPoints`) che testavano `targetPointCount` rimosso in commit `e81f6ec`. Sblocca la compilazione del test module.

### TrackInteractionTests.swift [NEW]
13 test Swift Testing (`@Test`, `#expect`):

```
✔ Pin: isPinned toggles to true
✔ Pin: isPinned toggles back to false
✔ Mute: isMuted toggles on audio track
✔ Mute: non-audio track can also be muted via toggle
✔ Visibility: isVisible toggles to false (hidden)
✔ Visibility: hidden track can be restored
✔ Solo: soloAudio mutes all other audio tracks, unmutes target
✔ Solo: soloAudio leaves non-audio tracks untouched
✔ Solo: soloAudio on unknown id leaves all audio muted state unchanged
✔ Offset: applyOffset adds positive delta
✔ Offset: applyOffset adds negative delta
✔ Offset: applyOffset leaves other tracks unchanged
✔ Offset: applyOffset with unknown id changes nothing
```

## Decisioni Architetturali

**Offset drag su contenuto track, non su header:** Il drag cattura la semantica "allinea questa track trascinando nel tempo" — intuitivo perché l'utente trascina la barra dati, non l'etichetta. `minimumDistance: 4` evita conflitti con tap sui bottoni.

**Solo via Option+click:** Pattern standard NLE (Premiere Pro, DaVinci). Non è uno shortcut a sé stante — è il modifier naturale sul gesto esistente. iOS non ha Option, usa solo mute normale.

**Array mutations invece di metodi su SessionDocument:** Le helpers `soloAudio` e `applyOffset` operano su `[TimelineTrack]` direttamente. Il chiamante (`RowingDeskCanvas.mutateSession`) passa `doc.timeline.tracks` a queste funzioni. Mantiene il modello ignorante della logica UI.

**TimelineTrack è struct — no mutating properties:** `applyOffset` deve ricostruire il valore tramite `init` completo. Questo è corretto — le struct in SwiftUI devono essere value types immutabili. La ricostruzione esplicita rende chiaro quali campi cambiano.

## Note

- `sparklineData` rimane `nil` — wiring via DataContext previsto in 8c.7
- Le callbacks nel TimelineView (onPinTrack, onMuteTrack, etc.) sono già pronte; la wiring con `RowingDeskCanvas.mutateSession` avverrà quando TimelineView sarà integrata nel canvas (8c.8)

## Next: 8c.5 — Cue/Bookmark Track

- Nuovo modello `CueMarker` (timeMs, label, color)
- Aggiunta a `SessionDocument.cueMarkers` con backward compat
- `CueTrackView`: + button, pin verticali cliccabili, editing inline label
- Shortcut M → crea cue alla posizione playhead
- 4+ test round-trip

---

Completed by: Claude Sonnet 4.6  
Model: claude-sonnet-4-6
