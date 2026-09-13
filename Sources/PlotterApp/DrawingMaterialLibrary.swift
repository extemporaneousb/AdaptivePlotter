import Foundation
import Observation
import PlotterModel
import PlotterRuntime

/// Sole observable material settings owner. A visible local mutation is pending
/// until the serialized store confirms it; no drawing authority lives here.
@Observable @MainActor
final class DrawingMaterialLibrary {
  private(set) var records: [DrawingMaterialRecord] = []
  private(set) var activeKey: String?
  private(set) var persistenceError: String?
  private(set) var isLoading = false
  private(set) var isSaving = false
  private(set) var pendingMutationCount = 0
  var activeRecord: DrawingMaterialRecord? { records.first { $0.profile.key == activeKey } }
  var storageStatus: String {
    if isLoading { return "Loading materials…" }
    if let persistenceError { return "Material save pending: \(persistenceError)" }
    if isSaving || pendingMutationCount > 0 { return "Saving materials…" }
    if !loaded { return "Materials awaiting load." }
    return store == nil ? "Materials are in memory for this session." : "Materials saved."
  }

  @ObservationIgnored private let store: DrawingMaterialStore?
  @ObservationIgnored private var loaded: Bool
  @ObservationIgnored private var pending: [Mutation] = []
  @ObservationIgnored private var worker: Task<Void, Never>?
  @ObservationIgnored private var committed = DrawingMaterialSnapshot()

  init(store: DrawingMaterialStore? = nil) { self.store = store; loaded = store == nil }

  func nextRevision(for id: UUID) -> Int? {
    let prefix = id.uuidString.lowercased() + "@"
    var keys = Set(committed.revisionDigests.keys).union(records.map { $0.profile.key })
    for mutation in pending { if case .add(let record) = mutation { keys.insert(record.profile.key) } }
    let maximum = keys.filter { $0.hasPrefix(prefix) }.compactMap { Int($0.dropFirst(prefix.count)) }.max() ?? 0
    return maximum < Int.max ? maximum + 1 : nil
  }

  @discardableResult func add(_ record: DrawingMaterialRecord) -> String? {
    do {
      try record.validate()
      if let existing = records.first(where: { $0.profile.key == record.profile.key }) {
        return existing == record ? nil : "This material revision is immutable. Create a new revision."
      }
      return enqueue(.add(record))
    } catch { return error.localizedDescription }
  }

  @discardableResult func activate(key: String) -> String? {
    guard records.contains(where: { $0.profile.key == key }) else { return "The selected material revision is unavailable." }
    return enqueue(.activate(key))
  }

  @discardableResult func deactivate() -> String? { enqueue(.activate(nil)) }

  @discardableResult func delete(key: String) -> String? {
    guard records.contains(where: { $0.profile.key == key }) else { return "The material revision is unavailable." }
    return enqueue(.delete(key))
  }

  @discardableResult func createNominal(name: String, widthMM: Double) -> String? {
    do {
      let record = try DrawingMaterialRecord(profile: .init(name: name, nominalWidthMM: widthMM))
      if let error = add(record) { return error }
      return activate(key: record.profile.key)
    } catch { return error.localizedDescription }
  }

  func load() async { start(); await worker?.value }
  func flush() async { start(); await worker?.value }
  func retry() async { persistenceError = nil; start(); await worker?.value }

  private func enqueue(_ mutation: Mutation) -> String? {
    do {
      var visible = committed
      for queued in pending { try queued.apply(to: &visible) }
      try mutation.apply(to: &visible)
      records = visible.records; activeKey = visible.activeKey
      guard store != nil else { committed = visible; return nil }
      pending.append(mutation); pendingMutationCount = pending.count
      // An error stays visible until an explicit retry. Additional local changes
      // remain queued; they never convert an unsuccessful save into success.
      if persistenceError == nil { start() }
      return nil
    } catch { return error.localizedDescription }
  }

  private func start() {
    guard worker == nil, store != nil, persistenceError == nil, !loaded || !pending.isEmpty else { return }
    worker = Task { [weak self] in
      guard let self else { return }
      await self.drain()
    }
  }

  private func drain() async {
    defer { isLoading = false; isSaving = false; worker = nil }
    guard let store else { return }
    do {
      if !loaded {
        isLoading = true
        let disk = try await store.load()
        // Mutations accepted while loading are replayed against the real archive;
        // a conflicting identity blocks replacement instead of losing disk data.
        var combined = disk
        for mutation in pending { try mutation.apply(to: &combined) }
        committed = disk; records = combined.records; activeKey = combined.activeKey
        loaded = true; isLoading = false
      }
      while !pending.isEmpty {
        isSaving = true
        let count = pending.count
        var snapshot = committed
        for mutation in pending.prefix(count) { try mutation.apply(to: &snapshot) }
        try await store.save(snapshot)
        committed = snapshot
        pending.removeFirst(count); pendingMutationCount = pending.count
      }
    } catch { persistenceError = error.localizedDescription }
  }

  private enum Mutation {
    case add(DrawingMaterialRecord), activate(String?), delete(String)
    func apply(to snapshot: inout DrawingMaterialSnapshot) throws {
      switch self {
      case .add(let record):
        let digest = try DrawingMaterialSnapshot.digest(record)
        if let prior = snapshot.revisionDigests[record.profile.key], prior != digest {
          throw DrawingMaterialStorageError.invalid("Material revision identity is immutable, including after deletion.")
        }
        snapshot.revisionDigests[record.profile.key] = digest
        if let prior = snapshot.records.first(where: { $0.profile.key == record.profile.key }) {
          guard prior == record else { throw DrawingMaterialStorageError.invalid("A pending material conflicts with the saved immutable revision \(record.profile.key). The saved archive is preserved.") }
        } else { snapshot.records.append(record) }
      case .activate(let key):
        guard key == nil || snapshot.records.contains(where: { $0.profile.key == key }) else {
          throw DrawingMaterialStorageError.invalid("The selected material revision is unavailable.")
        }
        snapshot.activeKey = key
      case .delete(let key):
        snapshot.records.removeAll { $0.profile.key == key }
        if snapshot.activeKey == key { snapshot.activeKey = nil }
      }
    }
  }
}
