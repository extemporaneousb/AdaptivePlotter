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
