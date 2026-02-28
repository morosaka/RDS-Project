# RowData Studio

RowData Studio is a native Apple tool (macOS + iPadOS + iOS) for deep analysis of rowing sessions. It integrates video tracks, GPMF telemetry data from GoPro, and biometric/instrumental data from FIT files (NK SpeedCoach, Garmin, Apple Watch).

## Features

- **Multi-track Timeline**: Independent tracks for video, audio, acceleration, gyroscope, GPS, HR, and cadence.
- **Infinite Canvas ("Rowing Desk")**: A flexible environment for positioning widgets (video, charts, map, metrics).
- **Synchronized Playhead**: All widgets react to a single temporal source of truth.
- **Fusion Engine**: High-performance IMU and GPS data fusion for precise metric derivation.
- **Stroke Detection**: Automated segmentation of rowing strokes with per-stroke analytics.

## Project Structure

- `docs/`: Design documentation, vision reports, and architectural proposals.
- `modules/`:
  - `gpmf-swift-sdk-main`: Swift SDK for extracting and processing GoPro GPMF telemetry.
  - `fit-swift-sdk-main`: Swift SDK for parsing Garmin/Garmin-compatible FIT files.

## Technology Stack

- **Platform**: Native Apple (Swift, SwiftUI, UIKit/AppKit)
- **Frameworks**: AVFoundation, Metal, Accelerate (vDSP)
- **Architecture**: Structure of Arrays (SoA) for telemetry data, Composable Transform Pipelines for visualization.

## Author

morosaka

---
*This repository contains the core SDKs and documentation for the RowData Studio project.*
