// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "DcmSwiftSQLite",
    platforms: [.macOS(.v10_15), .iOS(.v13)],
    products: [.library(name: "DcmSwiftSQLite", targets: ["DcmSwiftSQLite"])],
    dependencies: [.package(path: "../..")],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3", providers: [
            .brew(["sqlite"]), .apt(["libsqlite3-dev"]),
        ]),
        .target(name: "DcmSwiftSQLite", dependencies: ["CSQLite", .product(name: "DcmSwift", package: "DcmSwift")]),
        .testTarget(name: "DcmSwiftSQLiteTests", dependencies: [
            "DcmSwiftSQLite", .product(name: "DcmSwiftArchiveConformance", package: "DcmSwift"),
        ]),
    ]
)
