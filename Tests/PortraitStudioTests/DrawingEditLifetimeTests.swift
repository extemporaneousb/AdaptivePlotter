import Foundation
import DrawingLibrary
import PortraitCore
import PortraitLibrary
import PortraitStudioUI
import Testing

@Suite("DX08 editor transaction and lifetime", .serialized)
@MainActor
struct DrawingEditLifetimeTests {
  @Test("Opening, modifying and cancelling a temporary draft writes nothing")
  func cancelIsWriteFree() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let sketches = PortraitSketchCollection(library: library)
    let base = try DrawingEditFixture.value()
    sketches.selectTemporary(base)
    let editor = PortraitLineEditModel(base: base, sketches: sketches)
    await editor.load()
    editor.remove([try #require(base.program.strokes.first).id])
    #expect(editor.hasUnsavedChanges)
    editor.close()
    #expect(editor.isClosed && editor.savedDrawing == nil)
    #expect(!FileManager.default.fileExists(atPath: root.path))
    #expect(await editor.save() == false)
    #expect(!FileManager.default.fileExists(atPath: root.path))
    await sketches.shutdown(); await library.closeLibrary()
  }

  @Test("Explicit unchanged completion retains the base once and never invents a membership child")
  func unchangedCompletion() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let sketches = PortraitSketchCollection(library: library)
    let base = try DrawingEditFixture.value()
    sketches.selectTemporary(base)
    let first = PortraitLineEditModel(base: base, sketches: sketches)
    await first.load(); #expect(first.canSave)
    #expect(await first.save())
    let saved = try #require(first.savedDrawing), ref = try #require(saved.reference)
    #expect(saved.parent == .none && saved.program == base.program)
    try sketches.selectLoaded(saved)
    let second = PortraitLineEditModel(base: saved, sketches: sketches)
    await second.load(); #expect(await second.save())
    #expect(second.savedDrawing?.reference == ref)
    #expect(try await library.drawings().entries.map(\.reference) == [ref])
    await sketches.shutdown(); await library.closeLibrary()
  }

  @Test("Editor retries the same failed atomic parent-child intent without duplicate revisions", arguments: [LibraryExchangeCatalogBoundary.beforeSQLCommit, .afterSQLCommit])
  func stableIntentRetry(boundary: LibraryExchangeCatalogBoundary) async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root); try await library.open()
    let sketches = PortraitSketchCollection(library: library)
    let base = try DrawingEditFixture.value()
    sketches.selectTemporary(base)
    let editor = PortraitLineEditModel(base: base, sketches: sketches)
    await editor.load(); editor.remove([try #require(base.program.strokes.first).id])
    try await library.editFault(boundary)
    #expect(await editor.save() == false)
    #expect(editor.savedDrawing == nil)
    #expect(try await library.drawings().entries.count == (boundary == .beforeSQLCommit ? 0 : 2))
    try await library.editFault(nil)
    try await library.recover()
    let recovered = try await library.drawings().entries.map(\.reference)
    #expect(recovered.count == 2)
    #expect(await editor.save())
    let child = try #require(editor.savedDrawing)
    #expect(recovered.contains(try #require(child.reference)))
    #expect(Set(try await library.drawings().entries.map(\.reference)) == Set(recovered))
    #expect(child.program.strokes == base.program.strokes.dropFirst().map { $0 })
    #expect(await editor.save())
    #expect(Set(try await library.drawings().entries.map(\.reference)) == Set(recovered))
    await sketches.shutdown(); await library.closeLibrary()
  }

  @Test("Cancelled or superseded failed edit intents release temporary ownership before another save", arguments: ["cancel", "change"])
  func failedDraftCleanup(mode: String) async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root); try await library.open()
    let sketches = PortraitSketchCollection(library: library)
    let base = try DrawingEditFixture.value(); sketches.selectTemporary(base)
    let ids = base.program.strokes.map(\.id)
    let editor = PortraitLineEditModel(base: base, sketches: sketches)
    await editor.load(); editor.remove([ids[0]])
    try await library.editFault(.beforeSQLCommit)
    #expect(await editor.save() == false)
    let pending = await library.pendingEditResources()
    #expect(pending.count == 2 && !pending.roots.isEmpty)
    try await library.editFault(nil)
    if mode == "cancel" {
      editor.close()
      await sketches.shutdown()
      #expect(await library.pendingEditResources().count == 0)
      for url in pending.roots { #expect(!FileManager.default.fileExists(atPath: url.path)) }
      // Durable publication recovery remains the Common owner's responsibility.
      try await library.recover()
      let reopened = PortraitSketchCollection(library: library)
      reopened.selectTemporary(base)
      let next = PortraitLineEditModel(base: base, sketches: reopened)
      await next.load(); next.remove([ids[1]])
      #expect(await next.save())
      #expect(next.savedDrawing?.program.strokes == base.program.strokes.filter { $0.id != ids[1] })
      next.close(); await reopened.shutdown()
    } else {
      editor.remove([ids[1]])
      #expect(await editor.save())
      #expect(editor.savedDrawing?.program.strokes == [base.program.strokes[2]])
      editor.close(); await sketches.shutdown()
    }
    #expect(await library.pendingEditResources().count == 0)
    for url in pending.roots { #expect(!FileManager.default.fileExists(atPath: url.path)) }
    await library.closeLibrary()
  }

  @Test("Collection save uses stable intent and never changes the current selection")
  func collectionSaveAuthority() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let sketches = PortraitSketchCollection(library: library)
    let base = try DrawingEditFixture.value(), other = try DrawingEditFixture.value()
    sketches.selectTemporary(other)
    let selection = sketches.selectionID, epoch = sketches.selectionEpoch
    let parentIntent = UUID(), editIntent = UUID()
    let kept = Array(base.program.strokes.dropFirst().map(\.id))
    let saved = try await sketches.saveStrokeEdit(base: base, keptStrokeIDs: kept, parentIntentID: parentIntent, editIntentID: editIntent)
    let retried = try await sketches.saveStrokeEdit(base: base, keptStrokeIDs: kept, parentIntentID: parentIntent, editIntentID: editIntent)
    #expect(saved.reference == retried.reference)
    #expect(saved.program.strokes == Array(base.program.strokes.dropFirst()))
    #expect(sketches.selectionID == selection && sketches.selectionEpoch == epoch && sketches.selected?.program == other.program)
    #expect(try await library.drawings().entries.count == 2)
    await #expect(throws: (any Error).self) {
      try await sketches.saveStrokeEdit(base: base, keptStrokeIDs: [base.program.strokes[0].id], parentIntentID: parentIntent, editIntentID: editIntent)
    }
    #expect(try await library.drawings().entries.count == 2)
    await sketches.shutdown(); await library.closeLibrary()
  }

  @Test("A held save cannot replace a dismissed or same-geometry switched selection", arguments: ["dismiss", "switch"])
  func staleSaveCompletion(mode: String) async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let value = try DrawingEditFixture.value()
    let a = try await library.retain(value, reason: "first"), b = try await library.retain(value, reason: "second")
    let first = try await library.drawing(a.reference), second = try await library.drawing(b.reference)
    #expect(first.program == second.program && first.reference != second.reference)
    let sketches = PortraitSketchCollection(library: library)
    try sketches.selectLoaded(first)
    let editor = PortraitLineEditModel(base: first, sketches: sketches)
    await editor.load(); editor.remove([try #require(first.program.strokes.first).id])
    let gate = DrawingEditCommitGate(); try await library.editGate(gate)
    let saving = Task { await editor.save() }
    defer { gate.release() }
    #expect(await gate.waitUntilHeld())
    if mode == "dismiss" { editor.close() } else { try sketches.selectLoaded(second) }
    let expected = mode == "dismiss" ? a.reference : b.reference
    gate.release(); _ = await saving.value
    #expect(editor.savedDrawing == nil)
    #expect(sketches.selected?.reference == expected)
    let refs = try await library.drawings().entries.map(\.reference)
    #expect(refs.count == 3)
    var children: [Drawing] = []
    for ref in refs {
      let drawing = try await library.drawing(ref)
      if case .present = drawing.parent { children.append(drawing) }
    }
    #expect(children.count == 1 && children.first?.parent == .present(a.reference))
    #expect(children.first?.program.strokes == first.program.strokes.dropFirst().map { $0 })
    await sketches.shutdown(); await library.closeLibrary()
  }

  @Test("Collection shutdown drains admitted save and exact reload before closing its borrowed Library")
  func shutdownDrainsSave() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root); try await library.open()
    let sketches = PortraitSketchCollection(library: library)
    let base = try DrawingEditFixture.value(); sketches.selectTemporary(base)
    let editor = PortraitLineEditModel(base: base, sketches: sketches)
    await editor.load(); editor.remove([try #require(base.program.strokes.first).id])
    let gate = DrawingEditCommitGate(); try await library.editGate(gate)
    let saving = Task { await editor.save() }
    defer { gate.release() }
    #expect(await gate.waitUntilHeld())
    var didClose = false
    let closing = Task { await sketches.shutdown(); await library.closeLibrary(); didClose = true }
    while !sketches.isClosing { await Task.yield() }
    #expect(!didClose && !editor.canEdit)
    gate.release(); _ = await saving.value; await closing.value
    #expect(didClose && editor.savedDrawing == nil)
    let readonly = DrawingLibrary(directoryURL: root)
    #expect(try await readonly.drawings().entries.count == 2)
    await readonly.closeLibrary()
  }
}
