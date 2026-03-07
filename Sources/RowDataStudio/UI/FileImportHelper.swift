// UI/FileImportHelper.swift v1.0.0
/**
 * Async orchestrator: file import → GPMF/FIT parse → sync → fusion → DataContext.
 * Runs heavy work on a detached task; updates DataContext on @MainActor.
 * --- Revision History ---
 * v1.0.0 - 2026-03-07 - Initial implementation (Phase 4: Rendering + MVP).
 */

import Foundation

/// Errors produced during file import and processing.
public enum FileImportError: LocalizedError, Sendable {
    case gpmfExtractionFailed(String)
    case fitDecodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .gpmfExtractionFailed(let msg): return "GPMF extraction failed: \(msg)"
        case .fitDecodeFailed(let msg):      return "FIT decode failed: \(msg)"
        }
    }
}

/// Orchestrates the full import pipeline: file I/O → parse → sync → fusion.
///
/// All heavy work runs on a `Task.detached` background thread.
/// `DataContext` and `PlayheadController` are updated on the main actor
/// after processing completes.
///
/// **Pipeline:**
/// 1. GPMF extract → `SensorDataBuffers` + GPS/ACCL time series (via `GPMFAdapter.extractAll`)
/// 2. (Optional) FIT decode → `FITTimeSeries`
/// 3. Sync (Steps 0-3 with FIT; Steps 0-1 GPMF-only without FIT)
/// 4. Fusion (6-step pipeline → strokes, per-stroke stats, fused velocity)
/// 5. Update `DataContext` + `PlayheadController` on main actor
public enum FileImportHelper {

    // MARK: - Public Entry Point

    /// Runs the full import pipeline and updates the given context objects.
    ///
    /// - Parameters:
    ///   - videoURL: URL of the GoPro MP4 file.
    ///   - fitURL: Optional URL of a companion FIT file (NK SpeedCoach / Garmin).
    ///   - dataContext: Observable context to update after processing.
    ///   - playhead: Playhead controller whose `duration` is set after processing.
    /// - Throws: `FileImportError` on parse failure.
    @MainActor
    public static func process(
        videoURL: URL,
        fitURL: URL?,
        dataContext: DataContext,
        playhead: PlayheadController
    ) async throws {
        // All heavy work on a background thread. Only Sendable (URL) values captured.
        let (buffers, fusionResult, durationMs) = try await Task.detached(priority: .userInitiated) {
            try runPipeline(videoURL: videoURL, fitURL: fitURL)
        }.value

        // Back on @MainActor: update observable state.
        dataContext.buffers = buffers
        dataContext.fusionResult = fusionResult
        dataContext.sessionDurationMs = durationMs
        playhead.duration = durationMs
    }

    // MARK: - Background Pipeline

    private static func runPipeline(
        videoURL: URL,
        fitURL: URL?
    ) throws -> (SensorDataBuffers, FusionResult, Double) {

        // STEP 1: GPMF extraction — returns only app-layer types (no SDK types exposed here)
        let buffers: SensorDataBuffers
        let gpmfGps: GPMFGpsTimeSeries
        let gpmfAccel: GPMFAccelTimeSeries
        do {
            let extracted = try GPMFAdapter.extractAll(from: videoURL)
            buffers   = extracted.buffers
            gpmfGps   = extracted.gpsTimeSeries
            gpmfAccel = extracted.accelTimeSeries
        } catch {
            throw FileImportError.gpmfExtractionFailed(error.localizedDescription)
        }

        // STEP 2: FIT decode (optional)
        var fitTimeSeries: FITTimeSeries? = nil
        if let fitURL {
            do {
                let messages = try FITAdapter.decode(from: fitURL)
                fitTimeSeries = FITAdapter.toTimeSeries(from: messages)
            } catch {
                throw FileImportError.fitDecodeFailed(error.localizedDescription)
            }
        }

        // STEP 3: Sync pipeline
        let syncOutput: SyncEngine.Output
        if let fit = fitTimeSeries {
            // Full 4-step sync (Steps 0-3: tilt bias, SignMatch, FIT speed + track)
            syncOutput = SyncEngine.synchronize(
                gpmfGps: gpmfGps, gpmfAccel: gpmfAccel, fitTimeSeries: fit
            )
        } else {
            // GPMF-only sync (Steps 0-1: tilt bias + SignMatch)
            syncOutput = gpmfOnlySync(gpmfGps: gpmfGps, gpmfAccel: gpmfAccel)
        }

        // STEP 4: Fusion (6-step pipeline)
        let fusionResult = FusionEngine.fuse(
            buffers: buffers,
            gpmfGps: gpmfGps,
            fitTimeSeries: fitTimeSeries,
            syncOutput: syncOutput
        )

        let durationMs = buffers.timestamp.last(where: { !$0.isNaN }) ?? 0
        return (buffers, fusionResult, durationMs)
    }

    // MARK: - GPMF-Only Sync (no FIT file)

    /// Builds a `SyncEngine.Output` using only GPMF data (Steps 0-1 only).
    ///
    /// Steps 3A/3B (FIT-GPMF speed + track correlation) require a FIT file
    /// and are skipped when none is provided.
    private static func gpmfOnlySync(
        gpmfGps: GPMFGpsTimeSeries,
        gpmfAccel: GPMFAccelTimeSeries
    ) -> SyncEngine.Output {

        // Step 0: Tilt bias estimation
        let tiltBias = TiltBiasEstimator.estimate(
            accelSurgeMps2: gpmfAccel.surgeMps2,
            gpsSpeedMs: gpmfGps.speed,
            gpsTimestampsMs: gpmfGps.timestampsMs
        )

        // Step 1: SignMatch (bias-corrected accel vs GPS speed derivative)
        var correctedAccel = gpmfAccel.surgeMps2
        if let bias = tiltBias {
            let biasF = Float(bias.biasMps2)
            for i in 0..<correctedAccel.count { correctedAccel[i] -= biasF }
        }
        let signMatch = SignMatchStrategy.estimateLag(
            accelTimestampsMs: gpmfAccel.timestampsMs,
            accelSurgeMps2: correctedAccel,
            gpsTimestampsMs: gpmfGps.timestampsMs,
            gpsSpeed: gpmfGps.speed
        )

        return SyncEngine.Output(
            tiltBias: tiltBias,
            signMatch: signMatch,
            speedCorrelation: nil,
            trackCorrelation: nil,
            fitGpmfSync: SyncResult(
                offset: 0, confidence: 0, strategy: .none,
                diagnosticMessage: "GPMF-only session — no FIT file provided"
            ),
            warnings: ["No FIT file: Steps 3A/3B (FIT-GPMF sync) skipped."]
        )
    }
}
