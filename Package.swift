// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacSwitch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MacSwitch"),
        .testTarget(name: "MacSwitchTests", dependencies: ["MacSwitch"]),
    ]
)
