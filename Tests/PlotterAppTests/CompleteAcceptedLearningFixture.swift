import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import Testing
@testable import PlotterApp

/// Synthetic accepted-artifact data. Boundary values come from the existing
/// accepted Boundary fixture; the simulator supplies calibrated geometry and
/// a completed Border. Controller context is rebound to the synthetic lower
/// controller used by application tests; optical sources are rebound to one test camera and
/// dependent hashes are regenerated. This does not claim LIVE physical evidence
/// or test the acceptance of that preceding Learning path. The application
/// under restoration test receives only the normal persisted package/archive.
struct CompleteAcceptedLearningFixture: Sendable {
  let identities: TipCalibrationSemanticIdentityState
  let checkpoint: AcceptedLearningPathCheckpoint
  let borderRecord: DrawingRunEvidenceRecord
  let frame: DisplayedFrame
  let drawableRegion: DrawableMachineRegion
  let expectedCenter: EstimatedMachineCenter?

  var registration: TipCameraRegistration { checkpoint.tipCalibration!.registration }

  @MainActor
  static func make(raisedSpindleValue: Int? = nil) async throws -> Self {
    let identities = TipCalibrationSemanticIdentityState.ephemeral()
    let seeded = makeCausalSimulatorAppFixture(tipCalibrationSemanticIdentities: identities)
    let source = seeded.workspace
    try await completeSimulatedPenInteractionPrerequisite(source, raisedSpindleValue: raisedSpindleValue)
    try await installAcceptedBoundaryTestProjection(runtime: seeded.boundaryRuntime,
      workspace: source, environment: .simulated)
    try await completeSimulatedTipCalibration(source, simulator: seeded.simulator)
    await source.performTestExerciseAction(.start,
      for: .borderValidation(.chooseDrawingBorderPlan))
    #expect(source.borderValidationSnapshot.assessment == .predictionObserved)
    let syntheticSource = FrameSourceIdentity.live(CameraDeviceID(rawValue: "accepted-learning-fixture-camera"))
    let tip = try replacingFixtureSources(#require(source.tipCameraRegistration), with: syntheticSource)
    let machineCamera = try replacingFixtureSources(#require(source.machineCameraRegistration), with: syntheticSource)
    let completed = source.borderValidationSnapshot
    let comparison = try #require(source.learningArtifactGraph.currentRevision(for: .comparison(completed.group)))
    let postFrame = try #require(completed.postFrame)
    let originalRecord = try #require(try DrawingBorderEvidence.record(snapshot: completed,
      attemptID: comparison.attemptID, registration: tip, paper: source.currentPaperRevisionContext,
      nowNanoseconds: postFrame.frame.captureNanoseconds))
    let oldPlan = try #require(originalRecord.plan.executionPlan)
    let provenance = try PlotterDrawingPlanningAdapter.planningProvenance(for: tip)
    let plan = try ExecutionPlanRevision(sourceProgramID: oldPlan.sourceProgramID,
      sourceProgramContentHash: oldPlan.sourceProgramContentHash, placement: oldPlan.placement,
      drawableRegion: oldPlan.drawableRegion, provenance: provenance,
      strokes: oldPlan.strokes, checkpoints: oldPlan.checkpoints)
    let record = try DrawingRunEvidenceRecord(recordID: originalRecord.recordID,
      runID: originalRecord.runID, requestID: originalRecord.requestID,
      role: originalRecord.role, evidenceDisposition: originalRecord.evidenceDisposition,
      requestFrontier: originalRecord.requestFrontier, executionFrontiers: originalRecord.executionFrontiers,
      executionDisposition: originalRecord.executionDisposition, program: originalRecord.program,
      placement: originalRecord.placement, plan: DrawingExecutionPlanEvidenceReference(plan: plan),
      planningProvenance: provenance, tipCalibration: originalRecord.tipCalibration,
      paper: originalRecord.paper,
      observation: replacingFixtureSources(originalRecord.observation, with: syntheticSource),
      recordedAt: originalRecord.recordedAt)
    let penHistory = await seeded.penInteractionRuntime.snapshot(environment: .simulated)
    let penAttempt = try #require(penHistory.acceptedHistory.includedSuccessfulAttempts.last)
    let boundary = await seeded.boundaryRuntime.snapshot(for: .simulated)
    let originalFrame = try #require(source.displayedFrame)
    let frame = DisplayedFrame(source: syntheticSource, frame: originalFrame.frame)
    let originalMachine = try #require(boundary.acceptedMachineArtifacts)
    let fixtureMachine = try LowerMachineSessionFixture(log: EventLog())
    let machine = try AcceptedMachineArtifactCheckpoint(
      checkpointID: originalMachine.checkpointID,
      controllerContext: ControllerCheckpointContext(probe: await fixtureMachine.passiveProbeResult()),
      machinePositionAtSave: originalMachine.machinePositionAtSave,
      controllerSessionID: originalMachine.controllerSessionID,
      coordinateRevision: originalMachine.coordinateRevision,
      acceptedAttemptSequence: originalMachine.acceptedAttemptSequence,
      pairedBoundaryProgress: originalMachine.pairedBoundaryProgress,
      acceptedBoundaryEvidence: originalMachine.acceptedBoundaryEvidence,
      boundarySideAggregates: originalMachine.boundarySideAggregates,
      estimatedMachineCenter: originalMachine.estimatedMachineCenter,
      learnedLocalCoordinateFrame: originalMachine.learnedLocalCoordinateFrame,
      centerArrivalPosition: originalMachine.centerArrivalPosition,
      acceptedRevisions: originalMachine.acceptedRevisions)
    // The learned-color identity is part of the accepted cap map. Preserve the
    // actual sampled appearance instead of inventing a generic green value.
    let appearance = try replacingFixtureSources(#require(source.penCapAppearanceSelection),
      with: syntheticSource)
    #expect(machineCamera.capAnchorEstimatorRevision
      == "selected-cap-\(appearance.color.hexRGB)-bottom-center-anchor-v3")
    let checkpoint = try AcceptedLearningPathCheckpoint(semanticIdentity: identities.learningPathIdentity,
      penInteraction: AcceptedPenInteractionCheckpoint(
        revision: #require(source.learningArtifactGraph.currentRevision(for: .penInteraction)),
        acceptedSequence: penAttempt.acceptedSequence, evidence: #require(penAttempt.value)),
      machineArtifacts: machine,
      machineCamera: AcceptedMachineCameraCheckpoint(
        revision: #require(source.learningArtifactGraph.currentRevision(for: .machineCameraRegistration)),
        registration: machineCamera),
      tipCalibration: AcceptedTipCalibrationCheckpoint(registration: tip,
        acceptanceEvent: TipCalibrationAcceptanceEvent(acceptedRevisionID: tip.acceptedRevisionID,
          timestamp: tip.acceptedAt, actor: "synthetic accepted-artifact fixture")),
      stageFour: AcceptedStageFourCheckpoint(recordID: record.recordID,
        tipCalibrationRevisionID: tip.acceptedRevisionID,
        paperContactPlane: record.paper.contactPlane),
      penCapAppearance: appearance.acceptedCheckpoint(),
      referenceFrame: AcceptedLearningReferenceFrame(
        opticalConfiguration: tip.applicability.opticalConfiguration, frame: frame.frame))
    _ = try checkpoint.restoredLearningGraph()
    let region = try #require(source.currentDrawableMachineRegion)
    let center = boundary.estimatedCenter
    await source.shutdown()
    return Self(identities: identities, checkpoint: checkpoint, borderRecord: record,
      frame: frame, drawableRegion: region, expectedCenter: center)
  }
}

/// Constructs fresh synthetic fixture identities; never rewrites user archives.
private func replacingFixtureSources<T: Codable>(_ value: T,
  with source: FrameSourceIdentity) throws -> T {
  let encoder = JSONEncoder()
  let replacement = try JSONSerialization.jsonObject(with: encoder.encode(source))
  func visit(_ value: Any) -> Any {
    if let object = value as? [String: Any] {
      return object.mapValues { visit($0) }.merging(object["source"] == nil ? [:] : ["source": replacement]) { _, new in new }
    }
    if let values = value as? [Any] { return values.map(visit) }
    return value
  }
  let object = try JSONSerialization.jsonObject(with: encoder.encode(value))
  return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: visit(object)))
}

@MainActor
final class CompleteAcceptedLearningStores {
  let directory: URL
  let checkpointStore: AcceptedLearningPathCheckpointStore
  let evidenceStore: DrawingRunEvidenceStore
  let evidencePort: DrawingRunEvidencePort

  init() {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    checkpointStore = AcceptedLearningPathCheckpointStore(fileURL: directory.appendingPathComponent("accepted.json"))
    evidenceStore = DrawingRunEvidenceStore(fileURL: directory.appendingPathComponent("drawings.json"))
    evidencePort = DrawingRunEvidencePort(store: evidenceStore)
  }

  func save(_ fixture: CompleteAcceptedLearningFixture,
    additionalRecords: [DrawingRunEvidenceRecord] = []) async throws {
    try checkpointStore.save(fixture.checkpoint)
    _ = try await evidenceStore.append(fixture.borderRecord)
    for record in additionalRecords { _ = try await evidenceStore.append(record) }
  }

  var persistence: TestApplicationStatePersistencePort {
    let checkpointStore = checkpointStore
    return TestApplicationStatePersistencePort(loadCheckpoint: { checkpointStore.load() },
      saveCheckpoint: { try checkpointStore.save($0) }, clearCheckpoint: { try checkpointStore.clear() })
  }

  func remove() { try? FileManager.default.removeItem(at: directory) }
}

@MainActor
func applyCompleteSavedLearning(_ application: PlotterApplicationRuntime) async throws {
  let projection = application.testPlotterUIProjection(
    selectedItemID: application.testCurrentLearningPathItemID, includesLearningPath: true)
  let action = try #require(projection.semantic.actions.first {
    if case .learningAction(let request) = $0.intent { return request.action == .applySavedLearning }
    return false
  })
  let request = try #require(projection.semantic.request(for: action.id))
  #expect(await application.submitPlotterUIRequest(request) == .accepted(requestID: request.id))
}
