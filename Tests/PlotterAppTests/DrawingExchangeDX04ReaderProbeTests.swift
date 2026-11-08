import Darwin
import Foundation
import PlotterModel
import Testing
@testable import PortraitArtists
@testable import PortraitLibrary

/// New paired reader probes. Host-only fixture preparation and these identical
/// test bytes are independent of the frozen DX01 benchmark and original corpus.
@Suite("DX04 paired reader probes", .serialized)
struct DrawingExchangeDX04ReaderProbeTests {
  private struct Pins: Decodable {
    let bindings: [[String?]]
    let genericBindings: [[String?]]
    let immutableFiles: [String: String]
    let databaseSHA256: String
    let revision: Int64
    let candidateID: String
    let photoID: UUID
    let programHash: String
    let sourceHash: String
    let selectedRecordBytes: Int
    let selectedSourceBytes: Int
    let selectedRasterBytes: Int
    let expectedStyleIDs: [String]
    let expectedStyleNames: [String]
    let expectedStyleDates: [Double]
    let expectedRecipeJSON: String
  }
  private func immutableFiles(_ root: URL) throws -> [String: String] {
    var result: [String: String] = [:]
    for name in ["assets", "records"] {
      for file in try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent(name), includingPropertiesForKeys: nil) {
        result[name + "/" + file.lastPathComponent] = try DX04ProbeIdentity.sha256(file)
      }
    }
    return result
  }

  @Test("paired gallery, nonempty styles and exact native selected reader", .enabled(if:
    ProcessInfo.processInfo.environment["DX04_READER_PROBE"] == "1"
      && ProcessInfo.processInfo.environment["DX04_PROBE_PHASE"] == "measure"))
  func measure() async throws {
    let env = ProcessInfo.processInfo.environment
    let identity = try DX04ProbeIdentity.attest(env) // Host ACK before any backend work.
    let operation = try DX04ProbeIdentity.required(env, "DX04_PROBE_OPERATION")
    let trials = try #require(Int(try DX04ProbeIdentity.required(env, "DX04_PROBE_TRIALS")))
    guard ["gallery-first-page", "saved-style-catalog", "exact-native-reader"].contains(operation),
      trials == 1 || trials == 30 else { throw DX04ProbeError.arguments("Reader operation/trials") }
    let source = URL(fileURLWithPath: try DX04ProbeIdentity.required(env, "DX04_CORPUS"))
    let library = URL(fileURLWithPath: try DX04ProbeIdentity.required(env, "DX04_WORK_LIBRARY"))
    guard source.path.hasPrefix("/tmp/adaptiveplotter-dx01-"), library.path.hasPrefix("/tmp/adaptiveplotter-dx01-"),
      !FileManager.default.fileExists(atPath: library.path) else { throw DX04ProbeError.arguments("Disposable reader roots") }
    let pinsURL = URL(fileURLWithPath: try DX04ProbeIdentity.required(env, "DX04_INPUT_PINS"))
    guard try DX04ProbeIdentity.sha256(pinsURL) == env["DX04_INPUT_PINS_SHA256"] else { throw DX04ProbeError.invariant("Reader host pins") }
    // Only IDs/hashes/plain host metadata are decoded. No working-copy SQLite,
    // artwork or PortraitStyleRecipe DTO is read before the first operation.
    let pins = try JSONDecoder().decode(Pins.self, from: Data(contentsOf: pinsURL))
    try FileManager.default.createDirectory(at: library.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: source, to: library)
    let lockBefore = FileManager.default.fileExists(atPath: library.appendingPathComponent("library-writer.lock").path)
    guard !lockBefore else { throw DX04ProbeError.invariant("Reader setup opened writer") }
    let store = PortraitCandidateStore(directoryURL: library, evidenceArchiveURL: nil)
    let selected = PortraitDrawingIdentity(candidateID: pins.candidateID, photoID: pins.photoID)
    var lastStyles: [PortraitSavedStyle] = [], lastDrawing: SavedDrawing?, lastPhotos: [UUID] = []
    func perform() async throws {
      switch operation {
      case "gallery-first-page": lastPhotos = try await store.librarySnapshot(limit: 100).photos.map(\.id)
      case "saved-style-catalog": lastStyles = try await store.loadSavedStyles()
      default: lastDrawing = try await store.loadDrawing(selected)
      }
    }
    func verifyResult() throws {
      switch operation {
      case "gallery-first-page":
        guard lastPhotos.count == 40, Set(lastPhotos).count == 40 else { throw DX04ProbeError.invariant("Gallery output") }
      case "saved-style-catalog":
        guard lastStyles.map({ $0.id.uuidString.lowercased() }) == pins.expectedStyleIDs,
          lastStyles.map(\.name) == pins.expectedStyleNames,
          lastStyles.map({ $0.createdAt.timeIntervalSinceReferenceDate }) == pins.expectedStyleDates else { throw DX04ProbeError.invariant("Nonempty style values") }
        let expected = try #require(JSONSerialization.jsonObject(with: Data(pins.expectedRecipeJSON.utf8)) as? NSDictionary)
        for style in lastStyles {
          let actual = try #require(JSONSerialization.jsonObject(with: PortraitCandidateCoding.encoder().encode(style.recipe)) as? NSDictionary)
          guard actual.isEqual(expected) else { throw DX04ProbeError.invariant("Exact frozen style recipe") }
        }
      default:
        guard let drawing = lastDrawing, let candidate = drawing.portraitCandidate,
          candidate.id == pins.candidateID, candidate.photoID == pins.photoID,
          candidate.sourceSHA256 == pins.sourceHash, drawing.program.contentHash.description == pins.programHash else {
          throw DX04ProbeError.invariant("Exact selected occurrence/program/source")
        }
      }
    }
    if trials > 1 { try await perform(); try verifyResult() }
    var milliseconds: [Double] = [], counters: [[String: Any]] = []
    for _ in 0..<trials {
      let assets = await store.assetBytesVerified, records = await store.recordBytesEncoded, metadata = await store.metadataBytesEncoded
      let start = ProcessInfo.processInfo.systemUptime
      try await perform()
      milliseconds.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
      try verifyResult() // All output validation is outside the clock.
      let assetDelta = await store.assetBytesVerified - assets
      let recordDelta = await store.recordBytesEncoded - records
      let metadataDelta = await store.metadataBytesEncoded - metadata
      let expectedAssets = operation == "exact-native-reader" ? pins.selectedSourceBytes + pins.selectedRasterBytes : 0
      guard assetDelta == expectedAssets, recordDelta == 0, metadataDelta == 0 else { throw DX04ProbeError.invariant("Reader counter categories") }
      counters.append(["assetBytesVerified": assetDelta, "candidateRecordBytesEncoded": recordDelta,
        "metadataBytesEncoded": metadataDelta, "candidateRecordsDecoded": NSNull()])
    }
    let databaseURL = library.appendingPathComponent("library-v1.sqlite")
    let finalDB = try PortraitLibraryDatabase(url: databaseURL, readOnly: true)
    guard try finalDB.rows("SELECT id,photo_id,source_hash,program_hash,candidate_record,historical_record FROM drawing ORDER BY id") == pins.bindings,
      try finalDB.rows("SELECT id,reference FROM generic_drawing ORDER BY id") == pins.genericBindings,
      try finalDB.generation.revision == pins.revision,
      try DX04ProbeIdentity.sha256(databaseURL) == pins.databaseSHA256,
      try immutableFiles(library) == pins.immutableFiles else { throw DX04ProbeError.invariant("Readonly SQL/bindings/immutable inventory changed") }
    var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
    try DX04ProbeIdentity.write(["phase": "measure", "collection": env["DX04_PROBE_COLLECTION"] ?? "unknown",
      "operation": operation, "trials": trials, "milliseconds": milliseconds, "counters": counters, "identity": identity,
      "processPeakRSSBytes": usage.ru_maxrss, "writerLockPresentAfterSetup": lockBefore,
      "workingCopyDatabaseChanged": false, "revisionUnchanged": true, "existingImmutableFilesUnchanged": true,
      "existingImmutableFiles": pins.immutableFiles.count, "immutableBindingRows": pins.bindings.count,
      "genericBindingRows": pins.genericBindings.count, "selectedRecordInputBytes": pins.selectedRecordBytes,
      "styleCount": operation == "saved-style-catalog" ? lastStyles.count as Any : NSNull(),
      "fixture": operation == "saved-style-catalog" ? "NEW host-prepared three-style derivative of pinned DX01 small, original unchanged" : "Original pinned DX01 small40photos/200native+1generic20000stroke/no work rows",
      "methodScope": operation == "gallery-first-page" ? "Existing gallery API; output validation after clock" : "NEW paired existing-API reader probe, not historical DX01 measurement",
      "cache": trials == 1 ? "Fresh helper/Store; host metadata pins and corpus copy outside clock; no working SQLite/artwork/recipe DTO preload; filesystem cache not evicted" : "One actual untimed operation+verification, then30 same-Store operations; filesystem cache not evicted",
      "counterScope": "Existing asset verification/candidate-record encoding/metadata encoding categories only; actual record decode count and other IO/encoding/SQL work unknown",
      "RSSScope": "Whole helper lifetime including loader SHA/ACK, test startup, corpus copy and post-clock verification. Not interval allocations/live page cache",
      "productionLimit": "evidenceArchiveURL=nil; no production archive/nativeapp/UI-thread/physical evidence claim"],
      to: URL(fileURLWithPath: try DX04ProbeIdentity.required(env, "DX04_PROBE_OUTPUT")))
  }
}
