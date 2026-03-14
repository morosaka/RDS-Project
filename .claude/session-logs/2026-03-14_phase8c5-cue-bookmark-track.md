# Phase 8c.5 — Cue/Bookmark Track

**Date:** 2026-03-14  
**Status:** ✅ COMPLETED  
**Tests:** 6/6 passing (CueMarkerTests.swift)  
**Build:** `swift build` clean

## Acceptance Criteria

- [x] Cue track visibile in fondo alla timeline (CueTrackView)
- [x] M aggiunge cue alla posizione playhead (KeyPress modifier, macOS 14+)
- [x] Click su cue → seek playhead
- [x] Label editabili inline (TextField con onSubmit/onExitCommand)
- [x] Delete cue via context menu (right-click → "Delete Cue")
- [x] Cue persistiti in SessionDocument.cueMarkers
- [x] 6 test (superano il minimo richiesto di 4)

## Files Changed

### CueMarker.swift [NEW] v1.0.0
```swift
public struct CueMarker: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var timeMs: Double       // posizione in ms da session zero
    public var label: String        // user-editable
    public var color: String?       // hex "#RRGGBB", nil = accent orange
    public let createdAt: Date      // per ordinamento in caso di timeMs identici
}
```

### SessionDocument.swift → v1.1.0
- Aggiunto `public var cueMarkers: [CueMarker]` con default `[]` nell'init
- Aggiunto custom `init(from decoder:)` con `decodeIfPresent` per `cueMarkers`
- Tutti gli altri campi invariati (backward compat totale)

### CueTrackView.swift [NEW] v1.0.0
Struttura:
- Header (80pt): label "CUE" + bottone "+" → onAddCue
- Content (GeometryReader): pin Canvas-drawn + label overlay interattive
- Per ogni cue visibile nel viewport:
  - Canvas: linea verticale + cerchio al top nel colore del cue (hex o accent arancio)
  - Overlay: `Text(cue.label)` con:
    - `.onTapGesture(count: 1)` → seek
    - `.onTapGesture(count: 2)` → beginEdit (inline TextField)
    - `.contextMenu` → "Delete Cue" + "Rename"
  - In editing: `TextField` con `.onSubmit` / `.onExitCommand`
- Filtro `isVisible(_:)`: mostra solo cue nel range `viewportMs`
- Color helper: `Color(hex:)` private extension

### TimelineView.swift → v2.2.0
- `CueTrackView` aggiunto in fondo al body (fuori dallo ScrollView, dopo Divider)
- Nuovi callback opzionali: `onAddCue`, `onDeleteCue`, `onSeekToCue`, `onRenameCue`
- `CueKeyPressModifier`: `ViewModifier` privato che wrappa `.onKeyPress("m")` con
  `if #available(macOS 14.0, *)` — evita errore di availability

### CueMarkerTests.swift [NEW] v1.0.0
```
✔ CueMarker init stores all fields
✔ CueMarker default color is nil
✔ CueMarker Codable round-trip preserves all fields
✔ CueMarker identifiable: unique ids for distinct markers
✔ SessionDocument with cueMarkers round-trips correctly
✔ SessionDocument without cueMarkers key decodes to empty array
```

Nota tecnica sul test backward compat: il JSON minimal hardcoded falliva per campi mancanti in `CanvasState` (`layouts`, `zoomLevel`). Soluzione: encode programmatico del documento, strip del key `cueMarkers` via `JSONSerialization`, re-decode.

## Decisioni Architetturali

**`cueMarkers` in SessionDocument, non in Timeline:** Le cue sono annotazioni utente sull'intera sessione, non legate a una specifica track o DataSource. Semanticamente corrette a livello di documento.

**`color: String?` come hex:** Evita dipendenza da SwiftUI nel modello Core. La conversione `Color(hex:)` vive nel layer UI (CueTrackView), non nel modello. Il modello rimane Foundation-only.

**`CueKeyPressModifier` come ViewModifier privato:** Isola il guard `#available(macOS 14.0, *)` in un punto solo. Pattern pulito per gestire l'availabilty di API SwiftUI recenti.

**Inline editing con TextField + onExitCommand:** `onExitCommand` (Escape) annulla l'editing senza salvare. `onSubmit` (Return) salva e chiude. Standard macOS text editing.

## Next: 8c.6 — WaveformGenerator (parallelizzabile con 8c.7, 8c.8)

---

Completed by: Claude Sonnet 4.6  
Model: claude-sonnet-4-6
