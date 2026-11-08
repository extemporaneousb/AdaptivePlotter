import Foundation
import DrawingLibrary
import PortraitCore
import PortraitArtists
import PlotterModel

struct FlowPendingRetainedWrite: Sendable {
  let prepared: [DrawingLibraryPreparedRetention]
  let next: FlowPortfolioSnapshot
  let records: [DrawingLibraryRecord]
  let assets: [DrawingLibraryClosureAsset]
  let publishedBlobs: [FlowPortfolioBlob]
  let feedback: FlowPreparedFeedback?
  let feedbackIntent: DrawingLibraryCommitIntent
  var authoredCommitted = false
}

extension FlowPortfolioStore {
  package func retainedDrawing(candidateID: UUID, revisionID: UUID? = nil) async throws -> Drawing {
    guard let candidate = state.candidates.first(where: { $0.id == candidateID }) else { throw FlowPortfolioError.unavailable("Choose a drawing first.") }
    let revision = revisionID.flatMap { id in state.pruneRevisions.first { $0.id == id && $0.candidateID == candidateID } }
    if revisionID != nil, revision == nil { throw FlowPortfolioError.invalid("The exact edit is unavailable.") }
    if let ref = revision?.drawing ?? (revision == nil || revision?.removedIndices.isEmpty == true ? candidate.drawing : nil) {
      return try await storage.library.drawing(ref)
    }
    var next = state
    let prepared = try await prepareDrawing(candidateID: candidateID, revision: revision, next: &next)
    try await commitPrepared(prepared, next: next)
    let reference: DrawingRef?
    if let revisionID { reference = state.pruneRevisions.first { $0.id == revisionID && $0.candidateID == candidateID }?.drawing }
    else { reference = state.candidates.first { $0.id == candidateID }?.drawing }
    guard let reference else { throw DrawingExchangeError.mismatchedParent }
    return try await storage.library.drawing(reference)
  }

  /// Parent and child receive exact refs before one common publication commits
  /// their geometry, dependencies and the domain action together.
  func prepareDrawing(candidateID: UUID, revision: FlowPortfolioPruneRevision?, next: inout FlowPortfolioSnapshot) async throws -> [DrawingLibraryPreparedRetention] {
    pinCandidate(candidateID); defer { unpinCandidate(candidateID) }
    guard let index = next.candidates.firstIndex(where: { $0.id == candidateID }) else { throw FlowPortfolioError.unavailable("Drawing unavailable.") }
    let candidate = next.candidates[index]
    let existing: DrawingRef?
    if let revision {
      let prior = state.latestPrune(candidateID: candidateID)
      // Reuse an exact retained revision when the explicit membership target did
      // not change. This does not infer identity from geometry equality.
      existing = revision.drawing
        ?? (revision.removedIndices.isEmpty ? candidate.drawing : nil)
        ?? (prior?.removedIndices == revision.removedIndices ? prior?.drawing : nil)
    } else { existing = candidate.drawing }
    if let existing {
      _ = try await storage.library.drawing(existing)
      if let revision, let revisionIndex = next.pruneRevisions.firstIndex(where: { $0.id == revision.id }) {
        next.pruneRevisions[revisionIndex].drawing = existing
      } else { next.candidates[index].drawing = existing }
      return []
    }
    let closure = drawingInputs[candidateID].map { DrawingLibraryRetainedClosure(input: $0) } ?? .empty
    var prepared: [DrawingLibraryPreparedRetention] = []
    let drawing: Drawing
    if let revision, !revision.removedIndices.isEmpty {
      guard revision.removedIndices.count < candidate.strokeCount else { throw DrawingExchangeError.allStrokesRemoved }
      let base: Drawing
      if let reference = candidate.drawing { base = try await storage.library.drawing(reference) }
      else {
        guard let temporary = temporaryDrawings[candidateID] else { throw FlowPortfolioError.unavailable("This generated drawing was temporary; its geometry is unavailable.") }
        let parent = try await storage.library.prepareRetention(temporary, title: candidate.title, reason: "required-edit-parent", closure: closure, intent: .init(id: candidateID))
        prepared.append(parent); base = parent.drawing; next.candidates[index].drawing = parent.reference
      }
      guard let reference = base.reference else { throw DrawingExchangeError.mismatchedParent }
      let removed = Set(revision.removedIndices)
      let kept = base.program.strokes.enumerated().filter { !removed.contains($0.offset) }.map { $0.element.id }
      drawing = try base.applying(.membership(kept), to: reference, programID: ProgramID(revision.id))
    } else if let reference = candidate.drawing { drawing = try await storage.library.drawing(reference) }
    else if let temporary = temporaryDrawings[candidateID] { drawing = temporary }
    else { throw FlowPortfolioError.unavailable("This generated drawing was temporary; its geometry is unavailable.") }
    let retained = try await storage.library.prepareRetention(drawing, title: candidate.title,
      reason: revision == nil ? "chosen" : "committed-stroke-edit", closure: closure,
      intent: .init(id: revision?.id ?? candidateID))
    prepared.append(retained)
    if let revision, let index = next.pruneRevisions.firstIndex(where: { $0.id == revision.id }) { next.pruneRevisions[index].drawing = retained.reference }
    else { next.candidates[index].drawing = retained.reference }
    return prepared
  }
  func commitPrepared(_ prepared: [DrawingLibraryPreparedRetention], next: FlowPortfolioSnapshot) async throws {
    if prepared.isEmpty {
      if next != state { try await commit(next, operation: "retainedSelectionUpdated") }
      return
    }
    guard !writeAdmissionActive, pendingGraphWrite == nil, pendingRetainedWrite == nil else { throw FlowPortfolioError.conflict("Recover the pending Library action before accepting another action.") }
    guard next.revision == state.revision else { throw FlowPortfolioError.conflict("The authoring session changed while this action was being prepared.") }
    writeAdmissionActive = true; defer { writeAdmissionActive = false; trimTransientCaches() }
    var next = next; next.revision = state.revision + 1
    try FlowPortfolioValidation.validate(next)
    let feedback = try await prepareFeedback(next: &next)
    let records = try graphRecords(next), publishedBlobs = durableAssets(next)
    let assets = try await storage.closureAssets(publishedBlobs) + featureClosureAssets()
    pendingRetainedWrite = .init(prepared: prepared, next: next, records: records, assets: assets, publishedBlobs: publishedBlobs, feedback: feedback, feedbackIntent: .init())
    try await finishPendingRetainedWrite()
  }
  func finishPendingRetainedWrite() async throws {
    guard var write = pendingRetainedWrite else { return }
    if let feedback = write.feedback {
      if !write.authoredCommitted {
        // Explicit authored fact is independent of the human judgment. Its
        // stable retention tokens are distinct from the feedback commit intent.
        _ = try await storage.library.commitRetentions(write.prepared, assets: write.assets)
        write.authoredCommitted = true; pendingRetainedWrite = write
      }
      _ = try await storage.library.commitFeedback(feedback.package, records: write.records, intent: write.feedbackIntent)
      try? FileManager.default.removeItem(at: feedback.temporaryRoot)
    } else {
      _ = try await storage.library.commitRetentions(write.prepared, records: write.records, assets: write.assets)
    }
    for record in write.records { committedRecords.insert(record.key) }
    storage.markPublished(write.publishedBlobs)
    for asset in write.assets { featureSupportingAssets.removeValue(forKey: asset.descriptor.asset.object) }
    state = write.next; pendingRetainedWrite = nil
  }
  package func closeLibrary() async { await storage.library.closeLibrary() }
}
