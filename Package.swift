// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HandyTab",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "HandyTab", targets: ["HandyTab"])
    ],
    targets: [
        .executableTarget(
            name: "HandyTab",
            linkerSettings: [
                .unsafeFlags(["-F/System/Library/PrivateFrameworks"]),
                .linkedFramework("MultitouchSupport"),
            ]
        )
    ]
)
