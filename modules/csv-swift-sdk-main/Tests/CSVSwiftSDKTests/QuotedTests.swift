// Tests/CSVSwiftSDKTests/QuotedTests.swift v1.1.0
/**
 * Quoted field parsing tests using Swift Testing framework.
 * --- Revision History ---
 * v1.0.0 - 2026-03-01 - Initial standardization.
 * v1.1.0 - 2026-03-01 - REFACTOR: Migrated to Swift Testing framework.
 */

import Testing
import Foundation
@testable import CSVSwiftSDK

@Suite("Quoted Field Parsing")
struct QuotedTests {

    @Test("Quoted header fields")
    func quotedHeader() throws {
        let csv = try CSV<Named>(string: "id,\"name, person\",age\n\"5\",\"Smith, John\",67\n8,Joe Bloggs,\"8\"")
        #expect(csv.header == ["id", "name, person", "age"])
    }

    @Test("Quoted content fields")
    func quotedContent() throws {
        let csv = try CSV<Named>(string: "id,\"name, person\",age\n\"5\",\"Smith, John\",67\n8,Joe Bloggs,\"8\"")

        #expect(csv.rows[0] == [
            "id": "5",
            "name, person": "Smith, John",
            "age": "67"
        ])

        #expect(csv.rows[1] == [
            "id": "8",
            "name, person": "Joe Bloggs",
            "age": "8"
        ])
    }

    @Test("Embedded quotes (RFC 4180)")
    func embeddedQuotes() throws {
        guard let csvURL = ResourceHelper.url(forResource: "TestData/wonderland", withExtension: "csv") else {
            Issue.record("Could not get URL for wonderland.csv from Test Bundle")
            return
        }

        let csv = try CSV<Named>(url: csvURL)

        /*
         The test file:

         Character,Quote
         White Rabbit,"""Where shall I begin, please your Majesty?"" he asked."
         King,"""Begin at the beginning,"" the King said gravely, ""and go on till you come to the end: then stop."""
         March Hare,"""Do you mean that you think you can find out the answer to it?"" said the March Hare."

         Notice there are no commas (delimiters) in the 3rd line.
         For more information, see https://www.rfc-editor.org/rfc/rfc4180.html
         */

        let expected = [
            ["Character": "White Rabbit", "Quote": #""Where shall I begin, please your Majesty?" he asked."#],
            ["Character": "King", "Quote": #""Begin at the beginning," the King said gravely, "and go on till you come to the end: then stop.""#],
            ["Character": "March Hare", "Quote": #""Do you mean that you think you can find out the answer to it?" said the March Hare."#]
        ]

        for (index, row) in csv.rows.enumerated() {
            #expect(expected[index] == row)
        }

        // Verify serialization round-trip
        let serialized = csv.serialized
        let read = try String(contentsOf: csvURL, encoding: .utf8)
        #expect(serialized == read)
    }
}
