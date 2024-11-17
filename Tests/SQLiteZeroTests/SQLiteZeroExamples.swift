import Foundation
import Testing
@testable import SQLiteZero

func example1() throws {
    
    let path = ":memory:" //or "/path/to/database.sqlite"
    
    //Open or create a database at path with the default options
    let db = try SQLite(path)

    try db.execute("""
        create table birds (
            guid blob primary key,
            name text not null,
            speed real,
            flight_hours integer
        )
    """)
}
