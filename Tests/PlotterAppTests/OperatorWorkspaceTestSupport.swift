import Foundation
import PlotterModel
import PlotterTestSupport
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
  workflowTelemetry: WorkflowTelemetryFixture? = nil,
  checkpointActions: OperatorWorkspace.AcceptedArtifactCheckpointActions? = nil,
  tipCheckpointActions: OperatorWorkspace.AcceptedTipCalibrationCheckpointActions? = nil,
  tipCalibrationSemanticIdentities: TipCalibrationSemanticIdentityState = .ephemeral(),
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
    paddingPixels: 14,
    toolPaperRevision: tipCalibrationSemanticIdentities.paperContactPlane.rawValue
  )
  return SimulatedWorkspaceHarness(
    workspace: OperatorWorkspace(
      machineActions: isolatedMachineActions(log: machineActionLog),
      cameraActions: cameraActions ?? CameraComposition.makeIsolatedActionsForTesting(),
      acceptedArtifactCheckpointActions: checkpointActions,
      acceptedTipCalibrationCheckpointActions: tipCheckpointActions,
      tipCalibrationSemanticIdentities: tipCalibrationSemanticIdentities,
      workflowTelemetryActions: workflowTelemetry.map { fixture in
        .init(record: { await fixture.record($0) })
      },
      simulatedLearningRuntime: runtime,
      simulatedExecutionPacing: simulatedExecutionPacing,
      serialDevices: [],
      serialDeviceDiscovery: { [] },
      loadSelectedSerialIdentifier: { nil },
      persistSelectedSerialIdentifier: { _ in },
      loadPenCapAppearanceSelection: { testPenCapAppearanceSelection() },
      persistPenCapAppearanceSelection: { _ in },
      loadOverlayPreference: { Set(UserSceneOverlay.allCases) },
      persistOverlayPreference: { _ in },
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
func completeSimulatedBoundariesAndCenter(
  _ workspace: OperatorWorkspace,
  runtime: SimulatedLearningRuntime,
  boundaryOrder: [BoundaryDirection],
  moveToCenter: Bool = true
) async throws {
  await workspace.switchFrameMode(.simulated)
  #expect(workspace.frameMode == .simulated)
  #expect(workspace.simulatorEvidenceLabel == "SIMULATED — NOT PHYSICAL EVIDENCE")
  await workspace.performControllerConnectionAction()
  await workspace.activateMotionGuard()

  let penOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
  try await performPublicAction(.start, owner: penOwner, workspace: workspace)
  try await identifyPenCap(workspace)
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
}

@MainActor
func completeSimulatedSparseTipCalibration(
  _ workspace: OperatorWorkspace,
  runtime: SimulatedLearningRuntime
) async throws {
  let registrationOwner = LearningPathItemID.humanGuidedDiscovery(
    .calibrateCameraAndVisibleCap
  )
  try await performPublicAction(
    .runCameraCalibrationAndBuildProposal,
    owner: registrationOwner,
    workspace: workspace
  )
  try await performPublicAction(
    .acceptCameraCalibrationProposal,
    owner: registrationOwner,
    workspace: workspace
  )
  let tipOwner = LearningPathItemID.humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
  try await performPublicAction(.start, owner: tipOwner, workspace: workspace)
  let truthOffset = await runtime.capToTipPixelOffsetTruth()
  #expect(abs(truthOffset.dx) + abs(truthOffset.dy) > 0)
  let registration = try #require(workspace.machineCameraRegistration)
  let referencePosition = try #require(workspace.cameraCalibrationReferencePosition)
  let representativeBoundary = try #require(workspace.boundarySideAggregates.values.first)
  let plan = try CurrentCameraCalibrationPlan(
    targetPosition: referencePosition,
    boundarySideAggregates: workspace.boundarySideAggregates,
    controllerSessionID: representativeBoundary.controllerSessionID,
    coordinateRevision: representativeBoundary.coordinateRevision
  )
  for position in SparseTipCalibrationCoordinator.orderedPositions {
    try await performPublicAction(.createNextSparseTipMark, owner: tipOwner, workspace: workspace)
    let request = try #require(
      workspace.actionSurfacePresentation.pointSelectionRequest,
      "missing selection request for \(position): \(workspace.explorationError ?? "no error")"
    )
    let sample = try #require(plan.samples.first { $0.position == position })
    let capPoint = try registration.fit.cameraPoint(from: sample.machinePosition.point)
    let truthPoint = try capPoint.translated(by: truthOffset)
    workspace.selectToolContactPoint(
      ActionSurfacePointSelection(
        frame: request.frame,
        point: truthPoint,
        presentationTransformRevision: request.presentationTransformRevision
      ))
    try await performPublicAction(.acceptSparseTipMark, owner: tipOwner, workspace: workspace)
  }
  try await performPublicAction(.acceptTipCalibration, owner: tipOwner, workspace: workspace)
}

@MainActor
func completeSimulatedStageFour(_ workspace: OperatorWorkspace) async throws {
  let actions: [(LearningPathItemID, ExerciseActionKind)] = [
    (.observedDrawingTrial(.chooseIsolatedLinePlan), .chooseIsolatedLinePlan(.positiveX)),
    (.observedDrawingTrial(.captureLocalPreLineBaseline), .captureLocalPreLineBaseline),
    (.observedDrawingTrial(.moveToLineStart), .moveToLineStart),
    (.observedDrawingTrial(.drawIsolatedLine), .drawIsolatedLine),
    (
      .observedDrawingTrial(.revealAndObserveNewInk),
      .revealAndObserveNewInk
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
  try await identifyPenCap(workspace)
  try await finishPenInteraction(workspace)
}

@MainActor
func identifyPenCap(_ workspace: OperatorWorkspace) async throws {
  try submitPenCapClick(workspace)
  await workspace.awaitPenCapAcceptedClickTransition()
  try requireStep(workspace, "answer-initially-up")
}

@MainActor
func submitPenCapClick(_ workspace: OperatorWorkspace) throws {
  let request = try #require(workspace.actionSurfacePresentation.pointSelectionRequest)
  let displayed = try #require(workspace.actionSurfacePresentation.displayedFrame)
  #expect(request.purpose == .penCapAppearance)
  let overlayPoint = workspace.actionSurfacePresentation.overlays.compactMap {
    measurement -> Point2<CameraPixelSpace>? in
    guard measurement.provenance.kind == .penCap, case .point(let point) = measurement.geometry
    else { return nil }
    return point
  }.first
  let fallbackPoint = try Point2<CameraPixelSpace>(
    x: Double(displayed.frame.width - 1) / 2,
    y: Double(displayed.frame.height - 1) / 2
  )
  let point = overlayPoint.flatMap {
    $0.x >= 0 && $0.x < Double(displayed.frame.width)
      && $0.y >= 0 && $0.y < Double(displayed.frame.height) ? $0 : nil
  } ?? fallbackPoint
  workspace.selectToolContactPoint(
    ActionSurfacePointSelection(
      frame: request.frame,
      point: point,
      presentationTransformRevision: request.presentationTransformRevision
    )
  )
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
    (
      @Sendable (BoundaryMotionRequest, BoundaryMotionRenewalPlanner?) async
        -> BoundaryMotionAdmission
    )? = nil,
  jogCancel: (@Sendable (JogCancelIntent) async -> JogCancelOutcome)? = nil,
  announcements: AnnouncementFixture? = nil,
  checkpointActions: OperatorWorkspace.AcceptedArtifactCheckpointActions? = nil,
  workflowTelemetry: WorkflowTelemetryFixture? = nil,
  loadPenCapAppearanceSelection:
    @escaping @Sendable () -> PenCapAppearanceSelection? = { testPenCapAppearanceSelection() },
  persistPenCapAppearanceSelection:
    @escaping @Sendable (PenCapAppearanceSelection?) -> Void = { _ in },
  loadOverlayPreference: @escaping @Sendable () -> Set<UserSceneOverlay>? = { nil },
  persistOverlayPreference: @escaping @Sendable (Set<UserSceneOverlay>) -> Void = { _ in },
  log _: EventLog
) -> OperatorWorkspace {
  let clock = TestClock()
  let beginBoundaryMotion =
    boundaryMotionBegin ?? { @Sendable request, _ in
      BoundaryMotionAdmission.admitted(
        BoundaryMotionOperation(
          ownerID: request.ownerID,
          task: Task { await machine.requestBoundaryMotion(request) }
        )
      )
    }
  let requestJogCancel =
    jogCancel ?? { @Sendable intent in
      await machine.cancel(intent: intent)
    }
  return OperatorWorkspace(
    machineActions: .init(
      select: { _ in await machine.snapshot() },
      snapshot: { await machine.snapshot() },
      requestPassiveProbe: {
        await machine.passiveProbeResult()
      },
      requestControllerAlarmClear: { .refused(.noCurrentAlarmEvidence) },
      activateMotionGuard: { .activated },
      beginRelativeJog: { request in
        .admitted(
          RelativeJogOperation(
            id: UUID(),
            task: Task { await machine.requestRelativeJog(request) }
          )
        )
      },
      beginDrawingStroke: { request in
        .admitted(
          DrawingStrokeOperation(
            id: UUID(),
            task: Task { await machine.requestDrawingStroke(request) }
          )
        )
      },
      requestPenActuation: { await machine.requestPen($0, profile: $1) },
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
    workflowTelemetryActions: workflowTelemetry.map { fixture in
      .init(record: { await fixture.record($0) })
    },
    serialDevices: [machine.descriptor],
    serialDeviceDiscovery: { [machine.descriptor] },
    loadSelectedSerialIdentifier: { nil },
    persistSelectedSerialIdentifier: { _ in },
    loadPenCapAppearanceSelection: loadPenCapAppearanceSelection,
    persistPenCapAppearanceSelection: persistPenCapAppearanceSelection,
    loadOverlayPreference: loadOverlayPreference,
    persistOverlayPreference: persistOverlayPreference,
    nowNanoseconds: { clock.next() }
  )
}

func testPenCapAppearanceSelection(
  color: PenCapColor = .green,
  source: FrameSourceIdentity = .live(CameraDeviceID(rawValue: "test-camera")),
  cameraConfigurationID: CameraConfigurationID = CameraConfigurationID()
) -> PenCapAppearanceSelection {
  PenCapAppearanceSelection(
    color: color,
    frameID: FrameID(rawValue: "test-pen-cap-selection"),
    frameSHA256: String(repeating: "0", count: 64),
    source: source,
    cameraConfigurationID: cameraConfigurationID,
    width: 1,
    height: 1,
    pixelFormat: .bgra8,
    clickPoint: try! Point2(x: 0, y: 0),
    usableSampleCount: 9,
    totalSampleCount: 9,
    algorithmRevision: PenCapAppearanceSampler.algorithmRevision
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
    requestControllerAlarmClear: {
      await log.append("requestControllerAlarmClear")
      return .refused(.noCurrentAlarmEvidence)
    },
    activateMotionGuard: {
      await log.append("activateMotionGuard")
      return .refused(.notConnected)
    },
    beginRelativeJog: { _ in
      await log.append("beginRelativeJog")
      return .rejected(.refused(.notConnected))
    },
    beginDrawingStroke: { _ in
      await log.append("beginDrawingStroke")
      return .rejected(.refused(.notConnected))
    },
    requestPenActuation: { _, _ in
      await log.append("requestPenActuation")
      return .refused(.notConnected)
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
    discover: { fixture.discoverResponse() },
    select: { _ in fixture.selectResponse() },
    start: { fixture.startResponse() },
    stop: { fixture.snapshot },
    restart: { fixture.snapshot },
    snapshot: { fixture.snapshot },
    frames: { AsyncStream { $0.finish() } },
    inspectWorkflowScene: { boundary, features, region in
      try fixture.inspection(after: boundary, features: features, analysisRegion: region)
    },
    captureFrame: { try fixture.inspection(after: $0).displayedFrame },
    setSceneAnalysisRegion: { fixture.setSceneAnalysisRegion($0) },
    setPenCapColor: { fixture.setPenCapColor($0) },
    setAutomaticInspection: { fixture.setAutomaticInspection($0, features: $1) },
    analysisUpdates: { AsyncStream { $0.finish() } },
    observeIsolatedInk: { _ in fatalError("unused") }
  )
}

actor EventLog {
  private(set) var values: [String] = []
  func append(_ value: String) { values.append(value) }
  func clear() { values.removeAll(keepingCapacity: true) }
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
  private var loads = 0
  private var saves = 0
  private var clears = 0

  var checkpoint: AcceptedMachineArtifactCheckpoint? {
    lock.lock()
    defer { lock.unlock() }
    return stored
  }

  var operationCounts: (loads: Int, saves: Int, clears: Int) {
    lock.lock()
    defer { lock.unlock() }
    return (loads, saves, clears)
  }

  func load() -> AcceptedArtifactCheckpointLoadResult {
    lock.lock()
    defer { lock.unlock() }
    loads += 1
    return stored.map(AcceptedArtifactCheckpointLoadResult.loaded) ?? .absent
  }

  func save(_ checkpoint: AcceptedMachineArtifactCheckpoint) {
    lock.lock()
    saves += 1
    stored = checkpoint
    lock.unlock()
  }

  func clear() {
    lock.lock()
    clears += 1
    stored = nil
    lock.unlock()
  }
}

final class TipCheckpointBox: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: AcceptedTipCalibrationCheckpoint?
  private var loads = 0
  private var saves = 0
  private var clears = 0

  init(checkpoint: AcceptedTipCalibrationCheckpoint? = nil) {
    stored = checkpoint
  }

  var checkpoint: AcceptedTipCalibrationCheckpoint? {
    lock.lock()
    defer { lock.unlock() }
    return stored
  }

  var operationCounts: (loads: Int, saves: Int, clears: Int) {
    lock.lock()
    defer { lock.unlock() }
    return (loads, saves, clears)
  }

  func load() -> AcceptedTipCalibrationCheckpointLoadResult {
    lock.lock()
    defer { lock.unlock() }
    loads += 1
    return stored.map(AcceptedTipCalibrationCheckpointLoadResult.quarantined) ?? .absent
  }

  func save(_ checkpoint: AcceptedTipCalibrationCheckpoint) {
    lock.lock()
    saves += 1
    stored = checkpoint
    lock.unlock()
  }

  func clear() {
    lock.lock()
    clears += 1
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

actor WorkflowTelemetryFixture {
  private(set) var events: [WorkflowTelemetryEvent] = []

  func record(_ event: WorkflowTelemetryEvent) {
    events.append(event)
  }
}

actor PenRequestGate {
  private var shouldBlockFirstRequest = true
  private var releasedEarly = false
  private var continuation: CheckedContinuation<Void, Never>?

  func waitIfFirstRequest() async {
    guard shouldBlockFirstRequest else { return }
    shouldBlockFirstRequest = false
    if releasedEarly { return }
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func releaseFirstRequest() {
    guard let continuation else {
      releasedEarly = true
      return
    }
    self.continuation = nil
    continuation.resume()
  }
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
  let penRequestGate: PenRequestGate?
  private(set) var cancelCount = 0
  private(set) var cancelIntents: [JogCancelIntent] = []
  private(set) var requestedFeeds: [Double] = []
  private(set) var requestedDrawingStrokes: [DrawingStrokeRequest] = []
  private(set) var requestedPenCommands: [PenCommand] = []
  private(set) var requestedPenProfiles: [PenActuationProfile] = []
  private var moving = false
  private var cancelPending = false
  private var pendingCancelIntent: JogCancelIntent?
  private var continuation: CheckedContinuation<MotionOutcome, Never>?
  private var drawingContinuation: CheckedContinuation<DrawingStrokeOutcome, Never>?
  private var boundaryContinuation: CheckedContinuation<BoundaryMotionOutcome, Never>?
  private var position: MachinePosition
  private var penState: PenState = .up
  private var hasActuatedPen = false
  private var lastMotion: MotionOutcome?
  private var lastDrawing: DrawingStrokeOutcome?
  private var lastPen: PenOutcome?
  private var lastCancel: JogCancelOutcome?
  private var queuedPenOutcomes: [PenOutcome] = []
  private var activeRequest: RelativeJogRequest?
  private var activeDrawingRequest: DrawingStrokeRequest?
  private var drawingStartPosition: MachinePosition?
  private var activeBoundaryRequest: BoundaryMotionRequest?
  private var heldBoundaryCancelIntent: JogCancelIntent?

  init(
    log: EventLog,
    feedLimits: ControllerAxisFeedLimits? = nil,
    reportsBoundaryMoving: Bool = true,
    holdCancellationSettlement: Bool = false,
    relativeJogSettlementOffset: Vector2<MachineSpace>? = nil,
    penRequestGate: PenRequestGate? = nil
  ) throws {
    self.log = log
    self.feedLimits = feedLimits
    self.reportsBoundaryMoving = reportsBoundaryMoving
    self.holdCancellationSettlement = holdCancellationSettlement
    self.relativeJogSettlementOffset = relativeJogSettlementOffset
    self.penRequestGate = penRequestGate
    position = try MachinePosition(x: 0, y: 0)
  }

  func setPosition(x: Double, y: Double) throws {
    position = try MachinePosition(x: x, y: y)
  }

  func setPenState(_ state: PenState) {
    penState = state
  }

  func enqueuePenOutcome(_ outcome: PenOutcome) {
    queuedPenOutcomes.append(outcome)
  }

  func snapshot() -> RunInterpreterSnapshot {
    RunInterpreterSnapshot(
      currentOperation: activeBoundaryRequest.map(RunOperation.boundaryMotion)
        ?? activeDrawingRequest.map(RunOperation.drawingStroke)
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
        lastDrawingStrokeOutcome: lastDrawing,
        lastPenOutcome: lastPen,
        lastJogCancelOutcome: lastCancel,
        controllerAxisFeedLimits: feedLimits
      ),
      lastMotionOutcome: lastMotion,
      lastDrawingStrokeOutcome: lastDrawing,
      lastPenOutcome: lastPen,
      lastProbe: nil,
      lastJogCancelOutcome: lastCancel
    )
  }

  func passiveProbeResult() -> PassiveProbeResult {
    let parserState =
      hasActuatedPen
      ? "[GC:G0 G54 G17 G21 G90 G94 M3 M9 T0 F0 S40]"
      : "[GC:G0 G54 G17 G21 G90 G94 M5 M9 T0 F0 S0]"
    let reports: [(PassiveQuery, [String])] = [
      (.buildInfo, ["[VER:1.1h.20200101:workspace-fixture]"]),
      (.parserState, [parserState]),
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

  func requestDrawingStroke(_ request: DrawingStrokeRequest) async -> DrawingStrokeOutcome {
    requestedFeeds.append(request.feedMMPerMinute)
    requestedDrawingStrokes.append(request)
    activeDrawingRequest = request
    drawingStartPosition = position
    moving = true
    await log.append("machine:drawing-stroke")
    if let relativeJogSettlementOffset {
      let start = position
      position = try! MachinePosition(
        x: position.point.x + request.delta.dx + relativeJogSettlementOffset.dx,
        y: position.point.y + request.delta.dy + relativeJogSettlementOffset.dy
      )
      moving = false
      activeDrawingRequest = nil
      drawingStartPosition = nil
      let outcome = DrawingStrokeOutcome.completed(
        evidence: drawingEvidence(request: request, start: start, final: position)
      )
      lastDrawing = outcome
      return outcome
    }
    let outcome = await withCheckedContinuation { continuation in
      drawingContinuation = continuation
    }
    lastDrawing = outcome
    activeDrawingRequest = nil
    drawingStartPosition = nil
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
    } else if let drawingContinuation, let request = activeDrawingRequest {
      self.drawingContinuation = nil
      let outcome = settleDrawingCancelled(request)
      drawingContinuation.resume(returning: outcome)
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

  func requestPen(
    _ command: PenCommand,
    profile: PenActuationProfile = .initialDefaults
  ) async -> PenOutcome {
    await log.append("machine:pen-\(command.rawValue)")
    requestedPenCommands.append(command)
    requestedPenProfiles.append(profile)
    await penRequestGate?.waitIfFirstRequest()
    hasActuatedPen = true
    let outcome = queuedPenOutcomes.isEmpty
      ? PenOutcome.commandedAndSettled(command: command, commandedState: command.commandedState)
      : queuedPenOutcomes.removeFirst()
    if case .commandedAndSettled(_, let commandedState) = outcome {
      penState = commandedState
    }
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

  private func settleDrawingCancelled(_ request: DrawingStrokeRequest) -> DrawingStrokeOutcome {
    moving = false
    let start = drawingStartPosition ?? position
    let evidence = drawingEvidence(request: request, start: start, final: position)
    penState = .up
    let penOutcome = PenOutcome.commandedAndSettled(command: .raise, commandedState: .up)
    lastPen = penOutcome
    let outcome = DrawingStrokeOutcome.cancelled(
      evidence: evidence,
      penRaiseOutcome: penOutcome
    )
    lastDrawing = outcome
    activeDrawingRequest = nil
    drawingStartPosition = nil
    return outcome
  }

  private func drawingEvidence(
    request: DrawingStrokeRequest,
    start: MachinePosition,
    final: MachinePosition
  ) -> DrawingStrokeEvidence {
    DrawingStrokeEvidence(
      request: request,
      startPosition: start,
      startSampleNanoseconds: 10,
      finalPosition: final,
      finalSampleNanoseconds: 20
    )
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
  private let providesInspectionOverlay: Bool
  private let providesAutomaticAnalysisResult: Bool
  private let capCentroidXOffsets: [Double]
  private let lock = NSLock()
  private var inspectionCount = 0
  private var automaticInspectionRequests: [VisionAnalysisCadence?] = []
  private var automaticFeatureRequests: [SceneFeatureSet] = []
  private var workflowFeatureRequests: [SceneFeatureSet] = []
  private var workflowAnalysisRegionRequests: [PixelRect?] = []
  private var sceneAnalysisRegionRequests: [PixelRect?] = []
  private var penCapColorRequests: [PenCapColor] = []
  private var discoverCalls = 0
  private var selectCalls = 0
  private var startCalls = 0

  var inspectionCallCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return inspectionCount
  }

  var startupActionCounts: (discover: Int, select: Int, start: Int) {
    lock.lock()
    defer { lock.unlock() }
    return (discoverCalls, selectCalls, startCalls)
  }

  func discoverResponse() -> CameraCaptureSnapshot {
    lock.lock()
    discoverCalls += 1
    lock.unlock()
    return snapshot
  }

  func selectResponse() -> CameraCaptureSnapshot {
    lock.lock()
    selectCalls += 1
    lock.unlock()
    return snapshot
  }

  func startResponse() -> CameraCaptureSnapshot {
    lock.lock()
    startCalls += 1
    lock.unlock()
    return snapshot
  }

  init(
    rotatesConfiguration: Bool = false,
    providesInspectionOverlay: Bool = false,
    providesAutomaticAnalysisResult: Bool = false,
    capCentroidXOffsets: [Double] = []
  ) throws {
    self.rotatesConfiguration = rotatesConfiguration
    self.providesInspectionOverlay = providesInspectionOverlay
    self.providesAutomaticAnalysisResult = providesAutomaticAnalysisResult
    self.capCentroidXOffsets = capCentroidXOffsets
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

  func inspection(
    after captureBoundary: UInt64,
    features: SceneFeatureSet = [.penCap],
    analysisRegion: PixelRect? = nil
  ) throws -> LiveSceneInspection {
    lock.lock()
    inspectionCount += 1
    workflowFeatureRequests.append(features)
    workflowAnalysisRegionRequests.append(analysisRegion)
    let centroidOffset = capCentroidXOffsets.isEmpty
      ? 0
      : capCentroidXOffsets[(inspectionCount - 1) % capCentroidXOffsets.count]
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
    let overlays =
      providesInspectionOverlay
      ? [
        CameraOverlayMeasurement(
          frameID: fresh.frame.id,
          cameraConfigurationID: inspectionConfigurationID,
          geometry: .point(try Point2(x: 99 + centroidOffset, y: 52)),
          provenance: CameraMeasurementProvenance(
            kind: .penCap,
            source: .measured,
            algorithmRevision: "workspace-test-v1"
          )
        )
      ] : []
    let cap = PenCapMeasurement(
      pixelCount: 10,
      boundingBox: PixelRect(x: 98, y: 48, width: 2, height: 4),
      centroid: try Point2(x: 99 + centroidOffset, y: 50),
      confidence: 0.9
    )
    let diagnostics = PenCapDiagnostics(
      inspectedPixelCount: 100,
      thresholdPixelCount: 10,
      componentCount: 1,
      candidates: []
    )
    let measurement = PlotterSceneMeasurement(
      frameID: fresh.frame.id,
      frameSHA256: fresh.frame.contentSHA256,
      cameraConfigurationID: inspectionConfigurationID,
      penCap: .found(cap, diagnostics: diagnostics),
      armatureEnvelope: .notRequested,
      overlays: overlays,
      algorithmRevision: "workspace-test-v1",
      diagnosticSHA256: fresh.frame.contentSHA256,
      computation: SceneVisionComputationDiagnostics(
        requestedFeatures: [.penCap],
        expandedFeatures: [.penCap],
        executionCounts: [.penCap: 1],
        inspectedPixelCounts: [.penCap: 100]
      )
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

  var recordedAutomaticFeatureRequests: [SceneFeatureSet] {
    lock.lock()
    defer { lock.unlock() }
    return automaticFeatureRequests
  }

  var recordedWorkflowFeatureRequests: [SceneFeatureSet] {
    lock.lock()
    defer { lock.unlock() }
    return workflowFeatureRequests
  }

  var recordedWorkflowAnalysisRegionRequests: [PixelRect?] {
    lock.lock()
    defer { lock.unlock() }
    return workflowAnalysisRegionRequests
  }

  var recordedSceneAnalysisRegionRequests: [PixelRect?] {
    lock.lock()
    defer { lock.unlock() }
    return sceneAnalysisRegionRequests
  }

  var recordedPenCapColorRequests: [PenCapColor] {
    lock.lock()
    defer { lock.unlock() }
    return penCapColorRequests
  }

  func setSceneAnalysisRegion(_ region: PixelRect?) {
    lock.lock()
    sceneAnalysisRegionRequests.append(region)
    lock.unlock()
  }

  func setPenCapColor(_ color: PenCapColor) {
    lock.lock()
    penCapColorRequests.append(color)
    lock.unlock()
  }

  func setAutomaticInspection(
    _ cadence: VisionAnalysisCadence?,
    features: SceneFeatureSet
  ) -> PlotterSceneAnalysisSnapshot {
    lock.lock()
    automaticInspectionRequests.append(cadence)
    automaticFeatureRequests.append(features)
    lock.unlock()
    let latestResult =
      providesAutomaticAnalysisResult
      ? try? inspection(after: 100).asAnalysisResult
      : nil
    return PlotterSceneAnalysisSnapshot(
      state: cadence.map(PlotterSceneAnalysisState.running) ?? .stopped,
      submittedFrameCount: latestResult == nil ? 0 : 1,
      analyzedFrameCount: latestResult == nil ? 0 : 1,
      supersededFrameCount: 0,
      failedFrameCount: 0,
      activeFrameSequence: nil,
      pendingFrameSequence: nil,
      latestResult: latestResult,
      lastError: nil
    )
  }
}

extension LiveSceneInspection {
  fileprivate var asAnalysisResult: PlotterSceneAnalysisResult {
    PlotterSceneAnalysisResult(
      displayedFrame: displayedFrame,
      measurement: measurement,
      analysisDurationNanoseconds: 1,
      completedNanoseconds: displayedFrame.frame.captureNanoseconds + 1
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

func frame(
  id: String,
  sequence: UInt64,
  capture: UInt64,
  configurationID: CameraConfigurationID
) throws -> StampedFrame {
  let width = 9
  let height = 9
  let pixel = [UInt8(105), 185, 45, 255]
  return try StampedFrame(
    id: FrameID(rawValue: id),
    sequence: sequence,
    captureNanoseconds: capture,
    cameraConfigurationID: configurationID,
    width: width,
    height: height,
    rowBytes: width * 4,
    pixelFormat: .bgra8,
    bytes: OwnedFrameBytes(Array(repeating: pixel, count: width * height).flatMap { $0 })
  )
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
    suspended = false
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
