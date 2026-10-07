import Foundation
import Observation
import PlotterModel

/// The only observable archive owner. Attempt history, saved drawings and
/// labels have explicit deletion; recent capture/cache budgets are unrelated.
@Observable @MainActor
final class PortraitSketchCollection {
  private(set) var archive = PortraitCandidateArchive()
  var selectedID: String?
  var entries: [PortraitRetainedCandidate] { archive.entries }
  var sourcePhotos: [PortraitPhoto] { archive.sourcePhotos ?? [] }
  var labels: [PortraitLabelRevision] { archive.labels }
  var tombstones: [PortraitArchiveTombstone] { archive.tombstones }
  var sketches: [SavedDrawing] { PortraitCandidateStore.savedDrawings(in: archive) }
  var attempts: [PortraitRetainedCandidate] { entries.filter { $0.attempt != nil }.reversed() }
  var savedStyles: [PortraitSavedStyle] { archive.savedStyles ?? [] }
  var rejectedProposalIdentities: Set<String> {
    var latest: [String: PortraitAttemptFeedbackRevision] = [:]
    for entry in entries {
      guard let attempt = entry.attempt, let revision = attempt.feedbackRevisions.last else { continue }
      if let prior = latest[attempt.proposalIdentity], prior.createdAt > revision.createdAt { continue }
      latest[attempt.proposalIdentity] = revision
    }
    return Set(latest.filter { $0.value.value == .rejected }.map(\.key))
  }
  var selected: SavedDrawing? {
    guard let selectedID else { return nil }
    let drawing = sketches.first { $0.id == selectedID } ?? selectedDrawings[selectedID]
    guard let drawing, !drawingWasDeleted(drawing) else { return nil }
    return drawing
  }
  private(set) var drawingSummaries: [SavedDrawingSummary] = []
  private(set) var drawingBrowserState: PortraitPersistenceState = .loading
  private(set) var drawingHasMore = false
  private(set) var drawingPageRevision: UInt64 = 0
  @ObservationIgnored private var drawingBrowserPhotoID: UUID?
  @ObservationIgnored private var drawingBrowserStyle: PortraitStyle?
  @ObservationIgnored private var drawingCursor: SavedDrawingPageCursor?
  @ObservationIgnored private var drawingPageTask: Task<Void, Never>?
  @ObservationIgnored private var drawingBrowserHasLoaded = false
  @ObservationIgnored private var selectedDrawings: [String: SavedDrawing] = [:]
  private(set) var savedStylesState: PortraitPersistenceState = .saved
  private(set) var persistenceState: PortraitPersistenceState = .saved
  private(set) var retainedBytes = 0
  private(set) var unresolvedMutations = 0
  private(set) var persistenceIssues: [String] = []
  private(set) var photoReferences: [PortraitPhotoReference] = []
  private(set) var photoBrowserState: PortraitPersistenceState = .loading
  private(set) var photoHasMore = false
  private(set) var photoPageRevision: UInt64 = 0
  private(set) var historyLoadHasCompleted: Bool
  @ObservationIgnored private var photoCursor: PortraitPhotoPageCursor?
  @ObservationIgnored private var photoPageTask: Task<Void, Never>?
  @ObservationIgnored private var photoBrowserHasLoaded = false
  @ObservationIgnored private var deletedBrowseSources: [String: Date] = [:]
  @ObservationIgnored private let store: PortraitCandidateStore?
  @ObservationIgnored private var pending: [Mutation] = []
  @ObservationIgnored private var worker: Task<Void, Never>?
  @ObservationIgnored private var pendingCleanupBytes = 0
  @ObservationIgnored private var pendingCleanupCount = 0
  @ObservationIgnored private var hasLoaded: Bool

  init(store: PortraitCandidateStore? = nil) {
    self.store = store
    hasLoaded = store == nil
    historyLoadHasCompleted = store == nil
    if store != nil { persistenceState = .loading; savedStylesState = .loading }
  }

  func load() async {
    startWorker()
    await worker?.value
  }

  /// The one explicit Save path, shared by manual Save and Drawing handoff.
  func saveDrawing(_ drawing: SavedDrawing) async -> String? {
    guard !Task.isCancelled, !drawingWasDeleted(drawing) else { return SavedDrawingBrowserError.drawingUnavailable.localizedDescription }
    do { try drawing.validateIntegrity() } catch { return error.localizedDescription }
    if !sketches.contains(where: { $0.id == drawing.id }) { enqueue(.saveDrawing(drawing)) }
    else { startWorker() }
    await awaitPersistence()
    guard !Task.isCancelled, !drawingWasDeleted(drawing), sketches.contains(where: { $0.id == drawing.id }) else {
      return SavedDrawingBrowserError.drawingUnavailable.localizedDescription
    }
    guard persistenceState == .saved, unresolvedMutations == 0 else {
      if case .failed(let error) = persistenceState { return error }
      return "The drawing has not finished saving. Retry Save Drawing."
    }
    return nil
  }

  func drawingWasDeleted(_ drawing: SavedDrawing) -> Bool {
    summaryWasDeleted(SavedDrawingSummary(drawing))
  }

  private func summaryWasDeleted(_ drawing: SavedDrawingSummary) -> Bool {
    if let source = drawing.sourceSHA256,
      let date = deletedBrowseSources[source], drawing.createdAt <= date { return true }
    return tombstones.contains { $0.kind != .label && drawing.createdAt <= $0.createdAt
      && ($0.affectedCandidateIDs.contains(drawing.id) || ($0.kind == .source && $0.identity == drawing.sourceSHA256)) }
  }

  func loadDrawingBrowser(photoID: UUID? = nil, style: PortraitStyle? = nil) async {
    if let drawingPageTask { await drawingPageTask.value }
    if photoID != drawingBrowserPhotoID || style != drawingBrowserStyle {
      drawingBrowserPhotoID = photoID; drawingBrowserStyle = style
      drawingCursor = nil; drawingSummaries = []; drawingHasMore = false; drawingBrowserHasLoaded = false
    }
    guard !drawingBrowserHasLoaded else { return }
    await loadMoreDrawings()
  }

  func loadMoreDrawings() async {
    if let drawingPageTask { await drawingPageTask.value; return }
    guard !drawingBrowserHasLoaded || drawingHasMore else { return }
    drawingPageTask = Task {
      defer { drawingPageTask = nil }
      drawingBrowserState = .loading
      do {
        if let store {
          let cursor = drawingCursor, photoID = drawingBrowserPhotoID, style = drawingBrowserStyle
          let readPage: @Sendable (SavedDrawingPageCursor?) throws -> SavedDrawingPage = { initial in
            var cursor = initial
            while true {
              try Task.checkCancellation()
              let page = try store.loadDrawingPage(after: cursor, photoID: photoID, style: style)
              // Legacy v3 has no photo/style drawing catalog. Advance empty
              // bounded metadata batches so old-photo history opens usefully.
              guard page.drawings.isEmpty, page.next != nil, photoID != nil || style != nil else { return page }
              cursor = page.next
            }
          }
          let reader = Task.detached(priority: .utility) { try readPage(cursor) }
          let page: SavedDrawingPage
          do { page = try await reader.value }
          catch SavedDrawingBrowserError.archiveChanged {
            page = try await Task.detached(priority: .utility) { try readPage(nil) }.value
            drawingSummaries = []
          }
          var seen = Set(drawingSummaries.map(\.id))
          drawingSummaries += page.drawings.filter { !summaryWasDeleted($0) && seen.insert($0.id).inserted }
          drawingCursor = page.next; drawingHasMore = page.next != nil
        } else {
          refreshDrawingSummaries()
          drawingHasMore = false
        }
        drawingBrowserHasLoaded = true; drawingBrowserState = .saved
        drawingPageRevision &+= 1
      } catch { drawingBrowserState = .failed(error.localizedDescription) }
    }
    await drawingPageTask?.value
  }

  func drawingForBrowsing(_ id: String) async throws -> SavedDrawing {
    if let drawing = sketches.first(where: { $0.id == id }), !drawingWasDeleted(drawing) { return drawing }
    if let candidate = entries.first(where: { $0.id == id })?.candidate {
      let drawing = SavedDrawing(candidate: candidate)
      guard !drawingWasDeleted(drawing) else { throw SavedDrawingBrowserError.drawingUnavailable }
      return drawing
    }
    guard let store else { throw SavedDrawingBrowserError.drawingUnavailable }
    let reader = Task.detached(priority: .utility) {
      do { return try store.loadDrawing(id) }
      catch SavedDrawingBrowserError.archiveChanged { try Task.checkCancellation(); return try store.loadDrawing(id) }
    }
    let drawing = try await withTaskCancellationHandler { try await reader.value } onCancel: { reader.cancel() }
    guard !Task.isCancelled, !drawingWasDeleted(drawing) else { throw SavedDrawingBrowserError.drawingUnavailable }
    selectedDrawings[id] = drawing
    if selectedDrawings.count > 8 {
      selectedDrawings = selectedDrawings.filter { $0.key == id || $0.key == selectedID }
    }
    return drawing
  }

  func matchingCandidateForBrowsing(photoID: UUID, configuration: PortraitRenderConfiguration,
    strokeStyle: StrokeStyle) async throws -> PortraitCandidate? {
    if let candidate = entries.reversed().first(where: {
      $0.candidate.photoID == photoID && $0.candidate.recipe.style == configuration.style
        && $0.candidate.recipe.vectorOptions.bounded == configuration.vectors.bounded
        && $0.candidate.recipe.analysisOptions == configuration.analysis
        && $0.candidate.program.strokes.first?.style == strokeStyle
    })?.candidate { return candidate }
    guard let store else { return nil }
    let reader = Task.detached(priority: .utility) {
      var cursor: SavedDrawingPageCursor?
      repeat {
        try Task.checkCancellation()
        let page = try store.loadDrawingPage(after: cursor, photoID: photoID, style: configuration.style)
        if let summary = page.drawings.first(where: {
          $0.recipe?.vectorOptions.bounded == configuration.vectors.bounded
            && $0.recipe?.analysisOptions == configuration.analysis && $0.strokeStyle == strokeStyle
        }) { return try store.loadDrawing(summary.id).portraitCandidate }
        cursor = page.next
      } while cursor != nil
      return nil
    }
    let candidate = try await withTaskCancellationHandler { try await reader.value } onCancel: { reader.cancel() }
    try Task.checkCancellation()
    if let candidate, !drawingWasDeleted(SavedDrawing(candidate: candidate)) { return candidate }
    return nil
  }

  func candidateForBrowsing(_ id: String) async throws -> PortraitCandidate {
    guard let candidate = try await drawingForBrowsing(id).portraitCandidate else { throw SavedDrawingBrowserError.notPortrait }
    return candidate
  }

  private func refreshDrawingSummaries(including changedID: String? = nil) {
    // The canonical owner may have fully verified a large archive for writing.
    // Publishing a mutation must not silently expand a bounded browser page.
    var visibleIDs = Set(drawingSummaries.map(\.id))
    if let changedID { visibleIDs.insert(changedID) }
    let savedIDs = Set((archive.savedDrawings ?? []).map(\.id))
      .union(entries.filter { !$0.reasons.isEmpty }.map(\.id))
    let known = entries.filter { store == nil || visibleIDs.contains($0.id) }.map {
      SavedDrawingSummary(SavedDrawing(candidate: $0.candidate),
        isSaved: savedIDs.contains($0.id), feedback: $0.attempt?.feedback)
    } + (archive.savedDrawings ?? []).filter {
      $0.portraitCandidate == nil && (store == nil || visibleIDs.contains($0.id))
    }.map { SavedDrawingSummary($0) }
    let byID = Dictionary(uniqueKeysWithValues: known.map { ($0.id, $0) })
    drawingSummaries = (drawingSummaries.filter { byID[$0.id] == nil && !summaryWasDeleted($0) } + known).filter {
      (drawingBrowserPhotoID == nil || $0.photoID == drawingBrowserPhotoID)
        && (drawingBrowserStyle == nil || $0.style == drawingBrowserStyle)
    }
    drawingSummaries.sort { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt }
    drawingPageRevision &+= 1
  }

  func loadPhotoBrowser() async {
    guard !photoBrowserHasLoaded else { return }
    await loadMorePhotos()
  }

  func loadMorePhotos() async {
    if let photoPageTask { await photoPageTask.value; return }
    guard !photoBrowserHasLoaded || photoHasMore else { return }
    photoPageTask = Task {
      defer { photoPageTask = nil }
      photoBrowserState = .loading
      do {
        if let store {
          let cursor = photoCursor
          let reader = Task.detached(priority: .utility) { try store.loadPhotoPage(after: cursor) }
          let page: PortraitPhotoPage
          do { page = try await reader.value }
          catch PortraitPhotoBrowserError.archiveChanged {
            // A canonical save replaced the index. Restart its advisory cursor;
            // the full archive and pending mutations are never replaced here.
            page = try await Task.detached(priority: .utility) { try store.loadPhotoPage() }.value
            photoReferences = []
          }
          var seen = Set(photoReferences.map(\.id))
          photoReferences += page.photos.filter {
            !browseSourceWasDeleted($0) && seen.insert($0.id).inserted
          }
          photoCursor = page.next
          photoHasMore = page.next != nil
          // Recipes are an independent cheap catalog, not a partial archive.
          if !historyLoadHasCompleted {
            archive.savedStyles = page.savedStyles
            for mutation in pending { mutation.apply(to: &archive) }
            savedStylesState = .saved
          }
        } else {
          var seen = Set<UUID>()
          var references = sourcePhotos.map { PortraitPhotoReference($0) }
          seen.formUnion(references.map(\.id))
          references += entries.reversed().compactMap { entry in
            guard entry.candidate.renderPose != nil, seen.insert(entry.candidate.photoID).inserted else { return nil }
            return PortraitPhotoReference(candidate: entry.candidate, recordSHA256: nil)
          }
          references.sort { $0.capturedAt > $1.capturedAt }
          let end = min(references.count, photoReferences.count + 100)
          photoReferences = Array(references.prefix(end))
          photoHasMore = end < references.count
        }
        photoBrowserHasLoaded = true
        photoBrowserState = .saved
        photoPageRevision &+= 1
      } catch {
        photoBrowserState = .failed(error.localizedDescription)
        if !historyLoadHasCompleted { savedStylesState = .failed(error.localizedDescription) }
      }
    }
    await photoPageTask?.value
  }

  func photoForBrowsing(_ id: UUID) async throws -> PortraitPhoto {
    // A freshly queued source may not yet appear in the committed index.
    if let photo = sourcePhotos.first(where: { $0.id == id }) { return photo }
    if let candidate = entries.last(where: { $0.candidate.photoID == id })?.candidate,
      candidate.renderPose != nil {
      return try PortraitPhotoReference(candidate: candidate, recordSHA256: nil)
        .materialize(source: candidate.sourceData)
    }
    guard let reference = photoReferences.first(where: { $0.id == id }),
      !browseSourceWasDeleted(reference), let store else {
      throw PortraitPhotoBrowserError.sourceUnavailable
    }
    let reader = Task.detached(priority: .utility) {
      do { return try store.loadPhoto(reference) }
      catch PortraitPhotoBrowserError.archiveChanged {
        try Task.checkCancellation()
        return try store.loadPhoto(reference)
      }
    }
    let photo = try await withTaskCancellationHandler { try await reader.value } onCancel: { reader.cancel() }
    guard !Task.isCancelled, !browseSourceWasDeleted(reference),
      photoReferences.contains(where: { $0.id == reference.id && $0.sourceSHA256 == reference.sourceSHA256 }) else {
      throw PortraitPhotoBrowserError.sourceUnavailable
    }
    return photo
  }

  private func browseSourceWasDeleted(_ reference: PortraitPhotoReference) -> Bool {
    deletedBrowseSources[reference.sourceSHA256].map { reference.capturedAt <= $0 } ?? false
  }

  func retainSourcePhoto(_ photo: PortraitPhoto) {
    let reference = PortraitPhotoReference(photo)
    if !browseSourceWasDeleted(reference), !photoReferences.contains(where: { $0.id == photo.id }) {
      photoReferences.insert(reference, at: 0)
    }
    enqueue(.sourcePhoto(photo))
  }

  @discardableResult
  func retain(candidate: PortraitCandidate, reason: PortraitRetentionReason) -> String? {
    guard !drawingWasDeleted(SavedDrawing(candidate: candidate)) else {
      return SavedDrawingBrowserError.drawingUnavailable.localizedDescription
    }
    do {
      try candidate.validateIntegrity()
      enqueue(.retain(candidate, .init(reason: reason)))
      selectedID = candidate.id
      return nil
    } catch { return error.localizedDescription }
  }

  /// Prepared and checked by the joined render worker. Storage verifies integrity
  /// again off the main actor; publishing history never changes selection.
  func recordAttempt(_ candidate: PortraitCandidate, record: PortraitAttemptRecord) {
    guard !archive.tombstones.contains(where: { $0.kind != .label && candidate.createdAt <= $0.createdAt
        && ($0.affectedCandidateIDs.contains(candidate.id)
          || ($0.kind == .source && $0.identity == candidate.sourceSHA256)) }),
      !entries.contains(where: { $0.id == candidate.id && $0.attempt != nil }) else { return }
    enqueue(.attempt(candidate, record))
  }

  func setFeedback(_ value: PortraitAttemptFeedback, for id: String) {
    guard entries.first(where: { $0.id == id })?.attempt != nil
      || drawingSummaries.first(where: { $0.id == id })?.feedback != nil else { return }
    enqueue(.feedback(id, .init(id: UUID(), value: value, createdAt: Date())))
  }

  func clearUnkeptHistory(preserving id: String? = nil) {
    for entry in attempts where entry.id != id && entry.reasons.isEmpty && entry.attempt?.feedback != .promising {
      remove(entry.id)
    }
  }

  func saveStyle(name: String, recipe: PortraitStyleRecipe) {
    let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return }
    enqueue(.style(.init(id: UUID(), name: title, recipe: recipe, createdAt: Date())))
  }

  func removeStyle(_ id: UUID) { enqueue(.removeStyle(id)) }

  @discardableResult
  func rate(candidate: PortraitCandidate, rating: Int, scope: PortraitStyleScope,
    presentation: PortraitPresentationContext) -> String? {
    guard !drawingWasDeleted(SavedDrawing(candidate: candidate)) else {
      return SavedDrawingBrowserError.drawingUnavailable.localizedDescription
    }
    do {
      try candidate.validateIntegrity()
      let previous = labels.last { $0.candidateID == candidate.id && $0.scope.id == scope.id
        && $0.presentation.physicalAttemptID == presentation.physicalAttemptID
        && !archive.withdrawnLabelIDs.contains($0.id.uuidString) }
      let label = try PortraitLabelRevision(candidate: candidate, rating: rating, scope: scope,
        presentation: presentation, previousRevisionID: previous?.id)
      try PortraitArchiveValidation.label(label, candidate: candidate)
      enqueue(.rate(candidate, label, .init(reason: .rated(labelRevisionID: label.id))))
      return nil
    } catch { return error.localizedDescription }
  }

  func remove(_ id: String) {
    let candidate = entries.first(where: { $0.id == id })?.candidate
    guard candidate != nil || sketches.contains(where: { $0.id == id })
      || drawingSummaries.contains(where: { $0.id == id }) else { return }
    enqueue(.delete(.init(id: UUID(), kind: .candidate, identity: id,
      affectedCandidateIDs: [id], assetSHA256s: candidate.map { [$0.sourceSHA256, $0.rasterSHA256] } ?? [], createdAt: Date())))
    selectedDrawings[id] = nil
    drawingSummaries.removeAll { $0.id == id }
    if selectedID == id { selectedID = nil }
  }

  func deleteSource(_ sourceSHA256: String) {
    let affected = entries.filter { $0.candidate.sourceSHA256 == sourceSHA256 }
    guard !affected.isEmpty || sourcePhotos.contains(where: {
      PortraitCandidateCoding.digest($0.data) == sourceSHA256
    }) || photoReferences.contains(where: { $0.sourceSHA256 == sourceSHA256 }) else { return }
    deletedBrowseSources[sourceSHA256] = Date()
    photoReferences.removeAll { $0.sourceSHA256 == sourceSHA256 }
    enqueue(.delete(.init(id: UUID(), kind: .source, identity: sourceSHA256,
      affectedCandidateIDs: affected.map(\.id),
      assetSHA256s: [sourceSHA256] + affected.map { $0.candidate.rasterSHA256 }, createdAt: Date())))
    if let selectedID, affected.contains(where: { $0.id == selectedID }) { self.selectedID = nil }
  }

  func withdrawLabel(_ id: UUID) {
    guard let label = labels.first(where: { $0.id == id }),
      !archive.withdrawnLabelIDs.contains(id.uuidString) else { return }
    enqueue(.delete(.init(id: UUID(), kind: .label, identity: id.uuidString,
      affectedCandidateIDs: [label.candidateID], assetSHA256s: [], createdAt: Date())))
  }

  func retryPersistence() {
    guard worker == nil else { return }
    // Reload before retry so repaired assets/index are verified and retained
    // disk records are merged before replaying the still-pending mutations.
    if store != nil { hasLoaded = false }
    startWorker()
  }

  func awaitPersistence() async {
    await worker?.value
  }

  private enum Mutation {
    case saveDrawing(SavedDrawing)
    case retain(PortraitCandidate, PortraitRetentionEvent)
    case rate(PortraitCandidate, PortraitLabelRevision, PortraitRetentionEvent)
    case delete(PortraitArchiveTombstone)
    case attempt(PortraitCandidate, PortraitAttemptRecord)
    case feedback(String, PortraitAttemptFeedbackRevision)
    case style(PortraitSavedStyle)
    case removeStyle(UUID)
    case sourcePhoto(PortraitPhoto)

    var drawingID: String? {
      switch self {
      case .saveDrawing(let drawing): drawing.id
      case .retain(let candidate, _), .rate(let candidate, _, _), .attempt(let candidate, _): candidate.id
      case .feedback(let id, _): id
      default: nil
      }
    }

    func apply(to archive: inout PortraitCandidateArchive) {
      switch self {
      case .saveDrawing(let drawing):
        guard !archive.tombstones.contains(where: { $0.kind != .label && drawing.createdAt <= $0.createdAt
          && ($0.affectedCandidateIDs.contains(drawing.id)
            || ($0.kind == .source && $0.identity == drawing.portraitCandidate?.sourceSHA256)) }) else { return }
        if let candidate = drawing.portraitCandidate { Self.retain(candidate, event: .init(reason: .shortlisted), in: &archive) }
        if archive.savedDrawings == nil { archive.savedDrawings = [] }
        if archive.savedDrawings?.contains(where: { $0.id == drawing.id }) == false { archive.savedDrawings?.append(drawing) }

      case .sourcePhoto(let photo):
        let hash = PortraitCandidateCoding.digest(photo.data)
        guard !archive.tombstones.contains(where: {
          $0.kind == .source && $0.identity == hash && photo.capturedAt <= $0.createdAt
        }) else { return }
        if archive.sourcePhotos == nil { archive.sourcePhotos = [] }
        if archive.sourcePhotos?.contains(where: { $0.id == photo.id }) == false {
          archive.sourcePhotos?.append(photo)
        }
      case .attempt(let candidate, let record):
        guard !archive.tombstones.contains(where: { $0.kind != .label && candidate.createdAt <= $0.createdAt
        && ($0.affectedCandidateIDs.contains(candidate.id)
          || ($0.kind == .source && $0.identity == candidate.sourceSHA256)) }) else { return }
        if let index = archive.entries.firstIndex(where: { $0.id == candidate.id }) {
          if archive.entries[index].attempt == nil { archive.entries[index].attempt = record }
        } else { archive.entries.append(.init(candidate: candidate, reasons: [], attempt: record)) }
      case .feedback(let id, let revision):
        if let index = archive.entries.firstIndex(where: { $0.id == id }),
          archive.entries[index].attempt?.feedbackRevisions.contains(where: { $0.id == revision.id }) == false {
          archive.entries[index].attempt?.feedbackRevisions.append(revision)
        }
      case .style(let style):
        if archive.savedStyles == nil { archive.savedStyles = [] }
        if archive.savedStyles?.contains(where: { $0.id == style.id }) == false { archive.savedStyles?.append(style) }
      case .removeStyle(let id): archive.savedStyles?.removeAll { $0.id == id }
      case .retain(let candidate, let event):
        Self.retain(candidate, event: event, in: &archive)
      case .rate(let candidate, let label, let event):
        guard !archive.tombstones.contains(where: { $0.kind != .label && candidate.createdAt <= $0.createdAt
          && ($0.affectedCandidateIDs.contains(candidate.id)
            || ($0.kind == .source && $0.identity == candidate.sourceSHA256)) }) else { return }
        Self.retain(candidate, event: event, in: &archive)
        if !archive.labels.contains(where: { $0.id == label.id }) { archive.labels.append(label) }
      case .delete(let requested):
        let affected = archive.entries.filter { requested.affectedCandidateIDs.contains($0.id)
          || (requested.kind == .source && $0.candidate.sourceSHA256 == requested.identity) }
        let tombstone = PortraitArchiveTombstone(id: requested.id, kind: requested.kind,
          identity: requested.identity,
          affectedCandidateIDs: Array(Set(requested.affectedCandidateIDs + affected.map(\.id))).sorted(),
          assetSHA256s: requested.kind == .label ? [] : Array(Set(requested.assetSHA256s
            + affected.flatMap { [$0.candidate.sourceSHA256, $0.candidate.rasterSHA256] })).sorted(),
          createdAt: requested.createdAt)
        if let index = archive.tombstones.firstIndex(where: { $0.id == tombstone.id }) {
          archive.tombstones[index] = tombstone
        } else { archive.tombstones.append(tombstone) }
        if tombstone.kind != .label {
          archive.entries.removeAll { tombstone.affectedCandidateIDs.contains($0.id) }
          archive.savedDrawings?.removeAll { tombstone.affectedCandidateIDs.contains($0.id)
            || (tombstone.kind == .source && $0.portraitCandidate?.sourceSHA256 == tombstone.identity) }
        }
        if tombstone.kind == .source {
          archive.sourcePhotos?.removeAll {
            PortraitCandidateCoding.digest($0.data) == tombstone.identity
          }
        }
      }
    }

    private static func retain(_ candidate: PortraitCandidate, event: PortraitRetentionEvent,
      in archive: inout PortraitCandidateArchive) {
      guard !archive.tombstones.contains(where: { $0.kind != .label && candidate.createdAt <= $0.createdAt
        && ($0.affectedCandidateIDs.contains(candidate.id)
          || ($0.kind == .source && $0.identity == candidate.sourceSHA256)) }) else { return }
      if archive.savedDrawings == nil { archive.savedDrawings = [] }
      if archive.savedDrawings?.contains(where: { $0.id == candidate.id }) == false {
        archive.savedDrawings?.append(SavedDrawing(candidate: candidate))
      }
      if let index = archive.entries.firstIndex(where: { $0.id == candidate.id }) {
        if !archive.entries[index].reasons.contains(where: { $0.reason == event.reason }) {
          archive.entries[index].reasons.append(event)
        }
      } else { archive.entries.append(.init(candidate: candidate, reasons: [event])) }
    }
  }

  private func enqueue(_ mutation: Mutation) {
    mutation.apply(to: &archive)
    refreshDrawingSummaries(including: mutation.drawingID)
    pending.append(mutation)
    unresolvedMutations = pending.count + pendingCleanupCount
    persistenceState = .pending
    startWorker()
  }

  private func startWorker() {
    guard worker == nil else { return }
    worker = Task { await drain() }
  }

  private func drain() async {
    defer { worker = nil }
    if !hasLoaded, let store {
      persistenceState = .loading
      savedStylesState = .loading
      do {
        let styles = try await store.loadSavedStyles()
        archive.savedStyles = styles
        for mutation in pending { mutation.apply(to: &archive) }
        savedStylesState = .saved
      } catch { savedStylesState = .failed(error.localizedDescription) }
      let loaded = await store.load()
      historyLoadHasCompleted = true
      persistenceIssues = loaded.issues
      pendingCleanupCount = loaded.pendingCleanupCount
      pendingCleanupBytes = loaded.pendingCleanupBytes
      unresolvedMutations = pending.count + pendingCleanupCount
      if loaded.canWrite {
        archive = loaded.archive
        for mutation in pending { mutation.apply(to: &archive) }
        hasLoaded = true
        if let bytes = loaded.retainedBytes { retainedBytes = bytes }
        else { await updateRetainedBytes() }
      } else {
        // Healthy recovered records remain accessible without discarding any
        // new authoring candidate or failed mutation already held in memory.
        var recovered = loaded.archive
        for photo in sourcePhotos where recovered.sourcePhotos?.contains(where: { $0.id == photo.id }) != true {
          if recovered.sourcePhotos == nil { recovered.sourcePhotos = [] }
          recovered.sourcePhotos?.append(photo)
        }
        for entry in archive.entries where !recovered.entries.contains(where: { $0.id == entry.id }) {
          recovered.entries.append(entry)
        }
        for drawing in archive.savedDrawings ?? [] where recovered.savedDrawings?.contains(where: { $0.id == drawing.id }) != true {
          if recovered.savedDrawings == nil { recovered.savedDrawings = [] }
          recovered.savedDrawings?.append(drawing)
        }
        for label in archive.labels where !recovered.labels.contains(where: { $0.id == label.id }) {
          recovered.labels.append(label)
        }
        for tombstone in archive.tombstones where !recovered.tombstones.contains(where: { $0.id == tombstone.id }) {
          recovered.tombstones.append(tombstone)
        }
        for style in archive.savedStyles ?? [] where recovered.savedStyles?.contains(where: { $0.id == style.id }) != true {
          if recovered.savedStyles == nil { recovered.savedStyles = [] }
          recovered.savedStyles?.append(style)
        }
        for mutation in pending { mutation.apply(to: &recovered) }
        archive = recovered
        if let bytes = loaded.retainedBytes { retainedBytes = bytes }
        else { await updateRetainedBytes() }
        persistenceState = .failed(loaded.issues.joined(separator: " "))
        return
      }
    }
    while !pending.isEmpty {
      let snapshot = archive
      let mutationCount = pending.count
      persistenceState = .pending
      do {
        if let store {
          retainedBytes = try await store.save(snapshot: snapshot)
          savedStylesState = .saved
          // A successful save has also completed any previously pending cleanup.
          pendingCleanupCount = 0
          pendingCleanupBytes = 0
        } else {
          await updateRetainedBytes(snapshot: snapshot)
        }
        pending.removeFirst(mutationCount)
        unresolvedMutations = pending.count + pendingCleanupCount
      } catch {
        persistenceState = .failed(error.localizedDescription)
        return
      }
    }
    refreshDrawingSummaries()
    persistenceState = .saved
  }

  private func updateRetainedBytes(snapshot: PortraitCandidateArchive? = nil) async {
    let value = snapshot ?? archive
    if let bytes = try? await Task.detached(priority: .utility, operation: {
      try PortraitCandidateStore.retainedByteCount(snapshot: value)
    }).value {
      retainedBytes = bytes + pendingCleanupBytes
    }
  }
}
