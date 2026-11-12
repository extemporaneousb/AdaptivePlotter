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
@Suite("Flow Edge authoring bounded workspace", .serialized)
@MainActor
struct PortraitStudioWorkspaceLayoutTests {
  @Test("Explore, Prune, Rank and Fit retain visible core actions without regenerating on layout",
    arguments: FlowAuthoringModel.Stage.allCases)
  func controlsFit(stage: FlowAuthoringModel.Stage) async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let renderer = WorkspaceLayoutRenderer()
    let library = DrawingFirstTestStorage.library()
    let owner = PortraitStudioModel(library: library)
    let authoring = FlowAuthoringModel(directory: directory, library: library, strokeStyle: try portraitTestStyle(),
      purpose: .validationFixture, render: { data, recipe, pen in try await renderer.render(data, recipe, pen) },
      fit: { _, _ in .unavailable("Layout fixture has no trained artist.") })
    do {
      let stroke = try portraitTestStyle()
      await authoring.open()
      await authoring.addPhoto(data: try portraitTestImage(), title: "Disposable portrait layout fixture")
      authoring.count = 6
      await authoring.generate(refining: false)
      try #require(authoring.error == nil)
      try #require(authoring.roundCandidates.count == 6)
      let chosen = try #require(authoring.roundCandidates.first)
      await authoring.selectCandidate(chosen.id, prune: true)
      await authoring.edit(.remove, ids: [try #require(authoring.program?.strokes.first?.id)])
      await authoring.edit(.completeTarget)
      await authoring.presentRanking(scope: .round(try #require(authoring.round?.id)))
      let items = try #require(authoring.presentation?.items)
      try #require(items.count == 6)
      await authoring.rank(item: items[0].id, position: 1)
      await authoring.rank(item: items[1].id, position: 2)
      await authoring.fit()
      try #require(authoring.error == nil)
      let activeRound = try #require(authoring.round?.id)
      for index in 2...18 {
        await authoring.addPhoto(data: try portraitTestImage(), title: "Historical photo \(index)")
      }
      await authoring.selectRound(activeRound)
      if stage == .prune {
        let lines = try #require(authoring.program?.strokes)
        await authoring.edit(.remove, ids: [lines[1].id])
        await authoring.edit(.undo)
        authoring.selection = [lines[2].id]
      }
      authoring.stage = stage
      let renderCalls = await renderer.calls
      let revision = authoring.document?.revision
      let programHash = authoring.program?.contentHash
      let roundID = authoring.round?.id
      for size in [CGSize(width: 1100, height: 720), CGSize(width: 1440, height: 940)] {
        try await inspect(owner, authoring: authoring, stroke: stroke, stage: stage, size: size)
        #expect(await renderer.calls == renderCalls, "Layout must never regenerate drawings.")
        #expect(authoring.document?.revision == revision, "Layout must not create portfolio records or judgments.")
        #expect(authoring.program?.contentHash == programHash && authoring.round?.id == roundID)
        #expect(authoring.stage == stage && authoring.candidate?.id == chosen.id)
      }
      if stage == .rank {
        await authoring.presentRanking(scope: .round(try #require(authoring.round?.id)), count: 2)
        try #require(authoring.error == nil)
        let previousPair = try #require(authoring.presentation)
        try #require(previousPair.items.count == 2)
        await authoring.compare(preferred: try #require(previousPair.items.first?.id))
        try #require(authoring.error == nil)
        let nextPair = try #require(authoring.presentation)
        try #require(nextPair.id != previousPair.id && nextPair.items.count == 2)
        try #require(authoring.ranks.isEmpty)
        let pairRevision = authoring.document?.revision
        for size in [CGSize(width: 1100, height: 720), CGSize(width: 1440, height: 940)] {
          try await inspect(owner, authoring: authoring, stroke: stroke, stage: stage, size: size, suffix: "-pair", expectedFreshPair: true)
          #expect(authoring.document?.revision == pairRevision)
          #expect(await renderer.calls == renderCalls)
        }
      }
      await owner.shutdown()
    } catch {
      await owner.shutdown()
      throw error
    }
  }

  @Test("The user-opened camera panel exposes preview, capture and recovery actions without starting a real camera")
  func cameraPanelLayout() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let owner = PortraitStudioModel(library: DrawingFirstTestStorage.library())
    let host = NSHostingController(rootView: FlowAuthoringCameraPanel(camera: owner,
      strokeStyle: try portraitTestStyle(), selectCamera: { nil }, captured: { _ in })
      .frame(width: 640, height: 600).background(Color(nsColor: .windowBackgroundColor)))
    let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 640, height: 600),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentViewController = host
    window.appearance = NSAppearance(named: .aqua); window.orderFront(nil)
    do {
      try await settle(host.view)
      let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
      host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
      let image = try #require(bitmap.cgImage)
      if let directory = ProcessInfo.processInfo.environment["PORTRAIT_WORKSPACE_SNAPSHOT_DIR"] {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try PortraitImageAnalyzer.encodedImage(image).write(to:
          URL(fileURLWithPath: directory).appendingPathComponent("authoring-camera-panel-640x600.png"))
      }
      let controls = descendants(host.view).compactMap { $0 as? NSButton }.filter {
        !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 0 && $0.bounds.height > 0
      }
      let labels = controls.map { $0.title + " " + ($0.accessibilityLabel() ?? "") }
      // SwiftUI draws some button labels separately from its title-less native
      // NSButton. Verify rendered labels plus actual bounded native controls.
      let recognize = VNRecognizeTextRequest()
      recognize.recognitionLevel = .accurate; recognize.recognitionLanguages = ["en-US"]
      recognize.minimumTextHeight = 0.005
      try VNImageRequestHandler(cgImage: image).perform([recognize])
      let rendered = (recognize.results ?? []).compactMap { $0.topCandidates(1).first?.string }
      let diagnostic = "native=\(labels) rendered=\(rendered)"
      print("FLOW_AUTHORING_CAMERA_LAYOUT \(diagnostic)")
      #expect(controls.count >= 3, "Camera actions must remain real native controls: \(diagnostic)")
      for title in ["Restart Camera", "Close", "Capture Photo"] {
        #expect((labels + rendered).contains { normalize($0).contains(normalize(title)) },
          "Camera action '\(title)' is not visibly rendered: \(diagnostic)")
      }
      for button in controls {
        #expect(host.view.bounds.insetBy(dx: -2, dy: -2).contains(button.convert(button.bounds, to: host.view)),
          "Camera control lies outside the panel: \(button.title) \(button.frame)")
      }
      #expect(!owner.cameraIsRunning && !owner.isCapturing)
      window.close(); await owner.shutdown()
    } catch { window.close(); await owner.shutdown(); throw error }
  }

  private func inspect(_ owner: PortraitStudioModel, authoring: FlowAuthoringModel, stroke: PlotterModel.StrokeStyle,
    stage: FlowAuthoringModel.Stage, size: CGSize, suffix: String = "", expectedFreshPair: Bool = false) async throws {
    let host = NSHostingController(rootView: FlowAuthoringView(model: authoring, camera: owner,
      handoff: { _ in nil })
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
    #expect(!authoring.isBusy && authoring.error == nil)

    let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
    host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
    let image = try #require(bitmap.cgImage)
    if let directory = ProcessInfo.processInfo.environment["PORTRAIT_WORKSPACE_SNAPSHOT_DIR"] {
      try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
      let name = stage.rawValue.lowercased().replacingOccurrences(of: " & ", with: "-").replacingOccurrences(of: " ", with: "-")
      try PortraitImageAnalyzer.encodedImage(image).write(to: URL(fileURLWithPath: directory)
        .appendingPathComponent("authoring-\(name)\(suffix)-\(Int(size.width))x\(Int(size.height)).png"))
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
    print("FLOW_AUTHORING_HOSTED_LAYOUT \(diagnostic)")
    for label in ["Flow Edge", "Import Photo", "Portfolio", "Branches"] + coreLabels(stage) {
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
        #expect(visibleRanks.count >= min(columns, authoring.presentation?.items.count ?? 0),
          "The entire first row of rank pickers must be visible before scrolling at \(size): \(visibleRanks).")
        if expectedFreshPair {
          #expect(visibleRanks.filter { $0 == "Unranked" }.count == 2,
            "The fresh next pair must expose two distinct Unranked controls before scrolling.")
        } else {
          #expect(visibleRanks.contains("1") && visibleRanks.contains("2"))
        }
        if authoring.presentation?.items.count == 2 {
          #expect(normalized.contains { $0.contains(normalize("Prefer this drawing")) })
          #expect(normalized.contains { $0.contains(normalize("Equal preference")) })
        }
      }
    }
    if stage == .prune {
      let canvas = try #require(views.first { $0 is PortraitLineEditorNSView })
      #expect(canvas.bounds.width >= 400 && canvas.bounds.height >= 300,
        "The pruning canvas must remain usable at \(size): \(canvas.bounds).")
    }
  }

  private func coreLabels(_ stage: FlowAuthoringModel.Stage) -> [String] {
    switch stage {
    case .explore: return ["Broad exploration", "Refine selected drawing", "Prune selected drawing"]
    case .prune: return ["Delete Selected", "Undo", "Redo", "Finish pruning", "Original"]
    case .rank: return ["Rank by artistic preference", "This set", "Across photos", "Next pair", "Skip"]
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
      strokes: strokes, source: .init(kind: "portrait", sourceIdentifier: "layout-fixture|" + DrawingArtifactCoding.sha256(data)))
    return .init(raster: portraitTestRaster(), program: program)
  }
}
