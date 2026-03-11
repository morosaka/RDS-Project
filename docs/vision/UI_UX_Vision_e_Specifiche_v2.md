# RowData Studio — UI/UX Vision & Design System (v2)

> **Status:** Working draft — v1 interview + follow-up Q&A integrated
> **Date:** 2026-03-10
> **Origin:** User interview (v1) + architectural review + follow-up clarifications

---

## 0. Design Principles

1. **Beautiful AND Fast** — These are not in tension. The interface must provoke a "che figata" reaction on first launch AND be the fastest tool in the user's workflow. Beauty without speed is a demo; speed without beauty is a spreadsheet. We ship neither.
2. **Data Density Over Decoration** — Visual effects must *serve* data comprehension. A glassmorphism panel is beautiful when it frames data clearly. It's decoration when it obscures a chart.
3. **Predictable Interaction** — A pinch always does the same thing in the same context. No mode confusion.
4. **Progressive Disclosure** — Default: clean, focused. On demand: full power. An athlete glancing at split times and a coach deep-diving force curves use the same canvas — the complexity adapts.
5. **60fps Is the Floor** — Every visual effect must be justified against the frame budget. If it can't run at 60fps with 2 videos + 4 charts, it doesn't ship.
6. **macOS-Native, Not macOS-Defiant** — We transcend standard chrome without confusing users. Menu bar, keyboard shortcuts, and window management feel native. The app lives *inside* macOS, not against it.

---

## 1. Concept & Aesthetic

### The Vision

A **dark, immersive analysis environment** that feels like a purpose-built instrument — as polished as DaVinci Resolve, as focused as a cockpit. Video, telemetry, and biometrics coexist in a shared spatial workspace where everything moves in sync.

The inspiration draws from:

- **Professional NLEs** (DaVinci Resolve, Final Cut Pro) — dark canvas, floating panels, timeline-centric workflow
- **Apple visionOS / HIG** — glassmorphism materials, depth through elevation, system-consistent interaction
- **Instrument panels** — information density done right: every element earns its pixels

> **v1 evolution:** The "Minority Report" mood-board energy is preserved — the *feeling* of an immersive, futuristic, data-forward environment. The *mechanisms* are grounded in proven professional tool patterns rather than sci-fi UI idioms.
> See ./docs/vision/design-language-details.md

### The Material Language

- **Floating panels** (timeline, inspector, library): `ultraThinMaterial` — the glass effect is the signature visual identity. Translucent, layered, alive.
- **Widget chrome** (borders, title bars): `regularMaterial` — subtle depth, not heavy.
- **Data-rendering areas** (chart interiors, video frames): **Solid dark backgrounds** — translucency behind data harms legibility. The glass frames the data; the data itself sits on a clean, opaque surface.
- **Toggleable:** Glass/blur off in Settings for users who prefer solid backgrounds (accessibility + performance).

---

## 2. The Canvas (The Workspace)

The core is an **infinite 2D spatial canvas** — a freeform workspace where widgets live.

### Background

- **Default:** Deep charcoal (`#1C1C1E`, system dark). Zero visual noise.
- **Optional (Settings):**
  - Light mode (inverted palette, solid widget backgrounds).
  - Engineering grid (millimeter-scale, subtle lines — useful for precise widget alignment).
- **Extensibility:** Background system is a protocol; future styles can be added.

### Canvas Navigation

- **Pan:** Two-finger drag (trackpad) or middle-click drag (mouse) on empty canvas.
- **Zoom:** Pinch (trackpad) or Cmd+scroll on empty canvas. Uniform scale — all widgets scale together. Range: 25%–400%.
- **Zoom-to-Fit:** Double-tap empty canvas or Cmd+0 → animate to fit all visible widgets.

### Primary / Secondary Widget Tiers

A typical analysis session has **2-4 primary widgets** (1-2 videos, 2-3 charts) in active focus, plus **2-3 secondary widgets** (metric cards, map, stroke table) available at a glance for spot-checking.

Instead of 2.5D depth-of-field, we use a **tier system**:

- **Primary tier:** Full-size widgets at native resolution. Sharp, interactive, receiving all input.
- **Secondary tier:** Smaller widgets, slightly reduced visual prominence (subtle border dimming, slightly lower opacity on non-data elements like axes/legends — but data itself stays sharp and legible). Fully interactive — click to inspect, scroll to browse.
- **Transition:** Double-click widget title bar → **toggle** between primary and secondary tier (matching macOS convention where double-click on a window title bar toggles between two size states).
- **Spatial layout:** Primary widgets occupy the central canvas area. Secondary widgets cluster to the periphery, snapped to edges or grouped in a corner — but this is user-arranged, not forced.

> **v1 reconciliation:** This captures the intent behind the 2.5D Focus Groups (primary data in foreground, secondary at arm's reach) without parallax, blur, or Z-depth complexity. The differentiation is through **size and visual weight**, not through simulated depth.

### Focus Mode

- **Cmd+click** to select multiple widgets.
- **Press F:** Selected widgets animate to fill the viewport. Non-selected widgets **dim** (opacity 30%, no interaction).
- **Press Esc** or **F** again: restore previous viewport.
- Useful for deep-dive moments: "show me just the two force curve charts and the video."

> **OPEN QUESTION — Mouse-only access to Focus Mode:**
> Keyboard shortcut (F) is the primary path, but we need a mouse-only alternative for discoverability and trackpad-only use. Two candidates under evaluation:
>
> 1. **Right-click context menu** on multi-selection → "Focus Selection" item. Consistent with macOS conventions, no permanent UI cost. Risk: context menus are invisible until invoked — discoverability depends on user habit.
> 2. **Contextual floating pill** that appears near a multi-selection (like macOS text selection toolbar or Figma's action bar). Disappears when selection is cleared. Risk: adds a transient UI element — could break the "no chrome" aesthetic if not executed with extreme restraint.
>
> This needs further design exploration and prototyping before committing. The tension is real: any visible affordance risks breaking the immersive feel, but keyboard-only access is a discoverability dead end for new users.

---

## 3. Widgets

Widgets are the building blocks of analysis. Each widget is an independent, self-contained view of a data source or media stream.

### Widget Types (MVP)

| Widget | Content | Notes |
| ------ | ------- | ----- |
| **Video** | Video-only playback (no embedded audio) | AVPlayerLayer, synced to playhead |
| **Audio** | Waveform display of audio track | Peak envelope visualization, volume control |
| **Line Chart** | Multi-metric time series | Overlay N metrics, shared or independent Y-axes |
| **Stroke Table** | Per-stroke data rows | Scrollable, active row highlighted by playhead |
| **Map** | GPS track polyline + position marker | MapKit, playhead-synced annotation |
| **Radar** | Spider chart (Empower biomechanics) | 6-axis, configurable reference maxima |
| **Metric Card** | Single KPI with trend | Instantaneous value + session average delta |

### Video + Audio Separation

Video and audio are **independent widgets**, not bundled:

- **Video widget:** Renders video frames only. No audio playback, no volume control. Pure visual.
- **Audio widget:** Renders the waveform of an audio track (extracted from a video file, or standalone audio). Has volume control, mute toggle.
- **Why separate?** A single GoPro video has one audio track, but a multi-camera session might have 3 video tracks and only 1-2 useful audio tracks (the one from the coach boat, the one closest to the rower). Separating them lets the user choose which audio to monitor without coupling it to a specific video angle.
- **Snap behavior:** Audio widgets snap below/above video widgets for visual association, but remain independently moveable.

### Framing & Chrome

- **Default:** Subtle rounded rect border (`cornerRadius: 8`), 1pt stroke in `Color.secondary.opacity(0.3)`. No heavy chrome. No visible resize handles.
- **Selected:** Border brightens to accent color.
- **Hover:** Minimal title bar fades in (widget type icon + title + close button). Fades out on mouse exit.
- **Resize:** Invisible hit zones on edges and corners (4-6pt). Cursor changes to resize arrow on approach (macOS Finder behavior). Drag to resize. No visible handles — the cursor *is* the affordance.
- **All other widgets at one click:** Widget palette (toggleable panel) shows all available widget types. Drag onto canvas to instantiate. The palette also shows "suggested" widgets based on loaded data sources (e.g., if Empower data is present, the Radar widget is highlighted).

### Arrangement

- **Free placement** anywhere on canvas (drag to position).
- **Magnetic snapping:** Widgets snap to edges/centers of adjacent widgets (8pt threshold). Snap guides appear as thin lines (Figma-style).
- **Grid snapping (optional):** When engineering grid background is active, widgets also snap to grid intersections.

#### Overlap & Z-Ordering (Hybrid Approach)

Overlap is **permitted but discouraged by design**:

- **Snapping resists overlap:** When dragging a widget toward another, magnetic snapping favors edge-to-edge placement (adjacent, not overlapping). The user must drag past the snap threshold to intentionally overlap.
- **Implicit Z-ordering:** No manual "Send to Back" / "Bring to Front" controls. Simply: **the last widget clicked or dragged is on top.** Z-order is a side effect of interaction, not a feature to manage.
- **Overlap nudge:** When two widgets overlap, the border in the overlap zone shows a brief orange flash (500ms) — a subtle visual hint that says "these are overlapping" without preventing it. Non-blocking, non-modal.
- **Legitimate overlap use case:** A small Metric Card intentionally placed over the corner of a Video widget, functioning as an on-screen display (OSD). This is why overlap is allowed, not forbidden.

---

## 4. The Timeline (NLE-Style)

The timeline is not just a playback scrubber — it's a **multi-track NLE timeline** inspired by Final Cut Pro and DaVinci Resolve.

### Core Model: Tracks ↔ Widgets

The timeline and the canvas are two views of the same data. **Each metric gets its own track. Each widget is a view that subscribes to one or more tracks.**

- **Adding a widget to the canvas** automatically creates corresponding track(s) in the timeline.
- **Removing a widget from the canvas** automatically removes its track(s) from the timeline.
- **Symmetry:** automatic creation, automatic removal. No orphan tracks, no ghost state.
- **Pin to keep:** A pin icon on the track header lets the user mark a track as **permanent**. A pinned track persists even after its widget is closed — useful for keeping a sparkline reference visible in the timeline without a full canvas widget. Unpin → track follows normal lifecycle (disappears when no widget uses it).

### Track Granularity

Tracks represent **individual data streams**, not source files:

- A GoPro MP4 produces: 1 video track + 1 audio track (not a single "GoPro" track)
- A FIT file produces: individual tracks per metric opened (Speed, HR, Cadence — each a separate track when the user adds the corresponding widget)
- GPMF telemetry: individual tracks per metric (ACCL Surge, GYRO Yaw, etc.)
- CSV (Empower): individual tracks per metric (Catch Angle, Peak Force, etc.)

This means: **no monolithic "FIT" or "GPMF" tracks.** Each metric lives independently. The timeline becomes a precise inventory of what the user is currently analyzing.

### Architecture

```text
┌──────────────────────────────────────────────────────────┐
│  Ruler   │ 0:00    0:30    1:00    1:30    2:00          │
├──────────┼──────────────────────────────────────────────┤
│ 📹 V1    │ ████████ GoPro Bow ████████                   │  ← video thumbnails
│ 📹 V2    │    ████████ GoPro Stern ████████               │  ← video (offset)
│ 🔊 A1    │ ░░░░░░░ Coach Audio ░░░░░░░                   │  ← audio waveform
│ 🔵 Speed │ ╌╌╌~~~╌╌╌~~~╌╌╌~~~╌╌╌                         │  ← sparkline (FIT)
│ 🔴 HR    │ ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌                        │  ← sparkline (FIT)
│ 🟣 SR    │ ╌╌~╌╌~╌╌~╌╌~╌╌~╌╌~╌╌                         │  ← sparkline (FIT)
│ 🟢 Force │ ╌╌^╌╌^╌╌^╌╌^╌╌^╌╌^╌╌                         │  ← sparkline (Empower CSV)
│ 📍 GPS   │ ████ fix ████░░no░░████                       │  ← GPS fix availability
├──────────┼──────────────────────────────────────────────┤
│ 📌 Cues  │  🔖 "catch timing"     🔖 "good drive"       │  ← cue/bookmark track
├──────────┼──────────────────────────────────────────────┤
│          │              ▏← PLAYHEAD                      │
└──────────────────────────────────────────────────────────┘
```

### Widget → Track Mapping

| Widget Type | Creates Track(s)? | Track Content |
| ----------- | ----------------- | ------------- |
| Video | Yes (1 video track) | Thumbnail strip |
| Audio | Yes (1 audio track) | Mini-waveform |
| Line Chart (N metrics) | Yes (N tracks, one per metric) | Sparkline per metric |
| Stroke Table | Yes (1 track per displayed metric) | Sparklines |
| Map | Yes (1 GPS track) | GPS fix/availability bar |
| Radar | **No** — derived per-stroke aggregate | — |
| Metric Card | **No** — derived single KPI | — |

### Track Header

- **Left column:** semantic color dot + metric name (truncated) + type icon
- **Pin icon:** click to pin/unpin track (pinned = persists without widget)
- **Mute/solo:** for audio tracks only
- **Visibility toggle** (eye icon): hides the sparkline without removing the track

### Tracks

- **Tracks are ordered vertically** by the user (drag to reorder).
- **Track sparklines** use the metric's semantic color and render as a miniature waveform — enough to see patterns, anomalies, and temporal extent at a glance.
- **Offset:** Each track can be time-shifted independently (drag the bar left/right on the timeline). This is how multi-camera sync is achieved visually — the user aligns tracks by ear (audio) or by visual event matching, then locks them.

### Cue / Bookmark Track

- A dedicated track at the bottom for **temporal markers with notes**.
- **Add cue:** Click the "+" on the cue track at the playhead position, or press **M** (marker shortcut).
- **Each cue:** A vertical pin on the timeline + a short text label (editable inline). Clicking a cue seeks the playhead to that position.
- **Use cases:** "Catch timing issue here," "Good drive sequence," "Show to coach," "Possible sync drift."
- No frame-level annotations on video — cues on the timeline are sufficient.

### Timeline Interaction

- **Scrub:** Click/drag on the ruler → moves playhead. All synced widgets update in real-time.
- **Zoom:** Pinch horizontally on the timeline → temporal zoom (show more or less time). Cmd+scroll also works.
- **Scroll:** Scroll vertically to see more tracks if they overflow.
- **Trim:** In/out handles on video tracks for non-destructive trim (already implemented: VideoTrimView v1.0.0).

---

## 5. Floating Panels (Navigation & Controls)

Panels are the app's control surfaces: timeline, inspector, library, widget palette. They share a unified interaction model.

### Panel Behavior (Unified)

Panels behave like **super-widgets** — repositionable, resizable, minimizable — but in a layer above the canvas:

- **Always on top:** Panels live in a Z-layer above all canvas widgets. They can never end up "behind" a chart or video.
- **Window-level overlay:** Panels do NOT participate in canvas zoom/pan. When you zoom the canvas, panels stay fixed relative to the screen. This is the key perceptual distinction: widgets live *inside* the canvas, panels live *above* the window.
- **Repositionable:** Drag a panel's title bar to move it anywhere within the window.
- **Resizable:** Drag panel edges to resize (e.g., make the timeline taller to show more tracks, or the inspector wider).
- **Minimizable:** Minimize a panel → it collapses to a small **pill** (icon + name) anchored to the nearest window edge. Click the pill → panel expands back. Minimized panels occupy near-zero space but remain always findable.
- **Edge magnetism:** Panels have strong snap affinity to window edges. Dragging a panel near the bottom edge snaps it flush — guiding users toward sensible layouts without forcing them.

### Defaults & Safety Net

| Panel | Default Position | Toggle |
| ----- | ---------------- | ------ |
| **Timeline** | Bottom, full width | Cmd+T |
| **Inspector** | Right edge | Cmd+I |
| **Library** | Center overlay | Cmd+L |
| **Widget Palette** | Left edge | Cmd+P |

- **Reset Layout:** **Cmd+Shift+0** restores all panels to their default positions. The safety net for "I dragged everything into chaos."
- **Hide All:** Press **Tab** → all panels fade out. Only canvas + widgets remain. Press **Tab** again → panels reappear in their last positions.
- **Panel memory:** Panel positions, sizes, and visibility state persisted per session.

### The Library / Session Picker

- A floating panel, not a permanent sidebar.
- Shows: recent sessions (sorted by date), favorites, import button, search/filter.
- Selecting a session loads it into the canvas. Library can auto-dismiss or stay open.
- The library panel can also be summoned from a subtle persistent button in the window title bar area.

---

## 6. Interaction & Data Feedback

### The Playhead

- **Visual:** High-contrast vertical line (accent color, 2pt width). Traverses all temporal widgets AND the timeline simultaneously.
- **Sync:** Bidirectional — drag playhead → video/audio seek; play video → playhead moves. Frame-accurate. (Already implemented: VideoSyncController v1.0.0, PlayheadController.)
- **Cross-widget propagation:** Playhead position drives:
  - Video widgets → frame display
  - Audio widgets → playback position + waveform cursor
  - Line charts → vertical cursor line + value readout
  - Map widget → GPS position marker
  - Metric cards → instantaneous value
  - Stroke table → active row highlight

### Zoom Model (Three Layers)

The app has three distinct zoom scopes, each determined by *where* the gesture happens — no modes, no toggles. Both trackpad and mouse are first-class input devices.

#### Gesture Reference (Complete)

| Action | Trackpad | Mouse |
| ------ | -------- | ----- |
| **Canvas zoom** | Pinch on empty canvas | Cmd+scroll on empty canvas |
| **Canvas pan** | Two-finger drag on empty canvas | Middle-click drag on empty canvas |
| **Timeline zoom (global time)** | Pinch on timeline | Cmd+scroll on timeline |
| **Widget zoom X (time)** | Pinch inside widget | Cmd+scroll inside widget |
| **Widget zoom Y (values)** | Two-finger scroll vertical inside widget | Option+scroll inside widget |
| **Widget reset + re-link** | Double-tap inside widget | Double-click inside widget |
| **Force global zoom from widget** | Shift+pinch inside widget | Shift+Cmd+scroll inside widget |
| **Widget resize** | — | Edge/corner drag (invisible hit zones) |
| **Widget tier toggle** | Double-tap title bar | Double-click title bar |

#### Global Temporal Zoom (Timeline-Driven)

- Pinch on the timeline (or Cmd+scroll with mouse) → changes the visible time window (e.g., from full session to a 30-second segment).
- **All linked widgets** update to show the same time range. Charts, audio waveforms, video — everything follows.
- This is the primary zoom for analysis: "show me this 2-minute interval across all data."

#### Local Data Zoom (Widget Override)

- **Time axis (X):** Pinch (trackpad) or Cmd+scroll (mouse) inside a chart widget → that widget **unlinks** from the global time window and shows its own independent time range.
- **Value axis (Y):** Two-finger vertical scroll (trackpad) or Option+scroll (mouse) inside a chart → zooms the value axis (e.g., narrow the force range to 50-150N). Does NOT unlink the time axis.
- **Visual indicator for unlinked time:** The widget's time axis labels turn **accent color (orange)** instead of default gray — signaling "this widget is showing a different time range than the rest."
- **Reset + re-link:** Double-tap/double-click inside the widget → resets both axes to auto-fit AND re-links to the global time window. Orange labels disappear.
- **Force global from widget:** Shift+pinch (trackpad) or Shift+Cmd+scroll (mouse) inside a widget → zooms the global time window (same as acting on the timeline). Convenient when the timeline is collapsed or hidden.

#### Widget Resize (Not Zoom)

- Widget resizing uses **edge/corner drag** (invisible hit zones, cursor changes on approach — macOS Finder behavior). This is separate from all zoom gestures.
- **Double-click title bar** toggles between primary/secondary tier sizes.
- Pinch/scroll inside a widget NEVER resizes its frame — it always zooms the data.

### Animations

- **Philosophy:** Fast, purposeful, never decorative. `spring(response: 0.3, dampingFraction: 0.85)` as default.
- **Reduce Motion:** Respect `accessibilityReduceMotion`. When active: instant transitions, no spring physics.
- **Budget:** If an animation pushes frame time above 16ms → simplify or cut.

---

## 7. Typography & Color Palette

### Typography

| Context | Font | Rationale |
| ------- | ---- | --------- |
| UI headers, labels | SF Pro Display | Native, clean, elegant |
| Data values, telemetry readouts | **SF Mono** | Tabular alignment — numbers stack vertically. Critical for metrics. |
| Widget titles, secondary UI | SF Pro Text | Optimized for small sizes |
| Timeline ruler, cue labels | SF Mono (small) | Temporal precision |

### Color Palette

#### Base Tones

- **Canvas background:** `#1C1C1E` (system dark) to `#000000` (pure black for XDR displays).
- **Widget surface:** `#2C2C2E` (elevated).
- **Text:** `#FFFFFF` primary, `#8E8E93` secondary.
- **Panel glass:** `ultraThinMaterial` (system-managed translucency).

#### Accent & Playhead

- **Primary accent:** Vibrant Orange/Amber (`#FF9F0A` — system orange). Playhead, active selections, primary buttons.
- **Rationale:** Maximum contrast against dark backgrounds AND video content (water is blue/green; orange is complementary).

#### Semantic Metric Colors (Standardized — Immutable)

| Metric Family | Color | Hex | Rationale |
| ------------- | ----- | --- | --------- |
| Speed / Pace | Electric Blue | `#0A84FF` | Universal velocity association |
| Heart Rate | Crimson | `#FF453A` | Medical convention |
| Stroke Rate | Purple | `#BF5AF2` | Distinct from HR, cadence feel |
| Power / Force | Green | `#30D158` | Energy/strength |
| GPS / Position | Teal | `#64D2FF` | Navigation convention |
| IMU / Orientation | Yellow | `#FFD60A` | Sensor/instrument association |

These colors are **immutable across the app.** Users learn the color language once: "blue = speed, red = heart rate." No per-chart color configuration needed.

---

## 8. Keyboard-First Interaction

| Shortcut | Action |
| -------- | ------ |
| **Space** | Play / Pause |
| **J / K / L** | Reverse / Pause / Forward (NLE convention, repeated L = 2x/4x) |
| **Left / Right** | Step one frame |
| **Shift+Left/Right** | Step to next/previous stroke boundary |
| **M** | Add cue/bookmark at playhead |
| **Tab** | Hide/show all floating panels |
| **F** | Focus selected widgets |
| **Esc** | Exit focus / deselect all |
| **Cmd+0** | Zoom canvas to fit all widgets |
| **Cmd+L** | Toggle library panel |
| **Cmd+I** | Toggle inspector panel |
| **Cmd+T** | Toggle timeline panel |
| **Cmd+P** | Toggle widget palette |
| **Delete** | Remove selected widget |
| **Cmd+Z / Cmd+Shift+Z** | Undo / Redo canvas operations |
| **Cmd+D** | Duplicate selected widget |

---

## 9. Accessibility

- **Reduce Motion:** All animations → instant transitions.
- **Increase Contrast:** Glass materials → solid backgrounds. Widget borders → thicker, higher contrast.
- **VoiceOver:** Widget containers announce type, title, and current value. Playhead position announced on change.
- **Dynamic Type:** Metric cards and labels respect system text size preferences.
- **Color Blindness:** Semantic metric colors distinguishable in deuteranopia (most common). Chart lines use distinct dash patterns as secondary differentiator.

---

## 10. Platform Strategy

### macOS (Primary — Full Analysis Platform)

- Full keyboard+trackpad workflow. Mouse supported.
- Single-window canvas. All widgets live inside the canvas — **no detached windows**.
- Menu bar integration: standard File/Edit/View menus mirror all keyboard shortcuts.

### Mac + iPad (Extended Canvas)

When an iPad is available (via Sidecar or future custom protocol):

- The canvas extends to the second display. Widgets can be dragged to either screen.
- Alternatively: a specific widget can be sent to the iPad for full-screen display (e.g., video full-screen on iPad, charts on Mac) — but it remains part of the canvas, not a separate window.
- This is a **post-MVP** enhancement. MVP is single-screen Mac only.

### iPadOS (Coach Field Tool)

- **Primary use case:** Coach at the training venue managing athletes and monitoring the ongoing session.
- Touch-first interface optimized for quick glances, not extended analysis.
- Capabilities: session review, basic chart viewing, video playback with metric overlay, athlete roster management.
- **Not** the platform for deep biomechanical analysis — that's the Mac.
- Apple Pencil support for quick notes/annotations (post-MVP).

---

## 11. User Personas & Flow

### Persona A: The Technical Athlete (MVP Primary)

A competitive rower who owns their own data (GoPro + SpeedCoach + possibly Empower oarlock). Technically minded, wants to understand their stroke mechanics, not just see split times.

**Typical flow:**

1. Import session files (MP4 + FIT + CSV) via drag-and-drop
2. App auto-detects sources, creates session, aligns tracks on timeline
3. Opens canvas with default widget layout: 1 video + speed chart + stroke rate chart + metric card (avg split)
4. Scrubs through the session, watching video while reading speed/rate curves
5. Notices a speed drop at 12:30 → zooms the chart, checks stroke rate, sees it was a technical issue not fitness
6. Adds a cue: "Catch timing — handle dipping too early"
7. Adds Empower radar to compare that stroke vs session average
8. Saves session, closes app. Returns tomorrow to review another session.

**What matters:** Speed of import → analysis. Minimal clicks to get to insight. Beautiful but not distracting.

### Persona B: The Intrigued Coach (MVP Secondary)

A rowing coach who has been using CrewNerd or NK LiNK separately. Sees the athlete using RDS and wants to try it. Has more data sources (multiple athletes, multiple sessions per day) but less patience for complex setup.

**Typical flow:**

1. Athlete shares session files (or coach imports from their own devices)
2. Opens session, sees the multi-source integration for the first time ("che figata")
3. Compares 2-3 key metrics across the session
4. Uses cues to mark moments to discuss with athlete
5. Post-MVP: wants multi-athlete comparison, wants to use iPad at the dock

**What matters:** First impression. The app must look and feel like a premium tool that justifies learning a new workflow. Feature requests from coaches will drive post-MVP roadmap.

---

## 12. What's NOT in This Document (Deferred)

- **Export/Print workflow** (PDF report, CSV export UI)
- **Multi-athlete comparison** (side-by-side sessions)
- **Collaboration** (coach ↔ athlete session sharing)
- **Onboarding / First-Run Experience**
- **Settings UI** (preferences panel design)
- **Real-time streaming UI** (post-MVP)
- **Pose estimation overlay** (post-MVP)
- **AI/LLM coaching interface** (post-MVP)
- **iPad coach field tool** (post-MVP, separate design document)

---

## Appendix A: Changes from v1

| Topic | v1 | v2 | Rationale |
| ----- | -- | -- | --------- |
| Design stance | Beauty vs efficiency trade-off | Beauty AND efficiency, non-negotiable | "Le persone mediocri le mettono in contrapposizione" |
| Depth model | 2.5D parallax + DoF blur | Primary/secondary widget tiers by size + visual weight | Captures the intent without GPU cost or spatial confusion |
| Focus mechanism | Focus Groups with DoF blur | Dim non-selected (opacity 30%) | Same goal, 10x cheaper |
| Canvas zoom | Z-axis camera movement | Uniform 2D scale (25%-400%) | Predictable, proven in pro tools |
| Aesthetic reference | Minority Report | DaVinci Resolve + Apple HIG + instrument panels | Mood preserved, mechanisms grounded |
| Timeline | Simple playback bar | NLE multi-track timeline with independent tracks | Essential for multi-camera sync and audio management |
| Video/Audio | Bundled | Separate widgets (video-only + audio waveform) | Multi-camera sessions need independent audio routing |
| Data font | SF Pro Rounded | SF Mono | Tabular alignment for numeric data |
| Glass on data areas | Translucent everything | Glass for panels, solid for data areas | Legibility |
| Annotations | Not discussed | Cue/bookmark markers on timeline | Sufficient for "mark this moment" without frame-level complexity |
| Keyboard shortcuts | Not mentioned | Full shortcut table (J/K/L, M, Space, etc.) | Essential for power users |
| Accessibility | Toggle glass only | Full a11y section | Platform requirement |
| Platform strategy | Not mentioned | macOS primary, iPad = coach field tool, no separate windows | Clear scoping |
| User personas | Not mentioned | Technical athlete (primary) + intrigued coach (secondary) | Drives all design decisions |
| Multi-display | Not mentioned | Canvas extends to iPad (post-MVP), no detached windows | User requirement: everything in the canvas |
