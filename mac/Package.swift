// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FlowControl",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FlowControl", targets: ["FlowControl"]),
    ],
    targets: [
        .executableTarget(
            name: "FlowControl",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
            ]
        ),
        .testTarget(
            name: "FlowControlTests",
            dependencies: ["FlowControl"]
        ),
    ]
)
