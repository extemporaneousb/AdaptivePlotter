import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import PlotterUI
import Testing

@testable import PlotterApp

@MainActor
@Suite("Saved Learning calibration Pen Up", .serialized)
struct SavedLearningPenUpTests {
  @Test("cap-only replacement retains mechanical authority and durably removes only the optical suffix")
  func reidentifyCapPreservesBoundariesThroughReload() async throws {
    let fixture = try await SavedCameraCalibrationFixture.make(penState: .up, includeTip: true)
    defer { fixture.stores.remove() }
    let app = fixture.app
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let mechanicalKinds = [LearningArtifactKind.penInteraction, .estimatedMachineCenter, .centerArrival]
      + BoundaryDirection.allCases.map { .boundarySideAggregate($0) }
    let revisions = mechanicalKinds.map { app.learningArtifactGraph.currentRevision(for: $0) }
    let pose = app.controllerPoseApplicability
    let position = app.machineSnapshot?.machine.position
    let tipBefore = app.tipCameraRegistration
    // Image capture does not need motion authorization and must not actuate.
    await submitControllerSession(app, .toggleMotionAuthorization)
    let commandsBefore = await fixture.machine.requestedPenCommands
    let feedsBefore = await fixture.machine.requestedFeeds
    await app.performTestExerciseAction(.reidentifyPenCap, for: owner)
    let selection = try #require(app.pointSelectionEpisodeProjection.exactPointSelection.request)
    #expect(app.machineCameraRegistration == fixture.checkpoint.machineCamera?.registration)
    #expect(app.tipCameraRegistration == tipBefore)
    submitPointSelection(app, request: selection, point: try syntheticCapPoint(app))
    try await waitUntil { app.activeExerciseAttemptID == nil || app.discoveryError != nil }
    try #require(app.activeExerciseAttemptID == nil, "\(app.discoveryError ?? "Cap selection did not settle")")
    #expect(app.discoveryError == nil)
    #expect(mechanicalKinds.map { app.learningArtifactGraph.currentRevision(for: $0) } == revisions)
    #expect(app.controllerPoseApplicability == pose)
    #expect(app.machineSnapshot?.machine.position == position)
    #expect(app.machineCameraRegistration == nil)
    #expect(app.tipCameraRegistration == nil)
    #expect(app.penInteractionCompleted)
    #expect(app.relevantBoundaryObservationCount == 4)
    #expect(app.testCurrentLearningPathItemID == .humanGuidedDiscovery(.calibrateCameraAndVisibleCap))
    #expect(await fixture.machine.requestedPenCommands == commandsBefore)
    #expect(await fixture.machine.requestedFeeds == feedsBefore)
    #expect(app.restartableExerciseItemID == nil)
    guard case .loaded(let saved) = fixture.stores.checkpointStore.load() else {
      Issue.record("Expected durable cap replacement"); await app.shutdown(); return
    }
    #expect(saved.penInteraction == fixture.checkpoint.penInteraction)
    #expect(saved.machineArtifacts == fixture.checkpoint.machineArtifacts)
    #expect(saved.penCapAppearance != fixture.checkpoint.penCapAppearance)
    #expect(saved.referenceFrame?.frame.id.rawValue == selection.frame.frameID)
    #expect(saved.machineCamera == nil && saved.tipCalibration == nil && saved.stageFour == nil)
    await app.shutdown()
    let reloaded = plotterApplicationRuntime(machine: fixture.machine,
      statePersistencePort: fixture.stores.persistence,
      tipCalibrationSemanticIdentities: fixture.identities,
      loadPenCapAppearanceSelection: { nil }, log: fixture.log)
    await reloaded.performTestExerciseAction(.applySavedLearning, for: reloaded.testCurrentLearningPathItemID)
    #expect(reloaded.penInteractionCompleted)
    #expect(reloaded.relevantBoundaryObservationCount == 4)
    #expect(try reloaded.penCapAppearanceSelection?.acceptedCheckpoint() == saved.penCapAppearance)
    #expect(reloaded.machineCameraRegistration == nil && reloaded.tipCameraRegistration == nil)
    await reloaded.shutdown()
  }

  @Test("cancel, stale click, capture failure, and failed cap save retain previous Learning",
    arguments: ["cancel", "stale", "capture-failure", "save-failure"])
  func unsuccessfulCapReplacementRetainsLearning(outcome: String) async throws {
    let fixture = try await SavedCameraCalibrationFixture.make(penState: .up, includeTip: true,
      rejectCapReplacementSave: outcome == "save-failure")
    defer { fixture.stores.remove() }
    let app = fixture.app
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let revisions = app.learningArtifactGraph.revisions
    let cap = app.penCapAppearanceSelection
    guard case .loaded(let original) = fixture.stores.checkpointStore.load() else {
      Issue.record("Expected saved calibration"); await app.shutdown(); return
    }
    if outcome == "capture-failure" { await fixture.camera.injectFrameCaptureFailure() }
    await app.performTestExerciseAction(.reidentifyPenCap, for: owner)
    if outcome == "capture-failure" {
      #expect(app.activeExerciseAttemptID == nil)
      #expect(app.pointSelectionEpisodeProjection.exactPointSelection.request == nil)
      #expect(app.discoveryError?.contains("could not freeze") == true)
    } else if outcome == "save-failure" {
      let selection = try #require(app.pointSelectionEpisodeProjection.exactPointSelection.request)
      submitPointSelection(app, request: selection, point: try syntheticCapPoint(app))
      try await waitUntil { app.activeExerciseAttemptID == nil || app.discoveryError != nil }
      try #require(app.activeExerciseAttemptID == nil, "\(app.discoveryError ?? "Cap selection did not settle")")
      #expect(app.discoveryError?.contains("Previous Learning is retained") == true)
    } else {
      let selection = try #require(app.pointSelectionEpisodeProjection.exactPointSelection.request)
      await app.performTestExerciseAction(.cancel, for: owner)
      if outcome == "stale" {
        await app.performTestExerciseAction(.reidentifyPenCap, for: owner)
        submitPointSelection(app, request: selection, point: try Point2(x: 40, y: 40))
        try await waitUntil { app.discoveryError?.contains("rejected") == true }
        #expect(app.activeExerciseAttemptID != nil)
        await app.performTestExerciseAction(.cancel, for: owner)
      }
    }
    #expect(app.learningArtifactGraph.revisions == revisions)
    #expect(app.penCapAppearanceSelection == cap)
    #expect(app.machineCameraRegistration == original.machineCamera?.registration)
    #expect(app.tipCameraRegistration == original.tipCalibration?.registration)
    #expect(app.restartableExerciseItemID == nil)
    #expect(await fixture.machine.requestedPenCommands.isEmpty)
    #expect(await fixture.machine.requestedFeeds.isEmpty)
    guard case .loaded(let saved) = fixture.stores.checkpointStore.load() else {
      Issue.record("Expected unchanged package"); await app.shutdown(); return
    }
    #expect(saved == original)
    await app.shutdown()
  }

  @Test("scoped reset preserves compatible Pen optical evidence through disk reload without legacy fallback", arguments: [false, true])
  func scopedCameraResetRetainsOpticalPrefix(resetTip: Bool) async throws {
    let fixture = try await SavedCameraCalibrationFixture.make(penState: .up, includeTip: resetTip)
    defer { fixture.stores.remove() }
    let app = fixture.app
    let original = fixture.checkpoint
    let appearance = try #require(original.penCapAppearance)
    guard case .loaded(let beforeReset) = fixture.stores.checkpointStore.load() else {
      Issue.record("Expected accepted prefix before reset"); await app.shutdown(); return
    }
    let reference = try #require(beforeReset.referenceFrame)
    let owner = LearningPathItemID.humanGuidedDiscovery(
      resetTip ? .calibratePenContactFromSparseMarks : .calibrateCameraAndVisibleCap)
    let plan = try #require(app.learningVacatePlan(from: owner))
    #expect(await app.performLearningVacate(plan))
    guard case .loaded(let saved) = fixture.stores.checkpointStore.load() else {
      Issue.record("Expected durable scoped prefix"); await app.shutdown(); return
    }
    #expect(saved.penInteraction == original.penInteraction)
    #expect(saved.machineArtifacts == original.machineArtifacts)
    #expect(saved.machineCamera == (resetTip ? original.machineCamera : nil))
    #expect(saved.tipCalibration == nil)
    #expect(saved.penCapAppearance == appearance)
    #expect(saved.referenceFrame == reference)
    await app.shutdown()
    let reloaded = plotterApplicationRuntime(
      machine: fixture.machine, statePersistencePort: fixture.stores.persistence,
      tipCalibrationSemanticIdentities: fixture.identities,
      loadPenCapAppearanceSelection: { nil }, log: fixture.log)
    #expect(reloaded.penCapAppearanceSelection == nil)
    await reloaded.performTestExerciseAction(.applySavedLearning, for: reloaded.testCurrentLearningPathItemID)
    #expect(try reloaded.penCapAppearanceSelection?.acceptedCheckpoint() == appearance)
    #expect(reloaded.penInteractionCompleted)
    let penPlan = try #require(reloaded.learningVacatePlan(from: .humanGuidedDiscovery(.penInteraction)))
    #expect(await reloaded.performLearningVacate(penPlan))
    #expect(reloaded.penCapAppearanceSelection == nil)
    await reloaded.shutdown()
  }

  @Test("scoped Camera reset refuses stale optical prefix after current frame dimensions change")
  func scopedResetDropsIncompatibleOpticalPrefix() async throws {
    let fixture = try await SavedCameraCalibrationFixture.make(penState: .up)
    defer { fixture.stores.remove() }
    let app = fixture.app
    let previous = try #require(app.displayedFrame)
    let width = previous.frame.width + 1
    let changed = DisplayedFrame(source: previous.source, frame: try StampedFrame(
      id: FrameID(), sequence: previous.frame.sequence + 1,
      captureNanoseconds: previous.frame.captureNanoseconds + 1_000,
      cameraConfigurationID: CameraConfigurationID(), width: width,
      height: previous.frame.height, rowBytes: width * 4,
      pixelFormat: previous.frame.pixelFormat,
      bytes: OwnedFrameBytes(copying: Data(repeating: 0, count: width * 4 * previous.frame.height))))
    fixture.camera.previewFrames.inject(changed)
    try await waitUntil { app.actionSurfacePreview.latestFrameSnapshot?.frame.id == changed.frame.id }
    let plan = try #require(app.learningVacatePlan(from:
      .humanGuidedDiscovery(.calibrateCameraAndVisibleCap)))
    #expect(await app.performLearningVacate(plan))
    guard case .loaded(let saved) = fixture.stores.checkpointStore.load() else {
      Issue.record("Expected prefix"); await app.shutdown(); return
    }
    #expect(saved.penInteraction == fixture.checkpoint.penInteraction)
    #expect(saved.penCapAppearance == nil)
    #expect(saved.referenceFrame == nil)
    await app.shutdown()
  }

  @Test("saved camera calibration admits circles from Unknown or Down and settles Pen Up before travel",
    arguments: [PenState.unknown, .down], [false, true])
  func batchOwnsInitialPenUp(penState: PenState, raiseFails: Bool) async throws {
    let fixture = try await SavedCameraCalibrationFixture.make(penState: penState)
    let app = fixture.app
    let machine = fixture.machine
    defer { fixture.stores.remove() }
    let owner = LearningPathItemID.humanGuidedDiscovery(.calibratePenContactFromSparseMarks)

    #expect(app.testCurrentLearningPathItemID == owner)
    #expect(app.penInteractionCompleted)
    #expect(app.machineCameraRegistration == fixture.checkpoint.machineCamera?.registration)
    #expect(app.tipCameraRegistration == nil)
    #expect(await machine.requestedPenCommands.isEmpty)
    #expect(await machine.requestedFeeds.isEmpty)
    #expect(app.machineSnapshot?.machine.penState == penState)

    let initialAction = try #require(app.currentExerciseActionStripPresentation?.actions.first {
      $0.kind == .tipCalibration(.beginFourMarkBatch)
    })
    try #require(initialAction.isEnabled, "\(initialAction.unavailableReason ?? "Circle action unavailable")")

    // Motion authorization remains a separate operator decision.
    await submitControllerSession(app, .toggleMotionAuthorization)
    let blocked = try #require(app.currentExerciseActionStripPresentation?.actions.first {
      $0.kind == .tipCalibration(.beginFourMarkBatch)
    })
    #expect(!blocked.isEnabled)
    #expect(blocked.unavailableReason?.contains("Motion authorization") == true)
    // This test isolates calibration's own normalization from Enable Motion's
    // preparation. An already-Up enable emits no command; then model the later
    // Unknown/Down state that the calibration owner must handle independently.
    await machine.setPenState(.up)
    _ = await app.refreshControllerSessionSnapshot()
    await submitControllerSession(app, .toggleMotionAuthorization)
    await machine.setPenState(penState)
    _ = await app.refreshControllerSessionSnapshot()

    if raiseFails {
      await machine.enqueuePenOutcome(.refused(.controllerRejected("initial raise refused")))
    }
    let drawing = Task {
      await app.performTestExerciseAction(.tipCalibration(.beginFourMarkBatch), for: owner)
    }
    do {
      try await waitUntilAsync { await machine.requestedPenCommands == [.raise] }
      await fixture.penGate.waitUntilHeld()
      #expect(await machine.requestedFeeds.isEmpty)
      #expect(await machine.requestedDrawingStrokes.isEmpty)
      #expect((await machine.snapshot()).machine.penState == penState)
      #expect(app.contextualStopPresentation != nil)
      #expect(await machine.requestedPenProfiles == [
        try #require(fixture.checkpoint.penInteraction?.evidence.actuationProfile)
      ])

      await fixture.penGate.releaseFirstRequest()
      if raiseFails {
        await drawing.value
        #expect(await machine.requestedFeeds.isEmpty)
        #expect(await machine.requestedDrawingStrokes.isEmpty)
        #expect((await machine.snapshot()).machine.penState == penState)
      } else {
        try await waitUntilAsync { await machine.relativeJogIsAwaitingSettlement }
        #expect((await machine.snapshot()).machine.penState == .up)
        let events = await fixture.log.values
        let raise = try #require(events.firstIndex(of: "machine:pen-raise"))
        let travel = try #require(events.firstIndex(of: "machine:jog"))
        #expect(raise < travel)
        #expect(await machine.requestedDrawingStrokes.isEmpty)
        let stop = try #require(app.contextualStopPresentation?.capabilityID)
        await app.performTestExerciseAction(.stop(stop), for: owner)
        await drawing.value
      }
      #expect(await machine.requestedPenCommands == [.raise])
      #expect(app.tipCameraRegistration == nil)
      #expect(app.blacklistedToolContactLocations.isEmpty)
      #expect(app.contextualStopPresentation == nil)
      await app.shutdown()
    } catch {
      await fixture.penGate.releaseFirstRequest()
      await app.shutdown()
      await drawing.value
      throw error
    }
  }

  @Test("saved cap-map prefix blocks marking until current physical position is observed")
  func prefixRequiresPhysicalPositionBeforeMarking() async throws {
    let fixture = try await SavedCameraCalibrationFixture.make(penState: .up,
      verifyPhysicalPose: false)
    defer { fixture.stores.remove() }
    let app = fixture.app
    #expect(app.penInteractionCompleted)
    #expect(app.machineCameraRegistration != nil)
    #expect(app.tipCameraRegistration == nil)
    #expect(app.controllerPoseApplicability.requiresPhysicalPositionForTest)
    let action = try #require(app.currentExerciseActionStripPresentation?.actions.first {
      $0.kind == .tipCalibration(.revalidateCheckpoint)
    })
    #expect(action.isEnabled)
    _ = try physicalPositionRequest(app)
    await assertSavedPrefixMarkingIsRefused(app)
    #expect(await fixture.machine.requestedFeeds.isEmpty)
    #expect(await fixture.machine.requestedPenCommands.isEmpty)
    try await reestablishPhysicalPositionForTest(app)
    let marking = try #require(app.currentExerciseActionStripPresentation?.actions.first {
      $0.kind == .tipCalibration(.beginFourMarkBatch)
    })
    #expect(marking.isEnabled)
    #expect(app.tipCameraRegistration == nil)
    #expect(app.penInteractionCompleted)
    #expect(await fixture.machine.requestedFeeds.isEmpty)
    #expect(await fixture.machine.requestedPenCommands.isEmpty)
    await app.shutdown()
  }

  @Test("the automatic raise does not remove the live camera prerequisite")
  func cameraIsStillRequired() async throws {
    let fixture = try await SavedCameraCalibrationFixture.make(penState: .unknown, includeCamera: false)
    defer { fixture.stores.remove() }
    let action = try #require(fixture.app.currentExerciseActionStripPresentation?.actions.first {
      $0.kind == .tipCalibration(.revalidateCheckpoint)
    })
    #expect(!action.isEnabled)
    #expect(action.unavailableReason == "Show the current Plotter Video camera.")
    await assertSavedPrefixMarkingIsRefused(fixture.app)
    #expect(await fixture.machine.requestedFeeds.isEmpty)
    #expect(await fixture.machine.requestedDrawingStrokes.isEmpty)
    #expect(await fixture.machine.requestedPenCommands.isEmpty)
    await fixture.app.shutdown()
  }
}

@MainActor
private struct SavedCameraCalibrationFixture {
  let app: PlotterApplicationRuntime
  let machine: LowerMachineSessionFixture
  let penGate: PenRequestGate
  let stores: CompleteAcceptedLearningStores
  let checkpoint: AcceptedLearningPathCheckpoint
  let log: EventLog
  let identities: TipCalibrationSemanticIdentityState
  let camera: AcceptedDrawingCameraSession

  static func make(penState: PenState, includeCamera: Bool = true,
    verifyPhysicalPose: Bool = true, includeTip: Bool = false,
    rejectCapReplacementSave: Bool = false) async throws -> Self {
    // Use synthetic accepted artifacts through the production persistence and
    // Apply Saved Learning path, retaining only the prefix before tip marking.
    let accepted = try await CompleteAcceptedLearningFixture.make()
    let checkpoint = try AcceptedLearningPathCheckpoint(
      semanticIdentity: accepted.identities.learningPathIdentity,
      penInteraction: accepted.checkpoint.penInteraction,
      machineArtifacts: accepted.checkpoint.machineArtifacts,
      machineCamera: accepted.checkpoint.machineCamera,
      tipCalibration: includeTip ? accepted.checkpoint.tipCalibration : nil,
      penCapAppearance: accepted.checkpoint.penCapAppearance,
      referenceFrame: accepted.checkpoint.referenceFrame
    )
    let stores = CompleteAcceptedLearningStores()
    try stores.checkpointStore.save(checkpoint)
    let log = EventLog()
    let penGate = PenRequestGate()
    let machine = try LowerMachineSessionFixture(log: log, penRequestGate: penGate)
    await machine.setPenState(penState)
    let clock = ComputationTestClock()
    clock.set(max(clock.read(), accepted.frame.frame.captureNanoseconds))
    let capAnchor = try #require(checkpoint.machineCamera).registration.fit.cameraPoint(
      from: (await machine.snapshot()).machine.position!.point)
    let camera = try AcceptedDrawingCameraSession(frame: accepted.frame, clock: clock, poseCapAnchor: capAnchor)
    let basePersistence = stores.persistence
    let persistence: any PlotterApplicationStatePersistencePort = rejectCapReplacementSave
      ? TestApplicationStatePersistencePort(
        loadCheckpoint: { basePersistence.loadAcceptedLearningPathCheckpoint() },
        saveCheckpoint: { candidate in
          if candidate.penCapAppearance != checkpoint.penCapAppearance {
            throw LearningPathOperationError.requiredState("Injected cap save failure")
          }
          try basePersistence.saveAcceptedLearningPathCheckpoint(candidate)
        },
        clearCheckpoint: { try basePersistence.clearAcceptedLearningPathCheckpoint() }
      ) : basePersistence
    let app = plotterApplicationRuntime(
      machine: machine,
      observationSessionOverride: includeCamera ? camera : nil,
      statePersistencePort: persistence,
      tipCalibrationSemanticIdentities: accepted.identities,
      residualEffectPort: TestApplicationResidualEffectPort(
        discoverDevices: { [machine.descriptor] }, readNanoseconds: { clock.read() }),
      loadPenCapAppearanceSelection: { nil }, log: log
    )
    await app.performApplicationStartup(AdaptivePlotterLaunchPolicy(arguments: []))
    await app.establishMachineSession(machine.descriptor)
    await submitControllerSession(app, .requestPassiveProbe)
    if includeCamera {
      await submitObservationConfigurationForTest(app, .selectSource(.live, camera.device.id))
    }
    try await applyCompleteSavedLearning(app)
    if includeCamera && verifyPhysicalPose {
      await machine.setPenState(.up)
      _ = await app.refreshControllerSessionSnapshot()
      try await reestablishPhysicalPositionForTest(app)
      await machine.setPenState(penState)
      _ = await app.refreshControllerSessionSnapshot()
    }
    return Self(app: app, machine: machine, penGate: penGate, stores: stores,
      checkpoint: checkpoint, log: log, identities: accepted.identities, camera: camera)
  }
}

/// Locate this fixture's generated green armature, whose bottom is its cap
/// anchor. This is test-input construction, not the production reference matcher.
@MainActor
private func syntheticCapPoint(_ app: PlotterApplicationRuntime) throws -> Point2<CameraPixelSpace> {
  let frame = try #require(app.testActionSurfacePresentation.displayedFrame).frame
  var capPixels: [(Int, Int)] = []
  frame.bytes.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
    for y in 0..<frame.height {
      for x in 0..<frame.width {
        let i = y * frame.rowBytes + x * 4
        if bytes[i] == 0, bytes[i + 1] == 150, bytes[i + 2] == 0 {
          capPixels.append((x, y))
        }
      }
    }
  }
  let bottom = try #require(capPixels.map { $0.1 }.max())
  let xs = capPixels.filter { $0.1 == bottom }.map { Double($0.0) }
  return try Point2(x: (try #require(xs.min()) + #require(xs.max())) / 2, y: Double(bottom))
}

@MainActor
private func assertSavedPrefixMarkingIsRefused(_ app: PlotterApplicationRuntime) async {
  let owner = LearningPathItemID.humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
  let projection = app.testPlotterUIProjection(selectedItemID: owner, includesLearningPath: true).semantic
  let learning = PlotterLearningActionRequest(
    item: .init(rawValue: "\(owner.number)-\(owner.title)"), action: .tipCalibration(.beginFourMarkBatch))
  #expect(projection.request(matching: .learningAction(learning)) == nil)
  let request = PlotterUIRequest(id: .init(rawValue: UUID()), uiRevision: projection.revision,
    runtimeRevisions: projection.runtimeRevisions, actionID: .init(learningRequest: learning),
    intent: .learningAction(learning))
  guard case .refused = await app.submitPlotterUIRequest(request) else {
    Issue.record("Saved cap-map prefix admitted marking without current physical-position evidence")
    return
  }
}
