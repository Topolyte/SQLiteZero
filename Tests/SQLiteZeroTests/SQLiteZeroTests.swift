import Testing
@testable import SQLiteZero

@Test func open() async throws {
    let db = try SQLite(":memory:")
    #expect(db.isOpen)
}

