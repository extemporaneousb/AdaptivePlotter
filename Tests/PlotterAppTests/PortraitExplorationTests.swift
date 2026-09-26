import Foundation
import PlotterModel
import Testing

@testable import PlotterApp

@Suite("Portrait exploration ownership")
@MainActor
struct PortraitExplorationTests {
  @Test("a new source leaves retired archive styles and preserves the material snapshot")
  func newSourceUsesActiveStyle() async throws {
    let model = PortraitStudioModel(renderer: ExplorationTestRenderer())
    let material = try PortraitMaterialContext(
      profile: .init(name: "Retained material", nominalWidthMM: 0.4), drawingHeightMM: 100)
    model.style = .hatch
    model.vectorOptions.materialContext = material
    model.setPhoto(Data([1]), for: .front, strokeStyle: try portraitTestStyle())
    #expect(model.style == .contours)
    #expect(model.vectorOptions.materialContext == material)
    #expect(model.vectorOptions.hatchSpacing == PortraitVectorOptions().hatchSpacing)
    await model.awaitRendering()
    #expect(model.selectedCandidate?.recipe.style == .contours)
    await model.shutdown()
  }

  @Test("source removal cannot be undone by a renderer that ignores cancellation")
  func removedSourceRejectsLateResult() async throws {
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    model.style = .contours
    model.vectorOptions = PortraitVectorOptions()
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let photo = try #require(model.selectedPhotoID)
    await renderer.holdNext()
    model.nextPortrait(strokeStyle: pen)
    try await renderer.waitUntilHeld()
    model.removePhoto(photo, strokeStyle: pen)
    await renderer.release()
    await model.awaitRendering()
    #expect(model.selectedCandidate == nil)
    #expect(!model.canGoBackExploration)
    #expect(model.recentPhotos.isEmpty)
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    await model.shutdown()
  }

  @Test("source replacement joins old work and publishes only the new source")
  func sourceReplacementRejectsLateResult() async throws {
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    model.style = .contours
    model.vectorOptions = PortraitVectorOptions()
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    await renderer.holdNext()
    model.nextPortrait(strokeStyle: pen)
    try await renderer.waitUntilHeld()
    model.setPhoto(Data([2]), for: .front, strokeStyle: pen)
    await renderer.release()
    await model.awaitRendering()
    #expect(model.selectedCandidate?.sourceData == Data([2]))
    #expect(!model.canGoBackExploration)
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    await model.shutdown()
  }

  @Test("explicit handoff freezes the chosen program while exploration continues")
  func handoffIsolation() async throws {
    let model = PortraitStudioModel(renderer: ExplorationTestRenderer())
    model.style = .contours
    model.vectorOptions = PortraitVectorOptions()
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    model.nextPortrait(strokeStyle: pen)
    await model.awaitRendering()
    let accepted = try #require(model.selectedCandidate)
    #expect(await model.acceptProjection(accepted, perform: { nil }) == nil)
    model.nextPortrait(strokeStyle: pen)
    await model.awaitRendering()
    #expect(model.selectedCandidate?.id != accepted.id)
    #expect(try PortraitCandidateCoding.encoder().encode(#require(model.projectedCandidate))
      == PortraitCandidateCoding.encoder().encode(accepted))
    #expect(model.sketches.entries.first(where: { $0.id == accepted.id })?.candidate.program == accepted.program)
    #expect(model.sketches.sketches.count == 1)
    await model.shutdown()
  }

  @Test("legacy archive entries without exploration receipts remain readable")
  func legacyArchiveWithoutTrace() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("portrait-legacy-grid-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = PortraitStudioModel(renderer: ExplorationTestRenderer())
    model.style = .contours
    model.vectorOptions = PortraitVectorOptions()
    model.setPhoto(Data([1]), for: .front, strokeStyle: try portraitTestStyle())
    await model.awaitRendering()
    let candidate = try #require(model.selectedCandidate)
    let archive = PortraitCandidateArchive(entries: [.init(candidate: candidate, reasons: [])])
    try await PortraitCandidateStore(directoryURL: directory).save(snapshot: archive)
    let loaded = await PortraitCandidateStore(directoryURL: directory).load()
    #expect(loaded.canWrite)
    #expect(loaded.archive.entries.first?.exploration == nil)
    #expect(loaded.archive.entries.first?.candidate.id == candidate.id)
    await model.shutdown()
  }

}

actor ExplorationTestRenderer: PortraitRendering {
  private(set) var requests: [PortraitRenderRequest] = []
  private var holdsNext = false
  private var heldRequestNumber: Int?
  private var rejectsFuture = false
  private var noLinesRemaining = 0
  private var releaseWaiter: CheckedContinuation<Void, Never>?

  func holdNext() { holdsNext = true }
  func holdRequest(number: Int) { heldRequestNumber = number }
  func rejectFutureRequests() { rejectsFuture = true }
  func rejectNextAsNoLines(_ count: Int) { noLinesRemaining = count }
  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult {
    requests.append(request)
    if holdsNext || heldRequestNumber == requests.count {
      holdsNext = false
      heldRequestNumber = nil
      await withCheckedContinuation { releaseWaiter = $0 }
    }
    if rejectsFuture { throw PortraitDrawingError.unreadableImage }
    if noLinesRemaining > 0 { noLinesRemaining -= 1; throw PortraitDrawingError.noLines }
    let raster = request.cachedRaster ?? portraitTestRaster()
    // Deliberately ignore cancellation to test publication ownership.
    let program = try await Task.detached {
      try PortraitVectorizer.program(from: raster, pose: request.pose, style: request.style,
        strokeStyle: request.strokeStyle, vectorOptions: request.vectorOptions)
    }.value
    return PortraitRenderResult(raster: raster, program: program)
  }
  func waitUntilHeld() async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while releaseWaiter == nil {
      try #require(ContinuousClock.now < deadline, "Exploration worker never reached the held render.")
      try await Task.sleep(for: .milliseconds(1))
    }
  }
  func release() { releaseWaiter?.resume(); releaseWaiter = nil }
}
