import Foundation
import DrawingLibrary
import PortraitCore
import Testing

@Suite("DX06 image record and asset aliases", .serialized)
struct DrawingLibraryResultImageAliasTests {
  @Test("Equal Photo and preparation bytes preserve canonical objects and typed source records")
  func equalPhotoReceiptBytes() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("dx06-image-alias-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let pixels = try DrawingImageAsset.gray8(Data([1, 2, 3, 4]), width: 2, height: 2)
    let photo = try DrawingImageRecords.photo(identity: .init(issuer: UUID()), original: pixels, width: 2, height: 2,
      acquired: .unknown(provenance: "Synthetic acquisition"), imported: .unknown(provenance: "Synthetic import"))
    // These are legitimate JSON assets with exactly the same bytes as a typed
    // Photo record. A digest does not identify which path's closure role to keep.
    let preparation = try DrawingProducerReceipt(id: "example.alias-preparation", version: "1", recordJSON: photo.record.originalJSON)
    let input = try DrawingImageRecords.input(identity: .init(issuer: UUID()), photo: photo, raster: pixels,
      width: 2, height: 2, orientation: "up", sourceToInput: ExchangeTransform([1,0,0,0,1,0,0,0,1]),
      inputToField: ExchangeTransform([0.5,0,0,0,-0.5,1,0,0,1]), mask: .none,
      operations: [DrawingImageOperation(kind: "identity", parametersJSON: photo.record.originalJSON)], preparation: preparation)
    #expect(preparation.record == photo.reference.digest)
    let base = try DrawingLibraryResultFixture.drawing()
    let value = try Drawing(program: base.drawing.program, input: .present(input.reference), parent: .none,
      producer: DrawingProducerReceipt(id: "example.alias-drawing", version: "1", recordJSON: photo.record.originalJSON))
    let frozen = try DrawingExchangeCodec.freeze(value, identity: .init(issuer: UUID()), createdAt: Date(timeIntervalSince1970: 1_800_000_000))
    let photoPath = "data/photos/\(photo.reference.issuer.uuidString.lowercased())/\(photo.reference.revision.uuidString.lowercased())/photo.json"
    let inputPath = "data/inputs/\(input.reference.issuer.uuidString.lowercased())/\(input.reference.revision.uuidString.lowercased())/input.json"
    let objectPath = "data/objects/sha256/" + photo.reference.digest.description
    var opaque = try DrawingLibraryResultFixture(drawing: frozen, features: ["example.alias-context/1"])
    opaque.payload[photoPath] = photo.record.originalJSON
    opaque.payload[inputPath] = input.record.originalJSON
    var descriptors = try #require(opaque.index["assets"] as? [[String: Any]])
    for asset in input.assets {
      let digest = asset.descriptor.asset.object.description
      opaque.payload["data/objects/sha256/" + digest] = asset.bytes
      if !descriptors.contains(where: { ($0["object"] as? String) == digest }) {
        descriptors.append(try #require(DrawingLibraryResultFixture.wire(asset.descriptor) as? [String: Any]))
      }
    }
    opaque.index["assets"] = descriptors
    let opaqueURL = root.appendingPathComponent("opaque")
    try opaque.write(to: opaqueURL)
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("library"))
    let opaqueRef = try await library.mountResult(from: opaqueURL).reference
    let opaqueBytes = try DrawingLibraryResultFixture.bytes(await library.result(opaqueRef))
    let retained = try await library.retain(value, reason: "explicit-alias-source", closure: .init(input: input))
    // No closure on this request: selectedInputPublication must preserve BOTH
    // exact typed record paths despite canonical-object digest preference.
    let reused = try Drawing(program: value.program, input: .present(input.reference), parent: .none,
      producer: DrawingProducerReceipt(id: "example.alias-reused", version: "1", recordJSON: photo.record.originalJSON))
    let reusedRef = try await library.retain(reused, reason: "explicit-alias-reuse").reference
    for (position, ref) in [retained.reference, reusedRef].enumerated() {
      let exported = root.appendingPathComponent("export-\(position)")
      try await library.exportDrawing(ref, to: exported)
      let stage = root.appendingPathComponent("stage-\(position)")
      try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
      let staged = try DrawingExchangeCarrier.stageDirectory(exported, stagingParent: stage)
      let admitted = try ExchangeAdmission.validate(staged)
      #expect(try admitted.files.record(at: photoPath) == photo.record.originalJSON)
      #expect(try admitted.files.record(at: inputPath) == input.record.originalJSON)
      #expect(try admitted.files.record(at: objectPath) == photo.record.originalJSON)
      let inventory = admitted.files.entries.values.map {
        ExchangeCatalogFile(path: $0.path, storagePath: $0.path, digest: $0.digest, byteLength: $0.byteLength)
      }
      let lazy = try VerifiedExchangeFiles(catalogRoot: exported, inventory: inventory)
      #expect(try lazy.record(photo.reference.digest) == photo.record.originalJSON)
      let selectedAsset = try lazy.selectedVerifiedFiles()
      #expect(selectedAsset.entries[objectPath] != nil)
      #expect(selectedAsset.entries[photoPath] == nil)
      _ = try lazy.record(at: photoPath)
      _ = try lazy.record(at: inputPath)
      let selectedRoles = try lazy.selectedVerifiedFiles()
      #expect(selectedRoles.entries[objectPath] != nil && selectedRoles.entries[photoPath] != nil && selectedRoles.entries[inputPath] != nil)
      let offline = DrawingLibrary(directoryURL: root.appendingPathComponent("offline-\(position)"))
      #expect(try await offline.importDrawings(from: exported) == [ref])
      #expect(try await offline.drawing(ref).input == .present(input.reference))
      let roundtrip = root.appendingPathComponent("roundtrip-\(position).zip")
      try await offline.exportDrawing(ref, to: roundtrip)
      await offline.closeLibrary()
      let reopened = DrawingLibrary(directoryURL: root.appendingPathComponent("offline-\(position)"))
      #expect(try await reopened.drawing(ref).input == .present(input.reference))
      await reopened.closeLibrary()
    }
    let preserved = try await library.result(opaqueRef)
    if case .opaque? = preserved.drawings[frozen.reference] {} else { Issue.record("Authored aliases changed opaque result admission") }
    #expect(try DrawingLibraryResultFixture.bytes(preserved) == opaqueBytes)
    let opaqueExport = root.appendingPathComponent("opaque-roundtrip.zip")
    try await library.exportResult(opaqueRef, to: opaqueExport)
    let opaqueOffline = DrawingLibrary(directoryURL: root.appendingPathComponent("opaque-offline"))
    let importedOpaque = try await opaqueOffline.mountResult(from: opaqueExport).reference
    #expect(importedOpaque == opaqueRef)
    #expect(try DrawingLibraryResultFixture.bytes(await opaqueOffline.result(importedOpaque)) == opaqueBytes)
    await opaqueOffline.closeLibrary()
    await library.closeLibrary()
  }
}
