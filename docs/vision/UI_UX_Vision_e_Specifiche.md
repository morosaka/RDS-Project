# RowData Studio — UI/UX Vision & Design System

## 1. Concept & Aesthetic

The target aesthetic is a blend of **"Minority Report" futuristic interfaces** and **Apple's visionOS Glassmorphism**. The interface must feel weightless, dynamic, and focused entirely on data and media, avoiding heavy, traditional macOS chrome where possible.

### The Glassmorphism Principle

- **Materials:** Extensive use of translucent semantic materials (e.g., `regularMaterial`, `ultraThinMaterial`).
- **Depth:** Elements operate on Z-axis layers. The background is deepest, widgets float above, and active controls float highest.
- **Toggles:** The glass effect (transparency/blur) will be toggleable in Settings for users who prefer higher contrast or suffer from visual distraction.

## 2. The Canvas (The Workspace – 2.5D Spatial Architecture)

The core of the app is an infinite 2D spatial canvas enhanced with **2.5D depth perception**.

### Visuals

- **Default Background:** Clean, deep dark gray/black (zero distractions).
- **Optional Backgrounds (Settings):** Light mode, technical millimeter grid (engineering paper style).
- **Extensibility:** The background pattern system will be extensible for future styles.

### The 2.5D Engine & Focus Groups

- **Depth of Field:** Widgets are organized on semantic Z-layers. Widgets not currently in focus are slightly scaled down, pushed to the background, and dynamically blurred (Depth of Field effect).
- **Focus Groups (Multi-Focus):** You can select multiple widgets (e.g., 2 videos and 3 charts) to bring them into a "Focus Group". The selected widgets scale up and move to the sharp foreground (Z=0), while all other irrelevant widgets fade into a blurred, unobtrusive background. This allows distraction-free analysis of specific data combinations.

### Navigation & Zoom Mechanics (Constraint: Predictability)

- **Global Pan/Zoom (Z-Axis):** Pinching directly on the empty canvas navigates the space. Instead of a flat pan, it behaves like moving a camera on the Z-axis. Background widgets scale differently than foreground widgets, creating a parallax effect.
- **Local Zoom (Data - Opt Zoom):** Pinching *inside* a specific widget (like a Line Chart) zooms the temporal X-axis (time) or Y-axis (values) of that specific data view, *without* resizing the widget's physical frame on the canvas.
- *Design Rationale:* This cleanly separates "navigating the 2.5D workspace" from "inspecting the data within a crystal pane."

## 3. Widgets & Arrangement

Widgets are the building blocks of the analysis (Video, Audio, Charts, Maps, Radar).

### Framing & Organization

- **Visuals:** Thin, subtle borders. Floating window appearance.
- **Arrangement Mode:** "Chaotic Neutral to Lawful Good." Widgets can be placed freely anywhere (Minority Report style).
- **Magnetic Snapping:** Widgets snap to each other's edges and to the optional background grid to satisfy users who want perfect alignment. Allows building neat "dashboards" within Focus Groups.
- **Z-Ordering:** Controlled by the 2.5D Focus engine. Clicking a widget (or Shift-clicking multiple) promotes them to the sharp foreground layer.

### Audio Track Support

- **Purpose:** Essential for hearing coach/rower voice notes and verifying synchronization between multiple sources.
- **Representation:** Visualized as a waveform track widget. It can be snapped directly under or above video widgets.
- **Sync:** Fully tied to the universal Playhead. Scrubbing the playhead scrubs the audio, ensuring perfect alignment checks.

## 4. Navigation & Controls (The Tooling)

Traditional top-heavy toolbars are discarded in favor of floating, contextual UI.

### Floating Tools

- Primary controls (Timeline, Play/Pause, Session Picker) are floating panels, completely decoupled from the main canvas.
- **Visibility Toggle:** A dedicated global hotkey (e.g., `Tab`) or a single persistent hidden-until-hover button hides/shows all tools instantly, leaving *only* the data and video on screen for deep focus.

### The Library / Session Picker

- Instead of a traditional macOS sidebar (which grounds the app too much), the Library is a floating, specialized "Drawer" or "HUD" (Heads Up Display).
- It behaves like a transient widget: it appears over the canvas when summoned, and fades out/dismisses when a session is loaded or the user clicks away.

## 5. Interaction & Data Feedback

Performance and clarity are paramount given the high data density (4K video + 200Hz telemetry).

### The Playhead

- **Primary:** A distinct, high-contrast, razor-thin vertical line that slices through all aligned temporal widgets (charts).
- **Synchronization:** Dragging the playhead scrubs the video; playing the video moves the playhead. 1:1 hardware-accelerated sync.
- *(Note on "Magnetic Cursor": we will shelve complex magnetic snapping to data peaks for now to preserve 60fps rendering performance. The focus is a lightweight, instantly responsive playhead).*

### Animations

- **Philosophy:** "Respect the user's time." Animations must be purposeful, fluid, but incredibly fast.
- **Toggles:** "Reduce Motion" system settings will be respected, instantly appearing widgets without scale/fade animations if desired.

## 6. Typography & Color Palette

Inspired by modern Apple HIG and visionOS.

### Typography

- **Primary Headers/UI:** `San Francisco Pro Display` (Clean, elegant, native).
- **Telemetry Data/Numbers:** `San Francisco Pro Rounded` or `San Francisco Mono` (Monospaced styling for data tables so numbers align perfectly vertically, critical for reading rapid telemetry).

### Color Palette

- **Dominant:** Dark, cool tones (Deep Blue/Gray glass).
- **Accents:** Vibrant Orange/Amber for primary selections and the Playhead (high visibility against dark and video).
- **Trace Semantic Colors:** A standardized color-coding system for metrics (e.g., Speed is always Neon Blue, Heart Rate is Crimson, Stroke Rate is Purple) so users instantly recognize data without reading legends.
