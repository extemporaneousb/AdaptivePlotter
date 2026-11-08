import Foundation
import PortraitCore
import DrawingLibrary
import PlotterModel
import PlotterRuntime

/// Navigation staged before Start. It is neither a run receipt nor ink evidence.
package struct PortraitDrawingAttemptBinding: Codable, Sendable {
  package static let kind = "adaptiveplotter.drawing-run-binding/2"
  package let profile: String
  package let drawing: DrawingRef
  package let archive: UUID
  package let run: UUID
  package let request: UUID
  package let stagedGeneration: String

  package static func page(for drawing: DrawingRef, library: DrawingLibrary, limit: Int = 50,
    after: DrawingLibraryRecordCursor? = nil) async throws -> DrawingLibraryRecordPage {
    try await library.records(kind: kind, for: drawing, limit: limit, after: after)
  }
  package static func decode(_ record: DrawingLibraryRecord, for drawing: DrawingRef) throws -> Self {
    let value = try JSONDecoder().decode(Self.self, from: record.payload)
    guard record.kind == kind, value.profile == kind, record.id == value.run,
      record.drawings == [drawing], value.drawing == drawing else { throw DrawingExchangeError.mismatchedParent }
    _ = try ExchangeDigest(value.stagedGeneration)
    return value
  }
  /// Read the already-open raw owner's exact staged attempt. No program-hash
  /// join, archive import, issuance inference or historical fallback occurs.
  package func verify(in archive: DrawingRunEvidenceArchive, at url: URL, drawing value: Drawing) throws -> DrawingRunAttemptState {
    guard archive.archiveID == self.archive, value.reference == drawing,
      let attempt = archive.attempts.first(where: { $0.intent.runID.rawValue == run }),
      attempt.intent.requestID == request,
      let candidate = attempt.intent.context.candidate,
      candidate.candidateID == drawing.digest.description,
      candidate.contentHash.description == drawing.digest.description,
      candidate.sourceProgram == value.program, candidate.matches(attempt.intent.context.program) else { throw DrawingExchangeError.mismatchedParent }
    let proof = try PortraitEvidenceSource.proveStagedAttempt(attempt.intent, archive: archive, url: url)
    try proof.assertUnchanged()
    return attempt
  }
}
