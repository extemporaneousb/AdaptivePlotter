import Foundation
import PlotterModel
import PlotterRuntime

/// Library identity is a capture occurrence; renderer identity remains unchanged.
struct PortraitDrawingIdentity: Codable, Hashable, Identifiable, Sendable {
  let candidateID: String
  let photoID: UUID
  var id: String { photoID.uuidString.lowercased() + ":" + candidateID }
}

enum PortraitLibraryFilter: String, Codable, CaseIterable, Sendable {
  case allPhotos, photosWithPlottedWorks, photosWithoutPlottedWorks, plottedWorks
}

struct PortraitLibraryGeneration: Codable, Equatable, Sendable {
  let revision: Int64
  let legacyPortraitSHA256: String?
  let evidenceSHA256: String?
}

struct PortraitLibraryCursor: Equatable, Sendable {
  let generation: PortraitLibraryGeneration
  let filter: PortraitLibraryFilter
  let offset: Int
}

struct PortraitLibraryPhoto: Codable, Identifiable, Sendable {
  let reference: PortraitPhotoReference
  let drawingCount: Int
  let plottedWorkCount: Int
  var id: UUID { reference.id }
  /// Candidate creation time is only an internal legacy sort fallback.
  var actualCapturedAt: Date? { (reference.captureTimeKnown ?? (reference.candidateRecordSHA256 == nil)) ? reference.capturedAt : nil }
}

/// No program or pixels are decoded by a list query. Unknown historical inputs
/// remain unknown and cannot become a renderer candidate.
struct PortraitLibraryDrawing: Codable, Identifiable, Sendable {
  let identity: PortraitDrawingIdentity
  let summary: SavedDrawingSummary
  let isRenderable: Bool
  let recoveryMethod: String?
  var id: String { identity.id }
}

struct PortraitLibraryMedia: Codable, Equatable, Identifiable, Sendable {
  let id: String
  let stage: String
  let reference: DrawingRunMediaReference
  let isAvailable: Bool
  let unavailableReason: String?
}

struct PortraitLibraryWork: Codable, Identifiable, Sendable {
  let id: String
  let drawingID: String
  let photoID: UUID
  let runID: RunID
  let recordID: DrawingEvidenceRecordID?
  let status: String
  let recordedAt: Date?
  let executedOrPossibleInk: Bool
  let sourceGeneration: String
  let media: [PortraitLibraryMedia]
  let recoveryMethod: String
  var drawingTitle: String? = nil
  var sourcePhotoReference: PortraitPhotoReference? = nil
  var drawingIdentity: PortraitDrawingIdentity? = nil
}

struct PortraitLibrarySnapshot: Sendable {
  let generation: PortraitLibraryGeneration
  let photos: [PortraitLibraryPhoto]
  let drawings: [PortraitLibraryDrawing]
  let works: [PortraitLibraryWork]
  let next: PortraitLibraryCursor?
}

struct PortraitLibrarySelection: Sendable {
  let generation: PortraitLibraryGeneration
  let photo: PortraitLibraryPhoto
  let drawings: [PortraitLibraryDrawing]
  let works: [PortraitLibraryWork]
  let selectedDrawing: PortraitLibraryDrawing?
  let program: DrawingProgram?
  var selectedWorkID: String? = nil
}

struct PortraitHistoricalDrawing: Codable, Sendable {
  let identity: PortraitDrawingIdentity
  let program: DrawingProgram
  let sourceSHA256: String
  let recoveryMethod: String
  let proofSHA256: String
  // Recipe, raster, checkpoint and creation time were not retained. There is
  // deliberately no conversion to PortraitCandidate.
}

enum PortraitLibraryError: Error, LocalizedError {
  case database(String), staleGeneration, missingPhoto, missingDrawing, unresolvedLineage(String)
  var errorDescription: String? {
    switch self {
    case .database(let reason): "Portrait library database: \(reason)"
    case .staleGeneration: "Portrait history changed. Reconcile the archive before browsing."
    case .missingPhoto: "The exact source capture is unavailable."
    case .missingDrawing: "The exact portrait drawing is unavailable."
    case .unresolvedLineage(let reason): "Portrait provenance is unavailable: \(reason)"
    }
  }
}
