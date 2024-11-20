import Foundation
import CSQLite
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

public enum SQLiteValue: Equatable {
    case null
    case integer(Int64)
    case double(Double)
    case text(String)
    case blob(Data)
}

public struct SQLiteRow: Sequence, Equatable {
    let values: [SQLiteValue]
    let colNames: [String]
    
    public init(values: [SQLiteValue], colNames: [String]) {
        self.values = values
        self.colNames = colNames
    }
    
    public init(_ values: [SQLiteValue]) {
        self.values = values
        self.colNames = (0..<values.count).map{ String($0) }
    }
    
    public func isNull(_ index: Int) -> Bool {
        switch values[index] {
        case .null:
            return true
        default:
            return false
        }
    }
    
    public subscript<T>(_ index: Int) -> T? {
        let value = values[index]
        
        switch value {
        case let .integer(v):
            switch T.self {
            case is Int64.Type:
                return v as? T
            case is Int.Type:
                return Int(exactly: v) as? T
            case is Bool.Type:
                return (v != 0) as? T
            case is Double.Type:
                return Double(exactly: v) as? T
            case is String.Type:
                return String(describing: v) as? T
            default: return nil
            }
        case let .double(v):
            switch T.self  {
            case is Double.Type:
                return v as? T
            case is Int.Type:
                return Int(exactly: v) as? T
            case is Int64.Type:
                return Int64(exactly: v) as? T
            case is String.Type:
                return String(describing: v) as? T
            case is Bool.Type:
                return (v != 0.0) as? T
            default: return nil
            }
        case let .text(v):
            switch T.self {
            case is String.Type:
                return v as? T
            case is Data.Type:
                return v.data(using: .utf8) as? T
            case is Int.Type:
                return Int(v) as? T
            case is Int64.Type:
                return Int64(v) as? T
            case is Double.Type:
                return Double(v) as? T
            case is Bool.Type:
                let b = v.lowercased()
                if b == "true" {
                    return true as? T
                } else if b == "false" {
                    return false as? T
                }
                return nil
            default: return nil
            }
        case let .blob(v):
            switch T.self {
            case is Data.Type:
                return v as? T
            case is String.Type:
                return String(data: v, encoding: .utf8) as? T
            default: return nil
            }
        case .null:
            return nil
        }

    }

    public subscript<T>(_ name: String) -> T? {
        guard let index = colNames.firstIndex(of: name) else {
            return nil
        }
        return self[index]
    }
                    
    public var count: Int {
        return values.count
    }
    
    public func makeIterator() -> some IteratorProtocol {
        return zip(colNames, values).makeIterator()
    }
    
    public static func == (lhs: SQLiteRow, rhs: SQLiteRow) -> Bool {
        return lhs.values == rhs.values
    }
}

let SQLITE_TRANSIENT: sqlite3_destructor_type = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public class SQLiteStatement: Sequence, IteratorProtocol {
    public let sql: String
    public var changes: Int64 = 0
    public var error: Error? = nil
    public var hasRow = false
    public var colNames: [String] = []

    weak var db: SQLite?
    let log: Logger
    var stmt: OpaquePointer! = nil
    
    init(db: SQLite, stmt: OpaquePointer, sql: String) throws {
        self.sql = sql
        self.db = db
        self.log = db.log
        self.stmt = stmt
    }
    
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

    public func execute(_ args: Any?...) throws {
        try execute(SQLiteArgs(args))
    }
        
    public func nextRow() throws -> SQLiteRow? {
        guard hasRow else {
            return nil
        }
        guard self.error == nil else {
            throw self.error!
        }
        let row = readRow()
        try step()
        return row
    }
    
    public func all() throws -> [SQLiteRow] {
        let result = Array(self)
        try throwErrorIfAny()
        return result
    }
    
    public func one() throws -> SQLiteRow {
        guard let row = try nextRow() else {
            throw SQLiteError(code: SQLITE_ERROR, message: "Query returned no rows")
        }
        guard !hasRow else {
            throw SQLiteError(code: SQLITE_ERROR, message: "Query returned more than one row")
        }
        return row
    }
            
    public func makeIterator() -> SQLiteStatement {
        return self
    }
    
    public func next() -> SQLiteRow? {
        guard self.error == nil else {
            return nil
        }
        do {
            if let row = try nextRow() {
                return row
            }
        } catch {
            self.error = error
        }
        return nil
    }
    
    public func clearBindings() {
        sqlite3_clear_bindings(stmt)
    }
    
    public var handle: OpaquePointer? {
        return stmt
    }
    
    public func throwErrorIfAny() throws {
        if let error = self.error {
            throw error
        }
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
                    rc = sqlite3_bind_text(stmt, Int32(i + 1), v.description, -1, SQLITE_TRANSIENT)
                }
            case let v as any BinaryInteger:
                rc = sqlite3_bind_int64(stmt, Int32(i + 1), Int64(v))
            case let v as any BinaryFloatingPoint:
                rc = sqlite3_bind_double(stmt, Int32(i + 1), Double(v))
            case let v as String:
                rc = sqlite3_bind_text(stmt, Int32(i + 1), v, -1, SQLITE_TRANSIENT)
            case let v as Data:
                v.withUnsafeBytes { buf in
                    rc = sqlite3_bind_blob(
                        stmt, Int32(i + 1), buf.baseAddress, Int32(buf.count), SQLITE_TRANSIENT)
                }
            case let v as Bool:
                rc = sqlite3_bind_int(stmt, Int32(i + 1), v ? 1 : 0)
            default:
                rc = sqlite3_bind_text(stmt, Int32(i + 1), "\(arg!)", -1, SQLITE_TRANSIENT)
            }
            
            if rc != SQLITE_OK {
                self.error = SQLiteError(code: rc, message: errorMessage(db?.db, rc))
                throw self.error!
            }
        }
    }
    
    let paramPrefixes: [Character] = [":", "$", "@"]
    
    func bind(_ args: [String: Any?]) throws {
        var posArgs = [Any?](repeating: nil, count: args.count)
        
        for (k, v) in args {
            var index = sqlite3_bind_parameter_index(stmt, k) - 1
            if index == -1 {
                index = sqlite3_bind_parameter_index(stmt, ":" + k) - 1
            }
            if index == -1 {
                index = sqlite3_bind_parameter_index(stmt, "$" + k) - 1
            }
            if index == -1 {
                index = sqlite3_bind_parameter_index(stmt, "@" + k) - 1
            }
            if index == -1 {
                self.error = SQLiteError(
                    code: SQLITE_ERROR, message: "Invalid bind parameter name: \(k)")
                throw self.error!
            }
            posArgs[Int(index)] = v
        }
        
        try bind(posArgs)
    }
    
    func execute(_ params: SQLiteArgs) throws {
        let rc = sqlite3_reset(stmt)
        if rc != SQLITE_OK {
            self.error = SQLiteError(code: rc, message: errorMessage(db?.db, rc))
            throw self.error!
        }
        
        switch params {
            case .none: break
        case .named(let args):
            try bind(args)
        case .positional(let args):
            try bind(args)
        }
        try execute()
    }

    func execute() throws {
        self.changes = 0
        self.error = nil
        self.hasRow = false
        self.colNames = []

        try step()
        self.changes = db?.changes ?? 0
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
        var values: [SQLiteValue] = []
        for i in 0..<count {
            let type = sqlite3_column_type(stmt, i)
            switch type {
            case SQLITE_INTEGER:
                values.append(.integer(Int64(sqlite3_column_int64(stmt, i))))
            case SQLITE_FLOAT:
                values.append(.double(Double(sqlite3_column_double(stmt, i))))
            case SQLITE_TEXT:
                values.append(.text(String(cString: sqlite3_column_text(stmt, i))))
            case SQLITE_BLOB:
                values.append(.blob(Data(bytes: sqlite3_column_blob(stmt, i),
                                count: Int(sqlite3_column_bytes(stmt, i)))))
            default:
                values.append(.null)
            }
        }
        
        return SQLiteRow(values: values, colNames: colNames)
    }

    func step() throws {
        guard self.error == nil else {
            throw self.error!
        }
        let rc = sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            self.hasRow = false
            return
        }
        if rc == SQLITE_ROW {
            self.hasRow = true
        } else {
            self.error = SQLiteError(code: rc, message: errorMessage(db?.db, rc))
            throw self.error!
        }
    }
    
    deinit {
        if let stmt = stmt {
            let rc = sqlite3_finalize(stmt)
            if rc != SQLITE_OK {
                log.error("Failed to finalize statement: \(rc)")
            }
        }
    }
}

enum SQLiteArgs {
    case none
    case positional([Any?])
    case named([String: Any?])
    
    init (_ params: [Any?]? = nil) {
        if let params = params {
            if params.count == 1 && params.first is [String:Any?] {
                self = .named(params.first! as! [String:Any?])
            } else {
                self = .positional(params)
            }
        } else {
            self = .none
        }
    }
}

public enum SQLiteTransactionType: String {
    case deferred, immedate, exclusive
}

public class SQLite {
    public static let defaultBusyTimeout = TimeInterval(1.0)
    
    var db: OpaquePointer! = nil
    let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "General")
    
    public convenience init() throws {
        try self.init(":memory:")
    }
    
    public init(_ path: String, flags: SqliteOpenOptions = [.readWrite, .create]) throws {
        let rc = sqlite3_open_v2(path, &db, flags.rawValue, nil)
        
        if rc != SQLITE_OK {
            let message = errorMessage(db, rc)
            _ = sqlite3_close(db)
            throw SQLiteError(code: rc, message: message)
        }
        
        busyTimeout(seconds: SQLite.defaultBusyTimeout)
    }

    @discardableResult
    public func execute(_ sql: String, _ args: Any?...) throws -> SQLiteStatement {
        return try execute(sql, SQLiteArgs(args))
    }

    @discardableResult
    func execute(_ sql: String, _ args: SQLiteArgs) throws -> SQLiteStatement {
        let stmt = try prepare(sql)
        try stmt.execute(args)
        return stmt
    }
    
    @discardableResult
    public func transaction<T>(
        _ txType: SQLiteTransactionType = .deferred, _ f: () throws -> T) throws -> T
    {
        let savepoint = inTransaction ? UUID().uuidString : nil
        
        if let savepoint = savepoint {
            try execute("savepoint \"\(savepoint)\"")
        } else {
            try execute("begin \(txType.rawValue)")
        }
        
        do {
            let res = try f()
            if let savepoint = savepoint {
                try execute("release savepoint \"\(savepoint)\"")
            } else {
                try execute("commit")
            }
            return res
        } catch let err {
            if let savepoint = savepoint {
                _ = try? execute("rollback to \"\(savepoint)\"")
            } else {
                _ = try? execute("rollback")
            }
            throw err
        }
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

    public func prepare(_ sql: String) throws -> SQLiteStatement {
        var stmt: SQLiteStatement? = nil
        
        try sql.withCString {
            var pStmt: OpaquePointer! = nil
            var pCurrent: UnsafePointer<CChar>? = $0
            var pNext: UnsafePointer<CChar>? = nil
            
            while true {
                let rc = sqlite3_prepare_v2(db, pCurrent, -1, &pStmt, &pNext)
                if rc != SQLITE_OK {
                    let message = errorMessage(db, rc)
                    sqlite3_finalize(pStmt)
                    throw SQLiteError(code: rc, message: message)
                }
                
                if pNext == nil || pNext![0] == 0 {
                    stmt = try SQLiteStatement(db: self, stmt: pStmt, sql: String(cString: pCurrent!))
                    break
                } else {
                    let rc = sqlite3_step(pStmt)
                    if rc != SQLITE_DONE && rc != SQLITE_ROW {
                        let message = errorMessage(db, rc)
                        sqlite3_finalize(pStmt)
                        throw SQLiteError(code: rc, message: message)
                    }
                    
                    pCurrent = pNext
                    pNext = nil
                    sqlite3_finalize(pStmt)
                    pStmt = nil
                }
            }
        }
        
        guard let stmt = stmt else {
            throw SQLiteError(code: SQLITE_ERROR, message: "BUG: stmt == nil")
        }
        
        return stmt
    }
    
    public var isOpen: Bool {
        return self.db != nil
    }
    
    public var handle: OpaquePointer? {
        return db
    }
    
    deinit {
        let rc = sqlite3_close(db)
        if rc == SQLITE_OK {
            return
        }
        if rc != SQLITE_BUSY {
            log.error("Failed to close database because there are unclosed statements")
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
