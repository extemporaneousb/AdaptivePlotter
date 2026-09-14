import Foundation
import Observation

/// One quiet observable owner for durable style/checkpoint selection and bounded fits.
@Observable @MainActor
final class PortraitTrainingLibrary {
  private(set) var snapshot = PortraitCheckpointLibrarySnapshot()
  private(set) var issues: [String] = []
  private(set) var status = "No fitted style is active."
  private(set) var isWorking = false
  private(set) var isFitting = false
  private(set) var canWrite = false
  private(set) var pendingCheckpointID: String?
  @ObservationIgnored private let store: PortraitCheckpointStore?
  @ObservationIgnored private var fitWorker: Task<PortraitPreferenceCheckpoint, Error>?
  @ObservationIgnored private var epoch: UInt64 = 0
  @ObservationIgnored private var closed = false

  init(store: PortraitCheckpointStore? = nil) { self.store = store }
  var scopes: [PortraitTrainingScopeDefinition] { snapshot.scopes }
  var checkpoints: [PortraitPreferenceCheckpoint] { snapshot.checkpoints }
  func scope(_ id: UUID) -> PortraitTrainingScopeDefinition? { scopes.first { $0.id == id } }
  func checkpoint(_ id: String?) -> PortraitPreferenceCheckpoint? {
    guard let id else { return nil }; return checkpoints.first { $0.id == id }
  }
  func activeCheckpoint(for scopeID: UUID) -> PortraitPreferenceCheckpoint? {
    checkpoint(snapshot.activeCheckpointIDs[scopeID.uuidString])
  }

  func load() async {
    guard !isWorking, !closed, let store else { return }
    isWorking = true
    let result = await store.load()
    snapshot = result.snapshot; issues = result.issues; canWrite = result.canWrite
    status = result.issues.isEmpty ? "Style checkpoints loaded. Activation affects future drawings."
      : "Some training assets are unavailable. The renderer prior remains usable."
    isWorking = false
  }

  func saveScope(_ definition: PortraitTrainingScopeDefinition) async throws {
    guard !closed, !isWorking, canWrite, let store else {
      throw PortraitTrainingError.storage("Load or repair training storage before saving a style.")
    }
    isWorking = true; defer { isWorking = false }
    try PortraitTrainingValidation.scope(definition)
    snapshot = try await store.saveScope(definition)
    status = "Saved named style: " + definition.scope.name
  }

  /// The caller joins qualified candidate persistence before passing this frozen archive.
  func train(scopeID: UUID, archive: PortraitCandidateArchive,
    configuration: PortraitOrdinalFitConfiguration = .standard) async {
    guard !closed, !isWorking, canWrite, let store, let scope = scope(scopeID) else {
      status = "Select a saved scope and repair any training storage error before fitting."
      return
    }
    isWorking = true; isFitting = true; epoch &+= 1
    let revision = epoch, parent = activeCheckpoint(for: scopeID)
    status = parent == nil ? "Fitting scoped ratings…" : "Refitting an updated dataset from the completed parent…"
    let worker = Task.detached(priority: .userInitiated) {
      try Task.checkCancellation()
      let dataset = try PortraitPreferenceDatasetBuilder.freeze(archive: archive, scope: scope, seed: configuration.seed)
      return try await PortraitOrdinalTrainer.fit(dataset: dataset, parent: parent, configuration: configuration)
    }
    fitWorker = worker
    defer {
      fitWorker = nil; isWorking = false; isFitting = false
      if revision != epoch, !closed { status = "Fit cancelled. The previous checkpoint remains active." }
    }
    do {
      let checkpoint = try await worker.value
      guard revision == epoch, !closed else { return }
      // A completed model may be installed during a late cancel, but is never
      // activated implicitly. The previous active checkpoint is untouched.
      snapshot = try await store.install(checkpoint)
      guard revision == epoch, !closed else { return }
      pendingCheckpointID = checkpoint.id
      status = "Fit saved. Compare it, then activate it for future candidates."
      issues = checkpoint.payload.evaluation.limitations
    } catch is CancellationError {
      status = "Fit cancelled. The previous completed checkpoint remains active."
    } catch {
      status = error.localizedDescription
    }
  }

  func cancel() {
    guard isFitting else { return }
    epoch &+= 1; fitWorker?.cancel()
    status = "Cancelling fit; the active checkpoint is unchanged."
  }

  func activate(_ checkpointID: String?, scopeID: UUID) async {
    guard !closed, !isWorking, canWrite, let store else {
      status = "Training storage is busy or unavailable."; return
    }
    isWorking = true; defer { isWorking = false }
    do {
      snapshot = try await store.activate(checkpointID, scopeID: scopeID)
      status = checkpointID == nil ? "Renderer prior active for future candidates."
        : "Checkpoint active for future candidates; existing drawings are unchanged."
    } catch { status = error.localizedDescription }
  }

  func rollback(scopeID: UUID) async {
    let parent = activeCheckpoint(for: scopeID)?.payload.parentCheckpointID
    await activate(parent, scopeID: scopeID)
  }

  func shutdown() async {
    closed = true; epoch &+= 1; fitWorker?.cancel()
    _ = try? await fitWorker?.value
    // The store actor serializes index/asset mutations. This read joins any
    // already-owned installation or activation before shutdown returns.
    if let store { _ = await store.load() }
  }

  static func defaultStore() -> PortraitCheckpointStore {
    let base = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support", isDirectory: true)
    return PortraitCheckpointStore(directory: base.appendingPathComponent("AdaptivePlotter/PortraitTraining", isDirectory: true))
  }
}
