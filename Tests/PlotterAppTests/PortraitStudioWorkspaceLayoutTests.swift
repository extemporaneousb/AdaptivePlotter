import AppKit
import PlotterModel
import SwiftUI
import Testing
@testable import PlotterApp

/// Owned offscreen host only; no live camera, app replacement, or hardware use.
@Suite("Portrait Studio bounded workspace", .serialized)
@MainActor
struct PortraitStudioWorkspaceLayoutTests {
  @Test("grid and selected drawing fit with Styles and Adjustments folded or expanded",
    arguments: [false, true], [false, true])
  func controlsFit(expanded: Bool, detailsExpanded: Bool) async throws {
    _ = NSApplication.shared
    let model = PortraitStudioModel(renderer: WorkspaceLayoutRenderer())
    let stroke = try portraitTestStyle()
    model.setStyleComparisonExpanded(expanded, strokeStyle: stroke)
    model.setPhoto(try portraitTestImage(), for: .front, strokeStyle: stroke)
    await model.awaitRendering()
    try #require(model.algorithmCandidates.count == (expanded ? PortraitStyle.authoringCases.count : 1))
    for size in [CGSize(width: 1000, height: 550), CGSize(width: 1280, height: 650)] {
      for style in PortraitStyle.authoringCases {
        model.setStyleComparisonExpanded(false, strokeStyle: stroke)
        model.style = style
        model.renderIfNeeded(strokeStyle: stroke)
        await model.awaitRendering()
        let host = NSHostingController(rootView: PortraitStudioView(model: model,
          strokeStyle: stroke, showOnPlotter: { _ in nil }, showsAdjustments: detailsExpanded)
          .padding(12)
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
        try await settle(host.view)
        // Close the previous host before simulating disclosure input on this
        // one; its delayed onDisappear otherwise legitimately folds the model.
        model.setStyleComparisonExpanded(expanded, strokeStyle: stroke)
        await model.awaitRendering()
        await model.awaitExploration()
        try await settle(host.view)
        defer { window.close() }
        #expect(!window.isKeyWindow)
        #expect(model.isStyleComparisonExpanded == expanded)
        #expect(model.selectedCandidate?.recipe.style == style)
        let round = try #require(model.explorationRound)
        #expect(round.slots.count == 3)
        #expect(round.slots[1].candidate?.id == model.selectedCandidate?.id)
        #expect(abs(host.view.bounds.width - size.width) < 1)
        #expect(abs(host.view.bounds.height - size.height) < 1)
        let views = descendants(host.view)
        let scrolls = views.compactMap { $0 as? NSScrollView }
        let inspectorScrolls = scrolls.filter {
          $0.convert($0.bounds, to: host.view).minX >= host.view.bounds.maxX - 310
        }
        for scroll in scrolls {
          let document = try #require(scroll.documentView)
          let isInspector = detailsExpanded && inspectorScrolls.contains(scroll)
          #expect(isInspector || document.bounds.height <= scroll.contentView.bounds.height + 2,
            "Only detailed adjustments may scroll vertically in \(style.rawValue) at \(size): \(document.bounds) / \(scroll.contentView.bounds).")
        }
        let controls = views.compactMap { $0 as? NSControl }.filter {
          !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 0 && $0.bounds.height > 0
        }
        try #require(!controls.isEmpty)
        for control in controls {
          let rect = control.convert(control.bounds, to: host.view)
          let isInspector = detailsExpanded && inspectorScrolls.contains { control.isDescendant(of: $0) }
          #expect(rect.minX >= -2 && rect.maxX <= host.view.bounds.maxX + 2)
          #expect(isInspector || host.view.bounds.insetBy(dx: -2, dy: -2).contains(rect),
            "\(style.rawValue) control exceeds \(size): \(String(reflecting: type(of: control))) \(rect).")
        }
        if let directory = ProcessInfo.processInfo.environment["PORTRAIT_WORKSPACE_SNAPSHOT_DIR"] {
          try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
          let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
          host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
          let image = try #require(bitmap.cgImage)
          let index = try #require(PortraitStyle.authoringCases.firstIndex(of: style))
          try PortraitImageAnalyzer.encodedImage(image).write(to: URL(fileURLWithPath: directory)
            .appendingPathComponent("studio-\(Int(size.width))-style-\(index)-\(expanded ? "expanded" : "folded")-details-\(detailsExpanded ? "open" : "closed").png"))
          if detailsExpanded, style == .flowEdges {
            for scroll in inspectorScrolls {
              guard let document = scroll.documentView else { continue }
              let y = document.isFlipped
                ? max(0, document.bounds.height - scroll.contentView.bounds.height) : 0
              scroll.contentView.scroll(to: CGPoint(x: 0, y: y))
              scroll.reflectScrolledClipView(scroll.contentView)
            }
            try await settle(host.view)
            let lowerBitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
            host.view.cacheDisplay(in: host.view.bounds, to: lowerBitmap)
            let lowerImage = try #require(lowerBitmap.cgImage)
            try PortraitImageAnalyzer.encodedImage(lowerImage).write(to: URL(fileURLWithPath: directory)
              .appendingPathComponent("studio-\(Int(size.width))-flow-support-\(expanded ? "expanded" : "folded").png"))
          }
        }
      }
    }
    await model.shutdown()
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

private actor WorkspaceLayoutRenderer: PortraitRendering {
  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult {
    let raster = request.cachedRaster ?? portraitTestRaster()
    return .init(raster: raster, program: try PortraitVectorizer.program(from: raster,
      pose: request.pose, style: request.style, strokeStyle: request.strokeStyle,
      vectorOptions: request.vectorOptions))
  }
}
