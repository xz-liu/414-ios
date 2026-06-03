// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FourFourteen",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "FourFourteenCore",
            targets: ["FourFourteenCore"]
        )
    ],
    targets: [
        .target(
            name: "FourFourteenCore"
        ),
        .testTarget(
            name: "FourFourteenCoreTests",
            dependencies: ["FourFourteenCore"]
        )
    ]
)
