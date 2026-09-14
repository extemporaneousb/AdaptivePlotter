import Darwin
import Foundation

/// Owns complete checkpoint/dataset artifacts. Installation never activates a fit.
/// An incomplete archive remains read-only until an explicit reload can verify it.
actor PortraitCheckpointStore {
  private struct Entry: Codable {
    let id: String
    let sha256: String
    let scopeID: UUID
    let parentCheckpointID: String?
  }
  private struct Index: Codable {
    var revision = "portrait-checkpoint-library-v1"
    var scopes: [PortraitTrainingScopeDefinition] = []
    var checkpoints: [Entry] = []
    var activeCheckpointIDs: [String: String] = [:]
  }
  private struct Envelope: Codable {
    let payload: Index
    let sha256: String
  }

  private let directory: URL
  private var verified = PortraitCheckpointLibrarySnapshot()
  private var verifiedIndex = Index()

  init(directory: URL) { self.directory = directory }

  func load() -> PortraitCheckpointLibraryLoadResult {
    let indexURL = directory.appendingPathComponent("index-v1.json")
    guard FileManager.default.fileExists(atPath: indexURL.path) else {
      // Assets left by an interrupted installation remain immutable and reusable.
      // They do not implicitly create scopes or activate a checkpoint.
      verified = .init(); verifiedIndex = .init()
      return .init(snapshot: verified, issues: [], canWrite: true)
    }
    do {
      let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: indexURL))
      let bytes = try PortraitCandidateCoding.encoder().encode(envelope.payload)
      guard PortraitCandidateCoding.digest(bytes) == envelope.sha256 else {
        throw PortraitTrainingError.storage("Checkpoint index checksum does not match; its contents are preserved.")
      }
      let index = envelope.payload
      try validateIndex(index)
      var issues: [String] = []
      var checkpoints: [PortraitPreferenceCheckpoint] = []
      for entry in index.checkpoints {
        do {
          let data = try Data(contentsOf: assetURL(entry.id))
          guard PortraitCandidateCoding.digest(data) == entry.sha256 else {
            throw PortraitTrainingError.storage("Checkpoint asset checksum does not match.")
          }
          let checkpoint = try JSONDecoder().decode(PortraitPreferenceCheckpoint.self, from: data)
          try validate(checkpoint)
          guard checkpoint.id == entry.id, checkpoint.scopeID == entry.scopeID,
            checkpoint.payload.parentCheckpointID == entry.parentCheckpointID,
            index.scopes.contains(checkpoint.payload.dataset.payload.scope) else {
            throw PortraitTrainingError.incompatible("Checkpoint content does not match its index association.")
          }
          checkpoints.append(checkpoint)
        } catch { issues.append("Checkpoint \(entry.id): \(error.localizedDescription)") }
      }
      // A verified child also requires its exact healthy parent, recursively.
      var changed = true
      while changed {
        changed = false
        let available = checkpoints
        checkpoints.removeAll { child in
          guard let parentID = child.payload.parentCheckpointID else { return false }
          do {
            guard let parent = available.first(where: { $0.id == parentID }) else {
              throw PortraitTrainingError.incompatible("The installed parent is unavailable.")
            }
            try validateParent(parent, child: child)
            return false
          } catch {
            issues.append("Checkpoint \(child.id): \(error.localizedDescription)")
            changed = true
            return true
          }
        }
      }
      var active: [String: String] = [:]
      for (scopeID, checkpointID) in index.activeCheckpointIDs {
        if checkpoints.contains(where: { $0.id == checkpointID && $0.scopeID.uuidString == scopeID }) {
          active[scopeID] = checkpointID
        } else {
          issues.append("Active checkpoint \(checkpointID) is unavailable; scope \(scopeID) uses the renderer prior.")
        }
      }
      verified = .init(scopes: index.scopes, checkpoints: checkpoints, activeCheckpointIDs: active)
      verifiedIndex = index
      return .init(snapshot: verified, issues: issues, canWrite: issues.isEmpty)
    } catch {
      // Previously verified in-memory content is usable; never reinterpret an
      // unknown/corrupt index as an empty writable archive.
      return .init(snapshot: verified, issues: [error.localizedDescription], canWrite: false)
    }
  }

  func saveScope(_ scope: PortraitTrainingScopeDefinition) throws -> PortraitCheckpointLibrarySnapshot {
    try requireWritable()
    try PortraitTrainingValidation.scope(scope)
    if let existing = verified.scopes.first(where: { $0.id == scope.id }) {
      guard existing == scope else {
        throw PortraitTrainingError.incompatible("Named style scope identity is immutable; create a new scope.")
      }
      return verified
    }
    var next = verifiedIndex
    next.scopes.append(scope)
    try commit(next)
    verified.scopes.append(scope)
    return verified
  }

  func install(_ checkpoint: PortraitPreferenceCheckpoint) throws -> PortraitCheckpointLibrarySnapshot {
    try requireWritable()
    try validate(checkpoint)
    guard verified.scopes.contains(checkpoint.payload.dataset.payload.scope) else {
      throw PortraitTrainingError.incompatible("Save the exact named style scope before installing its checkpoint.")
    }
    if let parentID = checkpoint.payload.parentCheckpointID {
      guard let parent = verified.checkpoints.first(where: { $0.id == parentID }) else {
        throw PortraitTrainingError.incompatible("The exact parent checkpoint must already be installed.")
      }
      try validateParent(parent, child: checkpoint)
    }
    let bytes = try PortraitCandidateCoding.encoder().encode(checkpoint)
    if let existing = verified.checkpoints.first(where: { $0.id == checkpoint.id }) {
      guard try PortraitCandidateCoding.encoder().encode(existing) == bytes else {
        throw PortraitTrainingError.incompatible("Checkpoint identities are immutable.")
      }
      return verified
    }
    let target = assetURL(checkpoint.id)
    if FileManager.default.fileExists(atPath: target.path) {
      guard try Data(contentsOf: target) == bytes else {
        throw PortraitTrainingError.storage("An existing checkpoint asset conflicts with this identity; it is preserved.")
      }
    } else { try synchronizedAtomicWrite(bytes, to: target) }
    var next = verifiedIndex
    next.checkpoints.append(.init(id: checkpoint.id, sha256: PortraitCandidateCoding.digest(bytes),
      scopeID: checkpoint.scopeID, parentCheckpointID: checkpoint.payload.parentCheckpointID))
    try commit(next)
    verified.checkpoints.append(checkpoint)
    return verified
  }

  func activate(_ checkpointID: String?, scopeID: UUID) throws -> PortraitCheckpointLibrarySnapshot {
    try requireWritable()
    guard verified.scopes.contains(where: { $0.id == scopeID }) else {
      throw PortraitTrainingError.incompatible("The requested named style scope is not installed.")
    }
    if let checkpointID {
      guard verified.checkpoints.contains(where: { $0.id == checkpointID && $0.scopeID == scopeID }) else {
        throw PortraitTrainingError.incompatible("Activation requires a healthy checkpoint belonging to this scope.")
      }
    }
    var next = verifiedIndex
    next.activeCheckpointIDs[scopeID.uuidString] = checkpointID
    if next.activeCheckpointIDs == verifiedIndex.activeCheckpointIDs { return verified }
    try commit(next)
    verified.activeCheckpointIDs = next.activeCheckpointIDs
    return verified
  }

  private func requireWritable() throws {
    let result = load()
    guard result.canWrite else { throw PortraitTrainingError.storage(result.issues.joined(separator: " ")) }
  }

  private func validate(_ checkpoint: PortraitPreferenceCheckpoint) throws {
    guard isDigest(checkpoint.id),
      try PortraitCandidateCoding.digest(PortraitCandidateCoding.encoder().encode(checkpoint.payload)) == checkpoint.id else {
      throw PortraitTrainingError.invalid("Checkpoint content identity does not match its payload.")
    }
    try PortraitTrainingValidation.scope(checkpoint.payload.dataset.payload.scope)
    try PortraitTrainingValidation.dataset(checkpoint.payload.dataset)
    try PortraitTrainingValidation.checkpoint(checkpoint)
  }

  private func validateParent(_ parent: PortraitPreferenceCheckpoint, child: PortraitPreferenceCheckpoint) throws {
    guard parent.id != child.id,
      parent.payload.dataset.payload.scope == child.payload.dataset.payload.scope,
      parent.payload.dataset.payload.featureSchema == child.payload.dataset.payload.featureSchema,
      Set(parent.payload.producerRevisions) == Set(child.payload.producerRevisions),
      Set(parent.payload.warpRevisions) == Set(child.payload.warpRevisions) else {
      throw PortraitTrainingError.incompatible("Parent and child scope, feature schema, renderer and warp revisions must match.")
    }
  }

  private func validateIndex(_ index: Index) throws {
    guard index.revision == "portrait-checkpoint-library-v1",
      Set(index.scopes.map(\.id)).count == index.scopes.count,
      Set(index.checkpoints.map(\.id)).count == index.checkpoints.count else {
      throw PortraitTrainingError.storage("Unknown checkpoint index revision or duplicate immutable identity.")
    }
    for scope in index.scopes { try PortraitTrainingValidation.scope(scope) }
    let entries = Dictionary(uniqueKeysWithValues: index.checkpoints.map { ($0.id, $0) })
    for entry in index.checkpoints {
      guard isDigest(entry.id), isDigest(entry.sha256), index.scopes.contains(where: { $0.id == entry.scopeID }) else {
        throw PortraitTrainingError.storage("Checkpoint index has an invalid identity or unknown scope.")
      }
      var visited = Set([entry.id])
      var parentID = entry.parentCheckpointID
      while let id = parentID {
        guard visited.insert(id).inserted, let parent = entries[id], parent.scopeID == entry.scopeID else {
          throw PortraitTrainingError.storage("Checkpoint index has a cyclic, missing or cross-scope parent.")
        }
        parentID = parent.parentCheckpointID
      }
    }
    for (scopeID, checkpointID) in index.activeCheckpointIDs {
      guard let scope = index.scopes.first(where: { $0.id.uuidString == scopeID }),
        let entry = entries[checkpointID], entry.scopeID == scope.id else {
        throw PortraitTrainingError.storage("Checkpoint index has an impossible activation association.")
      }
    }
  }

  private func commit(_ index: Index) throws {
    try validateIndex(index)
    let bytes = try PortraitCandidateCoding.encoder().encode(index)
    let envelope = Envelope(payload: index, sha256: PortraitCandidateCoding.digest(bytes))
    try synchronizedAtomicWrite(PortraitCandidateCoding.encoder().encode(envelope),
      to: directory.appendingPathComponent("index-v1.json"))
    verifiedIndex = index
  }

  private func assetURL(_ id: String) -> URL {
    directory.appendingPathComponent("checkpoints", isDirectory: true).appendingPathComponent(id + ".json")
  }

  private func isDigest(_ value: String) -> Bool {
    value.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) }
  }

  private func synchronizedAtomicWrite(_ data: Data, to destination: URL) throws {
    let parent = destination.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let temporary = parent.appendingPathComponent(".checkpoint-\(UUID().uuidString).tmp")
    defer { try? FileManager.default.removeItem(at: temporary) }
    try data.write(to: temporary, options: .withoutOverwriting)
    let handle = try FileHandle(forWritingTo: temporary)
    do { try handle.synchronize(); try handle.close() }
    catch { try? handle.close(); throw error }
    guard rename(temporary.path, destination.path) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }
}
