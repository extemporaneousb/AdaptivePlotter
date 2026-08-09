import Foundation
import PlotterModel
import Testing

@testable import PlotterRuntime

@Suite("Simulated Learning Runtime")
struct SimulatedLearningRuntimeTests {
  @Test("connect and Enable Motion are separate simulator admissions")
  func connectAndEnableMotion() async throws {
    let runtime = SimulatedLearningRuntime()

    var snapshot = await runtime.snapshot()
    #expect(snapshot.session == .disconnected)
    #expect(snapshot.motionAuthorization == .disabled)
    #expect(snapshot.penPose == .up)
    #expect(snapshot.mpos == .zero)
    #expect(
      snapshot.evidenceNotice.label
        == "SIMULATED — NOT PHYSICAL EVIDENCE"
    )

    let refusedEnable = await runtime.enableMotion()
    #expect(refusal(refusedEnable) == .sessionDisconnected)
    #expect(refusedEnable.evidenceNotice == .notPhysicalEvidence)
    snapshot = try accepted(await runtime.connect())
    #expect(snapshot.session == .connected)
    #expect(snapshot.motionAuthorization == .disabled)

    snapshot = try accepted(await runtime.enableMotion())
    #expect(snapshot.motionAuthorization == .enabled)
    #expect(
      snapshot.evidenceNotice == .notPhysicalEvidence
    )

    snapshot = try accepted(await runtime.disableMotion())
    #expect(snapshot.motionAuthorization == .disabled)
    snapshot = try accepted(await runtime.disconnect())
    #expect(snapshot.session == .disconnected)
    #expect(snapshot.motionAuthorization == .disabled)
  }

  @Test("manual Stop settles and wakes the original logical owner")
  func manualStopWaitsForOriginalOwner() async throws {
    let runtime = try await enabledRuntime()
    let operation = try accepted(
      await runtime.beginManualJog(
        delta: SimulatedLearningMotionVector(dxMM: 5, dyMM: 0)
      )
    )

    let waiter = Task {
      await runtime.waitForOutcome(of: operation.id)
    }
    let stopOutcome = try accepted(await runtime.stop(operation.id))
    let waitedOutcome = try accepted(await waiter.value)

    #expect(stopOutcome == waitedOutcome)
    #expect(stopOutcome.operation.id == operation.id)
    #expect(stopOutcome.disposition == .stopped)
    #expect(stopOutcome.finalMPos == .zero)
    #expect(stopOutcome.evidenceNotice == .notPhysicalEvidence)
    #expect(await runtime.snapshot().currentOperation == nil)
  }

  @Test("Boundary Stop and Cancel are distinct first-winning dispositions")
  func boundaryStopVersusCancel() async throws {
    let runtime = try await enabledRuntime()
    let stopped = try accepted(
      await runtime.beginBoundary(direction: .positiveX, finiteSegmentLengthMM: 10)
    )
    let stoppedOutcome = try accepted(await runtime.stop(stopped.id))
    #expect(stoppedOutcome.disposition == .stopped)
    #expect(
      refusal(await runtime.cancel(stopped.id))
        == .operationAlreadySettled(stopped.id, .stopped)
    )

    let cancelled = try accepted(
      await runtime.beginBoundary(direction: .negativeY, finiteSegmentLengthMM: 4)
    )
    #expect(cancelled.id != stopped.id)
    let cancelledOutcome = try accepted(await runtime.cancel(cancelled.id))
    #expect(cancelledOutcome.disposition == .cancelled)
    #expect(
      refusal(await runtime.stop(cancelled.id))
        == .operationAlreadySettled(cancelled.id, .cancelled)
    )
  }

  @Test("repeated and stale Stop cannot settle the active operation")
  func repeatedAndStaleStop() async throws {
    let runtime = try await enabledRuntime()
    let operation = try accepted(
      await runtime.beginManualJog(
        delta: SimulatedLearningMotionVector(dxMM: 0, dyMM: 2)
      )
    )
    let staleID = SimulatedLearningOperationID(sequence: operation.id.sequence + 100)

    #expect(
      refusal(await runtime.stop(staleID))
        == .staleOperation(requested: staleID, active: operation.id)
    )
    #expect(await runtime.snapshot().currentOperation?.id == operation.id)

    _ = try accepted(await runtime.stop(operation.id))
    #expect(
      refusal(await runtime.stop(operation.id))
        == .operationAlreadySettled(operation.id, .stopped)
    )
  }

  @Test("one current operation rejects a second owner")
  func oneCurrentOperation() async throws {
    let runtime = try await enabledRuntime()
    let manual = try accepted(
      await runtime.beginManualJog(
        delta: SimulatedLearningMotionVector(dxMM: 1, dyMM: 0)
      )
    )

    #expect(
      refusal(
        await runtime.beginBoundary(
          direction: .positiveY,
          finiteSegmentLengthMM: 2
        )
      ) == .operationAlreadyActive(manual.id)
    )
    _ = try accepted(await runtime.cancel(manual.id))
  }

  @Test("drawing naturally completes only with simulated pen down")
  func drawingCompletion() async throws {
    let runtime = try await enabledRuntime()
    let delta = try SimulatedLearningMotionVector(dxMM: 3, dyMM: -2)

    #expect(
      refusal(await runtime.beginDrawing(delta: delta)) == .penMustBeDown
    )
    _ = try accepted(await runtime.setPenPose(.down))
    let drawing = try accepted(await runtime.beginDrawing(delta: delta))
    let outcome = try accepted(await runtime.completeNaturally(drawing.id))

    #expect(outcome.operation.kind == .drawing(delta))
    #expect(outcome.disposition == .naturallyCompleted)
    #expect(outcome.finalMPos == (try SimulatedLearningMPos(xMM: 3, yMM: -2)))
    #expect(outcome.evidenceNotice.label == SimulatedLearningEvidenceNotice.evidenceLabel)
  }

  @Test("cooperative target Stop after Pen Down preserves only the accepted ink prefix")
  func cooperativeTargetStopPreservesPartialInk() async throws {
    let runtime = try await enabledRuntime()
    let operation = try accepted(await runtime.beginVisibilityTarget())
    let pacing = ControlledSimulatedExecutionPacing()
    let execution = Task {
      await runtime.executeNaturally(operation.id, pacing: pacing)
    }

    // Approach, lower, and the first drawing segment are each admitted only
    // after a separate suspension. The fourth suspension precedes segment 2.
    await pacing.waitUntilSuspended(1)
    await pacing.resumeNext()
    await pacing.waitUntilSuspended(2)
    await pacing.resumeNext()
    await pacing.waitUntilSuspended(3)
    await pacing.resumeNext()
    await pacing.waitUntilSuspended(4)
    #expect(await runtime.snapshot().penPose == .down)
    #expect(await runtime.persistentInk().count == 1)

    let stopped = try accepted(await runtime.stop(operation.id))
    await pacing.resumeNext()
    let executionOutcome = try accepted(await execution.value)

    #expect(executionOutcome == stopped)
    #expect(stopped.disposition == .stopped)
    #expect(stopped.visibilityTargetSceneDisposition == .inkPossible)
    #expect(await runtime.persistentInk().count == 1)
    #expect(await runtime.snapshot().penPose == .up)
  }

  @Test("cooperative finite travel lets Stop win before position changes")
  func cooperativeFiniteTravelCanStop() async throws {
    let runtime = try await enabledRuntime()
    let operation = try accepted(await runtime.beginManualJog(
      delta: SimulatedLearningMotionVector(dxMM: 10, dyMM: -5)
    ))
    let pacing = ControlledSimulatedExecutionPacing()
    let execution = Task {
      await runtime.executeNaturally(operation.id, pacing: pacing)
    }

    await pacing.waitUntilSuspended(1)
    let stopped = try accepted(await runtime.stop(operation.id))
    await pacing.resumeNext()

    #expect(try accepted(await execution.value) == stopped)
    #expect(stopped.disposition == .stopped)
    #expect(stopped.finalMPos == .zero)
    #expect(await runtime.snapshot().mpos == .zero)

    _ = try accepted(await runtime.setPenPose(.down))
    let drawing = try accepted(await runtime.beginDrawing(
      delta: SimulatedLearningMotionVector(dxMM: 3, dyMM: 0)
    ))
    let drawingPacing = ControlledSimulatedExecutionPacing()
    let drawingExecution = Task {
      await runtime.executeNaturally(drawing.id, pacing: drawingPacing)
    }
    await drawingPacing.waitUntilSuspended(1)
    let drawingStop = try accepted(await runtime.stop(drawing.id))
    await drawingPacing.resumeNext()

    #expect(try accepted(await drawingExecution.value) == drawingStop)
    #expect(await runtime.persistentInk().isEmpty)
    #expect(await runtime.snapshot().mpos == .zero)
    #expect(await runtime.snapshot().penPose == .up)
  }

  @Test("Cancel and shutdown are first intent during cooperative target execution")
  func cooperativeTargetCancelAndShutdownWin() async throws {
    for (intent, disposition) in [
      (SimulatedLearningOperationIntent.cancel, SimulatedLearningOperationDisposition.cancelled),
      (.shutdown, .shutdown),
    ] {
      let runtime = try await enabledRuntime()
      let operation = try accepted(await runtime.beginVisibilityTarget())
      let pacing = ControlledSimulatedExecutionPacing()
      let execution = Task {
        await runtime.executeNaturally(operation.id, pacing: pacing)
      }

      await pacing.waitUntilSuspended(1)
      await pacing.resumeNext()
      await pacing.waitUntilSuspended(2)
      await pacing.resumeNext()
      await pacing.waitUntilSuspended(3)
      await pacing.resumeNext()
      await pacing.waitUntilSuspended(4)
      let terminal = try accepted(await runtime.request(intent, for: operation.id))
      await pacing.resumeNext()

      #expect(try accepted(await execution.value) == terminal)
      #expect(terminal.disposition == disposition)
      #expect(terminal.visibilityTargetSceneDisposition == .inkPossible)
      #expect(await runtime.persistentInk().count == 1)
      #expect(await runtime.snapshot().penPose == .up)
      #expect(
        refusal(await runtime.stop(operation.id))
          == .operationAlreadySettled(operation.id, disposition)
      )
    }
  }

  @Test("cooperative target ambiguity emits no segment after the ambiguous phase")
  func cooperativeTargetAmbiguityStopsProgress() async throws {
    let runtime = try await enabledRuntime()
    await runtime.injectFault(.ambiguityAtVisibilityTargetPhase(.drawSegment(1)))
    let operation = try accepted(await runtime.beginVisibilityTarget())

    let outcome = try accepted(await runtime.executeNaturally(
      operation.id,
      pacing: SimulatedLearningImmediatePacing()
    ))

    #expect(outcome.disposition == .failed)
    #expect(outcome.visibilityTargetFailurePhase == .drawSegment(1))
    #expect(outcome.visibilityTargetSceneDisposition == .inkPossible)
    #expect(await runtime.persistentInk().count == 1)
    #expect(await runtime.snapshot().penPose == .down)
  }

  @Test("zero-delay cooperative target completes all eight segments")
  func immediateCooperativeTargetCompletes() async throws {
    let runtime = try await enabledRuntime()
    let operation = try accepted(await runtime.beginVisibilityTarget())

    let outcome = try accepted(await runtime.executeNaturally(
      operation.id,
      pacing: SimulatedLearningImmediatePacing()
    ))

    #expect(outcome.disposition == .naturallyCompleted)
    #expect(outcome.visibilityTargetSceneDisposition == .inkPossible)
    #expect(await runtime.persistentInk().count == 8)
    #expect(await runtime.snapshot().penPose == .up)
  }

  @Test("natural Boundary segment completion continues the same owner without success")
  func boundaryNeverNaturallySucceeds() async throws {
    let runtime = try await enabledRuntime()
    let boundary = try accepted(
      await runtime.beginBoundary(direction: .positiveX, finiteSegmentLengthMM: 10)
    )

    let first = try accepted(
      await runtime.recordBoundarySegmentCompletion(for: boundary.id)
    )
    let second = try accepted(
      await runtime.recordBoundarySegmentCompletion(for: boundary.id)
    )
    #expect(first.operationID == boundary.id)
    #expect(first.completedSegmentCount == 1)
    #expect(second.operationID == boundary.id)
    #expect(second.completedSegmentCount == 2)
    #expect(second.mpos == (try SimulatedLearningMPos(xMM: 20, yMM: 0)))

    #expect(
      refusal(await runtime.completeNaturally(boundary.id))
        == .boundaryRequiresStopOrCancel
    )
    #expect(await runtime.snapshot().currentOperation?.id == boundary.id)

    let waiter = Task {
      await runtime.waitForOutcome(of: boundary.id)
    }
    let stopOutcome = try accepted(await runtime.stop(boundary.id))
    #expect(stopOutcome.disposition == .stopped)
    #expect(stopOutcome.completedBoundarySegmentCount == 2)
    #expect(try accepted(await waiter.value) == stopOutcome)
  }

  @Test("mocked operator completes two causal boundary and visibility routes")
  func completeCausalVisibilityRoutes() async throws {
    let xFirst = try await runVisibilityRoute(first: .positiveX, remainingFirst: .negativeY)
    let yFirst = try await runVisibilityRoute(first: .negativeY, remainingFirst: .negativeX)

    for route in [xFirst, yFirst] {
      #expect(route.progress.isComplete)
      #expect(route.center.point == (try Point2<MachineSpace>(x: 0, y: 0)))
      #expect(route.target.validSampleCount == 2)
      #expect(route.target.includedFrameIDs.count == 2)
      #expect(route.target.targetPlanRevision == VisibilityTargetPlanV1.revision)
      #expect(route.registration.source == .simulated)
      #expect(route.registration.validationResidualPixels < 1e-9)
      #expect(route.evidenceLabel == SimulatedLearningEvidenceNotice.evidenceLabel)
    }
    #expect(xFirst.progress.acceptedDirections.first == .positiveX)
    #expect(yFirst.progress.acceptedDirections.first == .negativeY)
  }

  @Test("causal route continues through target-anchored Stage 4 line comparison")
  func completeCausalLineRoute() async throws {
    let route = try await runVisibilityRoute(
      first: .negativeX,
      remainingFirst: .positiveY,
      includeLine: true
    )
    let line = try #require(route.line)
    #expect(line.observedPixelCount > 10)
    #expect(line.residual != nil)
    #expect(line.targetPresentBaseline.frameID != line.postLine.frameID)
    #expect(route.machineActionsCallCount == 0)
  }

  @Test("partial target and camera faults retain causal scene provenance")
  func partialTargetAndFrameFaults() async throws {
    let runtime = try await enabledRuntime()
    await runtime.injectFault(.partialVisibilityTarget(segmentCount: 3))
    let operation = try accepted(await runtime.beginVisibilityTarget())
    let outcome = try accepted(await runtime.completeVisibilityTargetNaturally(operation.id))
    #expect(outcome.disposition == .failed)
    #expect(outcome.visibilityTargetSceneDisposition == .inkPossible)
    #expect(await runtime.persistentInk().count == 3)
    let first = try accepted(await runtime.captureSceneFrame())
    await runtime.injectFault(.cameraConfigurationChangeBeforeNextFrame)
    let second = try accepted(await runtime.captureSceneFrame())
    #expect(first.displayedFrame.frame.id != second.displayedFrame.frame.id)
    #expect(
      first.displayedFrame.frame.cameraConfigurationID
        != second.displayedFrame.frame.cameraConfigurationID
    )
    #expect(second.evidenceNotice == .notPhysicalEvidence)
  }

  @Test("phase-specific target ambiguity emits no later command or manufactured ink")
  func targetAmbiguityIsPhaseSpecific() async throws {
    let approachRuntime = try await enabledRuntime()
    await approachRuntime.injectFault(.ambiguityAtVisibilityTargetPhase(.approach))
    let approach = try accepted(await approachRuntime.beginVisibilityTarget())
    let approachOutcome = try accepted(
      await approachRuntime.completeVisibilityTargetNaturally(approach.id)
    )
    #expect(approachOutcome.visibilityTargetSceneDisposition == .pristine)
    #expect(approachOutcome.visibilityTargetFailurePhase == .approach)
    #expect(await approachRuntime.persistentInk().isEmpty)
    let approachSnapshot = await approachRuntime.snapshot()
    #expect(approachSnapshot.penPose == .unknown)
    let sticky = try #require(approachSnapshot.stickyAmbiguity)
    #expect(sticky.operationID == approach.id)
    #expect(sticky.phase == .approach)
    #expect(
      refusal(await approachRuntime.beginVisibilityTarget())
        == .stickyAmbiguity(sticky)
    )
    let oneMillimeterX = try SimulatedLearningMotionVector(dxMM: 1, dyMM: 0)
    #expect(
      refusal(await approachRuntime.beginManualJog(
        delta: oneMillimeterX
      )) == .stickyAmbiguity(sticky)
    )
    _ = try accepted(await approachRuntime.disconnect())
    #expect(await approachRuntime.snapshot().stickyAmbiguity == nil)
    _ = try accepted(await approachRuntime.connect())
    _ = try accepted(await approachRuntime.enableMotion())
    let newSessionMove = try accepted(await approachRuntime.beginManualJog(
      delta: oneMillimeterX
    ))
    _ = try accepted(await approachRuntime.cancel(newSessionMove.id))

    let lowerRuntime = try await enabledRuntime()
    await lowerRuntime.injectFault(.ambiguityAtVisibilityTargetPhase(.lowerPen))
    let lower = try accepted(await lowerRuntime.beginVisibilityTarget())
    let lowerOutcome = try accepted(
      await lowerRuntime.completeVisibilityTargetNaturally(lower.id)
    )
    #expect(lowerOutcome.visibilityTargetSceneDisposition == .inkPossible)
    #expect(lowerOutcome.visibilityTargetFailurePhase == .lowerPen)
    #expect(await lowerRuntime.persistentInk().isEmpty)
    #expect(await lowerRuntime.snapshot().penPose == .unknown)

    let segmentRuntime = try await enabledRuntime()
    await segmentRuntime.injectFault(.ambiguityAtVisibilityTargetPhase(.drawSegment(2)))
    let segment = try accepted(await segmentRuntime.beginVisibilityTarget())
    let segmentOutcome = try accepted(
      await segmentRuntime.completeVisibilityTargetNaturally(segment.id)
    )
    #expect(segmentOutcome.visibilityTargetFailurePhase == .drawSegment(2))
    #expect(await segmentRuntime.persistentInk().count == 2)
    // No third segment and no final Pen Up were issued after ambiguity.
    #expect(await segmentRuntime.snapshot().penPose == .down)
  }

  @Test("simulated target Stop Cancel and shutdown retain first disposition without ink")
  func targetFirstIntentDispositions() async throws {
    let cases: [
      (
        SimulatedLearningOperationIntent,
        SimulatedLearningOperationDisposition
      )
    ] = [
      (.stop, .stopped),
      (.cancel, .cancelled),
      (.shutdown, .shutdown),
    ]
    for (intent, disposition) in cases {
      let runtime = try await enabledRuntime()
      let operation = try accepted(await runtime.beginVisibilityTarget())
      let outcome = try accepted(await runtime.request(intent, for: operation.id))
      #expect(outcome.disposition == disposition)
      #expect(outcome.visibilityTargetSceneDisposition == .pristine)
      #expect(await runtime.persistentInk().isEmpty)
      #expect(await runtime.snapshot().penPose == .up)
      #expect(
        refusal(await runtime.request(intent, for: operation.id))
          == .operationAlreadySettled(operation.id, disposition)
      )
    }
  }

  @Test("Paper Replaced clears persistent ink and rotates only paper compatibility")
  func paperReplacementResetsScene() async throws {
    let runtime = try await enabledRuntime()
    let operation = try accepted(await runtime.beginVisibilityTarget())
    _ = try accepted(await runtime.completeVisibilityTargetNaturally(operation.id))
    let before = await runtime.snapshot()
    #expect(before.persistentInkSegmentCount == 8)

    let after = try accepted(await runtime.recordPaperReplaced())
    #expect(after.persistentInkSegmentCount == 0)
    #expect(after.toolPaperRevision != before.toolPaperRevision)
    #expect(after.cameraConfigurationID == before.cameraConfigurationID)
    #expect(await runtime.persistentInk().isEmpty)

    let active = try accepted(await runtime.beginManualJog(
      delta: SimulatedLearningMotionVector(dxMM: 1, dyMM: 0)
    ))
    #expect(
      refusal(await runtime.recordPaperReplaced())
        == .operationAlreadyActive(active.id)
    )
    _ = try accepted(await runtime.cancel(active.id))
  }

  @Test("injected shutdown settles the admitted target owner and disconnects the session")
  func injectedTargetShutdown() async throws {
    let runtime = try await enabledRuntime()
    await runtime.injectFault(.shutdownDuringOperation)
    let operation = try accepted(await runtime.beginVisibilityTarget())
    let outcome = try accepted(
      await runtime.completeVisibilityTargetNaturally(operation.id)
    )

    #expect(outcome.disposition == .shutdown)
    #expect(outcome.visibilityTargetSceneDisposition == .pristine)
    #expect(await runtime.persistentInk().isEmpty)
    let snapshot = await runtime.snapshot()
    #expect(snapshot.session == .disconnected)
    #expect(snapshot.motionAuthorization == .disabled)
    #expect(snapshot.currentOperation == nil)
  }
}

private struct SimulatedRouteEvidence {
  let progress: PairedBoundaryProgress
  let center: EstimatedMachineCenter
  let registration: MachineCameraRegistration
  let target: VisibilityTargetObservation
  let line: IsolatedInkObservation?
  let evidenceLabel: String
  let machineActionsCallCount: Int
}

private actor ControlledSimulatedExecutionPacing: SimulatedLearningExecutionPacing {
  private var suspensionCount = 0
  private var suspendedContinuations: [CheckedContinuation<Void, Never>] = []
  private var countWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

  func suspendBetweenSteps() async {
    suspensionCount += 1
    let readyCounts = countWaiters.keys.filter { $0 <= suspensionCount }
    for count in readyCounts {
      let waiters = countWaiters.removeValue(forKey: count) ?? []
      for waiter in waiters {
        waiter.resume()
      }
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

private func runVisibilityRoute(
  first: BoundaryDirection,
  remainingFirst: BoundaryDirection,
  includeLine: Bool = false
) async throws -> SimulatedRouteEvidence {
  let runtime = try await enabledRuntime()
  let session = UUID()
  var progress = PairedBoundaryProgress()
  var boundaries: [AcceptedBoundarySide] = []
  let order = [first, first.opposite, remainingFirst, remainingFirst.opposite]
  for direction in order {
    #expect(progress.allowedDirections.contains(direction))
    let operation = try accepted(
      await runtime.beginBoundary(direction: direction, finiteSegmentLengthMM: 10)
    )
    while true {
      let before = await runtime.snapshot().mpos
      let continuation = try accepted(
        await runtime.recordBoundarySegmentCompletion(for: operation.id)
      )
      let coordinate: Double = direction.isXAxis
        ? continuation.mpos.xMM
        : continuation.mpos.yMM
      let limit = await runtime.snapshot().boundaryTruth.limit(for: direction)
      if coordinate == limit || continuation.mpos == before { break }
    }
    let stopped = try accepted(await runtime.stop(operation.id))
    let scene = try accepted(await runtime.captureSceneFrame())
    let revision = LearningArtifactRevisionID()
    try progress.accept(direction, revisionID: revision)
    boundaries.append(AcceptedBoundarySide(
      direction: direction,
      revisionID: revision,
      controllerSessionID: session,
      coordinateRevision: 1,
      finalPosition: try MachinePosition(
        x: stopped.finalMPos.xMM,
        y: stopped.finalMPos.yMM
      ),
      contactPoint: try ToolContactPointEstimate(
        componentCentroid: Point2(
          x: scene.contactPoint.x,
          y: scene.contactPoint.y - 10
        ),
        componentBounds: scene.armatureBounds,
        confidence: 1,
        estimatorRevision: "simulated-component-bottom-center-v1",
        source: .simulated,
        frameID: scene.displayedFrame.frame.id,
        cameraConfigurationID: scene.displayedFrame.frame.cameraConfigurationID
      ),
      sideEstimatorRevision: "simulated-side-v1",
      uncertaintyPixels: 0
    ))
  }
  let center = try EstimatedMachineCenter.derive(from: boundaries)
  let current = await runtime.snapshot().mpos
  try await simulateMove(
    runtime,
    dx: center.point.x - current.xMM,
    dy: center.point.y - current.yMM
  )
  let targetPose = try accepted(await runtime.captureSceneFrame())
  let fitCorrespondences = boundaries.map {
    MachineCameraRegistrationCorrespondence(
      machine: $0.finalPosition.point,
      camera: $0.contactPoint.point
    )
  }
  let registrationFit = try MachineCameraRegistrationFit.fit(
    correspondences: fitCorrespondences
  )
  let registration = try MachineCameraRegistration(
    fit: registrationFit,
    source: .simulated,
    controllerSessionID: session,
    coordinateRevision: 1,
    cameraConfigurationID: targetPose.displayedFrame.frame.cameraConfigurationID,
    correspondenceProvenance: boundaries.map {
      MachineCameraCorrespondenceProvenance(
        machinePoint: $0.finalPosition.point,
        contactPoint: $0.contactPoint.point,
        source: $0.contactPoint.source,
        controllerSessionID: $0.controllerSessionID,
        coordinateRevision: $0.coordinateRevision,
        frameID: $0.contactPoint.frameID,
        cameraConfigurationID: $0.contactPoint.cameraConfigurationID,
        artifactRevisionID: $0.revisionID
      )
    },
    validationTargetFrameID: targetPose.displayedFrame.frame.id,
    validationMachinePoint: center.point,
    validationContactPoint: targetPose.contactPoint,
    maximumValidationResidualPixels: 0.01,
    estimatorRevision: "simulated-affine-registration-v1",
    uncertaintyPixels: 0
  )
  try await simulateMove(runtime, dx: 10, dy: 0)
  let clearMPos = await runtime.snapshot().mpos
  let preTarget = try accepted(await runtime.captureSceneFrame())
  try await simulateMove(runtime, dx: -10, dy: 0)
  let targetOperation = try accepted(await runtime.beginVisibilityTarget())
  let targetOutcome = try accepted(
    await runtime.completeVisibilityTargetNaturally(targetOperation.id)
  )
  #expect(targetOutcome.visibilityTargetSceneDisposition == .inkPossible)
  let afterTarget = await runtime.snapshot().mpos
  try await simulateMove(
    runtime,
    dx: clearMPos.xMM - afterTarget.xMM,
    dy: clearMPos.yMM - afterTarget.yMM
  )
  let firstPost = try accepted(await runtime.captureSceneFrame())
  let secondPost = try accepted(await runtime.captureSceneFrame())
  let targetCenter = targetPose.contactPoint
  let roi = PixelRect(
    x: Int(targetCenter.x) - 20,
    y: Int(targetCenter.y) - 20,
    width: 40,
    height: 40
  )
  let targetOutcomeVision = await VisionWorker().observeVisibilityTarget(
    VisibilityTargetObservationRequest(
      baseline: SamePoseFrameSample(
        displayedFrame: preTarget.displayedFrame,
        controllerPosition: try MachinePosition(x: clearMPos.xMM, y: clearMPos.yMM)
      ),
      targetSamples: [firstPost, secondPost].map {
        SamePoseFrameSample(
          displayedFrame: $0.displayedFrame,
          controllerPosition: try! MachinePosition(
            x: $0.controllerPosition.xMM,
            y: $0.controllerPosition.yMM
          )
        )
      },
      region: roi,
      thresholds: GreenPixelThresholds(minimumGreen: 140, minimumGreenExcess: 70),
      controllerSessionID: session,
      coordinateRevision: 1,
      toolPaperRevision: UUID(),
      controllerPositionToleranceMM: 0.01,
      expectedDiameterPixels: 15...26,
      minimumTargetPixels: 20,
      maximumCentroidSpreadPixels: 0.01,
      maximumAreaRatio: 1.01,
      maximumBackgroundMeanAbsoluteDifference: 0.01,
      algorithmRevision: "simulated-target-v1"
    )
  )
  guard case .observed(let target) = targetOutcomeVision else {
    throw SimulatedRouteError.targetRejected(String(describing: targetOutcomeVision))
  }

  var lineObservation: IsolatedInkObservation?
  if includeLine {
    let trialBaseline = try accepted(await runtime.captureSceneFrame())
    let lineStartMPos = try SimulatedLearningMPos(
      xMM: center.point.x + 2,
      yMM: center.point.y
    )
    let beforeLineMove = await runtime.snapshot().mpos
    try await simulateMove(
      runtime,
      dx: lineStartMPos.xMM - beforeLineMove.xMM,
      dy: lineStartMPos.yMM - beforeLineMove.yMM
    )
    _ = try accepted(await runtime.setPenPose(.down))
    let lineOperation = try accepted(
      await runtime.beginDrawing(delta: SimulatedLearningMotionVector(dxMM: 5, dyMM: 0))
    )
    _ = try accepted(await runtime.completeNaturally(lineOperation.id))
    _ = try accepted(await runtime.setPenPose(.up))
    let afterLine = await runtime.snapshot().mpos
    try await simulateMove(
      runtime,
      dx: clearMPos.xMM - afterLine.xMM,
      dy: clearMPos.yMM - afterLine.yMM
    )
    let postLine = try accepted(await runtime.captureSceneFrame())
    let cameraLineStart = try Point2<CameraPixelSpace>(
      x: targetCenter.x + 8,
      y: targetCenter.y
    )
    let lineOutcome = await VisionWorker().observeIsolatedInk(IsolatedInkObservationRequest(
      targetPresentBaseline: SamePoseFrameSample(
        displayedFrame: trialBaseline.displayedFrame,
        controllerPosition: try MachinePosition(
          x: trialBaseline.controllerPosition.xMM,
          y: trialBaseline.controllerPosition.yMM
        )
      ),
      postLine: SamePoseFrameSample(
        displayedFrame: postLine.displayedFrame,
        controllerPosition: try MachinePosition(
          x: postLine.controllerPosition.xMM,
          y: postLine.controllerPosition.yMM
        )
      ),
      region: PixelRect(x: roi.x, y: roi.y, width: 70, height: roi.height),
      thresholds: GreenPixelThresholds(minimumGreen: 140, minimumGreenExcess: 70),
      lineStartPoint: cameraLineStart,
      controllerSessionID: session,
      coordinateRevision: 1,
      toolPaperRevision: target.toolPaperRevision,
      controllerPositionToleranceMM: 0.01,
      alignmentSearchRadiusPixels: 2,
      maximumAlignmentShiftPixels: 1,
      maximumBackgroundMeanAbsoluteDifference: 0.01,
      projectedActualStrokeDelta: try Vector2(dx: 20, dy: 0),
      algorithmRevision: "simulated-line-v1",
      minimumLinePixels: 10
    ))
    guard case .observed(let observedLine) = lineOutcome else {
      throw SimulatedRouteError.lineRejected(String(describing: lineOutcome))
    }
    lineObservation = observedLine
  }
  return SimulatedRouteEvidence(
    progress: progress,
    center: center,
    registration: registration,
    target: target,
    line: lineObservation,
    evidenceLabel: targetPose.evidenceNotice.label,
    machineActionsCallCount: 0
  )
}

private enum SimulatedRouteError: Error {
  case targetRejected(String)
  case lineRejected(String)
}

private func simulateMove(
  _ runtime: SimulatedLearningRuntime,
  dx: Double,
  dy: Double
) async throws {
  let operation = try accepted(
    await runtime.beginManualJog(delta: SimulatedLearningMotionVector(dxMM: dx, dyMM: dy))
  )
  _ = try accepted(await runtime.completeNaturally(operation.id))
}

private func enabledRuntime() async throws -> SimulatedLearningRuntime {
  let runtime = SimulatedLearningRuntime()
  _ = try accepted(await runtime.connect())
  _ = try accepted(await runtime.enableMotion())
  return runtime
}

private func accepted<Value: Sendable>(
  _ response: SimulatedLearningResponse<Value>
) throws -> Value {
  try response.result.get()
}

private func refusal<Value: Sendable>(
  _ response: SimulatedLearningResponse<Value>
) -> SimulatedLearningRefusal? {
  guard case .failure(let refusal) = response.result else { return nil }
  return refusal
}
