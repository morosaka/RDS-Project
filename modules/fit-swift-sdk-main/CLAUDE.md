# FITSwiftSDK -- CLAUDE.md

## Overview

Swift Package for parsing and encoding Garmin FIT (Flexible and Interoperable Data Transfer) binary protocol files. Port of the official Garmin FIT SDK to Swift.

**Scope:** FIT file decoding/encoding, message broadcasting, field interpretation.
Cross-device temporal alignment is the consuming application's responsibility.

## Build & Test

```bash
swift build
swift test              # 248 tests (mixed XCTest + Swift Testing)

# If swift test fails with "no such module 'XCTest'":
sudo xcode-select -s /Volumes/WDSN770/Applications/Xcode.app/Contents/Developer
```

**Platforms:** macOS 12+, iOS 14+
**Swift:** 6.0 (language modes v5 and v6)
**Dependencies:** swift-collections 1.2.0+ (Apple)

## Architecture

```
Sources/FITSwiftSDK/
├── Decoder.swift              Binary FIT decoder (main entry point)
├── Encoder.swift              Binary FIT encoder
├── FileHeader.swift           FIT file header parsing/writing
├── CrcCalculator.swift        CRC validation
├── InputStream.swift          Binary cursor (Little Endian)
├── FitMessages.swift          Container for 80+ typed message arrays
├── FIT.swift                  Constants, profile version (21.194.0)
├── Mesg.swift                 Generic message container
├── MesgDefinition.swift       Runtime message structure definitions
├── Field.swift                Field value access
├── FieldBase.swift            Base field with type/offset info
├── FieldDefinition.swift      Field layout in message
├── FieldComponent.swift       Sub-field component extraction
├── Field+Additions.swift      Convenience accessors
├── SubField.swift             Dynamic sub-field resolution
├── BaseType.swift             FIT base type enum (enum/sint8/.../string)
├── MesgBroadcaster.swift      Observer pattern for message dispatch
├── BufferedMesgBroadcaster.swift  Buffered variant
├── MesgBroadcastPlugin.swift  Plugin interface
├── FitListener.swift          Convenience listener (collects all messages)
├── HrMesgUtil.swift           Heart rate message utilities
├── Accumulator.swift          Compressed timestamp accumulation
├── BitStream.swift            Bit-level reading for compressed fields
├── DeveloperField.swift       Developer data extension fields
├── DeveloperFieldDefinition.swift
├── DeveloperFieldDescription.swift
├── DeveloperFieldDescriptionListener.swift
├── DeveloperDataKey.swift     Key for developer field lookup
├── DeveloperDataLookup.swift  Registry for developer fields
├── Array+Additions.swift      Array utilities
├── ArraySlice+Additions.swift
├── Numeric+Additions.swift    Numeric type helpers
├── MesgFilter.swift           Message filtering
├── MesgListener.swift         Protocol: onMesg(_:)
├── MesgDefinitionListener.swift  Protocol: onMesgDefinition(_:)
├── MesgSource.swift           Protocol: message source
├── MesgDefinitionSource.swift Protocol: definition source
└── Profile/                   Auto-generated FIT profile types (80+ message types)
```

## Key Public API

```swift
// Decoding
public class Decoder: MesgSource, MesgDefinitionSource {
    public init(stream: InputStream)
    public func decode(mode: DecodeMode = .normal) throws -> FitMessages
    public class func isFIT(stream: InputStream) throws -> Bool
    public class func checkIntegrity(stream: InputStream) throws -> Bool
}

// Message container (80+ typed arrays)
public class FitMessages {
    public var fileIdMesgs: [FileIdMesg]
    public var sessionMesgs: [SessionMesg]
    public var lapMesgs: [LapMesg]
    public var recordMesgs: [RecordMesg]
    // ... 80+ more
}

// Observer pattern
public protocol MesgListener: AnyObject {
    func onMesg(_ mesg: Mesg)
}
```

## Testing

**Framework:** Mixed XCTest (legacy, 19 files) + Swift Testing (9 files)
**Total tests:** 248 across 28 test files
**Test data:** Binary fixtures in `TestData/` (hardcoded Data arrays + .fit files)

Test categories:
- **Core parsers:** Decoder, Encoder, FileHeader, CRC
- **Binary utilities:** BitStream, InputStream, ArrayExtensions
- **Message handling:** Mesg, MesgDefinition, MesgBroadcaster, FitListener
- **Field handling:** Field, SubField, BaseType
- **Developer data:** DeveloperField, DeveloperFieldDescription, DeveloperDataLookup
- **Integration:** Full encode/decode roundtrip, real .fit file parsing
- **Examples:** Activity encoding, re-encoding, listener patterns

## Origin & License

Port of the **Garmin FIT SDK** (Profile Version 21.194.0). All source files carry Garmin
copyright headers and are auto-generated from the FIT profile. See LICENSE.txt.

**Important:** Do not modify auto-generated files. Changes to the FIT profile should be
regenerated from the Garmin SDK tools.

## Known Constraints

- FIT files from NK SpeedCoach **DO NOT** contain NK Empower Oarlock data (CSV only)
- Garmin epoch offset: **631065600 seconds** from Unix epoch (Dec 31 1989 00:00:00 UTC)
- FIT timestamps from Garmin devices are NTP/GPS-synced (medium-high reliability)
- NK SpeedCoach timestamp reliability varies (no NTP, GPS-derived)
- FIT semicircle coordinates: `degrees = semicircles * (180.0 / 2^31)`
