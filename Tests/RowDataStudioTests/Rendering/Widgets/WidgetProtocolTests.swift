// Tests/RowDataStudioTests/Rendering/Widgets/WidgetProtocolTests.swift v1.0.0
/**
 * Tests for WidgetType enum and WidgetState convenience extensions.
 * --- Revision History ---
 * v1.0.0 - 2026-03-08 - Initial implementation (Phase 6: Canvas & Widgets).
 */

import Testing
import Foundation
@testable import RowDataStudio

@Suite("WidgetType")
struct WidgetTypeTests {

    @Test("All 8 widget types exist")
    func allCasesCount() {
        #expect(WidgetType.allCases.count == 8)
    }

    @Test("Raw values match expected strings")
    func rawValues() {
        #expect(WidgetType.lineChart.rawValue      == "lineChart")
        #expect(WidgetType.multiLineChart.rawValue == "multiLineChart")
        #expect(WidgetType.strokeTable.rawValue    == "strokeTable")
        #expect(WidgetType.metricCard.rawValue     == "metricCard")
        #expect(WidgetType.map.rawValue            == "map")
        #expect(WidgetType.empowerRadar.rawValue   == "empowerRadar")
        #expect(WidgetType.video.rawValue          == "video")
        #expect(WidgetType.audio.rawValue          == "audio")
    }

    @Test("Display names are non-empty")
    func displayNames() {
        for type in WidgetType.allCases {
            #expect(!type.displayName.isEmpty, "Empty displayName for \(type)")
        }
    }

    @Test("Icons are valid SF Symbol name strings (non-empty)")
    func icons() {
        for type in WidgetType.allCases {
            #expect(!type.icon.isEmpty, "Empty icon for \(type)")
        }
    }

    @Test("Default sizes are positive")
    func defaultSizes() {
        for type in WidgetType.allCases {
            #expect(type.defaultSize.width > 0)
            #expect(type.defaultSize.height > 0)
        }
    }

    @Test("Round-trip: rawValue → WidgetType")
    func rawValueRoundTrip() {
        for type in WidgetType.allCases {
            let parsed = WidgetType(rawValue: type.rawValue)
            #expect(parsed == type)
        }
    }

    @Test("Unknown rawValue returns nil")
    func unknownRawValue() {
        #expect(WidgetType(rawValue: "unknownWidget") == nil)
    }
}

@Suite("WidgetState extensions")
struct WidgetStateExtensionTests {

    // MARK: make factory

    @Test("make(type:position:) sets correct widgetType string")
    func makeWidgetType() {
        let ws = WidgetState.make(type: .lineChart, position: .zero)
        #expect(ws.widgetType == "lineChart")
    }

    @Test("make sets default size from WidgetType")
    func makeDefaultSize() {
        let ws = WidgetState.make(type: .metricCard, position: .zero)
        #expect(ws.size == WidgetType.metricCard.defaultSize)
    }

    @Test("make(type:position:metricIDs:) stores metric IDs in config")
    func makeMetricIDs() {
        let ids = ["fus_cal_ts_vel_inertial", "phys_ext_ts_hr"]
        let ws = WidgetState.make(type: .multiLineChart, position: .zero, metricIDs: ids)
        #expect(ws.metricIDs == ids)
    }

    @Test("make(type:position:title:) stores custom title")
    func makeCustomTitle() {
        let ws = WidgetState.make(type: .lineChart, position: .zero, title: "My Chart")
        #expect(ws.title == "My Chart")
    }

    @Test("make without title falls back to displayName")
    func makeTitleFallback() {
        let ws = WidgetState.make(type: .strokeTable, position: .zero)
        #expect(ws.title == WidgetType.strokeTable.displayName)
    }

    @Test("make stores position correctly")
    func makePosition() {
        let pos = CGPoint(x: 120, y: 240)
        let ws = WidgetState.make(type: .map, position: pos)
        #expect(ws.position == pos)
    }

    // MARK: type computed property

    @Test("type computed property parses widgetType string")
    func typeComputedProperty() {
        let ws = WidgetState.make(type: .empowerRadar, position: .zero)
        #expect(ws.type == .empowerRadar)
    }

    @Test("type returns nil for unknown widgetType string")
    func typeUnknown() {
        let ws = WidgetState(
            widgetType: "notARealType",
            position: .zero,
            size: CGSize(width: 200, height: 150),
            configuration: [:]
        )
        #expect(ws.type == nil)
    }

    // MARK: isVisible

    @Test("isVisible defaults to true from make()")
    func isVisibleDefault() {
        let ws = WidgetState.make(type: .lineChart, position: .zero)
        #expect(ws.isVisible == true)
    }

    @Test("isVisible reads false when config set to false")
    func isVisibleFalse() {
        var ws = WidgetState.make(type: .lineChart, position: .zero)
        ws.configuration["isVisible"] = AnyCodable(false)
        #expect(ws.isVisible == false)
    }

    // MARK: metricIDs

    @Test("metricIDs returns empty when not set")
    func metricIDsEmpty() {
        let ws = WidgetState.make(type: .metricCard, position: .zero)
        // make() passes empty array by default — metricIDs should be empty
        #expect(ws.metricIDs.isEmpty)
    }

    @Test("metricIDs returns multiple IDs")
    func metricIDsMultiple() {
        let ids = ["a", "b", "c"]
        let ws = WidgetState.make(type: .multiLineChart, position: .zero, metricIDs: ids)
        #expect(ws.metricIDs.count == 3)
        #expect(ws.metricIDs.contains("b"))
    }
}
