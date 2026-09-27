import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterUI
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

@MainActor
@Suite("Plotter Boundary episode", .serialized)
struct PlotterBoundaryEpisodeTests {
  @Test("exact value revision and direction admission forces the opposite side next")
  func exactAdmissionAndDirectionOrder() async throws {
    let fixture = try makeBoundaryEpisodeFixture()
    let initial = await fixture.runtime.snapshot(for: .live)
    let selected = await fixture.runtime.submit(
      submission(initial, .selectDirection(.positiveX))
    )
    guard case .applied(let selectedProjection) = selected else {
      Issue.record("Expected exact direction selection to apply.")
      return
    }
    #expect(selectedProjection.selectedDirection == .positiveX)
    #expect(selectedProjection.reference.revision > initial.projection.reference.revision)

    let accepted = try await acceptSide(
      fixture,
      direction: .positiveX,
      mode: .normal,
      finalPosition: try MachinePosition(x: 100, y: 0)
    )
    #expect(accepted.projection.allowedDirections == [.negativeX])
    #expect(accepted.acceptedAggregates[.positiveX]?.estimateMM == 100)
    #expect(accepted.acceptedAggregates[.positiveX]?.validSampleCount == 1)

    let refused = await fixture.runtime.submit(
      submission(accepted, .selectDirection(.positiveY))
    )
    expectRefusal(refused, reason: .directionNotAllowed(.positiveY), remedy: .choosePublishedDirection)
    #expect(await fixture.effects.sideAdmissionCount == 1)
    #expect(!accepted.projection.physicalEvidenceClaimed)
  }

  @Test("stale foreign and duplicate submissions refuse before any lower effect")
  func staleForeignAndDuplicateRefuse() async throws {
    let gate = PlotterBoundaryAdmissionGate(held: true)
    let fixture = try makeBoundaryEpisodeFixture(admissionGate: gate)
    let initial = await fixture.runtime.snapshot(for: .live)
    let admitted = await fixture.runtime.submit(
      submission(initial, .acquire(direction: .negativeX, mode: .normal))
    )
    guard case .applied(let active) = admitted else {
      Issue.record("Expected exact Boundary admission.")
      return
    }
    await gate.waitUntilReady()

    expectRefusal(
      await fixture.runtime.submit(submission(initial, .selectDirection(.positiveX))),
      reason: .staleProjection,
      remedy: .useCurrentProjection
    )
    let foreign = PlotterBoundaryProjectionReference(
      environment: .live,
      revision: active.reference.revision,
      operationID: PlotterBoundaryOperationID()
    )
    expectRefusal(
      await fixture.runtime.submit(
        PlotterBoundarySubmission(
          projection: foreign,
          intent: .stop(active.cancellationCapabilityID!)
        )
      ),
      reason: .staleProjection,
      remedy: .useCurrentProjection
    )
    expectRefusal(
      await fixture.runtime.submit(
        PlotterBoundarySubmission(
          projection: active.reference,
          intent: .acquire(direction: .negativeX, mode: .normal)
        )
      ),
      reason: .operationInFlight,
      remedy: .waitForActiveOwner
    )
    #expect(await fixture.effects.preparationCount == 0)
    #expect(await fixture.effects.sideAdmissionCount == 0)

    let cancel = Task {
      await fixture.runtime.submit(
        PlotterBoundarySubmission(
          projection: (await fixture.runtime.snapshot(for: .live)).projection.reference,
          intent: .cancel(active.cancellationCapabilityID!)
        )
      )
    }
    _ = await fixture.recorder.waitForCancellation(.cancelAttempt, environment: .live)
    await gate.release()
    _ = await cancel.value
    let terminal = await fixture.recorder.waitForTerminalCount(1, environment: .live)
    #expect(terminal.projection.terminal?.disposition == .cancelled)
    #expect(await fixture.effects.sideAdmissionCount == 0)
  }

  @Test("pre-fact reservation owns one exact identity and invalid facts settle that owner")
  func preFactReservationIsExclusiveAndCausal() async throws {
    let cancellationGate = PlotterBoundaryAdmissionGate(held: true)
    let cancellationFixture = try makeBoundaryEpisodeFixture(admissionGate: cancellationGate)
    let initial = await cancellationFixture.runtime.snapshot(for: .live)
    guard case .applied(let reservedProjection) = await cancellationFixture.runtime.submit(
      submission(initial, .acquire(direction: .negativeX, mode: .normal))
    ) else {
      Issue.record("Expected the pre-fact Boundary reservation.")
      return
    }
    await cancellationGate.waitUntilReady()
    let reserved = await cancellationFixture.runtime.snapshot(for: .live)
    guard case .reserving(activity: .sideAcquisition, direction: .negativeX) =
      reserved.projection.phase
    else {
      Issue.record("Expected the exact pre-fact reserving phase.")
      return
    }
    let operationID = try #require(reserved.projection.reference.operationID)
    let capability = try #require(reserved.projection.cancellationCapabilityID)
    #expect(operationID == reservedProjection.reference.operationID)
    #expect(await cancellationFixture.facts.requestCount == 0)

    expectRefusal(
      await cancellationFixture.runtime.submit(
        submission(reserved, .acquire(direction: .negativeX, mode: .normal))
      ),
      reason: .operationInFlight,
      remedy: .waitForActiveOwner
    )
    expectRefusal(
      await cancellationFixture.runtime.submit(
        submission(reserved, .stop(PlotterBoundaryCancellationCapabilityID()))
      ),
      reason: .cancellationCapabilityMismatch,
      remedy: .useExactCancellationCapability
    )
    let foreignReference = PlotterBoundaryProjectionReference(
      environment: .live,
      revision: reserved.projection.reference.revision,
      operationID: PlotterBoundaryOperationID()
    )
    expectRefusal(
      await cancellationFixture.runtime.submit(
        PlotterBoundarySubmission(
          projection: foreignReference,
          intent: .stop(capability)
        )
      ),
      reason: .staleProjection,
      remedy: .useCurrentProjection
    )
    #expect(await cancellationFixture.effects.preparationCount == 0)
    #expect(await cancellationFixture.effects.sideAdmissionCount == 0)

    let cancelling = Task {
      await cancellationFixture.runtime.submit(submission(reserved, .cancel(capability)))
    }
    _ = await cancellationFixture.recorder.waitForCancellation(
      .cancelAttempt,
      environment: .live
    )
    await cancellationGate.release()
    _ = await cancelling.value
    let cancelled = await cancellationFixture.recorder.waitForTerminalCount(
      1,
      environment: .live
    )
    #expect(cancelled.projection.terminal?.operationID == operationID)
    #expect(cancelled.projection.terminal?.disposition == .cancelled)
    #expect(cancelled.attemptTerminals.count == 1)
    #expect(await cancellationFixture.effects.preparationCount == 0)
    #expect(await cancellationFixture.effects.sideAdmissionCount == 0)

    let invalidGate = PlotterBoundaryAdmissionGate(held: true)
    let invalidFixture = try makeBoundaryEpisodeFixture(admissionGate: invalidGate)
    guard case .applied(let invalidReserved) = await invalidFixture.runtime.submit(
      submission(
        await invalidFixture.runtime.snapshot(for: .live),
        .acquire(direction: .negativeX, mode: .normal)
      )
    ) else {
      Issue.record("Expected the invalid-fact reservation.")
      return
    }
    await invalidGate.waitUntilReady()
    let invalidOperationID = try #require(invalidReserved.reference.operationID)
    #expect(invalidReserved.cancellationCapabilityID != nil)
    #expect(await invalidFixture.facts.requestCount == 0)
    await invalidFixture.facts.setLearningEnabled(false)
    await invalidGate.release()
    let refused = await invalidFixture.recorder.waitForTerminalCount(1, environment: .live)
    #expect(refused.projection.terminal?.operationID == invalidOperationID)
    #expect(refused.projection.terminal?.disposition == .refused("learningDisabled"))
    #expect(refused.projection.lastRefusal?.reason == .learningDisabled)
    #expect(refused.attemptTerminals.count == 1)
    #expect(await invalidFixture.facts.requestCount == 1)
    #expect(await invalidFixture.effects.preparationCount == 0)
    #expect(await invalidFixture.effects.sideAdmissionCount == 0)
  }

  @Test("reserving publication precedes facts and remains cancellable and shutdown-safe")
  func reservingPublicationPrecedesFactsAndSettlesExactlyOnce() async throws {
    let cancellationGate = PlotterBoundaryAdmissionGate(held: true)
    let cancellationSink = BoundarySuspendingProjectionSink()
    let cancellationFixture = try makeBoundaryEpisodeFixture(
      admissionGate: cancellationGate,
      projectionSink: cancellationSink
    )
    let cancellationInitial = await cancellationFixture.runtime.snapshot(for: .live)
    let admission = Task {
      await cancellationFixture.runtime.submit(
        submission(
          cancellationInitial,
          .acquire(direction: .negativeX, mode: .normal)
        )
      )
    }
    let held = await cancellationSink.waitUntilHeld()
    guard case .reserving(activity: .sideAcquisition, direction: .negativeX) =
      held.projection.phase
    else {
      Issue.record("Expected the real reserving projection publication to be held.")
      return
    }
    let operationID = try #require(held.projection.reference.operationID)
    let capability = try #require(held.projection.cancellationCapabilityID)
    #expect(await cancellationFixture.facts.requestCount == 0)
    #expect(await cancellationFixture.effects.preparationCount == 0)
    #expect(await cancellationFixture.effects.sideAdmissionCount == 0)
    #expect(await cancellationFixture.effects.centerAdmissionCount == 0)

    let cancelling = Task {
      await cancellationFixture.runtime.submit(submission(held, .cancel(capability)))
    }
    let cancellingSnapshot = await cancellationSink.waitForCancellation(.cancelAttempt)
    #expect(cancellingSnapshot.projection.reference.operationID == operationID)
    #expect(await cancellationFixture.facts.requestCount == 0)
    #expect(await cancellationFixture.effects.preparationCount == 0)
    #expect(await cancellationFixture.effects.sideAdmissionCount == 0)
    #expect(await cancellationFixture.effects.centerAdmissionCount == 0)

    cancellationSink.releaseHeldPublication()
    _ = await admission.value
    await cancellationGate.waitUntilReady()
    #expect(await cancellationFixture.facts.requestCount == 0)
    #expect(await cancellationFixture.effects.preparationCount == 0)
    #expect(await cancellationFixture.effects.sideAdmissionCount == 0)
    await cancellationGate.release()
    _ = await cancelling.value
    let cancelled = await cancellationSink.waitForSettledTerminalCount(
      1,
      environment: .live
    )
    #expect(cancelled.projection.terminal?.operationID == operationID)
    #expect(cancelled.projection.terminal?.disposition == .cancelled)
    #expect(cancelled.attemptTerminals.count == 1)
    #expect(cancelled.projection.reference.operationID == nil)
    #expect(cancellationSink.heldPublicationCount == 1)
    #expect(await cancellationFixture.facts.requestCount == 0)
    #expect(await cancellationFixture.effects.preparationCount == 0)
    #expect(await cancellationFixture.effects.sideAdmissionCount == 0)
    #expect(await cancellationFixture.effects.cancellationCount == 0)

    let shutdownGate = PlotterBoundaryAdmissionGate(held: true)
    let shutdownSink = BoundarySuspendingProjectionSink()
    let shutdownFixture = try makeBoundaryEpisodeFixture(
      admissionGate: shutdownGate,
      projectionSink: shutdownSink
    )
    let shutdownInitial = await shutdownFixture.runtime.snapshot(for: .live)
    let shutdownAdmission = Task {
      await shutdownFixture.runtime.submit(
        submission(
          shutdownInitial,
          .acquire(direction: .positiveY, mode: .normal)
        )
      )
    }
    let shutdownHeld = await shutdownSink.waitUntilHeld()
    let shutdownOperationID = try #require(shutdownHeld.projection.reference.operationID)
    #expect(await shutdownFixture.facts.requestCount == 0)
    #expect(await shutdownFixture.effects.preparationCount == 0)
    #expect(await shutdownFixture.effects.sideAdmissionCount == 0)

    let shutdown = Task { await shutdownFixture.runtime.shutdown() }
    let shuttingDown = await shutdownSink.waitForCancellation(.shutdown)
    #expect(shuttingDown.projection.reference.operationID == shutdownOperationID)
    #expect(await shutdownFixture.facts.requestCount == 0)
    #expect(await shutdownFixture.effects.preparationCount == 0)
    #expect(await shutdownFixture.effects.sideAdmissionCount == 0)

    shutdownSink.releaseHeldPublication()
    _ = await shutdownAdmission.value
    await shutdownGate.waitUntilReady()
    #expect(await shutdownFixture.facts.requestCount == 0)
    await shutdownGate.release()
    await shutdown.value
    let shutdownTerminal = await shutdownSink.waitForSettledTerminalCount(
      1,
      environment: .live
    )
    #expect(shutdownTerminal.projection.terminal?.operationID == shutdownOperationID)
    #expect(shutdownTerminal.projection.terminal?.disposition == .shutdown)
    #expect(shutdownTerminal.attemptTerminals.count == 1)
    #expect(shutdownTerminal.projection.reference.operationID == nil)
    #expect(shutdownSink.heldPublicationCount == 1)
    #expect(await shutdownFixture.facts.requestCount == 0)
    #expect(await shutdownFixture.effects.preparationCount == 0)
    #expect(await shutdownFixture.effects.sideAdmissionCount == 0)
    #expect(await shutdownFixture.effects.cancellationCount == 0)
  }

  @Test("suspended side advisory remains Stop and shutdown owned before lower admission")
  func suspendedSideAdvisorySettlesExactlyOnceWithoutLowerAdmission() async throws {
    let stopped = try makeBoundaryEpisodeFixture()
    await stopped.effects.holdNextSideAdvisory()
    guard case .applied(let active) = await stopped.runtime.submit(
      submission(
        await stopped.runtime.snapshot(for: .live),
        .acquire(direction: .negativeX, mode: .normal)
      )
    ) else {
      Issue.record("Expected exact Boundary admission before the held advisory.")
      return
    }
    let advisory = try await stopped.effects.waitForSideAdvisory(1)
    #expect(advisory.environment == .live)
    #expect(advisory.direction == .negativeX)
    let operationID = try #require(active.reference.operationID)
    let capability = try #require(active.cancellationCapabilityID)
    #expect(await stopped.effects.preparationCount == 1)
    #expect(await stopped.effects.sideAdmissionCount == 0)
    #expect(await stopped.effects.cancellationCount == 0)

    expectRefusal(
      await stopped.runtime.submit(
        submission(
          await stopped.runtime.snapshot(for: .live),
          .stop(PlotterBoundaryCancellationCapabilityID())
        )
      ),
      reason: .cancellationCapabilityMismatch,
      remedy: .useExactCancellationCapability
    )
    let stopping = Task {
      await stopped.runtime.submit(
        submission(await stopped.runtime.snapshot(for: .live), .stop(capability))
      )
    }
    _ = await stopped.recorder.waitForCancellation(.operatorStop, environment: .live)
    #expect(await stopped.effects.sideAdmissionCount == 0)
    await stopped.effects.releaseHeldSideAdvisory()
    _ = await stopping.value
    let stoppedTerminal = await stopped.recorder.waitForTerminalCount(1, environment: .live)
    #expect(stoppedTerminal.projection.terminal?.operationID == operationID)
    #expect(stoppedTerminal.projection.terminal?.disposition == .cancelled)
    #expect(stoppedTerminal.attemptTerminals.count == 1)
    #expect(stoppedTerminal.projection.reference.operationID == nil)
    #expect(await stopped.effects.sideAdmissionCount == 0)
    #expect(await stopped.effects.cancellationCount == 0)

    let shutdown = try makeBoundaryEpisodeFixture()
    await shutdown.effects.holdNextSideAdvisory()
    guard case .applied(let shutdownActive) = await shutdown.runtime.submit(
      submission(
        await shutdown.runtime.snapshot(for: .live),
        .acquire(direction: .positiveY, mode: .normal)
      )
    ) else {
      Issue.record("Expected exact Boundary admission before shutdown advisory hold.")
      return
    }
    _ = try await shutdown.effects.waitForSideAdvisory(1)
    let shutdownOperationID = try #require(shutdownActive.reference.operationID)
    let shuttingDown = Task { await shutdown.runtime.shutdown() }
    _ = await shutdown.recorder.waitForCancellation(.shutdown, environment: .live)
    #expect(await shutdown.effects.preparationCount == 1)
    #expect(await shutdown.effects.sideAdmissionCount == 0)
    #expect(await shutdown.effects.cancellationCount == 0)
    await shutdown.effects.releaseHeldSideAdvisory()
    await shuttingDown.value
    let shutdownTerminal = await shutdown.recorder.waitForTerminalCount(
      1,
      environment: .live
    )
    #expect(shutdownTerminal.projection.terminal?.operationID == shutdownOperationID)
    #expect(shutdownTerminal.projection.terminal?.disposition == .shutdown)
    #expect(shutdownTerminal.attemptTerminals.count == 1)
    #expect(shutdownTerminal.projection.reference.operationID == nil)
    #expect(await shutdown.effects.sideAdmissionCount == 0)
    #expect(await shutdown.effects.cancellationCount == 0)
  }

  @Test("production composition owns one fixed-segment renewal and exact UI Stop routing")
  func fixedSegmentRenewalAndProductionUIStop() async throws {
    let identities = TipCalibrationSemanticIdentityState.ephemeral()
    let checkpointStore = try BoundaryRecoveryCheckpointStore(
      checkpoint: acceptedPenLearningTestCheckpoint(identity: identities.learningPathIdentity)
    )
    let checkpointActions = checkpointStore
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let lowerGate = BoundaryRenewalMotionGate()
    let runtimeAccess = TestBoundaryRuntimeAccess()
    let workspace = plotterApplicationRuntime(
      machine: machine,
      boundaryMotionBegin: { request, planner in
        .admitted(
          BoundaryMotionOperation(
            ownerID: request.ownerID,
            task: Task { await lowerGate.run(request, renewalPlanner: planner) }
          )
        )
      },
      jogCancel: { intent in await lowerGate.cancel(intent) },
      statePersistencePort: checkpointActions,
      tipCalibrationSemanticIdentities: identities,
      boundaryRuntimeAccess: runtimeAccess,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await workspace.performTestExerciseAction(
      .applySavedLearning,
      for: workspace.testCurrentLearningPathItemID
    )
    #expect(workspace.penInteractionCompleted)
    let owner = LearningPathItemID.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    let before = workspace.testPlotterUIProjection(selectedItemID: owner, includesLearningPath: true)
    try await submitRenderedBoundaryAcquisition(
      .positiveX,
      owner: owner,
      workspace: workspace
    )
    let request = await lowerGate.waitUntilRequested()
    #expect(request.direction == .positiveX)
    #expect(request.segment.delta.dx == 50)
    #expect(request.segment.delta.dy == 0)
    #expect(request.segment.feedMMPerMinute == 500)
    #expect(request.renewalBounds.minimumMM == 50)
    #expect(request.renewalBounds.maximumMM == 50)

    let active = workspace.testPlotterUIProjection(selectedItemID: owner, includesLearningPath: true)
    let boundaryRuntime = try #require(runtimeAccess.runtime)
    let expectedCapability = try #require(
      (await boundaryRuntime.snapshot(for: .live)).projection.cancellationCapabilityID
    )
    let stopAction = try #require(active.semantic.actions.first { action in
      guard case .learningAction(let request) = action.intent,
        request.item.rawValue == "\(owner.number)-\(owner.title)",
        case .boundary(.stop(let capability)) = request.action
      else { return false }
      return capability == expectedCapability
    })
    let exact = try #require(active.semantic.request(for: stopAction.id))
    let stale = PlotterUIRequest(
      id: PlotterUIRequestID(rawValue: UUID()),
      uiRevision: exact.uiRevision,
      runtimeRevisions: before.semantic.runtimeRevisions,
      actionID: exact.actionID,
      intent: exact.intent
    )
    let sink: any PlotterUIIntentSink = workspace
    // Cancellation keeps the exact active capability even when unrelated
    // runtime revisions change after the operator's Stop was rendered.
    await lowerGate.releaseFirstSegment()
    let exactStop = Task { await sink.submitPlotterUIRequest(stale) }
    let stopDisposition = await exactStop.value
    guard case .accepted(_) = stopDisposition else {
      Issue.record("Expected the exact projected Boundary Stop request to route.")
      return
    }
    let runtime = try #require(runtimeAccess.runtime)
    let settled = await runtime.snapshot(for: .live)
    #expect(settled.acceptedAggregates[.positiveX]?.estimateMM == 50)
    #expect(await machine.requestedBoundaryRequests.count == 0)
    #expect(await machine.cancelCount == 0)
    await workspace.shutdown()
  }

  @Test("LIVE center refreshes settled controller MPos and publishes terminal position")
  func liveCenterUsesControllerSessionTruthInsteadOfPresentationCache() async throws {
    let identities = TipCalibrationSemanticIdentityState.ephemeral()
    let checkpointStore = try BoundaryRecoveryCheckpointStore(
      checkpoint: acceptedPenLearningTestCheckpoint(identity: identities.learningPathIdentity)
    )
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(
      log: log,
      relativeJogSettlementOffset: try Vector2<MachineSpace>(dx: 0, dy: 0)
    )
    let runtimeAccess = TestBoundaryRuntimeAccess()
    let workspace = plotterApplicationRuntime(
      machine: machine,
      statePersistencePort: checkpointStore,
      tipCalibrationSemanticIdentities: identities,
      boundaryRuntimeAccess: runtimeAccess,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await workspace.performTestExerciseAction(
      .applySavedLearning,
      for: workspace.testCurrentLearningPathItemID
    )
    #expect(workspace.penInteractionCompleted)
    try await installAcceptedBoundaryTestProjection(
      runtime: try #require(runtimeAccess.runtime),
      workspace: workspace,
      environment: .live,
      centerArrivalIsAccepted: false
    )

    // Reproduce the incident: presentation says X 49.997/Y 0 while the
    // controller-session owner has since settled at X 100/Y 50.
    try await machine.setPosition(x: 49.997, y: 0)
    await submitControllerSession(workspace, .requestPassiveProbe)
    #expect(workspace.machineSnapshot?.machine.position == (try MachinePosition(x: 49.997, y: 0)))
    try await machine.setPosition(x: 100, y: 50)
    let snapshotCallsBeforeCenter = await machine.snapshotCallCount

    let owner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    try requireEnabledPublicAction(
      .boundary(.moveToEstimatedCenter(retry: false)),
      owner: owner,
      workspace: workspace
    )
    await workspace.performTestExerciseAction(
      .boundary(.moveToEstimatedCenter(retry: false)),
      for: owner
    )
    try await waitForAcceptedBoundaryCenterArrival(workspace: workspace)

    let center = try MachinePosition(x: 0, y: 0)
    #expect(workspace.testCenterArrivalPosition == center)
    #expect(workspace.machineSnapshot?.machine.position == center)
    #expect(await machine.snapshotCallCount > snapshotCallsBeforeCenter)
    #expect(!workspace.testBoundaryCenterArrivalRetryRequired)
    #expect(
      workspace.currentExerciseActionStripPresentation?.actions.contains {
        $0.kind == .boundary(.moveToEstimatedCenter(retry: true))
      } == false
    )
    await workspace.shutdown()
  }

  @Test("foreign Stop refuses and exact Stop publishes one atomic accepted terminal")
  func exactStopPublishesAtomically() async throws {
    let terminalGate = PlotterBoundaryTerminalPublicationGate(held: true)
    let fixture = try makeBoundaryEpisodeFixture(terminalPublicationGate: terminalGate)
    let initial = await fixture.runtime.snapshot(for: .live)
    guard case .applied = await fixture.runtime.submit(
      submission(initial, .acquire(direction: .negativeX, mode: .normal))
    ) else {
      Issue.record("Expected exact Stop test admission.")
      return
    }
    let lower = await fixture.effects.waitForSideAdmission(1)
    let active = await fixture.runtime.snapshot(for: .live)
    let capability = try #require(active.projection.cancellationCapabilityID)
    expectRefusal(
      await fixture.runtime.submit(
        submission(active, .stop(PlotterBoundaryCancellationCapabilityID()))
      ),
      reason: .cancellationCapabilityMismatch,
      remedy: .useExactCancellationCapability
    )
    #expect(await fixture.effects.cancellationCount == 0)

    let stopping = Task { await fixture.runtime.submit(submission(active, .stop(capability))) }
    _ = await fixture.effects.waitForCancellation(1)
    await fixture.effects.settle(
      lower,
      with: .operatorStopped(
        finalPosition: try MachinePosition(x: -100, y: 0),
        idleVerified: true
      )
    )
    await terminalGate.waitUntilReady()
    let held = await fixture.runtime.snapshot(for: .live)
    #expect(held.acceptedAggregates.isEmpty)
    #expect(held.projection.reference.operationID == active.projection.reference.operationID)
    expectRefusal(
      await fixture.runtime.submit(
        submission(held, .acquire(direction: .positiveX, mode: .normal))
      ),
      reason: .operationInFlight,
      remedy: .waitForActiveOwner
    )

    await terminalGate.release()
    _ = await stopping.value
    let published = await fixture.recorder.waitForAcceptedCount(1, environment: .live)
    #expect(published.acceptedEvidence.count == 1)
    #expect(published.acceptedAggregates[.negativeX]?.estimateMM == -100)
    #expect(published.attemptTerminals.count == 1)
    #expect(published.projection.terminal?.disposition == .accepted)
    #expect(published.projection.reference.operationID == nil)
    #expect(!published.projection.physicalEvidenceClaimed)
  }

  @Test("Cancel is distinct from Stop and cannot accept Boundary evidence")
  func cancelDoesNotAcceptEvidence() async throws {
    let fixture = try makeBoundaryEpisodeFixture()
    let initial = await fixture.runtime.snapshot(for: .live)
    guard case .applied = await fixture.runtime.submit(
      submission(initial, .acquire(direction: .negativeY, mode: .normal))
    ) else {
      Issue.record("Expected cancel test admission.")
      return
    }
    let lower = await fixture.effects.waitForSideAdmission(1)
    let active = await fixture.runtime.snapshot(for: .live)
    let capability = try #require(active.projection.cancellationCapabilityID)
    let cancelling = Task { await fixture.runtime.submit(submission(active, .cancel(capability))) }
    let cancellation = await fixture.effects.waitForCancellation(1)
    #expect(cancellation.intent == .cancelAttempt)
    await fixture.effects.settle(
      lower,
      with: .cancelled(finalPosition: try MachinePosition(x: 0, y: -25))
    )
    _ = await cancelling.value
    let terminal = await fixture.recorder.waitForTerminalCount(1, environment: .live)
    #expect(terminal.projection.terminal?.disposition == .cancelled)
    #expect(terminal.acceptedEvidence.isEmpty)
    #expect(terminal.acceptedAggregates.isEmpty)
  }

  @Test("shutdown closes admission and quiesces an owner before lower motion")
  func shutdownBeforeLowerIsQuiescent() async throws {
    let gate = PlotterBoundaryAdmissionGate(held: true)
    let fixture = try makeBoundaryEpisodeFixture(admissionGate: gate)
    let initial = await fixture.runtime.snapshot(for: .live)
    guard case .applied = await fixture.runtime.submit(
      submission(initial, .acquire(direction: .positiveY, mode: .normal))
    ) else {
      Issue.record("Expected shutdown test admission.")
      return
    }
    await gate.waitUntilReady()
    let shutdown = Task { await fixture.runtime.shutdown() }
    await gate.release()
    await shutdown.value
    let terminal = await fixture.recorder.waitForTerminalCount(1, environment: .live)
    #expect(terminal.projection.terminal?.disposition == .shutdown)
    #expect(terminal.projection.reference.operationID == nil)
    #expect(await fixture.effects.preparationCount == 0)
    #expect(await fixture.effects.sideAdmissionCount == 0)
    expectRefusal(
      await fixture.runtime.submit(
        submission(terminal, .acquire(direction: .positiveY, mode: .normal))
      ),
      reason: .admissionClosed,
      remedy: .restartApplication
    )
  }

  @Test("lower refusal and ambiguity publish needs-attention without retry")
  func refusalAndAmbiguityDoNotRetry() async throws {
    let refused = try makeBoundaryEpisodeFixture()
    await refused.effects.setNextAdmission(.refused("controller refused Boundary"))
    guard case .applied = await refused.runtime.submit(
      submission(
        await refused.runtime.snapshot(for: .live),
        .acquire(direction: .negativeX, mode: .normal)
      )
    ) else {
      Issue.record("Expected lower-refusal test admission.")
      return
    }
    let refusedTerminal = await refused.recorder.waitForTerminalCount(1, environment: .live)
    #expect(
      refusedTerminal.projection.terminal?.disposition
        == .refused("controller refused Boundary")
    )
    #expect(await refused.effects.sideAdmissionCount == 1)

    let ambiguous = try makeBoundaryEpisodeFixture()
    await ambiguous.effects.setNextAdmission(.ambiguous("possible physical change"))
    guard case .applied = await ambiguous.runtime.submit(
      submission(
        await ambiguous.runtime.snapshot(for: .live),
        .acquire(direction: .negativeX, mode: .normal)
      )
    ) else {
      Issue.record("Expected lower-ambiguity test admission.")
      return
    }
    let ambiguousTerminal = await ambiguous.recorder.waitForTerminalCount(1, environment: .live)
    #expect(
      ambiguousTerminal.projection.terminal?.disposition
        == .ambiguous("possible physical change")
    )
    #expect(await ambiguous.effects.sideAdmissionCount == 1)
    #expect(ambiguousTerminal.acceptedAggregates.isEmpty)
  }

  @Test("record-another aggregates and publication failure preserves prior authority")
  func boundaryAtomicFailurePreservesAcceptedAuthority() async throws {
    let fixture = try makeBoundaryEpisodeFixture()
    _ = try await acceptSide(
      fixture,
      direction: .negativeX,
      mode: .normal,
      finalPosition: try MachinePosition(x: -100, y: 0)
    )
    let first = try await acceptSide(
      fixture,
      direction: .negativeX,
      mode: .additional,
      finalPosition: try MachinePosition(x: -98, y: 0)
    )
    #expect(first.acceptedAggregates[.negativeX]?.estimateMM == -99)
    #expect(first.acceptedAggregates[.negativeX]?.validSampleCount == 2)
    let prior = try #require(first.acceptedAggregates[.negativeX])

    await fixture.persistence.failNextSave()
    _ = try await acceptSide(
      fixture,
      direction: .negativeX,
      mode: .replacement,
      finalPosition: try MachinePosition(x: -110, y: 0),
      expectedAcceptedCount: 2
    )
    let incomplete = await fixture.runtime.snapshot(for: .live)
    #expect(incomplete.acceptedAggregates[.negativeX] == prior)
    let recovery = try #require(incomplete.projection.publicationRecoveryCapabilityID)
    let recoveredDisposition = await fixture.runtime.submit(
      submission(incomplete, .recoverPublication(recovery))
    )
    guard case .applied = recoveredDisposition else {
      Issue.record("Expected exact publication recovery to apply.")
      return
    }
    let recovered = await fixture.runtime.snapshot(for: .live)
    #expect(recovered.acceptedAggregates[.negativeX]?.estimateMM == -110)
    #expect(recovered.acceptedAggregates[.negativeX]?.validSampleCount == 1)
  }

  @Test("canonical UI recovery is exclusive and Learning reset preserves pending authority")
  func workspaceRecoveryAndResetAreCapabilityBound() async throws {
    let identities = TipCalibrationSemanticIdentityState.ephemeral()
    let checkpointStore = try BoundaryRecoveryCheckpointStore(
      checkpoint: acceptedPenLearningTestCheckpoint(identity: identities.learningPathIdentity)
    )
    let checkpointActions = checkpointStore
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let lowerGate = BoundaryRenewalMotionGate()
    let runtimeAccess = TestBoundaryRuntimeAccess()
    let workspace = plotterApplicationRuntime(
      machine: machine,
      boundaryMotionBegin: { request, planner in
        .admitted(BoundaryMotionOperation(
          ownerID: request.ownerID,
          task: Task { await lowerGate.run(request, renewalPlanner: planner) }
        ))
      },
      jogCancel: { intent in await lowerGate.cancel(intent) },
      statePersistencePort: checkpointActions,
      tipCalibrationSemanticIdentities: identities,
      boundaryRuntimeAccess: runtimeAccess,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    let penOwner = workspace.testCurrentLearningPathItemID
    await workspace.performTestExerciseAction(.applySavedLearning, for: penOwner)
    #expect(workspace.penInteractionCompleted)

    checkpointStore.failNextSave()
    let boundaryOwner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    try await submitRenderedBoundaryAcquisition(
      .positiveX,
      owner: boundaryOwner,
      workspace: workspace
    )
    _ = await lowerGate.waitUntilRequested()
    let active = try #require(workspace.currentBoundarySnapshot)
    let stopCapability = try #require(active.projection.cancellationCapabilityID)
    let stopping = Task {
      await workspace.performTestExerciseAction(
        .boundary(.stop(stopCapability)),
        for: boundaryOwner
      )
    }
    await lowerGate.releaseFirstSegment()
    _ = await stopping.value
    let pending = try #require(workspace.currentBoundarySnapshot)
    let recovery = try #require(pending.projection.publicationRecoveryCapabilityID)
    guard case .publicationIncomplete(recovery) = pending.projection.phase else {
      Issue.record("Expected exact pending Boundary publication.")
      return
    }
    #expect(pending.acceptedAggregates.isEmpty)
    #expect(await lowerGate.requestCount == 1)

    let penRevision = workspace.learningArtifactGraph.currentRevision(for: .penInteraction)
    let graphBeforeReset = Set(workspace.learningArtifactGraph.revisions)
    let checkpointBeforeReset = checkpointStore.checkpoint
    let resetPlan = try #require(workspace.resetAllLearningPlan)
    let didResetPending = await workspace.submitResetAllLearning(resetPlan)
    #expect(!didResetPending)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .penInteraction) == penRevision)
    #expect(Set(workspace.learningArtifactGraph.revisions) == graphBeforeReset)
    #expect(checkpointStore.checkpoint?.checkpointID == checkpointBeforeReset?.checkpointID)
    #expect(workspace.controllerSessionProjection.sessionEstablished)
    #expect(workspace.controllerSessionProjection.motionAuthorized)
    #expect(workspace.currentBoundarySnapshot?.projection.publicationRecoveryCapabilityID == recovery)
    #expect(
      workspace.learningAuthorityError?.contains("Boundary publication is incomplete") == true
    )

    let actionKinds = try #require(
      workspace.selectedOperatorActionPresentation(for: boundaryOwner).actionStrip
    ).actions.map(\.kind)
    #expect(actionKinds == [.boundary(.recoverPublication(recovery))])
    let uiProjection = workspace.testPlotterUIProjection(
      selectedItemID: boundaryOwner,
      includesLearningPath: true
    )
    let boundaryIntents = uiProjection.semantic.actions.compactMap { action in
      if case .learningAction(let request) = action.intent,
        case .boundary(let intent) = request.action
      {
        return intent
      }
      return nil
    }
    #expect(boundaryIntents == [.recoverPublication(recovery)])
    let recoveryActionID = learningActionID(
      .boundary(.recoverPublication(recovery)),
      owner: boundaryOwner
    )
    let request = try #require(uiProjection.semantic.request(for: recoveryActionID))
    guard case .accepted = await workspace.submitPlotterUIRequest(request) else {
      Issue.record("Expected exact production UI Boundary recovery.")
      return
    }
    let recovered = try #require(workspace.currentBoundarySnapshot)
    #expect(recovered.projection.publicationRecoveryCapabilityID == nil)
    #expect(recovered.acceptedAggregates[.positiveX]?.validSampleCount == 1)
    #expect(await lowerGate.requestCount == 1)

    let freshResetPlan = try #require(workspace.resetAllLearningPlan)
    let didReset = await workspace.submitResetAllLearning(freshResetPlan)
    #expect(didReset)
    #expect(workspace.currentBoundarySnapshot?.acceptedAggregates.isEmpty == true)
    #expect(workspace.currentBoundarySnapshot?.projection.reference.operationID == nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .penInteraction) == nil)
    #expect(checkpointStore.checkpoint == nil)
    await workspace.shutdown()
  }

  @Test("reset reservation preserves authority and requires exact commit or abort")
  func resetReservationIsCapabilityBoundAndAtomic() async throws {
    let fixture = try makeBoundaryEpisodeFixture()
    let prior = try await acceptSide(
      fixture,
      direction: .negativeX,
      mode: .normal,
      finalPosition: try MachinePosition(x: -100, y: 0)
    )
    guard case .applied(let reservedProjection) = await fixture.runtime.submit(
      submission(prior, .reserveReset)
    ) else {
      Issue.record("Expected an exact Boundary reset reservation.")
      return
    }
    let reserved = await fixture.runtime.snapshot(for: .live)
    let capability = try #require(reservedProjection.resetCapabilityID)
    #expect(reserved.projection.phase == .resetReserved(capability))
    #expect(reserved.projection.reference.revision.rawValue == prior.projection.reference.revision.rawValue + 1)
    #expect(reserved.acceptedEvidence == prior.acceptedEvidence)
    #expect(reserved.acceptedAggregates == prior.acceptedAggregates)
    #expect(reserved.pairedProgress == prior.pairedProgress)
    #expect(reserved.estimatedCenter == prior.estimatedCenter)
    #expect(reserved.localCoordinateFrame == prior.localCoordinateFrame)
    #expect(reserved.centerArrivalPosition == prior.centerArrivalPosition)
    #expect(reserved.attemptTerminals == prior.attemptTerminals)
    #expect(reserved.currentRevisions == prior.currentRevisions)
    #expect(reserved.acceptedMachineArtifacts == prior.acceptedMachineArtifacts)
    #expect(
      reserved.projection.publicationRecoveryCapabilityID
        == prior.projection.publicationRecoveryCapabilityID
    )
    expectRefusal(
      await fixture.runtime.submit(
        submission(reserved, .acquire(direction: .negativeX, mode: .replacement))
      ),
      reason: .resetTransactionInFlight,
      remedy: .waitForResetTransaction
    )
    expectRefusal(
      await fixture.runtime.submit(submission(prior, .commitReset(capability))),
      reason: .staleProjection,
      remedy: .useCurrentProjection
    )
    expectRefusal(
      await fixture.runtime.submit(
        submission(reserved, .commitReset(PlotterBoundaryResetCapabilityID()))
      ),
      reason: .resetCapabilityMismatch,
      remedy: .useExactResetCapability
    )
    expectRefusal(
      await fixture.runtime.submit(
        submission(reserved, .abortReset(PlotterBoundaryResetCapabilityID()))
      ),
      reason: .resetCapabilityMismatch,
      remedy: .useExactResetCapability
    )
    guard case .applied = await fixture.runtime.submit(
      submission(reserved, .abortReset(capability))
    ) else {
      Issue.record("Expected the exact reset abort capability to restore prior authority.")
      return
    }
    let aborted = await fixture.runtime.snapshot(for: .live)
    #expect(aborted.projection.phase == prior.projection.phase)
    #expect(aborted.projection.resetCapabilityID == nil)
    #expect(aborted.projection.reference.revision.rawValue == prior.projection.reference.revision.rawValue + 2)
    #expect(aborted.acceptedEvidence == prior.acceptedEvidence)
    #expect(aborted.acceptedAggregates == prior.acceptedAggregates)
    #expect(aborted.currentRevisions == prior.currentRevisions)
    #expect(aborted.acceptedMachineArtifacts == prior.acceptedMachineArtifacts)

    guard case .applied(let secondReservation) = await fixture.runtime.submit(
      submission(aborted, .reserveReset)
    ) else {
      Issue.record("Expected a fresh reset reservation after exact abort.")
      return
    }
    let commitCapability = try #require(secondReservation.resetCapabilityID)
    guard case .applied = await fixture.runtime.submit(
      submission(secondReservation, .commitReset(commitCapability))
    ) else {
      Issue.record("Expected the exact reset commit capability to apply.")
      return
    }
    let committed = await fixture.runtime.snapshot(for: .live)
    #expect(committed.projection.phase == .idle)
    #expect(committed.projection.resetCapabilityID == nil)
    #expect(committed.acceptedEvidence.isEmpty)
    #expect(committed.acceptedAggregates.isEmpty)
    #expect(committed.currentRevisions.isEmpty)
    #expect(committed.acceptedMachineArtifacts == nil)

    let pendingFixture = try makeBoundaryEpisodeFixture()
    _ = try await acceptSide(
      pendingFixture,
      direction: .positiveX,
      mode: .normal,
      finalPosition: try MachinePosition(x: 100, y: 0)
    )
    await pendingFixture.persistence.failNextSave()
    _ = try await acceptSide(
      pendingFixture,
      direction: .positiveX,
      mode: .replacement,
      finalPosition: try MachinePosition(x: 110, y: 0),
      expectedAcceptedCount: 1
    )
    let pending = await pendingFixture.runtime.snapshot(for: .live)
    #expect(pending.projection.publicationRecoveryCapabilityID != nil)
    expectRefusal(
      await pendingFixture.runtime.submit(submission(pending, .reserveReset)),
      reason: .publicationRecoveryRequired,
      remedy: .retryExactPublication
    )
    #expect(
      (await pendingFixture.runtime.snapshot(for: .live)).projection
        .publicationRecoveryCapabilityID == pending.projection.publicationRecoveryCapabilityID
    )
  }

  @Test("Boundary repeat actions aggregate and replace the accepted set atomically")
  func boundaryRepeatActionsAggregateAndReplaceAcceptedSet() async throws {
    let fixture = try makeBoundaryEpisodeFixture()
    _ = try await acceptSide(
      fixture,
      direction: .positiveX,
      mode: .normal,
      finalPosition: try MachinePosition(x: 100, y: 0)
    )
    _ = try await acceptSide(
      fixture,
      direction: .positiveX,
      mode: .additional,
      finalPosition: try MachinePosition(x: 101, y: 0)
    )
    let accumulated = try await acceptSide(
      fixture,
      direction: .positiveX,
      mode: .additional,
      finalPosition: try MachinePosition(x: 102, y: 0)
    )
    let priorIDs = try #require(
      accumulated.acceptedAggregates[.positiveX]?.includedAttemptIDs
    )
    #expect(accumulated.acceptedAggregates[.positiveX]?.validSampleCount == 3)
    #expect(priorIDs.count == 3)

    let replaced = try await acceptSide(
      fixture,
      direction: .positiveX,
      mode: .replacement,
      finalPosition: try MachinePosition(x: 110, y: 0)
    )
    let aggregate = try #require(replaced.acceptedAggregates[.positiveX])
    let replacementID = try #require(aggregate.includedAttemptIDs.only)
    #expect(aggregate.validSampleCount == 1)
    #expect(Set(aggregate.supersededAttempts.map(\.attemptID)) == Set(priorIDs))
    #expect(priorIDs.allSatisfy { prior in replaced.acceptedEvidence.contains { $0.attemptID == prior } })
    #expect(replaced.acceptedEvidence.contains { $0.attemptID == replacementID })
  }

  @Test("four exact sides derive center and local frame from consumed revisions")
  func fourSidesDeriveCenterAndFrame() async throws {
    let fixture = try makeBoundaryEpisodeFixture()
    for sample in [
      (PlotterBoundaryDirection.negativeX, try MachinePosition(x: -100, y: 0)),
      (.positiveX, try MachinePosition(x: 100, y: 0)),
      (.negativeY, try MachinePosition(x: 0, y: -50)),
      (.positiveY, try MachinePosition(x: 0, y: 50)),
    ] {
      _ = try await acceptSide(
        fixture,
        direction: sample.0,
        mode: .normal,
        finalPosition: sample.1
      )
    }
    let snapshot = await fixture.runtime.snapshot(for: .live)
    #expect(snapshot.pairedProgress.isComplete)
    #expect(snapshot.acceptedAggregates.count == 4)
    #expect(snapshot.estimatedCenter?.point == (try Point2(x: 0, y: 0)))
    #expect(snapshot.localCoordinateFrame?.origin == (try Point2(x: -100, y: -50)))
    #expect(snapshot.estimatedCenter?.consumedRevisionIDs.count == 4)
    #expect(
      Set(snapshot.acceptedAggregates.values.map(\.revisionID))
        == snapshot.estimatedCenter?.consumedRevisionIDs
    )
  }

  @Test("retained Boundary rejects mixed numeric contexts before every side mode",
    arguments: [false, true],
    [PlotterBoundaryAttemptMode.normal, .replacement, .additional])
  func incompatibleRetainedSideContext(changesSession: Bool, mode: PlotterBoundaryAttemptMode) async throws {
    let fixture = try makeBoundaryEpisodeFixture()
    let direction: PlotterBoundaryDirection
    if mode == .normal {
      _ = try await acceptSide(fixture, direction: .positiveX, mode: .normal,
        finalPosition: MachinePosition(x: 100, y: 0))
      direction = .negativeX
    } else {
      try await fixture.runtime.restore(acceptedBoundaryTestCheckpoint(
        controllerSessionID: boundaryEpisodeControllerSessionID), environment: .live)
      direction = .positiveY
    }
    let session = changesSession ? UUID() : boundaryEpisodeControllerSessionID
    let coordinate: UInt64 = changesSession ? 1 : 2
    await fixture.facts.setControllerContext(session: session, coordinate: coordinate)
    let before = await fixture.runtime.snapshot(for: .live)
    let preparationCount = await fixture.effects.preparationCount
    let sideCount = await fixture.effects.sideAdmissionCount
    let saveCount = await fixture.persistence.candidateCount
    guard case .applied = await fixture.runtime.submit(submission(before,
      .acquire(direction: direction, mode: mode))) else {
      Issue.record("Expected the exact pre-fact reservation."); return
    }
    _ = await fixture.recorder.waitForTerminalCount(before.attemptTerminals.count + 1,
      environment: .live)
    try await waitUntilAsync {
      (await fixture.runtime.snapshot(for: .live)).projection.reference.operationID == nil
    }
    let after = await fixture.runtime.snapshot(for: .live)
    let expected = PlotterBoundaryRefusalReason.retainedContextMismatch(
      expectedSessionID: boundaryEpisodeControllerSessionID, expectedCoordinateRevision: 1,
      actualSessionID: session, actualCoordinateRevision: coordinate)
    #expect(after.projection.lastRefusal?.reason == expected)
    #expect(after.projection.lastRefusal?.remedy == .resetBoundaryForCurrentSession)
    #expect(after.projection.terminal?.disposition == .refused(String(describing: expected)))
    #expect(after.acceptedMachineArtifacts == before.acceptedMachineArtifacts)
    #expect(after.acceptedEvidence == before.acceptedEvidence)
    #expect(after.acceptedAggregates == before.acceptedAggregates)
    #expect(await fixture.effects.preparationCount == preparationCount)
    #expect(await fixture.effects.sideAdmissionCount == sideCount)
    #expect(await fixture.persistence.candidateCount == saveCount)
    #expect(after.projection.lastRefusal?.operatorMessage.contains(session.uuidString) == false)

    // A pre-effect compatibility refusal must not trap the existing reset owner.
    guard case .applied(let reserved) = await fixture.runtime.submit(
      submission(after, .reserveReset)) else {
      Issue.record("Expected reset after a settled compatibility refusal."); return
    }
    let capability = try #require(reserved.resetCapabilityID)
    guard case .applied = await fixture.runtime.submit(PlotterBoundarySubmission(
      projection: reserved.reference, intent: .commitReset(capability))) else {
      Issue.record("Expected exact reset commit."); return
    }
    #expect((await fixture.runtime.snapshot(for: .live)).acceptedAggregates.isEmpty)
  }

  @Test("a settled side with invalid derived geometry is refused without inventing motion ambiguity")
  func settledSideValidationFailureRemainsResettable() async throws {
    let fixture = try makeBoundaryEpisodeFixture()
    try await fixture.runtime.restore(acceptedBoundaryTestCheckpoint(
      controllerSessionID: boundaryEpisodeControllerSessionID), environment: .live)
    let before = await fixture.runtime.snapshot(for: .live)
    let final = try MachinePosition(x: 0, y: -60)
    let after = try await acceptSide(fixture, direction: .positiveY, mode: .replacement,
      finalPosition: final, expectedAcceptedCount: 4)
    guard case .refused(let diagnostic) = after.projection.terminal?.disposition else {
      Issue.record("Invalid geometry after verified Stop must be a value refusal."); return
    }
    #expect(diagnostic.contains("invalidSpans"))
    #expect(after.projection.terminal?.finalPosition == .init(xMM: 0, yMM: -60))
    #expect(after.acceptedMachineArtifacts == before.acceptedMachineArtifacts)
    #expect(after.acceptedEvidence == before.acceptedEvidence)
    #expect(after.projection.phase == .needsAttention(
      "Boundary result was not accepted. Accepted Boundary is unchanged."))
    #expect(await fixture.persistence.candidateCount == 0)
    guard case .applied = await fixture.runtime.submit(submission(after, .reserveReset)) else {
      Issue.record("Settled result rejection must leave exact reset available."); return
    }
  }

  @Test("actual motion ambiguity still blocks Learning reset without spilling diagnostics")
  func ambiguousResetUsesConciseOperatorText() async throws {
    let diagnostic = String(repeating:
      "unresolved-owner-76F0EE52-5137-4052-B8A4-A0C933C3EB76 ", count: 30)
    let fixture = try makeBoundaryEpisodeFixture()
    await fixture.effects.setNextAdmission(.ambiguous(diagnostic))
    guard case .applied = await fixture.runtime.submit(submission(
      await fixture.runtime.snapshot(for: .live),
      .acquire(direction: .positiveX, mode: .normal))) else {
      Issue.record("Expected reservation before the lower ambiguity."); return
    }
    _ = await fixture.recorder.waitForTerminalCount(1, environment: .live)
    try await waitUntilAsync {
      (await fixture.runtime.snapshot(for: .live)).projection.reference.operationID == nil
    }
    let terminal = await fixture.runtime.snapshot(for: .live)
    #expect(terminal.projection.terminal?.disposition == .ambiguous(diagnostic))
    let applicationFixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { applicationFixture.stores.remove() }
    let app = applicationFixture.application
    do {
      // Feed the real lower-ambiguity projection to the production reset gate.
      app.installBoundarySnapshot(terminal)
      let plan = try #require(app.resetAllLearningPlan)
      #expect(!(await app.submitResetAllLearning(plan)))
      #expect(app.learningAuthorityError ==
        "Boundary motion is unresolved. Check the controller before resetting Learning.")
      #expect(app.currentBoundarySnapshot?.projection.terminal?.disposition == .ambiguous(diagnostic))
      #expect(await applicationFixture.machine.requestedBoundaryRequests.isEmpty)
      await app.shutdown()
    } catch {
      await app.shutdown()
      throw error
    }
  }

  @Test("retained Boundary cannot raise or travel until current physical alignment is established")
  func centerRequiresCurrentPhysicalPosition() async throws {
    let fixture = try makeBoundaryEpisodeFixture(machinePosition: try MachinePosition(x: 100, y: 50))
    try await fixture.runtime.restore(acceptedBoundaryTestCheckpoint(centerArrivalIsAccepted: false,
      controllerSessionID: boundaryEpisodeControllerSessionID), environment: .live)
    let before = await fixture.runtime.snapshot(for: .live)
    let reason = "Saved Boundary has no current physical alignment."
    await fixture.facts.setPhysicalPositionUnavailableReason(reason)
    guard case .applied = await fixture.runtime.submit(submission(before, .moveToEstimatedCenter(retry: false))) else {
      Issue.record("Expected the owner's pre-fact Center reservation"); return
    }
    // Fact admission runs after the stoppable reservation is published. Join
    // its terminal refusal before replacing facts or requesting another run.
    let refused = await fixture.recorder.waitForTerminalCount(1, environment: .live)
    #expect(refused.projection.lastRefusal?.reason == .physicalPositionUnverified(reason))
    #expect(refused.projection.lastRefusal?.remedy == .restorePhysicalPosition)
    #expect(refused.projection.terminal?.disposition == .refused(String(describing:
      PlotterBoundaryRefusalReason.physicalPositionUnverified(reason))))
    #expect(await fixture.effects.preparationCount == 0)
    #expect(await fixture.effects.centerAdmissionCount == 0)
    #expect(await fixture.persistence.candidateCount == 0)
    #expect((await fixture.runtime.snapshot(for: .live)).acceptedAggregates == before.acceptedAggregates)

    // The root supplies this fact only after its accepted recovery or explicit
    // relearning transaction; owner admission responds to that authority change.
    await fixture.facts.setPhysicalPositionUnavailableReason(nil)
    let current = await fixture.runtime.snapshot(for: .live)
    let resumed = await fixture.runtime.submit(submission(current,
      .moveToEstimatedCenter(retry: current.projection.centerArrivalRetryRequired)))
    guard case .applied = resumed else {
      Issue.record("Current physical authority failed to restore Center admission: \(resumed)"); return
    }
    let center = await fixture.effects.waitForCenterAdmission(1)
    await fixture.effects.settle(center.handle,
      with: .completed(finalPosition: try MachinePosition(x: 0, y: 0), idleVerified: true))
    let terminal = await fixture.recorder.waitForTerminalCount(2, environment: .live)
    #expect(terminal.projection.terminal?.disposition == .accepted)
    #expect(await fixture.effects.preparationCount == 1)
  }

  @Test("losing physical alignment during Pen Up preparation prevents Boundary Center travel")
  func physicalPositionLossBeforeCenterTravel() async throws {
    let fixture = try makeBoundaryEpisodeFixture(machinePosition: try MachinePosition(x: 100, y: 50))
    try await fixture.runtime.restore(acceptedBoundaryTestCheckpoint(centerArrivalIsAccepted: false,
      controllerSessionID: boundaryEpisodeControllerSessionID), environment: .live)
    let before = await fixture.runtime.snapshot(for: .live)
    await fixture.effects.holdNextPreparation()
    guard case .applied = await fixture.runtime.submit(submission(before, .moveToEstimatedCenter(retry: false))) else {
      Issue.record("Expected initial known-pose Center admission"); return
    }
    _ = await fixture.effects.waitForPreparation(1)
    await fixture.facts.setPhysicalPositionUnavailableReason("Controller continuity was lost while preparing.")
    await fixture.effects.releaseHeldPreparation(.success(()))
    let terminal = await fixture.recorder.waitForTerminalCount(1, environment: .live)
    #expect(terminal.projection.terminal?.disposition != .accepted)
    #expect(terminal.acceptedAggregates == before.acceptedAggregates)
    #expect(await fixture.effects.centerAdmissionCount == 0)
    #expect(await fixture.persistence.candidateCount == 0)
  }

  @Test("center arrival accepts exact settlement and outside tolerance offers center-only retry")
  func centerArrivalAndRetry() async throws {
    let accepted = try makeBoundaryEpisodeFixture(machinePosition: try MachinePosition(x: 100, y: 50))
    try await accepted.runtime.restore(
      acceptedBoundaryTestCheckpoint(
        centerArrivalIsAccepted: false,
        controllerSessionID: boundaryEpisodeControllerSessionID
      ),
      environment: .live
    )
    let restored = await accepted.runtime.snapshot(for: .live)
    expectRefusal(
      await accepted.runtime.submit(
        submission(restored, .moveToEstimatedCenter(retry: true))
      ),
      reason: .centerRetryMismatch(expected: false, submitted: true),
      remedy: .usePublishedCenterRetry
    )
    #expect(await accepted.effects.centerAdmissionCount == 0)
    guard case .applied = await accepted.runtime.submit(
      submission(
        await accepted.runtime.snapshot(for: .live),
        .moveToEstimatedCenter(retry: false)
      )
    ) else {
      Issue.record("Expected exact center admission.")
      return
    }
    let center = await accepted.effects.waitForCenterAdmission(1)
    #expect(center.delta.dx == -100)
    #expect(center.delta.dy == -50)
    await accepted.effects.settle(
      center.handle,
      with: .completed(finalPosition: try MachinePosition(x: 0, y: 0), idleVerified: true)
    )
    let arrived = await accepted.recorder.waitForTerminalCount(1, environment: .live)
    #expect(arrived.centerArrivalPosition == (try MachinePosition(x: 0, y: 0)))
    #expect(!arrived.projection.centerArrivalRetryRequired)
    expectRefusal(
      await accepted.runtime.submit(
        submission(
          await accepted.runtime.snapshot(for: .live),
          .moveToEstimatedCenter(retry: false)
        )
      ),
      reason: .centerArrivalAlreadyAccepted,
      remedy: .continueAfterAcceptedCenter
    )
    #expect(await accepted.effects.centerAdmissionCount == 1)

    let outside = try makeBoundaryEpisodeFixture(machinePosition: try MachinePosition(x: 100, y: 50))
    try await outside.runtime.restore(
      acceptedBoundaryTestCheckpoint(
        centerArrivalIsAccepted: false,
        controllerSessionID: boundaryEpisodeControllerSessionID
      ),
      environment: .live
    )
    guard case .applied = await outside.runtime.submit(
      submission(
        await outside.runtime.snapshot(for: .live),
        .moveToEstimatedCenter(retry: false)
      )
    ) else {
      Issue.record("Expected retry-center admission.")
      return
    }
    let outsideCenter = await outside.effects.waitForCenterAdmission(1)
    await outside.effects.settle(
      outsideCenter.handle,
      with: .completed(finalPosition: try MachinePosition(x: 1.001, y: 0), idleVerified: true)
    )
    let needsRetry = await outside.recorder.waitForTerminalCount(1, environment: .live)
    #expect(needsRetry.centerArrivalPosition == nil)
    #expect(needsRetry.projection.centerArrivalRetryRequired)
    #expect(needsRetry.acceptedAggregates.count == 4)
    if case .ambiguous(_) = needsRetry.projection.terminal?.disposition {
      // Expected: no center-arrival evidence was accepted.
    } else {
      Issue.record("Expected an out-of-tolerance center terminal to remain ambiguous.")
    }
    expectRefusal(
      await outside.runtime.submit(
        submission(
          await outside.runtime.snapshot(for: .live),
          .moveToEstimatedCenter(retry: false)
        )
      ),
      reason: .centerRetryMismatch(expected: true, submitted: false),
      remedy: .usePublishedCenterRetry
    )
    #expect(await outside.effects.centerAdmissionCount == 1)
    guard case .applied = await outside.runtime.submit(
      submission(
        await outside.runtime.snapshot(for: .live),
        .moveToEstimatedCenter(retry: true)
      )
    ) else {
      Issue.record("Expected the exact published center retry.")
      return
    }
    let retryCenter = await outside.effects.waitForCenterAdmission(2)
    await outside.effects.settle(
      retryCenter.handle,
      with: .completed(finalPosition: try MachinePosition(x: 0, y: 0), idleVerified: true)
    )
    let retried = await outside.recorder.waitForTerminalCount(2, environment: .live)
    #expect(retried.centerArrivalPosition == (try MachinePosition(x: 0, y: 0)))
    #expect(!retried.projection.centerArrivalRetryRequired)
  }

  @Test("center travel normalizes Pen Up first and keeps cancellation and failures on one owner")
  func centerPenUpOrderingAndFailureTruth() async throws {
    let live = try makeBoundaryEpisodeFixture(machinePosition: try MachinePosition(x: 100, y: 50))
    try await live.runtime.restore(
      acceptedBoundaryTestCheckpoint(
        centerArrivalIsAccepted: false,
        controllerSessionID: boundaryEpisodeControllerSessionID
      ),
      environment: .live
    )
    await live.effects.holdNextPreparation()
    guard case .applied(let activeProjection) = await live.runtime.submit(
      submission(
        await live.runtime.snapshot(for: .live),
        .moveToEstimatedCenter(retry: false)
      )
    ) else {
      Issue.record("Expected LIVE center admission.")
      return
    }
    let operationID = try #require(activeProjection.reference.operationID)
    _ = try #require(activeProjection.cancellationCapabilityID)
    #expect(await live.effects.waitForPreparation(1) == .live)
    #expect(await live.effects.centerAdmissionCount == 0)
    expectRefusal(
      await live.runtime.submit(
        submission(
          await live.runtime.snapshot(for: .live),
          .stop(PlotterBoundaryCancellationCapabilityID())
        )
      ),
      reason: .cancellationCapabilityMismatch,
      remedy: .useExactCancellationCapability
    )
    await live.effects.releaseHeldPreparation(.success(()))
    let center = await live.effects.waitForCenterAdmission(1)
    #expect(center.environment == .live)
    #expect(await live.effects.events == [
      .preparationBegan(.live),
      .preparationEnded(.live),
      .centerAdmitted(.live),
    ])
    await live.effects.settle(
      center.handle,
      with: .completed(finalPosition: try MachinePosition(x: 0, y: 0), idleVerified: true)
    )
    let liveTerminal = await live.recorder.waitForTerminalCount(1, environment: .live)
    #expect(liveTerminal.projection.terminal?.operationID == operationID)
    #expect(liveTerminal.projection.terminal?.disposition == .accepted)
    #expect(await live.persistence.candidateCount == 1)

    let cancelled = try makeBoundaryEpisodeFixture(
      machinePosition: try MachinePosition(x: 100, y: 50)
    )
    try await cancelled.runtime.restore(
      acceptedBoundaryTestCheckpoint(
        centerArrivalIsAccepted: false,
        controllerSessionID: boundaryEpisodeControllerSessionID
      ),
      environment: .live
    )
    await cancelled.effects.holdNextPreparation()
    guard case .applied(let cancellingProjection) = await cancelled.runtime.submit(
      submission(
        await cancelled.runtime.snapshot(for: .live),
        .moveToEstimatedCenter(retry: false)
      )
    ) else {
      Issue.record("Expected cancellable center retry admission.")
      return
    }
    let cancellingID = try #require(cancellingProjection.reference.operationID)
    let cancellingCapability = try #require(cancellingProjection.cancellationCapabilityID)
    _ = await cancelled.effects.waitForPreparation(1)
    let cancelTask = Task {
      await cancelled.runtime.submit(
        submission(
          await cancelled.runtime.snapshot(for: .live),
          .cancel(cancellingCapability)
        )
      )
    }
    _ = await cancelled.recorder.waitForCancellation(.cancelAttempt, environment: .live)
    await cancelled.effects.releaseHeldPreparation(.success(()))
    _ = await cancelTask.value
    let cancelledTerminal = await cancelled.recorder.waitForTerminalCount(1, environment: .live)
    #expect(cancelledTerminal.projection.terminal?.operationID == cancellingID)
    #expect(cancelledTerminal.projection.terminal?.disposition == .cancelled)
    #expect(await cancelled.effects.centerAdmissionCount == 0)

    let refused = try makeBoundaryEpisodeFixture(
      machinePosition: try MachinePosition(x: 100, y: 50)
    )
    try await refused.runtime.restore(
      acceptedBoundaryTestCheckpoint(
        centerArrivalIsAccepted: false,
        controllerSessionID: boundaryEpisodeControllerSessionID
      ),
      environment: .live
    )
    await refused.effects.setNextPreparation(
      .failure(PlotterBoundaryLowerPortFailure(detail: "Pen Up refused"))
    )
    guard case .applied(let refusedProjection) = await refused.runtime.submit(
      submission(
        await refused.runtime.snapshot(for: .live),
        .moveToEstimatedCenter(retry: false)
      )
    ) else {
      Issue.record("Expected refused Pen-Up owner admission.")
      return
    }
    let refusedTerminal = await refused.recorder.waitForTerminalCount(1, environment: .live)
    #expect(refusedTerminal.projection.terminal?.operationID == refusedProjection.reference.operationID)
    #expect(refusedTerminal.projection.terminal?.disposition == .refused("Pen Up refused"))
    #expect(await refused.effects.centerAdmissionCount == 0)

    let ambiguous = try makeBoundaryEpisodeFixture(
      machinePosition: try MachinePosition(x: 100, y: 50)
    )
    try await ambiguous.runtime.restore(
      acceptedBoundaryTestCheckpoint(
        centerArrivalIsAccepted: false,
        controllerSessionID: boundaryEpisodeControllerSessionID
      ),
      environment: .live
    )
    await ambiguous.effects.setNextPreparation(
      .failure(PlotterBoundaryLowerPortFailure(detail: "Pen Up ambiguous", ambiguous: true))
    )
    guard case .applied(let ambiguousProjection) = await ambiguous.runtime.submit(
      submission(
        await ambiguous.runtime.snapshot(for: .live),
        .moveToEstimatedCenter(retry: false)
      )
    ) else {
      Issue.record("Expected ambiguous Pen-Up owner admission.")
      return
    }
    let ambiguousTerminal = await ambiguous.recorder.waitForTerminalCount(1, environment: .live)
    #expect(
      ambiguousTerminal.projection.terminal?.operationID
        == ambiguousProjection.reference.operationID
    )
    #expect(ambiguousTerminal.projection.terminal?.disposition == .ambiguous("Pen Up ambiguous"))
    #expect(await ambiguous.effects.centerAdmissionCount == 0)

    let simulated = try makeBoundaryEpisodeFixture(
      machinePosition: try MachinePosition(x: 100, y: 50)
    )
    try await simulated.runtime.restore(
      acceptedBoundaryTestCheckpoint(
        centerArrivalIsAccepted: false,
        controllerSessionID: boundaryEpisodeControllerSessionID
      ),
      environment: .simulated
    )
    await simulated.effects.holdNextPreparation()
    guard case .applied = await simulated.runtime.submit(
      submission(
        await simulated.runtime.snapshot(for: .simulated),
        .moveToEstimatedCenter(retry: false)
      )
    ) else {
      Issue.record("Expected SIMULATED center admission.")
      return
    }
    #expect(await simulated.effects.waitForPreparation(1) == .simulated)
    #expect(await simulated.effects.centerAdmissionCount == 0)
    await simulated.effects.releaseHeldPreparation(.success(()))
    let simulatedCenter = await simulated.effects.waitForCenterAdmission(1)
    await simulated.effects.settle(
      simulatedCenter.handle,
      with: .completed(finalPosition: try MachinePosition(x: 0, y: 0), idleVerified: true)
    )
    let simulatedTerminal = await simulated.recorder.waitForTerminalCount(
      1,
      environment: .simulated
    )
    #expect(simulatedTerminal.projection.terminal?.disposition == .accepted)
    #expect(!simulatedTerminal.projection.physicalEvidenceClaimed)
    #expect(simulatedTerminal.projection.terminal?.physicalEvidenceClaimed == false)
    #expect(await simulated.persistence.candidateCount == 0)
    #expect(await simulated.effects.events.allSatisfy { $0.environment == .simulated })
  }

  @Test("LIVE and SIMULATED Boundary authority remain isolated and nonphysical")
  func liveAndSimulatedAuthorityAreIsolated() async throws {
    let fixture = try makeBoundaryEpisodeFixture()
    let simulated = await fixture.runtime.snapshot(for: .simulated)
    guard case .applied = await fixture.runtime.submit(
      submission(simulated, .acquire(direction: .positiveY, mode: .normal))
    ) else {
      Issue.record("Expected simulated Boundary admission.")
      return
    }
    let lower = await fixture.effects.waitForSideAdmission(1)
    #expect(lower.environment == .simulated)
    let active = await fixture.runtime.snapshot(for: .simulated)
    let capability = try #require(active.projection.cancellationCapabilityID)
    let stopping = Task {
      await fixture.runtime.submit(submission(active, .stop(capability)))
    }
    _ = await fixture.effects.waitForCancellation(1)
    await fixture.effects.settle(
      lower.handle,
      with: .operatorStopped(
        finalPosition: try MachinePosition(x: 0, y: 50),
        idleVerified: true
      )
    )
    _ = await stopping.value
    let simFinal = await fixture.runtime.snapshot(for: .simulated)
    let liveFinal = await fixture.runtime.snapshot(for: .live)
    #expect(simFinal.acceptedAggregates[.positiveY]?.estimateMM == 50)
    #expect(liveFinal.acceptedAggregates.isEmpty)
    #expect(simFinal.projection.reference.environment == .simulated)
    #expect(!simFinal.projection.physicalEvidenceClaimed)
    #expect(simFinal.projection.terminal?.physicalEvidenceClaimed == false)
  }
}

private extension Collection {
  var only: Element? { count == 1 ? first : nil }
}

private struct BoundaryEpisodeFixture {
  let runtime: PlotterBoundaryRuntime
  let facts: BoundaryEpisodeFactSource
  let effects: BoundaryEpisodeEffectPort
  let persistence: BoundaryEpisodePersistencePort
  let recorder: BoundaryEpisodeProjectionRecorder
}

private let boundaryEpisodeControllerSessionID =
  UUID(uuidString: "00000000-0000-0000-0000-00000000B010")!

@MainActor
private func makeBoundaryEpisodeFixture(
  machinePosition: MachinePosition = try! MachinePosition(x: 0, y: 0),
  admissionGate: PlotterBoundaryAdmissionGate? = nil,
  terminalPublicationGate: PlotterBoundaryTerminalPublicationGate? = nil,
  projectionSink: (any PlotterBoundaryProjectionSink)? = nil
) throws -> BoundaryEpisodeFixture {
  let identity = LearningPathSemanticIdentity(
    machineGeometry: MachineGeometryIdentity(),
    toolAssembly: ToolAssemblyRevision(),
    penContactProfile: PenContactProfileRevision(),
    paperInstance: PaperInstanceRevision(),
    paperContactPlane: PaperContactPlaneRevision(),
    cameraMountRevision: UUID(),
    cameraReframingRevision: UUID()
  )
  let facts = BoundaryEpisodeFactSource(
    machinePosition: machinePosition,
    passiveProbe: boundaryCheckpointProbe(position: machinePosition),
    semanticIdentity: identity
  )
  let effects = BoundaryEpisodeEffectPort()
  let persistence = BoundaryEpisodePersistencePort()
  let recorder = BoundaryEpisodeProjectionRecorder()
  let runtime = PlotterBoundaryRuntime(
    factSource: facts,
    effectPort: effects,
    persistencePort: persistence,
    projectionSink: projectionSink ?? recorder,
    admissionGate: admissionGate,
    terminalPublicationGate: terminalPublicationGate
  )
  return BoundaryEpisodeFixture(
    runtime: runtime,
    facts: facts,
    effects: effects,
    persistence: persistence,
    recorder: recorder
  )
}

private func submission(
  _ snapshot: PlotterBoundaryRuntimeSnapshot,
  _ intent: PlotterBoundaryIntent
) -> PlotterBoundarySubmission {
  PlotterBoundarySubmission(projection: snapshot.projection.reference, intent: intent)
}

private func submission(
  _ projection: PlotterBoundaryProjection,
  _ intent: PlotterBoundaryIntent
) -> PlotterBoundarySubmission {
  PlotterBoundarySubmission(projection: projection.reference, intent: intent)
}

@MainActor
private func acceptSide(
  _ fixture: BoundaryEpisodeFixture,
  direction: PlotterBoundaryDirection,
  mode: PlotterBoundaryAttemptMode,
  finalPosition: MachinePosition,
  expectedAcceptedCount: Int? = nil
) async throws -> PlotterBoundaryRuntimeSnapshot {
  let before = await fixture.runtime.snapshot(for: .live)
  let priorSideCount = await fixture.effects.sideAdmissionCount
  let disposition = await fixture.runtime.submit(
    submission(before, .acquire(direction: direction, mode: mode))
  )
  guard case .applied = disposition else {
    Issue.record("Expected Boundary side admission for \(direction).")
    return before
  }
  let lower = await fixture.effects.waitForSideAdmission(priorSideCount + 1)
  let active = await fixture.runtime.snapshot(for: .live)
  let capability = try #require(active.projection.cancellationCapabilityID)
  let priorCancellationCount = await fixture.effects.cancellationCount
  let stopping = Task {
    await fixture.runtime.submit(submission(active, .stop(capability)))
  }
  _ = await fixture.effects.waitForCancellation(priorCancellationCount + 1)
  await fixture.effects.settle(
    lower.handle,
    with: .operatorStopped(finalPosition: finalPosition, idleVerified: true)
  )
  _ = await stopping.value
  if expectedAcceptedCount != nil {
    return await fixture.runtime.snapshot(for: .live)
  }
  return await fixture.recorder.waitForAcceptedCount(
    before.acceptedEvidence.count + 1,
    environment: .live
  )
}

private func expectRefusal(
  _ disposition: PlotterBoundaryDisposition,
  reason: PlotterBoundaryRefusalReason,
  remedy: PlotterBoundaryRemedy
) {
  guard case .refused(let refusal) = disposition else {
    Issue.record("Expected Boundary refusal \(reason).")
    return
  }
  #expect(refusal.owner == "PlotterBoundaryRuntime")
  #expect(refusal.reason == reason)
  #expect(refusal.remedy == remedy)
}

private actor BoundaryEpisodeFactSource: PlotterBoundaryFactSource {
  private var machinePosition: MachinePosition
  private var learningEnabled = true
  private var physicalPositionUnavailableReason: String?
  private var controllerSessionID = boundaryEpisodeControllerSessionID
  private var coordinateRevision: UInt64 = 1
  private(set) var requestCount = 0
  private let passiveProbe: PassiveProbeResult
  private let semanticIdentity: LearningPathSemanticIdentity

  init(
    machinePosition: MachinePosition,
    passiveProbe: PassiveProbeResult,
    semanticIdentity: LearningPathSemanticIdentity
  ) {
    self.machinePosition = machinePosition
    self.passiveProbe = passiveProbe
    self.semanticIdentity = semanticIdentity
  }

  func setPhysicalPositionUnavailableReason(_ reason: String?) {
    physicalPositionUnavailableReason = reason
  }

  func setLearningEnabled(_ enabled: Bool) {
    learningEnabled = enabled
  }

  func setControllerContext(session: UUID, coordinate: UInt64) {
    controllerSessionID = session
    coordinateRevision = coordinate
  }

  func currentBoundaryFacts(for environment: PlotterEnvironment) -> PlotterBoundaryExternalFacts {
    requestCount += 1
    return PlotterBoundaryExternalFacts(
      environment: environment,
      learningEnabled: learningEnabled,
      controllerSessionEstablished: true,
      motionAuthorized: true,
      foreignLowerOperationInFlight: false,
      stickyAmbiguity: nil,
      controllerSessionID: controllerSessionID,
      coordinateRevision: coordinateRevision,
      machinePosition: machinePosition,
      interpreterIsIdle: true,
      passiveProbe: environment == .live ? passiveProbe : nil,
      penActuationProfile: .initialDefaults,
      semanticIdentity: semanticIdentity,
      physicalPositionUnavailableReason: physicalPositionUnavailableReason
    )
  }
}

private actor BoundaryEpisodeEffectPort: PlotterBoundaryEffectPort {
  private enum WaitError: Error {
    case timedOutWaitingForSideAdvisory
  }

  private struct SideAdvisoryWaiter {
    let id: UUID
    let count: Int
    let continuation: CheckedContinuation<SideAdvisory, any Error>
  }

  enum Event: Hashable, Sendable {
    case preparationBegan(PlotterEnvironment)
    case preparationEnded(PlotterEnvironment)
    case sideAdmitted(PlotterEnvironment)
    case centerAdmitted(PlotterEnvironment)
    case cancellationRequested(PlotterEnvironment)

    var environment: PlotterEnvironment {
      switch self {
      case .preparationBegan(let environment), .preparationEnded(let environment),
        .sideAdmitted(let environment), .centerAdmitted(let environment),
        .cancellationRequested(let environment):
        environment
      }
    }
  }

  struct SideAdmission: Sendable {
    let environment: PlotterEnvironment
    let direction: PlotterBoundaryDirection
    let handle: PlotterBoundaryLowerHandle
  }

  struct CenterAdmission: Sendable {
    let environment: PlotterEnvironment
    let delta: Vector2<MachineSpace>
    let handle: PlotterBoundaryLowerHandle
  }

  struct Cancellation: Sendable {
    let intent: PlotterBoundaryCancellationIntent
    let handle: PlotterBoundaryLowerHandle
  }

  struct SideAdvisory: Sendable {
    let environment: PlotterEnvironment
    let direction: PlotterBoundaryDirection
  }

  private(set) var preparationCount = 0
  private(set) var events: [Event] = []
  private(set) var sideAdmissions: [SideAdmission] = []
  private(set) var centerAdmissions: [CenterAdmission] = []
  private(set) var cancellations: [Cancellation] = []
  private(set) var sideAdvisories: [SideAdvisory] = []
  private var nextAdmission: PlotterBoundaryLowerAdmission?
  private var nextPreparation:
    Result<Void, PlotterBoundaryLowerPortFailure>?
  private var holdPreparation = false
  private var heldPreparation:
    CheckedContinuation<Result<Void, PlotterBoundaryLowerPortFailure>, Never>?
  private var holdSideAdvisory = false
  private var heldSideAdvisory:
    CheckedContinuation<Result<Void, PlotterBoundaryLowerPortFailure>, Never>?
  private var preparationWaiters:
    [(Int, CheckedContinuation<PlotterEnvironment, Never>)] = []
  private var terminalContinuations:
    [UUID: CheckedContinuation<PlotterBoundaryLowerTerminal, Never>] = [:]
  private var queuedTerminals: [UUID: PlotterBoundaryLowerTerminal] = [:]
  private var sideWaiters: [(Int, CheckedContinuation<SideAdmission, Never>)] = []
  private var centerWaiters: [(Int, CheckedContinuation<CenterAdmission, Never>)] = []
  private var cancellationWaiters: [(Int, CheckedContinuation<Cancellation, Never>)] = []
  private var sideAdvisoryWaiters: [SideAdvisoryWaiter] = []

  var sideAdmissionCount: Int { sideAdmissions.count }
  var centerAdmissionCount: Int { centerAdmissions.count }
  var cancellationCount: Int { cancellations.count }
  var sideAdvisoryCount: Int { sideAdvisories.count }

  func setNextAdmission(_ admission: PlotterBoundaryLowerAdmission) {
    nextAdmission = admission
  }

  func setNextPreparation(
    _ result: Result<Void, PlotterBoundaryLowerPortFailure>
  ) {
    nextPreparation = result
  }

  func holdNextPreparation() {
    holdPreparation = true
  }

  func waitForPreparation(_ count: Int) async -> PlotterEnvironment {
    let calls = events.compactMap { event -> PlotterEnvironment? in
      if case .preparationBegan(let environment) = event { return environment }
      return nil
    }
    if calls.count >= count { return calls[count - 1] }
    return await withCheckedContinuation { preparationWaiters.append((count, $0)) }
  }

  func releaseHeldPreparation(
    _ result: Result<Void, PlotterBoundaryLowerPortFailure>
  ) {
    heldPreparation?.resume(returning: result)
    heldPreparation = nil
  }

  func holdNextSideAdvisory() {
    holdSideAdvisory = true
  }

  func waitForSideAdvisory(_ count: Int) async throws -> SideAdvisory {
    if sideAdvisories.count >= count { return sideAdvisories[count - 1] }
    let id = UUID()
    return try await withCheckedThrowingContinuation { continuation in
      sideAdvisoryWaiters.append(.init(id: id, count: count, continuation: continuation))
      Task { [weak self] in
        do {
          try await ContinuousClock().sleep(for: .seconds(2))
        } catch {
          return
        }
        await self?.timeOutSideAdvisoryWaiter(id: id)
      }
    }
  }

  func releaseHeldSideAdvisory(
    _ result: Result<Void, PlotterBoundaryLowerPortFailure> = .success(())
  ) {
    heldSideAdvisory?.resume(returning: result)
    heldSideAdvisory = nil
  }

  func preparePenUp(
    environment: PlotterEnvironment,
    profile _: PenActuationProfile
  ) async -> Result<Void, PlotterBoundaryLowerPortFailure> {
    preparationCount += 1
    events.append(.preparationBegan(environment))
    resumePreparationWaiters()
    let result: Result<Void, PlotterBoundaryLowerPortFailure>
    if let nextPreparation {
      self.nextPreparation = nil
      result = nextPreparation
    } else if holdPreparation {
      holdPreparation = false
      result = await withCheckedContinuation { heldPreparation = $0 }
    } else {
      result = .success(())
    }
    events.append(.preparationEnded(environment))
    return result
  }

  func prepareSideAdvisory(
    environment: PlotterEnvironment,
    direction: PlotterBoundaryDirection
  ) async -> Result<Void, PlotterBoundaryLowerPortFailure> {
    let advisory = SideAdvisory(environment: environment, direction: direction)
    sideAdvisories.append(advisory)
    let ready = sideAdvisoryWaiters.filter { sideAdvisories.count >= $0.count }
    sideAdvisoryWaiters.removeAll { sideAdvisories.count >= $0.count }
    ready.forEach { waiter in
      waiter.continuation.resume(returning: sideAdvisories[waiter.count - 1])
    }
    guard holdSideAdvisory else { return .success(()) }
    holdSideAdvisory = false
    return await withCheckedContinuation { heldSideAdvisory = $0 }
  }

  private func timeOutSideAdvisoryWaiter(id: UUID) {
    guard let index = sideAdvisoryWaiters.firstIndex(where: { $0.id == id }) else { return }
    let waiter = sideAdvisoryWaiters.remove(at: index)
    waiter.continuation.resume(throwing: WaitError.timedOutWaitingForSideAdvisory)
  }

  func admitSide(
    environment: PlotterEnvironment,
    direction: PlotterBoundaryDirection
  ) -> PlotterBoundaryLowerAdmission {
    if let nextAdmission {
      self.nextAdmission = nil
      if case .admitted = nextAdmission {
        preconditionFailure("Tests must let the probe mint admitted handles.")
      }
      let placeholder = PlotterBoundaryLowerHandle(
        id: UUID(),
        environment: environment,
        lowerOwnerID: UUID(),
        cancellationCapabilityID: UUID()
      )
      let admission = SideAdmission(
        environment: environment,
        direction: direction,
        handle: placeholder
      )
      sideAdmissions.append(admission)
      resumeSideWaiters()
      return nextAdmission
    }
    let handle = PlotterBoundaryLowerHandle(
      id: UUID(),
      environment: environment,
      lowerOwnerID: UUID(),
      cancellationCapabilityID: UUID()
    )
    sideAdmissions.append(.init(environment: environment, direction: direction, handle: handle))
    events.append(.sideAdmitted(environment))
    resumeSideWaiters()
    return .admitted(handle)
  }

  func admitCenterTravel(
    environment: PlotterEnvironment,
    delta: Vector2<MachineSpace>
  ) -> PlotterBoundaryLowerAdmission {
    let handle = PlotterBoundaryLowerHandle(
      id: UUID(),
      environment: environment,
      lowerOwnerID: UUID(),
      cancellationCapabilityID: UUID()
    )
    centerAdmissions.append(.init(environment: environment, delta: delta, handle: handle))
    events.append(.centerAdmitted(environment))
    resumeCenterWaiters()
    return .admitted(handle)
  }

  func waitForTerminal(_ handle: PlotterBoundaryLowerHandle) async
    -> PlotterBoundaryLowerTerminal
  {
    if let terminal = queuedTerminals.removeValue(forKey: handle.id) { return terminal }
    return await withCheckedContinuation { terminalContinuations[handle.id] = $0 }
  }

  func requestCancellation(
    _ intent: PlotterBoundaryCancellationIntent,
    handle: PlotterBoundaryLowerHandle
  ) {
    cancellations.append(.init(intent: intent, handle: handle))
    events.append(.cancellationRequested(handle.environment))
    resumeCancellationWaiters()
  }

  func settle(_ admission: SideAdmission, with terminal: PlotterBoundaryLowerTerminal) {
    settle(admission.handle, with: terminal)
  }

  func settle(_ handle: PlotterBoundaryLowerHandle, with terminal: PlotterBoundaryLowerTerminal) {
    if let continuation = terminalContinuations.removeValue(forKey: handle.id) {
      continuation.resume(returning: terminal)
    } else {
      queuedTerminals[handle.id] = terminal
    }
  }

  func waitForSideAdmission(_ count: Int) async -> SideAdmission {
    if sideAdmissions.count >= count { return sideAdmissions[count - 1] }
    return await withCheckedContinuation { sideWaiters.append((count, $0)) }
  }

  func waitForCenterAdmission(_ count: Int) async -> CenterAdmission {
    if centerAdmissions.count >= count { return centerAdmissions[count - 1] }
    return await withCheckedContinuation { centerWaiters.append((count, $0)) }
  }

  func waitForCancellation(_ count: Int) async -> Cancellation {
    if cancellations.count >= count { return cancellations[count - 1] }
    return await withCheckedContinuation { cancellationWaiters.append((count, $0)) }
  }

  private func resumeSideWaiters() {
    let ready = sideWaiters.filter { sideAdmissions.count >= $0.0 }
    sideWaiters.removeAll { sideAdmissions.count >= $0.0 }
    ready.forEach { $0.1.resume(returning: sideAdmissions[$0.0 - 1]) }
  }

  private func resumePreparationWaiters() {
    let calls = events.compactMap { event -> PlotterEnvironment? in
      if case .preparationBegan(let environment) = event { return environment }
      return nil
    }
    let ready = preparationWaiters.filter { calls.count >= $0.0 }
    preparationWaiters.removeAll { calls.count >= $0.0 }
    ready.forEach { $0.1.resume(returning: calls[$0.0 - 1]) }
  }

  private func resumeCenterWaiters() {
    let ready = centerWaiters.filter { centerAdmissions.count >= $0.0 }
    centerWaiters.removeAll { centerAdmissions.count >= $0.0 }
    ready.forEach { $0.1.resume(returning: centerAdmissions[$0.0 - 1]) }
  }

  private func resumeCancellationWaiters() {
    let ready = cancellationWaiters.filter { cancellations.count >= $0.0 }
    cancellationWaiters.removeAll { cancellations.count >= $0.0 }
    ready.forEach { $0.1.resume(returning: cancellations[$0.0 - 1]) }
  }
}

private enum BoundaryEpisodePersistenceError: Error {
  case injected
}

private final class BoundaryRecoveryCheckpointStore:
  PlotterApplicationStatePersistencePort, @unchecked Sendable
{
  private let lock = NSLock()
  private var stored: AcceptedLearningPathCheckpoint?
  private var shouldFailNextSave = false

  init(checkpoint: AcceptedLearningPathCheckpoint) throws {
    stored = checkpoint
  }

  var checkpoint: AcceptedLearningPathCheckpoint? {
    lock.lock()
    defer { lock.unlock() }
    return stored
  }

  func failNextSave() {
    lock.lock()
    shouldFailNextSave = true
    lock.unlock()
  }

  func load() -> AcceptedLearningPathCheckpointLoadResult {
    lock.lock()
    defer { lock.unlock() }
    return stored.map(AcceptedLearningPathCheckpointLoadResult.loaded) ?? .absent
  }

  func save(_ checkpoint: AcceptedLearningPathCheckpoint) throws {
    lock.lock()
    defer { lock.unlock() }
    if shouldFailNextSave {
      shouldFailNextSave = false
      throw BoundaryEpisodePersistenceError.injected
    }
    stored = checkpoint
  }

  func clear() {
    lock.lock()
    stored = nil
    lock.unlock()
  }

  func loadAcceptedLearningPathCheckpoint() -> AcceptedLearningPathCheckpointLoadResult {
    load()
  }

  func saveAcceptedLearningPathCheckpoint(
    _ checkpoint: AcceptedLearningPathCheckpoint
  ) throws {
    try save(checkpoint)
  }

  func clearAcceptedLearningPathCheckpoint() throws {
    clear()
  }

  func persistPaperRevisionContext(_ context: PaperRevisionContext) throws {}
}

private actor BoundaryEpisodePersistencePort: PlotterBoundaryPersistencePort {
  private var shouldFailNext = false
  private(set) var candidates: [PlotterBoundaryPersistenceCandidate] = []
  var candidateCount: Int { candidates.count }

  func failNextSave() { shouldFailNext = true }

  func persistBoundaryCandidate(_ candidate: PlotterBoundaryPersistenceCandidate) throws {
    candidates.append(candidate)
    if shouldFailNext {
      shouldFailNext = false
      throw BoundaryEpisodePersistenceError.injected
    }
  }
}

@MainActor
private final class BoundarySuspendingProjectionSink: PlotterBoundaryProjectionSink {
  private struct Waiter {
    let environment: PlotterEnvironment
    let predicate: @MainActor (PlotterBoundaryRuntimeSnapshot) -> Bool
    let continuation: CheckedContinuation<PlotterBoundaryRuntimeSnapshot, Never>
  }

  private var latestSnapshots: [PlotterEnvironment: PlotterBoundaryRuntimeSnapshot] = [:]
  private var heldSnapshot: PlotterBoundaryRuntimeSnapshot?
  private var heldWaiters: [CheckedContinuation<PlotterBoundaryRuntimeSnapshot, Never>] = []
  private var snapshotWaiters: [Waiter] = []
  private var heldContinuation: CheckedContinuation<Void, Never>?
  private var shouldHoldReservingPublication = true
  private(set) var heldPublicationCount = 0

  func publishBoundarySnapshot(_ snapshot: PlotterBoundaryRuntimeSnapshot) async {
    let environment = snapshot.projection.reference.environment
    latestSnapshots[environment] = snapshot
    let ready = snapshotWaiters.filter {
      $0.environment == environment && $0.predicate(snapshot)
    }
    snapshotWaiters.removeAll {
      $0.environment == environment && $0.predicate(snapshot)
    }
    ready.forEach { $0.continuation.resume(returning: snapshot) }

    guard shouldHoldReservingPublication,
      snapshot.projection.reference.environment == .live,
      case .reserving = snapshot.projection.phase
    else { return }
    shouldHoldReservingPublication = false
    heldPublicationCount += 1
    heldSnapshot = snapshot
    let waiters = heldWaiters
    heldWaiters.removeAll()
    waiters.forEach { $0.resume(returning: snapshot) }
    await withCheckedContinuation { heldContinuation = $0 }
  }

  func waitUntilHeld() async -> PlotterBoundaryRuntimeSnapshot {
    if let heldSnapshot { return heldSnapshot }
    return await withCheckedContinuation { heldWaiters.append($0) }
  }

  func waitForCancellation(
    _ intent: PlotterBoundaryCancellationIntent
  ) async -> PlotterBoundaryRuntimeSnapshot {
    await wait(environment: .live) { snapshot in
      if case .cancelling(intent) = snapshot.projection.phase { return true }
      return false
    }
  }

  func waitForSettledTerminalCount(
    _ count: Int,
    environment: PlotterEnvironment
  ) async -> PlotterBoundaryRuntimeSnapshot {
    await wait(environment: environment) { snapshot in
      snapshot.attemptTerminals.count >= count
        && snapshot.projection.reference.operationID == nil
    }
  }

  func releaseHeldPublication() {
    heldContinuation?.resume()
    heldContinuation = nil
  }

  private func wait(
    environment: PlotterEnvironment,
    predicate: @escaping @MainActor (PlotterBoundaryRuntimeSnapshot) -> Bool
  ) async -> PlotterBoundaryRuntimeSnapshot {
    if let latestSnapshot = latestSnapshots[environment], predicate(latestSnapshot) {
      return latestSnapshot
    }
    return await withCheckedContinuation {
      snapshotWaiters.append(
        .init(environment: environment, predicate: predicate, continuation: $0)
      )
    }
  }
}

@MainActor
private final class BoundaryEpisodeProjectionRecorder: PlotterBoundaryProjectionSink {
  private struct Waiter {
    let environment: PlotterEnvironment
    let predicate: @MainActor (PlotterBoundaryRuntimeSnapshot) -> Bool
    let continuation: CheckedContinuation<PlotterBoundaryRuntimeSnapshot, Never>
  }

  private var snapshots: [PlotterEnvironment: PlotterBoundaryRuntimeSnapshot] = [:]
  private var waiters: [Waiter] = []

  func publishBoundarySnapshot(_ snapshot: PlotterBoundaryRuntimeSnapshot) {
    let environment = snapshot.projection.reference.environment
    snapshots[environment] = snapshot
    let ready = waiters.filter {
      $0.environment == environment && $0.predicate(snapshot)
    }
    waiters.removeAll {
      $0.environment == environment && $0.predicate(snapshot)
    }
    ready.forEach { $0.continuation.resume(returning: snapshot) }
  }

  func waitForTerminalCount(
    _ count: Int,
    environment: PlotterEnvironment
  ) async -> PlotterBoundaryRuntimeSnapshot {
    await wait(environment: environment) { $0.attemptTerminals.count >= count }
  }

  func waitForAcceptedCount(
    _ count: Int,
    environment: PlotterEnvironment
  ) async -> PlotterBoundaryRuntimeSnapshot {
    await wait(environment: environment) { snapshot in
      snapshot.acceptedEvidence.count >= count
        && snapshot.projection.reference.operationID == nil
    }
  }

  func waitForCancellation(
    _ intent: PlotterBoundaryCancellationIntent,
    environment: PlotterEnvironment
  ) async -> PlotterBoundaryRuntimeSnapshot {
    await wait(environment: environment) { snapshot in
      if case .cancelling(intent) = snapshot.projection.phase { return true }
      return false
    }
  }

  private func wait(
    environment: PlotterEnvironment,
    predicate: @escaping @MainActor (PlotterBoundaryRuntimeSnapshot) -> Bool
  ) async -> PlotterBoundaryRuntimeSnapshot {
    if let snapshot = snapshots[environment], predicate(snapshot) { return snapshot }
    return await withCheckedContinuation {
      waiters.append(.init(environment: environment, predicate: predicate, continuation: $0))
    }
  }
}
