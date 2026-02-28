import Foundation

/// A single node in the GPMF KLV tree.
///
/// GPMF data is hierarchical: a root payload contains `DEVC` containers,
/// which contain `STRM` containers, which contain sensor data and metadata.
/// Each node represents one KLV 3-tuple.
public struct GpmfNode: Sendable {

    /// The 4-character key (FourCC) identifying this node.
    public let key: String

    /// The GPMF value type descriptor.
    public let valueType: GPMFValueType

    /// The size of a single sample (structure) in bytes.
    public let structSize: Int

    /// The number of samples (repeats) in this node's payload.
    public let repeatCount: Int

    /// Raw payload data for leaf nodes. `nil` for container nodes.
    public let data: Data?

    /// Child nodes for container types (valueType == .nested). `nil` for leaf nodes.
    public let children: [GpmfNode]?

    // MARK: Convenience

    /// Total payload size in bytes (structSize × repeatCount).
    public var payloadSize: Int {
        structSize * repeatCount
    }

    /// Number of elements per sample, derived from structSize / element size.
    /// For example, 3-axis accel with Int16 has structSize=6, elementSize=2 → 3 axes.
    /// Returns nil for nested or complex types.
    public var elementsPerSample: Int? {
        guard let elementSize = valueType.elementSize, elementSize > 0 else { return nil }
        return structSize / elementSize
    }

    /// The well-known GPMF key, if recognized.
    public var gpmfKey: GPMFKey? {
        GPMFKey(rawValue: key)
    }

    /// Whether this node is a container (has children, not leaf data).
    public var isContainer: Bool {
        valueType == .nested
    }

    // MARK: Child Lookup

    /// Finds the first child with the given FourCC key string.
    public func child(forKey key: String) -> GpmfNode? {
        children?.first { $0.key == key }
    }

    /// Finds the first child matching a well-known GPMF key.
    public func child(forKey key: GPMFKey) -> GpmfNode? {
        child(forKey: key.rawValue)
    }

    /// Finds all children matching a well-known GPMF key.
    public func children(forKey key: GPMFKey) -> [GpmfNode] {
        children?.filter { $0.key == key.rawValue } ?? []
    }
}
