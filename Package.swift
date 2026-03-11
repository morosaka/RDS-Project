// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RowDataStudio",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "RowDataStudio",
            targets: ["RowDataStudio"]
        ),
    ],
    dependencies: [
        .package(path: "modules/gpmf-swift-sdk-main"),
        .package(path: "modules/fit-swift-sdk-main"),
        .package(path: "modules/csv-swift-sdk-main"),
    ],
    targets: [
        // Library target: all app logic (models, services, signal processing, rendering)
        // This is the testable core — everything except the @main entry point.
        .target(
            name: "RowDataStudio",
            dependencies: [
                .product(name: "GPMFSwiftSDK", package: "gpmf-swift-sdk-main"),
                .product(name: "FITSwiftSDK", package: "fit-swift-sdk-main"),
                .product(name: "CSVSwiftSDK", package: "csv-swift-sdk-main"),
            ],
            path: "Sources/RowDataStudio"
        ),

        // Test target: unit + integration tests for app logic
        .testTarget(
            name: "RowDataStudioTests",
            dependencies: ["RowDataStudio"],
            path: "Tests/RowDataStudioTests"
        ),
    ],
    swiftLanguageModes: [.v5, .v6]
)
