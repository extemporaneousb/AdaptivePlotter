import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

struct DrawingRunEpisodeFixture: Sendable {
  let registration: TipCameraRegistration
  let drawableRegion: DrawableMachineRegion
  let paper: PaperRevisionContext
  let previewFrame: DisplayedFrame
  let baselineFrame: DisplayedFrame
  let completionFrame: DisplayedFrame
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

  func withMaterial(_ profile: DrawingMaterialProfileRevision) throws -> PlotterDrawingRunPlan {
    let original = plan.plan
    let prior = original.provenance
    let provenance = DrawingPlanningProvenance(modelRevisionID: prior.modelRevisionID,
      modelContentHash: prior.modelContentHash, registrationRevisionID: prior.registrationRevisionID,
      registrationContentHash: prior.registrationContentHash,
      materialContextHash: try DrawingRunAttemptContext.materialContextHash(profile: profile, applicability: nil))
    let revised = try ExecutionPlanRevision(sourceProgramID: original.sourceProgramID,
      sourceProgramContentHash: original.sourceProgramContentHash, placement: original.placement,
      drawableRegion: original.drawableRegion, provenance: provenance,
      strokes: original.strokes, checkpoints: original.checkpoints)
    return PlotterDrawingRunPlan(draftRevision: .init(rawValue: 2), program: plan.program,
      placementID: plan.placementID, plan: revised, evidenceRole: plan.evidenceRole,
      paperCoverage: plan.paperCoverage, registration: registration, materialProfile: profile)
  }

  func withChangedSourceStyleAndOpticalIdentity() throws -> PlotterDrawingRunPlan {
    let prior = plan.program
    let style = try StrokeStyle(nominalLineWidth: 1.2,
      penProfileID: PenProfileID(registration.applicability.toolAssembly.rawValue))
    let program = try DrawingProgram(id: prior.id, fieldExtent: prior.fieldExtent,
      strokes: prior.strokes.map { LogicalStroke(id: $0.id, path: $0.path, style: style,
        semanticRole: $0.semanticRole, ordering: $0.ordering) },
      source: DrawingSourceProvenance(kind: "another-generator", sourceIdentifier: "another-source"))
    let revisedRegistration = try drawingRunSyntheticRegistration(registration,
      source: .live(CameraDeviceID(rawValue: "synthetic-recovered-camera")))
    let built = PlotterDrawingPlanningAdapter.buildDraft(program: program, machineCenter: nil,
      uniformScale: 0.02, rotationDegrees: 0, drawableRegion: drawableRegion,
      registration: revisedRegistration)
    return PlotterDrawingRunPlan(draftRevision: .init(rawValue: 3), program: program,
      placementID: plan.placementID, plan: try requireForDrawingRun(built.plan), evidenceRole: plan.evidenceRole,
      paperCoverage: plan.paperCoverage, registration: revisedRegistration)
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
      penActuationProfile: penActuationProfile,
      acceptedMovementBounds: drawableRegion.bounds
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
    let simulatedRegistration = try requireForDrawingRun(harness.workspace.tipCameraRegistration)
    let drawableRegion = try requireForDrawingRun(harness.workspace.currentDrawableMachineRegion)
    let source = FrameSourceIdentity.live(
      CameraDeviceID(rawValue: "drawing-run-episode-camera")
    )
    // This is a synthetic runtime fixture, not a physical calibration claim.
    // Preserve the simulator-derived transform and its pixel coordinate space;
    // only the fixture camera identity changes, with a fresh accepted revision.
    let registration = try drawingRunSyntheticRegistration(simulatedRegistration, source: source)
    let optical = registration.applicability.opticalConfiguration
    let configuration = CameraConfigurationID()
    let preview = try drawingRunFrame(
      id: "drawing-run-preview",
      sequence: 10,
      source: source,
      configuration: configuration,
      width: optical.width, height: optical.height, pixelFormat: optical.pixelFormat
    )
    let baseline = try drawingRunFrame(
      id: "drawing-run-baseline",
      sequence: 20,
      source: source,
      configuration: configuration,
      width: optical.width, height: optical.height, pixelFormat: optical.pixelFormat
    )
    let completion = try drawingRunFrame(id: "drawing-run-completion", sequence: 25,
      source: source, configuration: configuration, width: optical.width, height: optical.height,
      pixelFormat: optical.pixelFormat)
    let post = try drawingRunFrame(
      id: "drawing-run-post",
      sequence: 30,
      source: source,
      configuration: configuration,
      width: optical.width, height: optical.height, pixelFormat: optical.pixelFormat
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
      completionFrame: completion,
      postFrame: post,
      plan: plan
    )
    cached = value
    return value
  }
}

/// Test-only Codable fixture construction. No production acceptance/rebase path
/// is called: all evidence here is synthetic. Numerical registration geometry,
/// covariance and observation coordinates retain their original pixel meaning.
private func drawingRunSyntheticRegistration(
  _ sourceRegistration: TipCameraRegistration, source: FrameSourceIdentity
) throws -> TipCameraRegistration {
  let prior = sourceRegistration.applicability.opticalConfiguration
  let optical = try CameraOpticalConfigurationIdentity(source: source,
    sensorFormat: "drawing-run-synthetic-" + prior.sensorFormat,
    width: prior.width, height: prior.height, pixelFormat: prior.pixelFormat,
    orientation: prior.orientation, mirrored: prior.mirrored,
    captureCrop: prior.captureCrop, digitalZoomFactor: prior.digitalZoomFactor,
    lensIdentity: "synthetic-fixture-lens", focusConfiguration: "synthetic-fixture-focus",
    mountRevision: prior.mountRevision, reframingRevision: prior.reframingRevision)
  let previous = sourceRegistration.applicability
  let applicability = TipCalibrationApplicabilityContext(opticalConfiguration: optical,
    machineGeometry: previous.machineGeometry, machineCoordinateFrame: previous.machineCoordinateFrame,
    toolAssembly: previous.toolAssembly, penContactProfile: previous.penContactProfile,
    paperContactPlane: previous.paperContactPlane)
  let encoder = JSONEncoder()
  var object = try JSONSerialization.jsonObject(with: encoder.encode(sourceRegistration)) as! [String: Any]
  object["applicability"] = try JSONSerialization.jsonObject(with: encoder.encode(applicability))
  object["acceptedRevisionID"] = try JSONSerialization.jsonObject(with: encoder.encode(LearningArtifactRevisionID()))
  object["estimatorRevision"] = sourceRegistration.estimatorRevision + "-synthetic-run-fixture"
  return try JSONDecoder().decode(TipCameraRegistration.self,
    from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
}

func drawingRunFrame(
  id: String,
  sequence: UInt64,
  source: FrameSourceIdentity,
  configuration: CameraConfigurationID,
  width: Int = 64,
  height: Int = 64,
  pixelFormat: FramePixelFormat = .gray8
) throws -> DisplayedFrame {
  DisplayedFrame(
    source: source,
    frame: try StampedFrame(
      id: FrameID(rawValue: id),
      sequence: sequence,
      captureNanoseconds: sequence,
      cameraConfigurationID: configuration,
      width: width,
      height: height,
      rowBytes: width * pixelFormat.bytesPerPixel,
      pixelFormat: pixelFormat,
      bytes: OwnedFrameBytes(Array(repeating: UInt8(sequence), count: width * height * pixelFormat.bytesPerPixel))
    )
  )
}

func drawingRunReadySnapshot(position: MachinePosition, penState: PenState = .up) -> RunInterpreterSnapshot {
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
      penState: penState,
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
  private var holdWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
  private var releaseContinuation: CheckedContinuation<Void, Never>?
  private var released = false

  func hold() async {
    isHolding = true
    let waiters = holdWaiters
    holdWaiters.removeAll()
    waiters.values.forEach { $0.resume() }
    if released { return }
    await withCheckedContinuation { releaseContinuation = $0 }
  }

  func waitUntilHeld() async {
    if isHolding { return }
    let id = UUID()
    let timeout = Task {
      do { try await Task.sleep(for: .seconds(10)) } catch { return }
      failUnreachedHold(id)
    }
    await withCheckedContinuation { holdWaiters[id] = $0 }
    timeout.cancel()
  }

  private func failUnreachedHold(_ id: UUID) {
    guard let waiter = holdWaiters.removeValue(forKey: id) else { return }
    Issue.record("Drawing run never reached the held effect within 10 seconds; inspect an earlier pipeline or fixture failure.")
    release()
    waiter.resume()
  }

  func release() {
    released = true
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

actor DrawingRunPlanGate {
  private(set) var request: DrawingPlanRequest?
  private var startedWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
  private var continuation: CheckedContinuation<DrawingRunOutcomeKind, Never>?
  private var releasedKind: DrawingRunOutcomeKind?

  func wait(_ request: DrawingPlanRequest) async -> DrawingRunOutcomeKind {
    self.request = request
    let waiters = startedWaiters
    startedWaiters.removeAll()
    waiters.values.forEach { $0.resume() }
    if let releasedKind { return releasedKind }
    return await withCheckedContinuation { continuation = $0 }
  }

  func waitUntilStarted() async {
    if request != nil { return }
    let id = UUID()
    let timeout = Task {
      do { try await Task.sleep(for: .seconds(10)) } catch { return }
      failUnreachedPlan(id)
    }
    await withCheckedContinuation { startedWaiters[id] = $0 }
    timeout.cancel()
  }

  private func failUnreachedPlan(_ id: UUID) {
    guard let waiter = startedWaiters.removeValue(forKey: id) else { return }
    Issue.record("Drawing run never admitted its plan within 10 seconds; inspect an earlier pipeline or fixture failure.")
    release(.cancelled)
    waiter.resume()
  }

  func release(_ kind: DrawingRunOutcomeKind) {
    releasedKind = kind
    continuation?.resume(returning: kind)
    continuation = nil
  }
}

actor DrawingRunInterpreterProbe: PlotterDrawingRunInterpreterPort {
  private var ready: RunInterpreterSnapshot
  private let events: DrawingRunEventProbe
  private let outcomeKind: DrawingRunOutcomeKind
  private let normalizationGate: DrawingRunHoldGate?
  private let planGate: DrawingRunPlanGate?
  private let releasePlanOnStop: Bool
  private var nextSnapshotGate: DrawingRunHoldGate?
  private var drawingProgress: DrawingPlanProgressSnapshot?
  private var drawingOutcomeOverride: DrawingPlanOutcome?
  private var heldTravel: (ordinal: Int, gate: DrawingRunHoldGate)?
  private var travelCount = 0
  private var emitProgressCheckpoints = false
  func enableProgressCheckpoints() { emitProgressCheckpoints = true }
  private(set) var planRequests: [DrawingPlanRequest] = []
  private(set) var stopIntents: [JogCancelIntent] = []

  init(
    ready: RunInterpreterSnapshot,
    events: DrawingRunEventProbe,
    outcomeKind: DrawingRunOutcomeKind = .completed,
    normalizationGate: DrawingRunHoldGate? = nil,
    planGate: DrawingRunPlanGate? = nil,
    releasePlanOnStop: Bool = true
  ) {
    self.ready = ready
    self.events = events
    self.outcomeKind = outcomeKind
    self.normalizationGate = normalizationGate
    self.planGate = planGate
    self.releasePlanOnStop = releasePlanOnStop
  }

  func snapshot() async -> RunInterpreterSnapshot? {
    let captured = RunInterpreterSnapshot(currentOperation: ready.currentOperation,
      machine: ready.machine, lastMotionOutcome: ready.lastMotionOutcome,
      drawingPlanProgress: drawingProgress, lastProbe: ready.lastProbe)
    let gate = nextSnapshotGate
    nextSnapshotGate = nil
    await gate?.hold()
    return captured
  }

  func holdNextSnapshot(at gate: DrawingRunHoldGate) { nextSnapshotGate = gate }

  func setDrawingProgress(_ progress: DrawingPlanProgressSnapshot) { drawingProgress = progress }

  func overrideDrawingOutcome(_ outcome: DrawingPlanOutcome) { drawingOutcomeOverride = outcome }

  func setPenState(_ state: PenState) {
    ready = drawingRunReadySnapshot(position: ready.machine.position!, penState: state)
  }

  func setPosition(_ position: MachinePosition) {
    ready = drawingRunReadySnapshot(position: position, penState: ready.machine.penState)
  }

  func normalizePenUp(profile _: PenActuationProfile) async -> PenOutcome {
    await events.append("normalize")
    await normalizationGate?.hold()
    setPenState(.up)
    return .commandedAndSettled(command: .raise, commandedState: .up)
  }

  func holdTravel(ordinal: Int, at gate: DrawingRunHoldGate) { heldTravel = (ordinal, gate) }

  func travelToObservationPosition(_ request: RelativeJogRequest) async -> MotionOutcome {
    travelCount += 1
    await events.append("travel")
    let position = ready.machine.position!
    if let hold = heldTravel, hold.ordinal == travelCount { await hold.gate.hold() }
    let final = MachinePosition(point: try! position.point.translated(by: request.delta))
    setPosition(final)
    return .acceptedThenCompleted(finalPosition: final)
  }

  func beginDrawingPlan(_ request: DrawingPlanRequest, checkpointObserver: (any DrawingPlanCheckpointObserver)?) async -> DrawingPlanAdmission {
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
        if self.emitProgressCheckpoints, let checkpointObserver {
          for count in 1...request.plan.strokes.count {
            let progress = drawingRunCheckpointProgress(request, completed: count)
            let position = MachinePosition(point: request.plan.strokes[count - 1].path.end)
            self.setPosition(position)
            self.drawingProgress = progress
            await checkpointObserver.reachedCheckpoint(progress, position: position)
            if !self.stopIntents.isEmpty {
              return .cancelled(progress: progress, intent: .operatorStop, jogCancelOutcome: .transmitted,
                finalPosition: position, penRaiseOutcome: .commandedAndSettled(command: .raise, commandedState: .up))
            }
          }
        }
        let result = self.drawingOutcomeOverride ?? drawingRunOutcome(kind, request: request)
        if case .completed(_, let position) = result { self.setPosition(position) }
        return result
      }
    ))
  }

  func requestStop(_ intent: JogCancelIntent) async -> JogCancelOutcome {
    stopIntents.append(intent)
    await events.append("stop")
    if releasePlanOnStop { await planGate?.release(.cancelled) }
    if let hold = heldTravel { await hold.gate.release() }
    return .transmitted
  }
}

actor DrawingRunCameraProbe: PlotterDrawingRunCameraPort {
  private let frames: [DisplayedFrame]
  private let events: DrawingRunEventProbe
  private var index = 0
  private var heldCapture: (ordinal: Int, gate: DrawingRunHoldGate)?
  private(set) var requests: [UInt64] = []

  init(frames: [DisplayedFrame], events: DrawingRunEventProbe) {
    self.frames = frames
    self.events = events
  }

  func holdCapture(ordinal: Int, at gate: DrawingRunHoldGate) { heldCapture = (ordinal, gate) }

  func captureFrame(newerThan captureNanoseconds: UInt64) async throws -> DisplayedFrame {
    requests.append(captureNanoseconds)
    if let hold = heldCapture, hold.ordinal == requests.count { await hold.gate.hold() }
    guard frames.indices.contains(index) else { throw LearningPathOperationError.freshFrameUnavailable }
    let frame = frames[index]
    index += 1
    await events.append(index == 1 ? "capture-baseline" : (index == 2 ? "capture-completion" : "capture-post"))
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
  case stageFailed
  case mediaFailed
}

actor DrawingRunEvidenceProbe: PlotterDrawingRunEvidencePort {
  private let events: DrawingRunEventProbe
  private let store: DrawingRunEvidenceStore
  private var failuresRemaining: Int
  private var stageFailuresRemaining: Int
  private var stageBaselineFailuresRemaining: Int
  private var failDispatchAcknowledgement: Bool
  private var rejectedMediaFrames: Set<FrameID> = []
  private var nextAppendGate: DrawingRunHoldGate?
  private(set) var attempts: [DrawingRunEvidenceRecord] = []
  private(set) var archive = DrawingRunEvidenceArchive()

  init(events: DrawingRunEventProbe, failures: Int = 0, stageFailures: Int = 0,
    stageBaselineFailures: Int = 0, failDispatchAcknowledgement: Bool = false) {
    self.events = events
    failuresRemaining = failures
    stageFailuresRemaining = stageFailures
    stageBaselineFailuresRemaining = stageBaselineFailures
    self.failDispatchAcknowledgement = failDispatchAcknowledgement
    store = DrawingRunEvidenceStore(fileURL: FileManager.default.temporaryDirectory
      .appendingPathComponent("drawing-run-probe-" + UUID().uuidString)
      .appendingPathComponent("evidence.json"))
  }

  deinit { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }

  func stageIntent(_ intent: DrawingRunIntent) async throws -> DrawingRunEvidenceArchive {
    if !archive.attempts.contains(where: { $0.intent.runID == intent.runID }) {
      await events.append("stage-intent")
    }
    if stageFailuresRemaining > 0 { stageFailuresRemaining -= 1; throw DrawingRunEvidenceProbeError.stageFailed }
    archive = try await store.stageIntent(intent)
    return archive
  }

  func rejectMediaFrames(_ ids: Set<FrameID>) { rejectedMediaFrames = ids }

  func installMedia(frame: StampedFrame, source: FrameSourceIdentity) async throws -> DrawingRunMediaReference {
    if rejectedMediaFrames.contains(frame.id) { throw DrawingRunEvidenceProbeError.mediaFailed }
    return try await store.installMedia(frame: frame, source: source)
  }

  func readMedia(_ reference: DrawingRunMediaReference) async throws -> StampedFrame {
    try await store.readMedia(reference)
  }

  func removeMediaForCorruptionTest(_ reference: DrawingRunMediaReference) throws {
    let url = store.fileURL.deletingLastPathComponent()
      .appendingPathComponent(store.fileURL.lastPathComponent + ".media")
      .appendingPathComponent(reference.frame.frameSHA256 + ".pixels")
    try FileManager.default.removeItem(at: url)
  }

  func reopenedArchive() async -> DrawingRunEvidenceArchive? {
    guard case .loaded(let value) = await DrawingRunEvidenceStore(fileURL: store.fileURL).load() else { return nil }
    return value
  }

  func stageBaseline(runID: RunID, media: DrawingRunMediaReference) async throws -> DrawingRunEvidenceArchive {
    if !archive.attempts.contains(where: { $0.intent.runID == runID && $0.baselines.contains(media) }) {
      await events.append("stage-baseline")
    }
    if stageBaselineFailuresRemaining > 0 {
      stageBaselineFailuresRemaining -= 1; throw DrawingRunEvidenceProbeError.stageFailed
    }
    archive = try await store.stageBaseline(runID: runID, media: media)
    return archive
  }

  func stageProgressFrame(runID: RunID, frame: DrawingRunProgressFrame) async throws -> DrawingRunEvidenceArchive {
    archive = try await store.stageProgressFrame(runID: runID, frame: frame)
    await events.append("stage-progress")
    return archive
  }

  private var failNoInkConfirmation = false
  func failNextNoInkConfirmation() { failNoInkConfirmation = true }

  func confirmNoInk(_ confirmation: DrawingRunNoInkConfirmation) async throws -> DrawingRunEvidenceArchive {
    if failNoInkConfirmation { failNoInkConfirmation = false; throw DrawingRunEvidenceProbeError.stageFailed }
    archive = try await store.confirmNoInk(confirmation)
    return archive
  }

  func markInkDispatchPossible(runID: RunID) async throws -> DrawingRunEvidenceArchive {
    await events.append("dispatch-marker")
    archive = try await store.markInkDispatchPossible(runID: runID)
    if failDispatchAcknowledgement {
      failDispatchAcknowledgement = false
      throw DrawingRunEvidenceProbeError.stageFailed
    }
    return archive
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
    archive = try await store.append(record)
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
  releasePlanOnStop: Bool = true,
  evidenceFailures: Int = 0,
  stageFailures: Int = 0,
  stageBaselineFailures: Int = 0,
  failDispatchAcknowledgement: Bool = false,
  archiveLoadResult: DrawingRunEvidenceStoreLoadResult = .absent,
  cameraFrames: [DisplayedFrame]? = nil,
  clock: any RuntimeClock = DrawingRunEpisodeClock()
) async -> DrawingRunRuntimeHarness {
  let events = DrawingRunEventProbe()
  let resolvedFacts = initialFacts ?? fixture.facts()
  let facts = DrawingRunFactProbe(resolvedFacts)
  let interpreter = DrawingRunInterpreterProbe(
    ready: drawingRunReadySnapshot(position: fixture.finalPosition),
    events: events,
    outcomeKind: outcome,
    normalizationGate: normalizationGate,
    planGate: planGate,
    releasePlanOnStop: releasePlanOnStop
  )
  let camera = DrawingRunCameraProbe(
    frames: cameraFrames ?? [fixture.baselineFrame, fixture.completionFrame, fixture.postFrame],
    events: events
  )
  let vision = DrawingRunVisionProbe(events: events)
  let evidence = DrawingRunEvidenceProbe(events: events, failures: evidenceFailures,
    stageFailures: stageFailures, stageBaselineFailures: stageBaselineFailures,
    failDispatchAcknowledgement: failDispatchAcknowledgement)
  let runtime = PlotterDrawingRunRuntime(
    facts: facts,
    interpreter: interpreter,
    camera: camera,
    vision: vision,
    evidence: evidence,
    clock: clock
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
  func nowNanoseconds() -> UInt64 { 10 }
  func sleep(nanoseconds _: UInt64) async throws {}
}

/// Deterministic monotonic times for intent, settled baseline/result boundaries
/// and terminal recording. It does not infer real camera timing from test time.
final class DrawingRunSequenceClock: RuntimeClock, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [UInt64]
  init(_ values: [UInt64]) { precondition(!values.isEmpty); self.values = values }
  func nowNanoseconds() -> UInt64 {
    lock.lock()
    defer { lock.unlock() }
    return values.count > 1 ? values.removeFirst() : values[0]
  }
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

func drawingRunCheckpointProgress(_ request: DrawingPlanRequest, completed count: Int) -> DrawingPlanProgressSnapshot {
  let schedule = try! DrawingWireSchedule(plan: request.plan)
  let segments = schedule.strokes.prefix(count).reduce(0) { $0 + $1.segments.count }
  return DrawingPlanProgressSnapshot(operationID: request.operationID, planRevisionID: request.plan.revisionID,
    plannedStrokeCount: request.plan.strokes.count, plannedSegmentCount: schedule.segmentCount,
    commandedStrokeCount: count, controllerCompletedStrokeCount: count,
    submittedSegmentCount: segments, controllerCompletedSegmentCount: segments,
    completedStrokeIDs: request.plan.strokes.prefix(count).map(\.logicalStrokeID),
    completedCheckpointIDs: request.plan.strokes.prefix(count).map(\.endingCheckpointID),
    activeStrokeID: nil, activeSegmentIndex: nil)
}
