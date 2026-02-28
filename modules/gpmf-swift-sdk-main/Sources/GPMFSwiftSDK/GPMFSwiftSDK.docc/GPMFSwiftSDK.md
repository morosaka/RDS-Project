# ``GPMFSwiftSDK``

Parse GoPro GPMF telemetry from MP4 files. Extract IMU, GPS, temperature, and orientation
data as typed, time-aligned Swift value types.

## Overview

GPMFSwiftSDK is a pure-Swift, Foundation-only library for decoding GoPro's
General Purpose Metadata Format (GPMF) from MP4 files.

### Key Features

- **Single-file extraction** — parse one MP4 into typed ``TelemetryData``
- **Chapter stitching** — transparently merge split recordings into one unified timeline
- **Session grouping** — organize mixed-bag directories into sorted ``SessionGroup`` arrays
- **ORIN axis remapping** — all IMU data delivered in the GPMF Camera Frame
- **GPS timestamp hardening** — exposes first *and* last GPS observations with relative
  file positions for back-computing a reliable absolute start time
- **Stream filtering** — extract only the sensors you need via ``StreamFilter``
- **TimestampedReading protocol** — generic time-range queries on any reading array
- **Zero dependencies** — Foundation only, no external packages

### Supported Sensors

| Stream | Type | Typical Rate |
|--------|------|-------------|
| ACCL | ``SensorReading`` | 200 Hz |
| GYRO | ``SensorReading`` | 200 Hz |
| GPS5/GPS9 | ``GpsReading`` | 10 Hz |
| CORI | ``OrientationReading`` | 60 Hz |
| GRAV | ``SensorReading`` | 60 Hz |
| TMPC | ``TemperatureReading`` | 2 Hz |
| MAGN | ``SensorReading`` | varies |

### Platforms

macOS 13+, iOS 15+, Swift 6.0 (language modes v5 and v6)

## Topics

### Extraction

- ``GPMFExtractor``
- ``ChapterStitcher``
- ``SessionGrouper``

### Output Models

- ``TelemetryData``
- ``StreamInfo``
- ``SensorReading``
- ``GpsReading``
- ``OrientationReading``
- ``TemperatureReading``
- ``ExposureReading``

### Absolute Timestamps

- ``GPSTimestampObservation``
- ``GPS9Timestamp``

### Time-Based Querying

- ``TimestampedReading``
- ``StreamFilter``

### Low-Level Decoding

- ``GPMFDecoder``
- ``GpmfNode``
- ``GPMFKey``
- ``GPMFValueType``
- ``ORINMapper``
- ``GPMFError``
