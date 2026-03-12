# CLAUDE.md -- RowData Studio

## Identity

**RowData Studio** (RDS) is a native Apple rowing performance analysis tool (macOS, iPadOS, iOS). It integrates multi-camera video, GoPro GPMF telemetry (IMU 200Hz, GPS 10-18Hz), biometric FIT data (NK SpeedCoach, Garmin, Apple Watch), and biomechanical CSV data (NK Empower Oarlock) in a unified infinite canvas interface. All processing on-device.

**Status:** SDK modules complete. Application layer development starting.

## Build & Test

```bash
# From any module directory:
swift build
swift test

# Run specific module:
cd modules/gpmf-swift-sdk-main && swift test   # 222 tests
cd modules/fit-swift-sdk-main && swift test     # 248 tests
cd modules/csv-swift-sdk-main && swift test     # 20 tests
```

| Module | Tests | Framework | Status |
| ------ | ----- | --------- | ------ |
| gpmf-swift-sdk-main | 222 | XCTest | Complete |
| fit-swift-sdk-main | 248 | Mixed XCTest + Swift Testing | Complete |
| csv-swift-sdk-main | 20 | Swift Testing | Complete |

**New app code:** Use Swift Testing (`@Test`, `#expect`) for all new tests.

## Xcode Configuration (CRITICAL)

Non-standard Xcode location on external volume:

```text
/Volumes/WDSN770/Applications/Xcode.app
```

If `swift test` fails with "no such module 'XCTest'":

```bash
sudo xcode-select -s /Volumes/WDSN770/Applications/Xcode.app/Contents/Developer
```

Command Line Tools alone do not include XCTest on macOS 26.0. Full Xcode is required.

## Module Map

| Module | Purpose | Status |
| ------ | ------- | ------ |
| `modules/gpmf-swift-sdk-main/` | GoPro GPMF parser (IMU, GPS, orientation) | Complete (222 tests) |
| `modules/fit-swift-sdk-main/` | Garmin FIT protocol parser/encoder | Complete (248 tests) |
| `modules/csv-swift-sdk-main/` | CSV parser + profiles (NK Empower, NK SpeedCoach, CrewNerd) | Complete (20 tests) |
| `app/` | Main application (SwiftUI, infinite canvas, fusion) | To create |

Each module has its own `CLAUDE.md` with detailed architecture and conventions.

## Architecture Principles

1. **Non-Destructive Editing** -- Source files (MP4, FIT, CSV) never modified; sidecar pattern for derived data
2. **Structure of Arrays (SoA)** -- `ContiguousArray<Float>` for sensor data; cache-efficient, Accelerate-compatible
3. **Composable Transform Pipelines** -- ViewportCull -> LTTBDownsample -> AdaptiveSmooth; shared across all widgets
4. **Scale-Aware Processing** -- HF (200Hz IMU), MF (1Hz FIT), LF (per-stroke aggregates)
5. **Video Sync Is Sacred** -- Frame-accurate alignment between video, telemetry, and playhead at all times
6. **Offline-First** -- Full functionality without network; on-device processing only

## Architectural Specifications

| Topic | Document |
| ----- | -------- |
| Full architecture + data models | `docs/architecture/kickoff-report.md` |
| SessionDocument, SoA buffers, MetricDef | `docs/architecture/data-models.md` |
| Visualization (Canvas, transforms, widgets) | `docs/architecture/visualization.md` |
| Sync pipeline (SignMatch, GPS correlators) | `docs/specs/sync-pipeline.md` |
| Fusion engine (6-step pipeline, stroke detection) | `docs/specs/fusion-engine.md` |
| Signal processing library (vDSP port) | `docs/specs/signal-processing.md` |
| NK Empower integration (13 biomechanical metrics) | `docs/specs/empower-integration.md` |
| Strategic vision and roadmap | `docs/vision/vision-4.0.md` |

## Governance

| Topic | Document |
| ----- | -------- |
| Values, trade-offs, decisional boundaries | `.claude/INTENT.md` |
| Code conventions, naming, testing patterns | `.claude/CONVENTIONS.md` |
| Multi-agent protocols, session lifecycle | `.claude/AGENTS.md` |
| Engineering standards (Context/Intent/Spec) | `docs/engineering-standards.md` |
| Agent work journals | `.claude/session-logs/` |

## Domain Context

- **Sport:** Competitive rowing (sweep, sculling)
- **Users:** Elite athletes, coaches, data engineers
- **Hardware:**
  - GoPro HERO10+ -- GPMF format, 200Hz IMU (ACCL/GYRO), 10-18Hz GPS
  - NK SpeedCoach GPS 2 / Garmin / Apple Watch -- FIT format, 1Hz metrics
  - NK Empower Oarlock -- CSV export, 13 per-stroke biomechanical metrics
- **Temporal scales:** HF (200Hz), MF (1Hz), LF (per-stroke ~0.3-0.5 Hz)
- **Privacy:** All processing on-device, no cloud dependencies

## Critical Constraints (Must Not Forget)

1. **AVFoundation Passthrough does NOT preserve GPMF track** -- Always generate telemetry sidecar during video trim (experimentally verified 2026-02-27)
2. **NK SpeedCoach FIT does NOT contain Empower data** -- CSV export from NK LiNK Logbook is the only source for force/angle metrics
3. **GPS timestamps need convergence** -- First GPS observation may be unreliable (camera GPS receiver cold start). Use `lastGPSU` for higher accuracy. See GPMF SDK CLAUDE.md timing model.
4. **Xcode on external volume** -- `/Volumes/WDSN770/Applications/Xcode.app`. All CI and agent sessions must verify `xcode-select` before building.
5. **Multi-camera sync precision** -- GPS back-computation gives ~1-5s accuracy (sufficient for rowing, not film production)
