// Core/Services/FusionEngine.swift v1.1.0
/**
 * 6-step fusion pipeline orchestrator.
 * Transforms raw multi-source data into analyzable buffers, stroke events,
 * and per-stroke statistics.
 * --- Revision History ---
 * v1.1.0 - 2026-03-03 - Pass surgeAccel to stroke detection; add FIT cadence
 *          cross-validation diagnostic.
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Foundation

/// Orchestrates the 6-step fusion pipeline.
///
/// **Pipeline:**
/// - Step 0: Tilt Bias (from SyncEngine output)
/// - Step 1: Auto-Sync (from SyncEngine output)
/// - Step 1.5: Physics Prep (ACCL → G units, Gaussian smooth)
/// - Step 2: Fusion Loop (200 Hz: IMU + GPS interpolation + FIT sync + complementary filter)
/// - Step 3: Stroke Detection (state machine on detrended velocity)
/// - Step 4: Per-Stroke Aggregation
///
/// Source: `docs/specs/fusion-engine.md`
public struct FusionEngine {

    /// Runs the complete fusion pipeline.
    ///
    /// - Parameters:
    ///   - buffers: SensorDataBuffers with IMU raw channels populated (from GPMFAdapter)
    ///   - gpmfGps: GPMF GPS time series (for interpolation into fusion loop)
    ///   - fitTimeSeries: FIT time series (for HR, cadence, power sync)
    ///   - syncOutput: Sync pipeline output (tilt bias, SignMatch lag, FIT offset)
    /// - Returns: FusionResult with strokes, per-stroke stats, and diagnostics.
    public static func fuse(
        buffers: SensorDataBuffers,
        gpmfGps: GPMFGpsTimeSeries,
        fitTimeSeries: FITTimeSeries?,
        syncOutput: SyncEngine.Output
    ) -> FusionResult {
        let startTime = Date()
        let warnings = syncOutput.warnings

        let n = buffers.size
        guard n > 0 else {
            return emptyResult(warnings: warnings, startTime: startTime)
        }

        // STEP 0 + 1: Already computed in SyncEngine output

        // STEP 1.5: Physics Prep
        // - Convert ACCL surge to G units and subtract tilt bias
        // - Apply Gaussian smoothing (σ=4)
        let tiltBiasG = Float(syncOutput.tiltBias?.biasG ?? 0)
        var preparedAccel = ContiguousArray<Float>(repeating: .nan, count: n)
        for i in 0..<n {
            let raw = buffers.imu_raw_ts_acc_surge[i]
            if !raw.isNaN {
                // Convert m/s² to G, then subtract tilt bias
                preparedAccel[i] = raw / Float(SyncConstants.standardGravity) - tiltBiasG
            }
        }
        let filteredAccel = DSP.gaussianSmooth(
            preparedAccel, sigma: FusionConstants.physPrepGaussianSigma
        )
        // Store filtered accel back into buffers
        buffers.imu_flt_ts_acc_surge = filteredAccel

        // STEP 2: Fusion Loop (200 Hz)
        // 2a) IMU raw/filtered already in buffers
        // 2b) GYRO/GRAV already interpolated by GPMFAdapter
        // 2c) Pitch/Roll from gravity
        computePitchRoll(buffers: buffers)

        // 2d) Synchronize GPS with applied lag
        let gpsLagMs = syncOutput.signMatch?.accepted == true
            ? syncOutput.signMatch!.lagMs : 0
        interpolateGps(
            buffers: buffers,
            gpmfGps: gpmfGps,
            lagMs: gpsLagMs
        )

        // 2e) Synchronize FIT records
        let fitOffsetMs = syncOutput.fitGpmfSync.offset * 1000.0
        if let fit = fitTimeSeries {
            interpolateFit(
                buffers: buffers,
                fitTimeSeries: fit,
                fitOffsetMs: fitOffsetMs
            )
        }

        // 2f) Complementary filter: fuse IMU accel + GPS speed → velocity
        // Convert filtered G back to m/s² for integration
        var accelMps2 = ContiguousArray<Float>(repeating: .nan, count: n)
        for i in 0..<n {
            let g = filteredAccel[i]
            if !g.isNaN {
                accelMps2[i] = g * Float(SyncConstants.standardGravity)
            }
        }

        let initialVelocity: Double
        if let firstGpsSpeed = gpmfGps.speed.first(where: { !$0.isNaN }) {
            initialVelocity = Double(firstGpsSpeed)
        } else {
            initialVelocity = 0
        }

        buffers.fus_cal_ts_vel_inertial = ComplementaryFilter.fuse(
            accelMps2: accelMps2,
            gpsSpeed: buffers.gps_gpmf_ts_speed,
            initialVelocity: initialVelocity
        )

        // STEP 3: Stroke Detection (multi-validated)
        let sampleRate = FusionConstants.imuSampleRate
        let strokes = DSP.detectStrokes(
            timestampsMs: buffers.timestamp,
            velocity: buffers.fus_cal_ts_vel_inertial,
            surgeAccel: buffers.imu_flt_ts_acc_surge,
            sampleRate: sampleRate
        )

        // Write stroke indices into buffers
        for stroke in strokes {
            let si = max(stroke.startIndex, 0)
            let ei = min(stroke.endIndex, n - 1)
            for j in si...ei {
                buffers.strokeIndex[j] = Int32(stroke.index)
            }
        }

        // STEP 4: Per-Stroke Aggregation
        let perStrokeStats = StrokeAggregator.aggregate(
            strokes: strokes,
            buffers: buffers
        )

        // FIT cadence cross-validation
        var cadenceAgreement: Double? = nil
        var mutableWarnings = warnings
        if let fit = fitTimeSeries {
            cadenceAgreement = validateStrokeRateWithCadence(
                strokes: strokes,
                fitTimeSeries: fit,
                fitOffsetMs: fitOffsetMs,
                bufferTimestamps: buffers.timestamp
            )
            if let agreement = cadenceAgreement, agreement < 0.5, !strokes.isEmpty {
                mutableWarnings.append(
                    "Stroke rate disagrees with FIT cadence: "
                    + "only \(Int(agreement * 100))% of strokes match (±\(Int(FusionConstants.strokeDetCadenceToleranceSPM)) SPM)"
                )
            }
        }

        // Build diagnostics
        let validStrokes = strokes.filter(\.isValid)
        let avgStrokeRate = validStrokes.isEmpty ? nil
            : validStrokes.map(\.strokeRate).reduce(0, +) / Double(validStrokes.count)

        let convergenceTime = ComplementaryFilter.convergenceTime()

        let diagnostics = FusionDiagnostics(
            tiltBias: syncOutput.tiltBias.map(\.biasG),
            convergenceTime: convergenceTime,
            gpsQuality: gpsQuality(gpmfGps: gpmfGps, bufferSize: n),
            imuQuality: imuQuality(buffers: buffers),
            strokeCount: strokes.count,
            validStrokeCount: validStrokes.count,
            avgStrokeRate: avgStrokeRate,
            imuGpsLagMs: syncOutput.signMatch?.lagMs,
            cadenceAgreement: cadenceAgreement,
            warnings: mutableWarnings
        )

        let processingDuration = Date().timeIntervalSince(startTime)

        return FusionResult(
            strokes: strokes,
            perStrokeStats: perStrokeStats,
            diagnostics: diagnostics,
            processingDuration: processingDuration,
            algorithmVersion: FusionConstants.algorithmVersion
        )
    }

    // MARK: - Step 2c: Pitch/Roll from Gravity

    /// Computes pitch and roll from gravity vector using atan2.
    private static func computePitchRoll(buffers: SensorDataBuffers) {
        for i in 0..<buffers.size {
            let gx = buffers.imu_raw_ts_grav_x[i]
            let gy = buffers.imu_raw_ts_grav_y[i]
            let gz = buffers.imu_raw_ts_grav_z[i]

            guard !gx.isNaN, !gy.isNaN, !gz.isNaN else { continue }

            // Pitch = atan2(gy, gz) — rotation around X axis
            buffers.fus_cal_ts_pitch[i] = atan2(gy, gz) * (180.0 / .pi)
            // Roll = atan2(-gx, sqrt(gy² + gz²))
            buffers.fus_cal_ts_roll[i] = atan2(-gx, sqrt(gy * gy + gz * gz)) * (180.0 / .pi)
        }
    }

    // MARK: - Step 2d: GPS Interpolation

    /// Interpolates GPS data onto IMU timeline with lag correction.
    private static func interpolateGps(
        buffers: SensorDataBuffers,
        gpmfGps: GPMFGpsTimeSeries,
        lagMs: Double
    ) {
        guard !gpmfGps.timestampsMs.isEmpty else { return }

        for i in 0..<buffers.size {
            let t = buffers.timestamp[i] - lagMs  // Correct for GPS lag

            // Speed (linear interpolation)
            buffers.gps_gpmf_ts_speed[i] = DSP.interpolateAt(
                timestamps: gpmfGps.timestampsMs,
                values: gpmfGps.speed,
                targetTime: t
            )

            // Lat/Lon (nearest neighbor for coordinates)
            let idx = DSP.binarySearchFloor(gpmfGps.timestampsMs, target: t)
            if idx >= 0, idx < gpmfGps.latitude.count {
                buffers.gps_gpmf_ts_lat[i] = gpmfGps.latitude[idx]
                buffers.gps_gpmf_ts_lon[i] = gpmfGps.longitude[idx]
            }
        }
    }

    // MARK: - Step 2e: FIT Interpolation

    /// Synchronizes FIT metrics onto IMU timeline.
    private static func interpolateFit(
        buffers: SensorDataBuffers,
        fitTimeSeries: FITTimeSeries,
        fitOffsetMs: Double
    ) {
        guard !fitTimeSeries.timestampsMs.isEmpty else {
            print("[FusionEngine] interpolateFit: FIT timestampsMs is empty — skipping HR sync")
            return
        }

        let validHR = fitTimeSeries.heartRate.filter { !$0.isNaN }
        let fitOriginMs = fitTimeSeries.timestampsMs.first(where: { !$0.isNaN }) ?? 0
        let fitEndMs   = fitTimeSeries.timestampsMs.last(where:  { !$0.isNaN }) ?? 0
        print("[FusionEngine] interpolateFit: \(fitTimeSeries.timestampsMs.count) FIT records, \(validHR.count) valid HR values, fitOriginMs=\(fitOriginMs), fitEndMs=\(fitEndMs), fitOffsetMs=\(fitOffsetMs)")
        if let minHR = validHR.min(), let maxHR = validHR.max() {
            print("[FusionEngine] HR range: \(minHR)–\(maxHR) bpm")
        } else {
            print("[FusionEngine] HR: all NaN in FIT time series")
        }
        print("[FusionEngine] GPMF buffer: \(buffers.size) samples, t[0]=\(buffers.timestamp.first ?? .nan) t[last]=\(buffers.timestamp.last ?? .nan)")

        // offsetMs semantic (from GpsSpeedCorrelator / GpsTrackCorrelator):
        //   offsetMs = fitStart - gpmfStart + lag
        // where gpmfStart is relative (0-based camera clock) and fitStart is Unix epoch ms.
        // So fitOffsetMs ≈ fitStart + small lag correction.
        // To map a GPMF relative time t to FIT absolute epoch: fitAbsoluteTime = fitOffsetMs + t.

        for i in 0..<buffers.size {
            let targetFitMs = fitOffsetMs + buffers.timestamp[i]

            // Heart rate (nearest-neighbor — 1 Hz is coarse)
            buffers.phys_ext_ts_hr[i] = DSP.interpolateAt(
                timestamps: fitTimeSeries.timestampsMs,
                values: fitTimeSeries.heartRate,
                targetTime: targetFitMs
            )
        }
    }

    // MARK: - Quality Metrics

    /// Estimates GPS data quality (0–1) based on coverage.
    private static func gpsQuality(gpmfGps: GPMFGpsTimeSeries, bufferSize: Int) -> Double {
        guard bufferSize > 0, !gpmfGps.speed.isEmpty else { return 0 }
        let validCount = gpmfGps.speed.reduce(0) { $0 + ($1.isNaN ? 0 : 1) }
        let coverage = Double(validCount) / Double(gpmfGps.speed.count)
        return min(coverage, 1.0)
    }

    /// Estimates IMU data quality (0–1) based on coverage and noise.
    private static func imuQuality(buffers: SensorDataBuffers) -> Double {
        guard buffers.size > 0 else { return 0 }
        var validCount = 0
        for i in 0..<buffers.size {
            if !buffers.imu_raw_ts_acc_surge[i].isNaN { validCount += 1 }
        }
        return Double(validCount) / Double(buffers.size)
    }

    // MARK: - FIT Cadence Cross-Validation

    /// Compares detected stroke rates against FIT cadence data.
    ///
    /// For each stroke, interpolates FIT cadence at the stroke midpoint and
    /// checks if the detected stroke rate agrees within tolerance.
    ///
    /// - Returns: Fraction of strokes that agree (0.0–1.0), or `nil` if no valid cadence data.
    private static func validateStrokeRateWithCadence(
        strokes: [StrokeEvent],
        fitTimeSeries: FITTimeSeries,
        fitOffsetMs: Double,
        bufferTimestamps: ContiguousArray<Double>
    ) -> Double? {
        guard !strokes.isEmpty, !fitTimeSeries.cadence.isEmpty else { return nil }

        // Check if FIT cadence has any valid (non-NaN) data
        let hasValidCadence = fitTimeSeries.cadence.contains(where: { !$0.isNaN })
        guard hasValidCadence else { return nil }

        let fitOriginMs = fitTimeSeries.timestampsMs.first(where: { !$0.isNaN }) ?? 0
        let tolerance = FusionConstants.strokeDetCadenceToleranceSPM
        var agreementCount = 0
        var comparedCount = 0

        for stroke in strokes {
            // Stroke midpoint in GPMF timeline (ms)
            let midpointMs = (stroke.startTime + stroke.endTime) / 2.0 * 1000.0
            // Convert to FIT timeline
            let targetFitMs = midpointMs + fitOriginMs - fitOffsetMs

            let fitCadence = DSP.interpolateAt(
                timestamps: fitTimeSeries.timestampsMs,
                values: fitTimeSeries.cadence,
                targetTime: targetFitMs
            )

            guard !fitCadence.isNaN else { continue }

            comparedCount += 1
            if abs(stroke.strokeRate - Double(fitCadence)) <= tolerance {
                agreementCount += 1
            }
        }

        guard comparedCount > 0 else { return nil }
        return Double(agreementCount) / Double(comparedCount)
    }

    // MARK: - Empty Result

    private static func emptyResult(warnings: [String], startTime: Date) -> FusionResult {
        FusionResult(
            strokes: [],
            perStrokeStats: [],
            diagnostics: FusionDiagnostics(warnings: warnings),
            processingDuration: Date().timeIntervalSince(startTime),
            algorithmVersion: FusionConstants.algorithmVersion
        )
    }
}
