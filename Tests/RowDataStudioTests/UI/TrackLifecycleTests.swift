// Tests/RowDataStudioTests/UI/TrackLifecycleTests.swift v1.0.0
/**
 * Tests for Widget↔Track lifecycle (Phase 8c.2).
 *
 * Validates that:
 * - Adding a widget creates the correct TimelineTrack entries
 * - Removing a widget removes non-pinned linked tracks
 * - Pinned tracks survive widget removal
 * - Widgets with no timeline representation (MetricCard, EmpowerRadar) produce 0 tracks
 * - streamType(for:) correctly classifies metric ID prefixes
 *
 * --- Revision History ---
 * v1.0.0 - 2026-03-13 - Initial implementation (Phase 8c.2: Widget↔Track Lifecycle).
 */

import Testing
import Foundation
@testable import RowDataStudio

@Suite struct TrackLifecycleTests {

    // MARK: - MultiLineChart → 3 tracks

    @Test func addMultiLineChartCreatesTrackPerMetric() {
        let ids = ["gps_gpmf_ts_speed", "imu_raw_ts_acc_surge", "fus_cal_ts_vel_inertial"]
        let widget = WidgetState.make(type: .multiLineChart, position: .zero, metricIDs: ids)
        let tracks = RowingDeskCanvas.tracks(for: widget)
        #expect(tracks.count == 3)
        #expect(tracks.allSatisfy { $0.linkedWidgetID == widget.id })
        #expect(tracks[0].metricID == "gps_gpmf_ts_speed")
        #expect(tracks[1].metricID == "imu_raw_ts_acc_surge")
        #expect(tracks[2].metricID == "fus_cal_ts_vel_inertial")
    }

    // MARK: - Remove widget → linked tracks removed

    @Test func deleteWidgetRemovesLinkedTracks() {
        let widget = WidgetState.make(type: .lineChart, position: .zero,
                                     metricIDs: ["gps_gpmf_ts_speed"])
        var session = makeSession()
        session.canvas.widgets.append(widget)
        session.timeline.tracks.append(contentsOf: RowingDeskCanvas.tracks(for: widget))
        #expect(session.timeline.tracks.count == 1)

        session.canvas.widgets.removeAll { $0.id == widget.id }
        session.timeline.tracks.removeAll { !$0.isPinned && $0.linkedWidgetID == widget.id }

        #expect(session.canvas.widgets.isEmpty)
        #expect(session.timeline.tracks.isEmpty)
    }

    // MARK: - Remove widget with pinned track → pinned track survives

    @Test func deleteWidgetPreservesPinnedTrack() {
        let widget = WidgetState.make(type: .lineChart, position: .zero,
                                     metricIDs: ["gps_gpmf_ts_speed"])
        var session = makeSession()
        var newTracks = RowingDeskCanvas.tracks(for: widget)
        newTracks[0].isPinned = true
        session.canvas.widgets.append(widget)
        session.timeline.tracks.append(contentsOf: newTracks)

        session.canvas.widgets.removeAll { $0.id == widget.id }
        session.timeline.tracks.removeAll { !$0.isPinned && $0.linkedWidgetID == widget.id }

        #expect(session.canvas.widgets.isEmpty)
        #expect(session.timeline.tracks.count == 1)
        #expect(session.timeline.tracks[0].isPinned)
        #expect(session.timeline.tracks[0].linkedWidgetID == widget.id)
    }

    // MARK: - MetricCard → 0 tracks

    @Test func addMetricCardCreatesNoTracks() {
        let widget = WidgetState.make(type: .metricCard, position: .zero)
        let tracks = RowingDeskCanvas.tracks(for: widget)
        #expect(tracks.isEmpty)
    }

    // MARK: - EmpowerRadar → 0 tracks

    @Test func addEmpowerRadarCreatesNoTracks() {
        let widget = WidgetState.make(type: .empowerRadar, position: .zero)
        let tracks = RowingDeskCanvas.tracks(for: widget)
        #expect(tracks.isEmpty)
    }

    // MARK: - Video widget → 1 track (stream: .video)

    @Test func addVideoWidgetCreatesOneVideoTrack() {
        let widget = WidgetState.make(type: .video, position: .zero)
        let tracks = RowingDeskCanvas.tracks(for: widget)
        #expect(tracks.count == 1)
        #expect(tracks[0].stream == .video)
        #expect(tracks[0].linkedWidgetID == widget.id)
    }

    // MARK: - Map widget → 1 track (stream: .gps)

    @Test func addMapWidgetCreatesOneGPSTrack() {
        let widget = WidgetState.make(type: .map, position: .zero)
        let tracks = RowingDeskCanvas.tracks(for: widget)
        #expect(tracks.count == 1)
        #expect(tracks[0].stream == .gps)
    }

    // MARK: - streamType(for:) prefix parsing

    @Test func streamTypeGPS() {
        #expect(RowingDeskCanvas.streamType(for: "gps_gpmf_ts_speed") == .gps)
    }

    @Test func streamTypeIMUAccel() {
        #expect(RowingDeskCanvas.streamType(for: "imu_raw_ts_acc_surge") == .accl)
    }

    @Test func streamTypeIMUGyro() {
        #expect(RowingDeskCanvas.streamType(for: "imu_raw_ts_gyro_x") == .gyro)
    }

    @Test func streamTypeFusedVelocity() {
        #expect(RowingDeskCanvas.streamType(for: "fus_cal_ts_vel_inertial") == .fusedVelocity)
    }

    // MARK: - Helpers

    private func makeSession() -> SessionDocument {
        SessionDocument(
            metadata: SessionMetadata(title: "TrackLifecycleTest"),
            timeline: Timeline(duration: 1800)
        )
    }
}
