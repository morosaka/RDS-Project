# CSVSwiftSDK -- CLAUDE.md

## Overview

Swift Package providing a generic RFC 4180 CSV parser and vendor-specific rowing data profiles.
Forked from SwiftCSV, standardized to RDS conventions.

**Scope:** CSV parsing, delimiter detection, and vendor-specific data extraction for rowing
hardware (NK Empower, NK SpeedCoach, CrewNerd). Additional profiles (Garmin, Peach) planned.

## Build & Test

```bash
swift build
swift test              # 20 tests (Swift Testing framework)

# If swift test fails with "no such module 'XCTest'":
sudo xcode-select -s /Volumes/WDSN770/Applications/Xcode.app/Contents/Developer
```

**Platforms:** macOS 12+, iOS 15+
**Swift:** 6.0
**Dependencies:** None (Foundation only)

## Architecture

```
Sources/CSVSwiftSDK/
├── CSV.swift                    Generic CSV container (CSV<DataView>)
├── CSV+DelimiterGuessing.swift  Auto-detect delimiter from content
├── CSVDelimiter.swift           Delimiter enum (comma, tab, semicolon, custom)
├── Parser.swift                 Low-level state machine parser
├── ParsingState.swift           Parser state enum
├── Serializer.swift             CSV writing/serialization
├── String+Lines.swift           Newline normalization (CR/LF/CRLF)
├── NamedCSVView.swift           Header-based column access (NamedCSV)
├── EnumeratedCSVView.swift      Index-based column access (EnumeratedCSV)
├── Resources/
│   └── PrivacyInfo.xcprivacy    Privacy manifest
└── Profiles/
    ├── NKEmpowerProfile.swift   NK Empower Oarlock (13 biomechanical metrics)
    ├── NKSpeedCoachProfile.swift NK SpeedCoach GPS 2 (session/interval/stroke)
    └── CrewNerdProfile.swift    CrewNerd rowing app (HR/GPS telemetry)
```

## Testing Framework

**This module uses Swift Testing (NOT XCTest).**
All tests use `@Suite`, `@Test`, and `#expect()`. New tests must follow this convention.

```swift
import Testing
@testable import CSVSwiftSDK

@Suite("Feature Name")
struct FeatureTests {
    @Test("Descriptive name")
    func descriptiveName() throws {
        #expect(condition)
    }
}
```

**Test data:** Real vendor CSV exports in `Tests/CSVSwiftSDKTests/TestData/`
- `NK csv exported-sessions/` -- 3 NK SpeedCoach CSV files
- `CN csv exported-sessions/` -- 3 CrewNerd CSV files
- Edge cases: `wonderland.csv`, `empty_fields.csv`, `quotes.csv`, `utf8_with_bom.csv`, `large.csv`

**Resource loading:** `ResourceHelper.swift` handles SPM (`Bundle.module`) vs Xcode project paths.

## Key Public API

```swift
// Generic CSV
public class CSV<DataView: CSVView> { ... }
public typealias NamedCSV = CSV<Named>
public typealias EnumeratedCSV = CSV<Enumerated>

// Vendor profile parsers (all static API)
public struct NKEmpowerParser {
    public static func parse(_ csvString: String) throws -> NKEmpowerSession
}
public struct NKSpeedCoachParser {
    public static func parse(_ csvString: String) throws -> NKSpeedCoachSession
}
public struct CrewNerdParser {
    public static func parse(_ csvString: String) throws -> CrewNerdSession
}
```

## Vendor Profiles

### NK Empower Oarlock (NKEmpowerProfile.swift)

13 biomechanical per-stroke metrics from NK Empower Oarlock CSV export:

| # | Metric | RDS Name | Unit |
|---|--------|----------|------|
| 1 | Catch Angle | `mech_ext_str_angle_catch` | degrees |
| 2 | Finish Angle | `mech_ext_str_angle_finish` | degrees |
| 3 | Slip | `mech_ext_str_slip` | degrees |
| 4 | Wash | `mech_ext_str_wash` | degrees |
| 5 | Effective Length | `mech_ext_str_length_effective` | degrees |
| 6 | Total Length | `mech_ext_str_length_total` | degrees |
| 7 | Force Avg | `mech_ext_str_force_avg` | N |
| 8 | Force Peak | `mech_ext_str_force_peak` | N |
| 9 | Power Avg | `mech_ext_str_power_avg` | W |
| 10 | Power Peak | `mech_ext_str_power_peak` | W |
| 11 | Work | `mech_ext_str_work` | J |
| 12 | Max Force Angle | `mech_ext_str_angle_maxforce` | degrees |
| 13 | Wash Force | `mech_ext_str_force_wash` | N |

For full integration details: `docs/specs/empower-integration.md`

### NK SpeedCoach GPS 2 (NKSpeedCoachProfile.swift)

Session metadata + intervals + per-stroke data:
- `NKSpeedCoachSession`: sessionInfo, deviceInfo, summary, intervals, strokes
- `NKSpeedCoachStroke`: 23 fields including optional Empower metrics when connected

### CrewNerd (CrewNerdProfile.swift)

Time-series telemetry from the CrewNerd rowing app (~1Hz):
- `CrewNerdSession`: metadata + telemetry samples
- `TelemetrySample`: 13 fields per sample (HR, GPS, stroke rate, speed, distance, etc.)

## Origin

Forked from [SwiftCSV](https://github.com/swiftcsv/SwiftCSV), standardized to RDS conventions.
See `docs/reports/csv-standardization.md` for migration history.
