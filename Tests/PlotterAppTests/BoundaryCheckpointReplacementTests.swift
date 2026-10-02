import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterUI
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Boundary checkpoint replacement production regression", .serialized)
@MainActor
struct BoundaryCheckpointReplacementTests {
  @Test("saved Boundary session mismatch retains Learning and leaves Reset All reachable")
  func retainedSessionMismatchAllowsExplicitReset() async throws {
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let app = fixture.application
    do {
      let owner = LearningPathItemID.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
      let before = try #require(app.currentBoundarySnapshot)
      let facts = await app.currentBoundaryExternalFacts(for: .live)
      #expect(before.acceptedMachineArtifacts?.controllerSessionID != facts.controllerSessionID)
      guard case .loaded(let stored) = fixture.stores.checkpointStore.load() else {
        Issue.record("Expected the retained checkpoint."); await app.shutdown(); return
      }
      let penCount = await fixture.machine.requestedPenCommands.count
      let motionCount = await fixture.machine.requestedBoundaryRequests.count
      // Completed Boundary exposes explicit per-side Redo controls rather
      // than the incomplete Boundary's direction selector.
      let redo = PlotterLearningAction.boundary(.acquire(direction: .positiveY, mode: .replacement))
      try requireEnabledPublicAction(redo, owner: owner, workspace: app)
      await app.performTestExerciseAction(redo, for: owner)
      try await waitUntil {
        if case .refused = app.currentBoundarySnapshot?.projection.phase { return true }
        return false
      }
      let after = try #require(app.currentBoundarySnapshot)
      guard case .retainedContextMismatch = after.projection.lastRefusal?.reason else {
        Issue.record("Expected a controller-session compatibility refusal."); await app.shutdown(); return
      }
      #expect(after.acceptedMachineArtifacts == before.acceptedMachineArtifacts)
      #expect(app.interactiveLearningIsComplete)
      guard case .loaded(let retained) = fixture.stores.checkpointStore.load() else {
        Issue.record("Expected the untouched checkpoint."); await app.shutdown(); return
      }
      #expect(retained == stored)
      #expect(await fixture.machine.requestedPenCommands.count == penCount)
      #expect(await fixture.machine.requestedBoundaryRequests.count == motionCount)
      let text = app.selectedOperatorActionPresentation(for: owner).instructions.compactMap {
        if case .text(let text) = $0 { return text }
        return nil
      }.joined(separator: " ")
      #expect(text.contains("different controller session"))
      #expect(!text.contains("PlotterRuntime."))
      #expect(!text.contains(facts.controllerSessionID.uuidString))
      let resetPlan = try #require(app.resetAllLearningPlan)
      #expect(await app.submitResetAllLearning(resetPlan))
      #expect(app.currentBoundarySnapshot?.acceptedMachineArtifacts == nil)
      #expect(app.learningArtifactGraph.currentRevision(for: .penInteraction) == nil)
      #expect(await fixture.machine.requestedBoundaryRequests.count == motionCount)
      await app.shutdown()
    } catch {
      await app.shutdown()
      throw error
    }
  }

  @Test("retraining persists fresh prefixes, archives complete predecessors and refuses disk conflicts", arguments: [0, 1, 2])
  func declinedCompleteLearning(diskConflict: Int) async throws {
    let accepted = try await CompleteAcceptedLearningFixture.make()
    let historical = try rebasedCompleteCheckpoint(accepted.checkpoint, to:
      try #require(accepted.checkpoint.machineArtifacts).coordinateRevision + 1)
    let persistence = try BoundaryReplacementPersistence(checkpoint: historical)
    defer { persistence.remove() }
    let originalBytes = try Data(contentsOf: persistence.fileURL)
    let fixture = try await BoundaryReplacementFixture.make(
      persistence: persistence, identities: accepted.identities)
    let app = fixture.application
    do {
      try await fixture.submitLearning(.startNewLearning, owner: app.testCurrentLearningPathItemID)
      #expect(try Data(contentsOf: persistence.fileURL) == originalBytes)
      try await fixture.completePenInteraction()
      let freshPen = try #require(app.learningArtifactGraph.currentRevision(for: .penInteraction))
      let penPrefix = try persistence.loaded()
      #expect(penPrefix.penInteraction?.revision.id == freshPen.id)
      #expect(penPrefix.machineCamera == nil)
      #expect(penPrefix.tipCalibration == nil)
      let historyDirectory = AcceptedLearningPathCheckpointStore(fileURL: persistence.fileURL).historyDirectoryURL
      let history = try FileManager.default.contentsOfDirectory(at: historyDirectory, includingPropertiesForKeys: nil)
      #expect(try history.contains { try Data(contentsOf: $0) == originalBytes })
      if diskConflict != 0 {
        if diskConflict == 1 { try persistence.saveAcceptedLearningPathCheckpoint(historical) }
        else { try persistence.clearAcceptedLearningPathCheckpoint() }
        let foreignBytes = try? Data(contentsOf: persistence.fileURL)
        try await fixture.acquireAndStop()
        let recovery = try #require(app.currentBoundarySnapshot?.projection.publicationRecoveryCapabilityID)
        #expect(app.currentBoundarySnapshot?.acceptedMachineArtifacts == nil)
        #expect(app.testAcceptedBoundaryEvidence.isEmpty)
        #expect((try? Data(contentsOf: persistence.fileURL)) == foreignBytes)
        #expect(app.artifactResetEpisodeSnapshot.savedLearning.appliedCheckpoint == penPrefix)
        let motionCount = await fixture.machine.requestedBoundaryRequests.count
        let cancelCount = await fixture.machine.cancelCount
        try persistence.saveAcceptedLearningPathCheckpoint(penPrefix)
        try await fixture.submitLearning(.boundary(.recoverPublication(recovery)), owner: fixture.boundaryOwner)
        #expect(await fixture.machine.requestedBoundaryRequests.count == motionCount)
        #expect(await fixture.machine.cancelCount == cancelCount)
      } else { try await fixture.acquireAndStop() }
      let boundary = try #require(app.currentBoundarySnapshot)
      #expect(boundary.projection.terminal?.disposition == .accepted)
      #expect(boundary.projection.publicationRecoveryCapabilityID == nil)
      let machine = try #require(boundary.acceptedMachineArtifacts)
      #expect(machine.coordinateRevision != historical.machineArtifacts?.coordinateRevision)
      #expect(machine.acceptedBoundaryEvidence.count == 1)
      #expect(app.machineCameraRegistration == nil)
      #expect(app.tipCameraRegistration == nil)
      #expect(app.learningArtifactGraph.currentRevision(for: .machineCameraRegistration) == nil)
      #expect(await fixture.machine.cancelIntents == [.operatorStop])
      #expect(await fixture.machine.requestedBoundaryRequests.count == 1)
      let prefix = try persistence.loaded()
      #expect(prefix.penInteraction?.revision.id == freshPen.id)
      #expect(prefix.machineArtifacts == machine)
      #expect(prefix.machineCamera == nil && prefix.tipCalibration == nil && prefix.stageFour == nil)
      #expect(app.artifactResetEpisodeSnapshot.savedLearning.appliedCheckpoint == prefix)
      await app.shutdown()
      let saved = try persistence.loaded()
      #expect(saved.penInteraction == prefix.penInteraction && saved.machineArtifacts == machine)
      let restarted = try await BoundaryReplacementFixture.make(
        persistence: persistence, identities: accepted.identities)
      #expect(restarted.application.learningArtifactGraph.revisions.isEmpty)
      #expect(restarted.application.machineCameraRegistration == nil)
      #expect(restarted.application.tipCameraRegistration == nil)
      #expect(restarted.application.artifactResetEpisodeSnapshot.savedLearning.candidate?.checkpoint == saved)
      await restarted.application.shutdown()
    } catch { await app.shutdown(); throw error }
  }

  @Test("Boundary persists the active Pen prefix and exact retry settles before reset", arguments: [false, true])
  func activePrefixAndPublicationRecovery(failSave: Bool) async throws {
    let persistence = try BoundaryReplacementPersistence()
    defer { persistence.remove() }
    let fixture = try await BoundaryReplacementFixture.make(persistence: persistence)
    let app = fixture.application
    do {
      try await fixture.completePenInteraction()
      let pen = try #require(app.learningArtifactGraph.currentRevision(for: .penInteraction))
      let penCheckpoint = try persistence.loaded()
      #expect(penCheckpoint.penInteraction?.revision.id == pen.id)
      #expect(penCheckpoint.machineArtifacts == nil)
      if failSave { persistence.failNextSave() }
      try await fixture.acquireAndStop()
      let motionCount = await fixture.machine.requestedBoundaryRequests.count
      let cancelCount = await fixture.machine.cancelCount
      if failSave {
        let recovery = try #require(app.currentBoundarySnapshot?.projection.publicationRecoveryCapabilityID)
        #expect(app.testAcceptedBoundaryEvidence.isEmpty)
        #expect(app.currentBoundarySnapshot?.acceptedMachineArtifacts == nil)
        #expect(try persistence.loaded() == penCheckpoint)
        #expect(app.artifactResetEpisodeSnapshot.savedLearning.appliedCheckpoint == penCheckpoint)
        let resetPlan = try #require(app.resetAllLearningPlan)
        #expect(!(await app.submitResetAllLearning(resetPlan)))
        #expect(app.currentBoundarySnapshot?.projection.publicationRecoveryCapabilityID == recovery)
        #expect(try persistence.loaded() == penCheckpoint)
        try await fixture.submitLearning(.boundary(.recoverPublication(recovery)), owner: fixture.boundaryOwner)
        #expect(await fixture.machine.requestedBoundaryRequests.count == motionCount)
        #expect(await fixture.machine.cancelCount == cancelCount)
      }
      let current = try #require(app.currentBoundarySnapshot)
      #expect(current.projection.terminal?.disposition == .accepted)
      #expect(current.projection.publicationRecoveryCapabilityID == nil)
      let saved = try persistence.loaded()
      try saved.validate()
      #expect(saved.penInteraction?.revision.id == pen.id)
      #expect(saved.machineArtifacts == current.acceptedMachineArtifacts)
      #expect(app.artifactResetEpisodeSnapshot.savedLearning.appliedCheckpoint == saved)
      #expect(saved.machineArtifacts?.acceptedBoundaryEvidence.count == 1)
      #expect(saved.machineCamera == nil)
      #expect(saved.tipCalibration == nil)
      #expect(saved.stageFour == nil)
      let resetPlan = try #require(app.resetAllLearningPlan)
      let historyIDs = Set(app.learningArtifactGraph.revisions.map(\.id))
      #expect(await app.submitResetAllLearning(resetPlan))
      #expect(!app.learningArtifactGraph.revisions.contains { $0.state == .current })
      #expect(Set(app.learningArtifactGraph.revisions.map(\.id)) == historyIDs)
      #expect(!historyIDs.isEmpty)
      #expect(app.currentBoundarySnapshot?.acceptedMachineArtifacts == nil)
      #expect(await fixture.machine.requestedBoundaryRequests.count == motionCount)
      await app.shutdown()
    } catch {
      await app.shutdown()
      throw error
    }
  }

  @Test("staged Boundary checkpoint preserves only coordinate-compatible active descendants without publishing", arguments: [false, true])
  func stagedActiveDescendants(changesCoordinate: Bool) async throws {
    let fixture = try await DrawingWorkbenchApplicationFixture.make(verifyPhysicalPose: false)
    defer { fixture.stores.remove() }
    let app = fixture.application
    do {
      let priorBoundary = try #require(app.currentBoundarySnapshot)
      let priorMachine = try #require(priorBoundary.acceptedMachineArtifacts)
      let priorSaved = app.artifactResetEpisodeSnapshot.savedLearning
      let priorCamera = app.machineCameraRegistration
      let priorTip = app.tipCameraRegistration
      let priorGraph = app.learningArtifactGraph.revisions
      let applied = try #require(priorSaved.appliedCheckpoint)
      try #require(applied.machineCamera != nil && applied.tipCalibration != nil && applied.stageFour != nil)
      let candidateMachine = changesCoordinate
        ? try priorMachine.rebasedForKnownMachineCoordinateChange(
          to: priorMachine.coordinateRevision + 1, delta: Vector2(dx: 0, dy: 0))
        : priorMachine
      #expect(Set(candidateMachine.acceptedRevisions.map(\.id)) == Set(priorMachine.acceptedRevisions.map(\.id)))
      let candidate = PlotterBoundaryPersistenceCandidate(environment: .live,
        semanticIdentity: applied.semanticIdentity, machineArtifacts: candidateMachine)
      try app.persistStagedBoundaryCheckpoint(candidate, using: fixture.stores.persistence)
      guard case .loaded(let staged) = fixture.stores.checkpointStore.load() else {
        Issue.record("Expected a valid staged checkpoint on disk.")
        await app.shutdown(); return
      }
      try staged.validate()
      #expect(staged.machineArtifacts == candidateMachine)
      #expect(staged.penInteraction == applied.penInteraction)
      if changesCoordinate {
        #expect(staged.machineCamera == nil)
        #expect(staged.tipCalibration == nil)
        #expect(staged.stageFour == nil)
      } else {
        #expect(staged.machineCamera == applied.machineCamera)
        #expect(staged.tipCalibration == applied.tipCalibration)
        #expect(staged.stageFour == applied.stageFour)
      }
      // This is a staging-policy unit. No Boundary terminal is manufactured,
      // and neither saving nor pruning may prepublish candidate authority.
      #expect(app.currentBoundarySnapshot?.projection == priorBoundary.projection)
      #expect(app.currentBoundarySnapshot?.acceptedMachineArtifacts == priorMachine)
      #expect(app.artifactResetEpisodeSnapshot.savedLearning == priorSaved)
      #expect(app.learningArtifactGraph.revisions == priorGraph)
      #expect(app.machineCameraRegistration == priorCamera)
      #expect(app.tipCameraRegistration == priorTip)
      await app.shutdown()
    } catch {
      await app.shutdown()
      throw error
    }
  }
}

/// Reconstruct a historical complete package without a coordinate-mismatched
/// camera/tip payload. Zero translation changes version provenance, not geometry.
private func rebasedCompleteCheckpoint(_ checkpoint: AcceptedLearningPathCheckpoint,
  to revision: UInt64) throws -> AcceptedLearningPathCheckpoint {
  let delta = try Vector2<MachineSpace>(dx: 0, dy: 0)
  let machine = try #require(checkpoint.machineArtifacts)
    .rebasedForKnownMachineCoordinateChange(to: revision, delta: delta)
  let camera = try #require(checkpoint.machineCamera)
  let tip = try #require(checkpoint.tipCalibration)
  let result = try AcceptedLearningPathCheckpoint(semanticIdentity: checkpoint.semanticIdentity,
    penInteraction: checkpoint.penInteraction, machineArtifacts: machine,
    machineCamera: AcceptedMachineCameraCheckpoint(revision: camera.revision,
      registration: camera.registration.rebasedForKnownMachineCoordinateChange(to: revision, delta: delta)),
    tipCalibration: AcceptedTipCalibrationCheckpoint(
      registration: tip.registration.rebasedForKnownMachineCoordinateChange(
        to: MachineCoordinateFrameRevision(rawValue: revision), delta: delta),
      acceptanceEvent: tip.acceptanceEvent),
    stageFour: checkpoint.stageFour, penCapAppearance: checkpoint.penCapAppearance,
    referenceFrame: checkpoint.referenceFrame)
  _ = try result.restoredLearningGraph()
  return result
}

/// Existing production compositions, with only synthetic lower camera/controller
/// effects and a real disk checkpoint store. No accepted Boundary is injected.
@MainActor
private struct BoundaryReplacementFixture {
  let application: PlotterApplicationRuntime
  let machine: LowerMachineSessionFixture
  let boundaryOwner = LearningPathItemID.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)

  static func make(persistence: BoundaryReplacementPersistence,
    identities: TipCalibrationSemanticIdentityState = .ephemeral()) async throws -> Self {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let app = plotterApplicationRuntime(machine: machine, camera: camera,
      statePersistencePort: persistence, tipCalibrationSemanticIdentities: identities, log: log)
    await app.establishMachineSession(machine.descriptor)
    await submitControllerSession(app, .requestPassiveProbe)
    await submitObservationConfigurationForTest(app, .selectSource(.live, nil))
    return Self(application: app, machine: machine)
  }

  func submitLearning(_ kind: PlotterLearningAction, owner: LearningPathItemID) async throws {
    let projection = application.testPlotterUIProjection(selectedItemID: owner, includesLearningPath: true).semantic
    let request = try #require(projection.request(for: learningActionID(kind, owner: owner)),
      "Expected current rendered request for \(kind); \(application.discoveryError ?? application.explorationError ?? "no error")")
    let disposition = await application.submitPlotterUIRequest(request)
    try #require(disposition == .accepted(requestID: request.id), "\(disposition)")
  }

  func completePenInteraction() async throws {
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    try await submitLearning(.start, owner: owner)
    let request = try #require(application.testActionSurfacePresentation.pointSelectionRequest)
    let frame = try #require(application.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(application, request: request,
      point: try Point2(x: Double(frame.frame.width - 1) / 2, y: Double(frame.frame.height - 1) / 2))
    try await waitUntil { application.activeDiscoverySequenceID == .penInteraction }
    for _ in 0..<3 { try await submitLearning(.choice(.yes), owner: owner) }
    try #require(application.penInteractionCompleted)
  }

  func acquireAndStop() async throws {
    try await submitRenderedBoundaryAcquisition(.positiveX, owner: boundaryOwner, workspace: application)
    try await waitUntilAsync { await machine.boundaryMotionIsAwaitingSettlement }
    let stop = try renderedBoundaryStopKind(owner: boundaryOwner, workspace: application)
    try await submitLearning(stop, owner: boundaryOwner)
    try #require(application.currentBoundarySnapshot?.projection.reference.operationID == nil)
  }
}

private final class BoundaryReplacementPersistence: PlotterApplicationStatePersistencePort, @unchecked Sendable {
  let directory: URL
  let fileURL: URL
  private let store: AcceptedLearningPathCheckpointStore
  private let lock = NSLock()
  private var shouldFailNextSave = false

  init(checkpoint: AcceptedLearningPathCheckpoint? = nil) throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent("boundary-replacement-\(UUID())")
    fileURL = directory.appendingPathComponent("accepted.json")
    store = AcceptedLearningPathCheckpointStore(fileURL: fileURL)
    if let checkpoint { try store.save(checkpoint) }
  }

  func failNextSave() { lock.withLock { shouldFailNextSave = true } }
  func remove() { try? FileManager.default.removeItem(at: directory) }
  func loaded() throws -> AcceptedLearningPathCheckpoint {
    guard case .loaded(let checkpoint) = loadAcceptedLearningPathCheckpoint() else {
      throw BoundaryReplacementError.missingCheckpoint
    }
    return checkpoint
  }
  func loadAcceptedLearningPathCheckpoint() -> AcceptedLearningPathCheckpointLoadResult {
    lock.withLock { store.load() }
  }
  func saveAcceptedLearningPathCheckpoint(_ checkpoint: AcceptedLearningPathCheckpoint) throws {
    try lock.withLock {
      if shouldFailNextSave {
        shouldFailNextSave = false
        throw BoundaryReplacementError.injectedSave
      }
      try store.save(checkpoint)
    }
  }
  func clearAcceptedLearningPathCheckpoint() throws { try lock.withLock { try store.clear() } }
  func persistPaperRevisionContext(_ context: PaperRevisionContext) throws {}
}

private enum BoundaryReplacementError: Error { case injectedSave, missingCheckpoint }
