import AppKit
import Foundation
import ImageIO
import PlotterModel
import SwiftUI
import Testing
@testable import PlotterApp

@Suite("Persistent portrait attempt browser", .serialized)
@MainActor
struct PortraitAttemptHistoryTests {
  @Test("restart retains exact payloads, thumbnail, feedback revisions and source-free named styles")
  func restartAndFeedback() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("portrait-history-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let collection = PortraitSketchCollection(store: .init(directoryURL: directory))
    let candidate = try portraitPersistenceCandidate()
    let record = try PortraitAttemptRecord.prepare(candidate: candidate, pen: portraitTestStyle())
    collection.recordAttempt(candidate, record: record)
    #expect(collection.selectedID == nil)
    #expect(collection.sketches.isEmpty)
    #expect(collection.attempts.first?.attempt?.feedback == .unknown)
    collection.setFeedback(.promising, for: candidate.id)
    collection.setFeedback(.rejected, for: candidate.id)
    collection.setFeedback(.unknown, for: candidate.id)
    collection.saveStyle(name: "My ink", recipe: candidate.recipe)
    await collection.awaitPersistence()
    let restored = PortraitSketchCollection(store: .init(directoryURL: directory))
    await restored.load()
    let exact = try #require(restored.attempts.first)
    #expect(try PortraitCandidateCoding.encoder().encode(exact.candidate) == PortraitCandidateCoding.encoder().encode(candidate))
    #expect(exact.attempt?.thumbnailPNG == record.thumbnailPNG)
    #expect(exact.attempt?.feedbackRevisions.map(\.value) == [.promising, .rejected, .unknown])
    #expect(restored.savedStyles.first?.recipe == candidate.recipe)
    #expect(restored.savedStyles.first?.name == "My ink")
    #expect(restored.selectedID == nil)
    #expect(restored.sketches.isEmpty)
    #expect(restored.rejectedProposalIdentities.isEmpty)
  }

  @Test("rejection ignores seed and ancestry and the latest explicit equivalent feedback reverses suppression")
  func rejectedEquivalentRecipe() throws {
    let first = try portraitPersistenceCandidate(seed: 1)
    let alias = try portraitPersistenceCandidate(seed: 2, lineage: .init(parentID: first.id,
      parentProgramHash: first.program.contentHash.description, parentRecipe: first.recipe,
      ancestryGroupID: first.lineage.ancestryGroupID))
    #expect(first.id != alias.id)
    let a = try PortraitAttemptRecord.prepare(candidate: first, pen: portraitTestStyle())
    let b = try PortraitAttemptRecord.prepare(candidate: alias, pen: portraitTestStyle())
    #expect(a.proposalIdentity == b.proposalIdentity)
    let collection = PortraitSketchCollection()
    collection.recordAttempt(first, record: a); collection.recordAttempt(alias, record: b)
    collection.setFeedback(.rejected, for: first.id)
    #expect(collection.rejectedProposalIdentities == [a.proposalIdentity])
    collection.setFeedback(.unknown, for: alias.id)
    #expect(collection.rejectedProposalIdentities.isEmpty)
    collection.setFeedback(.rejected, for: first.id)
    collection.setFeedback(.promising, for: alias.id)
    #expect(collection.rejectedProposalIdentities.isEmpty)
    collection.setFeedback(.rejected, for: alias.id)
    collection.setFeedback(.unknown, for: alias.id)
    #expect(collection.rejectedProposalIdentities.isEmpty)
    #expect(collection.entries.count == 2)
    #expect(collection.sketches.isEmpty)
  }

  @Test("clear keeps current, promising and saved; deletion tombstones block late exact generation")
  func clearAndLateGeneration() async throws {
    let collection = PortraitSketchCollection()
    let candidates = try (1...5).map { try portraitPersistenceCandidate(seed: UInt64($0)) }
    for candidate in candidates {
      collection.recordAttempt(candidate, record: try .prepare(candidate: candidate, pen: portraitTestStyle()))
    }
    collection.setFeedback(.promising, for: candidates[0].id)
    #expect(collection.retain(candidate: candidates[1], reason: .shortlisted) == nil)
    collection.setFeedback(.rejected, for: candidates[3].id)
    collection.clearUnkeptHistory(preserving: candidates[2].id)
    #expect(Set(collection.entries.map(\.id)) == Set(candidates.prefix(3).map(\.id)))
    collection.recordAttempt(candidates[3], record: try .prepare(candidate: candidates[3], pen: portraitTestStyle()))
    #expect(!collection.entries.contains { $0.id == candidates[3].id })
    collection.deleteSource(candidates[0].sourceSHA256)
    collection.recordAttempt(candidates[4], record: try .prepare(candidate: candidates[4], pen: portraitTestStyle()))
    #expect(collection.entries.isEmpty)
    await collection.awaitPersistence()
  }

  @Test("history and feedback use retained payloads without invoking a renderer, including after restart")
  func exactNavigationAndBranch() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("portrait-navigation-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer, candidateStore: .init(directoryURL: directory))
    let pen = try portraitTestStyle()
    model.style = .contours
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let original = try #require(model.selectedCandidate)
    model.vectorOptions.tonalStrength = 1.8
    model.renderIfConfigurationChanged(strokeStyle: pen)
    await model.awaitRendering()
    let branch = try #require(model.selectedCandidate)
    #expect(branch.lineage.parentID == original.id)
    let calls = await renderer.requests.count
    model.inspectAttempt(original.id, strokeStyle: pen)
    model.toggleFeedback(.promising, candidate: original)
    model.toggleFeedback(.promising, candidate: original)
    #expect(model.selectedCandidate?.program == original.program)
    #expect(model.selectedCandidate?.sourceData == original.sourceData)
    #expect(model.feedback(for: original) == .unknown)
    #expect(await renderer.requests.count == calls)
    #expect(!model.isProcessing && !model.isExploring)
    await model.shutdown()
    let restored = PortraitStudioModel(renderer: renderer, candidateStore: .init(directoryURL: directory))
    await restored.loadArchive()
    restored.inspectAttempt(branch.id, strokeStyle: pen)
    #expect(restored.selectedCandidate?.id == branch.id)
    #expect(restored.selectedCandidate?.program == branch.program)
    #expect(restored.selectedPhotoID == branch.photoID)
    #expect(await renderer.requests.count == calls)
    await restored.shutdown()
  }

  @Test("deleting a nonselected source prunes Back and equivalent recent source aliases")
  func deletingNonselectedSource() async throws {
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer, explorationSeed: 918)
    let pen = try portraitTestStyle()
    model.style = .contours
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    model.nextPortrait(strokeStyle: pen)
    await model.awaitRendering()
    let a = try #require(model.selectedCandidate)
    // Build a separately identified source B and retain A as Back.
    model.setPhoto(Data([2]), for: .left, strokeStyle: pen)
    model.selectPhoto(try #require(model.recentPhotos.last?.id), strokeStyle: pen)
    await model.awaitRendering()
    let b = try #require(model.selectedCandidate)
    model.inspectAttempt(a.id, strokeStyle: pen)
    model.nextPortrait(strokeStyle: pen)
    await model.awaitRendering()
    model.inspectAttempt(b.id, strokeStyle: pen)
    #expect(model.canGoBackExploration)
    model.deleteRetainedSource(a.photoID, strokeStyle: pen)
    model.previousPortrait()
    #expect(model.selectedCandidate?.sourceSHA256 != a.sourceSHA256)
    #expect(!model.browsablePhotos.contains { $0.id == a.photoID })
    #expect(!model.sketches.entries.contains { $0.candidate.sourceSHA256 == a.sourceSHA256 })
    await model.shutdown()
  }

  @Test("legacy saved Imaginations expose their retained source before any attempt-history migration")
  func legacySourceDiscovery() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("portrait-legacy-sources-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let collection = PortraitSketchCollection(store: .init(directoryURL: directory))
    let legacy = try portraitPersistenceCandidate()
    #expect(collection.retain(candidate: legacy, reason: .shortlisted) == nil)
    await collection.awaitPersistence()
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer, candidateStore: .init(directoryURL: directory))
    await model.loadArchive()
    #expect(model.sketches.attempts.isEmpty)
    #expect(model.browsablePhotos.map(\.id) == [legacy.photoID])
    #expect(await renderer.requests.isEmpty)
    model.selectPhoto(legacy.photoID, strokeStyle: try portraitTestStyle())
    await model.awaitRendering()
    #expect(model.selectedCandidate?.sourceData == legacy.sourceData)
    #expect(model.selectedCandidate?.photoID == legacy.photoID)
    #expect(model.sketches.sketches.map(\.id) == [legacy.id])
    await model.shutdown()
  }

  @Test("an explicit identical rerender after deletion survives restart without reviving stale instances")
  func regenerateDeletedIdentity() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("portrait-regenerate-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer, candidateStore: .init(directoryURL: directory))
    let pen = try portraitTestStyle()
    model.style = .contours
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let original = try #require(model.selectedCandidate)
    model.deleteAttempt(original.id)
    model.selectPhoto(original.photoID, strokeStyle: pen)
    await model.awaitRendering()
    let regenerated = try #require(model.selectedCandidate)
    #expect(regenerated.id == original.id)
    #expect(regenerated.createdAt > original.createdAt)
    #expect(model.currentProgram == original.program)
    #expect(model.sketches.attempts.contains { $0.id == original.id && $0.candidate.createdAt == regenerated.createdAt })
    #expect(model.keepSelection() == nil)
    var staleHandoffCalled = false
    #expect(await model.acceptProjection(original, perform: { staleHandoffCalled = true; return nil }) != nil)
    #expect(!staleHandoffCalled)
    model.deleteRetainedSource(regenerated.photoID, strokeStyle: pen)
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let reimported = try #require(model.selectedCandidate)
    #expect(reimported.id == original.id)
    #expect(reimported.createdAt > regenerated.createdAt)
    #expect(reimported.photoID != original.photoID)
    await model.shutdown()
    let restored = PortraitStudioModel(renderer: renderer, candidateStore: .init(directoryURL: directory))
    await restored.loadArchive()
    restored.inspectAttempt(reimported.id, strokeStyle: pen)
    #expect(restored.selectedCandidate?.createdAt == reimported.createdAt)
    #expect(restored.selectedCandidate?.program == reimported.program)
    #expect(await restored.acceptProjection(original, perform: { staleHandoffCalled = true; return nil }) != nil)
    #expect(!staleHandoffCalled)
    await restored.shutdown()
  }

  @Test("clearing unkept history during a selected edit preserves the displayed completed drawing")
  func clearWhileSelectedRenderPending() async throws {
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.style = .contours
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let displayed = try #require(model.selectedCandidate)
    await renderer.holdNext()
    model.vectorOptions.tonalStrength = 1.8
    model.renderIfConfigurationChanged(strokeStyle: pen)
    try await renderer.waitUntilHeld()
    #expect(model.isProcessing)
    #expect(model.selectedCandidate == nil)
    model.clearUnkeptHistory()
    #expect(model.sketches.attempts.contains { $0.id == displayed.id })
    #expect(!model.sketches.tombstones.contains { $0.affectedCandidateIDs.contains(displayed.id) })
    await renderer.release()
    await model.awaitRendering()
    #expect(model.selectedCandidate?.lineage.parentID == displayed.id)
    #expect(model.sketches.attempts.contains { $0.id == displayed.id })
    await model.shutdown()
  }

  @Test("retained thumbnail orientation matches the drawing preview for asymmetric geometry")
  func thumbnailOrientation() throws {
    let referencePen = try portraitTestStyle()
    let pen = try StrokeStyle(nominalLineWidth: 2, penProfileID: referencePen.penProfileID)
    let program = try DrawingProgram(id: ProgramID(UUID()), fieldExtent: .init(width: 100, height: 100),
      strokes: [LogicalStroke(id: StrokeID(UUID()), path: Polyline(points: [Point2(x: 15, y: 80), Point2(x: 80, y: 80)]), style: pen, ordering: 0)],
      source: DrawingSourceProvenance(kind: "fixture", sourceIdentifier: "asymmetric-top"))
    let data = try PortraitAttemptThumbnail.render(program)
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let thumbnail = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let preview = PortraitPlanePreviewSource().resolve(program: program, nominalWidth: pen.nominalLineWidth)
    let expected = try #require(ImageRenderer(content: PortraitPlaneProgramPreview(preview: preview)
      .frame(width: 192, height: 192).background(.white)).cgImage)
    let first = try inkCentroidY(thumbnail), second = try inkCentroidY(expected)
    #expect(abs(first - second) < 0.07)
    if let output = ProcessInfo.processInfo.environment["PORTRAIT_BROWSER_THUMBNAIL_PATH"] {
      try data.write(to: URL(fileURLWithPath: output))
    }
  }

  private func inkCentroidY(_ image: CGImage) throws -> Double {
    let width = image.width, height = image.height
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    try bytes.withUnsafeMutableBytes { buffer in
      let context = try #require(CGContext(data: buffer.baseAddress, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    var total = 0.0, moment = 0.0
    for y in 0..<height { for x in 0..<width {
      let index = (y * width + x) * 4
      if bytes[index] < 100 && bytes[index + 1] < 100 && bytes[index + 2] < 100 {
        total += 1; moment += Double(y)
      }
    } }
    try #require(total > 0)
    return moment / total / Double(height)
  }
}
