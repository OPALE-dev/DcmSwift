// swift-tools-version:6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DcmSwift",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13)
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
        .executable(name: "DcmIzer", targets: ["DcmIzer"]),
        .executable(name: "DcmConvert", targets: ["DcmConvert"]),
        .executable(name: "DcmValidate", targets: ["DcmValidate"]),
        .executable(name: "DcmSign", targets: ["DcmSign"]),
        .executable(name: "DcmDocument", targets: ["DcmDocument"])
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
        .package(url: "https://github.com/pointfreeco/swift-html", from: "0.5.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.103.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.29.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"6.0.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.0.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.36.2"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.5.0")
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
        // OpenJPEG 2.5.4, vendored unchanged (see Sources/COpenJPEG/README.DcmSwift.md).
        .target(
            name: "COpenJPEG",
            exclude: ["LICENSE", "README.DcmSwift.md"],
            cSettings: [
                // OPJ_STATIC would give the API hidden visibility, which breaks
                // Xcode builds that link the target separately.
                .define("MUTEX_pthread")
            ],
            linkerSettings: [
                .linkedLibrary("m", .when(platforms: [.linux])),
                .linkedLibrary("pthread", .when(platforms: [.linux]))
            ]),
        // OpenJPH 0.32.0, generic (non-SIMD) sources vendored unchanged, behind a
        // C interface (see Sources/COpenJPH/README.DcmSwift.md).
        .target(
            name: "COpenJPH",
            exclude: ["LICENSE", "README.DcmSwift.md"],
            cxxSettings: [
                .define("OJPH_DISABLE_SIMD"),
                .headerSearchPath("openjph/src/core/openjph"),
                .headerSearchPath("openjph/src/core/codestream"),
                .headerSearchPath("openjph/src/core/coding"),
                .headerSearchPath("openjph/src/core/transform"),
                .headerSearchPath("openjph/src/core/others")
            ],
            linkerSettings: [
                .linkedLibrary("m", .when(platforms: [.linux]))
            ]),
        // libjxl 0.12.0 decoder and encoder with the Highway runtime, Brotli
        // encoder, and skcms they pin, vendored as source (see
        // Sources/CJPEGXL/README.DcmSwift.md).
        .target(
            name: "CJPEGXL",
            exclude: [
                "LICENSE", "README.DcmSwift.md", "third_party/brotli/LICENSE", "third_party/highway/LICENSE",
                "third_party/skcms/LICENSE"
            ],
            cSettings: [
                .headerSearchPath("third_party/brotli/c/include")
            ],
            cxxSettings: [
                .define("JXL_INTERNAL_LIBRARY_BUILD"),
                .define("JXL_STATIC_DEFINE"),
                // JPEG recompression (.111) in both directions.
                .define("JPEGXL_ENABLE_TRANSCODE_JPEG", to: "1"),
                .define("JPEGXL_ENABLE_BOXES", to: "0"),
                // skcms as the color management system, without the AVX2 and
                // AVX-512 paths, which need per-file compiler flags.
                .define("JPEGXL_ENABLE_SKCMS", to: "1"),
                .define("SKCMS_DISABLE_HSW"),
                .define("SKCMS_DISABLE_SKX"),
                .headerSearchPath("."),
                .headerSearchPath("lib"),
                .headerSearchPath("lib/include"),
                .headerSearchPath("third_party/highway"),
                .headerSearchPath("third_party/brotli/c/include"),
                .headerSearchPath("third_party/skcms")
            ],
            linkerSettings: [
                .linkedLibrary("m", .when(platforms: [.linux])),
                .linkedLibrary("pthread", .when(platforms: [.linux]))
            ]),
        .target(
            name: "DcmSwift",
            dependencies: [
                "CZlib",
                "COpenJPEG",
                "COpenJPH",
                "CJPEGXL",
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "Html", package: "swift-html")
            ],
            resources: [
                .process("Resources/dicom-dictionary-2026d.json"),
                .process("Resources/dicom-command-dictionary-2026d.json"),
                .process("Resources/dicom-terminology-2026d.json"),
                .process("Resources/dicom-iods-2026d.json"),
                .process("Resources/dicom-deidentification-2026d.json"),
                .copy("Resources/CharacterSets")
            ]),
        .executableTarget(
            name: "DcmAnonymize",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            exclude: ["README.md"]),
        .executableTarget(
            name: "DcmPrint",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            exclude: ["README.md"]),
        .executableTarget(
            name: "DcmSR",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            exclude: ["README.md"]),
        // Options shared by the network tools; not a product.
        .target(
            name: "DcmNetworkCommand",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl")
            ]),
        .executableTarget(
            name: "DcmServer",
            dependencies: [
                "DcmSwift",
                "DcmNetworkCommand",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            exclude: ["README.md"]),
        .executableTarget(
            name: "DcmEcho",
            dependencies: [
                "DcmSwift",
                "DcmNetworkCommand",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            exclude: ["README.md"]),
        .executableTarget(
            name: "DcmStore",
            dependencies: [
                "DcmSwift",
                "DcmNetworkCommand",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            exclude: ["README.md"]),
        .executableTarget(
            name: "DcmFind",
            dependencies: [
                "DcmSwift",
                "DcmNetworkCommand",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            exclude: ["README.md"]),
        .executableTarget(
            name: "DcmIzer",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            exclude: ["README.md"]),
        .executableTarget(
            name: "DcmConvert",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            exclude: ["README.md"]),
        .executableTarget(
            name: "DcmValidate",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            exclude: ["README.md"]),
        .executableTarget(
            name: "DcmSign",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            exclude: ["README.md"]),
        .executableTarget(
            name: "DcmDocument",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            exclude: ["README.md"]),
        .testTarget(
            name: "DcmSwiftTests",
            dependencies: [
                "DcmSwift", "CZlib",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
            ],
            exclude: ["Resources"],
            resources: [.process("CIResources")]
        )
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx17
)
