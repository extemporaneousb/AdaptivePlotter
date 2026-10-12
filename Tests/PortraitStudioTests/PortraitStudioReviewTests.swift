import Foundation
import PlotterModel
import PortraitCore
import PortraitLibrary
import Testing
@testable import PortraitStudio

@Suite("Standalone immutable review", .serialized)
@MainActor
struct PortraitStudioReviewTests {
  @Test("Imported results reopen exact randomized sides and record only explicit human dimensions")
  func reviewReopenAndExplicitLabels() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PortraitCandidateStore(directoryURL: root.appendingPathComponent("library"))
    let capture = UUID(), producer = UUID()
    let first = try await store.importDrawingPackage(DrawingPackageCodec.encode(
      Self.package(captureID: capture, libraryID: producer, resultID: "first", shape: .square)), restoreDeleted: true)
    let second = try await store.importDrawingPackage(DrawingPackageCodec.encode(
      Self.package(captureID: capture, libraryID: producer, resultID: "second", shape: .triangle)), restoreDeleted: true)
    let model = PortraitStudioReviewModel(store: store)
    model.chooseFirst(first)
    await model.compare(with: second, presentationSeed: 42)
    #expect(model.error == nil)
    let comparison = try #require(model.comparison)
    #expect(comparison.originalVisible)
    #expect(Set([comparison.a.origin, comparison.b.origin]) == Set([first.transferOrigin!, second.transferOrigin!]))
    #expect(model.a?.source.bytes == model.b?.source.bytes)
    #expect(model.displayA?.sha256 == comparison.a.displayPreviewSHA256)
    #expect(model.displayB?.sha256 == comparison.b.displayPreviewSHA256)
    #expect(model.label == nil)
    await model.rate(.tie, dimension: .overall)
    #expect(model.label?.choices == [.overall: .tie])
    #expect(model.label?.reviewerID == nil)
    let firstRevision = try #require(model.label?.id)
    model.reviewerID = "fixture-reviewer"
    await model.rate(.b, dimension: .structure)
    #expect(model.label?.supersedes == firstRevision)
    #expect(model.label?.choices == [.overall: .tie, .structure: .b])
    await model.rate(.skip, dimension: .overall)
    #expect(model.label?.choices == [.overall: .skip])
    await model.rate(.a, dimension: .overall)
    #expect(model.label?.choices == [.overall: .a])
    await model.shutdown()

    let reopened = PortraitStudioReviewModel(store: store)
    await reopened.reload()
    #expect(reopened.comparisons.map(\.id) == [comparison.id])
    await reopened.select(comparison.id)
    #expect(reopened.comparison == comparison)
    #expect(reopened.a?.origin == comparison.a.origin)
    #expect(reopened.b?.origin == comparison.b.origin)
    #expect(reopened.label?.choices == [.overall: .a])
    try await reopened.exportDataset(to: root.appendingPathComponent("export"))
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("export/manifest.json").path))
    await reopened.shutdown()
  }

  @Test("Unknown groups remain absent until an explicit declaration and split are saved")
  func humanGroupDeclaration() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PortraitCandidateStore(directoryURL: root)
    let drawing = try await store.importDrawingPackage(DrawingPackageCodec.encode(Self.package()), restoreDeleted: true)
    let model = PortraitStudioReviewModel(store: store)
    await model.loadGroups(for: drawing)
    #expect(model.groupDeclaration == nil)
    #expect(model.subjectID.isEmpty && model.photoSessionID.isEmpty)
    #expect(model.groupSplit == .unassigned)
    #expect(!model.canDeclareGroups)
    model.subjectID = "person-1"
    model.photoSessionID = "session-1"
    model.groupProvenance = "Explicit fixture declaration"
    model.groupSplit = .test
    #expect(model.canDeclareGroups)
    await model.declareGroups()
    #expect(model.error == nil)
    #expect(model.groupDeclaration?.groups.subjectID == "person-1")
    #expect(model.groupDeclaration?.groups.photoSessionID == "session-1")
    #expect(model.groupDeclaration?.split == .test)
    #expect(!model.canDeclareGroups)
    await model.shutdown()
  }

  private static func package(captureID: UUID = UUID(), libraryID: UUID = UUID(),
    resultID: String = "fixture", shape: DrawingCatalogEntryID = .square) throws -> DrawingPackage {
    let style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID(UUID()))
    let base = try DrawingProgramCatalog.program(for: shape, style: style)
    let program = try DrawingProgram(id: base.id, fieldExtent: base.fieldExtent, strokes: base.strokes,
      source: .init(kind: "portrait", sourceIdentifier: "review-fixture-v1"))
    let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aY9sAAAAASUVORK5CYII=")!
    let image = DrawingPackageAsset(mediaType: "image/png", bytes: bytes, pixelWidth: 1, pixelHeight: 1)
    let record = Data("{\"fixture\":\"\(resultID)\"}".utf8)
    return try DrawingPackage(origin: .init(libraryID: libraryID, captureID: captureID,
      resultID: resultID, resultRecordSHA256: DrawingPackageCodec.sha256(record), programHash: program.contentHash),
      program: program, createdAt: Date(), title: resultID, resultRecordJSON: record,
      source: image, artistInput: image,
      artist: .init(identifier: "fixture", revision: "1", settingsJSON: Data("{}".utf8)), preview: image)
  }
}
