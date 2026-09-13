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
    if let failure = portraitStudio.sketches.retain(candidate: candidate,
      reason: .physicalAttempt(attemptID: intent.runID.rawValue)) {
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

  func physicalAttempts(candidateID: String) -> [DrawingRunEvidenceRecord] {
    drawingEvidenceArchive.records.filter { $0.attemptEvidence?.intent.context.candidate?.candidateID == candidateID }
  }

  func physicalAttemptImages(_ record: DrawingRunEvidenceRecord) async throws -> [DisplayedFrame] {
    guard drawingEvidenceArchive.records.contains(record), let attempt = record.attemptEvidence else {
      throw DrawingRunEvidenceError.invalidAttemptContext
    }
    var images: [DisplayedFrame] = []
    for reference in attempt.baselines + attempt.terminalFrames {
      let frame = try await drawingEvidencePort.readMedia(reference)
      images.append(DisplayedFrame(source: reference.source, frame: frame))
    }
    return images
  }

  func ratePhysicalAttempt(_ record: DrawingRunEvidenceRecord, rating: Int) -> String? {
    guard drawingEvidenceArchive.records.contains(record), let attempt = record.attemptEvidence,
      let reference = attempt.intent.context.candidate,
      let candidate = portraitStudio.sketches.entries.first(where: { $0.id == reference.candidateID })?.candidate,
      !attempt.terminalFrames.isEmpty else { return "A retained candidate and original result image are required." }
    let latestBaseline = attempt.baselines.map { $0.frame.captureNanoseconds }.max() ?? UInt64.max
    let resultImages = attempt.terminalFrames.filter { $0.frame.captureNanoseconds > latestBaseline }
    guard !resultImages.isEmpty else { return "No original result image newer than the baseline is available for a physical rating." }
    do {
      let scope = PortraitStyleScope(id: UUID(uuidString: "ACB37180-7DCB-4E6C-A4AD-90DC10F50171")!,
        name: "Physical drawing quality", revision: 1, objective: .physicalRealization,
        allowedFamilies: PortraitStyle.allCases, activeParameters: [], frozenParameters: [])
      let context = try PortraitPresentationContext(
        drawingHeightMM: physicalArtworkHeight(candidate: candidate, attempt: attempt),
        inkWidthMM: attempt.intent.context.materialProfile?.conservativeWidthMM ?? 0.4,
        inkWidthIsMeasured: physicalMaterialMeasurementApplies(attempt.intent.context),
        materialRevision: attempt.intent.context.materialProfile?.key, objective: .physicalRealization,
        prompt: "Rate the visible physical result in these original images; unseen ink remains unknown",
        physicalAttemptID: record.runID.rawValue, physicalRecordID: record.recordID.rawValue,
        physicalMediaSHA256s: resultImages.map { $0.frame.frameSHA256 })
      return portraitStudio.sketches.rate(candidate: candidate, rating: rating, scope: scope, presentation: context)
    } catch { return error.localizedDescription }
  }
}

/// Derive the actual uniform artwork scale from corresponding source/executed
/// segments. This also handles the border compositor whose own placement is 1:1.
private func physicalArtworkHeight(candidate: PortraitCandidate, attempt: DrawingRunAttemptEvidence) -> Double {
  for (source, executed) in zip(candidate.program.strokes, attempt.intent.plan.strokes) {
    guard source.id == executed.logicalStrokeID else { continue }
    for index in 1..<source.path.points.count {
      let a = source.path.points[index - 1], b = source.path.points[index]
      let c = executed.path.points[index - 1], d = executed.path.points[index]
      let sourceLength = hypot(b.x - a.x, b.y - a.y)
      if sourceLength > 1e-9 {
        return candidate.program.fieldExtent.height * hypot(d.x - c.x, d.y - c.y) / sourceLength
      }
    }
  }
  return candidate.program.fieldExtent.height * attempt.intent.plan.placement.uniformScale
}

private func physicalMaterialMeasurementApplies(_ context: DrawingRunAttemptContext) -> Bool {
  guard context.materialProfile?.independentlyMeasured == true, let paperStock = context.paperStock,
    let actual = try? DrawingMaterialApplicability(registration: context.registration,
      paperStock: paperStock, drawingFeedMMPerMinute: context.drawingFeedMMPerMinute,
      penActuationProfile: context.penActuationProfile) else { return false }
  return context.materialApplicability == actual
}
