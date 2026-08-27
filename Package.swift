// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SFCall",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SFCallCore", targets: ["SFCallCore"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "SFCallCore", dependencies: ["CSQLite"]),
        .testTarget(name: "SFCallCoreTests", dependencies: ["SFCallCore"])
    ]
)
