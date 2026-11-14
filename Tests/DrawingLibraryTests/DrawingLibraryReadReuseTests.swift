@testable import DrawingLibrary
import CSQLite
import Foundation
import PlotterModel
import PortraitCore
import Testing

private extension DrawingLibrary {
  func setCatalogVersion(_ version: Int) throws {
    try libraryDatabase().execute("PRAGMA user_version=\(version)")
  }
  func readConnectionIdentity() throws -> ObjectIdentifier? {
    try commonReadDatabase().map(ObjectIdentifier.init)
  }

  func failReadAfterReplacingCatalog() throws -> Bool {
    let db = try #require(try commonReadDatabase())
    do {
      try db.readSnapshot { db in
        _ = try db.scalar("SELECT value FROM state WHERE key='profile'")
        try FileManager.default.moveItem(at: db.url, to: db.url.appendingPathExtension("held"))
      }
      Issue.record("A moved selected catalog must refuse its snapshot")
    } catch { }
    return db.isOutsideTransaction
  }
}

@Suite("Drawing Library read reuse", .serialized)
struct DrawingLibraryReadReuseTests {
  private func root() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("drawing-read-reuse-" + UUID().uuidString)
  }

  private func drawing() throws -> Drawing {
    let style = try StrokeStyle(nominalLineWidth: 0.8, penProfileID: PenProfileID(UUID()))
    return try Drawing(program: DrawingProgramCatalog.program(for: .line, style: style), input: .none, parent: .none,
      producer: DrawingProducerReceipt(id: "example.read-reuse", version: "1", recordJSON: Data("{}".utf8)))
  }

  @Test("One reader sees later commits, releases snapshots, and refuses reuse after close")
  func readerLifetime() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let writer = DrawingLibrary(directoryURL: directory), reader = DrawingLibrary(directoryURL: directory)
    let retained = try await writer.retain(drawing(), reason: "fixture")
    let first = try #require(try await reader.readConnectionIdentity())
    #expect(try await reader.drawings().entries.count == 1)
    try await writer.rename(retained.reference, title: "Later commit")
    #expect(try await reader.drawings().entries.first?.title == "Later commit")
    #expect(try await reader.readConnectionIdentity() == first)
    await reader.closeLibrary()
    await #expect(throws: (any Error).self) { try await reader.drawings() }
    try await writer.rename(retained.reference, title: "After reader close")
    await writer.closeLibrary()
  }

  @Test("A selection failure still releases the retained read transaction")
  func failedSnapshotRollsBackActualConnection() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let writer = DrawingLibrary(directoryURL: directory)
    _ = try await writer.retain(drawing(), reason: "fixture")
    await writer.closeLibrary()
    let reader = DrawingLibrary(directoryURL: directory)
    #expect(try await reader.failReadAfterReplacingCatalog())
    await #expect(throws: (any Error).self) { try await reader.drawings() }
    await reader.closeLibrary()
  }

  @Test("A reused read connection revalidates an externally changed schema")
  func changedSchemaRefuses() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let writer = DrawingLibrary(directoryURL: directory), reader = DrawingLibrary(directoryURL: directory)
    _ = try await writer.retain(drawing(), reason: "fixture")
    #expect(try await reader.drawings().entries.count == 1)
    try await writer.setCatalogVersion(99)
    await #expect(throws: (any Error).self) { try await reader.drawings() }
    try await writer.setCatalogVersion(12)
    #expect(try await reader.drawings().entries.count == 1)
    await reader.closeLibrary()
    await writer.closeLibrary()
  }

  @Test("WAL-only commits revalidate schema and profile even when the main file stat is unchanged")
  func walSchemaRefuses() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let writer = DrawingLibrary(directoryURL: directory)
    _ = try await writer.retain(drawing(), reason: "fixture")
    await writer.closeLibrary()
    let file = directory.appendingPathComponent("drawing-library.sqlite")
    var connection: OpaquePointer?
    #expect(sqlite3_open_v2(file.path, &connection, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
    let raw = try #require(connection)
    defer { sqlite3_close(raw) }
    // Journal-mode selection alone creates no WAL/SHM for a read-only VFS to
    // open. Commit the unchanged schema version before opening the reader.
    #expect(sqlite3_exec(raw, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; PRAGMA user_version=12", nil, nil, nil) == SQLITE_OK)
    let reader = DrawingLibrary(directoryURL: directory)
    #expect(try await reader.drawings().entries.count == 1)
    let before = try DrawingLibraryFileState(file)
    #expect(sqlite3_exec(raw, "PRAGMA user_version=99", nil, nil, nil) == SQLITE_OK)
    #expect(try DrawingLibraryFileState(file) == before)
    await #expect(throws: (any Error).self) { try await reader.drawings() }
    #expect(sqlite3_exec(raw, "PRAGMA user_version=12", nil, nil, nil) == SQLITE_OK)
    #expect(try await reader.drawings().entries.count == 1)
    #expect(sqlite3_exec(raw, "UPDATE state SET value='unsupported' WHERE key='profile'", nil, nil, nil) == SQLITE_OK)
    #expect(try DrawingLibraryFileState(file) == before)
    await #expect(throws: (any Error).self) { try await reader.drawings() }
    await reader.closeLibrary()
  }

  @Test("Reused statements clear old bindings, survive constraint failures, and release scalar read locks")
  func statementLifetime() throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let db = try DrawingLibraryDatabase(url: directory.appendingPathComponent("drawing-library.sqlite"))
    try db.execute("CREATE TABLE probe(key TEXT PRIMARY KEY,value TEXT)")
    try db.execute("INSERT INTO probe(key,value) VALUES(?,?)", ["first", "old"])
    #expect(throws: (any Error).self) { try db.execute("INSERT INTO probe(key,value) VALUES(?,?)", ["first", "collision"]) }
    try db.execute("INSERT INTO probe(key,value) VALUES(?,?)", ["second", nil])
    #expect(try db.scalar("SELECT value FROM probe WHERE key=?", ["first"]) == "old")
    #expect(try db.scalar("SELECT value FROM probe WHERE key=?", ["second"]) == nil)
    #expect(try db.scalar("SELECT value FROM probe WHERE key=?", ["missing"]) == nil)
    #expect(try db.scalar("SELECT key FROM probe ORDER BY key") == "first")
    let other = try DrawingLibraryDatabase(url: db.url, readOnly: true)
    #expect(try other.scalar("SELECT key FROM probe ORDER BY key") == "first")
    try db.execute("UPDATE probe SET value=? WHERE key=?", ["after scalar", "first"])
    #expect(try other.scalar("SELECT value FROM probe WHERE key=?", ["first"]) == "after scalar")
    for index in 0..<96 { #expect(try db.scalar("SELECT \(index)") == String(index)) }
    #expect(db.cachedStatementCount <= 64)
    #expect(try db.scalar("SELECT value FROM probe WHERE key=?", ["first"]) == "after scalar")
  }

  @Test("Canonical marker fast path retains strict fallback validation")
  func markerValidation() throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let db = try DrawingLibraryDatabase(url: directory.appendingPathComponent("drawing-library.sqlite"))
    let marker = directory.appendingPathComponent("drawing-authority.json")
    for bytes in [LibraryExchangeCatalogSelection.markerBytes,
      Data("{ \"catalog\": \"drawing-library.sqlite\", \"version\": 1 }\n".utf8)] {
      try bytes.write(to: marker)
      #expect(try LibraryExchangeCatalogSelection.validate(root: directory, database: db.url))
    }
    for text in ["{\"version\":1,\"version\":1,\"catalog\":\"drawing-library.sqlite\"}",
      "{\"version\":1,\"catalog\":\"other.sqlite\"}",
      "{\"version\":1,\"catalog\":\"drawing-library.sqlite\",\"extra\":0}"] {
      try Data(text.utf8).write(to: marker)
      #expect(throws: (any Error).self) { try LibraryExchangeCatalogSelection.validate(root: directory, database: db.url) }
    }
  }
}
