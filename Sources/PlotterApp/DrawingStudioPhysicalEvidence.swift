import CryptoKit
import Foundation
import PlotterModel
import PlotterRuntime

extension PortraitStudioModel {
  /// Gallery selection and subsequent authoring never retarget this link.
  func projectedReference(for executionProgram: DrawingProgram) -> DrawingRunCandidateReference? {
    guard let candidate = projectedCandidate,
      executionProgram.contentHash == candidate.program.contentHash
        || executionProgram.source.sourceIdentifier.hasSuffix("|draw-border-v1|artwork=\(candidate.program.contentHash)")
    else { return nil }
    let characters = Array(candidate.id)
    guard characters.count == 64 else { return nil }
    let bytes = stride(from: 0, to: 64, by: 2).compactMap {
      UInt8(String(characters[$0...($0 + 1)]), radix: 16)
    }
    guard let digest = try? PlotterModel.Digest(bytes: bytes) else { return nil }
    let reference = DrawingRunCandidateReference(candidateID: candidate.id, contentHash: digest,
      sourceProgram: candidate.program)
    return reference.matches(executionProgram) ? reference : nil
  }
}

extension PlotterApplicationRuntime {
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
    guard let reference = intent.context.candidate else { return }
    guard let candidate = portraitStudio.projectedCandidate,
      candidate.id == reference.candidateID,
      candidate.program == reference.sourceProgram else {
      throw DrawingRunEvidenceError.invalidAttemptContext
    }
    let selection = portraitStudio.sketches.selectedID
    let failure = portraitStudio.sketches.retain(candidate: candidate,
      reason: .physicalAttempt(attemptID: intent.runID.rawValue))
    portraitStudio.sketches.selectedID = selection
    if let failure {
      throw PlotterModelError.invalidValue(failure)
    }
    await portraitStudio.sketches.awaitPersistence()
    guard case .saved = portraitStudio.sketches.persistenceState else {
      throw PlotterModelError.invalidValue("The attempted candidate could not be durably retained.")
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
    drawingEvidenceArchive.incompleteAttempts.filter {
      $0.intent.role == .ordinaryDrawing && !$0.progressFrames.isEmpty
    }
  }

  func physicalAttemptImages(_ attempt: DrawingRunAttemptState) async throws -> [DisplayedFrame] {
    guard drawingReviewIncompleteAttempts.contains(attempt) else {
      throw DrawingRunEvidenceError.invalidAttemptContext
    }
    var images: [DisplayedFrame] = []
    for reference in attempt.baselines + attempt.progressFrames.map(\.media) {
      let frame = try await drawingEvidencePort.readMedia(reference)
      images.append(DisplayedFrame(source: reference.source, frame: frame))
    }
    return images
  }

  func physicalAttempts(candidateID: String) -> [DrawingRunEvidenceRecord] {
    drawingEvidenceArchive.reviewRecords.filter { $0.attemptEvidence?.intent.context.candidate?.candidateID == candidateID }
  }

  func physicalAttemptImages(_ record: DrawingRunEvidenceRecord) async throws -> [DisplayedFrame] {
    guard drawingEvidenceArchive.reviewRecords.contains(record), let attempt = record.attemptEvidence else {
      throw DrawingRunEvidenceError.invalidAttemptContext
    }
    var images: [DisplayedFrame] = []
    for reference in attempt.baselines + attempt.progressFrames.map(\.media) + attempt.terminalFrames {
      let frame = try await drawingEvidencePort.readMedia(reference)
      images.append(DisplayedFrame(source: reference.source, frame: frame))
    }
    return images
  }

}
