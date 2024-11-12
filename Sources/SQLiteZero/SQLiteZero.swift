import Foundation
import CSQLiteZero
import os

public struct SqliteOpenOptions: OptionSet, Sendable {
    public let rawValue: Int32
    
    public init(rawValue: Self.RawValue) {
        self.rawValue = rawValue
    }
    
    public static let readOnly = SqliteOpenOptions(rawValue: 0x00000001)
    public static let readWrite = SqliteOpenOptions(rawValue: 0x00000002)
    public static let create = SqliteOpenOptions(rawValue: 0x00000004)
    public static let openURI = SqliteOpenOptions(rawValue: 0x00000040)
    public static let openMemory = SqliteOpenOptions(rawValue: 0x00000080)
    public static let openNomutex = SqliteOpenOptions(rawValue: 0x00008000)
    public static let openFullMutex = SqliteOpenOptions(rawValue: 0x00010000)
    public static let openSharedCache = SqliteOpenOptions(rawValue: 0x00020000)
    public static let openPrivateCache = SqliteOpenOptions(rawValue: 0x00040000)
    public static let openNoFollow = SqliteOpenOptions(rawValue: 0x01000000)
    public static let openExrescode = SqliteOpenOptions(rawValue: 0x02000000)
}

public struct SQLiteError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String
    
    public var description: String {
        return "[\(code)] \(message)"
    }
    
    public var isBusy: Bool {
        return code == SQLITE_BUSY
    }
}

public struct SQLiteRow: Sequence {
    let values: [Any?]
    let colNames: [String]
    
    public subscript(_ index: Int) -> Any? {
        return values[index]
    }
    
    public subscript(_ name: String) -> Any? {
        guard let index = colNames.firstIndex(of: name) else {
            return nil
        }
        return self[index]
    }
    
    public func asInt64(_ index: Int) -> Int64? {
        guard let value = self[index] else {
            return nil
        }

        switch value {
        case let v as Int64: return v
        case let v as Double: return Int64(v)
        case let v as String: return Int64(v)
        default: return nil
        }
    }
    
    public func asInt64(_ name: String) -> Int64? {
        if let index = colNames.firstIndex(of: name) {
            return self.asInt64(index)
        }
        return nil
    }

    public func asDouble(_ index: Int) -> Double? {
        guard let value = self[index] else {
            return nil
        }

        switch value {
        case let v as Double: return v
        case let v as Int64: return Double(v)
        case let v as String: return Double(v)
        default: return nil
        }
    }
    
    public func asDouble(_ name: String) -> Double? {
        if let index = colNames.firstIndex(of: name) {
            return self.asDouble(index)
        }
        return nil
    }

    public func asString(_ index: Int) -> String? {
        guard let value = self[index] else {
            return nil
        }
        
        switch value {
        case let v as String: return v
        case let v as Data: return String(data: v, encoding: .utf8)
        default: return String(describing: value)
        }
    }
    
    public func asString(_ name: String) -> String? {
        if let index = colNames.firstIndex(of: name) {
            return self.asString(index)
        }
        return nil
    }
    
    public func asData(_ index: Int) -> Data? {
        guard let value = self[index] else {
            return nil
        }
        
        switch value {
        case let v as Data: return v
        case let v as String: return v.data(using: .utf8)
        default: return nil
        }
    }
    
    public func asData(_ name: String) -> Data? {
        if let index = colNames.firstIndex(of: name) {
            return self.asData(index)
        }
        return nil
    }
        
    public var count: Int {
        return values.count
    }
    
    public func makeIterator() -> some IteratorProtocol {
        return zip(colNames, values).makeIterator()
    }
}

let SQLITE_TRANSIENT: sqlite3_destructor_type = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public class SQLiteStatement {
    public let sql: String
    public var changes: Int64 = 0
    public var hasRow = false
    public var colNames: [String] = []

    unowned var db: SQLite
    let log: Logger
    var stmt: OpaquePointer! = nil
    
    init(_ db: SQLite, _ sql: String) throws {
        self.db = db
        self.log = db.log
        self.sql = sql
        
        let rc = sqlite3_prepare_v2(db.db, sql, -1, &stmt, nil)
        if rc != SQLITE_OK {
            let message = errorMessage(db.db, rc)
            throw SQLiteError(code: rc, message: message)
        }
    }
    
    public func execute(_ args: [String: Any?]) throws {
        try bind(args)
        try execute()
    }

    public func execute(_ args: [Any?]) throws {
        try bind(args)
        try execute()
    }
    
    public func next() throws -> SQLiteRow? {
        guard hasRow else {
            return nil
        }
        let row = readRow()
        try step()
        return row
    }
    
    func bind(_ args: [Any?]) throws {
        var rc: Int32 = SQLITE_OK
        
        for (i, arg) in args.enumerated() {
            switch arg {
            case nil:
                rc = sqlite3_bind_null(stmt, Int32(i + 1))
            case let v as UInt64:
                if v <= Int64.max {
                    rc = sqlite3_bind_int64(stmt, Int32(i + 1), Int64(v))
                } else {
                    rc = sqlite3_bind_double(stmt, Int32(i + 1), Double(v))
                }
            case let v as any BinaryInteger:
                rc = sqlite3_bind_int64(stmt, Int32(i + 1), Int64(v))
            case let v as any BinaryFloatingPoint:
                rc = sqlite3_bind_double(stmt, Int32(i + 1), Double(v))
            case let v as String:
                rc = sqlite3_bind_text(stmt, Int32(i + 1), v, -1, SQLITE_TRANSIENT)
            case let v as Data:
                v.withUnsafeBytes { buf in
                    rc = sqlite3_bind_blob(stmt, Int32(i + 1), buf.baseAddress, -1, SQLITE_TRANSIENT)
                }
            case let v as Bool:
                rc = sqlite3_bind_int(stmt, Int32(i + 1), v ? 1 : 0)
            default:
                rc = sqlite3_bind_text(stmt, Int32(i + 1), "\(arg!)", -1, SQLITE_TRANSIENT)
            }
            
            if rc != SQLITE_OK {
                throw SQLiteError(code: rc, message: errorMessage(db.db, rc))
            }
        }
    }
    
    func bind(_ args: [String: Any?]) throws {
        var posArgs = [Any?](repeating: nil, count: args.count)
        
        for (k, v) in args {
            let index = sqlite3_bind_parameter_index(stmt, k) - 1
            if index == -1 {
                throw SQLiteError(code: SQLITE_ERROR, message: "Invalid bind parameter name: \(k)")
            }
            posArgs[Int(index)] = v
        }
        
        try bind(posArgs)
    }
    
    func execute() throws {
        self.changes = 0
        self.hasRow = false
        self.colNames = []
        
        let rc = sqlite3_reset(stmt)
        if rc != SQLITE_OK {
            throw SQLiteError(code: rc, message: errorMessage(db.db, rc))
        }

        try step()
        self.changes = db.changes
        self.colNames = readColNames()
    }
        
    func readColNames() -> [String] {
        let count = sqlite3_column_count(stmt)
        var colNames: [String] = []
        
        for i in 0..<count {
            colNames.append(String(cString: sqlite3_column_name(stmt, i)))
        }
        
        return colNames
    }

    func readRow() -> SQLiteRow {
        let count = sqlite3_column_count(stmt)
        var values: [Any?] = []
        for i in 0..<count {
            let type = sqlite3_column_type(stmt, i)
            switch type {
            case SQLITE_INTEGER:
                values.append(Int64(sqlite3_column_int64(stmt, i)))
            case SQLITE_FLOAT:
                values.append(Double(sqlite3_column_double(stmt, i)))
            case SQLITE_TEXT:
                values.append(String(cString: sqlite3_column_text(stmt, i)))
            case SQLITE_BLOB:
                values.append(Data(bytes: sqlite3_column_blob(stmt, i),
                                count: Int(sqlite3_column_bytes(stmt, i))))
            default:
                values.append(nil)
            }
        }
        
        return SQLiteRow(values: values, colNames: colNames)
    }

    func step() throws {
        let rc = sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            self.hasRow = false
            return
        }
        if rc == SQLITE_ROW {
            self.hasRow = true
        } else {
            throw SQLiteError(code: rc, message: errorMessage(db.db, rc))
        }
    }
    
    deinit {
        let rc = sqlite3_finalize(stmt)
        if rc != SQLITE_OK {
            log.error("Failed to finalize statement: \(rc)")
        }
    }
}

public class SQLite {
    public static let defaultBusyTimeout = TimeInterval(1.0)
    public static let defaultCacheSize = 100
    
    var db: OpaquePointer! = nil
    let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "General")
    var statements: Cache<String, SQLiteStatement>
    
    public init(_ path: String, flags: SqliteOpenOptions = [.readWrite, .create],
                cacheSize: Int = SQLite.defaultCacheSize) throws
    {
        let rc = sqlite3_open_v2(path, &db, flags.rawValue, nil)
        
        if rc != SQLITE_OK {
            let message = errorMessage(db, rc)
            _ = sqlite3_close(db)
            throw SQLiteError(code: rc, message: message)
        }
        
        statements = Cache(maxCount: cacheSize)
        busyTimeout(seconds: SQLite.defaultBusyTimeout)
    }
    
    public func execute(_ sql: String, _ args: [Any?] = [Any?]()) throws -> SQLiteStatement {
        let stmt = try getStatement(sql)
        try stmt.execute(args)
        return stmt
    }

    public func execute(_ sql: String, _ args: [String: Any?]) throws -> SQLiteStatement {
        let stmt = try getStatement(sql)
        try stmt.execute(args)
        return stmt
    }
        
    public var changes: Int64 {
        return sqlite3_changes64(db)
    }
    
    public var inTransaction: Bool {
        return sqlite3_get_autocommit(db) == 0
    }
    
    public func busyTimeout(seconds: TimeInterval) {
        sqlite3_busy_timeout(db, Int32(seconds * 1000.0))
    }

    func getStatement(_ sql: String) throws -> SQLiteStatement {
        if let stmt = statements[sql] {
            let rc = sqlite3_clear_bindings(stmt.stmt)
            if rc != SQLITE_OK {
                throw SQLiteError(code: rc, message: errorMessage(db, rc))
            }

            return stmt
        }
        let stmt = try SQLiteStatement(self, sql)
        statements[sql] = stmt
        return stmt
    }
    
    public var isOpen: Bool {
        return self.db != nil
    }
    
    deinit {
        statements.removeAll()
        let rc = sqlite3_close(db)
        if rc == SQLITE_OK {
            return
        }
        if rc != SQLITE_BUSY {
            log.error("Failed to close database because of unclosed statements")
        } else {
            log.error("Failed to close database: \(errorMessage(self.db, rc))")
        }
    }
    
}

func errorMessage(_ db: OpaquePointer?,_ rc: Int32) -> String {
    guard let db = db else {
        let cMessage = sqlite3_errstr(rc)
        let message = cMessage != nil ? String(cString: cMessage!) : "\(rc) - Unknown error"
        return message
    }
    
    var cMessage = sqlite3_errmsg(db)
    if cMessage == nil {
        cMessage = sqlite3_errstr(rc)
    }
    return cMessage != nil ? String(cString: cMessage!) : "\(rc) - Unknown error"
}
