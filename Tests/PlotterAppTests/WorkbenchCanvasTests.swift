import Foundation
import PlotterModel
import PlotterRuntime
import Testing
@testable import PlotterApp

@Suite("Permanent canvas")
struct WorkbenchCanvasTests {
  @Test("last camera image stays visible; only an explicit simulator uses the fallback")
  func sourceSelection() {
    #expect(WorkbenchCanvasContent.select(plotterFrameAvailable: false, isSimulated: true) == .simulationPreview)
    #expect(WorkbenchCanvasContent.select(plotterFrameAvailable: true, isSimulated: false) == .plotter)
    #expect(WorkbenchCanvasContent.select(plotterFrameAvailable: false, isSimulated: false) == .waitingForCamera)
  }

  @MainActor
  @Test("Live startup without pixels stays live and reports missing or ambiguous cameras", arguments: [0, 1, 2])
  func liveStartupWithoutFrames(cameraCount: Int) async throws {
    let driver = CanvasStartupCameraDriver(devices: (0..<cameraCount).map {
      CameraDevice(id: .init(rawValue: "camera-\($0)"), name: "Camera \($0)")
    })
    let vision = VisionWorker()
    let session = CameraSourceSession(live: CameraCapture(driver: driver), vision: vision,
      analysisPipeline: PlotterSceneAnalysisPipeline(worker: vision), plannedDrawingObserver: vision)
    let fixture = try PlotterApplicationFixture(observationSessionOverride: session)
    let app = fixture.application
    await app.performApplicationStartup(.init(arguments: []))
    #expect(app.frameMode == .live)
    #expect(app.workbenchCanvasPresentation.content == .waitingForCamera)
    #expect(await driver.startCount == (cameraCount == 1 ? 1 : 0))
    if cameraCount == 0 {
      #expect(app.cameraSnapshot?.error == .noDevices)
      #expect(app.cameraError == CameraCaptureError.noDevices.actionableDescription)
    }
    if cameraCount == 2 { #expect(app.cameraError?.contains("Multiple cameras detected") == true) }
    await app.shutdown()
  }

  @MainActor
  @Test("fallback image leaves live execution, Learning and semantic publications unchanged")
  func fallbackHasNoOperationalEffects() async throws {
    let application = makeCausalSimulatorAppFixture().workspace
    // Compose and settle the existing Draft -> Run publication chain before
    // taking the baseline. Rendering awaits must not include fixture startup.
    await application.drawingDraftSynchronizationTask?.value
    let mode = application.frameMode
    let projection = application.testPlotterUIProjection(includesLearningPath: true).semantic
    let episode = application.learningEpisodeRecord
    let draft = application.drawingDraftSnapshot
    let before = application.semanticPresentationRevision
    let frame = try #require(await application.canvasSimulationPreview())
    guard case .simulated = frame.source else { Issue.record("Fallback must be identified as simulation"); return }
    #expect(application.frameMode == mode)
    #expect(application.semanticPresentationRevision == before)
    #expect(application.learningEpisodeRecord.entries == episode.entries)
    #expect(application.drawingDraftSnapshot == draft)
    #expect(application.testPlotterUIProjection(includesLearningPath: true).semantic.actions == projection.actions)
    await application.shutdown()
  }

  @Test("passive simulator rendering preserves causal frame counters")
  func previewDoesNotCapture() async throws {
    let runtime = SimulatedLearningRuntime()
    let before = await runtime.snapshot()
    _ = try await runtime.previewSceneFrame().get()
    _ = try await runtime.previewSceneFrame().get()
    #expect(await runtime.snapshot() == before)
  }
}

private actor CanvasStartupCameraDriver: CameraCaptureDriver {
  let devices: [CameraDevice]
  private(set) var startCount = 0
  init(devices: [CameraDevice]) { self.devices = devices }
  func authorizationState() async -> CameraAuthorizationState { .authorized }
  func requestAccess() async -> Bool { true }
  func discoverDevices() async -> [CameraDevice] { devices }
  func start(deviceID: CameraDeviceID, maximumFramesPerSecond: Double?,
    eventHandler: @escaping @Sendable (CameraDriverEvent) -> Void) async throws -> CameraCaptureDriverStartResult {
    startCount += 1
    return .init(appliedMaximumFramesPerSecond: maximumFramesPerSecond)
  }
  func stop() async {}
}
