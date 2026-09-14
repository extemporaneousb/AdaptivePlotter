import Foundation
import PlotterModel
import PlotterRuntime
import Testing
@testable import PlotterApp

@MainActor
@Suite("Axis metric startup persistence recovery")
struct AxisMetricLearningTransitionTests {
  enum CrashBoundary: CaseIterable { case prepared, prefixSaved, identitySaved }

  @Test("prepared calibration reconciles every interrupted prefix/identity boundary without replay", arguments: CrashBoundary.allCases)
  func interruptedPreparation(_ boundary: CrashBoundary) async throws {
    let f = try await AxisTransitionFixture.make()
    defer { f.stores.remove() }
    let target = f.targetIdentity
    switch boundary {
    case .prepared: break
    case .prefixSaved: try f.stores.checkpointStore.save(f.prefix())
    case .identitySaved: try f.persistence.persistMachineGeometryIdentity(target.machineGeometry)
    }
    let originalArchive = try Data(contentsOf: f.archiveURL)
    let current = AxisMetricLearningTransition.replacingGeometry(in: f.source.semanticIdentity,
      with: try f.persistence.identity())
    let restored = try AxisMetricLearningTransition.reconcile(
      archive: await f.stores.evidenceStore.load(), identity: current, persistence: f.persistence)
    #expect(restored == target)
    #expect(try f.persistence.identity() == target.machineGeometry)
    let saved = try f.savedCheckpoint()
    #expect(saved.semanticIdentity == target)
    #expect(saved.penInteraction == f.source.penInteraction)
    #expect(saved.machineArtifacts == nil && saved.machineCamera == nil)
    #expect(saved.tipCalibration == nil && saved.stageFour == nil)
    #expect(saved.referenceFrame == nil)
    #expect(try Data(contentsOf: f.archiveURL) == originalArchive)
    let archive = try await f.archive()
    #expect(archive.axisMetricMeasurements.first?.sourceCheckpoint == f.source)
    #expect(archive.records.contains(f.accepted.borderRecord))
    #expect(archive.axisCalibrationTerminals.isEmpty)
    // Restart reconciliation operates only on archive/checkpoint/identity ports;
    // it cannot dispatch a controller write, camera capture, or portrait action.
    let checkpointBytes = try Data(contentsOf: f.checkpointURL)
    #expect(try AxisMetricLearningTransition.reconcile(archive: .loaded(archive),
      identity: restored, persistence: f.persistence) == target)
    #expect(try Data(contentsOf: f.checkpointURL) == checkpointBytes)
  }

  @Test("repeated startup preserves reacquired complete Learning and an explicit later clear")
  func preservesLaterAuthorityDecisions() async throws {
    let reacquired = try await CompleteAcceptedLearningFixture.make()
    let f = try await AxisTransitionFixture.make(proposedGeometry: reacquired.identities.machineGeometry)
    defer { f.stores.remove() }
    _ = try AxisMetricLearningTransition.reconcile(archive: await f.stores.evidenceStore.load(),
      identity: f.source.semanticIdentity, persistence: f.persistence)
    // A separately constructed coherent accepted package represents later
    // reacquisition, including any independently changed paper/camera identities.
    // It is not produced by rescaling the old accepted observations.
    try f.stores.checkpointStore.save(reacquired.checkpoint)
    let archiveBytes = try Data(contentsOf: f.archiveURL)
    let checkpointBytes = try Data(contentsOf: f.checkpointURL)
    let current = reacquired.identities.learningPathIdentity
    for _ in 0..<2 {
      #expect(try AxisMetricLearningTransition.reconcile(archive: await f.stores.evidenceStore.load(),
        identity: current, persistence: f.persistence) == current)
      #expect(try f.savedCheckpoint() == reacquired.checkpoint)
      #expect(try Data(contentsOf: f.checkpointURL) == checkpointBytes)
    }
    try f.stores.checkpointStore.clear()
    #expect(try AxisMetricLearningTransition.reconcile(archive: await f.stores.evidenceStore.load(),
      identity: current, persistence: f.persistence) == current)
    guard case .absent = f.stores.checkpointStore.load() else {
      Issue.record("Startup recreated Learning after an explicit clear"); return
    }
    #expect(try Data(contentsOf: f.archiveURL) == archiveBytes)
  }

  enum RefusalCheckpoint: CaseIterable { case oldComplete, absent, newPrefix }

  @Test("proven no-write refusal preserves old authority only before new-prefix publication", arguments: RefusalCheckpoint.allCases)
  func provenRefusal(_ state: RefusalCheckpoint) async throws {
    let f = try await AxisTransitionFixture.make()
    defer { f.stores.remove() }
    switch state {
    case .oldComplete: break
    case .absent: try f.stores.checkpointStore.clear()
    case .newPrefix: try f.stores.checkpointStore.save(f.prefix())
    }
    _ = try await f.stores.evidenceStore.appendAxisCalibrationTerminal(
      ControllerAxisCalibrationTerminal(proposalID: f.proposal.proposalID,
        outcome: ControllerAxisCalibrationOutcome(status: .refused,
          reason: "Fixture baseline mismatch before any setting write.")))
    let archiveBytes = try Data(contentsOf: f.archiveURL)
    let restored = try AxisMetricLearningTransition.reconcile(
      archive: await f.stores.evidenceStore.load(), identity: f.source.semanticIdentity,
      persistence: f.persistence)
    switch state {
    case .oldComplete:
      #expect(restored == f.source.semanticIdentity)
      #expect(try f.savedCheckpoint() == f.source)
      #expect(try f.persistence.identity() == f.source.semanticIdentity.machineGeometry)
    case .absent:
      #expect(restored == f.source.semanticIdentity)
      guard case .absent = f.stores.checkpointStore.load() else {
        Issue.record("No-write refusal restored a previously absent checkpoint"); return
      }
    case .newPrefix:
      #expect(restored == f.targetIdentity)
      #expect(try f.savedCheckpoint().semanticIdentity == f.targetIdentity)
      #expect(try f.persistence.identity() == f.targetIdentity.machineGeometry)
      #expect(try f.savedCheckpoint().machineArtifacts == nil)
    }
    #expect(try Data(contentsOf: f.archiveURL) == archiveBytes)
  }

  @Test("persistence failure throws before returning restoration identity; exact retry completes", arguments: [AxisIdentityPersistenceFixture.Failure.checkpoint, .identity])
  func persistenceFailure(_ failure: AxisIdentityPersistenceFixture.Failure) async throws {
    let f = try await AxisTransitionFixture.make()
    defer { f.stores.remove() }
    f.persistence.setFailure(failure)
    let archiveBytes = try Data(contentsOf: f.archiveURL)
    var publishedIdentity: LearningPathSemanticIdentity?
    do {
      publishedIdentity = try AxisMetricLearningTransition.reconcile(
        archive: await f.stores.evidenceStore.load(), identity: f.source.semanticIdentity,
        persistence: f.persistence)
      Issue.record("Injected persistence failure unexpectedly returned restoration authority")
    } catch AxisIdentityPersistenceFixture.PersistenceError.injected {
      // The startup owner must catch this refusal instead of installing old Learning.
    }
    #expect(publishedIdentity == nil)
    #expect(try f.persistence.identity() == f.source.semanticIdentity.machineGeometry)
    if failure == .checkpoint {
      #expect(try f.savedCheckpoint() == f.source)
    } else {
      #expect(try f.savedCheckpoint().semanticIdentity == f.targetIdentity)
      #expect(try f.savedCheckpoint().machineArtifacts == nil)
    }
    f.persistence.setFailure(nil)
    #expect(try AxisMetricLearningTransition.reconcile(archive: await f.stores.evidenceStore.load(),
      identity: f.source.semanticIdentity, persistence: f.persistence) == f.targetIdentity)
    #expect(try f.persistence.identity() == f.targetIdentity.machineGeometry)
    #expect(try Data(contentsOf: f.archiveURL) == archiveBytes)
  }
}

@MainActor
private struct AxisTransitionFixture {
  let accepted: CompleteAcceptedLearningFixture
  let stores: CompleteAcceptedLearningStores
  let source: AcceptedLearningPathCheckpoint
  let proposal: ControllerAxisCalibrationProposal
  let persistence: AxisIdentityPersistenceFixture
  var archiveURL: URL { stores.directory.appendingPathComponent("drawings.json") }
  var checkpointURL: URL { stores.directory.appendingPathComponent("accepted.json") }
  var targetIdentity: LearningPathSemanticIdentity {
    AxisMetricLearningTransition.replacingGeometry(in: source.semanticIdentity,
      with: proposal.proposedMachineGeometry)
  }

  static func make(proposedGeometry: MachineGeometryIdentity = MachineGeometryIdentity()) async throws -> Self {
    let accepted = try await CompleteAcceptedLearningFixture.make()
    let stores = CompleteAcceptedLearningStores()
    do {
      let source = try checkpointWithAxisSettings(accepted.checkpoint)
      try stores.checkpointStore.save(source)
      _ = try await stores.evidenceStore.append(accepted.borderRecord)
      let geometry = try LearningFrameMetricGeometry.extract(record: accepted.borderRecord)
      let measurement = try ControllerAxisMetricMeasurement(recordedAt: Date(), geometry: geometry,
        sourceCheckpoint: source, edges: geometry.edges.map {
          try ControllerAxisRulerMeasurement(segmentIndex: $0.segmentIndex,
            physicalLengthMM: $0.plannedControllerSpanMM * ($0.axis == .x ? 1.04 : 0.97),
            uncertaintyMM: 0.25)
        }, method: "Synthetic ruler fixture; no attended physical measurement",
        operatorAxisAssociationConfirmed: true)
      let proposal = try ControllerAxisCalibrationProposal(measurement: measurement,
        proposedMachineGeometry: proposedGeometry)
      _ = try await stores.evidenceStore.appendAxisMetricMeasurement(measurement)
      _ = try await stores.evidenceStore.prepareAxisCalibration(
        ControllerAxisCalibrationAttempt(proposal: proposal))
      let persistence = try AxisIdentityPersistenceFixture(store: stores.checkpointStore,
        identityURL: stores.directory.appendingPathComponent("geometry.json"),
        identity: source.semanticIdentity.machineGeometry)
      return Self(accepted: accepted, stores: stores, source: source, proposal: proposal,
        persistence: persistence)
    } catch { stores.remove(); throw error }
  }

  func prefix() throws -> AcceptedLearningPathCheckpoint {
    try AcceptedLearningPathCheckpoint(semanticIdentity: targetIdentity, penInteraction: source.penInteraction)
  }
  func savedCheckpoint() throws -> AcceptedLearningPathCheckpoint {
    guard case .loaded(let checkpoint) = stores.checkpointStore.load() else {
      throw AxisIdentityPersistenceFixture.PersistenceError.missing
    }
    return checkpoint
  }
  func archive() async throws -> DrawingRunEvidenceArchive {
    guard case .loaded(let archive) = await stores.evidenceStore.load() else {
      throw AxisIdentityPersistenceFixture.PersistenceError.missing
    }
    return archive
  }

  /// Reconstruct valid typed fixtures with explicit synthetic firmware settings;
  /// no private mutation, serialization rewriting, or firmware contact is involved.
  private static func checkpointWithAxisSettings(_ checkpoint: AcceptedLearningPathCheckpoint) throws -> AcceptedLearningPathCheckpoint {
    let old = try #require(checkpoint.machineArtifacts)
    let context = old.controllerContext
    let configuration = context.configuration.filter { !$0.hasPrefix("$100=") && !$0.hasPrefix("$101=") }
      + ["$100=80.000", "$101=80.000"]
    let reports: [(PassiveQuery, [String])] = [(.buildInfo, context.buildInfo),
      (.parserState, context.parserState), (.configuration, configuration),
      (.coordinateOffsets, context.coordinateOffsets), (.status, ["<Idle|MPos:0.000,0.000,0.000>"])]
    let probe = PassiveProbeResult(link: context.link,
      startedAt: RuntimeTimestamp(monotonicNanoseconds: 1),
      completedAt: RuntimeTimestamp(monotonicNanoseconds: 2),
      exchanges: reports.map { query, lines in
        PassiveProbeExchange(query: query, commandID: UUID(), rawIO: [],
          lines: (query == .status ? lines : lines + ["ok"]).map { GRBLParser.parseLine(Data($0.utf8)) },
          completed: true, blocker: nil)
      }, blockers: [])
    let machine = try AcceptedMachineArtifactCheckpoint(checkpointID: old.checkpointID,
      controllerContext: ControllerCheckpointContext(probe: probe), machinePositionAtSave: old.machinePositionAtSave,
      controllerSessionID: old.controllerSessionID, coordinateRevision: old.coordinateRevision,
      acceptedAttemptSequence: old.acceptedAttemptSequence, pairedBoundaryProgress: old.pairedBoundaryProgress,
      acceptedBoundaryEvidence: old.acceptedBoundaryEvidence, boundarySideAggregates: old.boundarySideAggregates,
      estimatedMachineCenter: old.estimatedMachineCenter, learnedLocalCoordinateFrame: old.learnedLocalCoordinateFrame,
      centerArrivalPosition: old.centerArrivalPosition, acceptedRevisions: old.acceptedRevisions)
    return try AcceptedLearningPathCheckpoint(checkpointID: checkpoint.checkpointID,
      semanticIdentity: checkpoint.semanticIdentity, penInteraction: checkpoint.penInteraction,
      machineArtifacts: machine, machineCamera: checkpoint.machineCamera,
      tipCalibration: checkpoint.tipCalibration, stageFour: checkpoint.stageFour,
      penCapAppearance: checkpoint.penCapAppearance, referenceFrame: checkpoint.referenceFrame)
  }
}

final class AxisIdentityPersistenceFixture: PlotterApplicationStatePersistencePort, @unchecked Sendable {
  enum Failure: Sendable { case checkpoint, identity }
  enum PersistenceError: Error { case injected, missing }
  private let store: AcceptedLearningPathCheckpointStore
  private let identityURL: URL
  private let lock = NSLock()
  private var failure: Failure?

  init(store: AcceptedLearningPathCheckpointStore, identityURL: URL,
    identity: MachineGeometryIdentity) throws {
    self.store = store; self.identityURL = identityURL
    try JSONEncoder().encode(identity).write(to: identityURL, options: .atomic)
  }
  func setFailure(_ failure: Failure?) { lock.withLock { self.failure = failure } }
  func identity() throws -> MachineGeometryIdentity {
    try lock.withLock { try JSONDecoder().decode(MachineGeometryIdentity.self, from: Data(contentsOf: identityURL)) }
  }
  func loadAcceptedLearningPathCheckpoint() -> AcceptedLearningPathCheckpointLoadResult { store.load() }
  func saveAcceptedLearningPathCheckpoint(_ checkpoint: AcceptedLearningPathCheckpoint) throws {
    if lock.withLock({ failure == .checkpoint }) { throw PersistenceError.injected }
    try store.save(checkpoint)
  }
  func clearAcceptedLearningPathCheckpoint() throws { try store.clear() }
  func persistPaperRevisionContext(_ context: PaperRevisionContext) throws {
    Issue.record("Axis metric startup recovery attempted unrelated paper persistence")
    throw PersistenceError.injected
  }
  func persistMachineGeometryIdentity(_ identity: MachineGeometryIdentity) throws {
    try lock.withLock {
      if failure == .identity { throw PersistenceError.injected }
      try JSONEncoder().encode(identity).write(to: identityURL, options: .atomic)
      guard try JSONDecoder().decode(MachineGeometryIdentity.self,
        from: Data(contentsOf: identityURL)) == identity else { throw PersistenceError.missing }
    }
  }
}
