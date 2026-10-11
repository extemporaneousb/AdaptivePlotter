import Foundation
import Observation
import PlotterRuntime
import PortraitArtists
import PortraitCore
import PortraitLibrary

extension SavedDrawingSummary {
  var studioRowID: String {
    photoID.map { PortraitDrawingIdentity(candidateID: id, photoID: $0).id } ?? id
  }
}

@Observable @MainActor
final class PortraitStudioLibraryModel {
  let sketches: PortraitSketchCollection
  private(set) var photos: [PortraitLibraryPhoto] = []
  private(set) var photoDrawings: [PortraitLibraryDrawing] = []
  private(set) var selectedPhotoID: UUID?
  private(set) var sourceData: Data?
  private(set) var drawing: SavedDrawing?
  private(set) var attachments: [PlotAttachmentSummary] = []
  private(set) var attachment: PlotAttachment?
  private(set) var record: DrawingRunEvidenceRecord?
  private(set) var isLoading = false
  var error: String?
  private var cursor: PortraitLibraryCursor?
  private var attachmentCursor: PlotAttachmentPageCursor?
  private var isClosing = false
  @ObservationIgnored private var operation: Task<Void, Never>?

  var hasMorePhotos: Bool { cursor != nil }
  var hasMoreAttachments: Bool { attachmentCursor != nil }
  var drawingAttachments: [PlotAttachmentSummary] {
    guard let drawing else { return [] }
    return attachments.filter {
      $0.linkedDrawingID == drawing.id && $0.linkedPhotoID == drawing.sourcePhotoID
    }
  }

  init(sketches: PortraitSketchCollection) { self.sketches = sketches }

  private func perform(_ body: @escaping @MainActor () async throws -> Void) async {
    guard !isClosing else { return }
    let previous = operation
    previous?.cancel()
    let next = Task {
      await previous?.value
      guard !Task.isCancelled else { return }
      isLoading = true
      error = nil
      defer { isLoading = false }
      do { try await body() }
      catch is CancellationError { }
      catch { self.error = error.localizedDescription }
    }
    operation = next
    await withTaskCancellationHandler { await next.value } onCancel: { next.cancel() }
  }

  func reload() async {
    await perform {
      let page = try await self.sketches.librarySnapshot(limit: 100)
      try Task.checkCancellation()
      self.photos = page.photos
      self.cursor = page.next
      await self.sketches.loadDrawingBrowser(photoID: nil)
      let attachments = try await self.sketches.plotAttachmentPage(limit: 100)
      try Task.checkCancellation()
      self.attachments = attachments.attachments
      self.attachmentCursor = attachments.next
    }
  }

  func loadMorePhotos() async {
    guard let cursor else { return }
    await perform {
      let page = try await self.sketches.librarySnapshot(after: cursor, limit: 100)
      try Task.checkCancellation()
      self.photos += page.photos
      self.cursor = page.next
    }
  }

  func loadMoreDrawings() async {
    await perform { await self.sketches.loadMoreDrawings() }
  }

  func loadMoreAttachments() async {
    guard let cursor = attachmentCursor else { return }
    await perform {
      let page = try await self.sketches.plotAttachmentPage(after: cursor, limit: 100)
      try Task.checkCancellation()
      self.attachments += page.attachments
      self.attachmentCursor = page.next
    }
  }

  func selectPhoto(_ id: UUID) async {
    await perform {
      let selection = try await self.sketches.librarySelection(photoID: id)
      let photo = try await self.sketches.photoForBrowsing(id)
      try Task.checkCancellation()
      self.selectedPhotoID = id
      self.sourceData = photo.data
      self.photoDrawings = selection.drawings
      self.drawing = nil; self.attachment = nil; self.record = nil
    }
  }

  func selectDrawing(_ id: String, identity: PortraitDrawingIdentity? = nil) async {
    await perform {
      let selected: SavedDrawing
      if let identity { selected = try await self.sketches.drawingForBrowsing(identity) }
      else { selected = try await self.sketches.drawingForBrowsing(id) }
      try Task.checkCancellation()
      self.drawing = selected
      self.sourceData = selected.sourceImageData
      self.selectedPhotoID = selected.sourcePhotoID
      self.attachment = nil; self.record = nil
    }
  }

  /// Summary IDs can be equal across captures. The native photo occurrence is
  /// part of the selection capability even when the drawing cache has that ID.
  func selectDrawing(_ summary: SavedDrawingSummary) async {
    let identity = summary.photoID.map {
      PortraitDrawingIdentity(candidateID: summary.id, photoID: $0)
    }
    await selectDrawing(summary.id, identity: identity)
  }

  func selectAttachment(_ id: String) async {
    await perform {
      let attachment = try await self.sketches.loadPlotAttachment(id)
      let record = try PortraitPlotAttachmentInspection.record(attachment)
      var drawing: SavedDrawing?
      if let summary = self.attachments.first(where: { $0.id == id }),
        let drawingID = summary.linkedDrawingID {
        if let photoID = summary.linkedPhotoID {
          drawing = try await self.sketches.drawingForBrowsing(
            PortraitDrawingIdentity(candidateID: drawingID, photoID: photoID))
        } else { drawing = try await self.sketches.drawingForBrowsing(drawingID) }
      }
      try Task.checkCancellation()
      self.drawing = drawing
      self.sourceData = drawing?.sourceImageData
      self.selectedPhotoID = drawing?.sourcePhotoID
      self.photoDrawings = []
      self.attachment = attachment; self.record = record
    }
  }

  func shutdown() async {
    isClosing = true
    operation?.cancel()
    await operation?.value
  }
}
