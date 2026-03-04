// Core/Services/Fusion/StrokeCrossValidator.swift v1.0.0
/**
 * Post-fusion stroke cross-validation against NK Empower reference data.
 * Compares algorithmically detected strokes with sensor-segmented ground truth.
 * --- Revision History ---
 * v1.0.0 - 2026-03-03 - Initial implementation.
 */

import Foundation
import CSVSwiftSDK

/// Cross-validates detected strokes against NK Empower reference data.
///
/// NK Empower provides per-stroke biomechanical data (force, angle, timing)
/// that is segmented by the oarlock sensor itself. This serves as the highest-
/// reliability ground truth for stroke boundaries.
///
/// Usage:
/// ```swift
/// let result = StrokeCrossValidator.validate(
///     detectedStrokes: fusionResult.strokes,
///     empowerSession: empowerSession
/// )
/// if !result.warnings.isEmpty { ... }
/// ```
///
/// **Not embedded in FusionEngine** — called separately when NK Empower data
/// is available. See `docs/specs/fusion-engine.md` §Multi-source validation.
public struct StrokeCrossValidator {

    /// Cross-validation result.
    public struct ValidationResult: Codable, Sendable, Hashable {
        /// Number of algorithmically detected strokes
        public let detectedCount: Int

        /// Number of NK Empower reference strokes
        public let referenceCount: Int

        /// Whether stroke counts agree within tolerance (±10%)
        public let countMatch: Bool

        /// Average absolute difference in stroke rate (SPM) for aligned strokes.
        /// `nil` if no strokes could be temporally aligned.
        public let avgRateDifferenceSPM: Double?

        /// Fraction of aligned strokes where rate agrees within ±5 SPM (0.0–1.0).
        /// `nil` if no strokes could be temporally aligned.
        public let rateAgreement: Double?

        /// Diagnostic warnings for significant discrepancies.
        public let warnings: [String]
    }

    /// Validates detected strokes against NK Empower reference.
    ///
    /// Comparison strategy:
    /// 1. Stroke count: detected vs. reference (±10% tolerance)
    /// 2. Per-stroke rate: for temporally aligned strokes, compare SPM (±5 SPM tolerance)
    ///
    /// Temporal alignment: NK Empower `elapsedTime` is cumulative from session start.
    /// Detected strokes use `startTime` (seconds from GPMF start). These timelines
    /// may have an offset that is estimated from the first aligned pair.
    ///
    /// - Parameters:
    ///   - detectedStrokes: Algorithmically detected stroke events.
    ///   - empowerSession: NK Empower session with per-stroke reference data.
    /// - Returns: Validation result with comparison metrics and warnings.
    public static func validate(
        detectedStrokes: [StrokeEvent],
        empowerSession: NKEmpowerSession
    ) -> ValidationResult {
        let detCount = detectedStrokes.count
        let refCount = empowerSession.strokes.count
        var warnings: [String] = []

        // Count comparison (±10%)
        let countTolerance = max(1, Int(Double(refCount) * 0.10))
        let countMatch = abs(detCount - refCount) <= countTolerance

        if !countMatch && refCount > 0 {
            warnings.append(
                "Stroke count mismatch: detected \(detCount) vs. Empower \(refCount) "
                + "(tolerance ±\(countTolerance))"
            )
        }

        // Per-stroke rate comparison via temporal alignment
        let empowerStrokes = empowerSession.strokes
        guard !detectedStrokes.isEmpty, !empowerStrokes.isEmpty else {
            return ValidationResult(
                detectedCount: detCount,
                referenceCount: refCount,
                countMatch: countMatch,
                avgRateDifferenceSPM: nil,
                rateAgreement: nil,
                warnings: warnings
            )
        }

        // Estimate timeline offset: align first detected stroke with nearest Empower stroke
        let detFirst = detectedStrokes[0].startTime
        let empFirst = empowerStrokes[0].elapsedTime
        let timelineOffset = empFirst - detFirst

        // Match detected strokes to nearest Empower stroke by elapsed time
        let rateTolerance = 5.0  // SPM
        var rateDiffSum = 0.0
        var rateAgreeCount = 0
        var matchedCount = 0

        for detected in detectedStrokes {
            let detTimeInEmp = detected.startTime + timelineOffset

            // Find nearest Empower stroke by elapsed time
            var bestIdx = -1
            var bestDist = Double.infinity
            for (j, emp) in empowerStrokes.enumerated() {
                let dist = abs(emp.elapsedTime - detTimeInEmp)
                if dist < bestDist {
                    bestDist = dist
                    bestIdx = j
                }
            }

            // Accept match if within 3 seconds
            guard bestIdx >= 0, bestDist < 3.0 else { continue }

            matchedCount += 1
            let rateDiff = abs(detected.strokeRate - empowerStrokes[bestIdx].strokeRate)
            rateDiffSum += rateDiff
            if rateDiff <= rateTolerance { rateAgreeCount += 1 }
        }

        let avgRateDiff: Double? = matchedCount > 0 ? rateDiffSum / Double(matchedCount) : nil
        let rateAgreement: Double? = matchedCount > 0
            ? Double(rateAgreeCount) / Double(matchedCount) : nil

        if let agreement = rateAgreement, agreement < 0.5, matchedCount >= 3 {
            warnings.append(
                "Stroke rate disagreement with Empower: "
                + "only \(Int(agreement * 100))% of aligned strokes match (±\(Int(rateTolerance)) SPM)"
            )
        }

        if let avg = avgRateDiff, avg > 5.0 {
            warnings.append(
                "Average stroke rate difference vs. Empower: \(String(format: "%.1f", avg)) SPM"
            )
        }

        return ValidationResult(
            detectedCount: detCount,
            referenceCount: refCount,
            countMatch: countMatch,
            avgRateDifferenceSPM: avgRateDiff,
            rateAgreement: rateAgreement,
            warnings: warnings
        )
    }
}
