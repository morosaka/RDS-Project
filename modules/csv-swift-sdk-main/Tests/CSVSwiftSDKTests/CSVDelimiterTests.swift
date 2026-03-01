// Tests/CSVSwiftSDKTests/CSVDelimiterTests.swift v1.1.0
/**
 * CSV Delimiter tests using Swift Testing framework.
 * --- Revision History ---
 * v1.0.0 - 2026-03-01 - Initial standardization.
 * v1.1.0 - 2026-03-01 - REFACTOR: Migrated to Swift Testing framework.
 */

import Testing
@testable import CSVSwiftSDK

@Suite("CSV Delimiter")
struct CSVDelimiterTests {

    @Test("Raw value extraction")
    func rawValue() {
        #expect(CSVDelimiter.comma.rawValue == ",")
        #expect(CSVDelimiter.semicolon.rawValue == ";")
        #expect(CSVDelimiter.tab.rawValue == "\t")
        #expect(CSVDelimiter.character("x").rawValue == "x")
    }

    @Test("Literal initializer")
    func literalInitializer() {
        #expect(CSVDelimiter.comma == ",")
        #expect(CSVDelimiter.semicolon == ";")
        #expect(CSVDelimiter.tab == "\t")
        #expect(CSVDelimiter.character("x") == "x")
    }
}
