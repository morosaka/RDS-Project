# Empower Oarlock (NK/Empacher) Sensor Integration Proposal

## 1. Overview
Empower Oarlocks by Nielsen-Kellerman (NK) represent the premium tier of rowing instrumentation. These devices replace standard oarlocks and use strain gauges and angle sensors to measure the direct mechanical interaction between the athlete and the boat.

Integrating these sensors into RowData Studio (RDS) bridges the gap between **Input (Force/Power)** and **Output (Acceleration/Speed/Video)**, providing a truly comprehensive biomechanical laboratory on-device.

## 2. Sensor Ecosystem
- **Hardware**: Empower Oarlock (Single or Pairs).
- **Communication**: ANT+ (Proprietary Profile).
- **Receiver**: NK SpeedCoach GPS 2 (requires Training Pack firmware).
- **Secondary Sync**: NK LiNK Logbook app (iOS/Android/Desktop).

## 3. Data Extraction Constraints
A critical technical constraint has been identified for the MVP:
- **FIT Files**: Standard .FIT files exported by the SpeedCoach for platforms like Strava or Garmin **do not** typically contain detailed Oarlock metrics.
- **CSV Export**: The **NK LiNK Logbook CSV export** is the primary and most reliable source for per-stroke biomechanical data (angles, force, wash, work).

## 4. Key Metrics for Integration
RDS will map the following data points from the NK CSV file to our internal nomenclature:

| NK Metric | RDS Nomenclature Mapping | Description |
|-----------|--------------------------|-------------|
| Catch Angle | `mech_ext_str_angle_catch` | Oar angle at the moment of blade entry |
| Finish Angle | `mech_ext_str_angle_finish` | Oar angle at the moment of blade exit |
| Slip | `mech_ext_str_eval_slip` | Angle lost during the catch phase |
| Wash | `mech_ext_str_eval_wash` | Angle lost during the finish phase |
| Peak Force | `mech_ext_str_force_peak` | Maximum force applied during the drive |
| Average Force | `mech_ext_str_force_avg` | Mean force across the drive phase |
| Work | `mech_ext_str_work` | Cumulative energy per stroke (Joules) |
| Power | `mech_ext_str_power` | Instantaneous mechanical power (Watts) |

## 5. Implementation Strategy

### Phase A: CSV Parser Module
Develop a dedicated parser within `app/Core/Services` to ingest NK LiNK CSV files.
1. **Validation**: Check headers and units (Degrees vs Radians, Lbs vs Kg).
2. **Buffering**: Store data in stroke-indexed arrays within the `SensorDataBuffers`.
3. **Nomenclature**: Register metrics in the `MetricDef` system for UI consumption.

### Phase B: GPS-Based Temporal Alignment
Since both NK SpeedCoach and GoPro HERO record GPS tracks with absolute UTC timestamps, the `SyncEngine` will use the GPS traccia as the "Temporal Bridge":
- **Anchor**: Match GPS timestamps from the NK CSV with GPSU/GPS9 timestamps from the GoPro GPMF stream.
- **Offset**: Calculate and apply the temporal offset to all NK metrics to sync with the video playhead.

### Phase C: Biomechanical Visualization
New specialized widgets for the **Rowing Desk**:
- **Force Curve Widget**: Real-time rendering of the force/angle curve synced to the video playhead.
- **Technique Radar**: A visual summary of "effective length" (Catch to Finish) versus "wasted length" (Slip + Wash).
- **Correlation Charts**: Automated scatter plots of Peak Force (Sensors) vs. Surge Acceleration (GoPro IMU).

## 6. Future Roadmap: Native ANT+ Capture
To streamline the user experience, RDS could eventually act as a direct ANT+ host (via USB dongle or native hardware), capturing Oarlock data live and bypassing the need for manual CSV export from NK LiNK.

---
*Document Version: 1.0.0*
*Date: 2026-02-28*
*Author: RowData Studio AI Assistant*
