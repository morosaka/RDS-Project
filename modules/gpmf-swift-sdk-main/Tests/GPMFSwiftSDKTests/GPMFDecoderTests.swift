import XCTest
import Foundation
@testable import GPMFSwiftSDK

final class GPMFDecoderTests: XCTestCase {

    // MARK: - Empty / Minimal

    func test_emptyData_returnsEmpty() {
        let nodes = GPMFDecoder.decode(data: Data())
        XCTAssertTrue(nodes.isEmpty)
    }

    func test_tooSmall_returnsEmpty() {
        let nodes = GPMFDecoder.decode(data: Data([0x44, 0x45, 0x56, 0x43]))
        XCTAssertTrue(nodes.isEmpty)
    }

    // MARK: - Single Leaf Node

    func test_singleUint32Node() {
        // Key="TSMP", Type='L'(0x4C), Size=4, Repeat=1, Value=196
        var data = Data()
        data.append(contentsOf: [0x54, 0x53, 0x4D, 0x50])  // "TSMP"
        data.append(contentsOf: [0x4C])                      // 'L' = uint32
        data.append(contentsOf: [0x04])                      // size = 4
        data.append(contentsOf: [0x00, 0x01])                // repeat = 1
        data.append(contentsOf: [0x00, 0x00, 0x00, 0xC4])   // value = 196

        let nodes = GPMFDecoder.decode(data: data)
        XCTAssertEqual(nodes.count, 1)

        let node = nodes[0]
        XCTAssertEqual(node.key, "TSMP")
        XCTAssertEqual(node.valueType, .uint32)
        XCTAssertEqual(node.structSize, 4)
        XCTAssertEqual(node.repeatCount, 1)

        let values = GPMFDecoder.readDoubles(from: node)
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values[0], 196.0)
    }

    // MARK: - Multi-Axis Int16 (ACCL-like)

    func test_threeAxisInt16() {
        var data = Data()
        data.append(contentsOf: [0x41, 0x43, 0x43, 0x4C])  // "ACCL"
        data.append(contentsOf: [0x73])                      // 's' = int16
        data.append(contentsOf: [0x06])                      // size = 6
        data.append(contentsOf: [0x00, 0x02])                // repeat = 2

        // Sample 0: [100, -200, 300]
        data.append(contentsOf: [0x00, 0x64])                // 100
        data.append(contentsOf: [0xFF, 0x38])                // -200
        data.append(contentsOf: [0x01, 0x2C])                // 300

        // Sample 1: [400, -500, 600]
        data.append(contentsOf: [0x01, 0x90])                // 400
        data.append(contentsOf: [0xFE, 0x0C])                // -500
        data.append(contentsOf: [0x02, 0x58])                // 600

        let nodes = GPMFDecoder.decode(data: data)
        XCTAssertEqual(nodes.count, 1)

        let node = nodes[0]
        XCTAssertEqual(node.elementsPerSample, 3)

        let values = GPMFDecoder.readDoubles(from: node)
        XCTAssertEqual(values.count, 6)
        XCTAssertEqual(values[0], 100.0)
        XCTAssertEqual(values[1], -200.0)
        XCTAssertEqual(values[2], 300.0)
        XCTAssertEqual(values[3], 400.0)
        XCTAssertEqual(values[4], -500.0)
        XCTAssertEqual(values[5], 600.0)
    }

    // MARK: - String Node

    func test_stringNode() {
        var data = Data()
        data.append(contentsOf: [0x53, 0x54, 0x4E, 0x4D])  // "STNM"
        data.append(contentsOf: [0x63])                      // 'c' = char
        data.append(contentsOf: [0x06])                      // size = 6
        data.append(contentsOf: [0x00, 0x01])                // repeat = 1
        data.append(contentsOf: Array("Camera".utf8))        // 6 bytes
        data.append(contentsOf: [0x00, 0x00])                // padding

        let nodes = GPMFDecoder.decode(data: data)
        XCTAssertEqual(nodes.count, 1)

        let str = GPMFDecoder.readString(from: nodes[0])
        XCTAssertEqual(str, "Camera")
    }

    // MARK: - Nested Container

    func test_nestedContainer() {
        // Inner: DVNM 'c' 4 1 "Cam\0" = 12 bytes
        var inner = Data()
        inner.append(contentsOf: [0x44, 0x56, 0x4E, 0x4D])  // "DVNM"
        inner.append(contentsOf: [0x63])                      // 'c'
        inner.append(contentsOf: [0x04])                      // size = 4
        inner.append(contentsOf: [0x00, 0x01])                // repeat = 1
        inner.append(contentsOf: Array("Cam\0".utf8))

        // Outer: DEVC nested 4 3 (payload=12)
        var data = Data()
        data.append(contentsOf: [0x44, 0x45, 0x56, 0x43])    // "DEVC"
        data.append(contentsOf: [0x00])                        // nested
        data.append(contentsOf: [0x04])                        // size = 4
        data.append(contentsOf: [0x00, 0x03])                  // repeat = 3
        data.append(inner)

        let nodes = GPMFDecoder.decode(data: data)
        XCTAssertEqual(nodes.count, 1)
        XCTAssertTrue(nodes[0].isContainer)
        XCTAssertEqual(nodes[0].children?.count, 1)
        XCTAssertEqual(nodes[0].children?[0].key, "DVNM")

        let name = GPMFDecoder.readString(from: nodes[0].children![0])
        XCTAssertEqual(name, "Cam")
    }

    // MARK: - Float Node

    func test_floatNode() {
        // Key="TMPC", Type='f'(0x66), Size=4, Repeat=1, Value=56.0 (0x42600000)
        var data = Data()
        data.append(contentsOf: [0x54, 0x4D, 0x50, 0x43])  // "TMPC"
        data.append(contentsOf: [0x66])                      // 'f' = float
        data.append(contentsOf: [0x04])                      // size = 4
        data.append(contentsOf: [0x00, 0x01])                // repeat = 1
        // 56.0f in big-endian IEEE754 = 0x42600000
        data.append(contentsOf: [0x42, 0x60, 0x00, 0x00])

        let nodes = GPMFDecoder.decode(data: data)
        XCTAssertEqual(nodes.count, 1)

        let values = GPMFDecoder.readDoubles(from: nodes[0])
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values[0], 56.0, accuracy: 0.001)
    }

    // MARK: - SCAL Node (Int16 scale factor)

    func test_scalNode_int16() {
        // Key="SCAL", Type='s'(0x73), Size=2, Repeat=1, Value=418
        var data = Data()
        data.append(contentsOf: [0x53, 0x43, 0x41, 0x4C])  // "SCAL"
        data.append(contentsOf: [0x73])                      // 's' = int16
        data.append(contentsOf: [0x02])                      // size = 2
        data.append(contentsOf: [0x00, 0x01])                // repeat = 1
        data.append(contentsOf: [0x01, 0xA2])                // 418
        data.append(contentsOf: [0x00, 0x00])                // padding

        let nodes = GPMFDecoder.decode(data: data)
        XCTAssertEqual(nodes.count, 1)

        let values = GPMFDecoder.readDoubles(from: nodes[0])
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values[0], 418.0)
    }
}
