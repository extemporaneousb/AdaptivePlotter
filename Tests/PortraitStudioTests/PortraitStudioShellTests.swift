import AppKit
import DrawingLibrary
import Foundation
import PortraitArtists
import PortraitCore
import PortraitLibrary
import PortraitStudioUI
import PlotterRuntime
import PlotterModel
import SwiftUI
import Testing
@testable import PortraitStudio

@Suite("Portrait Studio shell and photo region", .serialized)
@MainActor
struct PortraitStudioShellTests {
  @Test("Legacy bookmarks restore to the three Studio destinations")
  func routeCompatibility() {
    var route = DrawingLibraryRoute()
    #expect(PortraitStudioDestination.restored("", route: route, hasSavedRoute: false) == .booth)
    #expect(PortraitStudioDestination.restored("", route: route, hasSavedRoute: true) == .photos)
    route.workspace = .drawingStudio
    #expect(PortraitStudioDestination.restored("", route: route, hasSavedRoute: true) == .drawing)
    #expect(PortraitStudioDestination.restored("booth", route: route, hasSavedRoute: true) == .booth)
  }

  @Test("Native photo region excludes letterboxing and supports new, moved and resized selections")
  func nativeRegionGestures() throws {
    _ = NSApplication.shared
    let view = PortraitPhotoRegionNSView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
    view.image = NSImage(size: CGSize(width: 400, height: 200))
    let fit = PortraitPhotoRegionGeometry.imageRect(image: try #require(view.image).size, viewport: view.bounds.size)
    #expect(fit == CGRect(x: 0, y: 50, width: 600, height: 300))
    var changes = 0
    view.changed = { _ in changes += 1 }
    try drag(view, from: CGPoint(x: 120, y: 110), to: CGPoint(x: 420, y: 290))
    var region = try #require(view.region)
    #expect(abs(region.x - 0.2) < 0.001 && abs(region.y - 0.2) < 0.001)
    #expect(abs(region.width - 0.5) < 0.001 && abs(region.height - 0.6) < 0.001)
    try drag(view, from: CGPoint(x: 200, y: 150), to: CGPoint(x: 260, y: 180))
    region = try #require(view.region)
    #expect(abs(region.x - 0.3) < 0.001 && abs(region.y - 0.3) < 0.001)
    #expect(abs(region.width - 0.5) < 0.001 && abs(region.height - 0.6) < 0.001)
    let bottomRight = PortraitPhotoRegionGeometry.display(region, in: fit)
    try drag(view, from: CGPoint(x: bottomRight.maxX, y: bottomRight.maxY), to: CGPoint(x: 540, y: 320))
    region = try #require(view.region)
    #expect(abs(region.width - 0.6) < 0.001 && abs(region.height - 0.6) < 0.001)
    let count = changes
    try drag(view, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 70, y: 100))
    #expect(changes == count, "A gesture starting in a letterbox cannot create a crop.")
    view.selectionOnly = true
    try drag(view, from: CGPoint(x: 200, y: 150), to: CGPoint(x: 300, y: 200))
    #expect(changes == count, "Selection-only inspection never changes the source region.")
    view.selectionOnly = false; view.region = .init(x: 0, y: 0, width: 1, height: 1)
    try drag(view, from: CGPoint(x: fit.maxX, y: fit.maxY), to: CGPoint(x: 540, y: 320))
    let wholeResize = try #require(view.region)
    #expect(abs(wholeResize.width - 0.9) < 0.001 && abs(wholeResize.height - 0.9) < 0.001,
      "Whole-photo handles remain draggable at the exact image boundary.")
    let portrait = PortraitPhotoRegionGeometry.imageRect(image: CGSize(width: 200, height: 400), viewport: CGSize(width: 600, height: 400))
    #expect(portrait == CGRect(x: 200, y: 0, width: 200, height: 400))
  }

  @Test("Photo-only route cannot send a hidden previously loaded candidate")
  func hiddenSelectionGate() async throws {
    let directory = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: directory) }
    let library = DrawingLibrary(directoryURL: directory)
    let owner = PortraitStudioModel(library: library)
    let model = FlowAuthoringModel(directory: directory, library: library, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(1), title: "Photo A")
    await model.generate(refining: false)
    let candidateA = try #require(model.roundCandidates.first?.id)
    await model.browseCandidate(candidateA)
    try #require(model.canSendToPlotter)
    _ = try await model.retainedDrawing()
    let a = try #require(model.currentPhotoRef)
    await model.addPhoto(data: FlowAuthoringFixture.image(2), title: "Photo 29")
    let b = try #require(model.currentPhotoRef)
    await model.selectPhoto(a); await model.browseCandidate(candidateA)
    try #require(model.canSendToPlotter, "A must actually be loaded and sendable before selecting the photo-only B route.")
    var navigation = DrawingLibraryRoute(); navigation.selectPhoto(b)
    let shell = PortraitStudioAuthoringWindow(authoring: model, acquisition: owner, library: library,
      delegate: PortraitStudioApplicationDelegate(), route: Binding(get: { navigation }, set: { navigation = $0 }))
    #expect(!shell.canSendToPlotter)
    navigation.workspace = .drawingStudio
    #expect(!shell.canSendToPlotter, "Entering Drawing cannot enable the candidate from a different photo.")
    _ = await model.shutdown(); await owner.shutdown(); await library.closeLibrary()
  }

  @Test("Same-photo history ABA cannot revive an asynchronous generated handoff")
  func generatedHandoffRejectsHistoryABA() async throws {
    let directory = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: directory) }
    let model = FlowAuthoringModel(directory: directory, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(9), title: "Handoff lifetime fixture")
    model.count = 3; await model.generate(refining: false)
    let a = try #require(model.roundCandidates.first?.id)
    await model.browseCandidate(a); _ = try await model.retainedDrawing()
    await model.generate(refining: false)
    let b = try #require(model.roundCandidates.first?.id)
    await model.browseCandidate(b); _ = try await model.retainedDrawing()
    await model.browseCandidate(a)
    let photo = model.currentPhotoRef, revision = model.prune?.id, options = model.committedAnalysisOptions
    let selection = try #require(PortraitStudioGeneratedHandoffSelection(model: model))
    #expect(selection.isCurrent(in: model))
    let gate = StudioShellRenderGate(); await gate.arm()
    defer { Task { await gate.release() } }
    var activations = 0
    let handoff = Task { @MainActor in
      await gate.pauseIfArmed()
      guard selection.isCurrent(in: model) else { return false }
      activations += 1
      return true
    }
    try #require(await gate.waitUntilPaused())
    await model.browseCandidate(b); await model.browseCandidate(a)
    #expect(model.currentPhotoRef == photo && model.candidate?.id == a && model.prune?.id == revision)
    #expect(model.committedAnalysisOptions == options && model.canSendToPlotter)
    #expect(!selection.isCurrent(in: model), "Restored exact refs do not restore the old user intent.")
    await gate.release()
    #expect(await handoff.value == false && activations == 0)
    let current = try #require(PortraitStudioGeneratedHandoffSelection(model: model))
    #expect(current.isCurrent(in: model))
    #expect(await model.shutdown())
  }

  @Test("AX-capable host: production shell exposes three destinations, zero-drawing Photo 29, recommendation and one exact Send",
    .enabled(if: ProcessInfo.processInfo.environment["PORTRAIT_NATIVE_AX_CHECK"] == "1"))
  func productionShellControls() async throws {
    _ = NSApplication.shared
    let directory = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: directory) }
    let library = DrawingLibrary(directoryURL: directory)
    let owner = PortraitStudioModel(library: library)
    let model = FlowAuthoringModel(directory: directory, library: library, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(29), title: "Photo 29")
    let photo = try #require(model.currentPhotoRef)
    #expect(try await library.drawings(in: .photo(photo)).entries.isEmpty)
    var navigation = DrawingLibraryRoute(); navigation.selectPhoto(photo)
    let delegate = PortraitStudioApplicationDelegate(); delegate.destinationRoot = directory.appendingPathComponent("fake-destination")
    var deliveries: [URL] = []
    delegate.openDestination = { deliveries.append($0) }
    let shell = PortraitStudioAuthoringWindow(authoring: model, acquisition: owner, library: library,
      delegate: delegate, route: Binding(get: { navigation }, set: { navigation = $0 }))
    let host = NSHostingController(rootView: shell.frame(width: 1280, height: 850).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light))
    host.sizingOptions = []
    let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 1280, height: 850),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
    window.contentViewController = host; window.orderFront(nil)
    defer { window.orderOut(nil); window.contentViewController = nil; window.close() }
    try #require(await wait { self.button("portraitStudio.destination.photos", in: window) != nil })
    let actions = tree(window).filter { $0.accessibilityRole() == .button }
    #expect(actions.filter { $0.accessibilityIdentifier() == "portraitStudio.send" }.count == 1)
    for id in ["booth", "photos", "drawing"] { #expect(button("portraitStudio.destination." + id, in: window) != nil) }
    let send = try #require(button("portraitStudio.send", in: window))
    #expect(!send.isAccessibilityEnabled())
    try press("portraitStudio.destination.booth", in: window)
    try #require(await wait { model.recommendationCandidate != nil && !model.isBusy })
    try #require(await wait { self.button("portraitStudio.suggestion", in: window) != nil })
    #expect(!owner.cameraIsRunning && !owner.isCapturing && owner.selectedDeviceID == nil)
    try press("portraitStudio.suggestion", in: window)
    try #require(await wait { model.roundCandidates.count >= 3 && !model.isBusy })
    #expect(model.document?.choices.isEmpty == true, "Automatic suggestion entry is neutral.")
    let broadRound = try #require(model.round?.id)
    try press("flowAuthoring.tile.0", in: window)
    try #require(await wait { model.round?.id != broadRound && model.roundCandidates.count >= 3 && !model.isBusy })
    #expect(model.document?.choices.count == 1 && model.round?.explorationDepth == 1)
    let radius = try #require(model.round?.refinementRadius)
    try press("flowAuthoring.tile.1", in: window)
    try #require(await wait { model.round?.explorationDepth == 2 && !model.isBusy })
    #expect(try #require(model.round?.refinementRadius) < radius)
    let count = model.document?.candidates.count, choices = model.document?.choices.count
    try press("flowAuthoring.back", in: window)
    try #require(await wait { model.round?.explorationDepth == 1 && !model.isBusy })
    #expect(model.document?.candidates.count == count && model.document?.choices.count == choices)
    let expected = try await model.retainedDrawing()
    try press("portraitStudio.send", in: window)
    try #require(await wait { deliveries.count == 1 })
    let delivery = try JSONDecoder().decode(DrawingDestinationDelivery.self, from: Data(contentsOf: try #require(deliveries.first)))
    #expect(delivery.request == .prepare(try #require(expected.reference)))
    #expect(delegate.documentError == nil)
    // This proves durable enqueue and fake activation, not a receiver ACK.
    if let snapshots = ProcessInfo.processInfo.environment["PORTRAIT_WORKSPACE_SNAPSHOT_DIR"] {
      try FileManager.default.createDirectory(atPath: snapshots, withIntermediateDirectories: true)
      host.view.layoutSubtreeIfNeeded()
      let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
      host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
      try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: snapshots).appendingPathComponent("studio-production-shell.png"))
    }
    window.contentViewController = nil
    _ = await model.shutdown(); await owner.shutdown(); await library.closeLibrary()
  }

  @Test("AX-capable host: a newer crop draft survives an older Apply awaiting cancelled rendering",
    .enabled(if: ProcessInfo.processInfo.environment["PORTRAIT_NATIVE_AX_CHECK"] == "1"))
  func newerRegionDraftSurvivesApply() async throws {
    _ = NSApplication.shared
    let directory = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: directory) }
    let library = DrawingLibrary(directoryURL: directory), gate = StudioShellRenderGate()
    let owner = PortraitStudioModel(library: library)
    let model = FlowAuthoringModel(directory: directory, library: library, purpose: .validationFixture, render: { data, recipe, pen in
      await gate.pauseIfArmed()
      return try await FlowAuthoringFixture.render(data, recipe, pen)
    })
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(4), title: "Region race fixture")
    await model.ensureRecommendation()
    let host = NSHostingController(rootView: PortraitStudioBooth(model: model, camera: owner, openDrawing: {})
      .frame(width: 1200, height: 800).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light))
    let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 1200, height: 800),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua); window.contentViewController = host; window.orderFront(nil)
    defer { window.orderOut(nil); window.contentViewController = nil; window.close() }
    try #require(await wait { self.views(host.view).contains { $0 is PortraitPhotoRegionNSView } })
    let canvas = try #require(views(host.view).compactMap { $0 as? PortraitPhotoRegionNSView }.first)
    let fit = PortraitPhotoRegionGeometry.imageRect(image: try #require(canvas.image).size, viewport: canvas.bounds.size)
    func point(_ x: Double, _ y: Double) -> CGPoint { .init(x: fit.minX + x * fit.width, y: fit.minY + y * fit.height) }
    defer { Task { await gate.release() } }
    await gate.arm()
    let rendering = Task { await model.generate(refining: false) }
    try #require(await gate.waitUntilPaused(), "The render did not reach the held test slot before its deadline.")
    try drag(canvas, from: point(0.1, 0.1), to: point(0.7, 0.7))
    try #require(await wait { self.button("portraitStudio.applyRegion", in: window)?.isAccessibilityEnabled() == true })
    try press("portraitStudio.applyRegion", in: window)
    for _ in 0..<10 { await Task.yield() }
    // Start outside A and make B, while A is waiting behind the cancelled worker.
    try drag(canvas, from: point(0.8, 0.2), to: point(0.95, 0.6))
    let newer = try #require(canvas.region)
    await gate.release(); await rendering.value
    try #require(await wait { !model.isBusy })
    #expect(model.regionPreviewPending && !model.canSendToPlotter)
    try #require(await wait { self.button("portraitStudio.applyRegion", in: window)?.isAccessibilityEnabled() == true })
    try press("portraitStudio.applyRegion", in: window)
    try #require(await wait { !model.regionPreviewPending && !model.isBusy })
    #expect(model.committedAnalysisOptions.manualRegion == newer)
    window.contentViewController = nil
    _ = await model.shutdown(); await owner.shutdown(); await library.closeLibrary()
  }

  @Test("AX-capable host: production Booth reuses its fake camera across captures and releases it on tab leave",
    .enabled(if: ProcessInfo.processInfo.environment["PORTRAIT_NATIVE_AX_CHECK"] == "1"))
  func nativeCameraLifecycle() async throws {
    _ = NSApplication.shared
    let directory = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: directory) }
    let library = DrawingLibrary(directoryURL: directory), driver = StudioShellCameraDriver()
    let owner = PortraitStudioModel(camera: CameraCapture(driver: driver), library: library, photoAcquirer: StudioShellPhotoAcquirer())
    let model = FlowAuthoringModel(directory: directory, library: library, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    await model.open()
    var navigation = DrawingLibraryRoute()
    let delegate = PortraitStudioApplicationDelegate(); delegate.destinationRoot = directory.appendingPathComponent("fake-destination")
    let host = NSHostingController(rootView: PortraitStudioAuthoringWindow(authoring: model, acquisition: owner, library: library,
      delegate: delegate, route: Binding(get: { navigation }, set: { navigation = $0 }), showsCaptureLight: false).frame(width: 1280, height: 850).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light))
    let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 1280, height: 850), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua); window.contentViewController = host; window.orderFront(nil)
    defer { window.orderOut(nil); window.contentViewController = nil; window.close() }
    try #require(await wait { self.button("portraitStudio.destination.booth", in: window) != nil })
    try press("portraitStudio.destination.booth", in: window)
    try #require(await wait { self.button("portraitStudio.livePreview", in: window) != nil })
    #expect(!owner.cameraIsRunning && owner.selectedDeviceID == nil)
    try press("portraitStudio.livePreview", in: window)
    try #require(await wait { !owner.devices.isEmpty })
    #expect(await driver.starts == 0 && owner.selectedDeviceID == nil)
    // Explicit fake selection; no physical device can be chosen by this owner.
    owner.selectedDeviceID = try #require(owner.devices.first?.id)
    try #require(await wait { self.button("portraitStudio.startPreview", in: window)?.isAccessibilityEnabled() == true })
    try press("portraitStudio.startPreview", in: window)
    try #require(await wait { owner.cameraIsRunning && owner.preview.frame != nil })
    for count in 1...2 {
      try press("portraitStudio.capture", in: window)
      try #require(await wait { model.document?.sources.count == count && !owner.isCapturing && !model.isBusy })
      #expect(navigation.photo == model.currentPhotoRef && owner.cameraIsRunning)
      #expect(button("portraitStudio.capture", in: window) != nil, "The live Booth must stay mounted after adopting a still.")
    }
    #expect(await driver.starts == 1)
    try press("portraitStudio.destination.photos", in: window)
    try #require(await wait { !owner.cameraIsRunning && owner.preview.frame == nil && !owner.screenIlluminationActive })
    window.contentViewController = nil
    _ = await model.shutdown(); await owner.shutdown(); await library.closeLibrary()
  }

  @Test("AX-capable host: a completed image tile interrupts later slots and opens its child immediately",
    .enabled(if: ProcessInfo.processInfo.environment["PORTRAIT_NATIVE_AX_CHECK"] == "1"))
  func completedTileInterruptsGeneration() async throws {
    _ = NSApplication.shared
    let directory = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: directory) }
    let library = DrawingLibrary(directoryURL: directory), gate = StudioShellRenderGate()
    let owner = PortraitStudioModel(library: library)
    let model = FlowAuthoringModel(directory: directory, library: library, purpose: .validationFixture, render: { data, recipe, pen in
      await gate.pauseIfArmed()
      return try await FlowAuthoringFixture.render(data, recipe, pen)
    })
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(7), title: "Streamed tile fixture")
    model.count = 3
    let host = NSHostingController(rootView: FlowAuthoringView(model: model, camera: owner, embedded: true).frame(width: 1280, height: 850).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light))
    let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 1280, height: 850), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua); window.contentViewController = host; window.orderFront(nil)
    defer { window.orderOut(nil); window.contentViewController = nil; window.close(); Task { await gate.release() } }
    await gate.arm(after: 2)
    let rendering = Task { await model.generate(refining: false) }
    try #require(await gate.waitUntilPaused(), "The render did not reach the held test slot before its deadline.")
    let broad = try #require(model.round), parent = try #require(model.roundCandidates.first)
    #expect(model.roundCandidates.count == 1 && model.isBusy)
    try #require(await wait { self.button("flowAuthoring.tile.0", in: window)?.isAccessibilityEnabled() == true })
    try press("flowAuthoring.tile.0", in: window)
    try #require(await wait { model.pendingExplorationParentID == parent.id })
    #expect(model.isBusy, "The child intent must appear while the old later slot is still paused.")
    await gate.release(); await rendering.value
    try #require(await wait { model.round?.parentCandidateID == parent.id && model.roundCandidates.count == 3 && !model.isBusy })
    #expect(model.document?.rounds.first(where: { $0.id == broad.id })?.status == .cancelled)
    #expect(model.document?.choices.count == 1 && model.round?.refinementRadius == 0.06)
    window.contentViewController = nil
    _ = await model.shutdown(); await owner.shutdown(); await library.closeLibrary()
  }

  @Test("Owned-window dispatch selects, deletes, undoes and redoes a generated Flow stroke")
  func generatedPruningWindowDispatch() async throws {
    _ = NSApplication.shared
    let directory = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: directory) }
    let library = DrawingLibrary(directoryURL: directory), owner = PortraitStudioModel(library: DrawingLibrary(directoryURL: directory.appendingPathComponent("camera")))
    let model = FlowAuthoringModel(directory: directory, library: library, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(8), title: "Native Flow pruning fixture")
    model.count = 3; await model.generate(refining: false)
    await model.browseCandidate(try #require(model.roundCandidates.first?.id), prune: true)
    let original = try #require(model.program)
    let host = NSHostingController(rootView: FlowAuthoringView(model: model, camera: owner, embedded: true).frame(width: 1280, height: 850).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light))
    let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 1280, height: 850), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua); window.contentViewController = host; window.orderFront(nil)
    defer { window.orderOut(nil); window.contentViewController = nil; window.close() }
    try #require(await wait { self.views(host.view).compactMap { $0 as? PortraitLineEditorNSView }.first?.editingEnabled == true })
    let canvas = try #require(views(host.view).compactMap { $0 as? PortraitLineEditorNSView }.first)
    model.tool = .lasso
    try #require(await wait { canvas.tool == .lasso })
    let hit = try clickLine(canvas, through: window)
    try #require(await wait { model.selection == [hit] && canvas.selected == [hit] })
    try snapshot(host.view, name: "generated-flow-selected.png")
    try sendKey(window, keyCode: 51, characters: "\u{7f}")
    try #require(await wait { !model.isBusy && model.removedIDs == [hit] && canvas.editingEnabled && canvas.removed == [hit] })
    try snapshot(host.view, name: "generated-flow-deleted.png")
    try sendKey(window, keyCode: 6, characters: "z", modifiers: .command)
    try #require(await wait { !model.isBusy && model.removedIDs.isEmpty && canvas.editingEnabled && canvas.removed.isEmpty })
    try sendKey(window, keyCode: 6, characters: "z", modifiers: [.command, .shift])
    try #require(await wait { !model.isBusy && model.removedIDs == [hit] && canvas.editingEnabled && canvas.removed == [hit] })
    let sent = try await model.retainedDrawing()
    #expect(sent.program.strokes == original.strokes.filter { $0.id != hit })
    #expect(sent.program.strokes.count == original.strokes.count - 1)
    window.contentViewController = nil
    _ = await model.shutdown(); await owner.shutdown(); await library.closeLibrary()
  }

  @Test("Disposable historical77 editor receives owned-window pointer/key dispatch and saves an exact child",
    .enabled(if: ProcessInfo.processInfo.environment["PORTRAIT_RETAINED77_ROOT"] != nil))
  func retained77WindowDispatch() async throws {
    _ = NSApplication.shared
    let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PORTRAIT_RETAINED77_ROOT"]))
    try #require(root.path.hasPrefix("/tmp/portrait-studio-native-") || root.path.hasPrefix("/private/tmp/portrait-studio-native-"))
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("library"))
    var route = try JSONDecoder().decode(DrawingLibraryRoute.self, from: Data(contentsOf: root.appendingPathComponent("retained77-route.json")))
    let reference = try #require(route.drawing), original = try await library.drawing(reference)
    try #require(original.program.strokes.count == 77)
    let browser = DrawingLibraryBrowserModel(sketches: PortraitSketchCollection(library: library))
    // Use one borrowed collection for both the production view and its editor owner.
    let collection = browser.sketches
    let host = NSHostingController(rootView: DrawingLibraryBrowser(sketches: collection, close: {}, route: Binding(get: { route }, set: { route = $0 }), model: browser, embedded: true).frame(width: 1280, height: 850).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light))
    let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 1280, height: 850), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua); window.contentViewController = host; window.orderFront(nil)
    defer { window.orderOut(nil); window.contentViewController = nil; window.close() }
    try #require(await wait { !browser.isBusy && collection.selected?.reference == reference })
    let editor = try #require(browser.beginEdit())
    try #require(await wait { self.views(host.view).compactMap { $0 as? PortraitLineEditorNSView }.first?.editingEnabled == true })
    let canvas = try #require(views(host.view).compactMap { $0 as? PortraitLineEditorNSView }.first)
    editor.tool = .lasso
    try #require(await wait { canvas.tool == .lasso })
    let hit = try clickLine(canvas, through: window)
    try #require(await wait { editor.selection == [hit] && canvas.selected == [hit] })
    try snapshot(host.view, name: "retained77-selected.png")
    try sendKey(window, keyCode: 51, characters: "\u{7f}")
    #expect(editor.removed == [hit] && editor.remainingCount == 76)
    try sendKey(window, keyCode: 6, characters: "z", modifiers: .command)
    #expect(editor.removed.isEmpty && editor.remainingCount == 77)
    try sendKey(window, keyCode: 6, characters: "z", modifiers: [.command, .shift])
    #expect(editor.removed == [hit] && editor.remainingCount == 76)
    try #require(await wait { canvas.removed == [hit] })
    try snapshot(host.view, name: "retained77-deleted.png")
    try #require(await editor.save())
    let child = try #require(editor.savedDrawing)
    try #require(browser.finishEdit(editor))
    #expect(child.parent == .present(reference) && child.program.strokes == original.program.strokes.filter { $0.id != hit })
    #expect(try await library.drawing(reference).program.strokes.count == 77)
    await browser.select(child.reference).value
    let reopened = try #require(browser.beginEdit()); await reopened.load()
    #expect(reopened.base.reference == child.reference && reopened.remainingCount == 76)
    #expect(reopened.base.program == child.program && reopened.original?.program == child.program)
    #expect(reopened.removed.isEmpty, "A new draft starts from the saved76-stroke child; it does not reapply the parent's removal mask.")
    browser.dismissEditor(); browser.close(); window.contentViewController = nil
    await collection.shutdown(); await library.closeLibrary()
  }

  private func clickLine(_ canvas: PortraitLineEditorNSView, through window: NSWindow) throws -> StrokeID {
    let program = try #require(canvas.program)
    let geometry = PortraitLineSelectionGeometry(program: program, size: canvas.bounds.size)
    let point = try #require(geometry.lines.first?.points.first)
    let id = try #require(geometry.hit(point, excluding: []))
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
      let event = try #require(NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
      window.sendEvent(event)
    }
    return id
  }
  private func sendKey(_ window: NSWindow, keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags = []) throws {
    let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
    if modifiers.contains(.command) { try #require(window.performKeyEquivalent(with: event), "The owned window must route Undo/Redo; first responder: \(String(describing: window.firstResponder)).") }
    else { window.sendEvent(event) }
  }
  private func snapshot(_ view: NSView, name: String) throws {
    guard let directory = ProcessInfo.processInfo.environment["PORTRAIT_WORKSPACE_SNAPSHOT_DIR"] else { return }
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
  }

  private func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }

  private func drag(_ view: NSView, from start: CGPoint, to end: CGPoint) throws {
    func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
      try #require(NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }
    view.mouseDown(with: try event(.leftMouseDown, start))
    view.mouseDragged(with: try event(.leftMouseDragged, end))
    view.mouseUp(with: try event(.leftMouseUp, end))
  }
  private func tree(_ root: any NSAccessibilityProtocol) -> [any NSAccessibilityProtocol] {
    var pending: [any NSAccessibilityProtocol] = [root], result: [any NSAccessibilityProtocol] = []
    if let window = root as? NSWindow, let content = window.contentView {
      pending.append(content)
      pending += NSAccessibility.unignoredChildrenForOnlyChild(from: content).compactMap { $0 as? any NSAccessibilityProtocol }
    }
    var seen = Set<ObjectIdentifier>()
    while let element = pending.popLast(), result.count < 4096 {
      guard seen.insert(ObjectIdentifier(element)).inserted else { continue }
      result.append(element); pending += (element.accessibilityChildren() ?? []).compactMap { $0 as? any NSAccessibilityProtocol }
    }
    return result
  }
  private func button(_ id: String, in window: NSWindow) -> (any NSAccessibilityProtocol)? {
    tree(window).first { $0.accessibilityRole() == .button && $0.accessibilityIdentifier() == id }
  }
  private func press(_ id: String, in window: NSWindow) throws {
    let action = try #require(button(id, in: window), "Missing native action \(id)")
    try #require(action.isAccessibilityEnabled()); try #require(action.accessibilityPerformPress())
  }
  private func wait(_ predicate: () -> Bool) async -> Bool {
    for _ in 0..<500 { if predicate() { return true }; try? await Task.sleep(for: .milliseconds(10)) }
    return predicate()
  }
}

private actor StudioShellRenderGate {
  private var armed = false
  private var remaining = 0
  private var paused = false
  private var releaseWaiter: CheckedContinuation<Void, Never>?
  func arm(after calls: Int = 1) { armed = true; remaining = calls }
  func pauseIfArmed() async {
    guard armed else { return }
    remaining -= 1
    guard remaining <= 0 else { return }
    armed = false; paused = true
    await withCheckedContinuation { releaseWaiter = $0 }
    paused = false
  }
  func waitUntilPaused() async -> Bool {
    for _ in 0..<500 {
      if paused { return true }
      if Task.isCancelled { return false }
      try? await Task.sleep(for: .milliseconds(20))
    }
    return paused
  }
  func release() { armed = false; remaining = 0; releaseWaiter?.resume(); releaseWaiter = nil }
}

private actor StudioShellCameraDriver: CameraCaptureDriver {
  private(set) var starts = 0
  private var frames: Task<Void, Never>?
  func authorizationState() async -> CameraAuthorizationState { .authorized }
  func requestAccess() async -> Bool { true }
  func discoverDevices() async -> [CameraDevice] { [.init(id: .init(rawValue: "studio-shell-fake"), name: "Studio acceptance fake camera")] }
  func start(deviceID: CameraDeviceID, maximumFramesPerSecond: Double?, eventHandler: @escaping @Sendable (CameraDriverEvent) -> Void) async throws -> CameraCaptureDriverStartResult {
    starts += 1
    frames = Task {
      var stamp: UInt64 = 1
      while !Task.isCancelled {
        eventHandler(.frame(.init(width: 2, height: 2, rowBytes: 8, bytes: Data(repeating: UInt8(stamp % 255), count: 16), captureNanoseconds: stamp)))
        stamp += 1
        do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
      }
    }
    return .init(appliedMaximumFramesPerSecond: maximumFramesPerSecond)
  }
  func stop() async { let old = frames; frames = nil; old?.cancel(); await old?.value }
}
private actor StudioShellPhotoAcquirer: PortraitPhotoAcquiring {
  func acquire(_ input: PortraitPhotoInput) async throws -> PortraitAcquiredPhoto {
    guard case .frame(let frame) = input else { throw CocoaError(.fileReadUnsupportedScheme) }
    return .init(data: FlowAuthoringFixture.image(Int(frame.captureNanoseconds % 20)), sourcePixelExtent: nil)
  }
}
