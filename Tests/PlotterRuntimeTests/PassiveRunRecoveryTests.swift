import Foundation
import PlotterModel
import PlotterRuntime
import Testing

@Suite("Passive run recovery")
struct PassiveRunRecoveryTests {
  @Test("completed prior passive run permits another powered probe")
  func completedRunIsClear() async throws {
    let fixture = try RecoveryFixture(filename: "passive-b.sqlite")
    let runID = try await fixture.createRun()
    try await fixture.appendLifecycle(runID: runID, finished: true)
    await fixture.ledger.close()

    let scan = await PassiveRunRecoveryScanner.scan(directoryURL: fixture.directory)

    #expect(scan.inspectedDatabaseURLs == [fixture.databaseURL.standardizedFileURL])
    #expect(scan.issues.isEmpty)
    #expect(!scan.blocksPoweredProbe)
  }

  @Test("unfinished and unresolved prior evidence blocks without mutation")
  func unresolvedRunBlocksReadOnly() async throws {
    let fixture = try RecoveryFixture(filename: "passive-a.sqlite")
    let runID = try await fixture.createRun()
    try await fixture.appendLifecycle(runID: runID, finished: false)
    let commandID = UUID()
    try await fixture.ledger.prepareCommand(
      runID: runID,
      commandID: commandID,
      query: .status,
      bytes: PassiveQuery.status.wireBytes,
      timestamp: RuntimeTimestamp(monotonicNanoseconds: 3)
    )
    await fixture.ledger.close()

    let scan = await PassiveRunRecoveryScanner.scan(directoryURL: fixture.directory)

    #expect(scan.blocksPoweredProbe)
    #expect(
      scan.issues.contains(.unfinishedRun(databaseURL: fixture.databaseURL, runID: runID))
    )
    #expect(
      scan.issues.contains(
        .unresolvedCommands(
          databaseURL: fixture.databaseURL,
          runID: runID,
          commandIDs: [commandID]
        )
      )
    )
    let reopened = try RunLedger.openReadOnly(databaseURL: fixture.databaseURL)
    #expect(try await reopened.commandLifecycle(commandID: commandID) == .prepared)
    await reopened.close()
  }

  @Test("scan order is deterministic and unsafe passive entries fail closed")
  func deterministicAndUnsafeEntry() async throws {
    let fixture = try RecoveryFixture(filename: "passive-z.sqlite")
    let runID = try await fixture.createRun()
    try await fixture.appendLifecycle(runID: runID, finished: true)
    await fixture.ledger.close()
    let second = try RecoveryFixture(directory: fixture.directory, filename: "passive-a.sqlite")
    let secondRunID = try await second.createRun()
    try await second.appendLifecycle(runID: secondRunID, finished: true)
    await second.ledger.close()
    let link = fixture.directory.appendingPathComponent("passive-link.sqlite")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.databaseURL)

    let scan = await PassiveRunRecoveryScanner.scan(directoryURL: fixture.directory)

    #expect(
      scan.inspectedDatabaseURLs.map(\.lastPathComponent) == [
        "passive-a.sqlite", "passive-link.sqlite", "passive-z.sqlite",
      ])
    #expect(
      scan.issues.contains {
        if case .unsafeDatabaseEntry(databaseURL: link, reason: _) = $0 { true } else { false }
      }
    )
  }

  @Test("empty prior ledger blocks recovery")
  func emptyLedgerBlocks() async throws {
    let fixture = try RecoveryFixture(filename: "passive-empty.sqlite")
    await fixture.ledger.close()

    let scan = await PassiveRunRecoveryScanner.scan(directoryURL: fixture.directory)

    #expect(scan.issues == [.emptyDatabase(databaseURL: fixture.databaseURL)])
  }

  @Test("malformed lifecycle payload is a typed recovery issue")
  func malformedLifecycleBlocks() async throws {
    let fixture = try RecoveryFixture(filename: "passive-malformed.sqlite")
    let runID = try await fixture.createRun()
    try await fixture.appendLifecycle(runID: runID, finished: true, corruptStartPayload: true)
    await fixture.ledger.close()

    let scan = await PassiveRunRecoveryScanner.scan(directoryURL: fixture.directory)

    #expect(
      scan.issues.contains {
        if case .malformedRunLifecycle(databaseURL: fixture.databaseURL, runID: runID, reason: _) =
          $0
        {
          true
        } else {
          false
        }
      }
    )
  }
}

private struct RecoveryFixture {
  let directory: URL
  let databaseURL: URL
  let ledger: RunLedger

  init(directory: URL? = nil, filename: String) throws {
    let selectedDirectory =
      directory
      ?? FileManager.default.temporaryDirectory
      .appendingPathComponent("adaptiveplotter-recovery-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: selectedDirectory, withIntermediateDirectories: true)
    self.directory = selectedDirectory.standardizedFileURL
    databaseURL = self.directory.appendingPathComponent(filename).standardizedFileURL
    ledger = try RunLedger(databaseURL: databaseURL)
  }

  func createRun() async throws -> LedgerRunID {
    try await ledger.createRun(
      buildID: "test-build",
      createdAt: RuntimeTimestamp(monotonicNanoseconds: 1)
    )
  }

  func appendLifecycle(
    runID: LedgerRunID,
    finished: Bool,
    corruptStartPayload: Bool = false
  ) async throws {
    let link = MachineLinkDescriptor(
      identifier: "test-link",
      displayName: "Test link",
      bsdPath: nil,
      transport: .simulated
    )
    let probeID = UUID()
    let startedAt = RuntimeTimestamp(monotonicNanoseconds: 2)
    let started = PassiveProbeStartedRecord(
      probeID: probeID,
      link: link,
      startedAt: startedAt,
      queries: PassiveQuery.allCases
    )
    _ = try await ledger.appendEvent(
      runID: runID,
      timestamp: startedAt,
      kind: "machine.passive_probe.started",
      schemaVersion: 1,
      payload: corruptStartPayload ? Data("not-json".utf8) : try JSONEncoder().encode(started)
    )
    if finished {
      let result = PassiveProbeResult(
        link: link,
        startedAt: startedAt,
        completedAt: RuntimeTimestamp(monotonicNanoseconds: 3),
        exchanges: [],
        blockers: [.transport("test fixture")]
      )
      _ = try await ledger.appendEvent(
        runID: runID,
        timestamp: RuntimeTimestamp(monotonicNanoseconds: 3),
        kind: "machine.passive_probe.finished",
        schemaVersion: 1,
        payload: try JSONEncoder().encode(
          PassiveProbeFinishedRecord(probeID: probeID, result: result))
      )
      let authority = try ExecutionAuthority(
        allowed: false,
        operation: nil,
        planID: nil,
        modelID: nil,
        stateEstimateID: nil,
        fixedSafetyPolicyID: SafetyPolicyID(),
        evidence: [],
        limits: try AuthorityLimits(
          maximumFeed: 0,
          maximumDistance: 0,
          maximumCommandHorizonNanoseconds: 0
        ),
        blockers: [try RunBlocker(code: "test.blocked", summary: "Test authority remains blocked.")]
      )
      let token = InterpreterTransitionToken(generation: 1)
      let transition = AuthorityTransitionRecord(
        reason: .passiveProbeCompleted,
        generation: 1,
        transitionToken: token,
        priorAuthority: authority,
        resultingAuthority: authority,
        unresolvedCommandIDs: [],
        machineBlockers: result.blockers
      )
      _ = try await ledger.appendEvent(
        runID: runID,
        timestamp: RuntimeTimestamp(monotonicNanoseconds: 4),
        kind: "runtime.authority.transition",
        schemaVersion: 1,
        payload: try JSONEncoder().encode(transition)
      )
    }
  }
}
