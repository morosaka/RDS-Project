# THE ROWING SUPER APP
## Vision 4.0 — Consolidated Proposal
Integrating Proposals, Critiques, and State-of-the-Art Advances

**February 2026**
*Confidential — Internal Working Document*

### Executive Summary
This document consolidates three prior artefacts: the Vision 3.0 architecture proposal, the destructive critical analysis, and the initial literature-based research report. It distils every actionable proposal into a single reference, integrates the criticisms as binding design constraints, and extends the vision with new ideas grounded in the latest hardware, software, and research developments available as of February 2026. The result is Vision 4.0: a proposal that retains the intellectual ambition of the original while grounding it in engineering realism.

The fundamental thesis remains valid: a unified reactive graph engine fusing high-frequency IMU telemetry, monocular pose estimation, and physiological data, delivered through a progressive multi-tier UI with agentic AI, is technically feasible on Apple silicon. However, the path from vision to shipped product requires resolving seven structural deficiencies identified in the critical analysis: unrealistic timelines, missing MVP definition, absent user research, unspecified team and budget, no testing strategy, no business model, and single-platform lock-in.

---

### Part A: Synthesis of Existing Proposals
This section consolidates core ideas from all three source documents into a unified summary.

#### 1. Reactive Graph Engine (Multi-Rate DAG)
The architecture centres on a five-level hierarchical DAG:
- **L0:** Raw sources at native rates.
- **L1:** Feature extraction (Madgwick filter, ring buffers, Butterworth filtering using Accelerate/vDSP).
- **L2:** Stroke detection at ~0.5 Hz producing the stroke as the universal join key.
- **L3:** Session aggregation at 1 Hz.
- **L4:** Display-rate outputs.

Rate-changing boundary nodes bridge levels using Combine operators. A `DisplayDecimator` node decouples compute from display, feeding Swift Charts with at most ~1,200 points per viewport via MinMaxLTTB downsampling. The literature report corroborates this approach, recommending Kappa Architecture principles for stream processing with event-time ordering.

#### 2. Sensor Fusion
The IMU pipeline uses the Madgwick AHRS filter with acceleration rejection and Cloud et al.’s adaptive Kalman filter for GPS-IMU fusion. Stroke detection combines a real-time sliding-window peak detector with post-stroke UWT refinement. Key derived metrics include check factor, propulsive effectiveness, drive:recovery ratio, and LSTM-based force curve estimation. Auto-calibration uses gravity detection at launch and PCA over initial strokes for axis alignment.

#### 3. Data Sources: GoPro GPMF and NK SpeedCoach
GoPro provides a single-device video-plus-IMU-plus-GPS package via the GPMF telemetry track. The architecture must treat every GPMF file as self-describing (actual sample rates discovered per file, not assumed). NK SpeedCoach data is stroke-sampled (variable intervals), requiring dedicated boundary nodes in the DAG. The Source Adapter pattern abstracts timing differences.

#### 4. Pose Estimation
Coaching-grade accuracy (trunk inclination ±5–8°).
- **Frontal/Dorsal views:** Symmetry and timing analysis.
- **Lateral views:** Sagittal-plane technique geometry.
Primary pipeline: Apple Vision `VNDetectHumanBodyPose3DRequest`. fallback: MediaPipe BlazePose. Multi-video sync relies on audio cross-correlation, visual event matching, or IMU-to-visual-motion correlation.

#### 5. Agentic AI and DSL
Generates a rowing-domain DSL rather than raw code. Uses **Prompt2DAG** (92.3% success for template-based generation). **LangGraph** orchestrates multi-agent workflows: Pipeline Generation Agent, Coaching Insight Crew (via CrewAI), and Data Quality Agent. Hybrid inference: Apple Foundation Models (on-device) and Cloud LLMs (GPT-4o/Claude).

#### 6. Digital Twin (Four-Tier Staircase)
- **Tier 1:** CP/W’ pacing calculator (weeks).
- **Tier 2:** Banister FFM training load monitor (1–3 months).
- **Tier 3:** Margaria-Morton physiological model (3–6 months).
- **Tier 4:** Full biomechanical-physiological coupling (6–12+ months).

#### 7. Data Architecture (SQLite + DuckDB)
- **Bronze:** SQLite via GRDB.swift (WAL mode, BLOB packing).
- **Silver:** 1 Hz unified time series + per-stroke summary.
- **Gold:** DuckDB for columnar OLAP.
- **Sync:** CKSyncEngine (metadata) and Multipeer Connectivity (large data).

#### 8. Three-Tier UI
- **Consumer (athlete):** Glanceable KPI cards.
- **Power User (coach):** Vertical channel strips (Ableton-inspired).
- **Architect (node editor):** Widget-based DAG construction.
- **Features:** Sonification, haptic feedback, Apple Pencil annotation.

---

### Part B: New Ideas and Advances (February 2026)
Proposals informed by the latest developments.

#### 1. Replace Combine with Swift Concurrency
Combine is effectively frozen. The revised architecture uses **Swift Structured Concurrency** (`AsyncSequence`, `AsyncStream`, `TaskGroup`). This provides native backpressure, integrates with SwiftUI’s `.task` modifier, and improves debuggability.

#### 2. Apple Intelligence and Foundation Models (iOS 26)
Uses the ~3B parameter on-device model (iOS 26 Foundation Models) for natural-language workout summaries and basic offline coaching Q&A. Cloud LLMs are reserved for complex multi-session reasoning.

#### 3. Observation Framework
Replaces `ObservableObject` with SwiftUI’s **Observation** framework (`@Observable`). Enables fine-grained tracking, preventing unnecessary re-renders in multi-metric dashboards.

#### 4. Swift Testing Framework
Adds a mandatory testing layer: unit tests for transform nodes, integration tests via DAG simulator, and synthetic data generators (ICC target >0.95).

#### 5. Structured Environmental Context
Integrated **WeatherKit** for wind, temperature, and water conditions. Adds a normalization layer to Silver processing to prevent false attribution of speed changes to technique.

#### 6. Garmin/COROS/Polar Watch Integration
Adds a `FIT_Generic` Source Adapter and HealthKit bridge. Addresses market limitations beyond GoPro/SpeedCoach owners.

#### 7. Offline-First Architecture
Works fully offline for on-water sessions. Three-tier connectivity model: On-device (Tier 1), Dockside WiFi (Tier 2), and Full Connectivity (Tier 3).

#### 8. Confidence Scoring and Uncertainty Propagation
Every metric carries a confidence score (0–1). Pose estimation includes per-joint confidence. UI grey-out or warnings for unreliable data.

#### 9. Battery Budget Manager
Monitors thermal state and battery level. Dynamically adjusts sensor duty cycles (e.g., GPS drops to 1 Hz in Serious thermal state).

#### 10. MVP Definition: The “60-Minute Single Scull”
A single sculler uses an iPhone in the boat for 60 minutes. Gets session summary (stroke count, average split, rate trend, HR zones, force curve overlay). **Timeline: 3–4 months with 2–3 engineers.**

---

### Part C: Resolving Critical Deficiencies

#### 1. Realistic Timeline and Phasing
A 24-month roadmap with six phases (vMVP at month 6).
- **Phase 0:** Foundation.
- **Phase 1:** MVP (Month 6).
- **Phase 2:** Silver + Coach UI.
- **Phase 3:** Ecosystem (Watch/FIT).
- **Phase 4:** Intelligence (Tiers 1-2).
- **Phase 5:** Advanced (Pose 3D, Tier 3).

#### 2. Team and Budget
Minimum viable team: 4.25 FTE initially, scaling to 8.5 FTE. Estimated annual cost: €450K–€650K.

#### 3. User Research Plan
Integrates 10 interviews in Phase 0, beta TestFlight in Phase 1, and continuous feedback loops.

#### 4. Testing Pyramid
- **Unit tests:** >90% coverage on core pipeline.
- **Integration tests:** Regression suite via Bronze replay.
- **Performance:** End-to-end latency <50ms.
- **Cross-validation:** Automated alert if >5% divergence from SpeedCoach.

#### 5. Privacy and Compliance
Health data encrypted (iOS Data Protection). Anonymized AI queries. Wellness/Sports performance classification (not medical device).

#### 6. Business Model
- **Free:** Basic metrics.
- **Pro (€9.99/mo):** Unlimited sessions, GoPro import, AI summaries.
- **Coach (€19.99/mo):** Multi-rower management, Rack UI, Coach AI.

#### 7. Cross-Platform Strategy
Apple-first V1, but DAG/Signal code in pure Swift for future portability. SQLite/DuckDB/LangGraph are already platform-agnostic.

#### 8. Maintenance and Operations
30% capacity reserved for maintenance. Covers OS updates, firmware compatibility, and schema migrations.

#### 9. Storage Calculation (100 Sessions)
- **Bronze/Silver/Gold:** ~3.9 GB total.
- **Video:** ~400 GB (off-device offload recommended).
Minimum supported device: iPhone 13 (A15).

### Conclusion
Vision 4.0 preserves intellectual ambition while grounding it in engineering discipline. Highlights include replacing Combine with Swift Concurrency, defining a clear MVP at Month 6, and a 24-month roadmap with explicit testing and business strategies. The timing remains favourable due to advances in on-device AI and specialized mobile analytics.
