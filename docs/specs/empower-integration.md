# Empower Oarlock (NK/Empacher) Sensor Integration Proposal

## 1. Overview

Empower Oarlocks by Nielsen-Kellerman (NK) represent the premium tier of rowing instrumentation. These devices replace standard oarlocks and use strain gauges and angle sensors to measure the direct mechanical interaction between the athlete and the boat at **50Hz sampling rate**, outputting per-stroke aggregated metrics.

Integrating these sensors into RowData Studio (RDS) bridges the gap between **Input (Force/Power)** and **Output (Acceleration/Speed/Video)**, providing a truly comprehensive biomechanical laboratory on-device.

**Feasibility Assessment:** ✅ **HIGH** - CSV integration is straightforward and aligns with RDS architecture. ANT+ live capture deferred to post-MVP.

## 2. Sensor Ecosystem
- **Hardware**: Empower Oarlock (Single or Pairs).
- **Communication**: ANT+ (Proprietary Profile).
- **Receiver**: NK SpeedCoach GPS 2 (requires Training Pack firmware).
- **Secondary Sync**: NK LiNK Logbook app (iOS/Android/Desktop).

## 3. Data Extraction Constraints

**CRITICAL:** A fundamental technical constraint has been verified:
- **FIT Files**: Standard .FIT files exported by the SpeedCoach **DO NOT** contain Empower Oarlock data. This is a confirmed limitation ([NK Sports Documentation](https://nksports.com/support/empower-oarlock/)).
- **CSV Export**: The **NK LiNK Logbook CSV export** is the **only** reliable source for per-stroke biomechanical data (13 metrics total).
- **Data Granularity**: CSV provides stroke-by-stroke detail with session summary, interval summary, and stroke-level data ([Rowsandall Analysis](https://analytics.rowsandall.com/2019/03/27/rowsandall-and-the-empower-oarlock-part-1-intervals-flex-charts-and-force-curves/)).

## 4. NK Empower CSV Data Structure

### 4.1 Complete Metric Set (13 Total)

RDS will map all available Empower metrics to internal nomenclature:

| NK CSV Column | RDS Nomenclature | Unit | Description |
|---------------|------------------|------|-------------|
| Catch Angle | `mech_ext_str_angle_catch` | degrees | Oar angle at blade entry |
| Finish Angle | `mech_ext_str_angle_finish` | degrees | Oar angle at blade exit |
| Slip | `mech_ext_str_eval_slip` | degrees | Angle lost during catch phase |
| Wash | `mech_ext_str_eval_wash` | degrees | Angle lost during finish phase |
| Max Force | `mech_ext_str_force_peak` | N (or lbs) | Maximum force during drive |
| Average Force | `mech_ext_str_force_avg` | N (or lbs) | Mean force across drive phase |
| Max Force Angle | `mech_ext_str_angle_force_max` | degrees | Oar angle at peak force |
| Power | `mech_ext_str_power_peak` | W | Peak instantaneous power |
| Average Power | `mech_ext_str_power_avg` | W | Mean power per stroke |
| Work | `mech_ext_str_work` | J | Cumulative energy per stroke |
| Stroke Length | `mech_ext_str_length_total` | degrees | Total angular displacement |
| Effective Length | `mech_ext_str_length_effective` | degrees | `Stroke Length - (Slip + Wash)` |
| Stroke Rate | `mech_ext_str_rate` | SPM | Strokes per minute (redundant with SpeedCoach) |

### 4.2 CSV File Structure

**Header Section:**
```csv
Session Summary
Date, Start Time, Duration, Total Strokes, Avg Split, Avg SR, ...
[session metadata rows]

Interval Summary
Interval, Start Time, Duration, Distance, Avg Split, Avg SR, ...
[interval metadata rows]

Stroke Detail
Stroke #, Elapsed Time, Distance, Split, SR, Catch Angle, Finish Angle, ...
[stroke-by-stroke data rows]
```

**Example Stroke Row:**
```csv
123, 00:05:34.2, 1234.5, 2:15.3, 32, -52.3, 38.7, 2.1, 1.5, 485.2, 398.6, 28.4, 325, 285, 145, 91.0, 87.4, 32
```

**Critical Parsing Considerations:**
- **Multi-section format**: Session summary → Interval summary → Stroke detail
- **Unit validation**: Force may be in N or lbs, angles in degrees or radians (rare)
- **Missing values**: Possible for dropouts (ANT+ link loss)
- **Timestamp format**: `HH:MM:SS.s` (elapsed time from session start)

## 5. Implementation Strategy

### Phase A: Generic CSV Parser SDK (`modules/csv-swift-sdk-main/`)

**Architecture: Generic Parser + Vendor Profiles**

Inspired by FIT SDK pattern, the CSV SDK separates generic CSV parsing (RFC 4180) from vendor-specific interpretation:

```
csv-swift-sdk-main/
├── Sources/CSVSwiftSDK/
│   ├── CSVParser.swift              # Generic RFC 4180 parser
│   ├── Profiles/
│   │   ├── CSVProfile.swift         # Protocol for all profiles
│   │   ├── NKEmpowerProfile.swift   # NK Empower 13 metrics
│   │   ├── NKSpeedCoachProfile.swift # NK SpeedCoach GPS/HR CSV
│   │   ├── GarminProfile.swift      # Garmin Connect CSV export
│   │   └── PeachPowerLineProfile.swift # Peach force/angle CSV
│   └── Types.swift
└── Tests/
```

**Generic Parser (CSVParser.swift):**
```swift
public struct CSVParser {
    public init() {}

    public func parse<P: CSVProfile>(
        _ data: Data,
        using profile: P
    ) throws -> P.SessionType {
        // 1. RFC 4180 parsing → 2D array
        let rows = try parseRFC4180(data)

        // 2. Delegate to profile for interpretation
        return try profile.parse(rows)
    }

    private func parseRFC4180(_ data: Data) throws -> [[String]] {
        // Generic CSV parsing (handles quotes, escapes, etc.)
    }
}
```

**Profile Protocol:**
```swift
public protocol CSVProfile {
    associatedtype SessionType: Codable

    /// Detect if CSV matches this profile format
    func matches(headers: [String], firstRow: [String]) -> Bool

    /// Parse CSV rows into typed session
    func parse(_ rows: [[String]]) throws -> SessionType

    /// Validate parsed session
    func validate(_ session: SessionType) -> [ValidationWarning]
}
```

**NK Empower Profile (NKEmpowerProfile.swift):**
```swift
public struct NKEmpowerProfile: CSVProfile {
    public typealias SessionType = NKEmpowerSession

    public func matches(headers: [String], firstRow: [String]) -> Bool {
        headers.contains("Catch Angle") &&
        headers.contains("Max Force") &&
        headers.contains("Work")
    }

    public func parse(_ rows: [[String]]) throws -> NKEmpowerSession {
        // 1. Section Detection
        guard let summaryStart = rows.firstIndex(where: { $0.first == "Session Summary" }),
              let intervalStart = rows.firstIndex(where: { $0.first == "Interval Summary" }),
              let strokeStart = rows.firstIndex(where: { $0.first == "Stroke Detail" })
        else {
            throw CSVError.missingSections
        }

        // 2. Parse metadata section
        let metadata = try parseMetadata(rows[summaryStart..<intervalStart])

        // 3. Parse intervals
        let intervals = try parseIntervals(rows[intervalStart..<strokeStart])

        // 4. Parse stroke detail (with unit detection)
        let (strokes, units) = try parseStrokes(rows[strokeStart...])

        // 5. Unit conversion to SI
        let normalizedStrokes = strokes.map { normalize($0, units: units) }

        return NKEmpowerSession(
            metadata: metadata,
            intervals: intervals,
            strokes: normalizedStrokes
        )
    }

    public func validate(_ session: NKEmpowerSession) -> [ValidationWarning] {
        var warnings: [ValidationWarning] = []

        // Temporal monotonicity
        for i in 1..<session.strokes.count {
            if session.strokes[i].elapsedTime < session.strokes[i-1].elapsedTime {
                warnings.append(.nonMonotonicTime(stroke: i))
            }
        }

        // Angle plausibility
        for (idx, stroke) in session.strokes.enumerated() {
            if stroke.catchAngle > -30 || stroke.catchAngle < -70 {
                warnings.append(.implausibleCatchAngle(stroke: idx, value: stroke.catchAngle))
            }
            if stroke.finishAngle < 20 || stroke.finishAngle > 50 {
                warnings.append(.implausibleFinishAngle(stroke: idx, value: stroke.finishAngle))
            }
        }

        return warnings
    }

    private func normalize(_ stroke: StrokeData, units: UnitSet) -> StrokeData {
        var normalized = stroke

        // Force: lbs → N
        if units.force == .pounds {
            normalized.maxForce *= 4.448222
            normalized.avgForce *= 4.448222
        }

        // Angles: radians → degrees (rare but possible)
        if units.angle == .radians {
            normalized.catchAngle *= 180.0 / .pi
            normalized.finishAngle *= 180.0 / .pi
            // ... etc
        }

        return normalized
    }
}

// Data Model (as before)
public struct NKEmpowerSession: Codable {
    public let metadata: SessionMetadata
    public let intervals: [IntervalSummary]
    public let strokes: [StrokeData]
}

public struct StrokeData: Codable {
    public let strokeNumber: Int
    public let elapsedTime: TimeInterval
    public let distance: Double
    public let split: TimeInterval
    public let strokeRate: Double

    // Empower metrics (13 total)
    public var catchAngle: Double
    public var finishAngle: Double
    public var slip: Double
    public var wash: Double
    public var maxForce: Double
    public var avgForce: Double
    public var maxForceAngle: Double
    public var peakPower: Double
    public var avgPower: Double
    public var work: Double
    public var strokeLength: Double
    public var effectiveLength: Double
}
```

**Usage in App:**
```swift
import CSVSwiftSDK

let csvData = try Data(contentsOf: fileURL)
let parser = CSVParser()
let profile = NKEmpowerProfile()

let session = try parser.parse(csvData, using: profile)
let warnings = profile.validate(session)

if !warnings.isEmpty {
    // Display warnings to user
    for warning in warnings {
        print("⚠️ \(warning)")
    }
}
```

**Benefits of Generic Architecture:**
1. **Reusability**: Same parser for NK, Garmin, Peach, future vendors
2. **Extensibility**: New CSV source = new profile (< 200 lines code)
3. **Testability**: Generic parser tested once, profiles tested independently
4. **Consistency**: Same API for all CSV sources
5. **Maintainability**: Bug fix in parser benefits all profiles

### Phase B: Temporal Alignment (`SyncEngine` Extension)

**Strategy: Dual-Path Synchronization**

Since Empower data is **per-stroke** (LF scale) and GoPro is **200Hz** (HF scale):

1. **Primary Anchor: GPS Track Correlation**
   - Use existing `GpsTrackCorrelator` (Haversine distance minimization)
   - Match NK CSV GPS coordinates with GPMF GPS track
   - Output: `offsetSeconds` (NK elapsed time → GoPro relative time)

2. **Secondary Validation: Stroke Rate Cross-Check**
   - Compare NK stroke rate with RDS `FusionEngine` stroke detection
   - Expected agreement: ±2 SPM (NK measures at oarlock, RDS at hull IMU)
   - Flag discrepancies for user review

3. **Temporal Mapping:**
   ```swift
   func mapStrokeToVideoTime(stroke: StrokeData, offset: TimeInterval) -> TimeInterval {
       return stroke.elapsedTime + offset
   }
   ```

**Integration with SessionDocument:**
```swift
struct SessionDocument: Codable {
    // ... existing fields
    var empowerData: NKEmpowerSession?
    var empowerSyncOffset: TimeInterval?  // Calculated by SyncEngine
}
```

### Phase C: Data Validation & Cross-Correlation

**Validation Strategy:**
1. **Stroke Count Agreement**: NK stroke count vs. FusionEngine stroke count (±5%)
2. **Power Correlation**: Compare NK Average Power with RDS derived power from `velocity × force_estimate`
3. **Angle Plausibility**: Reject outliers (catch angle > -30° or < -70°, etc.)
4. **Missing Data Handling**: ANT+ dropouts → `nil` values in Swift, rendered as gaps in UI

**Test Data Generation:**
```swift
func createMockEmpowerData(strokeCount: Int = 500) -> NKEmpowerSession {
    // Generate synthetic data with known characteristics for testing
}
```

### Phase D: Biomechanical Visualization Widgets

**New Widget Types for Rowing Desk:**

1. **Force Curve Widget** (`ForceCurveWidget.swift`)
   - X-axis: Oar angle (catch → finish)
   - Y-axis: Force (N)
   - Rendering: SwiftUI Canvas with `.drawingGroup()`
   - Real-time cursor synced to video playhead
   - Overlay: Reference curve (avg of last 10 strokes)

2. **Technique Efficiency Radar** (`TechniqueRadarWidget.swift`)
   - Polar plot: Effective length vs. wasted length (slip + wash)
   - Color gradient: Green (efficient) → Red (inefficient)
   - Per-stroke or per-interval average

3. **Force-Acceleration Scatter Plot** (`ForceAccelCorrelationWidget.swift`)
   - X-axis: NK Peak Force (N)
   - Y-axis: GoPro IMU Peak Surge Acceleration (m/s²)
   - Expected correlation: R² > 0.7 for consistent technique
   - Outliers flagged for review

4. **Stroke Metrics Table** (`StrokeMetricsTableWidget.swift`)
   - Virtualized list (1000+ strokes) using SwiftUI `List`
   - Columns: Stroke #, Time, Split, SR, Catch, Finish, Slip, Wash, Pwr, Work
   - Click → jump to stroke in video timeline

## 6. Alternative Force Measurement Systems

### 6.1 Peach PowerLine

**System Overview:**
- **Manufacturer:** [Peach Innovations](http://www.peachinnovations.com/)
- **Technology:** Proprietary oarlock with precision strain gauges (replaces Concept2 oarlock)
- **Metrics:** Forces, angles, speeds, boat motion, optional stretcher force and seat position
- **Data Output:** Proprietary format (CSV export available)
- **Accuracy:** Research shows **higher accuracy than Empower** for mean and stroke power ([Frontiers in Physiology](https://www.frontiersin.org/journals/physiology/articles/10.3389/fphys.2021.758015/full))

**Integration Feasibility:** ⚠️ **MEDIUM** - Requires reverse-engineering CSV format or vendor API access

### 6.2 SmartOar & Others

- **SmartOar**: Similar concept to Empower, ANT+ based
- **XBoat**: Additional telemetry option
- **ActiveSpeed (Active Tools)**: Speed-focused telemetry

**Market Adoption:** Empower and Peach dominate high-performance rowing (national teams, elite clubs)

**Recommendation:** Support NK Empower (CSV) for MVP. Add Peach PowerLine if user demand justifies reverse-engineering effort.

## 7. Native ANT+ Capture (Post-MVP Consideration)

### 7.1 Technical Constraints

**iOS/macOS ANT+ Limitations ([THIS IS ANT Documentation](https://www.thisisant.com/developer/ant/starting-your-project)):**
- **No Native Support**: iOS/macOS lack native ANT+ radio hardware
- **Bridge Required**: Must use third-party USB dongle (e.g., Wahoo RFLKT+, Garmin ANT+ adapter)
- **SDK Availability**:
  - Wahoo provides iOS SDK **only with Wahoo adapters**
  - Garmin does NOT provide iOS SDK ([Zwift Insider](https://zwiftinsider.com/ant-ios/))
  - Third-party libraries exist but unmaintained

**Complexity Assessment:**
- **Hardware Dependency**: Requires USB-C dongle → excludes iPad/iPhone without adapter
- **Licensing**: ANT+ Alliance membership required for commercial use
- **Development Effort**: 3-6 months for stable implementation
- **Maintenance Burden**: ANT+ protocol updates, adapter compatibility

### 7.2 Recommendation: Defer to Post-MVP

**Rationale:**
1. **CSV workflow is sufficient**: 95% of users export sessions post-training (not real-time)
2. **Hardware friction**: Dongle requirement reduces value proposition
3. **Development ROI**: Low compared to core features (video sync, fusion engine, AI analysis)
4. **Market trend**: Industry moving toward Bluetooth LE (future Empower versions may support BLE)

**If Pursued Later:**
- Evaluate Wahoo SDK + adapter bundle
- Consider BLE bridge devices (ANT+ → BLE converter)
- Monitor for native BLE support in future Empower hardware

## 8. Testing & Validation Strategy

### 8.1 Unit Tests

**Generic Parser Tests (`CSVParserTests.swift`):**
```swift
@Suite("Generic CSV Parser")
struct CSVParserTests {
    @Test("Parse RFC 4180 compliant CSV")
    func testRFC4180Parsing() throws {
        let csvData = """
        Name,Age,City
        "Doe, John",30,"New York"
        Jane Smith,25,Boston
        """.data(using: .utf8)!

        let parser = CSVParser()
        let rows = try parser.parseRFC4180(csvData)

        #expect(rows.count == 3)  // Header + 2 data rows
        #expect(rows[1][0] == "Doe, John")  // Quoted field
    }
}
```

**NK Empower Profile Tests (`NKEmpowerProfileTests.swift`):**
```swift
@Suite("NK Empower Profile")
struct NKEmpowerProfileTests {
    @Test("Parse valid NK Empower CSV with 500 strokes")
    func testValidCSVParsing() async throws {
        let csvData = loadMockCSV("empower_500strokes.csv")
        let parser = CSVParser()
        let profile = NKEmpowerProfile()

        let session = try parser.parse(csvData, using: profile)

        #expect(session.strokes.count == 500)
        #expect(session.metadata.duration > 0)
    }

    @Test("Detect format from headers")
    func testFormatDetection() {
        let headers = ["Stroke #", "Catch Angle", "Max Force", "Work"]
        let profile = NKEmpowerProfile()

        #expect(profile.matches(headers: headers, firstRow: []))
    }

    @Test("Unit conversion: lbs to Newtons")
    func testUnitConversion() throws {
        let csvData = loadMockCSV("empower_imperial_units.csv")
        let parser = CSVParser()
        let profile = NKEmpowerProfile()

        let session = try parser.parse(csvData, using: profile)

        // 100 lbs ≈ 444.8 N
        #expect(abs(session.strokes[0].maxForce - 444.8) < 1.0)
    }

    @Test("Validation: implausible catch angle")
    func testCatchAngleValidation() throws {
        var session = createMockEmpowerSession()
        session.strokes[0].catchAngle = -10  // Too shallow (should be -70 to -30)

        let profile = NKEmpowerProfile()
        let warnings = profile.validate(session)

        #expect(warnings.contains { $0 is .implausibleCatchAngle })
    }
}
```

### 8.2 Integration Tests (`EmpowerSyncTests.swift`)

```swift
@Suite("Empower Temporal Sync")
struct EmpowerSyncTests {
    @Test("GPS-based sync with GoPro GPMF")
    func testGPSSync() async throws {
        let gpmfData = loadMockGPMF("GX040246.MP4")
        let empowerData = loadMockEmpowerCSV("session_123.csv")

        let offset = try await SyncEngine.alignEmpowerToGPMF(
            empowerData,
            gpmfData
        )

        #expect(abs(offset) < 5.0)  // Within 5 seconds
    }
}
```

### 8.3 Real-World Validation

**Test Dataset Requirements:**
- ✅ **Minimum 10 sessions** with paired GoPro + NK Empower data
- ✅ **Variety:** Sculling/sweep, calm/rough water, steady-state/intervals
- ✅ **Ground Truth:** Manual event markers (e.g., "start of 1000m piece")

**Validation Metrics:**
- Sync accuracy: <2s temporal offset (user-acceptable threshold)
- Stroke count agreement: ±5% (NK vs. RDS FusionEngine)
- Power correlation: R² > 0.7 (NK power vs. RDS derived power)

## 9. Implementation Roadmap

### Phase 0: CSV SDK Foundation (Week 1-2)
- [ ] `csv-swift-sdk-main/` package setup (SPM)
- [ ] `CSVParser.swift`: Generic RFC 4180 parser with unit tests
- [ ] `CSVProfile` protocol definition
- [ ] Basic test fixtures (valid/invalid CSV files)

### Phase 1: NK Empower Profile + Integration (Month 1-2)
- [ ] `NKEmpowerProfile.swift`: 13-metric parser with unit tests
- [ ] Unit conversion logic (lbs→N, rad→deg)
- [ ] Validation rules (angles, temporal monotonicity)
- [ ] `SessionDocument` extension: Empower data storage
- [ ] Basic `SyncEngine` integration: GPS-based alignment
- [ ] Simple table widget: Display stroke metrics

### Phase 2: Visualization (Month 3-4)
- [ ] `ForceCurveWidget.swift`: Real-time force/angle plot
- [ ] `TechniqueRadarWidget.swift`: Efficiency visualization
- [ ] `ForceAccelCorrelationWidget.swift`: Cross-sensor analysis

### Phase 3: Validation & Polish (Month 5-6)
- [ ] Real-world testing with 10+ paired datasets
- [ ] Cross-correlation validation metrics
- [ ] User documentation and tutorial videos
- [ ] Export enhancements: Include Empower data in PDF reports

### Phase 4: Advanced Features (Post-MVP)
- [ ] Peach PowerLine CSV support (if user demand exists)
- [ ] ANT+ live capture (evaluate BLE bridge option)
- [ ] ML-based technique scoring using Empower + IMU fusion

## 10. Open Questions & Risks

### 10.1 Open Questions

1. **CSV Header Variations**: Do different NK LiNK versions use different column names/order?
   - **Mitigation**: Request sample CSVs from NK Sports support, build flexible parser with header detection

2. **Dual Oarlock Data**: How to handle port/starboard CSV files (sculling pairs)?
   - **Proposal**: Merge into single `SessionDocument` with `portData` and `starboardData` fields

3. **ANT+ Live Feasibility**: Will future Empower versions support BLE natively?
   - **Action**: Monitor NK product roadmap, engage with NK engineering if possible

### 10.2 Technical Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| CSV format changes | High | Low | Versioned parser with fallback |
| GPS sync failure (poor satellite coverage) | Medium | Medium | Manual alignment UI fallback |
| Stroke count mismatch (>10%) | Medium | Low | Flag for user review, allow manual override |
| Peach PowerLine user demand | Low | Medium | Defer until 5+ user requests |

## 11. Success Criteria

**MVP Success Metrics:**
- ✅ Parse 95%+ of real-world NK LiNK CSV exports without error
- ✅ Achieve <2s temporal sync accuracy with GoPro video
- ✅ Stroke count agreement ±5% between NK and RDS FusionEngine
- ✅ Force curve visualization renders at 60fps during video playback
- ✅ Zero crashes when handling malformed CSV data

**User Satisfaction:**
- ✅ Coaches report "game-changing" insight from force + video integration
- ✅ Export workflow (CSV import → sync → analysis) takes <5 minutes per session

---

## Sistemi Alternativi
- Peach PowerLine: Maggiore accuracy (research-backed), ma format proprietario
- SmartOar, XBoat, ActiveSpeed: Alternative minori
- Raccomandazione: NK Empower per MVP, Peach se richiesto da utenti


## References

- [NK Empower Oarlock Documentation](https://nksports.com/support/empower-oarlock/)
- [Rowsandall Empower Analysis](https://analytics.rowsandall.com/2019/03/27/rowsandall-and-the-empower-oarlock-part-1-intervals-flex-charts-and-force-curves/)
- [Concurrent Validity Study (Frontiers in Physiology)](https://www.frontiersin.org/journals/physiology/articles/10.3389/fphys.2021.758015/full)
- [ANT+ Developer Portal](https://www.thisisant.com/developer/ant/starting-your-project)
- [Peach Innovations](http://www.peachinnovations.com/)
- [Advancements in Rowing Sensor Tech (MDPI)](https://www.mdpi.com/2075-4663/12/9/254)

---

*Document Version: 3.0.0*
*Date: 2026-03-01*
*Last Updated By: Claude Sonnet 4.5*

**Revision History:**
- v1.0.0 (2026-02-28): Initial proposal
- v2.0.0 (2026-03-01): Added CSV format details, ANT+ feasibility analysis, Peach PowerLine comparison, comprehensive implementation roadmap, testing strategy, validation metrics, and risk assessment
- v3.0.0 (2026-03-01): **ARCHITECTURE CHANGE** - Replaced specific `NKEmpowerParser` with generic `csv-swift-sdk-main` module using profile pattern (inspired by FIT SDK). Supports multiple vendors (NK Empower, Garmin, Peach) with single parser + vendor-specific profiles. Updated code examples, testing strategy, and roadmap to reflect modular architecture.
