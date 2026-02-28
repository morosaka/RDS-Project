import Foundation

/// A lightweight binary cursor over `Data`, supporting Big Endian reads.
///
/// Modelled after the FIT SDK's `InputStream` for consistency across sibling SDKs.
/// GPMF data is always Big Endian and 32-bit aligned.
final class InputStream: @unchecked Sendable {

    // MARK: Error

    enum InputStreamError: Error, Equatable {
        case positionIndexOutOfRange
        case readBeyondEnd(needed: Int, available: Int)
    }

    // MARK: Properties

    private let data: Data

    /// Current read position (byte offset from start).
    private(set) var position: Int = 0

    /// Total number of bytes in the stream.
    var count: Int { data.count }

    /// Number of bytes remaining from current position.
    var bytesRemaining: Int { max(0, data.count - position) }

    // MARK: Init

    init(data: Data) {
        self.data = data
    }

    // MARK: Position Control

    /// Seeks to the given absolute byte offset.
    func seek(to offset: Int) throws {
        guard offset >= 0, offset <= data.count else {
            throw InputStreamError.positionIndexOutOfRange
        }
        position = offset
    }

    /// Advances position by `count` bytes.
    func skip(_ count: Int) throws {
        try seek(to: position + count)
    }

    // MARK: Peek

    /// Returns the byte at the current position without advancing.
    func peekByte() throws -> UInt8 {
        guard position < data.count else {
            throw InputStreamError.readBeyondEnd(needed: 1, available: 0)
        }
        return data[data.startIndex + position]
    }

    // MARK: Read Raw

    /// Reads `length` bytes from the current position and advances.
    func readBytes(_ length: Int) throws -> Data {
        guard position + length <= data.count else {
            throw InputStreamError.readBeyondEnd(needed: length, available: bytesRemaining)
        }
        let start = data.startIndex + position
        let result = data[start..<start + length]
        position += length
        return Data(result)
    }

    /// Reads a single byte and advances.
    func readUInt8() throws -> UInt8 {
        guard position < data.count else {
            throw InputStreamError.readBeyondEnd(needed: 1, available: 0)
        }
        let value = data[data.startIndex + position]
        position += 1
        return value
    }

    // MARK: Big-Endian Numeric Reads

    /// Reads a Big-Endian `UInt16` and advances by 2 bytes.
    func readUInt16BE() throws -> UInt16 {
        let bytes = try readBytes(2)
        // loadUnaligned: GPMF data is 32-bit aligned but reads at arbitrary byte offsets
        // within a payload are not guaranteed to be naturally aligned.
        return bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }.bigEndian
    }

    /// Reads a Big-Endian `Int16` and advances by 2 bytes.
    func readInt16BE() throws -> Int16 {
        Int16(bitPattern: try readUInt16BE())
    }

    /// Reads a Big-Endian `UInt32` and advances by 4 bytes.
    func readUInt32BE() throws -> UInt32 {
        let bytes = try readBytes(4)
        return bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian
    }

    /// Reads a Big-Endian `Int32` and advances by 4 bytes.
    func readInt32BE() throws -> Int32 {
        Int32(bitPattern: try readUInt32BE())
    }

    /// Reads a Big-Endian `UInt64` and advances by 8 bytes.
    func readUInt64BE() throws -> UInt64 {
        let bytes = try readBytes(8)
        return bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.bigEndian
    }

    /// Reads a Big-Endian `Int64` and advances by 8 bytes.
    func readInt64BE() throws -> Int64 {
        Int64(bitPattern: try readUInt64BE())
    }

    /// Reads a Big-Endian IEEE 754 `Float` and advances by 4 bytes.
    func readFloatBE() throws -> Float {
        Float(bitPattern: try readUInt32BE())
    }

    /// Reads a Big-Endian IEEE 754 `Double` and advances by 8 bytes.
    func readDoubleBE() throws -> Double {
        Double(bitPattern: try readUInt64BE())
    }

    // MARK: String

    /// Reads `length` bytes as a UTF-8 string, stripping null terminators.
    func readString(_ length: Int) throws -> String {
        let bytes = try readBytes(length)
        let str = String(data: bytes, encoding: .utf8) ?? ""
        // Strip null terminators and trailing whitespace per GPMF convention
        return str.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .whitespaces)
    }

    /// Reads 4 bytes as an ASCII FourCC string.
    func readFourCC() throws -> String {
        try readString(4)
    }
}
