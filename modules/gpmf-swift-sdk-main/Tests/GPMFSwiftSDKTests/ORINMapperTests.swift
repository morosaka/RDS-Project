import XCTest
@testable import GPMFSwiftSDK

final class ORINMapperTests: XCTestCase {

    // MARK: - Identity Mapping

    func test_nilORIN_identityMapping() {
        let mapper = ORINMapper(orin: nil)
        let result = mapper.map(channels: (1.0, 2.0, 3.0))
        XCTAssertEqual(result.xCam, 1.0)
        XCTAssertEqual(result.yCam, 2.0)
        XCTAssertEqual(result.zCam, 3.0)
    }

    func test_XYZ_identityMapping() {
        let mapper = ORINMapper(orin: "XYZ")
        XCTAssertTrue(mapper.isValid)
        let result = mapper.map(channels: (10.0, 20.0, 30.0))
        XCTAssertEqual(result.xCam, 10.0)
        XCTAssertEqual(result.yCam, 20.0)
        XCTAssertEqual(result.zCam, 30.0)
    }

    // MARK: - HERO10 (ZXY)

    func test_ZXY_hero10Mapping() {
        let mapper = ORINMapper(orin: "ZXY")
        XCTAssertTrue(mapper.isValid)
        let result = mapper.map(channels: (100.0, 200.0, 300.0))
        XCTAssertEqual(result.xCam, 200.0)
        XCTAssertEqual(result.yCam, 300.0)
        XCTAssertEqual(result.zCam, 100.0)
    }

    // MARK: - Negative Axes

    func test_ZXy_negativeY() {
        let mapper = ORINMapper(orin: "ZXy")
        XCTAssertTrue(mapper.isValid)
        let result = mapper.map(channels: (10.0, 20.0, 30.0))
        XCTAssertEqual(result.xCam, 20.0)
        XCTAssertEqual(result.yCam, -30.0)
        XCTAssertEqual(result.zCam, 10.0)
    }

    func test_yxZ_mixedSigns() {
        let mapper = ORINMapper(orin: "yxZ")
        XCTAssertTrue(mapper.isValid)
        let result = mapper.map(channels: (10.0, 20.0, 30.0))
        XCTAssertEqual(result.xCam, -20.0)
        XCTAssertEqual(result.yCam, -10.0)
        XCTAssertEqual(result.zCam, 30.0)
    }

    // MARK: - Invalid ORIN

    func test_invalidORIN_isNotValid() {
        let mapper = ORINMapper(orin: "AB")
        XCTAssertFalse(mapper.isValid)
    }

    // MARK: - Gravity Validation

    func test_gravityTest_stationaryUpright() {
        let mapper = ORINMapper(orin: "ZXY")
        let result = mapper.map(channels: (9.81, 0.02, -0.01))
        XCTAssertEqual(result.zCam, 9.81, accuracy: 0.01)
        XCTAssertEqual(result.xCam, 0.02, accuracy: 0.1)
        XCTAssertEqual(result.yCam, -0.01, accuracy: 0.1)
    }

    // MARK: - Batch Mapping

    func test_mapToReadings_producesCorrectCount() {
        let mapper = ORINMapper(orin: "ZXY")
        let values: [Double] = [1, 2, 3, 4, 5, 6]
        let timestamps: [TimeInterval] = [0.0, 0.5]
        let readings = mapper.mapToReadings(values: values, timestamps: timestamps)
        XCTAssertEqual(readings.count, 2)
        XCTAssertEqual(readings[0].timestamp, 0.0)
        XCTAssertEqual(readings[1].timestamp, 0.5)
    }
}
