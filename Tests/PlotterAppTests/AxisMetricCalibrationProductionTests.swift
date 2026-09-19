import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import Testing
@testable import PlotterApp

@Suite("Axis metric production application composition", .serialized)
@MainActor
struct AxisMetricCalibrationProductionTests {
  @Test("Ruler save is passive; typed Apply durably prepares and resets dependent Learning before a partial write")
  func passiveSaveAndAmbiguousApply() async throws {
    let fixture = try await AxisMetricApplicationFixture.make(withPortraitCheckpoint: true)
    let app = fixture.app
    defer { fixture.stores.remove() }
    do {
      let portraitArchive = app.portraitStudio.sketches.archive
      let training = (await fixture.portraitCheckpoints.load()).snapshot
      #expect(!portraitArchive.entries.isEmpty)
      #expect(!training.checkpoints.isEmpty)
      let penBefore = await fixture.machine.requestedPenCommands
      let feedsBefore = await fixture.machine.requestedFeeds
      let oldCheckpoint = try fixture.savedCheckpoint()
      try await fixture.saveMeasurements()
      let proposal = try #require(app.axisCalibrationProposal, "\(app.axisMetricStatus ?? "")")
      #expect(fixture.trace.snapshot().invocations == 0)
      #expect(app.tipCameraRegistration == fixture.accepted.registration)
      #expect(try fixture.savedCheckpoint() == oldCheckpoint)
      #expect(app.drawingEvidenceArchive.axisCalibrationAttempts.isEmpty)
      #expect(app.axisMetricApplyUnavailableReason == nil, "\(app.axisMetricApplyUnavailableReason ?? "")")
      await app.applyAxisMetricCalibration()
      let trace = fixture.trace.snapshot()
      #expect(trace.invocations == 1 && trace.writes == 1)
      #expect(trace.preparedBeforeWrite)
      let prefix = try #require(trace.prefixBeforeWrite)
      #expect(prefix.semanticIdentity.machineGeometry == proposal.proposedMachineGeometry)
      #expect(prefix.penInteraction == oldCheckpoint.penInteraction)
      #expect(prefix.machineArtifacts == nil && prefix.machineCamera == nil && prefix.tipCalibration == nil && prefix.stageFour == nil)
      #expect(fixture.trace.snapshot().persistedGeometry == proposal.proposedMachineGeometry)
      #expect(app.tipCameraRegistration == nil)
      #expect(app.machineCameraRegistration == nil)
      #expect(!app.interactiveLearningIsComplete)
      #expect(app.penInteractionCompleted)
      #expect(app.drawingEvidenceArchive.axisMetricMeasurements.first?.sourceCheckpoint == oldCheckpoint)
      #expect(app.drawingEvidenceArchive.records.contains(fixture.accepted.borderRecord))
      #expect(app.drawingEvidenceArchive.axisCalibrationTerminals.last?.outcome.status == .ambiguous)
      #expect(await fixture.machine.requestedPenCommands == penBefore)
      #expect(await fixture.machine.requestedFeeds == feedsBefore)
      #expect(await fixture.machine.requestedDrawingStrokes.isEmpty)
      #expect(await fixture.machine.requestedBoundaryRequests.isEmpty)
      #expect(try axisMetricSnapshotData(app.portraitStudio.sketches.archive) == axisMetricSnapshotData(portraitArchive))
      #expect(try axisMetricSnapshotData((await fixture.portraitCheckpoints.load()).snapshot) == axisMetricSnapshotData(training))
      await app.applyAxisMetricCalibration()
      #expect(fixture.trace.snapshot().invocations == 1)
      #expect(app.axisMetricApplyUnavailableReason != nil)
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }

  @Test("A pre-write Learning-prefix persistence failure produces zero settings writes and preserves old authority")
  func prewritePersistenceFailure() async throws {
    let fixture = try await AxisMetricApplicationFixture.make()
    defer { fixture.stores.remove() }
    let app = fixture.app
    do {
      try await fixture.saveMeasurements()
      let old = try fixture.savedCheckpoint()
      fixture.trace.setFailCheckpointSave(true)
      await app.applyAxisMetricCalibration()
      #expect(fixture.trace.snapshot().invocations == 1)
      #expect(fixture.trace.snapshot().writes == 0)
      #expect(try fixture.savedCheckpoint() == old)
      #expect(app.tipCameraRegistration == fixture.accepted.registration)
      #expect(app.interactiveLearningIsComplete)
      #expect(app.drawingEvidenceArchive.axisCalibrationAttempts.count == 1)
      let terminal = try #require(app.drawingEvidenceArchive.axisCalibrationTerminals.last)
      #expect(terminal.outcome.status == .refused)
      #expect(terminal.outcome.attemptedCommands.isEmpty)
      #expect(await fixture.machine.requestedFeeds.isEmpty)
      fixture.trace.setFailCheckpointSave(false)
      await app.shutdown()
    } catch { fixture.trace.setFailCheckpointSave(false); await app.shutdown(); throw error }
  }

  @Test("Shutdown joins an admitted held calibration and retains its partial terminal")
  func shutdownJoinsPublication() async throws {
    let gate = TestInspectionSuspension(); await gate.arm()
    let fixture = try await AxisMetricApplicationFixture.make(gate: gate)
    defer { fixture.stores.remove() }
    let app = fixture.app
    do {
      try await fixture.saveMeasurements()
      let operation = Task { await app.applyAxisMetricCalibration() }
      try await waitUntilAsync { await gate.isWaiting }
      #expect(fixture.trace.snapshot().preparedBeforeWrite)
      let shutdown = Task { await app.shutdown() }
      try await waitUntil { app.isShutdown }
      #expect(fixture.trace.snapshot().writes == 1)
      await gate.release()
      await operation.value
      await shutdown.value
      guard case .loaded(let archive) = fixture.stores.evidenceStore.loadSnapshot() else {
        Issue.record("Shutdown must leave a readable calibration receipt"); return
      }
      #expect(archive.axisCalibrationAttempts.count == 1)
      #expect(archive.axisCalibrationTerminals.count == 1)
      #expect(archive.axisCalibrationTerminals[0].outcome.status == .ambiguous)
      #expect(archive.axisCalibrationTerminals[0].outcome.attemptedCommands.count == 1)
      #expect(fixture.trace.snapshot().invocations == 1)
    } catch { await gate.release(); await app.shutdown(); throw error }
  }

  @Test("Failed terminal publication retries the exact retained receipt without settings or motion replay")
  func publicationRetryIsEvidenceOnly() async throws {
    let fixture = try await AxisMetricApplicationFixture.make(obstructTerminalPublication: true)
    defer { fixture.stores.remove() }
    let app = fixture.app
    do {
      try await fixture.saveMeasurements()
      await app.applyAxisMetricCalibration()
      #expect(app.axisMetricHasPendingPublication)
      #expect(fixture.trace.snapshot().writes == 1)
      #expect(app.drawingEvidenceArchive.axisCalibrationTerminals.isEmpty)
      try fixture.trace.restoreEvidenceFile()
      await app.retryAxisMetricEvidencePublication()
      #expect(!app.axisMetricHasPendingPublication)
      let terminal = try #require(app.drawingEvidenceArchive.axisCalibrationTerminals.last)
      #expect(terminal.outcome.status == .ambiguous)
      let bytes = try Data(contentsOf: fixture.stores.evidenceStore.fileURL)
      await app.retryAxisMetricEvidencePublication()
      #expect(try Data(contentsOf: fixture.stores.evidenceStore.fileURL) == bytes)
      #expect(fixture.trace.snapshot().invocations == 1 && fixture.trace.snapshot().writes == 1)
      #expect(await fixture.machine.requestedFeeds.isEmpty)
      await app.shutdown()
    } catch { try? fixture.trace.restoreEvidenceFile(); await app.shutdown(); throw error }
  }
}

@MainActor
private struct AxisMetricApplicationFixture {
  let app: PlotterApplicationRuntime
  let machine: LowerMachineSessionFixture
  let stores: CompleteAcceptedLearningStores
  let accepted: CompleteAcceptedLearningFixture
  let trace: AxisMetricApplicationTrace
  let portraitCheckpoints: PortraitCheckpointStore

  static func make(gate: TestInspectionSuspension? = nil, obstructTerminalPublication: Bool = false,
                   withPortraitCheckpoint: Bool = false) async throws -> Self {
    let accepted = try await CompleteAcceptedLearningFixture.make()
    let stores = CompleteAcceptedLearningStores()
    try await stores.save(accepted)
    let checkpointStore = stores.checkpointStore, evidenceStore = stores.evidenceStore
    let trace = AxisMetricApplicationTrace(evidenceURL: evidenceStore.fileURL)
    let log = EventLog(), machine = try LowerMachineSessionFixture(log: log)
    let clock = ComputationTestClock()
    clock.set(max(clock.read(), accepted.frame.frame.captureNanoseconds))
    let camera = try AcceptedDrawingCameraSession(frame: accepted.frame, clock: clock)
    let portraitCheckpoints = PortraitCheckpointStore(directory: stores.directory.appendingPathComponent("styles"))
    let portrait = PortraitStudioModel(candidateStore: PortraitCandidateStore(directoryURL: stores.directory.appendingPathComponent("portraits")))
    if withPortraitCheckpoint {
      let (scope, archive) = try portraitTrainingFixture()
      let source = PortraitCandidateStore(directoryURL: stores.directory.appendingPathComponent("portraits"))
      try await source.save(snapshot: archive)
      await portrait.loadArchive()
      _ = await portraitCheckpoints.load()
      _ = try await portraitCheckpoints.saveScope(scope)
      let dataset = try PortraitPreferenceDatasetBuilder.freeze(archive: archive, scope: scope, seed: 7)
      let historical = try await PortraitOrdinalTrainer.fit(dataset: dataset, parent: nil)
      _ = try await portraitCheckpoints.install(historical)
      #expect(!(await portraitCheckpoints.load()).snapshot.checkpoints.isEmpty)
    }
    let app = plotterApplicationRuntime(machine: machine, observationSessionOverride: camera, portraitStudio: portrait,
      axisCalibration: { proposal, beforeSettingsWrite in
        trace.invoked()
        do {
          try await beforeSettingsWrite()
          try trace.recordWriteBoundary(proposal: proposal, evidenceStore: evidenceStore, checkpointStore: checkpointStore)
          if obstructTerminalPublication { try trace.obstructEvidenceFile() }
          await gate?.waitIfArmed()
          let transfer = try ControllerAxisCalibrationCommandTransfer(command: proposal.commands[0], writtenByteCount: 3,
            writeError: "Synthetic disconnection after a partial first settings command")
          return try ControllerAxisCalibrationOutcome(status: .ambiguous,
            attemptedCommands: [proposal.commands[0]], reason: "Synthetic partial write; re-probe and reacquire Learning",
            commandTransfers: [transfer])
        } catch {
          let possibleWrite = trace.snapshot().writes > 0
          return try! ControllerAxisCalibrationOutcome(status: possibleWrite ? .ambiguous : .refused,
            attemptedCommands: possibleWrite ? [proposal.commands[0]] : [],
            reason: "Synthetic lower owner stopped: \(error)")
        }
      }, drawingRunClock: AxisMetricTestRuntimeClock(clock: clock),
      statePersistencePort: TestApplicationStatePersistencePort(loadCheckpoint: { checkpointStore.load() },
        saveCheckpoint: { value in
          if trace.snapshot().failCheckpointSave { throw AxisMetricTestFailure.injectedPersistence }
          try checkpointStore.save(value)
        }, clearCheckpoint: { try checkpointStore.clear() }, saveMachineGeometry: { trace.savedGeometry($0) }),
      drawingEvidencePort: stores.evidencePort, tipCalibrationSemanticIdentities: accepted.identities,
      residualEffectPort: TestApplicationResidualEffectPort(discoverDevices: { [machine.descriptor] }, readNanoseconds: { clock.read() }),
      loadPenCapAppearanceSelection: { nil }, log: log)
    do {
      await app.performApplicationStartup(AdaptivePlotterLaunchPolicy(arguments: []))
      await app.establishMachineSession(machine.descriptor)
      await submitControllerSession(app, .requestPassiveProbe)
      await submitObservationConfigurationForTest(app, .selectSource(.live, camera.device.id))
      try await applyCompleteSavedLearning(app)
      #expect(app.interactiveLearningIsComplete)
      #expect(app.tipCameraRegistration == accepted.registration)
      let baseline = try #require(accepted.checkpoint.machineArtifacts).controllerContext
      #expect(try ControllerAxisCalibrationProposal.stepsPerMM(axis: .x, context: baseline) == 80)
      #expect(try ControllerAxisCalibrationProposal.stepsPerMM(axis: .y, context: baseline) == 80)
      return Self(app: app, machine: machine, stores: stores, accepted: accepted, trace: trace, portraitCheckpoints: portraitCheckpoints)
    } catch { await app.shutdown(); stores.remove(); throw error }
  }

  func savedCheckpoint() throws -> AcceptedLearningPathCheckpoint {
    guard case .loaded(let value) = stores.checkpointStore.load() else { throw AxisMetricTestFailure.missingCheckpoint }
    return value
  }
  func saveMeasurements() async throws {
    let geometry = try #require(app.axisMetricFrame)
    let edges = try geometry.edges.map { edge in
      try ControllerAxisRulerMeasurement(segmentIndex: edge.segmentIndex,
        physicalLengthMM: edge.plannedControllerSpanMM * (edge.axis == .x ? 1.002 : 0.783), uncertaintyMM: 0.1)
    }
    await app.saveAxisMetricMeasurement(edges, method: "Synthetic ruler observations; no physical evidence", axesConfirmed: true)
    _ = try #require(app.latestAxisMetricMeasurement, "\(app.axisMetricStatus ?? "")")
    _ = try #require(app.axisCalibrationProposal, "\(app.axisMetricStatus ?? "")")
  }
}

private enum AxisMetricTestFailure: Error { case injectedPersistence, missingCheckpoint, missingPreparation }
private final class AxisMetricApplicationTrace: @unchecked Sendable {
  struct Snapshot: Sendable {
    var invocations = 0
    var writes = 0
    var preparedBeforeWrite = false
    var prefixBeforeWrite: AcceptedLearningPathCheckpoint?
    var persistedGeometry: MachineGeometryIdentity?
    var failCheckpointSave = false
  }
  private let lock = NSLock()
  private var value = Snapshot()
  private let evidenceURL: URL
  private var backupURL: URL { evidenceURL.appendingPathExtension("before-terminal") }
  init(evidenceURL: URL) { self.evidenceURL = evidenceURL }
  func snapshot() -> Snapshot { lock.lock(); defer { lock.unlock() }; return value }
  func invoked() { lock.lock(); defer { lock.unlock() }; value.invocations += 1 }
  func savedGeometry(_ identity: MachineGeometryIdentity) { lock.lock(); defer { lock.unlock() }; value.persistedGeometry = identity }
  func setFailCheckpointSave(_ enabled: Bool) { lock.lock(); defer { lock.unlock() }; value.failCheckpointSave = enabled }
  func recordWriteBoundary(proposal: ControllerAxisCalibrationProposal, evidenceStore: DrawingRunEvidenceStore,
                           checkpointStore: AcceptedLearningPathCheckpointStore) throws {
    guard case .loaded(let archive) = evidenceStore.loadSnapshot(),
      archive.axisCalibrationAttempts.last?.proposal == proposal,
      case .loaded(let prefix) = checkpointStore.load(),
      prefix.semanticIdentity.machineGeometry == proposal.proposedMachineGeometry,
      prefix.machineArtifacts == nil && prefix.machineCamera == nil && prefix.tipCalibration == nil && prefix.stageFour == nil else {
      throw AxisMetricTestFailure.missingPreparation
    }
    lock.lock(); defer { lock.unlock() }
    value.preparedBeforeWrite = true; value.prefixBeforeWrite = prefix; value.writes += 1
  }
  func obstructEvidenceFile() throws {
    try FileManager.default.moveItem(at: evidenceURL, to: backupURL)
    try FileManager.default.createDirectory(at: evidenceURL, withIntermediateDirectories: false)
  }
  func restoreEvidenceFile() throws {
    guard FileManager.default.fileExists(atPath: backupURL.path) else { return }
    try FileManager.default.removeItem(at: evidenceURL)
    try FileManager.default.moveItem(at: backupURL, to: evidenceURL)
  }
}

private struct AxisMetricTestRuntimeClock: RuntimeClock {
  let clock: ComputationTestClock
  func nowNanoseconds() -> UInt64 { clock.read() }
  func sleep(nanoseconds _: UInt64) async throws { try Task.checkCancellation() }
}

private func axisMetricSnapshotData<T: Encodable>(_ value: T) throws -> Data {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  return try encoder.encode(value)
}
