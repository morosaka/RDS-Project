// Tests/CSVSwiftSDKTests/PerformanceTest.swift v1.0.0
/**
 * Generic CSV parsing utility.
 * --- Revision History ---
 * v1.0.0 - 2026-03-01 - Initial standardization.
 */
//
//  PerformanceTest.swift
//  SwiftCSV
//
//  Created by 杉本裕樹 on 2016/04/23.
//  Copyright © 2016年 Naoto Kaneko. All rights reserved.
//

import XCTest
@testable import CSVSwiftSDK

class PerformanceTest: XCTestCase {
    var csv: CSV<Named>!

    override func setUpWithError() throws {
        let testFilePath = "TestData/large"
        let testFileExtension = "csv"
        guard let csvURL = ResourceHelper.url(forResource: testFilePath, withExtension: testFileExtension) else {
            XCTAssertNotNil(nil, "Could not get URL for \(testFilePath).\(testFileExtension) from Test Bundle")
            return
        }
        
        csv = try CSV<Named>(url: csvURL)
    }

    func testParsePerformance() {
        measure {
            _ = self.csv.rows
        }
    }
}
