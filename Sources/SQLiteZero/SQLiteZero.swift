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
        return "\(code): \(message)"
    }
    
    public var isBusy: Bool {
        return code == SQLITE_BUSY
    }
    
    public static func from(_ db: OpaquePointer?,_ rc: Int32? = nil) -> SQLiteError {
        guard let db = db else {
            guard let rc = rc else {
                return SQLiteError(code: -1, message: "Unknown error")
            }
            let cMessage = sqlite3_errstr(rc)
            guard let cMessage = cMessage else {
                return SQLiteError(code: rc, message: "Error \(rc)")
            }
            return SQLiteError(code: rc, message: String(cString: cMessage))
        }

        let code: Int32 = rc ?? sqlite3_errcode(db)
        let cMessage = sqlite3_errmsg(db) ?? sqlite3_errstr(code)
        
        if let cMessage = cMessage {
            return SQLiteError(code: code, message: String(cString: cMessage))
        }
        return SQLiteError(code: code, message: "Error \(code)")
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
            throw SQLiteError.from(db.db, rc)
        }
    }

    @discardableResult
    public func execute(_ args: Any?...) throws -> Self {
        return try execute(SQLiteArgs(args))
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
                self.error = SQLiteError.from(db?.db, rc)
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
    
    @discardableResult
    func execute(_ params: SQLiteArgs) throws -> Self {
        let rc = sqlite3_reset(stmt)
        if rc != SQLITE_OK {
            self.error = SQLiteError.from(db?.db, rc)
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
        return self
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
            self.error = SQLiteError.from(db?.db, rc)
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
    public static let backupBatchSize: Int32 = 1024
    
    var db: OpaquePointer! = nil
    let path: String
    let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "General")
    
    public convenience init() throws {
        try self.init(":memory:")
    }
    
    public init(_ path: String, flags: SqliteOpenOptions = [.readWrite, .create]) throws {
        self.path = path
        let rc = sqlite3_open_v2(path, &db, flags.rawValue, nil)
        
        if rc != SQLITE_OK {
            let err = SQLiteError.from(db, rc)
            _ = sqlite3_close(db)
            throw err
        }
        
        busyTimeout(seconds: SQLite.defaultBusyTimeout)
    }

    @discardableResult
    public func execute(_ sql: String, _ args: Any?...) throws -> SQLiteStatement {
        return try execute(sql, SQLiteArgs(args))
    }
    
    public func executeScript(_ sql: String) throws {
        try sql.withCString {
            var pThisSQL = $0
            var (nextStmt, pRestSQL) = try prepareInternal(pThisSQL)
            
            while true {
                guard let stmt = nextStmt else {
                    break
                }
                try stmt.execute()
                guard let pNextSQL = pRestSQL else {
                    break
                }
                pThisSQL = pNextSQL
                (nextStmt, pRestSQL) = try prepareInternal(pThisSQL)
            }
        }
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
        return try sql.withCString {
            let (stmt, _) = try prepareInternal($0)
            guard let stmt = stmt else {
                throw SQLiteError(code: SQLITE_ERROR, message: "Empty or invalid SQL")
            }
            return stmt
        }
    }
    
    func prepareInternal(_ pSQL: UnsafePointer<CChar>) throws
        -> (SQLiteStatement?, UnsafePointer<CChar>?)
    {
        var pSQLNext: UnsafePointer<CChar>! = nil
        var pStmt: OpaquePointer! = nil
        
        let rc = sqlite3_prepare_v2(db, pSQL, -1, &pStmt, &pSQLNext)
        if rc != SQLITE_OK {
            sqlite3_finalize(pStmt)
            throw SQLiteError.from(db, rc)
        }

        guard let pStmt = pStmt else {
            return (nil, nil)
        }

        if pSQLNext == nil || pSQLNext![0] == 0 {
            return try (
                SQLiteStatement(db: self, stmt: pStmt, sql: String(cString: pSQL)),
                nil)
        }
        
        let bytes = UnsafeBufferPointer(
            start: pSQL,
            count: Int(pSQLNext! - pSQL))
        
        let thisSQL = bytes.withMemoryRebound(to: UInt8.self) { p in
            return String(bytes: p, encoding: .utf8)
        }
        
        guard let thisSQL = thisSQL else {
            throw SQLiteError(code: SQLITE_ERROR, message: "SQL statement contains invalid UTF-8")
        }
                        
        return try (SQLiteStatement(db: self, stmt: pStmt, sql: thisSQL), pSQLNext)
    }
    
    public var pageSize: Int {
        get throws {
            return try execute("pragma page_size").one()[0]!
        }
    }
    
    public func backup(to destination: SQLite, progress: ((Int, Int, Int) -> Bool)? = nil) throws {
        let backup = sqlite3_backup_init(destination.handle, "main", self.handle, "main")
        guard let backup = backup else {
            throw SQLiteError.from(destination.db)
        }

        var retryCount = 0
        let pageSize = try self.pageSize
        
        repeat {
            let rc = sqlite3_backup_step(backup, Self.backupBatchSize)
            let remaining = sqlite3_backup_remaining(backup)
            let total = sqlite3_backup_pagecount(backup)

            if rc == SQLITE_DONE {
                break
            } else if rc == SQLITE_LOCKED || rc == SQLITE_BUSY {
                retryCount += 1
            } else if rc == SQLITE_OK {
                retryCount = 0
            } else {
                let err = SQLiteError.from(destination.db, rc)
                sqlite3_backup_finish(backup)
                throw err
            }
            
            if let progress = progress {
                if !progress(Int(remaining) * pageSize, Int(total) * pageSize, retryCount) {
                    break
                }
            }
        } while true
                    
        sqlite3_backup_finish(backup)
    }
    
    public var isOpen: Bool {
        return self.db != nil
    }
    
    public var errorCode: Int32 {
        return sqlite3_errcode(db)
    }
        
    public var handle: OpaquePointer? {
        return db
    }
    
    deinit {
        let rc = sqlite3_close(db)
        if rc == SQLITE_OK {
            return
        }
        if rc == SQLITE_BUSY {
            log.error("Failed to close database because there are unclosed statements")
        } else {
            log.error("Failed to close database: \(SQLiteError.from(self.db, rc))")
        }
    }
}
