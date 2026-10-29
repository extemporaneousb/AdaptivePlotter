import Foundation

/// Small immutable changes, not a copy of all prior decisions on every click.
struct FlowPortfolioDelta: Codable {
  let sources: [FlowPortfolioSource]
  let rounds: [FlowPortfolioRound]
  let candidates: [FlowPortfolioCandidate]
  let choices: [FlowPortfolioChoice]
  let pruneRevisions: [FlowPortfolioPruneRevision]
  let presentations: [FlowPortfolioPresentation]
  let rankings: [FlowPortfolioRanking]
  let trainingSnapshots: [FlowPortfolioTrainingSnapshot]
  let fits: [FlowPortfolioFit]
  let activations: [FlowPortfolioActivation]
  let legacyImports: [FlowPortfolioLegacyImport]
  let selectedSourceID: UUID?
  let currentRoundID: UUID?
  let currentCandidateID: UUID?
  let currentPruneRevisionID: UUID?
  let activeFitID: UUID?
  let currentPresentationID: UUID?

  init(previous: FlowPortfolioSnapshot, next: FlowPortfolioSnapshot) {
    func changed<T: Identifiable & Equatable>(_ old: [T], _ new: [T]) -> [T] {
      let existing = old.reduce(into: [T.ID: T]()) { $0[$1.id] = $1 }
      return new.filter { existing[$0.id] != $0 }
    }
    sources = changed(previous.sources, next.sources)
    rounds = changed(previous.rounds, next.rounds)
    candidates = changed(previous.candidates, next.candidates)
    choices = Array(next.choices.dropFirst(previous.choices.count))
    pruneRevisions = next.pruneRevisions.dropFirst(previous.pruneRevisions.count).map { value in
      var compact = value
      // These projections are reconstructed from operations, not rewritten on
      // every click. Full frozen training documents retain them for inspection.
      compact.removedIndices = []; compact.undoOperationIDs = []; compact.redoOperationIDs = []
      return compact
    }
    presentations = Array(next.presentations.dropFirst(previous.presentations.count))
    rankings = Array(next.rankings.dropFirst(previous.rankings.count))
    trainingSnapshots = Array(next.trainingSnapshots.dropFirst(previous.trainingSnapshots.count))
    fits = Array(next.fits.dropFirst(previous.fits.count))
    activations = Array(next.activations.dropFirst(previous.activations.count))
    legacyImports = Array(next.legacyImports.dropFirst(previous.legacyImports.count))
    selectedSourceID = next.selectedSourceID; currentRoundID = next.currentRoundID
    currentCandidateID = next.currentCandidateID; currentPruneRevisionID = next.currentPruneRevisionID
    activeFitID = next.activeFitID; currentPresentationID = next.currentPresentationID
  }

  func apply(to snapshot: inout FlowPortfolioSnapshot, revision: Int) {
    func upsert<T: Identifiable>(_ additions: [T], into values: inout [T]) {
      var positions = values.enumerated().reduce(into: [T.ID: Int]()) { $0[$1.element.id] = $1.offset }
      for addition in additions {
        if let index = positions[addition.id] { values[index] = addition }
        else { positions[addition.id] = values.count; values.append(addition) }
      }
    }
    upsert(sources, into: &snapshot.sources); upsert(rounds, into: &snapshot.rounds)
    upsert(candidates, into: &snapshot.candidates)
    snapshot.choices.append(contentsOf: choices)
    for compact in pruneRevisions {
      var edit = compact
      let prior = snapshot.pruneRevisions.last { $0.candidateID == edit.candidateID }
      var mask = Set(prior?.removedIndices ?? []), undo = prior?.undoOperationIDs ?? [], redo = prior?.redoOperationIDs ?? []
      switch edit.action {
      case .remove: mask.formUnion(edit.affectedIndices); undo.append(edit.id); redo = []
      case .restore: mask.subtract(edit.affectedIndices); undo.append(edit.id); redo = []
      case .modelProposal, .inheritedSelection: mask = Set(edit.affectedIndices); undo = []; redo = []
      case .completeTarget: break
      case .undo, .redo:
        let targetID = edit.action == .undo ? undo.popLast() : redo.popLast()
        if let targetID, let target = snapshot.pruneRevisions.first(where: { $0.id == targetID }) {
          let remove = (target.action == .remove) == (edit.action == .redo)
          if remove { mask.formUnion(edit.affectedIndices) } else { mask.subtract(edit.affectedIndices) }
          if edit.action == .undo { redo.append(targetID) } else { undo.append(targetID) }
        }
      }
      edit.removedIndices = mask.sorted(); edit.undoOperationIDs = undo; edit.redoOperationIDs = redo
      snapshot.pruneRevisions.append(edit)
    }
    snapshot.presentations.append(contentsOf: presentations); snapshot.rankings.append(contentsOf: rankings)
    snapshot.trainingSnapshots.append(contentsOf: trainingSnapshots); snapshot.fits.append(contentsOf: fits)
    snapshot.activations.append(contentsOf: activations)
    snapshot.legacyImports.append(contentsOf: legacyImports)
    snapshot.selectedSourceID = selectedSourceID; snapshot.currentRoundID = currentRoundID
    snapshot.currentCandidateID = currentCandidateID; snapshot.currentPruneRevisionID = currentPruneRevisionID
    snapshot.activeFitID = activeFitID; snapshot.currentPresentationID = currentPresentationID; snapshot.revision = revision
  }
}
