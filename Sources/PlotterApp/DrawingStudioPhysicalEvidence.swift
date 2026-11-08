import PortraitCore
import PortraitLibrary
import Foundation
import PlotterModel
import PlotterRuntime

extension Drawing {
  /// The existing opaque digest branch binds the entire immutable drawing record.
  func executionReference(for executionProgram: DrawingProgram) -> DrawingRunCandidateReference? {
    guard capabilities.supported.contains(.plot), let ref = reference else { return nil }
    let hex = Array(ref.digest.description.utf8)
    let bytes = stride(from: 0, to: hex.count, by: 2).compactMap {
      UInt8(String(decoding: hex[$0...($0 + 1)], as: UTF8.self), radix: 16)
    }
    guard let digest = try? PlotterModel.Digest(bytes: bytes) else { return nil }
    let candidate = DrawingRunCandidateReference(candidateID: ref.digest.description,
      contentHash: digest, sourceProgram: program)
    return candidate.matches(executionProgram) ? candidate : nil
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

  /// Stage receipt, exact ref and plan are captured before the durable association.
  /// The existing runtime awaits this callback before Pen Up normalization or motion.
  func retainDrawingCandidateForAttempt(_ intent: DrawingRunIntent) async throws {
    do { try await retainStagedDrawing(intent) }
    catch {
      await drawingEvidencePort.finishPortraitBinding(intent)
      throw error
    }
    await drawingEvidencePort.finishPortraitBinding(intent)
  }

  private func retainStagedDrawing(_ intent: DrawingRunIntent) async throws {
    guard let drawing = authoredDrawing(for: intent.context.program), let ref = drawing.reference,
      let candidate = intent.context.candidate,
      drawing.executionReference(for: intent.context.program) == candidate,
      drawingDraftSnapshot.program == intent.context.program, drawingDraftSnapshot.plan == intent.plan,
      !Task.isCancelled else { throw DrawingRunEvidenceError.invalidAttemptContext }
    guard case .loaded(let archive) = await drawingEvidencePort.loadForPortraitBinding(intent),
      archive.attempts.contains(where: { $0.intent == intent }) else {
      throw DrawingRunEvidenceError.invalidAttemptContext
    }
    func assertCurrent() throws {
      guard !Task.isCancelled, drawingDraftSnapshot.program == intent.context.program,
        drawingDraftSnapshot.plan == intent.plan,
        let current = authoredDrawing(for: intent.context.program), current.reference == ref,
        current.executionReference(for: intent.context.program) == candidate else {
        throw DrawingRunEvidenceError.invalidAttemptContext
      }
    }
    try assertCurrent()
    try await portraitStudio.sketches.bindDrawingAttempt(intent, drawing: drawing, archive: archive, archiveURL: drawingEvidencePort.archiveURL)
    try assertCurrent()
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
