// swift-tools-version:4.2

import PackageDescription

let package = Package(
    name: "LibTessSwift",
    targets: [
        .target(name: "LibTessSwift"),
        .testTarget(name: "LibTessSwiftTests", dependencies: ["LibTessSwift"])
    ]
)
