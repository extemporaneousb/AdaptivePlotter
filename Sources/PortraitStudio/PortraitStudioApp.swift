import AppKit
import SwiftUI
import DrawingLibrary
import PortraitCore
import PortraitLibrary
import PortraitStudioUI

@main
struct PortraitStudioApp: App {
  @NSApplicationDelegateAdaptor(PortraitStudioApplicationDelegate.self) private var delegate
  @State private var dojo: FlowDojoModel
  @State private var acquisition: PortraitStudioModel
  private let launchError: String?
  private let library: DrawingLibrary

  init() {
    let args = CommandLine.arguments
    var location = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/PortraitStudio/DrawingLibrary", isDirectory: true)
    var error: String?
    if let index = args.firstIndex(of: "--library") {
      if args.filter({ $0 == "--library" }).count == 1, index + 1 < args.count, args[index + 1].hasPrefix("/") {
        location = URL(fileURLWithPath: args[index + 1], isDirectory: true)
      } else { error = "--library requires one absolute directory path." }
    }
    let owner = DrawingLibrary(directoryURL: location)
    library = owner
    _dojo = State(initialValue: FlowDojoModel(directory: location, library: owner))
    _acquisition = State(initialValue: PortraitStudioModel(library: owner))
    launchError = error
  }

  var body: some Scene {
    Window("Portrait Studio — Flow Edge Dojo", id: "portrait-studio") {
      if let launchError {
        ContentUnavailableView("Drawing Library configuration", systemImage: "folder.badge.questionmark", description: Text(launchError))
      } else {
        PortraitStudioDojoWindow(dojo: dojo, acquisition: acquisition, library: library, delegate: delegate)
      }
    }.defaultSize(width: 1440, height: 940)
  }
}

struct PortraitStudioDojoWindow: View {
  @Environment(\.openWindow) private var openWindow
  @Bindable var dojo: FlowDojoModel
  @Bindable var acquisition: PortraitStudioModel
  let library: DrawingLibrary
  @ObservedObject var delegate: PortraitStudioApplicationDelegate
  @State private var libraryError: String?
  @AppStorage("PortraitStudio.libraryRoute.v1") private var savedRoute = Data()
  private let routeOverride: Binding<DrawingLibraryRoute>?
  private var route: Binding<DrawingLibraryRoute> {
    routeOverride ?? Binding(get: { .restored(savedRoute) }, set: { savedRoute = $0.encoded })
  }
  init(dojo: FlowDojoModel, acquisition: PortraitStudioModel, library: DrawingLibrary,
    delegate: PortraitStudioApplicationDelegate, route: Binding<DrawingLibraryRoute>? = nil) {
    self.dojo = dojo; self.acquisition = acquisition; self.library = library; self.delegate = delegate
    routeOverride = route
  }
  /// Install the same route binding used by the window; a document can arrive
  /// before this callback exists, so the delegate retains only its reveal ref.
  func installDocumentHandling() {
    delegate.installDocumentHandling(library: library, acquisition: acquisition) { reference in
      var next = route.wrappedValue
      next.showDrawing(reference)
      next.workspace = .library
      route.wrappedValue = next
    }
  }
  var drawingBrowser: DrawingLibraryBrowser {
    DrawingLibraryBrowser(sketches: acquisition.sketches, close: { Task { libraryError = await showStudio() } },
      handoff: { drawing, request in
        guard request.isCurrent else { return "Drawing handoff was cancelled." }
        return await prepareDrawingAtDestination(drawing, isStillCurrent: { request.isCurrent })
      }, route: route, openStudio: openPhoto)
  }
  private func prepareDrawingAtDestination(_ drawing: Drawing,
    isStillCurrent: @escaping @MainActor () -> Bool = { true }) async -> String? {
    let opening = route.wrappedValue
    return await delegate.prepareAtDestination(drawing, isStillCurrent: {
      route.wrappedValue == opening && isStillCurrent()
    })
  }
  private func showStudio() async -> String? {
    if let ref = route.wrappedValue.photo { return await openPhoto(ref) }
    route.wrappedValue.workspace = .drawingStudio; return nil
  }
  private func openPhoto(_ ref: PhotoRef) async -> String? {
    let openingWorkspace = route.wrappedValue.workspace
    await dojo.open(); let failure = await dojo.selectPhoto(ref, isStillCurrent: {
      route.wrappedValue.photo == ref && route.wrappedValue.workspace == openingWorkspace
    })
    guard route.wrappedValue.photo == ref, route.wrappedValue.workspace == openingWorkspace else { return "The Library selection changed." }
    if let failure { return failure }
    guard dojo.currentPhotoRef == ref, dojo.error == nil else { return dojo.error ?? "The exact Photo is unavailable for authoring." }
    route.wrappedValue.workspace = .drawingStudio
    return nil
  }
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        ForEach([DrawingWorkspace.library, .drawingStudio], id: \.self) { workspace in
          Button(workspace.title) {
            if workspace == .drawingStudio { Task { libraryError = await showStudio() } }
            else { route.wrappedValue.workspace = workspace }
          }
            .accessibilityIdentifier("portraitStudio.workspace.\(workspace.rawValue)")
        }
        Spacer()
      }.padding(12)
      Divider()
      if route.wrappedValue.workspace == .library { drawingBrowser }
      else { FlowDojoView(model: dojo, camera: acquisition, selectCamera: {
      await acquisition.startCamera(); return acquisition.cameraStatus
      }, handoffTitle: "Prepare in AdaptivePlotter", handoff: { drawing in
        await prepareDrawingAtDestination(drawing)
      }, photoSelected: { ref in if let ref { route.wrappedValue.selectPhoto(ref) } }) }
    }
    .frame(minWidth: 1100, minHeight: 720)
    .overlay(alignment: .bottom) {
      VStack {
        if let libraryError { Text(libraryError).foregroundStyle(.red) }
        if let error = delegate.documentError { Text(error).foregroundStyle(.red) }
        if let status = delegate.destinationStatus { Text(status).foregroundStyle(.secondary) }
      }.padding()
    }
    .task {
      delegate.dojo = dojo
      installDocumentHandling()
      delegate.restorePortfolioWindow = {
        openWindow(id: "portrait-studio")
        NSApp.activate(ignoringOtherApps: true)
      }
      do { try await library.open() }
      catch { libraryError = "Drawing Library unavailable: " + error.localizedDescription }
      if route.wrappedValue.workspace == .drawingStudio, let ref = route.wrappedValue.photo {
        await dojo.open(); await dojo.selectPhoto(ref, isStillCurrent: { route.wrappedValue.photo == ref && route.wrappedValue.workspace == .drawingStudio })
        if route.wrappedValue.workspace == .drawingStudio, route.wrappedValue.photo == ref,
          dojo.currentPhotoRef != ref || dojo.error != nil {
          libraryError = dojo.error ?? "The exact Photo is unavailable for authoring."
          route.wrappedValue.workspace = .library
        }
      }
      await acquisition.discover(excluding: nil)
      while !Task.isCancelled {
        await delegate.recoverDestinationRequests()
        try? await Task.sleep(for: .seconds(1))
      }
    }
  }
}

@MainActor
final class PortraitStudioApplicationDelegate: NSObject, NSApplicationDelegate, ObservableObject {
  @Published var destinationStatus: String?
  @Published var documentError: String?
  var dojo: FlowDojoModel?
  var acquisition: PortraitStudioModel?
  var library: DrawingLibrary?
  var restorePortfolioWindow: (() -> Void)?
  private var revealDrawing: ((DrawingRef) -> Void)?
  private var pendingDrawingReveal: DrawingRef?
  private var pendingDrawingDocuments: [URL] = []
  private var drawingDocumentTask: Task<Void, Never>?
  private var terminating = false
  var destinationRoot: URL = DrawingDestinationFiles.defaultRoot
  var openDestination: ((URL) async throws -> Void)?
  private var destinationClient: DrawingDestinationClient?
  private var handoffs = 0
  private var handoffWaiters: [CheckedContinuation<Void, Never>] = []
  private func finishHandoff() {
    handoffs -= 1
    if handoffs == 0 { let waiters = handoffWaiters; handoffWaiters = []; waiters.forEach { $0.resume() } }
  }
  func prepareAtDestination(_ drawing: Drawing, isStillCurrent: @escaping @MainActor () -> Bool = { true }) async -> String? {
    guard !terminating, isStillCurrent() else { return "Drawing handoff was cancelled." }
    guard let library else { return "The Drawing Library is unavailable." }
    handoffs += 1; defer { finishHandoff() }
    destinationStatus = nil
    do {
      let retained = try await library.retain(drawing, reason: "destination-handoff")
      guard !terminating, isStillCurrent() else { return "Drawing handoff was cancelled." }
      let client = destinationClient ?? DrawingDestinationClient(library: library, root: destinationRoot)
      destinationClient = client
      let delivery = try await client.enqueue(.prepare(retained.reference), drawing: retained.reference)
      // Enqueue admission is durable. Closing the source after it is admitted
      // may leave Prepare queued, but must not foreground an obsolete window.
      guard !terminating, isStillCurrent() else {
        destinationStatus = "Drawing preparation is queued."
        return nil
      }
      let url = DrawingDestinationFiles.requestURL(root: client.root, client: delivery.client, delivery: delivery.id)
      if let openDestination {
        try await openDestination(url)
        destinationStatus = "Opening the drawing preview in AdaptivePlotter. Submission is unavailable."
        return nil
      }
      guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.bullard.AdaptivePlotter") else {
        return "AdaptivePlotter is unavailable. The preparation request is retained for retry."
      }
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      try await NSWorkspace.shared.open([url], withApplicationAt: application, configuration: configuration)
      destinationStatus = "Opening the drawing preview in AdaptivePlotter. Submission is unavailable."
      return nil
    } catch { return error.localizedDescription }
  }
  func recoverDestinationRequests() async {
    guard !terminating, let library else { return }
    handoffs += 1; defer { finishHandoff() }
    let client = destinationClient ?? DrawingDestinationClient(library: library, root: destinationRoot)
    destinationClient = client
    do {
      for reply in try await client.recoverPending() {
        if case .refused = reply { documentError = "The drawing could not be prepared. Review it in AdaptivePlotter." }
        if case .prepared = reply { documentError = nil; destinationStatus = "Preparation received from AdaptivePlotter. Review the preview. Submission is unavailable." }
      }
    } catch { documentError = "Drawing handoff recovery failed: " + error.localizedDescription }
  }
  func installDocumentHandling(library: DrawingLibrary, acquisition: PortraitStudioModel,
    reveal: @escaping (DrawingRef) -> Void) {
    self.library = library; self.acquisition = acquisition; revealDrawing = reveal
    if let reference = pendingDrawingReveal {
      pendingDrawingReveal = nil
      if acquisition.sketches.selected?.reference == reference { reveal(reference) }
    }
    drainDrawingDocuments()
  }
  func application(_ sender: NSApplication, open urls: [URL]) {
    guard !terminating else { return }
    pendingDrawingDocuments += urls
    drainDrawingDocuments()
  }
  func settleDrawingDocuments() async { await drawingDocumentTask?.value }
  private func drainDrawingDocuments() {
    guard !terminating, drawingDocumentTask == nil, !pendingDrawingDocuments.isEmpty,
      let library, let acquisition else { return }
    handoffs += 1
    drawingDocumentTask = Task {
      defer { finishHandoff(); drawingDocumentTask = nil }
      while !pendingDrawingDocuments.isEmpty {
        let url = pendingDrawingDocuments.removeFirst()
        do {
          let refs = try await library.importDrawings(from: url)
          guard let reference = refs.first else { throw DrawingExchangeError.malformed("Drawing document has no Drawing") }
          try await acquisition.sketches.select(reference)
          documentError = nil
          destinationStatus = "Drawing opened in Library."
          if let revealDrawing { revealDrawing(reference) }
          else { pendingDrawingReveal = reference }
          restorePortfolioWindow?()
        } catch { documentError = "Drawing could not be opened: " + error.localizedDescription }
      }
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !terminating else { return .terminateLater }
    if dojo?.needsRecovery == true {
      restorePortfolioWindow?()
      let alert = NSAlert(); alert.messageText = "Portfolio autosave needs recovery"
      alert.informativeText = "Resolve the write error and use Recover autosave before closing. Pending edits remain in this window."
      alert.addButton(withTitle: "Return to portfolio"); alert.runModal()
      return .terminateCancel
    }
    terminating = true
    Task {
      if await dojo?.shutdown() == false {
        restorePortfolioWindow?()
        terminating = false
        sender.reply(toApplicationShouldTerminate: false)
        return
      }
      if handoffs > 0 { await withCheckedContinuation { handoffWaiters.append($0) } }
      await acquisition?.shutdown()
      await library?.closeLibrary()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}
