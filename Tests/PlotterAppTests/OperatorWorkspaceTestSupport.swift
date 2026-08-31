import Foundation
import Observation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterTestSupport
import PlotterUI
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

private let defaultTestLearningPathItemID =
  LearningPathItemID.humanGuidedDiscovery(.penInteraction)

@MainActor
extension OperatorWorkspace {
  func testPlotterUIProjection(
    selectedItemID: LearningPathItemID = defaultTestLearningPathItemID,
    manualDraft: ManualMotionDraft = ManualMotionDraft(),
    includesLearningPath: Bool = false
  ) -> PlotterAppUIProjection {
    plotterUIProjection(
      selectedItemID: selectedItemID,
      manualDraft: manualDraft,
      includesLearningPath: includesLearningPath
    )
  }

  var testActionSurfacePresentation: ActionSurfacePresentation {
    testPlotterUIProjection().actionSurface
  }

  var testCurrentLearningPathItemID: LearningPathItemID {
    testPlotterUIProjection().currentLearningPathItemID
  }

  var testExercisePaneProtectionPresentation: ExercisePaneProtectionPresentation {
    testPlotterUIProjection().exercisePaneProtection
  }

  var testLearningIsEnabled: Bool {
    testPlotterUIProjection().learningIsEnabled
  }

  var testLearningModePresentation: LearningModePresentation {
    testPlotterUIProjection().learningMode
  }

  var testManualMotionEpisodePresentation: ManualMotionPresentation {
    testPlotterUIProjection().manualMotion
  }

  var testDrawingStudioPresentation: DrawingStudioPresentation {
    testPlotterUIProjection().drawingStudio
  }

  var testWorkbenchCapabilityPresentation: WorkbenchCapabilityPresentation {
    testPlotterUIProjection().workbenchCapability
  }

  func testLearningPathProjection(
    selectedItemID: LearningPathItemID
  ) -> LearningPathProjection {
    guard let projection = testPlotterUIProjection(
      selectedItemID: selectedItemID,
      includesLearningPath: true
    ).learningPath else {
      preconditionFailure("The test requested an included Learning projection.")
    }
    return projection
  }

  @discardableResult
  func submitTestPlotterUIAction(
    _ actionID: PlotterUIActionID,
    selectedItemID: LearningPathItemID = defaultTestLearningPathItemID,
    manualDraft: ManualMotionDraft = ManualMotionDraft(),
    overridingIntent: PlotterUIIntent? = nil
  ) async -> PlotterUIRequestDisposition? {
    let projection = testPlotterUIProjection(
      selectedItemID: selectedItemID,
      manualDraft: manualDraft,
      includesLearningPath: true
    ).semantic
    let request: PlotterUIRequest?
    if let overridingIntent {
      guard projection.action(id: actionID) != nil else {
        Issue.record("Missing test UI action \(actionID.rawValue).")
        return nil
      }
      request = PlotterUIRequest(
        id: PlotterUIRequestID(rawValue: UUID()),
        uiRevision: projection.revision,
        runtimeRevisions: projection.runtimeRevisions,
        actionID: actionID,
        intent: overridingIntent
      )
    } else {
      request = projection.request(for: actionID)
    }
    guard let request else {
      let action = projection.action(id: actionID)
      Issue.record(
        "Unavailable test UI action \(actionID.rawValue): \(action?.unavailableReason ?? "missing")"
      )
      return nil
    }
    let sink: any PlotterUIIntentSink = self
    return await sink.submitPlotterUIRequest(request)
  }

  func performTestExerciseAction(
    _ kind: ExerciseActionKind,
    for owner: LearningPathItemID
  ) async {
    await submitTestPlotterUIAction(
      PlotterAppUIActionID.retainedLearning(kind, owner: owner),
      selectedItemID: owner
    )
  }

  func submitTestManualJog(
    _ direction: JogDirection,
    manualDraft: ManualMotionDraft = ManualMotionDraft()
  ) async {
    let actionID = switch direction {
    case .xNegative: PlotterAppUIActionID.manualXNegative
    case .xPositive: PlotterAppUIActionID.manualXPositive
    case .yNegative: PlotterAppUIActionID.manualYNegative
    case .yPositive: PlotterAppUIActionID.manualYPositive
    }
    await submitTestPlotterUIAction(actionID, manualDraft: manualDraft)
  }

  func submitTestManualPen(_ command: PenCommand) async {
    await submitTestPlotterUIAction(
      command == .raise ? PlotterAppUIActionID.manualPenUp : PlotterAppUIActionID.manualPenDown
    )
  }

  func requestTestManualMotionStop(
    capabilityID: PlotterManualMotionStopCapabilityID
  ) async {
    await submitTestPlotterUIAction(
      PlotterAppUIActionID.manualStop,
      overridingIntent: .manualStop(capabilityID: capabilityID.rawValue)
    )
  }

  func recoverTestManualMotionPublication(
    capabilityID: PlotterManualMotionPublicationRecoveryCapabilityID
  ) async {
    await submitTestPlotterUIAction(
      PlotterAppUIActionID.manualRecovery,
      overridingIntent: .manualPublicationRecovery(capabilityID: capabilityID.rawValue)
    )
  }

  func resolveTestManualMotionEvidence(
    using action: PlotterManualMotionEvidenceDispositionAction
  ) async {
    await submitTestPlotterUIAction(
      PlotterAppUIActionID.manualEvidence,
      overridingIntent: .manualEvidenceDisposition(
        effectID: action.effectID.rawValue,
        environment: action.environment,
        observationID: action.observationID.rawValue,
        disposition: action.disposition == .acknowledgeAmbiguity
          ? .acknowledgeAmbiguity : .acknowledgePossibleInk
      )
    )
  }
}

/// App composition fixture whose effect authority remains inside the
/// production `PlotterCausalSimulatorEffectAdapter` owned by the workspace.
struct CausalSimulatorAppFixture {
  let workspace: OperatorWorkspace
  let simulator: CausalSimulatorProbe
  let penInteractionRuntime: PlotterPenInteractionRuntime
  let boundaryRuntime: PlotterBoundaryRuntime
}

/// Read-only causal truth plus explicit fault injection. This probe cannot
/// admit, execute, Stop, cancel, or settle a simulator effect.
struct CausalSimulatorProbe: Sendable {
  private let runtime: SimulatedLearningRuntime

  init(runtime: SimulatedLearningRuntime) {
    self.runtime = runtime
  }

  func snapshot() async -> SimulatedLearningSnapshot {
    await runtime.snapshot()
  }

  func persistentInk() async -> [SimulatedLearningInkSegment] {
    await runtime.persistentInk()
  }

  func capToTipPixelOffsetTruth() async -> Vector2<CameraPixelSpace> {
    await runtime.capToTipPixelOffsetTruth()
  }

  func injectFault(_ fault: SimulatedLearningFault) async {
    await runtime.injectFault(fault)
  }
}

func nominalDrawingDraftRuntime(
  paperPersistence: any PlotterDrawingDraftPaperPersistence =
    PlotterDrawingDraftTransientPaperPersistence()
) -> PlotterDrawingDraftRuntime {
  PlotterDrawingDraftRuntime(paperPersistence: paperPersistence)
}

func nominalIncidentPackageUIService() -> PlotterIncidentPackageUIService {
  PlotterIncidentPackageUIService(
    sourceProvider: PlotterIncidentPackageUIUnavailableSourceProvider()
  )
}

func nominalDrawingRunComposition(
  machineActions: OperatorWorkspace.MachineActions? = nil,
  cameraActions: OperatorWorkspace.CameraActions? = nil
) -> PlotterDrawingRunComposition {
  PlotterDrawingRunComposition.make(
    machineActions: machineActions ?? MachineSessionComposition.actions,
    cameraActions: cameraActions ?? CameraComposition.makeIsolatedActionsForTesting()
  )
}

func nominalPenInteractionRuntime(
  machineActions: OperatorWorkspace.MachineActions? = nil,
  manualMotionComposition: PlotterManualMotionRuntimeComposition? = nil
) -> PlotterPenInteractionRuntime {
  let composition = manualMotionComposition
    ?? PlotterManualMotionComposition.makeRuntimeComposition(
      journalFileURL: FileManager.default.temporaryDirectory.appendingPathComponent(
        "pen-interaction-test-\(UUID().uuidString).json"
      ),
      machineActions: machineActions,
      simulatedRuntime: SimulatedLearningRuntime(),
      simulatedExecutionPacing: SimulatedLearningInteractivePacing(stepDelay: .zero)
    )
  return PlotterPenInteractionComposition.makeRuntime(
    machineActions: machineActions,
    simulatedAdapter: composition.causalSimulatorEffectAdapter,
    nowNanoseconds: { 1 }
  )
}

private struct NominalBoundaryFactSource: PlotterBoundaryFactSource {
  func currentBoundaryFacts(for environment: PlotterEnvironment) async
    -> PlotterBoundaryExternalFacts
  {
    PlotterBoundaryExternalFacts(
      environment: environment,
      learningEnabled: false,
      controllerSessionEstablished: false,
      motionAuthorized: false,
      foreignLowerOperationInFlight: false,
      stickyAmbiguity: nil,
      controllerSessionID: UUID(),
      coordinateRevision: 0,
      machinePosition: nil,
      interpreterIsIdle: true,
      passiveProbe: nil,
      penActuationProfile: .initialDefaults,
      semanticIdentity: LearningPathSemanticIdentity(
        machineGeometry: MachineGeometryIdentity(),
        toolAssembly: ToolAssemblyRevision(),
        penContactProfile: PenContactProfileRevision(),
        paperInstance: PaperInstanceRevision(),
        paperContactPlane: PaperContactPlaneRevision(),
        cameraMountRevision: UUID(),
        cameraReframingRevision: UUID()
      )
    )
  }
}

private actor NominalBoundaryEffectPort: PlotterBoundaryEffectPort {
  func preparePenUp(
    environment _: PlotterEnvironment,
    profile _: PenActuationProfile
  ) -> Result<Void, PlotterBoundaryLowerPortFailure> {
    .failure(.init(detail: "No Boundary effect port is configured for this test."))
  }

  func prepareSideAdvisory(
    environment _: PlotterEnvironment,
    direction _: PlotterBoundaryDirection
  ) -> Result<Void, PlotterBoundaryLowerPortFailure> {
    .failure(.init(detail: "No Boundary advisory port is configured for this test."))
  }

  func admitSide(
    environment _: PlotterEnvironment,
    direction _: PlotterBoundaryDirection
  ) -> PlotterBoundaryLowerAdmission {
    .refused("No Boundary effect port is configured for this test.")
  }

  func admitCenterTravel(
    environment _: PlotterEnvironment,
    delta _: Vector2<MachineSpace>
  ) -> PlotterBoundaryLowerAdmission {
    .refused("No Boundary effect port is configured for this test.")
  }

  func waitForTerminal(
    _ handle: PlotterBoundaryLowerHandle
  ) -> PlotterBoundaryLowerTerminal {
    .refused("No Boundary effect port is configured for this test.", finalPosition: nil)
  }

  func requestCancellation(
    _ intent: PlotterBoundaryCancellationIntent,
    handle: PlotterBoundaryLowerHandle
  ) {}
}

private struct NominalBoundaryPersistencePort: PlotterBoundaryPersistencePort {
  func persistBoundaryCandidate(_ candidate: PlotterBoundaryPersistenceCandidate) async throws {}
}

func nominalBoundaryRuntime() -> PlotterBoundaryRuntime {
  PlotterBoundaryRuntime(
    factSource: NominalBoundaryFactSource(),
    effectPort: NominalBoundaryEffectPort(),
    persistencePort: NominalBoundaryPersistencePort()
  )
}

func nominalAcceptedLearningPathCheckpointActions()
  -> OperatorWorkspace.AcceptedLearningPathCheckpointActions
{
  .init(load: { .absent }, save: { _ in }, clear: {})
}

@MainActor
final class TestBoundaryRuntimeAccess {
  private(set) var runtime: PlotterBoundaryRuntime?

  func install(_ runtime: PlotterBoundaryRuntime) {
    precondition(self.runtime == nil)
    self.runtime = runtime
  }
}

@MainActor
extension OperatorWorkspace {
  var testAcceptedBoundaryAggregates: [BoundaryDirection: BoundarySideAggregate] {
    currentBoundarySnapshot?.acceptedAggregates ?? [:]
  }

  var testAcceptedBoundaryEvidence: [BoundarySideAttemptEvidence] {
    currentBoundarySnapshot?.acceptedEvidence ?? []
  }

  var testBoundaryEvidenceByAttemptID: [ExerciseAttemptID: BoundarySideAttemptEvidence] {
    Dictionary(uniqueKeysWithValues: testAcceptedBoundaryEvidence.map { ($0.attemptID, $0) })
  }

  var testPairedBoundaryProgress: PairedBoundaryProgress {
    currentBoundarySnapshot?.pairedProgress ?? PairedBoundaryProgress()
  }

  var testEstimatedMachineCenter: EstimatedMachineCenter? {
    currentBoundarySnapshot?.estimatedCenter
  }

  var testLearnedLocalCoordinateFrame: LearnedLocalCoordinateFrame? {
    currentBoundarySnapshot?.localCoordinateFrame
  }

  var testCenterArrivalPosition: MachinePosition? {
    currentBoundarySnapshot?.centerArrivalPosition
  }

  var testBoundaryCenterArrivalRetryRequired: Bool {
    currentBoundarySnapshot?.projection.centerArrivalRetryRequired == true
  }

  var testBoundaryTerminals: [PlotterBoundaryTerminal] {
    currentBoundarySnapshot?.attemptTerminals ?? []
  }

  var testSelectedBoundaryDirection: BoundaryDirection? {
    currentBoundarySnapshot?.projection.selectedDirection.lowerDirection
  }

}

private extension PlotterBoundaryDirection {
  var lowerDirection: BoundaryDirection? {
    BoundaryDirection(rawValue: rawValue)
  }
}

func sequenceIDForTest(_ direction: BoundaryDirection) -> DiscoverySequenceID {
  switch direction {
  case .negativeX: .boundaryNegativeX
  case .positiveX: .boundaryPositiveX
  case .negativeY: .boundaryNegativeY
  case .positiveY: .boundaryPositiveY
  }
}

func boundaryEpisodeDirection(_ direction: BoundaryDirection) -> PlotterBoundaryDirection {
  PlotterBoundaryDirection(rawValue: direction.rawValue)!
}

@MainActor
func makeCausalSimulatorAppFixture(
  cameraActions: OperatorWorkspace.CameraActions? = nil,
  workflowTelemetry: WorkflowTelemetryFixture? = nil,
  learningPathCheckpointActions: OperatorWorkspace.AcceptedLearningPathCheckpointActions? = nil,
  tipCalibrationSemanticIdentities: TipCalibrationSemanticIdentityState = .ephemeral(),
  drawingDraftRuntime: PlotterDrawingDraftRuntime = nominalDrawingDraftRuntime(),
  simulatedExecutionPacing: any SimulatedLearningExecutionPacing =
    SimulatedLearningInteractivePacing(stepDelay: .zero)
) -> CausalSimulatorAppFixture {
  let clock = TestClock()
  // Workspace state-machine tests need causal pixels and viable vision
  // geometry, not the production simulator's default presentation footprint.
  // Its simulator truth must exactly match acceptedBoundaryTestCheckpoint so
  // every accepted Boundary-derived sparse-tip point remains in the exact frame.
  // Dedicated runtime/renderer tests retain exact 640x480 coverage.
  let runtime = SimulatedLearningRuntime(
    boundaryTruth: SimulatedLearningBoundaryTruth(
      negativeXMM: -100,
      positiveXMM: 100,
      negativeYMM: -50,
      positiveYMM: 50
    ),
    frameWidth: 320,
    frameHeight: 240,
    paddingPixels: 14,
    toolPaperRevision: tipCalibrationSemanticIdentities.paperInstance.rawValue
  )
  let manualMotionComposition = PlotterManualMotionComposition.makeRuntimeComposition(
    journalFileURL: FileManager.default.temporaryDirectory.appendingPathComponent(
      "causal-simulator-app-fixture-\(UUID().uuidString).json"
    ),
    machineActions: nil,
    simulatedRuntime: runtime,
    simulatedExecutionPacing: simulatedExecutionPacing
  )
  let resolvedCameraActions =
    cameraActions ?? CameraComposition.makeIsolatedActionsForTesting()
  let penInteractionRuntime = nominalPenInteractionRuntime(
    manualMotionComposition: manualMotionComposition
  )
  let checkpointActions = learningPathCheckpointActions
    ?? nominalAcceptedLearningPathCheckpointActions()
  let boundaryComposition = PlotterBoundaryComposition.make(
    machineActions: MachineSessionComposition.actions,
    causalSimulator: manualMotionComposition.causalSimulatorEffectAdapter,
    checkpointActions: checkpointActions
  )
  let workspace = OperatorWorkspace(
      machineActions: nil,
      cameraActions: resolvedCameraActions,
      manualMotionComposition: manualMotionComposition,
      penInteractionRuntime: penInteractionRuntime,
      boundaryRuntime: boundaryComposition.runtime,
      acceptedLearningPathCheckpointActions: learningPathCheckpointActions,
      drawingDraftRuntime: drawingDraftRuntime,
      drawingRunComposition: nominalDrawingRunComposition(
        cameraActions: resolvedCameraActions
      ),
      incidentPackageUIService: nominalIncidentPackageUIService(),
      tipCalibrationSemanticIdentities: tipCalibrationSemanticIdentities,
      workflowTelemetryActions: workflowTelemetry.map { fixture in
        .init(record: { await fixture.record($0) })
      },
      serialDevices: [],
      serialDeviceDiscovery: { [] },
      loadSelectedSerialIdentifier: { nil },
      persistSelectedSerialIdentifier: { _ in },
      loadPenCapAppearanceSelection: { testPenCapAppearanceSelection() },
      persistPenCapAppearanceSelection: { _ in },
      loadOverlayPreference: { Set(UserSceneOverlay.allCases) },
      persistOverlayPreference: { _ in },
      nowNanoseconds: { clock.next() }
    )
  boundaryComposition.install(on: workspace)
  return CausalSimulatorAppFixture(
    workspace: workspace,
    simulator: CausalSimulatorProbe(runtime: runtime),
    penInteractionRuntime: penInteractionRuntime,
    boundaryRuntime: boundaryComposition.runtime
  )
}

@MainActor
func requireEnabledPublicAction(
  _ kind: ExerciseActionKind,
  owner: LearningPathItemID,
  workspace: OperatorWorkspace
) throws {
  let presentation = workspace.selectedOperatorActionPresentation(for: owner)
  let action = try #require(
    presentation.actionStrip?.actions.first(where: { $0.kind == kind }),
    "Missing public action \(kind); visible actions: \(String(describing: presentation.actionStrip?.actions.map(\.kind))); exploration error: \(workspace.explorationError ?? "nil")"
  )
  #expect(action.isEnabled)
}

func manualEpisodeJog(
  _ request: RelativeJogRequest,
  routing: PlotterManualJogRouting? = nil
) throws -> PlotterManualMotionIntent {
  let direction: PlotterJogDirection
  let distance: Double
  if request.delta.dy == 0, request.delta.dx != 0 {
    direction = request.delta.dx > 0 ? .positiveX : .negativeX
    distance = abs(request.delta.dx)
  } else if request.delta.dx == 0, request.delta.dy != 0 {
    direction = request.delta.dy > 0 ? .positiveY : .negativeY
    distance = abs(request.delta.dy)
  } else {
    throw PlotterIntentValidationError.invalidJogDistance
  }
  return .jog(try PlotterJogRequest(
    direction: direction,
    distanceMM: distance,
    feedMMPerMinute: request.feedMMPerMinute,
    routing: routing
      ?? (request.permitsUnknownPenStateAsPossibleInk ? .possibleInk : .relativeTravel)
  ))
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
    "Missing direction selection; discovery error: \(workspace.discoveryError ?? "nil"); exploration error: \(workspace.explorationError ?? "nil"); terminals: \(workspace.testBoundaryTerminals)"
  )
  #expect(selection.purpose == purpose)
  #expect(selection.options.contains(direction))
  await workspace.performTestExerciseAction(
    .boundary(.selectDirection(boundaryEpisodeDirection(direction))),
    for: owner
  )
}

@MainActor
func submitRenderedBoundaryAcquisition(
  _ direction: BoundaryDirection,
  mode: PlotterBoundaryAttemptMode = .normal,
  owner: LearningPathItemID,
  workspace: OperatorWorkspace
) async throws {
  try await selectPublicDirection(
    direction,
    purpose: .boundary,
    owner: owner,
    workspace: workspace
  )
  let kind = ExerciseActionKind.boundary(
    .acquire(direction: boundaryEpisodeDirection(direction), mode: mode)
  )
  try requireEnabledPublicAction(kind, owner: owner, workspace: workspace)
  await workspace.performTestExerciseAction(kind, for: owner)
}

@MainActor
func renderedBoundaryStopKind(
  owner: LearningPathItemID,
  workspace: OperatorWorkspace
) throws -> ExerciseActionKind {
  let kind = try #require(
    workspace.selectedOperatorActionPresentation(for: owner).actionStrip?.actions.first {
      if case .boundary(.stop(_)) = $0.kind { return true }
      return false
    }?.kind,
    "Missing exact rendered Boundary Stop action."
  )
  try requireEnabledPublicAction(kind, owner: owner, workspace: workspace)
  return kind
}

@MainActor
func submitRenderedBoundaryStop(
  owner: LearningPathItemID,
  workspace: OperatorWorkspace
) async throws {
  await workspace.performTestExerciseAction(
    try renderedBoundaryStopKind(owner: owner, workspace: workspace),
    for: owner
  )
}

@MainActor
func waitForBoundaryTerminalCount(
  _ count: Int,
  workspace: OperatorWorkspace
) async throws {
  try await BoundaryTerminalObservationWaiter(count: count, workspace: workspace).wait()
}

@MainActor
private final class BoundaryTerminalObservationWaiter {
  private enum WaitError: Error {
    case timedOut
  }

  private let count: Int
  private let workspace: OperatorWorkspace
  private var continuation: CheckedContinuation<Void, any Error>?
  private var deadlineTask: Task<Void, Never>?

  init(count: Int, workspace: OperatorWorkspace) {
    self.count = count
    self.workspace = workspace
  }

  func wait() async throws {
    try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      observe()
      deadlineTask = Task { @MainActor [weak self] in
        do {
          try await ContinuousClock().sleep(for: .seconds(2))
        } catch {
          return
        }
        self?.finish(.failure(WaitError.timedOut))
      }
    }
  }

  private func observe() {
    guard continuation != nil else { return }
    let reachedCount = withObservationTracking {
      _ = workspace.semanticPresentationRevision
      return workspace.testBoundaryTerminals.count >= count
        && workspace.currentBoundarySnapshot?.projection.reference.operationID == nil
        && workspace.currentBoundarySnapshot?.projection.cancellationCapabilityID == nil
    } onChange: { [weak self] in
      Task { @MainActor in self?.observe() }
    }
    if reachedCount {
      finish(.success(()))
    }
  }

  private func finish(_ result: Result<Void, any Error>) {
    guard let continuation else { return }
    self.continuation = nil
    deadlineTask?.cancel()
    deadlineTask = nil
    continuation.resume(with: result)
  }
}

@MainActor
func waitForAcceptedBoundaryCenterArrival(
  workspace: OperatorWorkspace
) async throws {
  try await BoundaryCenterTerminalObservationWaiter(workspace: workspace).wait()
}

@MainActor
private final class BoundaryCenterTerminalObservationWaiter {
  private enum WaitError: Error {
    case timedOut
  }

  private let workspace: OperatorWorkspace
  private var continuation: CheckedContinuation<Void, any Error>?
  private var deadlineTask: Task<Void, Never>?

  init(workspace: OperatorWorkspace) {
    self.workspace = workspace
  }

  func wait() async throws {
    try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      observe()
      deadlineTask = Task { @MainActor [weak self] in
        do {
          try await ContinuousClock().sleep(for: .seconds(2))
        } catch {
          return
        }
        self?.finish(.failure(WaitError.timedOut))
      }
    }
  }

  private func observe() {
    guard continuation != nil else { return }
    let arrived = withObservationTracking {
      _ = workspace.semanticPresentationRevision
      let projection = workspace.currentBoundarySnapshot?.projection
      return projection?.terminal?.activity == .centerArrival
        && projection?.terminal?.disposition == .accepted
        && projection?.reference.operationID == nil
        && projection?.cancellationCapabilityID == nil
        && workspace.testCenterArrivalPosition != nil
    } onChange: { [weak self] in
      Task { @MainActor in self?.observe() }
    }
    if arrived {
      finish(.success(()))
    }
  }

  private func finish(_ result: Result<Void, any Error>) {
    guard let continuation else { return }
    self.continuation = nil
    deadlineTask?.cancel()
    deadlineTask = nil
    continuation.resume(with: result)
  }
}

func acceptedBoundaryTestCheckpoint(
  centerArrivalIsAccepted: Bool = true,
  controllerSessionID: UUID = UUID(),
  coordinateRevision: UInt64 = 1,
  controllerProbe: PassiveProbeResult? = nil
) throws -> AcceptedMachineArtifactCheckpoint {
  let samples: [(BoundaryDirection, MachinePosition)] = [
    (.negativeX, try MachinePosition(x: -100, y: 0)),
    (.positiveX, try MachinePosition(x: 100, y: 0)),
    (.negativeY, try MachinePosition(x: 0, y: -50)),
    (.positiveY, try MachinePosition(x: 0, y: 50)),
  ]
  var evidence: [BoundarySideAttemptEvidence] = []
  var aggregates: [BoundarySideAggregate] = []
  var progress = PairedBoundaryProgress()
  var revisions: [LearningArtifactRevision] = []
  for (index, sample) in samples.enumerated() {
    let attemptID = ExerciseAttemptID()
    let revisionID = LearningArtifactRevisionID()
    let observation = try BoundarySideAttemptEvidence(
      attemptID: attemptID,
      direction: sample.0,
      controllerSessionID: controllerSessionID,
      coordinateRevision: coordinateRevision,
      ownerID: BoundaryMotionOwnerID(),
      stopCapabilityID: UUID(),
      stopIntent: .operatorStop,
      finalPosition: sample.1,
      disposition: .succeeded
    )
    let compatibility = BoundaryNumericCompatibility(
      direction: sample.0,
      controllerSessionID: controllerSessionID,
      coordinateRevision: coordinateRevision,
      numericEstimatorRevision: "boundary-machine-coordinate-v1"
    ).attemptCompatibility
    var history = try ExerciseAttemptHistory<BoundarySideAttemptEvidence>(
      compatibility: compatibility
    )
    try history.record(
      ExerciseAttempt(
        id: attemptID,
        disposition: .succeeded,
        compatibility: compatibility,
        acceptedSequence: UInt64(index + 1),
        value: observation
      )
    )
    let aggregate = try BoundarySideAggregate(
      direction: sample.0,
      revisionID: revisionID,
      history: history
    )
    try progress.accept(sample.0, revisionID: revisionID)
    evidence.append(observation)
    aggregates.append(aggregate)
    revisions.append(
      LearningArtifactRevision(
        id: revisionID,
        kind: .boundarySideAggregate(sample.0),
        attemptID: attemptID,
        disposition: .succeeded,
        state: .current
      )
    )
  }
  let center = try EstimatedMachineCenter.derive(from: aggregates)
  let frame = try LearnedLocalCoordinateFrame.derive(from: aggregates)
  let centerAttemptID = ExerciseAttemptID()
  let centerRevision = LearningArtifactRevision(
    kind: .estimatedMachineCenter,
    attemptID: centerAttemptID,
    disposition: .succeeded,
    consumedRevisionIDs: center.consumedRevisionIDs,
    state: .current
  )
  revisions.append(centerRevision)
  let centerPosition = MachinePosition(point: center.point)
  if centerArrivalIsAccepted {
    revisions.append(
      LearningArtifactRevision(
        kind: .centerArrival,
        attemptID: centerAttemptID,
        disposition: .succeeded,
        consumedRevisionIDs: [centerRevision.id],
        state: .current
      )
    )
  }
  return try AcceptedMachineArtifactCheckpoint(
    controllerContext: ControllerCheckpointContext(
      probe: controllerProbe ?? boundaryCheckpointProbe(position: centerPosition)
    ),
    machinePositionAtSave: centerPosition,
    controllerSessionID: controllerSessionID,
    coordinateRevision: coordinateRevision,
    acceptedAttemptSequence: 4,
    pairedBoundaryProgress: progress,
    acceptedBoundaryEvidence: evidence,
    acceptedBoundaryAggregates: aggregates,
    estimatedMachineCenter: center,
    learnedLocalCoordinateFrame: frame,
    centerArrivalPosition: centerArrivalIsAccepted ? centerPosition : nil,
    acceptedRevisions: revisions
  )
}

func acceptedPenLearningTestCheckpoint(
  identity: LearningPathSemanticIdentity
) throws -> AcceptedLearningPathCheckpoint {
  let attemptID = ExerciseAttemptID()
  let revision = LearningArtifactRevision(
    kind: .penInteraction,
    attemptID: attemptID,
    disposition: .succeeded,
    state: .current
  )
  let evidence = PenInteractionAttemptEvidence(
    actuationProfile: .initialDefaults,
    confirmedUpPositions: [],
    confirmedUpSpindleValues: [],
    confirmedUpControllerOutcomes: [],
    confirmedUpTimestamps: [],
    confirmedDownPositions: [],
    confirmedDownSpindleValues: [],
    confirmedDownControllerOutcomes: [],
    confirmedDownTimestamps: []
  )
  return try AcceptedLearningPathCheckpoint(
    semanticIdentity: identity,
    penInteraction: AcceptedPenInteractionCheckpoint(
      revision: revision,
      acceptedSequence: 1,
      evidence: evidence
    )
  )
}

func boundaryCheckpointProbe(position: MachinePosition) -> PassiveProbeResult {
  let descriptor = MachineLinkDescriptor(
    identifier: "/dev/cu.boundary-checkpoint-test",
    displayName: "Boundary Checkpoint Test",
    bsdPath: "/dev/cu.boundary-checkpoint-test",
    transport: .bsdSerial
  )
  let reports: [(PassiveQuery, [String])] = [
    (.buildInfo, ["[VER:1.1h.20200101:boundary-checkpoint-test]"]),
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

@MainActor
func installAcceptedBoundaryTestProjection(
  runtime: PlotterBoundaryRuntime,
  workspace: OperatorWorkspace,
  environment: PlotterEnvironment,
  centerArrivalIsAccepted: Bool = true
) async throws {
  let facts = workspace.currentBoundaryExternalFacts(for: environment)
  let checkpoint = try acceptedBoundaryTestCheckpoint(
    centerArrivalIsAccepted: centerArrivalIsAccepted,
    controllerSessionID: facts.controllerSessionID,
    coordinateRevision: facts.coordinateRevision,
    controllerProbe: facts.passiveProbe
  )
  try await runtime.restore(checkpoint, environment: environment)
  workspace.installBoundarySnapshot(await runtime.snapshot(for: environment))
}

@MainActor
func completeSimulatedPenInteractionPrerequisite(
  _ workspace: OperatorWorkspace
) async throws {
  await workspace.switchFrameMode(.simulated)
  await workspace.performControllerConnectionAction()
  await workspace.activateMotionGuard()
  let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
  try requireEnabledPublicAction(.start, owner: owner, workspace: workspace)
  await workspace.performTestExerciseAction(.start, for: owner)
  let request = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
  let displayed = try #require(workspace.testActionSurfacePresentation.displayedFrame)
  let fallback = try Point2<CameraPixelSpace>(
    x: Double(displayed.frame.width - 1) / 2,
    y: Double(displayed.frame.height - 1) / 2
  )
  let point = workspace.testActionSurfacePresentation.overlays.compactMap {
    overlay -> Point2<CameraPixelSpace>? in
    guard overlay.provenance.kind == .penCap, case .point(let point) = overlay.geometry else {
      return nil
    }
    return point
  }.first ?? fallback
  submitPointSelection(workspace, request: request, point: point)
  try await waitUntil {
    workspace.activeDiscoverySequenceID == .penInteraction || workspace.discoveryError != nil
  }
  for _ in 0..<8 where !workspace.penInteractionCompleted {
    try requireEnabledPublicAction(.choice(.yes), owner: owner, workspace: workspace)
    await workspace.performTestExerciseAction(.choice(.yes), for: owner)
  }
  #expect(workspace.penInteractionCompleted)
}

@MainActor
func completeSimulatedSparseTipCalibration(
  _ workspace: OperatorWorkspace,
  simulator: CausalSimulatorProbe
) async throws {
  let registrationOwner = LearningPathItemID.humanGuidedDiscovery(
    .calibrateCameraAndVisibleCap
  )
  try requireEnabledPublicAction(
    .runCameraCalibrationAndBuildProposal,
    owner: registrationOwner,
    workspace: workspace
  )
  await workspace.performTestExerciseAction(
    .runCameraCalibrationAndBuildProposal,
    for: registrationOwner
  )
  try requireEnabledPublicAction(
    .acceptCameraCalibrationProposal,
    owner: registrationOwner,
    workspace: workspace
  )
  await workspace.performTestExerciseAction(.acceptCameraCalibrationProposal, for: registrationOwner)
  let tipOwner = LearningPathItemID.humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
  let truthOffset = await simulator.capToTipPixelOffsetTruth()
  #expect(abs(truthOffset.dx) + abs(truthOffset.dy) > 0)
  let registration = try #require(workspace.machineCameraRegistration)
  let plan = try SparseTipBatchMarkPlan(
    acceptedBoundaryAggregates: workspace.testAcceptedBoundaryAggregates
  )
  try requireEnabledPublicAction(
    .drawFourCornerTipCircles,
    owner: tipOwner,
    workspace: workspace
  )
  await workspace.performTestExerciseAction(.drawFourCornerTipCircles, for: tipOwner)
  let request = try #require(
    workspace.testActionSurfacePresentation.pointSelectionRequest,
    "missing five-click selection request: \(workspace.explorationError ?? "no error")"
  )
  let exactRequest = try #require(
    workspace.pointSelectionEpisodeProjection.exactPointSelection.request
  )
  try #require(request == exactRequest)
  try #require(request.purpose == .toolContact)
  try #require(request.requiredPointCount == 4)
  let clicks = try plan.marks.map { mark in
    let capPoint = try registration.fit.cameraPoint(from: mark.machinePosition.point)
    return try capPoint.translated(by: truthOffset)
  }
  for truthPoint in [clicks[3], clicks[1], clicks[0], clicks[2]] {
    try await submitPointSelectionAndWait(
      workspace,
      request: request,
      point: truthPoint
    )
  }
  try requireEnabledPublicAction(
    .acceptTipCalibrationProposal,
    owner: tipOwner,
    workspace: workspace
  )
  await workspace.performTestExerciseAction(.acceptTipCalibrationProposal, for: tipOwner)
}

@MainActor
func completeSimulatedStageFour(_ workspace: OperatorWorkspace) async throws {
  let owner = LearningPathItemID.observedDrawingTrial(.chooseDrawingBorderPlan)
  try requireEnabledPublicAction(
    .start,
    owner: owner,
    workspace: workspace
  )
  await workspace.performTestExerciseAction(.start, for: owner)
  #expect(workspace.drawingTrialAssessment == .predictionObserved)
}

@MainActor
func submitPointSelection(
  _ workspace: OperatorWorkspace,
  request: PlotterPointSelectionRequest,
  point: Point2<CameraPixelSpace>
) {
  workspace.submitPointSelection(
    PlotterPointSelectionSubmission(
      selectionID: request.id,
      frame: request.frame,
      point: point,
      presentationTransformRevision: request.presentationTransformRevision
    )
  )
}

@MainActor
func submitPointSelectionAndWait(
  _ workspace: OperatorWorkspace,
  request: PlotterPointSelectionRequest,
  point: Point2<CameraPixelSpace>
) async throws {
  let priorCount = workspace.pointSelectionEpisodeProjection.exactPointSelection.selectedPoints.count
  let acceptedCount = priorCount + 1
  let priorProjectionRevision = workspace.pointSelectionEpisodeProjection.projectionRevision
  let waiter = PointSelectionProjectionObservationWaiter(
    workspace: workspace,
    priorProjectionRevision: priorProjectionRevision,
    acceptedCount: acceptedCount,
    requiresProposal: acceptedCount == request.requiredPointCount
  )
  submitPointSelection(workspace, request: request, point: point)
  _ = try await waiter.wait()
}

private struct PointSelectionTestRefusal: Error, CustomStringConvertible {
  let owner: String?
  let reason: String
  let remedy: String?

  var description: String {
    "Point selection refused by \(owner ?? "unknown owner") [\(reason)]: \(remedy ?? "no remedy")"
  }
}

@MainActor
private final class PointSelectionProjectionObservationWaiter {
  private let workspace: OperatorWorkspace
  private let priorProjectionRevision: PlotterProjectionRevision
  private let acceptedCount: Int
  private let requiresProposal: Bool
  private var continuation: CheckedContinuation<PlotterEpisodeProjection, any Error>?
  private var deadlineTask: Task<Void, Never>?

  init(
    workspace: OperatorWorkspace,
    priorProjectionRevision: PlotterProjectionRevision,
    acceptedCount: Int,
    requiresProposal: Bool
  ) {
    self.workspace = workspace
    self.priorProjectionRevision = priorProjectionRevision
    self.acceptedCount = acceptedCount
    self.requiresProposal = requiresProposal
  }

  func wait() async throws -> PlotterEpisodeProjection {
    try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      observe()
      deadlineTask = Task { @MainActor [weak self] in
        do {
          try await ContinuousClock().sleep(for: .seconds(5))
        } catch {
          return
        }
        self?.finish(.failure(TestTimeout(
          conditionDescription: "point-selection projection publication"
        )))
      }
    }
  }

  private func observe() {
    guard continuation != nil else { return }
    let result = withObservationTracking { () -> Result<PlotterEpisodeProjection, any Error>? in
      _ = workspace.semanticPresentationRevision
      let projection = workspace.pointSelectionEpisodeProjection
      guard projection.projectionRevision > priorProjectionRevision else { return nil }
      let selectedCount = projection.exactPointSelection.selectedPoints.count
      if selectedCount >= acceptedCount,
        !requiresProposal || workspace.proposedTipCameraRegistration != nil
      {
        return .success(projection)
      }
      if let reason = projection.currentReason {
        return .failure(PointSelectionTestRefusal(
          owner: projection.authoritativeOwner?.rawValue,
          reason: reason,
          remedy: projection.remedy
        ))
      }
      return nil
    } onChange: { [weak self] in
      Task { @MainActor in self?.observe() }
    }
    if let result { finish(result) }
  }

  private func finish(_ result: Result<PlotterEpisodeProjection, any Error>) {
    guard let continuation else { return }
    self.continuation = nil
    deadlineTask?.cancel()
    deadlineTask = nil
    continuation.resume(with: result)
  }
}

func exactPointSelectionFrame(_ frame: DisplayedFrame) -> PlotterExactFrameReference {
  let source: PlotterExactFrameSource
  switch frame.source {
  case .live(let identity):
    source = .live(deviceID: identity.rawValue)
  case .simulated:
    source = .simulated
  }
  return PlotterExactFrameReference(
    frameID: frame.frame.id.rawValue,
    frameSHA256: frame.frame.contentSHA256,
    source: source,
    cameraConfigurationID: frame.frame.cameraConfigurationID,
    captureNanoseconds: frame.frame.captureNanoseconds,
    sequence: frame.frame.sequence,
    width: frame.frame.width,
    height: frame.frame.height,
    rowBytes: frame.frame.rowBytes,
    pixelFormat: PlotterExactFramePixelFormat(rawValue: frame.frame.pixelFormat.rawValue)!
  )
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
  learningPathCheckpointActions: OperatorWorkspace.AcceptedLearningPathCheckpointActions? = nil,
  drawingDraftRuntime: PlotterDrawingDraftRuntime = nominalDrawingDraftRuntime(),
  tipCalibrationSemanticIdentities: TipCalibrationSemanticIdentityState = .ephemeral(),
  workflowTelemetry: WorkflowTelemetryFixture? = nil,
  penInteractionRuntimeFactory:
    ((OperatorWorkspace.MachineActions, PlotterManualMotionRuntimeComposition)
      -> PlotterPenInteractionRuntime)? = nil,
  boundaryRuntimeAccess: TestBoundaryRuntimeAccess? = nil,
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
  let machineActions = OperatorWorkspace.MachineActions(
    select: { _ in await machine.snapshot() },
    snapshot: { await machine.snapshot() },
    requestPassiveProbe: {
      await machine.passiveProbeResult()
    },
    requestControllerAlarmClear: { .refused(.noCurrentAlarmEvidence) },
    activateMotionGuard: { await machine.activateMotionGuard() },
    deactivateMotionGuard: { await machine.deactivateMotionGuard() },
    beginRelativeJog: { request in
      .admitted(
        RelativeJogOperation(
          id: UUID(),
          task: Task { await machine.performRelativeMotion(request) }
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
    beginDrawingPlan: nil,
    beginPenActuation: { command, profile in
      .admitted(PenActuationOperation(
        id: UUID(),
        task: Task { await machine.requestPen(command, profile: profile) }
      ))
    },
    beginBoundaryMotion: beginBoundaryMotion,
    requestJogCancel: requestJogCancel,
    disconnect: {}
  )
  let resolvedCameraActions =
    cameraActionsOverride ?? camera.map { cameraActions($0) }
  let manualMotionComposition = PlotterManualMotionComposition.makeRuntimeComposition(
    journalFileURL: FileManager.default.temporaryDirectory.appendingPathComponent(
      "operator-workspace-test-\(UUID().uuidString).json"
    ),
    machineActions: machineActions,
    simulatedRuntime: SimulatedLearningRuntime(),
    simulatedExecutionPacing: SimulatedLearningInteractivePacing(stepDelay: .zero)
  )
  let penInteractionRuntime = penInteractionRuntimeFactory?(
    machineActions,
    manualMotionComposition
  ) ?? nominalPenInteractionRuntime(
    machineActions: machineActions,
    manualMotionComposition: manualMotionComposition
  )
  let checkpointActions = learningPathCheckpointActions
    ?? nominalAcceptedLearningPathCheckpointActions()
  let boundaryComposition = PlotterBoundaryComposition.make(
    machineActions: machineActions,
    causalSimulator: manualMotionComposition.causalSimulatorEffectAdapter,
    checkpointActions: checkpointActions
  )
  let workspace = OperatorWorkspace(
    machineActions: machineActions,
    cameraActions: resolvedCameraActions,
    manualMotionComposition: manualMotionComposition,
    penInteractionRuntime: penInteractionRuntime,
    boundaryRuntime: boundaryComposition.runtime,
    announcementActions: announcements.map { fixture in
      .init(
        announce: { await fixture.announce($0) },
        cancelForShutdown: { await fixture.cancelForShutdown() }
      )
    },
    acceptedLearningPathCheckpointActions: learningPathCheckpointActions,
    drawingDraftRuntime: drawingDraftRuntime,
    drawingRunComposition: nominalDrawingRunComposition(
      machineActions: machineActions,
      cameraActions: resolvedCameraActions
    ),
    incidentPackageUIService: nominalIncidentPackageUIService(),
    tipCalibrationSemanticIdentities: tipCalibrationSemanticIdentities,
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
  boundaryComposition.install(on: workspace)
  boundaryRuntimeAccess?.install(boundaryComposition.runtime)
  return workspace
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
    algorithmRevision: PlotterPenCapPointSampler.algorithmRevision
  )
}

enum SimulatorIsolationViolation: Error {
  case machineAction(String)
}

func cameraActions(
  _ fixture: CameraFixture,
  analysisUpdates: @escaping @Sendable () async -> AsyncStream<PlotterSceneAnalysisSnapshot> = {
    AsyncStream { $0.finish() }
  },
  inspectionGate: CameraInspectionGate? = nil,
  reconfigurationGate: CameraReconfigurationGate? = nil,
  snapshotProvider: (@Sendable () async -> CameraCaptureSnapshot)? = nil,
  restartProvider: (@Sendable () async -> CameraCaptureSnapshot)? = nil
) -> OperatorWorkspace.CameraActions {
  .init(
    discover: { fixture.discoverResponse() },
    select: { _ in fixture.selectResponse() },
    start: { fixture.startResponse() },
    stop: {
      if let snapshotProvider { return await snapshotProvider() }
      return fixture.snapshot
    },
    restart: {
      if let restartProvider { return await restartProvider() }
      return fixture.snapshot
    },
    snapshot: {
      if let snapshotProvider { return await snapshotProvider() }
      return fixture.snapshot
    },
    frames: { AsyncStream { $0.finish() } },
    inspectWorkflowScene: { boundary, features, region in
      await inspectionGate?.waitIfArmed()
      return try fixture.inspection(
        after: boundary,
        features: features,
        analysisRegion: region
      )
    },
    captureFrame: { try fixture.inspection(after: $0).displayedFrame },
    captureStableWorkflowCap: StableWorkflowCapCaptureRunner { request in
      var boundary = request.newerThanNanoseconds
      var samples: [StableWorkflowCapInspection] = []
      for _ in 0..<FixedCameraOpticalSettlingPolicy.requiredCentroidFrameCount {
        try Task.checkCancellation()
        await inspectionGate?.waitIfArmed()
        let inspection = try fixture.inspection(
          after: boundary,
          features: [.penCap],
          analysisRegion: nil
        )
        guard case .found(let cap, _) = inspection.measurement.penCap else {
          throw LearningPathOperationError.requiredState(
            "Pen-cap measurement refused: \(inspection.measurement.penCap.diagnosticReason)."
          )
        }
        samples.append(StableWorkflowCapInspection(inspection: inspection, cap: cap))
        boundary = inspection.displayedFrame.frame.captureNanoseconds
      }
      return try FixedCameraOpticalSettlingPolicy.newestStableCapSample(samples)
    },
    setSceneAnalysisRegion: { fixture.setSceneAnalysisRegion($0) },
    setPenCapColor: {
      await reconfigurationGate?.waitIfArmed()
      fixture.setPenCapColor($0)
    },
    setAutomaticInspection: { fixture.setAutomaticInspection($0, features: $1) },
    analysisUpdates: analysisUpdates,
    visionDiagnostics: { fixture.visionDiagnosticsResponse() },
    observePlannedDrawingInk: nil
  )
}

actor CameraInspectionGate {
  private var isArmed = false
  private var continuation: CheckedContinuation<Void, Never>?

  var isWaiting: Bool { continuation != nil }

  func arm() {
    precondition(!isArmed && continuation == nil)
    isArmed = true
  }

  func waitIfArmed() async {
    guard isArmed else { return }
    isArmed = false
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func release() {
    continuation?.resume()
    continuation = nil
  }
}

actor CameraReconfigurationGate {
  private var isArmed = false
  private var continuation: CheckedContinuation<Void, Never>?

  var isWaiting: Bool { continuation != nil }

  func arm() {
    precondition(!isArmed && continuation == nil)
    isArmed = true
  }

  func waitIfArmed() async {
    guard isArmed else { return }
    isArmed = false
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func release() {
    continuation?.resume()
    continuation = nil
  }
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

final class LearningPathCheckpointBox: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: AcceptedLearningPathCheckpoint?
  private var loads = 0
  private var saves = 0
  private var clears = 0

  init(checkpoint: AcceptedLearningPathCheckpoint? = nil) {
    stored = checkpoint
  }

  var checkpoint: AcceptedLearningPathCheckpoint? {
    lock.lock()
    defer { lock.unlock() }
    return stored
  }

  var operationCounts: (loads: Int, saves: Int, clears: Int) {
    lock.lock()
    defer { lock.unlock() }
    return (loads, saves, clears)
  }

  func load() -> AcceptedLearningPathCheckpointLoadResult {
    lock.lock()
    defer { lock.unlock() }
    loads += 1
    return stored.map(AcceptedLearningPathCheckpointLoadResult.loaded) ?? .absent
  }

  func save(_ checkpoint: AcceptedLearningPathCheckpoint) {
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
  private var shouldBlockNextRequest = true
  private var releasedEarly = false
  private var held = false
  private var heldWaiters: [CheckedContinuation<Void, Never>] = []
  private var continuation: CheckedContinuation<Void, Never>?

  func waitIfFirstRequest() async {
    guard shouldBlockNextRequest else { return }
    shouldBlockNextRequest = false
    if releasedEarly {
      releasedEarly = false
      return
    }
    held = true
    let waiters = heldWaiters
    heldWaiters = []
    waiters.forEach { $0.resume() }
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
    held = false
  }

  func holdNextRequest() {
    precondition(!shouldBlockNextRequest && !held && continuation == nil)
    releasedEarly = false
    shouldBlockNextRequest = true
  }

  func waitUntilHeld() async {
    if held { return }
    await withCheckedContinuation { heldWaiters.append($0) }
  }

  func releaseFirstRequest() {
    guard let continuation else {
      releasedEarly = true
      shouldBlockNextRequest = false
      return
    }
    self.continuation = nil
    continuation.resume()
  }
}

@MainActor
func waitForObservedCondition(
  _ condition: @escaping @MainActor () -> Bool
) async {
  if condition() { return }
  await withCheckedContinuation { continuation in
    ObservationConditionWaiter(
      condition: condition,
      continuation: continuation
    ).start()
  }
}

@MainActor
private final class ObservationConditionWaiter {
  private let condition: @MainActor () -> Bool
  private var continuation: CheckedContinuation<Void, Never>?

  init(
    condition: @escaping @MainActor () -> Bool,
    continuation: CheckedContinuation<Void, Never>
  ) {
    self.condition = condition
    self.continuation = continuation
  }

  func start() {
    guard continuation != nil else { return }
    var satisfied = false
    withObservationTracking {
      satisfied = condition()
    } onChange: { [self] in
      Task { @MainActor in start() }
    }
    if satisfied {
      continuation?.resume()
      continuation = nil
    }
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
  let positionObserver: (@Sendable (MachinePosition) -> Void)?
  private(set) var cancelCount = 0
  private(set) var cancelIntents: [JogCancelIntent] = []
  private(set) var requestedFeeds: [Double] = []
  private(set) var requestedDrawingStrokes: [DrawingStrokeRequest] = []
  private(set) var requestedBoundaryRequests: [BoundaryMotionRequest] = []
  private(set) var requestedPenCommands: [PenCommand] = []
  private(set) var requestedPenProfiles: [PenActuationProfile] = []
  private(set) var snapshotCallCount = 0
  private(set) var passiveProbeCallCount = 0
  private var moving = false
  private var cancelPending = false
  private var pendingCancelIntent: JogCancelIntent?
  private var continuation: CheckedContinuation<MotionOutcome, Never>?
  private var drawingContinuation: CheckedContinuation<DrawingStrokeOutcome, Never>?
  private var boundaryContinuation: CheckedContinuation<BoundaryMotionOutcome, Never>?
  private var position: MachinePosition
  private var penState: PenState = .up
  private var motionGuardActive: Bool
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
  private var boundaryRequestWaiters:
    [(Int, CheckedContinuation<BoundaryMotionRequest, Never>)] = []

  init(
    log: EventLog,
    feedLimits: ControllerAxisFeedLimits? = nil,
    reportsBoundaryMoving: Bool = true,
    holdCancellationSettlement: Bool = false,
    relativeJogSettlementOffset: Vector2<MachineSpace>? = nil,
    penRequestGate: PenRequestGate? = nil,
    motionGuardInitiallyActive: Bool = true,
    positionObserver: (@Sendable (MachinePosition) -> Void)? = nil
  ) throws {
    self.log = log
    self.feedLimits = feedLimits
    self.reportsBoundaryMoving = reportsBoundaryMoving
    self.holdCancellationSettlement = holdCancellationSettlement
    self.relativeJogSettlementOffset = relativeJogSettlementOffset
    self.penRequestGate = penRequestGate
    motionGuardActive = motionGuardInitiallyActive
    self.positionObserver = positionObserver
    position = try MachinePosition(x: 0, y: 0)
    positionObserver?(position)
  }

  func activateMotionGuard() -> MotionGuardActivationOutcome {
    motionGuardActive = true
    return .activated
  }

  func deactivateMotionGuard() {
    motionGuardActive = false
  }

  func setPosition(x: Double, y: Double) throws {
    position = try MachinePosition(x: x, y: y)
    positionObserver?(position)
  }

  func setPenState(_ state: PenState) {
    penState = state
  }

  func enqueuePenOutcome(_ outcome: PenOutcome) {
    queuedPenOutcomes.append(outcome)
  }

  func snapshot() -> RunInterpreterSnapshot {
    snapshotCallCount += 1
    return RunInterpreterSnapshot(
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
        motionGuardState: motionGuardActive ? .active : .inactive,
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
    passiveProbeCallCount += 1
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

  func performRelativeMotion(_ request: RelativeJogRequest) async -> MotionOutcome {
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
      positionObserver?(position)
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

  var relativeJogIsAwaitingSettlement: Bool {
    continuation != nil
  }

  var boundaryMotionIsAwaitingSettlement: Bool {
    boundaryContinuation != nil
  }

  func settleRelativeJogNaturally() {
    guard let continuation, let request = activeRequest else { return }
    self.continuation = nil
    position = try! MachinePosition(
      x: position.point.x + request.delta.dx,
      y: position.point.y + request.delta.dy
    )
    positionObserver?(position)
    moving = false
    let outcome = MotionOutcome.acceptedThenCompleted(finalPosition: position)
    lastMotion = outcome
    continuation.resume(returning: outcome)
  }

  func requestBoundaryMotion(_ request: BoundaryMotionRequest) async -> BoundaryMotionOutcome {
    requestedFeeds.append(request.segment.feedMMPerMinute)
    requestedBoundaryRequests.append(request)
    let readyBoundaryRequestWaiters = boundaryRequestWaiters.filter {
      requestedBoundaryRequests.count >= $0.0
    }
    boundaryRequestWaiters.removeAll {
      requestedBoundaryRequests.count >= $0.0
    }
    readyBoundaryRequestWaiters.forEach { waiter in
      waiter.1.resume(returning: requestedBoundaryRequests[waiter.0 - 1])
    }
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

  func waitForBoundaryRequest(count: Int) async -> BoundaryMotionRequest {
    if requestedBoundaryRequests.count >= count {
      return requestedBoundaryRequests[count - 1]
    }
    return await withCheckedContinuation { boundaryRequestWaiters.append((count, $0)) }
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
      positionObserver?(position)
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
    let outcome =
      queuedPenOutcomes.isEmpty
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

final class CameraAnalysisTrafficFixture: @unchecked Sendable {
  private let lock = NSLock()
  private var continuations:
    [UUID: AsyncStream<PlotterSceneAnalysisSnapshot>.Continuation] = [:]
  private var subscriptions = 0
  private var isFinished = false

  var subscriptionCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return subscriptions
  }

  func updates() -> AsyncStream<PlotterSceneAnalysisSnapshot> {
    let id = UUID()
    return AsyncStream(bufferingPolicy: .bufferingNewest(32)) { [weak self] continuation in
      guard let self else {
        continuation.finish()
        return
      }
      continuation.onTermination = { [weak self] _ in
        self?.removeContinuation(id: id)
      }
      lock.lock()
      if isFinished {
        lock.unlock()
        continuation.finish()
        return
      }
      subscriptions += 1
      continuations[id] = continuation
      lock.unlock()
    }
  }

  func inject(revision: UInt64) {
    let snapshot = PlotterSceneAnalysisSnapshot(
      revision: revision,
      phase: PlotterSceneAnalysisPhase(
        state: .running(.twoFPS),
        requestedFeatures: [.penCap, .armatureEnvelope],
        analysisRegion: nil,
        penCapColor: .green
      ),
      latestResult: nil,
      lastError: nil
    )
    lock.lock()
    let activeContinuations = Array(continuations.values)
    lock.unlock()
    for continuation in activeContinuations {
      continuation.yield(snapshot)
    }
  }

  func finish() {
    lock.lock()
    isFinished = true
    let activeContinuations = Array(continuations.values)
    continuations.removeAll()
    lock.unlock()
    for continuation in activeContinuations {
      continuation.finish()
    }
  }

  private func removeContinuation(id: UUID) {
    lock.lock()
    continuations[id] = nil
    lock.unlock()
  }
}

final class CameraFixture: @unchecked Sendable {
  let device: CameraDevice
  let snapshot: CameraCaptureSnapshot
  private let configurationID: CameraConfigurationID
  private let rotatesConfiguration: Bool
  private let corruptsMeasurementFrameHash: Bool
  private let providesInspectionOverlay: Bool
  private let providesAutomaticAnalysisResult: Bool
  private let automaticAnalysisError: String?
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
  private var visionDiagnosticsCalls = 0
  private var trackedMachinePosition: MachinePosition?

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

  var visionDiagnosticsCallCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return visionDiagnosticsCalls
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

  func visionDiagnosticsResponse() -> CameraSourceSessionVisionDiagnostics {
    lock.lock()
    visionDiagnosticsCalls += 1
    lock.unlock()
    return CameraSourceSessionVisionDiagnostics(
      automaticInspectionConfigurationRevision: 0,
      automaticPipelineStartCallCount: 0,
      automaticFrameSubscriptionStartCount: 0,
      automaticPauseCallCount: 0,
      automaticFrameSubscriptionCancellationCount: 0,
      exclusiveLeaseBeginCount: 0,
      exclusiveLeaseEndCount: 0,
      automaticResumeAfterExclusiveCount: 0,
      activeExclusiveLeaseCount: 0,
      requestedCadence: nil,
      requestedFeatures: [],
      capture: .zero,
      pipeline: PlotterSceneAnalysisDiagnostics(
        phase: .stopped,
        submittedFrameCount: 0,
        analyzedFrameCount: 0,
        supersededFrameCount: 0,
        failedFrameCount: 0,
        activeFrameSequence: nil,
        pendingFrameSequence: nil,
        latestResult: nil,
        lastError: nil,
        configurationRevision: 0,
        semanticPublicationCount: 0,
        semanticSubscriptionStartCount: 0
      )
    )
  }

  func trackMachinePosition(_ position: MachinePosition) {
    lock.lock()
    trackedMachinePosition = position
    lock.unlock()
  }

  init(
    rotatesConfiguration: Bool = false,
    corruptsMeasurementFrameHash: Bool = false,
    providesInspectionOverlay: Bool = false,
    providesAutomaticAnalysisResult: Bool = false,
    automaticAnalysisError: String? = nil,
    capCentroidXOffsets: [Double] = []
  ) throws {
    self.rotatesConfiguration = rotatesConfiguration
    self.corruptsMeasurementFrameHash = corruptsMeasurementFrameHash
    self.providesInspectionOverlay = providesInspectionOverlay
    self.providesAutomaticAnalysisResult = providesAutomaticAnalysisResult
    self.automaticAnalysisError = automaticAnalysisError
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
    let trackedPosition = trackedMachinePosition
    let centroidXOffset = capCentroidXOffsets.isEmpty
      ? 0
      : capCentroidXOffsets[(inspectionCount - 1) % capCentroidXOffsets.count]
    let anchorX = trackedPosition.map { 4 + $0.point.x / 24 } ?? (99 + centroidXOffset)
    let anchorY = trackedPosition.map { 4 + $0.point.y / 24 } ?? 52
    let boundsX = trackedPosition == nil
      ? Int((98 + centroidXOffset).rounded())
      : Int(anchorX.rounded()) - 1
    let boundsY = trackedPosition == nil ? 48 : Int(anchorY.rounded()) - 2
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
          geometry: .point(try Point2(x: anchorX, y: anchorY)),
          provenance: CameraMeasurementProvenance(
            kind: .penCap,
            source: .measured,
            algorithmRevision: "workspace-test-v1"
          )
        )
      ] : []
    let cap = PenCapMeasurement(
      pixelCount: 10,
      boundingBox: PixelRect(
        x: boundsX,
        y: boundsY,
        width: 2,
        height: trackedPosition == nil ? 4 : 2
      ),
      centroid: try Point2(
        x: trackedPosition == nil ? 99 + centroidXOffset : anchorX,
        y: trackedPosition == nil ? 50 : anchorY - 1
      ),
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
      frameSHA256: corruptsMeasurementFrameHash
        ? String(repeating: "f", count: 64)
        : fresh.frame.contentSHA256,
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
    let revision = UInt64(automaticInspectionRequests.count)
    let analysisRegion = sceneAnalysisRegionRequests.last ?? nil
    let penCapColor = penCapColorRequests.last ?? .green
    lock.unlock()
    let latestResult =
      providesAutomaticAnalysisResult
      ? try? inspection(after: 100).asAnalysisResult
      : nil
    return PlotterSceneAnalysisSnapshot(
      revision: revision,
      phase: PlotterSceneAnalysisPhase(
        state: cadence.map(PlotterSceneAnalysisState.running) ?? .stopped,
        requestedFeatures: features,
        analysisRegion: analysisRegion,
        penCapColor: penCapColor
      ),
      latestResult: latestResult,
      lastError: automaticAnalysisError
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
  private(set) var requestCount = 0
  private(set) var cancellationIntents: [JogCancelIntent] = []
  private var requestWaiters: [CheckedContinuation<BoundaryMotionRequest, Never>] = []
  private var cancellationWaiters: [CheckedContinuation<JogCancelIntent, Never>] = []

  func run(
    _ request: BoundaryMotionRequest,
    renewalPlanner: BoundaryMotionRenewalPlanner?
  ) async -> BoundaryMotionOutcome {
    self.request = request
    requestCount += 1
    let waiters = requestWaiters
    requestWaiters.removeAll()
    waiters.forEach { $0.resume(returning: request) }
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

  func waitUntilRequested() async -> BoundaryMotionRequest {
    if let request { return request }
    return await withCheckedContinuation { requestWaiters.append($0) }
  }

  func cancel(_ intent: JogCancelIntent) -> JogCancelOutcome {
    cancellationIntents.append(intent)
    let waiters = cancellationWaiters
    cancellationWaiters.removeAll()
    waiters.forEach { $0.resume(returning: intent) }
    if let cancelContinuation {
      self.cancelContinuation = nil
      cancelContinuation.resume(returning: intent)
    } else {
      pendingCancelIntent = intent
    }
    return .completed(finalPosition: finalPosition ?? (try! MachinePosition(x: 0, y: 0)))
  }

  func waitUntilCancelled() async -> JogCancelIntent {
    if let intent = cancellationIntents.last { return intent }
    return await withCheckedContinuation { cancellationWaiters.append($0) }
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

actor FirstOperationSuspensionPacing: SimulatedLearningExecutionPacing {
  private var hasSuspended = false
  private var isSuspended = false
  private var suspension: CheckedContinuation<Void, Never>?
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func suspendBetweenSteps() async {
    guard !hasSuspended else {
      await Task.yield()
      return
    }
    hasSuspended = true
    await withCheckedContinuation { continuation in
      suspension = continuation
      isSuspended = true
      let currentWaiters = waiters
      waiters.removeAll()
      for waiter in currentWaiters { waiter.resume() }
    }
  }

  func waitUntilSuspended() async {
    if isSuspended { return }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func resume() {
    let continuation = suspension
    suspension = nil
    isSuspended = false
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

@MainActor
func waitForExecutorTurns(
  attempts: Int = 4_000,
  conditionDescription: String = "executor-turn condition",
  condition: () -> Bool
) async throws {
  for _ in 0..<attempts {
    if condition() { return }
    await Task.yield()
  }
  throw TestTimeout(conditionDescription: conditionDescription)
}

@MainActor
func waitForExecutorTurnsAsync(
  attempts: Int = 4_000,
  conditionDescription: String = "async executor-turn condition",
  condition: () async -> Bool
) async throws {
  for _ in 0..<attempts {
    if await condition() { return }
    await Task.yield()
  }
  throw TestTimeout(conditionDescription: conditionDescription)
}

struct TestTimeout: Error, CustomStringConvertible {
  let conditionDescription: String

  init(conditionDescription: String = "test condition") {
    self.conditionDescription = conditionDescription
  }

  var description: String {
    "Timed out waiting for \(conditionDescription)."
  }
}
struct StepMismatch: Error {
  let expected: String
  let actual: String
}
