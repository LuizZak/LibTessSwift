// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "LibTessSwift",
    dependencies: [
        Package.Dependency.package(url: "https://github.com/LuizZak/MiniLexer", from: "0.7.2")
    ],
    targets: [
        .target(name: "LibTessSwift"),
        .testTarget(name: "LibTessSwiftTests",
                    dependencies: ["LibTessSwift", "MiniLexer"])
    ]
)
