import Foundation
import ImageIO
import DrawingLibrary
import PortraitCore
import PlotterModel
import PortraitArtists
import PortraitStudioUI
@testable import PortraitLibrary
import Testing

private extension DrawingLibrary {
  func removeAdoptedSourceAfterCommit(_ url: URL) throws {
    let catalog = try commonCatalog()
    var armed = true
    catalog.injectFault = { boundary in
      if armed, boundary == .afterSQLCommit {
        armed = false
        try FileManager.default.removeItem(at: url)
      }
    }
  }
  func clearAdoptionFault() { cachedExchangeCatalog?.injectFault = nil }
}

@Suite("Existing canonical Photo adoption", .serialized)
struct DrawingLibraryAdoptionTests {
  @Test("PNG and JPEG adoption preserves occurrence, original bytes and cleared neutral metadata", arguments: [false, true])
  func exactAdoption(jpeg: Bool) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("dx10-adoption-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let png = FlowAuthoringFixture.image(1)
    let data: Data
    if jpeg {
      let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
      let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
      let bytes = NSMutableData()
      let target = try #require(CGImageDestinationCreateWithData(bytes, "public.jpeg" as CFString, 1, nil))
      CGImageDestinationAddImage(target, image, nil)
      #expect(CGImageDestinationFinalize(target))
      data = bytes as Data
    } else { data = png }
    let photo = try PortraitDrawingImages.photo(data: data, issuer: UUID(), captureID: UUID(),
      capturedAt: Date(timeIntervalSince1970: 100), importedAt: Date(timeIntervalSince1970: 200), facts: nil)
    try await library.commitRecords([], closure: .init(photo: photo))
    let patch = DrawingLibraryPhotoMetadataPatch(title: .set(nil), subjectID: .set("subject"), sessionID: .set(nil), excluded: true)
    try await library.updatePhotoMetadata(photo.reference, patch: patch)
    let originalMetadata = try await library.photoMetadata(photo.reference)
    let store = FlowPortfolioStore(directory: root, library: library)
    try await store.loadRecords()
    let adopted = try await store.adoptExistingPhoto(photo.reference)
    #expect(adopted.photo == photo.reference && adopted.title == "Photo")
    #expect(adopted.subjectID == "subject" && adopted.sessionID == nil && adopted.excluded)
    #expect(try await store.sourceData(adopted.id) == data)
    #expect(try await library.photoMetadata(photo.reference) == originalMetadata)
    let same = try await store.adoptExistingPhoto(photo.reference)
    #expect(same.id == adopted.id)
    #expect(try await library.photos().entries.count == 1)
    let reopened = FlowPortfolioStore(directory: root, library: library)
    try await reopened.loadRecords()
    #expect(await reopened.snapshot().sources.map(\.photo) == [photo.reference])
    #expect(try await reopened.sourceData(adopted.id) == data)
    let exact = try await library.photo(photo.reference)
    #expect(exact.record.originalJSON == photo.record.originalJSON)
    #expect(exact.acquired == photo.acquired && exact.imported == photo.imported)
    await library.closeLibrary()
  }

  @Test("Drawing name edits drain in arrival order before immediate close without changing immutable bytes")
  @MainActor func drawingNameDrain() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("drawing-name-drain-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let production = try await CatalogDrawingProducer().produce(input: .square, settings: .init(style: StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID(UUID()))))
    let ref = try await library.retain(production.drawing, reason: "name fixture").reference
    let sketches = PortraitSketchCollection(library: library)
    try await sketches.select(ref)
    let original = try await library.drawing(ref)
    let first = sketches.updateDrawingName(ref, title: "First")
    let last = sketches.updateDrawingName(ref, title: "Last")
    await sketches.shutdown(); await library.closeLibrary()
    let firstFailure = await first.value, lastFailure = await last.value
    #expect(firstFailure == nil && lastFailure == nil)
    let reopened = DrawingLibrary(directoryURL: root)
    let page = try await reopened.drawings()
    #expect(page.entries.first(where: { $0.reference == ref })?.title == "Last")
    let exact = try await reopened.drawing(ref)
    #expect(exact.reference == original.reference && exact.program == original.program && exact.producer.originalJSON == original.producer.originalJSON)
    #expect(await sketches.updateDrawingName(ref, title: "Too late").value != nil)
    await reopened.closeLibrary()
  }

  @Test("Accepted Photo field patches drain in arrival order before immediate collection and Library close")
  @MainActor func metadataDrain() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("dx10-metadata-drain-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let photo = try PortraitDrawingImages.photo(data: FlowAuthoringFixture.image(1), issuer: UUID(), captureID: UUID(), capturedAt: nil, importedAt: Date())
    try await library.commitRecords([], closure: .init(photo: photo))
    let sketches = PortraitSketchCollection(library: library)
    let first = sketches.updatePhotoMetadata(photo.reference, patch: .init(title: .set("First")))
    let groups = sketches.updatePhotoMetadata(photo.reference, patch: .init(subjectID: .set("subject"), sessionID: .set("session"), excluded: true))
    let last = sketches.updatePhotoMetadata(photo.reference, patch: .init(title: .set("Last"), sessionID: .set(nil)))
    // No yield between admission and shutdown: tasks need not have started yet.
    await sketches.shutdown()
    await library.closeLibrary()
    let firstError = await first.value, groupError = await groups.value, lastError = await last.value
    #expect(firstError == nil && groupError == nil && lastError == nil)
    let reopened = DrawingLibrary(directoryURL: root)
    let value = try await reopened.photoMetadata(photo.reference)
    #expect(value == DrawingLibraryPhotoMetadata(title: "Last", subjectID: "subject", sessionID: nil, excluded: true))
    let rejected = sketches.updatePhotoMetadata(photo.reference, patch: .init(title: .set("Too late")))
    #expect(await rejected.value != nil)
    #expect(try await reopened.photoMetadata(photo.reference) == value)
    await reopened.closeLibrary()
  }

  @Test("A failed new scope cannot leave the preceding scope's rows or cursor")
  @MainActor func failedScopeClearsRows() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("dx10-scope-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let value = try DrawingEditFixture.value()
    _ = try await library.retain(value, reason: "navigation")
    let sketches = PortraitSketchCollection(library: library)
    await sketches.load()
    #expect(!sketches.entries.isEmpty)
    let missing = PhotoRef(issuer: UUID(), revision: UUID(), digest: .hash(Data("missing".utf8)))
    await sketches.load(scope: .photo(missing))
    #expect(sketches.entries.isEmpty && !sketches.hasMore && sketches.error != nil)
    try await sketches.loadMore()
    #expect(sketches.entries.isEmpty)
    await sketches.shutdown(); await library.closeLibrary()
  }

  @Test("A selected Photo asset failure never pairs B identity with A pixels or reports successful Studio opening")
  @MainActor func failedSourceLoadClearsPixels() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("dx10-source-load-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let model = FlowAuthoringModel(directory: root, library: library, purpose: .validationFixture)
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(1), title: "A")
    let a = try #require(model.currentPhotoRef)
    #expect(model.sourceData != nil)
    let photo = try PortraitDrawingImages.photo(data: FlowAuthoringFixture.image(2), issuer: UUID(), captureID: UUID(), capturedAt: nil, importedAt: Date())
    try await library.commitRecords([], closure: .init(photo: photo))
    let object = root.appendingPathComponent("objects/sha256/" + photo.record.original.object.description)
    let original = try Data(contentsOf: object)
    try await library.removeAdoptedSourceAfterCommit(object)
    let failure = await model.selectPhoto(photo.reference)
    await library.clearAdoptionFault()
    #expect(failure != nil && model.error != nil)
    #expect(model.currentPhotoRef != a)
    #expect(model.sourceData == nil && model.program == nil)
    try original.write(to: object)
    _ = await model.shutdown(); await library.closeLibrary()
  }

  @Test("Unknown Photo semantics remain browsable and exportable while adoption refuses")
  func opaqueUnavailable() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("dx10-opaque-adoption-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("library"))
    let photo = try PortraitDrawingImages.photo(data: FlowAuthoringFixture.image(1), issuer: UUID(), captureID: UUID(), capturedAt: nil, importedAt: Date())
    var json = try #require(JSONSerialization.jsonObject(with: photo.record.originalJSON) as? [String: Any])
    json["requiredFeatures"] = ["example.unknown-photo/1"]
    let bytes = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes])
    let ref = PhotoRef(issuer: photo.reference.issuer, revision: photo.reference.revision, digest: .hash(bytes))
    try await library.commitRecords([], assets: photo.assets.map { .init(descriptor: $0.descriptor, bytes: $0.bytes) },
      closure: .init(records: [.init(reference: .photo(ref), originalJSON: bytes)]))
    let store = FlowPortfolioStore(directory: library.directoryURL, library: library)
    try await store.loadRecords()
    await #expect(throws: (any Error).self) { try await store.adoptExistingPhoto(ref) }
    #expect(await store.snapshot().sources.isEmpty)
    let entries = try await library.photos().entries
    #expect(entries.first?.reference == ref && entries.first?.unsupportedReasons.isEmpty == false)
    let destination = root.appendingPathComponent("export")
    try await library.exportPhoto(ref, to: destination)
    let path = "data/photos/" + ref.issuer.uuidString.lowercased() + "/" + ref.revision.uuidString.lowercased() + "/photo.json"
    #expect(try Data(contentsOf: destination.appendingPathComponent(path)) == bytes)
    await library.closeLibrary()
  }

  @Test("Raw sources stay browsable without being silently normalized into a new authoring Photo")
  func rawUnavailable() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("dx10-raw-adoption-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let image = try DrawingImageAsset.gray8(Data([0, 64, 128, 255]), width: 2, height: 2)
    let photo = try DrawingImageRecords.photo(identity: .init(issuer: UUID()), original: image, width: 2, height: 2,
      acquired: .unknown(provenance: "Synthetic unknown acquisition"), imported: .unknown(provenance: "Synthetic unknown import"))
    try await library.commitRecords([], closure: .init(photo: photo))
    let store = FlowPortfolioStore(directory: root, library: library)
    try await store.loadRecords()
    await #expect(throws: (any Error).self) { try await store.adoptExistingPhoto(photo.reference) }
    #expect(await store.snapshot().sources.isEmpty)
    #expect(try await library.photos().entries.map(\.reference) == [photo.reference])
    #expect(try await library.photo(photo.reference).record.originalJSON == photo.record.originalJSON)
    await library.closeLibrary()
  }
}
