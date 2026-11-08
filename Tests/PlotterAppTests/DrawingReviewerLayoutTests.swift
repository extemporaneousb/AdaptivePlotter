import AppKit
import Foundation
import PlotterModel
import PortraitStudioUI
import SwiftUI
import Testing
@testable import PlotterApp

@Suite("Current Drawing reviewer hosted layout", .serialized)
@MainActor
struct DrawingReviewerLayoutTests {
  @Test("Empty and source-free current-format reviewer fit an offscreen owned window")
  func currentReviewer() async throws {
    _ = NSApplication.shared
    let studio = DrawingFirstTestStorage.studio()
    let fixture = try await DrawingWorkbenchApplicationFixture.make(portraitStudio: studio)
    defer { fixture.stores.remove() }
    for populated in [false, true] {
      if populated {
        let program = try DrawingProgramCatalog.program(for: .line, style: portraitTestStyle())
        _ = try await studio.sketches.retain(drawingTestValue(program: program), reason: "save")
      }
      let size = NSSize(width: 1000, height: 700)
      let host = NSHostingController(rootView: DrawingReviewerView(application: fixture.application, close: {})
        .frame(width: size.width, height: size.height))
      let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.contentViewController = host
      window.orderFront(nil)
      host.view.layoutSubtreeIfNeeded()
      #expect(host.view.fittingSize.width <= size.width + 1)
      #expect(host.view.fittingSize.height <= size.height + 1)
      window.orderOut(nil); window.contentViewController = nil; window.close()
    }
    await fixture.application.shutdown(); await studio.library.closeLibrary()
  }
}
