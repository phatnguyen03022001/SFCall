// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SFCall",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SFCallCore", targets: ["SFCallCore"]),
        .library(name: "SFCallMac", targets: ["SFCallMac"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "SFCallCore", dependencies: ["CSQLite"]),
        .target(name: "SFCallMac", dependencies: ["SFCallCore"]),
        .testTarget(name: "SFCallCoreTests", dependencies: ["SFCallCore"]),
        .testTarget(name: "SFCallMacTests", dependencies: ["SFCallMac"])
    ]
)
