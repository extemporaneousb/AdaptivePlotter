import CryptoKit
import Darwin
import Foundation
import PlotterModel
import Testing
@testable import PortraitArtists
@testable import PortraitCore
@testable import PortraitLibrary

/// New paired DX04 probe. Frozen DX01 inputs/harness/driver are not modified.
/// The three read bodies correspond to DrawingExchangeBaselineTests.catalog/gallery;
/// the writer body is explicitly new and identical in the two source variants.
@Suite("DX04 paired metadata probe", .serialized)
struct DrawingExchangeDX04ProbeTests {
  private struct Selection: Decodable { let drawing: SavedDrawingSummary; let large: SavedDrawingSummary }
  private struct Input {
    let library: URL
    let store: PortraitCandidateStore
    let selection: Selection
    let native: PortraitCandidate?
    let writerLockPresentAfterSetup: Bool
  }
  private func input(_ env: [String:String], materializeNative: Bool) throws -> Input {
    let source = URL(fileURLWithPath:try DX04ProbeIdentity.required(env,"DX04_CORPUS"))
    let library = URL(fileURLWithPath:try DX04ProbeIdentity.required(env,"DX04_WORK_LIBRARY"))
    guard source.path.hasPrefix("/tmp/adaptiveplotter-dx01-") || source.path.hasPrefix("/private/tmp/adaptiveplotter-dx01-"),
      library.path.hasPrefix("/tmp/adaptiveplotter-dx01-") || library.path.hasPrefix("/private/tmp/adaptiveplotter-dx01-") else { throw DX04ProbeError.arguments("Disposable roots required") }
    guard !FileManager.default.fileExists(atPath:library.path) else { throw DX04ProbeError.arguments("Working copy exists") }
    try FileManager.default.createDirectory(at:library.deletingLastPathComponent(),withIntermediateDirectories:true)
    try FileManager.default.copyItem(at:source,to:library)
    let selection = try JSONDecoder().decode(Selection.self,from:Data(contentsOf:library.appendingPathComponent("dx01-selection.json")))
    // Explicit selected caller input, outside every timer. This is an independent
    // read-only endpoint; the timed writer actor still has no writable connection.
    var native: PortraitCandidate?
    if materializeNative {
      let loaded = try PortraitCandidateStore(directoryURL:library).loadDrawing(selection.drawing.id)
      guard let value = loaded.portraitCandidate,value.id == selection.drawing.id,
        value.photoID == selection.drawing.photoID,value.program.contentHash.description == selection.drawing.programContentHash else { throw DX04ProbeError.invariant("Selected input binding") }
      native = value
    }
    let writer = PortraitCandidateStore(directoryURL:library,evidenceArchiveURL:nil)
    let lockPresent = FileManager.default.fileExists(atPath:library.appendingPathComponent("library-writer.lock").path)
    guard !lockPresent else { throw DX04ProbeError.invariant("Setup unexpectedly opened a writer or gold contains a writer lock") }
    return .init(library:library,store:writer,selection:selection,native:native,writerLockPresentAfterSetup:lockPresent)
  }
  private func event(_ index: Int) -> PortraitRetentionEvent {
    .init(reason:.shortlisted,id:UUID(uuidString:String(format:"d4040000-0000-0000-0000-%012x",index+1))!,createdAt:Date(timeIntervalSince1970:1_800_000_000 + Double(index)))
  }
  private func save(_ entry: PortraitRetainedCandidate,in store: PortraitCandidateStore) async throws {
    _ = try await store.save(snapshot:.init(entries:[entry]),mode:.mutationDelta)
  }
  private func bindings(_ db: PortraitLibraryDatabase) throws -> [[String?]] {
    try db.rows("SELECT id,photo_id,source_hash,program_hash,candidate_record,historical_record FROM drawing ORDER BY id")
  }
  private func immutableFiles(_ library: URL) throws -> [String:String] {
    var result: [String:String] = [:]
    for name in ["assets","records"] {
      let directory = library.appendingPathComponent(name)
      for file in try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil) {
        result[name + "/" + file.lastPathComponent] = try DX04ProbeIdentity.sha256(file)
      }
    }
    return result
  }
  private func output(_ report: [String:Any],_ env: [String:String]) throws {
    try DX04ProbeIdentity.write(report,to:URL(fileURLWithPath:try DX04ProbeIdentity.required(env,"DX04_PROBE_OUTPUT")))
  }

  @Test("loader binding and positive counter controls", .enabled(if:ProcessInfo.processInfo.environment["DX04_PROBE_PHASE"] == "control"))
  func control() async throws {
    let env = ProcessInfo.processInfo.environment,kind = try DX04ProbeIdentity.required(env,"DX04_PROBE_CONTROL")
    if kind == "wrong-pid" || kind == "wrong-image" {
      var rejected = false
      do { _ = try DX04ProbeIdentity.attest(env) }
      catch DX04ProbeError.acknowledgement where kind == "wrong-pid" { rejected = true }
      catch DX04ProbeError.imageMismatch where kind == "wrong-image" { rejected = true }
      guard rejected else { throw DX04ProbeError.invariant("Negative identity control did not reject") }
      try output(["phase":"control","control":kind,"expectedRejection":true,"backendStarted":false,"identity":try DX04ProbeIdentity.observed()],env)
      return
    }
    guard kind == "positive" else { throw DX04ProbeError.arguments(kind) }
    let identity = try DX04ProbeIdentity.attest(env),prepared = try input(env,materializeNative:true),store = prepared.store
    _ = try await store.libraryDatabase() // The sentinel write has an actual writer owner.
    let sentinel = Data(repeating:0x5a,count:1024*1024),digest = PortraitCandidateCoding.digest(sentinel)
    try sentinel.write(to:prepared.library.appendingPathComponent("assets/" + digest),options:.atomic)
    let beforeAsset = await store.assetBytesVerified
    _ = try await store.readAsset(digest)
    let sentinelRead = await store.assetBytesVerified - beforeAsset
    guard sentinelRead == sentinel.count else { throw DX04ProbeError.invariant("Asset counter positive control") }
    let first = PortraitRetainedCandidate(candidate:prepared.native!,reasons:[event(0)])
    try await save(first,in:store)
    let beforeRecord = await store.recordBytesEncoded
    // Existing exact geometry, new synthetic acquisition occurrence. No renderer,
    // camera, real capture, model fit or geometry generation is invoked.
    let newOccurrence = try PortraitCandidate(sourceData:prepared.native!.sourceData,sourcePixelExtent:prepared.native!.sourcePixelExtent,
      raster:prepared.native!.raster,recipe:prepared.native!.recipe,program:prepared.native!.program,
      photoID:UUID(uuidString:"d4040000-0000-0000-0001-000000000001")!,captureSessionID:UUID(uuidString:"d4040000-0000-0000-0001-000000000002")!,
      createdAt:prepared.native!.createdAt,lineage:prepared.native!.lineage,checkpointID:prepared.native!.checkpointID,pose:prepared.native!.pose,
      proposal:prepared.native!.proposal,warpManifest:prepared.native!.warpManifest)
    try await save(.init(candidate:newOccurrence,reasons:[event(1)]),in:store)
    let recordControl = await store.recordBytesEncoded - beforeRecord
    guard recordControl > 0 else { throw DX04ProbeError.invariant("Candidate record counter positive control") }
    let beforeWarmRecord = await store.recordBytesEncoded,beforeWarmAsset = await store.assetBytesVerified,beforeMetadata = await store.metadataBytesEncoded
    try await save(.init(candidate:newOccurrence,reasons:[event(2)]),in:store)
    let warmRecord = await store.recordBytesEncoded - beforeWarmRecord,warmAsset = await store.assetBytesVerified - beforeWarmAsset
    let metadata = await store.metadataBytesEncoded - beforeMetadata
    guard warmRecord == 0,warmAsset == 0,metadata > 0 else { throw DX04ProbeError.invariant("Warm metadata counter control") }
    try output(["phase":"control","control":kind,"identity":identity,"backendStarted":true,
      "sentinelBytes":sentinel.count,"assetCounterReadPositive":sentinelRead,"candidateRecordEncodePositive":recordControl,
      "warmCandidateRecordBytesEncoded":warmRecord,"warmAssetBytesVerified":warmAsset,"metadataBytesEncodedPositive":metadata,
      "scope":"Existing Store counters only; not all reads/decodes/hash calls/allocations. Synthetic occurrence, no rendering or real capture."],env)
  }

  @Test("paired existing metadata calls and selected retention commit", .enabled(if:ProcessInfo.processInfo.environment["DX04_PROBE_PHASE"] == "measure"))
  func measure() async throws {
    let env = ProcessInfo.processInfo.environment
    let identity = try DX04ProbeIdentity.attest(env)
    let operation = try DX04ProbeIdentity.required(env,"DX04_PROBE_OPERATION")
    let prepared = try input(env,materializeNative:operation == "retention-metadata-save"),store = prepared.store
    let trials = Int(try DX04ProbeIdentity.required(env,"DX04_PROBE_TRIALS")) ?? 0
    guard ["photo-first-page","photo-filtered-drawing-page","gallery-first-page","retention-metadata-save"].contains(operation),trials == 1 || trials == 30 else { throw DX04ProbeError.arguments("Probe operation/trials") }
    let dbURL = prepared.library.appendingPathComponent("library-v1.sqlite")
    let selectedPhotoID = try #require(prepared.selection.drawing.photoID)
    // Host-computed immutable pins are input metadata, not a pre-clock SQLite or
    // artwork traversal inside this helper. Read scenarios materialize no artwork.
    struct Pins: Decodable { let bindings: [[String?]]; let genericBindings: [[String?]]; let immutableFiles: [String:String]; let databaseSHA256: String; let selectedMetadataRecord: String; let revision: Int64 }
    let pinURL = URL(fileURLWithPath:try DX04ProbeIdentity.required(env,"DX04_INPUT_PINS"))
    guard try DX04ProbeIdentity.sha256(pinURL) == env["DX04_INPUT_PINS_SHA256"] else { throw DX04ProbeError.invariant("Input pin file") }
    let pins = try JSONDecoder().decode(Pins.self,from:Data(contentsOf:pinURL))
    let initialBindings = pins.bindings,initialFiles = pins.immutableFiles
    var times: [Double] = [],counters: [[String:Any]] = [],previousChanges = 0
    var permittedMetadataFiles = Set<String>()
    var lastMetadata = pins.selectedMetadataRecord
    var previousRevision = pins.revision
    let events = (0...31).map(event)
    func perform(_ index: Int) async throws -> Int? {
      switch operation {
      case "photo-first-page":
        let page = try store.loadPhotoPage(limit:20)
        guard page.photos.count == 20 else { throw DX04ProbeError.invariant("Photo rows") };return page.candidateRecordsRead
      case "photo-filtered-drawing-page":
        let page = try store.loadDrawingPage(limit:20,photoID:selectedPhotoID)
        guard page.drawings.count == 5 else { throw DX04ProbeError.invariant("Drawing rows") };return page.candidateRecordsRead
      case "gallery-first-page":
        let page = try await store.librarySnapshot(limit:100)
        guard page.photos.count == 40 else { throw DX04ProbeError.invariant("Gallery rows") };return nil
      default:
        try await save(.init(candidate:prepared.native!,reasons:[events[index]]),in:store);return nil
      }
    }
    if trials > 1 {
      _ = try await perform(0)
      if operation == "retention-metadata-save" {
        let db = try await store.libraryDatabase()
        previousChanges = Int(try db.scalar("SELECT total_changes()") ?? "0")!
        guard let hash = try db.scalar("SELECT metadata_record FROM drawing WHERE candidate_id=? AND photo_id=?",[prepared.native!.id,selectedPhotoID.uuidString.lowercased()]) else { throw DX04ProbeError.invariant("Warmup selected metadata missing") }
        let revision = try db.generation.revision
        guard hash != lastMetadata,revision > previousRevision else { throw DX04ProbeError.invariant("Warmup did not commit a new selected metadata revision") }
        permittedMetadataFiles.insert("records/" + hash);lastMetadata = hash;previousRevision = revision
      }
    }
    for index in 0..<trials {
      let records = await store.recordBytesEncoded,assets = await store.assetBytesVerified,metadata = await store.metadataBytesEncoded
      let start = ProcessInfo.processInfo.systemUptime
      let pageCounter = try await perform(index + 1)
      times.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
      var row: [String:Any] = ["candidateRecordsRead":pageCounter as Any? ?? NSNull(),
        "candidateRecordBytesEncoded":await store.recordBytesEncoded - records,"assetBytesVerified":await store.assetBytesVerified - assets,
        "metadataBytesEncoded":await store.metadataBytesEncoded - metadata]
      if operation == "retention-metadata-save" {
        let db = try await store.libraryDatabase(),revision = try db.generation.revision
        let changed = Int(try db.scalar("SELECT total_changes()") ?? "0")!
        row["SQLiteTotalChangesDelta"] = changed - previousChanges;previousChanges = changed
        let hash = try db.scalar("SELECT metadata_record FROM drawing WHERE candidate_id=? AND photo_id=?",[prepared.native!.id,prepared.native!.photoID.uuidString.lowercased()])
        guard let hash,hash != lastMetadata,revision > previousRevision else { throw DX04ProbeError.invariant("Retention metadata/revision did not change") }
        lastMetadata = hash;previousRevision = revision;permittedMetadataFiles.insert("records/" + hash)
        guard (row["metadataBytesEncoded"] as? Int ?? 0) > 0 else { throw DX04ProbeError.invariant("No metadata encoding") }
        if trials > 1 {
          guard (row["candidateRecordBytesEncoded"] as? Int) == 0,(row["assetBytesVerified"] as? Int) == 0 else { throw DX04ProbeError.invariant("Warm metadata encoded candidate record or verified assets") }
        }
      }
      counters.append(row)
    }
    let finalDB = try PortraitLibraryDatabase(url:dbURL,readOnly:true)
    guard try bindings(finalDB) == initialBindings,try finalDB.rows("SELECT id,reference FROM generic_drawing ORDER BY id") == pins.genericBindings else { throw DX04ProbeError.invariant("Immutable/omitted drawing bindings changed") }
    let finalFiles = try immutableFiles(prepared.library)
    guard initialFiles.allSatisfy({ finalFiles[$0.key] == $0.value }) else { throw DX04ProbeError.invariant("Existing immutable file changed") }
    let newFiles = Set(finalFiles.keys).subtracting(Set(initialFiles.keys))
    guard newFiles.isSubset(of:permittedMetadataFiles) else { throw DX04ProbeError.invariant("Unexpected new immutable files beyond explicit selected metadata") }
    var usage = rusage();getrusage(RUSAGE_SELF,&usage)
    try output(["phase":"measure","collection":env["DX04_PROBE_COLLECTION"] ?? "unknown","operation":operation,"trials":trials,"milliseconds":times,"counters":counters,"identity":identity,
      "processPeakRSSBytes":usage.ru_maxrss,"fixture":"DX01 pinned small:40 photos,200 native drawings,1 source-free20000-stroke drawing; no work rows",
      "methodScope":operation == "retention-metadata-save" ? "NEW paired one-occurrence retention metadata save(mode:mutationDelta), not historical DX01 measurement" : "Existing DX01 API operation body on disposable full small-catalog copy",
      "cache":trials == 1 ? "Fresh helper/writer; writer-only selected caller input and host pins/copy outside timer; read scenarios preload no artwork or SQLite traversal; filesystem cache not evicted" : "One actual untimed operation then30 same-owner calls; writer-only input/copy/host pins outside timer; filesystem cache not evicted",
      "RSSScope":"Whole helper lifetime includes loader SHA/ACK, test startup, copied corpus, selected caller input and post-clock verification. Not interval allocations or live page cache.",
      "counterScope":"Existing Store candidate-record encoding/asset verification/metadata encoding counters only; other IO/decode/renderer/allocation counts unknown",
      "SQLiteChangesScope":trials == 1 ? "Post-call total_changes on the new writer connection, defined initial0; DB not opened to read a before counter" : "Actual before/after total_changes deltas on already-open writer connection",
      "writerLockPresentAfterSetup":prepared.writerLockPresentAfterSetup,
      "workingCopyDatabaseChanged":try DX04ProbeIdentity.sha256(dbURL) != pins.databaseSHA256,
      "immutableBindingRows":initialBindings.count,"genericBindingRows":pins.genericBindings.count,"newSelectedMetadataFiles":newFiles.sorted(),"existingImmutableFiles":initialFiles.count,"existingImmutableFilesUnchanged":true,
      "productionLimit":"evidenceArchiveURL=nil; no physical evidence joins, native app/paint/thread-occupancy or production archive claim"],env)
  }
}
