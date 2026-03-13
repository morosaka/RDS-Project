# Phase 8a — Design System Foundation (2026-03-11)

**Status:** ✅ COMPLETE | **Build:** Clean

## Session Summary

Implementato il design system "Spatial Glassmorphism" v2 per RowData Studio.
Tutti e 5 i task della fase 8a sono stati completati. Il risultato visivo è un'interfaccia
dark-immersive con widget chromeless, glow accent arancio, e header materializzati on hover.

## Task Completati

| Task | File | Stato |
|------|------|-------|
| 8a.1 — Design Tokens | `UI/DesignSystem/DesignTokens.swift` v1.0.0 | ✅ |
| 8a.2 — GlowButton | `UI/DesignSystem/GlowButton.swift` v1.0.0 | ✅ |
| 8a.3 — Widget Chrome Redesign | `UI/WidgetContainer.swift` v2.0.0 | ✅ |
| 8a.4 — Canvas Background | `UI/RowingDeskCanvas.swift` (pure black) | ✅ |
| 8a.5 — Window Styling | `RowDataStudioApp/App.swift` | ✅ |

## Files Created / Modified

### UI/DesignSystem/DesignTokens.swift (NEW, v1.0.0)

Token centralizzati per tutti i valori visual:
- `RDS.Colors`: `canvasBackground` (#000000), `accent` (#FF9F0A), `widgetSurfaceGradientTop/Bottom`, `widgetBorderGlow`, `widgetBorderSelected`, `textPrimary/Secondary`
- `RDS.Typography`: `widgetTitle`, `dataValue` (monospaced), `axisLabel`, `captionMono`
- `RDS.Springs`: `widgetSnap`, `focusModeZoom`, `tierResize`, `headerReveal`, `glowPulse`
- `RDS.Layout`: `widgetCornerRadius` (12), `widgetBorderWidth` (0.5), `focusDimOpacity` (0.3), `resizeHitZone` (8), `minWidgetWidth/Height` (200/120), `canvasZoomMin/Max` (0.25/4.0)
- `RDS.MetricColors`: palette semantica (speed, acceleration, heartRate, power, position, force)
- `StreamType` enum con `semanticColor` computed property

### UI/DesignSystem/GlowButton.swift (NEW, v1.0.0)

Pulsante chromeless: nessun background/bordo, solo icona SF Symbol.
- Opacity 0.45 a riposo → 1.0 on hover (easeOut 150ms)
- Hit area estesa di 8pt (`.contentShape(Rectangle())` padding)
- Usato nel header bar dei widget (visibility toggle, delete)

### UI/WidgetContainer.swift (MODIFY → v2.0.0)

Redesign completo del container widget:
- Background: `LinearGradient` scuro (widgetSurfaceGradientBottom → Top), opacity 0.95
- Bordo: `RoundedRectangle.stroke` con glow accent/selected/dim per tier
- Header bar: overlay invisibile a riposo, materializza on hover con `handleHover()`, scompare dopo 300ms con debounce Task. Header = `LinearGradient` da top trasparente.
- Resize handles: 8 zone invisibili (4 bordi + 4 angoli) via `ResizeHandler` struct
- Nuovi callbacks: `onSelect: () -> Void`, `onTierToggle: () -> Void`
- Double-click sul header → `onTierToggle()`
- Aggiunto `isHovered`, `isHeaderVisible`, `headerHideTask` come `@State`
- `RoundedCorner` + `RectCorner` OptionSet per angoli selettivi (header top-left/top-right)
- NSBezierPath → SwiftUI Path conversion per `RoundedCorner.path(in:)`

### UI/RowingDeskCanvas.swift (8a.4 — canvas background)

- `RDS.Colors.canvasBackground.ignoresSafeArea()` — pure black
- Rimossa griglia di punti/linee — solo nero

### App.swift (8a.5 — window styling)

- `NSWindow.titleVisibility = .hidden`, `titlebarAppearsTransparent = true`
- `colorScheme(.dark)` forzato sul root view
- Minimum size 1024×768
- Background finestra `#000000` (nessun flash bianco al resize)

## Test

- `UI/DesignTokensTests.swift`: verifica token critici (accent color, springs count, metric colors, StreamType coverage)
- Test count aggiornato: ~310 (da 298 Phase 7, +12 DesignTokens)

## Architectural Decisions

### Widget Content Evaluata una volta in init

`WidgetContainer` è `struct WidgetContainer<Content: View>` generico su `Content`.
`self.content = content()` valutata in `init` — evita `AnyView` type erasure.
SwiftUI re-crea il container intero quando necessario (widget ID stabile = stato stabile).

### Header reveal via Task + debounce

`handleHover(true)` cancella il hide task e mostra header.
`handleHover(false)` lancia Task con 300ms sleep, poi nasconde.
Gestisce correttamente hover rapidi (entra/esce in < 300ms → no flicker).

## Commits Chiave

- `915fbd0` — Phase 8 plan + DesignTokens + GlowButton (initial)
- `190a33d` — Spatial Glassmorphism Redesign (WidgetContainer v2.0)
- `c50ed42` — Dark theme enforcement (window styling, colorScheme)
