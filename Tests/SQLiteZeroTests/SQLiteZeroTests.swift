import Foundation
import Testing
@testable import SQLiteZero

@Test func open() async throws {
    let db = try SQLite(":memory:")
    #expect(db.isOpen)
}

@Test func select() async throws {
    let db = try SQLite()
    let stmt = try db.execute("SELECT 1 as i, 1.1 as d, 'one' as s, X'CAFEBABE' as h, null as u")
    #expect(stmt.hasRow)
    
    let row = try stmt.nextRow()
    #expect(row != nil)
    #expect(!stmt.hasRow)
    #expect(try stmt.nextRow() == nil)
    
    guard let row = row else {
        return
    }
    
    #expect(row.count == 5)
    
    #expect(row[0] == Int64(1))
    #expect(row[1] == 1.1)
    #expect(row[2] == "one")
    #expect(row[3] == Data([0xCA, 0xFE, 0xBA, 0xBE]))
    #expect(row[4] == nil)

    let row2 = try stmt.nextRow()
    #expect(row2 == nil)
    #expect(!stmt.hasRow)
}

@Test func selectDict() async throws {
    let db = try SQLite()
    let stmt = try db.execute("SELECT 1 as i, 1.1 as d, 'one' as s, X'CAFEBABE' as h, null as u")
    let row = try stmt.nextRow()
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
    let db = try SQLite()
    try createTestTable1(db)
    
    let select = try db.execute(
    """
        select id, name, balance
        from t
        order by id
    """)
    
    #expect(select.hasRow)
    
    var count = 0
    while let _ = try select.nextRow() {
        count += 1
    }
    
    #expect(!select.hasRow)
    #expect(count == 3)
}

@Test func emptyResult() async throws {
    let db = try SQLite()
    try createTestTable1(db)
    
    let select = try db.execute(
    """
        select id, name, balance
        from t
        where 0 = 1
    """)
    
    #expect(!select.hasRow)
    #expect(select.colNames == ["id", "name", "balance"])
    #expect(try Array(select).isEmpty)
}

@Test func bindings() async throws {
    let db = try SQLite()
    try createTestTable1(db)
    
    let select = try db.execute(
    """
        insert into t(id, name, balance)
        values(99, ?, ?)
        returning id
    """,
    "noa", 99.66)

    #expect(try select.nextRow()?["id"] == 99)
}

@Test func namedBindings() async throws {
    let db = try SQLite()
    try createTestTable1(db)
    
    let select = try db.execute(
    """
        insert into t(id, name, balance) values
        (99, :name, :balance)
        returning id
    """,
    [":name": "noa", "balance": 99.66])
    
    #expect(try select.nextRow()?["id"] == 99)
}

@Test func typeConversion() async throws {
    let db = try SQLite()
    let select = try db.execute("""
        SELECT
            1 as int,
            -1 as nint,
            1.1 as double,
            '1' as text,
            cast('abc' as blob) as blob,
            null as nl,
            'true' as sbool
        """)
    let row = try select.nextRow()
    #expect(row != nil)
    
    guard let row = row else {
        return
    }

    #expect(row["int"] == true)
    #expect(row["sbool"] == true)
    #expect(row["double"] == 1.1)
    #expect(row["text"] == Int64(1))
    #expect(row["int"] == 1)
    #expect(row["nint"] == -1)
    #expect(row["nint"] as UInt64? == nil)
    #expect(row["int"] == Double(1))
    #expect(row["text"] == Double(1))
    #expect(row["int"] == "1")
    #expect(row["double"] == "1.1")
    #expect(row["blob"] == "abc")
    #expect(row["nl"] == nil)
    
}

@Test func multipleStatements() async throws {
    let db = try SQLite()
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
    
    #expect(try last.nextRow()!["name"] == "xan")
}

@Test func statementReuse() async throws {
    let N = 50
    let db = try SQLite()
    try createTestTable1(db)
    
    let stmt1 = try db.execute("insert into t(id, name, balance) values(?, ?, ?)",
                               4, "stmt1", Double.random(in: 0.5...100))
    let stmt2 = try db.execute("update t set member = ? where id = ?", true, 4)
    
    for i in 5...N {
        try stmt1.execute(i, "stmt1", Double.random(in: 0.5...100))
        try stmt2.execute(true, i)
    }
    
    #expect(try db.execute(
        "select count(*) as count from t where member = true").nextRow()!["count"] == N-1)
}

@Test func rollback() async throws {
    let db = try SQLite()
    
    try db.execute("""
        create table t(id integer primary key, comment text);
    
        insert into t values (1, 'initial');
    """)
    
    var count: Int = 0
    
    #expect(throws: SQLiteError.self) {
        try db.transaction {
            try db.execute("insert into t values (2, 'two')")
            count = try db.execute("select count(*) from t").nextRow()![0]!
            throw SQLiteError(code: 1, message: "testing")
        }
    }
    
    #expect(count == 2)
    #expect(try db.execute("select count(*) from t").nextRow()![0]! == 1)
}

@Test func commit() async throws {
    let db = try SQLite()
    
    try db.execute("""
        create table t(id integer primary key, comment text);
    
        insert into t values (1, 'initial');
    """)
    
    try db.transaction {
        try db.execute("insert into t values (2, 'two')")
    }

    let count: Int = try db.execute("select count(*) from t").nextRow()![0]!
    #expect(count == 2)
}

@Test func savepoints() async throws {
    let db = try SQLite()
    
    try db.execute("""
        create table t(id integer primary key, comment text);
    
        insert into t values (1, 'initial');
    """)
    
    var count = 0
    
    try db.transaction {
        try db.execute("insert into t values (2, 'two')")
        do {
            try db.transaction {
                try db.execute("insert into t values (3, 'three')")
                count = try db.execute("select count(*) from t").nextRow()![0]!
                #expect(count == 3)
                throw SQLiteError(code: 1, message: "testing")
            }
        } catch {
            count = try db.execute("select count(*) from t").nextRow()![0]!
            #expect(count == 2)
        }
        
        try db.transaction {
            try db.execute("insert into t values (3, 'three')")
            count = try db.execute("select count(*) from t").nextRow()![0]!
        }
        #expect(count == 3)
    }
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


