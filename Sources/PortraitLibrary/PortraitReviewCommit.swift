import Foundation
import PortraitCore

package struct PortraitReviewCommittedResult: Sendable {
  package let drawing: SavedDrawing
  package let outcome: PortraitReviewGenerationOutcome?
  /// A saved result is still saved when secondary generation-journal persistence fails.
  package let evidenceError: String?
}

extension PortraitCandidateStore {
  /// Joins a single serialized commit; this creates no new scheduler, session, or drawing owner.
  /// Generic canonical loading checks Task cancellation even after its database commit. The small
  /// admitted import/finalization therefore uses an uncancelled task, with cancellation forwarded
  /// to the source token until the library's actual admission gate.
  package func commitExperimentalReviewResult(requestID: UUID, package: DrawingPackage,
    sourceAdmission: PortraitReviewSourceAdmissionToken, outputs: [PortraitReviewAsset] = [],
    now: Date = Date(), runtimeEnvironmentJSON: Data? = nil,
    runtimeMetricsJSON: Data? = nil) async throws -> PortraitReviewCommittedResult {
    try Task.checkCancellation()
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      let commit = Task.detached {
        try await self.commitAdmittedExperimentalResult(requestID: requestID, package: package,
          sourceAdmission: sourceAdmission, outputs: outputs, now: now,
          runtimeEnvironmentJSON: runtimeEnvironmentJSON, runtimeMetricsJSON: runtimeMetricsJSON)
      }
      return try await commit.value
    } onCancel: {
      sourceAdmission.cancel()
    }
  }

  private func commitAdmittedExperimentalResult(requestID: UUID, package: DrawingPackage,
    sourceAdmission: PortraitReviewSourceAdmissionToken, outputs: [PortraitReviewAsset], now: Date,
    runtimeEnvironmentJSON: Data?, runtimeMetricsJSON: Data?) throws -> PortraitReviewCommittedResult {
    try sourceAdmission.checkCancellation()
    try validateReviewMutationOwnership()
    guard let request = try reviewRecord(PortraitReviewGenerationRequest.self, kind: "request", id: requestID),
      let requestHash = try libraryDatabase().scalar("SELECT value FROM state WHERE key=?", [reviewKey("request", requestID)]) else {
      throw DrawingTransferError.unavailable("Freeze the generation request before committing its result.")
    }
    try request.validate(); try DrawingPackageLibraryValidation.validate(package)
    guard request.id == requestID, package.origin.captureID == request.captureID,
      package.source == request.source, package.artist == request.artist,
      package.program.fieldExtent.width == request.material.widthMM,
      package.program.fieldExtent.height == request.material.heightMM,
      package.program.strokes.allSatisfy({ $0.style.nominalLineWidth == request.material.nominalLineWidthMM }),
      request.inputs.first(where: { $0.role == "artist-input" }).map({ $0.asset == package.artistInput }) ?? true,
      now >= request.createdAt, package.createdAt <= now,
      package.createdAt >= request.createdAt || request.recordingMode == .retrospectiveExternalImport else {
      throw DrawingTransferError.conflict("Experimental result differs from its exact frozen request, source, or material.")
    }
    let bytes = try DrawingPackageCodec.encode(package), hash = DrawingPackageCodec.sha256(bytes)
    // Reject predictable journal/metadata errors before any canonical drawing row can be created.
    _ = try PortraitReviewGenerationOutcome(id: requestID, requestSHA256: requestHash, status: .succeeded,
      recordedAt: now, origin: package.origin, packageSHA256: hash, outputs: outputs,
      runtimeEnvironmentJSON: runtimeEnvironmentJSON, runtimeMetricsJSON: runtimeMetricsJSON)
    if let prior = try reviewRecord(PortraitReviewGenerationOutcome.self, kind: "outcome", id: requestID) {
      try prior.validate()
      guard prior.status == .succeeded, prior.origin == package.origin, prior.packageSHA256 == hash else {
        throw DrawingTransferError.conflict("This generation already has a different immutable terminal outcome.")
      }
      let drawing = try loadDrawing(package.origin.drawingID)
      try validateDurableDrawing(drawing)
      guard drawing.transferredPackage == package else { throw DrawingTransferError.conflict("Committed result identity differs.") }
      return .init(drawing: drawing, outcome: prior, evidenceError: nil)
    }
    func finalize(_ drawing: SavedDrawing) -> PortraitReviewCommittedResult {
      do {
        let outcome = try finishReviewGeneration(id: requestID, status: .succeeded, drawing: drawing,
          outputs: outputs, now: now, runtimeEnvironmentJSON: runtimeEnvironmentJSON, runtimeMetricsJSON: runtimeMetricsJSON)
        return .init(drawing: drawing, outcome: outcome, evidenceError: nil)
      } catch {
        if let committed = try? reviewRecord(PortraitReviewGenerationOutcome.self, kind: "outcome", id: requestID),
          committed.status == .succeeded, committed.origin == package.origin, committed.packageSHA256 == hash,
          (try? committed.validate()) != nil {
          refreshCommittedLibraryGeneration()
          return .init(drawing: drawing, outcome: committed, evidenceError: nil)
        }
        return .init(drawing: drawing, outcome: nil, evidenceError: error.localizedDescription)
      }
    }
    // Recovery can finalize an already proven canonical commit without restoring its deleted source.
    // The live-source admission below applies only when a new drawing row would be published.
    if let existing = try? loadDrawing(package.origin.drawingID), existing.transferredPackage == package,
      (try? validateDurableDrawing(existing)) != nil {
      return finalize(existing)
    }
    let db = try libraryDatabase(), captureKey = request.captureID.uuidString.lowercased()
    guard try db.scalar("SELECT source_hash FROM photo WHERE id=? AND deleted=0", [captureKey]) == request.source.sha256 else {
      throw DrawingTransferError.unavailable("The exact retained source capture was deleted or changed before result publication.")
    }
    let photo = try db.checkedPhoto(captureKey)
    guard photo.id == request.captureID, photo.sourceSHA256 == request.source.sha256,
      request.acquisitionID.map({ $0 == photo.captureSessionID }) ?? true else {
      throw DrawingTransferError.conflict("The live source capture provenance differs from the frozen request.")
    }
    let liveBytes = try Self.boundedReviewRead(directoryURL.appendingPathComponent("assets")
      .appendingPathComponent(request.source.sha256), maximumBytes: DrawingTransferLimits.sourceBytes)
    guard liveBytes == request.source.bytes else { throw DrawingTransferError.invalid("The live original source bytes differ.") }
    try validateReviewMutationOwnership()
    // No suspension occurs between this gate, canonical import, and terminal journal selection.
    try sourceAdmission.admitCommit()
    let drawing: SavedDrawing
    do {
      drawing = try importDrawingPackage(bytes, restoreDeleted: false)
    } catch {
      // A fault reported after COMMIT cannot turn a proven saved drawing into a failed/no-result job.
      guard let committed = try? loadDrawing(package.origin.drawingID), committed.transferredPackage == package,
        (try? validateDurableDrawing(committed)) != nil else { throw error }
      refreshCommittedLibraryGeneration()
      drawing = committed
    }
    return finalize(drawing)
  }
}
