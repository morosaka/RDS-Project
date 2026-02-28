import Foundation

/// Maps raw IMU channels to the GPMF Camera Frame using the ORIN metadata string.
///
/// ## GPMF Camera Frame (from rear of camera, looking forward)
/// - **X_cam**: positive = left
/// - **Y_cam**: positive = into the camera (towards lens)
/// - **Z_cam**: positive = up
///
/// ## ORIN Syntax
/// A 3-character string where:
/// - Character position = channel index (0, 1, 2)
/// - Character value = target camera axis (X, Y, Z)
/// - Character case = sign (uppercase = positive, lowercase = negative)
///
/// Example: `"ZXY"` means channel0→+Z_cam, channel1→+X_cam, channel2→+Y_cam
///
/// ## Reference
/// See `IMU_Canonical_Spec_Axes&Frames.md` for the full specification.
public struct ORINMapper: Sendable {

    /// The parsed mapping: for each camera axis (X, Y, Z), which channel
    /// index it comes from and what sign to apply.
    private let xSource: AxisSource
    private let ySource: AxisSource
    private let zSource: AxisSource

    /// Whether this mapper was successfully initialized from a valid ORIN string.
    public let isValid: Bool

    /// The original ORIN string.
    public let orinString: String

    // MARK: - Init

    /// Creates a mapper from an ORIN string (e.g. "ZXY", "YxZ").
    ///
    /// - Parameter orin: The 3-character ORIN string from the GPMF stream.
    ///   If nil or invalid, the mapper falls through to identity (ch0=X, ch1=Y, ch2=Z).
    public init(orin: String?) {
        guard let orin = orin, orin.count == 3 else {
            // Identity mapping (no ORIN available)
            self.xSource = AxisSource(channelIndex: 0, sign: 1.0)
            self.ySource = AxisSource(channelIndex: 1, sign: 1.0)
            self.zSource = AxisSource(channelIndex: 2, sign: 1.0)
            self.isValid = orin == nil  // nil is OK (unknown camera), wrong length is invalid
            self.orinString = orin ?? "XYZ"
            return
        }

        let chars = Array(orin)
        var xSrc: AxisSource?
        var ySrc: AxisSource?
        var zSrc: AxisSource?

        for (channelIndex, char) in chars.enumerated() {
            let axis = char.uppercased()
            let sign: Double = char.isUppercase ? 1.0 : -1.0
            let source = AxisSource(channelIndex: channelIndex, sign: sign)

            switch axis {
            case "X": xSrc = source
            case "Y": ySrc = source
            case "Z": zSrc = source
            default: break
            }
        }

        // All three axes must be assigned
        if let x = xSrc, let y = ySrc, let z = zSrc {
            self.xSource = x
            self.ySource = y
            self.zSource = z
            self.isValid = true
        } else {
            // Fallback to identity
            self.xSource = AxisSource(channelIndex: 0, sign: 1.0)
            self.ySource = AxisSource(channelIndex: 1, sign: 1.0)
            self.zSource = AxisSource(channelIndex: 2, sign: 1.0)
            self.isValid = false
        }
        self.orinString = orin
    }

    // MARK: - Mapping

    /// Maps a raw 3-channel IMU sample `[c0, c1, c2]` to the GPMF Camera Frame.
    ///
    /// - Parameter channels: Exactly 3 raw channel values (after SCAL).
    /// - Returns: `(xCam, yCam, zCam)` in the GPMF Camera Frame.
    public func map(channels: (Double, Double, Double)) -> (xCam: Double, yCam: Double, zCam: Double) {
        let c = [channels.0, channels.1, channels.2]
        return (
            xCam: xSource.sign * c[xSource.channelIndex],
            yCam: ySource.sign * c[ySource.channelIndex],
            zCam: zSource.sign * c[zSource.channelIndex]
        )
    }

    /// Maps a flat array of scaled values (3 per sample) to `SensorReading` array.
    ///
    /// - Parameters:
    ///   - values: Flat array [c0, c1, c2, c0, c1, c2, ...], already divided by SCAL.
    ///   - timestamps: One timestamp per sample (must have `values.count / 3` entries).
    /// - Returns: Array of `SensorReading` in the GPMF Camera Frame.
    public func mapToReadings(values: [Double], timestamps: [TimeInterval]) -> [SensorReading] {
        let sampleCount = values.count / 3
        guard sampleCount > 0, timestamps.count >= sampleCount else { return [] }

        var readings = [SensorReading]()
        readings.reserveCapacity(sampleCount)

        for i in 0..<sampleCount {
            let base = i * 3
            let mapped = map(channels: (values[base], values[base + 1], values[base + 2]))
            readings.append(SensorReading(
                timestamp: timestamps[i],
                xCam: mapped.xCam,
                yCam: mapped.yCam,
                zCam: mapped.zCam
            ))
        }

        return readings
    }

    // MARK: - Internal

    private struct AxisSource: Sendable {
        let channelIndex: Int
        let sign: Double
    }
}
