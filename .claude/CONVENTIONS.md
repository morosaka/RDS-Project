# Code Conventions

## File Header (MANDATORY)

Every Swift file must begin with a versioned docblock:

```swift
// Module/FileName.swift v1.0.0
/**
 * Brief description of the module.
 * --- Revision History ---
 * v1.0.0 - 2026-02-28 - Initial implementation.
 * v1.1.0 - 2026-03-01 - FEATURE: Added support for X.
 * v1.1.1 - 2026-03-02 - FIX: Corrected edge case in Y.
 */
```

**Category prefixes for revision history:**
`ARCHITECTURE`, `FEATURE`, `REFACTOR`, `FIX`, `PERFORMANCE`, `CLEANUP`, `MAINTENANCE`

## Versioning

App version tracked in `Info.plist` (CFBundleShortVersionString).
Semantic versioning: **X.Y.Z**
- **Z**: Patch/bugfix
- **Y**: New feature or algorithm
- **X**: Major (only on explicit instruction)

## Commit Messages

Conventional commits with lowercase type prefix:

```
feat: Add LTTB downsampling transform for charts
fix: Prevent GPS sync failure on missing GPSU timestamps
refactor: Extract stroke detection into separate module
docs: Update fusion engine architecture documentation
chore: Bump version to 0.2.0
test: Add integration tests for FusionEngine
```

## Swift Patterns

- **@Observable** for state management (not ObservableObject/Published)
- **@Environment** for shared context injection
- **async/await** for all I/O (file parsing, video loading) -- no Combine, no GCD
- **Result<T, Error>** for operations that can fail
- **Codable** on all persistence and output models
- **Sendable** on all public data types
- **struct** preferred over class (unless reference semantics required)
- **enum with associated values** for state machines (e.g., SyncState, StrokePhase)
- **No open classes** -- inheritance locked by design

## Constants

Group constants in enum namespaces (caseless enums prevent accidental instantiation):

```swift
enum TimeConstants {
    static let garminEpochOffset: TimeInterval = 631065600
    static let msPerSecond: Double = 1000.0
    static let gpsuConvergenceThreshold: TimeInterval = 300.0
}
```

## Metric Nomenclature

Pattern: `[FAMILY]_[SOURCE]_[TYPE]_[NAME]_[MODIFIER]`

| Segment  | Values                              | Meaning                          |
|----------|-------------------------------------|----------------------------------|
| FAMILY   | `imu`, `gps`, `phys`, `mech`, `fus` | Physical domain                  |
| SOURCE   | `raw`, `gpmf`, `ext`, `cal`, `fus`  | Data source (ext=FIT, cal=calibrated) |
| TYPE     | `ts`, `str`, `evt`                  | Temporal domain (time-series, stroke, event) |
| NAME     | `acc`, `gyro`, `speed`, `hr`, `vel` | Physical quantity                |
| MODIFIER | `surge`, `sway`, `heave`, `peak`, `avg` | Axis or aggregation          |

**Examples:**
- `imu_raw_ts_acc_surge` -- Raw IMU surge acceleration (time-series)
- `gps_gpmf_ts_speed` -- GPS speed from GoPro GPMF
- `fus_cal_ts_vel_inertial` -- Fused velocity (complementary filter)
- `mech_fus_str_rate` -- Stroke rate (per-stroke from FusionEngine)
- `mech_ext_str_force_peak` -- Peak oarlock force (NK Empower CSV)

## File Output Naming

Pattern: `RDS_[YYYYMMDD]_[HHMM]_[Description].ext`

Example: `RDS_20260228_1430_Session_Export.json`

## Testing

### Framework by Module

| Module | Framework | Tests | Notes |
|--------|-----------|-------|-------|
| gpmf-swift-sdk-main | XCTest | 222 | Mature, all XCTest |
| fit-swift-sdk-main | Mixed XCTest + Swift Testing | 248 | Garmin SDK port, transitioning |
| csv-swift-sdk-main | Swift Testing | 20 | All new code uses @Test/#expect |
| app/ (future) | Swift Testing | -- | New code uses Swift Testing |

### XCTest Pattern (GPMF, FIT legacy)

```swift
import XCTest
@testable import GPMFSwiftSDK

final class MyTests: XCTestCase {
    func test_subject_condition_expectedResult() {
        let result = compute(input)
        XCTAssertEqual(result, expected, accuracy: 0.01)
    }
}
```

### Swift Testing Pattern (CSV, new app code)

```swift
import Testing
@testable import CSVSwiftSDK

@Suite("Feature Name")
struct FeatureTests {
    @Test("Descriptive test name")
    func descriptiveName() throws {
        #expect(result == expected)
    }
}
```

### Test Conventions
- Factory helpers: `create*`, `mock*` prefix
- Constants: `MOCK_*` prefix
- Floating-point: `XCTAssertEqual(a, b, accuracy: epsilon)` or `#expect(abs(a - b) < epsilon)`
- Resource loading: Use `Bundle.module` for SPM, `ResourceHelper` pattern for dual SPM/Xcode

### Coverage Targets
- **Core logic** (FusionEngine, SyncEngine, StrokeDetection): >90%
- **Signal processing** (LTTB, smoothing, correlation): >85%
- **UI widgets**: Snapshot tests for visual regression (future)

## Safe Deprecation Protocol

When removing or superseding files:

1. **Hollow out** -- Remove functional logic
2. **Annotate** -- Add deprecation header with pointer to replacement
3. **Stub** -- Leave minimal structure to prevent import breakage

```swift
// Legacy/OldModule.swift v2.0.0 (DEPRECATED)
/**
 * DEPRECATED: Use NewModule.swift instead.
 * This file is retained only for import compatibility.
 */
```

## Editing Guidelines

1. **Read before editing** -- Always read the file before modifying it
2. **Surgical edits** -- Change only what is requested; preserve structure
3. **Increment version** -- Update file header and revision history on every change
4. **No placeholders** -- Complete, working implementations only (no TODOs or stubs)
5. **English only** -- All code, comments, UI labels in English
6. **Respect architecture** -- Follow Transform Pipeline, SoA, and separation of concerns
7. **Test critical logic** -- Add tests for parsers, fusion, signal processing, metrics
8. **No feature creep** -- Only implement explicit requirements
