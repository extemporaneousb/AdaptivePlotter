import Foundation
import DrawingLibrary
import PortraitCore
import Testing

private extension DrawingLibrary {
  func publishResultWithTransaction(_ source: URL, transaction: UUID) throws -> DrawingLibraryResultRef {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("dx06-fixed-transaction-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let staged = try DrawingExchangeCarrier.stageDirectory(source, stagingParent: temporary)
    let admitted = try ExchangeAdmission.validate(staged)
    let catalog = try commonCatalog()
    defer { refreshOwnership() }
    _ = try catalog.publish(admitted, transactionID: transaction)
    return .init(indexDigest: .hash(admitted.index.originalJSON), packageDigest: LibraryExchangeCatalog.inventoryDigest(admitted.files.entries.values.map {
      .init(path: $0.path, digest: $0.digest, byteLength: $0.byteLength)
    }))
  }
}

@Suite("DX06 compatible authored context selection", .serialized)
struct DrawingLibraryResultSourceContextTests {
  /// A bounded deterministic nonce search makes index ordering independent of
  /// UUID randomness. The test fails setup explicitly if its bound is exhausted.
  private func sortIndex(_ fixture: inout DrawingLibraryResultFixture, prefix: String) throws -> ExchangeDigest {
    for nonce in 0..<4096 {
      fixture.index["contextOrderingNonce"] = nonce
      let digest = ExchangeDigest.hash(try DrawingLibraryResultFixture.json(fixture.index))
      if digest.description.hasPrefix(prefix) { return digest }
    }
    throw DrawingExchangeError.malformed("Fixture nonce search exhausted 4096 candidates")
  }

  @Test("Cold load, authored export and parent closure skip only opaque contexts while supported integrity errors propagate")
  func compatibleContextAndIntegrity() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("dx06-compatible-context-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let frozen = try DrawingLibraryResultFixture.drawing()
    var opaque = try DrawingLibraryResultFixture(drawing: frozen, features: ["example.opaque-context/1"], marker: "opaque-only")
    var supported = try DrawingLibraryResultFixture(drawing: frozen, marker: "supported")
    let opaqueDigest = try sortIndex(&opaque, prefix: "0")
    let supportedDigest = try sortIndex(&supported, prefix: "f")
    #expect(opaqueDigest.description < supportedDigest.description)
    let opaqueURL = root.appendingPathComponent("opaque")
    let supportedURL = root.appendingPathComponent("supported")
    try opaque.write(to: opaqueURL)
    try supported.write(to: supportedURL)
    let directory = root.appendingPathComponent("library")
    let owner = DrawingLibrary(directoryURL: directory)
    let opaqueRef = try await owner.publishResultWithTransaction(opaqueURL,
      transaction: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")))
    let supportedRef = try await owner.mountResult(from: supportedURL).reference
    #expect(opaqueRef.indexDigest == opaqueDigest && supportedRef.indexDigest == supportedDigest)
    let originalOpaque = try await owner.result(opaqueRef)
    if case .opaque? = originalOpaque.drawings[frozen.reference] {} else { Issue.record("Unsupported index exposed a materialized Drawing") }
    #expect(!originalOpaque.capabilities.supported.contains(.interpretResults))
    let opaqueBytes = try DrawingLibraryResultFixture.bytes(originalOpaque)
    let export = root.appendingPathComponent("opaque-exact.zip")
    try await owner.exportResult(opaqueRef, to: export)
    await owner.closeLibrary()
    let offline = DrawingLibrary(directoryURL: root.appendingPathComponent("opaque-offline"))
    let offlineRef = try await offline.mountResult(from: export).reference
    #expect(offlineRef == opaqueRef)
    #expect(try DrawingLibraryResultFixture.bytes(await offline.result(offlineRef)) == opaqueBytes)
    await offline.closeLibrary()

    // This object occurs only in the opaque result. Geometry selection must not
    // demand integrity admission of unrelated result media to load the Drawing.
    #expect(opaque.media.object != supported.media.object)
    let opaqueMedia = directory.appendingPathComponent("objects/sha256/" + opaque.media.object.description)
    let mediaBytes = try Data(contentsOf: opaqueMedia)
    try FileManager.default.removeItem(at: opaqueMedia)
    let cold = DrawingLibrary(directoryURL: directory)
    #expect(try await cold.drawings().entries.map(\.reference) == [frozen.reference])
    let loaded = try await cold.drawing(frozen.reference)
    #expect(loaded.reference == frozen.reference && loaded.program == frozen.drawing.program)
    #expect(loaded.capabilities.supported.contains(.preview))
    #expect(loaded.capabilities.supported.contains(.plot))
    #expect(loaded.capabilities.supported.contains(.edit))
    let authoredExport = root.appendingPathComponent("authored.zip")
    try await cold.exportDrawing(frozen.reference, to: authoredExport)
    await cold.closeLibrary()
    let authored = DrawingLibrary(directoryURL: root.appendingPathComponent("authored-offline"))
    #expect(try await authored.importDrawings(from: authoredExport) == [frozen.reference])
    #expect(try await authored.drawing(frozen.reference).program == frozen.drawing.program)
    await authored.closeLibrary()

    // A selected supported context with corrupt bytes is an integrity failure,
    // not another unsupported candidate to skip in search of a convenient value.
    let supportedIndex = directory.appendingPathComponent("objects/sha256/" + supportedRef.indexDigest.description)
    let indexBytes = try Data(contentsOf: supportedIndex)
    try Data(repeating: 0x78, count: indexBytes.count).write(to: supportedIndex, options: .atomic)
    let corrupt = DrawingLibrary(directoryURL: directory)
    do {
      _ = try await corrupt.drawing(frozen.reference)
      Issue.record("Corrupt supported index was accepted or skipped")
    } catch DrawingExchangeError.digestMismatch { }
    await corrupt.closeLibrary()
    try indexBytes.write(to: supportedIndex, options: .atomic)

    // Parent closure acquisition uses the same compatible context lookup. A
    // synthetic child declares ancestry, without claiming verified edit semantics.
    let parentOwner = DrawingLibrary(directoryURL: directory)
    let parent = try await parentOwner.drawing(frozen.reference)
    let child = try Drawing(program: parent.program, input: .none, parent: .present(frozen.reference),
      producer: DrawingProducerReceipt(id: "example.dx06-child", version: "1", recordJSON: Data("{}".utf8)))
    let retained = try await parentOwner.retain(child, reason: "explicit-test-child")
    let childExport = root.appendingPathComponent("child.zip")
    try await parentOwner.exportDrawing(retained.reference, to: childExport)
    await parentOwner.closeLibrary()
    let childOffline = DrawingLibrary(directoryURL: root.appendingPathComponent("child-offline"))
    #expect(try await childOffline.importDrawings(from: childExport) == [retained.reference])
    #expect(try await childOffline.drawing(retained.reference).parent == .present(frozen.reference))
    #expect(try await childOffline.drawing(frozen.reference).program == frozen.drawing.program)
    await childOffline.closeLibrary()
    try mediaBytes.write(to: opaqueMedia, options: .atomic)
  }
  @Test("Warm selected non-index objects re-admit identical inode replacement and refuse corruption", arguments: ["program", "producer"])
  func warmSelectedObjectIntegrity(kind: String) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("dx06-warm-object-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryResultFixture()
    let input = root.appendingPathComponent("input")
    try fixture.write(to: input)
    let directory = root.appendingPathComponent("library")
    let library = DrawingLibrary(directoryURL: directory)
    _ = try await library.mountResult(from: input)
    let ref = fixture.frozen.reference
    let primed = try await library.drawing(ref)
    #expect(primed.reference == ref && primed.program == fixture.frozen.drawing.program)
    let bytes = kind == "program" ? fixture.frozen.originalProgramJSON : fixture.frozen.drawing.producer.originalJSON
    let object = directory.appendingPathComponent("objects/sha256/" + ExchangeDigest.hash(bytes).description)
    // Atomic write replaces the inode. Equal immutable bytes remain valid, so
    // cache invalidation must lead to fresh admission rather than false refusal.
    try bytes.write(to: object, options: .atomic)
    let replaced = try await library.drawing(ref)
    #expect(replaced.reference == ref && replaced.program == primed.program)
    // The immediately preceding read primes the replacement's own cache entry.
    try Data(repeating: 0x78, count: bytes.count).write(to: object, options: .atomic)
    do {
      _ = try await library.drawing(ref)
      Issue.record("Warm selected object corruption returned cached geometry")
    } catch DrawingExchangeError.digestMismatch { }
    try bytes.write(to: object, options: .atomic)
    let recovered = try await library.drawing(ref)
    #expect(recovered.reference == ref && recovered.program == primed.program)
    #expect(recovered.capabilities.supported.contains(.plot))
    await library.closeLibrary()
  }

  @Test("Input-bearing parents and reused inputs select compatible contexts and preserve exact photo closure")
  func imageInputContext() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("dx06-input-context-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let pixels = try DrawingImageAsset.gray8(Data([0, 64, 128, 255]), width: 2, height: 2)
    let mask = try DrawingImageAsset.gray8(Data([255, 0, 255, 0]), width: 2, height: 2)
    let photo = try DrawingImageRecords.photo(identity: .init(issuer: UUID()), original: pixels, width: 2, height: 2,
      acquired: .unknown(provenance: "Synthetic raw-pixel fixture has no camera acquisition"),
      imported: .known(ExchangeTimestamp(wallTime: "2027-01-15T08:00:00Z"), provenance: "Synthetic fixture construction"))
    let preparation = try DrawingProducerReceipt(id: "example.dx06-preparation", version: "1",
      recordJSON: Data("{\"profile\":\"example.dx06-preparation/1\",\"source\":\"synthetic 2x2 raw pixels\"}".utf8))
    let input = try DrawingImageRecords.input(identity: .init(issuer: UUID()), photo: photo, raster: pixels,
      width: 2, height: 2, orientation: "up", sourceToInput: ExchangeTransform([1,0,0,0,1,0,0,0,1]),
      inputToField: ExchangeTransform([0.5,0,0,0,-0.5,1,0,0,1]), mask: .present(mask),
      operations: [DrawingImageOperation(kind: "identity", parametersJSON: Data("{}".utf8)),
        DrawingImageOperation(kind: "mask", parametersJSON: Data("{\"purpose\":\"synthetic alternating coverage\"}".utf8))],
      preparation: preparation)
    let base = try DrawingLibraryResultFixture.drawing()
    let parentValue = try Drawing(program: base.drawing.program, input: .present(input.reference), parent: .none,
      producer: DrawingProducerReceipt(id: "example.dx06-image", version: "1", recordJSON: Data("{}".utf8)))
    let parent = try DrawingExchangeCodec.freeze(parentValue, identity: .init(issuer: UUID()), createdAt: Date(timeIntervalSince1970: 1_800_000_000))
    func includingInput(_ fixture: DrawingLibraryResultFixture) throws -> DrawingLibraryResultFixture {
      var value = fixture
      value.payload["data/photos/\(photo.reference.issuer.uuidString.lowercased())/\(photo.reference.revision.uuidString.lowercased())/photo.json"] = photo.record.originalJSON
      value.payload["data/inputs/\(input.reference.issuer.uuidString.lowercased())/\(input.reference.revision.uuidString.lowercased())/input.json"] = input.record.originalJSON
      var descriptors = try #require(value.index["assets"] as? [[String: Any]])
      for asset in input.assets {
        let object = asset.descriptor.asset.object.description
        value.payload["data/objects/sha256/" + object] = asset.bytes
        if !descriptors.contains(where: { ($0["object"] as? String) == object }) {
          descriptors.append(try #require(DrawingLibraryResultFixture.wire(asset.descriptor) as? [String: Any]))
        }
      }
      value.index["assets"] = descriptors
      return value
    }
    var opaque = try includingInput(DrawingLibraryResultFixture(drawing: parent, features: ["example.opaque-image-context/1"], marker: "opaque-image"))
    var supported = try includingInput(DrawingLibraryResultFixture(drawing: parent, marker: "supported-image"))
    let opaqueDigest = try sortIndex(&opaque, prefix: "0")
    let supportedDigest = try sortIndex(&supported, prefix: "f")
    #expect(opaqueDigest.description < supportedDigest.description)
    let opaqueURL = root.appendingPathComponent("opaque")
    let supportedURL = root.appendingPathComponent("supported")
    try opaque.write(to: opaqueURL)
    try supported.write(to: supportedURL)
    let directory = root.appendingPathComponent("library")
    let owner = DrawingLibrary(directoryURL: directory)
    _ = try await owner.publishResultWithTransaction(opaqueURL,
      transaction: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")))
    _ = try await owner.mountResult(from: supportedURL)
    await owner.closeLibrary()
    let author = DrawingLibrary(directoryURL: directory)
    #expect(try await author.drawing(parent.reference).input == .present(input.reference))
    // Raw source/raster and mask references must be verified selected objects,
    // including when a warm Drawing would otherwise reuse its geometry cache.
    for asset in [pixels, mask] {
      let object = directory.appendingPathComponent("objects/sha256/" + asset.descriptor.asset.object.description)
      try Data(repeating: 0x78, count: asset.bytes.count).write(to: object, options: .atomic)
      do {
        _ = try await author.drawing(parent.reference)
        Issue.record("Warm Drawing ignored corrupt selected raw image or mask")
      } catch DrawingExchangeError.digestMismatch { }
      try asset.bytes.write(to: object, options: .atomic)
      let recovered = try await author.drawing(parent.reference)
      #expect(recovered.reference == parent.reference && recovered.input == .present(input.reference))
      #expect(recovered.program == parentValue.program)
    }
    // No supplied image closure and no parent: this exercises standalone exact
    // InputRef lookup before another authored publication could mask the bug.
    let reused = try Drawing(program: parentValue.program, input: .present(input.reference), parent: .none,
      producer: DrawingProducerReceipt(id: "example.dx06-reused-input", version: "1", recordJSON: Data("{}".utf8)))
    let reusedRef = try await author.retain(reused, reason: "explicit-reused-input").reference
    let child = try Drawing(program: parentValue.program, input: .present(input.reference), parent: .present(parent.reference),
      producer: DrawingProducerReceipt(id: "example.dx06-image-child", version: "1", recordJSON: Data("{}".utf8)))
    let childRef = try await author.retain(child, reason: "explicit-image-child").reference
    for (position, ref) in [reusedRef, childRef].enumerated() {
      let exported = root.appendingPathComponent("image-\(position).zip")
      try await author.exportDrawing(ref, to: exported)
      let offline = DrawingLibrary(directoryURL: root.appendingPathComponent("image-offline-\(position)"))
      #expect(try await offline.importDrawings(from: exported) == [ref])
      let reloaded = try await offline.drawing(ref)
      #expect(reloaded.input == .present(input.reference))
      if ref == childRef {
        #expect(reloaded.parent == .present(parent.reference))
        #expect(try await offline.drawing(parent.reference).input == .present(input.reference))
      } else { #expect(reloaded.parent == .none) }
      let stage = root.appendingPathComponent("image-stage-\(position)")
      try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
      let staged = try DrawingExchangeCarrier.stageZIP(exported, stagingParent: stage)
      let admitted = try ExchangeAdmission.validate(staged)
      let index = try #require(admitted.index.known)
      let descriptors = Dictionary(index.assets.map { ($0.asset.object, $0) }, uniquingKeysWith: { $1 })
      let verifiedInput = try DrawingImageAdmission.input(input.reference, files: admitted.files, assetDescriptors: descriptors)
      let verifiedPhoto = try DrawingImageAdmission.photo(photo.reference, files: admitted.files, assetDescriptors: descriptors)
      #expect(verifiedInput.originalJSON == input.record.originalJSON)
      #expect(verifiedInput.photo == photo.reference)
      #expect(verifiedPhoto.originalJSON == photo.record.originalJSON)
      for asset in input.assets {
        #expect(try admitted.files.record(asset.descriptor.asset.object) == asset.bytes)
      }
      await offline.closeLibrary()
    }
    await author.closeLibrary()
  }

}
