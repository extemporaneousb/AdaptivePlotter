import Foundation
import Observation
import DrawingLibrary
import PortraitCore
import PlotterModel
import PlotterRuntime

/// A selection is the complete immutable ref, or a fresh temporary intent.
/// Geometry equality and renderer hashes never select an authored occurrence.
package enum DrawingSelectionID: Hashable, Sendable {
  case temporary(UUID)
  case retained(DrawingRef)
}

@Observable @MainActor
package final class PortraitSketchCollection {
  package let library: DrawingLibrary
  package private(set) var selectionID: DrawingSelectionID?
  package private(set) var selected: Drawing?
  package private(set) var entries: [DrawingLibraryEntry] = []
  package private(set) var error: String?
  package private(set) var isLoading = false
  private var cursor: DrawingLibraryCursor?
  private var selectionRevision: UInt64 = 0
  private var closing = false
  @ObservationIgnored private var inFlight = 0
  @ObservationIgnored private var drainWaiters: [CheckedContinuation<Void, Never>] = []
  private func admit() throws {
    guard !closing else { throw DrawingLibraryError.closed }; inFlight += 1
  }
  private func finished() {
    inFlight -= 1
    if inFlight == 0 { let waiters = drainWaiters; drainWaiters = []; for waiter in waiters { waiter.resume() } }
  }
  package init(library: DrawingLibrary) { self.library = library }
  package var hasMore: Bool { cursor != nil }
  package var selectionEpoch: UInt64 { selectionRevision }
  package var isClosing: Bool { closing }
  package func clearSelection() {
    selectionRevision &+= 1; selected = nil; selectionID = nil
  }

  package func selectTemporary(_ drawing: Drawing) {
    guard !closing else { return }
    selectionRevision &+= 1
    selectionID = .temporary(UUID()); selected = drawing
  }
  /// Only an already-validated bound value may enter this synchronous path.
  /// Publishing it invalidates any older asynchronous selection request.
  package func selectLoaded(_ drawing: Drawing) throws {
    guard !closing else { throw DrawingLibraryError.closed }
    guard let reference = drawing.reference else { throw DrawingExchangeError.mismatchedParent }
    selectionRevision &+= 1
    selected = drawing; selectionID = .retained(reference)
  }
  package func select(_ reference: DrawingRef) async throws {
    try admit(); defer { finished() }
    selectionRevision &+= 1
    let revision = selectionRevision
    let drawing = try await library.drawing(reference)
    guard !closing, revision == selectionRevision, !Task.isCancelled else { throw CancellationError() }
    try selectLoaded(drawing)
  }
  package func retain(_ drawing: Drawing, reason: String) async throws -> Drawing {
    try admit(); defer { finished() }
    guard !closing else { throw DrawingLibraryError.closed }
    try await library.open()
    let receipt = try await library.retain(drawing, reason: reason)
    return try await library.drawing(receipt.reference)
  }
  /// Explicit membership completion is one admitted operation. Persistence never
  /// changes selection; its caller owns any guarded visible adoption.
  package func saveStrokeEdit(base: Drawing, keptStrokeIDs: [StrokeID],
    parentIntentID: UUID, editIntentID: UUID) async throws -> Drawing {
    try admit(); defer { finished() }
    try base.capabilities.require(.edit)
    let all = base.program.strokes.map(\.id), kept = Set(keptStrokeIDs)
    guard !kept.isEmpty else { throw DrawingExchangeError.allStrokesRemoved }
    guard kept.count == keptStrokeIDs.count else { throw DrawingExchangeError.duplicateStroke }
    guard kept.isSubset(of: Set(all)) else { throw DrawingExchangeError.unknownStroke }
    let unchanged = kept == Set(all)
    if !unchanged { _ = try DrawingStrokeMembership.apply(.membership(keptStrokeIDs), to: base.program, universe: base.program) }
    try await library.open()
    let exact: Drawing
    if let ref = base.reference {
      exact = try await library.drawing(ref)
      guard exact.reference == ref, exact.program == base.program else { throw DrawingExchangeError.mismatchedParent }
    } else { exact = base }
    try exact.capabilities.require(.edit)
    // Cancellation may refuse before preparation. Once prepared, settle this
    // admitted transaction through reload so abandoned drafts leave no pending roots.
    try Task.checkCancellation()
    let parent = try await library.prepareRetention(exact, reason: unchanged ? "save" : "required-edit-parent",
      intent: .init(id: parentIntentID))
    let selected: DrawingRef
    if unchanged {
      _ = try await library.commitRetention(parent)
      selected = parent.reference
    } else {
      let child = try parent.drawing.applying(.membership(keptStrokeIDs), to: parent.reference, programID: ProgramID(editIntentID))
      let prepared = try await library.prepareRetention(child, reason: "committed-stroke-edit", intent: .init(id: editIntentID))
      _ = try await library.commitRetentions([parent, prepared])
      selected = prepared.reference
    }
    let saved = try await library.drawing(selected)
    guard saved.reference == selected else { throw DrawingExchangeError.mismatchedParent }
    try saved.capabilities.require(.edit)
    return saved
  }
  /// Cache-only release of this editor's local preparations. Register before
  /// spawning the task so owner shutdown drains abandonment too. This never
  /// opens/recovers a Library or removes a durable journal/committed object.
  @discardableResult package func discardStrokeEditPreparations(_ intents: Set<UUID>,
    after settlement: Task<Void, Never>? = nil) -> Task<Void, Never> {
    inFlight += 1
    return Task {
      defer { finished() }
      if let settlement { await settlement.value }
      for intent in intents { await library.discardPending(intent) }
    }
  }
  package func load() async {
    guard !closing else { return }
    inFlight += 1
    isLoading = true; defer { isLoading = false; finished() }
    do { let page = try await library.drawings(limit: 100); entries = page.entries; cursor = page.next; error = nil }
    catch { self.error = error.localizedDescription }
  }
  package func loadMore() async throws {
    try admit(); defer { finished() }
    guard let cursor, !closing else { return }
    let page = try await library.drawings(limit: 100, after: cursor)
    entries += page.entries; self.cursor = page.next
  }
  package func rename(_ reference: DrawingRef, title: String?) async throws {
    try admit(); defer { finished() }
    try await library.rename(reference, title: title)
    await load()
  }
  package func delete(_ reference: DrawingRef) async throws {
    try admit(); defer { finished() }
    try await library.delete(reference)
    if selected?.reference == reference { clearSelection() }
    await load()
  }
  package func importDrawings(from url: URL) async throws -> [DrawingRef] {
    try admit(); defer { finished() }
    try await library.open()
    return try await library.importDrawings(from: url)
  }
  package func exportDrawing(_ reference: DrawingRef, to url: URL) async throws {
    try admit(); defer { finished() }
    try await library.exportDrawing(reference, to: url)
  }

  /// Bind the exact authoring ref to the already-staged raw intent. This is an
  /// advisory authoring relation; the raw archive continues to own physical facts.
  package func bindDrawingAttempt(_ intent: DrawingRunIntent, drawing: Drawing,
    archive: DrawingRunEvidenceArchive, archiveURL: URL) async throws {
    try admit(); defer { finished() }
    guard let reference = drawing.reference,
      let candidate = intent.context.candidate,
      candidate.candidateID == reference.digest.description,
      candidate.contentHash.description == reference.digest.description,
      candidate.sourceProgram == drawing.program,
      candidate.matches(intent.context.program) else { throw DrawingExchangeError.mismatchedParent }
    let durable = try await library.drawing(reference)
    guard durable.program == drawing.program else { throw DrawingExchangeError.mismatchedParent }
    let proof = try PortraitEvidenceSource.proveStagedAttempt(intent, archive: archive, url: archiveURL)
    struct Binding: Codable {
      let profile: String
      let drawing: DrawingRef
      let run: UUID
      let request: UUID
      let intent: DrawingRunIntent
      let archive: UUID
      let stagedGeneration: String
    }
    let record = Binding(profile: "adaptiveplotter.drawing-run-binding/1", drawing: reference,
      run: intent.runID.rawValue, request: intent.requestID, intent: intent,
      archive: archive.archiveID, stagedGeneration: proof.generation)
    let payload = try DrawingArtifactCoding.encoder().encode(record)
    try proof.assertUnchanged()
    try await library.commitRecords([.init(kind: "adaptiveplotter.drawing-run-binding/1", id: intent.runID.rawValue,
      payload: payload, drawings: [reference])], intent: .init(id: intent.requestID))
    try proof.assertUnchanged()
  }
  package func shutdown() async {
    closing = true; selectionRevision &+= 1
    if inFlight > 0 { await withCheckedContinuation { drainWaiters.append($0) } }
  }
}
