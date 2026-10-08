import Foundation
import PlotterModel
import PlotterRuntime

extension SavedDrawing {
  /// Reference construction validates the known compositor against the exact authored payload.
  func executionReference(for executionProgram: DrawingProgram) -> DrawingRunCandidateReference? {
    guard let reference = runCandidateReference else { return nil }
    return reference.matches(executionProgram) ? reference : nil
  }
}

extension PlotterApplicationRuntime {
  func savedDrawingReference(for executionProgram: DrawingProgram) -> DrawingRunCandidateReference? {
    authoredDrawing(for: executionProgram)?.executionReference(for: executionProgram)
  }

  var currentDrawingMaterialContextHash: PlotterModel.Digest? {
    guard let record = drawingMaterials.activeRecord else { return nil }
    if drawingMaterialHashCache?.key == record.profile.key { return drawingMaterialHashCache?.digest }
    guard let digest = try? DrawingRunAttemptContext.materialContextHash(
      profile: record.profile, applicability: record.applicability) else { return nil }
    drawingMaterialHashCache = (record.profile.key, digest)
    return digest
  }

  /// The staged intent supplies identity. Retention must settle before the runtime
  /// can begin motion; a failed write is an explicit attempt failure.
  func retainDrawingCandidateForAttempt(_ intent: DrawingRunIntent) async throws {
    do {
      try await retainStagedDrawingCandidateForAttempt(intent)
    } catch {
      await drawingEvidencePort.finishPortraitBinding(intent)
      throw error
    }
    await drawingEvidencePort.finishPortraitBinding(intent)
  }

  private func retainStagedDrawingCandidateForAttempt(_ intent: DrawingRunIntent) async throws {
    guard let reference = intent.context.candidate else {
      if intent.role == .ordinaryDrawing, intent.context.program.source.kind == "portrait" {
        throw SavedDrawingBrowserError.portraitProvenanceRequired
      }
      return
    }
    guard drawingDraftSnapshot.program == intent.context.program,
      drawingDraftSnapshot.plan == intent.plan else {
      throw DrawingRunEvidenceError.invalidAttemptContext
    }
    guard let drawing = authoredDrawing(for: intent.context.program),
      drawing.id == reference.candidateID,
      drawing.program == reference.sourceProgram else {
      throw DrawingRunEvidenceError.invalidAttemptContext
    }
    if let failure = await portraitStudio.sketches.saveDrawing(drawing) {
      throw PlotterModelError.invalidValue(failure)
    }
    if let candidate = drawing.portraitCandidate {
      let selection = portraitStudio.sketches.selectedID
      let failure = portraitStudio.sketches.retain(candidate: candidate,
        reason: .physicalAttempt(attemptID: intent.runID.rawValue))
      portraitStudio.sketches.selectedID = selection
      if let failure { throw PlotterModelError.invalidValue(failure) }
      await portraitStudio.sketches.awaitPersistence()
      guard case .saved = portraitStudio.sketches.persistenceState else {
        throw PlotterModelError.invalidValue("The attempted drawing could not be durably retained.")
      }
      guard case .loaded(let stagedArchive) = await drawingEvidencePort.loadForPortraitBinding(intent) else {
        throw DrawingRunEvidenceError.invalidAttemptContext
      }
      try await portraitStudio.sketches.bindPortraitAttempt(intent, candidate: candidate,
        evidence: stagedArchive, sourceURL: drawingEvidencePort.archiveURL)
    }
    guard !Task.isCancelled, !portraitStudio.sketches.drawingWasDeleted(drawing),
      drawingDraftSnapshot.program == intent.context.program,
      drawingDraftSnapshot.plan == intent.plan,
      let current = authoredDrawing(for: intent.context.program),
      current.id == reference.candidateID, current.program == reference.sourceProgram else {
      throw DrawingRunEvidenceError.invalidAttemptContext
    }
  }

  func verifyMaterialMedia(_ record: DrawingMaterialRecord) async -> String? {
    guard record.measurement != nil else { return nil }
    guard let references = record.ownedMedia else {
      return "Legacy measurement: original image ownership was not recorded."
    }
    do {
      for reference in references {
        _ = try await drawingEvidencePort.readMedia(reference)
        try Task.checkCancellation()
      }
      return "Original measurement images verified (\(references.count))."
    } catch {
      return "Original measurement images unavailable: \(error.localizedDescription). The historical estimate is retained; image-based verification is unavailable."
    }
  }

  var drawingReviewRecords: [DrawingRunEvidenceRecord] {
    drawingEvidenceArchive.reviewRecords.filter { $0.role == .ordinaryDrawing }
  }

  var drawingReviewIncompleteAttempts: [DrawingRunAttemptState] {
    drawingEvidenceArchive.reviewIncompleteAttempts.filter {
      $0.intent.role == .ordinaryDrawing
    }
  }

  /// Reads only the currently selected retained photograph. Navigation never acquires live camera authority.
  func drawingReviewImage(_ reference: DrawingRunMediaReference, runID: RunID) async throws -> DisplayedFrame {
    func retained() -> Bool {
      if let record = drawingReviewRecords.first(where: { $0.runID == runID }), let attempt = record.attemptEvidence {
        return (attempt.baselines + attempt.progressFrames.map(\.media) + attempt.terminalFrames).contains(reference)
      }
      if let attempt = drawingReviewIncompleteAttempts.first(where: { $0.intent.runID == runID }) {
        return (attempt.baselines + attempt.progressFrames.map(\.media)).contains(reference)
      }
      return false
    }
    guard retained() else { throw DrawingRunEvidenceError.invalidAttemptContext }
    let frame = try await drawingEvidencePort.readMedia(reference)
    try Task.checkCancellation()
    guard retained() else { throw DrawingRunEvidenceError.invalidAttemptContext }
    return DisplayedFrame(source: reference.source, frame: frame)
  }



}
