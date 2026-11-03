// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TheCursor",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TheCursor", targets: ["TheCursor"])],
    targets: [
        .target(name: "CursorCore"),
        .target(name: "CursorDesign"),
        .executableTarget(name: "TheCursor", dependencies: ["CursorCore", "CursorDesign"]),
        .testTarget(name: "CursorCoreTests", dependencies: ["CursorCore"])
    ],
    swiftLanguageModes: [.v5]
)
