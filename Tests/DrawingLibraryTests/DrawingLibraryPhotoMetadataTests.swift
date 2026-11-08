import Foundation
import DrawingLibrary
import PortraitCore
import Testing

private enum PhotoMetadataFailure: Error { case boundary }
extension DrawingLibrary {
  func photoMetadataFault(_ boundary: LibraryExchangeCatalogBoundary?) throws {
    guard let boundary else { cachedExchangeCatalog?.injectFault = nil; return }
    let catalog = try commonCatalog()
    catalog.injectFault = { if $0 == boundary { throw PhotoMetadataFailure.boundary } }
  }
}

@Suite("DX07 attributed neutral photo metadata", .serialized)
struct DrawingLibraryPhotoMetadataTests {
  private func metadata(_ library: DrawingLibrary, _ ref: PhotoRef) async throws -> DrawingLibraryPhotoMetadata {
    try await library.photoMetadata(ref)
  }

  @Test("Photo patches distinguish unchanged from clear and retry cannot overwrite a later edit")
  func fieldIntentAndRetry() async throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryPhotoFixture()
    let library = DrawingLibrary(directoryURL: root)
    try await fixture.publish(to: library)
    let ref = fixture.photo.reference
    try await library.updatePhotoMetadata(ref, patch: .init(title: .set("First"), subjectID: .set("subject"), sessionID: .set("session")))
    let intent = DrawingLibraryCommitIntent()
    let patch = DrawingLibraryPhotoMetadataPatch(title: .set(nil), excluded: true)
    try await library.updatePhotoMetadata(ref, patch: patch, intent: intent)
    #expect(try await metadata(library, ref) == .init(title: nil, subjectID: "subject", sessionID: "session", excluded: true))
    try await library.updatePhotoMetadata(ref, patch: .init(title: .set("Later"), subjectID: .set(nil), excluded: false))
    let later = try await metadata(library, ref)
    try await library.updatePhotoMetadata(ref, patch: patch, intent: intent)
    #expect(try await metadata(library, ref) == later)
    await #expect(throws: (any Error).self) {
      try await library.updatePhotoMetadata(ref, patch: .init(title: .set("changed request")), intent: intent)
    }
    #expect(try await library.photo(ref).record.originalJSON == fixture.photo.record.originalJSON)
    await library.closeLibrary()
    let reopened = DrawingLibrary(directoryURL: root)
    #expect(try await metadata(reopened, ref) == later)
    await reopened.closeLibrary()
  }

  @Test("Photo metadata and domain selection publish atomically and recover the exact captured operation", arguments: [LibraryExchangeCatalogBoundary.beforeSQLCommit, .afterSQLCommit])
  func atomicDomainPatch(boundary: LibraryExchangeCatalogBoundary) async throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryPhotoFixture()
    let library = DrawingLibrary(directoryURL: root)
    try await fixture.publish(to: library)
    let ref = fixture.photo.reference
    let intent = DrawingLibraryCommitIntent()
    let row = DrawingLibraryRecord(kind: "example.dx07-selection/1", id: UUID(), payload: Data("{\"selection\":1}".utf8), photos: [ref])
    let updates = [DrawingLibraryPhotoMetadataUpdate(reference: ref, patch: .init(title: .set("Atomic"), subjectID: .set("declared"), excluded: true))]
    try await library.photoMetadataFault(boundary)
    await #expect(throws: PhotoMetadataFailure.self) {
      try await library.commitRecords([row], intent: intent, photoMetadata: updates)
    }
    let visible = boundary == .afterSQLCommit
    #expect((try await library.record(row.key) != nil) == visible)
    #expect(try await metadata(library, ref).title == (visible ? "Atomic" : nil))
    try await library.photoMetadataFault(nil)
    try await library.recover()
    #expect(try await library.record(row.key)?.payload == row.payload)
    #expect(try await metadata(library, ref) == .init(title: "Atomic", subjectID: "declared", excluded: true))
    try await library.updatePhotoMetadata(ref, patch: .init(title: .set("Newer title")))
    let updatedRow = DrawingLibraryRecord(kind: row.kind, id: row.id, payload: Data("{\"selection\":2}".utf8), photos: [ref])
    try await library.commitRecords([updatedRow])
    try await library.commitRecords([row], intent: intent, photoMetadata: updates)
    #expect(try await library.record(row.key)?.payload == updatedRow.payload)
    #expect(try await metadata(library, ref).title == "Newer title")
    await library.closeLibrary()
    let reopened = DrawingLibrary(directoryURL: root)
    #expect(try await metadata(reopened, ref).title == "Newer title")
    #expect(try await reopened.record(row.key)?.payload == updatedRow.payload)
    await reopened.closeLibrary()
  }

  @Test("Photo metadata revision ignores unrelated graph commits and advances once per captured edit")
  func metadataRevisionScope() async throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryPhotoFixture()
    let library = DrawingLibrary(directoryURL: root)
    try await fixture.publish(to: library)
    let before = try await library.photoMetadataRevision()
    let row = DrawingLibraryRecord(kind: "example.unrelated/1", id: UUID(), payload: Data("{}".utf8))
    try await library.commitRecords([row])
    #expect(try await library.photoMetadataRevision() == before)
    let intent = DrawingLibraryCommitIntent()
    let patch = DrawingLibraryPhotoMetadataPatch(title: .set("Changed once"))
    try await library.updatePhotoMetadata(fixture.photo.reference, patch: patch, intent: intent)
    let after = try await library.photoMetadataRevision()
    #expect(after > before)
    try await library.updatePhotoMetadata(fixture.photo.reference, patch: patch, intent: intent)
    #expect(try await library.photoMetadataRevision() == after)
    #expect(try await library.photoMetadata([fixture.photo.reference])[fixture.photo.reference]?.title == "Changed once")
    await library.closeLibrary()
  }

  @Test("Metadata updates need no artwork and refuse a same-identity wrong digest")
  func metadataWithoutArtwork() async throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryPhotoFixture()
    let library = DrawingLibrary(directoryURL: root)
    try await fixture.publish(to: library)
    let held = root.appendingPathComponent("held")
    try FileManager.default.createDirectory(at: held, withIntermediateDirectories: true)
    let digests = Set(fixture.input.assets.map { $0.descriptor.asset.object })
    for digest in digests {
      try FileManager.default.moveItem(at: root.appendingPathComponent("objects/sha256/" + digest.description), to: held.appendingPathComponent(digest.description))
    }
    try await library.updatePhotoMetadata(fixture.photo.reference, patch: .init(title: .set("Metadata only")))
    #expect(try await metadata(library, fixture.photo.reference).title == "Metadata only")
    let wrong = PhotoRef(issuer: fixture.photo.reference.issuer, revision: fixture.photo.reference.revision, digest: .hash(Data("divergent Photo digest".utf8)))
    await #expect(throws: (any Error).self) { try await library.updatePhotoMetadata(wrong, patch: .init(title: .set("Wrong"))) }
    #expect(try await metadata(library, fixture.photo.reference).title == "Metadata only")
    await #expect(throws: (any Error).self) { try await library.photoMetadata([fixture.photo.reference, wrong]) }
    let missing = PhotoRef(issuer: UUID(), revision: UUID(), digest: fixture.photo.reference.digest)
    await #expect(throws: (any Error).self) { try await library.photoMetadata(missing) }
    await #expect(throws: (any Error).self) { try await library.photoMetadata([fixture.photo.reference, missing]) }
    #expect(try await library.photoMetadata([fixture.photo.reference])[fixture.photo.reference]?.title == "Metadata only")
    for digest in digests {
      try FileManager.default.moveItem(at: held.appendingPathComponent(digest.description), to: root.appendingPathComponent("objects/sha256/" + digest.description))
    }
    await library.closeLibrary()
  }
}
