import Foundation
import PortraitArtists

extension PortraitParameterPreference {
  package static func report(around center: PortraitCandidate, archive: PortraitCandidateArchive) -> Report {
    guard let context = contextID(center) else {
      return .init(model: nil, labelCount: 0, groupCount: 0,
        summary: "Feedback learning uses shared parameters; this recipe retains its original controls.")
    }
    // Latest explicit vote per exact proposal wins. Saving, browsing and the
    // absence of a vote contribute no label. Apply the cap before numerical work.
    let voted = archive.entries.compactMap { entry -> (PortraitRetainedCandidate, PortraitAttemptFeedbackRevision)? in
      guard let vote = entry.attempt?.feedbackRevisions.last else { return nil }
      return (entry, vote)
    }.sorted { $0.1.createdAt > $1.1.createdAt }
    var identities = Set<String>(), rows: [Observation] = []
    for (entry, vote) in voted {
      guard let attempt = entry.attempt,
        contextID(entry.candidate) == context,
        identities.insert(attempt.proposalIdentity).inserted else { continue }
      guard vote.value != .unknown, let parameters = entry.candidate.recipe.vectorOptions.drawingParameters else { continue }
      rows.append(.init(candidateID: entry.id, proposalIdentity: attempt.proposalIdentity,
        feedbackID: vote.id, sourceSHA256: entry.candidate.sourceSHA256,
        sessionID: entry.candidate.captureSessionID, ancestryID: entry.candidate.lineage.ancestryGroupID,
        parameters: parameters, promising: vote.value == .promising))
      if rows.count == maximumLabels { break }
    }
    return fit(rows, contextID: context)
  }
}
