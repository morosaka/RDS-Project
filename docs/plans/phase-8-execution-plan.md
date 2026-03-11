# Phase 8 — Piano Esecutivo: Spatial Glassmorphism UI/UX

> **Status:** Approvato — pronto per esecuzione
> **Data:** 2026-03-11
> **Prerequisiti:** Phase 0-7 complete (298 test passanti). Xcode project configurato.
> **Obiettivo:** Reimplementare l'interfaccia di RowData Studio secondo la visione "Spatial Glassmorphism" v2, mantenendo un baseline 60fps.
> **Documenti di riferimento:**
>
> - `docs/vision/UI_UX_Vision_e_Specifiche_v2.md` — Visione UI/UX completa
> - `docs/vision/design-language-details.md` — Specifiche visual (glow, spring, chromeless)
> - `CLAUDE.md` — Convenzioni progetto

---

## Convenzioni del piano

### Path aliases

| Alias | Path assoluto |
| ----- | ------------- |
| `$LIB/` | `/Volumes/WDSN770/Projects/Antigravity/RowData-Studio/Sources/RowDataStudio/` |
| `$TESTS/` | `/Volumes/WDSN770/Projects/Antigravity/RowData-Studio/Tests/RowDataStudioTests/` |
| `$XCODE/` | `/Volumes/WDSN770/Projects/Antigravity/RDS-Xcode/RowData-Studio/RowData-Studio/` |

### Complessità

| Label | Significato |
| ----- | ----------- |
| **S** | < 2 ore. Modifiche localizzate, nessuna nuova architettura. |
| **M** | 2-6 ore. Nuovo file o refactor significativo di un file esistente. |
| **L** | 6-16 ore. Nuovo sottosistema, integrazione multi-file, test estensivi. |

### Regole per tutti i task

1. **File header obbligatorio**: ogni file nuovo o modificato deve avere il docblock versionato con revision history (vedi `CONVENTIONS.md`).
2. **Test**: ogni task con `[TEST]` richiede test unitari in Swift Testing (`@Test`, `#expect`). Inserire i test in `$TESTS/` seguendo la struttura mirror.
3. **Build check**: dopo ogni task, verificare `swift build` senza warning.
4. **Commit**: un commit per task completato, message in inglese, formato convenzionale.

---

## Grafo delle dipendenze

```textx
Phase 8a (Design System)
  ├─ 8a.1 ─┬─ 8a.2
  │         ├─ 8a.3 ──── 8b.*
  │         ├─ 8a.4
  │         └─ 8a.5
  │
Phase 8b (Canvas Interaction) ← dipende da 8a.3
  ├─ 8b.1 ── 8b.2 ── 8b.3 ── 8b.4
  ├─ 8b.5 (indipendente, parallelo a 8b.1-4)
  ├─ 8b.6 (indipendente)
  └─ 8b.7 ← dipende da 8b.4 + 8d.1
  │
Phase 8c (NLE Timeline & Audio) ← dipende da 8a.1
  ├─ 8c.1 ── 8c.2 ── 8c.3 ── 8c.4 ── 8c.5
  ├─ 8c.6 (indipendente, parallelizzabile)
  ├─ 8c.8 ── 8c.7 ← dipende da 8c.6
  │
Phase 8d (Floating Panels) ← dipende da 8a.1, 8a.5
  ├─ 8d.1 ── 8d.2, 8d.3, 8d.4, 8d.5 (paralleli)
  └─ 8d.6 ← dipende da 8d.1-5
  │
Phase 8e (Export & Polish) ← dipende da 8c.1
  ├─ 8e.1, 8e.2, 8e.3 (paralleli)
  ├─ 8e.4 ← ultimo (dopo tutto il resto)
  └─ 8e.5 ← ultimo (validazione performance)
```

---

## Phase 8a — Design System Foundation

### 8a.1 — Design Tokens [NEW] [TEST]

**Complessità:** M
**Dipendenze:** Nessuna (primo task)
**File:**

- `[NEW] $LIB/UI/DesignSystem/DesignTokens.swift`
- `[NEW] $TESTS/UI/DesignTokensTests.swift`

**Cosa fare:**

Creare un namespace `enum RDS` (RowData Studio design system) con costanti immutabili per colori, tipografia, spacing e animazioni. Tutti i valori provengono da `docs/vision/UI_UX_Vision_e_Specifiche_v2.md` §7 e `design-language-details.md`.

```swift
import SwiftUI

/// RowData Studio Design System tokens.
/// Source of truth per tutti i valori visual. NON usare valori hardcoded nei widget.
public enum RDS {

    // MARK: - Colors

    public enum Colors {
        /// Canvas background. Pure black per XDR (pixel off = data emits light).
        public static let canvasBackground = Color(red: 0, green: 0, blue: 0) // #000000

        /// Widget surface. Near-opaque dark, subtle bottom-up gradient base.
        public static let widgetSurface = Color(red: 0.051, green: 0.051, blue: 0.051) // #0D0D0D
        public static let widgetSurfaceGradientTop = Color(red: 0.039, green: 0.039, blue: 0.039) // #0A0A0A
        public static let widgetSurfaceGradientBottom = Color(red: 0.078, green: 0.078, blue: 0.078) // #141414

        /// Elevated surface (widget surface with slight lift)
        public static let elevatedSurface = Color(red: 0.173, green: 0.173, blue: 0.180) // #2C2C2E

        /// Text
        public static let textPrimary = Color.white    // #FFFFFF
        public static let textSecondary = Color(red: 0.557, green: 0.557, blue: 0.576) // #8E8E93

        /// Accent — Vibrant Orange/Amber. Playhead, selections, primary actions.
        public static let accent = Color(red: 1.0, green: 0.624, blue: 0.039) // #FF9F0A

        /// Widget border glow (resting state)
        public static let widgetBorderGlow = Color(red: 1.0, green: 0.624, blue: 0.039).opacity(0.12)

        /// Widget border glow (selected state)
        public static let widgetBorderSelected = Color(red: 1.0, green: 0.624, blue: 0.039).opacity(0.5)
    }

    // MARK: - Semantic Metric Colors (IMMUTABLE — §7 vision doc)

    public enum MetricColors {
        public static let speed    = Color(red: 0.039, green: 0.518, blue: 1.0)   // #0A84FF Electric Blue
        public static let heartRate = Color(red: 1.0, green: 0.271, blue: 0.227)  // #FF453A Crimson
        public static let strokeRate = Color(red: 0.749, green: 0.353, blue: 0.949) // #BF5AF2 Purple
        public static let power    = Color(red: 0.188, green: 0.820, blue: 0.345) // #30D158 Green
        public static let gps      = Color(red: 0.392, green: 0.824, blue: 1.0)   // #64D2FF Teal
        public static let imu      = Color(red: 1.0, green: 0.839, blue: 0.039)   // #FFD60A Yellow
    }

    // MARK: - Typography

    public enum Typography {
        public static let dataValue = Font.system(.body, design: .monospaced)
        public static let dataValueSmall = Font.system(.caption, design: .monospaced)
        public static let dataValueLarge = Font.system(.title2, design: .monospaced)
        public static let uiHeader = Font.system(.headline, design: .default)
        public static let uiLabel = Font.system(.subheadline, design: .default)
        public static let widgetTitle = Font.system(.caption, design: .default).weight(.semibold)
        public static let timelineRuler = Font.system(.caption2, design: .monospaced)
    }

    // MARK: - Spring Animations (design-language-details.md §4.2)

    public enum Springs {
        public static let widgetDrag = Animation.spring(response: 0.35, dampingFraction: 0.80)
        public static let panelShowHide = Animation.spring(response: 0.40, dampingFraction: 0.90)
        public static let focusModeZoom = Animation.spring(response: 0.50, dampingFraction: 0.85)
        public static let snapToGrid = Animation.spring(response: 0.25, dampingFraction: 0.75)
        public static let valuePulse = Animation.spring(response: 0.15, dampingFraction: 1.00)
    }

    // MARK: - Layout

    public enum Layout {
        public static let widgetCornerRadius: CGFloat = 8
        public static let widgetBorderWidth: CGFloat = 0.5
        public static let snapThreshold: CGFloat = 8       // magnetic snap distance
        public static let resizeHitZone: CGFloat = 5        // invisible edge resize hit area
        public static let minWidgetWidth: CGFloat = 200
        public static let minWidgetHeight: CGFloat = 150
        public static let canvasZoomMin: Double = 0.25      // 25%
        public static let canvasZoomMax: Double = 4.0        // 400%
        public static let focusDimOpacity: Double = 0.30     // non-selected widget opacity in focus mode
    }
}
```

**Anche:** Aggiungere estensione su `StreamType` per derivare colore semantico a runtime:

```swift
extension StreamType {
    public var semanticColor: Color {
        switch self {
        case .speed:                   return RDS.MetricColors.speed
        case .hr:                      return RDS.MetricColors.heartRate
        case .cadence:                 return RDS.MetricColors.strokeRate
        case .power, .force, .work:    return RDS.MetricColors.power
        case .gps:                     return RDS.MetricColors.gps
        case .accl, .gyro, .grav, .cori: return RDS.MetricColors.imu
        case .video:                   return RDS.Colors.accent
        case .audio:                   return .white
        case .angle:                   return RDS.MetricColors.power
        case .temperature:             return RDS.MetricColors.imu
        case .fusedVelocity:           return RDS.MetricColors.speed
        case .fusedPitch, .fusedRoll:  return RDS.MetricColors.imu
        }
    }
}
```

**Acceptance criteria:**

- [x] `RDS.Colors.accent` restituisce `#FF9F0A`
- [x] `RDS.MetricColors` ha esattamente 6 colori immutabili matching vision doc §7
- [x] `RDS.Typography.dataValue` usa `.monospaced` design
- [x] `RDS.Springs` ha 5 configurazioni matching design-language-details.md §4.2
- [x] `StreamType.speed.semanticColor` restituisce `RDS.MetricColors.speed`
- [x] Test: ogni `StreamType` case ha un colore assegnato (nessun `default` catch-all)

---

### 8a.2 — GlowButton Component [NEW]

**Complessità:** S
**Dipendenze:** 8a.1
**File:**

- `[NEW] $LIB/UI/DesignSystem/GlowButton.swift`

**Cosa fare:**

Implementare il componente button chromeless da `design-language-details.md` §5.2. Nessun background, nessun bordo. Solo l'icona SF Symbol che aumenta luminanza on hover.

```swift
/// Chromeless button — no background, no border, just light.
/// Source: design-language-details.md §5.2
public struct GlowButton: View {
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    public var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(RDS.Colors.textPrimary.opacity(isHovered ? 1.0 : 0.45))
            .contentShape(Rectangle().inset(by: -8))  // larger hit area
            .onHover { isHovered = $0 }
            .onTapGesture(perform: action)
            .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
```

**Acceptance criteria:**

- [x] Nessun background o bordo visibile
- [x] Opacity 0.45 a riposo, 1.0 on hover
- [x] Hit area estesa di 8pt in ogni direzione
- [x] Animazione easeOut 150ms

---

### 8a.3 — Widget Chrome Redesign [MODIFY]

**Complessità:** L
**Dipendenze:** 8a.1, 8a.2
**File:**

- `[MODIFY] $LIB/UI/WidgetContainer.swift` → v2.0.0

**Cosa fare:**

Ridisegnare completamente `WidgetContainer` secondo vision doc §3 + design-language-details.md §1-5. Il container attuale (v1.1.0) ha background bianco, bordi grigi, header sempre visibile, e resize handle visibile. Tutto deve cambiare.

**Modifiche specifiche:**

1. **Background**: da `Color.white.opacity(0.85)` a gradiente bottom-up (`RDS.Colors.widgetSurfaceGradientTop` → `...Bottom`) con 95% opacity.

2. **Border**: da `Color.gray.opacity(0.3)` stroke a glow emissivo:

   ```swift
   RoundedRectangle(cornerRadius: RDS.Layout.widgetCornerRadius)
       .stroke(RDS.Colors.widgetBorderGlow, lineWidth: RDS.Layout.widgetBorderWidth)
       .shadow(color: RDS.Colors.accent.opacity(0.08), radius: 4)
   ```

   Quando `isSelected`: opacity border → 0.5 (da `RDS.Colors.widgetBorderSelected`).

3. **Header bar**: da "sempre visibile" a "materializza on-hover". Usare `@State private var isHovered = false` + `.onHover`. Header appare con opacity animation (0→1 in 200ms). Scompare 300ms dopo mouse exit (usare `DispatchQueue.main.asyncAfter`). Header ha sfondo gradiente semi-trasparente, non opaco.

4. **Buttons nel header**: sostituire `Button` standard con `GlowButton`. Rimuovere `.buttonStyle(.plain)` e i colori hardcoded.

5. **Resize handle**: rimuovere l'icona freccia visibile. Sostituire con hit zone invisibile su tutti e 4 i bordi + 4 angoli (`RDS.Layout.resizeHitZone` = 5pt). Il cursore cambia a resize arrow sull'approach (usare `.onContinuousHover` + `NSCursor`). Nessun elemento visuale.

6. **Shadow**: rimuovere shadow. Il glow del bordo sostituisce la shadow.

7. **Corner radius**: usare `RDS.Layout.widgetCornerRadius` (8) invece di hardcoded.

8. **Min size**: usare `RDS.Layout.minWidgetWidth/Height` (200/150) invece di hardcoded.

9. **Aggiungere callbacks:** `onSelect: () -> Void` (per click-to-front, task 8b.2) e `onTierToggle: () -> Void` (per double-click title bar, task 8b.3). Per ora i callback non fanno nulla — saranno collegati in 8b.

10. **Aggiungere** `@State private var isHovered = false` per gestire hover detection su tutto il container (non solo il header).

**NON modificare:**

- La logica di posizionamento (`livePosition`, `liveSize`) — funziona.
- I `@GestureState` per drag e resize — funzionano.
- Il parametro `content: AnyView` — l'interfaccia pubblica resta uguale.

**Acceptance criteria:**

- [x] Background scuro con gradiente (non bianco)
- [x] Bordo glow arancio (non grigio)
- [x] Header invisibile a riposo, materializza on hover, scompare dopo 300ms
- [x] Nessun resize handle visibile, ma resize funziona da bordi/angoli
- [x] Nessuna shadow, solo glow
- [x] Tutti i valori da `RDS.*` tokens, zero hardcoded
- [x] Preview funzionante

---

### 8a.4 — Canvas Background [MODIFY]

**Complessità:** S
**Dipendenze:** 8a.1
**File:**

- `[MODIFY] $LIB/UI/RowingDeskCanvas.swift`

**Cosa fare:**

Il canvas attuale ha background implicito (default macOS). Cambiare a pure black (`RDS.Colors.canvasBackground`).

Nel `body` di `RowingDeskCanvas`, aggiungere come primo layer dello `ZStack`:

```swift
RDS.Colors.canvasBackground
    .ignoresSafeArea()
```

**Futuro (non in questo task):** il background diventerà un protocollo estensibile (grid opzionale, light mode). Per Phase 8 basta il nero.

**Acceptance criteria:**

- [x] Canvas background è `#000000` (pure black)
- [x] `.ignoresSafeArea()` applicato
- [x] Nessuna griglia o pattern (solo nero)

---

### 8a.5 — Window Styling [MODIFY]

**Complessità:** S
**Dipendenze:** 8a.1
**File:**

- `[MODIFY] $XCODE/RowDataStudioApp.swift`

**Cosa fare:**

Applicare lo stile finestra immersivo. Il file attuale:

```swift
WindowGroup {
    SessionListView()
}
.commands { }
```

Diventa:

```swift
WindowGroup {
    ContentView()  // sarà cambiato a RowingDeskCanvas in 8d.3
}
.windowStyle(.hiddenTitleBar)
.commands { }
```

**Nota:** Il root view cambierà da `SessionListView` a una nuova view wrapper quando i floating panels (8d) saranno implementati. Per ora, mantenere `SessionListView` come root — il task 8d.3 lo cambierà.

**Anche:** Nell'`AppDelegate.applicationDidFinishLaunching`, configurare la finestra principale:

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.activate(ignoringOtherApps: true)
    // Set minimum window size
    if let window = NSApp.windows.first {
        window.minSize = NSSize(width: 1024, height: 768)
        window.backgroundColor = .black
    }
}
```

**Acceptance criteria:**

- [x] Title bar nascosta
- [x] Finestra minimum size 1024×768
- [x] Background finestra nero (nessun flash bianco al resize)

---

## Phase 8b — Canvas Interaction Overhaul

### 8b.1 — Multi-Selection [MODIFY]

**Complessità:** M
**Dipendenze:** 8a.3
**File:**

- `[MODIFY] $LIB/UI/RowingDeskCanvas.swift`

**Cosa fare:**

Aggiungere stato di multi-selezione al canvas. Per decisione Q1, lo stato è **transient** (UI-only, non persistito in CanvasState).

1. Aggiungere in `RowingDeskCanvas`:

   ```swift
   @State private var selectedWidgetIDs: Set<UUID> = []
   ```

2. Modificare la logica di selezione widget:
   - **Click semplice** su un widget: deseleziona tutto, seleziona solo quello. `selectedWidgetIDs = [widget.id]`
   - **Cmd+Click** su un widget: toggle selezione (aggiungi se non presente, rimuovi se presente). `selectedWidgetIDs.symmetricDifference([widget.id])`
   - **Click su canvas vuoto**: deseleziona tutto. `selectedWidgetIDs = []`

3. Passare `isSelected: selectedWidgetIDs.contains(widget.id)` a ogni `WidgetContainer`.

4. Aggiungere `onSelect` callback al `WidgetContainer` (già predisposto in 8a.3) che chiama la logica di selezione.

**Acceptance criteria:**

- [x] Click su widget → quel widget selezionato, altri deselezionati
- [x] Cmd+Click → aggiunge/rimuove dalla selezione
- [x] Click su canvas vuoto → selezione svuotata
- [x] Bordo glow accent (da 8a.3) visibile solo sui widget selezionati
- [x] `selectedWidgetIDs` è `@State` (non in CanvasState)

---

### 8b.2 — Implicit Z-Ordering [MODIFY]

**Complessità:** S
**Dipendenze:** 8b.1
**File:**

- `[MODIFY] $LIB/UI/RowingDeskCanvas.swift`

**Cosa fare:**

Implementare "last clicked widget goes to top" (vision doc §3, Overlap & Z-Ordering).

1. Mantenere un contatore `@State private var nextZIndex: Int = 1`

2. Quando un widget viene selezionato (click o cmd+click), aggiornare il suo `zIndex`:

   ```swift
   mutateCanvas { canvas in
       if let idx = canvas.widgets.firstIndex(where: { $0.id == widget.id }) {
           canvas.widgets[idx].zIndex = nextZIndex
           nextZIndex += 1
       }
   }
   ```

3. Il `WidgetContainer` già usa `.zIndex(Double(state.zIndex))` — verificare che funzioni con valori crescenti.

**Acceptance criteria:**

- [x] Cliccare un widget lo porta in primo piano (sopra gli altri)
- [x] L'ordine è stabile tra sessioni (zIndex persistito in CanvasState)
- [x] Nessun pulsante "Send to Back/Front" visibile

---

### 8b.3 — Widget Tier System [MODIFY]

**Complessità:** M
**Dipendenze:** 8b.2
**File:**

- `[MODIFY] $LIB/UI/WidgetContainer.swift`
- `[MODIFY] $LIB/Core/Models/CanvasState.swift`

**Cosa fare:**

Implementare il sistema Primary/Secondary tier (vision doc §2).

1. **In `CanvasState.swift`**: aggiungere a `WidgetState`:

   ```swift
   /// Widget tier. Primary = full-size, Secondary = compact.
   /// Stored in configuration["isPrimaryTier"] for backward compat.
   ```

   Aggiungere convenience accessor in `WidgetProtocol.swift`:

   ```swift
   extension WidgetState {
       public var isPrimaryTier: Bool {
           (configuration["isPrimaryTier"]?.value as? Bool) ?? true  // default: primary
       }
   }
   ```

2. **In `WidgetContainer.swift`**: il double-click sulla title bar (area header) toglie tra primary e secondary:
   - **Primary → Secondary**: widget animates a `defaultSize * 0.5` con `RDS.Springs.snapToGrid`
   - **Secondary → Primary**: widget animates a `defaultSize` (tipo originale) con `RDS.Springs.snapToGrid`
   - Aggiungere un `.onTapGesture(count: 2)` SOLO sull'area header. Non su tutto il widget (il double-click nel contenuto serve per local zoom reset, task 8b.5).

3. **Visual differentiation Secondary tier:**
   - Border glow leggermente più dim: `opacity(0.06)` instead of `0.12`
   - Nessun altra differenza visiva (il contenuto resta sharp e interattivo)

**Acceptance criteria:**

- [x] Double-click title bar → widget si ridimensiona a metà (secondary) o torna a full (primary)
- [x] Animazione spring `snapToGrid` (response: 0.25, damping: 0.75)
- [x] Stato tier persistito in `WidgetState.configuration["isPrimaryTier"]`
- [x] I JSON esistenti senza `isPrimaryTier` decodificano come `true` (default)
- [x] Widget in tier secondary ha glow border leggermente più dim

---

### 8b.4 — Focus Mode [MODIFY] [TEST]

**Complessità:** L
**Dipendenze:** 8b.3
**File:**

- `[MODIFY] $LIB/UI/RowingDeskCanvas.swift`
- `[MODIFY] $LIB/UI/WidgetContainer.swift`
- `[NEW] $TESTS/UI/FocusModeTests.swift`

**Cosa fare:**

Implementare Focus Mode (vision doc §2) con i due access path decisi in Q5.

1. **Stato** (transient, decisione Q1):

   ```swift
   @State private var isFocusModeActive: Bool = false
   @State private var preFocusZoomLevel: Double = 1.0
   @State private var preFocusPanOffset: CGPoint = .zero
   ```

2. **Attivazione Focus Mode:**
   - **Keyboard (F)**: se `selectedWidgetIDs.count >= 1` e focus non attivo → attiva. Se focus attivo → disattiva.
   - **Keyboard (Esc)**: se focus attivo → disattiva.
   - **Context menu**: su WidgetContainer, quando `selectedWidgetIDs.count >= 2`, mostrare item "Focus Selection". (Aggiungere `.contextMenu` al WidgetContainer).
   - **Toolbar button**: nella toolbar/sidebar del canvas, aggiungere un pulsante "Focus" (icona `viewfinder`) che si illumina quando `selectedWidgetIDs.count >= 1`. Disabilitato/grigio altrimenti.

3. **Comportamento attivazione:**
   - Salvare `preFocusZoomLevel` e `preFocusPanOffset`
   - Calcolare il bounding rect di tutti i widget in `selectedWidgetIDs`
   - Animare zoom/pan per far entrare quel bounding rect nel viewport con padding 20pt
   - Per tutti i widget NON in `selectedWidgetIDs`:
     - `.opacity(RDS.Layout.focusDimOpacity)` (0.30)
     - `.allowsHitTesting(false)` — nessuna interazione
   - Animazione: `RDS.Springs.focusModeZoom` (response: 0.5, damping: 0.85)

4. **Comportamento disattivazione:**
   - Ripristinare `preFocusZoomLevel` e `preFocusPanOffset`
   - Tutti i widget tornano a opacity 1.0 e hit-testing abilitato
   - Stessa animazione spring

5. **Keyboard handling**: usare `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` (già usato per spacebar nel canvas). Aggiungere:
   - `keyCode == 3` (F) → toggle focus
   - `keyCode == 53` (Esc) → exit focus (solo se attivo)

**Test:**

- Focus con 0 widget selezionati: non si attiva
- Focus con 2 widget: entrambi a opacity 1.0, gli altri a 0.30
- Esc esce dal focus e ripristina zoom/pan
- F toggle: attiva → disattiva → attiva

**Acceptance criteria:**

- [x] F attiva/disattiva focus sui widget selezionati
- [x] Esc esce dal focus
- [x] Widget non selezionati: opacity 30%, non interattivi
- [x] Widget selezionati: opacity 100%, viewport si adatta al loro bounding rect
- [x] Viewport pre-focus ripristinato all'uscita
- [x] Context menu "Focus Selection" su multi-selezione
- [x] Toolbar button visibile e funzionante
- [x] Animazione spring `focusModeZoom`
- [x] 4+ test

---

### 8b.5 — Three-Layer Zoom Model [MODIFY] [TEST]

**Complessità:** L
**Dipendenze:** 8a.1
**File:**

- `[MODIFY] $LIB/UI/RowingDeskCanvas.swift` — global zoom
- `[MODIFY] $LIB/Rendering/Widgets/MultiLineChartWidget.swift` — local zoom
- `[MODIFY] $LIB/Rendering/Widgets/LineChartWidget.swift` — local zoom
- `[NEW] $TESTS/Rendering/LocalZoomTests.swift`

**Cosa fare:**

Implementare il modello a 3 livelli di zoom (vision doc §6):

#### Layer 1: Canvas Zoom (già esistente — verificare)

Pinch su canvas vuoto / Cmd+scroll su canvas vuoto → scala uniforme tutti i widget. Range: 25%-400% (da `RDS.Layout.canvasZoomMin/Max`). Già implementato in RowingDeskCanvas — **verificare** che i limiti siano corretti e usino i token.

#### Layer 2: Global Temporal Zoom (timeline-driven)

Pinch/Cmd+scroll sulla timeline → cambia `viewportMs` (finestra temporale visibile). **Già implementato** in `TimelineView` con `MagnificationGesture`. Tutti i widget temporali seguono. Nessuna modifica necessaria — ma verificare che funzioni.

#### Layer 3: Local Data Zoom (widget override) — DA IMPLEMENTARE

Pinch/Cmd+scroll dentro un chart widget → quel widget **si sgancia** dal global time window e mostra il suo range temporale indipendente.

**In `MultiLineChartWidget` e `LineChartWidget`:**

1. Aggiungere stato locale:

   ```swift
   @State private var localViewportMs: ClosedRange<Double>? = nil  // nil = linked to global
   @State private var localYRange: ClosedRange<Double>? = nil       // nil = auto-fit
   ```

2. **X-zoom (temporale):** `MagnificationGesture` nel widget → quando attivato, copiare il `viewportMs` globale in `localViewportMs` e poi applicare lo zoom solo su `localViewportMs`. Il widget ora usa `localViewportMs` per rendering.

3. **Y-zoom (valori):** Scroll verticale con Option premuto (`.onContinuousHover` + NSEvent per detectare Option key) → zoom l'asse Y.

4. **Visual indicator unlinked:** quando `localViewportMs != nil`, i label dell'asse X diventano `RDS.Colors.accent` (arancio) invece del colore default. Questo segnala "questo widget mostra un range diverso".

5. **Reset + re-link:** Double-tap/double-click dentro il widget → reset `localViewportMs = nil` e `localYRange = nil`. I label tornano al colore default.

6. **Force global from widget:** Shift+pinch dentro il widget → applica il zoom al `viewportMs` globale (come se fosse sulla timeline).

**Test:**

- Pinch dentro chart: `localViewportMs` impostato, diverso dal global
- Label asse X arancioni quando unlinked
- Double-click: reset a linked (localViewportMs = nil)
- Shift+pinch: modifica viewportMs globale, non locale

**Acceptance criteria:**

- [x] Pinch dentro chart → zoom locale asse X, non tocca gli altri widget
- [x] Option+scroll → zoom locale asse Y
- [x] Label asse X arancioni quando in zoom locale
- [x] Double-click/tap dentro chart → reset a global
- [x] Shift+pinch → zoom globale (timeline)
- [x] 4+ test

---

### 8b.6 — Magnetic Snapping [MODIFY] [TEST]

**Complessità:** M
**Dipendenze:** 8a.1
**File:**

- `[MODIFY] $LIB/UI/WidgetContainer.swift`
- `[MODIFY] $LIB/UI/RowingDeskCanvas.swift`
- `[NEW] $TESTS/UI/SnapTests.swift`

**Cosa fare:**

Implementare snap magnetico tra widget (vision doc §3, Arrangement).

1. **Snap detection:** durante il drag di un widget, calcolare la distanza tra i 4 bordi + 2 centri del widget in movimento e quelli di tutti gli altri widget visibili. Se distanza < `RDS.Layout.snapThreshold` (8pt), snappare.

2. **Snap targets:** bordi (left, right, top, bottom) e centri (centerX, centerY) di ogni altro widget.

3. **Snap guides:** quando lo snap è attivo, mostrare una linea sottile (1pt, `RDS.Colors.accent.opacity(0.5)`) che collega i due bordi allineati. Stile Figma.

4. **Implementazione:** La logica di snap va in una funzione statica:

   ```swift
   static func snapPosition(
       dragging: CGRect,
       others: [CGRect],
       threshold: CGFloat
   ) -> (position: CGPoint, guides: [SnapGuide])
   ```

   Dove `SnapGuide` è `struct SnapGuide { let start: CGPoint; let end: CGPoint }`.

5. **Applicazione:** nel `.onEnded` del DragGesture di WidgetContainer, chiamare `snapPosition` e usare il risultato.

6. **Snap resist overlap:** se lo snap porterebbe due widget a sovrapporsi, non snappare (prefer edge-to-edge).

**Test:**

- Due widget allineati verticalmente con bordi a 5pt → snap a 0pt
- Due widget a 15pt → nessun snap
- Snap al centro orizzontale di un widget vicino
- Snap non causa overlap

**Acceptance criteria:**

- [x] Widget si snappano a bordi/centri di altri widget entro 8pt
- [x] Linee guida arancioni visibili durante lo snap
- [x] Snap favorisce edge-to-edge (non overlap)
- [x] 4+ test su `snapPosition`

---

### 8b.7 — Keyboard Shortcuts [MODIFY]

**Complessità:** M
**Dipendenze:** 8b.4, 8d.1
**File:**

- `[MODIFY] $XCODE/RowDataStudioApp.swift` — `.commands {}`
- `[MODIFY] $LIB/UI/RowingDeskCanvas.swift` — NSEvent monitor

**Cosa fare:**

Implementare tutti gli shortcut del vision doc §8. Due meccanismi:

**A. Menu commands** (in `$XCODE/RowDataStudioApp.swift`):

```swift
.commands {
    CommandGroup(replacing: .pasteboard) { }  // keep standard Edit menu
    CommandMenu("View") {
        Button("Zoom to Fit") { NotificationCenter.default.post(name: .zoomToFit, object: nil) }
            .keyboardShortcut("0", modifiers: .command)
        Button("Toggle Library") { NotificationCenter.default.post(name: .toggleLibrary, object: nil) }
            .keyboardShortcut("l", modifiers: .command)
        Button("Toggle Inspector") { NotificationCenter.default.post(name: .toggleInspector, object: nil) }
            .keyboardShortcut("i", modifiers: .command)
        Button("Toggle Timeline") { NotificationCenter.default.post(name: .toggleTimeline, object: nil) }
            .keyboardShortcut("t", modifiers: .command)
        Button("Toggle Widget Palette") { NotificationCenter.default.post(name: .togglePalette, object: nil) }
            .keyboardShortcut("p", modifiers: .command)
    }
    CommandMenu("Session") {
        Button("Duplicate Widget") { NotificationCenter.default.post(name: .duplicateWidget, object: nil) }
            .keyboardShortcut("d", modifiers: .command)
    }
}
```

**B. NSEvent monitor per chiavi non-command** (in `RowingDeskCanvas`):
Il canvas ha già un `NSEvent.addLocalMonitorForEvents(matching: .keyDown)`. Estendere:

| Key | keyCode | Azione |
| --- | ------- | ------ |
| Space | 49 | PlayheadController play/pause (già fatto) |
| F | 3 | Toggle Focus Mode (da 8b.4) |
| Esc | 53 | Exit Focus / deselect all |
| M | 46 | Add cue at playhead (8c.5, placeholder per ora) |
| Tab | 48 | Hide/show all panels (8d.6) |
| Delete | 51 | Delete selected widget(s) |
| J | 38 | Reverse playback (rate = -1, -2, -4) |
| K | 40 | Pause |
| L | 37 | Forward playback (rate = 1, 2, 4) |
| Left | 123 | Step -1 frame (seek -33ms) |
| Right | 124 | Step +1 frame (seek +33ms) |
| Shift+Left | 123 + shift | Step to prev stroke boundary |
| Shift+Right | 124 + shift | Step to next stroke boundary |

**J/K/L shuttle logic:**

- Primo press L: rate 1x. Secondo press L (entro 500ms): rate 2x. Terzo: rate 4x.
- J funziona uguale ma con rate negativo.
- K sempre pause (rate 0).
- Usare `@State private var lastShuttlePress: Date?` e `@State private var shuttleRate: Double = 1.0`.

**Acceptance criteria:**

- [x] Space → play/pause
- [x] J/K/L → shuttle reverse/pause/forward con accelerazione
- [x] Left/Right → step frame
- [x] Shift+Left/Right → step stroke (se strokes disponibili, altrimenti no-op)
- [x] F → toggle focus
- [x] Esc → exit focus o deselect
- [x] Delete → rimuove widget selezionati
- [x] Cmd+0 → zoom to fit
- [x] Cmd+L/I/T/P → toggle panels (collegamento in 8d.6)
- [x] Tab → hide/show panels (collegamento in 8d.6)
- [x] M → add cue (placeholder, implementazione in 8c.5)

---

## Phase 8c — NLE Timeline & Audio

### 8c.1 — TimelineTrack Model [MODIFY] [TEST]

**Complessità:** M
**Dipendenze:** 8a.1
**File:**

- `[MODIFY] $LIB/Core/Models/TrackReference.swift` → rinominare a `TimelineTrack.swift`
- `[MODIFY] $LIB/Core/Models/SessionDocument.swift` — update type reference
- `[NEW] $TESTS/Core/TimelineTrackTests.swift`

**Cosa fare:**

Evolvere `TrackReference` → `TimelineTrack` con i campi NLE (decisione Q3).

1. **Rinominare** il file `TrackReference.swift` → `TimelineTrack.swift`.

2. **Rinominare** la struct `TrackReference` → `TimelineTrack`. Mantenere le stesse `CodingKeys` per backward compat (decisione Q3, migrazione a+b):

   ```swift
   public struct TimelineTrack: Codable, Sendable, Hashable, Identifiable {
       // === Existing fields (unchanged) ===
       public let id: UUID
       public let sourceID: UUID
       public let stream: StreamType
       public var offset: TimeInterval
       public var displayName: String?

       // === New: NLE behavior ===
       /// Widget that created this track. nil if manually pinned or orphaned.
       public var linkedWidgetID: UUID?

       /// Metric key for sparkline rendering (e.g. "fus_cal_ts_vel_inertial").
       public var metricID: String?

       /// Pinned tracks persist even when their linked widget is removed.
       public var isPinned: Bool

       /// Visibility toggle (hide sparkline without removing track).
       public var isVisible: Bool

       /// Audio mute state (only meaningful for .audio stream type).
       public var isMuted: Bool

       /// Audio solo state (only meaningful for .audio stream type).
       public var isSolo: Bool
   }
   ```

   **Nota:** nessun `orderIndex` — l'ordine è determinato dalla posizione nell'array `Timeline.tracks` (decisione Q3.4).

3. **Default values** per tutti i nuovi campi nell'`init`:

   ```swift
   linkedWidgetID: UUID? = nil,
   metricID: String? = nil,
   isPinned: Bool = false,
   isVisible: Bool = true,
   isMuted: Bool = false,
   isSolo: Bool = false
   ```

   Questo garantisce che i JSON esistenti (senza questi campi) decodificano correttamente con i default.

4. **Aggiungere custom `init(from decoder:)`** per gestire i campi mancanti nei JSON vecchi:

   ```swift
   public init(from decoder: Decoder) throws {
       let container = try decoder.container(keyedBy: CodingKeys.self)
       id = try container.decode(UUID.self, forKey: .id)
       sourceID = try container.decode(UUID.self, forKey: .sourceID)
       stream = try container.decode(StreamType.self, forKey: .stream)
       offset = try container.decode(TimeInterval.self, forKey: .offset)
       displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
       // New fields with defaults for backward compat
       linkedWidgetID = try container.decodeIfPresent(UUID.self, forKey: .linkedWidgetID)
       metricID = try container.decodeIfPresent(String.self, forKey: .metricID)
       isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
       isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
       isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
       isSolo = try container.decodeIfPresent(Bool.self, forKey: .isSolo) ?? false
   }
   ```

5. **In `SessionDocument.swift`**: `Timeline.tracks` type cambia da `[TrackReference]` a `[TimelineTrack]`. Cerca e sostituisci in tutto il progetto.

6. **Aggiungere `StreamType.audio`** se non già presente (verificare — è già nell'enum).

**Test:**

- Decodifica JSON vecchio (senza nuovi campi) → default corretti
- Encode/decode round-trip con tutti i campi
- `isPinned = false` di default
- `isVisible = true` di default

**Acceptance criteria:**

- [x] `TrackReference` rinominato a `TimelineTrack` ovunque
- [x] 6 nuovi campi con default
- [x] JSON backward compatible (vecchi file si aprono senza errori)
- [x] `SessionDocument.timeline.tracks` è `[TimelineTrack]`
- [x] Build clean, zero warning
- [x] 4+ test

---

### 8c.2 — Widget ↔ Track Lifecycle [MODIFY] [TEST]

**Complessità:** M
**Dipendenze:** 8c.1
**File:**

- `[MODIFY] $LIB/UI/RowingDeskCanvas.swift`
- `[NEW] $TESTS/UI/TrackLifecycleTests.swift`

**Cosa fare:**

Implementare il binding bidirezionale widget↔track (decisione Q3.2: `mutateCanvas` → `mutateSession`).

1. **Rinominare** `mutateCanvas` → `mutateSession` in `RowingDeskCanvas`. Il nuovo metodo muta sia `canvas` che `timeline.tracks`.

2. **Quando un widget viene aggiunto al canvas:**
   - Determinare quante track servono in base al tipo:
     - `.video` → 1 track (stream: `.video`)
     - `.audio` → 1 track (stream: `.audio`)
     - `.lineChart` → 1 track per metricID
     - `.multiLineChart` → N track, una per metricID in `state.metricIDs`
     - `.strokeTable` → 1 track per metrica visualizzata
     - `.map` → 1 track (stream: `.gps`)
     - `.empowerRadar` → 0 track (derivato per-stroke, vision doc §4)
     - `.metricCard` → 0 track (derivato KPI, vision doc §4)
   - Creare `TimelineTrack` con `linkedWidgetID = widget.id`
   - Appendere a `sessionDocument.timeline.tracks`

3. **Quando un widget viene rimosso dal canvas:**

   ```swift
   sessionDocument.timeline.tracks.removeAll {
       $0.linkedWidgetID == widgetID && !$0.isPinned
   }
   ```

   Le track pinned sopravvivono alla rimozione del widget.

4. **Utility function** per determinare il `StreamType` da un `metricID`:

   ```swift
   static func streamType(for metricID: String) -> StreamType {
       // Parse metric family prefix
       if metricID.hasPrefix("gps_") { return .gps }
       if metricID.hasPrefix("imu_") && metricID.contains("acc") { return .accl }
       // ... etc.
   }
   ```

**Test:**

- Aggiungere MultiLineChart con 3 metriche → 3 track create
- Rimuovere widget → track rimosse
- Rimuovere widget con track pinned → track pinned sopravvive
- Aggiungere MetricCard → 0 track create

**Acceptance criteria:**

- [x] `mutateCanvas` rinominato a `mutateSession`
- [x] Aggiunta widget → track automatiche in timeline
- [x] Rimozione widget → track non-pinned rimosse
- [x] Track pinned sopravvivono alla rimozione widget
- [x] Radar e MetricCard non creano track
- [x] 4+ test

---

### 8c.3 — Timeline Track Rendering [MODIFY]

**Complessità:** L
**Dipendenze:** 8c.2
**File:**

- `[MODIFY] $LIB/UI/Timeline/TimelineTrack.swift` → v2.0.0
- `[MODIFY] $LIB/UI/Timeline/TimelineView.swift` → v2.0.0

**Cosa fare:**

Ridisegnare il rendering delle track per il modello NLE (vision doc §4).

**TimelineTrack.swift v2.0.0:**

1. Il componente ora riceve un `TimelineTrack` model (non più parametri sciolti):

   ```swift
   public struct TimelineTrackRow: View {
       let track: TimelineTrack
       let viewportMs: ClosedRange<Double>
       let sessionDurationMs: Double
       let sparklineData: ContiguousArray<Float>?  // from DataContext
       let onPin: () -> Void
       let onMute: () -> Void
       let onToggleVisibility: () -> Void
   }
   ```

2. **Track header (colonna sinistra, 80pt):**
   - Cerchio colore semantico (10pt) derivato da `track.stream.semanticColor`
   - Nome metrica (truncated) dal `track.displayName ?? track.stream.rawValue`
   - Icona tipo (da `track.stream`)
   - Pin icon (toggle `isPinned`): `pin.fill` se pinned, `pin` se no
   - Per track audio: mute icon (`speaker.slash` / `speaker.wave.2`)
   - Eye icon (toggle `isVisible`)

3. **Track content (area destra):**
   - Se `.video`: barra a scacchiera (pattern esistente), colore dal semantic color
   - Se `.audio`: mini waveform (da sparklineData, se disponibile; altrimenti barra solid)
   - Se qualsiasi metrica con sparklineData: **sparkline** Canvas-rendered (linea sottile nel colore semantico, altezza 24pt, fill sotto la linea con opacity 0.15)
   - Se `!track.isVisible`: barra dimmed (opacity 0.1)

4. **Stile dark:** background track `RDS.Colors.canvasBackground`, nessun separatore tra righe (solo spacing 2pt).

**TimelineView.swift v2.0.0:**

1. Cambiare iterazione da `doc.sources` → `doc.timeline.tracks`:

   ```swift
   ForEach(sessionDocument.timeline.tracks) { track in
       TimelineTrackRow(track: track, ...)
   }
   ```

2. **Drag to reorder:** aggiungere `.onMove` al ForEach per permettere riordinamento track. Il riordinamento muta l'array `timeline.tracks` (decisione Q3.4: ordine = posizione array).

3. **Playhead line**: mantenere il rendering attuale (linea rossa verticale), ma cambiare colore a `RDS.Colors.accent` (arancio) e aggiungere glow:

   ```swift
   Rectangle()
       .fill(RDS.Colors.accent)
       .frame(width: 1)
       .shadow(color: RDS.Colors.accent.opacity(0.4), radius: 6)
   ```

**Acceptance criteria:**

- [x] Track rendering basato su `TimelineTrack` model, non su `DataSource`
- [x] Header con color dot semantico + nome + pin/mute/eye icons
- [x] Sparklines per track metriche (quando dati disponibili)
- [x] Drag to reorder funzionante
- [x] Playhead arancio con glow
- [x] Stile dark coerente con design system

---

### 8c.4 — Track Interactions [MODIFY]

**Complessità:** M
**Dipendenze:** 8c.3
**File:**

- `[MODIFY] $LIB/UI/Timeline/TimelineView.swift`
- `[MODIFY] $LIB/UI/Timeline/TimelineTrack.swift`

**Cosa fare:**

1. **Pin toggle:** click sull'icona pin → `mutateSession { $0.timeline.tracks[idx].isPinned.toggle() }`
2. **Mute toggle:** click sull'icona speaker (solo track audio) → `mutateSession { $0.timeline.tracks[idx].isMuted.toggle() }`
3. **Solo:** click con Option premuto sull'icona speaker → solo questa track audio (mute tutte le altre audio track, unmute questa).
4. **Visibility toggle:** click sull'icona eye → `mutateSession { $0.timeline.tracks[idx].isVisible.toggle() }`
5. **Track offset drag:** drag orizzontale sulla barra di una track → modifica `track.offset`. Questo è il meccanismo di sync visivo multi-camera. Mostrare il valore offset in ms durante il drag.

**Acceptance criteria:**

- [x] Pin/unpin funzionante con icona che cambia
- [x] Mute/unmute per track audio
- [x] Solo: mute tutte le altre audio, unmute questa
- [x] Eye toggle nasconde/mostra sparkline
- [x] Drag orizzontale modifica offset con feedback visivo

---

### 8c.5 — Cue/Bookmark Track [NEW] [TEST]

**Complessità:** M
**Dipendenze:** 8c.3
**File:**

- `[NEW] $LIB/Core/Models/CueMarker.swift`
- `[MODIFY] $LIB/UI/Timeline/TimelineView.swift`
- `[NEW] $LIB/UI/Timeline/CueTrackView.swift`
- `[NEW] $TESTS/Core/CueMarkerTests.swift`

**Cosa fare:**

Implementare la track cue/bookmark (vision doc §4, Cue/Bookmark Track).

1. **Modello** `CueMarker`:

   ```swift
   public struct CueMarker: Codable, Sendable, Hashable, Identifiable {
       public let id: UUID
       public var timeMs: Double       // position on timeline
       public var label: String        // user-editable text
       public var color: String?       // optional color override (hex)
       public let createdAt: Date
   }
   ```

2. **Aggiungere a `SessionDocument`:**

   ```swift
   public var cueMarkers: [CueMarker]
   ```

   Con default `[]` nell'init e `decodeIfPresent` nel decoder.

3. **CueTrackView:** una riga in fondo alla timeline con:
   - Pulsante "+" per aggiungere cue alla posizione playhead corrente
   - Ogni cue: un pin verticale (linea + pallino) con label text sotto
   - Click su un cue: seek playhead a quella posizione
   - Double-click su label: editing inline (TextField)
   - Delete cue: right-click → "Delete Cue"

4. **Shortcut M:** già predisposto in 8b.7. Collegare: `M` → crea `CueMarker(timeMs: playheadController.currentTimeMs, label: "Cue \(cueMarkers.count + 1)")`.

**Test:**

- Aggiungere cue → appare nella timeline alla posizione corretta
- Click cue → playhead seek
- Encode/decode round-trip di CueMarker
- CueMarkers aggiunti a SessionDocument con backward compat

**Acceptance criteria:**

- [x] Cue track visibile in fondo alla timeline
- [x] M aggiunge cue alla posizione playhead
- [x] Click su cue → seek
- [x] Label editabili inline
- [x] Cue persistiti in SessionDocument
- [x] 4+ test

---

### 8c.6 — WaveformGenerator [NEW] [TEST]

**Complessità:** L
**Dipendenze:** Nessuna (parallelizzabile con 8c.1-5)
**File:**

- `[NEW] $LIB/Core/Persistence/WaveformGenerator.swift`
- `[NEW] $LIB/Core/Models/WaveformPeaks.swift`
- `[NEW] $TESTS/Core/WaveformGeneratorTests.swift`

**Cosa fare:**

Implementare il generatore di peak envelope multi-risoluzione (decisione Q2).

1. **Modello** `WaveformPeaks`:

   ```swift
   /// Multi-resolution peak envelope for audio waveform rendering.
   public struct WaveformPeaks: Codable, Sendable {
       /// Source audio sample rate (Hz)
       public let sampleRate: Int

       /// Total number of audio samples
       public let totalSamples: Int

       /// Peak pyramid. levels[0] = finest (256 samples/bin), levels[4] = coarsest (65536 samples/bin).
       /// Each level is an array of min/max pairs.
       public let levels: [[PeakPair]]

       /// Samples per bin for each level.
       public static let samplesPerBin: [Int] = [256, 1024, 4096, 16384, 65536]
   }

   public struct PeakPair: Codable, Sendable, Hashable {
       public let min: Float
       public let max: Float
   }
   ```

2. **WaveformGenerator** (pattern mirror di `SidecarGenerator`):

   ```swift
   public struct WaveformGenerator {
       /// Generate peak envelope from video file audio track.
       /// Runs on background thread. Returns path to .waveform.gz sidecar.
       public static func generate(from videoURL: URL, outputDir: URL) async throws -> URL
   }
   ```

3. **Pipeline interna:**
   - `AVAsset(url:)` → `load(.tracks)` → primo track con `mediaType: .audio`
   - `AVAssetReaderTrackOutput` con settings: mono Float32, 48kHz (o sample rate nativo)
   - Loop `copyNextSampleBuffer()` su background thread → accumulare in `ContiguousArray<Float>`
   - Calcolare Level 0 (256 samples/bin) con `vDSP_minv` + `vDSP_maxv` per ogni blocco
   - Derivare Level 1-4 da Level 0: per ogni 4 bin consecutivi al livello N, il bin al livello N+1 è `(min dei 4 min, max dei 4 max)`
   - Encode `WaveformPeaks` come JSON → gzip → salvare come `.waveform.gz`

4. **Naming convention:** `GX030230.waveform.gz` (accanto a `.telemetry.gz`).

5. **Integrazione import:** in `FileImportHelper`, dopo la generazione del sidecar GPMF, lanciare `WaveformGenerator.generate` in parallelo (stesso `Task.detached`).

6. **Level selection at render time** (utility function):

   ```swift
   extension WaveformPeaks {
       /// Select the optimal pyramid level for the given viewport.
       /// Returns the level index and the slice of PeakPairs visible.
       public func peaksForViewport(
           viewportMs: ClosedRange<Double>,
           widthPixels: Int
       ) -> (levelIndex: Int, peaks: ArraySlice<PeakPair>)
   }
   ```

**Test:**

- Generare peaks da un buffer Float32 sintetico (no file reale)
- Level 0: 256 samples/bin → corretto numero di bin
- Level derivation: level 1 min = min dei 4 min di level 0
- `peaksForViewport`: seleziona il livello corretto per diverse zoom
- PeakPair encode/decode

**Acceptance criteria:**

- [x] Genera piramide a 5 livelli da audio Float32
- [x] vDSP usato per min/max (non loop manuale)
- [x] Output: `.waveform.gz` (gzipped JSON)
- [x] `peaksForViewport` seleziona livello ottimale
- [x] Integrato in pipeline di import (parallelo a sidecar GPMF)
- [x] 5+ test

---

### 8c.7 — AudioTrackWidget [NEW]

**Complessità:** L
**Dipendenze:** 8c.6, 8c.8
**File:**

- `[NEW] $LIB/Rendering/Widgets/AudioTrackWidget.swift`
- `[MODIFY] $LIB/Rendering/Widgets/WidgetProtocol.swift` — aggiungere `case audio`
- `[MODIFY] $LIB/UI/RowingDeskCanvas.swift` — aggiungere routing `.audio`

**Cosa fare:**

1. **WidgetType:** aggiungere case `.audio` con:
   - `displayName: "Audio Track"`
   - `icon: "waveform"`
   - `defaultSize: CGSize(width: 480, height: 100)`

2. **AudioTrackWidget:**

   ```swift
   public struct AudioTrackWidget: View {
       let state: WidgetState
       @ObservedObject var dataContext: DataContext
       @ObservedObject var playheadController: PlayheadController

       @State private var waveformPeaks: WaveformPeaks?
       @State private var volume: Float = 1.0
       @State private var isMuted: Bool = false
   }
   ```

3. **Rendering waveform** con SwiftUI Canvas:
   - Caricare `WaveformPeaks` dal sidecar `.waveform.gz` in `.task`
   - Usare `peaksForViewport(viewportMs:widthPixels:)` per ottenere i bin visibili
   - Per ogni colonna pixel: disegnare una linea verticale da `yCenter + peak.max * halfHeight` a `yCenter + peak.min * halfHeight`
   - Colore: bianco con opacity 0.8
   - Glow pass: stessa linea con `lineWidth: 3, opacity: 0.15` (design-language-details.md §1)

4. **Playhead cursor:** linea verticale accent color alla posizione corrente.

5. **Controls (on hover, come tutti i widget da 8a.3):**
   - Volume slider (orizzontale, piccolo)
   - Mute toggle button (GlowButton con `speaker.slash` / `speaker.wave.2`)

6. **Sync con PlayheadController:** il widget non riproduce audio direttamente. La riproduzione audio è gestita dal `VideoSyncController` dell'AVPlayer associato (che ora è muted sul video ma ancora decodifica audio). **Nota:** per Phase 8, l'audio playback reale richiede un `AVAudioPlayerNode` separato. Per ora, il widget è SOLO visualizzazione waveform + controlli volume/mute che modificano lo stato in `DataContext`. La riproduzione audio effettiva è post-MVP.

7. **In `RowingDeskCanvas.widgetContent()`:** aggiungere case `.audio`.

**Acceptance criteria:**

- [x] Waveform renderizzata da peak pyramid (non raw samples)
- [x] Zoom: waveform si adatta al viewport temporale
- [x] Playhead cursor sincronizzato
- [x] Volume slider e mute button funzionanti (stato UI)
- [x] `.audio` case in WidgetType con icona e default size
- [x] Widget instanziabile da widget palette

---

### 8c.8 — VideoWidget Audio Stripping [MODIFY]

**Complessità:** S
**Dipendenze:** Nessuna (parallelizzabile, ma prima di 8c.7 logicamente)
**File:**

- `[MODIFY] $LIB/Rendering/Widgets/VideoWidget.swift`

**Cosa fare:**

Il `VideoWidget` attuale usa `AVPlayer` che riproduce audio di default. Per la separazione video/audio (vision doc §3):

1. Aggiungere nel `.task` dove l'AVPlayer viene creato:

   ```swift
   player.isMuted = true
   ```

2. Rimuovere qualsiasi controllo volume dal VideoWidget (non ne ha di espliciti, ma verificare).

3. Aggiornare il header/title del widget per dire "Video" senza riferimenti audio.

4. **Styling:** applicare il nuovo material (`RDS.Colors.widgetSurface` background) e rimuovere chrome pesante (se presente).

**Acceptance criteria:**

- [x] AVPlayer muted di default
- [x] Nessun controllo audio nel VideoWidget
- [x] Build clean

---

## Phase 8d — Floating Panels (NSPanel)

### 8d.1 — NSPanel Infrastructure [NEW]

**Complessità:** L
**Dipendenze:** 8a.1, 8a.5
**File:**

- `[NEW] $LIB/UI/Panels/FloatingPanel.swift` — NSPanel subclass
- `[NEW] $LIB/UI/Panels/PanelManager.swift` — lifecycle manager
- `[NEW] $LIB/UI/Panels/PanelHostingView.swift` — SwiftUI bridge

**Cosa fare:**

Creare l'infrastruttura NSPanel (decisione Q4). Questa è la fondazione per tutti i panels.

1. **FloatingPanel** (NSPanel subclass):

   ```swift
   /// Custom NSPanel for floating tool panels.
   /// Stays above the main canvas window. Does not steal key focus.
   public class FloatingPanel: NSPanel {
       init(contentRect: NSRect, title: String) {
           super.init(
               contentRect: contentRect,
               styleMask: [.titled, .closable, .resizable, .utilityWindow,
                           .nonactivatingPanel],
               backing: .buffered,
               defer: true
           )
           self.title = title
           self.isFloatingPanel = true
           self.level = .floating
           self.becomesKeyOnlyIfNeeded = true
           self.isMovableByWindowBackground = true
           self.titleVisibility = .hidden
           self.titlebarAppearsTransparent = true
           self.backgroundColor = .clear
           // Auto-save position to UserDefaults
           self.setFrameAutosaveName("RDS_Panel_\(title)")
       }
   }
   ```

2. **PanelHostingView** — wrapper per hostare SwiftUI content in NSPanel:

   ```swift
   /// Hosts a SwiftUI view inside a FloatingPanel.
   public class PanelHostingView<Content: View>: NSHostingController<Content> {
       // Passa DataContext e PlayheadController via @ObservedObject nella content view
   }
   ```

3. **PanelManager** — singleton che gestisce il lifecycle di tutti i panels:

   ```swift
   @MainActor
   public class PanelManager: ObservableObject {
       public static let shared = PanelManager()

       @Published public var isTimelineVisible = true
       @Published public var isInspectorVisible = false
       @Published public var isLibraryVisible = false
       @Published public var isPaletteVisible = false

       private var timelinePanel: FloatingPanel?
       private var inspectorPanel: FloatingPanel?
       private var libraryPanel: FloatingPanel?
       private var palettePanel: FloatingPanel?

       /// Show/hide a panel with animation
       public func togglePanel(_ panel: PanelKind) { ... }

       /// Hide all panels (Tab shortcut)
       public func hideAll() {
           [timelinePanel, inspectorPanel, libraryPanel, palettePanel]
               .compactMap { $0 }
               .forEach { $0.orderOut(nil) }
       }

       /// Show all panels that were visible before hideAll
       public func showAll() { ... }

       /// Reset all panels to default positions (Cmd+Shift+0)
       public func resetLayout() { ... }

       public enum PanelKind {
           case timeline, inspector, library, palette
       }
   }
   ```

4. **Integrazione con AppDelegate:** in `applicationDidFinishLaunching`, creare i panels:

   ```swift
   PanelManager.shared.setup(
       dataContext: dataContext,
       playheadController: playheadController
   )
   ```

**Acceptance criteria:**

- [x] `FloatingPanel` non ruba focus tastiera dal canvas
- [x] Panels flottano sopra la finestra principale
- [x] Posizione auto-salvata in UserDefaults via `setFrameAutosaveName`
- [x] `PanelManager.hideAll()` nasconde tutti i panels
- [x] `PanelManager.showAll()` li ripristina
- [x] `PanelManager.resetLayout()` ripristina posizioni default
- [x] Panels appaiono correttamente in Mission Control

---

### 8d.2 — Timeline Panel [MODIFY]

**Complessità:** M
**Dipendenze:** 8d.1, 8c.3
**File:**

- `[NEW] $LIB/UI/Panels/TimelinePanelContent.swift`
- `[MODIFY] $LIB/UI/Panels/PanelManager.swift`

**Cosa fare:**

Migrare la `TimelineView` attuale in un NSPanel flottante.

1. Creare `TimelinePanelContent`: una SwiftUI view che wrappa `TimelineView` con:
   - Background `ultraThinMaterial` (vision doc §1)
   - Posizione default: bottom, full width (`Cmd+T` toggle)

2. In `PanelManager.setup()`: creare il timeline panel:

   ```swift
   let content = TimelinePanelContent(
       playheadController: playheadController,
       dataContext: dataContext
   )
   timelinePanel = FloatingPanel(
       contentRect: NSRect(x: 0, y: 0, width: 800, height: 200),
       title: "Timeline"
   )
   timelinePanel?.contentViewController = NSHostingController(rootView: content)
   ```

3. Posizione default: ancorato al bottom della finestra principale, larghezza = finestra.

**Acceptance criteria:**

- [x] Timeline vive in un NSPanel flottante
- [x] Background `ultraThinMaterial`
- [x] Cmd+T toggle visibilità
- [x] Gesture sulla timeline non interferiscono con il canvas

---

### 8d.3 — Library HUD Panel [MODIFY]

**Complessità:** M
**Dipendenze:** 8d.1
**File:**

- `[NEW] $LIB/UI/Panels/LibraryPanelContent.swift`
- `[MODIFY] $LIB/UI/Panels/PanelManager.swift`
- `[MODIFY] $XCODE/RowDataStudioApp.swift` — cambiare root view

**Cosa fare:**

Migrare `SessionListView` da root view a floating Library HUD.

1. Creare `LibraryPanelContent`: wrappa `SessionListView` con:
   - Background `ultraThinMaterial`
   - Posizione default: center overlay (dimensione ~400×600)
   - Auto-dismiss opzionale dopo selezione sessione

2. **Cambiare root view** in `$XCODE/RowDataStudioApp.swift`:

   ```swift
   WindowGroup {
       RowingDeskCanvas()  // oppure un RootView wrapper
           .environmentObject(dataContext)
           .environmentObject(playheadController)
           .environmentObject(PanelManager.shared)
   }
   .windowStyle(.hiddenTitleBar)
   ```

3. Il canvas è ora il root. La Library è un panel che appare con `Cmd+L`.

**Acceptance criteria:**

- [x] Root view = RowingDeskCanvas (non SessionListView)
- [x] Library accessibile via Cmd+L
- [x] Selezione sessione carica nel canvas
- [x] Library può auto-dismiss post-selezione

---

### 8d.4 — Inspector Panel [NEW]

**Complessità:** M
**Dipendenze:** 8d.1
**File:**

- `[NEW] $LIB/UI/Panels/InspectorPanelContent.swift`
- `[MODIFY] $LIB/UI/Panels/PanelManager.swift`

**Cosa fare:**

L'inspector mostra i dettagli del widget selezionato.

1. **Content:** quando `selectedWidgetIDs.count == 1`:
   - Widget type + title
   - Position (x, y) editabili
   - Size (w, h) editabili
   - Metric IDs (per chart)
   - Source ID (per video)
   - Tier toggle (primary/secondary)

   Quando `selectedWidgetIDs.count == 0`: "No selection"
   Quando `selectedWidgetIDs.count > 1`: "N widgets selected" + azioni batch (align, distribute)

2. Posizione default: right edge, Cmd+I toggle.

3. Background `ultraThinMaterial`.

**Acceptance criteria:**

- [x] Mostra dettagli widget selezionato
- [x] Campi editabili aggiornano WidgetState
- [x] Cmd+I toggle
- [x] "No selection" quando nessun widget selezionato

---

### 8d.5 — Widget Palette Panel [NEW]

**Complessità:** M
**Dipendenze:** 8d.1
**File:**

- `[NEW] $LIB/UI/Panels/PalettePanelContent.swift`
- `[MODIFY] $LIB/UI/Panels/PanelManager.swift`

**Cosa fare:**

Il widget palette permette di aggiungere nuovi widget al canvas.

1. **Content:** lista di tutti i `WidgetType.allCases` con:
   - Icona (da `type.icon`)
   - Nome (da `type.displayName`)
   - Click → aggiunge widget al centro del viewport corrente

2. **Suggested widgets:** se la sessione ha dati Empower, evidenziare il Radar. Se ha video, evidenziare Audio Track (vision doc §3).

3. Posizione default: left edge, Cmd+P toggle.

4. Background `ultraThinMaterial`.

**Acceptance criteria:**

- [x] Lista tutti i WidgetType disponibili
- [x] Click su tipo → widget aggiunto al canvas
- [x] Widget suggeriti evidenziati in base ai dati sessione
- [x] Cmd+P toggle

---

### 8d.6 — Panel Controls [MODIFY]

**Complessità:** M
**Dipendenze:** 8d.2, 8d.3, 8d.4, 8d.5
**File:**

- `[MODIFY] $LIB/UI/Panels/PanelManager.swift`
- `[MODIFY] $LIB/UI/RowingDeskCanvas.swift`
- `[MODIFY] $XCODE/RowDataStudioApp.swift`

**Cosa fare:**

Collegare tutti i controlli panels.

1. **Tab hide/show all:** nel NSEvent monitor del canvas (8b.7), keyCode 48 (Tab):

   ```swift
   if PanelManager.shared.anyPanelVisible {
       PanelManager.shared.hideAll()
   } else {
       PanelManager.shared.showAll()
   }
   ```

2. **Cmd+Shift+0 reset layout:** aggiungere nei `.commands` di RowDataStudioApp:

   ```swift
   Button("Reset Panel Layout") {
       PanelManager.shared.resetLayout()
   }
   .keyboardShortcut("0", modifiers: [.command, .shift])
   ```

3. **Minimize to pill:** (vision doc §5, Panel Behavior)
   - Quando l'utente clicca il close button del panel (intercettare via `windowShouldClose` delegate):
     - Non chiudere — nascondere (`orderOut`) e mostrare un pill.
     - Il pill è un piccolo `NSPanel` (40×24pt) ancorato al bordo finestra più vicino, con icona + nome abbreviato.
     - Click sul pill → `orderFront` il panel.
   - **Alternativa più semplice per Phase 8:** non implementare il pill. Il close button nasconde il panel, riattivabile via shortcut (Cmd+T/I/L/P). Il pill è un'enhancement post-Phase 8.

4. **Collegare shortcut** Cmd+T/I/L/P ai `PanelManager.togglePanel()` corrispondenti (via i menu commands in 8b.7).

**Acceptance criteria:**

- [x] Tab nasconde/mostra tutti i panels
- [x] Cmd+Shift+0 ripristina posizioni default
- [x] Cmd+T/I/L/P toggle singoli panels
- [x] Close button nasconde (non distrugge) il panel

---

## Phase 8e — Export & Finalization

### 8e.1 — ExportService: MP4 Trim [NEW] [TEST]

**Complessità:** L
**Dipendenze:** 8c.1
**File:**

- `[NEW] $LIB/Core/Services/ExportService.swift`
- `[NEW] $TESTS/Core/ExportServiceTests.swift`

**Cosa fare:**

1. **ExportService** namespace:

   ```swift
   public enum ExportService {
       /// Destructive MP4 trim using AVAssetExportSession.
       /// CRITICAL: triggers SidecarGenerator after trim to regenerate GPMF sidecar.
       public static func trimVideo(
           sourceURL: URL,
           outputURL: URL,
           timeRange: CMTimeRange
       ) async throws -> URL

       /// Generate GPX file from GPS data.
       public static func exportGPX(
           from buffers: SensorDataBuffers,
           to outputURL: URL
       ) throws -> URL

       /// Generate CSV dump of all metrics.
       public static func exportCSV(
           from buffers: SensorDataBuffers,
           metrics: [String],
           to outputURL: URL
       ) throws -> URL
   }
   ```

2. **trimVideo implementation:**
   - `AVAsset(url: sourceURL)`
   - `AVAssetExportSession(asset:presetName: .passthrough)` — preserva qualità originale
   - `exportSession.timeRange = timeRange`
   - `exportSession.outputURL = outputURL`
   - `exportSession.outputFileType = .mp4`
   - Await `exportSession.export()`
   - **CRITICO** (da CLAUDE.md §Critical Constraints): AVFoundation passthrough NON preserva la GPMF track. Dopo il trim, chiamare `SidecarGenerator.generate(from: outputURL, ...)` per rigenerare il sidecar telemetria.

3. **Integrazione UI:** in `SessionDetailView`, il pulsante "Export Data" (attualmente placeholder) chiama `ExportService.trimVideo` se c'è un trimRange attivo.

**Test:**

- Test trimVideo con un asset sintetico (se possibile) o mock
- Verifica che SidecarGenerator viene chiamato post-trim
- Test GPX output format (XML valido)
- Test CSV output (header + dati)

**Acceptance criteria:**

- [x] MP4 trim produce file con durata ridotta
- [x] Sidecar GPMF rigenerato automaticamente post-trim
- [x] Nessuna perdita di qualità (passthrough)
- [x] 4+ test

---

### 8e.2 — ExportService: GPX Generation [NEW] [TEST]

**Complessità:** M
**Dipendenze:** 8e.1 (usa lo stesso ExportService)
**File:**

- `[MODIFY] $LIB/Core/Services/ExportService.swift`
- `[MODIFY] $TESTS/Core/ExportServiceTests.swift`

**Cosa fare:**

Implementare `ExportService.exportGPX`:

1. Leggere da `SensorDataBuffers.dynamic`:
   - `gps_gpmf_ts_lat` → latitudine
   - `gps_gpmf_ts_lon` → longitudine
   - `gps_gpmf_ts_alt` → altitudine (opzionale)
   - Timestamps dal buffer timestamps

2. Generare XML GPX 1.1:

   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <gpx version="1.1" creator="RowData Studio">
     <trk>
       <name>Session Title</name>
       <trkseg>
         <trkpt lat="45.1234" lon="12.5678">
           <ele>5.2</ele>
           <time>2026-02-28T10:30:00Z</time>
         </trkpt>
         ...
       </trkseg>
     </trk>
   </gpx>
   ```

3. Filtrare punti con NaN (coordinate invalide).

**Test:**

- GPX valido da buffer sintetico
- NaN filtrati
- Formato timestamp ISO 8601

**Acceptance criteria:**

- [x] File GPX 1.1 valido
- [x] Punti NaN esclusi
- [x] Timestamps ISO 8601
- [x] 3+ test

---

### 8e.3 — ExportService: CSV Dump [NEW] [TEST]

**Complessità:** S
**Dipendenze:** 8e.1
**File:**

- `[MODIFY] $LIB/Core/Services/ExportService.swift`
- `[MODIFY] $TESTS/Core/ExportServiceTests.swift`

**Cosa fare:**

Implementare `ExportService.exportCSV`:

1. Header row: `"timestamp_ms,metric1,metric2,..."`
2. Data rows: per ogni timestamp, output dei valori per le metriche richieste
3. NaN → cella vuota (non "NaN" stringa)

**Acceptance criteria:**

- [x] CSV con header e dati
- [x] NaN → vuoto
- [x] 2+ test

---

### 8e.4 — Accessibility Pass [MODIFY]

**Complessità:** M
**Dipendenze:** Dopo tutti gli altri task
**File:**

- `[MODIFY] $LIB/UI/DesignSystem/DesignTokens.swift`
- `[MODIFY] $LIB/UI/WidgetContainer.swift`
- `[MODIFY] $LIB/UI/Panels/*.swift`
- `[MODIFY] $LIB/UI/RowingDeskCanvas.swift`

**Cosa fare:**

Implementare i requisiti accessibilità (vision doc §9).

1. **Reduce Motion:** leggere `@Environment(\.accessibilityReduceMotion)`. Quando attivo:
   - Tutte le animazioni spring → instant (`.animation(nil)`)
   - Focus mode transition → nessuna animazione
   - Aggiungere un check in `RDS.Springs`:

     ```swift
     public static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
         reduceMotion ? nil : animation
     }
     ```

2. **Increase Contrast:** leggere `@Environment(\.colorSchemeContrast)`. Quando `.increased`:
   - Glass materials → solid `RDS.Colors.elevatedSurface` backgrounds
   - Widget borders → 2pt width invece di 0.5pt
   - Text → `RDS.Colors.textPrimary` always (no secondary)

3. **VoiceOver:** su `WidgetContainer`:

   ```swift
   .accessibilityElement(children: .contain)
   .accessibilityLabel("\(state.type?.displayName ?? "Widget"): \(state.title)")
   ```

   Su playhead position: `.accessibilityValue("Playhead at \(formattedTime)")`

4. **Dynamic Type:** `MetricCardWidget` e label → usare `@ScaledMetric` per font size.

**Acceptance criteria:**

- [x] Reduce Motion: tutte le animazioni disattivate
- [x] Increase Contrast: materials solidi, bordi spessi
- [x] VoiceOver: widget containers annunciati correttamente
- [x] Nessun crash con accessibilità attiva

---

### 8e.5 — Performance Validation [MANUAL]

**Complessità:** M
**Dipendenze:** Dopo tutti gli altri task
**File:** Nessun file da modificare. Test manuale.

**Cosa fare:**

Verificare il budget 60fps con la configurazione target (vision doc §0.5).

**Setup test:**

1. Caricare una sessione con: 2 video GoPro (1080p), 1 FIT file, 1 CSV Empower
2. Aprire sul canvas: 2 VideoWidget, 2 MultiLineChart (3 metriche ciascuno), 1 StrokeTable, 1 MapWidget, 1 AudioTrackWidget
3. Attivare il timeline panel

### Test 1: Playback

- Play video. Verificare con Instruments (Time Profiler) che il frame time medio < 16ms.
- Se > 16ms: identificare il bottleneck e ottimizzare.

### Test 2: Focus Mode

- Cmd+Click 2 chart, premere F. Verificare che la transizione non droppa sotto 30fps.

### Test 3: Scrubbing

- Drag il playhead sulla timeline. Verificare che tutti i widget aggiornano senza stutter visibile.

### Test 4: Canvas Zoom

- Pinch zoom 25% → 400%. Verificare fluidità.

### Test 5: Panel Toggle

- Tab → hide all → show all. Verificare che non c'è flash/redraw artefatto.

**Acceptance criteria:**

- [x] Frame time medio < 16ms durante playback con 7 widget + timeline
- [x] Focus Mode transition senza frame drop
- [x] Scrubbing fluido
- [x] Canvas zoom fluido
- [x] Panel toggle senza artefatti

---

## Riepilogo Task Count

| Sub-phase | Task | Nuovi file | File modificati | Test richiesti |
| --------- | ---- | ---------- | ---------------- | --------------- |
| **8a** Design System | 5 | 3 | 3 | 1 |
| **8b** Canvas Interaction | 7 | 3 | 5 | 4 |
| **8c** NLE Timeline & Audio | 8 | 7 | 5 | 5 |
| **8d** Floating Panels | 6 | 7 | 3 | 0 |
| **8e** Export & Polish | 5 | 2 | 5 | 3 |
| **Totale** | **31 task** | **22 nuovi file** | **21 file modificati** | **13 task con test** |

## Parallelizzazione possibile

Il seguente è un possibile scheduling con 2 junior engineers (J1, J2):

```text
Settimana 1:  J1 → 8a.1, 8a.2, 8a.3     |  J2 → 8c.1, 8c.6 (paralleli, zero dipendenze incrociate)
Settimana 2:  J1 → 8a.4, 8a.5, 8b.1, 8b.2 |  J2 → 8c.2, 8c.3, 8c.8
Settimana 3:  J1 → 8b.3, 8b.4            |  J2 → 8c.4, 8c.5, 8c.7
Settimana 4:  J1 → 8b.5, 8b.6            |  J2 → 8d.1, 8d.2
Settimana 5:  J1 → 8b.7, 8e.1            |  J2 → 8d.3, 8d.4, 8d.5
Settimana 6:  J1 → 8e.2, 8e.3            |  J2 → 8d.6
Settimana 7:  J1 + J2 → 8e.4, 8e.5 (validation congiunta)
```
