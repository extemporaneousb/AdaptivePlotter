import CSQLite
import CryptoKit
import Foundation
import PlotterModel

/// Ledger identity is the canonical domain RunID; no runtime string identity
/// or DTO mirror is admitted at the persistence boundary.
public typealias LedgerRunID = RunID

public struct LedgerEvent: Codable, Hashable, Sendable {
  public let runID: LedgerRunID
  public let sequence: Int64
  public let timestamp: RuntimeTimestamp
  public let kind: String
  public let schemaVersion: Int
  public let payload: Data
  public let payloadSHA256: String

  public init(
    runID: LedgerRunID,
    sequence: Int64,
    timestamp: RuntimeTimestamp,
    kind: String,
    schemaVersion: Int,
    payload: Data,
    payloadSHA256: String
  ) {
    self.runID = runID
    self.sequence = sequence
    self.timestamp = timestamp
    self.kind = kind
    self.schemaVersion = schemaVersion
    self.payload = Data(payload)
    self.payloadSHA256 = payloadSHA256
  }
}

public enum LedgerCommandLifecycle: String, Codable, Hashable, Sendable {
  case prepared
  case written
  case completed
  case failed
  case ambiguous
}

public struct LedgerArtifactReference: Codable, Hashable, Sendable {
  public let sha256: String
  public let byteCount: Int64
  public let mediaType: String
  public let relativePath: String

  public init(sha256: String, byteCount: Int64, mediaType: String, relativePath: String) {
    self.sha256 = sha256
    self.byteCount = byteCount
    self.mediaType = mediaType
    self.relativePath = relativePath
  }
}

public struct UnresolvedCommandIntent: Codable, Hashable, Sendable {
  public let commandID: UUID
  public let runID: LedgerRunID
  public let sequence: Int64
  public let query: PassiveQuery
  public let wireBytes: Data
  public let lifecycle: LedgerCommandLifecycle
}

public struct LedgerRunSummary: Codable, Hashable, Sendable {
  public let runID: LedgerRunID
  public let createdAt: RuntimeTimestamp
  public let buildID: String

  public init(runID: LedgerRunID, createdAt: RuntimeTimestamp, buildID: String) {
    self.runID = runID
    self.createdAt = createdAt
    self.buildID = buildID
  }
}

public struct LedgerExportReceipt: Codable, Hashable, Sendable {
  public let databaseURL: URL
  public let databaseSHA256: String
  public let requiredArtifactsNotIncluded: [LedgerArtifactReference]

  public var isCompleteRunBundle: Bool { requiredArtifactsNotIncluded.isEmpty }
}

public enum RunLedgerError: Error, Equatable, Sendable {
  case openFailed(code: Int32, message: String)
  case sqlite(code: Int32, message: String, operation: String)
  case closed
  case runNotFound(LedgerRunID)
  case commandNotPrepared(UUID)
  case invalidArtifactHash(String)
  case exportDestinationIsSource
  case exportFailed(code: Int32, message: String)
  case payloadCorruption(runID: LedgerRunID, sequence: Int64)
  case unsupportedSchemaVersion(Int32)
  case malformedRunIdentifier(String)
  case malformedCommandIdentifier(runID: LedgerRunID, sequence: Int64, value: String)
  case malformedCommandQuery(runID: LedgerRunID, sequence: Int64, value: String)
  case malformedCommandLifecycle(runID: LedgerRunID, sequence: Int64, value: String)
  case commandWireQueryMismatch(
    runID: LedgerRunID,
    sequence: Int64?,
    commandID: UUID,
    query: PassiveQuery
  )
  case commandWireHashMismatch(
    runID: LedgerRunID,
    sequence: Int64,
    expectedSHA256: String,
    actualSHA256: String
  )
}

/// Owns the C connection independently of actor teardown. The actor is the only
/// caller; the lock exists solely because ARC may release the final reference on
/// a nonisolated executor during teardown.
private final class SQLiteHandle: @unchecked Sendable {
  private let lock = NSLock()
  private var pointer: OpaquePointer?

  init(_ pointer: OpaquePointer) {
    self.pointer = pointer
  }

  func borrow() throws -> OpaquePointer {
    try lock.withLock {
      guard let pointer else { throw RunLedgerError.closed }
      return pointer
    }
  }

  func close() {
    let value = lock.withLock { () -> OpaquePointer? in
      let value = pointer
      pointer = nil
      return value
    }
    if let value { sqlite3_close(value) }
  }

  deinit { close() }
}

public actor RunLedger {
  private static let schemaVersion: Int32 = 1
  private let databaseURL: URL
  private var handle: SQLiteHandle?

  public init(databaseURL: URL) throws {
    try self.init(databaseURL: databaseURL, readOnly: false)
  }

  private init(databaseURL: URL, readOnly: Bool) throws {
    self.databaseURL = databaseURL.standardizedFileURL
    var opened: OpaquePointer?
    let flags =
      readOnly
      ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
      : SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
    let result = sqlite3_open_v2(databaseURL.path, &opened, flags, nil)
    guard result == SQLITE_OK, let opened else {
      let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown sqlite error"
      if let opened { sqlite3_close(opened) }
      throw RunLedgerError.openFailed(code: result, message: message)
    }
    do {
      if readOnly {
        try Self.validateSchema(opened)
        sqlite3_busy_timeout(opened, 2_000)
      } else {
        try Self.configure(opened)
        try Self.migrate(opened)
      }
      handle = SQLiteHandle(opened)
    } catch {
      sqlite3_close(opened)
      throw error
    }
  }

  public static func openReadOnly(databaseURL: URL) throws -> RunLedger {
    try RunLedger(databaseURL: databaseURL, readOnly: true)
  }

  public func close() {
    handle?.close()
    handle = nil
  }

  public func createRun(
    id: LedgerRunID = LedgerRunID(),
    buildID: String,
    createdAt: RuntimeTimestamp
  ) throws -> LedgerRunID {
    let db = try requireDatabase()
    let sql =
      "INSERT INTO run(id, created_monotonic_ns, created_wall_time, build_id, next_sequence) VALUES(?, ?, ?, ?, 1)"
    let statement = try prepare(sql, in: db)
    defer { sqlite3_finalize(statement) }
    bind(id.description, at: 1, to: statement)
    sqlite3_bind_int64(statement, 2, Int64(bitPattern: createdAt.monotonicNanoseconds))
    bind(Self.iso8601(createdAt.wallTime), at: 3, to: statement)
    bind(buildID, at: 4, to: statement)
    try stepDone(statement, operation: "create run", in: db)
    return id
  }

  @discardableResult
  public func appendEvent(
    runID: LedgerRunID,
    timestamp: RuntimeTimestamp,
    kind: String,
    schemaVersion: Int = 1,
    payload: Data
  ) throws -> LedgerEvent {
    let db = try requireDatabase()
    try execute("BEGIN IMMEDIATE", in: db)
    do {
      let sequence = try allocateSequence(runID: runID, in: db)
      let digest = Self.sha256Hex(payload)
      let sql =
        "INSERT INTO event(run_id, sequence, monotonic_ns, wall_time, kind, schema_version, payload, payload_sha256) VALUES(?, ?, ?, ?, ?, ?, ?, ?)"
      let statement = try prepare(sql, in: db)
      defer { sqlite3_finalize(statement) }
      bind(runID.description, at: 1, to: statement)
      sqlite3_bind_int64(statement, 2, sequence)
      sqlite3_bind_int64(statement, 3, Int64(bitPattern: timestamp.monotonicNanoseconds))
      bind(Self.iso8601(timestamp.wallTime), at: 4, to: statement)
      bind(kind, at: 5, to: statement)
      sqlite3_bind_int(statement, 6, Int32(schemaVersion))
      bind(payload, at: 7, to: statement)
      bind(digest, at: 8, to: statement)
      try stepDone(statement, operation: "append event", in: db)
      try execute("COMMIT", in: db)
      return LedgerEvent(
        runID: runID,
        sequence: sequence,
        timestamp: timestamp,
        kind: kind,
        schemaVersion: schemaVersion,
        payload: payload,
        payloadSHA256: digest
      )
    } catch {
      try? execute("ROLLBACK", in: db)
      throw error
    }
  }

  public func prepareCommand(
    runID: LedgerRunID,
    commandID: UUID,
    query: PassiveQuery,
    bytes: Data,
    timestamp: RuntimeTimestamp
  ) throws {
    guard bytes == query.wireBytes else {
      throw RunLedgerError.commandWireQueryMismatch(
        runID: runID,
        sequence: nil,
        commandID: commandID,
        query: query
      )
    }
    let db = try requireDatabase()
    try execute("BEGIN IMMEDIATE", in: db)
    do {
      let sequence = try allocateSequence(runID: runID, in: db)
      let digest = Self.sha256Hex(bytes)
      let sql =
        "INSERT INTO command(id, run_id, sequence, query, wire_bytes, wire_sha256, lifecycle, prepared_monotonic_ns) VALUES(?, ?, ?, ?, ?, ?, ?, ?)"
      let statement = try prepare(sql, in: db)
      defer { sqlite3_finalize(statement) }
      bind(commandID.uuidString.lowercased(), at: 1, to: statement)
      bind(runID.description, at: 2, to: statement)
      sqlite3_bind_int64(statement, 3, sequence)
      bind(query.rawValue, at: 4, to: statement)
      bind(bytes, at: 5, to: statement)
      bind(digest, at: 6, to: statement)
      bind(LedgerCommandLifecycle.prepared.rawValue, at: 7, to: statement)
      sqlite3_bind_int64(statement, 8, Int64(bitPattern: timestamp.monotonicNanoseconds))
      try stepDone(statement, operation: "prepare command", in: db)
      try execute("COMMIT", in: db)
    } catch {
      try? execute("ROLLBACK", in: db)
      throw error
    }
  }

  public func markCommandWritten(commandID: UUID, timestamp: RuntimeTimestamp) throws {
    try updateCommand(
      commandID: commandID,
      expected: .prepared,
      lifecycle: .written,
      timestampColumn: "written_monotonic_ns",
      timestamp: timestamp,
      outcome: nil
    )
  }

  public func markCommandOutcome(
    commandID: UUID,
    lifecycle: LedgerCommandLifecycle,
    outcome: String,
    timestamp: RuntimeTimestamp
  ) throws {
    guard lifecycle == .completed || lifecycle == .failed || lifecycle == .ambiguous else {
      throw RunLedgerError.commandNotPrepared(commandID)
    }
    try updateCommand(
      commandID: commandID,
      expected: .written,
      lifecycle: lifecycle,
      timestampColumn: "completed_monotonic_ns",
      timestamp: timestamp,
      outcome: outcome
    )
  }

  public func commandLifecycle(commandID: UUID) throws -> LedgerCommandLifecycle? {
    let db = try requireDatabase()
    let statement = try prepare("SELECT lifecycle FROM command WHERE id = ?", in: db)
    defer { sqlite3_finalize(statement) }
    bind(commandID.uuidString.lowercased(), at: 1, to: statement)
    let stepResult = sqlite3_step(statement)
    guard stepResult == SQLITE_ROW else {
      guard stepResult == SQLITE_DONE else {
        throw Self.sqliteError(db, operation: "read command lifecycle")
      }
      return nil
    }
    return LedgerCommandLifecycle(rawValue: text(statement, column: 0))
  }

  public func markCommandPossiblyWrittenAmbiguous(
    commandID: UUID,
    outcome: String,
    timestamp: RuntimeTimestamp
  ) throws {
    let db = try requireDatabase()
    let sql =
      "UPDATE command SET lifecycle = ?, completed_monotonic_ns = ?, outcome = ? WHERE id = ? AND lifecycle IN (?, ?)"
    let statement = try prepare(sql, in: db)
    defer { sqlite3_finalize(statement) }
    bind(LedgerCommandLifecycle.ambiguous.rawValue, at: 1, to: statement)
    sqlite3_bind_int64(statement, 2, Int64(bitPattern: timestamp.monotonicNanoseconds))
    bind(outcome, at: 3, to: statement)
    bind(commandID.uuidString.lowercased(), at: 4, to: statement)
    bind(LedgerCommandLifecycle.prepared.rawValue, at: 5, to: statement)
    bind(LedgerCommandLifecycle.written.rawValue, at: 6, to: statement)
    try stepDone(statement, operation: "mark possibly written command ambiguous", in: db)
    guard sqlite3_changes(db) == 1 else { throw RunLedgerError.commandNotPrepared(commandID) }
  }

  public func unresolvedCommandIntents(runID: LedgerRunID) throws -> [UnresolvedCommandIntent] {
    let db = try requireDatabase()
    let sql =
      "SELECT id, sequence, query, wire_bytes, wire_sha256, lifecycle FROM command WHERE run_id = ? ORDER BY sequence"
    let statement = try prepare(sql, in: db)
    defer { sqlite3_finalize(statement) }
    bind(runID.description, at: 1, to: statement)
    var values: [UnresolvedCommandIntent] = []
    while true {
      let stepResult = sqlite3_step(statement)
      guard stepResult == SQLITE_ROW else {
        guard stepResult == SQLITE_DONE else {
          throw Self.sqliteError(db, operation: "read unresolved command intents")
        }
        break
      }
      let sequence = sqlite3_column_int64(statement, 1)
      let commandIDText = text(statement, column: 0)
      guard let commandID = UUID(uuidString: commandIDText) else {
        throw RunLedgerError.malformedCommandIdentifier(
          runID: runID,
          sequence: sequence,
          value: commandIDText
        )
      }
      let queryText = text(statement, column: 2)
      guard let query = PassiveQuery(rawValue: queryText) else {
        throw RunLedgerError.malformedCommandQuery(
          runID: runID,
          sequence: sequence,
          value: queryText
        )
      }
      let lifecycleText = text(statement, column: 5)
      guard let lifecycle = LedgerCommandLifecycle(rawValue: lifecycleText) else {
        throw RunLedgerError.malformedCommandLifecycle(
          runID: runID,
          sequence: sequence,
          value: lifecycleText
        )
      }
      let wireBytes = blob(statement, column: 3)
      let expectedSHA256 = text(statement, column: 4)
      let actualSHA256 = Self.sha256Hex(wireBytes)
      guard expectedSHA256 == actualSHA256 else {
        throw RunLedgerError.commandWireHashMismatch(
          runID: runID,
          sequence: sequence,
          expectedSHA256: expectedSHA256,
          actualSHA256: actualSHA256
        )
      }
      guard wireBytes == query.wireBytes else {
        throw RunLedgerError.commandWireQueryMismatch(
          runID: runID,
          sequence: sequence,
          commandID: commandID,
          query: query
        )
      }
      guard lifecycle == .prepared || lifecycle == .written || lifecycle == .ambiguous else {
        continue
      }
      values.append(
        UnresolvedCommandIntent(
          commandID: commandID,
          runID: runID,
          sequence: sequence,
          query: query,
          wireBytes: wireBytes,
          lifecycle: lifecycle
        )
      )
    }
    return values
  }

  public func runSummaries() throws -> [LedgerRunSummary] {
    let db = try requireDatabase()
    let statement = try prepare(
      "SELECT id, created_monotonic_ns, created_wall_time, build_id FROM run ORDER BY created_monotonic_ns, id",
      in: db
    )
    defer { sqlite3_finalize(statement) }
    var summaries: [LedgerRunSummary] = []
    while true {
      let stepResult = sqlite3_step(statement)
      guard stepResult == SQLITE_ROW else {
        guard stepResult == SQLITE_DONE else {
          throw Self.sqliteError(db, operation: "read run summaries")
        }
        break
      }
      let idText = text(statement, column: 0)
      guard let uuid = UUID(uuidString: idText) else {
        throw RunLedgerError.malformedRunIdentifier(idText)
      }
      summaries.append(
        LedgerRunSummary(
          runID: LedgerRunID(uuid),
          createdAt: RuntimeTimestamp(
            monotonicNanoseconds: UInt64(bitPattern: sqlite3_column_int64(statement, 1)),
            wallTime: Self.parseISO8601(text(statement, column: 2))
          ),
          buildID: text(statement, column: 3)
        )
      )
    }
    return summaries
  }

  public func events(runID: LedgerRunID) throws -> [LedgerEvent] {
    let db = try requireDatabase()
    let sql =
      "SELECT sequence, monotonic_ns, wall_time, kind, schema_version, payload, payload_sha256 FROM event WHERE run_id = ? ORDER BY sequence"
    let statement = try prepare(sql, in: db)
    defer { sqlite3_finalize(statement) }
    bind(runID.description, at: 1, to: statement)
    var result: [LedgerEvent] = []
    while true {
      let stepResult = sqlite3_step(statement)
      guard stepResult == SQLITE_ROW else {
        guard stepResult == SQLITE_DONE else {
          throw Self.sqliteError(db, operation: "read events")
        }
        break
      }
      let sequence = sqlite3_column_int64(statement, 0)
      let monotonic = UInt64(bitPattern: sqlite3_column_int64(statement, 1))
      let wall = Self.parseISO8601(text(statement, column: 2))
      let payload = blob(statement, column: 5)
      let storedHash = text(statement, column: 6)
      guard Self.sha256Hex(payload) == storedHash else {
        throw RunLedgerError.payloadCorruption(runID: runID, sequence: sequence)
      }
      result.append(
        LedgerEvent(
          runID: runID,
          sequence: sequence,
          timestamp: RuntimeTimestamp(monotonicNanoseconds: monotonic, wallTime: wall),
          kind: text(statement, column: 3),
          schemaVersion: Int(sqlite3_column_int(statement, 4)),
          payload: payload,
          payloadSHA256: storedHash
        )
      )
    }
    return result
  }

  public func registerArtifact(_ artifact: LedgerArtifactReference) throws {
    guard artifact.sha256.count == 64, artifact.sha256.allSatisfy({ $0.isHexDigit }) else {
      throw RunLedgerError.invalidArtifactHash(artifact.sha256)
    }
    let base = databaseURL.deletingLastPathComponent().standardizedFileURL
    let artifactURL = base.appendingPathComponent(artifact.relativePath).standardizedFileURL
    guard artifactURL.path.hasPrefix(base.path + "/"),
      let data = try? Data(contentsOf: artifactURL, options: [.mappedIfSafe]),
      data.count == artifact.byteCount,
      Self.sha256Hex(data) == artifact.sha256.lowercased()
    else {
      throw RunLedgerError.invalidArtifactHash(artifact.sha256)
    }
    try insertArtifactRecord(artifact)
  }

  /// Writes content bytes on the same volume, synchronizes the temporary
  /// file, atomically renames it, then records the content-addressed metadata.
  public func storeArtifact(data: Data, mediaType: String) throws -> LedgerArtifactReference {
    _ = try requireDatabase()
    let digest = Self.sha256Hex(data)
    let base = databaseURL.deletingLastPathComponent()
    let evidenceDirectory = base.appendingPathComponent("evidence", isDirectory: true)
    try FileManager.default.createDirectory(
      at: evidenceDirectory,
      withIntermediateDirectories: true
    )
    let destination = evidenceDirectory.appendingPathComponent("sha256-\(digest)")
    if FileManager.default.fileExists(atPath: destination.path) {
      let existing = try Data(contentsOf: destination, options: [.mappedIfSafe])
      guard existing.count == data.count, Self.sha256Hex(existing) == digest else {
        throw RunLedgerError.invalidArtifactHash(digest)
      }
    } else {
      let temporary = evidenceDirectory.appendingPathComponent(".tmp-\(UUID().uuidString)")
      defer { try? FileManager.default.removeItem(at: temporary) }
      try data.write(to: temporary, options: [.withoutOverwriting])
      let handle = try FileHandle(forWritingTo: temporary)
      try handle.synchronize()
      try handle.close()
      try FileManager.default.moveItem(at: temporary, to: destination)
    }
    let artifact = LedgerArtifactReference(
      sha256: digest,
      byteCount: Int64(data.count),
      mediaType: mediaType,
      relativePath: "evidence/sha256-\(digest)"
    )
    try insertArtifactRecord(artifact)
    return artifact
  }

  private func insertArtifactRecord(_ artifact: LedgerArtifactReference) throws {
    let db = try requireDatabase()
    let sql =
      "INSERT INTO artifact(sha256, byte_count, media_type, relative_path) VALUES(?, ?, ?, ?) ON CONFLICT(sha256) DO UPDATE SET byte_count=excluded.byte_count, media_type=excluded.media_type, relative_path=excluded.relative_path"
    let statement = try prepare(sql, in: db)
    defer { sqlite3_finalize(statement) }
    bind(artifact.sha256.lowercased(), at: 1, to: statement)
    sqlite3_bind_int64(statement, 2, artifact.byteCount)
    bind(artifact.mediaType, at: 3, to: statement)
    bind(artifact.relativePath, at: 4, to: statement)
    try stepDone(statement, operation: "register artifact", in: db)
  }

  public func referenceArtifact(runID: LedgerRunID, eventSequence: Int64, sha256: String) throws {
    let db = try requireDatabase()
    let sql =
      "INSERT INTO artifact_reference(run_id, event_sequence, artifact_sha256) VALUES(?, ?, ?)"
    let statement = try prepare(sql, in: db)
    defer { sqlite3_finalize(statement) }
    bind(runID.description, at: 1, to: statement)
    sqlite3_bind_int64(statement, 2, eventSequence)
    bind(sha256.lowercased(), at: 3, to: statement)
    try stepDone(statement, operation: "reference artifact", in: db)
  }

  public func exportDatabase(to destinationURL: URL) throws -> LedgerExportReceipt {
    let source = try requireDatabase()
    let destination = destinationURL.standardizedFileURL
    guard destination != databaseURL else { throw RunLedgerError.exportDestinationIsSource }

    var exported: OpaquePointer?
    let openResult = sqlite3_open_v2(
      destination.path,
      &exported,
      SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
      nil
    )
    guard openResult == SQLITE_OK, let exported else {
      let message =
        exported.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown sqlite export error"
      if let exported { sqlite3_close(exported) }
      throw RunLedgerError.exportFailed(code: openResult, message: message)
    }
    defer { sqlite3_close(exported) }
    guard let backup = sqlite3_backup_init(exported, "main", source, "main") else {
      throw RunLedgerError.exportFailed(
        code: sqlite3_errcode(exported),
        message: String(cString: sqlite3_errmsg(exported))
      )
    }
    let stepResult = sqlite3_backup_step(backup, -1)
    let finishResult = sqlite3_backup_finish(backup)
    guard stepResult == SQLITE_DONE, finishResult == SQLITE_OK else {
      throw RunLedgerError.exportFailed(
        code: finishResult == SQLITE_OK ? stepResult : finishResult,
        message: String(cString: sqlite3_errmsg(exported))
      )
    }
    let data = try Data(contentsOf: destination, options: [.mappedIfSafe])
    return LedgerExportReceipt(
      databaseURL: destination,
      databaseSHA256: Self.sha256Hex(data),
      requiredArtifactsNotIncluded: try artifacts(in: source)
    )
  }

  public func integrityCheck() throws -> Bool {
    let db = try requireDatabase()
    let statement = try prepare("PRAGMA integrity_check", in: db)
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { return false }
    return text(statement, column: 0) == "ok"
  }

  public static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func updateCommand(
    commandID: UUID,
    expected: LedgerCommandLifecycle,
    lifecycle: LedgerCommandLifecycle,
    timestampColumn: String,
    timestamp: RuntimeTimestamp,
    outcome: String?
  ) throws {
    let db = try requireDatabase()
    let sql =
      "UPDATE command SET lifecycle = ?, \(timestampColumn) = ?, outcome = ? WHERE id = ? AND lifecycle = ?"
    let statement = try prepare(sql, in: db)
    defer { sqlite3_finalize(statement) }
    bind(lifecycle.rawValue, at: 1, to: statement)
    sqlite3_bind_int64(statement, 2, Int64(bitPattern: timestamp.monotonicNanoseconds))
    if let outcome { bind(outcome, at: 3, to: statement) } else { sqlite3_bind_null(statement, 3) }
    bind(commandID.uuidString.lowercased(), at: 4, to: statement)
    bind(expected.rawValue, at: 5, to: statement)
    try stepDone(statement, operation: "update command lifecycle", in: db)
    guard sqlite3_changes(db) == 1 else { throw RunLedgerError.commandNotPrepared(commandID) }
  }

  private func allocateSequence(runID: LedgerRunID, in db: OpaquePointer) throws -> Int64 {
    let select = try prepare("SELECT next_sequence FROM run WHERE id = ?", in: db)
    bind(runID.description, at: 1, to: select)
    defer { sqlite3_finalize(select) }
    guard sqlite3_step(select) == SQLITE_ROW else { throw RunLedgerError.runNotFound(runID) }
    let sequence = sqlite3_column_int64(select, 0)

    let update = try prepare("UPDATE run SET next_sequence = ? WHERE id = ?", in: db)
    defer { sqlite3_finalize(update) }
    sqlite3_bind_int64(update, 1, sequence + 1)
    bind(runID.description, at: 2, to: update)
    try stepDone(update, operation: "advance run sequence", in: db)
    return sequence
  }

  private func artifacts(in db: OpaquePointer) throws -> [LedgerArtifactReference] {
    let statement = try prepare(
      "SELECT sha256, byte_count, media_type, relative_path FROM artifact ORDER BY sha256",
      in: db
    )
    defer { sqlite3_finalize(statement) }
    var values: [LedgerArtifactReference] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      values.append(
        LedgerArtifactReference(
          sha256: text(statement, column: 0),
          byteCount: sqlite3_column_int64(statement, 1),
          mediaType: text(statement, column: 2),
          relativePath: text(statement, column: 3)
        )
      )
    }
    return values
  }

  private func requireDatabase() throws -> OpaquePointer {
    guard let handle else { throw RunLedgerError.closed }
    return try handle.borrow()
  }

  private static func configure(_ db: OpaquePointer) throws {
    try executeStatic("PRAGMA journal_mode=WAL", in: db)
    try executeStatic("PRAGMA synchronous=FULL", in: db)
    try executeStatic("PRAGMA foreign_keys=ON", in: db)
    sqlite3_busy_timeout(db, 2_000)
  }

  private static func validateSchema(_ db: OpaquePointer) throws {
    let version = try readSchemaVersion(db)
    guard version == schemaVersion else {
      throw RunLedgerError.unsupportedSchemaVersion(version)
    }
  }

  private static func migrate(_ db: OpaquePointer) throws {
    let version = try readSchemaVersion(db)
    guard version <= schemaVersion else {
      throw RunLedgerError.unsupportedSchemaVersion(version)
    }
    if version == 0 {
      try executeStatic("BEGIN IMMEDIATE", in: db)
      do {
        try executeStatic(
          """
          CREATE TABLE run(
              id TEXT PRIMARY KEY,
              created_monotonic_ns INTEGER NOT NULL,
              created_wall_time TEXT NOT NULL,
              build_id TEXT NOT NULL,
              next_sequence INTEGER NOT NULL
          );
          CREATE TABLE event(
              run_id TEXT NOT NULL REFERENCES run(id),
              sequence INTEGER NOT NULL,
              monotonic_ns INTEGER NOT NULL,
              wall_time TEXT NOT NULL,
              kind TEXT NOT NULL,
              schema_version INTEGER NOT NULL,
              payload BLOB NOT NULL,
              payload_sha256 TEXT NOT NULL,
              PRIMARY KEY(run_id, sequence)
          );
          CREATE TABLE command(
              id TEXT PRIMARY KEY,
              run_id TEXT NOT NULL REFERENCES run(id),
              sequence INTEGER NOT NULL,
              query TEXT NOT NULL,
              wire_bytes BLOB NOT NULL,
              wire_sha256 TEXT NOT NULL,
              lifecycle TEXT NOT NULL,
              prepared_monotonic_ns INTEGER NOT NULL,
              written_monotonic_ns INTEGER,
              completed_monotonic_ns INTEGER,
              outcome TEXT,
              UNIQUE(run_id, sequence)
          );
          CREATE TABLE artifact(
              sha256 TEXT PRIMARY KEY,
              byte_count INTEGER NOT NULL,
              media_type TEXT NOT NULL,
              relative_path TEXT NOT NULL
          );
          CREATE TABLE artifact_reference(
              run_id TEXT NOT NULL,
              event_sequence INTEGER NOT NULL,
              artifact_sha256 TEXT NOT NULL REFERENCES artifact(sha256),
              PRIMARY KEY(run_id, event_sequence, artifact_sha256),
              FOREIGN KEY(run_id, event_sequence) REFERENCES event(run_id, sequence)
          );
          PRAGMA user_version = 1;
          """,
          in: db
        )
        try executeStatic("COMMIT", in: db)
      } catch {
        try? executeStatic("ROLLBACK", in: db)
        throw error
      }
    }
  }

  private static func readSchemaVersion(_ db: OpaquePointer) throws -> Int32 {
    var versionStatement: OpaquePointer?
    guard sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &versionStatement, nil) == SQLITE_OK,
      let versionStatement
    else {
      throw sqliteError(db, operation: "read schema version")
    }
    defer { sqlite3_finalize(versionStatement) }
    guard sqlite3_step(versionStatement) == SQLITE_ROW else {
      throw sqliteError(db, operation: "step schema version")
    }
    return sqlite3_column_int(versionStatement, 0)
  }

  private func prepare(_ sql: String, in db: OpaquePointer) throws -> OpaquePointer {
    var statement: OpaquePointer?
    let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
    guard result == SQLITE_OK, let statement else {
      throw Self.sqliteError(db, operation: "prepare")
    }
    return statement
  }

  private func execute(_ sql: String, in db: OpaquePointer) throws {
    try Self.executeStatic(sql, in: db)
  }

  private static func executeStatic(_ sql: String, in db: OpaquePointer) throws {
    var errorMessage: UnsafeMutablePointer<CChar>?
    let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
    guard result == SQLITE_OK else {
      let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
      sqlite3_free(errorMessage)
      throw RunLedgerError.sqlite(code: result, message: message, operation: "execute")
    }
  }

  private static func sqliteError(_ db: OpaquePointer, operation: String) -> RunLedgerError {
    RunLedgerError.sqlite(
      code: sqlite3_errcode(db),
      message: String(cString: sqlite3_errmsg(db)),
      operation: operation
    )
  }

  private func stepDone(_ statement: OpaquePointer, operation: String, in db: OpaquePointer) throws
  {
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw Self.sqliteError(db, operation: operation)
    }
  }

  private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) {
    sqlite3_bind_text(statement, index, value, -1, Self.sqliteTransient)
  }

  private func bind(_ value: Data, at index: Int32, to statement: OpaquePointer) {
    _ = value.withUnsafeBytes { bytes in
      sqlite3_bind_blob(
        statement, index, bytes.baseAddress, Int32(bytes.count), Self.sqliteTransient)
    }
  }

  private func text(_ statement: OpaquePointer, column: Int32) -> String {
    guard let value = sqlite3_column_text(statement, column) else { return "" }
    return String(cString: value)
  }

  private func blob(_ statement: OpaquePointer, column: Int32) -> Data {
    let count = Int(sqlite3_column_bytes(statement, column))
    guard count > 0, let value = sqlite3_column_blob(statement, column) else { return Data() }
    return Data(bytes: value, count: count)
  }

  private static var sqliteTransient: sqlite3_destructor_type {
    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  }

  private static func iso8601(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
  }

  private static func parseISO8601(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value) ?? Date(timeIntervalSince1970: 0)
  }
}
