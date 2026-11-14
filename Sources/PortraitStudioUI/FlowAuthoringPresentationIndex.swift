import Foundation
import PortraitLibrary
import PortraitCore

/// Derived lookup tables for one immutable portfolio revision. The document
/// remains authoritative; these values are never persisted or used for writes.
package struct FlowAuthoringPresentationIndex: Sendable {
  package let sources: [UUID: FlowPortfolioSource]
  package let rounds: [UUID: FlowPortfolioRound]
  package let candidates: [UUID: FlowPortfolioCandidate]
  package let latestPrunes: [UUID: FlowPortfolioPruneRevision]
  package let drawingNumbers: [UUID: Int]
  package let roundNumbers: [UUID: Int]

  package init(_ document: FlowPortfolioSnapshot) {
    sources = Dictionary(uniqueKeysWithValues: document.sources.map { ($0.id, $0) })
    rounds = Dictionary(uniqueKeysWithValues: document.rounds.map { ($0.id, $0) })
    candidates = Dictionary(uniqueKeysWithValues: document.candidates.map { ($0.id, $0) })
    var prunes: [UUID: FlowPortfolioPruneRevision] = [:]
    for revision in document.pruneRevisions { prunes[revision.candidateID] = revision }
    latestPrunes = prunes
    var firstSource: [PhotoRef: UUID] = [:], groups: [UUID: UUID] = [:]
    for source in document.sources {
      if let photo = source.photo {
        let group = firstSource[photo] ?? source.id
        firstSource[photo] = group; groups[source.id] = group
      } else { groups[source.id] = source.id }
    }
    var drawingCounts: [UUID: Int] = [:], drawingNumbers: [UUID: Int] = [:]
    for candidate in document.candidates {
      let group = groups[candidate.sourceID] ?? candidate.sourceID
      drawingCounts[group, default: 0] += 1
      drawingNumbers[candidate.id] = drawingCounts[group]
    }
    var roundCounts: [UUID: Int] = [:], roundNumbers: [UUID: Int] = [:]
    for round in document.rounds {
      let group = groups[round.sourceID] ?? round.sourceID
      roundCounts[group, default: 0] += 1
      roundNumbers[round.id] = roundCounts[group]
    }
    self.drawingNumbers = drawingNumbers; self.roundNumbers = roundNumbers
  }
}
