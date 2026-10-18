import AppKit
import Foundation
import PlotterModel
import PortraitArtists
import PortraitCore
import PortraitLibrary
import PortraitStudioUI
import Testing
import SwiftUI

@Suite("Flow Edge whole-line editing", .serialized)
@MainActor
struct PortraitLineEditTests {
  @Test("Picking chooses the closest visible polyline; lasso includes crossing segments, not just vertices")
  func geometry() throws {
    let program = try Self.program()
    let geometry = PortraitLineSelectionGeometry(program: program, size: .init(width: 420, height: 420))
    let a = geometry.lines[0], b = geometry.lines[2]
    let midpoint = CGPoint(x: (a.points[0].x+a.points[1].x)/2, y: a.points[0].y)
    #expect(geometry.hit(midpoint, excluding: [], tolerance: 0.1) == a.id)
    #expect(geometry.hit(midpoint, excluding: [a.id], tolerance: 0.1) == nil)
    let small = [CGPoint(x: midpoint.x-10,y: midpoint.y-2), CGPoint(x: midpoint.x+10,y: midpoint.y-2),
      CGPoint(x: midpoint.x+10,y: midpoint.y+2), CGPoint(x: midpoint.x-10,y: midpoint.y+2)]
    #expect(geometry.lasso(small, excluding: []) == [a.id])
    #expect(geometry.lasso(small, excluding: [a.id]).isEmpty)
    #expect(!geometry.lasso(small, excluding: []).contains(b.id))
    #expect(geometry.lasso(Array(small.prefix(2)), excluding: []).isEmpty)
    let enlarged = PortraitLineSelectionGeometry(program: program, size: .init(width: 840, height: 840))
    #expect(enlarged.hit(enlarged.lines[0].points[0], excluding: []) == a.id)
  }

  @Test("Removal groups undo and redo exactly, preserve root, persist and export a plot-admissible target")
  func persistenceAndPlotting() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PortraitCandidateStore(directoryURL: directory)
    let sketches = PortraitSketchCollection(store: store)
    let base = try Self.drawing()
    let model = PortraitLineEditModel(base: base, sketches: sketches)
    await model.load()
    #expect(model.error == nil)
    let root = try #require(model.original)
    let ids = root.program.strokes.map(\.id)
    model.remove([ids[0], ids[1]])
    #expect(model.removed == Set(ids.prefix(2)))
    #expect(model.batches.count == 1)
    model.undo(); #expect(model.removed.isEmpty)
    model.redo(); #expect(model.removed == Set(ids.prefix(2)))
    model.undo(); model.remove([ids[2]])
    #expect(!model.canRedo)
    #expect(model.original == root)
    #expect(await model.save())
    let edited = try #require(model.savedDrawing)
    #expect(!model.hasUnsavedChanges)
    #expect(edited.program.strokes == base.program.strokes.filter { $0.id != ids[2] })
    #expect(edited.runCandidateReference?.matches(edited.program) == true)
    #expect(SavedDrawing.authored(program: edited.program, projectedDrawing: edited, executionProgram: edited.program) == edited)
    #expect(sketches.labels.isEmpty)
    #expect(try await sketches.drawingForBrowsing(base.id, photoID: base.sourcePhotoID).program == base.program)

    let bytes = try await sketches.exportDrawingPackage(edited)
    let package = try DrawingPackageCodec.decode(bytes)
    let record = try #require(try DrawingStrokeSelection.record(in: package))
    #expect(record.judgment == "unrated-selection-target")
    #expect(record.removedStrokeIDs == [ids[2]])
    #expect(record.deletionBatches == [[ids[2]]])
    #expect(try record.original() == root)
    let reopened = PortraitSketchCollection(store: PortraitCandidateStore(directoryURL: directory))
    let loaded = try await reopened.drawingForBrowsing(edited.id)
    #expect(loaded == edited)
    #expect(try await reopened.exportDrawingPackage(loaded) == bytes)
    let receiver = PortraitSketchCollection(store: PortraitCandidateStore(directoryURL: directory.appendingPathComponent("receiver")))
    let imported = try await receiver.importDrawingPackage(bytes)
    #expect(imported == edited)
    let region = try DrawableMachineRegion(bounds: .init(minX: 0, minY: 0, maxX: 200, maxY: 200))
    let placement = try DrawingPlacement(fieldAnchor: .init(x: 0,y: 0), machineAnchor: .init(x: 10,y: 10), uniformScale: 1, rotationRadians: 0)
    let plan = try DrawingPlanner.plan(program: imported.program, placement: placement, drawableRegion: region,
      provenance: .init(modelRevisionID: DrawingModelRevisionID(), modelContentHash: imported.program.contentHash,
        registrationRevisionID: DrawingRegistrationRevisionID(), registrationContentHash: imported.program.contentHash))
    #expect(plan.strokes.count == imported.program.strokes.count)
    #expect(plan.sourceProgramContentHash == imported.program.contentHash)

    let next = PortraitLineEditModel(base: imported, sketches: receiver)
    await next.load(); #expect(next.error == nil)
    #expect(next.removed == [ids[2]])
    next.remove([ids[0]])
    #expect(await next.save())
    let nextPackage = try #require(next.savedDrawing?.transferredPackage)
    let nextRecord = try #require(try DrawingStrokeSelection.record(in: nextPackage))
    #expect(nextRecord.originalPackageJSON == record.originalPackageJSON)
    #expect(nextRecord.baseProgram == imported.program)
    #expect(nextPackage.origin.libraryID != package.origin.libraryID)
    #expect(Set(nextRecord.removedStrokeIDs) == [ids[0], ids[2]])
    #expect(nextRecord.initialRemovedStrokeIDs == [ids[2]])
  }

  @Test("Blank targets cannot save; original view cannot delete; save failure preserves undoable work")
  func failureAndEmpty() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let sketches = PortraitSketchCollection(store: PortraitCandidateStore(directoryURL: directory))
    let model = PortraitLineEditModel(base: try Self.drawing(), sketches: sketches)
    await model.load()
    let ids = try #require(model.original).program.strokes.map(\.id)
    model.showsOriginal = true; model.remove([ids[0]]); #expect(model.removed.isEmpty)
    model.showsOriginal = false
    model.remove(Set(ids)); #expect(model.remainingCount == 0); #expect(!model.canSave)
    #expect(!(await model.save()))
    model.undo(); model.remove([ids[0]])
    // Make the durable root unavailable after loading; saving must not fabricate a replacement.
    let root = try #require(model.original)
    let transfers = directory.appendingPathComponent("transfers")
    for file in try FileManager.default.contentsOfDirectory(at: transfers, includingPropertiesForKeys: nil) {
      let package = try DrawingPackageCodec.decode(Data(contentsOf: file))
      if package.origin == root.origin { try FileManager.default.removeItem(at: file) }
    }
    #expect(!(await model.save()))
    #expect(model.error != nil)
    #expect(model.hasUnsavedChanges && model.canUndo && model.removed == [ids[0]])
    model.undo(); #expect(model.removed.isEmpty)
  }

  @Test("Native canvas routes click, lasso, Delete and focused undo without taking text shortcuts")
  func nativeEvents() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = PortraitLineEditModel(base: try Self.drawing(),
      sketches: PortraitSketchCollection(store: PortraitCandidateStore(directoryURL: directory)))
    await model.load()
    let program = try #require(model.original?.program)
    let window = NSWindow(contentRect: .init(x: -10000,y: -10000,width: 440,height: 440),
      styleMask: [.borderless],backing: .buffered,defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let canvas = PortraitLineEditorNSView(frame: .init(x: 0,y: 0,width: 420,height: 420))
    window.contentView?.addSubview(canvas)
    canvas.model = model; canvas.program = program; canvas.editingEnabled = true
    let geometry = PortraitLineSelectionGeometry(program: program,size: canvas.bounds.size)
    let line = geometry.lines[0]
    let center = CGPoint(x: (line.points[0].x+line.points[1].x)/2,y: line.points[0].y)
    func mouse(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
      try #require(NSEvent.mouseEvent(with: type, location: canvas.convert(point,to: nil),modifierFlags: [],
        timestamp: 0,windowNumber: window.windowNumber,context: nil,eventNumber: 0,clickCount: 1,pressure: 1))
    }
    func key(_ code: UInt16, _ text: String, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
      try #require(NSEvent.keyEvent(with: .keyDown,location: .zero,modifierFlags: flags,timestamp: 0,
        windowNumber: window.windowNumber,context: nil,characters: text,charactersIgnoringModifiers: text,isARepeat: false,keyCode: code))
    }
    canvas.mouseDown(with: try mouse(.leftMouseDown,center)); canvas.mouseUp(with: try mouse(.leftMouseUp,center))
    #expect(model.removed == [line.id])
    #expect(window.firstResponder === canvas)
    #expect(canvas.performKeyEquivalent(with: try key(6,"z",.command)))
    #expect(model.removed.isEmpty)
    #expect(canvas.performKeyEquivalent(with: try key(6,"z",[.command,.shift])))
    #expect(model.removed == [line.id]); model.undo()
    canvas.tool = .lasso; model.tool = .lasso
    let polygon = [CGPoint(x:center.x-10,y:center.y-2),CGPoint(x:center.x+10,y:center.y-2),
      CGPoint(x:center.x+10,y:center.y+2),CGPoint(x:center.x-10,y:center.y+2)]
    canvas.mouseDown(with: try mouse(.leftMouseDown,polygon[0]))
    for point in polygon.dropFirst() { canvas.mouseDragged(with: try mouse(.leftMouseDragged,point)) }
    canvas.mouseUp(with: try mouse(.leftMouseUp,polygon[0]))
    #expect(model.selection == [line.id])
    canvas.keyDown(with: try key(51,"\u{7f}")); #expect(model.removed == [line.id])
    model.undo()
    let field = NSTextView(frame: .init(x: 0,y: 420,width: 100,height: 20))
    window.contentView?.addSubview(field); #expect(window.makeFirstResponder(field))
    #expect(!canvas.performKeyEquivalent(with: try key(6,"z",.command)))
    canvas.selected = [line.id]
    let bitmap = try #require(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
    canvas.cacheDisplay(in: canvas.bounds,to: bitmap)
    let png = try #require(bitmap.representation(using: .png,properties: [:]))
    try png.write(to: URL(fileURLWithPath: "/tmp/flow-edit-canvas-test.png"))
  }

  @Test("Actual Flow Edge output retains every surviving point and renderer record after selection")
  func nativeFlowOutput() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fixture = try Self.drawing(), prior = try #require(fixture.portraitCandidate)
    let raster = PortraitRaster(width: 32,height: 32,luminance: (0..<1024).map {
      (($0 % 32)/8 + ($0/32)/8).isMultiple(of: 2) ? 0.1 : 0.9
    },provenance: "synthetic-flow-grid",analysisSummary: "Synthetic Flow Edge renderer fixture")
    let program = try PortraitVectorizer.program(from: raster,pose: .front,style: .flowEdges,
      strokeStyle: fixture.program.strokes[0].style)
    #expect(program.strokes.count > 1)
    let candidate = try PortraitCandidate(sourceData: prior.sourceData,sourcePixelExtent: nil,raster: raster,
      recipe: prior.recipe,program: program,photoID: UUID(),captureSessionID: UUID())
    let model = PortraitLineEditModel(base: SavedDrawing(candidate: candidate),
      sketches: PortraitSketchCollection(store: PortraitCandidateStore(directoryURL: directory)))
    await model.load(); #expect(model.error == nil)
    model.remove([program.strokes[0].id]); #expect(await model.save())
    #expect(model.savedDrawing?.program.strokes == Array(program.strokes.dropFirst()))
    #expect(model.original?.legacyCandidateJSON == model.original?.resultRecordJSON)
  }

  @Test("The complete editor presents its native canvas at the minimum supported desktop size")
  func nativeLayout() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let sketches = PortraitSketchCollection(store: PortraitCandidateStore(directoryURL: directory))
    let host = NSHostingView(rootView: PortraitLineEditor(drawing: try Self.drawing(), sketches: sketches)
      .background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.light))
    let window = NSWindow(contentRect: .init(x: -10000,y: -10000,width: 900,height: 680),
      styleMask: [.borderless],backing: .buffered,defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    window.appearance = NSAppearance(named: .aqua)
    window.orderFront(nil)
    defer { window.close() }
    func canvas(in view: NSView) -> PortraitLineEditorNSView? {
      if let found = view as? PortraitLineEditorNSView { return found }
      return view.subviews.lazy.compactMap { canvas(in: $0) }.first
    }
    for _ in 0..<60 {
      host.layoutSubtreeIfNeeded()
      if canvas(in: host) != nil { break }
      try await Task.sleep(for: .milliseconds(50))
    }
    let surface = try #require(canvas(in: host))
    #expect(surface.frame.width >= 800)
    #expect(surface.frame.height >= 350)
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds,to: bitmap)
    try #require(bitmap.representation(using: .png,properties: [:])).write(to: URL(fileURLWithPath: "/tmp/flow-edit-editor-test.png"))
  }

  @Test("Unknown, duplicate, exhaustive and geometry-mismatched removal records are rejected")
  func invalidTargets() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let sketches = PortraitSketchCollection(store: PortraitCandidateStore(directoryURL: directory))
    let base = try Self.drawing(), bytes = try await sketches.exportDrawingPackage(base)
    let root = try DrawingPackageCodec.decode(bytes), ids = root.program.strokes.map(\.id)
    for groups in [[[StrokeID()]], [[ids[0],ids[0]]], [ids]] {
      #expect(throws: (any Error).self) {
        try DrawingStrokeSelection(editID: UUID(), createdAt: Date(), originalPackageJSON: bytes,
          baseOrigin: root.origin, baseProgram: root.program, initialRemovedStrokeIDs: [], deletionBatches: groups)
      }
    }
    let record = try DrawingStrokeSelection(editID: UUID(), createdAt: Date(), originalPackageJSON: bytes,
      baseOrigin: root.origin, baseProgram: root.program, initialRemovedStrokeIDs: [], deletionBatches: [[ids[0]]])
    let edited = try await sketches.saveStrokeSelection(record, base: base)
    let package = try #require(edited.transferredPackage)
    // Even rehashing the package around a different program cannot change the declared subset.
    #expect(throws: (any Error).self) {
      try DrawingPackage(origin: .init(libraryID: package.origin.libraryID, captureID: package.origin.captureID,
        resultID: package.origin.resultID, resultRecordSHA256: package.origin.resultRecordSHA256, programHash: root.program.contentHash),
        program: root.program, createdAt: package.createdAt, title: package.title, resultRecordJSON: package.resultRecordJSON,
        source: package.source, artistInput: package.artistInput, artist: package.artist, preview: package.preview)
    }
  }

  private static func program() throws -> DrawingProgram {
    let coordinates: [[(Double,Double)]] = [[(10,50),(90,50)],[(20,20),(20,30),(25,30)],[(10,52),(90,52)],[(70,70),(90,90)]]
    let style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID())
    return try DrawingProgram(id: ProgramID(), fieldExtent: .init(width: 100,height: 100),
      strokes: coordinates.enumerated().map { index, points in
        LogicalStroke(id: StrokeID(), path: try Polyline(points: points.map { try Point2(x: $0.0,y: $0.1) }),
          style: style, ordering: UInt32(index))
      }, source: .init(kind: "portrait", sourceIdentifier: "portrait-v3|pose=Front|flow=flow-edge-v1|fixture"))
  }

  private static func drawing() throws -> SavedDrawing {
    let source = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aY9sAAAAASUVORK5CYII=")!
    let raster = PortraitRaster(width: 2,height: 2,luminance: [0,1,1,0],provenance: "fixture",analysisSummary: "Synthetic fixture")
    let recipe = PortraitStyleRecipe(id: "fixture",title: "Flow Edge",seed: 0,style: .flowEdges,
      vectorOptions: .init(),analysisOptions: .init())
    return SavedDrawing(candidate: try PortraitCandidate(sourceData: source,sourcePixelExtent: nil,raster: raster,
      recipe: recipe,program: program(),photoID: UUID(),captureSessionID: UUID()))
  }
}
