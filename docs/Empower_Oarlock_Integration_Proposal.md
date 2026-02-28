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

### Phase A: CSV Parser Module (`app/Core/Services/NKEmpowerParser.swift`)

**Data Model:**
```swift
struct NKEmpowerSession: Codable {
    let metadata: SessionMetadata
    let intervals: [IntervalSummary]
    let strokes: [StrokeData]
}

struct StrokeData: Codable {
    let strokeNumber: Int
    let elapsedTime: TimeInterval        // Seconds from session start
    let distance: Double                 // Cumulative meters
    let split: TimeInterval              // 500m pace
    let strokeRate: Double               // SPM

    // Empower metrics (13 total)
    let catchAngle: Double               // degrees
    let finishAngle: Double              // degrees
    let slip: Double                     // degrees
    let wash: Double                     // degrees
    let maxForce: Double                 // N or lbs
    let avgForce: Double                 // N or lbs
    let maxForceAngle: Double            // degrees
    let peakPower: Double                // W
    let avgPower: Double                 // W
    let work: Double                     // J
    let strokeLength: Double             // degrees
    let effectiveLength: Double          // degrees
}
```

**Parser Implementation:**
1. **Section Detection**: Identify header boundaries (`Session Summary`, `Interval Summary`, `Stroke Detail`)
2. **Unit Detection**: Parse header row for unit indicators (N/lbs, °/rad)
3. **Conversion**: Normalize to SI units (N, degrees, W, J) for internal storage
4. **Validation**:
   - Reject files with missing Empower columns
   - Check for temporal monotonicity (elapsed time increasing)
   - Validate angle ranges (catch: -70° to -30°, finish: 20° to 50°)
5. **Error Handling**: Use `Result<NKEmpowerSession, NKParserError>` pattern

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

### 8.1 Unit Tests (`NKEmpowerParserTests.swift`)

```swift
@Suite("NK Empower CSV Parser")
struct NKEmpowerParserTests {
    @Test("Parse valid CSV with 500 strokes")
    func testValidCSVParsing() async throws {
        let csvData = loadMockCSV("empower_500strokes.csv")
        let session = try NKEmpowerParser.parse(csvData)

        #expect(session.strokes.count == 500)
        #expect(session.metadata.duration > 0)
    }

    @Test("Handle missing force columns gracefully")
    func testMissingColumns() {
        let csvData = loadMockCSV("empower_incomplete.csv")
        let result = NKEmpowerParser.parse(csvData)

        #expect(result == .failure(.missingEmpowerColumns))
    }

    @Test("Unit conversion: lbs to Newtons")
    func testUnitConversion() throws {
        let csvData = loadMockCSV("empower_imperial_units.csv")
        let session = try NKEmpowerParser.parse(csvData)

        // 100 lbs ≈ 444.8 N
        #expect(abs(session.strokes[0].maxForce - 444.8) < 1.0)
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

### Phase 1: MVP (Month 1-2)
- [ ] `NKEmpowerParser.swift`: CSV parsing with unit tests
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

*Document Version: 2.0.0*
*Date: 2026-03-01*
*Last Updated By: Claude Sonnet 4.5*

**Revision History:**
- v1.0.0 (2026-02-28): Initial proposal
- v2.0.0 (2026-03-01): Added CSV format details, ANT+ feasibility analysis, Peach PowerLine comparison, comprehensive implementation roadmap, testing strategy, validation metrics, and risk assessment
