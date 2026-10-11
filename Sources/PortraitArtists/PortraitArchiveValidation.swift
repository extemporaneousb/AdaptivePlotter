import Foundation
import PlotterModel

package enum PortraitArchiveValidation {
  package static func label(_ label: PortraitLabelRevision, candidate: PortraitCandidate? = nil) throws {
    let scope = label.scope, presentation = label.presentation
    guard (1...5).contains(label.rating), scope.objective == presentation.objective,
      presentation.drawingHeightMM.isFinite, presentation.drawingHeightMM > 0,
      presentation.inkWidthMM.isFinite, presentation.inkWidthMM > 0,
      !presentation.rendererRevision.isEmpty,
      !scope.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, scope.revision > 0,
      !scope.allowedFamilies.isEmpty, Set(scope.allowedFamilies).count == scope.allowedFamilies.count,
      Set(scope.activeParameters).count == scope.activeParameters.count,
      Set(scope.frozenParameters.map(\.parameter)).count == scope.frozenParameters.count,
      Set(scope.activeParameters).isDisjoint(with: scope.frozenParameters.map(\.parameter)),
      scope.frozenParameters.allSatisfy({ $0.value.isFinite }) else {
      throw PortraitCandidateError.incompatibleScope
    }
    try presentation.validateDisplayEvidence(program: candidate?.program)
    if let evidence = presentation.displayEvidence,
      evidence.programContentHash != label.programContentHash {
      throw PortraitCandidateError.invalidPresentation
    }
    if presentation.objective == .physicalRealization {
      guard presentation.physicalAttemptID != nil, presentation.physicalRecordID != nil,
        let hashes = presentation.physicalMediaSHA256s, !hashes.isEmpty,
        hashes.allSatisfy({ $0.count == 64 && $0.allSatisfy(\.isHexDigit) }) else {
        throw PortraitCandidateError.invalidPresentation
      }
    } else if presentation.physicalAttemptID != nil || presentation.physicalRecordID != nil
      || presentation.physicalMediaSHA256s != nil { throw PortraitCandidateError.invalidPresentation }
    if let candidate {
      guard candidate.id == label.candidateID,
        candidate.program.contentHash.description == label.programContentHash,
        scope.allowedFamilies.contains(candidate.recipe.style) else { throw PortraitCandidateError.incompatibleScope }
    }
  }
}
