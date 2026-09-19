import AppKit
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import SwiftUI
import Testing
@testable import PlotterApp

/// Offscreen views use fixture cameras/controllers exclusively. No running app
/// or physical device is selected, replaced, or operated by these checks.
@Suite("Drawing Reviewer hosted layout", .serialized)
@MainActor
struct DrawingReviewerLayoutTests {
  @Test("empty, saved and generic result reviewer controls fit at 1000 by 700")
  func minimumReviewerGeometry() async throws {
    _ = NSApplication.shared
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let application = fixture.application
    do {
      try await inspect(application, stage: "empty")
      let basis = try portraitPersistenceCandidate(seed: 924)
      let saved = try PortraitCandidate(sourceData: portraitTestImage(),
        sourcePixelExtent: .init(widthPixels: 60, heightPixels: 80), raster: basis.raster,
        recipe: basis.recipe, program: basis.program, photoID: basis.photoID,
        captureSessionID: basis.captureSessionID)
      #expect(application.portraitStudio.sketches.retain(candidate: saved, reason: .shortlisted) == nil)
      await application.portraitStudio.sketches.awaitPersistence()
      try await inspect(application, stage: "saved")

      try await fixture.submit(.fitInDrawableRegion)
      try await fixture.submit(.assertPaperCoverage)
      try await waitFor { application.drawingRunSnapshot?.readiness == .ready }
      await fixture.planGate.release(.possibleInk)
      let draw = try #require(application.testPlotterUIProjection().semantic.request(matching: .drawingRun(.start)))
      #expect(await application.submitPlotterUIRequest(draw) == .accepted(requestID: draw.id))
      try await waitFor { !application.drawingReviewRecords.isEmpty }
      try await inspect(application, stage: "result")
      await application.shutdown()
    } catch {
      await application.shutdown()
      throw error
    }
  }

  private func inspect(_ application: PlotterApplicationRuntime, stage: String) async throws {
    let size = CGSize(width: 1000, height: 700)
    let host = NSHostingController(rootView: DrawingReviewerView(application: application, close: {},
      showOnPlotter: { _ in nil })
      .frame(width: size.width, height: size.height)
      .background(Color(nsColor: .windowBackgroundColor))
      .environment(\.colorScheme, .light))
    host.sizingOptions = []
    let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .aqua)
    window.backgroundColor = .windowBackgroundColor
    window.contentViewController = host
    window.setContentSize(size)
    window.orderFront(nil)
    defer { window.close() }
    try await settle(host.view)
    #expect(!window.isKeyWindow)
    #expect(abs(host.view.bounds.width - size.width) < 1)
    #expect(abs(host.view.bounds.height - size.height) < 1)
    let controls = descendants(host.view).compactMap { $0 as? NSControl }.filter {
      !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 0 && $0.bounds.height > 0
    }
    try #require(!controls.isEmpty)
    for control in controls {
      let bounds = control.convert(control.bounds, to: host.view)
      #expect(host.view.bounds.insetBy(dx: -2, dy: -2).contains(bounds),
        "Reviewer \(stage) control clipped: \(String(reflecting: type(of: control))) \(bounds).")
    }
    if let directory = ProcessInfo.processInfo.environment["PORTRAIT_WORKSPACE_SNAPSHOT_DIR"] {
      try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
      let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
      host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
      let image = try #require(bitmap.cgImage)
      try PortraitImageAnalyzer.encodedImage(image).write(to: URL(fileURLWithPath: directory)
        .appendingPathComponent("reviewer-1000-\(stage).png"))
    }
  }

  private func waitFor(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !condition() {
      try #require(ContinuousClock.now < deadline)
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  private func settle(_ view: NSView) async throws {
    // onAppear may insert a selected detail view; its task starts on a later
    // layout pass, so allow several actual layout/render cycles before capture.
    for _ in 0..<8 {
      view.window?.layoutIfNeeded()
      view.layoutSubtreeIfNeeded()
      view.window?.displayIfNeeded()
      view.displayIfNeeded()
      try await Task.sleep(for: .milliseconds(50))
    }
    view.layoutSubtreeIfNeeded()
    view.window?.displayIfNeeded()
    view.displayIfNeeded()
  }

  private func descendants(_ root: NSView) -> [NSView] {
    [root] + root.subviews.flatMap(descendants)
  }
}
