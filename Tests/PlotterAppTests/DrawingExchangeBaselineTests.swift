import CoreGraphics
import ImageIO
import Darwin
import Foundation
import PlotterModel
import Testing
import PortraitCore
@testable import PortraitArtists
@testable import PortraitLibrary

/// Opt-in disposable workload. This imports no app entrypoint and opens no device.
@Suite("Drawing Exchange frozen baseline", .serialized)
struct DrawingExchangeBaselineTests {
  private struct Selection: Codable { let drawing: SavedDrawingSummary; let large: SavedDrawingSummary }
  @Test("legacy v1 transfer on disposable stores", .enabled(if:
    ProcessInfo.processInfo.environment["DX_TRANSFER_ROOT"] != nil))
  func transfer() async throws {
    let env = ProcessInfo.processInfo.environment
    let root = URL(fileURLWithPath: try #require(env["DX_TRANSFER_ROOT"]))
    try #require(root.path.hasPrefix("/tmp/adaptiveplotter-dx01-") || root.path.hasPrefix("/private/tmp/adaptiveplotter-dx01-"))
    let scratch = root.appendingPathComponent("work-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let store = PortraitCandidateStore(directoryURL: scratch)
    let fixture = root.appendingPathComponent("legacy-v1.json")
    if env["DX_BASELINE_PHASE"] == "prepare" {
      try #require(!FileManager.default.fileExists(atPath: fixture.path))
      let catalog = URL(fileURLWithPath: try #require(env["DX_TRANSFER_CATALOG"]))
      let selection = try JSONDecoder().decode(Selection.self,
        from: Data(contentsOf: catalog.appendingPathComponent("dx01-selection.json")))
      let drawing = try PortraitCandidateStore(directoryURL: catalog).loadDrawing(selection.drawing.id)
      let candidate = try #require(drawing.portraitCandidate)
      try await store.save(snapshot: .init(entries: [.init(candidate: candidate,
        reasons: [.init(reason: .shortlisted)])]))
      let bytes = try await store.exportDrawingPackage(drawing)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      try bytes.write(to: fixture)
      try report(["phase": "prepare", "packageSHA256": DrawingPackageCodec.sha256(bytes),
        "packageBytes": bytes.count, "programHash": drawing.programContentHash,
        "scope": "current photo-required v1 JSON; not new exchange/streaming"], env)
      return
    }
    let bytes = try Data(contentsOf: fixture)
    let operation = try #require(env["DX_BASELINE_OPERATION"])
    let expectedHash = try #require(env["DX_TRANSFER_EXPECTED_PROGRAM_HASH"])
    let expectedPackageSHA = try #require(env["DX_TRANSFER_EXPECTED_PACKAGE_SHA256"])
    #expect(DrawingPackageCodec.sha256(bytes) == expectedPackageSHA)
    let trials = Int(env["DX_BASELINE_TRIALS"] ?? "30")!
    var candidate: PortraitCandidate?
    if operation == "v1-native-export" {
      // Selected authored value is an explicit export input. Import cases do
      // not pre-decode the package, candidate or program before their timer.
      let package = try DrawingPackageCodec.decode(bytes)
      candidate = try JSONDecoder().decode(PortraitCandidate.self, from: package.resultRecordJSON)
      try await store.save(snapshot: .init(entries: [.init(candidate: candidate!,
        reasons: [.init(reason: .shortlisted)])]))
      try await store.dx01FreezeReplayNamespace(package.origin.libraryID)
    } else if operation == "v1-reimport" { _ = try await store.importDrawingPackage(bytes) }
    var lastExport: Data?, lastDrawing: SavedDrawing?
    func perform(_ index: Int) async throws {
      if operation == "v1-native-export" {
        lastExport = try await store.exportDrawingPackage(SavedDrawing(candidate: try #require(candidate)))
      } else if operation == "v1-reimport" { lastDrawing = try await store.importDrawingPackage(bytes) }
      else {
        try #require(operation == "v1-first-import")
        let destination = PortraitCandidateStore(directoryURL: scratch.appendingPathComponent("import-\(index)"))
        lastDrawing = try await destination.importDrawingPackage(bytes)
      }
    }
    func verify() {
      if let lastExport { #expect(DrawingPackageCodec.sha256(lastExport) == expectedPackageSHA); #expect(lastExport == bytes) }
      if let lastDrawing { #expect(lastDrawing.programContentHash == expectedHash) }
    }
    if trials > 1 { try await perform(-1); verify() }
    var times: [Double] = [], outputDigests: [String] = []
    for index in 0..<trials {
      let start = ProcessInfo.processInfo.systemUptime
      try await perform(index)
      times.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
      verify() // Exact output checks are outside the measured interval.
      if let lastExport { outputDigests.append(DrawingPackageCodec.sha256(lastExport)) }
    }
    var actualOutput: Any = NSNull()
    if let lastExport {
      let package = try DrawingPackageCodec.decode(lastExport)
      actualOutput = ["sha256": DrawingPackageCodec.sha256(lastExport), "bytes": lastExport.count,
        "origin": try JSONSerialization.jsonObject(with: DrawingPackageCodec.encoder().encode(package.origin))]
    }
    var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
    try report(["operation": operation, "milliseconds": times, "processPeakRSSBytes": usage.ru_maxrss,
      "inputPackageSHA256": DrawingPackageCodec.sha256(bytes), "inputPackageBytes": bytes.count,
      "actualExportOutput": actualOutput, "exportOutputSHA256PerSample": outputDigests,
      "mallocSnapshot": dx01AllZoneMallocSnapshot(),
      "scope": "small v1 drawing; process RSS/counts include test setup and post-timer output validation; no native paint",
      "setup": operation == "v1-native-export" ? "pre-materialized selected native candidate; original namespace seeded by test-only DB API; no package exists before first export" : operation == "v1-reimport" ? "one explicit untimed initial import; measured calls are duplicate admissions" : "only frozen package bytes and tiny expected hashes loaded; no package/candidate/program decode before API",
      "cache": trials == 1 ? "first call after operation-specific setup in fresh process; filesystem cache uncontrolled" : "one warmup then30 calls; export/reimport cached; first-import uses a new disposable destination per call",
      "queryCount": NSNull(), "decodeCount": NSNull(), "allocations": NSNull(),
      "readBytes": NSNull(), "writeBytes": NSNull()], env)
  }
  @Test("prepare or measure the exact current catalog APIs", .enabled(if:
    ProcessInfo.processInfo.environment["DX_BASELINE_ROOT"] != nil))
  func catalog() async throws {
    let env = ProcessInfo.processInfo.environment
    let root = URL(fileURLWithPath: try #require(env["DX_BASELINE_ROOT"]))
    try #require(root.path.hasPrefix("/tmp/adaptiveplotter-dx01-") || root.path.hasPrefix("/private/tmp/adaptiveplotter-dx01-"))
    let count = Int(env["DX_BASELINE_PHOTOS"] ?? "20")!
    let phase = env["DX_BASELINE_PHASE"] ?? "read"
    let encoder = PortraitCandidateCoding.encoder()
    let store = PortraitCandidateStore(directoryURL: root)
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    if phase == "prepare" {
      let seed = try portraitPersistenceCandidate(seed: 7301)
      try #require(!FileManager.default.fileExists(atPath: root.path))
      let sourceBytes = try pngSource()
      var photos: [PortraitPhoto] = [], entries: [PortraitRetainedCandidate] = []
      for p in 0..<count {
        let photo = PortraitPhoto(id: uuid(p + 1), data: sourceBytes,
          label: "DX01 capture \(p)", capturedAt: date.addingTimeInterval(Double(p)), pose: .front,
          sourcePixelExtent: seed.sourcePixelExtent, captureSessionID: uuid(1_000_000 + p / 10))
        photos.append(photo)
        for variant in 0..<5 {
          let recipe = PortraitStyleRecipe(id: "dx01-\(p)-\(variant)", title: "DX01 \(p)/\(variant)",
            seed: UInt64(p * 5 + variant + 7301), style: .hatch,
            vectorOptions: seed.recipe.vectorOptions, analysisOptions: seed.recipe.analysisOptions)
          let candidate = try PortraitCandidate(sourceData: photo.data, sourcePixelExtent: photo.sourcePixelExtent,
            raster: seed.raster, recipe: recipe, program: seed.program,
            photoID: photo.id, captureSessionID: photo.captureSessionID,
            createdAt: date.addingTimeInterval(Double(p * 5 + variant)))
          entries.append(.init(candidate: candidate, reasons: [.init(reason: .shortlisted,
            id: uuid(2_000_000 + p * 5 + variant), createdAt: date)]))
        }
      }
      let started = ProcessInfo.processInfo.systemUptime
      let base = try #require(seed.program.strokes.first)
      let large = try DrawingProgram(id: ProgramID(uuid(8_000_000)), fieldExtent: seed.program.fieldExtent,
        strokes: (0..<20_000).map { LogicalStroke(id: StrokeID(uuid(8_000_001 + $0)), path: base.path,
          style: base.style, ordering: UInt32($0)) }, source: .init(kind: "authored", sourceIdentifier: "dx01-large-20000"))
      let largeDrawing = SavedDrawing(program: large, createdAt: date)
      try await store.save(snapshot: .init(entries: entries, sourcePhotos: photos, savedDrawings: [largeDrawing]))
      let index = try PortraitLibraryDatabase(url: root.appendingPathComponent("library-v1.sqlite"), readOnly: true)
      try index.integrityCheck()
      #expect(try index.scalar("SELECT COUNT(*) FROM photo") == String(count))
      #expect(try index.scalar("SELECT COUNT(*) FROM drawing WHERE saved=1") == String(count * 5))
      // Equal original bytes do not collapse independent captures.
      #expect(try index.scalar("SELECT COUNT(DISTINCT source_hash) FROM photo") == "1")
      let frozen = try index.index()
      let selected = try #require(frozen.drawingCatalog?.first(where: { $0.photoID != nil }))
      try encoder.encode(Selection(drawing: selected, large: SavedDrawingSummary(largeDrawing)))
        .write(to: root.appendingPathComponent("dx01-selection.json"))
      try report(["phase": phase, "photos": count, "drawings": count * 5,
        "prepareMS": (ProcessInfo.processInfo.systemUptime - started) * 1000,
        "recordBytesEncoded": await store.recordBytesEncoded,
        "metadataBytesEncoded": await store.metadataBytesEncoded,
        "assetBytesVerified": await store.assetBytesVerified], env)
      return
    }
    let selection = try JSONDecoder().decode(Selection.self,
      from: Data(contentsOf: root.appendingPathComponent("dx01-selection.json")))
    let selected = selection.drawing
    if phase == "negative" {
      let copy = root.deletingLastPathComponent().appendingPathComponent("negative-" + UUID().uuidString)
      try FileManager.default.copyItem(at: root, to: copy)
      defer { try? FileManager.default.removeItem(at: copy) }
      let reader = PortraitCandidateStore(directoryURL: copy)
      let database = copy.appendingPathComponent("library-v1.sqlite")
      let originalIndex = try Data(contentsOf: database)
      let original = try reader.loadDrawing(selected.id)
      let sourceHash = try #require(original.sourceImageSHA256)
      let asset = copy.appendingPathComponent("assets").appendingPathComponent(sourceHash)
      let originalAsset = try Data(contentsOf: asset)
      try Data("corrupt claimed source".utf8).write(to: asset)
      #expect(throws: (any Error).self) { try reader.loadDrawing(selected.id) }
      #expect(try reader.loadDrawingPage(photoID: selected.photoID).candidateRecordsRead == 0)
      try FileManager.default.removeItem(at: asset)
      #expect(throws: (any Error).self) { try reader.loadDrawing(selected.id) }
      try originalAsset.write(to: asset)
      #expect(try reader.loadDrawing(selected.id) == original)
      #expect(try Data(contentsOf: database) == originalIndex)
      try report(["phase": phase, "missingSourceRejected": true, "corruptSourceRejected": true,
        "metadataStillBrowsable": true, "indexBytesPreserved": true,
        "equalByteCaptureCount": count, "sourceDistinctDigests": 1], env)
      return
    }
    let wanted = env["DX_BASELINE_OPERATION"]
    if let wanted, ["gallery-first-page", "gallery-next-page", "identity-drawing-load"].contains(wanted) {
      try await gallery(root: root, selected: selected, count: count, operation: wanted, env: env)
      return
    }
    // The tiny selection manifest contains no program, raster or catalog arrays.
    // Exactly one selected operation runs in each measurement process.
    let trials = Int(env["DX_BASELINE_TRIALS"] ?? "30")!
    var measurements: [[String: Any]] = []
    func measure(_ name: String, _ operation: () throws -> Int?) throws {
      guard wanted == nil || wanted == name else { return }
      // A process-cold run has no warm-up. It does not evict filesystem caches.
      if trials > 1 { _ = try operation() }
      var times: [Double] = [], counters: [Any] = []
      for _ in 0..<trials {
        let start = ProcessInfo.processInfo.systemUptime
        counters.append(try operation() as Any? ?? NSNull())
        times.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
      }
      measurements.append(["operation": name, "milliseconds": times,
        "candidateRecordsRead": counters])
    }
    try measure("photo-first-page") {
      let page = try store.loadPhotoPage(limit: 20)
      #expect(page.photos.count == min(20, count)); return page.candidateRecordsRead
    }
    if wanted == nil || wanted == "photo-next-page" {
      let photoNext = try store.loadPhotoPage(limit: 20).next
      if let photoNext {
        try measure("photo-next-page") { try store.loadPhotoPage(after: photoNext, limit: 20).candidateRecordsRead }
      }
    }
    try measure("drawing-first-page") {
      let page = try store.loadDrawingPage(limit: 20)
      #expect(page.drawings.count == 20); return page.candidateRecordsRead
    }
    if wanted == nil || wanted == "drawing-next-page" {
      let drawingNext = try #require(store.loadDrawingPage(limit: 20).next)
      try measure("drawing-next-page") { try store.loadDrawingPage(after: drawingNext, limit: 20).candidateRecordsRead }
    }
    try measure("photo-filtered-drawing-page") {
      let page = try store.loadDrawingPage(limit: 20, photoID: selected.photoID)
      #expect(page.drawings.count == 5); return page.candidateRecordsRead
    }
    try measure("exact-drawing-load") {
      let value = try store.loadDrawing(selected.id)
      #expect(value.program.contentHash.description == selected.programContentHash)
      return nil // This API exposes no read/decode counter.
    }
    try measure("large-drawing-load") {
      let value = try store.loadDrawing(selection.large.id)
      #expect(value.program.strokes.count == 20_000)
      return nil
    }
    var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
    try report(["phase": phase, "photos": count, "drawings": count * 5,
      "trials": trials, "measurements": measurements, "operationFilter": wanted ?? "all",
      "mallocSnapshot": dx01AllZoneMallocSnapshot(),
      "nextPageSetup": "previous cursor requires an untimed first page; no cold-archive claim",
      "RSSScope": "process lifetime peak including Swift test runner; one operation per process in runner", "processPeakRSSBytes": usage.ru_maxrss,
      "cache": trials == 1 ? "process-cold; filesystem cache uncontrolled" : "one warm-up per operation; filesystem cache uncontrolled",
      "queryCount": NSNull(), "decodeCount": NSNull(), "allocations": NSNull(),
      "readBytes": NSNull(), "writeBytes": NSNull(), "UIThreadOccupancy": NSNull()], env)
  }

  private func gallery(root: URL, selected: SavedDrawingSummary, count: Int,
    operation: String, env: [String: String]) async throws {
    let copy = root.deletingLastPathComponent().appendingPathComponent("gallery-work-" + UUID().uuidString)
    try FileManager.default.copyItem(at: root, to: copy)
    defer { try? FileManager.default.removeItem(at: copy) }
    let store = PortraitCandidateStore(directoryURL: copy, evidenceArchiveURL: nil)
    let trials = Int(env["DX_BASELINE_TRIALS"] ?? "30")!
    let identity = PortraitDrawingIdentity(candidateID: selected.id, photoID: try #require(selected.photoID))
    var cursor: PortraitLibraryCursor?
    if operation == "gallery-next-page" {
      cursor = try await store.librarySnapshot(limit: 100).next
      if cursor == nil {
        try report(["operation": operation, "status": "not_applicable", "reason": "40-photo small corpus has no second UI page at fixed k=100",
          "photos": count, "pageSize": 100, "trials": 0, "requestedTrials": trials], env)
        return
      }
    }
    func perform() async throws -> Int {
      if operation == "identity-drawing-load" {
        let value = try await store.loadDrawing(identity)
        #expect(value.programContentHash == selected.programContentHash)
        return 1
      }
      let page = try await store.librarySnapshot(after: cursor, limit: 100)
      #expect(page.photos.count == min(100, count))
      return page.photos.count
    }
    if trials > 1 { _ = try await perform() }
    var times: [Double] = [], rows: [Int] = []
    for _ in 0..<trials {
      let start = ProcessInfo.processInfo.systemUptime
      rows.append(try await perform())
      times.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
    }
    var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
    try report(["operation": operation, "milliseconds": times, "returnedRows": rows,
      "photos": count, "pageSize": 100, "trials": trials, "processPeakRSSBytes": usage.ru_maxrss,
      "mallocSnapshot": dx01AllZoneMallocSnapshot(),
      "scope": "actual actor gallery/typed endpoint on disposable full catalog copy; copy/setup/test startup included in RSS; not native paint",
      "cache": trials == 1 ? "first operation after copy and required cursor setup in fresh process; filesystem cache uncontrolled" : "one warmup then30 operations; filesystem cache uncontrolled",
      "productionLimit": "evidenceArchiveURL=nil; configured production raw-archive hashing and physical work joins not measured; no work rows",
      "candidateRecordsRead": NSNull(), "queryCount": NSNull(), "decodeCount": NSNull(),
      "allocations": NSNull(), "readBytes": NSNull(), "writeBytes": NSNull()], env)
  }

  private func pngSource() throws -> Data {
    let pixels = Data((0..<1600).map { UInt8(($0 * 37 + 73) % 256) })
    let provider = try #require(CGDataProvider(data: pixels as CFData))
    let image = try #require(CGImage(width: 40, height: 40, bitsPerComponent: 8, bitsPerPixel: 8,
      bytesPerRow: 40, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let result = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(result, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    try #require(CGImageDestinationFinalize(destination))
    return result as Data
  }
  private func uuid(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "73010000-0000-0000-0000-%012llx", Int64(n)))!
  }
  private func report(_ object: [String: Any], _ env: [String: String]) throws {
    var reported = object
    if object["mallocSnapshot"] != nil { reported["mallocSnapshotScope"] = "all process malloc zones after timing; live blocks/bytes and sum of zone highwater touched bytes; not cumulative events, simultaneous peak, RSS, VM or page/cache memory" }
    let data = try JSONSerialization.data(withJSONObject: reported, options: [.prettyPrinted, .sortedKeys])
    if let path = env["DX_BASELINE_OUTPUT"] { try data.write(to: URL(fileURLWithPath: path), options: .atomic) }
    print("DX01_BASELINE " + String(decoding: data, as: UTF8.self))
  }
}


// Test-only exact replay setup, using existing package DB APIs on a disposable
// native library. Mirrors namespace issuance while preserving its frozen UUID.
extension PortraitCandidateStore {
  func dx01FreezeReplayNamespace(_ id: UUID) throws {
    let db = try libraryDatabase()
    try db.transaction {
      try db.setState("library_uuid", id.uuidString.lowercased())
      try db.execute("PRAGMA user_version=2")
      try db.bumpRevision()
    }
    refreshCommittedLibraryGeneration()
  }
}
