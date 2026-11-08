import Foundation
import DrawingLibrary
import PortraitCore
import Testing

@Suite("DX07 reversible Drawing retention metadata", .serialized)
struct DrawingLibraryRetentionMetadataTests {
  @Test("Clearing, reapplying, hiding and restoring Drawing metadata never deletes immutable source assets")
  func reasonsAndRestore() async throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryPhotoFixture()
    let library = DrawingLibrary(directoryURL: root)
    let ref = try await library.retain(fixture.drawing(), title: "Kept title", reason: "save", closure: .init(input: fixture.input)).reference
    let original = try await library.drawing(ref)
    let objects = root.appendingPathComponent("objects/sha256")
    let bytes = try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: objects, includingPropertiesForKeys: nil).map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    try await library.setRetentionReason(ref, reason: "plot", retained: true)
    #expect(Set(try await library.retention(ref).reasons) == Set(["save", "plot"]))
    try await library.setRetentionReason(ref, reason: "save", retained: false)
    try await library.setRetentionReason(ref, reason: "plot", retained: false)
    #expect(try await library.retention(ref).reasons.isEmpty)
    #expect(try await library.drawing(ref).program == original.program)
    try await library.setRetentionReason(ref, reason: "save", retained: true)
    try await library.delete(ref)
    #expect(try await library.retention(ref).tombstoned)
    #expect(try await library.drawings().entries.isEmpty)
    await #expect(throws: (any Error).self) { try await library.drawing(ref) }
    try await library.restore(ref)
    let state = try await library.retention(ref)
    #expect(state.reference == ref && !state.tombstoned && state.reasons == ["save"])
    #expect(try await library.drawings().entries.first?.title == "Kept title")
    #expect(try await library.drawing(ref).program == original.program)
    for (digest, data) in bytes { #expect(try Data(contentsOf: objects.appendingPathComponent(digest)) == data) }
    await library.closeLibrary()
    let reopened = DrawingLibrary(directoryURL: root)
    #expect(try await reopened.retention(ref).reasons == ["save"])
    #expect(try await reopened.drawing(ref).reference == ref)
    await reopened.closeLibrary()
  }

  @Test("Committed reason and restore retries cannot undo intervening operator edits")
  func staleMutationRetry() async throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryPhotoFixture()
    let library = DrawingLibrary(directoryURL: root)
    let ref = try await library.retain(fixture.drawing(), reason: "save", closure: .init(input: fixture.input)).reference
    let reasonIntent = DrawingLibraryCommitIntent()
    try await library.setRetentionReason(ref, reason: "chosen", retained: true, intent: reasonIntent)
    try await library.setRetentionReason(ref, reason: "chosen", retained: false)
    try await library.setRetentionReason(ref, reason: "chosen", retained: true, intent: reasonIntent)
    #expect(try await library.retention(ref).reasons == ["save"])
    await #expect(throws: (any Error).self) { try await library.setRetentionReason(ref, reason: "different", retained: true, intent: reasonIntent) }
    try await library.delete(ref)
    let restoreIntent = DrawingLibraryCommitIntent()
    try await library.restore(ref, intent: restoreIntent)
    try await library.delete(ref)
    try await library.restore(ref, intent: restoreIntent)
    #expect(try await library.retention(ref).tombstoned)
    try await library.restore(ref)
    #expect(try await library.drawing(ref).reference == ref)
    await library.closeLibrary()
  }

  @Test("Uncertain reason mutation recovers once and preserves later reason edits")
  func uncertainReason() async throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryPhotoFixture()
    let library = DrawingLibrary(directoryURL: root)
    let ref = try await library.retain(fixture.drawing(), reason: "save", closure: .init(input: fixture.input)).reference
    let intent = DrawingLibraryCommitIntent()
    try await library.photoMetadataFault(.afterSQLCommit)
    await #expect(throws: (any Error).self) { try await library.setRetentionReason(ref, reason: "plot", retained: true, intent: intent) }
    try await library.photoMetadataFault(nil)
    try await library.recover()
    #expect(Set(try await library.retention(ref).reasons) == Set(["save", "plot"]))
    try await library.setRetentionReason(ref, reason: "plot", retained: false)
    try await library.setRetentionReason(ref, reason: "plot", retained: true, intent: intent)
    #expect(try await library.retention(ref).reasons == ["save"])
    await library.closeLibrary()
  }
}
