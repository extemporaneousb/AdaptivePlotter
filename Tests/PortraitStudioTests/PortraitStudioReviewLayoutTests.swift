import AppKit
import SwiftUI
import Testing
@testable import PortraitStudio

/// Hosted geometry only; it does not assert attended keyboard/mouse use.
@Suite("Compact Review hosted layout", .serialized)
@MainActor
struct PortraitStudioReviewLayoutTests {
  @Test("Collapsed review hosts navigation and scoring without a main vertical scroller at supported widths")
  func compactGeometry() async throws {
    _ = NSApplication.shared
    let fixture = try await ReviewNavigationFixture.make(count: 2)
    defer { fixture.remove() }
    let model = PortraitStudioReviewModel(store: fixture.store)
    await model.reload()
    for width in [900.0, 1200.0] {
      let size = NSSize(width: width, height: 650)
      let host = NSHostingController(rootView: PortraitStudioReviewView(model: model))
      host.sizingOptions = []
      let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentViewController = host
      window.setContentSize(size)
      window.orderFront(nil)
      for _ in 0..<3 { host.view.layoutSubtreeIfNeeded(); await Task.yield() }
      await model.waitForOperation()
      host.view.layoutSubtreeIfNeeded()
      #expect(!window.isKeyWindow)
      #expect(abs(host.view.bounds.width - size.width) < 2)
      #expect(abs(host.view.bounds.height - size.height) < 2)
      let controls = Self.views(host.view).compactMap { $0 as? NSControl }.filter {
        !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 0 && $0.bounds.height > 0
      }
      #expect(!controls.isEmpty)
      for control in controls {
        let rect = control.convert(control.bounds, to: host.view)
        #expect(host.view.bounds.insetBy(dx: -2, dy: -2).contains(rect),
          "Visible Review control clipped: \(rect) in \(host.view.bounds)")
      }
      for scroll in Self.views(host.view).compactMap({ $0 as? NSScrollView }).filter({ !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 0 && $0.bounds.height > 0 }) {
        let rect = scroll.convert(scroll.bounds, to: host.view)
        if rect.minX > 220 {
          let document = try #require(scroll.documentView)
          #expect(document.bounds.height <= scroll.contentView.bounds.height + 2,
            "Collapsed main Review unexpectedly scrolls vertically.")
        }
      }
      if let root = ProcessInfo.processInfo.environment["PORTRAIT_REVIEW_SNAPSHOT_ROOT"] {
        let directory = URL(fileURLWithPath: root, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
        host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("review-\(Int(width))-collapsed.png"), options: .atomic)
      }
      window.close()
    }
    await model.shutdown()
  }

  private static func views(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(views) }
}
