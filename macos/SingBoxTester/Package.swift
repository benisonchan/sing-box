// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SingBoxTester",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SingBoxTester", targets: ["SingBoxTester"])
    ],
    targets: [
        .executableTarget(
            name: "SingBoxTester",
            path: "Sources/SingBoxTester"
        )
    ]
)
