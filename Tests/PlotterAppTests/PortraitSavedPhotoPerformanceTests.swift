import Foundation
import PlotterModel
import Testing
@testable import PlotterApp

/// Read-only, opt-in replay of a retained recipe and raster. No archive installer
/// or camera is involved, and before/after runs use the same compilation mode.
@Suite("Portrait saved-photo workload", .serialized)
struct PortraitSavedPhotoPerformanceTests {
  private struct Reference: Decodable {
    let recipe: PortraitStyleRecipe
    let program: DrawingProgram
    let pose: PortraitPose
    let photoID: UUID
    let captureSessionID: UUID
    let sourceSHA256: String
    let rasterSHA256: String
    let sourcePixelExtent: PortraitSourceCropExtent?
  }

  @Test("retained drawing reproduces exactly and reports preparation/render stages",
    .enabled(if: ProcessInfo.processInfo.environment["PORTRAIT_SPEED_REFERENCE_RECORD"] != nil))
  func retainedRecipe() async throws {
    let environment = ProcessInfo.processInfo.environment
    let recordURL = URL(fileURLWithPath: try #require(environment["PORTRAIT_SPEED_REFERENCE_RECORD"]))
    let reference = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: recordURL))
    let assets = recordURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("assets")
    let data = try Data(contentsOf: assets.appendingPathComponent(reference.sourceSHA256))
    let rasterData = try Data(contentsOf: assets.appendingPathComponent(reference.rasterSHA256))
    #expect(PortraitCandidateCoding.digest(data) == reference.sourceSHA256)
    #expect(PortraitCandidateCoding.digest(rasterData) == reference.rasterSHA256)
    let raster = try JSONDecoder().decode(PortraitRaster.self, from: rasterData)
    let pen = try #require(reference.program.strokes.first?.style)
    let analyzer = PortraitImageAnalyzer()
    var reports: [[String: Any]] = []
    var workspace: PortraitFlowRenderer.Workspace?
    for index in 0..<5 {
      let started = ProcessInfo.processInfo.systemUptime
      let result = try await analyzer.render(.init(data: data, pose: reference.pose,
        style: reference.recipe.style, options: reference.recipe.analysisOptions,
        cachedRaster: raster, strokeStyle: pen, vectorOptions: reference.recipe.vectorOptions,
        sourcePixelExtent: reference.sourcePixelExtent, flowWorkspace: workspace))
      let candidate = try PortraitCandidate(sourceData: data, sourcePixelExtent: reference.sourcePixelExtent,
        raster: result.raster, recipe: reference.recipe, program: result.program,
        photoID: reference.photoID, captureSessionID: reference.captureSessionID,
        pose: reference.pose, warpManifest: result.warpManifest)
      _ = try PortraitAttemptRecord.prepare(candidate: candidate, pen: pen)
      // An immutable saved drawing is the oracle, including all points and IDs.
      #expect(result.program == reference.program)
      workspace = result.flowWorkspace
      reports.append(["kind": index == 0 ? "coldWorkspace" : "warmWorkspace",
        "totalMS": (ProcessInfo.processInfo.systemUptime - started) * 1000,
        "flowMS": result.timings?.flowMS ?? 0, "vectorMS": result.timings?.vectorMS ?? 0,
        "supportMS": workspace?.diagnostics.supportMS ?? 0,
        "structureMS": workspace?.diagnostics.structureMS ?? 0,
        "orientationMS": workspace?.diagnostics.orientationMS ?? 0,
        "tracingMS": workspace?.diagnostics.tracingMS ?? 0,
        "programHash": result.program.contentHash.description])
    }
    // Fresh source analysis exercises the exact crop and foreground controls.
    for _ in 0..<3 {
      let started = ProcessInfo.processInfo.systemUptime
      let result = try await analyzer.render(.init(data: data, pose: reference.pose,
        style: reference.recipe.style, options: reference.recipe.analysisOptions,
        cachedRaster: nil, strokeStyle: pen, vectorOptions: reference.recipe.vectorOptions,
        sourcePixelExtent: reference.sourcePixelExtent))
      reports.append(["kind": "freshSource",
        "totalMS": (ProcessInfo.processInfo.systemUptime - started) * 1000,
        "sourceMS": result.timings?.sourceMS ?? 0, "cropMS": result.timings?.cropMS ?? 0,
        "flowMS": result.timings?.flowMS ?? 0, "vectorMS": result.timings?.vectorMS ?? 0,
        "programHash": result.program.contentHash.description])
    }
    #if DEBUG
    let configuration = "debug"
    #else
    let configuration = "release"
    #endif
    let bytes = try JSONSerialization.data(withJSONObject: ["configuration": configuration,
      "sourceSHA256": reference.sourceSHA256, "samples": reports,
      "nativeClickToPaintMeasured": false], options: [.prettyPrinted, .sortedKeys])
    print("PORTRAIT_SAVED_PHOTO_WORKLOAD " + String(decoding: bytes, as: UTF8.self))
    if let output = environment["PORTRAIT_SPEED_OUTPUT"] {
      try bytes.write(to: URL(fileURLWithPath: output), options: .atomic)
    }
  }
}
