// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "LibTessSwift",
    dependencies: [
        Package.Dependency.package(url: "https://github.com/LuizZak/MiniLexer", .exact("0.9.5"))
    ],
    targets: [
        .target(name: "LibTessSwift"),
        .testTarget(name: "LibTessSwiftTests",
                    dependencies: ["LibTessSwift", "MiniLexer"])
    ]
)
