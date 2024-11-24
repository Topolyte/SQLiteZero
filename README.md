# SQLiteZero

SQLiteZero is a zero fuss SQLite wrapper for Swift.

This package statically compiles SQLite. It comes with a reasonably up-to-date version of SQLite,
but you can also bring your own.

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
To use your own version of SQLite, clone this repository locally,
copy your downloaded sqlite3.c and sqlite3.h files into SQLiteZero/Sources/CSQLite 
and update the dependencies in your Package.swift to refer to your local path:

```
...
    dependencies: [
        .package(path: "../SQLiteZero")
    ],
...
```

## Usage

```
import Foundation
import Testing
import SQLiteZero

@Test func example() throws {
    
    let path = ":memory:" //or "/path/to/database.sqlite"
    
    //Open or create a database at path with the default options
    let db = try SQLite(path)

    //Use executeScript to execute more than one statement. Scripts don't take any arguments.
    try db.executeScript("""
        create table person (
            id integer primary key,
            name text not null,
            height real not null,
            is_friend bool not null default false,
            meta blob
        );
    
        insert into person (id, name, height, is_friend, meta) values
        (1, 'Noa', 1.77, true, cast('{"lastSeen": "2024-11-05"}' as blob)),
        (2, 'Mia', 1.66, false, null),
        (3, 'Ada', 1.63, true, cast('{"lastSeen": "2024-10-16"}' as blob))
    """)
    
    let sql = "select * from person where height > ? order by name"
    
    // Prepare, execute and then iterate over the results of a one-off statement:

    for row in try db.execute(sql, 1.65) {
        #expect(["Noa", "Mia"].contains(row["name"]))
    }
    
    // Note that any errors that occur while fetching further records after the first one
    // are not thrown when using for-in because Swift's IteratorProtocol is non-throwing.
    // This is relatively rare because most erorrs occur when the statement is prepared
    // or when any arguments are bound to host variables. But it can happen e.g. if the
    // database is locked by another process or if concurrent schema changes are made.
    // If this is a possibility in your code, you can use a slightly more convoluted way of
    // iterating over query results:
    
    let statement = try db.execute(sql, 1.65)
    while let row = try statement.nextRow() {
        #expect(["Noa", "Mia"].contains(row["name"]))
    }
    
    // The most convenient way to ensure that all errors are handled is to load all rows
    // into an array. This is of course not ideal if the query returns a large number of rows:
    
    let allRows = try db.execute(sql, 1.65).all()
    #expect(allRows.count == 2)
    
    // Require that exactly one row is returned or else raise an exception:
    
    #expect (try db.execute("select 1 + 1").one()[0] == 2)

    // This is how you execute a statement repeatedly with different parameters:
    
    let prepared = try db.prepare(sql)
    for height in [1.50, 1.60, 1.70] {
        try prepared.execute(height)
        while let row = try prepared.nextRow() {
            #expect(row["height"]! > height)
        }
    }
    
    // Parameters can be provided by name or by position.
    // Using the name prefix character in your dictionary is optional
    // but recommended because it's slightly faster.
    
    try db.execute("""
        insert into person(id, name, height) values
        ($id, $name, $height)
    """,
    ["$id": 4, "$name": "Xan", "$height": 1.78])
        
    // Similarly, values can be retrieved from rows by position or by name.
    // Column values are accessed using the subscript operator [].
    // The operator will try to convert the returned value to the requested type,
    // i.e. the type that is implied by the context. If the context is ambiguous,
    // use a type cast for disambiguation. E.g. let h = row["height"]! as Double
    //
    // If the column is NULL or the conversion fails, nil is returned.
    // SQLite supports only five types natively: null, integer, real, text and blob.
    // These types are mapped to the following Swift types (supported conversions in brackets)
    //
    // null : nil
    // integer : Int64 [Int, Bool, Double, String]
    // real : Double [Int, Int64, String, Bool]
    // text : String [Data, Int, Int64, Double, Bool]
    // blob : Data [String]
    //
    // Note that conversions will fail and return nil if the value isn't exactly representable
    // as the requested type. So converting real to Int will only work if the real value
    // doesn't have any decimal places.
    //
    // Converting blob to String only succeeds if the blob value can be decoded as UTF-8.
    //
    // Converting text to Bool returns true/false if the text value is "true"/"false"
    // The comparison is case insensitive. Any other value will result in nil being returned
    //
    // If you want to be absolutely certain whether or not a column is NULL,
    // you should use the correct native type that doesn't require conversion or use row.isNull()
    //

    for row in try db.execute("select * from person") {
        let id: Int64 = row[0]!
        let idStr = row[0]! as String
        #expect(id == Int64(idStr))
        
        let name: String = row["name"]!
        let nameData = row["name"]! as Data
        #expect(name == String(data: nameData, encoding: .utf8))
        
        let heightInt = row["height"] as Int?
        // because none of our example heights is exactly representable as Int:
        #expect(heightInt == nil)
        
        let isFriend: Bool = row["is_friend"]!
        #expect(["Ada", "Noa"].contains(row["name"]) ? isFriend : !isFriend)
        
        if let note: Data = row["note"] {
            if let dict = try JSONSerialization.jsonObject(with: note) as? [String: Any?] {
                #expect(dict["lastSeen"] != nil)
            } else {
                throw Err.unexpected("Expected a Dictionary<String, Any>")
            }
            
            #expect((row["note"]! as String).hasPrefix(#"{"lastSeen":"#))
        }
    }
    
    // A transaction is committed when the closure passed to the transaction() method completes
    // without throwing an exception. If an exception occurs, the transaction is rolled back.
    // Transactions can be nested. The inner transactions use savepoints and are
    // therefore not durable unless the outermost transaction is committed as well:
    
    let insert = try db.prepare("insert into person (id, name, height) values (?, ?, 1.68)")
    let countName = try db.prepare("select count(*) from person where name = ?")
    
    try db.transaction {
        try insert.execute(5, "Liv")
        #expect(try countName.execute("Liv").one()[0] == 1)
        
        #expect(throws: Err.self) {
            try db.transaction {
                try insert.execute(6, "Ari")
                #expect(try countName.execute("Ari").one()[0] == 1)
                throw Err.testing("Oh no!")
            }
        }
        
        #expect(try countName.execute("Ari").one()[0] == 0)
    }
    #expect(try countName.execute("Liv").one()[0] == 1)
    
    // To make a backup open the source and destination databases and make sure
    // that there is no other connection to the destination database.
    // Then call the backup() method on the source database passing the destination database
    // as a parameter.
    //
    // The second parameter to backup() is an optional callback function that is called
    // once every SQLite.backupBatchSize pages to indicate progress or if retries were necessary
    // because either the source or destination database is temporarily locked.
    // The callback function receives the number of bytes remaining, the total number of bytes
    // in the source database and the number of retries.
    //
    // If the callback function returns false, the backup is aborted.
    
    let source = try SQLite()
    try source.executeScript("""
        create table backup_test (
            id integer primary key,
            data text
        );
    
        insert into backup_test(id, data) values
        (1, 'abc'),
        (2, 'xyz');    
    """)
    
    let destinationPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("backup.db")
        .path(percentEncoded: false)
    
    let destination = try SQLite(destinationPath)
    let maxRetries = 10
    
    try source.backup(to: destination) { remaining, total, retries in
        if retries > maxRetries {
            return false
        }
        return true
    }
    
    #expect(try destination.execute("select count(*) from backup_test").one()[0] == 2)
}

enum Err: Error {
    case unexpected(String)
    case testing(String)
}


```
