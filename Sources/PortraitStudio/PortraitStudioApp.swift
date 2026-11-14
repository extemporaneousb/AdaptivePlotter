import AppKit
import SwiftUI
import DrawingLibrary
import PortraitCore
import PortraitLibrary
import PortraitStudioUI

@main
struct PortraitStudioApp: App {
  @NSApplicationDelegateAdaptor(PortraitStudioApplicationDelegate.self) private var delegate
  @State private var authoring: FlowAuthoringModel
  @State private var acquisition: PortraitStudioModel
  private let launchError: String?
  private let library: DrawingLibrary

  static var defaultLibraryURL: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/PortraitStudio/DrawingLibrary", isDirectory: true)
  }

  init() {
    let args = CommandLine.arguments
    var location = Self.defaultLibraryURL
    var error: String?
    if let index = args.firstIndex(of: "--library") {
      if args.filter({ $0 == "--library" }).count == 1, index + 1 < args.count, args[index + 1].hasPrefix("/") {
        location = URL(fileURLWithPath: args[index + 1], isDirectory: true)
      } else { error = "--library requires one absolute directory path." }
    }
    let owner = DrawingLibrary(directoryURL: location, payloadValidators: DrawingDestinationResult.payloadValidators)
    library = owner
    _authoring = State(initialValue: FlowAuthoringModel(directory: location, library: owner))
    _acquisition = State(initialValue: PortraitStudioModel(library: owner))
    launchError = error
  }

  var body: some Scene {
    Window("Portrait Studio", id: "portrait-studio") {
      if let launchError {
        ContentUnavailableView("Drawing Library configuration", systemImage: "folder.badge.questionmark", description: Text(launchError))
      } else {
        PortraitStudioAuthoringWindow(authoring: authoring, acquisition: acquisition, library: library, delegate: delegate)
      }
    }.defaultSize(width: 1440, height: 940)
      .commands { PortraitStudioFileCommands() }
  }
}

struct PortraitStudioAuthoringWindow: View {
  @Environment(\.openWindow) private var openWindow
  @Bindable var authoring: FlowAuthoringModel
  @Bindable var acquisition: PortraitStudioModel
  let library: DrawingLibrary
  private let showsCaptureLight: Bool
  @ObservedObject var delegate: PortraitStudioApplicationDelegate
  @State private var libraryError: String?
  @State private var browserModel: DrawingLibraryBrowserModel
  @State private var routeEpoch: UInt64 = 0
  @State private var sending = false
  @AppStorage("PortraitStudio.destination.v1") private var savedDestination = ""
  private var destination: PortraitStudioDestination {
    .restored(savedDestination, route: route.wrappedValue, hasSavedRoute: !savedRoute.isEmpty || routeOverride != nil)
  }
  private var destinationBinding: Binding<PortraitStudioDestination> {
    Binding(get: { destination }, set: { next in
      routeEpoch &+= 1; savedDestination = next.rawValue
      route.wrappedValue.workspace = next == .photos ? .library : .drawingStudio
      if next != .photos, (next == .booth || route.wrappedValue.drawing == nil), let ref = route.wrappedValue.photo,
        authoring.currentPhotoRef != ref {
        let epoch = routeEpoch
        Task {
          _ = await authoring.selectPhoto(ref, isStillCurrent: { routeEpoch == epoch && route.wrappedValue.photo == ref })
        }
      }
    })
  }
  @AppStorage("PortraitStudio.libraryRoute.v1") private var savedRoute = Data()
  private let routeOverride: Binding<DrawingLibraryRoute>?
  private var route: Binding<DrawingLibraryRoute> {
    Binding(get: { routeOverride?.wrappedValue ?? .restored(savedRoute) }, set: { next in
      routeEpoch &+= 1
      if let routeOverride { routeOverride.wrappedValue = next } else { savedRoute = next.encoded }
    })
  }
  init(authoring: FlowAuthoringModel, acquisition: PortraitStudioModel, library: DrawingLibrary,
    delegate: PortraitStudioApplicationDelegate, route: Binding<DrawingLibraryRoute>? = nil, showsCaptureLight: Bool = true) {
    self.authoring = authoring; self.acquisition = acquisition; self.library = library; self.delegate = delegate
    routeOverride = route; self.showsCaptureLight = showsCaptureLight
    _browserModel = State(initialValue: DrawingLibraryBrowserModel(sketches: acquisition.sketches))
    let location = library.directoryURL.standardizedFileURL.resolvingSymlinksInPath()
    let isDefault = location == PortraitStudioApp.defaultLibraryURL.standardizedFileURL.resolvingSymlinksInPath()
    let key = "PortraitStudio.libraryRoute.v1" + (isDefault ? "" : "." + location.path)
    _savedRoute = AppStorage(wrappedValue: Data(), key)
    _savedDestination = AppStorage(wrappedValue: "", "PortraitStudio.destination.v1" + (isDefault ? "" : "." + location.path))
  }
  /// Install the same route binding used by the window; a document can arrive
  /// before this callback exists, so the delegate retains only its reveal ref.
  func installDocumentHandling() {
    delegate.installDocumentHandling(library: library, acquisition: acquisition) { reference in
      var next = route.wrappedValue
      next.showDrawing(reference)
      next.workspace = .drawingStudio
      route.wrappedValue = next
      destinationBinding.wrappedValue = .drawing
    }
  }
  var drawingBrowser: DrawingLibraryBrowser {
    DrawingLibraryBrowser(sketches: acquisition.sketches, close: {},
      handoff: { drawing, request in
        guard request.isCurrent else { return "Drawing handoff was cancelled." }
        return await prepareDrawingAtDestination(drawing, isStillCurrent: { request.isCurrent })
      }, route: route, openStudio: openPhoto, model: browserModel, embedded: true)
  }
  private func prepareDrawingAtDestination(_ drawing: Drawing,
    isStillCurrent: @escaping @MainActor () -> Bool = { true }) async -> String? {
    let opening = route.wrappedValue, epoch = routeEpoch
    return await delegate.prepareAtDestination(drawing, isStillCurrent: {
      routeEpoch == epoch && route.wrappedValue == opening && isStillCurrent()
    })
  }
  private func openPhoto(_ ref: PhotoRef) async -> String? {
    let openingWorkspace = route.wrappedValue.workspace, epoch = routeEpoch
    await authoring.open()
    guard routeEpoch == epoch, route.wrappedValue.photo == ref, route.wrappedValue.workspace == openingWorkspace else { return "The Library selection changed." }
    let failure = await authoring.selectPhoto(ref, isStillCurrent: {
      routeEpoch == epoch && route.wrappedValue.photo == ref && route.wrappedValue.workspace == openingWorkspace
    })
    guard routeEpoch == epoch, route.wrappedValue.photo == ref, route.wrappedValue.workspace == openingWorkspace else { return "The Library selection changed." }
    if let failure { return failure }
    guard authoring.currentPhotoRef == ref, authoring.error == nil else { return authoring.error ?? "The exact Photo is unavailable for authoring." }
    destinationBinding.wrappedValue = .booth
    return nil
  }
  private var showsRetainedDrawing: Bool {
    destination == .photos || (destination == .drawing && route.wrappedValue.drawing != nil)
  }
  var sendUnavailableReason: String? {
    if sending { return "Sending drawing…" }
    if showsRetainedDrawing {
      guard let selected = route.wrappedValue.drawing else { return "Select a retained drawing to send." }
      guard selected == acquisition.sketches.selected?.reference else { return "Wait for the exact selected drawing to load." }
      return browserModel.canSendSelected ? nil : "Finish loading or editing a supported nonempty drawing before sending."
    }
    guard authoring.currentPhotoRef == route.wrappedValue.photo else { return "Open the exact selected photo before sending." }
    if let reason = authoring.sendUnavailableReason { return reason }
    if destination == .booth, authoring.recommendationCandidate?.id != authoring.candidate?.id {
      return "Wait for a drawing for this exact photo and region."
    }
    return nil
  }
  var canSendToPlotter: Bool { sendUnavailableReason == nil }
  private func sendToPlotter() async {
    guard canSendToPlotter else { return }
    let epoch = routeEpoch, opening = route.wrappedValue, currentDestination = destination
    let retained = showsRetainedDrawing
    let generated = retained ? nil : PortraitStudioGeneratedHandoffSelection(model: authoring)
    guard retained || generated != nil else { return }
    sending = true; defer { sending = false }
    let current: @MainActor () -> Bool = {
      routeEpoch == epoch && route.wrappedValue == opening && destination == currentDestination
        && (retained || generated?.isCurrent(in: authoring) == true)
    }
    if retained {
      await browserModel.sendSelected { drawing, request in
        guard current(), request.isCurrent else { return "Drawing handoff was cancelled." }
        return await delegate.prepareAtDestination(drawing, isStillCurrent: { current() && request.isCurrent })
      }
    } else {
      do {
        let drawing = try await authoring.retainedDrawing()
        guard current() else { return }
        libraryError = await delegate.prepareAtDestination(drawing, isStillCurrent: current)
      } catch { if current() { libraryError = error.localizedDescription } }
    }
  }
  private func importPhotos(multiple: Bool) async {
    guard !authoring.isBusy, !authoring.needsRecovery else { return }
    let urls = await FlowAuthoringFiles.openPhotos(multiple: multiple)
    var failures: [String] = []
    for url in urls {
      if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
        await authoring.importPhotoCollection(url)
      } else {
        do {
          let bytes = try await Task.detached { try FlowAuthoringFiles.readImage(url) }.value
          await authoring.addPhoto(data: bytes, title: url.deletingPathExtension().lastPathComponent,
            mediaType: url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg")
        } catch { failures.append(url.lastPathComponent + ": " + error.localizedDescription) }
      }
      if let error = authoring.error { failures.append(url.lastPathComponent + ": " + error) }
    }
    guard !urls.isEmpty else { return }
    if let ref = authoring.currentPhotoRef { route.wrappedValue.selectPhoto(ref) }
    destinationBinding.wrappedValue = .booth
    libraryError = failures.isEmpty ? nil : failures.joined(separator: "\n")
  }
  private func exportSelected() async {
    guard canSendToPlotter, let url = await FlowAuthoringFiles.exportDrawing() else { return }
    do {
      if showsRetainedDrawing, let ref = acquisition.sketches.selected?.reference { try await library.exportDrawing(ref, to: url) }
      else { try await authoring.exportDrawing(to: url) }
    } catch { libraryError = error.localizedDescription }
  }
  var body: some View {
    VStack(spacing: 0) {
      PortraitStudioHeader(destination: destinationBinding, canSend: canSendToPlotter,
        sendReason: sendUnavailableReason,
        send: { Task { await sendToPlotter() } })
      Divider()
      if destination == .booth {
        PortraitStudioBooth(model: authoring, camera: acquisition,
          showsSource: route.wrappedValue.photo != nil && authoring.currentPhotoRef == route.wrappedValue.photo,
          showsCaptureLight: showsCaptureLight, photoSelected: { ref in
          if destination == .booth { route.wrappedValue.selectPhoto(ref) }
        }) {
          route.wrappedValue.drawing = nil; destinationBinding.wrappedValue = .drawing
        }
      } else if showsRetainedDrawing { drawingBrowser }
      else if route.wrappedValue.photo != nil && authoring.currentPhotoRef != route.wrappedValue.photo {
        ContentUnavailableView("Opening the selected photo", systemImage: "photo", description: Text(authoring.error ?? "Loading the exact source before authoring."))
      } else if route.wrappedValue.photo == nil {
        ContentUnavailableView("Choose a photo", systemImage: "photo", description: Text("Open a source in Photo Booth or Photos before exploring drawings."))
      } else {
        FlowAuthoringView(model: authoring, camera: acquisition, embedded: true, photoSelected: { ref in
          if let ref { route.wrappedValue.selectPhoto(ref) }
        })
      }
    }
    .frame(minWidth: 1100, minHeight: 720)
    .focusedSceneValue(\.portraitStudioFileActions, PortraitStudioFileActions(
      canImport: !authoring.isBusy && !authoring.needsRecovery, canExport: canSendToPlotter,
      importPhotos: { multiple in Task { await importPhotos(multiple: multiple) } }, export: { Task { await exportSelected() } }))
    .onChange(of: route.wrappedValue.photo) { _, _ in libraryError = nil }
    .overlay(alignment: .bottom) {
      VStack {
        if let libraryError { Text(libraryError).foregroundStyle(.red) }
        if let error = delegate.documentError { Text(error).foregroundStyle(.red) }
        if let status = delegate.destinationStatus { Text(status).foregroundStyle(.secondary) }
      }.padding()
    }
    .task {
      delegate.authoring = authoring
      installDocumentHandling()
      delegate.restorePortfolioWindow = {
        openWindow(id: "portrait-studio")
        NSApp.activate(ignoringOtherApps: true)
      }
      do { try await library.open() }
      catch { libraryError = "Drawing Library unavailable: " + error.localizedDescription }
      await authoring.open()
      if let ref = route.wrappedValue.photo {
        let epoch = routeEpoch
        _ = await authoring.selectPhoto(ref, isStillCurrent: { routeEpoch == epoch && route.wrappedValue.photo == ref })
      } else if route.wrappedValue.drawing == nil, let ref = authoring.currentPhotoRef {
        route.wrappedValue.selectPhoto(ref)
      }
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
  var authoring: FlowAuthoringModel?
  var acquisition: PortraitStudioModel?
  var library: DrawingLibrary?
  var restorePortfolioWindow: (() -> Void)?
  /// AppKit response adapter; terminating remains the sole admission flag.
  var replyToTermination: @MainActor (NSApplication, Bool) -> Void = {
    $0.reply(toApplicationShouldTerminate: $1)
  }
  private var revealDrawing: ((DrawingRef) -> Void)?
  private var pendingDrawingReveal: DrawingRef?
  private var pendingDestinationReplies: [DrawingDestinationReply] = []
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
      guard !terminating else { return nil }
      guard isStillCurrent() else { return "Drawing handoff was cancelled." }
      let client = destinationClient ?? DrawingDestinationClient(library: library, root: destinationRoot)
      destinationClient = client
      let delivery = try await client.enqueue(.prepare(retained.reference), drawing: retained.reference)
      // Enqueue admission is durable. Closing the source after it is admitted
      // may leave Prepare queued, but must not foreground an obsolete window.
      guard !terminating, isStillCurrent() else { return nil }
      let url = DrawingDestinationFiles.requestURL(root: client.root, client: delivery.client, delivery: delivery.id)
      if let openDestination {
        try await openDestination(url)
        guard !terminating, isStillCurrent() else { return nil }
        destinationStatus = "Opening the drawing preview in AdaptivePlotter. Review it before choosing Draw."
        return nil
      }
      guard let application = Self.plotterApplicationURL() else {
        return "AdaptivePlotter is unavailable. The preparation request is retained for retry."
      }
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      try await NSWorkspace.shared.open([url], withApplicationAt: application, configuration: configuration)
      guard !terminating, isStillCurrent() else { return nil }
      destinationStatus = "Opening the drawing preview in AdaptivePlotter. Review it before choosing Draw."
      return nil
    } catch { return terminating || !isStillCurrent() ? nil : error.localizedDescription }
  }
  private static func plotterApplicationURL() -> URL? {
    let identifier = "com.bullard.AdaptivePlotter"
    let sibling = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("AdaptivePlotter.app")
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
      .filter { !$0.isTerminated }.compactMap(\.bundleURL)
    if let paired = running.first(where: { $0.resolvingSymlinksInPath() == sibling.resolvingSymlinksInPath() }) { return paired }
    if let current = running.first { return current }
    if Bundle(url: sibling)?.bundleIdentifier == identifier { return sibling }
    return NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
  }
  func recoverDestinationRequests() async {
    guard !terminating, let library else { return }
    handoffs += 1; defer { finishHandoff() }
    let client = destinationClient ?? DrawingDestinationClient(library: library, root: destinationRoot)
    destinationClient = client
    do {
      pendingDestinationReplies += try await client.recoverPending()
      presentRecoveredDestinationReplies()
    } catch {
      if !terminating { documentError = "Drawing handoff recovery failed: " + error.localizedDescription }
    }
  }
  private func presentRecoveredDestinationReplies() {
    guard !terminating else { return }
    let replies = pendingDestinationReplies; pendingDestinationReplies = []
    for reply in replies {
      if case .refused = reply { documentError = "The drawing could not be prepared. Review it in AdaptivePlotter." }
      if case .referencePreview = reply {
        documentError = nil
        destinationStatus = "Drawing opened in AdaptivePlotter. Restore placement calibration to prepare a motion plan."
      }
      if case .prepared = reply { documentError = nil; destinationStatus = "Preparation received from AdaptivePlotter. Review the preview before choosing Draw." }
    }
  }
  func installDocumentHandling(library: DrawingLibrary, acquisition: PortraitStudioModel,
    reveal: @escaping (DrawingRef) -> Void) {
    self.library = library; self.acquisition = acquisition; revealDrawing = reveal
    drainDrawingDocuments()
  }
  func application(_ sender: NSApplication, open urls: [URL]) {
    guard !terminating else { return }
    pendingDrawingDocuments += urls
    drainDrawingDocuments()
  }
  func settleDrawingDocuments() async { await drawingDocumentTask?.value }
  private func drainDrawingDocuments() {
    guard !terminating, drawingDocumentTask == nil,
      pendingDrawingReveal != nil || !pendingDrawingDocuments.isEmpty,
      let library, let acquisition else { return }
    handoffs += 1
    drawingDocumentTask = Task {
      defer { finishHandoff(); drawingDocumentTask = nil }
      while !terminating && (pendingDrawingReveal != nil || !pendingDrawingDocuments.isEmpty) {
        do {
          let reference: DrawingRef
          if let pending = pendingDrawingReveal {
            reference = pending
          } else {
            let url = pendingDrawingDocuments.removeFirst()
            let refs = try await library.importDrawings(from: url)
            guard let imported = refs.first else { throw DrawingExchangeError.malformed("Drawing document has no Drawing") }
            reference = imported
            pendingDrawingReveal = reference
          }
          // Import is durable independently of whether this window still owns
          // presentation. Cold-load first, then adopt only while quit is open.
          guard !terminating else { break }
          if acquisition.sketches.selected?.reference != reference {
            let drawing = try await library.drawing(reference)
            guard !terminating else { break }
            try acquisition.sketches.selectLoaded(drawing)
          }
          guard !terminating else { break }
          documentError = nil
          destinationStatus = "Drawing opened in Library."
          guard let revealDrawing else { break }
          pendingDrawingReveal = nil
          revealDrawing(reference)
          restorePortfolioWindow?()
        } catch {
          pendingDrawingReveal = nil
          if !terminating { documentError = "Drawing could not be opened: " + error.localizedDescription }
        }
      }
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !terminating else { return .terminateLater }
    if authoring?.needsRecovery == true {
      restorePortfolioWindow?()
      let alert = NSAlert(); alert.messageText = "Portfolio autosave needs recovery"
      alert.informativeText = "Resolve the write error and use Recover autosave before closing. Pending edits remain in this window."
      alert.addButton(withTitle: "Return to portfolio"); alert.runModal()
      return .terminateCancel
    }
    terminating = true
    Task {
      if await authoring?.shutdown() == false {
        terminating = false
        await drawingDocumentTask?.value
        drainDrawingDocuments()
        presentRecoveredDestinationReplies()
        restorePortfolioWindow?()
        replyToTermination(sender, false)
        return
      }
      if handoffs > 0 { await withCheckedContinuation { handoffWaiters.append($0) } }
      await acquisition?.shutdown()
      await library?.closeLibrary()
      replyToTermination(sender, true)
    }
    return .terminateLater
  }
}
