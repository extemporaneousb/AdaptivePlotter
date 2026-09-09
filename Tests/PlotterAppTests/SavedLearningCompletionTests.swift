import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import Testing
@testable import PlotterApp

@Suite("Complete saved Learning restoration", .serialized)
@MainActor
struct SavedLearningCompletionTests {
  @Test("production Apply Saved restores every accepted milestone and Border completion with Unknown or Down pen",
    arguments: [PenState.unknown, .down])
  func completeSavedPackageDoesNotReplayLearning(_ penState: PenState) async throws {
    // Synthetic accepted artifacts are generated separately; this workspace
    // only exercises ordinary persisted startup and the projected Apply action.
    let fixture = try await CompleteAcceptedLearningFixture.make()
    let checkpoint = fixture.checkpoint
    let record = fixture.borderRecord
    let tip = fixture.registration
    let expectedGraph = try checkpoint.restoredLearningGraph()
    let stores = CompleteAcceptedLearningStores()
    defer { stores.remove() }
    try await stores.save(fixture)
    let checkpointStore = stores.checkpointStore
    let evidenceStore = stores.evidenceStore

    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    await machine.setPenState(penState)
    let restored = plotterApplicationRuntime(machine: machine, statePersistencePort: stores.persistence,
      drawingEvidencePort: stores.evidencePort,
      tipCalibrationSemanticIdentities: fixture.identities,
      loadPenCapAppearanceSelection: { nil }, log: log)
    // Startup loads the existing archive even before a fresh camera is chosen.
    // No new optical context or pen pose is fabricated during restoration.
    await restored.performApplicationStartup(AdaptivePlotterLaunchPolicy(arguments: []))
    await restored.establishMachineSession(machine.descriptor)
    await submitControllerSession(restored, .requestPassiveProbe)
    let beforeApply = await log.values
    try await applyCompleteSavedLearning(restored)
    // Graph enumeration is dictionary order; compare every complete typed
    // revision and its current-kind lookup, including dependency identities.
    #expect(restored.learningArtifactGraph.revisions.count == expectedGraph.revisions.count)
    #expect(Set(restored.learningArtifactGraph.revisions) == Set(expectedGraph.revisions))
    for revision in expectedGraph.revisions {
      #expect(restored.learningArtifactGraph.revision(id: revision.id) == revision)
      #expect(restored.learningArtifactGraph.currentRevision(for: revision.kind)
        == expectedGraph.currentRevision(for: revision.kind))
    }
    #expect(restored.penInteractionCompleted)
    #expect(restored.testAcceptedBoundaryAggregates.count == 4)
    #expect(restored.testEstimatedMachineCenter == fixture.expectedCenter)
    #expect(restored.machineCameraRegistration == checkpoint.machineCamera?.registration)
    #expect(restored.tipCameraRegistration == tip)
    #expect(try restored.penCapAppearanceSelection?.acceptedCheckpoint() == checkpoint.penCapAppearance)
    #expect(restored.artifactResetEpisodeSnapshot.savedLearning.appliedCheckpoint?.checkpointID == checkpoint.checkpointID)
    #expect(restored.borderValidationSnapshot.assessment == .predictionObserved)
    #expect(restored.interactiveLearningIsComplete)
    #expect(restored.currentExerciseActionStripPresentation == nil)
    #expect(restored.learningPathItemPresentations.allSatisfy { $0.status == .complete })
    #expect(restored.activeExerciseAttemptID == nil)
    #expect(restored.testActionSurfacePresentation.pointSelectionRequest == nil)
    #expect(await log.values == beforeApply)
    #expect((await machine.snapshot()).machine.penState == penState)
    guard case .loaded(let savedAgain) = checkpointStore.load() else {
      Issue.record("The accepted package was not retained after application")
      await restored.shutdown()
      return
    }
    #expect(savedAgain.checkpointID == checkpoint.checkpointID)
    guard case .loaded(let archive) = await evidenceStore.load() else {
      Issue.record("The accepted Border archive was not retained")
      await restored.shutdown()
      return
    }
    #expect(archive.records == [record])
    await restored.shutdown()
  }
}
