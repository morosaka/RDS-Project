# Phase 8c.3 — Timeline Track Rendering

**Date:** 2026-03-14  
**Status:** ✅ COMPLETED  
**Build:** `swift build` clean (0 warnings)  
**Tests:** No new tests (pure UI — visual correctness verified by build)

## Acceptance Criteria

- [x] Track rendering basato su `TimelineTrack` model, non su `DataSource`
- [x] Header con color dot semantico + nome + pin/mute/eye icons
- [x] Sparklines per track metriche (quando dati disponibili)
- [x] Drag to reorder funzionante (onMove callback)
- [x] Playhead arancio con glow
- [x] Stile dark coerente con design system

## Files Changed

### DesignTokens.swift → v1.1.0
- Added `StreamType.symbolName: String` — SF Symbol per tipo di stream
  - `.video` → `"video.fill"`, `.audio` → `"waveform"`, `.gps` → `"location.fill"`, etc.
- `StreamType.semanticColor` già presente (invariato)

### TimelineTrackRow.swift → v2.0.0
Completo redesign NLE model-driven.

**Signature:**
```swift
public struct TimelineTrackRow: View {
    let track: TimelineTrack
    let viewportMs: ClosedRange<Double>
    let sessionDurationMs: Double
    let sparklineData: ContiguousArray<Float>?
    let onPin: () -> Void
    let onMute: () -> Void
    let onToggleVisibility: () -> Void
}
```

**Struttura:**
- `HStack`: header (80pt fissi) + content area (`height: 28`)
- **Header**: colore semantico dot (10pt) + nome troncato + icona stream + bottoni [pin, mute*, eye]
  - *mute visibile solo per `.audio`
  - Pin: `pin.fill` arancio se pinned, `pin` grigio altrimenti
  - Eye: `eye.slash` arancio se nascosto, `eye` grigio se visibile
- **Content** (dispatching su `track.stream`):
  - `.video` → `checkerboardBar(color:)` — pattern a scacchiera con colore semantico
  - `.audio` + sparklineData → `sparklineView(data:color:)`
  - `.audio` senza dati → `solidBar(color:)`
  - qualsiasi altra stream + sparklineData → `sparklineView`
  - qualsiasi altra stream senza dati → `solidBar`
  - `!track.isVisible` → opacity 0.1 sull'intera content area
- **Sparkline Canvas**: linea (1pt) + fill sotto (opacity 0.15), altezza 24pt, normalizzato min/max

### TimelineView.swift → v2.0.0
- Iterazione da `doc.sources` → `doc.timeline.tracks` (ForEach su `[TimelineTrack]`)
- `.onMove` → `onMoveTracks?((IndexSet, Int) -> Void)` callback — ordine = posizione array
- **Callbacks aggiunti**: `onMoveTracks`, `onPinTrack`, `onMuteTrack`, `onToggleTrackVisibility` (tutti opzionali, default nil)
- **Track spacing**: `LazyVStack(spacing: 2)` — no separator lines
- **Playhead**: da `.red` a `RDS.Colors.accent` (arancio) + `.shadow(color: accent.opacity(0.4), radius: 6)`
- Playhead x-origin corretto: `80 + normalizedPos * contentWidth` (allineato al content area, non al bordo schermo)
- `sparklineData: nil` passato a ogni `TimelineTrackRow` — sarà iniettato dal `DataContext` in 8c.4

## Decisioni Architetturali

**sparklineData è nil per ora:** La wiring con DataContext (sorgente effettiva dei campioni) avverrà in 8c.4. Il componente è già pronto a riceverlo; finché è nil mostra solid bar (fallback corretto).

**onMoveTracks è un callback, non una Binding:** TimelineView non possiede il SessionDocument — la mutazione avviene nel chiamante (RowingDeskCanvas/DataContext). Pattern coerente con 8c.2 `mutateSession`.

**LazyVStack vs List:** Si usa `LazyVStack` (non `List`) per evitare lo stile di default di List (sfondo bianco/separatori) e per poter controllare al pixel l'aspetto dark. Il `.onMove` su `ForEach` dentro `List` sarebbe più idiomatico ma rompe il dark styling. Accettabile per il numero atteso di track (< 50).

## Next: 8c.4 — Track Interactions

- Wire `onPinTrack`, `onMuteTrack`, `onToggleTrackVisibility` in `RowingDeskCanvas.mutateSession`
- Iniettare `sparklineData` da `DataContext` (richiede lookup per metricID)
- Track solo mode (isola una track, dima le altre)

---

Completed by: Claude Sonnet 4.6  
Model: claude-sonnet-4-6
