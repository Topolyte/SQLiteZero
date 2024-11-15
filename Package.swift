// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SQLiteZero",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(
            name: "SQLiteZero",
            targets: ["SQLiteZero"]),
    ],
    targets: [
        .target(
            name: "SQLiteZero",
            dependencies: ["CSQLite"]),
        .target(
            name: "CSQLite",
            publicHeadersPath: "./",
            cSettings: [.unsafeFlags(["-Wno-everything"])]),
        .testTarget(
            name: "SQLiteZeroTests",
            dependencies: ["SQLiteZero"]
        ),
    ]
)
