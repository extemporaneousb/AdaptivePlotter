import Foundation
import Testing

@testable import PlotterApp

@Suite("Exact transient portrait exploration")
@MainActor
struct PortraitExplorationHistoryTests {
  @Test("branch and parent navigation recover exact completed program and analysis payloads")
  func branchRecovery() throws {
    let history = PortraitExplorationHistory()
    let root = try portraitPersistenceCandidate(seed: 1)
    let first = try child(of: root, seed: 2)
    let second = try child(of: root, seed: 3)
    history.record(root)
    history.record(first)
    #expect(history.parent?.id == root.id)
    #expect(history.goToParent()?.id == root.id)
    history.record(second)
    #expect(history.goBack()?.id == root.id)
    #expect(history.children.map(\.id) == [first.id, second.id])
    #expect(history.goForward()?.id == second.id)
    let recovered = try #require(history.select(first.id))
    #expect(recovered.program == first.program)
    #expect(recovered.sourceData == first.sourceData)
    #expect(try PortraitCandidateCoding.encoder().encode(recovered.raster)
      == PortraitCandidateCoding.encoder().encode(first.raster))
    #expect(recovered.lineage.parentProgramHash == root.program.contentHash.description)
  }

  @Test("duplicate identities navigate without replacing first provenance and metadata")
  func duplicateIdentity() throws {
    let history = PortraitExplorationHistory()
    let original = try portraitPersistenceCandidate(seed: 1)
    let other = try portraitPersistenceCandidate(seed: 2)
    let duplicate = try PortraitCandidate(sourceData: original.sourceData,
      sourcePixelExtent: original.sourcePixelExtent, raster: original.raster,
      recipe: original.recipe, program: original.program, photoID: UUID(), captureSessionID: UUID(),
      createdAt: Date(timeIntervalSince1970: 0))
    #expect(duplicate.id == original.id)
    history.record(original)
    history.record(other)
    let bytes = history.retainedBytes
    history.record(duplicate)
    #expect(history.candidates.count == 2)
    #expect(history.retainedBytes == bytes)
    #expect(history.current?.photoID == original.photoID)
    #expect(history.current?.captureSessionID == original.captureSessionID)
    #expect(history.current?.createdAt == original.createdAt)
    #expect(history.goBack()?.id == other.id)
    #expect(history.goForward()?.id == original.id)
    #expect(history.goBack()?.id == other.id)
    history.record(try portraitPersistenceCandidate(seed: 3))
    #expect(!history.canGoForward)
  }

  @Test("count eviction removes dead navigation and branch payloads while preserving current")
  func countEviction() throws {
    let history = PortraitExplorationHistory(maximumCount: 2)
    let root = try portraitPersistenceCandidate(seed: 1)
    let first = try child(of: root, seed: 2)
    let second = try child(of: root, seed: 3)
    history.record(root)
    history.record(first)
    history.record(second)
    #expect(history.current?.id == second.id)
    #expect(history.candidates.map(\.id) == [first.id, second.id])
    #expect(history.parent == nil)
    #expect(history.goToParent() == nil)
    #expect(history.status?.contains("expired") == true)
    #expect(history.goBack()?.id == first.id)
    #expect(!history.canGoBack)
    #expect(history.goForward()?.id == second.id)
    #expect(history.select(root.id) == nil)
    #expect(history.current?.id == second.id)
    #expect(history.children.isEmpty)
  }

  @Test("byte limit and oversize rejection preserve honest exact recovery availability")
  func byteLimitAndOversize() throws {
    let first = try portraitPersistenceCandidate(seed: 1)
    let second = try portraitPersistenceCandidate(seed: 2)
    let size = max(try encodedSize(first), try encodedSize(second))
    let history = PortraitExplorationHistory(maximumCount: 24, maximumBytes: size)
    history.record(first)
    history.record(second)
    #expect(history.candidates.map(\.id) == [second.id])
    #expect(history.retainedBytes == (try encodedSize(second)))
    #expect(history.retainedBytes <= size)
    #expect(!history.canGoBack)
    let oversized = try PortraitCandidate(sourceData: Data(repeating: 7, count: size * 2),
      sourcePixelExtent: first.sourcePixelExtent, raster: first.raster,
      recipe: first.recipe, program: first.program, photoID: UUID(), captureSessionID: UUID())
    history.record(oversized)
    #expect(history.current?.id == second.id)
    #expect(history.candidates.count == 1)
    #expect(history.status?.contains("exceeds") == true)
    let empty = PortraitExplorationHistory(maximumBytes: 1)
    empty.record(first)
    #expect(empty.current == nil && empty.retainedBytes == 0)
  }

  @Test("navigation metadata stays bounded even when revisiting the same two payloads")
  func boundedVisits() throws {
    let history = PortraitExplorationHistory(maximumCount: 2)
    let first = try portraitPersistenceCandidate(seed: 1)
    let second = try portraitPersistenceCandidate(seed: 2)
    history.record(first)
    history.record(second)
    for index in 0..<100 { _ = history.select(index.isMultiple(of: 2) ? first.id : second.id) }
    var backwardVisits = 0
    while history.goBack() != nil { backwardVisits += 1 }
    #expect(backwardVisits == 7)
    #expect(history.candidates.count == 2)
    #expect(history.retainedBytes == (try encodedSize(first) + encodedSize(second)))
  }

  @Test("lineage is metadata only and browsing performs no qualified collection writes")
  func transientOnly() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("portrait-history-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let collection = PortraitSketchCollection(store: .init(directoryURL: directory))
    await collection.load()
    let history = PortraitExplorationHistory()
    let unrecordedRoot = try portraitPersistenceCandidate(seed: 1)
    let child = try child(of: unrecordedRoot, seed: 2)
    history.record(child)
    #expect(history.candidates.map(\.id) == [child.id])
    #expect(history.current?.lineage.parentID == unrecordedRoot.id)
    #expect(history.parent == nil && history.goToParent() == nil)
    #expect(history.status?.contains("unavailable") == true)
    #expect(collection.entries.isEmpty && collection.labels.isEmpty)
    #expect(collection.unresolvedMutations == 0)
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("index-v1.json").path))
  }

  private func child(of parent: PortraitCandidate, seed: UInt64) throws -> PortraitCandidate {
    try portraitPersistenceCandidate(seed: seed, lineage: .init(parentID: parent.id,
      parentProgramHash: parent.program.contentHash.description, parentRecipe: parent.recipe,
      ancestryGroupID: parent.captureSessionID))
  }

  private func encodedSize(_ candidate: PortraitCandidate) throws -> Int {
    try PortraitCandidateCoding.encoder().encode(candidate).count
  }
}
