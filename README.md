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
your best option is to clone this git repository to your local drive
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

```
func example() throws {
    
    let path = ":memory:" //or "/path/to/database.sqlite"
    
    //Open or create a database at path with the default options
    let db = try SQLite(path)

    //Execute one or more statements
    try db.execute("""
        create table person (
            id integer primary key,
            name text not null,
            height real,
            is_friend bool not null default false,
            meta blob
        );
    
        insert into person (id, name, height, is_friend, meta) values
        (1, 'Noa', 1.77, true, cast('{"lastSeen": "2024-11-05"}' as blob)),
        (2, 'Mia', 1.66, false, null),
        (3, 'Ada', 1.63, true, cast('{"note": "expecting call"}' as blob))
    """)
    
    let sql = "select * from person where height > ?"
    
    // If you expect the query to return a small number of records,
    // you can load them all into an array and loop over them.
    // Unfortunately, the Swift IteratorProtocol's next() method is non-throwing,
    // which is why you can't use a for-in loop directly on the statement returned
    // by the execute() call.

    for row in try db.execute(sql, 1.65).all() {
        //...
    }

    // If you expect a large number of records and don't want to load them all into memory
    // you have to use the throwing next() method.

    while let row = try db.execute(sql, 1.65).next() {
        //...
    }
    
    //If you only need the first row and you are certain that at least one row will be returned
    //you can use first(). If the query doesn't return any rows an exception will be thrown.

    let row = try db.execute(sql, 1.65).first()
    
    
}

```
