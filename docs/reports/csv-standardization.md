# CSV Swift SDK Standardization Report

## 1. Overview

The current `csv-swift-sdk-main` module is a clone/fork of the open-source `SwiftCSV` library. While it provides a robust RFC 4180 compliant CSV parser, its structural and architectural state does not conform to the **RowData Studio (RDS)** project standards defined in `CLAUDE.md`.

This report outlines the necessary steps to standardize this SDK, aligning it with `gpmf-swift-sdk-main` and `fit-swift-sdk-main`, and preparing it for vendor-specific rowing data profiles.

## 2. Directory & Project Structure

The current layout uses legacy iOS/macOS open-source conventions (CocoaPods, Xcode projects, custom source folders). RDS strictly uses Swift Package Manager (SPM).

### 2.1 Removals

Delete the following files/directories that are irrelevant or deprecated in the RDS SPM-first architecture:

- `SwiftCSV.xcodeproj/` (redundant, SPM provides Xcode integration)
- `SwiftCSV.podspec` (CocoaPods is not used)
- `.travis.yml` & `.spi.yml` (legacy CI configs)

### 2.2 Restructuring

Restructure the source directories to match the standard SPM layout used by the other SDKs:

- **Rename/Move** `SwiftCSV/` to `Sources/CSVSwiftSDK/`.
- **Rename/Move** `SwiftCSVTests/` to `Tests/CSVSwiftSDKTests/`.
- **Create** `Sources/CSVSwiftSDK/Profiles/` to house the vendor-specific data models (NK Empower, Garmin, etc.).

## 3. Package.swift Modernization

The `Package.swift` file must be updated to align with RDS platforms and Swift 6 constraints.

**Required Changes:**

- **Swift Tools Version**: Bump `swift-tools-version` from `5.6` to `6.0`.
- **Platforms**: Update to RDS minimums: `.iOS(.v15), .macOS(.v12), .watchOS(.v8)`.
- **Target Names**: Rename the module from `SwiftCSV` to `CSVSwiftSDK` to match the `GPMFSwiftSDK` and `FITSwiftSDK` naming convention.
- **Paths**: Remove custom `path:` overrides in the target definitions once the folders are correctly named `Sources` and `Tests`.

## 4. Codebase Conventions & Architecture

### 4.1 File Headers (MANDATORY)

Every `.swift` file must be updated to include the standard RDS versioned docblock header:

```swift
// Module/FileName.swift v1.0.0
/**
 * Brief description of the module.
 * --- Revision History ---
 * v1.0.0 - 2026-03-01 - Initial implementation.
 */
```

### 4.2 Architecture (Generic Parser + Profiles)

The SDK currently only provides a generic CSV parser. According to the `CLAUDE.md` architecture, this module must serve as the foundation for vendor-specific CSV intake.

**Action Items:**

1. Isolate the generic RFC 4180 parsing logic into `CSVParser.swift`.
2. Implement specific Codable structs and parsing wrappers in the `Profiles/` directory:
   - `NKEmpowerProfile.swift` (Crucial for the 13 biomechanical metrics at 50Hz)
   - `NKSpeedCoachProfile.swift`
   - `GarminProfile.swift`
   - `PeachPowerLineProfile.swift` (Stubs for future integration)

### 4.3 Swift Modernization

- **Concurrency**: Replace synchronous file loading/blocking operations with Swift Structured Concurrency (`async`/`await`).
- **Error Handling**: Ensure operations return `Result<T, Error>` or throw typed errors conforming to `Error`.
- **Value Types**: Favor `struct` over `class` for the generic parsed rows and profile models to conform with the SoA (Structure of Arrays) transition later in the pipeline.

## 5. Testing Framework

The current test suite currently uses `XCTest`. While acceptable for legacy compatibility, the RDS standard testing framework is **Swift Testing** (`@Test`, `@Suite`, `#expect()`).

**Action Items:**

- Retain existing `XCTest` cases for the generic CSV parsing to avoid rewriting working tests.
- **Mandatory**: Any new tests written for the `Profiles/` implementations (e.g., `NKEmpowerProfileTests`) must use the Swift Testing framework.
- Ensure the test suite has >90% coverage for the `NKEmpowerProfile` parser before integration into the `FusionEngine`.

## 6. Execution Plan Summary

1. Cleanup root directory (remove `.xcodeproj`, `.podspec`, etc.).
2. Reorganize directories into `Sources/CSVSwiftSDK` and `Tests/CSVSwiftSDKTests`.
3. Rewrite `Package.swift` to Swift 6, RDS platforms, and appropriate target names.
4. Execute a batch update to prepend the mandatory File Header to all existing `.swift` files.
5. Create the `Profiles/` directory structure and implement the `NKEmpowerProfile.swift` base model.
