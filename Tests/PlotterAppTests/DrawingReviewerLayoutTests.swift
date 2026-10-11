@testable import PortraitArtists
@testable import PortraitStudioUI
import AppKit
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import SwiftUI
import Testing
import Vision
@testable import PlotterApp

/// Offscreen views use fixture cameras/controllers exclusively. No running app
/// or physical device is selected, replaced, or operated by these checks.
@Suite("Drawing Reviewer hosted layout", .serialized)
@MainActor
struct DrawingReviewerLayoutTests {
  @Test("persistent empty and saved reviewer geometry excludes generic run history")
  func minimumReviewerGeometry() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let studio = PortraitStudioModel(candidateStore: .init(directoryURL: directory))
    let fixture = try await DrawingWorkbenchApplicationFixture.make(portraitStudio: studio)
    defer { fixture.stores.remove() }
    let application = fixture.application
    do {
      try await inspect(application, stage: "empty", expectedPhotos: 0)
      let basis = try portraitPersistenceCandidate(seed: 924)
      let saved = try PortraitCandidate(sourceData: portraitTestImage(),
        sourcePixelExtent: .init(widthPixels: 60, heightPixels: 80), raster: basis.raster,
        recipe: basis.recipe, program: basis.program, photoID: basis.photoID,
        captureSessionID: basis.captureSessionID)
      studio.sketches.retainSourcePhoto(.init(id: saved.photoID, data: saved.sourceData,
        label: "Hosted source", capturedAt: saved.createdAt, frameID: nil,
        captureNanoseconds: nil, pose: .front, sourcePixelExtent: saved.sourcePixelExtent,
        captureSessionID: saved.captureSessionID))
      #expect(studio.sketches.retain(candidate: saved, reason: .shortlisted) == nil)
      await application.portraitStudio.sketches.awaitPersistence()
      await studio.sketches.awaitLibrarySynchronization()
      let savedSelection = try await studio.sketches.librarySelection(photoID: saved.photoID)
      #expect(savedSelection.selectedDrawing?.identity == .init(candidateID: saved.id, photoID: saved.photoID))
      #expect(savedSelection.program == saved.program && savedSelection.works.isEmpty)
      try await inspect(application, stage: "saved", expectedPhotos: 1)

      try await fixture.submit(.fitInDrawableRegion)
      try await fixture.submit(.assertPaperCoverage)
      try await waitFor { application.drawingRunSnapshot?.readiness == .ready }
      await fixture.planGate.release(.possibleInk)
      let draw = try #require(application.testPlotterUIProjection().semantic.request(matching: .drawingRun(.start)))
      #expect(await application.submitPlotterUIRequest(draw) == .accepted(requestID: draw.id))
      try await waitFor { !application.drawingReviewRecords.isEmpty }
      await studio.sketches.awaitLibrarySynchronization()
      let genericExcluded = try await studio.sketches.librarySnapshot(filter: .plottedWorks)
      #expect(genericExcluded.works.isEmpty)
      #expect(try await studio.sketches.librarySelection(photoID: saved.photoID).works.isEmpty)
      try await inspect(application, stage: "generic-result-excluded", expectedPhotos: 1)
      await application.shutdown()
    } catch {
      await application.shutdown()
      throw error
    }
  }

  @Test("persistent portrait reviewer renders the exact source and latest possible-ink work with retained media")
  func populatedPortraitWorkGeometry() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let studio = PortraitStudioModel(candidateStore: .init(directoryURL: directory))
    let fixture = try await DrawingWorkbenchApplicationFixture.make(portraitStudio: studio)
    defer { fixture.stores.remove() }
    let application = fixture.application
    do {
      let basis = try portraitPersistenceCandidate(seed: 925)
      let candidate = try PortraitCandidate(sourceData: portraitTestImage(),
        sourcePixelExtent: .init(widthPixels: 60, heightPixels: 80), raster: basis.raster,
        recipe: basis.recipe, program: basis.program, photoID: basis.photoID,
        captureSessionID: basis.captureSessionID)
      studio.sketches.retainSourcePhoto(.init(id: candidate.photoID, data: candidate.sourceData,
        label: "Portrait run source", capturedAt: candidate.createdAt, frameID: nil,
        captureNanoseconds: nil, pose: .front, sourcePixelExtent: candidate.sourcePixelExtent,
        captureSessionID: candidate.captureSessionID))
      let handoffFailure = await application.projectPortrait(candidate)
      try #require(handoffFailure == nil)
      try await fixture.submit(.assertPaperCoverage)
      try await waitFor { application.drawingRunSnapshot?.readiness == .ready }
      await fixture.planGate.release(.possibleInk)
      let draw = try #require(application.testPlotterUIProjection().semantic.request(matching: .drawingRun(.start)))
      #expect(await application.submitPlotterUIRequest(draw) == .accepted(requestID: draw.id))
      try await waitFor { application.drawingRunSnapshot?.terminal != nil }
      await studio.sketches.awaitLibrarySynchronization()
      let terminal = try #require(application.drawingRunSnapshot?.terminal)
      let selected = try await studio.sketches.librarySelection(photoID: candidate.photoID)
      let work = try #require(selected.works.first { $0.runID == terminal.runID })
      #expect(selected.selectedWorkID == work.id)
      #expect(selected.selectedDrawing?.identity == work.drawingIdentity)
      #expect(work.drawingIdentity == .init(candidateID: candidate.id, photoID: candidate.photoID))
      #expect(selected.program == candidate.program)
      #expect(selected.photo.reference.sourceSHA256 == candidate.sourceSHA256)
      #expect(work.executedOrPossibleInk)
      try #require(!work.media.isEmpty && work.media.allSatisfy(\.isAvailable))
      let workSelection = try await studio.sketches.librarySelection(workID: work.id)
      #expect(workSelection.photo.id == selected.photo.id)
      #expect(workSelection.selectedDrawing?.identity == selected.selectedDrawing?.identity)
      #expect(workSelection.selectedWorkID == selected.selectedWorkID)
      try await inspect(application, stage: "portrait-result", expectedPhotos: 1, expectedWork: true)
      await application.shutdown()
    } catch {
      await application.shutdown()
      throw error
    }
  }

  private func inspect(_ application: PlotterApplicationRuntime, stage: String,
    expectedPhotos: Int, expectedWork: Bool = false) async throws {
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
    let hostedViews = descendants(host.view)
    let rowCount = hostedViews.compactMap { $0 as? NSTableView }.reduce(0) { $0 + $1.numberOfRows }
    let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
    host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
    let image = try #require(bitmap.cgImage)
    if let directory = ProcessInfo.processInfo.environment["PORTRAIT_WORKSPACE_SNAPSHOT_DIR"] {
      try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
      try PortraitImageAnalyzer.encodedImage(image).write(to: URL(fileURLWithPath: directory)
        .appendingPathComponent("reviewer-1000-\(stage).png"))
    }
    // SwiftUI may host buttons without an NSButton.title. Verify the actual
    // bitmap's visible detail actions, independent of AX-host availability.
    let recognize = VNRecognizeTextRequest()
    recognize.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: image).perform([recognize])
    let renderedText = (recognize.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    let controlsDescription = hostedViews.compactMap { view -> String? in
      guard let control = view as? NSControl else { return nil }
      return "\(String(reflecting: type(of: control))): title=\((control as? NSButton)?.title ?? "") label=\(control.accessibilityLabel() ?? "")"
    }
    let diagnostic = "stage=\(stage); rows=\(rowCount); controls=\(controlsDescription); rendered=\(renderedText)"
    print("PORTRAIT_HOSTED_REVIEW \(diagnostic)")
    #expect(rowCount == expectedPhotos, "\(diagnostic)")
    if expectedPhotos > 0 {
      #expect(renderedText.contains { $0.localizedCaseInsensitiveContains("Delete Drawing") }, "\(diagnostic)")
      #expect(renderedText.contains { $0.localizedCaseInsensitiveContains("Exact drawing reference") }, "\(diagnostic)")
    }
    if expectedWork {
      #expect(renderedText.contains { $0.localizedCaseInsensitiveContains("Delete Run Review") }, "\(diagnostic)")
    }
    #expect(!window.isKeyWindow)
    #expect(abs(host.view.bounds.width - size.width) < 1)
    #expect(abs(host.view.bounds.height - size.height) < 1)
    let controls = descendants(host.view).compactMap { $0 as? NSControl }.filter {
      !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 0 && $0.bounds.height > 0
    }
    try #require(!controls.isEmpty)
    func assertVisible(_ control: NSControl) {
      let bounds = control.convert(control.bounds, to: host.view)
      #expect(host.view.bounds.insetBy(dx: -2, dy: -2).contains(bounds),
        "Reviewer \(stage) control clipped: \(String(reflecting: type(of: control))) \(bounds).")
    }
    // Pinned controls must fit before any scrolling. Detail controls must be
    // reachable through their real scroll containers, including nested Notes.
    for control in controls where scrollingAncestors(of: control).isEmpty {
      assertVisible(control)
    }
    for control in controls where !scrollingAncestors(of: control).isEmpty {
      for scroll in scrollingAncestors(of: control) {
        let document = try #require(scroll.documentView)
        document.scrollToVisible(control.convert(control.bounds, to: document))
        scroll.reflectScrolledClipView(scroll.contentView)
      }
      try await settle(host.view)
      assertVisible(control)
    }
    #expect(!window.isKeyWindow)
    if expectedWork, let directory = ProcessInfo.processInfo.environment["PORTRAIT_WORKSPACE_SNAPSHOT_DIR"] {
      let finalBitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
      host.view.cacheDisplay(in: host.view.bounds, to: finalBitmap)
      try PortraitImageAnalyzer.encodedImage(try #require(finalBitmap.cgImage)).write(
        to: URL(fileURLWithPath: directory).appendingPathComponent("reviewer-1000-\(stage)-scrolled.png"))
    }
  }

  private func scrollingAncestors(of view: NSView) -> [NSScrollView] {
    var result: [NSScrollView] = []
    var ancestor = view.superview
    while let current = ancestor {
      if let scroll = current as? NSScrollView, let document = scroll.documentView,
        view.isDescendant(of: document), document.bounds.height > scroll.contentView.bounds.height + 1 {
        result.append(scroll)
      }
      ancestor = current.superview
    }
    return result
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
