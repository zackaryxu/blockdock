// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BlockDock",
    platforms: [.macOS(.v13)],
    products: [.library(name: "BlockDockCore", targets: ["BlockDockCore"])],
    targets: [
        .target(name: "BlockDockCore"),
        .executableTarget(name: "BlockDock", dependencies: ["BlockDockCore"]),
        .testTarget(name: "BlockDockCoreTests", dependencies: ["BlockDockCore"])
    ]
)
