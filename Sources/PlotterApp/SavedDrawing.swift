import Foundation
import PlotterModel
import PlotterRuntime

/// The reusable authored drawing. Portrait programs require their exact source
/// provenance; generic vector programs remain source-free. Physical execution
/// truth belongs to DrawingEvidence, independently of this library payload.
struct SavedDrawing: Identifiable, Codable, Equatable, Sendable {
  let id: String
  let program: DrawingProgram
  let portraitCandidate: PortraitCandidate?
  let createdAt: Date

  init(program: DrawingProgram, createdAt: Date = Date()) {
    id = "drawing-" + program.contentHash.description
    self.program = program; portraitCandidate = nil; self.createdAt = createdAt
  }

  init(candidate: PortraitCandidate) {
    id = candidate.id; program = candidate.program
    portraitCandidate = candidate; createdAt = candidate.createdAt
  }

  var sourceImageData: Data? { portraitCandidate?.sourceData }
  var sourceImageSHA256: String? { portraitCandidate?.sourceSHA256 }
  var sourcePhotoID: UUID? { portraitCandidate?.photoID }
  var programContentHash: String { program.contentHash.description }
  var title: String {
    if let candidate = portraitCandidate { return candidate.recipe.title }
    guard program.source.kind == "built-in-vector-catalog" else { return "Drawing" }
    let source = program.source.sourceIdentifier
    return DrawingProgramCatalog.entries.first {
      source == $0.sourceIdentifier
        || ($0.supportsCurveTessellation && source.hasPrefix($0.sourceIdentifier + ".tess-"))
    }?.displayName ?? "Drawing"
  }

  var runCandidateReference: DrawingRunCandidateReference? {
    let identity = id.hasPrefix("drawing-") ? String(id.dropFirst(8)) : id
    let characters = Array(identity)
    guard characters.count == 64 else { return nil }
    let bytes = stride(from: 0, to: 64, by: 2).compactMap {
      UInt8(String(characters[$0...($0 + 1)]), radix: 16)
    }
    guard let digest = try? Digest(bytes: bytes) else { return nil }
    return DrawingRunCandidateReference(candidateID: id, contentHash: digest, sourceProgram: program)
  }

  static func authored(program: DrawingProgram, projectedDrawing: SavedDrawing?,
    executionProgram: DrawingProgram) -> SavedDrawing? {
    let drawing: SavedDrawing
    if let projectedDrawing, projectedDrawing.program == program { drawing = projectedDrawing }
    else {
      guard program.source.kind != "portrait" else { return nil }
      drawing = SavedDrawing(program: program)
    }
    guard program.source.kind != "portrait" || drawing.portraitCandidate != nil else { return nil }
    guard drawing.runCandidateReference?.matches(executionProgram) == true else { return nil }
    return drawing
  }

  func validateIntegrity() throws {
    if let candidate = portraitCandidate {
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
struct SavedDrawingSummary: Codable, Equatable, Identifiable, Sendable {
  let id: String
  let title: String
  let createdAt: Date
  let programContentHash: String
  let programKind: String
  let strokeCount: Int
  let strokeStyle: StrokeStyle?
  let pose: PortraitPose?
  let photoID: UUID?
  let sourceSHA256: String?
  let recipe: PortraitStyleRecipe?
  let isSaved: Bool
  let feedback: PortraitAttemptFeedback?
  var style: PortraitStyle? { recipe?.style }

  init(id: String, title: String, createdAt: Date, programContentHash: String,
    programKind: String, strokeCount: Int, strokeStyle: StrokeStyle?, pose: PortraitPose?,
    photoID: UUID?, sourceSHA256: String?, recipe: PortraitStyleRecipe?,
    isSaved: Bool, feedback: PortraitAttemptFeedback?) {
    self.id = id; self.title = title; self.createdAt = createdAt
    self.programContentHash = programContentHash; self.programKind = programKind
    self.strokeCount = strokeCount; self.strokeStyle = strokeStyle; self.pose = pose
    self.photoID = photoID; self.sourceSHA256 = sourceSHA256; self.recipe = recipe
    self.isSaved = isSaved; self.feedback = feedback
  }

  init(_ drawing: SavedDrawing, isSaved: Bool = true, feedback: PortraitAttemptFeedback? = nil) {
    id = drawing.id; title = drawing.title; createdAt = drawing.createdAt
    programContentHash = drawing.programContentHash; programKind = drawing.program.source.kind
    strokeCount = drawing.program.strokes.count; strokeStyle = drawing.program.strokes.first?.style
    pose = drawing.portraitCandidate?.renderPose; photoID = drawing.portraitCandidate?.photoID
    sourceSHA256 = drawing.portraitCandidate?.sourceSHA256; recipe = drawing.portraitCandidate?.recipe
    self.isSaved = isSaved; self.feedback = feedback
  }
}

struct SavedDrawingPage: Sendable {
  let drawings: [SavedDrawingSummary]
  let next: SavedDrawingPageCursor?
  let candidateRecordsRead: Int
}

struct SavedDrawingPageCursor: Sendable {
  let indexState: VerifiedFileState
  var offset = 0
}

enum SavedDrawingBrowserError: Error, LocalizedError {
  case archiveChanged, drawingUnavailable, notPortrait, portraitProvenanceRequired
  var errorDescription: String? {
    switch self {
    case .archiveChanged: "Drawing history changed. Reload the drawing list."
    case .drawingUnavailable: "This drawing was deleted or is unavailable."
    case .notPortrait: "This drawing has no portrait image provenance."
    case .portraitProvenanceRequired: "This portrait is missing its exact retained source photograph and drawing provenance. Send the retained portrait to Drawing before saving or executing it."
    }
  }
}
