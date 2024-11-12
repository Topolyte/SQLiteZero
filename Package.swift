// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SQLiteZero",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SQLiteZero",
            targets: ["SQLiteZero"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", .upToNextMajor(from: "1.1.0"))
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SQLiteZero",
            dependencies: [
                "CSQLiteZero",
               .product(name: "Collections", package: "swift-collections")]),
        .target(
            name: "CSQLiteZero",
            publicHeadersPath: "./"),
        .testTarget(
            name: "SQLiteZeroTests",
            dependencies: ["SQLiteZero"]
        ),
    ]
)
