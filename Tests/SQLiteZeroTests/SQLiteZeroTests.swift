import Foundation
import Testing
@testable import SQLiteZero

@Test func open() async throws {
    let db = try SQLite(":memory:")
    #expect(db.isOpen)
}

@Test func select() async throws {
    let db = try SQLite(":memory:")
    let stmt = try db.execute("SELECT 1 as i, 1.1 as d, 'one' as s, X'CAFEBABE' as h, null as u")
    #expect(stmt.hasRow)
    
    let row = try stmt.next()
    #expect(row != nil)
    #expect(!stmt.hasRow)
    #expect(try stmt.next() == nil)
    
    guard let row = row else {
        return
    }
    
    #expect(row.count == 5)
    
    #expect(row[0] == Int64(1))
    #expect(row[1] == 1.1)
    #expect(row[2] == "one")
    #expect(row[3] == Data([0xCA, 0xFE, 0xBA, 0xBE]))
    #expect(row[4] == nil)

    let row2 = try stmt.next()
    #expect(row2 == nil)
    #expect(!stmt.hasRow)
}

@Test func selectDict() async throws {
    let db = try SQLite(":memory:")
    let stmt = try db.execute("SELECT 1 as i, 1.1 as d, 'one' as s, X'CAFEBABE' as h, null as u")
    let row = try stmt.next()
    #expect(row != nil)
    
    guard let row = row else {
        return
    }
    #expect(row.count == 5)
    
    #expect(row["i"] == Int64(1))
    #expect(row["d"] == 1.1)
    #expect(row["s"] == "one")
    #expect(row["h"] == Data([0xCA, 0xFE, 0xBA, 0xBE]))
    #expect(row["u"] == nil)
    #expect(row["notfound"] == nil)
}

@Test func selectMultiple() async throws {
    let db = try SQLite(":memory:")
    try createTestTable1(db)
    
    let select = try db.execute(
    """
        select id, name, balance
        from t
        order by id
    """)
    
    #expect(select.hasRow)
    
    var count = 0
    while let _ = try select.next() {
        count += 1
    }
    
    #expect(!select.hasRow)
    #expect(count == 3)
}

@Test func emptyResult() async throws {
    let db = try SQLite(":memory:")
    try createTestTable1(db)
    
    let select = try db.execute(
    """
        select id, name, balance
        from t
        where 0 = 1
    """)
    
    #expect(!select.hasRow)
    #expect(select.colNames == ["id", "name", "balance"])
    #expect(try select.all().isEmpty)
}

@Test func bindings() async throws {
    let db = try SQLite(":memory:")
    try createTestTable1(db)
    
    let select = try db.execute(
    """
        insert into t(id, name, balance)
        values(99, ?, ?)
        returning id
    """,
    ["noa", 99.66])

    #expect(try select.next()?["id"] == 99)
}

@Test func namedBindings() async throws {
    let db = try SQLite(":memory:")
    try createTestTable1(db)
    
    let select = try db.execute(
    """
        insert into t(id, name, balance) values
        (99, :name, :balance)
        returning id
    """,
    [":name": "noa", "balance": 99.66])
    
    #expect(try select.next()?["id"] == 99)
}

@Test func typeConversion() async throws {
    let db = try SQLite(":memory:")
    let select = try db.execute(
        "SELECT 1 as i, 1.1 as d, '1' as s, cast('abc' as blob) as h, null as u")
    let row = try select.next()
    #expect(row != nil)
    
    guard let row = row else {
        return
    }

    #expect(row["i"] == true)
    #expect(row["d"] == 1.1)
    #expect(row["s"] == Int64(1))
    #expect(row["i"] == Double(1))
    #expect(row["s"] == Double(1))
    #expect(row["i"] == "1")
    #expect(row["d"] == "1.1")
    #expect(row["h"] == "abc")
    #expect(row["u"] == nil)
}

@Test func one() async throws {
    let db = try SQLite(":memory:")
    
    let noRows = try db.execute("select 1 where 1 = 2")
    #expect(throws: SQLiteError.self) {
        _ = try noRows.first()
    }

    let oneRow = try db.execute("select 1, 'noa'")
    let row = try oneRow.first()
    #expect(row == SQLiteRow([.integer(1), .text("noa")]))
}

@Test func multipleStatements() async throws {
    let db = try SQLite(":memory:")
    let last = try db.execute(
    """
        create table t(
            id integer primary key,
            name text not null
        );
    
        insert into t(id, name) values
        (1, 'xan'),
        (2, 'mia');
    
        select id, name from t where id = :id;
    """, [":id": 1])
    
    #expect(try last.first()["name"] == "xan")
}


func createTestTable1(_ db: SQLite) throws {
    let _ = try db.execute(
    """
        create table t(
            id integer primary key,
            name text not null,
            balance real not null,
            member integer not null default false,
            comment text
        )
    """)
    
    let _ = try db.execute(
    """
        insert into t(id, name, balance, member, comment) values
        (1, 'max', 123.456, 1, "best"),
        (2, 'ada', 1024.1024, 1, "nice"),
        (3, 'ari', 0.01, 0, null)
    """)
}


