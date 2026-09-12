import Foundation
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import Testing
@testable import PlotterApp

@Suite("Automatic Border completion", .serialized)
@MainActor
struct DrawingBorderCompletionTests {
  @Test("inconclusive Vision graduates a completed drawing and retains the exact rejection")
  func completedDrawingRetainsInconclusiveObservation() async throws {
    // This existing camera fixture rejects planned-drawing observation with
    // unsupportedDrawing. Motion and calibration still use causal simulation.
    let camera = try TestObservationCameraSession()
    let harness = makeCausalSimulatorAppFixture(observationSession: resolvedObservationSession(camera))
    let workspace = harness.workspace
    try await completeSimulatedPenInteractionPrerequisite(workspace)
    try await installAcceptedBoundaryTestProjection(
      runtime: harness.boundaryRuntime, workspace: workspace, environment: .simulated
    )
    try await completeSimulatedTipCalibration(workspace, simulator: harness.simulator)
    let owner = LearningPathItemID.borderValidation(.chooseDrawingBorderPlan)
    let beforeInk = await harness.simulator.persistentInk().count
    await workspace.performTestExerciseAction(.start, for: owner)
    let snapshot = workspace.borderValidationSnapshot
    #expect(snapshot.assessment == .drawingCompleted)
    #expect(snapshot.phase == .accepted)
    #expect(snapshot.inkObservation == nil)
    #expect(snapshot.observationRejection?.reason == .unsupportedDrawing)
    #expect(snapshot.terminalHistory.last?.detail.contains("unsupportedDrawing") == true)
    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.currentExerciseActionStripPresentation == nil)
    #expect(workspace.workbenchCapabilityPresentation.learning == .interactiveLearningComplete)
    #expect(workspace.workbenchCapabilityPresentation.learning == .interactiveLearningComplete)
    #expect(await harness.simulator.persistentInk().count > beforeInk)
    #expect(!workspace.learningArtifactGraph.revisions.contains {
      if case .comparison = $0.kind { return $0.state == .current }
      return false
    })
    let projection = workspace.testPlotterUIProjection(selectedItemID: owner, includesLearningPath: true).semantic
    let diagnostic = WorkbenchDebugSnapshot(application: workspace, projection: projection)
    #expect(diagnostic.diagnostics.contains { $0.contains("unsupportedDrawing") })
    let registration = try #require(workspace.tipCameraRegistration)
    let record = try #require(try DrawingBorderEvidence.record(
      snapshot: snapshot, attemptID: .init(), registration: registration,
      paper: workspace.currentPaperRevisionContext,
      nowNanoseconds: snapshot.postFrame?.frame.captureNanoseconds ?? 0
    ))
    #expect(record.executionDisposition == .completed)
    #expect(record.evidenceDisposition == .visionUnclear)
    #expect(record.executionFrontiers.inkVerifiedStrokeCount == 0)
    #expect(record.observation == .rejected(try #require(snapshot.observationRejection)))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = DrawingRunEvidenceStore(fileURL: directory.appendingPathComponent("evidence.json"))
    _ = try await store.append(record)
    guard case .loaded(let archive) = await store.load() else {
      Issue.record("Completed trial was not retained")
      await workspace.shutdown()
      return
    }
    #expect(archive.records == [record])
    await workspace.shutdown()
  }
}
