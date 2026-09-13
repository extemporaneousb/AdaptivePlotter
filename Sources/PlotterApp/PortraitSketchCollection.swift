import Foundation
import Observation
import PlotterModel

struct PortraitSavedSketch: Identifiable, Sendable {
  let candidate: PortraitCandidate
  var id: String { candidate.id }
  var program: DrawingProgram { candidate.program }
  var title: String { "\(candidate.recipe.title) · \(candidate.program.strokes.count) strokes" }
  var photoID: UUID { candidate.photoID }
  var recipe: PortraitStyleRecipe { candidate.recipe }
}

/// The only observable archive owner. Qualified candidates and labels have no
/// FIFO limit; recent capture/cache budgets are deliberately unrelated.
@Observable @MainActor
final class PortraitSketchCollection {
  private(set) var archive = PortraitCandidateArchive()
  var selectedID: String?
  var entries: [PortraitRetainedCandidate] { archive.entries }
  var labels: [PortraitLabelRevision] { archive.labels }
  var tombstones: [PortraitArchiveTombstone] { archive.tombstones }
  var sketches: [PortraitSavedSketch] { entries.map { .init(candidate: $0.candidate) } }
  var selected: PortraitSavedSketch? { sketches.first { $0.id == selectedID } }
  private(set) var persistenceState: PortraitPersistenceState = .saved
  private(set) var retainedBytes = 0
  private(set) var unresolvedMutations = 0
  private(set) var persistenceIssues: [String] = []
  @ObservationIgnored private let store: PortraitCandidateStore?
  @ObservationIgnored private var pending: [Mutation] = []
  @ObservationIgnored private var worker: Task<Void, Never>?
  @ObservationIgnored private var pendingCleanupBytes = 0
  @ObservationIgnored private var pendingCleanupCount = 0
  @ObservationIgnored private var hasLoaded: Bool

  init(store: PortraitCandidateStore? = nil) {
    self.store = store
    hasLoaded = store == nil
    if store != nil { persistenceState = .loading }
  }

  func load() async {
    startWorker()
    await worker?.value
  }

  @discardableResult
  func retain(candidate: PortraitCandidate, reason: PortraitRetentionReason) -> String? {
    do {
      try candidate.validateIntegrity()
      enqueue(.retain(candidate, .init(reason: reason)))
      selectedID = candidate.id
      return nil
    } catch { return error.localizedDescription }
  }

  @discardableResult
  func rate(candidate: PortraitCandidate, rating: Int, scope: PortraitStyleScope,
    presentation: PortraitPresentationContext) -> String? {
    do {
      try candidate.validateIntegrity()
      let previous = labels.last { $0.candidateID == candidate.id && $0.scope.id == scope.id
        && $0.presentation.physicalAttemptID == presentation.physicalAttemptID
        && !archive.withdrawnLabelIDs.contains($0.id.uuidString) }
      let label = try PortraitLabelRevision(candidate: candidate, rating: rating, scope: scope,
        presentation: presentation, previousRevisionID: previous?.id)
      try PortraitArchiveValidation.label(label, candidate: candidate)
      enqueue(.rate(candidate, label, .init(reason: .rated(labelRevisionID: label.id))))
      return nil
    } catch { return error.localizedDescription }
  }

  func remove(_ id: String) {
    guard let candidate = entries.first(where: { $0.id == id })?.candidate else { return }
    enqueue(.delete(.init(id: UUID(), kind: .candidate, identity: id,
      affectedCandidateIDs: [id], assetSHA256s: [candidate.sourceSHA256, candidate.rasterSHA256], createdAt: Date())))
    if selectedID == id { selectedID = nil }
  }

  func deleteSource(_ sourceSHA256: String) {
    let affected = entries.filter { $0.candidate.sourceSHA256 == sourceSHA256 }
    guard !affected.isEmpty else { return }
    enqueue(.delete(.init(id: UUID(), kind: .source, identity: sourceSHA256,
      affectedCandidateIDs: affected.map(\.id),
      assetSHA256s: [sourceSHA256] + affected.map { $0.candidate.rasterSHA256 }, createdAt: Date())))
    if let selectedID, affected.contains(where: { $0.id == selectedID }) { self.selectedID = nil }
  }

  func withdrawLabel(_ id: UUID) {
    guard let label = labels.first(where: { $0.id == id }),
      !archive.withdrawnLabelIDs.contains(id.uuidString) else { return }
    enqueue(.delete(.init(id: UUID(), kind: .label, identity: id.uuidString,
      affectedCandidateIDs: [label.candidateID], assetSHA256s: [], createdAt: Date())))
  }

  func retryPersistence() {
    guard worker == nil else { return }
    // Reload before retry so repaired assets/index are verified and retained
    // disk records are merged before replaying the still-pending mutations.
    if store != nil { hasLoaded = false }
    startWorker()
  }

  func awaitPersistence() async {
    await worker?.value
  }

  private enum Mutation {
    case retain(PortraitCandidate, PortraitRetentionEvent)
    case rate(PortraitCandidate, PortraitLabelRevision, PortraitRetentionEvent)
    case delete(PortraitArchiveTombstone)

    func apply(to archive: inout PortraitCandidateArchive) {
      switch self {
      case .retain(let candidate, let event): Self.retain(candidate, event: event, in: &archive)
      case .rate(let candidate, let label, let event):
        Self.retain(candidate, event: event, in: &archive)
        if !archive.labels.contains(where: { $0.id == label.id }) { archive.labels.append(label) }
      case .delete(let requested):
        let affected = archive.entries.filter { requested.affectedCandidateIDs.contains($0.id)
          || (requested.kind == .source && $0.candidate.sourceSHA256 == requested.identity) }
        let tombstone = PortraitArchiveTombstone(id: requested.id, kind: requested.kind,
          identity: requested.identity,
          affectedCandidateIDs: Array(Set(requested.affectedCandidateIDs + affected.map(\.id))).sorted(),
          assetSHA256s: requested.kind == .label ? [] : Array(Set(requested.assetSHA256s
            + affected.flatMap { [$0.candidate.sourceSHA256, $0.candidate.rasterSHA256] })).sorted(),
          createdAt: requested.createdAt)
        if let index = archive.tombstones.firstIndex(where: { $0.id == tombstone.id }) {
          archive.tombstones[index] = tombstone
        } else { archive.tombstones.append(tombstone) }
        if tombstone.kind != .label {
          archive.entries.removeAll { tombstone.affectedCandidateIDs.contains($0.id) }
        }
      }
    }

    private static func retain(_ candidate: PortraitCandidate, event: PortraitRetentionEvent,
      in archive: inout PortraitCandidateArchive) {
      if let index = archive.entries.firstIndex(where: { $0.id == candidate.id }) {
        if !archive.entries[index].reasons.contains(where: { $0.reason == event.reason }) {
          archive.entries[index].reasons.append(event)
        }
      } else { archive.entries.append(.init(candidate: candidate, reasons: [event])) }
    }
  }

  private func enqueue(_ mutation: Mutation) {
    mutation.apply(to: &archive)
    pending.append(mutation)
    unresolvedMutations = pending.count + pendingCleanupCount
    updateRetainedBytes()
    persistenceState = .pending
    startWorker()
  }

  private func startWorker() {
    guard worker == nil else { return }
    worker = Task { await drain() }
  }

  private func drain() async {
    defer { worker = nil }
    if !hasLoaded, let store {
      persistenceState = .loading
      let loaded = await store.load()
      persistenceIssues = loaded.issues
      pendingCleanupCount = loaded.pendingCleanupCount
      pendingCleanupBytes = loaded.pendingCleanupBytes
      unresolvedMutations = pending.count + pendingCleanupCount
      if loaded.canWrite {
        archive = loaded.archive
        for mutation in pending { mutation.apply(to: &archive) }
        hasLoaded = true
        updateRetainedBytes()
      } else {
        // Healthy recovered records remain accessible without discarding any
        // new authoring candidate or failed mutation already held in memory.
        var recovered = loaded.archive
        for entry in archive.entries where !recovered.entries.contains(where: { $0.id == entry.id }) {
          recovered.entries.append(entry)
        }
        for label in archive.labels where !recovered.labels.contains(where: { $0.id == label.id }) {
          recovered.labels.append(label)
        }
        for tombstone in archive.tombstones where !recovered.tombstones.contains(where: { $0.id == tombstone.id }) {
          recovered.tombstones.append(tombstone)
        }
        for mutation in pending { mutation.apply(to: &recovered) }
        archive = recovered
        updateRetainedBytes()
        persistenceState = .failed(loaded.issues.joined(separator: " "))
        return
      }
    }
    while !pending.isEmpty {
      let snapshot = archive
      let mutationCount = pending.count
      persistenceState = .pending
      do {
        if let store { try await store.save(snapshot: snapshot) }
        pending.removeFirst(mutationCount)
        unresolvedMutations = pending.count + pendingCleanupCount
      } catch {
        persistenceState = .failed(error.localizedDescription)
        return
      }
    }
    persistenceState = .saved
  }

  private func updateRetainedBytes() {
    if let bytes = try? PortraitCandidateStore.retainedByteCount(snapshot: archive) {
      retainedBytes = bytes + pendingCleanupBytes
    }
  }
}
