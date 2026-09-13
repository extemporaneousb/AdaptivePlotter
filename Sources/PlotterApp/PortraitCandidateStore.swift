import Foundation
import PlotterModel

struct PortraitRetainedCandidate: Identifiable, Codable, Sendable {
  var candidate: PortraitCandidate
  var reasons: [PortraitRetentionEvent]
  var id: String { candidate.id }
}

struct PortraitArchiveTombstone: Identifiable, Codable, Hashable, Sendable {
  enum Kind: String, Codable, Sendable { case candidate, source, label }
  let id: UUID
  let kind: Kind
  let identity: String
  let affectedCandidateIDs: [String]
  let assetSHA256s: [String]
  let createdAt: Date
}

struct PortraitCandidateArchive: Codable, Sendable {
  var entries: [PortraitRetainedCandidate] = []
  var labels: [PortraitLabelRevision] = []
  var tombstones: [PortraitArchiveTombstone] = []

  var withdrawnLabelIDs: Set<String> {
    let explicit = Set(tombstones.filter { $0.kind == .label }.map(\.identity))
    let deleted = labels.filter { label in
      tombstones.contains { $0.kind != .label && $0.affectedCandidateIDs.contains(label.candidateID)
        && label.createdAt <= $0.createdAt }
    }.map { $0.id.uuidString }
    return explicit.union(deleted)
  }
}

enum PortraitPersistenceState: Equatable, Sendable {
  case loading, pending, saved, failed(String)
}

struct PortraitCandidateStoreLoadResult: Sendable {
  let archive: PortraitCandidateArchive
  let issues: [String]
  let canWrite: Bool
  var pendingCleanupCount = 0
  var pendingCleanupBytes = 0
}

enum PortraitCandidateStoreError: Error, LocalizedError {
  case invalidIndex(String), invalidAsset(String), unsupportedVersion(Int)
  var errorDescription: String? {
    switch self {
    case .invalidIndex(let reason): "The portrait archive index is unavailable: \(reason)"
    case .invalidAsset(let identity): "The portrait asset is missing or corrupt: \(identity)"
    case .unsupportedVersion(let version): "Portrait archive version \(version) is unsupported."
    }
  }
}

enum PortraitArchiveValidation {
  static func label(_ label: PortraitLabelRevision, candidate: PortraitCandidate? = nil) throws {
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

/// One serialized installer owns source/analysis blobs and the checksummed index.
/// A committed index never refers to an asset that this installer has not verified.
actor PortraitCandidateStore {
  nonisolated let directoryURL: URL
  private var writeBlock: String?
  private var hasInspected = false
  private let removeAsset: @Sendable (URL) throws -> Void

  init(directoryURL: URL,
    removeAsset: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) {
    self.directoryURL = directoryURL
    self.removeAsset = removeAsset
  }

  nonisolated static func defaultStore() -> PortraitCandidateStore {
    // Never silently substitute temporary storage for durable application data.
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return PortraitCandidateStore(directoryURL: base.appendingPathComponent("AdaptivePlotter/PortraitCandidates", isDirectory: true))
  }

  private var indexURL: URL { directoryURL.appendingPathComponent("index-v1.json") }
  private var blobDirectory: URL { directoryURL.appendingPathComponent("assets", isDirectory: true) }

  func load() -> PortraitCandidateStoreLoadResult {
    hasInspected = true
    let manager = FileManager.default
    guard manager.fileExists(atPath: directoryURL.path) else {
      writeBlock = nil
      return .init(archive: .init(), issues: [], canWrite: true)
    }
    var isDirectory: ObjCBool = false
    guard manager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      return failedLoad("The archive location is not a directory.")
    }
    do {
      let children = try manager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
      var issues = children.filter { $0.lastPathComponent.hasPrefix("staging-") }
        .map { "Interrupted save retained at \($0.lastPathComponent)." }
      guard manager.fileExists(atPath: indexURL.path) else {
        let orphans = try assetNames()
        issues += orphans.map { "Unassociated asset \($0) retained for recovery." }
        writeBlock = nil
        return .init(archive: .init(), issues: issues, canWrite: true)
      }
      let envelope = try JSONDecoder().decode(IndexEnvelope.self, from: Data(contentsOf: indexURL))
      guard envelope.schemaVersion == 1 else { throw PortraitCandidateStoreError.unsupportedVersion(envelope.schemaVersion) }
      guard PortraitCandidateCoding.digest(envelope.payload) == envelope.sha256 else {
        throw PortraitCandidateStoreError.invalidIndex("checksum mismatch; original file preserved")
      }
      let stored = try JSONDecoder().decode(StoredArchive.self, from: envelope.payload)
      guard stored.schemaVersion == 1 else { throw PortraitCandidateStoreError.unsupportedVersion(stored.schemaVersion) }
      var entries: [PortraitRetainedCandidate] = []
      var referenced = Set<String>()
      var missing = false
      for entry in stored.entries {
        referenced.insert(entry.candidate.sourceSHA256)
        referenced.insert(entry.candidate.rasterSHA256)
        do {
          let candidate = try entry.candidate.materialize(
            source: readAsset(entry.candidate.sourceSHA256),
            raster: readAsset(entry.candidate.rasterSHA256))
          entries.append(.init(candidate: candidate, reasons: entry.reasons))
        } catch {
          // Preserve the damaged index and all healthy candidates. A partial
          // recovery is visible and cannot overwrite the missing record.
          missing = true
          issues.append("Candidate \(entry.candidate.id) is unavailable: \(error.localizedDescription)")
        }
      }
      try validateLabels(stored.labels, entries: stored.entries)
      // The committed tombstone is deletion authority after a crash too. Finish
      // payload cleanup before reporting the archive saved, preserving every
      // blob still referenced even by an unavailable candidate.
      let cleanup = try cleanupDeletedAssets(stored.tombstones, referenced: referenced)
      issues += cleanup.issues
      issues += try assetNames().filter { !referenced.contains($0) }
        .map { "Unassociated asset \($0) retained for recovery." }
      var blockers: [String] = []
      if missing { blockers.append("Repair missing/corrupt portrait assets before saving this archive; the original index is preserved.") }
      if cleanup.count > 0 { blockers.append("Explicit asset deletion is unfinished; retry archive save to finish cleanup.") }
      writeBlock = blockers.isEmpty ? nil : blockers.joined(separator: " ")
      return .init(archive: .init(entries: entries, labels: stored.labels, tombstones: stored.tombstones),
        issues: issues, canWrite: writeBlock == nil,
        pendingCleanupCount: cleanup.count, pendingCleanupBytes: cleanup.bytes)
    } catch {
      return failedLoad(error.localizedDescription)
    }
  }

  private func failedLoad(_ message: String) -> PortraitCandidateStoreLoadResult {
    writeBlock = message
    return .init(archive: .init(), issues: [message], canWrite: false)
  }

  func save(snapshot: PortraitCandidateArchive) throws {
    if !hasInspected { _ = load() }
    if let writeBlock { throw PortraitCandidateStoreError.invalidIndex(writeBlock) }
    let manager = FileManager.default
    try manager.createDirectory(at: blobDirectory, withIntermediateDirectories: true)
    let encoder = PortraitCandidateCoding.encoder()
    for entry in snapshot.entries {
      try entry.candidate.validateIntegrity()
      try install(entry.candidate.sourceData, hash: entry.candidate.sourceSHA256)
      try install(try encoder.encode(entry.candidate.raster), hash: entry.candidate.rasterSHA256)
    }
    let stored = StoredArchive(snapshot)
    try validateLabels(stored.labels, entries: stored.entries)
    let payload = try encoder.encode(stored)
    let envelope = IndexEnvelope(schemaVersion: 1, sha256: PortraitCandidateCoding.digest(payload), payload: payload)
    let bytes = try encoder.encode(envelope)
    // A crash before index replacement leaves either an unassociated verified
    // blob or this explicit staging file. Neither looks like a committed save.
    let staging = directoryURL.appendingPathComponent("staging-\(UUID().uuidString).json")
    try bytes.write(to: staging, options: .atomic)
    let handle = try FileHandle(forWritingTo: staging)
    try handle.synchronize()
    try handle.close()
    try bytes.write(to: indexURL, options: .atomic)
    let indexHandle = try FileHandle(forWritingTo: indexURL)
    try indexHandle.synchronize()
    try indexHandle.close()
    try? manager.removeItem(at: staging)
    // Explicit deletion removes unreferenced assets after the tombstone/index
    // commit. Interrupted cleanup is reported on the next load and never risks
    // references to blobs already deleted before their index update.
    let referenced = Set(snapshot.entries.flatMap { [$0.candidate.sourceSHA256, $0.candidate.rasterSHA256] })
    let cleanup = try cleanupDeletedAssets(snapshot.tombstones, referenced: referenced)
    if cleanup.count > 0 { throw PortraitCandidateStoreError.invalidIndex(cleanup.issues.joined(separator: " ")) }
  }

  private func cleanupDeletedAssets(_ tombstones: [PortraitArchiveTombstone],
    referenced: Set<String>) throws -> (count: Int, bytes: Int, issues: [String]) {
    var count = 0, bytes = 0
    var issues: [String] = []
    let manager = FileManager.default
    for hash in Set(tombstones.flatMap(\.assetSHA256s)).subtracting(referenced).sorted() {
      guard validHash(hash) else { throw PortraitCandidateStoreError.invalidAsset(hash) }
      let url = blobDirectory.appendingPathComponent(hash)
      guard manager.fileExists(atPath: url.path) else { continue }
      do { try removeAsset(url) }
      catch {
        count += 1
        let attributes = try? manager.attributesOfItem(atPath: url.path)
        bytes += (attributes?[.size] as? NSNumber)?.intValue ?? 0
        issues.append("Deletion of asset \(hash) is pending: \(error.localizedDescription)")
      }
    }
    return (count, bytes, issues)
  }

  nonisolated static func retainedByteCount(snapshot: PortraitCandidateArchive) throws -> Int {
    let encoder = PortraitCandidateCoding.encoder()
    var assets: [String: Int] = [:]
    for entry in snapshot.entries {
      assets[entry.candidate.sourceSHA256] = entry.candidate.sourceData.count
      assets[entry.candidate.rasterSHA256] = try encoder.encode(entry.candidate.raster).count
    }
    let payload = try encoder.encode(StoredArchive(snapshot))
    let envelope = IndexEnvelope(schemaVersion: 1, sha256: PortraitCandidateCoding.digest(payload), payload: payload)
    return try encoder.encode(envelope).count + assets.values.reduce(0, +)
  }

  private func validateLabels(_ labels: [PortraitLabelRevision], entries: [StoredEntry]) throws {
    guard Set(labels.map(\.id)).count == labels.count,
      Set(entries.map { $0.candidate.id }).count == entries.count else {
      throw PortraitCandidateStoreError.invalidIndex("duplicate candidate or label identity")
    }
    for label in labels {
      try PortraitArchiveValidation.label(label)
      if let previous = label.previousRevisionID {
        guard let predecessor = labels.first(where: { $0.id == previous }),
          predecessor.id != label.id, predecessor.candidateID == label.candidateID,
          predecessor.scope.id == label.scope.id else {
          throw PortraitCandidateStoreError.invalidIndex("invalid label revision ancestry")
        }
      }
      if let candidate = entries.first(where: { $0.candidate.id == label.candidateID })?.candidate,
        (candidate.program.contentHash.description != label.programContentHash
          || !label.scope.allowedFamilies.contains(candidate.recipe.style)) {
        throw PortraitCandidateStoreError.invalidIndex("label program identity mismatch")
      }
    }
  }

  private func assetNames() throws -> [String] {
    guard FileManager.default.fileExists(atPath: blobDirectory.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(atPath: blobDirectory.path).sorted()
  }

  private func validHash(_ hash: String) -> Bool {
    hash.count == 64 && hash.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }

  private func readAsset(_ hash: String) throws -> Data {
    guard validHash(hash) else { throw PortraitCandidateStoreError.invalidAsset(hash) }
    let data = try Data(contentsOf: blobDirectory.appendingPathComponent(hash))
    guard PortraitCandidateCoding.digest(data) == hash else { throw PortraitCandidateStoreError.invalidAsset(hash) }
    return data
  }

  private func install(_ data: Data, hash: String) throws {
    guard validHash(hash), PortraitCandidateCoding.digest(data) == hash else {
      throw PortraitCandidateStoreError.invalidAsset(hash)
    }
    let url = blobDirectory.appendingPathComponent(hash)
    if FileManager.default.fileExists(atPath: url.path) { _ = try readAsset(hash); return }
    try data.write(to: url, options: .atomic)
    let handle = try FileHandle(forWritingTo: url)
    try handle.synchronize()
    try handle.close()
    _ = try readAsset(hash)
  }
}

private struct IndexEnvelope: Codable {
  let schemaVersion: Int
  let sha256: String
  let payload: Data
}

private struct StoredArchive: Codable {
  let schemaVersion: Int
  let entries: [StoredEntry]
  let labels: [PortraitLabelRevision]
  let tombstones: [PortraitArchiveTombstone]
  init(_ archive: PortraitCandidateArchive) {
    schemaVersion = 1
    entries = archive.entries.map { StoredEntry(candidate: StoredCandidate($0.candidate), reasons: $0.reasons) }
    labels = archive.labels
    tombstones = archive.tombstones
  }
}

private struct StoredEntry: Codable {
  let candidate: StoredCandidate
  let reasons: [PortraitRetentionEvent]
}

/// Payload metadata only; source bytes and exact analyzed raster each have one
/// content-addressed blob, independent of candidate/label count.
private struct StoredCandidate: Codable {
  let id: String
  let sourceSHA256: String
  let rasterSHA256: String
  let recipeSHA256: String
  let sourcePixelExtent: PortraitSourceCropExtent?
  let recipe: PortraitStyleRecipe
  let program: DrawingProgram
  let photoID: UUID
  let captureSessionID: UUID
  let createdAt: Date
  let lineage: PortraitCandidateLineage
  let producerRevision: String
  let checkpointID: String?
  let pose: PortraitPose?
  let proposal: PortraitProposalMetadata?
  let warpManifest: PortraitHeadWarpManifest?

  init(_ value: PortraitCandidate) {
    id = value.id; sourceSHA256 = value.sourceSHA256; rasterSHA256 = value.rasterSHA256
    recipeSHA256 = value.recipeSHA256; sourcePixelExtent = value.sourcePixelExtent
    recipe = value.recipe; program = value.program; photoID = value.photoID
    captureSessionID = value.captureSessionID; createdAt = value.createdAt
    lineage = value.lineage; producerRevision = value.producerRevision; checkpointID = value.checkpointID; pose = value.pose; proposal = value.proposal; warpManifest = value.warpManifest
  }

  func materialize(source: Data, raster: Data) throws -> PortraitCandidate {
    let candidate = try PortraitCandidate(sourceData: source, sourcePixelExtent: sourcePixelExtent,
      raster: JSONDecoder().decode(PortraitRaster.self, from: raster), recipe: recipe,
      program: program, photoID: photoID, captureSessionID: captureSessionID,
      createdAt: createdAt, lineage: lineage, checkpointID: checkpointID, pose: pose, proposal: proposal, warpManifest: warpManifest)
    guard candidate.id == id, candidate.sourceSHA256 == sourceSHA256,
      candidate.rasterSHA256 == rasterSHA256, candidate.recipeSHA256 == recipeSHA256,
      candidate.producerRevision == producerRevision else { throw PortraitCandidateError.integrityMismatch }
    return candidate
  }
}
