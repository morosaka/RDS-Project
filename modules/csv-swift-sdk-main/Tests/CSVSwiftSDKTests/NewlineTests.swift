// Tests/CSVSwiftSDKTests/NewlineTests.swift v1.1.0
/**
 * Newline handling tests using Swift Testing framework.
 * --- Revision History ---
 * v1.0.0 - 2026-03-01 - Initial standardization.
 * v1.1.0 - 2026-03-01 - REFACTOR: Migrated to Swift Testing framework.
 */

import Testing
@testable import CSVSwiftSDK

@Suite("Newline Handling")
struct NewlineTests {

    @Test("Parse CSV with CR newlines")
    func parseWithCR() throws {
        let csv = try CSV<Named>(string: "id,name,age\r1,Alice,18\r2,Bob,19\r3,Charlie,20")
        #expect(csv.header == ["id", "name", "age"])

        let expectedRows = [
            ["id": "1", "name": "Alice", "age": "18"],
            ["id": "2", "name": "Bob", "age": "19"],
            ["id": "3", "name": "Charlie", "age": "20"]
        ]

        for (index, row) in csv.rows.enumerated() {
            #expect(expectedRows[index] == row)
        }
    }

    @Test("Parse CSV with LF newlines")
    func parseWithLF() throws {
        let csv = try CSV<Named>(string: "id,name,age\n1,Alice,18\n2,Bob,19\n3,Charlie,20")
        #expect(csv.header == ["id", "name", "age"])

        let expectedRows = [
            ["id": "1", "name": "Alice", "age": "18"],
            ["id": "2", "name": "Bob", "age": "19"],
            ["id": "3", "name": "Charlie", "age": "20"]
        ]

        for (index, row) in csv.rows.enumerated() {
            #expect(expectedRows[index] == row)
        }
    }

    @Test("Parse CSV with CRLF newlines")
    func parseWithCRLF() throws {
        let csv = try CSV<Named>(string: "id,name,age\r\n1,Alice,18\r\n2,Bob,19\r\n3,Charlie,20")
        #expect(csv.header == ["id", "name", "age"])

        let expectedRows = [
            ["id": "1", "name": "Alice", "age": "18"],
            ["id": "2", "name": "Bob", "age": "19"],
            ["id": "3", "name": "Charlie", "age": "20"]
        ]

        for (index, row) in csv.rows.enumerated() {
            #expect(expectedRows[index] == row)
        }
    }

    @Test("Handle extra carriage return at end")
    func extraCarriageReturnAtEnd() throws {
        let csv = try CSV<Named>(string: "id,name,age\n1,Alice,18\n2,Bob,19\n3,Charlie\r\n")

        let expected = [
            ["id": "1", "name": "Alice", "age": "18"],
            ["id": "2", "name": "Bob", "age": "19"],
            ["id": "3", "name": "Charlie", "age": ""]
        ]

        for (index, row) in csv.rows.enumerated() {
            #expect(expected[index] == row)
        }
    }
}
