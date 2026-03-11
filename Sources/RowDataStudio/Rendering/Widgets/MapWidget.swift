// Rendering/Widgets/MapWidget.swift v1.1.0
/**
 * GPS track map widget using MapKit.
 *
 * Renders the rowing course GPS track as a polyline overlay on a map.
 * Playhead position is shown as a moving marker.
 * Falls back to a "No GPS data" placeholder when no coordinates are available.
 *
 * GPS coordinates are read from DataContext.buffers.dynamic:
 *   "gps_gpmf_ts_lat" / "gps_gpmf_ts_lon" (GPMF track, ~10Hz)
 *
 * **Performance fix (v1.1.0):** Binary search for playhead index (was O(n) linear scan).
 * Track coordinates computed once and cached, not rebuilt every frame.
 *
 * --- Revision History ---
 * v1.1.0 - 2026-03-11 - Binary search playheadIndex; cache track coords.
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 6: Canvas & Widgets).
 */

import SwiftUI
import MapKit

/// GPS track widget rendering the rowing course on a map.
///
/// **Data source:** `DataContext.buffers.dynamic["gps_gpmf_ts_lat"]` and `..._lon`
/// sampled at the same cadence as the IMU timestamp array.
///
/// The track is displayed as a blue polyline; the current playhead position
/// is shown as a red dot. If no GPS data is available (e.g. indoor session or
/// GPMF without GPS), a placeholder is shown instead.
public struct MapWidget: View {

    let latitudes: ContiguousArray<Float>
    let longitudes: ContiguousArray<Float>
    let timestamps: ContiguousArray<Double>
    let playheadTimeMs: Double

    @State private var region: MKCoordinateRegion
    /// Track coordinates computed once and cached (avoids 140k alloc per frame).
    @State private var cachedTrackCoords: [CLLocationCoordinate2D] = []

    public init(
        latitudes: ContiguousArray<Float>,
        longitudes: ContiguousArray<Float>,
        timestamps: ContiguousArray<Double>,
        playheadTimeMs: Double
    ) {
        self.latitudes = latitudes
        self.longitudes = longitudes
        self.timestamps = timestamps
        self.playheadTimeMs = playheadTimeMs

        // Initial region: center on mean GPS position (or default to Oxford)
        let center = Self.meanCoordinate(lats: latitudes, lons: longitudes)
        self._region = State(initialValue: MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
    }

    private var hasData: Bool {
        !latitudes.isEmpty && latitudes.count == longitudes.count
    }

    /// Index of the GPS sample closest to the playhead time (binary search, O(log n)).
    private var playheadIndex: Int? {
        guard hasData, !timestamps.isEmpty else { return nil }
        var lo = 0, hi = timestamps.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if timestamps[mid] < playheadTimeMs { lo = mid + 1 }
            else { hi = mid }
        }
        // lo is now the first index >= playheadTimeMs; check if lo-1 is closer
        if lo > 0 {
            let diffLo = abs(timestamps[lo] - playheadTimeMs)
            let diffPrev = abs(timestamps[lo - 1] - playheadTimeMs)
            if diffPrev < diffLo { return lo - 1 }
        }
        return lo
    }

    private var playheadCoordinate: CLLocationCoordinate2D? {
        guard let i = playheadIndex,
              i < latitudes.count else { return nil }
        let lat = Double(latitudes[i])
        let lon = Double(longitudes[i])
        guard lat.isFinite, lon.isFinite else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    public var body: some View {
        if hasData {
            mapView
                .onAppear {
                    buildTrackCoords()
                    fitRegionToTrack()
                }
        } else {
            noDataPlaceholder
        }
    }

    // MARK: - Map

    @ViewBuilder
    private var mapView: some View {
        Map(coordinateRegion: $region, annotationItems: playheadAnnotations) { item in
            MapAnnotation(coordinate: item.coordinate) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
        }
        .overlay(trackOverlay)
    }

    @ViewBuilder
    private var trackOverlay: some View {
        // Draw GPS track as a Canvas polyline using cached coordinates
        Canvas { context, size in
            guard cachedTrackCoords.count >= 2 else { return }
            let latSpan = region.span.latitudeDelta
            let lonSpan = region.span.longitudeDelta
            let centerLat = region.center.latitude
            let centerLon = region.center.longitude

            var path = Path()
            for (i, coord) in cachedTrackCoords.enumerated() {
                let x = ((coord.longitude - centerLon) / lonSpan + 0.5) * size.width
                let y = (0.5 - (coord.latitude - centerLat) / latSpan) * size.height
                let pt = CGPoint(x: x, y: y)
                if i == 0 { path.move(to: pt) }
                else { path.addLine(to: pt) }
            }
            context.stroke(
                path,
                with: .color(.blue.opacity(0.8)),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )
        }
    }

    // MARK: - No data placeholder

    private var noDataPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "map.slash")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No GPS Track")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Import a GoPro GPMF file with GPS data")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.05))
    }

    // MARK: - Helpers

    private var playheadAnnotations: [MapAnnotationItem] {
        guard let coord = playheadCoordinate else { return [] }
        return [MapAnnotationItem(coordinate: coord)]
    }

    /// Build track coordinates once (called in onAppear).
    private func buildTrackCoords() {
        cachedTrackCoords = zip(latitudes, longitudes).compactMap { lat, lon in
            let la = Double(lat), lo = Double(lon)
            guard la.isFinite, lo.isFinite else { return nil }
            return CLLocationCoordinate2D(latitude: la, longitude: lo)
        }
    }

    private func fitRegionToTrack() {
        guard hasData else { return }
        let validLats = latitudes.filter { $0.isFinite && $0 != 0 }
        let validLons = longitudes.filter { $0.isFinite && $0 != 0 }
        guard !validLats.isEmpty, !validLons.isEmpty else { return }

        let minLat = Double(validLats.min()!)
        let maxLat = Double(validLats.max()!)
        let minLon = Double(validLons.min()!)
        let maxLon = Double(validLons.max()!)
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.3, 0.001),
            longitudeDelta: max((maxLon - minLon) * 1.3, 0.001)
        )
        region = MKCoordinateRegion(center: center, span: span)
    }

    private static func meanCoordinate(
        lats: ContiguousArray<Float>,
        lons: ContiguousArray<Float>
    ) -> CLLocationCoordinate2D {
        guard !lats.isEmpty else {
            return CLLocationCoordinate2D(latitude: 51.7520, longitude: -1.2577)
        }
        let lat = lats.reduce(0, +) / Float(lats.count)
        let lon = lons.reduce(0, +) / Float(lons.count)
        return CLLocationCoordinate2D(latitude: Double(lat), longitude: Double(lon))
    }
}

// MARK: - Supporting types

private struct MapAnnotationItem: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

#Preview {
    let lats: ContiguousArray<Float> = [51.7520, 51.7521, 51.7523, 51.7525, 51.7528]
    let lons: ContiguousArray<Float> = [-1.2577, -1.2575, -1.2572, -1.2568, -1.2563]
    let ts: ContiguousArray<Double>  = [0, 5000, 10000, 15000, 20000]

    return MapWidget(
        latitudes: lats,
        longitudes: lons,
        timestamps: ts,
        playheadTimeMs: 10_000
    )
    .frame(width: 400, height: 400)
}
