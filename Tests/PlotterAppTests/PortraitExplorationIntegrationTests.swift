import Foundation
import PlotterModel
import Testing

@testable import PlotterApp

@Suite("Exact Drawing Studio exploration integration")
@MainActor
struct PortraitExplorationIntegrationTests {
  @Test("local branches reuse exact retained analysis after photo eviction without implicit retention")
  func retainedSourceLocalBranch() async throws {
    let renderer = ExplorationRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let parent = try #require(model.selectedCandidate)
    #expect(model.keepSelection() == nil)
    model.removePhoto(parent.photoID, strokeStyle: pen)
    #expect(model.recentPhotos.isEmpty)
    model.moreLikeThis(seed: 17)
    // A SwiftUI configuration callback uses today's nominal pen. It must not
    // replace the already-owned local proposal or its inherited pen/context.
    let otherPen = try StrokeStyle(nominalLineWidth: pen.nominalLineWidth + 0.3,
      penProfileID: pen.penProfileID)
    model.renderIfConfigurationChanged(strokeStyle: otherPen)
    await model.awaitRendering()
    let child = try #require(model.selectedCandidate)
    let request = try #require(await renderer.requests.last)
    #expect(request.data == parent.sourceData)
    #expect(request.cachedRaster?.luminance == parent.raster.luminance)
    #expect(request.cachedRaster?.provenance == parent.raster.provenance)
    #expect(request.options == parent.recipe.analysisOptions)
    #expect(request.strokeStyle == pen)
    #expect(child.lineage.parentID == parent.id)
    #expect(child.proposal?.kind == .local)
    #expect(child.proposal?.seed == 17)
    #expect(child.rasterSHA256 == parent.rasterSHA256)
    #expect(child.recipe.style == parent.recipe.style)
    #expect(child.recipe.vectorOptions.headScale == parent.recipe.vectorOptions.headScale)
    #expect(model.sketches.entries.map(\.id) == [parent.id])
    #expect(model.sketches.labels.isEmpty)
    await model.shutdown()
  }

  @Test("parent and branch navigation restore exact programs without rendering or recent photos")
  func exactNavigation() async throws {
    let renderer = ExplorationRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let parent = try #require(model.selectedCandidate)
    model.moreLikeThis(seed: 10)
    await model.awaitRendering()
    let first = try #require(model.selectedCandidate)
    model.selectHistory(parent.id)
    model.moreLikeThis(seed: 11)
    await model.awaitRendering()
    let second = try #require(model.selectedCandidate)
    model.removePhoto(parent.photoID, strokeStyle: pen)
    let calls = await renderer.requests.count
    model.selectHistory(parent.id)
    model.renderIfConfigurationChanged(strokeStyle: pen)
    #expect(model.selectedCandidate?.program == parent.program)
    #expect(Set(model.explorationBranches.map(\.id)) == [first.id, second.id])
    model.selectHistory(first.id)
    #expect(model.selectedCandidate?.id == first.id)
    #expect(model.selectedCandidate?.program == first.program)
    model.historyParent()
    #expect(model.selectedCandidate?.id == parent.id)
    model.historyBack()
    #expect(model.selectedCandidate?.id == first.id)
    model.historyForward()
    #expect(model.selectedCandidate?.id == parent.id)
    #expect(await renderer.requests.count == calls)
    #expect(model.recentPhotos.isEmpty)
    #expect(model.sketches.entries.isEmpty)
    model.selectHistory(second.id)
    #expect(model.keepSelection() == nil)
    #expect(model.sketches.entries.map(\.id) == [second.id])
    #expect(model.sketches.entries.first?.candidate.lineage.parentID == parent.id)
    await model.shutdown()
  }

  @Test("a new photo never inherits another restored source's analyzed raster")
  func distinctSourceAnalysis() async throws {
    let renderer = ExplorationRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let original = try #require(model.selectedCandidate)
    model.selectHistory(original.id)
    model.setPhoto(Data([2]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let request = try #require(await renderer.requests.last)
    #expect(request.data == Data([2]))
    #expect(request.cachedRaster == nil)
    #expect(model.selectedCandidate?.sourceData == Data([2]))
    #expect(model.selectedCandidate?.raster.provenance != original.raster.provenance)
    await model.shutdown()
  }

  @Test("a reloaded archived parent enters exact Back history before local exploration")
  func archivedParentBack() async throws {
    let renderer = ExplorationRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    let parent = try portraitPersistenceCandidate()
    _ = model.sketches.retain(candidate: parent, reason: .shortlisted)
    #expect(model.history.candidates.isEmpty)
    model.moreLikeThis(seed: 71)
    await model.awaitRendering()
    #expect(model.history.canGoBack)
    #expect(model.selectedCandidate?.lineage.parentID == parent.id)
    let calls = await renderer.requests.count
    model.historyBack()
    #expect(model.selectedCandidate?.id == parent.id)
    #expect(model.selectedCandidate?.program == parent.program)
    #expect(await renderer.requests.count == calls)
    await model.shutdown()
  }

  @Test("local exploration supersedes a held import and the old acquisition cannot replace its source")
  func localSupersedesAcquisition() async throws {
    let acquirer = ExplorationHeldAcquirer()
    let model = PortraitStudioModel(renderer: ExplorationRenderer(), photoAcquirer: acquirer)
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let parent = try #require(model.selectedCandidate)
    let importing = Task { await model.importPhoto(URL(fileURLWithPath: "/unused/held-exploration-fixture"), strokeStyle: pen) }
    await acquirer.waitUntilStarted()
    model.moreLikeThis(seed: 72)
    await acquirer.release()
    await importing.value
    let child = try #require(model.selectedCandidate)
    #expect(child.sourceData == parent.sourceData)
    #expect(child.lineage.parentID == parent.id)
    #expect(child.proposal?.seed == 72)
    #expect(!model.recentPhotos.contains(where: { $0.data == Data([2]) }))
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    await model.shutdown()
  }

  @Test("DS02 candidates without additive metadata retain their content identity and exact legacy pose")
  func legacyCandidateMigration() async throws {
    let legacy = try portraitPersistenceCandidate()
    var object = try #require(JSONSerialization.jsonObject(with: PortraitCandidateCoding.encoder().encode(legacy)) as? [String: Any])
    object.removeValue(forKey: "pose")
    object.removeValue(forKey: "proposal")
    let decoded = try JSONDecoder().decode(PortraitCandidate.self, from: JSONSerialization.data(withJSONObject: object))
    try decoded.validateIntegrity()
    #expect(decoded.id == legacy.id)
    #expect(decoded.pose == nil)
    #expect(decoded.proposal == nil)
    #expect(decoded.renderPose == .front)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("portrait-ds03-migration-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let writer = PortraitCandidateStore(directoryURL: directory)
    try await writer.save(snapshot: .init(entries: [.init(candidate: decoded, reasons: [.init(reason: .shortlisted)])]))
    let loaded = await PortraitCandidateStore(directoryURL: directory).load()
    #expect(loaded.canWrite)
    #expect(loaded.archive.entries.first?.candidate.id == legacy.id)
    #expect(loaded.archive.entries.first?.candidate.renderPose == .front)
  }
}

private actor ExplorationRenderer: PortraitRendering {
  private(set) var requests: [PortraitRenderRequest] = []
  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult {
    requests.append(request)
    let fixture = portraitTestRaster()
    let raster = request.cachedRaster ?? PortraitRaster(width: fixture.width, height: fixture.height,
      luminance: fixture.luminance, provenance: "source-\(request.data.first ?? 0)", analysisSummary: "fixture")
    return PortraitRenderResult(raster: raster, program: try PortraitVectorizer.program(
      from: raster, pose: request.pose, style: request.style, strokeStyle: request.strokeStyle,
      vectorOptions: request.vectorOptions))
  }
}

private actor ExplorationHeldAcquirer: PortraitPhotoAcquiring {
  private var continuation: CheckedContinuation<Void, Never>?
  func acquire(_ input: PortraitPhotoInput) async throws -> PortraitAcquiredPhoto {
    await withCheckedContinuation { continuation = $0 }
    return PortraitAcquiredPhoto(data: Data([2]), sourcePixelExtent: nil)
  }
  func waitUntilStarted() async {
    while continuation == nil { await Task.yield() }
  }
  func release() { continuation?.resume(); continuation = nil }
}
