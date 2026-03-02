# The Rowing Super App: Vision 3.0 Architecture

## Unified Reactive Graph Engine Fusing 200Hz IMU Telemetry, Monocular Pose Estimation, and Physiological Data on Apple Silicon

**A unified reactive graph engine fusing 200Hz IMU telemetry, monocular pose estimation, and physiological data—delivered through a three-tier progressive UI with agentic AI—can be built today on Apple silicon, but only if the architecture treats the stroke as its atomic unit, the DAG as a multi-rate hierarchy, and the digital twin as an incremental capability earned through data accumulation.** This evolved framework redefines the original vision's nine domains with concrete technology choices, validated algorithms, and a phased build sequence grounded in what Apple hardware actually supports in 2025–2026. The strongest aspects of the current vision—the DAG/whiteboard concept and tiered user model—survive largely intact. The weakest—the digital twin aspiration and pose estimation accuracy expectations—require significant recalibration.

---

## 1. The Reactive Graph Engine Must Be Multi-Rate by Design

The original vision describes a flat DAG of Streams → Transforms → Views. This underestimates the fundamental architectural challenge: **the app simultaneously operates at three temporal scales** (200Hz gesture, ~0.5Hz stroke, and session-level aggregation), and the graph engine must natively accommodate rate-changing nodes rather than treating everything as a uniform stream.

The recommended engine is a **custom DAG scheduler built on top of Apple's Combine framework**. Combine provides first-class backpressure via `Subscribers.Demand`, native SwiftUI integration through `.onReceive()`, and scheduler control for directing work off the main thread—capabilities that RxSwift lacks. Each DAG node wraps a Combine `Publisher` and processing closure; edges are `Subscription` connections. A central coordinator maintains a topological ordering (Kahn's algorithm, O(V+E)) and propagates dirtiness only through affected subgraphs when source data changes.

The graph becomes a **five-level hierarchy** with explicit rate boundaries:

- **Level 0 (Sources, native rate):** `CMMotionManager` at 200Hz, GPS at 1Hz, heart rate at 1Hz, video frames at 30–60fps, GoPro GPMF streams at per-file discovered rates
- **Level 1 (Feature extraction, batched):** Madgwick orientation filter, ring buffers (capacity 2000 for 10s windows), Butterworth low-pass filtering—all processed via Apple's Accelerate/vDSP framework for SIMD-accelerated FFT and statistical operations
- **Level 2 (Event detection, ~0.5Hz):** Stroke segmentation fires per-stroke (~15–45 events/minute across the full range from light paddling to race starts), producing the stroke as the **fundamental anchor entity** across all data modalities
- **Level 3 (Aggregation, 1Hz):** Session metrics, moving averages, W'BAL depletion tracking, cardiac decoupling detection
- **Level 4 (Views, display rate):** UI-bound outputs throttled to display refresh rate

Rate-changing nodes use Combine's `collect(.byCount(200))` or `collect(.byTime(scheduler, .seconds(1)))` to bridge between levels. High-frequency nodes subscribe with `.demand(.unlimited)` backed by ring buffers; low-frequency nodes use standard demand management. This architecture avoids the ECS (Entity Component System) pattern, which excels at cache-friendly batch processing of homogeneous data but is poorly suited to the heterogeneous, variable-rate DAG structure needed here.

### The Display Pipeline: Compute at Full Resolution, Display at Pixel Resolution

A critical architectural principle: **compute at full resolution, display at pixel resolution.** The 200Hz rate matters exclusively for the processing pipeline (Madgwick filter, stroke detection, force curve computation). The display pipeline is bounded by two physical ceilings: temporal (60Hz sustained / 120Hz ProMotion bursts—no human eye or screen benefits from faster rendering) and spatial (1 datapoint per horizontal pixel). On an iPhone 15 Pro (1179px logical width in landscape), any chart needs at most ~1,200 visible points at any zoom level. This means **Swift Charts handles both real-time and post-session rendering comfortably** once proper decimation is in place—no Metal renderer is required.

The key enabling component is a **`DisplayDecimator` node** that sits at the boundary between any Metric Stream and any View in the DAG. It takes viewport width (pixels) and visible time range as dynamic inputs, and outputs exactly the right number of points via MinMaxLTTB. As the user zooms in, the visible time window shrinks, pixel density stays constant, but the underlying data resolution increases automatically—delivering the seamless "scroll the session, click into micro-analysis" experience. Pre-computed resolution tiers during Bronze→Silver processing (session-level at ~1,000 points, segment-level at ~2,000 per 10-min window) serve as fast-path caches; on-demand decimation handles arbitrary zoom levels.

For the real-time in-boat display—which needs minimal chrome (big numbers, simple sparklines)—a lightweight `CADisplayLink`-driven refresh at 60Hz feeds Swift Charts with the last ~5 seconds of data (~300 points after decimation), well within its performance envelope.

**MinMaxLTTB** is the downsampling algorithm of choice over standard LTTB. Its two-step approach (MinMax preselection at 4× target points, then LTTB on the preselected set) is **10x faster** while preserving the acceleration peaks and force-curve troughs that standard LTTB may smooth away. Pre-compute session-level (1,000 points) and segment-level (2,000 per 10-min window) resolutions during Silver processing; compute detail-level on demand.

---

## 2. Sensor Fusion Starts with the Madgwick Filter and Cloud's Kalman

The IMU processing pipeline rests on two validated algorithms that together solve rowing's core sensing challenges.

For **orientation estimation**, the Madgwick AHRS filter with acceleration rejection is the optimal choice. It requires only **109 scalar operations per update** at 200Hz—trivial on A-series silicon—and its single tunable parameter β (recommended **0.01–0.02** for rowing's high-dynamics profile, lower than the default 0.033) makes it far simpler to calibrate than an Extended Kalman Filter's dual covariance matrices. The acceleration rejection feature is critical: during the drive phase, boat acceleration reaches 0.5–1.0g, which a naive filter would misinterpret as a gravity direction change. Madgwick's angular error threshold (set to ~10°) temporarily ignores the accelerometer during these bursts, relying on gyroscope integration alone, then allows accelerometer correction during the calmer recovery phase. The filter outputs quaternion orientation, gravity vector, and linear acceleration with gravity removed—exactly the inputs needed for downstream stroke analysis.

For **GPS-IMU fusion**, Cloud et al.'s 2019 adaptive Kalman filter is the gold standard for smartphone-based rowing. Its three-state model [position, velocity, accelerometer_bias] predicts at 200Hz using the accelerometer and corrects at GPS rate (1–10Hz). The key innovation is real-time estimation of effective accelerometer bias, which captures sensor bias, gravity projection from boat pitch, and periodic remnants. Validated results show **48% improvement in boat speed accuracy and 82% improvement in distance-per-stroke accuracy** over GPS alone. Process noise should be tuned to Q_accel ≈ 0.1 m/s² and Q_bias ≈ 0.001 m/s²/√s; GPS measurement noise at R_pos ≈ 4m for phone GPS, dropping to ~0.5m with an external Bluetooth 10Hz receiver.

For **stroke detection**, the Undecimated Wavelet Transform (UWT) using a biorthogonal 4.4 wavelet at 9-level decomposition achieves ICC >0.95 against instrumented oarlocks for stroke timing, drive timing, and recovery timing across single sculls through eights. For real-time applications, a simpler sliding-window minimum detector on low-pass filtered forward acceleration (Butterworth 4th-order, 5Hz cutoff) reliably identifies the catch—the most stereotypical acceleration feature across all boat classes. The UWT refinement can run post-stroke for sub-phase segmentation.

Rowing-specific metrics derivable from IMU data alone include:

- **Check factor** = σ(v) / μ(v) within each stroke (coefficient of velocity variation; lower = smoother = less drag loss)
- **Propulsive effectiveness** ≈ V_mean² / ⟨V²⟩ (penalizes velocity fluctuation, since drag ∝ V³)
- **Drive:recovery ratio** from stroke phase timing
- **Force curve estimation** via F_net = m_boat × a_measured + F_drag(V), with LSTM networks achieving <5% MAE for gate force reconstruction from IMU+GPS features

Auto-calibration for sensor mounting misalignment uses a brief stationary period at launch to determine gravity direction, followed by PCA over several strokes to identify the boat's longitudinal axis from the dominant acceleration component.

---

## 2.5. The Real-World Data Landscape: GoPro GPMF and NK SpeedCoach

The architecture must be grounded in the actual data sources that rowers use today, not idealized sensor configurations. Two discoveries fundamentally shape the ingestion layer.

### GoPro as the Entry-Level "Swiss Army Knife"

A GoPro action camera mounted on the boat provides, from a single device at consumer price point, a remarkably complete sensor package: synchronized video + ACCL + GYRO + GRAV (at frame rate) + GPS5 (lat, lon, alt, 2D speed, 3D speed), all embedded in the MP4 file as a GPMF telemetry track alongside video, audio, and timecode. This is architecturally significant for three reasons:

1. **Single-device video-IMU synchronization is free.** Because GPMF telemetry and video share the same MP4 container with a common timecode track, the temporal alignment between sensor data and video frames is inherent—no external sync hardware or cross-correlation is needed. This eliminates what the Vision 2.0 document identified as one of the hardest problems in multi-modal fusion.

2. **Axis calibration is simplified.** The camera's known mounting orientation (typically facing forward or backward on the deck) provides a reference frame that the user can visually verify: "the video shows straight ahead, so +Z is forward." This is far more intuitive than calibrating an arbitrary IMU box. The GRAV stream (gravity vector at frame rate) directly provides the tilt reference, and the camera's own image stabilization metadata (CORI/IORI quaternions in newer GoPro models) provides additional orientation data that could bootstrap the Madgwick filter.

3. **The "bring your GoPro" onboarding path** is vastly simpler than "bring your own sensor." Most competitive rowers already own a GoPro for filming technique. The app's entry-level story becomes: "Mount your GoPro, row, import the video—we extract everything."

However, GoPro data introduces specific challenges the architecture must handle:

- **Actual sample rates must be discovered per file, not assumed from spec.** GoPro's GPMF documentation lists nominal rates (e.g., GYRO "up to 400Hz," ACCL "~200Hz," GPS "18Hz"), but real-world measurement reveals these are unreliable. In testing, two units of the same GoPro model produced ACCL at 197.36Hz and 198.45Hz respectively—and critically, GYRO ran at the **same rate as ACCL** (~197-198Hz), not the 2× multiple the spec implies. GPS nominal 18Hz measured at ~10Hz in practice. Rates can vary not just between camera units but between recording sessions on the same unit (firmware state, thermal conditions, battery level may all play a role). **The architecture must treat every GPMF file as self-describing**: at parse time, the Source Adapter counts actual samples within each MP4-indexed time window to compute the true sample rate, and propagates this measured rate downstream as metadata. No node in the DAG may assume a hardcoded rate for any GoPro stream.
- **GPMF extraction requires MP4 parsing.** The GPMF track is embedded as a fourth track in the MP4 container. The open-source `gpmf-parser` (C) and `gopro-telemetry` (JavaScript) libraries handle extraction, but a Swift-native parser is needed for on-device import without shelling out to external tools. The GPMF KLV (Key-Length-Value) format is simple enough to implement natively.
- **Data is post-session only.** Unlike a phone's CoreMotion, GoPro data is not available in real-time via Bluetooth or WiFi during rowing. GoPro is exclusively a Bronze-layer capture device—import happens after the session via SD card or WiFi transfer.

The Source Adapter pattern in the DAG must abstract away these differences. A `GoPro_GPMF_Source` node and a `CoreMotion_Source` node both output the same canonical stream types (linear acceleration, angular velocity, GPS position), but with different actual sample rates and timing characteristics. Downstream transform nodes must be rate-agnostic.

### NK SpeedCoach GPS Model 2: The Variable-Rate Challenge

The NK SpeedCoach GPS Model 2 is the industry-standard performance monitor in competitive rowing. Its data export (via NK LiNK as CSV or FIT) provides **stroke-sampled data**: one row per stroke, with each row containing elapsed time, split (speed), stroke rate, distance, heart rate, and optionally EmPower oarlock data (power, catch/finish angles, slip). This creates a fundamental architectural problem:

**Stroke-sampled data has variable sample intervals.** At 20 SPM, samples arrive every 3.0 seconds. At 40 SPM, every 1.5 seconds. During a rate change from 20 to 40 SPM within a single piece, the sample interval halves. This is not a fixed-rate stream that can be processed with standard DSP tools—it is an **event-sampled signal** indexed by stroke number, not by time.

This has proven particularly hard to reconcile with the fixed-rate streams from other sources. A 60-minute session generates:

| Source | Nominal Rate | Measured Rate | Samples/Hour | Timing |
| --- | --- | --- | --- | --- |
| GoPro ACCL | "~200 Hz" | 197–199 Hz* | ~710,000* | Fixed (per file) |
| GoPro GYRO | "up to 400 Hz" | 197–199 Hz* | ~710,000* | Fixed (per file, often = ACCL rate) |
| GoPro GPS | "18 Hz" | ~10 Hz* | ~36,000* | Fixed but unreliable |
| GoPro GRAV | Frame rate | 24–60 Hz | 86,400–216,000 | Variable by frame rate |
| NK SpeedCoach | Per stroke | 15–45 SPM | ~900–2,700 | Variable by stroke rate |
| HR strap (BLE) | ~1 Hz | ~1 Hz | ~3,600 | Fixed |

\* All GoPro rates are indicative. Actual rate varies per camera unit, per session, and must be measured from each file at parse time.

The DAG engine must therefore support **three stream types**, not one:

1. **Time-sampled streams** (fixed rate): ACCL, GYRO, HR. Standard ring buffers, Combine `collect(.byTime())`. The measured-vs-nominal rate discrepancy (197.36 vs 200Hz) requires that all timestamps use actual `mach_absolute_time()` or GPMF STMP timestamps, never assumed intervals. Interpolation between sources uses timestamp matching, not sample-index matching.

2. **Time-sampled streams (variable rate)**: GRAV (frame-rate dependent), GPS (nominally fixed but with real-world gaps and jitter). These need explicit timestamp per sample and nearest-neighbor or linear interpolation when consumed by fixed-rate nodes.

3. **Event-sampled streams** (stroke-indexed): NK SpeedCoach data, and also the app's own derived per-stroke metrics. These are indexed by stroke number with an associated timestamp, but have no meaningful "sample rate." They cannot be filtered, FFT'd, or processed with time-domain DSP.

The architectural solution is a set of **boundary nodes** that convert between stream types:

- **`EventToTimeSeries` node**: Takes stroke-sampled data + a target time grid, produces interpolated time series (linear interpolation for speed/distance, step-hold for discrete values like stroke rate). Essential for overlaying NK SpeedCoach data on GoPro IMU time series in the same chart.
- **`TimeSeriesToPerStroke` node**: Takes a fixed-rate stream + stroke boundary timestamps, produces per-stroke aggregates (mean, peak, RMS, area under curve). This is how 200Hz acceleration data becomes "check factor per stroke" aligned with NK SpeedCoach stroke numbers.
- **`ResampleTimeSeries` node**: Takes a variable-rate time series and outputs at a target fixed rate via interpolation. Needed to normalize GRAV and GPS before feeding into the Madgwick filter or Kalman fusion.

All three conversion nodes must be explicitly represented in the DAG—they are not invisible plumbing. In the Rack UI, a coach sees "NK SpeedCoach → Interpolate to 1Hz → Overlay with GoPro Speed" as a visible processing step, making the data alignment transparent rather than magical.

The per-stroke summary table in the Silver layer (Section 6) becomes even more critical here: it is the **universal join key** that aligns NK SpeedCoach stroke N with GoPro IMU data from timestamp T₁ to T₂ with video frame range F₁ to F₂. The stroke detection algorithm (Section 2) running on GoPro IMU data produces the same stroke segmentation that the NK SpeedCoach uses internally, enabling cross-validation between the two sources.

### Implications for the Source Adapter Catalog

The Bronze layer's Source Adapter pattern must include at minimum:

| Adapter | Input Format | Output Streams | Timing Model |
| --- | --- | --- | --- |
| `GoPro_GPMF` | MP4 file (GPMF track) | ACCL, GYRO, GRAV, GPS5 | Post-session, per-file discovered rates |
| `CoreMotion_Live` | iOS CMMotionManager | ACCL, GYRO, GPS | Real-time, fixed rate |
| `NK_SpeedCoach_CSV` | CSV (via LiNK export) | Speed, Rate, Distance, HR, Power* | Post-session, stroke-sampled |
| `NK_SpeedCoach_FIT` | FIT file (via LiNK export) | Speed, Rate, Distance, HR, Power* | Post-session, stroke-sampled |
| `FIT_Generic` | FIT file (Garmin, Polar, etc.) | HR, Power, Cadence | Post-session, fixed 1Hz |
| `BLE_HR_Live` | Bluetooth LE HR strap | HR, RR intervals | Real-time, ~1Hz |

*Power and angle data available only with EmPower Oarlock add-on.

Each adapter is responsible for emitting data with **accurate, source-specific timestamps** (not assumed intervals), declaring its timing model (fixed/variable/event), and tagging each sample with a source provenance ID for downstream data quality tracking.

---

## 3. Pose Estimation Is Coaching-Grade, Not Clinical-Grade — And Camera Angle Is the Binding Constraint

The current vision's pose estimation ambitions need tempering with realistic accuracy expectations. **On-device monocular pose estimation can reliably measure trunk inclination (±5–8°) and detect gross technique patterns, but cannot achieve the ±5° clinical precision needed for detailed joint biomechanics.** This is still enormously useful for coaching — but only if the camera sees the right plane of motion.

### The View Angle Problem

The biomechanically meaningful metrics listed in this section — trunk inclination/layback, hip flexion, body preparation sequence — are all **sagittal-plane measurements**. They require a side (lateral) view of the rower. Research on camera angle effects on pose estimation validity (Sensors, 2025) confirms that accuracy degrades substantially when the primary movement plane is not perpendicular to the camera's line of sight, and that the fewest keypoint occlusions occur when the camera faces the movement plane directly.

On a rowing boat, however, the only practical fixed camera positions are **bow-facing-aft or stern-facing-forward** — both giving a frontal or dorsal view. This is nearly orthogonal to the sagittal plane. The rower's hip flexion, trunk layback, and knee drive all occur along the boat's longitudinal axis and are foreshortened to near-invisibility from an end-on camera.

This means the document must be honest about **what each view can and cannot measure**:

**Frontal/Dorsal view (on-boat GoPro, bow or stern mount):**

- ✅ Shoulder height symmetry (left vs. right, critical in sculling)
- ✅ Lateral body sway / lean
- ✅ Hand height differential at catch and finish
- ✅ Head position (looking straight vs. tilting)
- ✅ Timing symmetry between left and right arms (sculling)
- ✅ Catch timing across crew members (multi-seat boats with wide-angle lens)
- ❌ Trunk inclination / layback angle
- ❌ Hip flexion range
- ❌ Knee compression at catch
- ❌ Body preparation sequence (arms-away → body-rock-over → slide)
- ❌ Layback progression through the drive

**Lateral/Side view (required for sagittal-plane biomechanics):**

- ✅ Trunk inclination / layback angle (largest angular range, most reliable measurement)
- ✅ Hip flexion (primary power generation indicator)
- ✅ Body preparation sequence on recovery
- ✅ Catch body position (shin angle, forward lean)
- ✅ Drive sequence visualization
- ✅ Slide timing (when the seat moves relative to handle movement)
- ❌ Left/right symmetry
- ❌ Lateral sway

The architecture should therefore present frontal/dorsal metrics as "symmetry and timing analysis" and sagittal metrics as "technique geometry analysis" — two distinct and complementary capability modules, each explicitly tagged with its required camera position.

### Obtaining a Lateral View: Three Approaches

**Approach 1: Coaching launch (traditional).** A coach in a motorboat alongside the rower films from the side. This is the gold standard for technique video in competitive rowing — it provides a stable, perpendicular, side-on view at 3–5m distance. The camera (phone or GoPro) captures the ideal sagittal view. However, this requires a second person, a powered launch, and favorable water conditions. It is available at organized training sessions but not for solo practice.

**Approach 2: Follow-me drone in lateral tracking mode.** A DJI Neo 2 (151g, ~$200, 4K/60fps, omnidirectional obstacle sensing) in "Parallel" ActiveTrack mode maintains a constant angle and distance from the side of a moving subject — precisely the lateral view needed for sagittal-plane biomechanics. Key viability factors for rowing:

- **Speed ceiling is adequate.** The Neo 2 tracks at up to 12 m/s (43 km/h). Competitive single-scull race pace is ~5–5.5 m/s; even a coxless four at full race pressure rarely exceeds 6 m/s. The drone has ample speed headroom.
- **Flight time is limiting but workable.** 19 minutes covers a 2K race piece or a substantial interval set, but not a full 90-minute practice. With the Fly More Combo (3 batteries), ~57 minutes of total flight time is available, swapping batteries between pieces.
- **Open water is ideal for obstacle avoidance.** Unlike forest trails or urban environments where the Neo 2 may get confused, a rowing course is an unobstructed flat plane — the simplest possible tracking environment.
- **Lateral wind is the risk.** Rowing venues can be windy; the Neo 2's Level 5 wind resistance (10.7 m/s / 38 km/h) is adequate for moderate conditions but may falter in strong crosswinds.
- **Regulatory considerations vary by venue.** Drone use over or near water, near other boats, and at organized events is subject to local regulations. Many rowing venues already prohibit or restrict drones. This limits drone footage to specific training venues and conditions.
- **No embedded telemetry comparable to GoPro GPMF.** The Neo 2 captures video-only (no accessible IMU telemetry in a parseable format). All biomechanical inference must come from pose estimation on the video frames, with no accelerometer cross-validation.

**Approach 3: Fixed bank-side camera.** At venues with a straight, accessible bank (e.g., Rotsee, Dorney Lake), a tripod-mounted camera at the 1000m mark captures side-on video as the boat passes. This provides excellent sagittal-plane footage for the ~20–30 seconds the rower is in frame, but only a slice of the session. Useful for periodic technique checks, not continuous monitoring.

### Multi-Video Synchronization Architecture

The drone option (and to a lesser extent, coaching launch video) introduces a fundamental new requirement: **multi-source video synchronization**. The system must handle:

1. **On-boat GoPro** (frontal/dorsal view + GPMF telemetry) — provides the master timeline via embedded ACCL/GYRO/GPS timestamps.
2. **Drone or external camera** (lateral view, video-only) — no shared clock, no embedded telemetry.

Temporal alignment between these sources requires cross-modal synchronization. Several approaches, in order of reliability:

- **Audio cross-correlation.** Both devices record ambient sound (oar splash, slide clunk, coach calls). Cross-correlation of audio waveforms achieves sub-frame alignment (±10–30ms). This is the most robust method when both sources have audio tracks, and is a well-established technique in multi-camera video production. The GoPro's audio track and the drone's audio track (which will include propeller noise, but the rowing sounds are still detectable underneath) can be aligned automatically.
- **Visual event matching.** The catch splash — a high-contrast visual event visible from any angle — occurs at a precise instant. Detecting splash timing in both video streams provides manual or semi-automatic sync points. Multiple catch events across a piece provide redundant alignment and can compensate for clock drift between devices.
- **GPS timestamp matching.** If the drone records GPS metadata in its video file (DJI drones typically embed GPS in EXIF/XMP), coarse alignment (±1s) can be achieved by matching GPS timestamps, then refined by one of the above methods.
- **IMU-to-visual-motion correlation.** The GoPro's embedded ACCL data produces a clear stroke-periodic signal. Optical flow computed from the drone's lateral video also produces a stroke-periodic signal (the rower's body oscillates fore-and-aft). Cross-correlation of these two periodic signals provides automatic alignment without requiring audio. This is the most architecturally elegant solution and should be the target for V2.

The DAG must accommodate multi-video as a first-class concept:

- A `VideoSource` node declares its view angle (frontal, dorsal, lateral, aerial) and its timing basis (embedded GPMF, GPS-only, audio-synced, manual offset).
- A `VideoSync` node takes two or more `VideoSource` streams plus the master timeline (from the telemetry-bearing source) and outputs frame-aligned multi-view access.
- The Rack UI presents synchronized multi-angle playback: scrubbing the timeline moves all video views in lockstep. A stroke-by-stroke scrubber (linked to the per-stroke summary table) jumps all views to the same stroke.
- Pose estimation runs independently on each video stream, producing view-specific metrics. The system does **not** attempt to fuse 2D poses from multiple views into a single 3D reconstruction (this is a research-grade problem that adds enormous complexity for marginal gain over independent per-view analysis at coaching-grade accuracy).

### Recommended Primary Pipeline

Given these constraints, the recommended primary pipeline is **Apple Vision `VNDetectHumanBodyPose3DRequest`** (iOS 17+), which returns 17 joints in 3D with `simd_float4x4` matrices and runs on the Neural Engine at 30+ fps on A14+ chips. On iPad Pro with LiDAR, it provides metric (meters) depth estimation rather than assumed body proportions. MediaPipe BlazePose serves as a cross-platform fallback with 33 landmarks and has been validated for rowing in the ARrow system (Harvard/ETH Zurich, Eurographics 2023). For post-session enhanced analysis, lightweight 2D→3D lifting models — MotionAGFormer-XS or the newer Mamba-based Pose3DM (only **2.8M parameters**, 82.5% fewer than MotionBERT) — can batch-process recorded video with physics-informed refinement enforcing bone-length constraints and rowing-specific joint angle limits.

For frontal/dorsal views (on-boat GoPro), pose estimation should focus on **symmetry metrics**: bilateral comparison of shoulder/hand keypoint heights and timing, lateral trunk deviation from the boat's centerline. For lateral views (drone or coaching launch), pose estimation targets the **sagittal-plane technique metrics**: trunk inclination, hip flexion, body preparation sequence. The ARrow system demonstrated that heuristic rules on body angles and handle direction changes can detect all four stroke phases with sufficient accuracy for coaching feedback from lateral video.

**IMU-pose fusion** is where the real power emerges. IMU provides sub-millisecond timing precision for catch/finish events; video provides the spatial body configuration that IMU alone cannot capture. The recommended V1 approach is post-hoc fusion with timestamp-based alignment using shared `mach_absolute_time()` for on-device camera (both camera and CoreMotion reference the same clock on iPhone), or audio/visual cross-correlation for external cameras (GoPro, drone). Future versions can graduate to real-time Kalman fusion following the FusePose architecture (IEEE TMM 2022), where IMU bone vectors merge with vision-detected 3D positions through kinematic-space fusion layers.

A crucial insight from the ARrow team: for perpendicular side-view cameras, **2D angle computation is actually more reliable than 3D** because there is no depth ambiguity in the primary measurement plane. They recommend averaging 2D and 3D angle estimates. This further validates the approach of treating lateral video as a 2D sagittal-plane analysis rather than attempting full 3D reconstruction.

---

## 4. Agentic AI Should Generate DSL, Not Raw Code

The AI integration layer is where the current vision's ambition most exceeds current reliable capabilities—but a carefully structured architecture makes it viable. The critical finding from the Prompt2DAG research (2025) is that **deterministic template-based pipeline generation achieves 92.3% success, while purely LLM-driven end-to-end generation achieves only 29.2%.** The architecture must therefore separate language understanding (where LLMs excel) from pipeline construction (where deterministic templates excel).

**LangGraph** is the recommended orchestration framework. Its native graph-based state machine directly mirrors the app's Streams → Transforms → Views DAG, and its explicit branching, time-travel debugging, and LangSmith observability address the production reliability requirements that CrewAI and AutoGen lack. The multi-agent architecture should include:

- **Pipeline Generation Agent:** Translates natural language to a rowing-domain DSL that compiles to DAG node configurations. Uses RAG against a vector store of all available transforms (stroke segmentation, force curve analysis, efficiency metrics, etc.) to match intent to existing operators before attempting to create new ones.
- **Coaching Insight Crew** (CrewAI subsystem with role-based agents): Technique Analyst, Training Load Monitor, Recovery Advisor. Each draws from a RAG knowledge base of rowing biomechanics literature (Kleshnev's corpus, FISA guidelines, physiological training principles) and receives pre-processed metrics (not raw data) as context.
- **Data Quality Agent:** Statistical anomaly detection on stroke metrics (Z-score, Isolation Forest) plus schema drift detection for firmware updates that change sensor data formats.

The on-device vs. cloud split is decisive for the on-water use case. **Apple Foundation Models** (iOS 26+, ~3B parameters, free inference, fully offline) handle real-time workout summaries, basic anomaly alerts, and simple natural-language queries. Complex pipeline generation, multi-session trend analysis, and RAG-based coaching Q&A route to cloud LLMs (GPT-4o/Claude) with **500ms–2s round-trip latency**, acceptable only post-session. The hybrid pattern: process raw sensor data on-device, sync processed metrics to cloud, generate insights in cloud, cache insights on device.

For the Consumer tier, pre-built natural language templates ("Show me my stroke rate trend over the last 5 sessions") map to pre-defined query patterns with guardrails preventing hallucinated queries. For the Power User tier, the LLM operates as a schema-aware SQL/DSL agent with visual confirmation before execution. For the Architect tier, AI assists DAG construction: the user describes an analysis in natural language, the system suggests node configurations, and a sandboxed verification agent tests the pipeline before deployment—following the DataFlow-Agent pattern of 7 specialized agents.

---

## 5. The Digital Twin Is a Four-Tier Staircase, Not a Single Leap

The current vision's "Digital Twin aspirations" need reframing from an aspirational moonshot into an **incremental capability ladder**, where each tier delivers immediate user value while accumulating the data needed for the next tier. The Boillet et al. (2024) cycling digital twin—which validated a Margaria-Morton 3-component model against field performance with ~15% average error—is the closest existing template.

**Tier 1: Pacing Calculator (weeks to build).** Requires only 2–3 maximal ergometer efforts to calibrate Critical Power (CP) and W' (anaerobic work capacity). The core equation T_lim = W' / (P - CP) combined with a cubic drag model (P = c·v³) enables "what-if" pacing simulation: "What happens if I start at 105% CP for the first 500m?" Forward Euler integration at 1s timesteps produces predicted split times within ~2% of actual. This alone answers the most common pacing question with physiological grounding.

**Tier 2: Training Load Monitor (1–3 months).** Adds Banister Fitness-Fatigue Model (FFM) with Kalman filter extensions for optimal state estimation. Performance = P₀ + k₁·Fitness - k₂·Fatigue, with typical time constants τ₁ ≈ 45 days (fitness) and τ₂ ≈ 12 days (fatigue). Includes ACWR calculation (sweet spot **0.8–1.3**, danger zone >1.5) and cardiac decoupling detection (efficiency factor declining >5% signals fatigue). Data requirements: daily session RPE, duration, power/pace, heart rate—all available from consumer sensors.

**Tier 3: Physiological Digital Twin (3–6 months).** Implements the full Margaria-Morton 3-tank energy model: aerobic (rate-limited by VO₂max ≈ 6.0–6.6 L/min in elite male rowers), anaerobic lactic (~15–20 kJ capacity), and anaerobic alactic (~5–8 kJ, fast PCr recovery). W'BAL tracking (Skiba et al., 2014) provides real-time fatigue monitoring during interval training. Optimal pacing can be computed via numerical optimization (gradient descent or pseudo-spectral methods, as demonstrated for cross-country skiing in Nature 2022, reducing race times by 12.6s). VO₂max can be estimated from 2000m ergometer power via validated regression; lactate threshold approximated at ~85% of 2000m HR.

**Tier 4: Full Digital Twin (6–12+ months).** Couples biomechanical and physiological models through the power-velocity relationship: physiological model outputs available P(t) → biomechanical model converts to boat velocity v(t) via ITTC drag model → integration yields distance/time predictions. The biomechanical subsystem models the boat-oar-rower interaction using TU Delft's findings that quadriceps deliver >25% of power while glutes and hamstrings fatigue most despite producing less. ML-based injury prediction (Random Forest/XGBoost on ACWR, training monotony, HRV, and injury history) requires ≥1 season of accumulated data per athlete.

Consumer-grade sensors (phone IMU + GPS + Bluetooth HR strap) are **sufficient for Tiers 1–3**. Only Tier 4 benefits substantially from lab-grade equipment (instrumented oarlocks, gas exchange analyzers), though even here, estimated values from field data provide useful approximations.

---

## 6. Data Architecture: SQLite for Speed, DuckDB for Insight

The data volume math is favorable: a 60-minute 200Hz session generates only **~32MB of raw IMU data** (9 channels × 4 bytes × 200Hz × 3600s), well within iPhone memory and storage constraints. The real challenge is architectural—separating the hot capture path from the cold analysis path while maintaining the Bronze-Silver-Gold maturity model.

**Bronze layer (real-time capture):** Direct SQLite via GRDB.swift in WAL mode. Pack 200 samples × 9 channels into a single **7.2KB BLOB per second**, reducing row count from 720,000 to 3,600 per session. This is the single most important optimization—it reduces write overhead by 200x while preserving all raw data for reprocessing. Video stores as H.264/HEVC `.mov` on the filesystem (never in the database); FIT files store as raw binary BLOBs alongside parsed JSON.

**Silver layer (cleaned, aligned):** Unified 1Hz time series with all sensors aligned to common timestamps. The **per-stroke summary table** serves as the anchor entity that unifies all data modalities—each stroke links to IMU chunks (via timestamp range), video (via `video_frame_offset_ms`), FIT data, and pose estimation results. Temporal alignment between camera and CoreMotion is free on iPhone (both reference `mach_absolute_time()`).

**Gold layer (analytics):** **DuckDB** for columnar OLAP queries. DuckDB has been proven on iPhone 16 Pro running TPC-H SF100 benchmarks—it is a production-ready mobile analytical engine. Its vectorized execution and Apache Arrow integration enable sub-second cross-session aggregations, power-duration curve computation, and trend analysis that would be painfully slow in row-oriented SQLite.

For sync, **CKSyncEngine** (iOS 17+) handles session metadata, athlete profiles, and annotations—small records well within CloudKit's 1MB limit. Large data (sensor bundles, video) transfers via **Multipeer Connectivity** (Bonjour/peer-to-peer WiFi) for direct iPhone→Mac transfer post-session, requiring no internet. The rowing session is fundamentally **write-once** from the capture device, eliminating true sync conflicts for raw data. Annotations use last-writer-wins with device-id + timestamp.

---

## 7. Three UIs United by a Single Transformation Grammar

The three-tier UX model—Consumer dashboard, Power User rack, Architect node editor—is the vision's strongest conceptual contribution. Research validates the progressive disclosure approach and provides concrete design models.

**Consumer (Athlete):** A clean dashboard with **3–5 glanceable KPI cards** (split time, stroke rate, heart rate, distance/stroke, efficiency score). Large, high-contrast numbers. Color-coded zones (green = target, amber = drifting, red = off-target). One-tap drill-down to charts. This maps to the STATSports Apex model that democratized GPS tracking for individual athletes.

**Power User (Coach Rack):** Vertical channel strips, one per rower in crew boats (seats 1–8), inspired by Ableton Live's Session View rather than Propellerheads Reason's literal skeuomorphism. Each strip shows real-time metric readout, mini sparkline, color-coded status indicator, and a stack of analysis modules (raw → filtered → derived). Cross-strip "cable patching" enables crew synchronization analysis. The rack metaphor should reference something familiar to coaches—a **crew lineup/boat configuration**—not audio production equipment.

**Architect (Node Editor):** Start with Orange Data Mining's widget-based simplicity and grow toward KNIME's component depth. Pre-built analysis widgets (Data Source → Filter → Transform → Visualize) snap together with **typed, color-coded ports** that prevent invalid connections (à la the Flume React library). Template DAGs for common analyses ("Crew Synchronization Analysis," "Fatigue Detection Pipeline") teach through deconstruction. Live data preview at each node shows what each transformation step does to the data. DaVinci Resolve provides the definitive progressive model: basic effects on the Edit page (Consumer), node-based color on the Color page (Power User), full compositing on the Fusion page (Architect).

**Sonification is a first-class feature, not a gimmick.** Schaffert et al.'s rowing-specific research conclusively demonstrates that **mapping boat acceleration to audio pitch improves boat speed, increases distance per stroke, and enhances crew synchronization.** The real-time feedback hierarchy should prioritize audio (bone conduction headphones for safety) and haptic (wrist-tap cadence from Apple Watch) over visual, because during active rowing, visual attention must be on the water. Detailed visual feedback is reserved for rest intervals and the dock. The feedback priority order: (1) pitch-mapped acceleration sonification, (2) rhythmic crew-sync audio, (3) haptic stroke-rate cadence, (4) peripheral screen-edge color, (5) glanceable split/rate numbers.

For iPad post-session analysis, **Apple Pencil annotation directly on charts** lets coaches circle technique issues, draw arrows, and add handwritten notes attached to specific timestamps. Semantic zoom on the timeline scrubber—pinch to transition between session, piece, and stroke views—exploits the natural touch vocabulary.

---

## 8. What the Current Vision Misses and What Transforms the Approach

### Gaps in the Current Vision

- **Battery is the binding constraint, not compute.** The vision focuses on computational feasibility but underestimates that continuous GPS + IMU + screen consumes 40–60% of an iPhone charge in 60 minutes. Battery management (screen dimming, sensor duty cycling, GPS rate reduction) must be a first-class architectural concern with explicit thermal-state monitoring via `ProcessInfo.processInfo.thermalState`.
- **The stroke, not the sample, is the atomic unit.** The vision's DAG operates on continuous streams, but every downstream consumer—coaching insights, digital twin, visualization—ultimately indexes on strokes. The per-stroke summary row should be the universal join key across all data modalities.
- **Pose estimation accuracy is overestimated.** A rigorous 2025 Nature study (Rode et al., 2.2M frames) measured 3D MPJPE of **146–249mm** and knee flexion MAE of **14.1–25.8°** for monocular 3D estimation. The vision should frame pose estimation as "coaching-grade pattern detection" rather than "biomechanical measurement."
- **HealthKit is unavailable on iPad.** The desktop analysis module on iPad cannot directly access HealthKit data. All physiological data must route through iPhone sync.

### Strongest Aspects of the Current Vision

- **The DAG/whiteboard concept is architecturally sound** and maps cleanly to both reactive programming (Combine) and topological scheduling. The Streams → Transforms → Views abstraction is the right level of generality.
- **Three user tiers align with research-validated progressive disclosure patterns** and have clear precedent in professional creative tools.
- **Bronze-Silver-Gold data maturity** is a proven pattern from data engineering that gives the system self-healing capabilities—reprocessing Silver/Gold from immutable Bronze fixes any processing bugs retroactively.
- **AI as pipeline generator rather than black box** is the correct framing—LLMs excel at intent translation, not direct sensor processing.

### Novel Approaches from Adjacent Domains

- **F1 telemetry's dual-axis views** (time-indexed vs. distance-indexed) should be adopted. Rowing coaches toggle between "what happened at minute 5?" (time) and "what happened at the 1000m mark?" (distance).
- **WKO5's power-duration curve modeling** should be adapted as a "boat speed duration curve" or "stroke efficiency duration curve"—individualized, model-driven analytics that reveal physiological thresholds specific to each rower.
- **Cycling's CTL/ATL/TSB framework** (TrainingPeaks' Performance Management Chart) is directly applicable to rowing training load management and should be implemented as a standard Gold-layer metric.

### Emerging Technologies That Transform the Roadmap

- **Apple's M5 chip** (October 2025) places Neural Accelerators in each GPU core, delivering 4× peak AI compute over M4. Combined with the Foundation Models framework providing **free on-device LLM inference** on 3B-parameter models, post-session coaching insights can run entirely on-device without cloud dependency or cost.
- **Ultra-wideband (UWB) sensors** could provide sub-centimeter oar blade tracking. UWB anchors on a coaching launch with tags on each blade would enable complete 3D stroke reconstruction—a medium-term hardware integration opportunity.
- **On-device LLMs** (Apple Foundation Models, ~3B params) enable offline natural-language workout summaries and basic coaching queries during on-water sessions. The hybrid on-device/cloud pattern becomes: real-time sensing and basic AI on-device, complex reasoning and RAG in the cloud.

---

## 9. Implementation Phasing and Technology Stack

The build sequence follows the data maturity model—Bronze capabilities first (capture and store everything), Silver next (clean and align), Gold last (derive insights). Each phase delivers immediate user value.

**Phase 1 (Months 1–3): Capture Engine and Consumer Dashboard.**
Build the Combine-based DAG scheduler with Level 0–2 nodes (sensor sources through stroke detection). Implement SQLite Bronze storage with BLOB packing. Deploy Madgwick filter and Cloud's Kalman filter for GPS-IMU fusion. Ship the Consumer dashboard with real-time stroke rate, split time, and heart rate via Swift Charts fed by `CADisplayLink` at 60Hz with `DisplayDecimator` node. Implement sonification (pitch-mapped acceleration). Battery budget management as first-class concern.

**Phase 2 (Months 3–6): Silver Processing and Coach Rack.**
Build the Silver pipeline (stroke alignment, 1Hz unified time series, per-stroke summaries). Implement the Rack UI with per-rower channel strips. Add DuckDB Gold layer for cross-session queries. Integrate Apple Vision pose estimation with post-hoc IMU fusion. Deploy MinMaxLTTB visualization with semantic zoom via `DisplayDecimator`. Implement CKSyncEngine + Multipeer Connectivity for device sync.

**Phase 3 (Months 6–9): Digital Twin Tiers 1–2 and AI Layer.**
Implement CP/W' pacing calculator and Banister FFM training load monitor. Build LangGraph orchestrator with Pipeline Generation Agent and NL Query Agent. Deploy RAG-based coaching insight engine. Add ACWR injury risk monitoring. Ship the Architect node editor with template DAGs and typed ports.

**Phase 4 (Months 9–12+): Advanced Capabilities.**
Implement Margaria-Morton 3-tank physiological model and race simulation engine. Deploy self-healing pipeline monitoring. Fine-tune rowing-specific LoRA adapters for on-device LLM. Add ML-based injury prediction (requires accumulated data). Integrate UWB blade tracking if hardware becomes available.

### Technology Stack

| Layer | Technology | Rationale |
|---|---|---|
| Reactive pipeline | Combine + custom DAG scheduler | Native backpressure, SwiftUI integration, topological dirty propagation |
| IMU fusion | Madgwick AHRS (β=0.015) + Cloud Kalman | Validated for rowing, minimal compute, acceleration rejection |
| Stroke detection | Peak detection (real-time) + UWT (post-stroke) | ICC >0.95 vs instrumented oarlocks |
| Pose estimation | Apple Vision 3D (primary) + BlazePose (fallback) | Native Neural Engine, 17/33 joints, 30+ fps |
| Signal processing | Accelerate/vDSP | Hardware SIMD for FFT, filtering, statistics |
| Real-time charts | Swift Charts + CADisplayLink @ 60Hz | DisplayDecimator ensures ≤1,200 points per viewport width |
| Post-session charts | Swift Charts + MinMaxLTTB | Pre-computed resolution tiers, semantic zoom on demand |
| Downsampling | MinMaxLTTB (custom Swift) | 10× faster than LTTB, preserves peaks and troughs |
| Bronze storage | SQLite (WAL, BLOB-packed via GRDB.swift) | 3,600 rows/session, proven write performance |
| Gold analytics | DuckDB (Swift client) | Columnar OLAP, proven on iPhone, sub-second aggregation |
| Metadata sync | CKSyncEngine | Apple-supported, conflict handling, push notifications |
| Large data sync | Multipeer Connectivity | Peer-to-peer WiFi, no internet required, fast |
| On-device AI | Apple Foundation Models + Core ML | Free inference, offline capable, ~3B params |
| Cloud AI | LangGraph + GPT-4o/Claude | Complex reasoning, RAG, pipeline generation |
| ML training | Create ML Activity Classifier | Purpose-built for IMU classification, tiny models |
| Physiological models | CP/W'BAL + Banister FFM + Margaria-Morton | Validated across endurance sports, incrementally deployable |

---

## 10. Conclusion: From Vision to Executable Architecture

The rowing Super App's conceptual foundation is sound—the DAG abstraction, the tiered user model, and the Bronze-Silver-Gold data maturity all survive scrutiny and have strong precedent in adjacent domains. Three evolutionary shifts move the architecture from vision to execution.

First, **the multi-rate hierarchical DAG** replaces the flat reactive graph, with the stroke as the universal join key and explicit rate-changing nodes bridging 200Hz capture to 0.5Hz stroke events to session-level aggregation. This is not a refinement of the original concept—it is a structural prerequisite that the original vision's uniform-stream model does not address.

Second, **the digital twin becomes an earned capability** rather than a design goal. The tiered staircase (pacing calculator → training load → physiological model → full twin) delivers immediate value at each step while naturally accumulating the longitudinal data that makes the next tier possible. Critically, consumer-grade sensors support the first three tiers without requiring lab equipment.

Third, **the AI layer operates through a domain-specific language**, not through direct code generation. LLM reliability drops precipitously for end-to-end pipeline generation (29.2% success) but rises sharply when the LLM translates intent into structured operator selections from a curated library (92.3% success). The rowing DSL—with typed inputs/outputs, pre-built transforms for every standard metric, and sandboxed validation—is the missing architectural layer that makes AI-assisted analytics reliable enough for coaching decisions.

Fourth, **the display pipeline is decoupled from the compute pipeline** through the `DisplayDecimator` node, which respects the physical limits of screen hardware (≤120Hz temporal, 1 datapoint per pixel spatial). This eliminates the need for Metal-based custom renderers, keeps the entire visualization stack within Swift Charts' native capabilities, and enables seamless semantic zoom from session overview to single-stroke detail through a single, elegant mechanism.

The technology timing is favorable. Apple's M5/A19 Neural Accelerators, Foundation Models framework with free on-device inference, `VNDetectHumanBodyPose3DRequest` for native 3D pose estimation, CKSyncEngine for sync, and DuckDB's mobile OLAP capability collectively provide a platform stack that was simply unavailable 18 months ago. The rowing analytics Super App is no longer a question of whether the technology exists—it is a question of engineering execution against a well-defined architecture.
