import Foundation
import PlotterModel
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Operator workspace learning runtime")
@MainActor
struct OperatorWorkspaceTests {
  @Test("successful LIVE camera start and restart enable automatic overlays")
  func cameraStartEnablesAutomaticOverlays() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)

    await workspace.startCamera()
    #expect(workspace.automaticVisionEnabled)
    #expect(workspace.visibleLayers == Set(CanvasLayer.allCases))
    #expect(camera.recordedAutomaticCadences == [.fiveFPS])
    #expect(
      workspace.cameraUtilityPresentation.actions.first {
        $0.kind == .toggleAutomaticAnalysis
      }?.title == "Stop Auto Analysis"
    )

    await workspace.restartCamera()
    #expect(workspace.automaticVisionEnabled)
    #expect(camera.recordedAutomaticCadences == [.fiveFPS, .fiveFPS])
    await workspace.setAutomaticVisionAnalysis(false)
    #expect(!workspace.automaticVisionEnabled)
    #expect(
      workspace.cameraUtilityPresentation.actions.first {
        $0.kind == .toggleAutomaticAnalysis
      }?.title == "Start Auto Analysis"
    )
    await workspace.shutdown()
  }

  @Test("manual contextual Stop sends one cancel and creates no boundary evidence")
  func manualStopHasNoBoundaryEvidence() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let workspace = workspace(machine: machine, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()

    let request = RelativeJogRequest(
      delta: try Vector2(dx: 1, dy: 0),
      feedMMPerMinute: 100
    )
    let owner = Task { await workspace.requestRelativeJog(request) }
    try await waitUntil { workspace.contextualStopPresentation != nil }
    let capabilityID = try #require(workspace.manualMotionPresentation.stopAction?.capabilityID)
    #expect(workspace.controllerSessionEstablished)
    #expect(workspace.motionAuthorizationEnabled)
    if case .busy = workspace.motionRequestStatusPresentation {
      // Expected: authorization remains enabled while transient availability is busy.
    } else {
      Issue.record("Expected a busy motion-request projection while the manual jog owns motion.")
    }
    async let first: Void = workspace.stopManualJog(capabilityID: capabilityID)
    async let repeated: Void = workspace.stopManualJog(capabilityID: capabilityID)
    _ = await (first, repeated)
    _ = await owner.value

    #expect(await machine.cancelCount == 1)
    #expect(await machine.cancelIntents == [.operatorStop])
    #expect(workspace.relevantBoundaryObservationCount == 0)
    #expect(workspace.discoveryTransactions.isEmpty)
    #expect(workspace.contextualStopPresentation == nil)

    let secondOwner = Task { await workspace.requestRelativeJog(request) }
    try await waitUntil { workspace.manualMotionPresentation.stopAction != nil }
    let secondCapabilityID = try #require(
      workspace.manualMotionPresentation.stopAction?.capabilityID
    )
    #expect(secondCapabilityID != capabilityID)
    await workspace.stopManualJog(capabilityID: capabilityID)
    #expect(await machine.cancelCount == 1)
    #expect(workspace.manualMotionPresentation.stopAction?.capabilityID == secondCapabilityID)
    await workspace.stopManualJog(capabilityID: secondCapabilityID)
    _ = await secondOwner.value
    #expect(await machine.cancelCount == 2)
    await workspace.shutdown()
  }

  @Test("boundary Stop records Stop first, settles owner, captures fresh frame, and updates posterior")
  func boundaryStopCompletesTransaction() async throws {
    let log = EventLog()
    let machine = try MachineFixture(
      log: log,
      feedLimits: ControllerAxisFeedLimits(
        maximumXFeedMMPerMinute: 900,
        maximumYFeedMMPerMinute: 600
      )
    )
    let camera = try CameraFixture()
    let announcements = AnnouncementFixture(log: log, outcomes: [.failed("test failure")])
    let workspace = workspace(
      machine: machine,
      camera: camera,
      announcements: announcements,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)

    let owner = LearningPathItemID.humanGuidedDiscovery(.boundaryDiscovery)
    #expect(workspace.currentLearningPathItemID == owner)
    await workspace.performExerciseAction(.start, for: owner)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    let liveActions = try #require(workspace.currentExerciseActionStripPresentation).actions
    #expect(liveActions.filter { if case .stop = $0.kind { true } else { false } }.count == 1)
    #expect(liveActions.filter { $0.kind == .cancel }.count == 1)
    #expect(!liveActions.contains(where: { if case .choice = $0.kind { true } else { false } }))
    let stopKind = try #require(liveActions.first(where: {
      if case .stop = $0.kind { true } else { false }
    })?.kind)
    async let first: Void = workspace.performExerciseAction(stopKind, for: owner)
    async let repeated: Void = workspace.performExerciseAction(stopKind, for: owner)
    _ = await (first, repeated)

    #expect(await machine.cancelCount == 1)
    #expect(await machine.cancelIntents == [.operatorStop])
    #expect(await machine.requestedFeeds.last == 900)
    #expect(workspace.discoveryTransactions[.boundaryPositiveX]?.state == .succeeded)
    #expect(workspace.relevantBoundaryObservationCount == 1)
    #expect(workspace.drawingFramePosterior?.observationCount == 1)
    #expect(workspace.humanGuidedDiscoveryCurrentStep == .clearViewDiscovery)
    #expect(workspace.lastContextualStopAuditRecord?.actor == "Operator")
    #expect(workspace.lastContextualStopAuditRecord?.action == "Stop")
    #expect(workspace.lastContextualStopAuditRecord?.disposition == .operatorStop)
    #expect(workspace.currentExerciseActionStripPresentation?.actions.map(\.kind) == [.start])
    let events = await log.values
    #expect(events.firstIndex(of: "announce:Moving toward X+ boundary.")! < events.firstIndex(of: "machine:boundary")!)
    await workspace.shutdown()
  }

  @Test("Boundary Stop and Cancel races latch one semantic disposition and one cancel")
  func boundaryStopCancelFirstIntentWins() async throws {
    let stopLog = EventLog()
    let stopMachine = try MachineFixture(log: stopLog, holdCancellationSettlement: true)
    let stopWorkspace = workspace(
      machine: stopMachine,
      camera: try CameraFixture(),
      log: stopLog
    )
    await stopWorkspace.establishMachineSession(stopMachine.descriptor)
    await stopWorkspace.requestPassiveProbe()
    await stopWorkspace.startCamera()
    try await completePenInteraction(stopWorkspace)
    let owner = LearningPathItemID.humanGuidedDiscovery(.boundaryDiscovery)
    await stopWorkspace.performExerciseAction(.start, for: owner)
    try await waitUntil { stopWorkspace.contextualStopPresentation != nil }
    let stopKind = try #require(
      stopWorkspace.currentExerciseActionStripPresentation?.actions.first(where: {
        if case .stop = $0.kind { true } else { false }
      })?.kind
    )
    let stopTask = Task { await stopWorkspace.performExerciseAction(stopKind, for: owner) }
    try await waitUntilAsync { await stopMachine.cancelCount == 1 }
    await stopWorkspace.performExerciseAction(.cancel, for: owner)
    #expect(await stopMachine.cancelIntents == [.operatorStop])
    await stopMachine.settleHeldCancellation()
    await stopTask.value
    #expect(stopWorkspace.relevantBoundaryObservationCount == 1)
    await stopWorkspace.shutdown()

    let cancelLog = EventLog()
    let cancelMachine = try MachineFixture(log: cancelLog, holdCancellationSettlement: true)
    let cancelWorkspace = workspace(
      machine: cancelMachine,
      camera: try CameraFixture(),
      log: cancelLog
    )
    await cancelWorkspace.establishMachineSession(cancelMachine.descriptor)
    await cancelWorkspace.requestPassiveProbe()
    await cancelWorkspace.startCamera()
    try await completePenInteraction(cancelWorkspace)
    await cancelWorkspace.performExerciseAction(.start, for: owner)
    try await waitUntil { cancelWorkspace.contextualStopPresentation != nil }
    let staleStopKind = try #require(
      cancelWorkspace.currentExerciseActionStripPresentation?.actions.first(where: {
        if case .stop = $0.kind { true } else { false }
      })?.kind
    )
    let cancelTask = Task { await cancelWorkspace.performExerciseAction(.cancel, for: owner) }
    try await waitUntilAsync { await cancelMachine.cancelCount == 1 }
    await cancelWorkspace.performExerciseAction(staleStopKind, for: owner)
    #expect(await cancelMachine.cancelIntents == [.cancelAttempt])
    await cancelMachine.settleHeldCancellation()
    await cancelTask.value
    #expect(cancelWorkspace.relevantBoundaryObservationCount == 0)
    #expect(cancelWorkspace.currentExerciseActionStripPresentation?.actions.map(\.kind) == [.restart])
    await cancelWorkspace.shutdown()
  }

  @Test("SIMULATED runs the complete Learning Path through Boundary Stop without MachineActions")
  func simulatedLearningPathHasFullActionParity() async throws {
    let machineActionLog = EventLog()
    let clock = TestClock()
    let workspace = OperatorWorkspace(
      machineActions: isolatedMachineActions(log: machineActionLog),
      cameraActions: CameraComposition.actions,
      serialDevices: [],
      serialDeviceDiscovery: { [] },
      loadSelectedSerialIdentifier: { nil },
      persistSelectedSerialIdentifier: { _ in },
      nowNanoseconds: { clock.next() }
    )

    await workspace.switchFrameMode(.simulated)
    #expect(workspace.frameMode == .simulated)
    #expect(workspace.currentLearningPathItemID == .stage(.connect))
    #expect(workspace.simulatorEvidenceLabel == "SIMULATED — NOT PHYSICAL EVIDENCE")
    #expect(workspace.cameraUtilityPresentation.actions.map(\.kind) == CameraUtilityActionKind.allCases)

    await workspace.performControllerConnectionAction()
    #expect(workspace.currentLearningPathItemID == .stage(.enableMotion))
    await workspace.activateMotionGuard()
    #expect(workspace.controllerSessionEstablished)
    #expect(workspace.motionAuthorizationEnabled)
    #expect(workspace.currentLearningPathItemID == .humanGuidedDiscovery(.penInteraction))

    let penOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await performStart(workspace, owner: penOwner)
    for _ in 0..<4 {
      let presentation = workspace.selectedOperatorActionPresentation(for: penOwner)
      #expect(presentation.question?.prompt.isEmpty == false)
      #expect(presentation.question?.choices == [.yes, .no])
      await workspace.performExerciseAction(.choice(.yes), for: penOwner)
    }
    #expect(workspace.penInteractionCompleted)

    let boundaryOwner = LearningPathItemID.humanGuidedDiscovery(.boundaryDiscovery)
    #expect(workspace.currentLearningPathItemID == boundaryOwner)
    await performStart(workspace, owner: boundaryOwner)
    try await waitUntil {
      workspace.currentExerciseActionStripPresentation?.actions.contains(where: {
        if case .stop = $0.kind { true } else { false }
      }) == true
    }
    let boundaryActions = try #require(
      workspace.currentExerciseActionStripPresentation?.actions
    )
    #expect(!boundaryActions.contains(where: { if case .choice = $0.kind { true } else { false } }))
    let stopKind = try #require(boundaryActions.first(where: {
      if case .stop = $0.kind { true } else { false }
    })?.kind)
    await workspace.performExerciseAction(stopKind, for: boundaryOwner)
    #expect(workspace.relevantBoundaryObservationCount == 1)
    #expect(workspace.lastContextualStopAuditRecord?.disposition == .operatorStop)

    let clearOwner = LearningPathItemID.humanGuidedDiscovery(.clearViewDiscovery)
    #expect(workspace.currentLearningPathItemID == clearOwner)
    await performStart(workspace, owner: clearOwner)
    await workspace.performExerciseAction(.recordClearViewLabel(.clear), for: clearOwner)
    await workspace.performExerciseAction(.acceptCurrentClearView, for: clearOwner)
    #expect(workspace.clearViewPoseAccepted)

    for step in ObservedDrawingTrialStep.allCases where step != .compareIntendedAndObservedGeometry {
      let owner = LearningPathItemID.observedDrawingTrial(step)
      #expect(workspace.currentLearningPathItemID == owner)
      await performStart(workspace, owner: owner)
    }
    let comparisonOwner = LearningPathItemID.observedDrawingTrial(
      .compareIntendedAndObservedGeometry
    )
    #expect(workspace.currentLearningPathItemID == comparisonOwner)
    await performStart(workspace, owner: comparisonOwner)
    await workspace.performExerciseAction(
      .recordDrawingTrialAssessment(.observedGeometryAccepted),
      for: comparisonOwner
    )

    #expect(workspace.currentLearningPathItemID == .stage(.adaptiveDrawing))
    #expect(workspace.drawingTrialAssessment == .observedGeometryAccepted)
    #expect(workspace.displayedFrame?.source == .simulated)
    #expect(await machineActionLog.values.isEmpty)
  }

  @Test("SIMULATED learning is discarded and the parked LIVE authority is restored")
  func simulatedLearningDoesNotReplaceLiveAuthority() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    await workspace.beginBoundaryDiscovery(.positiveY)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)

    let livePenRevisionID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id
    )
    let liveBoundaryRevisionID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .boundaryObservation(.positiveY))?.id
    )
    await workspace.switchFrameMode(.simulated)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .penInteraction) == nil)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .boundaryObservation(.positiveY)) == nil
    )

    await workspace.switchFrameMode(.live)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id == livePenRevisionID
    )
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .boundaryObservation(.positiveY))?.id
        == liveBoundaryRevisionID
    )
    await workspace.shutdown()
  }

  @Test("logical boundary owner exposes Stop without a moving-state timer or natural success")
  func boundaryOwnerDoesNotAssumeMovingOrNaturalSuccess() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log, reportsBoundaryMoving: false)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)

    await workspace.beginBoundaryDiscovery(.negativeY)
    try await waitUntil { workspace.contextualStopPresentation != nil }

    #expect(workspace.machineSnapshot?.machine.connection == .connected)
    #expect(workspace.relevantBoundaryObservationCount == 0)
    #expect(workspace.drawingFramePosterior == nil)
    try await stopActiveOperation(workspace)
    #expect(workspace.relevantBoundaryObservationCount == 1)
    await workspace.shutdown()
  }

  @Test("invalid manual step text does not gate Boundary Discovery")
  func manualStepTextIsNotBoundaryAuthority() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    workspace.xStepText = "not-a-number"
    workspace.yStepText = ""

    #expect(workspace.motionUnavailableReason != nil)
    #expect(workspace.discoveryStartUnavailableReason(for: .boundaryPositiveX) == nil)
    await workspace.beginBoundaryDiscovery(.positiveX)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)
    #expect(workspace.relevantBoundaryObservationCount == 1)
    await workspace.shutdown()
  }

  @Test("shutdown stops an active boundary before draining and erasing its authority")
  func authorityClearingStopsBeforeErasure() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()

    await workspace.beginBoundaryDiscovery(.negativeY)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    await workspace.shutdown()

    #expect(await machine.cancelCount == 1)
    #expect(await machine.cancelIntents == [.shutdown])
    #expect(await machine.requestedFeeds.last == 100)
    #expect(workspace.discoveryTransactions.isEmpty)
    #expect(workspace.contextualStopPresentation == nil)
    #expect(workspace.isShutdown)
  }

  @Test("announcement failure is advisory and Pen Interaction preserves output-before-actuation order")
  func announcementFailureDoesNotGatePenInteraction() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let announcements = AnnouncementFixture(
      log: log,
      outcomes: [.failed("output unavailable"), .completed]
    )
    let workspace = workspace(
      machine: machine,
      camera: camera,
      announcements: announcements,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)

    #expect(workspace.penInteractionCompleted)
    let events = await log.values
    #expect(events.firstIndex(of: "announce:Lowering the pen.")! < events.firstIndex(of: "machine:pen-lower")!)
    #expect(events.firstIndex(of: "announce:Raising the pen.")! < events.firstIndex(of: "machine:pen-raise")!)
    #expect(workspace.lastAnnouncementResultText == "Announcement completed.")
    await workspace.shutdown()
  }

  @Test("review projections are inert and preserve the runtime current owner")
  func reviewProjectionIsInert() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let workspace = workspace(machine: machine, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()

    let current = workspace.currentLearningPathItemID
    let transactionCount = workspace.discoveryTransactions.count
    let revisionCount = workspace.learningArtifactGraph.revisions.count
    let requestedFeedCount = await machine.requestedFeeds.count
    for itemID in LearningPathItemID.navigationOrder {
      _ = workspace.selectedOperatorActionPresentation(for: itemID)
    }

    #expect(workspace.currentLearningPathItemID == current)
    #expect(workspace.discoveryTransactions.count == transactionCount)
    #expect(workspace.learningArtifactGraph.revisions.count == revisionCount)
    #expect(await machine.requestedFeeds.count == requestedFeedCount)
    #expect(await machine.cancelCount == 0)
    #expect(
      workspace.learningPathItemPresentations.first {
        $0.id == .stage(.humanGuidedDiscovery)
      }?.status == .current
    )
    #expect(
      workspace.learningPathItemPresentations.first {
        $0.id == .humanGuidedDiscovery(.penInteraction)
      }?.status == .current
    )
    let adaptive = workspace.selectedOperatorActionPresentation(for: .stage(.adaptiveDrawing))
    #expect(adaptive.status == .future)
    #expect(adaptive.actionStrip == nil)
    await workspace.shutdown()
  }

  @Test("Start becomes typed choices and Cancel settles to a fresh Restart route")
  func exerciseActionTransitions() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)

    #expect(workspace.currentExerciseActionStripPresentation?.actions.map(\.kind) == [.start])
    await workspace.performExerciseAction(.start, for: owner)
    let liveActions = workspace.currentExerciseActionStripPresentation?.actions.map(\.kind) ?? []
    #expect(liveActions.contains(.choice(.yes)))
    #expect(liveActions.contains(.choice(.no)))
    #expect(liveActions.contains(.cancel))
    #expect(!liveActions.contains(.start))

    await workspace.performExerciseAction(.cancel, for: owner)
    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.currentLearningPathItemID == owner)
    #expect(workspace.currentExerciseActionStripPresentation?.actions.map(\.kind) == [.restart])
    await workspace.shutdown()
  }

  @Test("Boundary Cancel uses cancelAttempt and records no Stop success or boundary evidence")
  func boundaryCancelHasNoSuccessEvidence() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)

    let owner = LearningPathItemID.humanGuidedDiscovery(.boundaryDiscovery)
    await workspace.beginBoundaryDiscovery(.negativeX)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    await workspace.performExerciseAction(.cancel, for: owner)

    #expect(await machine.cancelIntents == [.cancelAttempt])
    #expect(workspace.relevantBoundaryObservationCount == 0)
    #expect(workspace.drawingFramePosterior == nil)
    #expect(workspace.discoveryTransactions[.boundaryNegativeX]?.state == .cancelled)
    #expect(
      workspace.discoveryTransactions[.boundaryNegativeX]?.evidenceSummaries
        .contains(where: { $0.summary.contains("Operator requested Stop") }) == false
    )
    #expect(workspace.currentExerciseActionStripPresentation?.actions.map(\.kind) == [.restart])
    await workspace.shutdown()
  }

  @Test("Record Another Attempt preserves compatible boundary samples and recomputes N")
  func boundaryAdditionalAttemptAggregates() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)

    await workspace.beginBoundaryDiscovery(.positiveX)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)

    let owner = LearningPathItemID.humanGuidedDiscovery(.boundaryDiscovery)
    let attemptsBeforeReview = workspace.boundaryAttemptHistories[.positiveX]?
      .values.first?.attempts.count
    let revisionsBeforeReview = workspace.learningArtifactGraph.revisions.count
    let machineActionsBeforeReview = await machine.requestedFeeds.count
    let repeatActions = try #require(
      workspace.selectedOperatorActionPresentation(for: owner).actionStrip
    ).actions.map(\.kind)
    #expect(repeatActions.contains(.redoThisStep))
    #expect(repeatActions.contains(.recordAnotherAttempt))
    #expect(attemptsBeforeReview == workspace.boundaryAttemptHistories[.positiveX]?
      .values.first?.attempts.count)
    #expect(revisionsBeforeReview == workspace.learningArtifactGraph.revisions.count)
    let machineActionsAfterReview = await machine.requestedFeeds.count
    #expect(machineActionsBeforeReview == machineActionsAfterReview)
    await workspace.performExerciseAction(.recordAnotherAttempt, for: owner)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)

    let histories = try #require(workspace.boundaryAttemptHistories[.positiveX])
    let history = try #require(histories.values.first)
    let aggregate = try NumericAttemptAggregate(history: history)
    #expect(aggregate.validSampleCount == 2)
    #expect(aggregate.includedAttemptIDs.count == 2)
    #expect(aggregate.estimator.revision == "1")
    #expect(workspace.drawingFramePosterior?.observationCount == 2)
    #expect(workspace.drawingFramePosterior?.observationsByKey.count == 2)
    await workspace.shutdown()
  }

  @Test("Redo replaces one accepted boundary sample while Record Another keeps compatible samples")
  func boundaryRedoSupersedesOnlyReplacedSample() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)

    await workspace.beginBoundaryDiscovery(.positiveX)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)
    let owner = LearningPathItemID.humanGuidedDiscovery(.boundaryDiscovery)
    let oldAttemptID = try #require(
      workspace.boundaryAttemptHistories[.positiveX]?.values.first?.attempts.first?.id
    )
    let oldObservationKey = try #require(
      workspace.boundaryFrameObservationsByAttemptID[oldAttemptID]?.key
    )

    await workspace.performExerciseAction(.redoThisStep, for: owner)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)

    let history = try #require(workspace.boundaryAttemptHistories[.positiveX]?.values.first)
    let aggregate = try NumericAttemptAggregate(history: history)
    let replacementID = try #require(history.attempts.last?.id)
    #expect(history.records.count == 2)
    #expect(history.records.first?.inclusionState == .superseded(by: replacementID))
    #expect(history.records.last?.inclusionState == .included)
    #expect(aggregate.validSampleCount == 1)
    #expect(aggregate.includedAttemptIDs == [replacementID])
    #expect(!aggregate.includedAttemptIDs.contains(oldAttemptID))
    #expect(workspace.drawingFramePosterior?.observationCount == 1)
    #expect(workspace.drawingFramePosterior?.observationsByKey[oldObservationKey] == nil)
    #expect(workspace.boundaryFrameObservationsByAttemptID[oldAttemptID]?.key == oldObservationKey)
    #expect(workspace.boundaryFrameObservationsByAttemptID[replacementID] != nil)
    await workspace.shutdown()
  }

  @Test("cancelled boundary Redo preserves the accepted included sample")
  func cancelledBoundaryRedoPreservesAggregate() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)

    await workspace.beginBoundaryDiscovery(.negativeX)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)
    let owner = LearningPathItemID.humanGuidedDiscovery(.boundaryDiscovery)
    let acceptedAttemptID = try #require(
      workspace.boundaryAttemptHistories[.negativeX]?.values.first?.attempts.first?.id
    )
    let acceptedPosterior = workspace.drawingFramePosterior

    await workspace.performExerciseAction(.redoThisStep, for: owner)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    await workspace.performExerciseAction(.cancel, for: owner)

    let history = try #require(workspace.boundaryAttemptHistories[.negativeX]?.values.first)
    let aggregate = try NumericAttemptAggregate(history: history)
    #expect(history.records.count == 2)
    #expect(history.records.first?.inclusionState == .included)
    #expect(history.records.last?.inclusionState == .excludedUnsuccessful)
    #expect(history.attempts.last?.disposition == .cancelled)
    #expect(aggregate.validSampleCount == 1)
    #expect(aggregate.includedAttemptIDs == [acceptedAttemptID])
    #expect(workspace.drawingFramePosterior == acceptedPosterior)
    await workspace.shutdown()
  }

  @Test("configuration-changing boundary Redo supersedes across separate histories without pooling")
  func incompatibleBoundaryRedoRemainsSeparate() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture(rotatesConfiguration: true)
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)

    await workspace.beginBoundaryDiscovery(.positiveY)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)
    let acceptedAttemptID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .boundaryObservation(.positiveY))?
        .attemptID
    )

    let owner = LearningPathItemID.humanGuidedDiscovery(.boundaryDiscovery)
    await workspace.performExerciseAction(.redoThisStep, for: owner)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)

    let replacementAttemptID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .boundaryObservation(.positiveY))?
        .attemptID
    )
    let histories = try #require(workspace.boundaryAttemptHistories[.positiveY])
    let oldHistory = try #require(histories.values.first(where: {
      $0.attempts.contains(where: { $0.id == acceptedAttemptID })
    }))
    let newHistory = try #require(histories.values.first(where: {
      $0.attempts.contains(where: { $0.id == replacementAttemptID })
    }))
    #expect(histories.count == 2)
    #expect(acceptedAttemptID != replacementAttemptID)
    #expect(oldHistory.records.first?.inclusionState == .superseded(by: replacementAttemptID))
    #expect(oldHistory.includedSuccessfulAttempts.isEmpty)
    #expect(newHistory.records.first?.inclusionState == .included)
    #expect(newHistory.includedSuccessfulAttempts.map(\.id) == [replacementAttemptID])
    #expect(try NumericAttemptAggregate(history: newHistory).validSampleCount == 1)
    await workspace.shutdown()
  }

  @Test("Redo Pen Interaction replaces only its revision and retains independent boundary evidence")
  func redoPenRetainsBoundary() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    await workspace.beginBoundaryDiscovery(.positiveY)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)

    let oldPen = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)
    )
    let oldBoundary = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .boundaryObservation(.positiveY))
    )
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await workspace.performExerciseAction(.redoThisStep, for: owner)
    try await finishPenInteraction(workspace)

    let newPen = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)
    )
    let retainedBoundary = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .boundaryObservation(.positiveY))
    )
    #expect(newPen.id != oldPen.id)
    #expect(workspace.learningArtifactGraph.revision(id: oldPen.id)?.state == .superseded)
    #expect(retainedBoundary.id == oldBoundary.id)
    #expect(workspace.relevantBoundaryObservationCount == 1)
    await workspace.shutdown()
  }

  @Test("cancelled replacement leaves the accepted artifact current")
  func cancelledReplacementKeepsAcceptedArtifact() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    let accepted = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)
    )
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)

    await workspace.performExerciseAction(.redoThisStep, for: owner)
    await workspace.performExerciseAction(.cancel, for: owner)

    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id == accepted.id
    )
    #expect(workspace.learningArtifactGraph.revision(id: accepted.id)?.state == .current)
    #expect(workspace.penAttemptHistory.attempts.last?.disposition == .cancelled)
    #expect(workspace.penAttemptHistory.records.first?.inclusionState == .included)
    #expect(workspace.penAttemptHistory.records.last?.inclusionState == .excludedUnsuccessful)
    #expect(workspace.currentPenStateAggregate?.validSampleCount == 1)
    #expect(workspace.currentPenStateAggregate?.includedAttemptIDs == [accepted.attemptID])
    await workspace.shutdown()
  }
}

@MainActor
private func stopActiveOperation(_ workspace: OperatorWorkspace) async throws {
  let capabilityID = try #require(workspace.contextualStopPresentation?.capabilityID)
  await workspace.stopCurrentOperation(capabilityID: capabilityID)
}

@MainActor
private func performStart(
  _ workspace: OperatorWorkspace,
  owner: LearningPathItemID
) async {
  let start = workspace.currentExerciseActionStripPresentation?.actions.first {
    $0.kind == .start
  }
  #expect(start?.isEnabled == true)
  await workspace.performExerciseAction(.start, for: owner)
}

@MainActor
private func completePenInteraction(_ workspace: OperatorWorkspace) async throws {
  if let reason = workspace.discoveryStartUnavailableReason(for: .penInteraction) {
    throw StepMismatch(expected: "available", actual: reason)
  }
  await workspace.beginPenInteraction()
  try await finishPenInteraction(workspace)
}

@MainActor
private func finishPenInteraction(_ workspace: OperatorWorkspace) async throws {
  try requireStep(workspace, "answer-initially-up")
  await workspace.answerCurrentQuestion(.yes)
  try requireStep(workspace, "answer-clear-to-lower")
  await workspace.answerCurrentQuestion(.yes)
  try requireStep(workspace, "answer-currently-down")
  await workspace.answerCurrentQuestion(.yes)
  try requireStep(workspace, "answer-finally-up")
  await workspace.answerCurrentQuestion(.yes)
  guard workspace.discoveryTransactions[.penInteraction]?.state == .succeeded else {
    throw StepMismatch(
      expected: "succeeded",
      actual: String(describing: workspace.discoveryTransactions[.penInteraction]?.state)
    )
  }
}

@MainActor
private func requireStep(_ workspace: OperatorWorkspace, _ expected: String) throws {
  let actual = workspace.discoveryTransactions[.penInteraction]?.currentStep?.id
  guard actual == expected else {
    throw StepMismatch(expected: expected, actual: actual ?? "nil")
  }
}

@MainActor
private func workspace(
  machine: MachineFixture,
  camera: CameraFixture? = nil,
  announcements: AnnouncementFixture? = nil,
  log _: EventLog
) -> OperatorWorkspace {
  let clock = TestClock()
  return OperatorWorkspace(
    machineActions: .init(
      select: { _ in await machine.snapshot() },
      snapshot: { await machine.snapshot() },
      requestPassiveProbe: {
        PassiveProbeResult(
          link: machine.descriptor,
          startedAt: RuntimeTimestamp(monotonicNanoseconds: 1),
          completedAt: RuntimeTimestamp(monotonicNanoseconds: 2),
          exchanges: [],
          blockers: []
        )
      },
      activateMotionGuard: { .activated },
      deactivateMotionGuard: {},
      requestRelativeJog: { await machine.requestRelativeJog($0) },
      beginRelativeJog: { request in
        .admitted(
          RelativeJogOperation(
            id: UUID(),
            task: Task { await machine.requestRelativeJog(request) }
          )
        )
      },
      requestDrawingStroke: { _ in fatalError("unused") },
      beginDrawingStroke: { _ in fatalError("unused") },
      requestPenActuation: { await machine.requestPen($0) },
      requestBoundaryMotion: { await machine.requestBoundaryMotion($0) },
      beginBoundaryMotion: { request in
        .admitted(
          BoundaryMotionOperation(
            ownerID: request.ownerID,
            task: Task { await machine.requestBoundaryMotion(request) }
          )
        )
      },
      requestJogCancel: { await machine.cancel(intent: $0) },
      disconnect: {}
    ),
    cameraActions: camera.map(cameraActions),
    announcementActions: announcements.map { fixture in
      .init(
        announce: { await fixture.announce($0) },
        cancelForShutdown: { await fixture.cancelForShutdown() }
      )
    },
    serialDevices: [machine.descriptor],
    serialDeviceDiscovery: { [machine.descriptor] },
    loadSelectedSerialIdentifier: { nil },
    persistSelectedSerialIdentifier: { _ in },
    nowNanoseconds: { clock.next() }
  )
}

private enum SimulatorIsolationViolation: Error {
  case machineAction(String)
}

private func isolatedMachineActions(log: EventLog) -> OperatorWorkspace.MachineActions {
  .init(
    select: { _ in
      await log.append("select")
      throw SimulatorIsolationViolation.machineAction("select")
    },
    snapshot: {
      await log.append("snapshot")
      return nil
    },
    requestPassiveProbe: {
      await log.append("requestPassiveProbe")
      throw SimulatorIsolationViolation.machineAction("requestPassiveProbe")
    },
    activateMotionGuard: {
      await log.append("activateMotionGuard")
      return .refused(.notConnected)
    },
    deactivateMotionGuard: {
      await log.append("deactivateMotionGuard")
    },
    requestRelativeJog: { _ in
      await log.append("requestRelativeJog")
      return .refused(.notConnected)
    },
    beginRelativeJog: { _ in
      await log.append("beginRelativeJog")
      return .rejected(.refused(.notConnected))
    },
    requestDrawingStroke: { _ in
      await log.append("requestDrawingStroke")
      return .refused(.notConnected)
    },
    beginDrawingStroke: { _ in
      await log.append("beginDrawingStroke")
      return .rejected(.refused(.notConnected))
    },
    requestPenActuation: { _ in
      await log.append("requestPenActuation")
      return .refused(.notConnected)
    },
    requestBoundaryMotion: { request in
      await log.append("requestBoundaryMotion")
      return .needsAttention(ownerID: request.ownerID, terminal: .refusal(.notConnected))
    },
    beginBoundaryMotion: { request in
      await log.append("beginBoundaryMotion")
      return .rejected(
        .needsAttention(ownerID: request.ownerID, terminal: .refusal(.notConnected))
      )
    },
    requestJogCancel: { _ in
      await log.append("requestJogCancel")
      return .refused(.noActiveJog)
    },
    disconnect: {
      await log.append("disconnect")
    }
  )
}

private func cameraActions(_ fixture: CameraFixture) -> OperatorWorkspace.CameraActions {
  .init(
    discover: { fixture.snapshot },
    select: { _ in fixture.snapshot },
    start: { fixture.snapshot },
    stop: { fixture.snapshot },
    restart: { fixture.snapshot },
    snapshot: { fixture.snapshot },
    frames: { AsyncStream { $0.finish() } },
    inspectScene: { try fixture.inspection(after: $0) },
    captureFrame: { try fixture.inspection(after: $0).displayedFrame },
    captureSnapshot: { "unused" },
    setAutomaticInspection: { fixture.setAutomaticInspection($0) },
    analysisUpdates: { AsyncStream { $0.finish() } },
    simulatedContent: { mode in
      try await CameraComposition.actions.simulatedContent(mode)
    },
    simulatedExplorationFrames: {
      try await CameraComposition.actions.simulatedExplorationFrames()
    },
    observeAnchorDot: { _ in fatalError("unused") },
    observeIsolatedInk: { _ in fatalError("unused") },
    exportLearningEpisode: { _, _ in fatalError("unused") }
  )
}

private actor EventLog {
  private(set) var values: [String] = []
  func append(_ value: String) { values.append(value) }
}

private final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: UInt64 = 100

  func next() -> UInt64 {
    lock.lock()
    defer { lock.unlock() }
    let result = value
    value &+= 10
    return result
  }
}

private actor AnnouncementFixture {
  let log: EventLog
  var outcomes: [SpeechAnnouncementOutcome]

  init(log: EventLog, outcomes: [SpeechAnnouncementOutcome]) {
    self.log = log
    self.outcomes = outcomes
  }

  func announce(_ message: String) async -> SpeechAnnouncementOutcome {
    await log.append("announce:\(message)")
    return outcomes.isEmpty ? .completed : outcomes.removeFirst()
  }

  func cancelForShutdown() {}
}

private actor MachineFixture {
  nonisolated let descriptor = MachineLinkDescriptor(
    identifier: "fixture",
    displayName: "Fixture",
    bsdPath: nil,
    transport: .simulated
  )
  let log: EventLog
  let feedLimits: ControllerAxisFeedLimits?
  let reportsBoundaryMoving: Bool
  let holdCancellationSettlement: Bool
  private(set) var cancelCount = 0
  private(set) var cancelIntents: [JogCancelIntent] = []
  private(set) var requestedFeeds: [Double] = []
  private var moving = false
  private var cancelPending = false
  private var pendingCancelIntent: JogCancelIntent?
  private var continuation: CheckedContinuation<MotionOutcome, Never>?
  private var boundaryContinuation: CheckedContinuation<BoundaryMotionOutcome, Never>?
  private var position: MachinePosition
  private var penState: PenState = .up
  private var lastMotion: MotionOutcome?
  private var lastPen: PenOutcome?
  private var lastCancel: JogCancelOutcome?
  private var activeRequest: RelativeJogRequest?
  private var activeBoundaryRequest: BoundaryMotionRequest?
  private var heldBoundaryCancelIntent: JogCancelIntent?

  init(
    log: EventLog,
    feedLimits: ControllerAxisFeedLimits? = nil,
    reportsBoundaryMoving: Bool = true,
    holdCancellationSettlement: Bool = false
  ) throws {
    self.log = log
    self.feedLimits = feedLimits
    self.reportsBoundaryMoving = reportsBoundaryMoving
    self.holdCancellationSettlement = holdCancellationSettlement
    position = try MachinePosition(x: 0, y: 0)
  }

  func snapshot() -> RunInterpreterSnapshot {
    RunInterpreterSnapshot(
      currentOperation: activeBoundaryRequest.map(RunOperation.boundaryMotion)
        ?? activeRequest.map(RunOperation.relativeJog) ?? .idle,
      machine: MachineSnapshot(
        connection: moving && (activeBoundaryRequest == nil || reportsBoundaryMoving)
          ? .moving : .connected,
        link: descriptor,
        lastProbe: nil,
        blockers: [],
        controllerState: moving && (activeBoundaryRequest == nil || reportsBoundaryMoving)
          ? .jog : .idle,
        position: position,
        penState: penState,
        motionGuardState: .active,
        operationInFlight: moving,
        lastMotionOutcome: lastMotion,
        lastPenOutcome: lastPen,
        lastJogCancelOutcome: lastCancel,
        controllerAxisFeedLimits: feedLimits
      ),
      lastMotionOutcome: lastMotion,
      lastPenOutcome: lastPen,
      lastProbe: nil,
      lastJogCancelOutcome: lastCancel
    )
  }

  func requestRelativeJog(_ request: RelativeJogRequest) async -> MotionOutcome {
    requestedFeeds.append(request.feedMMPerMinute)
    activeRequest = request
    moving = true
    await log.append("machine:jog")
    if cancelPending {
      cancelPending = false
      return settleCancelled()
    }
    let outcome = await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
    lastMotion = outcome
    activeRequest = nil
    return outcome
  }

  func requestBoundaryMotion(_ request: BoundaryMotionRequest) async -> BoundaryMotionOutcome {
    requestedFeeds.append(request.segment.feedMMPerMinute)
    activeBoundaryRequest = request
    moving = true
    await log.append("machine:boundary")
    if let pendingCancelIntent {
      self.pendingCancelIntent = nil
      return settleBoundary(request: request, intent: pendingCancelIntent)
    }
    let outcome = await withCheckedContinuation { continuation in
      boundaryContinuation = continuation
    }
    activeBoundaryRequest = nil
    return outcome
  }

  func cancel(intent: JogCancelIntent) -> JogCancelOutcome {
    cancelCount += 1
    cancelIntents.append(intent)
    let cancelOutcome = JogCancelOutcome.completed(finalPosition: position)
    if let boundaryContinuation, let request = activeBoundaryRequest {
      if holdCancellationSettlement {
        heldBoundaryCancelIntent = intent
      } else {
        self.boundaryContinuation = nil
        let outcome = settleBoundary(request: request, intent: intent)
        boundaryContinuation.resume(returning: outcome)
      }
    } else if let continuation {
      self.continuation = nil
      let outcome = settleCancelled()
      continuation.resume(returning: outcome)
    } else {
      cancelPending = true
      pendingCancelIntent = intent
    }
    lastCancel = cancelOutcome
    return cancelOutcome
  }

  func settleHeldCancellation() {
    guard let boundaryContinuation, let request = activeBoundaryRequest,
      let intent = heldBoundaryCancelIntent
    else { return }
    self.boundaryContinuation = nil
    heldBoundaryCancelIntent = nil
    let outcome = settleBoundary(request: request, intent: intent)
    boundaryContinuation.resume(returning: outcome)
  }

  func requestPen(_ command: PenCommand) async -> PenOutcome {
    await log.append("machine:pen-\(command.rawValue)")
    penState = command.commandedState
    let outcome = PenOutcome.commandedAndSettled(command: command, commandedState: penState)
    lastPen = outcome
    return outcome
  }

  private func settleCancelled() -> MotionOutcome {
    moving = false
    let outcome = MotionOutcome.cancelled(finalPosition: position)
    lastMotion = outcome
    activeRequest = nil
    return outcome
  }

  private func settleBoundary(
    request: BoundaryMotionRequest,
    intent: JogCancelIntent
  ) -> BoundaryMotionOutcome {
    moving = false
    activeBoundaryRequest = nil
    return .settled(
      BoundaryMotionSettlement(
        ownerID: request.ownerID,
        intent: intent,
        completedSegmentCount: 0,
        finalPosition: position,
        jogCancelOutcome: .completed(finalPosition: position)
      )
    )
  }
}

private final class CameraFixture: @unchecked Sendable {
  let device: CameraDevice
  let snapshot: CameraCaptureSnapshot
  private let configurationID: CameraConfigurationID
  private let rotatesConfiguration: Bool
  private let lock = NSLock()
  private var inspectionCount = 0
  private var automaticCadences: [VisionAnalysisCadence] = []

  init(rotatesConfiguration: Bool = false) throws {
    self.rotatesConfiguration = rotatesConfiguration
    configurationID = CameraConfigurationID()
    device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Fixture camera")
    let initial = DisplayedFrame(
      source: .live(device.id),
      frame: try frame(id: "initial", sequence: 1, capture: 50, configurationID: configurationID)
    )
    snapshot = CameraCaptureSnapshot(
      devices: [device],
      selectedDeviceID: device.id,
      state: .running,
      latestFrame: initial,
      error: nil
    )
  }

  func inspection(after captureBoundary: UInt64) throws -> LiveSceneInspection {
    lock.lock()
    inspectionCount += 1
    let inspectionConfigurationID = rotatesConfiguration
      ? CameraConfigurationID()
      : configurationID
    lock.unlock()
    let capture = captureBoundary &+ 1
    let fresh = DisplayedFrame(
      source: .live(device.id),
      frame: try frame(
        id: "fresh-\(capture)",
        sequence: capture,
        capture: capture,
        configurationID: inspectionConfigurationID
      )
    )
    let geometry = try Polyline<CameraPixelSpace>(points: [
      try Point2(x: 0, y: 0),
      try Point2(x: 100, y: 0),
      try Point2(x: 100, y: 100),
      try Point2(x: 0, y: 100),
      try Point2(x: 0, y: 0),
    ])
    let measurement = PlotterSceneMeasurement(
      frameID: fresh.frame.id,
      frameSHA256: fresh.frame.contentSHA256,
      cameraConfigurationID: inspectionConfigurationID,
      greenComponentCount: 1,
      cap: GreenCapMeasurement(
        pixelCount: 10,
        boundingBox: PixelRect(x: 98, y: 48, width: 2, height: 4),
        centroid: try Point2(x: 99, y: 50),
        confidence: 0.9
      ),
      topFrameSide: nil,
      rightFrameSide: nil,
      drawingFrame: DrawingFrameEstimate(
        geometry: geometry,
        confidence: 0.9,
        basis: "test exact frame"
      ),
      armature: nil,
      overlays: [],
      algorithmRevision: "workspace-test-v1",
      diagnosticSHA256: fresh.frame.contentSHA256
    )
    return LiveSceneInspection(displayedFrame: fresh, measurement: measurement)
  }

  var recordedAutomaticCadences: [VisionAnalysisCadence] {
    lock.lock()
    defer { lock.unlock() }
    return automaticCadences
  }

  func setAutomaticInspection(
    _ cadence: VisionAnalysisCadence?
  ) -> PlotterSceneAnalysisSnapshot {
    lock.lock()
    if let cadence { automaticCadences.append(cadence) }
    lock.unlock()
    return PlotterSceneAnalysisSnapshot(
      state: cadence.map(PlotterSceneAnalysisState.running) ?? .stopped,
      submittedFrameCount: 0,
      analyzedFrameCount: 0,
      supersededFrameCount: 0,
      failedFrameCount: 0,
      activeFrameSequence: nil,
      pendingFrameSequence: nil,
      latestResult: nil,
      lastError: nil
    )
  }
}

private func frame(
  id: String,
  sequence: UInt64,
  capture: UInt64,
  configurationID: CameraConfigurationID
) throws -> StampedFrame {
  try StampedFrame(
    id: FrameID(rawValue: id),
    sequence: sequence,
    captureNanoseconds: capture,
    cameraConfigurationID: configurationID,
    width: 1,
    height: 1,
    rowBytes: 4,
    pixelFormat: .bgra8,
    bytes: OwnedFrameBytes([255, 255, 255, 255])
  )
}

@MainActor
private func waitUntil(
  attempts: Int = 2_000,
  condition: () -> Bool
) async throws {
  for _ in 0..<attempts {
    if condition() { return }
    await Task.yield()
  }
  throw TestTimeout()
}

@MainActor
private func waitUntilAsync(
  attempts: Int = 2_000,
  condition: () async -> Bool
) async throws {
  for _ in 0..<attempts {
    if await condition() { return }
    await Task.yield()
  }
  throw TestTimeout()
}

private struct TestTimeout: Error {}
private struct StepMismatch: Error {
  let expected: String
  let actual: String
}
