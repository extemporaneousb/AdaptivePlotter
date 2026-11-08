import Foundation
import DrawingLibrary
import Testing

@Suite("Drawing Library transaction ownership")
struct DrawingLibraryDatabaseTests {
  private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("portrait-sql-"+UUID().uuidString) }

  @Test("Synchronous transaction guards are bounded, nesting refuses, throws rollback, and after-COMMIT remains uncertain")
  func transactionOwnershipScope() throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let db = try DrawingLibraryDatabase(url: directory.appendingPathComponent("drawing-library.sqlite"))
    for count in [1, 100] {
      let before = db.selectedFileValidationCount
      try db.transaction {
        #expect(throws: (any Error).self) { try db.transaction { try db.setState("nested", "must not publish") } }
        for value in 0..<count { try db.setState("probe", String(value)) }
      }
      #expect(db.selectedFileValidationCount - before == 3)
    }
    enum Abort: Error { case requested }
    #expect(throws: Abort.self) { try db.transaction { try db.setState("probe", "rolled back"); throw Abort.requested } }
    #expect(try db.scalar("SELECT value FROM state WHERE key='probe'") == "99")
    try db.execute("BEGIN")
    #expect(throws: (any Error).self) { try db.transaction { try db.setState("nested", "raw transaction") } }
    try db.setState("raw", "caller still owns transaction")
    try db.execute("ROLLBACK")
    #expect(try db.scalar("SELECT value FROM state WHERE key='raw'") == nil)
    db.injectFault = { if $0 == .afterCommit { throw Abort.requested } }
    #expect(throws: Abort.self) { try db.transaction { try db.setState("probe", "committed despite response") } }
    #expect(try db.scalar("SELECT value FROM state WHERE key='probe'") == "committed despite response")
    db.injectFault = nil
    try db.transaction { try db.setState("probe", "next transaction works") }
    let before = db.selectedFileValidationCount
    try db.setState("outside", "fully guarded")
    #expect(db.selectedFileValidationCount - before == 1)
  }

  @Test("Rolled back and SQLite auto-aborted guarded scopes refuse later autocommitted statements")
  func transactionOwnershipScopeLost() throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let db = try DrawingLibraryDatabase(url: directory.appendingPathComponent("drawing-library.sqlite"))
    try db.setState("probe", "original")
    for automatic in [false, true] {
      var scopeError: (any Error)?
      do {
        try db.transaction {
          if automatic {
            #expect(throws: (any Error).self) { try db.execute("INSERT OR ROLLBACK INTO state(key,value) VALUES('probe','collision')") }
          } else { try db.execute("ROLLBACK") }
          #expect(throws: (any Error).self) { try db.setState("must-not-autocommit", "forbidden") }
        }
      } catch { scopeError = error }
      #expect(scopeError != nil)
      #expect(try db.scalar("SELECT value FROM state WHERE key='must-not-autocommit'") == nil)
      #expect(try db.scalar("SELECT value FROM state WHERE key='probe'") == "original")
      try db.transaction { try db.setState("recovered", automatic ? "auto" : "explicit") }
    }
  }

  @Test("Before-COMMIT unlink or replacement refuses publication and rollback leaves selected replacement bytes untouched")
  func transactionOwnershipScopeSelection() throws {
    for replacement in [false, true] {
      let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
      let selected = directory.appendingPathComponent("current/drawing-library.sqlite")
      let prepared = directory.appendingPathComponent("replacement/drawing-library.sqlite")
      do { let other = try DrawingLibraryDatabase(url: prepared); try other.setState("probe", "replacement") }
      let replacementBytes = try Data(contentsOf: prepared)
      let db = try DrawingLibraryDatabase(url: selected)
      try db.setState("probe", "original")
      db.injectFault = { point in
        guard point == .beforeCommit else { return }
        try FileManager.default.moveItem(at: selected, to: selected.deletingLastPathComponent().appendingPathComponent("retained-original.sqlite"))
        if replacement { try replacementBytes.write(to: selected, options: .atomic) }
      }
      #expect(throws: (any Error).self) { try db.transaction { try db.setState("probe", "must not commit") } }
      if replacement {
        #expect(try Data(contentsOf: selected) == replacementBytes)
        let reader = try DrawingLibraryDatabase(url: selected, readOnly: true)
        #expect(try reader.scalar("SELECT value FROM state WHERE key='probe'") == "replacement")
      } else { #expect(!FileManager.default.fileExists(atPath: selected.path)) }
      #expect(throws: (any Error).self) { try db.setState("outside", "must refuse stale owner") }
    }
  }

}
