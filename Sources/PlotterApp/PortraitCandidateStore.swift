import Darwin
import Foundation
import PlotterRuntime
import PlotterModel

struct PortraitRetainedCandidate: Identifiable, Codable, Sendable {
  var candidate: PortraitCandidate
  var reasons: [PortraitRetentionEvent]
  var exploration: [PortraitExplorationRecord]? = nil
  var attempt: PortraitAttemptRecord? = nil
  var id: String { candidate.id }
}

struct PortraitArchiveTombstone: Identifiable, Codable, Hashable, Sendable {
  enum Kind: String, Codable, Sendable { case candidate, drawing, source, photo, label }
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
  var savedStyles: [PortraitSavedStyle]? = nil
  var sourcePhotos: [PortraitPhoto]? = nil
  var savedDrawings: [SavedDrawing]? = nil
  var labelPhotoIDs: [String:UUID]? = nil
  var photoCaptureTimeUnknownIDs: [UUID]? = nil

  var withdrawnLabelIDs: Set<String> {
    let explicit = Set(tombstones.filter { $0.kind == .label }.map(\.identity))
    let deleted = labels.filter { label in
      tombstones.contains { tombstone in
        let photo = labelPhotoIDs?[label.id.uuidString.lowercased()]
        if tombstone.kind == .photo { return photo == UUID(uuidString:tombstone.identity) }
        if tombstone.kind == .drawing,let photo {
          return tombstone.identity.lowercased() == PortraitDrawingIdentity(candidateID:label.candidateID,photoID:photo).id
            && label.createdAt <= tombstone.createdAt
        }
        return tombstone.kind != .label && tombstone.affectedCandidateIDs.contains(label.candidateID)
          && label.createdAt <= tombstone.createdAt
      }
    }.map { $0.id.uuidString }
    return explicit.union(deleted)
  }
}

enum PortraitPersistenceState: Equatable, Sendable {
  case loading, pending, saved, failed(String)
}

enum PortraitCandidateSaveMode: Sendable {
  case fullArchive, mutationDelta
}

struct PortraitCandidateStoreLoadResult: Sendable {
  let archive: PortraitCandidateArchive
  let issues: [String]
  let canWrite: Bool
  var pendingCleanupCount = 0
  var pendingCleanupBytes = 0
  var retainedBytes: Int? = nil
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

/// One serialized installer owns source/analysis blobs and the checksummed index.
/// A committed index never refers to an asset that this installer has not verified.
actor PortraitCandidateStore {
  nonisolated let directoryURL: URL
  private(set) var evidenceArchiveURL: URL?
  nonisolated let legacyDirectoryURL: URL
  private var installingCanonical = false
  private var database: PortraitLibraryDatabase?
  private var committedGeneration: PortraitLibraryGeneration?
  var evidenceRecordHashes: [UUID:(DrawingRunEvidenceRecord,String)] = [:]
  var evidenceAttemptHashes: [UUID:(DrawingRunAttemptState,String)] = [:]
  var durableCandidateCache: [String:PortraitCandidate] = [:]
  var durableCandidateFiles: [String:[URL:VerifiedFileState]] = [:]
  var projectionMediaFiles: [URL:VerifiedFileState] = [:]
  private var legacyReadOnly = false
  private var legacyReadRootOverride: URL?
  private var verifiedLegacyImportSHA256: String?
  private var writeBlock: String?
  private var fullHistoryWriteBlock: String?
  private var hasInspected = false
  private var loadedRecordHash: String?
  private var drawingRecords: [String: String] = [:]
  private var verifiedDrawings: [String: SavedDrawing] = [:]
  private var candidateRecords: [String: String] = [:]
  private var metadataRecords: [String: String] = [:]
  private var verifiedMetadata: [String: EntryMetadata] = [:]
  private var labelRecords: [UUID: String] = [:]
  private var verifiedLabels: [UUID: PortraitLabelRevision] = [:]
  private var verifiedCandidates: [String: PortraitCandidate] = [:]
  private var verifiedPhotos: [UUID: (photo: PortraitPhoto, hash: String)] = [:]
  private var verifiedFiles: [URL: VerifiedFileState] = [:]
  private var fileByteCounts: [URL: Int] = [:]
  private var committedIndexState: VerifiedFileState?
  private var lastReadIndexState: VerifiedFileState?
  private(set) var recordBytesEncoded = 0
  private(set) var metadataBytesEncoded = 0
  private(set) var assetBytesVerified = 0
  private let removeAsset: @Sendable (URL) throws -> Void

  init(directoryURL: URL, legacyDirectoryURL: URL? = nil, evidenceArchiveURL: URL? = nil,
    removeAsset: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) {
    self.directoryURL = directoryURL
    self.evidenceArchiveURL = evidenceArchiveURL
    self.legacyDirectoryURL = legacyDirectoryURL ?? directoryURL
    self.removeAsset = removeAsset
  }

  nonisolated static func defaultStore() -> PortraitCandidateStore {
    // Never silently substitute temporary storage for durable application data.
    return PortraitCandidateStore(directoryURL: AdaptivePlotterStoragePaths.production.portraitLibraryDirectory,
      legacyDirectoryURL: AdaptivePlotterStoragePaths.production.portraitCandidatesDirectory,
      evidenceArchiveURL: AdaptivePlotterStoragePaths.production.drawingEvidenceArchive)
  }

  nonisolated var databaseURL: URL { directoryURL.appendingPathComponent("library-v1.sqlite") }
  nonisolated private var legacySourceIndexURL: URL { legacyDirectoryURL.appendingPathComponent("index-v1.json") }
  private var legacyIndexURL: URL { (legacyReadRootOverride ?? legacyDirectoryURL).appendingPathComponent("index-v1.json") }
  nonisolated var canonicalLibraryCommitted: Bool { (try? PortraitLibraryDatabase.hasCommittedGeneration(at:databaseURL)) == true }
  private var indexURL: URL { !legacyReadOnly && canonicalLibraryCommitted ? databaseURL : legacyIndexURL }
  func libraryDatabase() throws -> PortraitLibraryDatabase {
    if let database { return database }
    let opened = try PortraitLibraryDatabase(url: databaseURL); database = opened; return opened
  }
  private var payloadRoot: URL { !installingCanonical && indexURL != databaseURL ? (legacyReadRootOverride ?? legacyDirectoryURL) : directoryURL }
  private var blobDirectory: URL { payloadRoot.appendingPathComponent("assets", isDirectory: true) }

  private var recordDirectory: URL { payloadRoot.appendingPathComponent("records", isDirectory: true) }

  /// The committed recipe catalog needs neither candidate geometry nor assets.
  /// Legacy indexes still pay their JSON/checksum cost, but skip materialization.
  func loadSavedStyles() throws -> [PortraitSavedStyle] {
    if FileManager.default.fileExists(atPath:databaseURL.path) { _ = try libraryDatabase().generation }
    guard FileManager.default.fileExists(atPath: indexURL.path) else {
      var isDirectory: ObjCBool = false
      if FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), !isDirectory.boolValue {
        throw PortraitCandidateStoreError.invalidIndex("The archive location is not a directory.")
      }
      return []
    }
    let envelope = try readIndex()
    if envelope.schemaVersion >= 3 {
      return try JSONDecoder().decode(IndexedArchive.self, from: envelope.payload).savedStyles ?? []
    }
    if envelope.schemaVersion == 2 {
      let manifest = try JSONDecoder().decode(ArchiveManifest.self, from: envelope.payload)
      guard validHash(manifest.recordSHA256) else { throw PortraitCandidateStoreError.invalidIndex("invalid record identity") }
      return manifest.savedStyles ?? []
    }
    let legacy = try JSONDecoder().decode(LegacyStyleCatalog.self, from: envelope.payload)
    guard legacy.schemaVersion == 1 else { throw PortraitCandidateStoreError.unsupportedVersion(legacy.schemaVersion) }
    return legacy.savedStyles ?? []
  }

  private func readIndex() throws -> IndexEnvelope {
    if !legacyReadOnly, indexURL == databaseURL {
      let db = try libraryDatabase(); try db.integrityCheck()
      let payload = try PortraitCandidateCoding.encoder().encode(db.index())
      lastReadIndexState = try VerifiedFileState(databaseURL); committedGeneration = try db.generation
      return IndexEnvelope(schemaVersion: 4, sha256: PortraitCandidateCoding.digest(payload), payload: payload)
    }
    let (bytes, state) = try VerifiedFileState.read(indexURL)
    let envelope = try JSONDecoder().decode(IndexEnvelope.self, from: bytes)
    lastReadIndexState = state
    guard [1, 2, 3, 4].contains(envelope.schemaVersion) else {
      throw PortraitCandidateStoreError.unsupportedVersion(envelope.schemaVersion)
    }
    guard PortraitCandidateCoding.digest(envelope.payload) == envelope.sha256 else {
      throw PortraitCandidateStoreError.invalidIndex("checksum mismatch; original file preserved")
    }
    return envelope
  }

  func readRecords(_ hash: String) throws -> Data {
    guard validHash(hash) else { throw PortraitCandidateStoreError.invalidIndex("invalid record identity") }
    let (data, state) = try VerifiedFileState.read(recordDirectory.appendingPathComponent(hash))
    guard PortraitCandidateCoding.digest(data) == hash else {
      throw PortraitCandidateStoreError.invalidIndex("record checksum mismatch; original file preserved")
    }
    verifiedFiles[recordDirectory.appendingPathComponent(hash)] = state
    fileByteCounts[recordDirectory.appendingPathComponent(hash)] = data.count
    return data
  }

  private func loadArchive() -> PortraitCandidateStoreLoadResult {
    hasInspected = true
    if FileManager.default.fileExists(atPath:databaseURL.path) {
      do { _ = try libraryDatabase().generation } catch { return failedLoad(error.localizedDescription) }
    }
    verifiedFiles = [:]; fileByteCounts = [:]
    drawingRecords = [:]; verifiedDrawings = [:]
    verifiedCandidates = [:]; verifiedPhotos = [:]; candidateRecords = [:]
    metadataRecords = [:]; verifiedMetadata = [:]; labelRecords = [:]; verifiedLabels = [:]
    committedIndexState = nil; loadedRecordHash = nil
    let manager = FileManager.default
    guard manager.fileExists(atPath: directoryURL.path) || manager.fileExists(atPath: legacyDirectoryURL.path) else {
      writeBlock = nil
      return .init(archive: .init(), issues: [], canWrite: true)
    }
    var isDirectory: ObjCBool = false
    let readingRoot = canonicalLibraryCommitted && !legacyReadOnly ? directoryURL : (legacyReadRootOverride ?? legacyDirectoryURL)
    guard manager.fileExists(atPath: readingRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      return failedLoad("The archive location is not a directory.")
    }
    do {
      let children = try manager.contentsOfDirectory(at: readingRoot, includingPropertiesForKeys: nil)
      var issues = children.filter { $0.lastPathComponent.hasPrefix("staging-") }
        .map { "Interrupted save retained at \($0.lastPathComponent)." }
      guard manager.fileExists(atPath: indexURL.path) else {
        let orphans = try assetNames()
        issues += orphans.map { "Unassociated asset \($0) retained for recovery." }
        writeBlock = nil
        return .init(archive: .init(), issues: issues, canWrite: true)
      }
      let envelope = try readIndex()
      committedIndexState = lastReadIndexState
      let payload: Data
      let savedStyles: [PortraitSavedStyle]?
      let stored: StoredArchive
      var drawingReferences: [SavedDrawingRecordReference]? = nil
      if envelope.schemaVersion >= 3 {
        let indexed = try JSONDecoder().decode(IndexedArchive.self, from: envelope.payload)
        guard [3, 4].contains(indexed.schemaVersion) else { throw PortraitCandidateStoreError.unsupportedVersion(indexed.schemaVersion) }
        if indexed.schemaVersion == 4, indexed.savedDrawings == nil || indexed.drawingCatalog == nil {
          throw PortraitCandidateStoreError.invalidIndex("saved drawing catalog is missing")
        }
        drawingReferences = indexed.savedDrawings
        var entries: [StoredEntry] = []
        for entry in indexed.entries {
          let bytes = try readRecords(entry.candidateSHA256)
          let candidate = try JSONDecoder().decode(StoredCandidate.self, from: bytes)
          guard candidate.id == entry.candidateID else { throw PortraitCandidateStoreError.invalidIndex("candidate record identity mismatch") }
          let metadata = try JSONDecoder().decode(EntryMetadata.self, from: readRecords(entry.metadataSHA256))
          guard metadata.candidateID == candidate.id else { throw PortraitCandidateStoreError.invalidIndex("candidate metadata identity mismatch") }
          entries.append(StoredEntry(candidate: candidate, reasons: metadata.reasons,
            exploration: metadata.exploration, attempt: metadata.attempt))
          candidateRecords[candidate.id] = entry.candidateSHA256
          metadataRecords[candidate.id] = entry.metadataSHA256
          verifiedMetadata[candidate.id] = metadata
        }
        let labels = try indexed.labels.map { reference -> PortraitLabelRevision in
          let label = try JSONDecoder().decode(PortraitLabelRevision.self, from: readRecords(reference.sha256))
          guard label.id == reference.id else { throw PortraitCandidateStoreError.invalidIndex("label record identity mismatch") }
          labelRecords[label.id] = reference.sha256; verifiedLabels[label.id] = label
          return label
        }
        stored = StoredArchive(entries: entries, labels: labels, indexed: indexed)
        payload = envelope.payload
        savedStyles = indexed.savedStyles
      } else {
        if envelope.schemaVersion == 2 {
          let manifest = try JSONDecoder().decode(ArchiveManifest.self, from: envelope.payload)
          loadedRecordHash = manifest.recordSHA256
          payload = try readRecords(manifest.recordSHA256)
          savedStyles = manifest.savedStyles
        } else {
          payload = envelope.payload
          savedStyles = nil
        }
        stored = try JSONDecoder().decode(StoredArchive.self, from: payload)
        guard [1, 2].contains(stored.schemaVersion) else { throw PortraitCandidateStoreError.unsupportedVersion(stored.schemaVersion) }
      }
      let sourceRecords = stored.sourcePhotos ?? []
      guard Set(sourceRecords.map(\.id)).count == sourceRecords.count else {
        throw PortraitCandidateStoreError.invalidIndex("duplicate source photo identity")
      }
      let sourcesByID = Dictionary(uniqueKeysWithValues: sourceRecords.map { ($0.id, $0.sourceSHA256) })
      var entries: [PortraitRetainedCandidate] = []
      var referenced = Set<String>()
      var missing = false
      var assets: [String: Data] = [:]
      func asset(_ hash: String) throws -> Data {
        if let data = assets[hash] { return data }
        let data = try readAsset(hash); assets[hash] = data; return data
      }
      var photos: [PortraitPhoto] = []
      for photo in sourceRecords {
        referenced.insert(photo.sourceSHA256)
        do { photos.append(try photo.materialize(source: asset(photo.sourceSHA256))) }
        catch {
          missing = true
          issues.append("Source photo \(photo.id) is unavailable: \(error.localizedDescription)")
        }
      }
      for entry in stored.entries {
        referenced.insert(entry.candidate.sourceSHA256)
        referenced.insert(entry.candidate.rasterSHA256)
        do {
          if let source = sourcesByID[entry.candidate.photoID], source != entry.candidate.sourceSHA256 {
            throw PortraitCandidateStoreError.invalidIndex("candidate/source association changed")
          }
          let candidate = try entry.candidate.materialize(
            source: asset(entry.candidate.sourceSHA256),
            raster: asset(entry.candidate.rasterSHA256))
          try PortraitExplorationRecord.validate(entry.exploration, for: candidate)
          entries.append(.init(candidate: candidate, reasons: entry.reasons, exploration: entry.exploration, attempt: entry.attempt))
          verifiedCandidates[candidate.id] = candidate
        } catch {
          // Preserve the damaged index and all healthy candidates. A partial
          // recovery is visible and cannot overwrite the missing record.
          missing = true
          issues.append("Candidate \(entry.candidate.id) is unavailable: \(error.localizedDescription)")
        }
      }
      var drawings: [SavedDrawing] = []
      if let drawingReferences {
        guard Set(drawingReferences.map(\.id)).count == drawingReferences.count else {
          throw PortraitCandidateStoreError.invalidIndex("duplicate saved drawing identity")
        }
        for reference in drawingReferences {
          do {
            let drawing: SavedDrawing
            if let candidateID = reference.candidateID {
              guard let candidate = entries.first(where: { $0.id == candidateID })?.candidate,
                candidateID == reference.id else { throw SavedDrawingBrowserError.drawingUnavailable }
              drawing = SavedDrawing(candidate: candidate)
            } else {
              guard let hash = reference.recordSHA256 else { throw SavedDrawingBrowserError.drawingUnavailable }
              drawing = try JSONDecoder().decode(StoredDrawing.self, from: readRecords(hash)).materialize()
              guard drawing.id == reference.id else { throw PortraitCandidateError.integrityMismatch }
              drawingRecords[drawing.id] = hash; verifiedDrawings[drawing.id] = drawing
            }
            drawings.append(drawing)
          } catch {
            missing = true
            issues.append("Saved drawing \(reference.id) is unavailable: \(error.localizedDescription)")
          }
        }
      } else { drawings = entries.filter { !$0.reasons.isEmpty }.map { SavedDrawing(candidate: $0.candidate) } }
      try validateLabels(stored.labels, entries: stored.entries)
      if manager.fileExists(atPath: recordDirectory.path) {
        issues += try manager.contentsOfDirectory(atPath: recordDirectory.path)
          .filter { $0 != loadedRecordHash && !candidateRecords.values.contains($0) && !metadataRecords.values.contains($0) && !labelRecords.values.contains($0) && !drawingRecords.values.contains($0) }.map { "Unassociated archive records \($0) retained for recovery." }
      }
      // The committed tombstone is deletion authority after a crash too. Finish
      // payload cleanup before reporting the archive saved, preserving every
      // blob still referenced even by an unavailable candidate.
      let selectedSQLAssets = indexURL == databaseURL
        ? Set(try libraryDatabase().rows("SELECT source_hash FROM photo WHERE deleted=0 UNION SELECT raster_hash FROM drawing WHERE deleted=0 AND raster_hash IS NOT NULL").compactMap{$0[0]}) : Set<String>()
      let cleanup = indexURL == databaseURL && !legacyReadOnly
        ? try cleanupDeletedAssets(stored.tombstones,referenced:referenced.union(selectedSQLAssets))
        : (count:0,bytes:0,issues:[String]())
      issues += cleanup.issues
      issues += try assetNames().filter { !referenced.contains($0) }
        .map { "Unassociated asset \($0) retained for recovery." }
      var blockers: [String] = []
      if missing { blockers.append("Repair missing/corrupt portrait assets before saving this archive; the original index is preserved.") }
      if cleanup.count > 0 { blockers.append("Explicit asset deletion is unfinished; retry archive save to finish cleanup.") }
      writeBlock = blockers.isEmpty ? nil : blockers.joined(separator: " ")
      let archive = PortraitCandidateArchive(entries: entries, labels: stored.labels,
        tombstones: stored.tombstones, savedStyles: envelope.schemaVersion >= 2
          ? (stored.savedStyles == nil && (savedStyles?.isEmpty ?? true) ? nil : savedStyles) : stored.savedStyles,
        sourcePhotos: stored.sourcePhotos == nil ? nil : photos, savedDrawings: drawings,labelPhotoIDs:stored.labelPhotoIDs,
        photoCaptureTimeUnknownIDs:stored.photoCaptureTimeUnknownIDs)
      let selectedRecords = Set(Array(candidateRecords.values) + Array(metadataRecords.values) + Array(labelRecords.values) + Array(drawingRecords.values))
      let recordBytes = selectedRecords.reduce(0) { total, hash in
        total + (fileByteCounts[recordDirectory.appendingPathComponent(hash)] ?? 0)
      }
      let metadataBytes = envelope.schemaVersion >= 3 ? recordBytes : (loadedRecordHash == nil ? 0 : payload.count)
      let assetBytes = assets.values.reduce(0) { $0 + $1.count }
      var retained = try Data(contentsOf: indexURL).count + metadataBytes + assetBytes + cleanup.bytes
      // Upgrade once during the existing archive load, before Draw is available.
      // Missing assets never authorize migration or replacement.
      guard verifiedFiles.allSatisfy({ (try? VerifiedFileState($0.key)) == $0.value }),
        (try? VerifiedFileState(indexURL)) == committedIndexState else {
        throw PortraitCandidateStoreError.invalidIndex("Archive changed during verification; reload before retrying.")
      }
      if indexURL != databaseURL, !legacyReadOnly, writeBlock == nil {
        try preserveVerifiedLegacyPayloads()
        retained = try save(snapshot: archive)
      }
      return .init(archive: archive, issues: issues, canWrite: writeBlock == nil,
        pendingCleanupCount: cleanup.count, pendingCleanupBytes: cleanup.bytes, retainedBytes: retained)
    } catch {
      return failedLoad(error.localizedDescription)
    }
  }

  func ensureLibraryGraph() throws {
    guard !canonicalLibraryCommitted else { return }
    let loaded = load()
    guard loaded.canWrite,canonicalLibraryCommitted else { throw PortraitLibraryError.database(loaded.issues.joined(separator:" ")) }
  }

  /// Mutation ownership needs immutable label ancestry and metadata, not every
  /// historical renderer input. Initial or changed legacy graphs still pass
  /// through the verified importer before this compact state can be selected.
  func loadMutationState() -> PortraitCandidateStoreLoadResult {
    do {
      if let fullHistoryWriteBlock { return failedLoad(fullHistoryWriteBlock) }
      let legacyExists = FileManager.default.fileExists(atPath:legacySourceIndexURL.path)
      let legacyHash = legacyExists ? PortraitCandidateCoding.digest(try Data(contentsOf:legacySourceIndexURL)) : nil
      var importRequired = !canonicalLibraryCommitted
      if !importRequired { importRequired = try libraryDatabase().generation.legacyPortraitSHA256 != legacyHash }
      if importRequired {
        let imported = loadVerifiedHistory()
        guard imported.canWrite,canonicalLibraryCommitted else { return imported }
      }
      let db = try libraryDatabase()
      try assertCurrentInputs(db,checkEvidence:false)
      try db.integrityCheck()
      let before = try VerifiedFileState(databaseURL),generation = try db.generation
      let index = try db.index()
      let labels = try index.labels.map { reference -> PortraitLabelRevision in
        let label = try JSONDecoder().decode(PortraitLabelRevision.self,from:readRecords(reference.sha256))
        guard label.id == reference.id else { throw PortraitCandidateStoreError.invalidIndex("label record identity mismatch") }
        labelRecords[label.id] = reference.sha256;verifiedLabels[label.id] = label
        return label
      }
      try validateLabels(labels,entries:[])
      let unknownPhotos = (index.sourcePhotos ?? []).filter {
        !($0.captureTimeKnown ?? ($0.candidateRecordSHA256 == nil))
      }.map(\.id)
      try assertCurrentInputs(db,checkEvidence:false)
      guard try VerifiedFileState(databaseURL) == before,try db.generation == generation,
        verifiedFiles.allSatisfy({(try? VerifiedFileState($0.key)) == $0.value}) else { throw PortraitLibraryError.staleGeneration }
      committedIndexState = before;committedGeneration = generation;hasInspected = true;writeBlock = nil
      return .init(archive:.init(labels:labels,tombstones:index.tombstones,savedStyles:index.savedStyles,
        labelPhotoIDs:index.labelPhotoIDs,photoCaptureTimeUnknownIDs:unknownPhotos.isEmpty ? nil : unknownPhotos),
        issues:[],canWrite:true,retainedBytes:try ownedPayloadByteCount())
    } catch { return failedLoad(error.localizedDescription) }
  }

  private func ownedPayloadByteCount() throws -> Int {
    var total = ((try FileManager.default.attributesOfItem(atPath:databaseURL.path)[.size]) as? NSNumber)?.intValue ?? 0
    for folder in [blobDirectory,recordDirectory] where FileManager.default.fileExists(atPath:folder.path) {
      for file in try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.fileSizeKey]) {
        total += try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
      }
    }
    return total
  }

  func refreshCommittedLibraryGeneration() {
    committedGeneration = try? libraryDatabase().generation
    committedIndexState = try? VerifiedFileState(databaseURL)
  }

  func configureEvidenceArchiveURL(_ url: URL) throws {
    if let evidenceArchiveURL, evidenceArchiveURL.standardizedFileURL != url.standardizedFileURL {
      throw PortraitLibraryError.database("evidence archive owner cannot change")
    }
    evidenceArchiveURL = url
  }

  func load() -> PortraitCandidateStoreLoadResult {
    let result = loadVerifiedHistory()
    // A compact metadata read cannot reverse observed full-history corruption.
    // Only another successful verified history read releases this write block.
    fullHistoryWriteBlock = result.canWrite ? nil : (writeBlock ?? result.issues.joined(separator:" "))
    return result
  }

  private func loadVerifiedHistory() -> PortraitCandidateStoreLoadResult {
    do {
      let originalIndex = legacySourceIndexURL
      let exists = FileManager.default.fileExists(atPath:originalIndex.path)
      let currentHash = exists ? PortraitCandidateCoding.digest(try Data(contentsOf:originalIndex)) : nil
      let knownHash = canonicalLibraryCommitted ? try libraryDatabase().generation.legacyPortraitSHA256 : nil
      if exists, !canonicalLibraryCommitted || currentHash != knownHash {
        if canonicalLibraryCommitted,try libraryDatabase().scalar("SELECT value FROM state WHERE key='canonical_library_dirty'") == "1" {
          throw PortraitLibraryError.database("Legacy and canonical libraries both changed; the prior canonical generation is retained for reviewed reconciliation.")
        }
        let colocatedLegacy = legacyDirectoryURL.standardizedFileURL == directoryURL.standardizedFileURL
        let snapshots = colocatedLegacy
          ? directoryURL.deletingLastPathComponent().appendingPathComponent("PortraitImportSnapshots").appendingPathComponent(PortraitCandidateCoding.digest(Data(directoryURL.path.utf8)))
          : directoryURL.appendingPathComponent("ImportSnapshots")
        let snapshot = try PortraitLegacySnapshot.capture(from:legacyDirectoryURL,into:snapshots)
        legacyReadRootOverride = snapshot.directory
        verifiedLegacyImportSHA256 = snapshot.manifestSHA256
        if canonicalLibraryCommitted {
          legacyReadOnly = true
          let imported = loadArchive()
          legacyReadOnly = false
          guard imported.canWrite else { legacyReadRootOverride=nil;verifiedLegacyImportSHA256=nil;return imported }
          try preserveVerifiedLegacyPayloads()
          committedIndexState = try VerifiedFileState(databaseURL)
          committedGeneration = try libraryDatabase().generation
          _ = try save(snapshot:imported.archive)
        }
      }
      let result = loadArchive()
      legacyReadRootOverride = nil;verifiedLegacyImportSHA256 = nil
      guard result.canWrite else { return result }
      if !canonicalLibraryCommitted { _ = try save(snapshot:result.archive) }
      if let evidenceArchiveURL,FileManager.default.fileExists(atPath:evidenceArchiveURL.path) {
        let source = try PortraitEvidenceSource.read(evidenceArchiveURL)
        try reconcileEvidence(archive:source.archive,generation:source.sha256)
      }
      return result
    } catch { legacyReadOnly=false;legacyReadRootOverride=nil;verifiedLegacyImportSHA256=nil;return failedLoad(error.localizedDescription) }
  }

  private func preserveVerifiedLegacyPayloads() throws {
    guard (legacyReadRootOverride ?? legacyDirectoryURL) != directoryURL else { return }
    for (source,state) in verifiedFiles where source != legacyIndexURL {
      guard try VerifiedFileState(source) == state else { throw PortraitLibraryError.staleGeneration }
      let bytes = try Data(contentsOf:source)
      let hash = source.lastPathComponent
      guard PortraitCandidateCoding.digest(bytes) == hash else { throw PortraitCandidateStoreError.invalidAsset(hash) }
      let target = directoryURL.appendingPathComponent(source.deletingLastPathComponent().lastPathComponent).appendingPathComponent(hash)
      try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
      if FileManager.default.fileExists(atPath:target.path) {
        guard PortraitCandidateCoding.digest(try Data(contentsOf:target)) == hash else { throw PortraitCandidateStoreError.invalidAsset(hash) }
      } else { try bytes.write(to:target,options:.atomic);try synchronize(target) }
    }
  }

  private func failedLoad(_ message: String) -> PortraitCandidateStoreLoadResult {
    writeBlock = message
    return .init(archive: .init(), issues: [message], canWrite: false)
  }

  /// Immutable candidate geometry is installed once; retention, feedback and
  /// deletion commit only the compact index. Verified unchanged bytes are reused.
  @discardableResult
  func save(snapshot: PortraitCandidateArchive, occurrences: [PortraitRetainedCandidate] = [],
    mode: PortraitCandidateSaveMode = .fullArchive) throws -> Int {
    if legacyReadOnly { throw PortraitLibraryError.database("legacy importer is read-only") }
    if !hasInspected {
      if case .mutationDelta = mode { _ = loadMutationState() }
      else { _ = load() }
    }
    if let writeBlock { throw PortraitCandidateStoreError.invalidIndex(writeBlock) }
    if let committedIndexState {
      guard try VerifiedFileState(indexURL) == committedIndexState else {
        throw PortraitCandidateStoreError.invalidIndex("The committed index changed; reload before retrying.")
      }
    } else if FileManager.default.fileExists(atPath: indexURL.path) {
      throw PortraitCandidateStoreError.invalidIndex("An archive appeared; reload before retrying.")
    }
    installingCanonical = true
    var didCommit = false
    defer {
      installingCanonical = false
      if !didCommit { verifiedCandidates.removeAll();verifiedMetadata.removeAll() }
    }
    let manager = FileManager.default
    try manager.createDirectory(at: blobDirectory, withIntermediateDirectories: true)
    try manager.createDirectory(at: recordDirectory, withIntermediateDirectories: true)
    let encoder = PortraitCandidateCoding.encoder()
    let db = try libraryDatabase()
    let previousTombstones = try db.decode([PortraitArchiveTombstone].self,db.scalar("SELECT value FROM state WHERE key='tombstones'") ?? "[]")
    let authoredTombstones = previousTombstones + snapshot.tombstones
    var occurrenceOrder: [PortraitDrawingIdentity] = []
    var occurrenceEntries: [PortraitDrawingIdentity:PortraitRetainedCandidate] = [:]
    for entry in occurrences + snapshot.entries {
      let identity = PortraitDrawingIdentity(candidateID:entry.id,photoID:entry.candidate.photoID)
      if let previous = occurrenceEntries[identity] {
        let metadata = try Self.mergeMetadata(.init(candidateID:previous.id,reasons:previous.reasons,
          exploration:previous.exploration,attempt:previous.attempt),with:entry)
        occurrenceEntries[identity] = .init(candidate:entry.candidate,reasons:metadata.reasons,
          exploration:metadata.exploration,attempt:metadata.attempt)
      } else { occurrenceOrder.append(identity);occurrenceEntries[identity] = entry }
    }
    let canonicalOccurrences = Set(snapshot.entries.map { PortraitDrawingIdentity(candidateID:$0.id,photoID:$0.candidate.photoID) })
    var preparedOccurrences: [PreparedPortraitOccurrence] = []
    var assetBytes: [String: Int] = [:]
    var photos = snapshot.sourcePhotos ?? []
    var photoIDs = Set(photos.map(\.id))
    for entry in occurrenceOrder.compactMap({occurrenceEntries[$0]}) where photoIDs.insert(entry.candidate.photoID).inserted {
      let c = entry.candidate
      guard let pose = c.renderPose else { throw PortraitLibraryError.missingPhoto }
      photos.append(PortraitPhoto(id:c.photoID,data:c.sourceData,label:"Retained source",capturedAt:c.createdAt,
        frameID:nil,captureNanoseconds:nil,pose:pose,sourcePixelExtent:c.sourcePixelExtent,captureSessionID:c.captureSessionID))
    }
    guard Set(photos.map(\.id)).count == photos.count else {
      throw PortraitCandidateStoreError.invalidIndex("duplicate source photo identity")
    }
    var sourcesByID: [UUID: String] = [:]
    for photo in photos {
      let hash: String
      if let verified = verifiedPhotos[photo.id], verified.photo == photo { hash = verified.hash }
      else { hash = PortraitCandidateCoding.digest(photo.data) }
      sourcesByID[photo.id] = hash
      if assetBytes[hash] == nil {
        try install(photo.data, hash: hash)
        assetBytes[hash] = photo.data.count
      }
      verifiedPhotos[photo.id] = (photo, hash)
    }
    var indexedEntries: [IndexedEntry] = []
    var nextCandidateRecords: [String: String] = [:]
    var nextMetadataRecords: [String: String] = [:]
    var nextLabelRecords: [UUID: String] = [:]
    for identity in occurrenceOrder {
      guard var entry = occurrenceEntries[identity] else { throw PortraitLibraryError.missingDrawing }
      let occurrenceRecord = try db.scalar("SELECT candidate_record FROM drawing WHERE id=?",[identity.id])
      let cacheMatches = verifiedCandidates[entry.id] == entry.candidate && candidateRecords[entry.id] == occurrenceRecord
      let previousCandidate: StoredCandidate? = try cacheMatches ? nil : occurrenceRecord.map { try JSONDecoder().decode(StoredCandidate.self,from:readRecords($0)) }
      let isReplacement = previousCandidate.map { Self.permitsPostDeletionReplacement($0,with:entry.candidate,tombstones:authoredTombstones) } ?? false
      if !isReplacement,let previous = try db.scalar("SELECT metadata_record FROM drawing WHERE id=?",[identity.id]) {
        let metadata = try Self.mergeMetadata(JSONDecoder().decode(EntryMetadata.self,from:readRecords(previous)),with:entry)
        entry.reasons = metadata.reasons;entry.exploration = metadata.exploration;entry.attempt = metadata.attempt
      }
      let candidate = entry.candidate
      let unchanged = verifiedCandidates[candidate.id] == candidate
      if !unchanged { try candidate.validateIntegrity() }
      try PortraitExplorationRecord.validate(entry.exploration, for: candidate)
      if let source = sourcesByID[candidate.photoID], source != candidate.sourceSHA256 {
        throw PortraitCandidateStoreError.invalidIndex("candidate/source association changed")
      }
      if assetBytes[candidate.sourceSHA256] == nil {
        try install(candidate.sourceData, hash: candidate.sourceSHA256)
        assetBytes[candidate.sourceSHA256] = candidate.sourceData.count
      }
      if assetBytes[candidate.rasterSHA256] == nil {
        let url = blobDirectory.appendingPathComponent(candidate.rasterSHA256)
        if unchanged, let count = fileByteCounts[url] {
          try verifyUnchangedFile(url, hash: candidate.rasterSHA256, isAsset: true)
          assetBytes[candidate.rasterSHA256] = count
        } else {
          let raster = try encoder.encode(candidate.raster)
          try install(raster, hash: candidate.rasterSHA256)
          assetBytes[candidate.rasterSHA256] = raster.count
        }
      }
      let recordHash: String
      if let previous = occurrenceRecord,!(unchanged && candidateRecords[candidate.id] == previous) {
        guard let retained = previousCandidate else { throw PortraitLibraryError.missingDrawing }
        if retained == StoredCandidate(candidate) { recordHash = previous }
        else {
          guard Self.permitsPostDeletionReplacement(retained,with:candidate,tombstones:authoredTombstones) else {
            throw PortraitLibraryError.unresolvedLineage("immutable drawing occurrence changed")
          }
          recordHash = try installCandidatePayload(candidate,encoder:encoder)
        }
      } else if unchanged, let previous = candidateRecords[candidate.id] {
        try verifyUnchangedFile(recordDirectory.appendingPathComponent(previous), hash: previous, isAsset: false)
        recordHash = previous
      } else {
        recordHash = try installCandidatePayload(candidate,encoder:encoder)
      }
      if canonicalOccurrences.contains(identity) { nextCandidateRecords[candidate.id] = recordHash }
      if canonicalOccurrences.contains(identity) { verifiedCandidates[candidate.id] = candidate }
      let metadata = EntryMetadata(candidateID: candidate.id, reasons: entry.reasons,
        exploration: entry.exploration, attempt: entry.attempt)
      let metadataHash: String
      if verifiedMetadata[candidate.id] == metadata, let previous = metadataRecords[candidate.id] {
        try verifyUnchangedFile(recordDirectory.appendingPathComponent(previous), hash: previous, isAsset: false)
        metadataHash = previous
      } else { metadataHash = try installMetadata(metadata, encoder: encoder) }
      if canonicalOccurrences.contains(identity) { nextMetadataRecords[candidate.id] = metadataHash }
      if canonicalOccurrences.contains(identity) { verifiedMetadata[candidate.id] = metadata }
      let reference = IndexedEntry(candidateID:candidate.id,candidateSHA256:recordHash,metadataSHA256:metadataHash)
      if canonicalOccurrences.contains(identity) { indexedEntries.append(reference) }
      let explicitlySaved = (snapshot.savedDrawings ?? []).contains { $0.id == candidate.id && $0.sourcePhotoID == candidate.photoID }
      let saved = !entry.reasons.isEmpty || explicitlySaved
      preparedOccurrences.append(.init(candidate:StoredCandidate(candidate),reference:reference,
        summary:SavedDrawingSummary(SavedDrawing(candidate:candidate),isSaved:saved,feedback:entry.attempt?.feedback),saved:saved))
    }
    let snapshotOrdinals = Dictionary(uniqueKeysWithValues:snapshot.entries.enumerated().map { ($0.element.id,$0.offset) })
    indexedEntries.sort { snapshotOrdinals[$0.candidateID]! < snapshotOrdinals[$1.candidateID]! }
    let entries = snapshot.entries.map {
      StoredEntry(candidate: StoredCandidate($0.candidate), reasons: $0.reasons, exploration: $0.exploration, attempt: $0.attempt)
    }
    try validateLabels(snapshot.labels, entries: entries)
    var labels: [LabelReference] = []
    for label in snapshot.labels {
      let hash: String
      if verifiedLabels[label.id] == label, let previous = labelRecords[label.id] {
        try verifyUnchangedFile(recordDirectory.appendingPathComponent(previous), hash: previous, isAsset: false)
        hash = previous
      } else { hash = try installMetadata(label, encoder: encoder) }
      verifiedLabels[label.id] = label; nextLabelRecords[label.id] = hash
      labels.append(LabelReference(id: label.id, sha256: hash))
    }
    let drawings = Self.savedDrawings(in: snapshot)
    guard Set(drawings.map(\.id)).count == drawings.count else {
      throw PortraitCandidateStoreError.invalidIndex("duplicate saved drawing identity")
    }
    let preparedByIdentity = Dictionary(uniqueKeysWithValues:preparedOccurrences.map {
      (PortraitDrawingIdentity(candidateID:$0.candidate.id,photoID:$0.candidate.photoID),$0.candidate)
    })
    var nextDrawingRecords: [String: String] = [:]
    var drawingReferences: [SavedDrawingRecordReference] = []
    for drawing in drawings {
      if let candidate = drawing.portraitCandidate {
        // The candidate installer above already verified this immutable payload.
        // Do not rehash every historical raster for a retention-only commit.
        guard drawing.id == candidate.id, drawing.program == candidate.program,
          drawing.createdAt == candidate.createdAt else {
          throw PortraitCandidateStoreError.invalidIndex("saved drawing provenance is unavailable")
        }
        let identity = PortraitDrawingIdentity(candidateID:candidate.id,photoID:candidate.photoID)
        if let prepared = preparedByIdentity[identity] {
          guard prepared == StoredCandidate(candidate) else { throw PortraitCandidateStoreError.invalidIndex("saved drawing provenance is unavailable") }
        } else {
          _ = try db.checkedDrawing(identity.id)
          guard let hash = try db.scalar("SELECT candidate_record FROM drawing WHERE id=? AND deleted=0",[identity.id]) else {
            throw PortraitCandidateStoreError.invalidIndex("saved drawing provenance is unavailable")
          }
          if verifiedCandidates[candidate.id] != candidate || candidateRecords[candidate.id] != hash {
            let existing = try JSONDecoder().decode(StoredCandidate.self,from:readRecords(hash))
            guard existing == StoredCandidate(candidate) else { throw PortraitCandidateStoreError.invalidIndex("saved drawing provenance is unavailable") }
          } else { try verifyUnchangedFile(recordDirectory.appendingPathComponent(hash),hash:hash,isAsset:false) }
        }
        drawingReferences.append(.init(id: drawing.id, candidateID: candidate.id, recordSHA256: nil))
      } else {
        try drawing.validateIntegrity()
        let hash: String
        if verifiedDrawings[drawing.id] == drawing, let previous = drawingRecords[drawing.id] {
          try verifyUnchangedFile(recordDirectory.appendingPathComponent(previous), hash: previous, isAsset: false)
          hash = previous
        } else { hash = try installMetadata(StoredDrawing(drawing), encoder: encoder) }
        nextDrawingRecords[drawing.id] = hash; verifiedDrawings[drawing.id] = drawing
        drawingReferences.append(.init(id: drawing.id, candidateID: nil, recordSHA256: hash))
      }
    }
    var indexed = IndexedArchive(schemaVersion: 4, entries: indexedEntries,
      labels: labels, tombstones: snapshot.tombstones,
      savedStyles: snapshot.savedStyles, sourcePhotos: photos.map {
        var reference = PortraitPhotoReference($0, sourceSHA256:sourcesByID[$0.id]!)
        if snapshot.photoCaptureTimeUnknownIDs?.contains($0.id) == true { reference.captureTimeKnown = false }
        return reference
      })
    indexed.savedDrawings = drawingReferences
    indexed.drawingCatalog = Self.drawingCatalog(snapshot)
    if snapshot.sourcePhotos == nil || photos.count != snapshot.sourcePhotos?.count {
      let explicit = Set((snapshot.sourcePhotos ?? []).map(\.id))
      indexed = IndexedArchive(schemaVersion:4,entries:indexed.entries,labels:indexed.labels,tombstones:indexed.tombstones,
        savedStyles:indexed.savedStyles,sourcePhotos:(indexed.sourcePhotos ?? []).map { photo in
          var ref = photo
          if !explicit.contains(ref.id) {
            ref.candidateRecordSHA256 = preparedOccurrences.first(where:{$0.candidate.photoID == ref.id})?.reference.candidateSHA256
            ref.captureTimeKnown = false
          }
          return ref
        },savedDrawings:drawingReferences,drawingCatalog:Self.drawingCatalog(snapshot))
    }
    indexed.photoCatalog = Self.photoCatalog(sources: indexed.sourcePhotos ?? [],
      candidates: snapshot.entries.map(\.candidate), records: nextCandidateRecords)
    indexed.labelPhotoIDs = snapshot.labelPhotoIDs
    let liveLegacyHash = FileManager.default.fileExists(atPath:legacySourceIndexURL.path)
      ? PortraitCandidateCoding.digest(try Data(contentsOf:legacySourceIndexURL)) : nil
    let expectedLegacyHash = verifiedLegacyImportSHA256 ?? committedGeneration?.legacyPortraitSHA256
    guard liveLegacyHash == expectedLegacyHash else { throw PortraitLibraryError.staleGeneration }
    let legacyHash = verifiedLegacyImportSHA256
    try db.commit(index:indexed,candidates:Dictionary(uniqueKeysWithValues:snapshot.entries.map { ($0.id,StoredCandidate($0.candidate)) }),
      occurrences:preparedOccurrences,legacyHash:legacyHash,expected:committedGeneration,mode:mode)
    committedGeneration = try db.generation
    didCommit = true
    verifiedLegacyImportSHA256 = nil
    committedIndexState = try VerifiedFileState(databaseURL)
    // Legacy records are immutable importer inputs. No publisher, retirement or
    // writable JSON fallback remains after SQL publication.
    let selectedRecords = Set(Array(nextCandidateRecords.values) + Array(nextMetadataRecords.values) + Array(nextLabelRecords.values) + Array(nextDrawingRecords.values))
    drawingRecords = nextDrawingRecords
    verifiedDrawings = verifiedDrawings.filter { nextDrawingRecords[$0.key] != nil }
    candidateRecords = nextCandidateRecords; metadataRecords = nextMetadataRecords
    labelRecords = nextLabelRecords; loadedRecordHash = nil
    // The committed index owns cache membership too. Explicit deletion must
    // release old values and file identities so a later identical reimport can
    // install fresh assets; a missing still-selected asset continues to refuse.
    verifiedCandidates = verifiedCandidates.filter { nextCandidateRecords[$0.key] != nil }
    verifiedMetadata = verifiedMetadata.filter { nextMetadataRecords[$0.key] != nil }
    verifiedLabels = verifiedLabels.filter { nextLabelRecords[$0.key] != nil }
    verifiedPhotos = verifiedPhotos.filter { sourcesByID[$0.key] != nil }
    let selectedFiles = Set(selectedRecords.map { recordDirectory.appendingPathComponent($0) }
      + assetBytes.keys.map { blobDirectory.appendingPathComponent($0) })
    verifiedFiles = verifiedFiles.filter { selectedFiles.contains($0.key) }
    fileByteCounts = fileByteCounts.filter { selectedFiles.contains($0.key) }
    let durableAssets = Set(try db.rows("SELECT source_hash FROM photo WHERE deleted=0 UNION SELECT raster_hash FROM drawing WHERE deleted=0 AND raster_hash IS NOT NULL").compactMap{$0[0]})
    let cleanup = try cleanupDeletedAssets(snapshot.tombstones, referenced: Set(assetBytes.keys).union(durableAssets))
    if cleanup.count > 0 { throw PortraitCandidateStoreError.invalidIndex(cleanup.issues.joined(separator: " ")) }
    if case .mutationDelta = mode { return try ownedPayloadByteCount() }
    return (try Data(contentsOf:databaseURL).count) + selectedRecords.reduce(0) {
      $0 + (fileByteCounts[recordDirectory.appendingPathComponent($1)] ?? 0)
    } + assetBytes.values.reduce(0, +)
  }

  func installMetadata<T: Encodable>(_ value: T, encoder: JSONEncoder) throws -> String {
    let bytes = try encoder.encode(value)
    metadataBytesEncoded += bytes.count
    let hash = PortraitCandidateCoding.digest(bytes)
    let url = recordDirectory.appendingPathComponent(hash)
    if FileManager.default.fileExists(atPath: url.path) { _ = try readRecords(hash) }
    else { try bytes.write(to: url, options: .atomic); try synchronize(url); _ = try readRecords(hash) }
    return hash
  }

  private func installCandidatePayload(_ candidate: PortraitCandidate, encoder: JSONEncoder) throws -> String {
    let bytes = try encoder.encode(StoredCandidate(candidate))
    recordBytesEncoded += bytes.count
    let hash = PortraitCandidateCoding.digest(bytes),url = recordDirectory.appendingPathComponent(hash)
    if FileManager.default.fileExists(atPath:url.path) { _ = try readRecords(hash) }
    else { try bytes.write(to:url,options:.atomic);try synchronize(url);_ = try readRecords(hash) }
    return hash
  }

  static func permitsPostDeletionReplacement(_ old: StoredCandidate, with candidate: PortraitCandidate,
    tombstones: [PortraitArchiveTombstone]) -> Bool {
    guard old.id == candidate.id,old.photoID == candidate.photoID,old.captureSessionID == candidate.captureSessionID,
      old.sourceSHA256 == candidate.sourceSHA256,old.program == candidate.program,
      old.rasterSHA256 == candidate.rasterSHA256,old.recipeSHA256 == candidate.recipeSHA256 else { return false }
    let identity = PortraitDrawingIdentity(candidateID:candidate.id,photoID:candidate.photoID)
    return tombstones.contains { tombstone in
      let matches = tombstone.kind == .drawing ? tombstone.identity.lowercased() == identity.id
        : tombstone.kind == .candidate && (tombstone.identity == candidate.id || tombstone.affectedCandidateIDs.contains(candidate.id))
      return matches && old.createdAt <= tombstone.createdAt && candidate.createdAt > tombstone.createdAt
    }
  }

  private static func mergeMetadata(_ previous: EntryMetadata, with incoming: PortraitRetainedCandidate) throws -> EntryMetadata {
    guard previous.candidateID == incoming.id else { throw PortraitLibraryError.database("occurrence metadata candidate changed") }
    func merged<T: Equatable>(_ old: [T], _ new: [T], key: (T) -> String) throws -> [T] {
      var result = old
      for value in new {
        if let existing = result.first(where:{key($0) == key(value)}) {
          guard existing == value else { throw PortraitLibraryError.database("immutable occurrence revision changed") }
        } else { result.append(value) }
      }
      return result
    }
    let reasons = try merged(previous.reasons,incoming.reasons,key:{$0.id.uuidString})
    let previousExploration: [PortraitExplorationRecord] = previous.exploration ?? []
    let incomingExploration: [PortraitExplorationRecord] = incoming.exploration ?? []
    let explorationKey: (PortraitExplorationRecord) -> String = { record in
      record.traceSessionID.uuidString + ":" + String(record.sequence)
    }
    let mergedExploration: [PortraitExplorationRecord] = try merged(previousExploration,incomingExploration,key:explorationKey)
    let explorationOrder: (PortraitExplorationRecord,PortraitExplorationRecord) -> Bool = { left,right in
      if left.traceSessionID == right.traceSessionID { return left.sequence < right.sequence }
      return left.traceSessionID.uuidString < right.traceSessionID.uuidString
    }
    let exploration: [PortraitExplorationRecord] = mergedExploration.sorted(by:explorationOrder)
    var attempt = incoming.attempt ?? previous.attempt
    if let old = previous.attempt,let new = incoming.attempt {
      guard old.proposalIdentity == new.proposalIdentity,old.thumbnailPNG == new.thumbnailPNG,
        old.changeCue == new.changeCue else { throw PortraitLibraryError.database("immutable attempt identity changed") }
      attempt?.burdenSummary = new.burdenSummary ?? old.burdenSummary
      attempt?.parameterPreference = new.parameterPreference ?? old.parameterPreference
      attempt?.feedbackRevisions = try merged(old.feedbackRevisions,new.feedbackRevisions,key:{$0.id.uuidString})
    }
    return .init(candidateID:incoming.id,reasons:reasons,exploration:exploration.isEmpty ? nil : exploration,attempt:attempt)
  }

  func synchronize(_ url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.synchronize()
    // Atomic rename selects the commit; synchronize that directory entry too.
    let descriptor = url.deletingLastPathComponent().withUnsafeFileSystemRepresentation { Darwin.open($0!, O_RDONLY) }
    guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    defer { Darwin.close(descriptor) }
    guard Darwin.fsync(descriptor) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
  }

  private func verifyUnchangedFile(_ url: URL, hash: String, isAsset: Bool) throws {
    if let previous = verifiedFiles[url], try VerifiedFileState(url) == previous { return }
    if isAsset { _ = try readAsset(hash) } else { _ = try readRecords(hash) }
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
    for photo in snapshot.sourcePhotos ?? [] { assets[PortraitCandidateCoding.digest(photo.data)] = photo.data.count }
    for entry in snapshot.entries {
      assets[entry.candidate.sourceSHA256] = entry.candidate.sourceData.count
      if assets[entry.candidate.rasterSHA256] == nil {
        assets[entry.candidate.rasterSHA256] = try encoder.encode(entry.candidate.raster).count
      }
    }
    var recordBytes: [String: Int] = [:]
    let entries = try snapshot.entries.map { entry in
      let bytes = try encoder.encode(StoredCandidate(entry.candidate))
      let hash = PortraitCandidateCoding.digest(bytes)
      recordBytes[hash] = bytes.count
      let metadata = try encoder.encode(EntryMetadata(candidateID: entry.id, reasons: entry.reasons,
        exploration: entry.exploration, attempt: entry.attempt))
      let metadataHash = PortraitCandidateCoding.digest(metadata)
      recordBytes[metadataHash] = metadata.count
      return IndexedEntry(candidateID: entry.id, candidateSHA256: hash, metadataSHA256: metadataHash)
    }
    let labels = try snapshot.labels.map { label in
      let bytes = try encoder.encode(label), hash = PortraitCandidateCoding.digest(bytes)
      recordBytes[hash] = bytes.count
      return LabelReference(id: label.id, sha256: hash)
    }
    let drawings = savedDrawings(in: snapshot)
    let drawingReferences = try drawings.map { drawing -> SavedDrawingRecordReference in
      if let candidate = drawing.portraitCandidate {
        return .init(id: drawing.id, candidateID: candidate.id, recordSHA256: nil)
      }
      let bytes = try encoder.encode(StoredDrawing(drawing)), hash = PortraitCandidateCoding.digest(bytes)
      recordBytes[hash] = bytes.count
      return .init(id: drawing.id, candidateID: nil, recordSHA256: hash)
    }
    var indexed = IndexedArchive(schemaVersion: 4, entries: entries,
      labels: labels, tombstones: snapshot.tombstones, savedStyles: snapshot.savedStyles,
      sourcePhotos: snapshot.sourcePhotos?.map { PortraitPhotoReference($0) })
    indexed.savedDrawings = drawingReferences
    indexed.drawingCatalog = drawingCatalog(snapshot)
    indexed.photoCatalog = photoCatalog(sources: indexed.sourcePhotos ?? [],
      candidates: snapshot.entries.map(\.candidate), records: Dictionary(uniqueKeysWithValues:
        entries.map { ($0.candidateID, $0.candidateSHA256) }))
    let payload = try encoder.encode(indexed)
    let envelope = IndexEnvelope(schemaVersion: 4, sha256: PortraitCandidateCoding.digest(payload), payload: payload)
    return try encoder.encode(envelope).count + recordBytes.values.reduce(0, +) + assets.values.reduce(0, +)
  }

  private func validateLabels(_ labels: [PortraitLabelRevision], entries: [StoredEntry]) throws {
    guard Set(labels.map(\.id)).count == labels.count,
      Set(entries.map { $0.candidate.id }).count == entries.count else {
      throw PortraitCandidateStoreError.invalidIndex("duplicate candidate or label identity")
    }
    let labelsByID = Dictionary(uniqueKeysWithValues: labels.map { ($0.id, $0) })
    let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.candidate.id, $0) })
    for label in labels {
      try PortraitArchiveValidation.label(label)
      if let previous = label.previousRevisionID {
        guard let predecessor = labelsByID[previous],
          predecessor.id != label.id, predecessor.candidateID == label.candidateID,
          predecessor.scope.id == label.scope.id else {
          throw PortraitCandidateStoreError.invalidIndex("invalid label revision ancestry")
        }
      }
      if let candidate = entriesByID[label.candidateID]?.candidate,
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

  func readAsset(_ hash: String) throws -> Data {
    guard validHash(hash) else { throw PortraitCandidateStoreError.invalidAsset(hash) }
    let (data, state) = try VerifiedFileState.read(blobDirectory.appendingPathComponent(hash))
    assetBytesVerified += data.count
    guard PortraitCandidateCoding.digest(data) == hash else { throw PortraitCandidateStoreError.invalidAsset(hash) }
    verifiedFiles[blobDirectory.appendingPathComponent(hash)] = state
    fileByteCounts[blobDirectory.appendingPathComponent(hash)] = data.count
    return data
  }

  private func install(_ data: Data, hash: String) throws {
    let url = blobDirectory.appendingPathComponent(hash)
    if let previous = verifiedFiles[url], try VerifiedFileState(url) == previous { return }
    guard validHash(hash), PortraitCandidateCoding.digest(data) == hash else {
      throw PortraitCandidateStoreError.invalidAsset(hash)
    }
    if FileManager.default.fileExists(atPath: url.path) { _ = try readAsset(hash); return }
    try data.write(to: url, options: .atomic)
    let handle = try FileHandle(forWritingTo: url)
    try handle.synchronize()
    try handle.close()
    _ = try readAsset(hash)
  }
}

extension PortraitCandidateStore {
  /// Independent read-only work deliberately bypasses the serialized installer:
  /// a cold full archive validation must not hold the photo picker behind it.
  /// Every result is still bound to the committed index and verified file bytes.
  nonisolated func loadPhotoPage(after previous: PortraitPhotoPageCursor? = nil,
    limit requestedLimit: Int = 100) throws -> PortraitPhotoPage {
    let limit = min(100, max(1, requestedLimit))
    let url = browseCommitURL
    guard FileManager.default.fileExists(atPath: url.path) else {
      var isDirectory: ObjCBool = false
      if FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), !isDirectory.boolValue {
        throw PortraitCandidateStoreError.invalidIndex("The archive location is not a directory.")
      }
      return .init(photos: [], next: nil, savedStyles: [], candidateRecordsRead: 0)
    }
    let (envelope, state) = try Self.browseIndex(url)
    if let previous, previous.indexState != state { throw PortraitPhotoBrowserError.archiveChanged }
    var cursor = previous ?? .init(indexState: state)
    let catalog = try browseCatalog(envelope)
    var photos: [PortraitPhotoReference] = []
    var recordsRead = 0
    if cursor.sourceOffset < catalog.sources.count {
      let end = min(catalog.sources.count, cursor.sourceOffset + limit)
      for source in catalog.sources[cursor.sourceOffset..<end] {
        if Self.isBrowsable(source, tombstones: catalog.tombstones), cursor.seen.insert(source.id).inserted {
          photos.append(source)
        }
      }
      cursor.sourceOffset = end
    } else if !catalog.hasCompleteCatalog {
      // Older indexes lack per-photo metadata. Scan at most one bounded batch
      // of backwards candidate references per scroll request, skipping programs,
      // analyzed rasters, thumbnails, labels and attempt records entirely.
      let end = min(catalog.candidates.count, cursor.candidateOffset + limit)
      for offset in cursor.candidateOffset..<end {
        try Task.checkCancellation()
        let candidate = try browseCandidate(catalog.candidates[offset])
        recordsRead += catalog.candidates[offset].recordSHA256 == nil ? 0 : 1
        guard candidate.pose != nil,
          !catalog.tombstones.contains(where: { $0.kind != .label
            && $0.affectedCandidateIDs.contains(candidate.id) && candidate.createdAt <= $0.createdAt }) else { continue }
        let source = PortraitPhotoReference(candidate: candidate,
          recordSHA256: catalog.candidates[offset].recordSHA256)
        if Self.isBrowsable(source, tombstones: catalog.tombstones), cursor.seen.insert(source.id).inserted {
          photos.append(source)
        }
      }
      cursor.candidateOffset = end
    }
    guard try VerifiedFileState(url) == state else { throw PortraitPhotoBrowserError.archiveChanged }
    let hasMore = cursor.sourceOffset < catalog.sources.count
      || (!catalog.hasCompleteCatalog && cursor.candidateOffset < catalog.candidates.count)
    return .init(photos: photos, next: hasMore ? cursor : nil,
      savedStyles: catalog.savedStyles, candidateRecordsRead: recordsRead)
  }

  nonisolated func loadPhoto(_ reference: PortraitPhotoReference) throws -> PortraitPhoto {
    let indexURL = browseCommitURL
    let (envelope, state) = try Self.browseIndex(indexURL)
    let catalog = try browseCatalog(envelope)
    // A new candidate can update legacy-derived display metadata without
    // changing source identity. Use current committed provenance for that exact
    // ID/hash, rather than permanently breaking an already-visible tile.
    let currentSource = catalog.sources.first { $0.id == reference.id && $0.sourceSHA256 == reference.sourceSHA256 }
    var isCommitted = currentSource != nil
    if !isCommitted, !catalog.hasCompleteCatalog, let hash = reference.candidateRecordSHA256,
      let candidate = catalog.candidates.first(where: { $0.recordSHA256 == hash }) {
      let metadata = try browseCandidate(candidate)
      isCommitted = metadata.pose != nil
        && PortraitPhotoReference(candidate: metadata, recordSHA256: hash) == reference
        && !catalog.tombstones.contains(where: { $0.kind != .label
          && $0.affectedCandidateIDs.contains(metadata.id) && metadata.createdAt <= $0.createdAt })
    }
    if !isCommitted, !catalog.hasCompleteCatalog, reference.candidateRecordSHA256 == nil {
      isCommitted = catalog.candidates.contains { candidate in
        guard let metadata = candidate.embedded, metadata.pose != nil else { return false }
        return PortraitPhotoReference(candidate: metadata, recordSHA256: nil) == reference
          && !catalog.tombstones.contains(where: { $0.kind != .label
            && $0.affectedCandidateIDs.contains(metadata.id) && metadata.createdAt <= $0.createdAt })
      }
    }
    let source = currentSource ?? reference
    guard isCommitted, Self.isBrowsable(reference, tombstones: catalog.tombstones),
      Self.isBrowsable(source, tombstones: catalog.tombstones) else {
      throw PortraitPhotoBrowserError.sourceUnavailable
    }
    try Task.checkCancellation()
    let (bytes, _) = try VerifiedFileState.read(browsePayloadRoot.appendingPathComponent("assets")
      .appendingPathComponent(reference.sourceSHA256))
    let photo = try source.materialize(source: bytes)
    guard try VerifiedFileState(indexURL) == state else { throw PortraitPhotoBrowserError.archiveChanged }
    return photo
  }

  nonisolated var browsePayloadRoot: URL { canonicalLibraryCommitted ? directoryURL : legacyDirectoryURL }
  nonisolated var browseCommitURL: URL { canonicalLibraryCommitted ? databaseURL : legacySourceIndexURL }

  nonisolated private static func browseIndex(_ url: URL) throws -> (IndexEnvelope, VerifiedFileState) {
    if url.pathExtension == "sqlite" {
      let db = try PortraitLibraryDatabase(url:url,readOnly:true)
      let state = try VerifiedFileState(url)
      let payload = try PortraitCandidateCoding.encoder().encode(db.index())
      guard try VerifiedFileState(url) == state else { throw PortraitLibraryError.staleGeneration }
      return (.init(schemaVersion:4,sha256:PortraitCandidateCoding.digest(payload),payload:payload),state)
    }
    let (bytes, state) = try VerifiedFileState.read(url)
    let envelope = try JSONDecoder().decode(IndexEnvelope.self, from: bytes)
    guard [1, 2, 3, 4].contains(envelope.schemaVersion) else {
      throw PortraitCandidateStoreError.unsupportedVersion(envelope.schemaVersion)
    }
    guard PortraitCandidateCoding.digest(envelope.payload) == envelope.sha256 else {
      throw PortraitCandidateStoreError.invalidIndex("checksum mismatch; original file preserved")
    }
    return (envelope, state)
  }

  nonisolated private func browseCatalog(_ envelope: IndexEnvelope) throws -> PhotoBrowseCatalog {
    if envelope.schemaVersion >= 3 {
      let indexed = try JSONDecoder().decode(IndexedArchive.self, from: envelope.payload)
      guard [3, 4].contains(indexed.schemaVersion) else { throw PortraitCandidateStoreError.unsupportedVersion(indexed.schemaVersion) }
      let sources = indexed.photoCatalog ?? (indexed.sourcePhotos ?? []).sorted(by: Self.newestPhotoFirst)
      guard Set(sources.map(\.id)).count == sources.count else {
        throw PortraitCandidateStoreError.invalidIndex("duplicate source photo identity")
      }
      return .init(sources: sources,
        candidates: indexed.entries.reversed().map { .init(id: $0.candidateID, recordSHA256: $0.candidateSHA256) },
        tombstones: indexed.tombstones, savedStyles: indexed.savedStyles ?? [],
        hasCompleteCatalog: indexed.photoCatalog != nil)
    }
    var bytes = envelope.payload
    var styles: [PortraitSavedStyle] = []
    if envelope.schemaVersion == 2 {
      let manifest = try JSONDecoder().decode(ArchiveManifest.self, from: bytes)
      bytes = try browseRecord(manifest.recordSHA256)
      styles = manifest.savedStyles ?? []
    }
    // Embedded/bulk legacy JSON still needs checksum/parsing; its programs and
    // assets are never decoded or admitted by this advisory reader.
    let legacy = try JSONDecoder().decode(LegacyPhotoCatalog.self, from: bytes)
    guard [1, 2].contains(legacy.schemaVersion) else {
      throw PortraitCandidateStoreError.unsupportedVersion(legacy.schemaVersion)
    }
    return .init(sources: (legacy.sourcePhotos ?? []).sorted(by: Self.newestPhotoFirst),
      candidates: legacy.entries.reversed().map { .init(id: $0.candidate.id, embedded: $0.candidate) },
      tombstones: legacy.tombstones, savedStyles: legacy.savedStyles ?? styles, hasCompleteCatalog: false)
  }

  nonisolated private func browseRecord(_ hash: String) throws -> Data {
    guard Self.browseHashIsValid(hash) else { throw PortraitCandidateStoreError.invalidIndex("invalid record identity") }
    let (bytes, _) = try VerifiedFileState.read(browsePayloadRoot.appendingPathComponent("records").appendingPathComponent(hash))
    guard PortraitCandidateCoding.digest(bytes) == hash else { throw PortraitCandidateStoreError.invalidIndex("record checksum mismatch") }
    return bytes
  }

  nonisolated private func browseCandidate(_ reference: CandidatePhotoReference) throws -> CandidatePhotoMetadata {
    if let embedded = reference.embedded { return embedded }
    let candidate = try JSONDecoder().decode(CandidatePhotoMetadata.self,
      from: browseRecord(reference.recordSHA256!))
    guard candidate.id == reference.id else { throw PortraitCandidateStoreError.invalidIndex("candidate record identity mismatch") }
    return candidate
  }

  nonisolated private static func browseHashIsValid(_ hash: String) -> Bool {
    hash.count == 64 && hash.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }

  nonisolated private static func isBrowsable(_ source: PortraitPhotoReference,
    tombstones: [PortraitArchiveTombstone]) -> Bool {
    if tombstones.contains(where:{$0.kind == .photo && $0.identity.lowercased() == source.id.uuidString.lowercased()}) { return false }
    return browseHashIsValid(source.sourceSHA256) && !tombstones.contains {
      $0.kind == .source && $0.identity == source.sourceSHA256 && source.capturedAt <= $0.createdAt
    }
  }

  nonisolated private static func newestPhotoFirst(_ lhs: PortraitPhotoReference, _ rhs: PortraitPhotoReference) -> Bool {
    lhs.capturedAt == rhs.capturedAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.capturedAt > rhs.capturedAt
  }

  nonisolated private static func photoCatalog(sources: [PortraitPhotoReference],
    candidates: [PortraitCandidate], records: [String: String]) -> [PortraitPhotoReference] {
    var photos = sources
    var seen = Set(sources.map(\.id))
    for candidate in candidates.reversed() where candidate.renderPose != nil && seen.insert(candidate.photoID).inserted {
      photos.append(.init(candidate: candidate, recordSHA256: records[candidate.id]))
    }
    return photos.sorted(by: newestPhotoFirst)
  }
}

private struct PhotoBrowseCatalog {
  let sources: [PortraitPhotoReference]
  let candidates: [CandidatePhotoReference]
  let tombstones: [PortraitArchiveTombstone]
  let savedStyles: [PortraitSavedStyle]
  let hasCompleteCatalog: Bool
}

private struct CandidatePhotoReference {
  let id: String
  var recordSHA256: String? = nil
  var embedded: CandidatePhotoMetadata? = nil
}

fileprivate struct CandidatePhotoMetadata: Decodable {
  private struct Program: Decodable {
    struct Source: Decodable { let kind: String; let sourceIdentifier: String }
    let source: Source
  }
  let id: String
  let sourceSHA256: String
  let photoID: UUID
  let captureSessionID: UUID
  let createdAt: Date
  private let recordedPose: PortraitPose?
  private let program: Program
  let sourcePixelExtent: PortraitSourceCropExtent?
  enum CodingKeys: String, CodingKey {
    case id, sourceSHA256, photoID, captureSessionID, createdAt, program, sourcePixelExtent
    case recordedPose = "pose"
  }
  var pose: PortraitPose? {
    if let recordedPose { return recordedPose }
    let source = program.source
    guard source.kind == "portrait", source.sourceIdentifier.hasPrefix("portrait-v3|") else { return nil }
    let tokens = source.sourceIdentifier.split(separator: "|").filter { $0.hasPrefix("pose=") }
    guard tokens.count == 1, let token = tokens.first else { return nil }
    return PortraitPose(rawValue: String(token.dropFirst(5)))
  }
}

private struct LegacyPhotoCatalog: Decodable {
  struct Entry: Decodable { let candidate: CandidatePhotoMetadata }
  let schemaVersion: Int
  let entries: [Entry]
  let tombstones: [PortraitArchiveTombstone]
  let sourcePhotos: [PortraitPhotoReference]?
  let savedStyles: [PortraitSavedStyle]?
}

struct IndexEnvelope: Codable {
  let schemaVersion: Int
  let sha256: String
  let payload: Data
}

/// One checksummed commit binds the cheap recipes and immutable bulk records.
/// This is an index format, not a second archive or a mutable recipe cache.
private struct ArchiveManifest: Codable {
  let recordSHA256: String
  let savedStyles: [PortraitSavedStyle]?
}

private struct LegacyStyleCatalog: Decodable {
  let schemaVersion: Int
  let savedStyles: [PortraitSavedStyle]?
}

private struct StoredArchive: Codable {
  let schemaVersion: Int
  let entries: [StoredEntry]
  let labels: [PortraitLabelRevision]
  let tombstones: [PortraitArchiveTombstone]
  let savedStyles: [PortraitSavedStyle]?
  let sourcePhotos: [PortraitPhotoReference]?
  var labelPhotoIDs: [String:UUID]? = nil
  var photoCaptureTimeUnknownIDs: [UUID]? = nil
  init(entries: [StoredEntry], labels: [PortraitLabelRevision], indexed: IndexedArchive) {
    schemaVersion = 2; self.entries = entries; self.labels = labels
    tombstones = indexed.tombstones; savedStyles = indexed.savedStyles; sourcePhotos = indexed.sourcePhotos
    labelPhotoIDs = indexed.labelPhotoIDs
    let unknown = (indexed.sourcePhotos ?? []).filter { !($0.captureTimeKnown ?? ($0.candidateRecordSHA256 == nil)) }.map(\.id)
    photoCaptureTimeUnknownIDs = unknown.isEmpty ? nil : unknown.sorted { $0.uuidString < $1.uuidString }
  }
  init(_ archive: PortraitCandidateArchive, includeSavedStyles: Bool = true) {
    // Older readers reject this bulk schema instead of silently dropping photos.
    schemaVersion = 2
    entries = archive.entries.map { StoredEntry(candidate: StoredCandidate($0.candidate), reasons: $0.reasons, exploration: $0.exploration, attempt: $0.attempt) }
    labels = archive.labels
    tombstones = archive.tombstones
    savedStyles = includeSavedStyles ? archive.savedStyles : nil
    sourcePhotos = archive.sourcePhotos?.map { PortraitPhotoReference($0) }
    labelPhotoIDs = archive.labelPhotoIDs
    photoCaptureTimeUnknownIDs = archive.photoCaptureTimeUnknownIDs
  }
}

/// Source metadata is committed independently of a successful render. Pixels
/// share the existing asset owner with candidates, never another photo store.
struct PortraitPhotoReference: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let sourceSHA256: String
  let label: String
  let capturedAt: Date
  let frameID: FrameID?
  let captureNanoseconds: UInt64?
  let pose: PortraitPose
  let sourcePixelExtent: PortraitSourceCropExtent?
  let captureSessionID: UUID
  let selectionProvenance: PortraitCaptureSelectionProvenance?
  var candidateRecordSHA256: String? = nil
  var captureTimeKnown: Bool? = nil

  init(_ photo: PortraitPhoto, sourceSHA256: String? = nil) {
    id = photo.id; self.sourceSHA256 = sourceSHA256 ?? PortraitCandidateCoding.digest(photo.data)
    label = photo.label; capturedAt = photo.capturedAt; frameID = photo.frameID
    captureNanoseconds = photo.captureNanoseconds; pose = photo.pose
    sourcePixelExtent = photo.sourcePixelExtent; captureSessionID = photo.captureSessionID
    selectionProvenance = photo.selectionProvenance
    captureTimeKnown = true
  }

  init(candidate: PortraitCandidate, recordSHA256: String?) {
    id = candidate.photoID; sourceSHA256 = candidate.sourceSHA256
    label = "Retained frame"; capturedAt = candidate.createdAt; frameID = nil
    captureNanoseconds = nil; pose = candidate.renderPose!
    sourcePixelExtent = candidate.sourcePixelExtent; captureSessionID = candidate.captureSessionID
    selectionProvenance = nil; candidateRecordSHA256 = recordSHA256
    captureTimeKnown = false
  }

  fileprivate init(candidate: CandidatePhotoMetadata, recordSHA256: String?) {
    id = candidate.photoID; sourceSHA256 = candidate.sourceSHA256
    label = "Retained frame"; capturedAt = candidate.createdAt; frameID = nil
    captureNanoseconds = nil; pose = candidate.pose!
    sourcePixelExtent = candidate.sourcePixelExtent; captureSessionID = candidate.captureSessionID
    selectionProvenance = nil; candidateRecordSHA256 = recordSHA256
    captureTimeKnown = false
  }

  func materialize(source: Data) throws -> PortraitPhoto {
    guard PortraitCandidateCoding.digest(source) == sourceSHA256 else {
      throw PortraitCandidateStoreError.invalidAsset(sourceSHA256)
    }
    return PortraitPhoto(id: id, data: source, label: label, capturedAt: capturedAt,
      frameID: frameID, captureNanoseconds: captureNanoseconds, pose: pose,
      sourcePixelExtent: sourcePixelExtent, captureSessionID: captureSessionID,
      selectionProvenance: selectionProvenance)
  }
}

private struct StoredEntry: Codable {
  let candidate: StoredCandidate
  let reasons: [PortraitRetentionEvent]
  let exploration: [PortraitExplorationRecord]?
  let attempt: PortraitAttemptRecord?
}

/// Payload metadata only; source bytes and exact analyzed raster each have one
/// content-addressed blob, independent of candidate/label count.
struct StoredCandidate: Codable, Equatable {
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

/// One compact commit references immutable candidate records and shared assets.
/// Retention/feedback metadata never copies the candidate's DrawingProgram.
struct IndexedArchive: Codable {
  let schemaVersion: Int
  let entries: [IndexedEntry]
  let labels: [LabelReference]
  let tombstones: [PortraitArchiveTombstone]
  let savedStyles: [PortraitSavedStyle]?
  let sourcePhotos: [PortraitPhotoReference]?
  var photoCatalog: [PortraitPhotoReference]? = nil
  var savedDrawings: [SavedDrawingRecordReference]? = nil
  var drawingCatalog: [SavedDrawingSummary]? = nil
  var labelPhotoIDs: [String:UUID]? = nil
}

struct IndexedEntry: Codable {
  let candidateID: String
  let candidateSHA256: String
  let metadataSHA256: String
}

struct EntryMetadata: Codable, Equatable {
  let candidateID: String
  let reasons: [PortraitRetentionEvent]
  let exploration: [PortraitExplorationRecord]?
  let attempt: PortraitAttemptRecord?
}

struct LabelReference: Codable {
  let id: UUID
  let sha256: String
}

struct SavedDrawingRecordReference: Codable {
  let id: String
  let candidateID: String?
  let recordSHA256: String?
}

struct StoredDrawing: Codable {
  let id: String
  let program: DrawingProgram
  let createdAt: Date
  init(_ drawing: SavedDrawing) { id = drawing.id; program = drawing.program; createdAt = drawing.createdAt }
  func materialize() throws -> SavedDrawing {
    let drawing = SavedDrawing(program: program, createdAt: createdAt)
    guard drawing.id == id else { throw PortraitCandidateError.integrityMismatch }
    try drawing.validateIntegrity()
    return drawing
  }
}

extension PortraitCandidateStore {
  nonisolated static func savedDrawings(in archive: PortraitCandidateArchive) -> [SavedDrawing] {
    var drawings = archive.savedDrawings ?? []
    var seen = Set(drawings.map(\.id))
    drawings += archive.entries.filter { !$0.reasons.isEmpty && seen.insert($0.id).inserted }
      .map { SavedDrawing(candidate: $0.candidate) }
    return drawings
  }

  nonisolated private static func drawingCatalog(_ archive: PortraitCandidateArchive) -> [SavedDrawingSummary] {
    let drawings = savedDrawings(in: archive)
    let savedIDs = Set(drawings.map(\.id))
    var summaries = archive.entries.map { entry in
      SavedDrawingSummary(SavedDrawing(candidate: entry.candidate), isSaved: savedIDs.contains(entry.id),
        feedback: entry.attempt?.feedback)
    }
    let seen = Set(summaries.map(\.id))
    summaries += drawings.filter { !seen.contains($0.id) }.map { SavedDrawingSummary($0) }
    return summaries.sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt }
  }

  /// Browse immutable metadata independently from the canonical installer. Only
  /// selected drawing reads decode vectors, analyzed raster and source pixels.
  nonisolated func loadDrawingPage(after previous: SavedDrawingPageCursor? = nil,
    limit requestedLimit: Int = 100, photoID: UUID? = nil, style: PortraitStyle? = nil) throws -> SavedDrawingPage {
    let url = browseCommitURL
    guard FileManager.default.fileExists(atPath: url.path) else {
      var isDirectory: ObjCBool = false
      if FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), !isDirectory.boolValue {
        throw PortraitCandidateStoreError.invalidIndex("The archive location is not a directory.")
      }
      return .init(drawings: [], next: nil, candidateRecordsRead: 0)
    }
    if url == databaseURL,let photoID {
      let state = try VerifiedFileState(url)
      if let previous,previous.indexState != state { throw SavedDrawingBrowserError.archiveChanged }
      let db = try PortraitLibraryDatabase(url:url,readOnly:true)
      try db.execute("BEGIN")
      defer { try? db.execute("ROLLBACK") }
      let limit = min(100,max(1,requestedLimit)),offset = previous?.offset ?? 0
      var predicate = "photo_id=? AND deleted=0"
      var values: [String?] = [photoID.uuidString.lowercased()]
      if let style { predicate += " AND json_extract(summary,'$.recipe.style')=?";values.append(style.rawValue) }
      values += [String(limit+1),String(offset)]
      let rows = try db.rows("SELECT id FROM drawing WHERE "+predicate+" ORDER BY created_at DESC,id LIMIT ? OFFSET ?",values)
      let selected = Array(rows.prefix(limit))
      let summaries = try selected.map { try db.checkedDrawing($0[0]!).summary }
      guard try VerifiedFileState(url) == state else { throw SavedDrawingBrowserError.archiveChanged }
      let next: SavedDrawingPageCursor? = rows.count > limit ? .init(indexState:state,offset:offset+selected.count) : nil
      return .init(drawings:summaries,next:next,candidateRecordsRead:0)
    }
    let (envelope, state) = try Self.browseIndex(url)
    if let previous, previous.indexState != state { throw SavedDrawingBrowserError.archiveChanged }
    var cursor = previous ?? .init(indexState: state)
    let limit = min(100, max(1, requestedLimit))
    var summaries: [SavedDrawingSummary] = []
    var count: Int
    var recordsRead = 0
    if envelope.schemaVersion >= 3 {
      let indexed = try JSONDecoder().decode(IndexedArchive.self, from: envelope.payload)
      guard [3, 4].contains(indexed.schemaVersion) else { throw PortraitCandidateStoreError.unsupportedVersion(indexed.schemaVersion) }
      if let completeCatalog = indexed.drawingCatalog {
        let catalog = completeCatalog.filter { (photoID == nil || $0.photoID == photoID) && (style == nil || $0.style == style) }
        guard Set(catalog.map(\.id)).count == catalog.count else {
          throw PortraitCandidateStoreError.invalidIndex("duplicate drawing catalog identity")
        }
        count = catalog.count
        let end = min(count, cursor.offset + limit)
        summaries = Array(catalog[cursor.offset..<end])
        cursor.offset = end
      } else {
        // Old v3 records have no compact drawing catalog. Decode only metadata
        // for one bounded batch, never the full canonical archive or assets.
        let entries = Array(indexed.entries.reversed())
        count = entries.count
        let end = min(count, cursor.offset + limit)
        for reference in entries[cursor.offset..<end] {
          try Task.checkCancellation()
          let candidate = try JSONDecoder().decode(CandidateDrawingMetadata.self,
            from: browseRecord(reference.candidateSHA256))
          let metadata = try JSONDecoder().decode(EntryBrowseMetadata.self, from: browseRecord(reference.metadataSHA256))
          guard candidate.id == reference.candidateID, metadata.candidateID == candidate.id else {
            throw PortraitCandidateStoreError.invalidIndex("drawing metadata identity mismatch")
          }
          summaries.append(candidate.summary(isSaved: !metadata.reasons.isEmpty, feedback: metadata.attempt?.feedback))
          recordsRead += 1
        }
        cursor.offset = end
      }
      summaries.removeAll { Self.drawingWasDeleted($0, tombstones: indexed.tombstones) }
    } else {
      var bytes = envelope.payload
      if envelope.schemaVersion == 2 {
        let manifest = try JSONDecoder().decode(ArchiveManifest.self, from: bytes)
        bytes = try browseRecord(manifest.recordSHA256)
      }
      let legacy = try JSONDecoder().decode(LegacyDrawingCatalog.self, from: bytes)
      guard [1, 2].contains(legacy.schemaVersion) else { throw PortraitCandidateStoreError.unsupportedVersion(legacy.schemaVersion) }
      let entries = Array(legacy.entries.reversed())
      count = entries.count
      let end = min(count, cursor.offset + limit)
      summaries = entries[cursor.offset..<end].map {
        $0.candidate.summary(isSaved: !$0.reasons.isEmpty, feedback: $0.attempt?.feedback)
      }.filter { !Self.drawingWasDeleted($0, tombstones: legacy.tombstones) }
      cursor.offset = end
    }
    summaries = summaries.filter { (photoID == nil || $0.photoID == photoID) && (style == nil || $0.style == style) }
    try Task.checkCancellation()
    guard try VerifiedFileState(url) == state else { throw SavedDrawingBrowserError.archiveChanged }
    return .init(drawings: summaries, next: cursor.offset < count ? cursor : nil, candidateRecordsRead: recordsRead)
  }

  nonisolated func loadDrawing(_ id: String) throws -> SavedDrawing {
    let url = browseCommitURL
    let (envelope, state) = try Self.browseIndex(url)
    let drawing: SavedDrawing
    let tombstones: [PortraitArchiveTombstone]
    if envelope.schemaVersion >= 3 {
      let indexed = try JSONDecoder().decode(IndexedArchive.self, from: envelope.payload)
      tombstones = indexed.tombstones
      if let reference = indexed.entries.first(where: { $0.candidateID == id }) {
        let candidate = try JSONDecoder().decode(StoredCandidate.self, from: browseRecord(reference.candidateSHA256))
        guard candidate.id == id else { throw PortraitCandidateError.integrityMismatch }
        let source = try browseAsset(candidate.sourceSHA256)
        let raster = try browseAsset(candidate.rasterSHA256)
        drawing = SavedDrawing(candidate: try candidate.materialize(source: source, raster: raster))
      } else if let reference = indexed.savedDrawings?.first(where: { $0.id == id }),
        reference.candidateID == nil, let hash = reference.recordSHA256 {
        drawing = try JSONDecoder().decode(StoredDrawing.self, from: browseRecord(hash)).materialize()
        guard drawing.id == id else { throw PortraitCandidateError.integrityMismatch }
      } else { throw SavedDrawingBrowserError.drawingUnavailable }
    } else {
      var bytes = envelope.payload
      if envelope.schemaVersion == 2 {
        let manifest = try JSONDecoder().decode(ArchiveManifest.self, from: bytes)
        bytes = try browseRecord(manifest.recordSHA256)
      }
      // Legacy payloads are monolithic. Decode the requested candidate only,
      // skipping other drawing programs rather than materializing the archive.
      let selected = try JSONDecoder().decode(SelectedLegacyDrawing.self, from: bytes, selectedID: id)
      guard let candidate = selected.candidate else { throw SavedDrawingBrowserError.drawingUnavailable }
      tombstones = selected.tombstones
      drawing = SavedDrawing(candidate: try candidate.materialize(source: browseAsset(candidate.sourceSHA256),
        raster: browseAsset(candidate.rasterSHA256)))
    }
    guard !Self.drawingWasDeleted(SavedDrawingSummary(drawing), tombstones: tombstones) else {
      throw SavedDrawingBrowserError.drawingUnavailable
    }
    try Task.checkCancellation()
    guard try VerifiedFileState(url) == state else { throw SavedDrawingBrowserError.archiveChanged }
    return drawing
  }

  nonisolated private func browseAsset(_ hash: String) throws -> Data {
    guard Self.browseHashIsValid(hash) else { throw PortraitCandidateStoreError.invalidAsset(hash) }
    let (bytes, _) = try VerifiedFileState.read(browsePayloadRoot.appendingPathComponent("assets").appendingPathComponent(hash))
    guard PortraitCandidateCoding.digest(bytes) == hash else { throw PortraitCandidateStoreError.invalidAsset(hash) }
    return bytes
  }

  nonisolated private static func drawingWasDeleted(_ drawing: SavedDrawingSummary,
    tombstones: [PortraitArchiveTombstone]) -> Bool {
    tombstones.contains { $0.kind != .label && drawing.createdAt <= $0.createdAt
      && ($0.affectedCandidateIDs.contains(drawing.id) || ($0.kind == .source && $0.identity == drawing.sourceSHA256)) }
  }
}

private struct CandidateDrawingMetadata: Decodable {
  struct Program: Decodable {
    struct Stroke: Decodable { let style: StrokeStyle }
    let contentHash: Digest
    let source: DrawingSourceProvenance
    let strokes: [Stroke]
  }
  let id: String
  let createdAt: Date
  let photoID: UUID
  let sourceSHA256: String
  let recipe: PortraitStyleRecipe
  let pose: PortraitPose?
  let program: Program
  func summary(isSaved: Bool, feedback: PortraitAttemptFeedback?) -> SavedDrawingSummary {
    .init(id: id, title: recipe.title, createdAt: createdAt,
      programContentHash: program.contentHash.description, programKind: program.source.kind,
      strokeCount: program.strokes.count, strokeStyle: program.strokes.first?.style, pose: pose,
      photoID: photoID, sourceSHA256: sourceSHA256, recipe: recipe, isSaved: isSaved, feedback: feedback)
  }
}

private struct AttemptFeedbackMetadata: Decodable {
  let feedbackRevisions: [PortraitAttemptFeedbackRevision]?
  var feedback: PortraitAttemptFeedback { feedbackRevisions?.last?.value ?? .unknown }
}

private struct EntryBrowseMetadata: Decodable {
  let candidateID: String
  let reasons: [PortraitRetentionEvent]
  let attempt: AttemptFeedbackMetadata?
}

private struct LegacyDrawingCatalog: Decodable {
  struct Entry: Decodable {
    let candidate: CandidateDrawingMetadata
    let reasons: [PortraitRetentionEvent]
    let attempt: AttemptFeedbackMetadata?
  }
  let schemaVersion: Int
  let entries: [Entry]
  let tombstones: [PortraitArchiveTombstone]
}

private let selectedDrawingIDKey = CodingUserInfoKey(rawValue: "selectedDrawingID")!
private struct SelectedLegacyDrawing: Decodable {
  struct Entry: Decodable {
    let candidate: StoredCandidate?
    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: Key.self)
      struct Identity: Decodable { let id: String }
      let metadata = try container.decode(Identity.self, forKey: .candidate)
      candidate = metadata.id == decoder.userInfo[selectedDrawingIDKey] as? String
        ? try container.decode(StoredCandidate.self, forKey: .candidate) : nil
    }
    enum Key: CodingKey { case candidate }
  }
  let candidate: StoredCandidate?
  let tombstones: [PortraitArchiveTombstone]
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: Key.self)
    candidate = try container.decode([Entry].self, forKey: .entries).compactMap(\.candidate).first
    tombstones = try container.decode([PortraitArchiveTombstone].self, forKey: .tombstones)
  }
  enum Key: CodingKey { case entries, tombstones }
}

private extension JSONDecoder {
  func decode<T: Decodable>(_ type: T.Type, from data: Data, selectedID: String) throws -> T {
    userInfo[selectedDrawingIDKey] = selectedID
    return try decode(type, from: data)
  }
}
