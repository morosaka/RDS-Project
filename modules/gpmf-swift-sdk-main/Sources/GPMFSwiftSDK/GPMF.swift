import Foundation

// MARK: - Constants

/// Namespace for GPMF format constants.
public struct GPMF: Sendable {

    private init() {}

    /// GPMF KLV header size in bytes: Key(4) + Type(1) + Size(1) + Repeat(2).
    public static let KLV_HEADER_SIZE = 8

    /// All GPMF data is 32-bit aligned.
    public static let ALIGNMENT = 4

    /// MP4 handler subtype identifying the GPMF metadata track.
    public static let HANDLER_SUBTYPE = "meta"

    /// MP4 sample description format for GPMF data.
    public static let SAMPLE_FORMAT = "gpmd"
}

// MARK: - FourCC Keys

/// Well-known GPMF FourCC keys.
///
/// All-uppercase keys are reserved by GoPro.
/// Mixed-case keys are available for third-party data.
public enum GPMFKey: String, Sendable, CaseIterable {

    // Structure
    case devc = "DEVC"  // Device container
    case dvid = "DVID"  // Device ID
    case dvnm = "DVNM"  // Device name
    case strm = "STRM"  // Stream container

    // Stream metadata (sticky)
    case stnm = "STNM"  // Stream name
    case rmrk = "RMRK"  // Comments
    case scal = "SCAL"  // Scale factor (divisor)
    case siun = "SIUN"  // SI units string
    case unit = "UNIT"  // Display units string
    case type = "TYPE"  // Complex structure typedef
    case tsmp = "TSMP"  // Total samples since record start
    case timo = "TIMO"  // Time offset (seconds)
    case empt = "EMPT"  // Empty payload count

    // Timing
    case tick = "TICK"  // Time in (ms)
    case tock = "TOCK"  // Time out (ms)

    // IMU sensors
    case accl = "ACCL"  // 3-axis accelerometer (m/s²)
    case gyro = "GYRO"  // 3-axis gyroscope (rad/s)
    case magn = "MAGN"  // 3-axis magnetometer (µT)

    // Orientation
    case cori = "CORI"  // Camera orientation quaternion
    case grav = "GRAV"  // Gravity vector
    case oren = "OREN"  // IMU orientation string (e.g. "U")
    case orin = "ORIN"  // IMU axis-to-camera-frame mapping (e.g. "ZXY")
    case orio = "ORIO"  // Output axis mapping

    // GPS
    case gps5 = "GPS5"  // GPS (lat, lon, alt, speed2d, speed3d)
    case gps9 = "GPS9"  // Enhanced GPS (HERO11+)
    case gpsp = "GPSP"  // GPS DOP × 100
    case gpsf = "GPSF"  // GPS fix type (0=none, 2=2D, 3=3D)
    case gpsu = "GPSU"  // GPS UTC timestamp

    // Exposure
    case isog = "ISOG"  // Image sensor gain (ISO)
    case shut = "SHUT"  // Shutter speed (seconds)

    // Camera metadata
    case wndm = "WNDM"  // Wind processing
    case tmpc = "TMPC"  // Temperature (°C)

    // Global settings
    case minf = "MINF"  // Camera model name
    case vres = "VRES"  // Video resolution
    case vfps = "VFPS"  // Video framerate
    case tzon = "TZON"  // Timezone offset (minutes)
}

// MARK: - GPMF Value Type

/// GPMF binary type descriptors.
///
/// Each case corresponds to the ASCII character used in the KLV type field.
/// All data is stored Big Endian.
public enum GPMFValueType: UInt8, Sendable {
    case nested     = 0x00  // null — nested GPMF KLV data
    case int8       = 0x62  // 'b'
    case uint8      = 0x42  // 'B'
    case char       = 0x63  // 'c'
    case double     = 0x64  // 'd'
    case float      = 0x66  // 'f'
    case fourCC     = 0x46  // 'F'
    case guid       = 0x47  // 'G'
    case int64      = 0x6A  // 'j'
    case uint64     = 0x4A  // 'J'
    case int32      = 0x6C  // 'l'
    case uint32     = 0x4C  // 'L'
    case qNumber32  = 0x71  // 'q' — Q15.16
    case qNumber64  = 0x51  // 'Q' — Q31.32
    case int16      = 0x73  // 's'
    case uint16     = 0x53  // 'S'
    case utcDate    = 0x55  // 'U' — yymmddhhmmss.sss
    case complex    = 0x3F  // '?' — structure defined by preceding TYPE

    /// Size in bytes of a single element of this type, or nil for variable-size types.
    public var elementSize: Int? {
        switch self {
        case .nested:    return nil
        case .int8:      return 1
        case .uint8:     return 1
        case .char:      return 1
        case .double:    return 8
        case .float:     return 4
        case .fourCC:    return 4
        case .guid:      return 16
        case .int64:     return 8
        case .uint64:    return 8
        case .int32:     return 4
        case .uint32:    return 4
        case .qNumber32: return 4
        case .qNumber64: return 8
        case .int16:     return 2
        case .uint16:    return 2
        case .utcDate:   return 16
        case .complex:   return nil
        }
    }
}
