import EpisodeCore
import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import Testing

@Suite("Plotter causal episode environment")
struct PlotterCausalEpisodeEnvironmentTests {
  @Test("shared grammar preserves SIMULATED provenance and separated causal truth")
  func sharedGrammarAndTruthLayers() async throws {
    let fixture = try await enabledEnvironment()
    let before = await fixture.adapter.truthSnapshot()
    #expect(before.controllerCommand == nil)
    #expect(before.plantPosition == .zero)
    #expect(before.penPose == .up)
    #expect(before.ink.isEmpty)
    #expect(before.latestCausalFrame == nil)
    #expect(before.visionTruth == .notComputedBySimulator)
    #expect(before.visionAuthority == EpisodeAuthorityID(rawValue: "VisionWorker"))
    #expect(before.evidenceClass == .simulatedCausal)
    #expect(before.physicalEvidenceClaimed == false)
    #expect(before.evidenceNotice == .notPhysicalEvidence)

    let request = try jog(.positiveX, distanceMM: 5)
    let operation = try admitted(
      await fixture.adapter.admitManualJog(manualEffectRequest(.jog(request)))
    )
    #expect(operation.attribution.intent == .manualMotion(.jog(request)))
    #expect(operation.attribution.effect?.context.environment == .simulated)

    let admittedTruth = await fixture.adapter.truthSnapshot()
    #expect(admittedTruth.controllerCommand?.id == operation.id)
    #expect(admittedTruth.plantPosition == .zero)
    #expect(admittedTruth.penPose == .up)
    #expect(admittedTruth.ink.isEmpty)

    let outcome = await fixture.adapter.executeNaturally(operation)
    #expect(outcome.disposition == .naturallyCompleted)
    #expect(outcome.finalMPos == (try SimulatedLearningMPos(xMM: 5, yMM: 0)))
    #expect(outcome.effectResult?.context.environment == .simulated)
    #expect(outcome.observation.context.environment == .simulated)
    #expect(outcome.observation.context.source == .causalSimulator)
    #expect(outcome.truth.controllerCommand == nil)
    #expect(outcome.truth.plantPosition == outcome.finalMPos)
    #expect(outcome.truth.evidenceClass == .simulatedCausal)
    #expect(outcome.truth.physicalEvidenceClaimed == false)
  }

  @Test("manual Stop settles and wakes the exact adapter-owned operation")
  func manualStopWaitsForOriginalOwner() async throws {
    let fixture = try await enabledEnvironment()
    let operation = try admitted(
      await fixture.adapter.admitManualJog(
        manualEffectRequest(.jog(try jog(.positiveX, distanceMM: 5)))
      )
    )
    let waiter = Task { await fixture.adapter.waitForOutcome(of: operation) }
    let stopped = await fixture.adapter.request(.stop, for: operation)
    let waited = await waiter.value

    #expect(stopped == waited)
    #expect(stopped.operation.id == operation.id)
    #expect(stopped.disposition == .stopped)
    #expect(stopped.finalMPos == .zero)
    #expect(stopped.evidenceNotice == .notPhysicalEvidence)
    #expect(stopped.effectResult?.context.environment == .simulated)
    guard case let .cancelledAfterSettlement(_, settlement)? = stopped.effectResult else {
      Issue.record("Expected typed cancellation settlement")
      return
    }
    #expect(settlement.possibleInk == false)
    #expect((await fixture.adapter.truthSnapshot()).controllerCommand == nil)
  }

  @Test("Boundary Stop, cancel, and shutdown retain distinct first-winning dispositions")
  func boundaryStopCancelAndShutdown() async throws {
    let fixture = try await enabledEnvironment()
    let owner = EpisodeAuthorityID(rawValue: "test.boundaryStopCancelShutdown")
    let stopped = try retained(
      await fixture.adapter.admitRetainedWorkflowBoundary(
        direction: .positiveX,
        finiteSegmentLengthMM: 10,
        owner: owner
      ),
      owner: owner
    )
    let stoppedOutcome = await fixture.adapter.request(.stop, for: stopped)
    #expect(stoppedOutcome.disposition == .stopped)
    #expect(stoppedOutcome.effectResult == nil)
    #expect(await fixture.adapter.request(.cancel, for: stopped) == stoppedOutcome)

    let cancelled = try retained(
      await fixture.adapter.admitRetainedWorkflowBoundary(
        direction: .negativeY,
        finiteSegmentLengthMM: 4,
        owner: owner
      ),
      owner: owner
    )
    #expect(cancelled.id != stopped.id)
    let cancelledOutcome = await fixture.adapter.request(.cancel, for: cancelled)
    #expect(cancelledOutcome.disposition == .cancelled)
    #expect(cancelledOutcome.effectResult == nil)
    #expect(await fixture.adapter.request(.stop, for: cancelled) == cancelledOutcome)

    let shutdown = try retained(
      await fixture.adapter.admitRetainedWorkflowBoundary(
        direction: .positiveY,
        finiteSegmentLengthMM: 3,
        owner: owner
      ),
      owner: owner
    )
    let shutdownOutcome = await fixture.adapter.request(.shutdown, for: shutdown)
    #expect(shutdownOutcome.disposition == .shutdown)
    #expect(shutdownOutcome.effectResult == nil)
    #expect(await fixture.adapter.request(.cancel, for: shutdown) == shutdownOutcome)
  }

  @Test("a settled capability cannot stop its active successor")
  func staleStopCannotSettleSuccessor() async throws {
    let fixture = try await enabledEnvironment()
    let first = try admitted(
      await fixture.adapter.admitManualJog(
        manualEffectRequest(.jog(try jog(.positiveY, distanceMM: 2)))
      )
    )
    let firstStop = await fixture.adapter.request(.stop, for: first)
    #expect(firstStop.disposition == .stopped)

    let second = try admitted(
      await fixture.adapter.admitManualJog(
        manualEffectRequest(.jog(try jog(.positiveX, distanceMM: 1)))
      )
    )
    let stale = await fixture.adapter.request(.stop, for: first)
    #expect(stale == firstStop)
    #expect((await fixture.adapter.truthSnapshot()).controllerCommand?.id == second.id)
    #expect(await fixture.adapter.request(.stop, for: second).operation.id == second.id)
  }

  @Test("successor waits for cached terminal publication and cannot contaminate predecessor truth")
  func successorWaitsForAtomicTerminalPublication() async throws {
    let runtime = SimulatedLearningRuntime()
    _ = try accepted(await runtime.connect())
    _ = try accepted(await runtime.enableMotion())
    let gate = PlotterCausalSimulatorTerminalPublicationGate()
    let adapter = PlotterCausalSimulatorEffectAdapter(
      runtime: runtime,
      pacing: SimulatedLearningInteractivePacing(stepDelay: .zero),
      terminalPublicationGate: gate
    )
    let predecessorOwner = EpisodeAuthorityID(rawValue: "test.publicationPredecessor")
    let lowered = await adapter.executeRetainedWorkflowPen(.down, owner: predecessorOwner)
    #expect(lowered.effectResult == nil)
    #expect(lowered.refusal == nil)
    let predecessor = try retained(
      await adapter.admitRetainedWorkflowDrawing(
        delta: try SimulatedLearningMotionVector(dxMM: 3, dyMM: 0),
        owner: predecessorOwner
      ),
      owner: predecessorOwner
    )
    let predecessorExecution = Task { await adapter.executeNaturally(predecessor) }

    let heldPredecessorID = await gate.waitUntilHeld()
    #expect(heldPredecessorID == predecessor.id)
    let successorOwner = EpisodeAuthorityID(rawValue: "test.publicationSuccessor")
    let heldTruthBeforeSuccessors = await adapter.truthSnapshot()
    let lowerBeforePenSuccessor = await runtime.snapshot()
    #expect(heldTruthBeforeSuccessors.penPose == .down)
    #expect(lowerBeforePenSuccessor.penPose == .down)

    let prematurePenSuccessor = await adapter.executeRetainedWorkflowPen(
      .up,
      owner: successorOwner
    )
    #expect(prematurePenSuccessor.refusal == .operationAlreadyActive(predecessor.id))
    #expect(prematurePenSuccessor.effectResult == nil)
    #expect(prematurePenSuccessor.truth == heldTruthBeforeSuccessors)
    #expect(prematurePenSuccessor.truth.penPose == .down)
    #expect(await runtime.snapshot() == lowerBeforePenSuccessor)
    #expect(await adapter.truthSnapshot() == heldTruthBeforeSuccessors)

    let prematureSuccessor = await adapter.admitRetainedWorkflowDrawing(
      delta: try SimulatedLearningMotionVector(dxMM: 2, dyMM: 1),
      owner: successorOwner
    )
    guard case let .refused(refusal) = prematureSuccessor else {
      await gate.release(operationID: heldPredecessorID)
      _ = await predecessorExecution.value
      Issue.record("Expected predecessor reservation through terminal publication")
      return
    }
    #expect(refusal.refusal == .operationAlreadyActive(predecessor.id))
    #expect(refusal.effectResult == nil)

    await gate.release(operationID: heldPredecessorID)
    let predecessorOutcome = await predecessorExecution.value
    #expect(predecessorOutcome.effectResult == nil)
    #expect(predecessorOutcome.truth == heldTruthBeforeSuccessors)
    #expect(predecessorOutcome.truth.penPose == .down)
    #expect(predecessorOutcome.truth.ink.count == 1)
    let predecessorFrame = try #require(predecessorOutcome.truth.latestCausalFrame)
    #expect(predecessorFrame.controllerPosition == predecessorOutcome.finalMPos)

    let successor = try retained(
      await adapter.admitRetainedWorkflowDrawing(
        delta: try SimulatedLearningMotionVector(dxMM: 2, dyMM: 1),
        owner: successorOwner
      ),
      owner: successorOwner
    )
    let successorExecution = Task { await adapter.executeNaturally(successor) }
    let heldSuccessorID = await gate.waitUntilHeld()
    #expect(heldSuccessorID == successor.id)
    await gate.release(operationID: heldSuccessorID)
    let successorOutcome = await successorExecution.value
    #expect(successorOutcome.effectResult == nil)
    #expect(successorOutcome.truth.ink.count == 2)
    #expect(successorOutcome.truth.latestCausalFrame?.displayedFrame.frame.id
      != predecessorFrame.displayedFrame.frame.id)

    let cachedPredecessor = await adapter.waitForOutcome(of: predecessor)
    #expect(cachedPredecessor == predecessorOutcome)
    #expect(cachedPredecessor.truth.ink.count == 1)
    #expect(cachedPredecessor.truth.latestCausalFrame == predecessorFrame)
    #expect(cachedPredecessor.truth.plantPosition
      == (try SimulatedLearningMPos(xMM: 3, yMM: 0)))
    #expect(successorOutcome.truth.plantPosition
      == (try SimulatedLearningMPos(xMM: 5, yMM: 1)))
  }

  @Test("one current simulator operation rejects a second attributed owner")
  func oneCurrentOperation() async throws {
    let fixture = try await enabledEnvironment()
    let manual = try admitted(
      await fixture.adapter.admitManualJog(
        manualEffectRequest(.jog(try jog(.positiveX, distanceMM: 1)))
      )
    )
    let owner = EpisodeAuthorityID(rawValue: "test.occupiedBoundary")
    let second = await fixture.adapter.admitRetainedWorkflowBoundary(
      direction: .positiveY,
      finiteSegmentLengthMM: 2,
      owner: owner
    )
    guard case let .refused(refusal) = second else {
      Issue.record("Expected the occupied causal operation to refuse a successor")
      return
    }
    #expect(refusal.refusal == .operationAlreadyActive(manual.id))
    #expect(refusal.truth.controllerCommand?.id == manual.id)
    #expect(refusal.effectResult == nil)
    _ = await fixture.adapter.request(.cancel, for: manual)
  }

  @Test("retained drawing naturally completes only with simulated Pen Down")
  func drawingCompletion() async throws {
    let fixture = try await enabledEnvironment()
    let delta = try SimulatedLearningMotionVector(dxMM: 3, dyMM: -2)
    let owner = EpisodeAuthorityID(rawValue: "test.retainedDrawingCompletion")
    let refused = await fixture.adapter.admitRetainedWorkflowDrawing(
      delta: delta,
      owner: owner
    )
    guard case let .refused(refusal) = refused else {
      Issue.record("Expected Pen-Up drawing refusal")
      return
    }
    #expect(refusal.refusal == .penMustBeDown)
    #expect(refusal.effectResult == nil)

    let lowered = await fixture.adapter.executeRetainedWorkflowPen(.down, owner: owner)
    #expect(lowered.effectResult == nil)
    #expect(lowered.refusal == nil)
    let drawing = try retained(
      await fixture.adapter.admitRetainedWorkflowDrawing(delta: delta, owner: owner),
      owner: owner
    )
    let outcome = await fixture.adapter.executeNaturally(drawing)
    #expect(outcome.operation.id == drawing.id)
    #expect(outcome.disposition == .naturallyCompleted)
    #expect(outcome.finalMPos == (try SimulatedLearningMPos(xMM: 3, yMM: -2)))
    #expect(outcome.truth.ink.count == 1)
    #expect(outcome.effectResult == nil)
  }

  @Test("cooperative finite travel and drawing let exact Stop win before mutation")
  func cooperativeFiniteTravelCanStop() async throws {
    let pacing = ControlledCausalExecutionPacing()
    let fixture = try await enabledEnvironment(pacing: pacing)
    let travelOwner = EpisodeAuthorityID(rawValue: "test.supervisedTravel")
    let travel = try retained(
      await fixture.adapter.admitRetainedWorkflowTravel(
        delta: try SimulatedLearningMotionVector(dxMM: 10, dyMM: -5),
        owner: travelOwner
      ),
      owner: travelOwner
    )
    let execution = Task { await fixture.adapter.executeNaturally(travel) }

    await pacing.waitUntilSuspended(1)
    let stopped = await fixture.adapter.request(.stop, for: travel)
    await pacing.resumeNext()
    #expect(await execution.value == stopped)
    #expect(stopped.disposition == .stopped)
    #expect(stopped.finalMPos == .zero)
    #expect(stopped.effectResult == nil)
    #expect((await fixture.adapter.truthSnapshot()).plantPosition == .zero)

    let drawingOwner = EpisodeAuthorityID(rawValue: "test.retainedDrawingStop")
    let lowered = await fixture.adapter.executeRetainedWorkflowPen(.down, owner: drawingOwner)
    #expect(lowered.effectResult == nil)
    #expect(lowered.refusal == nil)
    let drawing = try retained(
      await fixture.adapter.admitRetainedWorkflowDrawing(
        delta: try SimulatedLearningMotionVector(dxMM: 3, dyMM: 0),
        owner: drawingOwner
      ),
      owner: drawingOwner
    )
    let drawingExecution = Task { await fixture.adapter.executeNaturally(drawing) }
    await pacing.waitUntilSuspended(2)
    let drawingStop = await fixture.adapter.request(.stop, for: drawing)
    await pacing.resumeNext()

    #expect(await drawingExecution.value == drawingStop)
    #expect(drawingStop.disposition == .stopped)
    #expect(drawingStop.effectResult == nil)
    #expect(drawingStop.truth.ink.isEmpty)
    #expect(drawingStop.truth.plantPosition == .zero)
    #expect(drawingStop.truth.penPose == .up)
  }

  @Test("retained workflow travel completes causally and publishes its frame")
  func cooperativeTravelNaturalCompletion() async throws {
    let fixture = try await enabledEnvironment()
    let owner = EpisodeAuthorityID(rawValue: "test.retainedTravel")
    let operation = try retained(
      await fixture.adapter.admitRetainedWorkflowTravel(
        delta: try SimulatedLearningMotionVector(dxMM: 4, dyMM: -3),
        owner: owner
      ),
      owner: owner
    )
    let outcome = await fixture.adapter.executeNaturally(operation)
    #expect(outcome.disposition == .naturallyCompleted)
    #expect(outcome.finalMPos == (try SimulatedLearningMPos(xMM: 4, yMM: -3)))
    let frame = try #require(outcome.truth.latestCausalFrame)
    #expect(frame.controllerPosition == outcome.finalMPos)
    #expect(frame.displayedFrame.frame.sequence == 1)
    #expect(outcome.truth.cameraFrameSequence == 2)
    #expect(outcome.completedBoundarySegmentCount == 0)
    #expect(outcome.effectResult == nil)
  }

  @Test("Boundary segments retain one logical owner and never manufacture success")
  func boundaryNeverNaturallySucceeds() async throws {
    let pacing = ControlledCausalExecutionPacing()
    let fixture = try await enabledEnvironment(pacing: pacing)
    let owner = EpisodeAuthorityID(rawValue: "test.boundaryOwner")
    let boundary = try retained(
      await fixture.adapter.admitRetainedWorkflowBoundary(
        direction: .positiveX,
        finiteSegmentLengthMM: 10,
        owner: owner
      ),
      owner: owner
    )
    let execution = Task { await fixture.adapter.executeBoundaryCooperatively(boundary) }

    await pacing.waitUntilSuspended(1)
    await pacing.resumeNext()
    await pacing.waitUntilSuspended(2)
    await pacing.resumeNext()
    await pacing.waitUntilSuspended(3)
    await pacing.resumeNext()
    await pacing.waitUntilSuspended(4)

    let activeTruth = await fixture.adapter.truthSnapshot()
    #expect(activeTruth.controllerCommand?.id == boundary.id)
    #expect(activeTruth.plantPosition == (try SimulatedLearningMPos(xMM: 20, yMM: 0)))
    let stopped = await fixture.adapter.request(.stop, for: boundary)
    await pacing.resumeNext()
    #expect(await execution.value == stopped)
    #expect(stopped.disposition == .stopped)
    #expect(stopped.completedBoundarySegmentCount == 2)
    #expect(stopped.operation.id == boundary.id)
    #expect(stopped.effectResult == nil)
  }

  @Test("Paper Replaced clears ink without rotating camera identity")
  func paperReplacementResetsScene() async throws {
    let fixture = try await enabledEnvironment()
    let owner = EpisodeAuthorityID(rawValue: "test.paperReplacement")
    let lowered = await fixture.adapter.executeRetainedWorkflowPen(.down, owner: owner)
    #expect(lowered.effectResult == nil)
    #expect(lowered.refusal == nil)
    let drawing = try retained(
      await fixture.adapter.admitRetainedWorkflowDrawing(
        delta: try SimulatedLearningMotionVector(dxMM: 4, dyMM: 0),
        owner: owner
      ),
      owner: owner
    )
    #expect((await fixture.adapter.executeNaturally(drawing)).effectResult == nil)
    let raised = await fixture.adapter.executeRetainedWorkflowPen(.up, owner: owner)
    #expect(raised.effectResult == nil)
    #expect(raised.refusal == nil)
    let before = await fixture.adapter.truthSnapshot()
    #expect(before.ink.count == 1)

    let replaced = try accepted(await fixture.runtime.recordPaperReplaced())
    let after = await fixture.adapter.truthSnapshot()
    #expect(after.ink.isEmpty)
    #expect(after.paperRevision == replaced.toolPaperRevision)
    #expect(after.paperRevision != before.paperRevision)
    #expect(after.cameraConfigurationID == before.cameraConfigurationID)

    let active = try admitted(
      await fixture.adapter.admitManualJog(
        manualEffectRequest(.jog(try jog(.positiveX, distanceMM: 1)))
      )
    )
    #expect(
      refusal(await fixture.runtime.recordPaperReplaced())
        == .operationAlreadyActive(active.id)
    )
    _ = await fixture.adapter.request(.cancel, for: active)
  }

  @Test("causal scene keeps armature, truth, and ink useful and padded")
  func usefulPaddedSceneFootprint() async throws {
    for direction in BoundaryDirection.allCases {
      let fixture = try await enabledEnvironment()
      let owner = EpisodeAuthorityID(rawValue: "test.sceneBoundary.\(direction)")
      let operation = try retained(
        await fixture.adapter.admitRetainedWorkflowBoundary(
          direction: direction,
          finiteSegmentLengthMM: 1_000,
          owner: owner
        ),
        owner: owner
      )
      let execution = Task { await fixture.adapter.executeBoundaryCooperatively(operation) }
      while await fixture.runtime.latestPublishedCausalFrame() == nil { await Task.yield() }
      #expect((await fixture.adapter.request(.stop, for: operation)).effectResult == nil)
      #expect((await execution.value).effectResult == nil)
      let scene = try accepted(await fixture.runtime.captureSceneFrame())
      #expect(scene.armatureBounds.minX >= scene.worldToCameraTransform.paddingPixels)
      #expect(scene.armatureBounds.minY >= scene.worldToCameraTransform.paddingPixels)
      #expect(
        scene.armatureBounds.maxX
          <= Double(scene.worldToCameraTransform.frameWidth)
            - scene.worldToCameraTransform.paddingPixels
      )
      #expect(
        scene.armatureBounds.maxY
          <= Double(scene.worldToCameraTransform.frameHeight)
            - scene.worldToCameraTransform.paddingPixels
      )
    }

    let fixture = try await enabledEnvironment()
    let drawingOwner = EpisodeAuthorityID(rawValue: "test.sceneDrawing")
    let lowered = await fixture.adapter.executeRetainedWorkflowPen(.down, owner: drawingOwner)
    #expect(lowered.effectResult == nil)
    #expect(lowered.refusal == nil)
    let drawing = try retained(
      await fixture.adapter.admitRetainedWorkflowDrawing(
        delta: try SimulatedLearningMotionVector(dxMM: 4, dyMM: 0),
        owner: drawingOwner
      ),
      owner: drawingOwner
    )
    #expect((await fixture.adapter.executeNaturally(drawing)).effectResult == nil)
    let raised = await fixture.adapter.executeRetainedWorkflowPen(.up, owner: drawingOwner)
    #expect(raised.effectResult == nil)
    #expect(raised.refusal == nil)
    let scene = try accepted(await fixture.runtime.captureSceneFrame())
    let ink = scene.annotations.filter { $0.kind == .ink }
    #expect(ink.count == 1)
    let inkPoints = ink.flatMap { annotation -> [Point2<CameraPixelSpace>] in
      guard case .polyline(let line) = annotation.geometry else { return [] }
      return line.points
    }
    #expect(
      inkPoints.allSatisfy {
        $0.x >= scene.worldToCameraTransform.paddingPixels
          && $0.y >= scene.worldToCameraTransform.paddingPixels
          && $0.x <= Double(scene.worldToCameraTransform.frameWidth)
            - scene.worldToCameraTransform.paddingPixels
          && $0.y <= Double(scene.worldToCameraTransform.frameHeight)
            - scene.worldToCameraTransform.paddingPixels
      }
    )
    let projectedLength = (inkPoints.map(\.x).max() ?? 0) - (inkPoints.map(\.x).min() ?? 0)
    #expect(
      abs(projectedLength - 4 * scene.worldToCameraTransform.scalePixelsPerMillimeter) < 1e-8
    )
    let truth = try #require(scene.annotations.first { $0.kind == .truthEnvelope })
    guard case .bounds(let bounds) = truth.geometry else { return }
    #expect(bounds.maxX - bounds.minX > 300)
    #expect(bounds.maxY - bounds.minY > 300)
  }

  @Test("Boundary Stop wins before segment and between segment and frame")
  func cooperativeBoundaryStopRaces() async throws {
    let firstPacing = ControlledCausalExecutionPacing()
    let beforeSegment = try await enabledEnvironment(pacing: firstPacing)
    let firstOwner = EpisodeAuthorityID(rawValue: "test.boundaryStopBeforeSegment")
    let first = try retained(
      await beforeSegment.adapter.admitRetainedWorkflowBoundary(
        direction: .positiveX,
        finiteSegmentLengthMM: 10,
        owner: firstOwner
      ),
      owner: firstOwner
    )
    let firstExecution = Task {
      await beforeSegment.adapter.executeBoundaryCooperatively(first)
    }
    await firstPacing.waitUntilSuspended(1)
    let firstStop = await beforeSegment.adapter.request(.stop, for: first)
    await firstPacing.resumeNext()
    #expect(await firstExecution.value == firstStop)
    #expect(firstStop.effectResult == nil)
    #expect((await beforeSegment.adapter.truthSnapshot()).plantPosition == .zero)
    #expect((await beforeSegment.adapter.truthSnapshot()).cameraFrameSequence == 1)

    let secondPacing = ControlledCausalExecutionPacing()
    let between = try await enabledEnvironment(pacing: secondPacing)
    let secondOwner = EpisodeAuthorityID(rawValue: "test.boundaryStopBeforeFrame")
    let second = try retained(
      await between.adapter.admitRetainedWorkflowBoundary(
        direction: .positiveX,
        finiteSegmentLengthMM: 10,
        owner: secondOwner
      ),
      owner: secondOwner
    )
    let secondExecution = Task {
      await between.adapter.executeBoundaryCooperatively(second)
    }
    await secondPacing.waitUntilSuspended(1)
    await secondPacing.resumeNext()
    await secondPacing.waitUntilSuspended(2)
    let betweenTruth = await between.adapter.truthSnapshot()
    #expect(betweenTruth.plantPosition == (try SimulatedLearningMPos(xMM: 10, yMM: 0)))
    #expect(betweenTruth.cameraFrameSequence == 1)
    let secondStop = await between.adapter.request(.stop, for: second)
    await secondPacing.resumeNext()
    #expect(await secondExecution.value == secondStop)
    #expect(secondStop.effectResult == nil)
    #expect((await between.adapter.truthSnapshot()).cameraFrameSequence == 1)
    #expect(await between.runtime.latestPublishedCausalFrame() == nil)
  }

  @Test("Boundary publishes causal segments then parks at truth for Stop")
  func cooperativeBoundaryAtTruth() async throws {
    let truth = SimulatedLearningBoundaryTruth(
      negativeXMM: -10, positiveXMM: 10,
      negativeYMM: -10, positiveYMM: 10
    )
    let runtime = SimulatedLearningRuntime(boundaryTruth: truth)
    _ = try accepted(await runtime.connect())
    _ = try accepted(await runtime.enableMotion())
    let pacing = ControlledCausalExecutionPacing()
    let adapter = PlotterCausalSimulatorEffectAdapter(runtime: runtime, pacing: pacing)
    let owner = EpisodeAuthorityID(rawValue: "test.boundaryAtTruth")
    let operation = try retained(
      await adapter.admitRetainedWorkflowBoundary(
        direction: .positiveX,
        finiteSegmentLengthMM: 10,
        owner: owner
      ),
      owner: owner
    )
    let execution = Task { await adapter.executeBoundaryCooperatively(operation) }
    await pacing.waitUntilSuspended(1)
    await pacing.resumeNext()
    await pacing.waitUntilSuspended(2)
    await pacing.resumeNext()
    while await runtime.latestPublishedCausalFrame() == nil { await Task.yield() }
    let active = await adapter.truthSnapshot()
    #expect(active.plantPosition == (try SimulatedLearningMPos(xMM: 10, yMM: 0)))
    #expect(active.controllerCommand?.id == operation.id)
    #expect(active.cameraFrameSequence == 2)
    let stopped = await adapter.request(.stop, for: operation)
    #expect(await execution.value == stopped)
    #expect(stopped.disposition == .stopped)
    #expect(stopped.completedBoundarySegmentCount == 1)
    #expect(stopped.truth.cameraFrameSequence == 2)
    #expect(stopped.effectResult == nil)
  }

  @Test("retained Boundary ambiguity is sticky and fabricates no effect result")
  func cooperativeBoundaryAmbiguity() async throws {
    let fixture = try await enabledEnvironment()
    await fixture.runtime.injectFault(.ambiguityBeforeNextBoundarySegment)
    let owner = EpisodeAuthorityID(rawValue: "test.boundaryAmbiguity")
    let operation = try retained(
      await fixture.adapter.admitRetainedWorkflowBoundary(
        direction: .negativeY,
        finiteSegmentLengthMM: 5,
        owner: owner
      ),
      owner: owner
    )
    let outcome = await fixture.adapter.executeBoundaryCooperatively(operation)
    #expect(outcome.disposition == .failed)
    #expect(outcome.finalMPos == .zero)
    #expect(outcome.truth.cameraFrameSequence == 1)
    #expect(outcome.truth.latestCausalFrame == nil)
    #expect(outcome.truth.runtime.stickyAmbiguity?.context == .boundarySegment(.negativeY))
    #expect(outcome.effectResult == nil)
  }
}

private struct CausalEnvironment {
  let runtime: SimulatedLearningRuntime
  let adapter: PlotterCausalSimulatorEffectAdapter
}

private actor ControlledCausalExecutionPacing: SimulatedLearningExecutionPacing {
  private var suspensionCount = 0
  private var suspendedContinuations: [CheckedContinuation<Void, Never>] = []
  private var countWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

  func suspendBetweenSteps() async {
    suspensionCount += 1
    let readyCounts = countWaiters.keys.filter { $0 <= suspensionCount }
    for count in readyCounts {
      let waiters = countWaiters.removeValue(forKey: count) ?? []
      for waiter in waiters { waiter.resume() }
    }
    await withCheckedContinuation { continuation in
      suspendedContinuations.append(continuation)
    }
  }

  func waitUntilSuspended(_ count: Int) async {
    if suspensionCount >= count { return }
    await withCheckedContinuation { continuation in
      countWaiters[count, default: []].append(continuation)
    }
  }

  func resumeNext() {
    precondition(!suspendedContinuations.isEmpty)
    suspendedContinuations.removeFirst().resume()
  }
}

private func enabledEnvironment(
  pacing: any SimulatedLearningExecutionPacing =
    SimulatedLearningInteractivePacing(stepDelay: .zero)
) async throws -> CausalEnvironment {
  let runtime = SimulatedLearningRuntime()
  _ = try accepted(await runtime.connect())
  _ = try accepted(await runtime.enableMotion())
  return CausalEnvironment(
    runtime: runtime,
    adapter: PlotterCausalSimulatorEffectAdapter(runtime: runtime, pacing: pacing)
  )
}

private func admitted(
  _ admission: PlotterCausalSimulatorAdmission
) throws -> PlotterCausalSimulatorOperation {
  switch admission {
  case let .admitted(operation): return operation
  case let .refused(refusal): throw refusal.refusal
  }
}

private func retained(
  _ admission: PlotterCausalSimulatorAdmission,
  owner: EpisodeAuthorityID
) throws -> PlotterCausalSimulatorOperation {
  let operation = try admitted(admission)
  #expect(operation.attribution == .retainedWorkflow(owner: owner))
  #expect(operation.attribution.intent == nil)
  #expect(operation.attribution.effect == nil)
  return operation
}

private func manualEffectRequest(
  _ intent: PlotterManualMotionIntent
) -> PlotterManualMotionEffectRequest {
  PlotterManualMotionEffectRequest(
    context: PlotterEffectContext(
      episodeID: EpisodeID(rawValue: UUID()),
      requestID: IntentRequestID(rawValue: UUID()),
      effectID: EpisodeEffectID(rawValue: UUID()),
      environment: .simulated
    ),
    intent: intent,
    effectRevision: PlotterManualMotionRuntime.effectRevision
  )
}

private func jog(
  _ direction: PlotterJogDirection,
  distanceMM: Double,
  routing: PlotterManualJogRouting = .relativeTravel
) throws -> PlotterJogRequest {
  try PlotterJogRequest(
    direction: direction,
    distanceMM: distanceMM,
    feedMMPerMinute: 500,
    routing: routing
  )
}

private func accepted<Value: Sendable>(
  _ response: SimulatedLearningResponse<Value>
) throws -> Value {
  try response.result.get()
}

private func refusal<Value: Sendable>(
  _ response: SimulatedLearningResponse<Value>
) -> SimulatedLearningRefusal? {
  guard case let .failure(refusal) = response.result else { return nil }
  return refusal
}
