// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DcmSwift",
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "DcmSwift",
            targets: ["DcmSwift"]),
        .executable(name: "DcmAnonymize", targets: ["DcmAnonymize"]),
        .executable(name: "DcmPrint", targets: ["DcmPrint"]),
        .executable(name: "DcmServer", targets: ["DcmServer"]),
        .executable(name: "DcmEcho", targets: ["DcmEcho"]),
        .executable(name: "DcmStore", targets: ["DcmStore"]),
        .executable(name: "DcmSR", targets: ["DcmSR"])
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(name: "Socket", url: "https://github.com/Kitura/BlueSocket.git", from:"1.0.8"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.4.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        
        .target(
            name: "DcmSwift",
            dependencies: [ "Socket" ]),
        .target(
            name: "DcmAnonymize",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .target(
            name: "DcmPrint",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .target(
            name: "DcmSR",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .target(
            name: "DcmServer",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .target(
            name: "DcmEcho",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .target(
            name: "DcmStore",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .testTarget(
            name: "DcmSwiftTests",
            dependencies: ["DcmSwift"],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
