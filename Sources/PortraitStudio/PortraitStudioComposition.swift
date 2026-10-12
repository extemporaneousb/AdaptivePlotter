import Foundation
import Observation
import PlotterModel
import PlotterRuntime
import PortraitArtists
import PortraitCore
import PortraitLibrary
import PortraitStudioUI

@Observable @MainActor
final class PortraitStudioComposition {
  enum Workspace: String, CaseIterable, Hashable { case studio, library, artists, review }
  let model: PortraitStudioModel
  let browser: PortraitStudioLibraryModel
  let review: PortraitStudioReviewModel
  let artist: PortraitStudioArtistModel
  let strokeStyle: StrokeStyle
  var workspace: Workspace = .studio
  var showsLibrary: Bool {
    get { workspace == .library }
    set { workspace = newValue ? .library : .studio }
  }
  var message: String?
  private(set) var isBusy = false
  private(set) var isClosing = false
  private var startedDeviceID: CameraDeviceID?
  @ObservationIgnored private let files = PortraitStudioFiles()
  @ObservationIgnored private var startup: Task<Void, Never>?
  @ObservationIgnored private var action: Task<Void, Never>?
  @ObservationIgnored private var export: Task<String?, Never>?

  nonisolated static var privateLibraryURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/PortraitStudio/PortraitLibrary", isDirectory: true)
  }

  init(directoryURL: URL = PortraitStudioComposition.privateLibraryURL,
    camera: CameraCapture = CameraCapture(materializationPolicy:
      LiveFrameMaterializationPolicy(minimumPreviewIntervalNanoseconds: 33_333_333))) {
    let store = PortraitCandidateStore(directoryURL: directoryURL)
    let model = PortraitStudioModel(camera: camera, candidateStore: store)
    self.model = model
    browser = PortraitStudioLibraryModel(sketches: model.sketches)
    review = PortraitStudioReviewModel(store: store)
    artist = PortraitStudioArtistModel(studio: model, store: store)
    // A nominal authoring preview width; physical material qualification belongs
    // to the receiving plotter application.
    strokeStyle = try! StrokeStyle(nominalLineWidth: 0.4,
      penProfileID: PenProfileID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!))
  }

  func start() async {
    guard startup == nil, !isClosing else { return }
    let task = Task { await model.discover(excluding: nil) }
    startup = task
    await task.value
  }

  func selectCamera() async -> String? {
    guard !isClosing else { return "Portrait Studio is closing." }
    let requested = model.selectedDeviceID
    if !model.cameraIsRunning || startedDeviceID != requested {
      await model.startCamera()
      startedDeviceID = model.cameraIsRunning ? requested : nil
    }
    return model.cameraStatus
  }

  func exportDrawing(_ drawing: SavedDrawing) async -> String? {
    guard !isClosing, export == nil, action == nil else { return "Another file operation is in progress." }
    isBusy = true
    let task = Task { () -> String? in
      do {
        let data = try await model.sketches.exportDrawingPackage(drawing)
        try Task.checkCancellation()
        guard let url = await files.chooseExport(name: "Drawing.portraitdrawing.json") else { return nil }
        let write = Task.detached { try PortraitStudioFiles.write(data, to: url) }
        try await withTaskCancellationHandler { try await write.value } onCancel: { write.cancel() }
        return nil
      } catch is CancellationError { return nil }
      catch { return error.localizedDescription }
    }
    export = task
    let result = await task.value
    export = nil
    isBusy = false
    return result
  }

  func exportSelection() {
    guard let drawing = browser.drawing else { return }
    Task { message = await exportDrawing(drawing) }
  }

  func exportReviewDataset() {
    guard !isClosing, export == nil, action == nil, !review.isLoading else { return }
    isBusy = true
    let task = Task { () -> String? in
      do {
        guard let url = await files.chooseReviewDatasetExport() else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        try await review.exportDataset(to: url)
        return nil
      } catch is CancellationError { return nil }
      catch { return error.localizedDescription }
    }
    export = task
    Task {
      message = await task.value
      export = nil
      isBusy = false
    }
  }

  func importFile(attachment: Bool) {
    guard !isClosing, action == nil, export == nil else { return }
    isBusy = true
    action = Task {
      defer { action = nil; isBusy = false }
      do {
        guard let url = await files.chooseImport(title: attachment ? "Import Plot Attachment" : "Import Drawing") else { return }
        let maximum = attachment ? DrawingTransferLimits.attachmentJSONBytes : DrawingTransferLimits.drawingJSONBytes
        let read = Task.detached { try PortraitStudioFiles.read(url, maximumBytes: maximum) }
        let data = try await withTaskCancellationHandler { try await read.value } onCancel: { read.cancel() }
        try Task.checkCancellation()
        if attachment {
          let result = try await model.sketches.importPlotAttachment(data)
          message = result.linkedDrawingID == nil
            ? "Plot attachment retained. Import its exact originating drawing to link it."
            : "Plot attachment retained with its originating drawing."
          await browser.reload()
        } else {
          let drawing = try await model.sketches.importDrawingPackage(data, restoreDeleted: true)
          showsLibrary = true
          await browser.reload()
          await browser.selectDrawing(drawing.id)
        }
      } catch is CancellationError { }
      catch { message = error.localizedDescription }
    }
  }

  func editSelection() async {
    guard !isClosing, let candidate = browser.drawing?.portraitCandidate else { return }
    let identity = PortraitDrawingIdentity(candidateID: candidate.id, photoID: candidate.photoID)
    if let error = await model.inspectDrawing(identity, strokeStyle: strokeStyle) { message = error }
    else { showsLibrary = false }
  }

  func shutdown() async {
    guard !isClosing else { return }
    isClosing = true
    startup?.cancel(); action?.cancel(); export?.cancel()
    files.cancel()
    await startup?.value
    await action?.value
    _ = await export?.value
    await browser.shutdown()
    await review.shutdown()
    await artist.shutdown()
    await model.shutdown()
  }
}
