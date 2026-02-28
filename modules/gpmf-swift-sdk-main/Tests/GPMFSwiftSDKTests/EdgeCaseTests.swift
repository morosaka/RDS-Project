import XCTest
import Foundation
@testable import GPMFSwiftSDK

// MARK: - KLV Binary Helpers

/// Constructs a minimal GPMF KLV binary record for testing.
///
/// Layout: [key: 4B ASCII][type: 1B][structSize: 1B][repeat: 2B BE][payload][padding]
private func makeKLV(
    key: String,
    type typeByte: UInt8,
    structSize: UInt8,
    repeat repeatCount: UInt16,
    payload: [UInt8] = []
) -> Data {
    var d = Data()
    let keyBytes = Array(key.utf8.prefix(4))
    // Pad key to exactly 4 bytes if needed
    d.append(contentsOf: keyBytes + Array(repeating: UInt8(0x20), count: max(0, 4 - keyBytes.count)))
    d.append(typeByte)
    d.append(structSize)
    d.append(UInt8(repeatCount >> 8))
    d.append(UInt8(repeatCount & 0xFF))
    let payloadLen = Int(structSize) * Int(repeatCount)
    // Append provided payload (truncated/padded to exactly payloadLen)
    let clipped = Array(payload.prefix(payloadLen))
    d.append(contentsOf: clipped)
    d.append(contentsOf: [UInt8](repeating: 0, count: max(0, payloadLen - clipped.count)))
    // Alignment padding
    let aligned = (payloadLen + 3) & ~3
    d.append(contentsOf: [UInt8](repeating: 0, count: aligned - payloadLen))
    return d
}

/// Big-endian Int16 bytes.
private func beInt16(_ v: Int16) -> [UInt8] {
    let u = UInt16(bitPattern: v)
    return [UInt8(u >> 8), UInt8(u & 0xFF)]
}

/// Big-endian Float32 bytes.
private func beFloat32(_ v: Float) -> [UInt8] {
    var bits = v.bitPattern
    return [
        UInt8(bits >> 24), UInt8((bits >> 16) & 0xFF),
        UInt8((bits >> 8) & 0xFF), UInt8(bits & 0xFF)
    ]
}

// MARK: - GPMFDecoder Binary Edge Cases

final class GPMFDecoderBinaryEdgeCaseTests: XCTestCase {

    // MARK: Malformed / Truncated Input

    func test_decode_emptyData_returnsEmpty() {
        let result = GPMFDecoder.decode(data: Data())
        XCTAssertTrue(result.isEmpty, "Empty data must produce no nodes")
    }

    func test_decode_sevenBytes_returnsEmpty() {
        // Less than the 8-byte KLV_HEADER_SIZE
        let data = Data([0x41, 0x43, 0x43, 0x4C, 0x73, 0x06, 0x00])
        let result = GPMFDecoder.decode(data: data)
        XCTAssertTrue(result.isEmpty, "7-byte input (< KLV header) must produce no nodes")
    }

    func test_decode_validHeaderButPayloadExtendsPassEnd_returnsEmpty() {
        // ACCL, int16, structSize=6, repeat=3 → needs 18 bytes of payload; we supply 0
        // After reading the 8-byte header the guard fires and the node is skipped.
        let data = makeKLV(key: "ACCL", type: 0x73, structSize: 6, repeat: 3, payload: [])
        // Supply only the 8-byte header, not the payload
        let headerOnly = data.prefix(8)
        let result = GPMFDecoder.decode(data: headerOnly)
        XCTAssertTrue(result.isEmpty, "Header without payload must return no nodes")
    }

    func test_decode_repeatCountZero_nodeCreatedButDataEmpty() {
        // repeat=0 → payloadSize=0 → valid, but no data
        let data = makeKLV(key: "ACCL", type: 0x73, structSize: 6, repeat: 0, payload: [])
        let nodes = GPMFDecoder.decode(data: data)
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].repeatCount, 0)
        XCTAssertEqual(GPMFDecoder.readDoubles(from: nodes[0]).count, 0)
    }

    func test_decode_structSizeZero_doesNotCrash() {
        // structSize=0, repeat=5 → payloadSize=0; node is created
        let data = makeKLV(key: "ACCL", type: 0x73, structSize: 0, repeat: 5, payload: [])
        // Must not crash; result count is an implementation detail
        XCTAssertNoThrow(GPMFDecoder.decode(data: data))
    }

    func test_decode_consecutiveValidNodes_parsedCorrectly() {
        // Two SCAL nodes back-to-back
        var data = Data()
        data.append(makeKLV(key: "SCAL", type: 0x53, structSize: 2, repeat: 1, payload: [0, 64]))
        data.append(makeKLV(key: "SCAL", type: 0x53, structSize: 2, repeat: 1, payload: [0, 32]))
        let nodes = GPMFDecoder.decode(data: data)
        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(nodes[0].key, "SCAL")
        XCTAssertEqual(nodes[1].key, "SCAL")
    }

    // MARK: readDoubles Behavior

    func test_readDoubles_emptyData_returnsEmpty() {
        let node = GpmfNode(
            key: "ACCL", valueType: .int16, structSize: 6, repeatCount: 3,
            data: Data(), children: nil
        )
        XCTAssertTrue(GPMFDecoder.readDoubles(from: node).isEmpty,
            "readDoubles with empty data must return []")
    }

    func test_readDoubles_nilData_returnsEmpty() {
        let node = GpmfNode(
            key: "TMPC", valueType: .float, structSize: 4, repeatCount: 1,
            data: nil, children: nil
        )
        XCTAssertTrue(GPMFDecoder.readDoubles(from: node).isEmpty,
            "readDoubles with nil data must return []")
    }

    func test_readDoubles_int16Payload_returnsCorrectValues() {
        // 3 int16 values: 100, -200, 300 (Big Endian)
        let payload: [UInt8] = [0x00, 0x64, 0xFF, 0x38, 0x01, 0x2C]  // 100, -200, 300
        let node = GpmfNode(
            key: "ACCL", valueType: .int16, structSize: 6, repeatCount: 1,
            data: Data(payload), children: nil
        )
        let doubles = GPMFDecoder.readDoubles(from: node)
        XCTAssertEqual(doubles.count, 3)
        XCTAssertEqual(doubles[0],  100.0, accuracy: 0.001)
        XCTAssertEqual(doubles[1], -200.0, accuracy: 0.001)
        XCTAssertEqual(doubles[2],  300.0, accuracy: 0.001)
    }

    func test_readDoubles_floatPayload_returnsCorrectValues() {
        // One float sample: 9.81 m/s²
        let bytes = beFloat32(9.81)
        let node = GpmfNode(
            key: "TMPC", valueType: .float, structSize: 4, repeatCount: 1,
            data: Data(bytes), children: nil
        )
        let doubles = GPMFDecoder.readDoubles(from: node)
        XCTAssertEqual(doubles.count, 1)
        XCTAssertEqual(doubles[0], 9.81, accuracy: 0.01)
    }

    func test_readDoubles_truncatedData_doesNotCrash() {
        // Claim 3 int16 samples but only supply 4 bytes (not enough for all)
        let node = GpmfNode(
            key: "ACCL", valueType: .int16, structSize: 6, repeatCount: 3,
            data: Data([0x00, 0x64, 0x00, 0x32]), children: nil
        )
        // Must not crash
        XCTAssertNoThrow(GPMFDecoder.readDoubles(from: node))
    }

    func test_readString_nilData_returnsNil() {
        let node = GpmfNode(
            key: "DVNM", valueType: .char, structSize: 5, repeatCount: 1,
            data: nil, children: nil
        )
        XCTAssertNil(GPMFDecoder.readString(from: node))
    }

    func test_readString_nullTerminated_stripsNull() {
        let s = "HERO\0".data(using: .utf8)!
        let node = GpmfNode(
            key: "DVNM", valueType: .char, structSize: 5, repeatCount: 1,
            data: s, children: nil
        )
        XCTAssertEqual(GPMFDecoder.readString(from: node), "HERO")
    }

    func test_readString_allNulls_returnsEmptyOrNil() {
        let node = GpmfNode(
            key: "DVNM", valueType: .char, structSize: 4, repeatCount: 1,
            data: Data(repeating: 0, count: 4), children: nil
        )
        // After stripping nulls and whitespace, result is "" which should be empty
        let result = GPMFDecoder.readString(from: node)
        XCTAssertTrue(result == nil || result == "",
            "All-null data should return nil or empty string")
    }
}

// MARK: - GpmfNode Property Edge Cases

final class GpmfNodeEdgeCaseTests: XCTestCase {

    func test_elementsPerSample_nestedType_returnsNil() {
        let node = GpmfNode(
            key: "DEVC", valueType: .nested, structSize: 100, repeatCount: 1,
            data: nil, children: []
        )
        XCTAssertNil(node.elementsPerSample,
            "Nested nodes have no element size, so elementsPerSample must be nil")
    }

    func test_elementsPerSample_float3axis_returns3() {
        let node = GpmfNode(
            key: "GRAV", valueType: .float, structSize: 12, repeatCount: 10,
            data: nil, children: nil
        )
        XCTAssertEqual(node.elementsPerSample, 3,
            "float (4 bytes) × 3 axes = structSize 12 → 3 elements per sample")
    }

    func test_elementsPerSample_int16_3axis_returns3() {
        let node = GpmfNode(
            key: "ACCL", valueType: .int16, structSize: 6, repeatCount: 100,
            data: nil, children: nil
        )
        XCTAssertEqual(node.elementsPerSample, 3)
    }

    func test_elementsPerSample_zeroStructSize_returns0_andDoesNotCrash() {
        let node = GpmfNode(
            key: "ACCL", valueType: .int16, structSize: 0, repeatCount: 10,
            data: nil, children: nil
        )
        // structSize 0 / elementSize 2 = 0 — must not crash
        XCTAssertEqual(node.elementsPerSample, 0)
    }

    func test_payloadSize_computedCorrectly() {
        let node = GpmfNode(
            key: "ACCL", valueType: .int16, structSize: 6, repeatCount: 100,
            data: nil, children: nil
        )
        XCTAssertEqual(node.payloadSize, 600)
    }

    func test_isContainer_nestedType_true() {
        let node = GpmfNode(
            key: "STRM", valueType: .nested, structSize: 50, repeatCount: 1,
            data: nil, children: []
        )
        XCTAssertTrue(node.isContainer)
    }

    func test_isContainer_leafType_false() {
        let node = GpmfNode(
            key: "ACCL", valueType: .int16, structSize: 6, repeatCount: 1,
            data: Data(count: 6), children: nil
        )
        XCTAssertFalse(node.isContainer)
    }

    func test_childForKey_leafNode_returnsNil() {
        let node = GpmfNode(
            key: "ACCL", valueType: .int16, structSize: 6, repeatCount: 1,
            data: Data(count: 6), children: nil
        )
        XCTAssertNil(node.child(forKey: "SCAL"))
        XCTAssertNil(node.child(forKey: .scal))
    }

    func test_childForKey_containerWithChildren_findsChild() {
        let child = GpmfNode(
            key: "SCAL", valueType: .uint16, structSize: 2, repeatCount: 1,
            data: Data([0, 100]), children: nil
        )
        let parent = GpmfNode(
            key: "STRM", valueType: .nested, structSize: 10, repeatCount: 1,
            data: nil, children: [child]
        )
        XCTAssertNotNil(parent.child(forKey: .scal))
        XCTAssertNil(parent.child(forKey: .accl))
    }

    func test_gpmfKey_knownKey_returnsEnum() {
        let node = GpmfNode(
            key: "ACCL", valueType: .int16, structSize: 6, repeatCount: 1,
            data: nil, children: nil
        )
        XCTAssertEqual(node.gpmfKey, .accl)
    }

    func test_gpmfKey_unknownKey_returnsNil() {
        let node = GpmfNode(
            key: "UNKN", valueType: .int16, structSize: 4, repeatCount: 1,
            data: nil, children: nil
        )
        XCTAssertNil(node.gpmfKey)
    }
}

// MARK: - ORINMapper Edge Cases

final class ORINMapperEdgeCaseTests: XCTestCase {

    func test_init_nil_isValidAndIdentity() {
        let m = ORINMapper(orin: nil)
        XCTAssertTrue(m.isValid, "nil ORIN = unknown camera, treated as valid identity")
        let r = m.map(channels: (1, 2, 3))
        XCTAssertEqual(r.xCam, 1); XCTAssertEqual(r.yCam, 2); XCTAssertEqual(r.zCam, 3)
    }

    func test_init_emptyString_fallbackIdentity() {
        let m = ORINMapper(orin: "")
        XCTAssertFalse(m.isValid)
        let r = m.map(channels: (1, 2, 3))
        XCTAssertEqual(r.xCam, 1); XCTAssertEqual(r.yCam, 2); XCTAssertEqual(r.zCam, 3)
    }

    func test_init_wrongLength_fallbackIdentity() {
        let m = ORINMapper(orin: "ZX")  // only 2 chars
        XCTAssertFalse(m.isValid)
    }

    func test_init_invalidAxisChar_fallbackIdentity() {
        // "ZXA" — 'A' is not a valid axis
        let m = ORINMapper(orin: "ZXA")
        XCTAssertFalse(m.isValid)
        let r = m.map(channels: (1, 2, 3))
        XCTAssertEqual(r.xCam, 1); XCTAssertEqual(r.yCam, 2); XCTAssertEqual(r.zCam, 3)
    }

    func test_init_duplicateAxis_fallbackIdentity() {
        // "XXZ" — X assigned twice, Y never assigned
        let m = ORINMapper(orin: "XXZ")
        XCTAssertFalse(m.isValid)
        let r = m.map(channels: (1, 2, 3))
        XCTAssertEqual(r.xCam, 1); XCTAssertEqual(r.yCam, 2); XCTAssertEqual(r.zCam, 3)
    }

    func test_init_ZXY_mapsCorrectly() {
        // HERO10 canonical: ch0→+Z, ch1→+X, ch2→+Y
        let m = ORINMapper(orin: "ZXY")
        XCTAssertTrue(m.isValid)
        let r = m.map(channels: (10, 20, 30))
        XCTAssertEqual(r.xCam,  20)  // ch1 = +X
        XCTAssertEqual(r.yCam,  30)  // ch2 = +Y
        XCTAssertEqual(r.zCam,  10)  // ch0 = +Z
    }

    func test_init_allNegative_appliesSign() {
        // "zxy" — ch0→-Z, ch1→-X, ch2→-Y
        let m = ORINMapper(orin: "zxy")
        XCTAssertTrue(m.isValid)
        let r = m.map(channels: (10, 20, 30))
        XCTAssertEqual(r.xCam, -20)
        XCTAssertEqual(r.yCam, -30)
        XCTAssertEqual(r.zCam, -10)
    }

    func test_init_mixedCase_appliesCorrectSigns() {
        // "ZXy" — ch0→+Z, ch1→+X, ch2→-Y
        let m = ORINMapper(orin: "ZXy")
        XCTAssertTrue(m.isValid)
        let r = m.map(channels: (1, 2, 3))
        XCTAssertEqual(r.xCam,  2)
        XCTAssertEqual(r.yCam, -3)
        XCTAssertEqual(r.zCam,  1)
    }

    func test_mapToReadings_emptyValues_returnsEmpty() {
        let m = ORINMapper(orin: "ZXY")
        let result = m.mapToReadings(values: [], timestamps: [])
        XCTAssertTrue(result.isEmpty)
    }

    func test_mapToReadings_insufficientTimestamps_returnsEmpty() {
        let m = ORINMapper(orin: "ZXY")
        // 6 values = 2 samples, but only 1 timestamp
        let result = m.mapToReadings(values: [1, 2, 3, 4, 5, 6], timestamps: [0.5])
        XCTAssertTrue(result.isEmpty,
            "Not enough timestamps for the sample count should return []")
    }

    func test_mapToReadings_partialExtraValues_ignoredGracefully() {
        let m = ORINMapper(orin: "XYZ")
        // 7 values — 2 complete samples (6 values), 1 leftover; only 2 samples mapped
        let result = m.mapToReadings(values: [1, 2, 3, 4, 5, 6, 7], timestamps: [0, 1])
        XCTAssertEqual(result.count, 2, "Leftover values (7 mod 3 = 1) are silently dropped")
    }
}

// MARK: - StreamFilter Edge Cases

final class StreamFilterEdgeCaseTests: XCTestCase {

    func test_emptyFilter_extractsNothing() throws {
        let f = StreamFilter(keys: [])
        // No sensor keys — shouldExtract always returns false for sensors
        XCTAssertFalse(f.shouldExtract(.accl))
        XCTAssertFalse(f.shouldExtract(.gyro))
        XCTAssertFalse(f.shouldExtract(.gps5))
    }

    func test_filter_withSingleKey_returnsExpected() {
        let f = StreamFilter(.tmpc)
        XCTAssertTrue(f.shouldExtract(.tmpc))
        XCTAssertFalse(f.shouldExtract(.accl))
    }

    func test_filter_isValueType_equalitySafe() {
        let f1 = StreamFilter(.accl, .gyro)
        let f2 = StreamFilter(.gyro, .accl)
        XCTAssertEqual(f1, f2, "StreamFilter equality must be order-independent (Set semantics)")
    }

    func test_filter_all_hasExactly8SensorKeys() {
        XCTAssertEqual(StreamFilter.all.keys.count, 8)
    }
}

// MARK: - UNIT Tag Regression Tests

/// Regression tests for the UNIT tag (`GPMFKey.unit`) bug.
///
/// **Bug:** `extractStreamMetadata` was missing a `case GPMFKey.unit.rawValue:` branch,
/// so `StreamInfo.displayUnit` was always `nil` even when the GPMF stream contained a
/// UNIT tag. Fixed by adding the missing case.
///
/// These tests validate the two building blocks that the fix depends on:
/// 1. `GPMFKey.unit.rawValue` is the correct FourCC string `"UNIT"`.
/// 2. A UNIT KLV node decoded from binary produces a readable display-unit string
///    via `GPMFDecoder.readString(from:)`.
final class UNITTagRegressionTests: XCTestCase {

    // MARK: Key constant

    func test_unitKey_rawValue_isUNIT() {
        XCTAssertEqual(GPMFKey.unit.rawValue, "UNIT",
            "GPMFKey.unit must encode to the FourCC 'UNIT'")
    }

    // MARK: KLV decode of a UNIT node

    func test_decode_unitKLV_yieldsNodeWithCorrectKey() {
        // Build a UNIT KLV: type 'c' (0x63), structSize=4, repeat=1, payload = "m/s"
        let payload: [UInt8] = [UInt8(ascii: "m"), UInt8(ascii: "/"), UInt8(ascii: "s"), 0x00]
        let unitKLV = makeKLV(key: "UNIT", type: 0x63, structSize: 4, repeat: 1, payload: payload)
        let nodes = GPMFDecoder.decode(data: unitKLV)
        XCTAssertEqual(nodes.count, 1, "Expected exactly one decoded node")
        XCTAssertEqual(nodes.first?.key, "UNIT")
    }

    func test_decode_unitKLV_readStringReturnsDisplayUnit() {
        // Builds a UNIT KLV with value "m/s" and verifies GPMFDecoder.readString extracts it.
        let unitString = "m/s"
        var payloadBytes = Array(unitString.utf8)
        payloadBytes.append(0x00) // null terminator
        let unitKLV = makeKLV(
            key: "UNIT", type: 0x63, // 'c' = char
            structSize: UInt8(payloadBytes.count),
            repeat: 1,
            payload: payloadBytes
        )
        let nodes = GPMFDecoder.decode(data: unitKLV)
        guard let unitNode = nodes.first else {
            XCTFail("No UNIT node decoded"); return
        }
        let result = GPMFDecoder.readString(from: unitNode)
        XCTAssertEqual(result, unitString,
            "readString should strip the null terminator and return '\(unitString)'")
    }

    func test_unitKey_isDifferentFromSiunKey() {
        // UNIT (display, e.g. "km/h") and SIUN (SI unit, e.g. "m/s") are distinct keys.
        XCTAssertNotEqual(GPMFKey.unit.rawValue, GPMFKey.siun.rawValue)
    }
}

// MARK: - 8.4 Fuzz Tests

final class GPMFDecoderFuzzTests: XCTestCase {

    // Deterministic pseudorandom bytes (no Foundation.arc4random dependency)
    private static func pseudoRandom(seed: UInt64, count: Int) -> [UInt8] {
        var state = seed
        var bytes = [UInt8](repeating: 0, count: count)
        for i in 0..<count {
            // xorshift64
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            bytes[i] = UInt8(state & 0xFF)
        }
        return bytes
    }

    /// Core invariant: `GPMFDecoder.decode` must never crash on any binary input.
    private func assertDecodesWithoutCrash(_ data: Data, label: String) {
        let nodes = GPMFDecoder.decode(data: data)
        // For each node, also invoke readDoubles and readString
        func visitNodes(_ ns: [GpmfNode]) {
            for n in ns {
                _ = GPMFDecoder.readDoubles(from: n)
                _ = GPMFDecoder.readString(from: n)
                if let children = n.children { visitNodes(children) }
            }
        }
        visitNodes(nodes)
        // If we get here without crashing or throwing, the test passes
        _ = nodes.count  // consume the result
    }

    // MARK: Pathological Inputs

    func test_fuzz_allZeros_lengths() {
        for length in [0, 1, 4, 7, 8, 9, 15, 16, 32, 64, 128, 256] {
            assertDecodesWithoutCrash(Data(repeating: 0, count: length),
                                      label: "allZeros_\(length)")
        }
    }

    func test_fuzz_allFF_lengths() {
        for length in [0, 1, 7, 8, 16, 32, 100, 1000] {
            assertDecodesWithoutCrash(Data(repeating: 0xFF, count: length),
                                      label: "allFF_\(length)")
        }
    }

    func test_fuzz_repeatingACCLKey_withGarbagePayload() {
        // "ACCL" key bytes repeated — each iteration is 4 bytes of key
        let garbageChunk = Data([0x41, 0x43, 0x43, 0x4C,   // "ACCL"
                                  0x73, 0x06, 0x00, 0x03,   // int16, size=6, repeat=3
                                  0xFF, 0xFF, 0xFF, 0xFF,   // garbage payload (partial)
                                  0xFF, 0xFF, 0xFF, 0xFF])
        for n in [1, 5, 20] {
            var data = Data()
            for _ in 0..<n { data.append(garbageChunk) }
            assertDecodesWithoutCrash(data, label: "repeatingACCL_\(n)")
        }
    }

    func test_fuzz_maxSizeRepeatCount() {
        // repeat=0xFFFF with structSize=1 → claims 65535 bytes payload but data is only 8 bytes
        let data = Data([
            0x41, 0x43, 0x43, 0x4C,  // "ACCL"
            0x66, 0x01,               // float, structSize=1
            0xFF, 0xFF                // repeat=65535
        ])
        assertDecodesWithoutCrash(data, label: "maxRepeatCount")
    }

    func test_fuzz_nestedContainerWithExaggeratedSize() {
        // DEVC claiming a 65535-byte body with only 8 bytes of data
        let data = Data([
            0x44, 0x45, 0x56, 0x43,  // "DEVC"
            0x00, 0xFF,               // nested, structSize=255
            0x01, 0x00                // repeat=256 → 65280 bytes claimed
        ])
        assertDecodesWithoutCrash(data, label: "nestedExaggeratedSize")
    }

    // MARK: Random Byte Sequences

    func test_fuzz_randomBytes_seed1() {
        let bytes = Self.pseudoRandom(seed: 0xDEAD_BEEF_CAFE_1234, count: 4096)
        assertDecodesWithoutCrash(Data(bytes), label: "random_seed1")
    }

    func test_fuzz_randomBytes_seed2() {
        let bytes = Self.pseudoRandom(seed: 0x0102_0304_0506_0708, count: 4096)
        assertDecodesWithoutCrash(Data(bytes), label: "random_seed2")
    }

    func test_fuzz_randomBytes_seed3() {
        let bytes = Self.pseudoRandom(seed: 0xFEDC_BA98_7654_3210, count: 512)
        assertDecodesWithoutCrash(Data(bytes), label: "random_seed3")
    }

    func test_fuzz_randomBytes_seed4_shortBuffers() {
        // Lots of tiny buffers to exercise boundary conditions
        var state: UInt64 = 0xABCD_EF01_2345_6789
        for _ in 0..<100 {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            let length = Int(state & 0x3F)  // 0..63 bytes
            let bytes = Self.pseudoRandom(seed: state, count: length)
            assertDecodesWithoutCrash(Data(bytes), label: "shortBuffer_\(length)")
        }
    }

    func test_fuzz_randomBytes_seed5_largBuffer() {
        let bytes = Self.pseudoRandom(seed: 0x9999_8888_7777_6666, count: 65536)
        assertDecodesWithoutCrash(Data(bytes), label: "random_seed5_64KB")
    }

    // MARK: Well-formed KLV With Extreme Values

    func test_fuzz_wideRange_scaleValues_doesNotDivideByZero() {
        // Build a SCAL KLV with value 0 (uint16 = 0x0000)
        let scal = makeKLV(key: "SCAL", type: 0x53, structSize: 2, repeat: 1,
                           payload: [0x00, 0x00])
        let nodes = GPMFDecoder.decode(data: scal)
        XCTAssertEqual(nodes.count, 1)
        let vals = GPMFDecoder.readDoubles(from: nodes[0])
        XCTAssertEqual(vals.count, 1)
        XCTAssertEqual(vals[0], 0.0)  // SCAL=0 is just data; division guard is in extractor
    }

    func test_fuzz_gps5KLV_correctParsing() {
        // Build one GPS5 sample: [lat, lon, alt, speed2d, speed3d] as int32 BE
        // Values: lat=900000000, lon=1800000000, alt=10000, speed2d=100, speed3d=150
        func beInt32(_ v: Int32) -> [UInt8] {
            let u = UInt32(bitPattern: v)
            return [UInt8(u >> 24), UInt8((u >> 16) & 0xFF), UInt8((u >> 8) & 0xFF), UInt8(u & 0xFF)]
        }
        var payload = [UInt8]()
        payload += beInt32(900_000_000)
        payload += beInt32(1_800_000_000)
        payload += beInt32(10_000)
        payload += beInt32(100)
        payload += beInt32(150)
        // GPS5 is int32, structSize=20 (5×4), repeat=1
        let data = makeKLV(key: "GPS5", type: 0x6C, structSize: 20, repeat: 1, payload: payload)
        let nodes = GPMFDecoder.decode(data: data)
        XCTAssertEqual(nodes.count, 1)
        let vals = GPMFDecoder.readDoubles(from: nodes[0])
        XCTAssertEqual(vals.count, 5)
        XCTAssertEqual(vals[0], 900_000_000.0, accuracy: 1)
        XCTAssertEqual(vals[2],      10_000.0, accuracy: 1)
    }
}
