// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PromptRefiner",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PromptRefiner", targets: ["PromptRefiner"])],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "RefinerCore", dependencies: ["CSQLite"], resources: [.process("Resources")]),
        .executableTarget(name: "PromptRefiner", dependencies: ["RefinerCore"]),
        .testTarget(name: "RefinerCoreTests", dependencies: ["RefinerCore", "CSQLite"])
    ]
)
