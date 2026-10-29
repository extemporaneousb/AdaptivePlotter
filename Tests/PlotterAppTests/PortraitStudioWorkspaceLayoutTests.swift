@testable import PortraitArtists
@testable import PortraitStudioUI
import AppKit
import Foundation
import PortraitCore
import PortraitLibrary
import PlotterModel
import SwiftUI
import Testing
import Vision
@testable import PlotterApp

/// Owned offscreen hosts and a disposable validation portfolio only. This proves
/// native layout and rendered controls, not interactive inspection of the app.
@Suite("Flow Edge dojo bounded workspace", .serialized)
@MainActor
struct PortraitStudioWorkspaceLayoutTests {
  @Test("Explore, Prune, Rank and Fit retain visible core actions without regenerating on layout",
    arguments: FlowDojoModel.Stage.allCases)
  func controlsFit(stage: FlowDojoModel.Stage) async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let renderer = WorkspaceLayoutRenderer()
    let owner = PortraitStudioModel(candidateStore: .init(directoryURL: directory.appendingPathComponent("legacy")),
      portfolioFactory: { stroke in
        FlowDojoModel(directory: directory.appendingPathComponent("layout.flowportfolio"), strokeStyle: stroke,
          purpose: .validationFixture, render: { data, recipe, pen in
            try await renderer.render(data, recipe, pen)
          }, fit: { _, _ in
            .unavailable("Layout fixture: collect independent photo groups and explicit keep/remove judgments before evaluating an artist checkpoint.")
          })
      })
    do {
      let stroke = try portraitTestStyle()
      let dojo = owner.portfolioDojo(strokeStyle: stroke)
      await dojo.open()
      await dojo.addPhoto(data: try portraitTestImage(), title: "Disposable portrait layout fixture")
      dojo.count = 6
      await dojo.generate(refining: false)
      try #require(dojo.error == nil)
      try #require(dojo.roundCandidates.count == 6)
      let chosen = try #require(dojo.roundCandidates.first)
      await dojo.selectCandidate(chosen.id, prune: true)
      await dojo.edit(.remove, ids: [try #require(dojo.program?.strokes.first?.id)])
      await dojo.edit(.completeTarget)
      await dojo.presentRanking(scope: .round(try #require(dojo.round?.id)))
      let items = try #require(dojo.presentation?.items)
      try #require(items.count == 6)
      await dojo.rank(item: items[0].id, position: 1)
      await dojo.rank(item: items[1].id, position: 2)
      await dojo.fit()
      try #require(dojo.error == nil)
      if stage == .prune {
        let lines = try #require(dojo.program?.strokes)
        await dojo.edit(.remove, ids: [lines[1].id])
        await dojo.edit(.undo)
        dojo.selection = [lines[2].id]
      }
      dojo.stage = stage
      let renderCalls = await renderer.calls
      let revision = dojo.document?.revision
      let programHash = dojo.program?.contentHash
      let roundID = dojo.round?.id
      for size in [CGSize(width: 1100, height: 720), CGSize(width: 1440, height: 940)] {
        try await inspect(owner, dojo: dojo, stroke: stroke, stage: stage, size: size)
        #expect(await renderer.calls == renderCalls, "Layout must never regenerate drawings.")
        #expect(dojo.document?.revision == revision, "Layout must not create portfolio records or judgments.")
        #expect(dojo.program?.contentHash == programHash && dojo.round?.id == roundID)
        #expect(dojo.stage == stage && dojo.candidate?.id == chosen.id)
      }
      await owner.shutdown()
    } catch {
      await owner.shutdown()
      throw error
    }
  }

  private func inspect(_ owner: PortraitStudioModel, dojo: FlowDojoModel, stroke: PlotterModel.StrokeStyle,
    stage: FlowDojoModel.Stage, size: CGSize) async throws {
    let host = NSHostingController(rootView: PortraitStudioView(model: owner,
      strokeStyle: stroke, showOnPlotter: { _ in nil }, showEditedOnPlotter: { _ in nil })
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
    defer { window.close() }
    try await settle(host.view)
    #expect(!window.isKeyWindow)
    #expect(abs(host.view.bounds.width - size.width) < 1 && abs(host.view.bounds.height - size.height) < 1)
    #expect(!dojo.isBusy && dojo.error == nil)

    let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
    host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
    let image = try #require(bitmap.cgImage)
    if let directory = ProcessInfo.processInfo.environment["PORTRAIT_WORKSPACE_SNAPSHOT_DIR"] {
      try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
      let name = stage.rawValue.lowercased().replacingOccurrences(of: " & ", with: "-").replacingOccurrences(of: " ", with: "-")
      try PortraitImageAnalyzer.encodedImage(image).write(to: URL(fileURLWithPath: directory)
        .appendingPathComponent("dojo-\(name)-\(Int(size.width))x\(Int(size.height)).png"))
    }
    // Read the full frame plus overlapping bands: small native labels otherwise
    // disappear in OCR segmentation beside the large blank drawing canvas.
    let bandHeight = CGFloat(image.height) * 0.6
    let bands = [image, image.cropping(to: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: bandHeight)),
      image.cropping(to: CGRect(x: 0, y: CGFloat(image.height) - bandHeight, width: CGFloat(image.width), height: bandHeight))].compactMap { $0 }
    var rendered: [String] = []
    for band in bands {
      let recognize = VNRecognizeTextRequest()
      recognize.recognitionLevel = .accurate
      recognize.recognitionLanguages = ["en-US"]
      recognize.minimumTextHeight = 0.005
      try VNImageRequestHandler(cgImage: band).perform([recognize])
      rendered += (recognize.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
    // Disabled native controls can be too low-contrast for OCR. A real native
    // button title is also evidence when its complete frame is in the viewport.
    let nativeLabels = descendants(host.view).compactMap { view -> String? in
      guard let button = view as? NSButton, !button.isHiddenOrHasHiddenAncestor,
        button.bounds.width > 0, button.bounds.height > 0,
        host.view.bounds.insetBy(dx: -2, dy: -2).contains(button.convert(button.bounds, to: host.view)),
        scrollingAncestors(of: button).allSatisfy({ $0.contentView.bounds.insetBy(dx: -2, dy: -2).contains(button.convert(button.bounds, to: $0.contentView)) }) else { return nil }
      return button.title.isEmpty ? button.accessibilityLabel() : button.title
    }
    let normalized = (rendered + nativeLabels).map(normalize)
    let diagnostic = "stage=\(stage.rawValue) size=\(size) native=\(nativeLabels) rendered=\(rendered)"
    print("FLOW_DOJO_HOSTED_LAYOUT \(diagnostic)")
    for label in ["Flow Edge Dojo", "Import Photo", "Portfolio"] + coreLabels(stage) {
      #expect(normalized.contains { $0.contains(normalize(label)) }, "Core action '\(label)' is not visibly rendered: \(diagnostic)")
    }

    let bounds = host.view.bounds.insetBy(dx: -2, dy: -2)
    let views = descendants(host.view)
    let controls = views.compactMap { $0 as? NSControl }.filter {
      !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 0 && $0.bounds.height > 0 && !($0 is NSTableView)
    }
    try #require(!controls.isEmpty)
    // Candidate cards, ranking cards and the photo list may scroll. The viewport
    // and every action outside a document must still fit the supported window.
    for control in controls where scrollingAncestors(of: control).isEmpty {
      let rect = control.convert(control.bounds, to: host.view)
      #expect(bounds.contains(rect), "Pinned \(stage.rawValue) control exceeds \(size): \(type(of: control)) \(rect).")
    }
    let scrolls = views.compactMap { $0 as? NSScrollView }.filter {
      !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 0 && $0.bounds.height > 0
    }
    for scroll in scrolls where scrollingAncestors(of: scroll).isEmpty {
      let rect = scroll.convert(scroll.bounds, to: host.view)
      #expect(bounds.contains(rect), "\(stage.rawValue) scroll viewport exceeds \(size): \(rect).")
    }
    if stage == .explore || stage == .rank {
      let contentViewport = try #require(scrolls.first { scroll in
        scroll.convert(scroll.bounds, to: host.view).midX > size.width / 2
      })
      #expect(contentViewport.contentView.bounds.height >= 180,
        "The drawing panel needs a usable viewport at \(size), not a collapsed scroll region.")
      if stage == .rank {
        let columns = max(1, Int((contentViewport.contentView.bounds.width + 12) / 232))
        let visibleRanks = nativeLabels.filter { ["1", "2", "Unranked"].contains($0) }
        #expect(visibleRanks.count >= min(columns, 6),
          "The entire first row of rank pickers must be visible before scrolling at \(size): \(visibleRanks).")
        #expect(visibleRanks.contains("1") && visibleRanks.contains("2"))
      }
    }
    if stage == .prune {
      let canvas = try #require(views.first { $0 is PortraitLineEditorNSView })
      #expect(canvas.bounds.width >= 400 && canvas.bounds.height >= 300,
        "The pruning canvas must remain usable at \(size): \(canvas.bounds).")
    }
  }

  private func coreLabels(_ stage: FlowDojoModel.Stage) -> [String] {
    switch stage {
    case .explore: return ["Broad exploration", "Refine chosen drawing", "Prune chosen drawing"]
    case .prune: return ["Delete Selected", "Undo", "Redo", "Finish pruning", "Original"]
    case .rank: return ["Rank by artistic preference", "Random set: this round", "Random set: portfolio", "Skip"]
    case .fit: return ["Fit portfolio", "Use untrained exploration", "Results", "Training loss", "Holdout loss"]
    }
  }
  private func normalize(_ value: String) -> String {
    value.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
  }
  private func settle(_ view: NSView) async throws {
    for _ in 0..<8 {
      view.window?.layoutIfNeeded(); view.layoutSubtreeIfNeeded()
      view.window?.displayIfNeeded(); view.displayIfNeeded()
      try await Task.sleep(for: .milliseconds(50))
    }
  }
  private func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(descendants) }
  private func scrollingAncestors(of view: NSView) -> [NSScrollView] {
    var result: [NSScrollView] = [], ancestor = view.superview
    while let current = ancestor {
      if let scroll = current as? NSScrollView, let document = scroll.documentView, view.isDescendant(of: document) {
        result.append(scroll)
      }
      ancestor = current.superview
    }
    return result
  }
}

private actor WorkspaceLayoutRenderer {
  private(set) var calls = 0
  func render(_ data: Data, _ recipe: FlowArtistRecipe, _ pen: PlotterModel.StrokeStyle) throws -> PortraitRenderResult {
    calls += 1
    let strokes = try (0..<12).map { index in
      let value = recipe.values[index % recipe.values.count]
      return LogicalStroke(id: StrokeID(), path: try Polyline(points: [
        .init(x: 8, y: Double(index) * 8 + 8),
        .init(x: 30 + value * 60, y: Double(index) * 8 + 8 + value * 3)]),
        style: pen, ordering: UInt32(index))
    }
    let program = try DrawingProgram(id: ProgramID(), fieldExtent: .init(width: 100, height: 110),
      strokes: strokes, source: .init(kind: "portrait", sourceIdentifier: "layout-fixture|" + DrawingPackageCodec.sha256(data)))
    return .init(raster: portraitTestRaster(), program: program)
  }
}
