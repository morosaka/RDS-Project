// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CSVSwiftSDK",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "CSVSwiftSDK",
            targets: ["CSVSwiftSDK"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CSVSwiftSDK",
            dependencies: [],
            resources: [
                .process("Resources/PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: "CSVSwiftSDKTests",
            dependencies: ["CSVSwiftSDK"],
            resources: [
                .copy("TestData")
            ]
        ),
    ]
)
