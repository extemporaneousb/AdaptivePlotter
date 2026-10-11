import Foundation
import PlotterModel

/// Historical preference-export wire format. These records remain readable;
/// Studio authoring has no rating or preference-collection owner.
package struct PortraitPreferenceExample: Identifiable, Codable, Sendable {
  package let candidate: PortraitCandidate
  package let label: PortraitLabelRevision
  package var id: UUID { label.id }
  package var photoID: UUID { candidate.photoID }
  package var photoData: Data { candidate.sourceData }
  package var photoSHA256: String { candidate.sourceSHA256 }
  package var recipe: PortraitStyleRecipe { candidate.recipe }
  package var recipeSHA256: String { candidate.recipeSHA256 }
  package var program: DrawingProgram { candidate.program }
  package var rating: Int { label.rating }
  package var createdAt: Date { candidate.createdAt }
  package var ratedAt: Date { label.createdAt }
  package var programContentHash: String { candidate.program.contentHash.description }

  package init(candidate: PortraitCandidate, label: PortraitLabelRevision) {
    self.candidate = candidate
    self.label = label
  }
}

package struct PortraitPreferenceExport: Codable, Sendable {
  package let schemaVersion: Int
  package let kind: String
  package let ratingMinimum: Int
  package let ratingMaximum: Int
  package let intendedUsage: String
  package let sourceImageEncoding: String
  package let examples: [PortraitPreferenceExample]

  package init(examples: [PortraitPreferenceExample]) {
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

