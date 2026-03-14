// Rendering/DataContext.swift v1.4.0
/**
 * Shared observable data reference for rendering widgets.
 * Holds the processed session buffers, fusion result, and active SessionDocument.
 * --- Revision History ---
 * v1.4.0 - 2026-03-14 - Add waveformPeaks for AudioTrackWidget (Phase 8c DataContext wiring).
 * v1.3.0 - 2026-03-12 - Default metric → gps_gpmf_ts_speed; add imu_raw_ts_vel_inertial
 *                        computed channel (trapezoidal integration of raw ACCL-Y at 200 Hz).
 * v1.2.0 - 2026-03-08 - Add sessionDocument for Phase 6 canvas integration.
 * v1.1.0 - 2026-03-07 - Switch from @Observable (macOS 14+) to ObservableObject (macOS 13+).
 * v1.0.0 - 2026-03-07 - Initial implementation (Phase 4: Rendering + MVP).
 */

import Combine
import Foundation

/// Shared session data for all rendering widgets.
///
/// Widgets read from `DataContext` to access sensor buffers and select
/// which metric to display. Mutations only happen after pipeline processing
/// completes (file import → sync → fusion).
///
/// **Isolation:** `@MainActor` — all reads and writes happen on the main thread,
/// which matches SwiftUI's rendering thread.
@MainActor
public final class DataContext: ObservableObject {

    // MARK: - Session Data

    /// Active SessionDocument (loaded from SessionStore or created on import).
    /// `nil` before a session is opened.
    @Published public var sessionDocument: SessionDocument?

    /// Processed sensor buffers (SoA). `nil` before first file import.
    @Published public var buffers: SensorDataBuffers?

    /// Fusion pipeline result (strokes, per-stroke stats, diagnostics). `nil` before processing.
    @Published public var fusionResult: FusionResult?

    /// Total session duration in milliseconds. Derived from last valid timestamp.
    @Published public var sessionDurationMs: Double = 0

    /// Multi-resolution waveform peak pyramid for the primary audio track.
    /// Populated by `FileImportHelper` after the `.waveform.gz` sidecar is loaded.
    /// `nil` until the sidecar exists and has been decoded.
    @Published public var waveformPeaks: WaveformPeaks?

    // MARK: - Display State

    /// Key of the currently selected metric channel for the line chart.
    ///
    /// Valid keys: "gps_gpmf_ts_speed", "fus_cal_ts_vel_inertial",
    /// "imu_raw_ts_acc_surge", "imu_raw_ts_vel_inertial",
    /// "imu_flt_ts_acc_surge", "phys_ext_ts_hr".
    @Published public var selectedMetric: String = "gps_gpmf_ts_speed"

    public init() {}

    // MARK: - Accessors

    /// Timestamp array from the current buffers (nil if no session loaded).
    public var timestamps: ContiguousArray<Double>? {
        buffers?.timestamp
    }

    /// Value array for the currently selected metric (nil if no session loaded).
    public var selectedValues: ContiguousArray<Float>? {
        values(for: selectedMetric)
    }

    /// Returns values for a named metric channel.
    ///
    /// Returns `nil` if no buffers are loaded or the key is unknown.
    public func values(for key: String) -> ContiguousArray<Float>? {
        guard let b = buffers else { return nil }
        switch key {
        case "gps_gpmf_ts_speed":        return b.gps_gpmf_ts_speed
        case "fus_cal_ts_vel_inertial":  return b.fus_cal_ts_vel_inertial
        case "imu_raw_ts_acc_surge":     return b.imu_raw_ts_acc_surge
        case "imu_raw_ts_vel_inertial":
            // Inertial velocity derived from raw IMU surge (ACCL-Y) via trapezoidal
            // integration at the nominal 200 Hz IMU sample rate (dt = 5 ms).
            // Useful for debugging the comb artifact independent of the fusion filter.
            return DSP.integrate(b.imu_raw_ts_acc_surge, dt: 0.005)
        case "imu_flt_ts_acc_surge":     return b.imu_flt_ts_acc_surge
        case "phys_ext_ts_hr":           return b.phys_ext_ts_hr
        default:                          return b.dynamic[key]
        }
    }
}
