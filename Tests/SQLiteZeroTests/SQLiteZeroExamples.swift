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
    
    // If you expect the query to return a small number of records,
    // you can load them all into an array and loop over them:

    let rows = try db.execute(sql, 1.65).all()

    // If you expect a large number of records and don't want to load them all into memory
    // you can use for-in to loop over the statement returned by execute.
    // Unfortunately there is throwin version of Swift's IteratorProtocol,
    // which is why the for-in loop looks slightly convoluted:

    for result in try db.execute(sql, 1.65) {
        switch result {
        case .success(let row):
            print(row)
        case .failure(let error):
            throw error
        }
    }
    
    // Alternatively, you can use the throwing nextRow() function to iterate over rows:

    let stmt = try db.execute(sql, 1.65)
    while let row = try stmt.nextRow() {
        //...
    }
    
    // If you expect the query to return exactly one row you can call one().
    // If the query returns no rows or more than one row, an exception will be thrown:

    let row = try db.execute(sql, 1.70).one()
    
    // If your query may or may not return a row but you only need the first one, use next():
    
    if let row = try db.execute(sql, 1.65).nextRow() {
        //...
    }
    
    // Values can be retrieved from rows by position or by name:
    
    let id: Int64 = row[0]!
    let name: String = row["name"]!
    let height: Double = row["height"]!
    let isFriend: Bool = row["is_friend"]!
    
    if let note: Data = row["note"] {
        let jsonObject = try JSONSerialization.jsonObject(with: note)
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
