import Darwin
import Foundation
import CSQLite

package final class DrawingLibraryDatabase {
  package let url: URL
  private let rootURL: URL
  private let catalogPath: String
  private var db: OpaquePointer?
  private var openedIdentity: (device: dev_t, inode: ino_t)?
  package let writerLease: DrawingLibraryWriterLease?
  private var guardedTransaction = false
  package private(set) var selectedFileValidationCount = 0
  private let encoder: JSONEncoder = {
    let value = JSONEncoder()
    value.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return value
  }()
  package enum Fault: String { case beforeCommit, afterCommit }
  package var injectFault: ((Fault) throws -> Void)?
  package init(url: URL, readOnly: Bool = false, writerLease suppliedLease: DrawingLibraryWriterLease? = nil) throws {
    self.url = url
    self.rootURL = url.deletingLastPathComponent()
    self.catalogPath = url.path
    if readOnly {
      guard suppliedLease == nil else { throw DrawingLibraryDatabaseError.database("Read-only connection cannot borrow a writer lease") }
      writerLease = nil
      try LibraryExchangeCatalogSelection.validate(root: rootURL, database: url)
    } else {
      let lease = try suppliedLease ?? DrawingLibraryWriterLease(root: rootURL)
      try lease.assertMatches(root: rootURL)
      writerLease = lease
      try LibraryExchangeCatalogSelection.validate(root: rootURL, database: url)
    }
    var selected = stat()
    if lstat(catalogPath, &selected) == 0 {
      guard selected.st_mode & S_IFMT == S_IFREG, selected.st_nlink == 1 else { throw DrawingLibraryDatabaseError.database("Catalog must be a regular private file") }
    } else if errno != ENOENT { throw DrawingLibraryDatabaseError.database("Catalog path unavailable") }
    try writerLease?.claimDatabase()
    do {
      let flags = (readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) | SQLITE_OPEN_FULLMUTEX
      guard sqlite3_open_v2(catalogPath, &db, flags, nil) == SQLITE_OK else { throw failure() }
      var opened = stat()
      guard lstat(catalogPath, &opened) == 0, opened.st_mode & S_IFMT == S_IFREG, opened.st_nlink == 1 else { throw DrawingLibraryDatabaseError.database("Opened catalog path changed") }
      openedIdentity = (opened.st_dev, opened.st_ino)
      try assertSelectedFile()
      sqlite3_busy_timeout(db, 5000)
      try execute("PRAGMA foreign_keys=ON")
      guard try scalar("PRAGMA foreign_keys") == "1" else { throw DrawingLibraryDatabaseError.database("foreign key enforcement unavailable") }
      let existingVersion = try scalar("PRAGMA user_version")
      guard existingVersion == "0" || existingVersion == "11" else { throw DrawingLibraryDatabaseError.database("unsupported schema") }
      if existingVersion == "11" {
        guard try scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN ('dx_source_summary','dx_photo_metadata')") == "2" else {
          throw DrawingLibraryDatabaseError.database("unsupported schema: required source metadata tables are missing")
        }
      }
      if !readOnly {
        try execute("PRAGMA journal_mode=DELETE")
        try execute("PRAGMA synchronous=FULL")
        if existingVersion == "0" { try execute(Self.schema) }
      }
      guard let version = try scalar("PRAGMA user_version"), version == "11" else {
        throw DrawingLibraryDatabaseError.database("unsupported schema")
      }
      guard try scalar("SELECT value FROM state WHERE key='profile'") == "adaptiveplotter.drawing-library/1" else { throw DrawingLibraryDatabaseError.database("Unsupported Library profile") }
    } catch { sqlite3_close(db); db = nil; writerLease?.releaseDatabase(); throw error }
  }
  // Close SQLite before releasing the lifetime lease, including failed init.
  deinit { sqlite3_close(db); writerLease?.releaseDatabase() }

  private func failure() -> DrawingLibraryDatabaseError {
    .database(db.map { String(cString: sqlite3_errmsg($0)) } ?? "connection unavailable")
  }
  package func assertSelectedFile() throws {
    selectedFileValidationCount += 1
    guard let db, let openedIdentity else { throw DrawingLibraryDatabaseError.database("Opened catalog identity is unavailable") }
    try writerLease?.assertMatches(root: rootURL)
    try LibraryExchangeCatalogSelection.validate(root: rootURL, database: url)
    // The VFS owns the actual opened descriptor. A pathname stat immediately
    // after sqlite3_open alone could already describe a replacement file.
    var moved: Int32 = 0
    guard sqlite3_file_control(db, "main", SQLITE_FCNTL_HAS_MOVED, &moved) == SQLITE_OK else {
      throw DrawingLibraryDatabaseError.database("SQLite VFS cannot prove opened catalog selection")
    }
    guard moved == 0 else { throw DrawingLibraryDatabaseError.database("Opened catalog was moved, deleted or replaced") }
    var current = stat()
    guard lstat(catalogPath, &current) == 0, current.st_mode & S_IFMT == S_IFREG, current.st_nlink == 1,
      current.st_dev == openedIdentity.device, current.st_ino == openedIdentity.inode else {
      throw DrawingLibraryDatabaseError.database("Selected catalog disappeared or was replaced; close the owner and explicitly recover")
    }
  }
  package func execute(_ sql: String, _ values: [String?] = []) throws {
    if guardedTransaction {
      guard sqlite3_get_autocommit(db) == 0 else { throw DrawingLibraryDatabaseError.database("Guarded catalog transaction was lost") }
    } else { try assertSelectedFile() }
    try executeOnConnection(sql, values)
  }
  /// Cleanup uses the actual retained connection even when the selected pathname changed.
  private func executeOnConnection(_ sql: String, _ values: [String?] = []) throws {
    if values.isEmpty {
      guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
      return
    }
    let stmt = try prepare(sql, values)
    defer { sqlite3_finalize(stmt) }
    guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
  }
  private func prepare(_ sql: String, _ values: [String?]) throws -> OpaquePointer {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw failure() }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (index, value) in values.enumerated() {
      let code = value.map { sqlite3_bind_text(stmt, Int32(index + 1), $0, -1, transient) }
        ?? sqlite3_bind_null(stmt, Int32(index + 1))
      guard code == SQLITE_OK else { sqlite3_finalize(stmt); throw failure() }
    }
    return stmt
  }
  package func rows(_ sql: String, _ values: [String?] = []) throws -> [[String?]] {
    let stmt = try prepare(sql, values)
    defer { sqlite3_finalize(stmt) }
    var result: [[String?]] = []
    while true {
      let code = sqlite3_step(stmt)
      if code == SQLITE_DONE { return result }
      guard code == SQLITE_ROW else { throw failure() }
      result.append((0..<sqlite3_column_count(stmt)).map { index in
        sqlite3_column_type(stmt, index) == SQLITE_NULL ? nil
          : String(cString: sqlite3_column_text(stmt, index))
      })
    }
  }
  package func scalar(_ sql: String, _ values: [String?] = []) throws -> String? { try rows(sql, values).first?.first ?? nil }
  package func encode<T: Encodable>(_ value: T) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }
  package func decode<T: Decodable>(_ type: T.Type, _ value: String?) throws -> T {
    guard let value else { throw DrawingLibraryDatabaseError.database("required payload missing") }
    return try JSONDecoder().decode(type, from: Data(value.utf8))
  }
  /// A synchronous, nonescaping operation owns one connection and lease. Its
  /// trusted statements must not COMMIT/END the transaction themselves.
  package func transaction<T>(_ operation: () throws -> T) throws -> T {
    guard !guardedTransaction, sqlite3_get_autocommit(db) != 0 else {
      throw DrawingLibraryDatabaseError.database("Nested catalog transactions are unsupported")
    }
    try execute("BEGIN IMMEDIATE") // Full actual-file/root/lock/marker proof.
    guardedTransaction = true
    defer { guardedTransaction = false }
    var committed = false
    do {
      let value = try operation()
      try injectFault?(.beforeCommit)
      guard sqlite3_get_autocommit(db) == 0 else { throw DrawingLibraryDatabaseError.database("Guarded catalog transaction was lost") }
      try assertSelectedFile()
      try executeOnConnection("COMMIT")
      committed = true
      guardedTransaction = false
      try assertSelectedFile()
      try injectFault?(.afterCommit)
      return value
    } catch {
      if !committed, sqlite3_get_autocommit(db) == 0 { try? executeOnConnection("ROLLBACK") }
      throw error
    }
  }
  package func integrityCheck() throws {
    guard try scalar("PRAGMA integrity_check") == "ok", try rows("PRAGMA foreign_key_check").isEmpty else {
      throw DrawingLibraryDatabaseError.database("integrity or foreign key check failed")
    }
  }
  package var generation: DrawingLibraryGeneration {
    get throws {
      .init(revision: Int64(try scalar("SELECT value FROM state WHERE key='revision'") ?? "0") ?? 0)
    }
  }
  package func setState(_ key: String, _ value: String?) throws {
    if let value { try execute("INSERT INTO state(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [key,value]) }
    else { try execute("DELETE FROM state WHERE key=?", [key]) }
  }
  package func bumpRevision() throws { try setState("revision", String((try generation).revision + 1)) }

  package func backup(to destination: URL) throws {
    try assertSelectedFile()
    let destinationLease = try DrawingLibraryWriterLease(root: destination.deletingLastPathComponent())
    try destinationLease.assertMatches(root: destination.deletingLastPathComponent())
    defer { withExtendedLifetime(destinationLease) {} }
    var target: OpaquePointer?
    guard sqlite3_open_v2(destination.path,&target,SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,nil) == SQLITE_OK, let target else { throw failure() }
    defer { sqlite3_close(target) }
    func targetForeignKeysEnabled() -> Bool {
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(target,"PRAGMA foreign_keys",-1,&statement,nil) == SQLITE_OK,let statement else { return false }
      defer { sqlite3_finalize(statement) }
      return sqlite3_step(statement) == SQLITE_ROW && sqlite3_column_int(statement,0) == 1
    }
    guard sqlite3_exec(target,"PRAGMA foreign_keys=ON",nil,nil,nil) == SQLITE_OK,targetForeignKeysEnabled() else {
      throw DrawingLibraryDatabaseError.database("backup destination foreign key enforcement unavailable")
    }
    guard let backup = sqlite3_backup_init(target,"main",db,"main") else { throw failure() }
    let code = sqlite3_backup_step(backup,-1);let finish = sqlite3_backup_finish(backup)
    guard code == SQLITE_DONE,finish == SQLITE_OK else { throw DrawingLibraryDatabaseError.database("backup failed") }
    guard targetForeignKeysEnabled() else { throw DrawingLibraryDatabaseError.database("backup destination foreign key enforcement changed") }
  }

  private static let schema = """
  CREATE TABLE state(key TEXT PRIMARY KEY,value TEXT NOT NULL);
  INSERT INTO state(key,value) VALUES('profile','adaptiveplotter.drawing-library/1');
  CREATE TABLE dx_source_summary(kind TEXT NOT NULL,namespace TEXT NOT NULL,identity TEXT NOT NULL,digest TEXT NOT NULL,payload TEXT NOT NULL,known_date INTEGER NOT NULL,chronology REAL,photo_namespace TEXT,photo_identity TEXT,photo_digest TEXT,PRIMARY KEY(kind,namespace,identity));
  CREATE TABLE dx_photo_metadata(namespace TEXT NOT NULL,identity TEXT NOT NULL,digest TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(namespace,identity));
  PRAGMA user_version=11;
  """
}
