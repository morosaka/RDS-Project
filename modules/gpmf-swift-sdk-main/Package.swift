// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GPMFSwiftSDK",
    platforms: [
        .macOS(.v13),
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "GPMFSwiftSDK",
            targets: ["GPMFSwiftSDK"]
        ),
    ],
    targets: [
        .target(
            name: "GPMFSwiftSDK"
        ),
        .testTarget(
            name: "GPMFSwiftSDKTests",
            dependencies: ["GPMFSwiftSDK"],
            exclude: ["TestData"]
        ),
    ],
    swiftLanguageModes: [.v5, .v6]
)
