import Foundation
import Testing
@testable import SQLiteZero

@Test func example() throws {
    
    let path = ":memory:" //or "/path/to/database.sqlite"
    
    //Open or create a database at path with the default options
    let db = try SQLite(path)

    //Execute one or more statements
    try db.execute("""
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
        (3, 'Ada', 1.63, true, cast('{"note": "expecting call"}' as blob))
    """)
    
    let sql = "select * from person where height > ?"
    
    // Prepare, execute and then iterate over the results of a one-off statement:

    for row in try db.execute(sql, 1.65) {
        //...
    }
    
    // Note that any errors that occur while fetching further records after the first one
    // are not thrown because Swift's IteratorProtocol is non-throwing.
    // This is relatively rare because most erorrs occur when the statement is prepared
    // or when arguments are bound to host variables. But it can happen e.g. if the
    // database is locked by another process or if concurrent schema changes are made.
    // If this is a possibility in your code, you can use a slightly more convoluted way of
    // iterating over query results:
    
    let statement = try db.execute(sql, 1.65)
    while let row = try statement.nextRow() {
        //...
    }

    // This is how you execute a statement repeatedly with different parameters:
    
    let prepared = try db.prepare(sql)
    for height in [1.50, 1.60, 1.70] {
        try prepared.execute(height)
        while let row = try prepared.nextRow() {
            //...
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
        
    // Similarly, values can be retrieved from rows by position or by name:
    
    for row in try db.execute("select * from person") {
        let id: Int64 = row[0]!
        let name: String = row["name"]!
        let height: Double = row["height"]!
        let isFriend: Bool = row["is_friend"]!
        
        if let note: Data = row["note"] {
            let jsonObject = try JSONSerialization.jsonObject(with: note)
        }
    }
    
    // The subscript operator [] will try to convert the returned value to the requested type,
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
    
}
