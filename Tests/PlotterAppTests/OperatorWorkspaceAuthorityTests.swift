import Foundation
import PlotterModel
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

extension OperatorWorkspaceTests {
  @Test("Center arrival accepts reproduced controller quantization residual")
  func centerArrivalAcceptsQuantizedSettlement() async throws {
    let target = try MachinePosition(x: -51.975, y: -73.684)
    let reproduced = try MachinePosition(x: -51.963, y: -73.673)
    #expect(MachinePositionAcceptancePolicy.toleranceMM == 0.05)
    #expect(MachinePositionAcceptancePolicy.accepts(reproduced, target: target))

    let log = EventLog()
    let machine = try MachineFixture(
      log: log,
      relativeJogSettlementOffset: try Vector2(dx: 0.012, dy: 0.011)
    )
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    try await completeLiveBoundaries(workspace, machine: machine)

    let owner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    try await performPublicAction(.moveToEstimatedCenter, owner: owner, workspace: workspace)

    let expectedCenter = try MachinePosition(x: 0, y: 0)
    #expect(camera.recordedAutomaticInspectionRequests == [.twoFPS, .twoFPS, .twoFPS, .twoFPS])
    #expect(!workspace.scopedVisionAnalysisActive)
    #expect(workspace.centerArrivalPosition == expectedCenter)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .centerArrival) != nil)
    #expect(!workspace.centerArrivalRetryRequired)
    #expect(
      workspace.currentLearningPathItemID
        == .humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    )
  }

  @Test("Out-of-tolerance center settlement offers center-only retry")
  func centerArrivalRejectsOutsideToleranceWithoutBoundaryRestart() async throws {
    let target = try MachinePosition(x: 0, y: 0)
    let outside = try MachinePosition(x: 0.04, y: 0.04)
    #expect(!MachinePositionAcceptancePolicy.accepts(outside, target: target))

    let log = EventLog()
    let machine = try MachineFixture(
      log: log,
      relativeJogSettlementOffset: try Vector2(dx: 0.04, dy: 0.04)
    )
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    try await completeLiveBoundaries(workspace, machine: machine)
    let acceptedAggregates = workspace.boundarySideAggregates
    let acceptedCenter = workspace.estimatedMachineCenter

    let owner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    try await performPublicAction(.moveToEstimatedCenter, owner: owner, workspace: workspace)

    #expect(workspace.centerArrivalPosition == nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .centerArrival) == nil)
    #expect(workspace.boundarySideAggregates == acceptedAggregates)
    #expect(workspace.estimatedMachineCenter == acceptedCenter)
    #expect(workspace.centerArrivalRetryRequired)
    #expect(workspace.restartableExerciseItemID == nil)
    let recovery = try #require(workspace.currentExerciseActionStripPresentation)
    #expect(recovery.actions.map(\.kind) == [.moveToEstimatedCenter])
    #expect(recovery.actions.map(\.title) == ["Retry Center Arrival"])
    let activity = workspace.selectedOperatorActionPresentation(for: owner).activity
    #expect(activity?.action == "Move to Estimated Center")
    #expect(
      activity?.detail.accessibilityText.contains("outside the 0.050 mm tolerance") == true
    )
    #expect(
      activity?.acceptedResult.accessibilityText.contains("four accepted Boundary") == true
    )
  }

  @Test("source-indexed sessions preserve LIVE and replace SIMULATED independently")
  func simulatedLearningDoesNotReplaceLiveAuthority() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    await workspace.beginPairedBoundarySide(.positiveY)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)

    let livePenRevisionID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id
    )
    let liveBoundaryRevisionID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveY))?.id
    )
    await workspace.switchFrameMode(.simulated)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .penInteraction) == nil)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveY))
        == nil
    )
    workspace.selectedDiscoverySequenceID = .boundaryNegativeX

    await workspace.switchFrameMode(.live)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id == livePenRevisionID
    )
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveY))?.id
        == liveBoundaryRevisionID
    )
    await workspace.switchFrameMode(.simulated)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .penInteraction) == nil)
    #expect(workspace.discoveryTransactions.isEmpty)
    #expect(workspace.selectedDiscoverySequenceID == .penInteraction)
    await workspace.switchFrameMode(.live)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id == livePenRevisionID
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

    await workspace.beginPairedBoundarySide(.negativeY)
    try await waitUntil { workspace.contextualStopPresentation != nil }

    #expect(workspace.machineSnapshot?.machine.connection == .connected)
    #expect(workspace.relevantBoundaryObservationCount == 0)
    #expect(workspace.boundarySideAggregates.isEmpty)
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
    await workspace.beginPairedBoundarySide(.positiveX)
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

    await workspace.beginPairedBoundarySide(.negativeY)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    await workspace.shutdown()

    #expect(await machine.cancelCount == 1)
    #expect(await machine.cancelIntents == [.shutdown])
    #expect(await machine.requestedFeeds.last == 500)
    #expect(workspace.discoveryTransactions.isEmpty)
    #expect(workspace.contextualStopPresentation == nil)
    #expect(workspace.isShutdown)
  }

  @Test(
    "announcement failure is advisory and Pen Interaction preserves output-before-actuation order")
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
    #expect(
      events.firstIndex(of: "announce:Lowering the pen.")! < events.firstIndex(
        of: "machine:pen-lower")!)
    #expect(
      events.firstIndex(of: "announce:Raising the pen.")! < events.firstIndex(
        of: "machine:pen-raise")!)
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
    #expect(!LearningPathItemID.navigationOrder.contains { $0.number == "5" })
    await workspace.shutdown()
  }

  @Test("Pen Interaction Start exposes Next and Cancel, then Cancel settles to Restart")
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
    #expect(
      workspace.actionSurfacePresentation.pointSelectionRequest?.prompt
        == "Click the pen cap body—not the tip—on the current camera frame."
    )
    #expect(workspace.currentExerciseActionStripPresentation?.actions.map(\.kind) == [.cancel])
    try await identifyPenCap(workspace)
    let liveActions = workspace.currentExerciseActionStripPresentation?.actions.map(\.kind) ?? []
    #expect(liveActions.contains(.choice(.yes)))
    #expect(!liveActions.contains(.choice(.no)))
    #expect(liveActions.contains(.cancel))
    #expect(!liveActions.contains(.start))

    await workspace.performExerciseAction(.cancel, for: owner)
    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.currentLearningPathItemID == owner)
    #expect(workspace.currentExerciseActionStripPresentation?.actions.map(\.kind) == [.restart])
    await workspace.shutdown()
  }

  @Test("Boundary Cancel is unavailable until its movement owner settles")
  func boundaryCancelUnavailableDuringMotion() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)

    let owner = LearningPathItemID.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    await workspace.beginPairedBoundarySide(.negativeX)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    #expect(
      workspace.currentExerciseActionStripPresentation?.actions.contains(where: {
        $0.kind == .cancel
      }) == false
    )
    await workspace.performExerciseAction(.cancel, for: owner)

    #expect(await machine.cancelIntents.isEmpty)
    #expect(workspace.relevantBoundaryObservationCount == 0)
    #expect(workspace.boundarySideAggregates.isEmpty)
    #expect(workspace.discoveryTransactions[.boundaryNegativeX]?.state == .active)
    try await stopActiveOperation(workspace)
    await workspace.shutdown()
  }

  @Test("Boundary repeat actions aggregate and replace the accepted set atomically")
  func boundaryRepeatActionsAggregateAndReplaceAcceptedSet() async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    try await completeSimulatedBoundariesAndCenter(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY]
    )

    let owner = LearningPathItemID.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    let attemptsBeforeReview = workspace.boundaryAttemptHistories[.positiveX]?
      .values.first?.attempts.count
    let revisionsBeforeReview = workspace.learningArtifactGraph.revisions.count
    let machineActionsBeforeReview = await harness.machineActionLog.values.count
    let repeatActions = try #require(
      workspace.selectedOperatorActionPresentation(for: owner).actionStrip
    ).actions.map(\.kind)
    #expect(repeatActions.contains(.redoBoundary(.positiveX)))
    #expect(repeatActions.contains(.recordAnotherBoundaryAttempt(.positiveX)))
    #expect(
      attemptsBeforeReview
        == workspace.boundaryAttemptHistories[.positiveX]?
        .values.first?.attempts.count)
    #expect(revisionsBeforeReview == workspace.learningArtifactGraph.revisions.count)
    let machineActionsAfterReview = await harness.machineActionLog.values.count
    #expect(machineActionsBeforeReview == machineActionsAfterReview)

    for _ in 0..<2 {
      await workspace.performExerciseAction(.recordAnotherBoundaryAttempt(.positiveX), for: owner)
      try await waitUntil { workspace.contextualStopPresentation != nil }
      try await stopActiveOperation(workspace)
    }

    let histories = try #require(workspace.boundaryAttemptHistories[.positiveX])
    let history = try #require(histories.values.first)
    let aggregate = try #require(workspace.boundarySideAggregates[.positiveX])
    #expect(histories.count == 1)
    #expect(aggregate.validSampleCount == 3)
    #expect(aggregate.includedAttemptIDs.count == 3)
    #expect(aggregate.estimator.revision == "boundary-machine-coordinate-v1")
    #expect(history.includedSuccessfulAttempts.count == 3)
    let oldAttemptIDs = aggregate.includedAttemptIDs
    #expect(oldAttemptIDs.count == 3)

    await harness.runtime.injectFault(.cameraConfigurationChangeBeforeNextFrame)
    await workspace.performExerciseAction(.redoBoundary(.positiveX), for: owner)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)

    let finalHistories = try #require(workspace.boundaryAttemptHistories[.positiveX])
    let finalHistory = try #require(finalHistories.values.first)
    let finalAggregate = try #require(workspace.boundarySideAggregates[.positiveX])
    let replacementID = try #require(finalHistory.attempts.last?.id)
    #expect(finalHistories.count == 1)
    #expect(finalHistory.records.count == 4)
    #expect(
      finalHistory.records.filter { oldAttemptIDs.contains($0.attempt.id) }
        .allSatisfy { $0.inclusionState == .superseded(by: replacementID) }
    )
    #expect(finalHistory.records.last?.inclusionState == .included)
    #expect(finalHistory.includedSuccessfulAttempts.map(\.id) == [replacementID])
    #expect(finalAggregate.validSampleCount == 1)
    #expect(finalAggregate.includedAttemptIDs == [replacementID])
    #expect(Set(finalAggregate.supersededAttempts.map(\.attemptID)) == Set(oldAttemptIDs))
    #expect(oldAttemptIDs.allSatisfy { workspace.boundaryAttemptEvidenceByAttemptID[$0] != nil })
    #expect(workspace.boundaryAttemptEvidenceByAttemptID[replacementID] != nil)
    #expect(await harness.machineActionLog.values.isEmpty)
  }

  @Test("every injected Boundary commit failure preserves all accepted current authority")
  func boundaryAtomicFailurePreservesAcceptedAuthority() async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    try await completeSimulatedBoundariesAndCenter(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY],
      moveToCenter: false
    )
    let aggregates = workspace.boundarySideAggregates
    let progress = workspace.pairedBoundaryProgress
    let center = workspace.estimatedMachineCenter
    let localFrame = workspace.learnedLocalCoordinateFrame
    let graphRevisions = Set(workspace.learningArtifactGraph.revisions)
    let boundaryEvidence = workspace.boundaryAttemptEvidenceByAttemptID
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )

    for failurePoint in BoundaryAtomicCommitFailurePoint.allCases {
      workspace.replaceBoundaryAtomicCommitFailurePointsForTesting([failurePoint])
      let snapshot = await harness.runtime.snapshot()
      _ = await workspace.requestRelativeJog(
        RelativeJogRequest(
          delta: try Vector2(
            dx: snapshot.boundaryTruth.positiveXMM - snapshot.mpos.xMM,
            dy: 0
          ),
          feedMMPerMinute: 1_000
        )
      )

      await workspace.performExerciseAction(.redoBoundary(.positiveX), for: owner)
      try await waitUntil { workspace.contextualStopPresentation != nil }
      try await stopActiveOperation(workspace)

      #expect(workspace.boundarySideAggregates == aggregates)
      #expect(workspace.pairedBoundaryProgress == progress)
      #expect(workspace.estimatedMachineCenter == center)
      #expect(workspace.learnedLocalCoordinateFrame == localFrame)
      #expect(workspace.centerArrivalPosition == nil)
      #expect(Set(workspace.learningArtifactGraph.revisions) == graphRevisions)
      #expect(workspace.boundaryAttemptEvidenceByAttemptID == boundaryEvidence)
      #expect(workspace.restartableExerciseItemID == nil)
      let recoveryActions =
        workspace.selectedOperatorActionPresentation(for: owner)
        .actionStrip?.actions.map(\.kind) ?? []
      #expect(recoveryActions.first == .moveToEstimatedCenter)
      #expect(recoveryActions.contains(.redoBoundary(.positiveX)))
      #expect(!recoveryActions.contains(.restart))
      #expect(!recoveryActions.contains(.cancel))
      #expect(await harness.machineActionLog.values.isEmpty)
    }
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
    await workspace.beginPairedBoundarySide(.positiveY)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)

    let oldPen = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)
    )
    let oldBoundary = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveY))
    )
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await workspace.performExerciseAction(.redoThisStep, for: owner)
    try await identifyPenCap(workspace)
    try await finishPenInteraction(workspace)

    let newPen = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)
    )
    let retainedBoundary = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveY))
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
    try submitPenCapClick(workspace)
    await workspace.performExerciseAction(.cancel, for: owner)

    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id == accepted.id
    )
    #expect(workspace.learningArtifactGraph.revision(id: accepted.id)?.state == .current)
    #expect(workspace.penAttemptHistory.attempts.last?.disposition == .cancelled)
    #expect(workspace.penAttemptHistory.records.first?.inclusionState == .included)
    #expect(workspace.penAttemptHistory.records.last?.inclusionState == .excludedUnsuccessful)
    #expect(workspace.currentPenInteractionAggregate?.validSampleCount == 1)
    #expect(workspace.currentPenInteractionAggregate?.includedAttemptIDs == [accepted.attemptID])
    await workspace.shutdown()
  }
}
