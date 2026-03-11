# RowData Studio — Design Language: From Mood to Mechanism

> **Status:** Working draft
> **Date:** 2026-03-10
> **Context:** Deep-dive on how to translate the "Minority Report feeling" into concrete, implementable design decisions without 2.5D, parallax, or expensive GPU effects.

---

## What Strikes Us About Futuristic UI (The Feeling)

Before implementation, we identify the *sensations* that make futuristic interfaces compelling:

1. **Information emerges from darkness** — the background doesn't exist, data glows. There's no "window" with a "title bar" — there's a luminous entity floating in void.
2. **Transparency and layering** — panels are semi-transparent, you see "through" layers. This creates depth without real parallax.
3. **Light as information** — edges glow, data pulses, transitions are luminous. No material shadows (card with drop-shadow) — instead: glow, bloom, emission.
4. **Fluid, intentional motion** — elements move as if they have mass and inertia, but very little. They glide, never snap.
5. **Absence of traditional chrome** — no scrollbars, no bordered buttons, no dropdown menus. Controls appear when needed and vanish when they don't.

---

## 1. Information Emerges From Darkness

### 1.1 Decisions

- Canvas background **`#000000` (pure black)** as default, not `#1C1C1E`. On XDR displays, pixels are literally off — widgets *emit light* from the screen.
- Widget surface: not flat gray, but a **subtle bottom-up gradient** (`#0A0A0A` → `#141414`). Creates the illusion of a slab lit from beneath.
- Widget borders: not `Color.secondary.opacity(0.3)` (gray on gray), but a **hairline glow** — `Color.accentColor.opacity(0.15)` with `shadow(.inner, color: .accent.opacity(0.05), radius: 1)`. The border appears to *emit* faint light, not *contain* the widget.
- Chart lines drawn with `lineWidth: 1.5` plus a second pass at `lineWidth: 4, opacity: 0.15` in the same color → **glow effect** on the data curve. Negligible GPU cost (a second stroke on the same path).

### 1.2 SwiftUI Example

```swift
// Widget border: subtle glow instead of flat stroke
RoundedRectangle(cornerRadius: 8)
    .stroke(Color.accentColor.opacity(0.12), lineWidth: 0.5)
    .shadow(color: Color.accentColor.opacity(0.08), radius: 4)

// Chart line: data + glow pass
Canvas { context, size in
    // Glow pass (wide, transparent)
    context.stroke(path, with: .color(metricColor.opacity(0.2)),
                   lineWidth: 5)
    // Data pass (sharp, opaque)
    context.stroke(path, with: .color(metricColor),
                   lineWidth: 1.5)
}
```

---

## 2. Transparency and Layering

### 2.1 Decisions

- **Floating panels** (timeline, inspector, palette) use `ultraThinMaterial` — these are the true "glass" element. Through them you glimpse the canvas and widgets beneath. This is where glassmorphism lives legitimately.
- **Widgets** have near-opaque backgrounds (`#0D0D0D` at 95% opacity) — not fully solid, but with a *hint* of transparency that makes them feel "above" the canvas, not "glued to it." On XDR, this 5% transparency is enough to create perceived depth.
- **The canvas** (black background) is visible only in the interstices between widgets and under panels. It functions as "the void" — the nothingness from which information emerges.

### 2.2 The Trick

Three opacity levels are sufficient to create convincing depth without parallax:

```text
Z0: Canvas      — pure black, #000
Z1: Widgets     — near-opaque, 95% opacity, dark surface
Z2: Panels      — ultraThinMaterial, ~60% translucent
```

---

## 3. Light as Information

### 3.1 Decisions

- **Playhead:** not just a red line — a thin line (1pt) with a **vertical glow** (orange shadow `radius: 6, opacity: 0.4`). On XDR displays it looks like a laser cutting the screen.
- **Selected widget:** border glow intensifies (opacity from 0.12 to 0.5). No shape change, no added chrome — it becomes *brighter*, as if charged with energy.
- **Hover on controls:** buttons (play/pause, mute, close) have no background — they're pure SF Symbol icons that increase luminance on mouse hover (`opacity: 0.5 → 1.0`). Zero chrome.
- **Metric Card value update:** when the value changes (playhead moves), the number doesn't "snap" — it does a very brief luminance flash (100ms, `opacity: 1.0 → 1.3 → 1.0` with `blendMode: .plusLighter`). Extremely subtle, but your peripheral vision catches it.
- **Semantic metric colors with glow:** colors (speed blue, HR red, etc.) are never flat — they always have a subtle halo of their own color. Speed's blue *slightly illuminates* the widget background around the curve.

### 3.2 SwiftUI Examples

```swift
// Playhead with laser glow
Rectangle()
    .fill(Color.orange)
    .frame(width: 1)
    .shadow(color: Color.orange.opacity(0.4), radius: 6)
    .shadow(color: Color.orange.opacity(0.15), radius: 15)

// Button: no chrome, just luminance
Image(systemName: "play.fill")
    .foregroundStyle(.white.opacity(isHovered ? 1.0 : 0.5))
    .animation(.easeOut(duration: 0.15), value: isHovered)
    // No background, no border, no shape — just light
```

---

## 4. Fluid, Intentional Motion

### 4.1 Decisions

- **Spring animations everywhere**, never `linear` or `easeInOut`. Elements have "mass":
  - Widget drag: `spring(response: 0.35, dampingFraction: 0.8)` — follows the finger with a slight elastic delay.
  - Panel show/hide: `spring(response: 0.4, dampingFraction: 0.9)` — glides, doesn't snap.
  - Focus mode transition: `spring(response: 0.5, dampingFraction: 0.85)` — cinematic zoom, but fast.
- **No gratuitous movement.** Widgets don't bounce, don't wobble, don't have idle animations. They move only when the user commands them. Movement is *response*, not *decoration*.
- **Inertial scrolling** on the timeline: flick and the timeline continues scrolling, decelerating with friction. SwiftUI provides this for free with `ScrollView`, but the custom canvas must implement it (`velocity * dampingFactor` per frame).

### 4.2 Spring Reference Table

| Interaction | Response | Damping | Feel |
| ----------- | -------- | ------- | ---- |
| Widget drag | 0.35 | 0.80 | Elastic, responsive |
| Panel show/hide | 0.40 | 0.90 | Smooth glide |
| Focus mode zoom | 0.50 | 0.85 | Cinematic but quick |
| Widget snap to grid | 0.25 | 0.75 | Snappy, satisfying |
| Value flash (metric card) | 0.15 | 1.00 | Critically damped pulse |

---

## 5. Absence of Traditional Chrome

### 5.1 Decisions

- **No button with visible border.** All controls are icon-only with luminous hover state. The "button" is the glow that appears on mouse hover, not a rectangle with a background.
- **No visible scrollbars.** The stroke table scrolls but scrollbars appear only during scroll (overlay style, like Safari). Never permanent.
- **Widget title bar:** doesn't exist at rest. Materializes on-hover as a semi-transparent gradient at the top of the widget with type icon + title + close button. Disappears 300ms after mouse exit.
- **Timeline track header** (left column with source names) is minimal: type icon + truncated name. No borders between rows — just spacing. Rows are distinguished by content, not by separator lines.
- **Context menu** (right-click): not the native macOS menu — a custom menu with `ultraThinMaterial` background, rounded corners, SF Symbol icons per item. Consistent with app aesthetic.

### 5.2 SwiftUI Example

```swift
// Chromeless button — no background, no border, just light
struct GlowButton: View {
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white.opacity(isHovered ? 1.0 : 0.45))
            .contentShape(Rectangle().inset(by: -8)) // larger hit area
            .onHover { isHovered = $0 }
            .onTapGesture(perform: action)
    }
}
```

---

## The Composite Result

When all five principles combine:

- **Launch the app** → black screen. Widgets *emerge* with a fade + scale spring. They appear to switch on.
- **Charts glow** faintly in their semantic colors against the black. The playhead cuts the screen like an orange laser.
- **Hover a widget** → its border illuminates, the title bar materializes from nothing. Move away → it fades.
- **Press Tab** → all chrome vanishes. Only luminous data on black remains. **This** is the "Minority Report" moment.
- **Press Space** → video plays, the playhead glides, metric card numbers pulse imperceptibly with each update. Everything moves with inertia, nothing snaps.
- **The timeline panel** at the bottom is a translucent glass through which you glimpse the widgets beneath — it doesn't hide them, it veils them.

---

## Implementation Cost Assessment

None of this requires 2.5D, parallax, or expensive blur. Everything is achievable with:

| Technique | Cost | SwiftUI Native? |
| --------- | ---- | --------------- |
| Calibrated opacity colors | Zero | Yes |
| 2-3 shadow passes for glow | Negligible | Yes (`.shadow()`) |
| Double-stroke for line glow | ~0.5ms per chart | Yes (`Canvas` API) |
| Spring animations | Zero (framework) | Yes (`.spring()`) |
| `ultraThinMaterial` on panels | System-managed | Yes |
| Pure black background | Free (saves energy on OLED/XDR) | Yes |
| On-hover reveal/hide | Zero | Yes (`.onHover`) |
| `blendMode: .plusLighter` for value flash | Negligible | Yes |

**Total additional GPU budget vs flat UI:** estimated <2ms per frame on Apple Silicon. Well within the 16ms budget for 60fps.
