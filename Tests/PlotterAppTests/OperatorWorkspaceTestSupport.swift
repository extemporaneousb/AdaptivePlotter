import Foundation
import PlotterModel
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

@MainActor
func stopActiveOperation(_ workspace: OperatorWorkspace) async throws {
  let capabilityID = try #require(workspace.contextualStopPresentation?.capabilityID)
  await workspace.stopCurrentOperation(capabilityID: capabilityID)
}

@MainActor
func performStart(
  _ workspace: OperatorWorkspace,
  owner: LearningPathItemID
) async {
  let start = workspace.currentExerciseActionStripPresentation?.actions.first {
    $0.kind == .start
  }
  #expect(start?.isEnabled == true)
  await workspace.performExerciseAction(.start, for: owner)
}

struct SimulatedWorkspaceHarness {
  let workspace: OperatorWorkspace
  let runtime: SimulatedLearningRuntime
  let machineActionLog: EventLog
}

func sequenceIDForTest(_ direction: BoundaryDirection) -> DiscoverySequenceID {
  switch direction {
  case .negativeX: .boundaryNegativeX
  case .positiveX: .boundaryPositiveX
  case .negativeY: .boundaryNegativeY
  case .positiveY: .boundaryPositiveY
  }
}

@MainActor
func makeSimulatedHarness(
  cameraActions: OperatorWorkspace.CameraActions? = nil,
  eventLog: EventLog? = nil,
  simulatedExecutionPacing: any SimulatedLearningExecutionPacing =
    SimulatedLearningImmediatePacing()
) -> SimulatedWorkspaceHarness {
  let machineActionLog = eventLog ?? EventLog()
  let clock = TestClock()
  // Workspace state-machine tests need causal pixels and viable vision
  // geometry, not the production simulator's default presentation footprint.
  // Dedicated runtime/renderer tests retain exact 640x480 coverage.
  let runtime = SimulatedLearningRuntime(
    frameWidth: 320,
    frameHeight: 240,
    paddingPixels: 14
  )
  return SimulatedWorkspaceHarness(
    workspace: OperatorWorkspace(
      machineActions: isolatedMachineActions(log: machineActionLog),
      cameraActions: cameraActions ?? CameraComposition.makeIsolatedActionsForTesting(),
      simulatedLearningRuntime: runtime,
      simulatedExecutionPacing: simulatedExecutionPacing,
      serialDevices: [],
      serialDeviceDiscovery: { [] },
      loadSelectedSerialIdentifier: { nil },
      persistSelectedSerialIdentifier: { _ in },
      nowNanoseconds: { clock.next() }
    ),
    runtime: runtime,
    machineActionLog: machineActionLog
  )
}

@MainActor
func performPublicAction(
  _ kind: ExerciseActionKind,
  owner: LearningPathItemID,
  workspace: OperatorWorkspace
) async throws {
  let presentation = workspace.selectedOperatorActionPresentation(for: owner)
  let action = try #require(
    presentation.actionStrip?.actions.first(where: { $0.kind == kind }),
    "Missing public action \(kind); visible actions: \(String(describing: presentation.actionStrip?.actions.map(\.kind))); exploration error: \(workspace.explorationError ?? "nil")"
  )
  #expect(action.isEnabled)
  await workspace.performExerciseAction(kind, for: owner)
}

func acceptedSimulated<Value: Sendable>(
  _ response: SimulatedLearningResponse<Value>
) throws -> Value {
  try response.result.get()
}

@MainActor
func selectPublicDirection(
  _ direction: BoundaryDirection,
  purpose: ExerciseDirectionSelectionPurpose,
  owner: LearningPathItemID,
  workspace: OperatorWorkspace
) async throws {
  let selection = try #require(
    workspace.selectedOperatorActionPresentation(for: owner).actionStrip?.directionSelection,
    "Missing direction selection; discovery error: \(workspace.discoveryError ?? "nil"); exploration error: \(workspace.explorationError ?? "nil"); activities: \(workspace.boundaryActivityRecords)"
  )
  #expect(selection.purpose == purpose)
  #expect(selection.options.contains(direction))
  await workspace.performExerciseAction(.selectDirection(purpose, direction), for: owner)
}

@MainActor
func redoSimulatedBoundary(
  _ direction: BoundaryDirection,
  workspace: OperatorWorkspace
) async throws {
  let owner = LearningPathItemID.humanGuidedDiscovery(
    .pairedBoundaryDiscoveryAndCentering
  )
  try await performPublicAction(.redoBoundary(direction), owner: owner, workspace: workspace)
  try await waitUntil {
    workspace.selectedOperatorActionPresentation(for: owner).actionStrip?.actions
      .contains(where: { if case .stop = $0.kind { true } else { false } }) == true
  }
  let stop = try #require(
    workspace.selectedOperatorActionPresentation(for: owner).actionStrip?.actions
      .first(where: { if case .stop = $0.kind { true } else { false } })?.kind
  )
  await workspace.performExerciseAction(stop, for: owner)
  try await waitUntil { workspace.activeExerciseAttemptID == nil }
}

@MainActor
func completeSimulatedVisibilityProtocol(
  _ workspace: OperatorWorkspace,
  runtime: SimulatedLearningRuntime,
  boundaryOrder: [BoundaryDirection],
  throughVisibility: Bool = true,
  moveToCenter: Bool = true,
  observeVisibility: Bool = true,
  drawVisibility: Bool = true,
  returnToClear: Bool = true,
  acceptVisibility: Bool = true
) async throws {
  await workspace.switchFrameMode(.simulated)
  #expect(workspace.frameMode == .simulated)
  #expect(workspace.simulatorEvidenceLabel == "SIMULATED — NOT PHYSICAL EVIDENCE")
  await workspace.performControllerConnectionAction()
  await workspace.activateMotionGuard()

  let penOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
  try await performPublicAction(.start, owner: penOwner, workspace: workspace)
  var physicalPoseQuestionCount = 0
  for _ in 0..<8 where !workspace.penInteractionCompleted {
    let presentation = workspace.selectedOperatorActionPresentation(for: penOwner)
    #expect(presentation.question?.prompt.isEmpty == false)
    #expect(presentation.question?.choices == [.yes, .no])
    #expect(presentation.actionStrip?.actions.contains(where: { $0.kind == .start }) == false)
    physicalPoseQuestionCount += 1
    try await performPublicAction(.choice(.yes), owner: penOwner, workspace: workspace)
  }
  #expect(workspace.penInteractionCompleted)
  #expect(physicalPoseQuestionCount == 3)

  let boundaryOwner = LearningPathItemID.humanGuidedDiscovery(
    .pairedBoundaryDiscoveryAndCentering
  )
  for direction in boundaryOrder {
    try await selectPublicDirection(
      direction,
      purpose: .boundary,
      owner: boundaryOwner,
      workspace: workspace
    )
    try await performPublicAction(.start, owner: boundaryOwner, workspace: workspace)
    try await waitUntil {
      workspace.selectedOperatorActionPresentation(for: boundaryOwner).actionStrip?.actions
        .contains(where: { if case .stop = $0.kind { true } else { false } }) == true
    }
    try await waitUntilAsync {
      let snapshot = await runtime.snapshot()
      let limit = snapshot.boundaryTruth.limit(for: direction)
      return switch direction {
      case .negativeX, .positiveX: snapshot.mpos.xMM == limit
      case .negativeY, .positiveY: snapshot.mpos.yMM == limit
      }
    }
    let stop = try #require(
      workspace.selectedOperatorActionPresentation(for: boundaryOwner).actionStrip?.actions
        .first(where: { if case .stop = $0.kind { true } else { false } })?.kind
    )
    await workspace.performExerciseAction(stop, for: boundaryOwner)
    #expect(
      workspace.activeExerciseAttemptID == nil,
      "transaction=\(String(describing: workspace.discoveryTransactions[sequenceIDForTest(direction)]?.state)) error=\(workspace.discoveryError ?? "nil") count=\(workspace.relevantBoundaryObservationCount)"
    )
    try await waitUntil { workspace.activeExerciseAttemptID == nil }
  }
  #expect(
    workspace.pairedBoundaryProgress.isComplete,
    "discovery error: \(workspace.discoveryError ?? "nil"); activities: \(workspace.boundaryActivityRecords)"
  )
  #expect(workspace.boundarySideAggregates.count == 4)
  #expect(workspace.currentLearningPathItemID == boundaryOwner)
  let boundaryReviewActions =
    workspace.selectedOperatorActionPresentation(for: boundaryOwner)
    .actionStrip?.actions.map(\.kind) ?? []
  #expect(boundaryReviewActions.first == .moveToEstimatedCenter)
  #expect(boundaryReviewActions.contains(.redoBoundary(boundaryOrder[0])))
  if !moveToCenter { return }
  try await performPublicAction(.moveToEstimatedCenter, owner: boundaryOwner, workspace: workspace)
  if !throughVisibility { return }

  let registrationOwner = LearningPathItemID.humanGuidedDiscovery(
    .registerTargetPoseAndCameraGeometry
  )
  try await performPublicAction(
    .captureTargetPoseAndBuildGeometryProposal,
    owner: registrationOwner,
    workspace: workspace
  )
  try await performPublicAction(
    .acceptTargetGeometryProposal,
    owner: registrationOwner,
    workspace: workspace
  )

  let clearOwner = LearningPathItemID.humanGuidedDiscovery(.discoverAndAcceptClearView)
  try await performPublicAction(.start, owner: clearOwner, workspace: workspace)
  let clearAttemptID = try #require(workspace.activeExerciseAttemptID)
  try await performPublicAction(
    .recordClearViewLabel(.blocked),
    owner: clearOwner,
    workspace: workspace
  )
  #expect(workspace.activeExerciseAttemptID == clearAttemptID)
  #expect(
    workspace.selectedOperatorActionPresentation(for: clearOwner).actionStrip?.actions
      .first(where: { $0.kind == .acceptClearPose })?.isEnabled == false
  )
  try await selectPublicDirection(
    .positiveX,
    purpose: .clearViewSearch,
    owner: clearOwner,
    workspace: workspace
  )
  try await performPublicAction(
    .moveForClearView(ClearViewSearchMove(direction: .positiveX, distance: .fiftyMillimeters)),
    owner: clearOwner,
    workspace: workspace
  )
  try await performPublicAction(
    .recordClearViewLabel(.partial),
    owner: clearOwner,
    workspace: workspace
  )
  #expect(workspace.activeExerciseAttemptID == clearAttemptID)
  #expect(
    workspace.selectedOperatorActionPresentation(for: clearOwner).actionStrip?.actions
      .first(where: { $0.kind == .acceptClearPose })?.isEnabled == false
  )
  try await performPublicAction(
    .moveForClearView(ClearViewSearchMove(direction: .positiveX, distance: .tenMillimeters)),
    owner: clearOwner,
    workspace: workspace
  )
  try await performPublicAction(
    .recordClearViewLabel(.clear),
    owner: clearOwner,
    workspace: workspace
  )
  #expect(workspace.activeExerciseAttemptID == clearAttemptID)
  try await performPublicAction(.acceptClearPose, owner: clearOwner, workspace: workspace)

  let baselineOwner = LearningPathItemID.humanGuidedDiscovery(.confirmBlankTargetBaseline)
  try await performPublicAction(.start, owner: baselineOwner, workspace: workspace)
  try await performPublicAction(
    .captureBlankTargetBaselineCandidate,
    owner: baselineOwner,
    workspace: workspace
  )
  try await performPublicAction(
    .confirmBlankTargetBaseline,
    owner: baselineOwner,
    workspace: workspace
  )

  let targetReturnOwner = LearningPathItemID.humanGuidedDiscovery(.returnToRegisteredTargetPose)
  try await performPublicAction(.start, owner: targetReturnOwner, workspace: workspace)
  try await performPublicAction(
    .returnToRegisteredTargetPose,
    owner: targetReturnOwner,
    workspace: workspace
  )
  if !drawVisibility { return }

  let drawOwner = LearningPathItemID.humanGuidedDiscovery(.drawVisibilityTarget)
  try await performPublicAction(.start, owner: drawOwner, workspace: workspace)
  try await performPublicAction(.drawVisibilityTarget, owner: drawOwner, workspace: workspace)
  if !returnToClear { return }

  let observationOwner = LearningPathItemID.humanGuidedDiscovery(.returnAndObserveExistingTarget)
  try await performPublicAction(.start, owner: observationOwner, workspace: workspace)
  try await performPublicAction(
    .returnToAcceptedClearPose,
    owner: observationOwner,
    workspace: workspace
  )
  if !observeVisibility { return }
  try await performPublicAction(
    .observeExistingVisibilityTarget,
    owner: observationOwner,
    workspace: workspace
  )
  if !acceptVisibility { return }

  let acceptanceOwner = LearningPathItemID.humanGuidedDiscovery(.acceptVisibilityRegistration)
  try await performPublicAction(.start, owner: acceptanceOwner, workspace: workspace)
  try await performPublicAction(
    .acceptVisibilityRegistration,
    owner: acceptanceOwner,
    workspace: workspace
  )
}

@MainActor
func completeSimulatedStageFour(_ workspace: OperatorWorkspace) async throws {
  let actions: [(LearningPathItemID, ExerciseActionKind)] = [
    (.observedDrawingTrial(.chooseIsolatedLinePlan), .chooseIsolatedLinePlan(.positiveX)),
    (.observedDrawingTrial(.captureTargetAnchoredBaseline), .captureTargetAnchoredBaseline),
    (.observedDrawingTrial(.moveToLineStart), .moveToLineStart),
    (.observedDrawingTrial(.drawIsolatedLine), .drawIsolatedLine),
    (
      .observedDrawingTrial(.returnToClearPoseAndObserveNewInk),
      .returnToClearPoseAndObserveNewInk
    ),
  ]
  for (owner, kind) in actions {
    try await performPublicAction(kind, owner: owner, workspace: workspace)
  }
  let comparison = LearningPathItemID.observedDrawingTrial(
    .compareIntendedAndObservedGeometry
  )
  try await performPublicAction(.start, owner: comparison, workspace: workspace)
  try await performPublicAction(
    .recordDrawingTrialAssessment(.observedGeometryAccepted),
    owner: comparison,
    workspace: workspace
  )
}

@MainActor
func completeLiveBoundaries(
  _ workspace: OperatorWorkspace,
  machine: MachineFixture
) async throws {
  let samples: [(BoundaryDirection, Double, Double)] = [
    (.negativeX, -100, 0),
    (.positiveX, 100, 0),
    (.negativeY, 100, -50),
    (.positiveY, 100, 50),
  ]
  for (direction, x, y) in samples {
    await workspace.beginPairedBoundarySide(direction)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await machine.setPosition(x: x, y: y)
    try await stopActiveOperation(workspace)
  }
  #expect(workspace.pairedBoundaryProgress.isComplete)
  #expect(workspace.boundarySideAggregates.count == BoundaryDirection.allCases.count)
}

@MainActor
func completePenInteraction(_ workspace: OperatorWorkspace) async throws {
  if let reason = workspace.discoveryStartUnavailableReason(for: .penInteraction) {
    throw StepMismatch(expected: "available", actual: reason)
  }
  await workspace.beginPenInteraction()
  try await finishPenInteraction(workspace)
}

@MainActor
func finishPenInteraction(_ workspace: OperatorWorkspace) async throws {
  try requireStep(workspace, "answer-initially-up")
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
func requireStep(_ workspace: OperatorWorkspace, _ expected: String) throws {
  let actual = workspace.discoveryTransactions[.penInteraction]?.currentStep?.id
  guard actual == expected else {
    throw StepMismatch(expected: expected, actual: actual ?? "nil")
  }
}

@MainActor
func workspace(
  machine: MachineFixture,
  camera: CameraFixture? = nil,
  cameraActionsOverride: OperatorWorkspace.CameraActions? = nil,
  boundaryMotionBegin:
    (@Sendable (BoundaryMotionRequest, BoundaryMotionRenewalPlanner?) async
      -> BoundaryMotionAdmission)? = nil,
  jogCancel: (@Sendable (JogCancelIntent) async -> JogCancelOutcome)? = nil,
  announcements: AnnouncementFixture? = nil,
  checkpointActions: OperatorWorkspace.AcceptedArtifactCheckpointActions? = nil,
  log _: EventLog
) -> OperatorWorkspace {
  let clock = TestClock()
  let beginBoundaryMotion = boundaryMotionBegin ?? { @Sendable request, _ in
    BoundaryMotionAdmission.admitted(
      BoundaryMotionOperation(
        ownerID: request.ownerID,
        task: Task { await machine.requestBoundaryMotion(request) }
      )
    )
  }
  let requestJogCancel = jogCancel ?? { @Sendable intent in
    await machine.cancel(intent: intent)
  }
  return OperatorWorkspace(
    machineActions: .init(
      select: { _ in await machine.snapshot() },
      snapshot: { await machine.snapshot() },
      requestPassiveProbe: {
        await machine.passiveProbeResult()
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
      beginVisibilityTarget: { _ in fatalError("unused") },
      requestVisibilityTargetIntent: { _, _ in fatalError("unused") },
      requestPenActuation: { await machine.requestPen($0) },
      requestBoundaryMotion: { await machine.requestBoundaryMotion($0) },
      beginBoundaryMotion: beginBoundaryMotion,
      requestJogCancel: requestJogCancel,
      disconnect: {}
    ),
    cameraActions: cameraActionsOverride ?? camera.map(cameraActions),
    announcementActions: announcements.map { fixture in
      .init(
        announce: { await fixture.announce($0) },
        cancelForShutdown: { await fixture.cancelForShutdown() }
      )
    },
    acceptedArtifactCheckpointActions: checkpointActions,
    serialDevices: [machine.descriptor],
    serialDeviceDiscovery: { [machine.descriptor] },
    loadSelectedSerialIdentifier: { nil },
    persistSelectedSerialIdentifier: { _ in },
    nowNanoseconds: { clock.next() }
  )
}

enum SimulatorIsolationViolation: Error {
  case machineAction(String)
}

func isolatedMachineActions(log: EventLog) -> OperatorWorkspace.MachineActions {
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
    beginVisibilityTarget: { request in
      await log.append("beginVisibilityTarget")
      return .rejected(
        .needsAttention(
          phase: .approach,
          scene: .pristine,
          failure: .approach(.refused(.notConnected)),
          progress: VisibilityTargetOperationProgress(
            planRevision: request.plan.algorithmRevision,
            phase: .approach,
            completedTraversalStepCount: 0,
            lastCompletedTraversalStep: nil
          )
        )
      )
    },
    requestVisibilityTargetIntent: { _, _ in
      await log.append("requestVisibilityTargetIntent")
      return .staleOperation
    },
    requestPenActuation: { _ in
      await log.append("requestPenActuation")
      return .refused(.notConnected)
    },
    requestBoundaryMotion: { request in
      await log.append("requestBoundaryMotion")
      return .needsAttention(ownerID: request.ownerID, terminal: .refusal(.notConnected))
    },
    beginBoundaryMotion: { request, _ in
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

func cameraActions(_ fixture: CameraFixture) -> OperatorWorkspace.CameraActions {
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
    observeIsolatedInk: { _ in fatalError("unused") },
    observeVisibilityTarget: { _, _ in fatalError("unused") },
  )
}

actor EventLog {
  private(set) var values: [String] = []
  func append(_ value: String) { values.append(value) }
  func clear() { values.removeAll(keepingCapacity: true) }
}

actor VisibilityObservationGate {
  enum CancellationDisposition: Sendable {
    case cancelled
    case staleRejection
  }

  private let cancellationDisposition: CancellationDisposition
  private let log: EventLog?
  private var continuation: CheckedContinuation<VisibilityTargetObservationOutcome, Never>?
  private var cancellationFrameID: FrameID?
  private(set) var callCount = 0
  private(set) var cancelRequestCount = 0

  init(
    cancellationDisposition: CancellationDisposition,
    log: EventLog? = nil
  ) {
    self.cancellationDisposition = cancellationDisposition
    self.log = log
  }

  func observe(
    _ request: VisibilityTargetObservationRequest,
    progress: @escaping @Sendable (VisibilityTargetObservationProgress) -> Void
  ) async -> VisibilityTargetObservationOutcome {
    callCount += 1
    cancellationFrameID = request.targetSamples.first?.frame.id
    progress(VisibilityTargetObservationProgress(sampleIndex: 1, sampleCount: 2))
    let outcome = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if Task.isCancelled {
          continuation.resume(returning: cancellationOutcome())
        } else {
          self.continuation = continuation
        }
      }
    } onCancel: {
      Task { await self.requestCancellation() }
    }
    await log?.append("vision-returned")
    return outcome
  }

  private func requestCancellation() async {
    cancelRequestCount += 1
    await log?.append("vision-cancel-requested")
    continuation?.resume(returning: cancellationOutcome())
    continuation = nil
  }

  private func cancellationOutcome() -> VisibilityTargetObservationOutcome {
    switch cancellationDisposition {
    case .cancelled:
      return .cancelled
    case .staleRejection:
      return .rejected(
        .targetMissing(
          frameID: cancellationFrameID ?? FrameID(rawValue: "late-stale-frame")
        ))
    }
  }
}

func gatedCameraActions(
  gate: VisibilityObservationGate,
  log: EventLog? = nil
) -> OperatorWorkspace.CameraActions {
  let base = CameraComposition.makeIsolatedActionsForTesting()
  return OperatorWorkspace.CameraActions(
    discover: base.discover,
    select: base.select,
    start: base.start,
    stop: {
      await log?.append("camera-stop")
      return await base.stop()
    },
    restart: base.restart,
    snapshot: base.snapshot,
    frames: base.frames,
    inspectScene: base.inspectScene,
    captureFrame: base.captureFrame,
    captureSnapshot: base.captureSnapshot,
    setAutomaticInspection: base.setAutomaticInspection,
    analysisUpdates: base.analysisUpdates,
    observeIsolatedInk: base.observeIsolatedInk,
    observeVisibilityTarget: { request, progress in
      await gate.observe(request, progress: progress)
    }
  )
}

final class TestClock: @unchecked Sendable {
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

final class CheckpointBox: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: AcceptedMachineArtifactCheckpoint?

  var checkpoint: AcceptedMachineArtifactCheckpoint? {
    lock.lock()
    defer { lock.unlock() }
    return stored
  }

  func load() -> AcceptedArtifactCheckpointLoadResult {
    lock.lock()
    defer { lock.unlock() }
    return stored.map(AcceptedArtifactCheckpointLoadResult.loaded) ?? .absent
  }

  func save(_ checkpoint: AcceptedMachineArtifactCheckpoint) {
    lock.lock()
    stored = checkpoint
    lock.unlock()
  }

  func clear() {
    lock.lock()
    stored = nil
    lock.unlock()
  }
}

actor AnnouncementFixture {
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

actor MachineFixture {
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
  let relativeJogSettlementOffset: Vector2<MachineSpace>?
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
    holdCancellationSettlement: Bool = false,
    relativeJogSettlementOffset: Vector2<MachineSpace>? = nil
  ) throws {
    self.log = log
    self.feedLimits = feedLimits
    self.reportsBoundaryMoving = reportsBoundaryMoving
    self.holdCancellationSettlement = holdCancellationSettlement
    self.relativeJogSettlementOffset = relativeJogSettlementOffset
    position = try MachinePosition(x: 0, y: 0)
  }

  func setPosition(x: Double, y: Double) throws {
    position = try MachinePosition(x: x, y: y)
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

  func passiveProbeResult() -> PassiveProbeResult {
    let reports: [(PassiveQuery, [String])] = [
      (.buildInfo, ["[VER:1.1h.20200101:workspace-fixture]"]),
      (.parserState, ["[GC:G0 G54 G17 G21 G90 G94 M5 M9 T0 F0 S0]"]),
      (
        .status,
        [String(format: "<Idle|MPos:%.3f,%.3f,0.000>", position.point.x, position.point.y)]
      ),
      (.configuration, ["$100=80.000", "$101=80.000", "$110=900.000"]),
      (.coordinateOffsets, ["[G54:0.000,0.000,0.000]", "[G92:0.000,0.000,0.000]"]),
    ]
    return PassiveProbeResult(
      link: descriptor,
      startedAt: RuntimeTimestamp(monotonicNanoseconds: 1),
      completedAt: RuntimeTimestamp(monotonicNanoseconds: 2),
      exchanges: reports.map { query, report in
        let text = query == .status ? report : report + ["ok"]
        return PassiveProbeExchange(
          query: query,
          commandID: UUID(),
          rawIO: [],
          lines: text.map { GRBLParser.parseLine(Data($0.utf8)) },
          completed: true,
          blocker: nil
        )
      },
      blockers: []
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
    if let relativeJogSettlementOffset {
      position = try! MachinePosition(
        x: position.point.x + request.delta.dx + relativeJogSettlementOffset.dx,
        y: position.point.y + request.delta.dy + relativeJogSettlementOffset.dy
      )
      moving = false
      activeRequest = nil
      let outcome = MotionOutcome.acceptedThenCompleted(finalPosition: position)
      lastMotion = outcome
      return outcome
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

final class CameraFixture: @unchecked Sendable {
  let device: CameraDevice
  let snapshot: CameraCaptureSnapshot
  private let configurationID: CameraConfigurationID
  private let rotatesConfiguration: Bool
  private let lock = NSLock()
  private var inspectionCount = 0
  private var automaticInspectionRequests: [VisionAnalysisCadence?] = []

  var inspectionCallCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return inspectionCount
  }

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
    let inspectionConfigurationID =
      rotatesConfiguration
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
    return automaticInspectionRequests.compactMap { $0 }
  }

  var recordedAutomaticInspectionRequests: [VisionAnalysisCadence?] {
    lock.lock()
    defer { lock.unlock() }
    return automaticInspectionRequests
  }

  func setAutomaticInspection(
    _ cadence: VisionAnalysisCadence?
  ) -> PlotterSceneAnalysisSnapshot {
    lock.lock()
    automaticInspectionRequests.append(cadence)
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

actor BoundaryRenewalMotionGate {
  private var segmentReleased = false
  private var segmentContinuation: CheckedContinuation<Void, Never>?
  private var pendingCancelIntent: JogCancelIntent?
  private var cancelContinuation: CheckedContinuation<JogCancelIntent, Never>?
  private var finalPosition: MachinePosition?
  private(set) var request: BoundaryMotionRequest?

  func run(
    _ request: BoundaryMotionRequest,
    renewalPlanner: BoundaryMotionRenewalPlanner?
  ) async -> BoundaryMotionOutcome {
    self.request = request
    await waitForFirstSegmentRelease()
    let finalPosition = try! MachinePosition(
      x: request.segment.delta.dx,
      y: request.segment.delta.dy
    )
    self.finalPosition = finalPosition
    if let renewalPlanner {
      _ = await renewalPlanner.nextSegmentLength(
        after: BoundaryMotionSegmentProgress(
          ownerID: request.ownerID,
          direction: request.direction,
          completedSegmentCount: 1,
          completedSegment: request.segment,
          startPosition: try! MachinePosition(x: 0, y: 0),
          finalPosition: finalPosition
        )
      )
    }
    let intent = await waitForCancelIntent()
    return .settled(
      BoundaryMotionSettlement(
        ownerID: request.ownerID,
        intent: intent,
        completedSegmentCount: 1,
        finalPosition: finalPosition,
        jogCancelOutcome: .completed(finalPosition: finalPosition)
      )
    )
  }

  func releaseFirstSegment() {
    segmentReleased = true
    segmentContinuation?.resume()
    segmentContinuation = nil
  }

  func cancel(_ intent: JogCancelIntent) -> JogCancelOutcome {
    if let cancelContinuation {
      self.cancelContinuation = nil
      cancelContinuation.resume(returning: intent)
    } else {
      pendingCancelIntent = intent
    }
    return .completed(finalPosition: finalPosition ?? (try! MachinePosition(x: 0, y: 0)))
  }

  private func waitForFirstSegmentRelease() async {
    guard !segmentReleased else { return }
    await withCheckedContinuation { segmentContinuation = $0 }
  }

  private func waitForCancelIntent() async -> JogCancelIntent {
    if let pendingCancelIntent {
      self.pendingCancelIntent = nil
      return pendingCancelIntent
    }
    return await withCheckedContinuation { cancelContinuation = $0 }
  }
}

actor BoundaryInspectionGate {
  private var started = false
  private var cancelled = false
  private var released = false
  private var continuation: CheckedContinuation<Void, Never>?

  var isStarted: Bool { started }
  var isCancelled: Bool { cancelled }

  func inspect(_ inspection: LiveSceneInspection) async throws -> LiveSceneInspection {
    started = true
    await withTaskCancellationHandler {
      if !released {
        await withCheckedContinuation { continuation = $0 }
      }
    } onCancel: {
      Task { await self.recordCancellation() }
    }
    try Task.checkCancellation()
    return inspection
  }

  func release() {
    released = true
    continuation?.resume()
    continuation = nil
  }

  private func recordCancellation() {
    cancelled = true
  }
}

func boundaryGatedCameraActions(
  _ fixture: CameraFixture,
  gate: BoundaryInspectionGate
) -> OperatorWorkspace.CameraActions {
  let base = cameraActions(fixture)
  return OperatorWorkspace.CameraActions(
    discover: base.discover,
    select: base.select,
    start: base.start,
    stop: base.stop,
    restart: base.restart,
    snapshot: base.snapshot,
    frames: base.frames,
    inspectScene: { boundary in
      try await gate.inspect(fixture.inspection(after: boundary))
    },
    captureFrame: base.captureFrame,
    captureSnapshot: base.captureSnapshot,
    setAutomaticInspection: base.setAutomaticInspection,
    analysisUpdates: base.analysisUpdates,
    observeIsolatedInk: base.observeIsolatedInk,
    observeVisibilityTarget: base.observeVisibilityTarget
  )
}

func frame(
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

actor LateVisibilityStopPacing: SimulatedLearningExecutionPacing {
  private let lateStopSuspension = VisibilityTargetPlanV2().drawingStepCount + 3
  private var suspensionCount = 0
  private var suspension: CheckedContinuation<Void, Never>?
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func suspendBetweenSteps() async {
    suspensionCount += 1
    guard suspensionCount == lateStopSuspension else { return }
    await withCheckedContinuation { continuation in
      suspension = continuation
      let pending = waiters
      waiters.removeAll()
      for waiter in pending { waiter.resume() }
    }
  }

  func waitUntilLateStopPoint() async {
    if suspensionCount >= lateStopSuspension { return }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func resume() {
    let continuation = suspension
    suspension = nil
    continuation?.resume()
  }
}

actor CalibrationStopPacing: SimulatedLearningExecutionPacing {
  private var suspended = false
  private var suspension: CheckedContinuation<Void, Never>?
  private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []

  func suspendBetweenSteps() async {
    await withCheckedContinuation { continuation in
      suspension = continuation
      suspended = true
      let waiters = suspensionWaiters
      suspensionWaiters.removeAll()
      for waiter in waiters { waiter.resume() }
    }
  }

  func waitUntilSuspended() async {
    if suspended { return }
    await withCheckedContinuation { continuation in
      suspensionWaiters.append(continuation)
    }
  }

  func resume() {
    let continuation = suspension
    suspension = nil
    continuation?.resume()
  }
}

@MainActor
func waitUntil(
  attempts: Int = 2_000,
  condition: () -> Bool
) async throws {
  for _ in 0..<attempts {
    if condition() { return }
    try await Task.sleep(for: .milliseconds(1))
  }
  throw TestTimeout()
}

@MainActor
func waitUntilAsync(
  attempts: Int = 2_000,
  condition: () async -> Bool
) async throws {
  for _ in 0..<attempts {
    if await condition() { return }
    try await Task.sleep(for: .milliseconds(1))
  }
  throw TestTimeout()
}

struct TestTimeout: Error {}
struct StepMismatch: Error {
  let expected: String
  let actual: String
}
