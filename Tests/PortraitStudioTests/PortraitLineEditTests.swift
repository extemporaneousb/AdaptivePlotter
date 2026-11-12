import AppKit
import Foundation
import DrawingLibrary
import PlotterModel
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary
import PortraitStudioUI
import Testing
import ImageIO

@Suite("Drawing stable whole-line editing", .serialized)
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

  @Test("Export PNG orientation agrees with y-up authored paths and the editor")
  func previewOrientation() throws {
    let png = try PortraitDrawingPreview.png(Self.program())
    let imageSource = try #require(CGImageSourceCreateWithData(png as CFData,nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(imageSource,0,nil))
    let data = try #require(image.dataProvider?.data)
    let bytes = try #require(CFDataGetBytePtr(data))
    func luminance(x: Double,y: Double) -> UInt8 {
      let offset = Int(y * Double(image.height)) * image.bytesPerRow + Int(x * Double(image.width)) * 4
      return min(bytes[offset],bytes[offset+1],bytes[offset+2])
    }
    // Only the upper-right diagonal passes (80,80). Its vertical mirror is empty.
    #expect(luminance(x: 0.8,y: 0.2) < 100)
    #expect(luminance(x: 0.8,y: 0.8) > 240)
  }

  @Test("Native canvas routes click, lasso, Delete and focused undo without taking text shortcuts")
  func nativeEvents() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = PortraitLineEditModel(base: try Self.drawing(),
      sketches: PortraitSketchCollection(library: DrawingLibrary(directoryURL: directory)))
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
    canvas.removed = model.removed; canvas.tool = .restore; model.tool = .restore
    canvas.mouseDown(with: try mouse(.leftMouseDown,center)); canvas.mouseUp(with: try mouse(.leftMouseUp,center))
    #expect(model.removed.isEmpty)
    model.undo(); #expect(model.removed == [line.id]); model.redo(); #expect(model.removed.isEmpty)
    canvas.removed = []; canvas.tool = .lasso; model.tool = .lasso
    let field = NSTextView(frame: .init(x: 0,y: 420,width: 100,height: 20))
    window.contentView?.addSubview(field); #expect(window.makeFirstResponder(field))
    #expect(!canvas.performKeyEquivalent(with: try key(6,"z",.command)))
    canvas.selected = [line.id]
    let bitmap = try #require(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
    canvas.cacheDisplay(in: canvas.bounds,to: bitmap)
    let png = try #require(bitmap.representation(using: .png,properties: [:]))
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try png.write(to: directory.appendingPathComponent("canvas.png"))
  }

  @Test("Opening does not retain; remove restore undo redo save a child with exact surviving points")
  func immutableEdit() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let library = DrawingLibrary(directoryURL: directory); try await library.open()
    let base = try Self.drawing(), sketches = PortraitSketchCollection(library: library)
    let editor = PortraitLineEditModel(base: base, sketches: sketches)
    await editor.load()
    #expect(try await library.drawings().entries.isEmpty)
    let ids = base.program.strokes.map(\.id)
    editor.remove([ids[0], ids[2]]); editor.restore([ids[0]])
    #expect(editor.removed == [ids[2]])
    editor.undo(); #expect(editor.removed == [ids[0], ids[2]])
    editor.redo(); #expect(editor.removed == [ids[2]])
    #expect(await editor.save())
    let child = try #require(editor.savedDrawing), ref = try #require(child.reference)
    #expect(child.program.strokes == base.program.strokes.filter { $0.id != ids[2] })
    guard case .present(let parent) = child.parent else { Issue.record("Exact retained parent missing"); return }
    #expect(try await library.drawing(parent).program == base.program)
    #expect(try await library.drawing(ref).program == child.program)
    let unchanged = PortraitLineEditModel(base: child, sketches: sketches); await unchanged.load()
    #expect(await unchanged.save()); #expect(unchanged.savedDrawing?.reference == ref)
    editor.remove(Set(ids)); #expect(!editor.canSave && editor.remainingCount == 0)
    #expect(await editor.save() == false)
    editor.showsOriginal = true; let mask = editor.removed; editor.restore([ids[0]]); #expect(editor.removed == mask)
    await sketches.shutdown(); await library.closeLibrary()
  }

  @Test("Actual Flow output keeps renderer receipt and every surviving point under Drawing edits")
  func renderedPoints() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID())
    let production = try await PortraitFlowDrawingProducer().produce(input: .init(data: FlowAuthoringFixture.image(4)),
      settings: .init(recipe: .standard, analysisOptions: .init(cropToFace: false, removeBackground: false), strokeStyle: style))
    let library = DrawingLibrary(directoryURL: root); try await library.open()
    let editor = PortraitLineEditModel(base: production.drawing, sketches: PortraitSketchCollection(library: library))
    await editor.load(); let first = try #require(production.drawing.program.strokes.first)
    editor.remove([first.id]); #expect(await editor.save())
    let child = try #require(editor.savedDrawing)
    #expect(child.program.strokes == production.drawing.program.strokes.filter { $0.id != first.id })
    guard case .present(let parent) = child.parent else { Issue.record("Missing parent"); return }
    #expect(try await library.drawing(parent).producer.originalJSON == production.drawing.producer.originalJSON)
    await library.closeLibrary()
  }

  @Test("Drawing-own requirements deny editor entry and save without changing retained bytes")
  func unsupportedOwnFeatures() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("library"))
    let imported = try await DrawingEditFixture.imported(in: library, directory: root, unsupportedOwn: true)
    let before = try await library.drawings().entries.map(\.reference)
    let sketches = PortraitSketchCollection(library: library)
    let editor = PortraitLineEditModel(base: imported.drawing, sketches: sketches)
    #expect(!PortraitLineEditModel.supports(imported.drawing))
    await editor.load()
    #expect(!editor.canEdit && !editor.canSave)
    editor.remove([try #require(imported.drawing.program.strokes.first).id])
    #expect(editor.removed.isEmpty)
    #expect(await editor.save() == false)
    #expect(try await library.drawings().entries.map(\.reference) == before)
    await sketches.shutdown(); await library.closeLibrary()
  }

  @Test("Fresh source-free catalog output edits with unknown physical width and no Photo")
  func sourceFreeParity() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let base = try await DrawingEditFixture.sourceFree()
    #expect(base.input == .none && base.units.nominalPenWidthMM == nil)
    let library = DrawingLibrary(directoryURL: root)
    let sketches = PortraitSketchCollection(library: library)
    let editor = PortraitLineEditModel(base: base, sketches: sketches)
    await editor.load()
    #expect(editor.canEdit)
    #expect(!FileManager.default.fileExists(atPath: root.path))
    let removed = try #require(base.program.strokes.first).id
    editor.remove([removed]); #expect(await editor.save())
    let child = try #require(editor.savedDrawing)
    #expect(child.input == .none && child.units.nominalPenWidthMM == nil)
    #expect(child.program.strokes == base.program.strokes.filter { $0.id != removed })
    guard case .present(let parent) = child.parent else { Issue.record("Missing catalog parent"); return }
    #expect(try await library.drawing(parent).producer.originalJSON == base.producer.originalJSON)
    #expect(try await library.photos().entries.isEmpty)
    await sketches.shutdown(); await library.closeLibrary()
  }

  @Test("Intrinsic source uncertainty permits exact membership edits and survives offline child closure")
  func uncertainSourceOfflineChild() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("library"))
    let imported = try await DrawingEditFixture.imported(in: library, directory: root, uncertainSource: true)
    let parentRef = try #require(imported.drawing.reference)
    #expect(!imported.drawing.capabilities.sourceSemanticsSupported)
    #expect(PortraitLineEditModel.supports(imported.drawing))
    let sketches = PortraitSketchCollection(library: library)
    let editor = PortraitLineEditModel(base: imported.drawing, sketches: sketches)
    await editor.load(); #expect(editor.canEdit)
    let removed = try #require(imported.drawing.program.strokes.first).id
    editor.remove([removed]); #expect(await editor.save())
    let child = try #require(editor.savedDrawing), childRef = try #require(child.reference)
    let inputRef = try #require(imported.input)
    #expect(child.parent == .present(parentRef) && child.input == .present(inputRef))
    #expect(child.program.strokes == imported.drawing.program.strokes.filter { $0.id != removed })
    #expect(!child.capabilities.sourceSemanticsSupported)
    #expect(throws: (any Error).self) { try child.capabilities.require(.regenerate) }
    #expect(throws: (any Error).self) { try child.capabilities.require(.train) }
    let exported = root.appendingPathComponent("child.zip")
    try await library.exportDrawing(childRef, to: exported)
    await sketches.shutdown(); await library.closeLibrary()
    try FileManager.default.removeItem(at: root.appendingPathComponent("library"))
    let offline = DrawingLibrary(directoryURL: root.appendingPathComponent("offline"))
    #expect(try await offline.importDrawings(from: exported) == [childRef])
    let reloaded = try await offline.drawing(childRef)
    #expect(reloaded.parent == .present(parentRef) && reloaded.program == child.program)
    #expect(try await offline.drawing(parentRef).producer.originalJSON == imported.drawing.producer.originalJSON)
    let stage = root.appendingPathComponent("stage")
    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
    let admitted = try ExchangeAdmission.validate(DrawingExchangeCarrier.stageZIP(exported, stagingParent: stage))
    for (path, bytes) in imported.sourceFiles where path != "data/exchange.json" {
      #expect(try admitted.files.record(at: path) == bytes)
    }
    await offline.closeLibrary()
  }

  @Test("Stable membership refuses unknown, duplicate, exhaustive and mismatched stroke bases")
  func rejectedMembership() throws {
    let program = try Self.program(), ids = program.strokes.map(\.id)
    #expect(throws: DrawingExchangeError.unknownStroke) { try DrawingStrokeMembership.apply(.remove([StrokeID()]), to: program, universe: program) }
    #expect(throws: DrawingExchangeError.duplicateStroke) { try DrawingStrokeMembership.apply(.remove([ids[0], ids[0]]), to: program, universe: program) }
    #expect(throws: DrawingExchangeError.allStrokesRemoved) { try DrawingStrokeMembership.apply(.remove(ids), to: program, universe: program) }
    let other = try Self.program()
    #expect(throws: DrawingExchangeError.mismatchedParent) { try DrawingStrokeMembership.apply(.remove([ids[0]]), to: program, universe: other) }
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

  private static func drawing() throws -> Drawing {
    try StudioDrawingFixture.production(program: program(), raster: FlowPortfolioTests.raster).drawing
  }
}
