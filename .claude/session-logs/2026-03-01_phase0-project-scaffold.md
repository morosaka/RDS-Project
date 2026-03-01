---
date: 2026-03-01
scope: Phase 0 — Project Scaffold
status: completed
---

## Summary

Created the root Swift Package scaffold that imports all 3 SDK modules (GPMF, FIT, CSV) as local SPM dependencies. The project builds cleanly and all 4 smoke tests pass with zero warnings.

## Architecture Decision

**Decision:** Library + Executable + Test target split (standard SPM convention)
**Alternatives considered:** Single executable target; monolithic Xcode project
**Rationale:** Test targets cannot depend on executable targets in SPM. Splitting into a `RowDataStudio` library (all app logic, testable) and a thin `RowDataStudioApp` executable (@main only) ensures all app code is testable from CLI without Xcode. The Xcode project will be added later when needed for asset catalogs, signing, and platform-specific features.
**Reversibility:** Easy — can wrap in .xcodeproj at any time without changing source layout.

## Files Created

| File | Purpose |
|------|---------|
| `Package.swift` | Root package: library + executable + test targets, 3 local SPM dependencies |
| `Sources/RowDataStudio/ContentView.swift` | Placeholder root view (public, in library target) |
| `Sources/RowDataStudioApp/App.swift` | @main SwiftUI entry point (imports library) |
| `Tests/RowDataStudioTests/SmokeTests.swift` | 4 smoke tests verifying SDK imports |

## Package Structure

```
Package.swift                          # Root (macOS 13+, Swift 6.0)
├── RowDataStudio (library)            # All app logic, testable
│   ├── depends: GPMFSwiftSDK, FITSwiftSDK, CSVSwiftSDK
│   └── path: Sources/RowDataStudio/
├── RowDataStudioApp (executable)      # Thin @main entry
│   ├── depends: RowDataStudio
│   └── path: Sources/RowDataStudioApp/
└── RowDataStudioTests (test)          # Swift Testing framework
    ├── depends: RowDataStudio
    └── path: Tests/RowDataStudioTests/
```

## Gotcha: SPM package identity

SPM `.product(name:package:)` uses the **directory-derived package identity** (e.g., `gpmf-swift-sdk-main`), NOT the `name:` field from the dependency's Package.swift (`GPMFSwiftSDK`). Initial build failed until corrected.

## Test Results

```
swift build  → Build complete! (14.33s)
swift test   → 4/4 tests passed, 0 warnings, 0 failures
```

## Next Steps

- Phase 1: Define core data models in `Sources/RowDataStudio/Core/Models/`
- Reference: `docs/architecture/data-models.md`, `docs/specs/fusion-engine.md`
