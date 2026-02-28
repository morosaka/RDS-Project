import Foundation

/// Decodes raw GPMF binary data into a hierarchical tree of `GpmfNode`.
///
/// GPMF is a KLV (Key-Length-Value) format with 32-bit alignment
/// and Big Endian byte order.
///
/// The decoder handles all standard GPMF value types:
/// `b, B, c, d, f, F, G, j, J, l, L, q, Q, s, S, U, ?` and nested (null).
public final class GPMFDecoder {

    private init() {}

    // MARK: - Public API

    /// Parses a raw GPMF payload into a tree of nodes.
    ///
    /// - Parameter data: Raw GPMF bytes (one MP4 sample payload).
    /// - Returns: Array of top-level `GpmfNode` (typically one `DEVC` per device).
    public static func decode(data: Data) -> [GpmfNode] {
        let stream = InputStream(data: data)
        return parseNodes(stream: stream, end: data.count)
    }

    // MARK: - Recursive Parser

    private static func parseNodes(stream: InputStream, end: Int) -> [GpmfNode] {
        var nodes: [GpmfNode] = []

        while stream.position + GPMF.KLV_HEADER_SIZE <= end {
            guard let header = try? readKLVHeader(stream: stream) else { break }

            let payloadSize = header.structSize * header.repeatCount
            let alignedSize = (payloadSize + 3) & ~3

            guard stream.position + payloadSize <= end else { break }

            if header.valueType == .nested {
                // Container — recurse
                let childEnd = stream.position + payloadSize
                let children = parseNodes(stream: stream, end: childEnd)
                // Advance past any alignment padding
                if stream.position < stream.position + (alignedSize - payloadSize) {
                    try? stream.seek(to: stream.position + (alignedSize - payloadSize))
                }
                // Ensure we are past the aligned end
                let targetPos = childEnd + ((alignedSize - payloadSize))
                if stream.position < targetPos {
                    try? stream.seek(to: min(targetPos, end))
                }

                nodes.append(GpmfNode(
                    key: header.key,
                    valueType: .nested,
                    structSize: header.structSize,
                    repeatCount: header.repeatCount,
                    data: nil,
                    children: children
                ))
            } else {
                // Leaf — read raw payload
                let payloadData = try? stream.readBytes(payloadSize)
                // Skip alignment padding
                let padding = alignedSize - payloadSize
                if padding > 0 { try? stream.skip(padding) }

                nodes.append(GpmfNode(
                    key: header.key,
                    valueType: header.valueType,
                    structSize: header.structSize,
                    repeatCount: header.repeatCount,
                    data: payloadData,
                    children: nil
                ))
            }
        }

        return nodes
    }

    // MARK: - KLV Header

    private struct KLVHeader {
        let key: String
        let valueType: GPMFValueType
        let structSize: Int
        let repeatCount: Int
    }

    private static func readKLVHeader(stream: InputStream) throws -> KLVHeader {
        let keyData = try stream.readBytes(4)
        guard let key = String(data: keyData, encoding: .ascii) else {
            throw GPMFError.invalidKLV("Non-ASCII key at offset \(stream.position - 4)")
        }
        let typeByte = try stream.readUInt8()
        let structSize = Int(try stream.readUInt8())
        let repeatCount = Int(try stream.readUInt16BE())

        let valueType = GPMFValueType(rawValue: typeByte) ?? .uint8  // fallback to uint8 for unknown

        return KLVHeader(key: key, valueType: valueType, structSize: structSize, repeatCount: repeatCount)
    }

    // MARK: - Value Reading

    /// Reads all scalar values from a leaf node, returning them as `Double`.
    ///
    /// Multi-axis samples are flattened: a 3-axis sensor with 100 repeats
    /// produces 300 values: [x0, y0, z0, x1, y1, z1, ...].
    public static func readDoubles(from node: GpmfNode) -> [Double] {
        guard let data = node.data, !data.isEmpty else { return [] }
        let stream = InputStream(data: data)
        var values: [Double] = []

        let totalElements = totalElementCount(node: node)
        values.reserveCapacity(totalElements)

        for _ in 0..<node.repeatCount {
            let elementsInSample = elementCount(structSize: node.structSize, type: node.valueType)
            for _ in 0..<elementsInSample {
                guard let v = readOneDouble(stream: stream, type: node.valueType) else { break }
                values.append(v)
            }
        }

        return values
    }

    /// Reads all values as their native type, boxed as `Any`.
    public static func readValues(from node: GpmfNode) -> [Any] {
        guard let data = node.data, !data.isEmpty else { return [] }
        let stream = InputStream(data: data)
        var values: [Any] = []

        for _ in 0..<node.repeatCount {
            let elementsInSample = elementCount(structSize: node.structSize, type: node.valueType)
            for _ in 0..<elementsInSample {
                guard let v = readOneValue(stream: stream, type: node.valueType) else { break }
                values.append(v)
            }
        }

        return values
    }

    /// Reads the node payload as a UTF-8 string, stripping null terminators.
    public static func readString(from node: GpmfNode) -> String? {
        guard let data = node.data else { return nil }
        return String(data: data, encoding: .utf8)?
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Single-Value Readers

    private static func readOneDouble(stream: InputStream, type: GPMFValueType) -> Double? {
        do {
            switch type {
            case .int8:      return Double(Int8(bitPattern: try stream.readUInt8()))
            case .uint8:     return Double(try stream.readUInt8())
            case .int16:     return Double(try stream.readInt16BE())
            case .uint16:    return Double(try stream.readUInt16BE())
            case .int32:     return Double(try stream.readInt32BE())
            case .uint32:    return Double(try stream.readUInt32BE())
            case .int64:     return Double(try stream.readInt64BE())
            case .uint64:    return Double(try stream.readUInt64BE())
            case .float:     return Double(try stream.readFloatBE())
            case .double:    return try stream.readDoubleBE()
            case .qNumber32:
                let raw = try stream.readUInt32BE()
                let intPart = Int16(bitPattern: UInt16(raw >> 16))
                let fracPart = Double(raw & 0xFFFF) / 65536.0
                return Double(intPart) + fracPart
            case .qNumber64:
                let raw = try stream.readUInt64BE()
                let intPart = Int32(bitPattern: UInt32(raw >> 32))
                let fracPart = Double(raw & 0xFFFFFFFF) / 4294967296.0
                return Double(intPart) + fracPart
            default:
                return nil
            }
        } catch {
            return nil
        }
    }

    private static func readOneValue(stream: InputStream, type: GPMFValueType) -> Any? {
        do {
            switch type {
            case .int8:      return Int8(bitPattern: try stream.readUInt8())
            case .uint8:     return try stream.readUInt8()
            case .int16:     return try stream.readInt16BE()
            case .uint16:    return try stream.readUInt16BE()
            case .int32:     return try stream.readInt32BE()
            case .uint32:    return try stream.readUInt32BE()
            case .int64:     return try stream.readInt64BE()
            case .uint64:    return try stream.readUInt64BE()
            case .float:     return try stream.readFloatBE()
            case .double:    return try stream.readDoubleBE()
            case .fourCC:    return try stream.readFourCC()
            case .char:      return try stream.readUInt8()  // char-by-char
            case .qNumber32:
                let raw = try stream.readUInt32BE()
                let intPart = Int16(bitPattern: UInt16(raw >> 16))
                let fracPart = Double(raw & 0xFFFF) / 65536.0
                return Double(intPart) + fracPart
            case .qNumber64:
                let raw = try stream.readUInt64BE()
                let intPart = Int32(bitPattern: UInt32(raw >> 32))
                let fracPart = Double(raw & 0xFFFFFFFF) / 4294967296.0
                return Double(intPart) + fracPart
            case .utcDate:
                return try stream.readString(16)
            case .guid:
                return try stream.readBytes(16)
            default:
                return nil
            }
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    /// Number of typed elements in one struct sample.
    private static func elementCount(structSize: Int, type: GPMFValueType) -> Int {
        guard let elemSize = type.elementSize, elemSize > 0 else { return 1 }
        return structSize / elemSize
    }

    /// Total number of typed elements across all repeats.
    private static func totalElementCount(node: GpmfNode) -> Int {
        elementCount(structSize: node.structSize, type: node.valueType) * node.repeatCount
    }
}
