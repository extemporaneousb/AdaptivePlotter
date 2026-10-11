import PortraitArtists
import PortraitCore
import Foundation
import Observation
import PlotterModel
import PlotterRuntime

/// The only observable archive owner. Attempt history, saved drawings and
/// labels have explicit deletion; recent capture/cache budgets are unrelated.
@Observable @MainActor
package final class PortraitSketchCollection {
  package private(set) var archive = PortraitCandidateArchive()
  package var selectedID: String?
  package var entries: [PortraitRetainedCandidate] { archive.entries }
  package var sourcePhotos: [PortraitPhoto] { archive.sourcePhotos ?? [] }
  package var labels: [PortraitLabelRevision] { archive.labels }
  package var tombstones: [PortraitArchiveTombstone] { archive.tombstones }
  package var sketches: [SavedDrawing] { PortraitCandidateStore.savedDrawings(in: archive) }
  package var attempts: [PortraitRetainedCandidate] { entries.filter { $0.attempt != nil }.reversed() }
  package var savedStyles: [PortraitSavedStyle] { archive.savedStyles ?? [] }
  package var rejectedProposalIdentities: Set<String> {
    var latest: [String: PortraitAttemptFeedbackRevision] = [:]
    for entry in entries {
      guard let attempt = entry.attempt, let revision = attempt.feedbackRevisions.last else { continue }
      if let prior = latest[attempt.proposalIdentity], prior.createdAt > revision.createdAt { continue }
      latest[attempt.proposalIdentity] = revision
    }
    return Set(latest.filter { $0.value.value == .rejected }.map(\.key))
  }
  package var selected: SavedDrawing? {
    guard let selectedID else { return nil }
    let drawing = selectedDrawings[selectedID] ?? sketches.first { $0.id == selectedID }
    guard let drawing, !drawingWasDeleted(drawing) else { return nil }
    return drawing
  }
  package private(set) var drawingSummaries: [SavedDrawingSummary] = []
  package private(set) var drawingBrowserState: PortraitPersistenceState = .loading
  package private(set) var drawingHasMore = false
  package private(set) var drawingPageRevision: UInt64 = 0
  @ObservationIgnored private var drawingBrowserPhotoID: UUID?
  @ObservationIgnored private var drawingBrowserStyle: PortraitStyle?
  @ObservationIgnored private var drawingCursor: SavedDrawingPageCursor?
  @ObservationIgnored private var drawingPageTask: Task<Void, Never>?
  @ObservationIgnored private var drawingBrowserHasLoaded = false
  @ObservationIgnored private var selectedDrawings: [String: SavedDrawing] = [:]
  package private(set) var savedStylesState: PortraitPersistenceState = .saved
  package private(set) var persistenceState: PortraitPersistenceState = .saved
  package private(set) var retainedBytes = 0
  package private(set) var unresolvedMutations = 0
  package private(set) var persistenceIssues: [String] = []
  package private(set) var photoReferences: [PortraitPhotoReference] = []
  package private(set) var photoBrowserState: PortraitPersistenceState = .loading
  package private(set) var photoHasMore = false
  package private(set) var photoPageRevision: UInt64 = 0
  package private(set) var historyLoadHasCompleted: Bool
  package private(set) var libraryState: PortraitPersistenceState = .loading
  @ObservationIgnored private var librarySynchronizationRequired = false
  @ObservationIgnored private var librarySynchronizationFailure: String?
  @ObservationIgnored private var librarySynchronizationRevision: UInt64 = 0
  @ObservationIgnored private var pendingEvidenceProjection: (DrawingRunEvidenceArchive, URL)?
  @ObservationIgnored private var pendingEvidenceBindingRunID: RunID?
  @ObservationIgnored private var evidenceProjectionWorker: Task<Void, Never>?
  @ObservationIgnored private var photoCursor: PortraitPhotoPageCursor?
  @ObservationIgnored private var photoPageTask: Task<Void, Never>?
  @ObservationIgnored private var photoBrowserHasLoaded = false
  @ObservationIgnored private var deletedBrowseSources: [String: Date] = [:]
  @ObservationIgnored private var deletedBrowsePhotos: [UUID: Date] = [:]
  @ObservationIgnored private let store: PortraitCandidateStore?
  @ObservationIgnored private var pending: [Mutation] = []
  @ObservationIgnored private var worker: Task<Void, Never>?
  @ObservationIgnored private var pendingCleanupBytes = 0
  @ObservationIgnored private var pendingCleanupCount = 0
  @ObservationIgnored private var mutationStateHasLoaded: Bool
  @ObservationIgnored private var historyLoadRequested = false
  @ObservationIgnored private var historyLoadWasRequested = false
  @ObservationIgnored private var historyLoadInProgress = false
  @ObservationIgnored private var pendingHistoryClears: [PortraitDrawingIdentity?] = []

  package init(store: PortraitCandidateStore? = nil) {
    self.store = store
    mutationStateHasLoaded = store == nil
    historyLoadHasCompleted = store == nil
    if store != nil { persistenceState = .loading; savedStylesState = .loading }
  }

  package func load() async {
    historyLoadWasRequested = true
    if !historyLoadHasCompleted, !historyLoadInProgress { historyLoadRequested = true }
    startWorker()
    await worker?.value
  }

  /// Startup joins the current raw evidence generation before exposing catalog
  /// projections. A successful raw commit is never invalidated by this index.
  package func requireEvidenceSynchronization() {
    librarySynchronizationRevision &+= 1
    librarySynchronizationRequired = true
    libraryState = .loading
  }

  package func markLibraryUnavailable(_ detail: String) {
    librarySynchronizationRevision &+= 1
    pendingEvidenceProjection = nil
    pendingEvidenceBindingRunID = nil
    librarySynchronizationFailure = detail
    libraryState = .failed(detail)
  }

  package func reconcileDrawingEvidence(_ evidence: DrawingRunEvidenceArchive, sourceURL: URL) async {
    requireEvidenceSynchronization()
    let revision = librarySynchronizationRevision
    do {
      if let store { try await store.reconcileEvidence(archive: evidence, sourceURL: sourceURL) }
      guard revision == librarySynchronizationRevision, pendingEvidenceProjection == nil else { return }
      librarySynchronizationFailure = nil
      librarySynchronizationRequired = false
      libraryState = .saved
    } catch {
      guard revision == librarySynchronizationRevision, pendingEvidenceProjection == nil else { return }
      markLibraryUnavailable("Portrait library is stale: \(error.localizedDescription)")
    }
  }

  /// No raw archive is a valid startup state only when the storage owner proves
  /// that no earlier raw generation or downstream lineage has been selected.
  package func reconcileAbsentDrawingEvidence(sourceURL: URL) async {
    pendingEvidenceProjection = nil
    pendingEvidenceBindingRunID = nil
    requireEvidenceSynchronization()
    let revision = librarySynchronizationRevision
    do {
      if let store { try await store.reconcileAbsentEvidence(sourceURL: sourceURL) }
      guard revision == librarySynchronizationRevision, pendingEvidenceProjection == nil else { return }
      librarySynchronizationFailure = nil
      librarySynchronizationRequired = false
      libraryState = .saved
    } catch {
      guard revision == librarySynchronizationRevision, pendingEvidenceProjection == nil else { return }
      markLibraryUnavailable("Portrait library is stale: \(error.localizedDescription)")
    }
  }

  /// Raw publication marks browsing stale synchronously, then coalesces advisory
  /// projection work. Only the latest completed request may publish current.
  package func queueDrawingEvidenceReconciliation(_ evidence: DrawingRunEvidenceArchive, sourceURL: URL) {
    requireEvidenceSynchronization()
    pendingEvidenceProjection = (evidence, sourceURL)
    // A subsequent raw publication releases an abandoned stage event. A
    // recovered archive never creates a binding hold from its prepared history.
    pendingEvidenceBindingRunID = nil
    startEvidenceProjectionWorker()
  }

  package func deferDrawingEvidenceReconciliation(_ evidence: DrawingRunEvidenceArchive,
    sourceURL: URL, untilBinding runID: RunID) {
    requireEvidenceSynchronization()
    pendingEvidenceProjection = (evidence, sourceURL)
    pendingEvidenceBindingRunID = runID
  }

  package func finishDrawingEvidenceBinding(_ runID: RunID) {
    guard pendingEvidenceBindingRunID == runID else { return }
    pendingEvidenceBindingRunID = nil
    startEvidenceProjectionWorker()
  }

  private func startEvidenceProjectionWorker() {
    guard pendingEvidenceBindingRunID == nil else { return }
    guard evidenceProjectionWorker == nil else { return }
    evidenceProjectionWorker = Task {
      defer { evidenceProjectionWorker = nil }
      while pendingEvidenceBindingRunID == nil, let (archive, url) = pendingEvidenceProjection {
        pendingEvidenceProjection = nil
        await reconcileDrawingEvidence(archive, sourceURL: url)
      }
    }
  }

  package func awaitLibrarySynchronization() async {
    await evidenceProjectionWorker?.value
  }

  private func requireCurrentLibrary() throws {
    if let librarySynchronizationFailure {
      throw PortraitLibraryError.unresolvedLineage(librarySynchronizationFailure)
    }
    guard !librarySynchronizationRequired else { throw PortraitLibraryError.staleGeneration }
  }

  package func librarySnapshot(filter: PortraitLibraryFilter = .allPhotos,
    after: PortraitLibraryCursor? = nil, limit: Int = 100) async throws -> PortraitLibrarySnapshot {
    try requireCurrentLibrary()
    guard let store else {
      libraryState = .saved
      return .init(generation: .init(revision: 0, legacyPortraitSHA256: nil, evidenceSHA256: nil),
        photos: [], drawings: [], works: [], next: nil)
    }
    do {
      let snapshot = try await store.librarySnapshot(filter: filter, after: after, limit: limit)
      try requireCurrentLibrary()
      let references = snapshot.photos.map(\.reference) + snapshot.works.compactMap(\.sourcePhotoReference)
      guard references.allSatisfy({ !browseSourceWasDeleted($0) }) else {
        throw PortraitLibraryError.staleGeneration
      }
      publishLibraryPhotoReferences(references)
      libraryState = .saved
      return snapshot
    } catch {
      libraryState = .failed(error.localizedDescription)
      throw error
    }
  }

  package func librarySelection(photoID: UUID,
    drawingIdentity: PortraitDrawingIdentity? = nil) async throws -> PortraitLibrarySelection {
    try requireCurrentLibrary()
    guard let store else { throw PortraitLibraryError.missingPhoto }
    let selection = try await store.librarySelection(photoID: photoID, drawingIdentity: drawingIdentity)
    try requireCurrentLibrary()
    guard !browseSourceWasDeleted(selection.photo.reference) else { throw PortraitLibraryError.missingPhoto }
    publishLibraryPhotoReferences([selection.photo.reference])
    return selection
  }

  package func librarySelection(workID: String) async throws -> PortraitLibrarySelection {
    try requireCurrentLibrary()
    guard let store else { throw PortraitLibraryError.missingDrawing }
    let selection = try await store.librarySelection(workID: workID)
    try requireCurrentLibrary()
    guard !browseSourceWasDeleted(selection.photo.reference) else { throw PortraitLibraryError.missingPhoto }
    publishLibraryPhotoReferences([selection.photo.reference])
    return selection
  }

  package func librarySelection(drawingIdentity: PortraitDrawingIdentity) async throws -> PortraitLibrarySelection {
    try requireCurrentLibrary()
    guard let store else { throw PortraitLibraryError.missingDrawing }
    let selection = try await store.librarySelection(drawingIdentity: drawingIdentity)
    try requireCurrentLibrary()
    guard !browseSourceWasDeleted(selection.photo.reference),
      selection.selectedDrawing.map({ !summaryWasDeleted($0.summary) }) == true else {
      throw PortraitLibraryError.missingDrawing
    }
    publishLibraryPhotoReferences([selection.photo.reference])
    return selection
  }

  /// Register only service-admitted captures for the existing verified pixel
  /// reader. This is an advisory reference cache, never an archive mutation.
  private func publishLibraryPhotoReferences(_ references: [PortraitPhotoReference]) {
    for reference in references where !browseSourceWasDeleted(reference) {
      if let index = photoReferences.firstIndex(where: { $0.id == reference.id }) {
        photoReferences[index] = reference
      } else { photoReferences.append(reference) }
    }
  }

  /// The run occurrence commitment is ancestry only; DrawingEvidence retains
  /// all motion, possible-ink and no-redraw authority.
  package func bindPortraitAttempt(_ intent: DrawingRunIntent, candidate: PortraitCandidate,
    evidence: DrawingRunEvidenceArchive, sourceURL: URL) async throws {
    guard !drawingWasDeleted(SavedDrawing(candidate: candidate)) else {
      throw SavedDrawingBrowserError.drawingUnavailable
    }
    if let store {
      try await store.validateDurableCandidate(candidate)
      try await store.bindRunOccurrence(intent: intent, candidate: candidate, archive: evidence, sourceURL: sourceURL)
    }
    guard !Task.isCancelled, !drawingWasDeleted(SavedDrawing(candidate: candidate)) else {
      throw SavedDrawingBrowserError.drawingUnavailable
    }
  }

  /// The one explicit Save path, shared by manual Save and Drawing handoff.
  package func saveDrawing(_ requestedDrawing: SavedDrawing) async -> String? {
    // A source-free draft is content-addressed; repeated projection may supply a
    // new display date. Preserve the first retained occurrence of that program.
    let drawing: SavedDrawing
    if requestedDrawing.portraitCandidate == nil, requestedDrawing.transferredPackage == nil,
      let existing = sketches.first(where: { $0.id == requestedDrawing.id && $0.sourcePhotoID == nil }),
      existing.portraitCandidate == nil, existing.transferredPackage == nil,
      existing.program == requestedDrawing.program { drawing = existing }
    else { drawing = requestedDrawing }
    guard !Task.isCancelled, !drawingWasDeleted(drawing) else { return SavedDrawingBrowserError.drawingUnavailable.localizedDescription }
    do { try drawing.validateIntegrity() } catch { return error.localizedDescription }
    if drawing.transferredPackage != nil, let store {
      await awaitPersistence()
      guard !Task.isCancelled, !drawingWasDeleted(drawing) else { return SavedDrawingBrowserError.drawingUnavailable.localizedDescription }
      do {
        try await store.ensureRetainedTransferredDrawing(drawing)
        guard !Task.isCancelled, !drawingWasDeleted(drawing) else { return SavedDrawingBrowserError.drawingUnavailable.localizedDescription }
        cacheTransferredDrawing(drawing, restoreDeleted: false)
        return nil
      } catch { return error.localizedDescription }
    }
    if let existing = sketches.first(where: { $0.id == drawing.id && $0.sourcePhotoID == drawing.sourcePhotoID }),
      existing != drawing { return "The selected immutable drawing differs from its retained record." }
    if !sketches.contains(where: { $0.id == drawing.id && $0.sourcePhotoID == drawing.sourcePhotoID }) { enqueue(.saveDrawing(drawing)) }
    else { startWorker() }
    await awaitPersistence()
    guard !Task.isCancelled, !drawingWasDeleted(drawing), sketches.contains(where: { $0.id == drawing.id && $0.sourcePhotoID == drawing.sourcePhotoID }) else {
      return SavedDrawingBrowserError.drawingUnavailable.localizedDescription
    }
    guard persistenceState == .saved, unresolvedMutations == 0 else {
      if case .failed(let error) = persistenceState { return error }
      return "The drawing has not finished saving. Retry Save Drawing."
    }
    if let store {
      do { try await store.validateDurableDrawing(drawing) }
      catch { return error.localizedDescription }
      guard !Task.isCancelled, !drawingWasDeleted(drawing) else {
        return SavedDrawingBrowserError.drawingUnavailable.localizedDescription
      }
    }
    return nil
  }

  package func exportDrawingPackage(_ drawing: SavedDrawing) async throws -> Data {
    if let failure = await saveDrawing(drawing) { throw DrawingTransferError.unavailable(failure) }
    guard !Task.isCancelled, !drawingWasDeleted(drawing), let store else {
      throw DrawingTransferError.unavailable("The drawing has no available durable library.")
    }
    let bytes = try await store.exportDrawingPackage(drawing)
    guard !Task.isCancelled, !drawingWasDeleted(drawing) else { throw SavedDrawingBrowserError.drawingUnavailable }
    return bytes
  }

  package func importDrawingPackage(_ data: Data, restoreDeleted: Bool = false) async throws -> SavedDrawing {
    await awaitPersistence()
    try Task.checkCancellation()
    guard let store else { throw DrawingTransferError.unavailable("Drawing import requires a durable library.") }
    let drawing = try await store.importDrawingPackage(data, restoreDeleted: restoreDeleted)
    try Task.checkCancellation()
    cacheTransferredDrawing(drawing, restoreDeleted: restoreDeleted)
    selectedID = drawing.id
    return drawing
  }

  private func cacheTransferredDrawing(_ drawing: SavedDrawing, restoreDeleted: Bool) {
    if restoreDeleted {
      archive.tombstones.removeAll { PortraitCandidateStore.exactTransferredTombstone($0, id: drawing.id) }
    }
    if archive.savedDrawings == nil { archive.savedDrawings = [] }
    if let index = archive.savedDrawings?.firstIndex(where: { $0.id == drawing.id && $0.sourcePhotoID == drawing.sourcePhotoID }) {
      archive.savedDrawings?[index] = drawing
    } else { archive.savedDrawings?.append(drawing) }
    selectedDrawings[drawing.id] = drawing
    drawingCursor = nil; drawingBrowserHasLoaded = false; drawingSummaries = []; drawingHasMore = false
    persistenceState = .saved
  }

  package func validateDurableDrawing(_ drawing: SavedDrawing) async throws {
    guard !drawingWasDeleted(drawing), let store else { throw SavedDrawingBrowserError.drawingUnavailable }
    try await store.validateDurableDrawing(drawing)
    guard !Task.isCancelled, !drawingWasDeleted(drawing) else { throw SavedDrawingBrowserError.drawingUnavailable }
  }

  package func importPlotAttachment(_ data: Data) async throws -> PlotAttachmentImportResult {
    await awaitPersistence()
    try Task.checkCancellation()
    guard let store else { throw DrawingTransferError.unavailable("Plot attachment import requires a durable library.") }
    return try await store.importPlotAttachment(data)
  }

  package func plotAttachments(for origin: DrawingOriginReference? = nil) async throws -> [PlotAttachmentSummary] {
    guard let store else { return [] }
    return try await store.plotAttachments(for: origin)
  }

  package func plotAttachmentPage(after cursor: PlotAttachmentPageCursor? = nil, limit: Int = 100,
    for origin: DrawingOriginReference? = nil) async throws -> PlotAttachmentPage {
    guard let store else { return PlotAttachmentPage(attachments: [], next: nil) }
    return try await store.plotAttachmentPage(after: cursor, limit: limit, for: origin)
  }

  package func loadPlotAttachment(_ id: String) async throws -> PlotAttachment {
    guard let store else { throw DrawingTransferError.unavailable("Plot attachment is unavailable.") }
    return try await store.loadPlotAttachment(id)
  }

  package func drawingWasDeleted(_ drawing: SavedDrawing) -> Bool {
    summaryWasDeleted(SavedDrawingSummary(drawing))
  }

  private func summaryWasDeleted(_ drawing: SavedDrawingSummary) -> Bool {
    if let photoID = drawing.photoID, deletedBrowsePhotos[photoID] != nil { return true }
    if let source = drawing.sourceSHA256,
      let date = deletedBrowseSources[source], drawing.createdAt <= date { return true }
    return tombstones.contains { Self.affects($0, drawingID: drawing.id,
      photoID: drawing.photoID, sourceSHA256: drawing.sourceSHA256, createdAt: drawing.createdAt) }
  }

  private nonisolated static func affects(_ tombstone: PortraitArchiveTombstone,
    drawingID: String?, photoID: UUID?, sourceSHA256: String?, createdAt: Date) -> Bool {
    if tombstone.kind == .photo { return photoID == UUID(uuidString: tombstone.identity) }
    guard createdAt <= tombstone.createdAt else { return false }
    switch tombstone.kind {
    case .photo: return photoID == UUID(uuidString: tombstone.identity)
    case .source: return sourceSHA256 == tombstone.identity
      || drawingID.map { tombstone.affectedCandidateIDs.contains($0) } == true
    case .drawing:
      guard let drawingID, let photoID else { return false }
      return tombstone.identity == PortraitDrawingIdentity(candidateID: drawingID, photoID: photoID).id
    case .candidate: return drawingID.map { tombstone.affectedCandidateIDs.contains($0) || tombstone.identity == $0 } == true
    case .label: return false
    }
  }

  package func loadDrawingBrowser(photoID: UUID? = nil, style: PortraitStyle? = nil) async {
    if let drawingPageTask { await drawingPageTask.value }
    if photoID != drawingBrowserPhotoID || style != drawingBrowserStyle {
      drawingBrowserPhotoID = photoID; drawingBrowserStyle = style
      drawingCursor = nil; drawingSummaries = []; drawingHasMore = false; drawingBrowserHasLoaded = false
    }
    guard !drawingBrowserHasLoaded else { return }
    await loadMoreDrawings()
  }

  package func loadMoreDrawings() async {
    if let drawingPageTask { await drawingPageTask.value; return }
    guard !drawingBrowserHasLoaded || drawingHasMore else { return }
    drawingPageTask = Task {
      defer { drawingPageTask = nil }
      drawingBrowserState = .loading
      do {
        if let store {
          let cursor = drawingCursor, photoID = drawingBrowserPhotoID, style = drawingBrowserStyle
          let readPage: @Sendable (SavedDrawingPageCursor?) async throws -> SavedDrawingPage = { initial in
            var cursor = initial
            while true {
              try Task.checkCancellation()
              let page = try await store.loadDrawingPage(after: cursor, photoID: photoID, style: style)
              // Legacy v3 has no photo/style drawing catalog. Advance empty
              // bounded metadata batches so old-photo history opens usefully.
              guard page.drawings.isEmpty, page.next != nil, photoID != nil || style != nil else { return page }
              cursor = page.next
            }
          }
          let reader = Task.detached(priority: .utility) { try await readPage(cursor) }
          let page: SavedDrawingPage
          do { page = try await reader.value }
          catch SavedDrawingBrowserError.archiveChanged {
            page = try await Task.detached(priority: .utility) { try await readPage(nil) }.value
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

  package func drawingForBrowsing(_ id: String, photoID requestedPhotoID: UUID? = nil) async throws -> SavedDrawing {
    let photoID = requestedPhotoID ?? drawingBrowserPhotoID
    if let drawing = sketches.first(where: { $0.id == id && (photoID == nil || $0.sourcePhotoID == photoID) }),
      !drawingWasDeleted(drawing) { return drawing }
    if let candidate = entries.first(where: { $0.id == id && (photoID == nil || $0.candidate.photoID == photoID) })?.candidate {
      let drawing = SavedDrawing(candidate: candidate)
      guard !drawingWasDeleted(drawing) else { throw SavedDrawingBrowserError.drawingUnavailable }
      return drawing
    }
    guard let store else { throw SavedDrawingBrowserError.drawingUnavailable }
    let reader = Task.detached(priority: .utility) {
      if let photoID { return try await store.loadDrawing(PortraitDrawingIdentity(candidateID: id, photoID: photoID)) }
      return try await store.loadDrawing(id)
    }
    let drawing = try await withTaskCancellationHandler { try await reader.value } onCancel: { reader.cancel() }
    guard !Task.isCancelled, !drawingWasDeleted(drawing) else { throw SavedDrawingBrowserError.drawingUnavailable }
    selectedDrawings[id] = drawing
    if selectedDrawings.count > 8 {
      selectedDrawings = selectedDrawings.filter { $0.key == id || $0.key == selectedID }
    }
    return drawing
  }

  package func drawingForBrowsing(_ identity: PortraitDrawingIdentity) async throws -> SavedDrawing {
    try await drawingForBrowsing(identity.candidateID, photoID: identity.photoID)
  }

  package func matchingCandidateForBrowsing(photoID: UUID, configuration: PortraitRenderConfiguration,
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
        let page = try await store.loadDrawingPage(after: cursor, photoID: photoID, style: configuration.style)
        if let summary = page.drawings.first(where: {
          $0.recipe?.vectorOptions.bounded == configuration.vectors.bounded
            && $0.recipe?.analysisOptions == configuration.analysis && $0.strokeStyle == strokeStyle
        }) { return try await store.loadDrawing(PortraitDrawingIdentity(candidateID: summary.id, photoID: photoID)).portraitCandidate }
        cursor = page.next
      } while cursor != nil
      return nil
    }
    let candidate = try await withTaskCancellationHandler { try await reader.value } onCancel: { reader.cancel() }
    try Task.checkCancellation()
    if let candidate, !drawingWasDeleted(SavedDrawing(candidate: candidate)) { return candidate }
    return nil
  }

  package func candidateForBrowsing(_ id: String) async throws -> PortraitCandidate {
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

  package func loadPhotoBrowser() async {
    guard !photoBrowserHasLoaded else { return }
    await loadMorePhotos()
  }

  package func loadMorePhotos() async {
    if let photoPageTask { await photoPageTask.value; return }
    guard !photoBrowserHasLoaded || photoHasMore else { return }
    photoPageTask = Task {
      defer { photoPageTask = nil }
      photoBrowserState = .loading
      do {
        if let store {
          let cursor = photoCursor
          let reader = Task.detached(priority: .utility) { try await store.loadPhotoPage(after: cursor) }
          let page: PortraitPhotoPage
          do { page = try await reader.value }
          catch PortraitPhotoBrowserError.archiveChanged {
            // A canonical save replaced the index. Restart its advisory cursor;
            // the full archive and pending mutations are never replaced here.
            page = try await Task.detached(priority: .utility) { try await store.loadPhotoPage() }.value
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

  package func photoForBrowsing(_ id: UUID) async throws -> PortraitPhoto {
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
      do { return try await store.loadPhoto(reference) }
      catch PortraitPhotoBrowserError.archiveChanged {
        try Task.checkCancellation()
        return try await store.loadPhoto(reference)
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
    if deletedBrowsePhotos[reference.id] != nil { return true }
    if let date = deletedBrowseSources[reference.sourceSHA256], reference.capturedAt <= date { return true }
    return tombstones.contains { Self.affects($0, drawingID: nil, photoID: reference.id,
      sourceSHA256: reference.sourceSHA256, createdAt: reference.capturedAt) }
  }

  package func retainSourcePhoto(_ photo: PortraitPhoto) {
    let reference = PortraitPhotoReference(photo)
    if !browseSourceWasDeleted(reference), !photoReferences.contains(where: { $0.id == photo.id }) {
      photoReferences.insert(reference, at: 0)
    }
    enqueue(.sourcePhoto(photo))
  }

  @discardableResult
  package func retain(candidate: PortraitCandidate, reason: PortraitRetentionReason) -> String? {
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
  package func recordAttempt(_ candidate: PortraitCandidate, record: PortraitAttemptRecord) {
    guard !drawingWasDeleted(SavedDrawing(candidate: candidate)),
      !entries.contains(where: { $0.id == candidate.id && $0.candidate.photoID == candidate.photoID && $0.attempt != nil }) else { return }
    enqueue(.attempt(candidate, record))
  }

  package func feedback(for identity: PortraitDrawingIdentity) -> PortraitAttemptFeedback {
    entries.first { $0.id == identity.candidateID && $0.candidate.photoID == identity.photoID }?.attempt?.feedback
      ?? drawingSummaries.first { $0.id == identity.candidateID && $0.photoID == identity.photoID }?.feedback
      ?? .unknown
  }

  package func setFeedback(_ value: PortraitAttemptFeedback, for id: String) {
    if let entry = entries.first(where: { $0.id == id }), entry.attempt != nil {
      setFeedback(value, for: .init(candidateID: id, photoID: entry.candidate.photoID))
    } else if let summary = drawingSummaries.first(where: { $0.id == id && $0.feedback != nil }),
      let photoID = summary.photoID, !summaryWasDeleted(summary) {
      setFeedback(value, for: .init(candidateID: id, photoID: photoID))
    }
  }

  package func setFeedback(_ value: PortraitAttemptFeedback, for identity: PortraitDrawingIdentity) {
    let entry = entries.first { $0.id == identity.candidateID && $0.candidate.photoID == identity.photoID }
    if let entry {
      guard entry.attempt != nil, !drawingWasDeleted(SavedDrawing(candidate: entry.candidate)) else { return }
    } else if store == nil { return }
    enqueue(.feedback(identity, entry, .init(id: UUID(), value: value, createdAt: Date())))
  }

  package func clearUnkeptHistory(preserving id: String? = nil) {
    let identity = entries.first { $0.id == id }.map {
      PortraitDrawingIdentity(candidateID: $0.id, photoID: $0.candidate.photoID)
    } ?? drawingSummaries.first { $0.id == id }.flatMap { summary in
      summary.photoID.map { PortraitDrawingIdentity(candidateID: summary.id, photoID: $0) }
    }
    clearUnkeptHistory(preservingOccurrence: identity)
  }

  package func clearUnkeptHistory(preserving identity: PortraitDrawingIdentity) {
    clearUnkeptHistory(preservingOccurrence: identity)
  }

  private func clearUnkeptHistory(preservingOccurrence identity: PortraitDrawingIdentity?) {
    guard historyLoadHasCompleted else {
      pendingHistoryClears.append(identity)
      historyLoadWasRequested = true
      if !historyLoadInProgress { historyLoadRequested = true }
      unresolvedMutations = pending.count + pendingHistoryClears.count + pendingCleanupCount
      persistenceState = .pending
      startWorker()
      return
    }
    for entry in attempts where entry.reasons.isEmpty && entry.attempt?.feedback != .promising {
      let occurrence = PortraitDrawingIdentity(candidateID: entry.id, photoID: entry.candidate.photoID)
      if occurrence != identity { deleteDrawing(occurrence) }
    }
  }

  package func saveStyle(name: String, recipe: PortraitStyleRecipe) {
    let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return }
    enqueue(.style(.init(id: UUID(), name: title, recipe: recipe, createdAt: Date())))
  }

  package func removeStyle(_ id: UUID) { enqueue(.removeStyle(id)) }

  @discardableResult
  package func rate(candidate: PortraitCandidate, rating: Int, scope: PortraitStyleScope,
    presentation: PortraitPresentationContext) -> String? {
    guard !drawingWasDeleted(SavedDrawing(candidate: candidate)) else {
      return SavedDrawingBrowserError.drawingUnavailable.localizedDescription
    }
    do {
      try candidate.validateIntegrity()
      let previous = labels.last { $0.candidateID == candidate.id && $0.scope.id == scope.id
        && $0.presentation.physicalAttemptID == presentation.physicalAttemptID
        && archive.labelPhotoIDs?[$0.id.uuidString.lowercased()] == candidate.photoID
        && !archive.withdrawnLabelIDs.contains($0.id.uuidString) }
      let label = try PortraitLabelRevision(candidate: candidate, rating: rating, scope: scope,
        presentation: presentation, previousRevisionID: previous?.id)
      try PortraitArchiveValidation.label(label, candidate: candidate)
      enqueue(.rate(candidate, label, .init(reason: .rated(labelRevisionID: label.id))))
      return nil
    } catch { return error.localizedDescription }
  }

  package func remove(_ id: String) {
    let photoID = (selectedID == id ? selected?.sourcePhotoID : nil)
      ?? entries.first(where: { $0.id == id })?.candidate.photoID
      ?? sketches.first(where: { $0.id == id })?.sourcePhotoID
      ?? drawingSummaries.first(where: { $0.id == id })?.photoID
    if let photoID {
      deleteDrawing(.init(candidateID: id, photoID: photoID))
      return
    }
    guard sketches.contains(where: { $0.id == id }) || drawingSummaries.contains(where: { $0.id == id }) else { return }
    // Source-free generic drawings have no capture occurrence to bind.
    enqueue(.delete(.init(id: UUID(), kind: .candidate, identity: id,
      affectedCandidateIDs: [id], assetSHA256s: [], createdAt: Date())))
    selectedDrawings[id] = nil
    drawingSummaries.removeAll { $0.id == id }
    if selectedID == id { selectedID = nil }
  }

  /// Browser deletion is occurrence-specific. Legacy candidate tombstones keep
  /// their candidate-wide meaning, while equal-content captures remain distinct.
  package func deleteDrawing(_ identity: PortraitDrawingIdentity) {
    let wasSelected = selectedID == identity.candidateID && selected?.sourcePhotoID == identity.photoID
    enqueue(.delete(.init(id: UUID(), kind: .drawing, identity: identity.id,
      affectedCandidateIDs: [], assetSHA256s: [], createdAt: Date())))
    if selectedDrawings[identity.candidateID]?.sourcePhotoID == identity.photoID {
      selectedDrawings[identity.candidateID] = nil
    }
    drawingSummaries.removeAll { $0.id == identity.candidateID && $0.photoID == identity.photoID }
    if wasSelected { selectedID = nil }
  }

  /// Capture identity owns source deletion. SHA equality never broadens it to
  /// another photograph; imported legacy SHA tombstones keep their old meaning.
  package func deleteSource(photoID: UUID) {
    let affected = entries.filter { $0.candidate.photoID == photoID }
    guard !affected.isEmpty || sourcePhotos.contains(where: { $0.id == photoID })
      || photoReferences.contains(where: { $0.id == photoID }) else { return }
    let now = Date()
    deletedBrowsePhotos[photoID] = now
    photoReferences.removeAll { $0.id == photoID }
    enqueue(.delete(.init(id: UUID(), kind: .photo, identity: photoID.uuidString.lowercased(),
      affectedCandidateIDs: [], assetSHA256s: [], createdAt: now)))
    selectedDrawings = selectedDrawings.filter { $0.value.sourcePhotoID != photoID }
    drawingSummaries.removeAll { $0.photoID == photoID }
    if let selectedID, affected.contains(where: { $0.id == selectedID }) { self.selectedID = nil }
  }

  package func withdrawLabel(_ id: UUID) {
    guard let label = labels.first(where: { $0.id == id }),
      !archive.withdrawnLabelIDs.contains(id.uuidString) else { return }
    enqueue(.delete(.init(id: UUID(), kind: .label, identity: id.uuidString,
      affectedCandidateIDs: [label.candidateID], assetSHA256s: [], createdAt: Date())))
  }

  package func retryPersistence() {
    guard worker == nil else { return }
    // Reload before retry so repaired assets/index are verified and retained
    // disk records are merged before replaying the still-pending mutations.
    if store != nil {
      mutationStateHasLoaded = false
      if historyLoadWasRequested { historyLoadRequested = true }
    }
    startWorker()
  }

  package func awaitPersistence() async {
    await worker?.value
  }

  private enum Mutation {
    case saveDrawing(SavedDrawing)
    case retain(PortraitCandidate, PortraitRetentionEvent)
    case rate(PortraitCandidate, PortraitLabelRevision, PortraitRetentionEvent)
    case delete(PortraitArchiveTombstone)
    case attempt(PortraitCandidate, PortraitAttemptRecord)
    case feedback(PortraitDrawingIdentity, PortraitRetainedCandidate?, PortraitAttemptFeedbackRevision)
    case style(PortraitSavedStyle)
    case removeStyle(UUID)
    case sourcePhoto(PortraitPhoto)

    var drawingID: String? {
      switch self {
      case .saveDrawing(let drawing): drawing.id
      case .retain(let candidate, _), .rate(let candidate, _, _), .attempt(let candidate, _): candidate.id
      case .feedback(let identity, _, _): identity.candidateID
      default: nil
      }
    }

    var occurrenceCandidate: PortraitCandidate? {
      switch self {
      case .saveDrawing(let drawing): drawing.portraitCandidate
      case .retain(let candidate, _), .rate(let candidate, _, _), .attempt(let candidate, _): candidate
      case .feedback(_, let entry, _): entry?.candidate
      default: nil
      }
    }

    func apply(to archive: inout PortraitCandidateArchive) {
      switch self {
      case .saveDrawing(let drawing):
        guard !archive.tombstones.contains(where: { PortraitSketchCollection.affects($0,
          drawingID: drawing.id, photoID: drawing.sourcePhotoID, sourceSHA256: drawing.sourceImageSHA256,
          createdAt: drawing.createdAt) }) else { return }
        if let candidate = drawing.portraitCandidate { Self.retain(candidate, event: .init(reason: .shortlisted), in: &archive) }
        if archive.savedDrawings == nil { archive.savedDrawings = [] }
        if let index = archive.savedDrawings?.firstIndex(where: { $0.id == drawing.id }) {
          archive.savedDrawings?[index] = drawing
        } else { archive.savedDrawings?.append(drawing) }

      case .sourcePhoto(let photo):
        let hash = PortraitCandidateCoding.digest(photo.data)
        guard !archive.tombstones.contains(where: { PortraitSketchCollection.affects($0,
          drawingID: nil, photoID: photo.id, sourceSHA256: hash, createdAt: photo.capturedAt) }) else { return }
        if archive.sourcePhotos == nil { archive.sourcePhotos = [] }
        if let index = archive.sourcePhotos?.firstIndex(where: { $0.id == photo.id }) {
          guard archive.sourcePhotos?[index].data == photo.data else { return }
          archive.sourcePhotos?[index] = photo
        } else { archive.sourcePhotos?.append(photo) }
        archive.photoCaptureTimeUnknownIDs?.removeAll { $0 == photo.id }
      case .attempt(let candidate, let record):
        guard !archive.tombstones.contains(where: { PortraitSketchCollection.affects($0,
        drawingID: candidate.id, photoID: candidate.photoID, sourceSHA256: candidate.sourceSHA256,
        createdAt: candidate.createdAt) }) else { return }
        if let index = archive.entries.firstIndex(where: { $0.id == candidate.id }) {
          if archive.entries[index].candidate.photoID != candidate.photoID {
            archive.entries[index] = .init(candidate: candidate, reasons: [], attempt: record)
          } else if archive.entries[index].attempt == nil { archive.entries[index].attempt = record }
        } else { archive.entries.append(.init(candidate: candidate, reasons: [], attempt: record)) }
      case .feedback(let identity, let captured, let revision):
        guard let captured, !archive.tombstones.contains(where: { PortraitSketchCollection.affects($0,
          drawingID: identity.candidateID, photoID: identity.photoID,
          sourceSHA256: captured.candidate.sourceSHA256, createdAt: captured.candidate.createdAt) }) else { return }
        if !archive.entries.contains(where: { $0.id == identity.candidateID }) { archive.entries.append(captured) }
        if let index = archive.entries.firstIndex(where: {
          $0.id == identity.candidateID && $0.candidate.photoID == identity.photoID
        }), archive.entries[index].attempt?.feedbackRevisions.contains(where: { $0.id == revision.id }) == false {
          archive.entries[index].attempt?.feedbackRevisions.append(revision)
        }
      case .style(let style):
        if archive.savedStyles == nil { archive.savedStyles = [] }
        if archive.savedStyles?.contains(where: { $0.id == style.id }) == false { archive.savedStyles?.append(style) }
      case .removeStyle(let id): archive.savedStyles?.removeAll { $0.id == id }
      case .retain(let candidate, let event):
        Self.retain(candidate, event: event, in: &archive)
      case .rate(let candidate, let label, let event):
        guard !archive.tombstones.contains(where: { PortraitSketchCollection.affects($0,
          drawingID: candidate.id, photoID: candidate.photoID, sourceSHA256: candidate.sourceSHA256,
          createdAt: candidate.createdAt) }) else { return }
        Self.retain(candidate, event: event, in: &archive)
        if !archive.labels.contains(where: { $0.id == label.id }) {
          archive.labels.append(label)
          if archive.labelPhotoIDs == nil { archive.labelPhotoIDs = [:] }
          archive.labelPhotoIDs?[label.id.uuidString.lowercased()] = candidate.photoID
        }
      case .delete(let requested):
        let affected = archive.entries.filter { PortraitSketchCollection.affects(requested,
          drawingID: $0.id, photoID: $0.candidate.photoID, sourceSHA256: $0.candidate.sourceSHA256,
          createdAt: $0.candidate.createdAt) }
        let tombstone = PortraitArchiveTombstone(id: requested.id, kind: requested.kind,
          identity: requested.identity,
          affectedCandidateIDs: requested.kind == .photo || requested.kind == .drawing ? [] : Array(Set(requested.affectedCandidateIDs + affected.map(\.id))).sorted(),
          assetSHA256s: requested.kind == .label ? [] : Array(Set(requested.assetSHA256s
            + affected.flatMap { [$0.candidate.sourceSHA256, $0.candidate.rasterSHA256] })).sorted(),
          createdAt: requested.createdAt)
        if let index = archive.tombstones.firstIndex(where: { $0.id == tombstone.id }) {
          archive.tombstones[index] = tombstone
        } else { archive.tombstones.append(tombstone) }
        if tombstone.kind != .label {
          archive.entries.removeAll { PortraitSketchCollection.affects(tombstone, drawingID: $0.id,
            photoID: $0.candidate.photoID, sourceSHA256: $0.candidate.sourceSHA256, createdAt: $0.candidate.createdAt) }
          archive.savedDrawings?.removeAll { PortraitSketchCollection.affects(tombstone, drawingID: $0.id,
            photoID: $0.sourcePhotoID, sourceSHA256: $0.sourceImageSHA256, createdAt: $0.createdAt) }
        }
        if tombstone.kind == .source || tombstone.kind == .photo {
          archive.sourcePhotos?.removeAll { PortraitSketchCollection.affects(tombstone, drawingID: nil,
            photoID: $0.id, sourceSHA256: PortraitCandidateCoding.digest($0.data), createdAt: $0.capturedAt) }
        }
      }
    }

    private static func retain(_ candidate: PortraitCandidate, event: PortraitRetentionEvent,
      in archive: inout PortraitCandidateArchive) {
      guard !archive.tombstones.contains(where: { PortraitSketchCollection.affects($0,
        drawingID: candidate.id, photoID: candidate.photoID, sourceSHA256: candidate.sourceSHA256,
        createdAt: candidate.createdAt) }) else { return }
      if archive.savedDrawings == nil { archive.savedDrawings = [] }
      if let index = archive.savedDrawings?.firstIndex(where: { $0.id == candidate.id }) {
        archive.savedDrawings?[index] = SavedDrawing(candidate: candidate)
      } else { archive.savedDrawings?.append(SavedDrawing(candidate: candidate)) }
      if let index = archive.entries.firstIndex(where: { $0.id == candidate.id }) {
        if archive.entries[index].candidate.photoID != candidate.photoID {
          archive.entries[index] = .init(candidate: candidate, reasons: [event])
          return
        }
        if !archive.entries[index].reasons.contains(where: { $0.reason == event.reason }) {
          archive.entries[index].reasons.append(event)
        }
      } else { archive.entries.append(.init(candidate: candidate, reasons: [event])) }
    }
  }

  private func enqueue(_ mutation: Mutation) {
    if case .saveDrawing(let drawing) = mutation,
      selectedDrawings[drawing.id]?.sourcePhotoID != drawing.sourcePhotoID { selectedDrawings[drawing.id] = nil }
    mutation.apply(to: &archive)
    refreshDrawingSummaries(including: mutation.drawingID)
    pending.append(mutation)
    unresolvedMutations = pending.count + pendingHistoryClears.count + pendingCleanupCount
    persistenceState = .pending
    startWorker()
  }

  private func startWorker() {
    guard worker == nil else { return }
    worker = Task { await drain() }
  }

  /// Eager cache mutations keep one candidate ID, but a queued batch can author
  /// several capture occurrences of that ID. Preserve each exact pending
  /// payload and its metadata for the actor's single relational commit.
  private func pendingOccurrences(_ mutations: ArraySlice<Mutation>,
    snapshot: PortraitCandidateArchive) -> [PortraitRetainedCandidate] {
    let candidateIDs = Set(mutations.compactMap(\.drawingID))
    var partitions: [PortraitDrawingIdentity: PortraitCandidateArchive] = [:]
    for entry in snapshot.entries where candidateIDs.contains(entry.id) {
      let identity = PortraitDrawingIdentity(candidateID: entry.id, photoID: entry.candidate.photoID)
      partitions[identity] = .init(entries: [entry])
    }
    for mutation in mutations {
      let identity: PortraitDrawingIdentity
      if case .feedback(let capturedIdentity, let entry, _) = mutation {
        identity = capturedIdentity
        if partitions[identity] == nil, let entry { partitions[identity] = .init(entries: [entry]) }
      } else if let candidate = mutation.occurrenceCandidate {
        identity = .init(candidateID: candidate.id, photoID: candidate.photoID)
      } else { continue }
      var partition = partitions[identity] ?? .init()
      mutation.apply(to: &partition)
      partitions[identity] = partition
    }
    // Deletion stays in the complete snapshot: install the valid ancestors of
    // earlier labels, then apply their tombstones in that same SQL transaction.
    return partitions.keys.sorted { $0.id < $1.id }.compactMap { identity in
      partitions[identity]?.entries.first {
        $0.id == identity.candidateID && $0.candidate.photoID == identity.photoID
      }
    }
  }

  private func loadPersistenceState(fullHistory: Bool, store: PortraitCandidateStore) async -> Bool {
    persistenceState = .loading
    savedStylesState = .loading
    if fullHistory {
      do {
        let styles = try await store.loadSavedStyles()
        archive.savedStyles = styles
        for mutation in pending { mutation.apply(to: &archive) }
        savedStylesState = .saved
      } catch { savedStylesState = .failed(error.localizedDescription) }
    }
    let loaded = fullHistory ? await store.load() : await store.loadMutationState()
    persistenceIssues = loaded.issues
    pendingCleanupCount = loaded.pendingCleanupCount
    pendingCleanupBytes = loaded.pendingCleanupBytes
    unresolvedMutations = pending.count + pendingHistoryClears.count + pendingCleanupCount
    if loaded.canWrite {
      if fullHistory { historyLoadHasCompleted = true }
      archive = loaded.archive
      for mutation in pending { mutation.apply(to: &archive) }
      mutationStateHasLoaded = true
      savedStylesState = .saved
      if let bytes = loaded.retainedBytes { retainedBytes = bytes }
      else { await updateRetainedBytes() }
      return true
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
        if let photoID = archive.labelPhotoIDs?[label.id.uuidString.lowercased()] {
          if recovered.labelPhotoIDs == nil { recovered.labelPhotoIDs = [:] }
          recovered.labelPhotoIDs?[label.id.uuidString.lowercased()] = photoID
        }
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
      if !fullHistory { savedStylesState = .failed(loaded.issues.joined(separator: " ")) }
      return false
    }
  }

  private func drain() async {
    defer { worker = nil }
    while true {
      // A full history request joins this owner instead of racing a second
      // loader against a snapshot or replacing mutations queued while awaiting.
      if let store, historyLoadRequested || !mutationStateHasLoaded {
        let fullHistory = historyLoadRequested
        historyLoadRequested = false
        historyLoadInProgress = fullHistory
        if fullHistory { historyLoadHasCompleted = false }
        let ready = await loadPersistenceState(fullHistory: fullHistory, store: store)
        historyLoadInProgress = false
        if !ready, !historyLoadRequested { return }
        continue
      }
      if !pendingHistoryClears.isEmpty, historyLoadHasCompleted {
        let requests = pendingHistoryClears
        pendingHistoryClears.removeAll()
        for identity in requests { clearUnkeptHistory(preservingOccurrence: identity) }
        unresolvedMutations = pending.count + pendingCleanupCount
      }
      guard !pending.isEmpty else { break }
      let mutationCount = pending.count
      persistenceState = .pending
      do {
        if let store {
          for index in 0..<mutationCount {
            if case .feedback(let identity, nil, let revision) = pending[index] {
              let entry = try await store.loadRetainedOccurrence(identity)
              pending[index] = .feedback(identity, entry, revision)
              pending[index].apply(to: &archive)
            }
          }
        }
        let snapshot = archive
        if let store {
          let occurrences = pendingOccurrences(pending.prefix(mutationCount), snapshot: snapshot)
          retainedBytes = try await store.save(snapshot: snapshot, occurrences: occurrences,
            mode: historyLoadHasCompleted ? .fullArchive : .mutationDelta)
          savedStylesState = .saved
          // A successful save has also completed any previously pending cleanup.
          pendingCleanupCount = 0
          pendingCleanupBytes = 0
        } else {
          await updateRetainedBytes(snapshot: snapshot)
        }
        pending.removeFirst(mutationCount)
        unresolvedMutations = pending.count + pendingHistoryClears.count + pendingCleanupCount
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
