import AppKit
import PlotterModel
import SwiftUI
import Testing
@testable import PlotterApp

/// Owned offscreen host only; no live camera, app replacement, or hardware use.
@Suite("Portrait Studio bounded workspace", .serialized)
@MainActor
struct PortraitStudioWorkspaceLayoutTests {
  @Test("one portrait fits with a persistent parameter panel and navigation",
    arguments: [PortraitStyle.contours, .flowEdges], [false, true])
  func controlsFit(style: PortraitStyle, detailsExpanded: Bool) async throws {
    _ = NSApplication.shared
    let model = PortraitStudioModel(renderer: WorkspaceLayoutRenderer())
    let stroke = try portraitTestStyle()
    model.setPhoto(try portraitTestImage(), for: .left, strokeStyle: stroke)
    model.setPhoto(try portraitTestImage(), for: .right, strokeStyle: stroke)
    model.setPhoto(try portraitTestImage(), for: .front, strokeStyle: stroke)
    await model.awaitRendering()
    model.saveStyle(name: "Saved layout recipe")
    #expect(model.browsablePhotos.count >= 3)
    #expect(!model.isExploring)
    for size in [CGSize(width: 1000, height: 550), CGSize(width: 1280, height: 650)] {
      do {
        model.resetStyle(style, strokeStyle: stroke)
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
        let calls = model.renderDiagnostics.startedWorkerCount
        await model.awaitRendering()
        try await settle(host.view)
        defer { window.close() }
        #expect(!window.isKeyWindow)
        #expect(model.selectedCandidate?.recipe.style == style)
        #expect(!model.isExploring)
        #expect(model.renderDiagnostics.startedWorkerCount == calls)
        #expect(abs(host.view.bounds.width - size.width) < 1)
        #expect(abs(host.view.bounds.height - size.height) < 1)
        let views = descendants(host.view)
        let scrolls = views.compactMap { $0 as? NSScrollView }
        let inspectorScrolls = scrolls.filter {
          $0.convert($0.bounds, to: host.view).minX >= host.view.bounds.maxX - 310
        }
        for scroll in scrolls {
          let document = try #require(scroll.documentView)
          let isInspector = inspectorScrolls.contains(scroll)
          #expect(isInspector || document.bounds.height <= scroll.contentView.bounds.height + 2,
            "Only detailed adjustments may scroll vertically in \(style.rawValue) at \(size): \(document.bounds) / \(scroll.contentView.bounds).")
        }
        let parameterScroll = try #require(inspectorScrolls.first { scroll in
          descendants(scroll).contains { $0 is NSSlider }
        }, "The native parameter controls must have their own inspector viewport.")
        try assertCoreParametersVisible(in: parameterScroll, style: style, size: size)
        let controls = views.compactMap { $0 as? NSControl }.filter {
          !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 0 && $0.bounds.height > 0
        }
        try #require(!controls.isEmpty)
        for control in controls {
          let rect = control.convert(control.bounds, to: host.view)
          let isInspector = inspectorScrolls.contains { control.isDescendant(of: $0) }
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
            .appendingPathComponent("studio-\(Int(size.width))-style-\(index)-details-\(detailsExpanded ? "open" : "closed").png"))

        }
      }
    }
    await model.shutdown()
  }

  private func assertCoreParametersVisible(in scroll: NSScrollView, style: PortraitStyle, size: CGSize) throws {
    let document = try #require(scroll.documentView)
    let clip = scroll.contentView
    // Four sliders plus the integer level/spacing stepper are the five native
    // core rows. The sliders follow that stepper before optional Flow controls
    // and framing; ordering the real native controls gives a host-independent
    // viewport assertion without requiring SwiftPM accessibility support.
    let sliders = descendants(document).compactMap { $0 as? NSSlider }.filter {
      !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 0 && $0.bounds.height > 0
    }.sorted { first, second in
      let a = first.convert(first.bounds, to: document)
      let b = second.convert(second.bounds, to: document)
      return document.isFlipped ? a.minY < b.minY : a.maxY > b.maxY
    }
    try #require(sliders.count >= 4, "\(style.rawValue) must host its four native core sliders.")
    #expect(clip.bounds.height >= 230,
      "Parameters need room for all five core rows at \(size); viewport is \(clip.bounds).")
    for control in sliders.prefix(4) {
      let rect = control.convert(control.bounds, to: clip)
      #expect(clip.bounds.insetBy(dx: -2, dy: -2).contains(rect),
        "\(style.rawValue) core parameter is hidden at the initial scroll position in \(size): \(rect) / \(clip.bounds).")
    }
    let steppers = descendants(document).compactMap { $0 as? NSStepper }.filter {
      !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 0 && $0.bounds.height > 0
    }
    for control in steppers {
      let rect = control.convert(control.bounds, to: clip)
      #expect(clip.bounds.insetBy(dx: -2, dy: -2).contains(rect),
        "\(style.rawValue) level/spacing stepper is hidden at the initial scroll position in \(size).")
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

private actor WorkspaceLayoutRenderer: PortraitRendering {
  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult {
    let raster = request.cachedRaster ?? portraitTestRaster()
    return .init(raster: raster, program: try PortraitVectorizer.program(from: raster,
      pose: request.pose, style: request.style, strokeStyle: request.strokeStyle,
      vectorOptions: request.vectorOptions))
  }
}
