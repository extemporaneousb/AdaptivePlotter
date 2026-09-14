import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import PlotterUI
import Testing

@testable import PlotterApp

@MainActor
@Suite("Motion authorization Pen preparation", .serialized)
struct MotionAuthorizationPenPreparationTests {
  @Test("simulated Enable Motion uses the same typed pen preparation without physical evidence")
  func simulatedEnableMotionPreparesPen() async throws {
    let f = makeCausalSimulatorAppFixture()
    let app = f.workspace
    await submitObservationConfigurationForTest(app, .selectSource(.simulated, nil))
    await submitControllerSession(app, .toggleConnection)
    await submitControllerSession(app, .toggleMotionAuthorization)
    await app.submitTestManualPen(.lower)
    await submitControllerSession(app, .toggleMotionAuthorization)
    let before = await f.simulator.snapshot()
    #expect(before.penPose == .down)
    let request = try enableRequest(app)
    #expect(await app.submitPlotterUIRequest(request) == .accepted(requestID: request.id))
    let after = await f.simulator.snapshot()
    #expect(after.penPose == .up)
    #expect(after.mpos == before.mpos)
    #expect(app.frameMode == .simulated)
    #expect(app.controllerSessionProjection.motionAuthorized)
    #expect(app.manualMotionEpisodeSnapshot?.activeOperation == nil)
    #expect(app.machineSnapshot == nil)
    await app.shutdown()
  }

  @Test("explicit Enable Motion settles one retained-profile Pen Up without capture or XY motion",
    arguments: [PenState.unknown, .down, .up])
  func enableMotionPreparesPen(state: PenState) async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make(verifyPhysicalPose: false)
    defer { f.stores.remove() }
    let app = f.application
    await submitControllerSession(app, .toggleMotionAuthorization)
    await f.machine.setPenState(state)
    _ = await app.refreshControllerSessionSnapshot()
    let before = await f.machine.requestedPenCommands
    let captures = await f.camera.poseCaptureCount
    let point = app.machineSnapshot?.machine.position
    let request = try enableRequest(app)
    #expect(await app.submitPlotterUIRequest(request) == .accepted(requestID: request.id))
    #expect(app.controllerSessionProjection.motionAuthorized)
    #expect(app.machineSnapshot?.machine.penState == .up)
    #expect(app.manualMotionEpisodeSnapshot?.activeOperation == nil)
    #expect(await f.machine.requestedPenCommands == before + (state == .up ? [] : [.raise]))
    if state != .up {
      #expect(await f.machine.requestedPenProfiles.last
        == f.accepted.checkpoint.penInteraction?.evidence.actuationProfile)
    }
    #expect(app.machineSnapshot?.machine.position == point)
    #expect(await f.machine.requestedFeeds.isEmpty)
    #expect(await f.machine.requestedDrawingStrokes.isEmpty)
    #expect(await f.camera.poseCaptureCount == captures)
    #expect(app.controllerPoseApplicability.requiresPhysicalPositionForTest)
    #expect(app.interactiveLearningIsComplete)
    #expect(app.tipCameraRegistration == f.accepted.registration)
    await app.shutdown()
  }

  @Test("Connect, probe and Disable Motion never actuate the pen")
  func nonEnableControllerActionsDoNotRaise() async throws {
    let machine = try LowerMachineSessionFixture(log: EventLog(), motionGuardInitiallyActive: false)
    await machine.setPenState(.unknown)
    let app = plotterApplicationRuntime(machine: machine, log: EventLog())
    await app.establishMachineSession(machine.descriptor)
    await submitControllerSession(app, .requestPassiveProbe)
    #expect(await machine.requestedPenCommands.isEmpty)
    #expect(app.machineSnapshot?.machine.penState == .unknown)
    // Establish authorization at the lower fixture to isolate the disabling action.
    _ = await machine.activateMotionGuard()
    _ = await app.refreshControllerSessionSnapshot()
    await submitControllerSession(app, .toggleMotionAuthorization)
    #expect(!app.controllerSessionProjection.motionAuthorized)
    #expect(await machine.requestedPenCommands.isEmpty)
    await app.shutdown()
  }

  @Test("a refused motion guard leaves the pen untouched and authorization disabled")
  func refusedEnableDoesNotRaise() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make(verifyPhysicalPose: false)
    defer { f.stores.remove() }
    let app = f.application
    await submitControllerSession(app, .toggleMotionAuthorization)
    await f.machine.enqueueMotionGuardOutcome(.refused(.controllerRejected("fixture guard rejected")))
    let request = try enableRequest(app)
    _ = await app.submitPlotterUIRequest(request)
    #expect(!app.controllerSessionProjection.motionAuthorized)
    #expect(await f.machine.requestedPenCommands.isEmpty)
    #expect(app.machineSnapshot?.machine.penState == .unknown)
    #expect(app.controllerPoseApplicability.requiresPhysicalPositionForTest)
    #expect(await f.camera.poseCaptureCount == 0)
    await app.shutdown()
  }

  @Test("failed Pen Up preserves its actual outcome and keeps camera recovery unavailable",
    arguments: [false, true])
  func failedEnablePreparationDoesNotClaimReady(ambiguous: Bool) async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make(verifyPhysicalPose: false)
    defer { f.stores.remove() }
    let app = f.application
    await submitControllerSession(app, .toggleMotionAuthorization)
    let outcome: PenOutcome = ambiguous
      ? .ambiguous(.transport("fixture acknowledgement lost"))
      : .refused(.controllerRejected("fixture raise rejected"))
    await f.machine.enqueuePenOutcome(outcome)
    let request = try enableRequest(app)
    _ = await app.submitPlotterUIRequest(request)
    #expect(await f.machine.requestedPenCommands == [.raise])
    #expect(app.machineSnapshot?.machine.lastPenOutcome == outcome)
    #expect(app.machineSnapshot?.machine.penState == .unknown)
    #expect(app.manualMotionEpisodeSnapshot?.activeOperation == nil)
    #expect(app.controllerPoseApplicability.requiresPhysicalPositionForTest)
    #expect(app.interactiveLearningIsComplete)
    let recovery = try recoveryAction(app)
    #expect(!recovery.isAvailable)
    #expect(recovery.unavailableReason != nil)
    #expect(await f.camera.poseCaptureCount == 0)
    #expect(await f.machine.requestedFeeds.isEmpty)
    await app.shutdown()
  }

  @Test("held finite automatic Pen Up blocks duplicate work and joins settlement after request cancellation")
  func heldEnablePreparationKeepsOwnerBoundary() async throws {
    let gate = PenRequestGate()
    let f = try await DrawingWorkbenchApplicationFixture.make(verifyPhysicalPose: false, penRequestGate: gate)
    defer { f.stores.remove() }
    let app = f.application
    await submitControllerSession(app, .toggleMotionAuthorization)
    let request = try enableRequest(app)
    var result: PlotterUIRequestDisposition?
    let enabling = Task {
      let value = await app.submitPlotterUIRequest(request)
      result = value
      return value
    }
    do {
      try await waitUntilAsync {
        if result != nil { return true }
        // Lower execution starts before submit returns the admission snapshot
        // to the application. Observe both owners before asserting its UI.
        return await gate.isHeld && app.manualMotionEpisodeSnapshot?.activeOperation != nil
      }
      try #require(await gate.isHeld, "Enable completed without entering lower Pen hold: \(String(describing: result))")
      _ = await app.refreshControllerSessionSnapshot()
      #expect(app.machineSnapshot?.machine.connection == .actuatingPen)
      #expect(app.machineSnapshot?.machine.penState == .unknown)
      #expect(app.manualMotionEpisodeSnapshot?.activeOperation != nil)
      let heldRecovery = try recoveryAction(app)
      #expect(!heldRecovery.isAvailable)
      let busyProjection = app.testPlotterUIProjection().semantic
      #expect(busyProjection.request(for: PlotterAppUIActionID.controllerMotion) == nil)
      let preparation = PositionPenPreparationControls(plotterUIProjection: busyProjection,
        plotterUIIntentSink: app)
      #expect(preparation.raisePenButton?.title == "Raising Pen…")
      #expect(preparation.raisePenButton?.request == nil)
      #expect(preparation.prerequisiteText == heldRecovery.unavailableReason)
      // The existing finite servo owner does not advertise a cancellable
      // manual capability. Cancelling its caller must still join settlement,
      // without inventing a Stop or allowing a second pen request.
      #expect(busyProjection.request(for: PlotterAppUIActionID.manualStop) == nil)
      let duplicate = await app.submitPlotterUIRequest(request)
      guard case .refused = duplicate else {
        Issue.record("Busy stale enable must be refused: \(duplicate)")
        await gate.releaseFirstRequest(); _ = await enabling.value
        await app.shutdown(); return
      }
      enabling.cancel()
      await gate.releaseFirstRequest()
      _ = await enabling.value
      #expect(app.manualMotionEpisodeSnapshot?.activeOperation == nil)
      #expect(await f.machine.requestedPenCommands == [.raise])
      #expect(await f.machine.requestedFeeds.isEmpty)
      #expect(await f.camera.poseCaptureCount == 0)
      #expect(app.controllerPoseApplicability.requiresPhysicalPositionForTest)
      await app.shutdown()
    } catch {
      await gate.releaseFirstRequest()
      _ = await enabling.value
      await app.shutdown()
      throw error
    }
  }

  @Test("caller cancellation retains completed authorization but prevents the Pen Up successor")
  func cancelledEnablePublishesAuthorizationWithoutPenSuccessor() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make(verifyPhysicalPose: false)
    defer { f.stores.remove() }
    let app = f.application
    await submitControllerSession(app, .toggleMotionAuthorization)
    let gate = TestInspectionSuspension()
    await gate.arm()
    await f.machine.holdMotionGuardActivation(on: gate)
    let request = try enableRequest(app)
    var result: PlotterUIRequestDisposition?
    let enabling = Task {
      let value = await app.submitPlotterUIRequest(request)
      result = value
      return value
    }
    do {
      try await waitUntilAsync {
        if await gate.isWaiting { return true }
        return result != nil
      }
      try #require(await gate.isWaiting,
        "Enable never reached lower authorization hold: \(String(describing: result))")
      #expect(!app.controllerSessionProjection.motionAuthorized)
      enabling.cancel()
      await gate.release()
      let terminal = await enabling.value
      guard case .refused(let refusal) = terminal else {
        Issue.record("Cancelled owner request must surface a typed refusal: \(terminal)")
        await app.shutdown(); return
      }
      #expect(refusal.reason == .retainedOwnerRefused)
      #expect(refusal.remedy.contains("cancelled"))
      #expect((await f.machine.snapshot()).machine.motionGuardState == .active)
      #expect(app.controllerSessionProjection.motionAuthorized)
      #expect(await f.machine.requestedPenCommands.isEmpty)
      #expect(await f.machine.requestedFeeds.isEmpty)
      #expect(await f.camera.poseCaptureCount == 0)
      #expect(app.machineSnapshot?.machine.penState == .unknown)
      #expect(app.controllerPoseApplicability.requiresPhysicalPositionForTest)
      await app.shutdown()
    } catch {
      await gate.release()
      _ = await enabling.value
      await app.shutdown()
      throw error
    }
  }

  @Test("saved profile loading and enabling agree in either order without motion during restore",
    arguments: [40, 55], [false, true])
  func savedProfileAndEnableOrder(raisedValue: Int, loadFirst: Bool) async throws {
    let accepted = try await CompleteAcceptedLearningFixture.make(raisedSpindleValue: raisedValue)
    let stores = CompleteAcceptedLearningStores()
    defer { stores.remove() }
    try await stores.save(accepted)
    let machine = try LowerMachineSessionFixture(log: EventLog(), motionGuardInitiallyActive: false)
    await machine.setPenState(.unknown)
    let clock = ComputationTestClock()
    clock.set(max(clock.read(), accepted.frame.frame.captureNanoseconds))
    let capAnchor = try #require(accepted.checkpoint.machineCamera).registration.fit.cameraPoint(
      from: (await machine.snapshot()).machine.position!.point)
    let camera = try AcceptedDrawingCameraSession(frame: accepted.frame, clock: clock, poseCapAnchor: capAnchor)
    let app = plotterApplicationRuntime(machine: machine, observationSessionOverride: camera,
      statePersistencePort: stores.persistence, drawingEvidencePort: stores.evidencePort,
      tipCalibrationSemanticIdentities: accepted.identities,
      residualEffectPort: TestApplicationResidualEffectPort(
        discoverDevices: { [machine.descriptor] }, readNanoseconds: { clock.read() }),
      loadPenCapAppearanceSelection: { nil }, log: EventLog())
    await app.performApplicationStartup(AdaptivePlotterLaunchPolicy(arguments: []))
    await app.establishMachineSession(machine.descriptor)
    await submitControllerSession(app, .requestPassiveProbe)
    await submitObservationConfigurationForTest(app, .selectSource(.live, camera.device.id))
    if !loadFirst {
      let enable = try enableRequest(app)
      #expect(await app.submitPlotterUIRequest(enable) == .accepted(requestID: enable.id))
      #expect(await machine.requestedPenProfiles == [.initialDefaults])
      #expect(app.machineSnapshot?.machine.penState == .up)
    }
    let commandsBeforeLoad = await machine.requestedPenCommands
    try await applyCompleteSavedLearning(app)
    #expect(await machine.requestedPenCommands == commandsBeforeLoad)
    #expect(app.interactiveLearningIsComplete)
    #expect(app.tipCameraRegistration == accepted.registration)
    #expect(app.controllerPoseApplicability.requiresPhysicalPositionForTest)
    if loadFirst {
      let enable = try enableRequest(app)
      #expect(await app.submitPlotterUIRequest(enable) == .accepted(requestID: enable.id))
    } else if raisedValue != PenActuationProfile.initialDefaults.raisedSpindleValue {
      #expect(app.machineSnapshot?.machine.penState == .unknown)
      #expect((await machine.snapshot()).machine.penState == .unknown)
      let blockedRecovery = try recoveryAction(app)
      #expect(!blockedRecovery.isAvailable)
      let view = DrawingStudioView(presentation: app.drawingStudioPresentation,
        plotterUIProjection: app.testPlotterUIProjection().semantic, plotterUIIntentSink: app)
      let raise = try #require(view.positionRaisePenButton?.request)
      #expect(await app.submitPlotterUIRequest(raise) == .accepted(requestID: raise.id))
    }
    #expect(app.machineSnapshot?.machine.penState == .up)
    #expect(await machine.requestedPenProfiles.last == accepted.checkpoint.penInteraction?.evidence.actuationProfile)
    #expect(await machine.requestedPenCommands.count == (loadFirst || raisedValue == 40 ? 1 : 2))
    let recovery = try recoveryAction(app)
    #expect(recovery.isAvailable)
    #expect(recovery.unavailableReason == nil)
    #expect(await camera.poseCaptureCount == 0)
    #expect(await machine.requestedFeeds.isEmpty)
    #expect(await machine.requestedDrawingStrokes.isEmpty)
    await app.shutdown()
  }

  @Test("a disconnected controller cannot use an old Enable Motion request")
  func staleEnableAfterDisconnectDoesNotRaise() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make(verifyPhysicalPose: false)
    defer { f.stores.remove() }
    let app = f.application
    await submitControllerSession(app, .toggleMotionAuthorization)
    let request = try enableRequest(app)
    await submitControllerSession(app, .toggleConnection)
    let result = await app.submitPlotterUIRequest(request)
    guard case .refused = result else {
      Issue.record("Disconnected stale Enable request must be refused: \(result)")
      await app.shutdown(); return
    }
    #expect(await f.machine.requestedPenCommands.isEmpty)
    #expect(!app.controllerSessionProjection.motionAuthorized)
    #expect(app.controllerPoseApplicability.requiresPhysicalPositionForTest)
    await app.shutdown()
  }

  private func enableRequest(_ app: PlotterApplicationRuntime) throws -> PlotterUIRequest {
    try #require(app.testPlotterUIProjection().semantic.request(for: PlotterAppUIActionID.controllerMotion))
  }

  private func recoveryAction(_ app: PlotterApplicationRuntime) throws -> PlotterUIAction {
    try #require(app.testPlotterUIProjection().semantic.actions.first {
      if case .learningAction(let request) = $0.intent {
        return request.action == .tipCalibration(.revalidateCheckpoint)
      }
      return false
    })
  }
}
