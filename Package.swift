// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "LibTessSwift",
    products: [
        .library(
            name: "LibTessSwift",
            targets: ["LibTessSwift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/LuizZak/MiniLexer.git", .exact("0.9.5")),
    ],
    targets: [
        .target(
            name: "libtess2",
            dependencies: []),
        .target(
            name: "LibTessSwift",
            dependencies: ["libtess2"]),
        .testTarget(
            name: "LibTessSwiftTests",
            dependencies: ["LibTessSwift", "MiniLexer"]),
    ]
)
