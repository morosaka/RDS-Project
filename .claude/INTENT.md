# Project Intent and Governance

## Purpose

RowData Studio exists to give competitive rowers and coaches a unified analysis tool that
integrates multi-angle video, high-frequency telemetry (IMU 200Hz, GPS 10-18Hz), biometric
data (HR, power), and biomechanical force/angle data in a single interactive environment.

The product should feel like **one tool**, not a Swiss Army knife. No product on the market
integrates multi-angle video with high-frequency IMU, GPS, and biometric data in a single
interactive canvas. Existing solutions (CrewNerd, NK LiNK, Strava) offer only subsets, never
integrated.

This is the **fourth iteration** of the rowing analysis platform (Python v1-v2, TypeScript/React
web v3 "RowDataLab"). Each iteration refined domain understanding. The algorithms, constants,
and architectural patterns from RowDataLab v0.32.0 are production-verified and form the
foundation for RDS.

## Values (Ranked)

1. **Correctness** -- A wrong metric is worse than no metric. Prefer explicit uncertainty over
   confident errors. Every algorithm must reference its source (RDL file, paper, or spec).
2. **Data Integrity** -- Source files are sacred. Non-destructive editing always. Sidecar pattern
   for all derived data. No data loss, ever.
3. **Performance** -- 60fps with 200Hz data is non-negotiable. Users judge the tool by
   responsiveness. Use Accelerate/vDSP, SoA buffers, and .drawingGroup() Metal backing.
4. **Simplicity** -- One way to do things. No configuration options until proven necessary.
   Defaults that work for 90% of cases. Minimal public API surface.
5. **Privacy** -- All processing on-device. No telemetry, no cloud dependencies for core
   functionality. Users trust us with their training data.

## Trade-off Hierarchies

When in conflict, apply in order:

- **Correctness > Performance > API Elegance > Code Brevity**
- **Working code > Beautiful code > Documented code**
- **Test coverage > Feature completeness > Polish**
- **Existing patterns > New patterns > External patterns**
- **User safety (data integrity) > User convenience**
- **Explicit > Implicit** (no magic behavior, no hidden defaults)

## Architectural Decisions (Settled)

These decisions are final and must not be revisited without explicit instruction:

- **SwiftUI Canvas + .drawingGroup()** for all high-frequency visualization (not manual Metal)
- **Composable Transform Pipelines** shared across all widgets (not per-widget rendering logic)
- **Structure of Arrays (SoA)** with ContiguousArray<Float> for sensor data (not AoS)
- **Swift Structured Concurrency** (async/await) for all I/O (not Combine, not GCD)
- **@Observable** for state management (not ObservableObject/Published)
- **XCTest** for GPMF SDK; **Swift Testing** for CSV SDK and new code; FIT SDK mixed (needs updating)
- **SQLite (GRDB.swift)** for session metadata persistence
- **Single playhead** (@Observable TimeInterval) as global temporal source of truth

## Decisional Boundaries

### Agent MAY do autonomously (no approval needed):
- Fix compilation errors
- Fix test failures caused by recent changes
- Add missing tests for existing code
- Refactor within a single file (renaming, extracting methods)
- Update file headers and revision history
- Fix factual errors in documentation
- Add inline comments where logic is non-obvious
- Run swift build / swift test to verify changes

### Agent MUST ask before:
- Creating new public API surface (public types, protocols, methods)
- Adding external dependencies (SPM packages)
- Changing data model schemas (SessionDocument, TelemetrySidecar, SoA buffers)
- Deleting or deprecating existing public API
- Modifying sync/fusion algorithm constants (these are calibrated on real data)
- Changing directory structure or module organization
- Modifying Package.swift files
- Any change to CLAUDE.md or .claude/ governance documents
- Bumping the major version number
- Architectural changes that affect more than 3 files

### Agent MUST NEVER:
- Modify source MP4/FIT/CSV test fixture files
- Commit secrets, API keys, or personal data
- Push to remote without explicit instruction
- Force-push to any branch
- Delete test fixtures or test data
- Reduce test coverage below current levels
- Use placeholder implementations (no TODOs, no fatalError(), no stubs)
- Add Swift packages not already in the dependency graph without approval
- Introduce Combine or GCD where async/await should be used

## Quality Standards

- Every Swift file: versioned docblock header (see .claude/CONVENTIONS.md)
- Every new public type: at least one test
- Every algorithm: reference to source (RDL file path, paper citation, or format spec)
- Floating-point comparisons: always with epsilon/accuracy parameter
- All I/O operations: async/await, never blocking the main thread
- All public data types: Sendable conformance
- All output models: Codable conformance
- No force-unwrapping in production code (test code may use XCTUnwrap)

## Product Scope

### MVP (In Scope):
Manual ingest, full parsing (GPMF/FIT/CSV), video triage with sidecar, multi-track timeline,
semi-automatic synchronization, infinite canvas ("Rowing Desk"), synchronized playhead,
ROI marking, metric comparison, export (PDF/CSV/GPX).

### Post-MVP (Out of Scope):
Real-time streaming, in-boat athlete module (iPhone/Watch), remote coach monitoring,
pose estimation, AI/LLM integration, cloud sync, multi-language.

Do not implement post-MVP features. Do not add hooks or abstractions "in preparation for"
post-MVP features. Build exactly what is needed now.
