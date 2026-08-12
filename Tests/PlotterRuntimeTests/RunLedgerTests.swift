import CSQLite
import Foundation
import PlotterRuntime
import Testing

@Suite("Session log")
struct RunLedgerTests {
  @Test("events are ordered and survive reopen")
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
    await fixture.ledger.close()

    let reopened = try RunLedger(databaseURL: fixture.databaseURL)
    let events = try await reopened.events(runID: runID)
    #expect(events.map(\.kind) == ["first", "second"])
    #expect(try await reopened.integrityCheck())
  }

  @Test("corrupt event payload is reported when the log is inspected")
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
    #expect(sqlite3_exec(database, "UPDATE event SET payload = x'00'", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)

    let reopened = try RunLedger(databaseURL: fixture.databaseURL)
    await #expect(throws: RunLedgerError.payloadCorruption(runID: runID, sequence: 1)) {
      _ = try await reopened.events(runID: runID)
    }
  }

  @Test("typed workflow telemetry survives in the same ordered diagnostic ledger")
  func workflowTelemetryRoundTrip() async throws {
    let fixture = try LedgerFixture()
    let runID = try await fixture.ledger.createRun(
      buildID: "test-build",
      createdAt: RuntimeTimestamp(monotonicNanoseconds: 1)
    )
    let expected = WorkflowTelemetryEvent(
      operationID: UUID(),
      operation: .manualJog,
      phase: .intentAccepted,
      detail: "An ordinary operator-authored manual jog was admitted.",
      motionIntent: WorkflowMotionIntent(
        deltaXMM: -100,
        deltaYMM: 0,
        feedMMPerMinute: 500
      )
    )
    let payload = try JSONEncoder().encode(expected)

    _ = try await fixture.ledger.appendEvent(
      runID: runID,
      timestamp: RuntimeTimestamp(monotonicNanoseconds: 2),
      kind: "workflow.manualJog.intentAccepted",
      schemaVersion: WorkflowTelemetryEvent.schemaVersion,
      payload: payload
    )

    let events = try await fixture.ledger.events(runID: runID)
    let event = try #require(events.count == 1 ? events[0] : nil)
    #expect(event.kind == "workflow.manualJog.intentAccepted")
    #expect(event.schemaVersion == WorkflowTelemetryEvent.schemaVersion)
    #expect(try JSONDecoder().decode(WorkflowTelemetryEvent.self, from: event.payload) == expected)
  }
}

private struct LedgerFixture {
  let databaseURL: URL
  let ledger: RunLedger

  init() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("adaptiveplotter-session-log-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    databaseURL = directory.appendingPathComponent("run.sqlite")
    ledger = try RunLedger(databaseURL: databaseURL)
  }
}
