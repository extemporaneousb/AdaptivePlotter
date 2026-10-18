import Foundation
import PlotterModel
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary
import Testing
@testable import PortraitStudio

/// Opt-in local curation. Reads frozen sources and writes only a fresh exercise
/// root. It neither downloads portraits nor opens production libraries.
@Suite("Opt-in Flow Edge surface exercises", .serialized)
@MainActor
struct PortraitSurfaceExerciseTests {
  struct Source: Codable {
    let index: Int
    let title: String
    let filename: String
    let sha256: String
    let captureID: UUID
    let acquisitionID: UUID
  }
  struct Selection: Codable { let sources: [Source] }
  struct Output: Codable {
    let sourceIndex: Int
    let round: Int
    let drawingID: String
    let title: String
    let rootProgramHash: String
    let targetProgramHash: String
    let protectedCount: Int
    let keptCount: Int
    let removedCount: Int
    let packageFile: String
  }
  struct Report: Codable {
    let revision: String
    let selectionSHA256: String
    let outputs: [Output]
    let failures: [String]
    let humanLabels: Int
  }

  @Test("Generate two feature-preserving whole-line proposals per frozen source",
    .enabled(if: ProcessInfo.processInfo.environment["PORTRAIT_SURFACE_EXERCISE_ROOT"] != nil))
  func generate() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["PORTRAIT_SURFACE_EXERCISE_ROOT"])
    guard path.hasPrefix("/") else { throw DrawingTransferError.invalid("Exercise root must be absolute.") }
    let root = URL(fileURLWithPath:path,isDirectory:true)
    let selectionBytes = try Data(contentsOf:root.appendingPathComponent("sources.json"))
    let selection = try JSONDecoder().decode(Selection.self,from:selectionBytes)
    guard (1...8).contains(selection.sources.count),
      Set(selection.sources.map(\.sha256)).count == selection.sources.count,
      Set(selection.sources.map(\.index)).count == selection.sources.count else {
      throw DrawingTransferError.invalid("Exercise sources must be distinct and bounded to eight.")
    }
    let libraryURL = root.appendingPathComponent("ExerciseLibrary",isDirectory:true)
    guard !FileManager.default.fileExists(atPath:libraryURL.path) else {
      throw DrawingTransferError.conflict("Exercise library already exists; preserve it and choose a fresh root.")
    }
    let store = PortraitCandidateStore(directoryURL:libraryURL)
    let sketches = PortraitSketchCollection(store:store)
    let style = try StrokeStyle(nominalLineWidth:0.4,penProfileID:PenProfileID(UUID(uuidString:"00000000-0000-0000-0000-000000000001")!))
    let analysis = PortraitAnalysisOptions(cropToFace:true,removeBackground:true,faceCropMargin:0.18)
    var vectors = PortraitVectorOptions.nativeDefaults(for:.flowEdges)
    vectors.tonalStrength = 0.25
    vectors.flowSupport = 0.65
    vectors.flowSupportScale = 0.5
    // Keep structural thresholds unchanged. Whole-line proposals below protect
    // measured features; skin suppression must not destroy their recovery pool.
    var outputs: [Output] = [], failures: [String] = []
    for source in selection.sources {
      let directory = root.appendingPathComponent(String(format:"source-%02d",source.index),isDirectory:true)
      try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
      do {
        guard !source.filename.contains("/"), source.filename != ".", source.filename != ".." else {
          throw DrawingTransferError.invalid("Source filenames must name direct frozen files.")
        }
        let bytes = try Data(contentsOf:root.appendingPathComponent(source.filename))
        guard DrawingPackageCodec.sha256(bytes) == source.sha256 else {
          throw DrawingTransferError.invalid("Frozen source hash changed.")
        }
        let asset = try DrawingPackageLibraryValidation.sourceAsset(bytes)
        let extent = try PortraitSourceCropExtent(widthPixels:Double(try #require(asset.pixelWidth)),heightPixels:Double(try #require(asset.pixelHeight)))
        let result = try await PortraitImageAnalyzer().render(.init(data:bytes,pose:.front,style:.flowEdges,
          options:analysis,strokeStyle:style,vectorOptions:vectors,sourcePixelExtent:extent))
        let recipe = PortraitStyleRecipe(id:"surface-exercise-basis-v1",title:String(format:"Source %02d · ",source.index)+source.title,
          seed:0,style:.flowEdges,vectorOptions:vectors,analysisOptions:analysis)
        let candidate = try PortraitCandidate(sourceData:bytes,sourcePixelExtent:extent,raster:result.raster,
          recipe:recipe,program:result.program,photoID:source.captureID,captureSessionID:source.acquisitionID,pose:.front)
        let base = SavedDrawing(candidate:candidate)
        let originalBytes = try await sketches.exportDrawingPackage(base)
        let original = try DrawingPackageCodec.decode(originalBytes)
        try originalBytes.write(to:directory.appendingPathComponent("basis.portraitdrawing.json"),options:.withoutOverwriting)
        try original.preview.bytes.write(to:directory.appendingPathComponent("basis.png"),options:.withoutOverwriting)
        for round in 1...2 {
          let proposal = try PortraitSurfaceSelection.propose(program:result.program,raster:result.raster,round:round)
          let repeated = try PortraitSurfaceSelection.propose(program:result.program,raster:result.raster,round:round)
          #expect(proposal.decisions == repeated.decisions)
          #expect(proposal.decisions.filter(\.featureProtected).allSatisfy { $0.retained })
          let title = "Round \(round) · " + String(format:"%02d",source.index) + " · " + source.title
          let policy = try DrawingPackageCodec.encoder().encode(proposal)
          try policy.write(to:directory.appendingPathComponent("round-\(round)-policy.json"),options:.withoutOverwriting)
          let record = try DrawingStrokeSelection(editID:UUID(),createdAt:Date(),originalPackageJSON:originalBytes,
            baseOrigin:original.origin,baseProgram:original.program,initialRemovedStrokeIDs:[],
            operations:proposal.removedIDs.isEmpty ? [] : [.init(action:.remove,strokeIDs:proposal.removedIDs)],
            operationSource:.exerciseProposal,exerciseContext:.init(id:UUID(),title:title,policyJSON:policy))
          let drawing = try await sketches.saveStrokeSelection(record,base:base)
          let packageBytes = try await sketches.exportDrawingPackage(drawing)
          let package = try DrawingPackageCodec.decode(packageBytes)
          let name = "round-\(round).portraitdrawing.json"
          try packageBytes.write(to:directory.appendingPathComponent(name),options:.withoutOverwriting)
          try package.preview.bytes.write(to:directory.appendingPathComponent("round-\(round).png"),options:.withoutOverwriting)
          let expected = Set(proposal.decisions.filter(\.retained).map(\.strokeID))
          #expect(drawing.program.strokes == original.program.strokes.filter { expected.contains($0.id) })
          outputs.append(Output(sourceIndex:source.index,round:round,drawingID:drawing.id,title:title,
            rootProgramHash:original.program.contentHash.description,targetProgramHash:drawing.program.contentHash.description,
            protectedCount:proposal.decisions.filter(\.featureProtected).count,keptCount:drawing.program.strokes.count,
            removedCount:proposal.removedIDs.count,packageFile:directory.lastPathComponent+"/"+name))
        }
      } catch {
        failures.append("\(source.index): \(error.localizedDescription)")
        try Data(error.localizedDescription.utf8).write(to:directory.appendingPathComponent("failure.txt"),options:.withoutOverwriting)
      }
    }
    let report = Report(revision:PortraitSurfaceSelection.revision,
      selectionSHA256:DrawingPackageCodec.sha256(selectionBytes),outputs:outputs,failures:failures,humanLabels:0)
    try DrawingPackageCodec.encoder().encode(report).write(to:root.appendingPathComponent("exercise-report.json"),options:.withoutOverwriting)
    #expect(!outputs.isEmpty)
    #expect(failures.isEmpty)
  }
}
