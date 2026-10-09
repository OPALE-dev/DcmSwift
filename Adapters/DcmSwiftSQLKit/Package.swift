// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "DcmSwiftSQLKit",
    platforms: [.macOS(.v10_15), .iOS(.v13)],
    products: [.library(name: "DcmSwiftSQLKit", targets: ["DcmSwiftSQLKit"])],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/vapor/sql-kit.git", from: "3.0.0"),
        .package(url: "https://github.com/vapor/sqlite-kit.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor/postgres-kit.git", from: "2.0.0"),
        .package(url: "https://github.com/vapor/mysql-kit.git", from: "4.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"6.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.103.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    ],
    targets: [
        .target(name: "DcmSwiftSQLKit", dependencies: [
            .product(name: "DcmSwift", package: "DcmSwift"),
            .product(name: "SQLKit", package: "sql-kit"),
            .product(name: "Crypto", package: "swift-crypto"),
        ]),
        .testTarget(name: "DcmSwiftSQLKitTests", dependencies: [
            "DcmSwiftSQLKit", .product(name: "DcmSwiftArchiveConformance", package: "DcmSwift"),
            .product(name: "SQLiteKit", package: "sqlite-kit"),
            .product(name: "PostgresKit", package: "postgres-kit"),
            .product(name: "MySQLKit", package: "mysql-kit"),
            .product(name: "NIOPosix", package: "swift-nio"),
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "Logging", package: "swift-log"),
        ]),
    ]
)
