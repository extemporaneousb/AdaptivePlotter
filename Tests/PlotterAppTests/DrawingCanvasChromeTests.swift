import AppKit
import SwiftUI
import Testing
import Vision
@testable import PlotterApp

@Suite("Drawing canvas controls", .serialized)
@MainActor
struct DrawingCanvasChromeTests {
  @Test("full workbench canvas keeps movement and visibility controls clear of calibration captions",
    .enabled(if: ProcessInfo.processInfo.environment["ACTION_SURFACE_RENDER_TEST"] == "1"))
  func calibrationCaptionDoesNotCoverControls() async throws {
    _ = NSApplication.shared
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let app = fixture.application
    do {
      try await fixture.submit(.showTarget)
      try #require(app.drawingPositioningUnavailableReason == nil)
      let frame = try #require(app.workbenchCanvasPresentation.displayedFrame)
      try #require(app.sparseTipGuideDetail(on: frame) != nil)
      for width in [420, 900] {
        let view = WorkbenchCameraCanvas(application: app,
          semantic: app.testPlotterUIProjection().semantic,
          viewport: .constant(ActionSurfaceViewportState()),
          pendingDrawingPlacement: .constant(nil), pendingPointSelection: .constant(nil))
          .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: .init(x: -10000, y: -10000, width: width, height: 600),
          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        host.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
        host.layoutSubtreeIfNeeded(); window.display(); host.display()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: "/tmp/drawing-canvas-chrome-\(width).png"))
        let image = try #require(bitmap.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: image).perform([request])
        let text = (request.results ?? []).compactMap { observation in
          observation.topCandidates(1).first.map { ($0.string, observation.boundingBox) }
        }
        func box(_ phrase: String) throws -> CGRect {
          try #require(text.first { $0.0.contains(phrase) }?.1,
            "Missing visible \(phrase) at \(width) pt. Recognized: \(text.map(\.0))")
        }
        let move = try box("Move Drawing"), hide = try box("Hide Drawing")
        let caption = try box("Calibration circles")
        // Vision uses a bottom-left origin. Captions must be below both controls.
        #expect(caption.maxY < min(move.minY, hide.minY))
        #expect(!move.intersects(hide))
      }
      let feeds = await fixture.machine.requestedFeeds
      let penCommands = await fixture.machine.requestedPenCommands
      let editID = UUID()
      #expect(await app.beginDrawingFrameEdit(id: editID, on: frame))
      #expect(app.drawingFrameEditSession?.id == editID)
      app.endDrawingFrameEdit(id: editID)
      #expect(await fixture.machine.requestedFeeds == feeds)
      #expect(await fixture.machine.requestedPenCommands == penCommands)
      await app.shutdown()
    } catch {
      await app.shutdown()
      throw error
    }
  }
}
