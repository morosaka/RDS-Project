// Core/Services/FusionEngineTests.swift v1.0.0
/**
 * Integration tests for the 6-step fusion engine.
 * Uses synthetic data to verify the complete pipeline.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Foundation
import Testing
@testable import RowDataStudio

@Suite("FusionEngine Integration")
struct FusionEngineTests {

    /// Creates a synthetic dataset mimicking a 30-second rowing session.
    private static func syntheticSession() -> (
        buffers: SensorDataBuffers,
        gpmfGps: GPMFGpsTimeSeries,
        fitTimeSeries: FITTimeSeries,
        syncOutput: SyncEngine.Output
    ) {
        let durationS = 30.0
        let sampleRate = 200.0
        let n = Int(durationS * sampleRate)

        let buffers = SensorDataBuffers(size: n)

        // Rowing velocity: 4 m/s base + sinusoidal strokes at 30 SPM
        let strokeFreqHz = 30.0 / 60.0
        for i in 0..<n {
            let tS = Double(i) / sampleRate
            let tMs = tS * 1000.0
            buffers.timestamp[i] = tMs

            // ACCL surge = derivative of velocity (sinusoidal pattern)
            let acc = 1.5 * 2.0 * .pi * strokeFreqHz * cos(2.0 * .pi * strokeFreqHz * tS)
            buffers.imu_raw_ts_acc_surge[i] = Float(acc)
            buffers.imu_raw_ts_acc_sway[i] = 0
            buffers.imu_raw_ts_acc_heave[i] = Float(9.81)

            // GYRO
            buffers.imu_raw_ts_gyro_pitch[i] = Float(5.0 * sin(2.0 * .pi * strokeFreqHz * tS))
            buffers.imu_raw_ts_gyro_roll[i] = Float(2.0 * sin(2.0 * .pi * strokeFreqHz * tS))
            buffers.imu_raw_ts_gyro_yaw[i] = 0

            // Gravity (slight tilt)
            buffers.imu_raw_ts_grav_x[i] = 0
            buffers.imu_raw_ts_grav_y[i] = Float(sin(3.0 * .pi / 180.0) * 9.81)
            buffers.imu_raw_ts_grav_z[i] = Float(cos(3.0 * .pi / 180.0) * 9.81)
        }

        // GPS (10 Hz)
        let gpsN = Int(durationS * 10)
        var gpsTs = ContiguousArray<Double>(repeating: 0, count: gpsN)
        var gpsSpeed = ContiguousArray<Float>(repeating: 0, count: gpsN)
        var gpsLat = ContiguousArray<Double>(repeating: 0, count: gpsN)
        var gpsLon = ContiguousArray<Double>(repeating: 0, count: gpsN)
        for i in 0..<gpsN {
            let tS = Double(i) * 0.1
            gpsTs[i] = tS * 1000.0
            gpsSpeed[i] = Float(4.0 + 1.5 * sin(2.0 * .pi * strokeFreqHz * tS))
            gpsLat[i] = 45.43 + tS * 0.000036  // ~4 m/s northward
            gpsLon[i] = 12.34
        }
        let gpmfGps = GPMFGpsTimeSeries(
            timestampsMs: gpsTs, speed: gpsSpeed,
            latitude: gpsLat, longitude: gpsLon
        )

        // FIT (1 Hz) — optional
        let fitN = Int(durationS)
        var fitTs = ContiguousArray<Double>(repeating: 0, count: fitN)
        var fitHR = ContiguousArray<Float>(repeating: 0, count: fitN)
        for i in 0..<fitN {
            fitTs[i] = Double(i) * 1000.0
            fitHR[i] = Float(150 + i % 10)
        }
        let fitTimeSeries = FITTimeSeries(
            timestampsMs: fitTs,
            speed: ContiguousArray<Float>(repeating: 4.0, count: fitN),
            latitude: ContiguousArray<Double>(repeating: 45.43, count: fitN),
            longitude: ContiguousArray<Double>(repeating: 12.34, count: fitN),
            heartRate: fitHR,
            cadence: ContiguousArray<Float>(repeating: .nan, count: fitN),
            power: ContiguousArray<Float>(repeating: .nan, count: fitN),
            distance: ContiguousArray<Float>(repeating: .nan, count: fitN)
        )

        // Minimal sync output (pre-computed)
        let syncOutput = SyncEngine.Output(
            tiltBias: TiltBiasEstimator.Result(
                biasMps2: 0.513, biasG: 0.0523,
                avgImuSurge: 0.513, avgGpsAccel: 0
            ),
            signMatch: SignMatchStrategy.Result(lagMs: 200, score: 0.5, accepted: true),
            speedCorrelation: nil,
            trackCorrelation: nil,
            fitGpmfSync: SyncResult(offset: 0, confidence: 1.0, strategy: .signMatch),
            warnings: []
        )

        return (buffers, gpmfGps, fitTimeSeries, syncOutput)
    }

    @Test("Full fusion pipeline produces strokes")
    func fullPipelineProducesStrokes() {
        let (buffers, gps, fit, sync) = Self.syntheticSession()

        let result = FusionEngine.fuse(
            buffers: buffers,
            gpmfGps: gps,
            fitTimeSeries: fit,
            syncOutput: sync
        )

        // Should detect some strokes (30 SPM × 30s = ~15, allow wide margin)
        #expect(result.strokes.count >= 3,
                "Expected strokes, got \(result.strokes.count)")
        #expect(result.perStrokeStats.count == result.strokes.count)
    }

    @Test("Diagnostics are populated")
    func diagnosticsPopulated() {
        let (buffers, gps, fit, sync) = Self.syntheticSession()

        let result = FusionEngine.fuse(
            buffers: buffers, gpmfGps: gps,
            fitTimeSeries: fit, syncOutput: sync
        )

        #expect(result.diagnostics.tiltBias != nil)
        #expect(result.diagnostics.imuGpsLagMs != nil)
        #expect(result.diagnostics.gpsQuality != nil)
        #expect(result.diagnostics.imuQuality != nil)
        #expect(result.processingDuration >= 0)
        #expect(result.algorithmVersion == FusionConstants.algorithmVersion)
    }

    @Test("Pitch and roll are computed from gravity")
    func pitchRollComputed() {
        let (buffers, gps, fit, sync) = Self.syntheticSession()

        _ = FusionEngine.fuse(
            buffers: buffers, gpmfGps: gps,
            fitTimeSeries: fit, syncOutput: sync
        )

        // Verify pitch/roll are populated (not NaN)
        var nonNanPitch = 0
        for i in 0..<buffers.size {
            if !buffers.fus_cal_ts_pitch[i].isNaN { nonNanPitch += 1 }
        }
        #expect(nonNanPitch > buffers.size / 2,
                "Expected most pitch values to be computed")
    }

    @Test("Velocity is fused from IMU and GPS")
    func velocityFused() {
        let (buffers, gps, fit, sync) = Self.syntheticSession()

        _ = FusionEngine.fuse(
            buffers: buffers, gpmfGps: gps,
            fitTimeSeries: fit, syncOutput: sync
        )

        // Velocity should be populated and in reasonable range
        var validVel = 0
        for i in 0..<buffers.size {
            let v = buffers.fus_cal_ts_vel_inertial[i]
            if !v.isNaN && v > 0 && v < 20 { validVel += 1 }
        }
        #expect(validVel > buffers.size / 2,
                "Expected most velocity values to be valid, got \(validVel)/\(buffers.size)")
    }

    @Test("Empty buffers produce empty result")
    func emptyBuffers() {
        let buffers = SensorDataBuffers(size: 0)
        let gps = GPMFGpsTimeSeries(
            timestampsMs: ContiguousArray<Double>(),
            speed: ContiguousArray<Float>(),
            latitude: ContiguousArray<Double>(),
            longitude: ContiguousArray<Double>()
        )
        let sync = SyncEngine.Output(
            tiltBias: nil, signMatch: nil,
            speedCorrelation: nil, trackCorrelation: nil,
            fitGpmfSync: SyncResult(offset: 0, confidence: 0, strategy: .none),
            warnings: []
        )

        let result = FusionEngine.fuse(
            buffers: buffers, gpmfGps: gps,
            fitTimeSeries: nil, syncOutput: sync
        )

        #expect(result.strokes.isEmpty)
        #expect(result.perStrokeStats.isEmpty)
    }
}
