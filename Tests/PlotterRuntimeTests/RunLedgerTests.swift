import CSQLite
import Foundation
import PlotterRuntime
import Testing

@Suite("Run ledger")
struct RunLedgerTests {
  @Test("command preparation rejects bytes that do not match the closed query")
  func commandPreparationWireMismatch() async throws {
    let fixture = try LedgerFixture()
    let runID = try await fixture.ledger.createRun(
      buildID: "test-build",
      createdAt: RuntimeTimestamp(monotonicNanoseconds: 1)
    )
    let commandID = UUID()
    do {
      try await fixture.ledger.prepareCommand(
        runID: runID,
        commandID: commandID,
        query: .status,
        bytes: PassiveQuery.parserState.wireBytes,
        timestamp: RuntimeTimestamp(monotonicNanoseconds: 2)
      )
      Issue.record("mismatched wire bytes must not be prepared")
    } catch let error as RunLedgerError {
      #expect(
        error
          == .commandWireQueryMismatch(
            runID: runID,
            sequence: nil,
            commandID: commandID,
            query: .status
          )
      )
    }
  }

  @Test("reconciliation rejects wire bytes whose stored hash is stale")
  func commandWireHashCorruption() async throws {
    let fixture = try await preparedCommandFixture()
    try mutateDatabase(
      fixture.databaseURL,
      sql: "UPDATE command SET wire_bytes = x'24470a'"
    )
    let ledger = try RunLedger.openReadOnly(databaseURL: fixture.databaseURL)
    do {
      _ = try await ledger.unresolvedCommandIntents(runID: fixture.runID)
      Issue.record("wire corruption must not be returned")
    } catch let error as RunLedgerError {
      #expect(
        error
          == .commandWireHashMismatch(
            runID: fixture.runID,
            sequence: 1,
            expectedSHA256: RunLedger.sha256Hex(PassiveQuery.status.wireBytes),
            actualSHA256: RunLedger.sha256Hex(PassiveQuery.parserState.wireBytes)
          )
      )
    }
    await ledger.close()
  }

  @Test("reconciliation rejects self-consistent bytes for a different query")
  func commandWireQueryCorruption() async throws {
    let fixture = try await preparedCommandFixture()
    let replacement = PassiveQuery.parserState.wireBytes
    let hash = RunLedger.sha256Hex(replacement)
    try mutateDatabase(
      fixture.databaseURL,
      sql: "UPDATE command SET wire_bytes = x'24470a', wire_sha256 = '\(hash)'"
    )
    let ledger = try RunLedger.openReadOnly(databaseURL: fixture.databaseURL)
    do {
      _ = try await ledger.unresolvedCommandIntents(runID: fixture.runID)
      Issue.record("wire bytes for a different query must not be returned")
    } catch let error as RunLedgerError {
      #expect(
        error
          == .commandWireQueryMismatch(
            runID: fixture.runID,
            sequence: 1,
            commandID: fixture.commandID,
            query: .status
          )
      )
    }
    await ledger.close()
  }

  @Test("reconciliation rejects malformed command identity, query, and lifecycle")
  func malformedCommandRows() async throws {
    enum Mutation {
      case identifier
      case query
      case lifecycle
    }
    for mutation in [Mutation.identifier, .query, .lifecycle] {
      let fixture = try await preparedCommandFixture()
      let expected: RunLedgerError
      switch mutation {
      case .identifier:
        try mutateDatabase(fixture.databaseURL, sql: "UPDATE command SET id = 'not-a-uuid'")
        expected = .malformedCommandIdentifier(
          runID: fixture.runID,
          sequence: 1,
          value: "not-a-uuid"
        )
      case .query:
        try mutateDatabase(fixture.databaseURL, sql: "UPDATE command SET query = 'not-a-query'")
        expected = .malformedCommandQuery(
          runID: fixture.runID,
          sequence: 1,
          value: "not-a-query"
        )
      case .lifecycle:
        try mutateDatabase(fixture.databaseURL, sql: "UPDATE command SET lifecycle = 'unknown'")
        expected = .malformedCommandLifecycle(
          runID: fixture.runID,
          sequence: 1,
          value: "unknown"
        )
      }
      let ledger = try RunLedger.openReadOnly(databaseURL: fixture.databaseURL)
      do {
        _ = try await ledger.unresolvedCommandIntents(runID: fixture.runID)
        Issue.record("malformed command row must not be skipped")
      } catch let error as RunLedgerError {
        #expect(error == expected)
      }
      await ledger.close()
    }
  }

  @Test("event payload corruption fails closed on read")
  func payloadCorruption() async throws {
    let fixture = try LedgerFixture()
    let runID = try await fixture.ledger.createRun(
      buildID: "test-build",
      createdAt: RuntimeTimestamp(monotonicNanoseconds: 1)
    )
    _ = try await fixture.ledger.appendEvent(
      runID: runID,
      timestamp: RuntimeTimestamp(monotonicNanoseconds: 2),
      kind: "corrupt-me",
      payload: Data("original".utf8)
    )
    await fixture.ledger.close()

    var database: OpaquePointer?
    #expect(sqlite3_open(fixture.databaseURL.path, &database) == SQLITE_OK)
    let update = "UPDATE event SET payload = x'00' WHERE sequence = 1"
    #expect(sqlite3_exec(database, update, nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)

    let reopened = try RunLedger(databaseURL: fixture.databaseURL)
    do {
      _ = try await reopened.events(runID: runID)
      Issue.record("corrupt payload should not be returned")
    } catch let error as RunLedgerError {
      #expect(error == .payloadCorruption(runID: runID, sequence: 1))
    }
  }

  @Test("command intent is durable before write and lifecycle is monotonic")
  func commandIntent() async throws {
    let fixture = try LedgerFixture()
    let runID = try await fixture.ledger.createRun(
      buildID: "test-build",
      createdAt: RuntimeTimestamp(monotonicNanoseconds: 1)
    )
    let commandID = UUID()
    try await fixture.ledger.prepareCommand(
      runID: runID,
      commandID: commandID,
      query: .status,
      bytes: PassiveQuery.status.wireBytes,
      timestamp: RuntimeTimestamp(monotonicNanoseconds: 2)
    )
    #expect(try await fixture.ledger.commandLifecycle(commandID: commandID) == .prepared)
    let unresolvedPrepared = try await fixture.ledger.unresolvedCommandIntents(runID: runID)
    #expect(unresolvedPrepared.map(\.commandID) == [commandID])
    #expect(unresolvedPrepared.map(\.lifecycle) == [.prepared])
    try await fixture.ledger.markCommandWritten(
      commandID: commandID,
      timestamp: RuntimeTimestamp(monotonicNanoseconds: 3)
    )
    #expect(try await fixture.ledger.commandLifecycle(commandID: commandID) == .written)
    try await fixture.ledger.markCommandOutcome(
      commandID: commandID,
      lifecycle: .completed,
      outcome: "idle",
      timestamp: RuntimeTimestamp(monotonicNanoseconds: 4)
    )
    #expect(try await fixture.ledger.commandLifecycle(commandID: commandID) == .completed)
    #expect(try await fixture.ledger.unresolvedCommandIntents(runID: runID).isEmpty)
  }

  @Test("events are ordered, hashed, and survive reopen")
  func orderingAndReopen() async throws {
    let fixture = try LedgerFixture()
    let runID = try await fixture.ledger.createRun(
      buildID: "test-build",
      createdAt: RuntimeTimestamp(monotonicNanoseconds: 1)
    )
    let first = try await fixture.ledger.appendEvent(
      runID: runID,
      timestamp: RuntimeTimestamp(monotonicNanoseconds: 2),
      kind: "first",
      payload: Data("one".utf8)
    )
    let second = try await fixture.ledger.appendEvent(
      runID: runID,
      timestamp: RuntimeTimestamp(monotonicNanoseconds: 3),
      kind: "second",
      payload: Data("two".utf8)
    )
    #expect(first.sequence == 1)
    #expect(second.sequence == 2)
    #expect(first.payloadSHA256 == RunLedger.sha256Hex(Data("one".utf8)))
    await fixture.ledger.close()

    let reopened = try RunLedger(databaseURL: fixture.databaseURL)
    let events = try await reopened.events(runID: runID)
    #expect(events.map(\.kind) == ["first", "second"])
    #expect(try await reopened.integrityCheck())
  }

  @Test("sqlite backup export is WAL-safe and includes artifact manifest")
  func export() async throws {
    let fixture = try LedgerFixture()
    let runID = try await fixture.ledger.createRun(
      buildID: "test-build",
      createdAt: RuntimeTimestamp(monotonicNanoseconds: 1)
    )
    let event = try await fixture.ledger.appendEvent(
      runID: runID,
      timestamp: RuntimeTimestamp(monotonicNanoseconds: 2),
      kind: "frame",
      payload: Data("frame".utf8)
    )
    let bytes = Data("artifact".utf8)
    let artifact = try await fixture.ledger.storeArtifact(
      data: bytes,
      mediaType: "application/octet-stream"
    )
    try await fixture.ledger.referenceArtifact(
      runID: runID,
      eventSequence: event.sequence,
      sha256: artifact.sha256
    )
    let destination = fixture.directory.appendingPathComponent("export.sqlite")
    let receipt = try await fixture.ledger.exportDatabase(to: destination)
    #expect(receipt.databaseSHA256.count == 64)
    #expect(receipt.requiredArtifactsNotIncluded == [artifact])
    #expect(receipt.isCompleteRunBundle == false)
    let storedArtifactURL = fixture.directory.appendingPathComponent(artifact.relativePath)
    #expect(try Data(contentsOf: storedArtifactURL) == bytes)
    let exported = try RunLedger(databaseURL: destination)
    #expect(try await exported.events(runID: runID).count == 1)
    #expect(try await exported.integrityCheck())
  }
}

private struct PreparedCommandFixture {
  let databaseURL: URL
  let runID: LedgerRunID
  let commandID: UUID
}

private func preparedCommandFixture() async throws -> PreparedCommandFixture {
  let fixture = try LedgerFixture()
  let runID = try await fixture.ledger.createRun(
    buildID: "test-build",
    createdAt: RuntimeTimestamp(monotonicNanoseconds: 1)
  )
  let commandID = UUID()
  try await fixture.ledger.prepareCommand(
    runID: runID,
    commandID: commandID,
    query: .status,
    bytes: PassiveQuery.status.wireBytes,
    timestamp: RuntimeTimestamp(monotonicNanoseconds: 2)
  )
  await fixture.ledger.close()
  return PreparedCommandFixture(
    databaseURL: fixture.databaseURL,
    runID: runID,
    commandID: commandID
  )
}

private func mutateDatabase(_ databaseURL: URL, sql: String) throws {
  var database: OpaquePointer?
  guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
    throw RunLedgerError.openFailed(code: SQLITE_CANTOPEN, message: "test database open failed")
  }
  defer { sqlite3_close(database) }
  let result = sqlite3_exec(database, sql, nil, nil, nil)
  guard result == SQLITE_OK else {
    throw RunLedgerError.sqlite(
      code: result,
      message: String(cString: sqlite3_errmsg(database)),
      operation: "test mutation"
    )
  }
}

private struct LedgerFixture {
  let directory: URL
  let databaseURL: URL
  let ledger: RunLedger

  init() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("adaptiveplotter-ledger-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    databaseURL = directory.appendingPathComponent("run.sqlite")
    ledger = try RunLedger(databaseURL: databaseURL)
  }
}
