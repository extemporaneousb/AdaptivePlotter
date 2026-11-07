import Foundation
import Testing
@testable import PortraitCore

struct DrawingExchangeCarrierTestBag {
  let root: URL
  let source: URL
  init(files: [String: Data] = ["data/exchange.json": Data("{\"profile\":\"example.exchange/2\",\"optional\":17}".utf8)]) throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("dx03-test-" + UUID().uuidString)
    source = root.appendingPathComponent("source")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    var payload = files
    payload["bagit.txt"] = DrawingExchangeCarrier.bagit
    payload["manifest-sha256.txt"] = Data(files.keys.sorted().map { ExchangeDigest.hash(files[$0]!).description + "  " + $0 + "\n" }.joined().utf8)
    payload["tagmanifest-sha256.txt"] = Data(["bagit.txt", "manifest-sha256.txt"].map { ExchangeDigest.hash(payload[$0]!).description + "  " + $0 + "\n" }.joined().utf8)
    for (path, bytes) in payload {
      let url = source.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try bytes.write(to: url)
    }
  }
  func dispose() { try? FileManager.default.removeItem(at: root) }
}
@Suite("DX03 closed carrier", .serialized)
struct DrawingExchangeCarrierTests {
  @Test func frozenZIPAndExactPreservation() throws {
    let bag = try DrawingExchangeCarrierTestBag(); defer { bag.dispose() }
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/DrawingExchange/v1/source-free.zip")
    #expect(ExchangeDigest.hash(try Data(contentsOf: fixture)).description == "da5b913b8d946958dcc03dc4beddca0394052b539af3298667c521be3dd61c25")
    let staged = try DrawingExchangeCarrier.stageZIP(fixture, stagingParent: bag.root)
    #expect(staged.files.entries.count == 7)
    #expect(staged.statistics.imageDecodeCount == 0)
    #expect(staged.statistics.hashedBytes == staged.files.entries.values.reduce(0) { $0 + $1.byteLength })
    let output = bag.root.appendingPathComponent("preserved.zip")
    try DrawingExchangeCarrier.preserveZIP(staged.files, to: output)
    let again = try DrawingExchangeCarrier.stageZIP(output, stagingParent: bag.root)
    #expect(staged.indexJSON == again.indexJSON)
    #expect(staged.files.entries.mapValues(\.digest) == again.files.entries.mapValues(\.digest))
    let directory = bag.root.appendingPathComponent("preserved-directory")
    try DrawingExchangeCarrier.preserveDirectory(staged.files, to: directory)
    let reopened = try DrawingExchangeCarrier.stageDirectory(directory, stagingParent: bag.root)
    #expect(reopened.files.entries.mapValues(\.digest) == staged.files.entries.mapValues(\.digest))
  }
  @Test func tamperAndInspectionRecovery() throws {
    let bag = try DrawingExchangeCarrierTestBag(); defer { bag.dispose() }
    let original = bag.source.appendingPathComponent("data/exchange.json")
    try Data("{}".utf8).write(to: original)
    do {
      _ = try DrawingExchangeCarrier.stageDirectory(bag.source, stagingParent: bag.root)
      Issue.record("Tampered payload accepted")
    } catch let failure as ExchangeCarrierFailure {
      #expect(FileManager.default.fileExists(atPath: failure.stagingURL.appendingPathComponent("payload/data/exchange.json").path))
      #expect(try Data(contentsOf: original) == Data("{}".utf8))
    }
  }
  @Test func strictManifestAndJSONMatrix() throws {
    let invalid = ["../escape", "/absolute", "data//empty", "data/./dot", "data/../up", "data\\windows", "data/colon:name", "data/line\nbreak"]
    for path in invalid { #expect(throws: (any Error).self) { try DrawingExchangeCarrier.safePath(path) } }
    for manifest in ["", String(repeating: "a", count: 64) + " data/x\n", String(repeating: "A", count: 64) + "  data/x\n", String(repeating: "a", count: 64) + "  data/x", String(repeating: "a", count: 64) + "  data/x\n" + String(repeating: "a", count: 64) + "  DATA/X\n"] {
      #expect(throws: (any Error).self) { try DrawingExchangeCarrier.manifest(Data(manifest.utf8)) }
    }
    let duplicate = try DrawingExchangeCarrierTestBag(files: ["data/exchange.json": Data("{\"a\":1,\"a\":2}".utf8)])
    defer { duplicate.dispose() }
    #expect(throws: ExchangeCarrierFailure.self) { try DrawingExchangeCarrier.stageDirectory(duplicate.source, stagingParent: duplicate.root) }
  }
  @Test func linksExtraFilesLimitsAndCancellation() throws {
    let bag = try DrawingExchangeCarrierTestBag(); defer { bag.dispose() }
    let link = bag.source.appendingPathComponent("linked")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: bag.source.appendingPathComponent("data/exchange.json"))
    #expect(throws: ExchangeCarrierFailure.self) { try DrawingExchangeCarrier.stageDirectory(bag.source, stagingParent: bag.root) }
    try FileManager.default.removeItem(at: link)
    try Data([1]).write(to: link)
    #expect(throws: ExchangeCarrierFailure.self) { try DrawingExchangeCarrier.stageDirectory(bag.source, stagingParent: bag.root) }
    try FileManager.default.removeItem(at: link)
    var limits = ExchangeCarrierLimits(); limits.maximumEntryBytes = 1
    #expect(throws: ExchangeCarrierFailure.self) { try DrawingExchangeCarrier.stageDirectory(bag.source, stagingParent: bag.root, limits: limits) }
    do { _ = try DrawingExchangeCarrier.stageDirectory(bag.source, stagingParent: bag.root, cancelled: { true }); Issue.record("Cancellation accepted") }
    catch let failure as ExchangeCarrierFailure { #expect(failure.underlying is CancellationError); #expect(FileManager.default.fileExists(atPath: failure.stagingURL.path)) }
    #expect(FileManager.default.fileExists(atPath: bag.source.path))
  }
  @Test func stagedMutationAndBoundedMaterialization() throws {
    let bag = try DrawingExchangeCarrierTestBag(); defer { bag.dispose() }
    let staged = try DrawingExchangeCarrier.stageDirectory(bag.source, stagingParent: bag.root)
    #expect(throws: (any Error).self) { try staged.files.record(at: "data/exchange.json", maximumBytes: 1) }
    let path = staged.stagingURL.appendingPathComponent("data/exchange.json")
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    try Data("{}".utf8).write(to: path)
    #expect(throws: (any Error).self) { try staged.files.record(at: "data/exchange.json") }
  }
  @Test func ZIPRefusalMatrixAndIncomingRetention() throws {
    let bag = try DrawingExchangeCarrierTestBag(); defer { bag.dispose() }
    let staged = try DrawingExchangeCarrier.stageDirectory(bag.source, stagingParent: bag.root)
    let archive = bag.root.appendingPathComponent("good.zip")
    try DrawingExchangeCarrier.preserveZIP(staged.files, to: archive)
    let original = try Data(contentsOf: archive)
    var mutations: [Data] = []
    var trailing = original; trailing.append(0); mutations.append(trailing)
    mutations.append(original.dropLast())
    var encrypted = original; encrypted[6] = 1; mutations.append(encrypted)
    var method = original; method[8] = 99; mutations.append(method)
    var crc = original; crc[14] ^= 1; mutations.append(crc)
    var body = original; body[30 + Int(original[26])] ^= 1; mutations.append(body)
    for (i, bytes) in mutations.enumerated() {
      let bad = bag.root.appendingPathComponent("bad-\(i).zip"); try bytes.write(to: bad)
      do { _ = try DrawingExchangeCarrier.stageZIP(bad, stagingParent: bag.root); Issue.record("Malformed ZIP accepted: \(i)") }
      catch let failure as ExchangeCarrierFailure {
        #expect(try Data(contentsOf: failure.stagingURL.appendingPathComponent("incoming.zip")) == bytes)
        #expect(try Data(contentsOf: bad) == bytes)
      }
    }
  }
  @Test func manyUnrelatedAssetsDoNotTripDictionaryCompatibilityLimit() throws {
    let temporary = try DrawingExchangeCarrierTestBag(); defer { temporary.dispose() }
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/DrawingExchange/v1/source-free.zip")
    let seed = try DrawingExchangeCarrier.stageZIP(fixture, stagingParent: temporary.root)
    var payload: [String: Data] = [:]
    for path in seed.files.entries.keys where path.hasPrefix("data/") { payload[path] = try seed.files.record(at: path) }
    var index = try ExchangeJSON.validate(seed.indexJSON)
    var assets = try #require(index["assets"] as? [[String: Any]])
    for n in 0..<10_001 {
      let data = Data("media-\(n)".utf8), asset = try ExchangeAsset(bytes: data, mediaType: "application/octet-stream", encoding: "example.binary/1")
      payload["data/objects/sha256/" + asset.object.description] = data
      assets.append(try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(asset)) as? [String: Any]))
    }
    index["assets"] = assets; payload["data/exchange.json"] = try JSONSerialization.data(withJSONObject: index)
    let bag = try DrawingExchangeCarrierTestBag(files: payload); defer { bag.dispose() }
    let staged = try DrawingExchangeCarrier.stageDirectory(bag.source, stagingParent: bag.root)
    #expect(staged.files.entries.count > 10_000)
    let drawingPath = try #require(staged.files.entries.keys.first { $0.hasSuffix("/drawing.json") })
    let drawing = try staged.files.record(at: drawingPath)
    guard case .materialized = try DrawingExchangeCodec.decode(drawing, files: staged.files) else { Issue.record("Valid source-free drawing rejected"); return }
    #expect(staged.statistics.imageDecodeCount == 0)
  }
  @Test func parentDirectoryReplacementIsRejected() throws {
    let bag = try DrawingExchangeCarrierTestBag(); defer { bag.dispose() }
    let staged = try DrawingExchangeCarrier.stageDirectory(bag.source, stagingParent: bag.root)
    let data = staged.stagingURL.appendingPathComponent("data"), moved = staged.stagingURL.appendingPathComponent("moved")
    try FileManager.default.moveItem(at: data, to: moved)
    try FileManager.default.createSymbolicLink(at: data, withDestinationURL: moved)
    #expect(throws: (any Error).self) { try staged.files.record(at: "data/exchange.json") }
  }

  @Test func cancellationInsideHighlyCompressibleOutputIsBounded() throws {
    let bag = try DrawingExchangeCarrierTestBag(); defer { bag.dispose() }
    let archive = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/DrawingExchange/dx03/compressible-cancellation.zip")
    let original = try Data(contentsOf: archive)
    let root = bag.root
    do {
      _ = try DrawingExchangeCarrier.stageZIP(archive, stagingParent: root, cancelled: {
        guard let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return false }
        for case let url as URL in entries where url.path.contains("exchange-incoming-") && url.path.hasSuffix("/data/blob") {
          if ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) >= 1024 * 1024 { return true }
        }
        return false
      })
      Issue.record("DEFLATE output cancellation ignored")
    } catch let failure as ExchangeCarrierFailure {
      #expect(failure.underlying is CancellationError)
      let blob = failure.stagingURL.appendingPathComponent("payload/data/blob")
      let size = try blob.resourceValues(forKeys: [.fileSizeKey]).fileSize
      #expect(size != nil && size! <= 2 * 1024 * 1024)
      #expect(try Data(contentsOf: failure.stagingURL.appendingPathComponent("incoming.zip")) == original)
    }
    #expect(try Data(contentsOf: archive) == original)
  }

  @Test func emptyDirectoryStreamsAndCRC() throws {
    let bag = try DrawingExchangeCarrierTestBag(); defer { bag.dispose() }
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/DrawingExchange/dx03")
    for name in ["empty-directory-deflated", "empty-directory-stored"] {
      _ = try DrawingExchangeCarrier.stageZIP(fixtures.appendingPathComponent(name + ".zip"), stagingParent: bag.root)
    }
    for name in ["empty-directory-bad-deflate", "empty-directory-missing-deflate", "empty-directory-bad-crc"] {
      #expect(throws: ExchangeCarrierFailure.self) { try DrawingExchangeCarrier.stageZIP(fixtures.appendingPathComponent(name + ".zip"), stagingParent: bag.root) }
    }
  }
  @Test func preservationCannotMutateInputCarrier() throws {
    let bag = try DrawingExchangeCarrierTestBag(); defer { bag.dispose() }
    let staged = try DrawingExchangeCarrier.stageDirectory(bag.source, stagingParent: bag.root)
    let childDirectory = staged.stagingURL.appendingPathComponent("copy"), childZIP = staged.stagingURL.appendingPathComponent("copy.zip")
    #expect(throws: (any Error).self) { try DrawingExchangeCarrier.preserveDirectory(staged.files, to: childDirectory) }
    #expect(throws: (any Error).self) { try DrawingExchangeCarrier.preserveZIP(staged.files, to: childZIP) }
    #expect(!FileManager.default.fileExists(atPath: childDirectory.path))
    #expect(!FileManager.default.fileExists(atPath: childZIP.path))
    let again = try DrawingExchangeCarrier.stageDirectory(staged.stagingURL, stagingParent: bag.root)
    #expect(again.files.entries.mapValues(\.digest) == staged.files.entries.mapValues(\.digest))
  }

  @Test func mutationBetweenHashVerificationAndResolverSealIsRefused() throws {
    let bag = try DrawingExchangeCarrierTestBag(); defer { bag.dispose() }
    let limits = ExchangeCarrierLimits(), counters = ExchangeCarrierCounters()
    let entries = try DrawingExchangeCarrier.verify(bag.source, limits: limits, counters: counters, cancelled: { false })
    try Data("{}".utf8).write(to: bag.source.appendingPathComponent("data/exchange.json"))
    #expect(throws: (any Error).self) { try VerifiedExchangeFiles(entries: entries, stagingURL: bag.source, limits: limits, counters: counters) }
  }

}
