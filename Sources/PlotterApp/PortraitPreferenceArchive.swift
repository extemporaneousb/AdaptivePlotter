import Foundation
import PlotterModel

/// Historical preference-export wire format. These records remain readable;
/// Studio authoring has no rating or preference-collection owner.
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

