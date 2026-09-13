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

  static func make(penState: PenState, includeCamera: Bool = true,
    verifyPhysicalPose: Bool = true) async throws -> Self {
    // Use synthetic accepted artifacts through the production persistence and
    // Apply Saved Learning path, retaining only the prefix before tip marking.
    let accepted = try await CompleteAcceptedLearningFixture.make()
    let checkpoint = try AcceptedLearningPathCheckpoint(
      semanticIdentity: accepted.identities.learningPathIdentity,
      penInteraction: accepted.checkpoint.penInteraction,
      machineArtifacts: accepted.checkpoint.machineArtifacts,
      machineCamera: accepted.checkpoint.machineCamera,
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
    let app = plotterApplicationRuntime(
      machine: machine,
      observationSessionOverride: includeCamera ? camera : nil,
      statePersistencePort: stores.persistence,
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
      checkpoint: checkpoint, log: log)
  }
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
