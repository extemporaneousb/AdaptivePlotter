import Foundation
import PlotterModel
@testable import PlotterRuntime
import Testing

@Suite("Durable accepted-artifact checkpoints")
struct AcceptedArtifactCheckpointTests {
  @Test("atomic store round-trips accepted artifacts and restores only accepted graph state")
  func roundTrip() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("checkpoint.json")
    let store = AcceptedArtifactCheckpointStore(fileURL: url)
    let checkpoint = try makeCheckpoint()

    try store.save(checkpoint)
    let restored = try loaded(store.load())

    #expect(restored == checkpoint)
    #expect(try restored.restoredLearningGraph().currentRevision(
      for: .boundarySideAggregate(.positiveX)
    )?.id == checkpoint.boundarySideAggregates[0].revisionID)
    #expect(try restored.restoredBoundaryHistories()[.positiveX]?.values.first?
      .includedSuccessfulAttempts.count == 1)
    let encoded = String(decoding: try Data(contentsOf: url), as: UTF8.self)
    #expect(!encoded.contains("activeStopTarget"))
    #expect(!encoded.contains("motionGuard"))
    #expect(!encoded.contains("pendingCommand"))
    #expect(!encoded.contains("DiscoveryTransaction"))
  }

  @Test("explicit clear removes the durable authority file idempotently")
  func clear() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("checkpoint.json")
    let store = AcceptedArtifactCheckpointStore(fileURL: url)

    try store.save(makeCheckpoint())
    #expect(FileManager.default.fileExists(atPath: url.path))
    try store.clear()
    #expect(!FileManager.default.fileExists(atPath: url.path))
    if case .absent = store.load() {
      // Expected.
    } else {
      Issue.record("Expected an absent checkpoint after explicit clear.")
    }
    try store.clear()
  }

  @Test("tampering is rejected before any artifact can be decoded")
  func corruptionRejected() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("checkpoint.json")
    let store = AcceptedArtifactCheckpointStore(fileURL: url)
    try store.save(makeCheckpoint())
    var bytes = try Data(contentsOf: url)
    bytes[bytes.count / 2] ^= 0x01
    try bytes.write(to: url)

    guard case .rejected = store.load() else {
      Issue.record("Expected a corrupted checkpoint to be rejected.")
      return
    }
  }

  @Test("controller settings and MPos must both revalidate")
  func controllerCompatibility() throws {
    let checkpoint = try makeCheckpoint()
    let exactContext = try ControllerCheckpointContext(
      probe: passiveProbe(position: try MachinePosition(x: 10, y: 0))
    )
    guard case .compatible(let residual) = checkpoint.compatibility(
      with: exactContext,
      currentPosition: try MachinePosition(x: 10.03, y: 0)
    ) else {
      Issue.record("Expected exact context and a 0.03 mm residual to revalidate.")
      return
    }
    #expect(abs(residual - 0.03) < 0.000_001)

    let changedSettings = try ControllerCheckpointContext(
      probe: passiveProbe(
        position: try MachinePosition(x: 10, y: 0),
        configuration: ["$100=81.000", "$101=80.000", "$110=900.000"]
      )
    )
    guard case .incompatible = checkpoint.compatibility(
      with: changedSettings,
      currentPosition: try MachinePosition(x: 10, y: 0)
    ) else {
      Issue.record("Expected changed controller settings to quarantine the checkpoint.")
      return
    }
    guard case .incompatible = checkpoint.compatibility(
      with: exactContext,
      currentPosition: try MachinePosition(x: 10.06, y: 0)
    ) else {
      Issue.record("Expected an out-of-tolerance MPos to quarantine the checkpoint.")
      return
    }
  }

  @Test("application-owned pen parser changes do not invalidate coordinate context")
  func penParserChangeIsCompatible() throws {
    let position = try MachinePosition(x: 10, y: 0)
    let baseline = try ControllerCheckpointContext(
      probe: passiveProbe(
        position: position,
        parserState: ["[GC:G0 G54 G17 G21 G90 G94 M5 M9 T0 F0 S0]"]
      )
    )
    let refreshed = try ControllerCheckpointContext(
      probe: passiveProbe(
        position: position,
        parserState: ["[GC:G1 G54 G17 G21 G90 G94 M3 M9 T0 F500 S40]"]
      )
    )

    let comparison = baseline.comparison(with: refreshed)

    #expect(comparison.isCompatible)
    #expect(comparison.differences.isEmpty)
    #expect(comparison.ignoredApplicationParserChanges.count == 1)
    #expect(comparison.actionableDescription.contains("application-owned parser modes"))
  }

  @Test("coordinate parser changes are rejected with a field-level difference")
  func coordinateParserChangeIsIncompatible() throws {
    let position = try MachinePosition(x: 10, y: 0)
    let baselineProbe = passiveProbe(
      position: position,
      parserState: ["[GC:G0 G54 G17 G21 G90 G94 M5 M9 T0 F0 S0]"]
    )
    let refreshedProbe = passiveProbe(
      position: position,
      parserState: ["[GC:G0 G55 G17 G21 G90 G94 M3 M9 T0 F0 S40]"]
    )
    let baseline = try ControllerContextBaseline(probe: baselineProbe)
    let refreshed = try ControllerContextBaseline(probe: refreshedProbe)

    let comparison = baseline.context.comparison(with: refreshed.context)

    #expect(!comparison.isCompatible)
    #expect(comparison.differences.map(\.field) == [.parserCoordinateState])
    #expect(comparison.actionableDescription.contains("G54"))
    #expect(comparison.actionableDescription.contains("G55"))
    #expect(baseline.probeID == baselineProbe.probeID)
    #expect(refreshed.probeID == refreshedProbe.probeID)
  }
}

private func loaded(
  _ result: AcceptedArtifactCheckpointLoadResult
) throws -> AcceptedMachineArtifactCheckpoint {
  switch result {
  case .loaded(let checkpoint): checkpoint
  case .absent:
    throw CheckpointTestError.unexpectedLoad("absent")
  case .rejected(let reason):
    throw CheckpointTestError.unexpectedLoad(reason)
  }
}

private enum CheckpointTestError: Error {
  case unexpectedLoad(String)
}

private func makeCheckpoint() throws -> AcceptedMachineArtifactCheckpoint {
  let sessionID = UUID()
  let coordinateRevision: UInt64 = 7
  let attemptID = ExerciseAttemptID()
  let revisionID = LearningArtifactRevisionID()
  let evidence = try BoundarySideAttemptEvidence(
    attemptID: attemptID,
    direction: .positiveX,
    controllerSessionID: sessionID,
    coordinateRevision: coordinateRevision,
    ownerID: BoundaryMotionOwnerID(),
    stopCapabilityID: UUID(),
    stopIntent: .operatorStop,
    finalPosition: MachinePosition(x: 10, y: 0),
    disposition: .succeeded
  )
  let compatibility = BoundaryNumericCompatibility(
    direction: .positiveX,
    controllerSessionID: sessionID,
    coordinateRevision: coordinateRevision,
    numericEstimatorRevision: "boundary-machine-coordinate-v1"
  ).attemptCompatibility
  var history = try ExerciseAttemptHistory<BoundarySideAttemptEvidence>(
    compatibility: compatibility
  )
  try history.record(
    ExerciseAttempt(
      id: attemptID,
      disposition: .succeeded,
      compatibility: compatibility,
      acceptedSequence: 1,
      value: evidence
    )
  )
  let aggregate = try BoundarySideAggregate(
    direction: .positiveX,
    revisionID: revisionID,
    history: history
  )
  var progress = PairedBoundaryProgress()
  try progress.accept(.positiveX, revisionID: revisionID)
  let revision = LearningArtifactRevision(
    id: revisionID,
    kind: .boundarySideAggregate(.positiveX),
    attemptID: attemptID,
    disposition: .succeeded,
    state: .current
  )
  let position = try MachinePosition(x: 10, y: 0)
  return try AcceptedMachineArtifactCheckpoint(
    controllerContext: ControllerCheckpointContext(probe: passiveProbe(position: position)),
    machinePositionAtSave: position,
    controllerSessionID: sessionID,
    coordinateRevision: coordinateRevision,
    acceptedAttemptSequence: 1,
    pairedBoundaryProgress: progress,
    acceptedBoundaryEvidence: [evidence],
    boundarySideAggregates: [aggregate],
    estimatedMachineCenter: nil,
    learnedLocalCoordinateFrame: nil,
    centerArrivalPosition: nil,
    acceptedRevisions: [revision]
  )
}

private func passiveProbe(
  position: MachinePosition,
  configuration: [String] = ["$100=80.000", "$101=80.000", "$110=900.000"],
  parserState: [String] = ["[GC:G0 G54 G17 G21 G90 G94 M5 M9 T0 F0 S0]"]
) -> PassiveProbeResult {
  let link = MachineLinkDescriptor(
    identifier: "/dev/cu.checkpoint-fixture",
    displayName: "Checkpoint Fixture",
    bsdPath: "/dev/cu.checkpoint-fixture",
    transport: .bsdSerial
  )
  let reports: [(PassiveQuery, [String])] = [
    (.buildInfo, ["[VER:1.1h.20200101:checkpoint]"]),
    (.parserState, parserState),
    (
      .status,
      [String(format: "<Idle|MPos:%.3f,%.3f,0.000>", position.point.x, position.point.y)]
    ),
    (.configuration, configuration),
    (.coordinateOffsets, ["[G54:0.000,0.000,0.000]", "[G92:0.000,0.000,0.000]"]),
  ]
  let exchanges = reports.map { query, report in
    let text = query == .status ? report : report + ["ok"]
    return PassiveProbeExchange(
      query: query,
      commandID: UUID(),
      rawIO: [],
      lines: text.map { GRBLParser.parseLine(Data($0.utf8)) },
      completed: true,
      blocker: nil
    )
  }
  return PassiveProbeResult(
    link: link,
    startedAt: RuntimeTimestamp(monotonicNanoseconds: 1),
    completedAt: RuntimeTimestamp(monotonicNanoseconds: 2),
    exchanges: exchanges,
    blockers: []
  )
}
