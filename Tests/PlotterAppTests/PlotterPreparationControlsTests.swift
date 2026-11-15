import Foundation
import SwiftUI
import Testing
import PlotterModel
import PlotterUI
import PlotterEpisodeRuntime
@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Small plotter preparation controls", .serialized)
@MainActor
struct PlotterPreparationControlsTests {
  @Test("Saved Learning automatically verifies current camera position with Learning hidden/off")
  func savedLearningAutomaticallyRecoversPosition() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make(verifyPhysicalPose: false, restoreSavedLearning: false)
    defer { f.stores.remove() }
    let app = f.application
    await f.machine.setPenState(.up)
    _ = await app.refreshControllerSessionSnapshot()
    await app.submitTestPlotterUIAction(PlotterAppUIActionID.learningMode)
    let projection = app.testPlotterUIProjection(includesLearningPath: false).semantic
    let action = try #require(projection.actions.first {
      if case .learningAction(let request) = $0.intent { return request.action == .applySavedLearning }
      return false
    })
    let request = try #require(projection.request(for: action.id))
    let penCommands = await f.machine.requestedPenCommands
    #expect(await app.submitPlotterUIRequest(request) == .accepted(requestID: request.id))
    #expect(!app.controllerPoseApplicability.requiresPhysicalPositionForTest)
    #expect(app.positionRecoveryStatus == "Position verified from current camera evidence.")
    #expect(await f.camera.poseCaptureCount > 0)
    #expect(await f.machine.requestedPenCommands == penCommands)
    #expect(await f.machine.requestedFeeds.isEmpty)
    #expect(await f.machine.requestedDrawingStrokes.isEmpty)
    #expect(!app.testLearningIsEnabled)
    // The permanently available action supports another observation with Learning off.
    try await reestablishPhysicalPositionForTest(app)
    await app.shutdown()
  }

  @Test("failed automatic camera recovery retains Saved Learning and blocks Draw",
    arguments: [PhysicalPoseCaptureMode.unavailable, .wrongConfiguration])
  func automaticRecoveryFailure(_ mode: PhysicalPoseCaptureMode) async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make(verifyPhysicalPose: false, restoreSavedLearning: false)
    defer { f.stores.remove() }
    let app = f.application
    await f.machine.setPenState(.up)
    _ = await app.refreshControllerSessionSnapshot()
    await f.camera.configurePoseCapture(mode: mode)
    try await applyCompleteSavedLearning(app)
    #expect(app.interactiveLearningIsComplete)
    #expect(app.tipCameraRegistration == f.accepted.registration)
    #expect(app.controllerPoseApplicability.requiresPhysicalPositionForTest)
    #expect(app.positionRecoveryStatus?.contains("Position not verified") == true)
    #expect(app.testPlotterUIProjection().semantic.request(matching: .drawingRun(.start)) == nil)
    #expect(await f.machine.requestedPenCommands.isEmpty)
    #expect(await f.machine.requestedFeeds.isEmpty)
    await app.shutdown()
  }

  @Test("an unsettled pen prevents automatic recovery without implicitly raising it")
  func automaticRecoveryWaitsForPen() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make(verifyPhysicalPose: false)
    defer { f.stores.remove() }
    #expect(f.application.controllerPoseApplicability.requiresPhysicalPositionForTest)
    #expect(f.application.positionRecoveryStatus?.contains("Raise the pen first") == true)
    #expect(await f.camera.poseCaptureCount == 0)
    #expect(await f.machine.requestedPenCommands.isEmpty)
    await f.application.shutdown()
  }

  @Test("one Paper confirmation preserves or replaces the sheet and uses current coverage",
    arguments: [false, true])
  func combinedPaperConfirmation(replacingSheet: Bool) async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make()
    defer { f.stores.remove() }
    let app = f.application
    let paper = app.currentPaperRevisionContext
    let registration = app.tipCameraRegistration
    let pose = app.controllerPoseApplicability
    let history = app.drawingEvidenceArchive
    let projection = app.testPlotterUIProjection().semantic
    let request = try #require(projection.request(for:
      PlotterAppUIActionID.paperConfirmation(replacingSheet: replacingSheet)))
    #expect(await app.submitPlotterUIRequest(request) == .accepted(requestID: request.id))
    #expect(app.paperCoverageIsCurrent)
    #expect((app.currentPaperRevisionContext.instance != paper.instance) == replacingSheet)
    #expect(app.currentPaperRevisionContext.contactPlane == paper.contactPlane)
    #expect(app.tipCameraRegistration == registration)
    #expect(app.controllerPoseApplicability == pose)
    #expect(app.drawingEvidenceArchive == history)
    #expect(await f.machine.requestedFeeds.isEmpty)
    #expect(await f.machine.requestedPenCommands.isEmpty)
    await app.shutdown()
  }

  @Test("failed combined coverage retains the committed new sheet and an explicit remedy")
  func combinedPaperFailureIsVisibleAndRetryable() async throws {
    let paper = PreparationPaperPersistence()
    let f = try await DrawingWorkbenchApplicationFixture.make(paperPersistence: paper)
    defer { f.stores.remove() }
    let app = f.application
    let previous = app.currentPaperRevisionContext
    let projection = app.testPlotterUIProjection().semantic
    let request = try #require(projection.request(for: PlotterAppUIActionID.paperConfirmation(replacingSheet: true)))
    guard case .refused = await app.submitPlotterUIRequest(request) else {
      Issue.record("Expected coverage persistence to refuse confirmation"); await app.shutdown(); return
    }
    let replacement = app.currentPaperRevisionContext
    #expect(replacement.instance != previous.instance)
    #expect(!app.paperCoverageIsCurrent)
    #expect(app.paperConfirmationFailure?.contains("persistence") == true)
    await paper.allowSave()
    let retryProjection = app.testPlotterUIProjection().semantic
    let retry = try #require(retryProjection.request(for: PlotterAppUIActionID.paperConfirmation(replacingSheet: false)))
    #expect(await app.submitPlotterUIRequest(retry) == .accepted(requestID: retry.id))
    #expect(app.currentPaperRevisionContext == replacement)
    #expect(app.paperCoverageIsCurrent)
    #expect(app.paperConfirmationFailure == nil)
    await app.shutdown()
  }

  @Test("combined Paper confirmation retains the clicked frame across a slow replacement save")
  func paperConfirmationRetainsClickedFrame() async throws {
    let gate = TestInspectionSuspension()
    let paper = PreparationPaperPersistence(clearGate: gate)
    await paper.allowSave()
    let f = try await DrawingWorkbenchApplicationFixture.make(paperPersistence: paper)
    defer { f.stores.remove() }
    let app = f.application
    let clicked = try #require(app.testActionSurfacePresentation.displayedFrame)
    await gate.arm()
    let projection = app.testPlotterUIProjection().semantic
    let request = try #require(projection.request(for: PlotterAppUIActionID.paperConfirmation(replacingSheet: true)))
    let confirmation = Task { await app.submitPlotterUIRequest(request) }
    do {
      try await waitUntilAsync { await gate.isWaiting }
      let advanced = try await f.camera.publishNextFrame()
      try await waitUntil { app.actionSurfacePreview.latestFrameSnapshot?.frame.id == advanced.frame.id }
      #expect(advanced.frame.id != clicked.frame.id)
      await gate.release()
      #expect(await confirmation.value == .accepted(requestID: request.id))
      #expect(app.drawingDraftSnapshot.paperCoverageObservation?.frame.frameID == clicked.frame.id)
      #expect(app.paperCoverageIsCurrent)
      await app.shutdown()
    } catch {
      await gate.release()
      _ = await confirmation.value
      await app.shutdown()
      throw error
    }
  }

  @Test("a failed repeat camera check revokes prior position trust")
  func repeatRecoveryFailureInvalidatesPosition() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make()
    defer { f.stores.remove() }
    let app = f.application
    #expect(!app.controllerPoseApplicability.requiresPhysicalPositionForTest)
    await f.machine.setPenState(.up)
    _ = await app.refreshControllerSessionSnapshot()
    await f.camera.configurePoseCapture(mode: .unavailable)
    let request = try physicalPositionRequest(app)
    guard case .refused = await app.submitPlotterUIRequest(request) else {
      Issue.record("Expected failed camera evidence to refuse recovery"); await app.shutdown(); return
    }
    #expect(app.controllerPoseApplicability.requiresPhysicalPositionForTest)
    #expect(app.positionRecoveryStatus?.contains("Position not verified") == true)
    #expect(await f.machine.requestedFeeds.isEmpty)
    #expect(await f.machine.requestedPenCommands.isEmpty)
    await app.shutdown()
  }

  @Test("Draw exposes the same blocker as its current admission, including simultaneous prerequisites")
  func drawExplainsReadiness() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make(verifyPhysicalPose: false)
    defer { f.stores.remove() }
    let app = f.application
    _ = await app.currentDrawingRunFacts(for: .live)
    _ = await f.runRuntime.synchronize(environment: .live)
    let view = DrawingStudioView(presentation: app.drawingStudioPresentation,
      plotterUIProjection: app.testPlotterUIProjection().semantic, plotterUIIntentSink: app)
    #expect(view.drawRequest == nil)
    #expect(view.drawUnavailableReason?.isEmpty == false)
    #expect(view.drawUnavailableReason?.contains("position") == true)
    #expect(view.drawUnavailableReason?.contains("Paper") == true)
    await app.shutdown()
  }

  @Test("a disabled request never lacks an explanation")
  func disabledRequestExplanation() {
    let button = OperatorRequestButton(title: "Action", request: nil,
      unavailableReason: "Select a drawing first.", sink: PreparationNoopSink())
    #expect(button.disabledReason == "Select a drawing first.")
    let missing = OperatorRequestButton(title: "Action", request: nil,
      unavailableReason: nil, sink: PreparationNoopSink())
    #expect(missing.disabledReason?.isEmpty == false)
  }
}

@MainActor
private final class PreparationNoopSink: PlotterUIIntentSink {
  func submitPlotterUIRequest(_ request: PlotterUIRequest) async -> PlotterUIRequestDisposition {
    .accepted(requestID: request.id)
  }
}

private actor PreparationPaperPersistence: PlotterDrawingDraftPaperPersistence {
  enum Failure: Error { case save }
  private var fails = true
  private let clearGate: TestInspectionSuspension?
  init(clearGate: TestInspectionSuspension? = nil) { self.clearGate = clearGate }
  private var observation: PaperCoverageObservation?
  func load() -> PaperCoverageObservation? { observation }
  func clear() async { await clearGate?.waitIfArmed(); observation = nil }
  func allowSave() { fails = false }
  func save(_ value: PaperCoverageObservation) throws {
    if fails { throw Failure.save }
    observation = value
  }
}
