import Foundation
import Testing
@testable import Drawing

@Suite("Receipt JSON proof reuse", .serialized)
struct DrawingExchangeReceiptProofCacheTests {
  private struct InputFixture {
    let reference: ImageInputRef
    let objects: [ExchangeDigest: Data]
    let receipt: ExchangeDigest
    let bytesPerRead: UInt64

    init(receiptBytes: Data) throws {
      let issuer = UUID(), photoID = UUID(), inputID = UUID()
      let photo = try JSONSerialization.data(withJSONObject: [
        "profile": "example.opaque-photo/1",
        "ref": ["issuer": issuer.uuidString.lowercased(), "revision": photoID.uuidString.lowercased()],
      ])
      let pixels = Data([0, 255]), parameters = Data("{}".utf8)
      let raster = try ExchangeAsset(bytes: pixels, mediaType: "application/octet-stream", encoding: "raw-gray8")
      let parameter = try ExchangeAsset(bytes: parameters, mediaType: "application/json", encoding: "example.parameters/1")
      let layout = try ExchangeRasterLayout(width: 2, height: 1, bytesPerPixel: 1, rowStride: 2)
      let descriptor = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ExchangeAssetDescriptor(asset: raster, pixelLayout: layout)))
      let parameterObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(parameter))
      receipt = .hash(receiptBytes)
      let input = try JSONSerialization.data(withJSONObject: [
        "profile": "adaptiveplotter.image-input/1", "requiredFeatures": [],
        "ref": ["issuer": issuer.uuidString.lowercased(), "revision": inputID.uuidString.lowercased()],
        "photo": ["issuer": issuer.uuidString.lowercased(), "revision": photoID.uuidString.lowercased(), "digest": ExchangeDigest.hash(photo).description],
        "pixelBasis": ["dimensions": ["width": 2, "height": 1], "orientation": "up", "origin": "top-left",
          "xAxis": "right", "yAxis": "down", "pixelEdges": "integer", "pixelCenters": "half-integer"],
        "sourceToInput": [1, 0, 0, 0, 1, 0, 0, 0, 1], "inputToField": [1, 0, 0, 0, 1, 0, 0, 0, 1],
        "raster": descriptor, "mask": ["state": "none"],
        "operations": [["kind": "identity", "parameters": parameterObject]],
        "preparation": ["id": "example.preparation", "version": "1", "record": receipt.description],
      ])
      reference = .init(issuer: issuer, revision: inputID, digest: .hash(input))
      objects = [.hash(photo): photo, .hash(input): input, raster.object: pixels,
        parameter.object: parameters, receipt: receiptBytes]
      bytesPerRead = UInt64(input.count + photo.count + receiptBytes.count)
    }

    func catalog(at root: URL) throws -> VerifiedExchangeFiles {
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      var inventory: [ExchangeCatalogFile] = []
      for (digest, bytes) in objects {
        try bytes.write(to: root.appendingPathComponent(digest.description))
        inventory.append(.init(path: "data/objects/sha256/" + digest.description,
          storagePath: digest.description, digest: digest, byteLength: UInt64(bytes.count)))
      }
      return try VerifiedExchangeFiles(catalogRoot: root, inventory: inventory)
    }

    func admit(_ resolver: ExchangeObjectResolver, cache: ExchangeJSONProofCache) throws -> ExchangeImageInputRecord {
      try DrawingImageAdmission.input(reference, objects: resolver, supportedFeatures: [], assetDescriptors: [:], proofCache: cache)
    }
  }

  @Test func cacheHitRetainsReceiptReadAndExactMaterializationBudget() throws {
    let fixture = try InputFixture(receiptBytes: Data("{\"raster\":[0.25,0.75]}".utf8))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("receipt-budget-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = try fixture.catalog(at: root)
    let budget = ExchangeReadBudget(maximum: fixture.bytesPerRead * 2)
    let resolver = ExchangeObjectResolver.files(files, budget: budget), cache = ExchangeJSONProofCache()
    let first = try fixture.admit(resolver, cache: cache), second = try fixture.admit(resolver, cache: cache)
    #expect(first.originalJSON == second.originalJSON)
    #expect(!first.supportedSemantics && !second.supportedSemantics)
    #expect(budget.used == fixture.bytesPerRead * 2)
    #expect(files.statistics.materializationReadPassesByPath["data/objects/sha256/" + fixture.receipt.description] == 2)
    #expect(throws: (any Error).self) { try fixture.admit(resolver, cache: cache) }
  }

  @Test func cachedReceiptStillRejectsFileMutationAndDictionaryDigestMismatch() throws {
    let original = Data("{\"raster\":[0.25,0.75]}".utf8), changed = Data("{\"raster\":[0.75,0.25]}".utf8)
    let fixture = try InputFixture(receiptBytes: original)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("receipt-mutation-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = try fixture.catalog(at: root), cache = ExchangeJSONProofCache()
    let resolver = ExchangeObjectResolver.files(files)
    _ = try fixture.admit(resolver, cache: cache)
    #expect(original.count == changed.count)
    let writer = try FileHandle(forWritingTo: root.appendingPathComponent(fixture.receipt.description))
    try writer.write(contentsOf: changed)
    try writer.close()
    #expect(throws: (any Error).self) { try fixture.admit(resolver, cache: cache) }
    var objects = fixture.objects
    objects[fixture.receipt] = changed
    #expect(throws: (any Error).self) { try fixture.admit(.dictionary(objects), cache: cache) }
  }

  @Test func failedJSONProofNeverBecomesReusable() throws {
    for invalid in ["{\"value\":1,\"value\":2}", "{\"value\":NaN}", "[1,2]", "{\"value\":01}"] {
      let fixture = try InputFixture(receiptBytes: Data(invalid.utf8)), cache = ExchangeJSONProofCache()
      for _ in 0..<2 {
        #expect(throws: (any Error).self) { try fixture.admit(.dictionary(fixture.objects), cache: cache) }
      }
    }
  }
}
