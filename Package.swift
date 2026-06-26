// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HandyTabSwift",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "HandyTabSwift", targets: ["HandyTabSwift"])
    ],
    targets: [
        .executableTarget(
            name: "HandyTabSwift",
            linkerSettings: [
                .unsafeFlags(["-F/System/Library/PrivateFrameworks"]),
                .linkedFramework("MultitouchSupport"),
            ]
        )
    ]
)
