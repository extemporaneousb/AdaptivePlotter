import PortraitArtists
import PortraitCore
import Foundation
import PlotterModel
import PlotterRuntime

/// The reusable authored drawing. Portrait programs require their exact source
/// provenance; generic vector programs remain source-free. Physical execution
/// truth belongs to DrawingEvidence, independently of this library payload.
package struct SavedDrawing: Identifiable, Codable, Equatable, Sendable {
  package let id: String
  package let program: DrawingProgram
  package let portraitCandidate: PortraitCandidate?
  package let transferredPackage: DrawingPackage?
  package let createdAt: Date

  package init(program: DrawingProgram, createdAt: Date = Date()) {
    id = "drawing-" + program.contentHash.description
    self.program = program; portraitCandidate = nil; transferredPackage = nil; self.createdAt = createdAt
  }

  package init(candidate: PortraitCandidate) {
    id = candidate.id; program = candidate.program
    portraitCandidate = candidate; transferredPackage = nil; createdAt = candidate.createdAt
  }

  package init(package: DrawingPackage) throws {
    try DrawingPackageLibraryValidation.validate(package)
    id = package.origin.drawingID; program = package.program; createdAt = package.createdAt
    portraitCandidate = nil; transferredPackage = package
  }

  package var transferOrigin: DrawingOriginReference? { transferredPackage?.origin }
  package var sourceImageData: Data? { portraitCandidate?.sourceData ?? transferredPackage?.source.bytes }
  package var sourceImageSHA256: String? { portraitCandidate?.sourceSHA256 ?? transferredPackage?.source.sha256 }
  package var sourcePhotoID: UUID? { portraitCandidate?.photoID }
  package var programContentHash: String { program.contentHash.description }
  package var title: String {
    if let transferredPackage { return transferredPackage.title }
    if let candidate = portraitCandidate { return candidate.recipe.title }
    guard program.source.kind == "built-in-vector-catalog" else { return "Drawing" }
    let source = program.source.sourceIdentifier
    return DrawingProgramCatalog.entries.first {
      source == $0.sourceIdentifier
        || ($0.supportsCurveTessellation && source.hasPrefix($0.sourceIdentifier + ".tess-"))
    }?.displayName ?? "Drawing"
  }

  package var runCandidateReference: DrawingRunCandidateReference? {
    if let origin = transferOrigin {
      return DrawingRunCandidateReference(candidateID: id, contentHash: origin.identityHash,
        sourceProgram: program, origin: origin)
    }
    let identity = id.hasPrefix("drawing-") ? String(id.dropFirst(8)) : id
    let characters = Array(identity)
    guard characters.count == 64 else { return nil }
    let bytes = stride(from: 0, to: 64, by: 2).compactMap {
      UInt8(String(characters[$0...($0 + 1)]), radix: 16)
    }
    guard let digest = try? Digest(bytes: bytes) else { return nil }
    return DrawingRunCandidateReference(candidateID: id, contentHash: digest, sourceProgram: program)
  }

  package static func authored(program: DrawingProgram, projectedDrawing: SavedDrawing?,
    executionProgram: DrawingProgram) -> SavedDrawing? {
    let drawing: SavedDrawing
    if let projectedDrawing, projectedDrawing.program == program { drawing = projectedDrawing }
    else {
      guard program.source.kind != "portrait" else { return nil }
      drawing = SavedDrawing(program: program)
    }
    guard program.source.kind != "portrait" || drawing.portraitCandidate != nil
      || drawing.transferredPackage != nil else { return nil }
    guard drawing.runCandidateReference?.matches(executionProgram) == true else { return nil }
    return drawing
  }

  package func validateIntegrity() throws {
    if let package = transferredPackage {
      try DrawingPackageLibraryValidation.validate(package)
      guard portraitCandidate == nil, id == package.origin.drawingID,
        program == package.program, createdAt == package.createdAt else {
        throw PortraitCandidateError.integrityMismatch
      }
    } else if let candidate = portraitCandidate {
      try candidate.validateIntegrity()
      guard id == candidate.id, program == candidate.program, createdAt == candidate.createdAt else {
        throw PortraitCandidateError.integrityMismatch
      }
    } else {
      guard program.source.kind != "portrait" else { throw SavedDrawingBrowserError.portraitProvenanceRequired }
      if id != "drawing-" + program.contentHash.description { throw PortraitCandidateError.integrityMismatch }
    }
  }
}

/// A small read-only projection, never a partial writable archive.
package struct SavedDrawingSummary: Codable, Equatable, Identifiable, Sendable {
  package let id: String
  package let title: String
  package let createdAt: Date
  package let programContentHash: String
  package let programKind: String
  package let strokeCount: Int
  package let strokeStyle: StrokeStyle?
  package let pose: PortraitPose?
  package let photoID: UUID?
  package let sourceSHA256: String?
  package let recipe: PortraitStyleRecipe?
  package let isSaved: Bool
  package let feedback: PortraitAttemptFeedback?
  package let transferOrigin: DrawingOriginReference?
  package var style: PortraitStyle? { recipe?.style }

  package init(id: String, title: String, createdAt: Date, programContentHash: String,
    programKind: String, strokeCount: Int, strokeStyle: StrokeStyle?, pose: PortraitPose?,
    photoID: UUID?, sourceSHA256: String?, recipe: PortraitStyleRecipe?,
    isSaved: Bool, feedback: PortraitAttemptFeedback?, transferOrigin: DrawingOriginReference? = nil) {
    self.id = id; self.title = title; self.createdAt = createdAt
    self.programContentHash = programContentHash; self.programKind = programKind
    self.strokeCount = strokeCount; self.strokeStyle = strokeStyle; self.pose = pose
    self.photoID = photoID; self.sourceSHA256 = sourceSHA256; self.recipe = recipe
    self.isSaved = isSaved; self.feedback = feedback
    self.transferOrigin = transferOrigin
  }

  package init(_ drawing: SavedDrawing, isSaved: Bool = true, feedback: PortraitAttemptFeedback? = nil) {
    id = drawing.id; title = drawing.title; createdAt = drawing.createdAt
    programContentHash = drawing.programContentHash; programKind = drawing.program.source.kind
    strokeCount = drawing.program.strokes.count; strokeStyle = drawing.program.strokes.first?.style
    pose = drawing.portraitCandidate?.renderPose; photoID = drawing.portraitCandidate?.photoID
    sourceSHA256 = drawing.sourceImageSHA256; recipe = drawing.portraitCandidate?.recipe
    self.isSaved = isSaved; self.feedback = feedback
    transferOrigin = drawing.transferOrigin
  }
}

package struct SavedDrawingPage: Sendable {
  package let drawings: [SavedDrawingSummary]
  package let next: SavedDrawingPageCursor?
  package let candidateRecordsRead: Int

  package init(drawings: [SavedDrawingSummary], next: SavedDrawingPageCursor? = nil, candidateRecordsRead: Int) {
    self.drawings = drawings
    self.next = next
    self.candidateRecordsRead = candidateRecordsRead
  }
}

package struct SavedDrawingPageCursor: Sendable {
  package let indexState: VerifiedFileState
  package var offset = 0

  package init(indexState: VerifiedFileState, offset: Int = 0) {
    self.indexState = indexState
    self.offset = offset
  }
}

package enum SavedDrawingBrowserError: Error, LocalizedError {
  case archiveChanged, drawingUnavailable, notPortrait, portraitProvenanceRequired
  package var errorDescription: String? {
    switch self {
    case .archiveChanged: "Drawing history changed. Reload the drawing list."
    case .drawingUnavailable: "This drawing was deleted or is unavailable."
    case .notPortrait: "This drawing has no portrait image provenance."
    case .portraitProvenanceRequired: "This portrait is missing its exact retained source photograph and drawing provenance. Send the retained portrait to Drawing before saving or executing it."
    }
  }
}
