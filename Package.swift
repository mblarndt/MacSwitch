// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacSwitch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MacSwitch"),
        // Die Logik der iPhone-App (Funkprotokoll, Layout, Touch → Zustand); die App kompiliert dieselben Dateien (iPhoneController/project.yml).
        .target(name: "PadLogic", path: "iPhoneController/Logic"),
        .testTarget(name: "MacSwitchTests", dependencies: ["MacSwitch", "PadLogic"]),
    ]
)
