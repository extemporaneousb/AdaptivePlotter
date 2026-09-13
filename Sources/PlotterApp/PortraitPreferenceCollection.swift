import Foundation
import Observation
import PlotterModel

/// One immutable label plus the exact candidate it evaluated. The collection
/// below is a projection of the shared archive, never another storage owner.
struct PortraitPreferenceExample: Identifiable, Codable, Sendable {
  let candidate: PortraitCandidate
  let label: PortraitLabelRevision
  var id: UUID { label.id }
  var photoID: UUID { candidate.photoID }
  var photoData: Data { candidate.sourceData }
  var photoSHA256: String { candidate.sourceSHA256 }
  var recipe: PortraitStyleRecipe { candidate.recipe }
  var recipeSHA256: String { candidate.recipeSHA256 }
  var program: DrawingProgram { candidate.program }
  var rating: Int { label.rating }
  var createdAt: Date { candidate.createdAt }
  var ratedAt: Date { label.createdAt }
  var programContentHash: String { candidate.program.contentHash.description }
}

struct PortraitPreferenceExport: Codable, Sendable {
  let schemaVersion: Int
  let kind: String
  let ratingMinimum: Int
  let ratingMaximum: Int
  let intendedUsage: String
  let sourceImageEncoding: String
  let examples: [PortraitPreferenceExample]

  init(examples: [PortraitPreferenceExample]) {
    schemaVersion = 2
    kind = "portrait-preference-examples"
    ratingMinimum = 1
    ratingMaximum = 5
    intendedUsage = "Immutable scoped operator labels with exact candidate, analysis and presentation context. "
      + "Generated vectors are not corrected target artwork. Retention events are not ratings. "
      + "Screen aesthetic labels contain no evidence of physical plotting and do not represent a trained generator."
    sourceImageEncoding = "base64-original-retained-image-bytes"
    self.examples = examples
  }
}

enum PortraitPreferenceError: LocalizedError {
  case emptyCollection
  var errorDescription: String? { "Rate a completed portrait before exporting examples." }
}

@Observable @MainActor
final class PortraitPreferenceCollection {
  let collection: PortraitSketchCollection
  init(collection: PortraitSketchCollection) { self.collection = collection }

  var examples: [PortraitPreferenceExample] {
    let withdrawn = collection.archive.withdrawnLabelIDs
    let candidates = Dictionary(uniqueKeysWithValues: collection.entries.map { ($0.id, $0.candidate) })
    return collection.labels.compactMap { label in
      guard !withdrawn.contains(label.id.uuidString), let candidate = candidates[label.candidateID] else { return nil }
      return PortraitPreferenceExample(candidate: candidate, label: label)
    }
  }

  var retainedBytes: Int { collection.retainedBytes }

  func remove(_ id: UUID) { collection.withdrawLabel(id) }

  func exportData() throws -> Data { try Self.exportData(examples: examples) }

  nonisolated static func exportData(examples: [PortraitPreferenceExample]) throws -> Data {
    guard !examples.isEmpty else { throw PortraitPreferenceError.emptyCollection }
    return try PortraitCandidateCoding.encoder().encode(PortraitPreferenceExport(examples: examples))
  }
}
