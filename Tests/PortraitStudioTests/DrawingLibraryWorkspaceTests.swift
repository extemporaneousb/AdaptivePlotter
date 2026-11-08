import Foundation
import DrawingLibrary
import PortraitCore
import PortraitLibrary
import PortraitStudioUI
import SwiftUI
import Testing

@Suite("DX10 exact workspace restoration", .serialized)
@MainActor
struct DrawingLibraryWorkspaceTests {
  @Test("Missing restored branch parent clears a preceding populated page and its Load More cursor")
  func missingBranchClearsBrowsePage() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let value = try DrawingEditFixture.value()
    var prepared: [DrawingLibraryPreparedRetention] = []
    for _ in 0..<101 { prepared.append(try await library.prepareRetention(value, reason: "save")) }
    let retained = try await library.commitRetentions(prepared)
    let sketches = PortraitSketchCollection(library: library)
    let browser = DrawingLibraryBrowserModel(sketches: sketches)
    await sketches.load(scope: .all)
    #expect(sketches.entries.count == 100 && sketches.hasMore)
    let selected = try #require(retained.first?.reference)
    await browser.select(selected).value
    var route = DrawingLibraryRoute(); route.collection = .children
    route.branchParent = .init(issuer: UUID(), revision: UUID(), digest: .hash(Data("missing parent".utf8)))
    let oldRows = sketches.entries.map(\.reference)
    let closed = DrawingLibraryBrowserModel(sketches: sketches); closed.close()
    await closed.restore(route)
    await browser.restore(route, isStillCurrent: { false })
    let cancelled = Task { await browser.restore(route) }; cancelled.cancel(); await cancelled.value
    #expect(sketches.selected?.reference == selected)
    #expect(sketches.entries.map(\.reference) == oldRows && sketches.hasMore)
    #expect(browser.error == nil && !browser.isBusy)
    await browser.restore(route)
    #expect(browser.error != nil && sketches.selected == nil)
    #expect(sketches.entries.isEmpty && !sketches.hasMore && !sketches.isLoading)
    try await sketches.loadMore()
    #expect(sketches.entries.isEmpty && !sketches.hasMore)
    browser.close(); await sketches.shutdown(); await library.closeLibrary()
  }
  @Test("Global source-free Drawing edits reopen and export without an old Photo scope")
  func sourceFreeReopen() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let retained = try await library.retain(DrawingEditFixture.value(), reason: "save")
    let sketches = PortraitSketchCollection(library: library)
    let browser = DrawingLibraryBrowserModel(sketches: sketches)
    var route = DrawingLibraryRoute(); route.collection = .drawings; route.drawing = retained.reference
    // This stale context must not select a Photos scope during a global reopen.
    let missingPhoto = PhotoRef(issuer: UUID(), revision: UUID(), digest: .hash(Data("unavailable old Photo".utf8)))
    route.photo = missingPhoto
    await browser.restore(DrawingLibraryRoute.restored(route.encoded))
    #expect(browser.error == nil && sketches.selected?.reference == retained.reference)
    #expect(sketches.scope == .all)
    let editor = try #require(browser.beginEdit()); await editor.load()
    editor.remove([try #require(editor.base.program.strokes.first?.id)])
    #expect(await editor.save()); #expect(browser.finishEdit(editor))
    let child = try #require(sketches.selected?.reference)
    await browser.select(retained.reference).value
    route.collection = .children; route.branchParent = retained.reference
    route.photo = nil; route.input = nil; route.drawing = nil
    await browser.restore(route)
    #expect(browser.error == nil && sketches.selected == nil)
    #expect(sketches.entries.map(\.reference) == [child])
    route.drawing = child
    await browser.restore(route)
    #expect(browser.error == nil && sketches.selected?.reference == child)
    let branchEditor = try #require(browser.beginEdit()); await branchEditor.load()
    branchEditor.remove([try #require(branchEditor.base.program.strokes.first?.id)])
    #expect(await branchEditor.save()); #expect(browser.finishEdit(branchEditor))
    let grandchild = try #require(sketches.selected?.reference)
    #expect(sketches.selected?.parent == .present(child))
    // The inline completion uses this same typed normalization after finishEdit.
    route.showDrawing(grandchild)
    #expect(route.activeCollection == .drawings && route.branchParent == nil && route.photo == nil && route.input == nil)
    browser.close()
    let reopened = DrawingLibraryBrowserModel(sketches: sketches)
    await reopened.restore(DrawingLibraryRoute.restored(route.encoded))
    #expect(reopened.error == nil && sketches.selected?.reference == grandchild)
    let exported = root.appendingPathComponent("Drawing.zip")
    await reopened.exportDrawing(grandchild, to: exported)
    #expect(reopened.error == nil && FileManager.default.fileExists(atPath: exported.path))
    // The same Drawing cannot be admitted into an unrelated Photos bookmark.
    route.collection = .photos; route.photo = missingPhoto
    await reopened.restore(route)
    #expect(reopened.error != nil && sketches.selected == nil)
    reopened.close(); await sketches.shutdown(); await library.closeLibrary()
  }
  @Test("Photo/Input ancestry and imported Drawings preserve exact current route intent")
  func wrongPhotoInput() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let raster = try DrawingImageAsset.gray8(Data([0, 64, 128, 255]), width: 2, height: 2)
    func photo() throws -> FrozenPhotoRecord {
      try DrawingImageRecords.photo(identity: .init(issuer: UUID()), original: raster, width: 2, height: 2,
        acquired: .unknown(provenance: "fixture"), imported: .unknown(provenance: "fixture"))
    }
    let first = try photo(), second = try photo()
    let transform = try ExchangeTransform([1,0,0,0,1,0,0,0,1])
    let prepared = try DrawingImageRecords.input(identity: .init(issuer: UUID()), photo: second, raster: raster,
      width: 2, height: 2, orientation: "up", sourceToInput: transform, inputToField: transform,
      mask: .none, operations: [.init(kind: "identity", parametersJSON: Data("{}".utf8))],
      preparation: .init(id: "example.dx10.workspace", version: "1", recordJSON: Data("{}".utf8)))
    try await library.commitRecords([], closure: .init(photo: first))
    try await library.commitRecords([], closure: .init(input: prepared))
    let repairedInput = try DrawingImageRecords.input(identity: .init(issuer: UUID()), photo: first, raster: raster,
      width: 2, height: 2, orientation: "up", sourceToInput: transform, inputToField: transform,
      mask: .none, operations: [.init(kind: "identity", parametersJSON: Data("{}".utf8))],
      preparation: .init(id: "example.dx10.workspace", version: "1", recordJSON: Data("{}".utf8)))
    let base = try DrawingEditFixture.value()
    let associated = try Drawing(program: base.program, input: .present(repairedInput.reference), parent: .none, producer: base.producer)
    let associatedRef = try await library.retain(associated, reason: "save", closure: .init(input: repairedInput)).reference
    let sketches = PortraitSketchCollection(library: library)
    let browser = DrawingLibraryBrowserModel(sketches: sketches)
    var route = DrawingLibraryRoute(); route.photo = first.reference; route.input = prepared.reference
    await #expect(throws: DrawingExchangeError.mismatchedParent) { try await route.validatedScope(in: library) }
    await browser.restore(route)
    #expect(browser.error != nil && sketches.entries.isEmpty && sketches.selected == nil)
    // Repair the Input while keeping the same Photo: no stale UI scope mask may
    // prevent the actual repaired page and exact Drawing from becoming usable.
    route.input = repairedInput.reference; route.drawing = nil
    await browser.restore(route)
    #expect(browser.error == nil && sketches.entries.map(\.reference) == [associatedRef] && sketches.selected == nil)
    await browser.select(associatedRef).value; route.drawing = associatedRef
    #expect(sketches.selected?.reference == associatedRef)
    route.photo = second.reference
    route.input = prepared.reference; route.drawing = nil
    #expect(try await route.validatedScope(in: library) == .input(prepared.reference))
    let source = DrawingLibrary(directoryURL: root.appendingPathComponent("import-source"))
    let imported = try await source.retain(DrawingEditFixture.value(), reason: "save")
    let carrier = root.appendingPathComponent("Import.zip")
    try await source.exportDrawing(imported.reference, to: carrier)
    await source.closeLibrary()
    let newer = try await library.retain(DrawingEditFixture.value(), reason: "save")
    let newerDrawing = try await library.drawing(newer.reference)
    route.collection = .photos; route.photo = first.reference; route.input = nil; route.drawing = nil
    await browser.restore(route)
    #expect(browser.error == nil && sketches.selected == nil)
    let navigation = Binding(get: { route }, set: { route = $0 })
    let gate = DrawingEditCommitGate(); defer { gate.release() }
    try await library.editGate(gate)
    let pendingImport = Task { await browser.importDrawings(from: carrier, route: navigation) }
    try #require(await gate.waitUntilHeld())
    // A new exact intent supersedes the import while its actor commit is held.
    route.showDrawing(newer.reference)
    try sketches.selectLoaded(newerDrawing)
    let superseding = route
    gate.release(); await pendingImport.value
    try await library.editFault(nil)
    #expect(route == superseding && sketches.selected?.reference == newer.reference)
    route.collection = .photos; route.photo = first.reference; route.input = nil; route.branchParent = nil; route.drawing = nil
    await browser.restore(route)
    await browser.importDrawings(from: carrier, route: navigation)
    #expect(browser.error == nil && route.activeCollection == .drawings)
    #expect(route.photo == nil && route.input == nil && route.branchParent == nil && route.drawing == imported.reference)
    #expect(sketches.selected?.reference == imported.reference && sketches.scope == .all)
    let committedRoute = route
    await browser.importDrawings(from: root.appendingPathComponent("missing.zip"), route: navigation)
    #expect(browser.error != nil && route == committedRoute && sketches.selected?.reference == imported.reference)
    let cancelledImport = Task { await browser.importDrawings(from: carrier, route: navigation) }
    cancelledImport.cancel(); await cancelledImport.value
    #expect(route == committedRoute && sketches.selected?.reference == imported.reference)
    let reopened = DrawingLibraryBrowserModel(sketches: sketches)
    await reopened.restore(DrawingLibraryRoute.restored(route.encoded))
    #expect(reopened.error == nil && sketches.selected?.reference == imported.reference)
    reopened.close(); browser.close(); await sketches.shutdown()
    await library.closeLibrary()
  }
  @Test("Workspace bookmarks preserve the complete Photo, Input and Drawing occurrence")
  func exactBookmarks() throws {
    let issuer = UUID(), revision = UUID()
    var route = DrawingLibraryRoute()
    route.workspace = .drawingStudio
    route.photo = PhotoRef(issuer: issuer, revision: revision, digest: .hash(Data("photo".utf8)))
    route.input = ImageInputRef(issuer: issuer, revision: revision, digest: .hash(Data("input".utf8)))
    route.drawing = DrawingRef(issuer: issuer, revision: revision, digest: .hash(Data("drawing".utf8)))
    #expect(DrawingLibraryRoute.restored(route.encoded) == route)
    var conflict = route
    conflict.drawing = DrawingRef(issuer: issuer, revision: revision, digest: .hash(Data("different".utf8)))
    #expect(DrawingLibraryRoute.restored(conflict.encoded) != route)
    #expect(DrawingLibraryRoute.restored(Data("invalid".utf8)).drawing == nil)
    route.collection = .photos; route.branchParent = route.drawing
    let samePhoto = route
    let sameReference = route.photo
    let changedSamePhoto = route.selectPhoto(sameReference)
    #expect(!changedSamePhoto)
    #expect(route == samePhoto)
    let nextPhoto = PhotoRef(issuer: issuer, revision: UUID(), digest: .hash(Data("next photo".utf8)))
    let changedPhoto = route.selectPhoto(nextPhoto)
    #expect(changedPhoto)
    #expect(route.workspace == .drawingStudio && route.activeCollection == .photos && route.photo == nextPhoto)
    #expect(route.input == nil && route.drawing == nil && route.branchParent == nil)
  }

  @Test("A missing exact occurrence clears the old preview and never reattaches equal geometry")
  func missingSelectionDoesNotKeepPriorPreview() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let retained = try await library.retain(DrawingEditFixture.value(), reason: "save")
    let sketches = PortraitSketchCollection(library: library)
    let browser = DrawingLibraryBrowserModel(sketches: sketches)
    await browser.select(retained.reference).value
    let wrong = DrawingRef(issuer: retained.reference.issuer, revision: retained.reference.revision,
      digest: .hash(Data("wrong digest".utf8)))
    await browser.select(wrong).value
    #expect(sketches.selected == nil)
    #expect(browser.error != nil)
    #expect(browser.beginEdit() == nil)
    #expect(browser.makeHandoffRequest() == nil)
    browser.close(); await sketches.shutdown(); await library.closeLibrary()
  }
}
