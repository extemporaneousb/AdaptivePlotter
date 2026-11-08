import Foundation
import PortraitCore
import Testing

@Suite("DX07 exact source factory context", .serialized)
struct DrawingLibraryPhotoAdmissionTests {
  private func files(_ payload: [String: Data], root: URL) throws -> VerifiedExchangeFiles {
    let source = root.appendingPathComponent("source")
    try DrawingLibraryPhotoFixture.write(payload, to: source)
    let stage = root.appendingPathComponent("stage")
    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
    return try DrawingExchangeCarrier.stageDirectory(source, stagingParent: stage).files
  }
  @Test("Exact Core factories refuse unresolved enclosing and record requirements", arguments: ["index", "photo", "input", "kind"])
  func requiredSourceContext(scope: String) throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryPhotoFixture()
    var payload: [String: Data]
    let photo: PhotoRef, input: ImageInputRef
    if scope == "kind" {
      payload = try fixture.packagePayload()
      var index = try #require(JSONSerialization.jsonObject(with: payload["data/exchange.json"]!) as? [String: Any])
      index["kind"] = "example.unsupported-source-kind"
      payload["data/exchange.json"] = try DrawingLibraryPhotoFixture.json(index)
      photo = fixture.photo.reference; input = fixture.input.reference
    } else {
      let required = try fixture.requiring(#require(DrawingLibraryPhotoFixture.RequiredScope(rawValue: scope)))
      payload = required.payload; photo = required.photo; input = required.input
    }
    let selected = try files(payload, root: root)
    if scope != "input" {
      #expect(throws: (any Error).self) { try DrawingImageRecords.admitPhoto(photo, files: selected) }
    }
    #expect(throws: (any Error).self) { try DrawingImageRecords.admitInput(input, files: selected) }
  }

  @Test("Unknown extension objects never acquire asset semantics")
  func inertVendorObjects() throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryPhotoFixture()
    var payload = try fixture.packagePayload()
    let inert: [String: Any] = ["object": String(repeating: "0", count: 64), "byteLength": 42,
      "nested": ["object": String(repeating: "f", count: 64), "byteLength": 9]]
    var photoJSON = try #require(JSONSerialization.jsonObject(with: payload[fixture.photoPath]!) as? [String: Any])
    photoJSON["vendorExtension"] = inert
    let photoBytes = try DrawingLibraryPhotoFixture.json(photoJSON)
    payload[fixture.photoPath] = photoBytes
    let photo = PhotoRef(issuer: fixture.photo.reference.issuer, revision: fixture.photo.reference.revision, digest: .hash(photoBytes))
    var inputJSON = try #require(JSONSerialization.jsonObject(with: payload[fixture.inputPath]!) as? [String: Any])
    inputJSON["photo"] = try DrawingLibraryPhotoFixture.wire(photo)
    inputJSON["vendorExtension"] = inert
    let inputBytes = try DrawingLibraryPhotoFixture.json(inputJSON)
    payload[fixture.inputPath] = inputBytes
    let input = ImageInputRef(issuer: fixture.input.reference.issuer, revision: fixture.input.reference.revision, digest: .hash(inputBytes))
    var index = try #require(JSONSerialization.jsonObject(with: payload["data/exchange.json"]!) as? [String: Any])
    index["photos"] = try DrawingLibraryPhotoFixture.wire([photo])
    index["inputs"] = try DrawingLibraryPhotoFixture.wire([input])
    index["vendorExtension"] = inert
    payload["data/exchange.json"] = try DrawingLibraryPhotoFixture.json(index)
    let selected = try files(payload, root: root)
    let loadedPhoto = try DrawingImageRecords.admitPhoto(photo, files: selected)
    let loadedInput = try DrawingImageRecords.admitInput(input, files: selected)
    #expect(loadedPhoto.record.originalJSON == photoBytes)
    #expect(loadedInput.record.originalJSON == inputBytes)
    #expect(loadedInput.photo.reference == photo)
    let required = Set(fixture.input.assets.map { $0.descriptor.asset.object })
    #expect(Set(loadedInput.assets.map { $0.descriptor.asset.object }) == required)
  }

  @Test("Conflicting duplicate index descriptors cannot be normalized by a last-wins map")
  func conflictingDescriptors() throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryPhotoFixture()
    var payload = try fixture.packagePayload()
    var index = try #require(JSONSerialization.jsonObject(with: payload["data/exchange.json"]!) as? [String: Any])
    var assets = try #require(index["assets"] as? [[String: Any]])
    var conflict = try #require(assets.first)
    conflict["encoding"] = "example.conflicting-encoding/1"
    assets.append(conflict); index["assets"] = assets
    payload["data/exchange.json"] = try DrawingLibraryPhotoFixture.json(index)
    let selected = try files(payload, root: root)
    #expect(throws: (any Error).self) { try DrawingImageRecords.admitPhoto(fixture.photo.reference, files: selected) }
    #expect(throws: (any Error).self) { try DrawingImageRecords.admitInput(fixture.input.reference, files: selected) }
  }
  @Test("One top-level source load enforces an aggregate materialization budget across nested Photo and assets")
  func aggregateBudget() throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryPhotoFixture()
    let payload = try fixture.packagePayload()
    let source = root.appendingPathComponent("source")
    try DrawingLibraryPhotoFixture.write(payload, to: source)
    let stage = root.appendingPathComponent("stage")
    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
    let staged = try DrawingExchangeCarrier.stageDirectory(source, stagingParent: stage)
    #expect(try DrawingImageRecords.admitInput(fixture.input.reference, files: staged.files).reference == fixture.input.reference)
    let inventory = staged.files.entries.values.map {
      ExchangeCatalogFile(path: $0.path, storagePath: $0.path, digest: $0.digest, byteLength: $0.byteLength)
    }
    let largest = try #require(inventory.map(\.byteLength).max())
    var limits = ExchangeCarrierLimits()
    limits.maximumMaterializedBytes = largest + 1
    #expect(inventory.allSatisfy { $0.byteLength < limits.maximumMaterializedBytes })
    let boundedPhoto = try VerifiedExchangeFiles(catalogRoot: source, inventory: inventory, limits: limits)
    #expect(throws: (any Error).self) { try DrawingImageRecords.admitPhoto(fixture.photo.reference, files: boundedPhoto) }
    let boundedInput = try VerifiedExchangeFiles(catalogRoot: source, inventory: inventory, limits: limits)
    #expect(throws: (any Error).self) { try DrawingImageRecords.admitInput(fixture.input.reference, files: boundedInput) }
  }

}
