# SQLiteZero

SQLiteZero is a zero fuss SQLite wrapper for Swift.

## Installation

### Swift Package Manager

```
let package = Package(
    // name, platforms, products, etc.
    dependencies: [
        .package(url: "https://github.com/Topolyte/SQLiteZero.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(name: "<your target>", dependencies: [
            .product(name: "SQLiteZero", package: "SQLiteZero"),
        ])
    ]
)
```
If you want to use the latest SQLite source code,
your best option is to clone this git repository to your local disk
and copy the latest sqlite3.c and sqlite3.h into the
SQLiteZero/Sources/CSQLite directory (overwriting the existing files).

You can then replace the reference to github with the path to the local package
in your Package.swift file:

```
...
    dependencies: [
        .package(path: "../SQLiteZero")
    ],
...
```

## Usage


