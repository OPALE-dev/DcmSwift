// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DcmSwift",
    platforms: [
        .macOS(.v10_15)
    ],
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
        .executable(name: "DcmFind", targets: ["DcmFind"]),
        .executable(name: "DcmSR", targets: ["DcmSR"]),
        .executable(name: "DcmIzer", targets: ["DcmIzer"])
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/Kitura/BlueSocket.git", from: "2.0.2"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
        .package(url: "https://github.com/pointfreeco/swift-html", from: "0.5.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.103.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        
        .systemLibrary(
            name: "CZlib",
            providers: [
                .brew(["zlib"]),
                .apt(["zlib1g-dev"])
            ]),
        .target(
            name: "DcmSwift",
            dependencies: [
                "CZlib",
                .product(name: "Socket", package: "BlueSocket"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "Html", package: "swift-html")
            ],
            resources: [
                .process("Resources/dicom-dictionary-2026d.json")
            ]),
        .executableTarget(
            name: "DcmAnonymize",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .executableTarget(
            name: "DcmPrint",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .executableTarget(
            name: "DcmSR",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .executableTarget(
            name: "DcmServer",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .executableTarget(
            name: "DcmEcho",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .executableTarget(
            name: "DcmStore",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .executableTarget(
            name: "DcmFind",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .executableTarget(
            name: "DcmIzer",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .testTarget(
            name: "DcmSwiftTests",
            dependencies: ["DcmSwift"],
            resources: [
                .process("Resources/DICOM"),
                .process("Resources/DICOMDIR"),
                .process("Resources/SR"),
                .process("Resources/RT"),
            ]
        )
    ]
)
