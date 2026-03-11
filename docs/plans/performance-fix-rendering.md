# Performance Fix: Rendering Pipeline Hot Path

**Data:** 2026-03-11
**Stato:** Diagnosi completata, fix in corso
**Contesto:** Primo test con dati reali (~140k campioni IMU 200Hz, sessione ~12 minuti)
**Sintomo:** UI completamente bloccata all'apertura di qualsiasi widget grafico

---

## Diagnosi

### Causa radice

Il `PlayheadController` emette `currentTimeMs` a 60fps via CVDisplayLink. Essendo un `@ObservedObject`, ogni tick invalida l'intero `body` di `RowingDeskCanvas`, che riesegue `widgetContent(for:)` per **ogni widget visibile**. Questo causa la riesecuzione della pipeline di rendering (ViewportCull → LTTB → AdaptiveSmooth) su tutti i 140k campioni, per ogni serie, 60 volte al secondo, sul main thread.

### Dettaglio per widget

#### 1. LineChartWidget / MultiLineChartWidget (CRITICO)

**File:** `Sources/RowDataStudio/Rendering/Widgets/LineChartWidget.swift`, `MultiLineChartWidget.swift`

- La `TransformPipeline.mvp()` viene creata **dentro `body`** (nel `GeometryReader`)
- Il viewport è impostato all'intera sessione (`0...sessionDurationMs`) in `RowingDeskCanvas:226`
  → `ViewportCull` non scarta nessun campione
  → LTTB riceve tutti i 140k punti ad ogni frame
- LTTB è O(n) → 140k × 6 serie × 60fps = **~50M operazioni/sec** sul main thread
- `MetricSeries` copia i `ContiguousArray<Float>` (140k elementi) ad ogni costruzione
- **Nessun caching** — risultato LTTB ricalcolato da zero ogni frame

#### 2. MetricCardWidget (ALTO)

**File:** `Sources/RowDataStudio/Rendering/Widgets/MetricCardWidget.swift`

- `sessionMean` è una computed property che itera **tutti** i 140k valori
- Chiamata ad ogni body evaluation → 140k iterazioni × 60fps = **8.4M iterazioni/sec**
- `currentIndex` usa binary search (OK), ma `sessionMean` domina

#### 3. MapWidget (ALTO)

**File:** `Sources/RowDataStudio/Rendering/Widgets/MapWidget.swift`

- `playheadIndex` usa **scansione lineare** O(n) invece di binary search
  → 140k iterazioni × 60fps = **8.4M iterazioni/sec**
- `trackOverlay` Canvas crea un nuovo `[CLLocationCoordinate2D]` da `zip(lats, lons).map{}`
  ad ogni render → 140k allocazioni × 60fps
- `meanCoordinate` usa `reduce` su 140k elementi (chiamato solo una volta, OK)

#### 4. RowingDeskCanvas.widgetContent(for:) (CRITICO)

**File:** `Sources/RowDataStudio/UI/RowingDeskCanvas.swift:223-319`

- Funzione factory chiamata nel `body` per ogni widget visibile
- Estrae array 140k da `DataContext` e li passa ai widget come nuove copie
- Ogni tick del playhead (60fps) → ricostruzione completa di tutti i widget

### Stima impatto

| Widget | Operazioni/sec (main thread) | Allocazioni/frame |
|--------|-----------------------------:|------------------:|
| LineChart (1 serie) | ~8.4M | 140k × 2 arrays |
| MultiLineChart (4 serie) | ~33.6M | 140k × 8 arrays |
| MetricCard | ~8.4M | 140k × 2 arrays |
| MapWidget | ~8.4M + 140k alloc | 140k coords |
| **Totale tipico (6 widget)** | **~60M+** | **~2M valori/frame** |

---

## Fix implementato

### Strategia: Separare aggiornamento dati da aggiornamento playhead

Il playhead che si muove a 60fps deve **solo** ridisegnare la linea rossa verticale. I dati downsampled del grafico cambiano solo quando:
- Cambiano i dati sorgente (import/switch sessione)
- Cambia il viewport (zoom/pan)
- Cambia la selezione metrica

### Modifiche

#### A. LineChartWidget / MultiLineChartWidget — Cache dei dati downsampled

**Prima:** Pipeline eseguita in `body` → ricalcolata 60×/sec
**Dopo:** Pipeline eseguita solo quando `timestamps`/`values`/`viewportMs` cambiano.
Il `body` riceve dati pre-downsampled e disegna solo il path + playhead.

Tecnica: `onChange(of: viewportMs)` trigger per ricalcolo, dati cached in `@State`.

#### B. MetricCardWidget — Cache della media sessione

**Prima:** `sessionMean` iterava 140k valori ad ogni body eval
**Dopo:** Media calcolata una volta in `onAppear` / `onChange(of: values.count)`

#### C. MapWidget — Binary search + cache coordinate

**Prima:** Scansione lineare O(n) per playheadIndex, allocazione coords ad ogni frame
**Dopo:** Binary search O(log n) per playheadIndex, coordinate track calcolate una volta

#### D. RowingDeskCanvas — Nessuna ricostruzione widget su playhead tick

Questo è il fix più architetturale e va oltre il quick-fix. Per Phase 8 si dovrà:
- Estrarre il playhead in un overlay separato che non invalida i widget sottostanti
- Oppure usare `EquatableView` per impedire re-render quando cambiano solo i dati del playhead

Per ora: il caching nei singoli widget risolve il problema immediato.

---

## Nota per Phase 8

Questo fix è **tattico** — risolve il sintomo immediato senza ristrutturare l'architettura.
La soluzione strutturale per Phase 8 dovrebbe considerare:

1. **Viewport reattivo** — Il viewport attuale è fisso a `0...duration`. Con zoom/pan del canvas,
   il viewport reale sarà una finestra mobile → ViewportCull diventerà efficace
2. **DataContext con dati pre-downsampled** — Calcolare le serie downsampled una volta nel DataContext
   e passare solo quelle ai widget (non i 140k campioni raw)
3. **Playhead come overlay globale** — Un unico layer playhead sopra tutti i widget,
   non un componente interno a ciascun widget
4. **Rendering asincrono** — Pipeline LTTB su background thread, risultato pubblicato via `@Published`
5. **Widget identity stability** — `ForEach(widgets)` con ID stabili per evitare ricostruzione completa

### File coinvolti in questo fix

| File | Tipo modifica |
|------|---------------|
| `Rendering/Widgets/LineChartWidget.swift` | Cache pipeline output |
| `Rendering/Widgets/MultiLineChartWidget.swift` | Cache pipeline output |
| `Rendering/Widgets/MetricCardWidget.swift` | Cache sessionMean |
| `Rendering/Widgets/MapWidget.swift` | Binary search + cache coords |
