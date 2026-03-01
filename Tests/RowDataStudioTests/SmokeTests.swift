// RowDataStudioTests/SmokeTests.swift v0.1.0
/**
 * Smoke tests verifying that all SDK modules import successfully
 * and their core types are accessible from the app layer.
 * --- Revision History ---
 * v0.1.0 - 2026-03-01 - ARCHITECTURE: Initial scaffold.
 */

import Testing
@testable import RowDataStudio
import GPMFSwiftSDK
import FITSwiftSDK
import CSVSwiftSDK

@Suite("Phase 0 — Smoke Tests")
struct SmokeTests {

    @Test("GPMF SDK types are accessible")
    func gpmfSDKImport() {
        // Verify core GPMF types compile and are constructible
        let data = TelemetryData()
        #expect(data.accelReadings.isEmpty)
        #expect(data.gyroReadings.isEmpty)
        #expect(data.gpsReadings.isEmpty)
        #expect(data.duration == 0)
    }

    @Test("FIT SDK types are accessible")
    func fitSDKImport() {
        // Verify core FIT types compile and are constructible
        let messages = FitMessages()
        #expect(messages.recordMesgs.isEmpty)
        #expect(messages.sessionMesgs.isEmpty)
    }

    @Test("CSV SDK types are accessible")
    func csvSDKImport() {
        // Verify vendor profile types compile
        let empower = NKEmpowerSession(strokes: [])
        #expect(empower.strokes.isEmpty)
    }

    @Test("App ContentView is accessible")
    @MainActor func contentViewImport() {
        // Verify the app's library target exports correctly
        let _ = ContentView()
    }
}
