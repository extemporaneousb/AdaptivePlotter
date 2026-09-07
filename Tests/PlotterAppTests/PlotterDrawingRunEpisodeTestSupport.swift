import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel

@testable import PlotterApp
@testable import PlotterRuntime

struct DrawingRunEpisodeFixture: Sendable {
  let registration: TipCameraRegistration
  let drawableRegion: DrawableMachineRegion
  let paper: PaperRevisionContext
  let previewFrame: DisplayedFrame
  let baselineFrame: DisplayedFrame
  let postFrame: DisplayedFrame
  let plan: PlotterDrawingRunPlan

  var finalPosition: MachinePosition {
    MachinePosition(point: plan.plan.strokes.last!.path.points.last!)
  }

  func makePlan(
    catalogItemID: DrawingCatalogEntryID,
    center: Point2<MachineSpace>? = nil,
    role: BorderValidationEvidenceRole = .ordinaryDrawing,
    draftRevision: UInt64 = 2
  ) throws -> PlotterDrawingRunPlan {
    let built = PlotterDrawingPlanningAdapter.buildDraft(
      program: try DrawingProgramCatalog.program(
        for: catalogItemID,
        style: StrokeStyle(nominalLineWidth: 0.4,
          penProfileID: PenProfileID(registration.applicability.toolAssembly.rawValue))),
      machineCenter: center,
      uniformScale: 0.02,
      rotationDegrees: 0,
      drawableRegion: drawableRegion,
      registration: registration
    )
    return PlotterDrawingRunPlan(
      draftRevision: PlotterDrawingDraftRevision(rawValue: draftRevision),
      program: try requireForDrawingRun(built.program),
      placementID: UUID(),
      plan: try requireForDrawingRun(built.plan),
      evidenceRole: role,
      paperCoverage: plan.paperCoverage,
      registration: registration
    )
  }

  func facts(
    environment: PlotterEnvironment = .live,
    plan: PlotterDrawingRunPlan? = nil,
    learningComplete: Bool = true,
    paperCurrent: Bool = true,
    penActuationProfile: PenActuationProfile = .initialDefaults
  ) -> PlotterDrawingRunExternalFacts {
    PlotterDrawingRunExternalFacts(
      environment: environment,
      interactiveLearningIsComplete: learningComplete,
      plan: plan ?? self.plan,
      paperCoverageIsCurrent: paperCurrent,
      displayedFrame: previewFrame,
      interpreter: drawingRunReadySnapshot(position: finalPosition),
      penActuationProfile: penActuationProfile
    )
  }
}

private enum DrawingRunFixtureError: Error {
  case missingFixtureValue
}

private func requireForDrawingRun<Value>(_ value: Value?) throws -> Value {
  guard let value else { throw DrawingRunFixtureError.missingFixtureValue }
  return value
}

@MainActor
enum DrawingRunEpisodeFixtureCache {
  private static var cached: DrawingRunEpisodeFixture?

  static func load() async throws -> DrawingRunEpisodeFixture {
    if let cached { return cached }
    let harness = makeCausalSimulatorAppFixture()
    try await completeSimulatedPenInteractionPrerequisite(harness.workspace)
    try await installAcceptedBoundaryTestProjection(
      runtime: harness.boundaryRuntime,
      workspace: harness.workspace,
      environment: .simulated
    )
    try await completeSimulatedTipCalibration(
      harness.workspace,
      simulator: harness.simulator
    )
    let registration = try requireForDrawingRun(harness.workspace.tipCameraRegistration)
    let drawableRegion = try requireForDrawingRun(harness.workspace.currentDrawableMachineRegion)
    let source = FrameSourceIdentity.live(
      CameraDeviceID(rawValue: "drawing-run-episode-camera")
    )
    let configuration = CameraConfigurationID()
    let preview = try drawingRunFrame(
      id: "drawing-run-preview",
      sequence: 10,
      source: source,
      configuration: configuration
    )
    let baseline = try drawingRunFrame(
      id: "drawing-run-baseline",
      sequence: 20,
      source: source,
      configuration: configuration
    )
    let post = try drawingRunFrame(
      id: "drawing-run-post",
      sequence: 30,
      source: source,
      configuration: configuration
    )
    let paper = harness.workspace.currentPaperRevisionContext
    let paperCoverage = try PaperCoverageObservation(
      paper: paper,
      source: source,
      frame: ExactFrameProvenance(frame: preview.frame),
      polygon: [
        Point2(x: 1, y: 1), Point2(x: 40, y: 1),
        Point2(x: 40, y: 40), Point2(x: 1, y: 40),
      ],
      method: .operatorAccepted,
      observedAt: RuntimeTimestamp(monotonicNanoseconds: 100),
      algorithmRevision: "drawing-run-episode-paper-v1"
    )
    let built = PlotterDrawingPlanningAdapter.buildDraft(
      program: try DrawingProgramCatalog.program(
        for: .line,
        style: StrokeStyle(nominalLineWidth: 0.4,
          penProfileID: PenProfileID(registration.applicability.toolAssembly.rawValue))),
      machineCenter: nil,
      uniformScale: 0.02,
      rotationDegrees: 0,
      drawableRegion: drawableRegion,
      registration: registration
    )
    let plan = PlotterDrawingRunPlan(
      draftRevision: PlotterDrawingDraftRevision(rawValue: 1),
      program: try requireForDrawingRun(built.program),
      placementID: UUID(),
      plan: try requireForDrawingRun(built.plan),
      evidenceRole: .ordinaryDrawing,
      paperCoverage: paperCoverage,
      registration: registration
    )
    await harness.workspace.shutdown()
    let value = DrawingRunEpisodeFixture(
      registration: registration,
      drawableRegion: drawableRegion,
      paper: paper,
      previewFrame: preview,
      baselineFrame: baseline,
      postFrame: post,
      plan: plan
    )
    cached = value
    return value
  }
}

func drawingRunFrame(
  id: String,
  sequence: UInt64,
  source: FrameSourceIdentity,
  configuration: CameraConfigurationID
) throws -> DisplayedFrame {
  DisplayedFrame(
    source: source,
    frame: try StampedFrame(
      id: FrameID(rawValue: id),
      sequence: sequence,
      captureNanoseconds: sequence,
      cameraConfigurationID: configuration,
      width: 64,
      height: 64,
      rowBytes: 64,
      pixelFormat: .gray8,
      bytes: OwnedFrameBytes(Array(repeating: UInt8(sequence), count: 64 * 64))
    )
  )
}

func drawingRunReadySnapshot(position: MachinePosition) -> RunInterpreterSnapshot {
  let descriptor = MachineLinkDescriptor(
    identifier: "drawing-run-interpreter",
    displayName: "Drawing Run Interpreter",
    bsdPath: nil,
    transport: .simulated
  )
  return RunInterpreterSnapshot(
    currentOperation: .idle,
    machine: MachineSnapshot(
      connection: .connected,
      link: descriptor,
      lastProbe: nil,
      blockers: [],
      controllerState: .idle,
      position: position,
      penState: .up,
      motionGuardState: .active,
      operationInFlight: false,
      lastMotionOutcome: nil,
      lastDrawingStrokeOutcome: nil,
      lastPenOutcome: nil,
      lastJogCancelOutcome: nil,
      controllerAxisFeedLimits: nil
    ),
    lastMotionOutcome: nil,
    lastDrawingStrokeOutcome: nil,
    lastPenOutcome: nil,
    lastProbe: nil,
    lastJogCancelOutcome: nil
  )
}

actor DrawingRunFactProbe: PlotterDrawingRunFactSource {
  private var values: [PlotterEnvironment: PlotterDrawingRunExternalFacts]
  private var nextAcquisitionGate: DrawingRunHoldGate?

  init(_ facts: PlotterDrawingRunExternalFacts) {
    values = [facts.environment: facts]
  }

  func drawingRunFacts(
    for environment: PlotterEnvironment
  ) async -> PlotterDrawingRunExternalFacts {
    let value = values[environment] ?? PlotterDrawingRunExternalFacts(
      environment: environment,
      interactiveLearningIsComplete: false,
      plan: nil,
      paperCoverageIsCurrent: false,
      displayedFrame: nil,
      interpreter: nil,
      penActuationProfile: .initialDefaults
    )
    let gate = nextAcquisitionGate
    nextAcquisitionGate = nil
    await gate?.hold()
    return value
  }

  func replace(_ facts: PlotterDrawingRunExternalFacts) {
    values[facts.environment] = facts
  }

  func holdNextAcquisition(at gate: DrawingRunHoldGate) {
    nextAcquisitionGate = gate
  }
}

actor DrawingRunEventProbe {
  private(set) var values: [String] = []

  func append(_ value: String) { values.append(value) }
}

enum DrawingRunOutcomeKind: Hashable, Sendable {
  case completed
  case refused
  case cancelled
  case ambiguous
  case possibleInk
}

actor DrawingRunHoldGate {
  private var isHolding = false
  private var holdWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseContinuation: CheckedContinuation<Void, Never>?
  private var released = false

  func hold() async {
    isHolding = true
    let waiters = holdWaiters
    holdWaiters.removeAll()
    waiters.forEach { $0.resume() }
    if released { return }
    await withCheckedContinuation { releaseContinuation = $0 }
  }

  func waitUntilHeld() async {
    if isHolding { return }
    await withCheckedContinuation { holdWaiters.append($0) }
  }

  func release() {
    released = true
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

actor DrawingRunPlanGate {
  private var request: DrawingPlanRequest?
  private var startedWaiters: [CheckedContinuation<Void, Never>] = []
  private var continuation: CheckedContinuation<DrawingRunOutcomeKind, Never>?
  private var releasedKind: DrawingRunOutcomeKind?

  func wait(_ request: DrawingPlanRequest) async -> DrawingRunOutcomeKind {
    self.request = request
    let waiters = startedWaiters
    startedWaiters.removeAll()
    waiters.forEach { $0.resume() }
    if let releasedKind { return releasedKind }
    return await withCheckedContinuation { continuation = $0 }
  }

  func waitUntilStarted() async {
    if request != nil { return }
    await withCheckedContinuation { startedWaiters.append($0) }
  }

  func release(_ kind: DrawingRunOutcomeKind) {
    releasedKind = kind
    continuation?.resume(returning: kind)
    continuation = nil
  }
}

actor DrawingRunInterpreterProbe: PlotterDrawingRunInterpreterPort {
  private let ready: RunInterpreterSnapshot
  private let events: DrawingRunEventProbe
  private let outcomeKind: DrawingRunOutcomeKind
  private let normalizationGate: DrawingRunHoldGate?
  private let planGate: DrawingRunPlanGate?
  private(set) var planRequests: [DrawingPlanRequest] = []
  private(set) var stopIntents: [JogCancelIntent] = []

  init(
    ready: RunInterpreterSnapshot,
    events: DrawingRunEventProbe,
    outcomeKind: DrawingRunOutcomeKind = .completed,
    normalizationGate: DrawingRunHoldGate? = nil,
    planGate: DrawingRunPlanGate? = nil
  ) {
    self.ready = ready
    self.events = events
    self.outcomeKind = outcomeKind
    self.normalizationGate = normalizationGate
    self.planGate = planGate
  }

  func snapshot() -> RunInterpreterSnapshot? { ready }

  func normalizePenUp(profile _: PenActuationProfile) async -> PenOutcome {
    await events.append("normalize")
    await normalizationGate?.hold()
    return .commandedAndSettled(command: .raise, commandedState: .up)
  }

  func travelToObservationPosition(_ request: RelativeJogRequest) async -> MotionOutcome {
    await events.append("travel")
    let position = ready.machine.position!
    return .acceptedThenCompleted(
      finalPosition: MachinePosition(point: try! position.point.translated(by: request.delta))
    )
  }

  func beginDrawingPlan(_ request: DrawingPlanRequest) async -> DrawingPlanAdmission {
    planRequests.append(request)
    await events.append("execute")
    if outcomeKind == .refused, planGate == nil {
      return .rejected(drawingRunOutcome(.refused, request: request))
    }
    let gate = planGate
    let fallback = outcomeKind
    return .admitted(DrawingPlanOperation(
      id: request.operationID,
      planRevisionID: request.plan.revisionID,
      task: Task {
        let kind = await gate?.wait(request) ?? fallback
        return drawingRunOutcome(kind, request: request)
      }
    ))
  }

  func requestStop(_ intent: JogCancelIntent) async -> JogCancelOutcome {
    stopIntents.append(intent)
    await events.append("stop")
    await planGate?.release(.cancelled)
    return .transmitted
  }
}

actor DrawingRunCameraProbe: PlotterDrawingRunCameraPort {
  private let frames: [DisplayedFrame]
  private let events: DrawingRunEventProbe
  private var index = 0
  private(set) var requests: [UInt64] = []

  init(frames: [DisplayedFrame], events: DrawingRunEventProbe) {
    self.frames = frames
    self.events = events
  }

  func captureFrame(newerThan captureNanoseconds: UInt64) async throws -> DisplayedFrame {
    requests.append(captureNanoseconds)
    let frame = frames[index]
    index += 1
    await events.append(index == 1 ? "capture-baseline" : "capture-post")
    return frame
  }
}

actor DrawingRunVisionProbe: PlotterDrawingRunVisionPort {
  private let events: DrawingRunEventProbe
  private(set) var requests: [PlannedDrawingObservationRequest] = []

  init(events: DrawingRunEventProbe) { self.events = events }

  func observePlannedDrawingInk(
    _ request: PlannedDrawingObservationRequest
  ) async -> PlannedDrawingObservationOutcome {
    requests.append(request)
    await events.append("observe")
    let algorithms = request.additionalAlgorithmRevisions.union([request.observerRevision])
    let evidence = try! DrawingObservedInkEvidence(
      frames: request.frames,
      intendedInk: request.intendedCameraPolylines,
      observedInk: request.intendedCameraPolylines,
      residual: try! DrawingResidualEvidence(
        correspondenceCount: UInt32(request.intendedCameraPolylines.count),
        rootMeanSquarePixels: 0,
        maximumPixels: 0,
        rootMeanSquareCrossTrackPixels: 0
      ),
      algorithmRevisions: algorithms
    )
    return .observed(PlannedDrawingObservation(
      evidence: evidence,
      alignment: IntegerFrameAlignment(
        shiftX: 0,
        shiftY: 0,
        backgroundMeanAbsoluteDifference: 0,
        estimatorRevision: "drawing-run-episode-alignment-v1",
        supportRegion: request.region,
        exclusionRegion: PixelRect(x: 0, y: 0, width: 0, height: 0),
        evaluatedPixelCount: request.region.width * request.region.height
      ),
      overlays: [],
      observedPixelCount: max(1, request.intendedCameraPolylines.count)
    ))
  }
}

enum DrawingRunEvidenceProbeError: Error {
  case appendFailed
}

actor DrawingRunEvidenceProbe: PlotterDrawingRunEvidencePort {
  private let events: DrawingRunEventProbe
  private var failuresRemaining: Int
  private var nextAppendGate: DrawingRunHoldGate?
  private(set) var attempts: [DrawingRunEvidenceRecord] = []
  private(set) var archive = DrawingRunEvidenceArchive()

  init(events: DrawingRunEventProbe, failures: Int = 0) {
    self.events = events
    failuresRemaining = failures
  }

  func append(_ record: DrawingRunEvidenceRecord) async throws -> DrawingRunEvidenceArchive {
    attempts.append(record)
    await events.append("append")
    let gate = nextAppendGate
    nextAppendGate = nil
    await gate?.hold()
    if failuresRemaining > 0 {
      failuresRemaining -= 1
      throw DrawingRunEvidenceProbeError.appendFailed
    }
    archive = try archive.appending(record)
    return archive
  }

  func holdNextAppend(at gate: DrawingRunHoldGate) {
    nextAppendGate = gate
  }
}

struct DrawingRunRuntimeHarness: Sendable {
  let runtime: PlotterDrawingRunRuntime
  let facts: DrawingRunFactProbe
  let interpreter: DrawingRunInterpreterProbe
  let camera: DrawingRunCameraProbe
  let vision: DrawingRunVisionProbe
  let evidence: DrawingRunEvidenceProbe
  let events: DrawingRunEventProbe
}

func drawingRunHarness(
  fixture: DrawingRunEpisodeFixture,
  facts initialFacts: PlotterDrawingRunExternalFacts? = nil,
  outcome: DrawingRunOutcomeKind = .completed,
  normalizationGate: DrawingRunHoldGate? = nil,
  planGate: DrawingRunPlanGate? = nil,
  evidenceFailures: Int = 0,
  archiveLoadResult: DrawingRunEvidenceStoreLoadResult = .absent
) async -> DrawingRunRuntimeHarness {
  let events = DrawingRunEventProbe()
  let resolvedFacts = initialFacts ?? fixture.facts()
  let facts = DrawingRunFactProbe(resolvedFacts)
  let interpreter = DrawingRunInterpreterProbe(
    ready: drawingRunReadySnapshot(position: fixture.finalPosition),
    events: events,
    outcomeKind: outcome,
    normalizationGate: normalizationGate,
    planGate: planGate
  )
  let camera = DrawingRunCameraProbe(
    frames: [fixture.baselineFrame, fixture.postFrame],
    events: events
  )
  let vision = DrawingRunVisionProbe(events: events)
  let evidence = DrawingRunEvidenceProbe(events: events, failures: evidenceFailures)
  let runtime = PlotterDrawingRunRuntime(
    facts: facts,
    interpreter: interpreter,
    camera: camera,
    vision: vision,
    evidence: evidence,
    clock: DrawingRunEpisodeClock()
  )
  if resolvedFacts.environment == .live {
    _ = await runtime.restoreNoRedrawTruth(
      from: archiveLoadResult,
      paper: fixture.paper,
      environment: .live
    )
  }
  return DrawingRunRuntimeHarness(
    runtime: runtime,
    facts: facts,
    interpreter: interpreter,
    camera: camera,
    vision: vision,
    evidence: evidence,
    events: events
  )
}

struct DrawingRunEpisodeClock: RuntimeClock {
  func nowNanoseconds() -> UInt64 { 1_000 }
  func sleep(nanoseconds _: UInt64) async throws {}
}

func drawingRunOutcome(
  _ kind: DrawingRunOutcomeKind,
  request: DrawingPlanRequest
) -> DrawingPlanOutcome {
  let commanded = kind == .refused ? 0 : request.plan.strokes.count
  let completed = kind == .completed ? request.plan.strokes.count : 0
  let segmentCount = request.plan.strokes.reduce(0) {
    $0 + max(0, $1.path.points.count - 1)
  }
  let progress = DrawingPlanProgressSnapshot(
    operationID: request.operationID,
    planRevisionID: request.plan.revisionID,
    plannedStrokeCount: request.plan.strokes.count,
    plannedSegmentCount: segmentCount,
    commandedStrokeCount: commanded,
    controllerCompletedStrokeCount: completed,
    submittedSegmentCount: commanded == 0 ? 0 : segmentCount,
    controllerCompletedSegmentCount: completed == 0 ? 0 : segmentCount,
    completedStrokeIDs: completed == 0 ? [] : request.plan.strokes.map(\.logicalStrokeID),
    completedCheckpointIDs: completed == 0
      ? [] : request.plan.strokes.map(\.endingCheckpointID),
    activeStrokeID: nil,
    activeSegmentIndex: nil
  )
  let final = MachinePosition(point: request.plan.strokes.last!.path.points.last!)
  switch kind {
  case .completed:
    return .completed(progress: progress, finalPosition: final)
  case .refused:
    return .refused(progress: progress, reason: .notConnected)
  case .cancelled:
    return .cancelled(
      progress: progress,
      intent: .operatorStop,
      jogCancelOutcome: .transmitted,
      finalPosition: final,
      penRaiseOutcome: .commandedAndSettled(command: .raise, commandedState: .up)
    )
  case .ambiguous:
    return .ambiguous(progress: progress, reason: .stroke(.disconnected))
  case .possibleInk:
    return .possibleInk(
      progress: progress,
      reason: .strokeRefused(.controllerRejected("fixture")),
      penRaiseOutcome: .commandedAndSettled(command: .raise, commandedState: .up)
    )
  }
}
