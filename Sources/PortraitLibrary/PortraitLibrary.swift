import PortraitArtists
import Foundation
import PlotterModel
import PlotterRuntime

/// Library identity is a capture occurrence; renderer identity remains unchanged.
package struct PortraitDrawingIdentity: Codable, Hashable, Identifiable, Sendable {
  package let candidateID: String
  package let photoID: UUID
  package var id: String { photoID.uuidString.lowercased() + ":" + candidateID }

  package init(candidateID: String, photoID: UUID) {
    self.candidateID = candidateID
    self.photoID = photoID
  }
}

package enum PortraitLibraryFilter: String, Codable, CaseIterable, Sendable {
  case allPhotos, photosWithPlottedWorks, photosWithoutPlottedWorks, plottedWorks
}

package struct PortraitLibraryGeneration: Codable, Equatable, Sendable {
  package let revision: Int64
  package let legacyPortraitSHA256: String?
  package let evidenceSHA256: String?

  package init(revision: Int64, legacyPortraitSHA256: String? = nil, evidenceSHA256: String? = nil) {
    self.revision = revision
    self.legacyPortraitSHA256 = legacyPortraitSHA256
    self.evidenceSHA256 = evidenceSHA256
  }
}

package struct PortraitLibraryCursor: Equatable, Sendable {
  package let generation: PortraitLibraryGeneration
  package let filter: PortraitLibraryFilter
  package let offset: Int

  package init(generation: PortraitLibraryGeneration, filter: PortraitLibraryFilter, offset: Int) {
    self.generation = generation
    self.filter = filter
    self.offset = offset
  }
}

package struct PortraitLibraryPhoto: Codable, Identifiable, Sendable {
  package let reference: PortraitPhotoReference
  package let drawingCount: Int
  package let plottedWorkCount: Int
  package var id: UUID { reference.id }
  /// Candidate creation time is only an internal legacy sort fallback.
  package var actualCapturedAt: Date? { (reference.captureTimeKnown ?? (reference.candidateRecordSHA256 == nil)) ? reference.capturedAt : nil }

  package init(reference: PortraitPhotoReference, drawingCount: Int, plottedWorkCount: Int) {
    self.reference = reference
    self.drawingCount = drawingCount
    self.plottedWorkCount = plottedWorkCount
  }
}

/// No program or pixels are decoded by a list query. Unknown historical inputs
/// remain unknown and cannot become a renderer candidate.
package struct PortraitLibraryDrawing: Codable, Identifiable, Sendable {
  package let identity: PortraitDrawingIdentity
  package let summary: SavedDrawingSummary
  package let isRenderable: Bool
  package let recoveryMethod: String?
  package var id: String { identity.id }

  package init(
    identity: PortraitDrawingIdentity,
    summary: SavedDrawingSummary,
    isRenderable: Bool,
    recoveryMethod: String? = nil
  ) {
    self.identity = identity
    self.summary = summary
    self.isRenderable = isRenderable
    self.recoveryMethod = recoveryMethod
  }
}

package struct PortraitLibraryMedia: Codable, Equatable, Identifiable, Sendable {
  package let id: String
  package let stage: String
  package let reference: DrawingRunMediaReference
  package let isAvailable: Bool
  package let unavailableReason: String?

  package init(
    id: String,
    stage: String,
    reference: DrawingRunMediaReference,
    isAvailable: Bool,
    unavailableReason: String? = nil
  ) {
    self.id = id
    self.stage = stage
    self.reference = reference
    self.isAvailable = isAvailable
    self.unavailableReason = unavailableReason
  }
}

package struct PortraitLibraryWork: Codable, Identifiable, Sendable {
  package let id: String
  package let drawingID: String
  package let photoID: UUID
  package let runID: RunID
  package let recordID: DrawingEvidenceRecordID?
  package let status: String
  package let recordedAt: Date?
  package let executedOrPossibleInk: Bool
  package let sourceGeneration: String
  package let media: [PortraitLibraryMedia]
  package let recoveryMethod: String
  package var drawingTitle: String? = nil
  package var sourcePhotoReference: PortraitPhotoReference? = nil
  package var drawingIdentity: PortraitDrawingIdentity? = nil

  package init(
    id: String,
    drawingID: String,
    photoID: UUID,
    runID: RunID,
    recordID: DrawingEvidenceRecordID? = nil,
    status: String,
    recordedAt: Date? = nil,
    executedOrPossibleInk: Bool,
    sourceGeneration: String,
    media: [PortraitLibraryMedia],
    recoveryMethod: String,
    drawingTitle: String? = nil,
    sourcePhotoReference: PortraitPhotoReference? = nil,
    drawingIdentity: PortraitDrawingIdentity? = nil
  ) {
    self.id = id
    self.drawingID = drawingID
    self.photoID = photoID
    self.runID = runID
    self.recordID = recordID
    self.status = status
    self.recordedAt = recordedAt
    self.executedOrPossibleInk = executedOrPossibleInk
    self.sourceGeneration = sourceGeneration
    self.media = media
    self.recoveryMethod = recoveryMethod
    self.drawingTitle = drawingTitle
    self.sourcePhotoReference = sourcePhotoReference
    self.drawingIdentity = drawingIdentity
  }
}

package struct PortraitLibrarySnapshot: Sendable {
  package let generation: PortraitLibraryGeneration
  package let photos: [PortraitLibraryPhoto]
  package let drawings: [PortraitLibraryDrawing]
  package let works: [PortraitLibraryWork]
  package let next: PortraitLibraryCursor?

  package init(
    generation: PortraitLibraryGeneration,
    photos: [PortraitLibraryPhoto],
    drawings: [PortraitLibraryDrawing],
    works: [PortraitLibraryWork],
    next: PortraitLibraryCursor? = nil
  ) {
    self.generation = generation
    self.photos = photos
    self.drawings = drawings
    self.works = works
    self.next = next
  }
}

package struct PortraitLibrarySelection: Sendable {
  package let generation: PortraitLibraryGeneration
  package let photo: PortraitLibraryPhoto
  package let drawings: [PortraitLibraryDrawing]
  package let works: [PortraitLibraryWork]
  package let selectedDrawing: PortraitLibraryDrawing?
  package let program: DrawingProgram?
  package var selectedWorkID: String? = nil

  package init(
    generation: PortraitLibraryGeneration,
    photo: PortraitLibraryPhoto,
    drawings: [PortraitLibraryDrawing],
    works: [PortraitLibraryWork],
    selectedDrawing: PortraitLibraryDrawing? = nil,
    program: DrawingProgram? = nil,
    selectedWorkID: String? = nil
  ) {
    self.generation = generation
    self.photo = photo
    self.drawings = drawings
    self.works = works
    self.selectedDrawing = selectedDrawing
    self.program = program
    self.selectedWorkID = selectedWorkID
  }
}

package struct PortraitHistoricalDrawing: Codable, Sendable {
  package let identity: PortraitDrawingIdentity
  package let program: DrawingProgram
  package let sourceSHA256: String
  package let recoveryMethod: String
  package let proofSHA256: String
  // Recipe, raster, checkpoint and creation time were not retained. There is
  // deliberately no conversion to PortraitCandidate.

  package init(
    identity: PortraitDrawingIdentity,
    program: DrawingProgram,
    sourceSHA256: String,
    recoveryMethod: String,
    proofSHA256: String
  ) {
    self.identity = identity
    self.program = program
    self.sourceSHA256 = sourceSHA256
    self.recoveryMethod = recoveryMethod
    self.proofSHA256 = proofSHA256
  }
}

package enum PortraitLibraryError: Error, LocalizedError {
  case database(String), staleGeneration, missingPhoto, missingDrawing, unresolvedLineage(String)
  package var errorDescription: String? {
    switch self {
    case .database(let reason): "Portrait library database: \(reason)"
    case .staleGeneration: "Portrait history changed. Reconcile the archive before browsing."
    case .missingPhoto: "The exact source capture is unavailable."
    case .missingDrawing: "The exact portrait drawing is unavailable."
    case .unresolvedLineage(let reason): "Portrait provenance is unavailable: \(reason)"
    }
  }
}
