import PortraitArtists
import Darwin
import Foundation
import PlotterModel
import PlotterRuntime

/// Storage-only migration, invoked by the opt-in command harness. No App,
/// camera, controller, Learning or machine-session composition is initialized.
package enum PortraitLibraryReconciler {
  package struct Receipt: Codable {
    package let sourcePortraitSHA256: String
    package let sourceEvidenceSHA256: String
    package let backupManifestSHA256: String
    package let auditSHA256: String?
    package let photoCount: Int
    package let drawingCount: Int
    package let workCount: Int
    package let plottedWorkCount: Int
    package let quarantineCount: Int
    package let destination: String

    package init(
      sourcePortraitSHA256: String,
      sourceEvidenceSHA256: String,
      backupManifestSHA256: String,
      auditSHA256: String? = nil,
      photoCount: Int,
      drawingCount: Int,
      workCount: Int,
      plottedWorkCount: Int,
      quarantineCount: Int,
      destination: String
    ) {
      self.sourcePortraitSHA256 = sourcePortraitSHA256
      self.sourceEvidenceSHA256 = sourceEvidenceSHA256
      self.backupManifestSHA256 = backupManifestSHA256
      self.auditSHA256 = auditSHA256
      self.photoCount = photoCount
      self.drawingCount = drawingCount
      self.workCount = workCount
      self.plottedWorkCount = plottedWorkCount
      self.quarantineCount = quarantineCount
      self.destination = destination
    }
  }

  /// Promote an already verified immutable generation without rematerializing
  /// its historical rasters. The source database is copied by its actor through
  /// SQLite backup, and the destination is selected only after fresh input and
  /// payload verification. This operation accepts an absent destination only.
  package static func installValidatedGeneration(sourceLibrary: URL,destination: URL,
    legacyDirectory: URL,evidenceArchive: URL,backupDirectory: URL,expectedDatabaseSHA256: String,auditURL: URL? = nil) async throws -> Receipt {
    let manager = FileManager.default
    guard !manager.fileExists(atPath:destination.path),sourceLibrary.standardizedFileURL != destination.standardizedFileURL else {
      throw PortraitLibraryError.database("validated generation installation requires a new destination")
    }
    guard expectedDatabaseSHA256.count == 64,
      try PortraitCandidateCoding.digest(Data(contentsOf:sourceLibrary.appendingPathComponent("library-v1.sqlite"))) == expectedDatabaseSHA256 else {
      throw PortraitLibraryError.database("validated database differs from independently accepted generation")
    }
    let receiptBytes = try Data(contentsOf:sourceLibrary.appendingPathComponent("reconciliation-receipt.json"))
    let expected = try JSONDecoder().decode(Receipt.self,from:receiptBytes)
    guard URL(fileURLWithPath:expected.destination).standardizedFileURL == sourceLibrary.standardizedFileURL else {
      throw PortraitLibraryError.database("validated receipt source does not match")
    }
    if let auditHash = expected.auditSHA256 {
      guard let auditURL,try PortraitCandidateCoding.digest(Data(contentsOf:auditURL)) == auditHash else { throw PortraitLibraryError.database("validated audit changed") }
    }
    try verifySnapshotInputs(backupDirectory:backupDirectory,legacyDirectory:legacyDirectory,evidenceArchive:evidenceArchive,receipt:expected)
    let source = PortraitCandidateStore(directoryURL:sourceLibrary,legacyDirectoryURL:legacyDirectory,evidenceArchiveURL:evidenceArchive)
    try await source.ensureLibraryGraph();try await source.verifyLibraryIntegrity()
    try await source.verifySelectedPayloads()
    let counts = try await source.libraryCounts()
    guard counts.photos == expected.photoCount,counts.drawings == expected.drawingCount,counts.works == expected.workCount,
      counts.plotted == expected.plottedWorkCount,counts.quarantine == expected.quarantineCount else { throw PortraitLibraryError.database("validated generation counts changed") }
    let sourceState = try VerifiedFileState(sourceLibrary.appendingPathComponent("library-v1.sqlite"))
    let stagingRoot = destination.deletingLastPathComponent().appendingPathComponent("portrait-promotion-"+UUID().uuidString)
    let staging = stagingRoot.appendingPathComponent("PortraitLibrary")
    try manager.createDirectory(at:staging,withIntermediateDirectories:true)
    defer { try? manager.removeItem(at:stagingRoot) }
    try await source.backupDatabase(to:staging.appendingPathComponent("library-v1.sqlite"))
    for name in ["records","assets"] {
      let output = staging.appendingPathComponent(name)
      try manager.createDirectory(at:output,withIntermediateDirectories:true)
      for file in try manager.contentsOfDirectory(at:sourceLibrary.appendingPathComponent(name),includingPropertiesForKeys:nil) {
        let bytes = try Data(contentsOf:file)
        guard file.lastPathComponent.count == 64,PortraitCandidateCoding.digest(bytes) == file.lastPathComponent else {
          throw PortraitLibraryError.database("validated immutable payload changed")
        }
        try durableWrite(bytes,to:output.appendingPathComponent(file.lastPathComponent))
      }
    }
    let stagedQuarantine = stagingRoot.appendingPathComponent("PortraitQuarantine")
    try installQuarantine(from:sourceLibrary.deletingLastPathComponent().appendingPathComponent("PortraitQuarantine"),to:stagedQuarantine,copy:true)
    let stagedOwner = PortraitCandidateStore(directoryURL:staging,legacyDirectoryURL:legacyDirectory,evidenceArchiveURL:evidenceArchive)
    try await stagedOwner.verifyLibraryIntegrity()
    try await stagedOwner.verifySelectedPayloads()
    for filter in PortraitLibraryFilter.allCases {
      var cursor: PortraitLibraryCursor?
      repeat {
        let page = try await stagedOwner.librarySnapshot(filter:filter,after:cursor)
        cursor = page.next
      } while cursor != nil
    }
    guard try VerifiedFileState(sourceLibrary.appendingPathComponent("library-v1.sqlite")) == sourceState,
      try PortraitCandidateCoding.digest(Data(contentsOf:sourceLibrary.appendingPathComponent("library-v1.sqlite"))) == expectedDatabaseSHA256 else { throw PortraitLibraryError.staleGeneration }
    try verifySnapshotInputs(backupDirectory:backupDirectory,legacyDirectory:legacyDirectory,evidenceArchive:evidenceArchive,receipt:expected)
    let receipt = Receipt(sourcePortraitSHA256:expected.sourcePortraitSHA256,sourceEvidenceSHA256:expected.sourceEvidenceSHA256,
      backupManifestSHA256:expected.backupManifestSHA256,auditSHA256:expected.auditSHA256,photoCount:counts.photos,drawingCount:counts.drawings,
      workCount:counts.works,plottedWorkCount:counts.plotted,quarantineCount:counts.quarantine,destination:destination.path)
    try durableWrite(PortraitCandidateCoding.encoder().encode(receipt),to:staging.appendingPathComponent("reconciliation-receipt.json"))
    let selectedQuarantine = destination.deletingLastPathComponent().appendingPathComponent("PortraitQuarantine")
    try installQuarantine(from:stagedQuarantine,to:selectedQuarantine)
    try await stagedOwner.verifySelectedPayloads(quarantineDirectory:selectedQuarantine)
    guard !manager.fileExists(atPath:destination.path),
      try PortraitCandidateCoding.digest(Data(contentsOf:legacyDirectory.appendingPathComponent("index-v1.json"))) == expected.sourcePortraitSHA256,
      try PortraitCandidateCoding.digest(Data(contentsOf:evidenceArchive)) == expected.sourceEvidenceSHA256 else { throw PortraitLibraryError.staleGeneration }
    try manager.moveItem(at:staging,to:destination);try synchronizeDirectory(destination.deletingLastPathComponent())
    return receipt
  }

  private static func verifySnapshotInputs(backupDirectory:URL,legacyDirectory:URL,evidenceArchive:URL,receipt:Receipt) throws {
    let bytes = try Data(contentsOf:backupDirectory.appendingPathComponent("snapshot-manifest.json"))
    guard PortraitCandidateCoding.digest(bytes) == receipt.backupManifestSHA256,
      let manifest = try JSONSerialization.jsonObject(with:bytes) as? [String:Any],
      manifest["portraitSHA256"] as? String == receipt.sourcePortraitSHA256,
      manifest["evidenceSHA256"] as? String == receipt.sourceEvidenceSHA256,
      let files = manifest["files"] as? [[String:Any]] else { throw PortraitLibraryError.database("verified snapshot receipt changed") }
    for file in files {
      guard let path = file["path"] as? String,!path.hasPrefix("/"),!path.split(separator:"/").contains(".."),
        let hash = file["sha256"] as? String,let count = file["byteCount"] as? Int else { throw PortraitLibraryError.database("verified snapshot inventory invalid") }
      let copied = try Data(contentsOf:backupDirectory.appendingPathComponent(path))
      guard copied.count == count,PortraitCandidateCoding.digest(copied) == hash else { throw PortraitLibraryError.database("verified snapshot payload changed") }
      let original:URL
      if path == "PortraitCandidates/verified-snapshot.json" { continue }
      else if path.hasPrefix("PortraitCandidates/") { original = legacyDirectory.appendingPathComponent(String(path.dropFirst("PortraitCandidates/".count))) }
      else if path.hasPrefix("DrawingEvidence/") { original = evidenceArchive.deletingLastPathComponent().appendingPathComponent(String(path.dropFirst("DrawingEvidence/".count))) }
      else { throw PortraitLibraryError.database("verified snapshot inventory namespace invalid") }
      guard try PortraitCandidateCoding.digest(Data(contentsOf:original)) == hash else { throw PortraitLibraryError.staleGeneration }
    }
    guard try PortraitCandidateCoding.digest(Data(contentsOf:legacyDirectory.appendingPathComponent("index-v1.json"))) == receipt.sourcePortraitSHA256,
      try PortraitCandidateCoding.digest(Data(contentsOf:evidenceArchive)) == receipt.sourceEvidenceSHA256 else { throw PortraitLibraryError.staleGeneration }
  }

  private static func installQuarantine(from source:URL,to target:URL,copy:Bool = false) throws {
    let manager = FileManager.default
    guard manager.fileExists(atPath:source.path) else { return }
    try manager.createDirectory(at:target,withIntermediateDirectories:true)
    for child in try manager.contentsOfDirectory(at:source,includingPropertiesForKeys:nil) {
      let output = target.appendingPathComponent(child.lastPathComponent)
      try manager.createDirectory(at:output,withIntermediateDirectories:true)
      for file in try manager.contentsOfDirectory(at:child,includingPropertiesForKeys:nil) {
        let bytes = try Data(contentsOf:file),hash = PortraitCandidateCoding.digest(bytes)
        guard String(file.lastPathComponent.prefix(64)) == hash else { throw PortraitLibraryError.database("selected quarantine bytes changed") }
        let final = output.appendingPathComponent(file.lastPathComponent)
        if manager.fileExists(atPath:final.path) {
          guard PortraitCandidateCoding.digest(try Data(contentsOf:final)) == hash else { throw PortraitLibraryError.database("existing quarantine bytes changed") }
        } else if copy { try durableWrite(bytes,to:final) }
        else { try manager.moveItem(at:file,to:final) }
        guard PortraitCandidateCoding.digest(try Data(contentsOf:final)) == hash else { throw PortraitLibraryError.database("selected quarantine bytes changed") }
      }
      try synchronizeDirectory(output)
    }
    try synchronizeDirectory(target)
  }

  package static func run(legacyDirectory: URL,evidenceArchive: URL,destination: URL,
    backupDirectory: URL,auditURL: URL? = nil) async throws -> Receipt {
    let manager = FileManager.default
    for original in [legacyDirectory,evidenceArchive.deletingLastPathComponent(),destination] {
      guard !backupDirectory.standardizedFileURL.path.hasPrefix(original.standardizedFileURL.path + "/"),backupDirectory.standardizedFileURL != original.standardizedFileURL else { throw PortraitLibraryError.database("backup must be independent of active stores") }
    }
    let snapshot = try snapshotInputs(legacyDirectory:legacyDirectory,evidenceArchive:evidenceArchive,backupDirectory:backupDirectory)
    let stagingRoot = destination.deletingLastPathComponent().appendingPathComponent("portrait-reconciliation-staging-" + UUID().uuidString)
    let staging = stagingRoot.appendingPathComponent("PortraitLibrary")
    try manager.createDirectory(at:staging,withIntermediateDirectories:true)
    defer { try? manager.removeItem(at:stagingRoot) }
    if manager.fileExists(atPath:destination.appendingPathComponent("library-v1.sqlite").path) {
      let source = PortraitCandidateStore(directoryURL:destination,legacyDirectoryURL:legacyDirectory,evidenceArchiveURL:evidenceArchive)
      try await source.backupDatabase(to:staging.appendingPathComponent("library-v1.sqlite"))
      for name in ["assets","records"] {
        let input = destination.appendingPathComponent(name),output = staging.appendingPathComponent(name)
        if manager.fileExists(atPath:input.path) { try manager.copyItem(at:input,to:output) }
      }
    }
    let legacy = backupDirectory.appendingPathComponent("PortraitCandidates")
    let evidence = backupDirectory.appendingPathComponent("DrawingEvidence").appendingPathComponent(evidenceArchive.lastPathComponent)
    let store = PortraitCandidateStore(directoryURL:staging,legacyDirectoryURL:legacy)
    let loaded = await store.load()
    guard loaded.canWrite else { throw PortraitLibraryError.database(loaded.issues.joined(separator:" ")) }
    let raw = try PortraitEvidenceSource.read(evidence)
    let auditBytes = try auditURL.map { try Data(contentsOf:$0) }
    let auditHash = auditBytes.map(PortraitCandidateCoding.digest)
    let proofs = try auditBytes.map { try auditProofs($0,sha256:auditHash!,generation:raw.sha256,raw:raw.archive,evidenceURL:evidence) } ?? []
    try await store.configureEvidenceArchiveURL(evidence)
    try await store.reconcileEvidence(archive:raw.archive,generation:raw.sha256,recoveryProofs:proofs)
    let counts = try await store.libraryCounts()
    try await store.verifyLibraryIntegrity()
    try await store.verifySelectedPayloads()
    // No generation becomes selected if either original manifest has drifted.
    guard try PortraitCandidateCoding.digest(Data(contentsOf:legacyDirectory.appendingPathComponent("index-v1.json"))) == snapshot.portrait,
      try PortraitCandidateCoding.digest(Data(contentsOf:evidenceArchive)) == snapshot.evidence else { throw PortraitLibraryError.staleGeneration }
    let receipt = Receipt(sourcePortraitSHA256:snapshot.portrait,sourceEvidenceSHA256:snapshot.evidence,
      backupManifestSHA256:snapshot.manifest,auditSHA256:auditHash,photoCount:counts.photos,drawingCount:counts.drawings,
      workCount:counts.works,plottedWorkCount:counts.plotted,quarantineCount:counts.quarantine,destination:destination.path)
    let receiptBytes = try PortraitCandidateCoding.encoder().encode(receipt)
    try durableWrite(receiptBytes,to:staging.appendingPathComponent("reconciliation-receipt.json"))
    // Preserve independent quarantine before selecting any new SQL generation.
    let quarantine = stagingRoot.appendingPathComponent("PortraitQuarantine")
    try installQuarantine(from:quarantine,to:destination.deletingLastPathComponent().appendingPathComponent("PortraitQuarantine"))
    if manager.fileExists(atPath:destination.path) {
      // New immutable bytes can coexist with the previous selected SQL graph.
      // Replace its closed DELETE-journal database in one atomic rename; never
      // copy a live database or create a missing-destination restart window.
      let current = PortraitCandidateStore(directoryURL:destination)
      let retained = backupDirectory.appendingPathComponent("previous-library.sqlite")
      try await current.backupDatabase(to:retained)
      let handle = try FileHandle(forWritingTo:retained);try handle.synchronize();try handle.close()
      for name in ["assets","records"] {
        let folder = staging.appendingPathComponent(name),target = destination.appendingPathComponent(name)
        try manager.createDirectory(at:target,withIntermediateDirectories:true)
        for file in try manager.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil) {
          let output = target.appendingPathComponent(file.lastPathComponent)
          let bytes = try Data(contentsOf:file),hash = PortraitCandidateCoding.digest(bytes)
          if manager.fileExists(atPath:output.path) {
            guard PortraitCandidateCoding.digest(try Data(contentsOf:output)) == hash else { throw PortraitLibraryError.database("existing immutable payload changed") }
          } else { try durableWrite(bytes,to:output) }
        }
      }
      let from = staging.appendingPathComponent("library-v1.sqlite"),to = destination.appendingPathComponent("library-v1.sqlite")
      let result = from.withUnsafeFileSystemRepresentation { source in to.withUnsafeFileSystemRepresentation { target in Darwin.rename(source!,target!) } }
      guard result == 0 else { throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno)) }
      try synchronizeDirectory(destination)
      try durableWrite(receiptBytes,to:destination.appendingPathComponent("reconciliation-receipt.json"))
    } else {
      try manager.moveItem(at:staging,to:destination)
      try synchronizeDirectory(destination.deletingLastPathComponent())
    }
    return receipt
  }

  private static func snapshotInputs(legacyDirectory:URL,evidenceArchive:URL,backupDirectory:URL) throws -> (portrait:String,evidence:String,manifest:String) {
    let manager = FileManager.default
    guard !manager.fileExists(atPath:backupDirectory.path) else { throw PortraitLibraryError.database("backup destination already exists; use a fresh snapshot directory") }
    let beforePortrait = PortraitCandidateCoding.digest(try Data(contentsOf:legacyDirectory.appendingPathComponent("index-v1.json")))
    let beforeEvidence = PortraitCandidateCoding.digest(try Data(contentsOf:evidenceArchive))
    try manager.createDirectory(at:backupDirectory,withIntermediateDirectories:true)
    let legacySnapshot = try PortraitLegacySnapshot.capture(from:legacyDirectory,into:backupDirectory.appendingPathComponent("LegacySnapshots"))
    try manager.moveItem(at:legacySnapshot.directory,to:backupDirectory.appendingPathComponent("PortraitCandidates"))
    try manager.copyItem(at:evidenceArchive.deletingLastPathComponent(),to:backupDirectory.appendingPathComponent("DrawingEvidence"))
    var selected: [[String:Any]] = []
    // Foundation enumerators resolve /var to /private/var. Derive relative
    // inventory paths from that same resolved root, never mismatched lengths.
    let inventoryRoot = backupDirectory.resolvingSymlinksInPath()
    guard let files = manager.enumerator(at:inventoryRoot,includingPropertiesForKeys:[.isRegularFileKey],options:[.skipsHiddenFiles]) else { throw PortraitLibraryError.database("snapshot inventory failed") }
    for case let file as URL in files {
      guard try file.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile == true else { continue }
      let bytes = try Data(contentsOf:file),hash = PortraitCandidateCoding.digest(bytes)
      let handle = try FileHandle(forWritingTo:file);try handle.synchronize();try handle.close()
      guard PortraitCandidateCoding.digest(try Data(contentsOf:file)) == hash else { throw PortraitLibraryError.database("snapshot checksum invalid") }
      let inventoryFile = file.resolvingSymlinksInPath()
      guard inventoryFile.path.hasPrefix(inventoryRoot.path + "/") else { throw PortraitLibraryError.database("snapshot inventory escaped its root") }
      selected.append(["path":String(inventoryFile.path.dropFirst(inventoryRoot.path.count+1)),"sha256":hash,"byteCount":bytes.count])
    }
    try synchronizeDirectory(backupDirectory)
    guard PortraitCandidateCoding.digest(try Data(contentsOf:legacyDirectory.appendingPathComponent("index-v1.json"))) == beforePortrait,
      PortraitCandidateCoding.digest(try Data(contentsOf:evidenceArchive)) == beforeEvidence else { throw PortraitLibraryError.staleGeneration }
    guard PortraitCandidateCoding.digest(try Data(contentsOf:backupDirectory.appendingPathComponent("PortraitCandidates/index-v1.json"))) == beforePortrait,
      PortraitCandidateCoding.digest(try Data(contentsOf:backupDirectory.appendingPathComponent("DrawingEvidence").appendingPathComponent(evidenceArchive.lastPathComponent))) == beforeEvidence else { throw PortraitLibraryError.staleGeneration }
    // Verify selected raw components independently; missing observation pixels
    // are recorded later and do not invalidate valid upstream run ancestry.
    _ = try PortraitEvidenceSource.read(backupDirectory.appendingPathComponent("DrawingEvidence").appendingPathComponent(evidenceArchive.lastPathComponent))
    let manifest = try JSONSerialization.data(withJSONObject:["schemaVersion":1,"portraitSHA256":beforePortrait,"evidenceSHA256":beforeEvidence,"files":selected.sorted{($0["path"] as! String)<($1["path"] as! String)}],options:[.sortedKeys,.prettyPrinted])
    try durableWrite(manifest,to:backupDirectory.appendingPathComponent("snapshot-manifest.json"))
    return (beforePortrait,beforeEvidence,PortraitCandidateCoding.digest(manifest))
  }

  private static func auditProofs(_ bytes:Data,sha256:String,generation:String,raw:DrawingRunEvidenceArchive,evidenceURL:URL) throws -> [PortraitLegacyLineageProof] {
    guard let audit = try JSONSerialization.jsonObject(with:bytes) as? [String:Any],let records = audit["terminalRecords"] as? [[String:Any]] else { throw PortraitLibraryError.database("audit format invalid") }
    return try records.compactMap { row in
      guard let lineage = row["lineage"] as? [String:Any],lineage["status"] as? String == "resolved",
        lineage["explicitCandidateID"] is NSNull,
        let validation = lineage["validation"] as? [String:Any],validation["valid"] as? Bool == true,
        let run = (row["runID"] as? String).flatMap(UUID.init(uuidString:)),let candidate = lineage["candidateID"] as? String,
        let photo = lineage["photo"] as? [String:Any],let photoID = (photo["photoID"] as? String).flatMap(UUID.init(uuidString:)),
        let source = photo["sourceSHA256"] as? String,let program = lineage["sourceProgramContentHash"] as? String,
        let execution = lineage["executionProgramContentHash"] as? String,let method = lineage["method"] as? String,
        let recordHash = row["recordSHA256"] as? String,let candidateRecordHash = lineage["candidateRecordSHA256"] as? String else { return nil }
      guard let record = raw.records.first(where:{$0.runID.rawValue == run}) else { return nil }
      let hashes = try PortraitEvidenceSource.componentHashes(evidenceURL)
      guard hashes.records[record.recordID.rawValue] == recordHash,record.program.contentHash.description == execution else { throw PortraitLibraryError.database("audit raw record proof no longer matches") }
      return .init(runID:run,candidateID:candidate,photoID:photoID,sourceSHA256:source,programContentHash:program,
        executionProgramContentHash:execution,method:method,evidenceGeneration:generation,auditSHA256:sha256,recordSHA256:recordHash,candidateRecordSHA256:candidateRecordHash)
    }
  }
  private static func durableWrite(_ bytes:Data,to url:URL) throws {
    try bytes.write(to:url,options:.atomic)
    let handle = try FileHandle(forWritingTo:url);try handle.synchronize();try handle.close()
    try synchronizeDirectory(url.deletingLastPathComponent())
  }
  private static func synchronizeDirectory(_ url:URL) throws {
    let fd = url.withUnsafeFileSystemRepresentation{Darwin.open($0!,O_RDONLY)}
    guard fd >= 0 else { throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno)) }
    defer { Darwin.close(fd) }
    guard Darwin.fsync(fd) == 0 else { throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno)) }
  }
}

extension PortraitCandidateStore {
  package func backupDatabase(to url:URL) throws { try libraryDatabase().backup(to:url) }
  package func verifyLibraryIntegrity() throws { try libraryDatabase().integrityCheck() }
  /// Verify the complete selected compact SQL inventory. Missing selected
  /// payloads cannot pass merely because the directory's remaining files hash.
  package func verifySelectedPayloads(quarantineDirectory:URL? = nil) throws {
    let db = try libraryDatabase()
    var records = Set<String>(),assets = Set<String>()
    for row in try db.rows("SELECT source_hash FROM photo WHERE deleted=0") { if let hash = row[0] { assets.insert(hash) } }
    for row in try db.rows("SELECT candidate_record,metadata_record,historical_record,raster_hash,recipe_hash FROM drawing WHERE deleted=0") {
      if let candidate = row[0] {
        guard let metadata = row[1],let raster = row[3],row[4] != nil else { throw PortraitLibraryError.database("selected renderable drawing is incomplete") }
        records.formUnion([candidate,metadata]);assets.insert(raster)
      } else if let historical = row[2] { records.insert(historical) }
      else { throw PortraitLibraryError.database("selected drawing has no immutable payload") }
    }
    records.formUnion(try db.rows("SELECT record_hash FROM label UNION SELECT record_hash FROM withdrawn_label").compactMap{$0[0]})
    for row in try db.rows("SELECT reference FROM generic_drawing") {
      let reference = try db.decode(SavedDrawingRecordReference.self,row[0])
      guard let hash = reference.recordSHA256,reference.candidateID == nil else { throw PortraitLibraryError.database("selected generic drawing reference invalid") }
      records.insert(hash)
    }
    for (folder,hashes) in [("records",records),("assets",assets)] {
      for hash in hashes {
        guard hash.count == 64,hash.allSatisfy(\.isHexDigit),
          try PortraitCandidateCoding.digest(Data(contentsOf:directoryURL.appendingPathComponent(folder).appendingPathComponent(hash))) == hash else {
          throw PortraitLibraryError.database("selected immutable payload missing or changed")
        }
      }
    }
    let root = quarantineDirectory ?? directoryURL.deletingLastPathComponent().appendingPathComponent("PortraitQuarantine")
    let generation = try db.generation.evidenceSHA256
    for row in try db.rows("SELECT id,reason,manifest FROM quarantine") {
      guard let id = row[0],let payload = row[2],let generation else { throw PortraitLibraryError.database("selected quarantine identity invalid") }
      let folder = root.appendingPathComponent(id),payloadHash = PortraitCandidateCoding.digest(Data(payload.utf8))
      guard try PortraitCandidateCoding.digest(Data(contentsOf:folder.appendingPathComponent(payloadHash+".json"))) == payloadHash else {
        throw PortraitLibraryError.database("selected quarantine payload missing or changed")
      }
      var found = false
      for file in try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil) where file.lastPathComponent.hasSuffix(".manifest.json") {
        let bytes = try Data(contentsOf:file)
        guard PortraitCandidateCoding.digest(bytes) == String(file.lastPathComponent.prefix(64)),
          let manifest = try JSONSerialization.jsonObject(with:bytes) as? [String:Any] else { throw PortraitLibraryError.database("quarantine manifest checksum invalid") }
        guard manifest["id"] as? String == id,manifest["sourceGeneration"] as? String == generation,
          manifest["payloadSHA256"] as? String == payloadHash,manifest["reason"] as? String == row[1] else { continue }
        guard let originalFiles = manifest["originalFiles"] as? [[String:Any]] else { throw PortraitLibraryError.database("quarantine original inventory invalid") }
        var includesOriginalManifest = false
        for original in originalFiles {
          if original["availability"] as? String == "missing",original["file"] == nil { continue }
          guard let name = original["file"] as? String,!name.contains("/"),name != ".",name != "..",
            let hash = original["sha256"] as? String,let count = original["byteCount"] as? Int else {
            throw PortraitLibraryError.database("quarantine original reference invalid")
          }
          let retained = try Data(contentsOf:folder.appendingPathComponent(name))
          guard retained.count == count,PortraitCandidateCoding.digest(retained) == hash else { throw PortraitLibraryError.database("quarantine original missing or changed") }
          if hash == generation { includesOriginalManifest = true }
        }
        guard includesOriginalManifest else { throw PortraitLibraryError.database("quarantine original selected manifest missing") }
        found = true
      }
      guard found else { throw PortraitLibraryError.database("selected quarantine manifest unavailable") }
    }
  }
  package func libraryCounts() throws -> (photos:Int,drawings:Int,works:Int,plotted:Int,quarantine:Int) {
    let db = try libraryDatabase()
    func count(_ table:String,_ whereSQL:String="") throws -> Int { Int(try db.scalar("SELECT COUNT(*) FROM " + table + whereSQL) ?? "0") ?? 0 }
    return (try count("photo"," WHERE deleted=0"),try count("drawing"," WHERE deleted=0"),try count("work"," WHERE deleted=0"),try count("work"," WHERE deleted=0 AND executed=1"),try count("quarantine"))
  }
}
