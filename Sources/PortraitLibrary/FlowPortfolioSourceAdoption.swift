import Foundation

/// A presentation lease changes only navigation. Acquisition durability is independent.
package struct FlowPortfolioSourceAdoption: Sendable {
  let id: UUID
  let previousOwner: UUID
  let previous: FlowPortfolioSelection
  let adopted: FlowPortfolioSelection
}

struct FlowPortfolioSelection: Equatable, Sendable {
  let source: UUID?
  let round: UUID?
  let candidate: UUID?
  let prune: UUID?
  init(_ snapshot: FlowPortfolioSnapshot) {
    source = snapshot.selectedSourceID; round = snapshot.currentRoundID
    candidate = snapshot.currentCandidateID; prune = snapshot.currentPruneRevisionID
  }
  func apply(to snapshot: inout FlowPortfolioSnapshot) {
    snapshot.selectedSourceID = source; snapshot.currentRoundID = round
    snapshot.currentCandidateID = candidate; snapshot.currentPruneRevisionID = prune
  }
}

extension FlowPortfolioStore {
  package func setSourceAdoptionDidPersistHook(_ hook: (@Sendable () async -> Void)?) {
    sourceAdoptionDidPersist = hook
  }
  /// Prepare before the throwing write so its caller can retain the lease through recovery.
  package func prepareSourceAdoption(_ id: UUID) throws -> FlowPortfolioSourceAdoption {
    guard state.sources.contains(where: { $0.id == id }) else {
      throw FlowPortfolioError.unavailable("Portfolio photograph is unavailable.")
    }
    var selected = state; selected.selectedSourceID = id
    let options = selected.sources.first(where: { $0.id == id })?.authoringOptions
    selected.currentRoundID = selected.rounds.last(where: {
      $0.sourceID == id && (options == nil || $0.analysisOptions == options)
    })?.id
    selected.currentCandidateID = selected.choices.last(where: { $0.roundID == selected.currentRoundID })?.candidateID
    selected.currentPruneRevisionID = selected.currentCandidateID.flatMap { selected.latestPrune(candidateID: $0)?.id }
    return .init(id: UUID(), previousOwner: selectionOwner,
      previous: .init(state), adopted: .init(selected))
  }

  package func selectSourceForPresentation(_ lease: FlowPortfolioSourceAdoption) async throws {
    if selectionOwner == lease.id, FlowPortfolioSelection(state) == lease.adopted { return }
    guard selectionOwner == lease.previousOwner, FlowPortfolioSelection(state) == lease.previous else {
      throw FlowPortfolioError.conflict("A newer navigation intent owns the photograph selection.")
    }
    var next = state; lease.adopted.apply(to: &next)
    try await commit(next,
      selectionOwner: lease.id)
    await sourceAdoptionDidPersist?()
  }

  /// A stale admitted write may settle durably. Restore only its four selection
  /// fields, without reverting imported sources, feedback or unrelated graph writes.
  @discardableResult package func restoreSelectionIfUnchanged(_ lease: FlowPortfolioSourceAdoption) async throws -> Bool {
    if selectionOwner == lease.id, FlowPortfolioSelection(state) == lease.previous { return true }
    guard selectionOwner == lease.id, FlowPortfolioSelection(state) == lease.adopted else { return false }
    var next = state; lease.previous.apply(to: &next)
    try await commit(next, selectionOwner: lease.id)
    return true
  }
}
