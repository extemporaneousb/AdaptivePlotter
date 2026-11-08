import Foundation
import DrawingLibrary
import PortraitCore
import Testing

@Suite("DX07 neutral exact Photo and Input values", .serialized)
struct DrawingLibraryInputTests {
  @Test("Exact source loading preserves JSON, masks, descriptor aliases and offline selected closure", arguments: [false, true])
  func exactClosure(aliases: Bool) async throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryPhotoFixture(aliases: aliases)
    let directory = root.appendingPathComponent("library")
    let owner = DrawingLibrary(directoryURL: directory)
    try await fixture.publish(to: owner)
    #expect(try await owner.drawings().entries.isEmpty)
    await owner.closeLibrary()
    let library = DrawingLibrary(directoryURL: directory)
    let photo = try await library.photo(fixture.photo.reference)
    let input = try await library.input(fixture.input.reference)
    #expect(photo.record.originalJSON == fixture.photo.record.originalJSON)
    #expect(input.record.originalJSON == fixture.input.record.originalJSON)
    #expect(input.photo.record.originalJSON == photo.record.originalJSON)
    #expect(input.reference == fixture.input.reference && input.record.photo == photo.reference)
    #expect(input.record.mask == fixture.input.record.mask)
    #expect(input.record.sourceToInput == fixture.input.record.sourceToInput)
    #expect(input.record.inputToField == fixture.input.record.inputToField)
    let expected = Dictionary(fixture.input.assets.map { ($0.descriptor.asset.object, $0.bytes) }, uniquingKeysWith: { $1 })
    let actual = Dictionary(input.assets.map { ($0.descriptor.asset.object, $0.bytes) }, uniquingKeysWith: { $1 })
    #expect(actual == expected)
    for asset in input.assets { #expect(try await library.asset(asset.descriptor.asset.object) == asset.bytes) }
    let retained = try await library.retain(fixture.drawing(), reason: "explicit-source-test", closure: .init(input: input))
    let exported = root.appendingPathComponent("drawing.zip")
    try await library.exportDrawing(retained.reference, to: exported)
    let stage = root.appendingPathComponent("stage")
    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
    let admitted = try ExchangeAdmission.validate(DrawingExchangeCarrier.stageZIP(exported, stagingParent: stage))
    #expect(try admitted.files.record(at: fixture.photoPath) == photo.record.originalJSON)
    #expect(try admitted.files.record(at: fixture.inputPath) == input.record.originalJSON)
    if aliases {
      #expect(try admitted.files.record(at: "data/objects/sha256/" + photo.reference.digest.description) == photo.record.originalJSON)
    }
    let offline = DrawingLibrary(directoryURL: root.appendingPathComponent("offline"))
    #expect(try await offline.importDrawings(from: exported) == [retained.reference])
    #expect(try await offline.photo(photo.reference).record.originalJSON == photo.record.originalJSON)
    #expect(try await offline.input(input.reference).record.originalJSON == input.record.originalJSON)
    await offline.closeLibrary()
    await library.closeLibrary()
  }

  @Test("Unknown source requirements gate dependent capabilities without erasing intrinsic source facts", arguments: DrawingLibraryPhotoFixture.RequiredScope.allCases)
  func unsupportedSource(scope: DrawingLibraryPhotoFixture.RequiredScope) async throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryPhotoFixture()
    let required = try fixture.requiring(scope)
    let library = DrawingLibrary(directoryURL: root)
    try await library.publishPhotoFixture(required.payload)
    if scope != .input {
      await #expect(throws: (any Error).self) { try await library.photo(required.photo) }
    }
    await #expect(throws: (any Error).self) { try await library.input(required.input) }
    if scope == .index {
      // An unresolved enclosing requirement cannot be stripped by extracting
      // its source records into a new supported authored publication.
      await #expect(throws: (any Error).self) {
        try await library.retain(fixture.drawing(input: required.input), reason: "unsupported-enclosing-context")
      }
      #expect(try await library.drawings().entries.isEmpty)
    } else {
      // Intrinsic source requirements remain on their exact records. Known
      // geometry is independently usable while source-dependent work is denied.
      let ref = try await library.retain(fixture.drawing(input: required.input), reason: "explicit-known-geometry").reference
      let geometry = try await library.drawing(ref)
      #expect(geometry.input == .present(required.input))
      #expect(!geometry.capabilities.sourceSemanticsSupported)
      try geometry.capabilities.require(.plot)
      #expect(throws: (any Error).self) { try geometry.capabilities.require(.regenerate) }
      #expect(throws: (any Error).self) { try geometry.capabilities.require(.train) }
      let exported = root.appendingPathComponent("intrinsic-source.zip")
      try await library.exportDrawing(ref, to: exported)
      let stage = root.appendingPathComponent("stage")
      try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
      let admitted = try ExchangeAdmission.validate(DrawingExchangeCarrier.stageZIP(exported, stagingParent: stage))
      #expect(try admitted.files.record(at: fixture.photoPath) == required.payload[fixture.photoPath])
      #expect(try admitted.files.record(at: fixture.inputPath) == required.payload[fixture.inputPath])
      let sourcePath = scope == .photo ? fixture.photoPath : fixture.inputPath
      let sourceJSON = try #require(JSONSerialization.jsonObject(with: admitted.files.record(at: sourcePath)) as? [String: Any])
      #expect(sourceJSON["requiredFeatures"] as? [String] == ["example.dx07-required/1"])
      let offline = DrawingLibrary(directoryURL: root.appendingPathComponent("offline"))
      #expect(try await offline.importDrawings(from: exported) == [ref])
      let reopened = try await offline.drawing(ref)
      #expect(reopened.input == .present(required.input) && reopened.program == geometry.program)
      #expect(!reopened.capabilities.sourceSemanticsSupported)
      #expect(throws: (any Error).self) { try reopened.capabilities.require(.regenerate) }
      #expect(throws: (any Error).self) { try reopened.capabilities.require(.train) }
      await #expect(throws: (any Error).self) { try await offline.input(required.input) }
      if scope == .photo { await #expect(throws: (any Error).self) { try await offline.photo(required.photo) } }
      await offline.closeLibrary()
    }
    #expect(try await library.photos().entries.map(\.reference) == [required.photo])
    await library.closeLibrary()
  }

  @Test("Exact source selectors reject divergent digests and corrupted selected raw assets")
  func exactSelectorsAndIntegrity() async throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryPhotoFixture()
    let library = DrawingLibrary(directoryURL: root)
    try await fixture.publish(to: library)
    let wrongPhoto = PhotoRef(issuer: fixture.photo.reference.issuer, revision: fixture.photo.reference.revision, digest: .hash(Data("wrong photo".utf8)))
    let wrongInput = ImageInputRef(issuer: fixture.input.reference.issuer, revision: fixture.input.reference.revision, digest: .hash(Data("wrong input".utf8)))
    await #expect(throws: (any Error).self) { try await library.photo(wrongPhoto) }
    await #expect(throws: (any Error).self) { try await library.input(wrongInput) }
    await #expect(throws: (any Error).self) { try await library.inputs(for: wrongPhoto) }
    let loaded = try await library.input(fixture.input.reference)
    for digest in [loaded.record.raster.object, try #require(loaded.record.mask).object] {
      let asset = try #require(loaded.assets.first { $0.descriptor.asset.object == digest })
      let file = root.appendingPathComponent("objects/sha256/" + digest.description)
      try Data(repeating: 0x78, count: asset.bytes.count).write(to: file, options: .atomic)
      do {
        _ = try await library.input(fixture.input.reference)
        Issue.record("Selected raw source corruption was accepted")
      } catch DrawingExchangeError.digestMismatch { }
      try asset.bytes.write(to: file, options: .atomic)
      #expect(try await library.input(fixture.input.reference).reference == fixture.input.reference)
    }
    await library.closeLibrary()
  }
}
