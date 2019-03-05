// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "LibTessSwift",
    dependencies: [
        Package.Dependency.package(url: "https://github.com/LuizZak/MiniLexer", .branch("swift5.0"))
    ],
    targets: [
        .target(name: "LibTessSwift"),
        .testTarget(name: "LibTessSwiftTests",
                    dependencies: ["LibTessSwift", "MiniLexer"])
    ]
)
