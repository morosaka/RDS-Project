# CSVSwiftSDK

Generic CSV parsing library for RowData Studio, with specialized profiles for rowing telemetry vendors.

## Overview

**CSVSwiftSDK** provides RFC 4180-compliant CSV parsing capabilities for RowData Studio (RDS). It includes:

- **Generic CSV Parser**: Fast, memory-efficient parsing with automatic delimiter detection
- **Vendor Profiles**: Specialized parsers for rowing telemetry CSV exports:
  - **NK Empower Oarlock**: 13 biomechanical metrics per stroke (force, angle, power, work)
  - **NK SpeedCoach** (planned)
  - **Garmin Connect** (planned)
  - **Peach PowerLine** (planned)
  - **CrewNerd** (planned)

## Integration with RowData Studio

This module is part of the RowData Studio data ingestion pipeline:

```
NK Empower CSV → CSVSwiftSDK → NKEmpowerSession → SessionDocument
                 (NKEmpowerProfile)
```

### NK Empower Oarlock Integration

The NK Empower Oarlock exports per-stroke biomechanical data from the NK LiNK Logbook as CSV. This is the **only** source for oarlock force/angle metrics (FIT files from SpeedCoach do NOT contain Empower data).

**Metrics (13 per stroke):**
- **Angles**: Catch, Finish, Max Force Angle
- **Forces**: Peak, Average
- **Power**: Peak, Average
- **Efficiency**: Slip, Wash, Work
- **Length**: Stroke Length, Effective Length

**Synchronization:** GPS track correlation aligns Empower CSV with GoPro GPMF and FIT telemetry (same strategy as FIT ↔ GPMF sync).

## Architecture

### Generic CSV Parser

RFC 4180 compliant with support for:
- Quoted fields with embedded delimiters, newlines, and quotes
- Automatic delimiter detection (comma, semicolon, tab, custom)
- UTF-8 BOM handling
- Memory-efficient streaming for large files
- Named (dictionary-based) or enumerated (array-based) access

### Vendor Profiles

Profile parsers extend the generic parser with domain-specific:
- Column mapping and validation
- Unit conversion (degrees, newtons, watts, joules)
- Data normalization (stroke numbering, elapsed time)
- Error handling for malformed vendor exports

## Usage

### Generic CSV Parsing

```swift
import CSVSwiftSDK

// Parse with automatic delimiter detection
let csv = try CSV<Named>(url: fileURL)
csv.header         // ["id", "name", "age"]
csv.rows[0]["name"] // "Alice"

// Specify delimiter
let tsv = try CSV<Enumerated>(url: fileURL, delimiter: .tab)
tsv.rows[0][1]     // "Alice"

// Memory-efficient streaming
try csv.enumerateAsDict { row in
    print(row["name"])
}
```

### NK Empower Profile

```swift
import CSVSwiftSDK

let csvString = try String(contentsOf: empowerFileURL)
let session = try NKEmpowerParser.parse(csvString)

for stroke in session.strokes {
    print("Stroke \(stroke.strokeNumber): \(stroke.maxForce)N @ \(stroke.catchAngle)°")
}
```

## Requirements

- Swift 6.0+
- macOS 12.0+ / iOS 15.0+
- Swift Package Manager

## Testing

```bash
swift test                         # Run all tests
swift test --filter NKEmpowerTests # Run profile tests
swift build                        # Build module
```

## File Naming Convention

RDS uses standardized metric nomenclature for CSV columns:

```
[FAMILY]_[SOURCE]_[TYPE]_[NAME]_[MODIFIER]
```

**Example:**
- `mech_ext_str_force_peak` - Peak oarlock force (external mechanical, per-stroke)
- `mech_ext_str_angle_catch` - Catch angle in degrees

See `CLAUDE.md` § Metric Nomenclature for complete specification.

## Project Status

- ✅ **Generic CSV Parser**: Complete (based on SwiftCSV)
- ✅ **NK Empower Profile**: Data structures defined
- 🚧 **NK Empower Parser**: Implementation pending
- 📋 **Other Profiles**: Planned

## Credits

Based on [SwiftCSV](https://github.com/swiftcsv/SwiftCSV) by Naoto Kaneko and contributors.
Integrated and extended for RowData Studio by Mauro Saccà.

## License

MIT License (see LICENSE file)

---

**RowData Studio** - Native Apple rowing performance analysis
📍 [Project Documentation](../../docs/RowDataStudio_Kickoff_Report_v1.md)
