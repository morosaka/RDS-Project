# Phase 8b — Canvas Interaction Overhaul (2026-03-11 → 2026-03-12)

**Status:** ⚠️ PARZIALE — 8b.1–8b.4 complete; 8b.5, 8b.6, 8b.7 non implementati

## Task Status

| Task | Descrizione | Stato |
|------|-------------|-------|
| 8b.1 | Multi-Selection | ✅ |
| 8b.2 | Implicit Z-Ordering | ✅ |
| 8b.3 | Widget Tier System | ✅ |
| 8b.4 | Focus Mode | ✅ |
| 8b.5 | Three-Layer Zoom Model | ❌ non implementato |
| 8b.6 | Magnetic Snapping | ❌ non implementato |
| 8b.7 | Keyboard Shortcuts | ⚠️ parziale (Space/F/Esc/magnify only) |

---

## Task Completati (8b.1–8b.4)

### 8b.1 — Multi-Selection

In `RowingDeskCanvas`:
- `@State private var selectedWidgetIDs: Set<UUID>` — non in sessionDocument (transient)
- Click → `selectedWidgetIDs = [id]`
- Cmd+Click → toggle membership
- Click su canvas vuoto → `selectedWidgetIDs = []` (via `.onTapGesture`)
- Bordo glow accent applicato in `WidgetContainer` via `isSelected` prop

### 8b.2 — Implicit Z-Ordering

- `@State private var nextZIndex: Int = 1` in canvas
- `handleWidgetSelection(id:)` → `widgets[idx].zIndex = nextZIndex; nextZIndex += 1`
- `zIndex` persistito in `WidgetState` (dentro `CanvasState.widgets` → SessionDocument)
- `WidgetContainer`: `.zIndex(isSelected ? 1000 : Double(state.zIndex))`

### 8b.3 — Widget Tier System

- `WidgetState.isPrimaryTier`: computed da `configuration["isPrimaryTier"]` AnyCodable Bool
- Default `true` (JSON vecchi senza il campo decodificano come primary)
- `toggleTier(id:)` in canvas: toggle Bool + ridimensionamento a `defaultSize` vs `0.5×`
- Animazione spring `RDS.Springs.tierResize`
- Header double-click → `onTierToggle()` callback → `toggleTier(id:)`
- Bordo: `widgetBorderGlow` (primary) vs `accent.opacity(0.06)` (secondary)

### 8b.4 — Focus Mode

In `RowingDeskCanvas`:
- `@State private var isFocusModeActive: Bool`
- `@State private var preFocusZoom/Pan` — snapshot pre-focus
- `toggleFocusMode()`: calcola bounding rect dei widget selezionati → `targetZoom` (fit) → `targetPan` (centra) → anima con `RDS.Springs.focusModeZoom`
- F (keyCode 3) → `toggleFocusMode()`
- Esc (keyCode 53) → exit focus o deselect
- Context menu "Focus Selection" (su multi-selezione ≥ 2 widget)
- Widget non selezionati: `opacity(focusDimOpacity = 0.3)` + `allowsHitTesting(false)`
- Viewport pre-focus ripristinato all'uscita

**Test:** `Tests/RowDataStudioTests/UI/FocusModeTests.swift` — 4+ test

---

## Architettura: RowingDeskCanvas v2.0 (Refactor critico)

Contestualmente a 8b, è stato eseguito un refactor architetturale significativo:

### Decouple zoom/pan da @Published (v2.0.0)

**Problema:** canvasZoom/canvasPan scritti su `sessionDocument` (@Published) causavano
re-eval di `body` a ogni frame di animazione → 1.25s/frame durante pan/zoom.

**Soluzione:**
- `@State private var canvasZoom/canvasPan` — animati direttamente, economici
- `@GestureState private var livePanDelta` — solo durante il drag
- `schedulePositionSave()` — debounce 500ms, scrive su sessionDocument SOLO quando il gesto finisce
- `CanvasWidgetLayer` e `CanvasGrid` estratti come struct `Equatable` privati
- `CanvasWidgetLayer.==` confronta SOLO `selectedWidgetIDs + isFocusModeActive`
  (le closure sono escluse — non confrontabili in Swift; `dataContext` gestito da `@ObservedObject`)
- `.equatable()` sul layer → nessuna re-eval durante zoom/pan animation

### PlayheadController come `let` (v1.5.0)

`let playheadController: PlayheadController` nel canvas — NOT `@ObservedObject`.
Solo i child widget (PlayheadOverlay, MultiLinePlayheadOverlay) osservano il controller.
Canvas body NON re-evalua a 60fps.

---

## Ottimizzazioni rendering (contestuali a 8b)

| Commit | Ottimizzazione |
|--------|----------------|
| `6535cc5` | Remove AnyView type erasure dai widget; child view per 60fps isolation |
| `b0e632d` | Decouple playhead observation dal canvas |
| `99c69a7` | Pipeline LineChart off main thread (@State cache, .task(id:)) |
| `bb5cf8f` | PlayheadController throttle 30fps |
| `07eedcc` | EmpowerRadar: cache averages + O(log n) stroke lookup |

---

## Bonus non pianificati (eseguiti dopo 8b.4)

### PreSmoothTransform (comb artifact fix) — commit `e81f6ec`

**Problema:** LTTB su segnale IMU 200Hz ad alto SNR produceva un "comb artifact"
(pattern a pettine) perché LTTB massimizza l'area del triangolo, preferendo picchi e valli alternati.

**Soluzione:** `PreSmoothTransform` aggiunto nella pipeline PRIMA di LTTB:
- SMA (Simple Moving Average) con window ∝ decimation ratio
- `windowSize = max(3, ceil(inputCount/targetCount) / 2)` arrotondato al dispari
- Skippato se inputCount ≤ targetCount (no downsampling necessario)
- Pipeline aggiornata: ViewportCull → **PreSmooth** → LTTB → AdaptiveSmooth

**File:** `Rendering/Transforms/PreSmoothTransform.swift` v1.0.0

### Dynamic LTTB target count — commit `e81f6ec`

- `LineChartWidget` e `MultiLineChartWidget` eliminano il parametro `targetPointCount`
- `dynamicTargetCount = max(200, Int(chartWidth))` — 1 punto per pixel
- `chartWidth` misurato via `GeometryReader` background + `.onAppear` / `.onChange`
- `pipelineKey` include `dynamicTargetCount` per invalidazione cache corretta

### Investigazione metrica widgets (2026-03-12)

- `lineChart` default → `gps_gpmf_ts_speed` (GPS puro, no fusion)
- `multiLineChart` default → `["imu_raw_ts_acc_surge"]` (surge IMU grezzo)
- `DataContext.values(for:)` aggiunto `imu_raw_ts_vel_inertial` (integrazione trapezoidale dt=5ms)
- Risultato: tracce corrette e senza artifact anomali (confermato dall'utente 2026-03-13)

---

## Task Aperti (non implementati)

### 8b.5 — Three-Layer Zoom Model ❌

Da fare:
- Pinch DENTRO un chart widget → zoom locale asse X (non tocca altri widget)
- Option+scroll → zoom locale asse Y
- Shift+pinch → zoom globale timeline (timeline decimation)
- Label asse X arancioni quando in zoom locale
- Double-click/tap dentro chart → reset a global viewport
- `@State private var localViewportMs: ClosedRange<Double>?` in LineChartDataLayer
- 4+ test su logica zoom

### 8b.6 — Magnetic Snapping ❌

Da fare:
- `snapPosition(_ pos: CGPoint, against widgets: [WidgetState]) -> CGPoint` pura
- Soglia 8pt; snap a bordi e centri degli altri widget
- Linee guida arancioni durante drag (via `@State private var snapGuides: [CGFloat]`)
- 4+ test su `snapPosition`

### 8b.7 — Keyboard Shortcuts ⚠️ PARZIALE

Implementati: Space (play/pause), F (focus), Esc (exit focus/deselect), magnify (zoom)
Mancanti:
- J/K/L shuttle (reverse/pause/forward con accelerazione)
- Left/Right → step frame (±1/fps ms)
- Shift+Left/Right → step stroke
- Delete → rimuove widget selezionati
- Cmd+0 → zoom to fit
- Cmd+L/I/T/P → toggle panels (dipende da 8d)
- Tab → hide/show all panels (dipende da 8d)
- M → add cue (placeholder, implementazione in 8c.5)

---

## Prossima priorità consigliata

Completare 8b.7 (shortcuts rimaste, indipendenti da 8d) → poi passare a 8c o 8b.5/8b.6
secondo le priorità dell'utente.

## Commits Chiave

- `190a33d` — Spatial Glassmorphism (8a.3 + 8b.1-8b.3 parziale)
- `6535cc5` — AnyView removal + playhead isolation (8b.4 perf)
- `b0e632d` — Decouple playhead
- `1c73cb5` — NSEvent monitor (Space/F/Esc/magnify)
- `bb5cf8f` — PlayheadController 30fps throttle
- `07eedcc` — EmpowerRadar cache
- `c50ed42` — Dark theme enforcement
- `e81f6ec` — PreSmoothTransform + dynamic LTTB target count
