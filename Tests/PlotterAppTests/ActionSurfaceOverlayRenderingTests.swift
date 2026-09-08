import AppKit
import PlotterModel
import PlotterRuntime
import SwiftUI
import Testing
@testable import PlotterApp

@Suite("Action Surface overlay rendering", .serialized)
@MainActor
struct ActionSurfaceOverlayRenderingTests {
  @Test("native Action Surface retains its dense overlay Canvas across video frames",
    .enabled(if: ProcessInfo.processInfo.environment["ACTION_SURFACE_RENDER_TEST"] == "1"))
  func nativeOverlayReuse() async throws {
    _ = NSApplication.shared
    let workspace = makeCausalSimulatorAppFixture().workspace
    let projection = workspace.testPlotterUIProjection(
      selectedItemID: .humanGuidedDiscovery(.penInteraction), includesLearningPath: true).semantic
    let diagnostics = ActionSurfacePreviewModel()
    let configuration = CameraConfigurationID()
    func frame(_ sequence: UInt64, configuration: CameraConfigurationID) throws -> DisplayedFrame {
      DisplayedFrame(source: .live(.init(rawValue: "render-fixture")), frame: try StampedFrame(
        sequence: sequence, captureNanoseconds: sequence,
        cameraConfigurationID: configuration, width: 2, height: 2, rowBytes: 8,
        pixelFormat: .bgra8, bytes: OwnedFrameBytes(Array(repeating: 255, count: 16))))
    }
    let measured = try frame(1, configuration: configuration)
    let overlay = CameraOverlayMeasurement(
      frameID: measured.frame.id, cameraConfigurationID: configuration,
      geometry: .polyline(try Polyline(points: (0...2_000).map {
        try Point2<CameraPixelSpace>(x: Double($0) / 1_000, y: Double($0 % 2))
      })), provenance: .init(kind: .intendedPath, source: .diagnostic, algorithmRevision: "render-test"))
    let base = ActionSurfacePresentation(displayedFrame: measured, overlays: [overlay])
    func surface(_ presentation: ActionSurfacePresentation) -> ActionSurface {
      ActionSurface(presentation: presentation, renderDiagnostics: diagnostics,
        plotterUIProjection: projection, plotterUIIntentSink: workspace)
    }
    let host = NSHostingView(rootView: surface(base))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    func render() async throws {
      host.layoutSubtreeIfNeeded()
      window.display()
      try await Task.sleep(for: .milliseconds(40))
      host.layoutSubtreeIfNeeded()
      host.display()
    }
    try await render()
    // Settle native layout and the initial exact-to-ambient presentation before
    // measuring steady preview traffic, as the signed-app gate does.
    host.rootView = surface(base.resolvingAmbientPreviewFrame(try frame(2, configuration: configuration)))
    try await render()
    try await Task.sleep(for: .milliseconds(200))
    try await render()
    let initialDraws = diagnostics.overlayCanvasDrawCount
    let initialBuilds = diagnostics.overlayCanvasBuildCount
    #expect(initialDraws > 0)
    for sequence in 3...32 {
      host.rootView = surface(base.resolvingAmbientPreviewFrame(
        try frame(UInt64(sequence), configuration: configuration)))
      try await render()
    }
    try #require(diagnostics.overlayCanvasDrawCount == initialDraws)
    #expect(diagnostics.overlayCanvasBuildCount == initialBuilds)
    host.setFrameSize(NSSize(width: 800, height: 600))
    try await render()
    let resizedDraws = diagnostics.overlayCanvasDrawCount
    #expect(resizedDraws > initialDraws)
    host.rootView = surface(base.resolvingAmbientPreviewFrame(
      try frame(33, configuration: CameraConfigurationID())))
    try await render()
    #expect(diagnostics.overlayCanvasDrawCount > resizedDraws)
    print("OVERLAY_RENDER: 30 advancing frames, 2001 points, zero Canvas redraws; resize and source configuration invalidate")
    await workspace.shutdown()
  }
}
