import Foundation
import PortraitCore

/// Declared portable snapshot facts, not a claim of physical execution or ink.
public struct DrawingLibraryAttemptEntry: Sendable {
  public let drawing: DrawingRef
  public let archive: UUID
  public let run: UUID
  public let snapshot: SnapshotRef
  public let environment: String
  public let state: String
  public let dispatch: String
  public let observation: String
  public let unsupportedReasons: [String]
  public let result: DrawingLibraryResultRef
}
public struct DrawingLibraryAttemptCursor: Sendable {
  let drawing: DrawingRef
  let generation: DrawingLibraryGeneration
  let archive: String
  let run: String
}
public struct DrawingLibraryAttemptPage: Sendable {
  public let entries: [DrawingLibraryAttemptEntry]
  public let next: DrawingLibraryAttemptCursor?
}
struct DrawingLibraryProjectedAttempt: Codable, Equatable {
  let drawing: DrawingRef
  let snapshot: SnapshotRef
  let environment: String
  let state: String
  let dispatch: String
  let observation: String
  let unsupportedReasons: [String]
}
extension DrawingLibrary {
  /// One row per exact archive/run, using only admitted snapshot targets. A
  /// result with several roots does not assign every attempt to every root.
  public func attempts(for drawing: DrawingRef, limit: Int = 50,
    after: DrawingLibraryAttemptCursor? = nil) throws -> DrawingLibraryAttemptPage {
    guard limit > 0, limit <= 500 else { throw DrawingLibraryError.invalidQuery }
    if let after, after.drawing != drawing { throw DrawingLibraryError.invalidQuery }
    guard let db = try commonReadDatabase() else { return .init(entries: [], next: nil) }
    return try commonSnapshot(db) {
      try assertSourceReference(.drawing(drawing), database: db)
      let generation = try db.generation
      if let after, after.generation != generation { throw DrawingLibraryError.staleSelection }
      let rows = try db.rows("SELECT a.payload,p.index_digest,p.package_digest,a.archive,a.run FROM dx_result_attempt a JOIN dx_result_publication p ON p.transaction_id=a.transaction_id WHERE a.issuer=? AND a.revision=? AND a.digest=? AND (a.archive,a.run)>(?,?) AND NOT EXISTS(SELECT 1 FROM dx_result_attempt b WHERE b.issuer=a.issuer AND b.revision=a.revision AND b.digest=a.digest AND b.archive=a.archive AND b.run=a.run AND (b.sequence>a.sequence OR (b.sequence=a.sequence AND b.transaction_id<a.transaction_id))) ORDER BY a.archive,a.run LIMIT ?", [drawing.issuer.uuidString.lowercased(), drawing.revision.uuidString.lowercased(), drawing.digest.description, after?.archive ?? "", after?.run ?? "", String(limit + 1)])
      let page = Array(rows.prefix(limit))
      let entries = try page.map { row -> DrawingLibraryAttemptEntry in
        let value = try db.decode(DrawingLibraryProjectedAttempt.self, row[0])
        guard value.drawing == drawing, let index = row[1], let package = row[2],
          value.snapshot.archive.uuidString.lowercased() == row[3], value.snapshot.run.uuidString.lowercased() == row[4] else { throw DrawingLibraryError.invalidIdentity }
        return .init(drawing: drawing, archive: value.snapshot.archive, run: value.snapshot.run,
          snapshot: value.snapshot, environment: value.environment, state: value.state, dispatch: value.dispatch, observation: value.observation,
          unsupportedReasons: value.unsupportedReasons,
          result: .init(indexDigest: try ExchangeDigest(index), packageDigest: try ExchangeDigest(package)))
      }
      let next: DrawingLibraryAttemptCursor? = rows.count > limit ? .init(drawing: drawing, generation: generation, archive: page.last![3]!, run: page.last![4]!) : nil
      return .init(entries: entries, next: next)
    }
  }
}
extension LibraryExchangeCatalog {
  func applyAttempts(_ attempts: [DrawingLibraryProjectedAttempt], transaction: String) throws {
    for value in attempts {
      let ref = value.drawing, snapshot = value.snapshot
      let payload = String(decoding: try DrawingArtifactCoding.encoder().encode(value), as: UTF8.self)
      try database.execute("INSERT INTO dx_result_attempt(transaction_id,issuer,revision,digest,archive,run,sequence,payload) VALUES(?,?,?,?,?,?,?,?)", [transaction, ref.issuer.uuidString.lowercased(), ref.revision.uuidString.lowercased(), ref.digest.description, snapshot.archive.uuidString.lowercased(), snapshot.run.uuidString.lowercased(), String(snapshot.sequence), payload])
    }
  }
  func verifyAttempts(_ attempts: [DrawingLibraryProjectedAttempt], transaction: String) throws {
    let stored = try database.rows("SELECT payload FROM dx_result_attempt WHERE transaction_id=? ORDER BY archive,run,sequence", [transaction]).map { try database.decode(DrawingLibraryProjectedAttempt.self, $0[0]) }
    let ordered = attempts.sorted {
      let a = $0.snapshot, b = $1.snapshot
      if a.archive != b.archive { return a.archive.uuidString.lowercased() < b.archive.uuidString.lowercased() }
      if a.run != b.run { return a.run.uuidString.lowercased() < b.run.uuidString.lowercased() }
      return a.sequence < b.sequence
    }
    guard stored == ordered else { throw LibraryExchangeCatalogError.invalidPublication("Result attempt projection missing or divergent") }
  }
}
