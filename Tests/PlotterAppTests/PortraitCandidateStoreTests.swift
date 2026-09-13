import Foundation
import PlotterModel
import Testing

@testable import PlotterApp

@Suite("Qualified portrait candidate persistence")
@MainActor
struct PortraitCandidateStoreTests {
  @Test("restart restores owned exact source/raster, program, labels and all qualifying reasons")
  func restartAndTriggers() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let collection = PortraitSketchCollection(store: .init(directoryURL: directory))
    let candidate = try portraitPersistenceCandidate()
    #expect(collection.retain(candidate: candidate, reason: .shortlisted) == nil)
    #expect(collection.retain(candidate: candidate, reason: .projectionAccepted(acceptanceID: UUID())) == nil)
    #expect(collection.retain(candidate: candidate, reason: .physicalAttempt(attemptID: UUID())) == nil)
    #expect(collection.rate(candidate: candidate, rating: 1, scope: .screenSketch,
      presentation: try .init(drawingHeightMM: 175, inkWidthMM: 1.2)) == nil)
    await collection.awaitPersistence()
    #expect(collection.persistenceState == .saved)
    #expect(collection.unresolvedMutations == 0)
    let restored = PortraitSketchCollection(store: .init(directoryURL: directory))
    await restored.load()
    let retained = try #require(restored.entries.first)
    #expect(retained.id == candidate.id)
    #expect(retained.candidate.sourceData == candidate.sourceData)
    #expect(retained.candidate.program == candidate.program)
    #expect(try PortraitCandidateCoding.encoder().encode(retained.candidate.raster)
      == PortraitCandidateCoding.encoder().encode(candidate.raster))
    #expect(retained.reasons.count == 4)
    #expect(restored.labels.first?.rating == 1)
    #expect(restored.labels.first?.presentation.inkWidthMM == 1.2)
    #expect(restored.retainedBytes > candidate.sourceData.count)
  }

  @Test("generation and browsing snapshots alone never retain, and ancestors are metadata only")
  func transientAndAncestry() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let collection = PortraitSketchCollection(store: .init(directoryURL: directory))
    await collection.load()
    let ancestor = try portraitPersistenceCandidate(seed: 1)
    let child = try portraitPersistenceCandidate(seed: 2, lineage: .init(parentID: ancestor.id,
      parentProgramHash: ancestor.program.contentHash.description, parentRecipe: ancestor.recipe,
      ancestryGroupID: ancestor.captureSessionID))
    for seed in 3...70 { _ = try portraitPersistenceCandidate(seed: UInt64(seed)) }
    #expect(collection.entries.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("index-v1.json").path))
    #expect(collection.retain(candidate: child, reason: .shortlisted) == nil)
    await collection.awaitPersistence()
    let result = await PortraitCandidateStore(directoryURL: directory).load()
    #expect(result.archive.entries.map(\.id) == [child.id])
    #expect(result.archive.entries[0].candidate.lineage.parentID == ancestor.id)
  }

  @Test("one source/raster blob serves many immutable labels and qualified candidates without FIFO")
  func dedupAndNoFIFO() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let collection = PortraitSketchCollection(store: .init(directoryURL: directory))
    let first = try portraitPersistenceCandidate(seed: 1)
    #expect(collection.rate(candidate: first, rating: 1, scope: .screenSketch,
      presentation: try .init(inkWidthMM: 0.4)) == nil)
    let initialLabel = try #require(collection.labels.first)
    #expect(collection.rate(candidate: first, rating: 5, scope: .screenSketch,
      presentation: try .init(inkWidthMM: 1.0)) == nil)
    for seed in 2...40 {
      #expect(collection.retain(candidate: try portraitPersistenceCandidate(seed: UInt64(seed)), reason: .shortlisted) == nil)
    }
    await collection.awaitPersistence()
    #expect(collection.entries.count == 40)
    #expect(collection.labels.count == 2)
    #expect(collection.labels[0] == initialLabel)
    #expect(collection.labels[1].previousRevisionID == initialLabel.id)
    #expect(collection.labels[0].presentation != collection.labels[1].presentation)
    let assets = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("assets").path)
    #expect(assets.count == 2)
    let restored = await PortraitCandidateStore(directoryURL: directory).load()
    #expect(restored.canWrite)
    #expect(restored.archive.entries.count == 40)
  }

  @Test("partial save reports retained staging/orphan blobs without inventing candidates")
  func interruptedSave() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let assets = directory.appendingPathComponent("assets")
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
    let source = Data([17, 18])
    try source.write(to: assets.appendingPathComponent(PortraitCandidateCoding.digest(source)))
    try Data("unfinished".utf8).write(to: directory.appendingPathComponent("staging-interrupted.json"))
    let result = await PortraitCandidateStore(directoryURL: directory).load()
    #expect(result.canWrite)
    #expect(result.archive.entries.isEmpty)
    #expect(result.issues.contains { $0.contains("Interrupted save") })
    #expect(result.issues.contains { $0.contains("Unassociated asset") })
  }

  @Test("corrupt index blocks mutation and survives; repairing it permits ordered retry")
  func corruptedIndexRecovery() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = try portraitPersistenceCandidate(seed: 1)
    let writer = PortraitSketchCollection(store: .init(directoryURL: directory))
    _ = writer.retain(candidate: first, reason: .shortlisted)
    await writer.awaitPersistence()
    let index = directory.appendingPathComponent("index-v1.json")
    let validIndex = try Data(contentsOf: index), corruptIndex = Data("broken".utf8)
    try corruptIndex.write(to: index)
    let collection = PortraitSketchCollection(store: .init(directoryURL: directory))
    let second = try portraitPersistenceCandidate(seed: 2)
    _ = collection.retain(candidate: second, reason: .shortlisted)
    await collection.awaitPersistence()
    #expect(collection.unresolvedMutations == 1)
    #expect(collection.entries.contains { $0.id == second.id })
    #expect(try Data(contentsOf: index) == corruptIndex)
    if case .failed = collection.persistenceState {} else { Issue.record("corruption was not visible") }
    try validIndex.write(to: index)
    collection.retryPersistence()
    await collection.awaitPersistence()
    #expect(collection.persistenceState == .saved)
    #expect(collection.entries.count == 2)
    #expect(collection.unresolvedMutations == 0)
  }

  @Test("missing asset gives partial healthy recovery and blocks destructive index replacement")
  func missingAsset() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let candidate = try portraitPersistenceCandidate()
    let collection = PortraitSketchCollection(store: .init(directoryURL: directory))
    _ = collection.retain(candidate: candidate, reason: .shortlisted)
    await collection.awaitPersistence()
    let index = directory.appendingPathComponent("index-v1.json")
    let indexBytes = try Data(contentsOf: index)
    let asset = directory.appendingPathComponent("assets").appendingPathComponent(candidate.sourceSHA256)
    try FileManager.default.removeItem(at: asset)
    let store = PortraitCandidateStore(directoryURL: directory)
    let result = await store.load()
    #expect(!result.canWrite)
    #expect(result.issues.contains { $0.contains(candidate.id) })
    do { try await store.save(snapshot: .init()); Issue.record("damaged archive was overwritten") } catch {}
    #expect(try Data(contentsOf: index) == indexBytes)
  }

  @Test("disk failure preserves current work and retries retain, rate and delete in order")
  func diskFailureAndRetry() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data([1]).write(to: directory)
    let collection = PortraitSketchCollection(store: .init(directoryURL: directory))
    let deleted = try portraitPersistenceCandidate(seed: 1), kept = try portraitPersistenceCandidate(seed: 2)
    _ = collection.retain(candidate: deleted, reason: .shortlisted)
    _ = collection.rate(candidate: kept, rating: 1, scope: .screenSketch, presentation: try .init())
    collection.remove(deleted.id)
    await collection.awaitPersistence()
    #expect(collection.unresolvedMutations == 3)
    #expect(collection.entries.map(\.id) == [kept.id])
    #expect(collection.labels.count == 1)
    try FileManager.default.removeItem(at: directory)
    collection.retryPersistence()
    await collection.awaitPersistence()
    #expect(collection.persistenceState == .saved)
    let result = await PortraitCandidateStore(directoryURL: directory).load()
    #expect(result.archive.entries.map(\.id) == [kept.id])
    #expect(result.archive.tombstones.contains { $0.identity == deleted.id })
  }

  @Test("source deletion removes owned payloads but preserves label identities and tombstones")
  func explicitSourceDeletion() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let collection = PortraitSketchCollection(store: .init(directoryURL: directory))
    let candidate = try portraitPersistenceCandidate()
    _ = collection.rate(candidate: candidate, rating: 4, scope: .screenSketch, presentation: try .init())
    await collection.awaitPersistence()
    let labelID = try #require(collection.labels.first?.id)
    collection.deleteSource(candidate.sourceSHA256)
    await collection.awaitPersistence()
    let restored = await PortraitCandidateStore(directoryURL: directory).load()
    #expect(restored.archive.entries.isEmpty)
    #expect(restored.archive.labels.first?.id == labelID)
    #expect(restored.archive.tombstones.first?.identity == candidate.sourceSHA256)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("assets").path).isEmpty)
  }

  @Test("candidate deletion retains shared blobs for surviving candidates")
  func sharedAssetDeletion() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let collection = PortraitSketchCollection(store: .init(directoryURL: directory))
    let first = try portraitPersistenceCandidate(seed: 1), second = try portraitPersistenceCandidate(seed: 2)
    _ = collection.retain(candidate: first, reason: .shortlisted)
    _ = collection.retain(candidate: second, reason: .shortlisted)
    await collection.awaitPersistence()
    collection.remove(first.id)
    await collection.awaitPersistence()
    let restored = await PortraitCandidateStore(directoryURL: directory).load()
    #expect(restored.canWrite)
    #expect(restored.archive.entries.map(\.id) == [second.id])
    #expect(restored.archive.entries.first?.candidate.sourceData == second.sourceData)
  }

  @Test("restart resumes committed deletion without an unrelated authoring mutation")
  func interruptedDeletionCleanup() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let candidate = try portraitPersistenceCandidate()
    let collection = PortraitSketchCollection(store: .init(directoryURL: directory))
    _ = collection.retain(candidate: candidate, reason: .shortlisted)
    await collection.awaitPersistence()
    collection.deleteSource(candidate.sourceSHA256)
    await collection.awaitPersistence()
    // Recreate the exact disk state between committed index and blob cleanup.
    let assets = directory.appendingPathComponent("assets")
    let source = assets.appendingPathComponent(candidate.sourceSHA256)
    let raster = assets.appendingPathComponent(candidate.rasterSHA256)
    try candidate.sourceData.write(to: source)
    try PortraitCandidateCoding.encoder().encode(candidate.raster).write(to: raster)
    let restored = PortraitSketchCollection(store: .init(directoryURL: directory))
    await restored.load()
    #expect(restored.entries.isEmpty)
    #expect(restored.persistenceState == .saved)
    #expect(restored.unresolvedMutations == 0)
    #expect(!FileManager.default.fileExists(atPath: source.path))
    #expect(!FileManager.default.fileExists(atPath: raster.path))
  }

  @Test("interrupted deletion failure stays visible with owned bytes and succeeds on retry")
  func interruptedDeletionRetry() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let candidate = try portraitPersistenceCandidate()
    let collection = PortraitSketchCollection(store: .init(directoryURL: directory))
    _ = collection.retain(candidate: candidate, reason: .shortlisted)
    await collection.awaitPersistence()
    collection.deleteSource(candidate.sourceSHA256)
    await collection.awaitPersistence()
    let source = directory.appendingPathComponent("assets").appendingPathComponent(candidate.sourceSHA256)
    try candidate.sourceData.write(to: source)
    let fault = PortraitDeletionFault()
    let restored = PortraitSketchCollection(store: .init(directoryURL: directory, removeAsset: { url in
      try fault.remove(url)
    }))
    await restored.load()
    if case .failed = restored.persistenceState {} else { Issue.record("Cleanup failure must remain visible") }
    #expect(restored.unresolvedMutations == 1)
    let bytesWithPendingSource = restored.retainedBytes
    fault.permitRemoval()
    restored.retryPersistence()
    await restored.awaitPersistence()
    #expect(restored.persistenceState == .saved)
    #expect(restored.unresolvedMutations == 0)
    #expect(restored.retainedBytes == bytesWithPendingSource - candidate.sourceData.count)
    #expect(!FileManager.default.fileExists(atPath: source.path))
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("portrait-candidate-tests-\(UUID().uuidString)")
  }
}

func portraitPersistenceCandidate(seed: UInt64 = 42,
  lineage: PortraitCandidateLineage? = nil) throws -> PortraitCandidate {
  let extent = try PortraitSourceCropExtent(widthPixels: 40, heightPixels: 40)
  let raster = PortraitRaster(width: 40, height: 40,
    luminance: Array(repeating: 0.1, count: 1600), provenance: "exact-owned-fixture",
    analysisSummary: "retained analysis", sourceCropExtent: extent)
  let recipe = PortraitStyleRecipe(id: "persistence-\(seed)", title: "Hatch \(seed)", seed: seed,
    style: .hatch, vectorOptions: .init(hatchSpacing: 8), analysisOptions: .init())
  let stroke = try StrokeStyle(nominalLineWidth: 0.8,
    penProfileID: PenProfileID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!))
  let program = try PortraitVectorizer.program(from: raster, pose: .front,
    style: recipe.style, strokeStyle: stroke, vectorOptions: recipe.vectorOptions)
  return try PortraitCandidate(sourceData: Data([1, 2, 3, 4]), sourcePixelExtent: extent,
    raster: raster, recipe: recipe, program: program, photoID: UUID(), captureSessionID: UUID(), lineage: lineage)
}

private final class PortraitDeletionFault: @unchecked Sendable {
  private let lock = NSLock()
  private var isPermitted = false
  func permitRemoval() { lock.withLock { isPermitted = true } }
  func remove(_ url: URL) throws {
    let permitted = lock.withLock { isPermitted }
    guard permitted else { throw CocoaError(.fileWriteNoPermission) }
    try FileManager.default.removeItem(at: url)
  }
}
