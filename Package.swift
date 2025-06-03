// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "raytrace",
    platforms: [
        .macOS(.v15)  // Specify minimum macOS version requirement
    ],
    targets: [
        .executableTarget(
            name: "raytrace",
            path: "Sources"
        )
    ]
)