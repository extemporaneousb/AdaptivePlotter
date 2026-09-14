import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterUI
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Application-owned unified Voice", .serialized)
@MainActor
struct WorkbenchVoiceProductionTests {
  @Test("the application switch gates both actual Pen cues and recognition", arguments: [false, true])
  func productionPenCues(enabled: Bool) async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let listener = TestVoiceListener()
    let speech = ScriptedSpeechAnnouncer(log: log, outcomes: [])
    let app = plotterApplicationRuntime(machine: machine, camera: camera,
      speechAnnouncer: speech, speechOutputEnabled: false, workbenchVoiceListener: listener, log: log)
    let voice = app.workbenchVoiceController
    #expect(voice === app.workbenchVoiceController)
    #expect(!voice.isEnabled)
    do {
      await app.establishMachineSession(machine.descriptor)
      await submitControllerSession(app, .requestPassiveProbe)
      await submitObservationConfigurationForTest(app, .selectSource(.live, nil))
      let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
      await app.performTestExerciseAction(.start, for: owner)
      let selection = try #require(app.testActionSurfacePresentation.pointSelectionRequest)
      let frame = try #require(app.testActionSurfacePresentation.displayedFrame)
      submitPointSelection(app, request: selection, point: try Point2(
        x: Double(frame.frame.width - 1) / 2, y: Double(frame.frame.height - 1) / 2))
      try await waitUntil { app.activeDiscoverySequenceID == .penInteraction }
      updateProductionPenVoiceContext(app)
      voice.setEnabled(enabled)
      if enabled { try await waitUntil { voice.isListening } }
      for _ in 0..<3 {
        await app.performTestExerciseAction(.choice(.yes), for: owner)
        updateProductionPenVoiceContext(app)
      }
      #expect(app.penInteractionCompleted)
      #expect(await machine.requestedPenCommands == [.lower, .raise])
      let events = await log.values
      #expect(events.contains("announce:Lowering the pen.") == enabled)
      #expect(events.contains("announce:Raising the pen.") == enabled)
      #expect((listener.startCount > 0) == enabled)
      voice.setEnabled(false)
      #expect(!voice.isListening)
      #expect(voice === app.workbenchVoiceController)
      await app.shutdown()
      #expect(!voice.isEnabled)
      #expect(!voice.isListening)
      let afterShutdown = await app.speechEffectRuntime.snapshot()
      #expect(afterShutdown.admissionClosed)
      #expect(afterShutdown.activeRequests.isEmpty)
    } catch {
      await app.shutdown()
      throw error
    }
  }
}

/// Mirrors the existing view's current Pen action strip using the actual typed
/// application projection. It neither compiles actions nor supplies fake Stop.
@MainActor
func updateProductionPenVoiceContext(_ app: PlotterApplicationRuntime) {
  let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
  let semantic = app.testPlotterUIProjection(selectedItemID: owner, includesLearningPath: true).semantic
  let presentation = app.selectedOperatorActionPresentation(for: owner)
  app.workbenchVoiceController.update(WorkbenchVoiceContext(presentation: presentation,
    projection: semantic, actionStrip: presentation.actionStrip))
}
