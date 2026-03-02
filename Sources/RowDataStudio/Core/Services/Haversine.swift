// Core/Services/Haversine.swift v1.0.0
/**
 * Haversine distance formula for GPS coordinate pairs.
 * Used by GpsTrackCorrelator for track-based sync.
 * --- Revision History ---
 * v1.0.0 - 2026-03-02 - Initial implementation (Phase 3: Sync + Fusion).
 */

import Foundation

/// GPS distance utilities.
public enum Haversine {

    /// Earth radius in meters (WGS-84 mean)
    public static let earthRadiusM: Double = 6_371_000.0

    /// Computes great-circle distance between two GPS coordinates.
    ///
    /// - Parameters:
    ///   - lat1: Latitude of point 1 (degrees)
    ///   - lon1: Longitude of point 1 (degrees)
    ///   - lat2: Latitude of point 2 (degrees)
    ///   - lon2: Longitude of point 2 (degrees)
    /// - Returns: Distance in meters
    public static func distance(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let dLat = (lat2 - lat1) * .pi / 180.0
        let dLon = (lon2 - lon1) * .pi / 180.0
        let lat1Rad = lat1 * .pi / 180.0
        let lat2Rad = lat2 * .pi / 180.0

        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusM * c
    }

    /// Converts FIT semicircles to degrees.
    ///
    /// FIT protocol stores GPS coordinates as Int32 semicircles.
    /// Formula: degrees = semicircles × (180.0 / 2^31)
    public static func semicirclesToDegrees(_ semicircles: Int32) -> Double {
        Double(semicircles) * (180.0 / 2_147_483_648.0)
    }
}
