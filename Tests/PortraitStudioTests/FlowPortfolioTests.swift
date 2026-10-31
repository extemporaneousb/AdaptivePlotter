import Foundation
import PlotterModel
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary
import Testing

@Suite("Portable Flow artist portfolio", .serialized)
struct FlowPortfolioTests {
  @Test("Incremental rounds, exact displayed choices, partial ranks and pruning survive relocation")
  func portableRound() async throws {
    let root = temporary(), moved = temporary()
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: moved) }
    let store = try FlowPortfolioStore(directory: root, purpose: .validationFixture)
    let source = try await store.addSource(data: Self.photo, title: "Synthetic geometry")
    let round = try await store.beginRound(sourceID: source.id, recipes: [.standard, .standard], seed: 17)
    let program = try Self.program(), raster = Self.raster
    let preview = try DrawingPackageLibraryValidation.preview(program).bytes
    let a = try await store.completeCandidate(roundID: round.id, slot: 0, program: program, raster: raster, previewPNG: preview)
    let b = try await store.completeCandidate(roundID: round.id, slot: 1, program: program, raster: raster, previewPNG: preview)
    try await store.finishRound(round.id, displayOrder: [b.id, a.id], recommendedCandidateID: b.id)
    _ = try await store.applyPrune(candidateID: a.id, action: .modelProposal, indices: [0], modelID: "fixture-model",
      probabilities: [0.9, 0.1, 0.1, 0.1], threshold: 0.65, policy: "threshold-keep-one-v1")
    #expect(await store.snapshot().currentCandidateID == nil)
    try await store.chooseCandidate(a.id)
    let choice = try #require(await store.snapshot().choices.last)
    #expect(choice.offeredCandidateIDs == [b.id, a.id])
    #expect(choice.offeredItems.last?.removedIndices == [0])
    #expect(choice.selectedItemID == choice.offeredItems.last?.id)
    _ = try await store.applyPrune(candidateID: a.id, action: .restore, indices: [0])
    _ = try await store.applyPrune(candidateID: a.id, action: .remove, indices: [0, 1, 2, 3])
    let empty = try #require(await store.snapshot().latestPrune(candidateID: a.id))
    #expect(empty.removedIndices.count == 4)
    await #expect(throws: (any Error).self) { try await store.exportPackage(candidateID: a.id, revisionID: empty.id) }
    let undo = try await store.applyPrune(candidateID: a.id, action: .undo)
    #expect(undo.removedIndices.isEmpty)
    _ = try await store.applyPrune(candidateID: a.id, action: .redo)
    _ = try await store.applyPrune(candidateID: a.id, action: .undo)
    let target = try await store.applyPrune(candidateID: a.id, action: .completeTarget)
    let presentation = try await store.presentRanking(scope: .candidate(a.id), count: 3, seed: 42)
    let first = presentation.items[0].id, second = presentation.items[1].id
    _ = try await store.recordRanking(presentationID: presentation.id, orderedGroups: [[first]])
    let rank = try await store.recordRanking(presentationID: presentation.id, orderedGroups: [[first], [second]])
    #expect(await store.snapshot().rankings.count == 2)
    #expect(await store.snapshot().latestRankings == [rank])
    let frozen = try await store.freezeTrainingSnapshot()
    _ = try await store.applyPrune(candidateID: a.id, action: .remove, indices: [3])
    #expect(try await store.trainingDocument(snapshotID: frozen.id).latestPrune(candidateID: a.id)?.id == target.id)
    let expected = await store.snapshot()
    try FileManager.default.copyItem(at: root, to: moved)
    let reopened = try FlowPortfolioStore(directory: moved)
    #expect(await reopened.snapshot() == expected)
    #expect(await reopened.snapshot().purpose == .validationFixture)
    #expect(try await reopened.sourceData(source.id) == Self.photo)
    #expect(try await reopened.candidateProgram(a.id) == program)
    let exported = try DrawingPackageCodec.decode(await reopened.exportPackage(candidateID: a.id, revisionID: target.id))
    #expect(exported.source.bytes == Self.photo)
    #expect(exported.program.strokes == program.strokes)
    #expect(exported.artist.identifier == "adaptiveplotter.flow-artist")
  }

  @Test("One writer owns a portfolio and unrelated directories cannot be initialized")
  func ownership() async throws {
    let root = temporary(), unrelated = temporary()
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: unrelated) }
    let store = try FlowPortfolioStore(directory: root, purpose: .validationFixture)
    #expect(throws: (any Error).self) { try FlowPortfolioStore(directory: root) }
    #expect(await store.snapshot().revision == 0)
    try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
    let sentinel = unrelated.appendingPathComponent("historical-library.txt")
    try Data("preserve".utf8).write(to: sentinel)
    #expect(throws: (any Error).self) { try FlowPortfolioStore(directory: unrelated) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: unrelated.path) == ["historical-library.txt"])
  }

  @Test("Uncommitted files are ignored; corruption refuses reopening instead of resetting history")
  func recoveryIntegrity() async throws {
    let root = temporary(), copy = temporary(), corrupt = temporary()
    defer { for url in [root, copy, corrupt] { try? FileManager.default.removeItem(at: url) } }
    let store = try FlowPortfolioStore(directory: root, purpose: .validationFixture)
    let source = try await store.addSource(data: Self.photo, title: "Retained source")
    let round = try await store.beginRound(sourceID: source.id, recipes: [.standard])
    let expected = await store.snapshot()
    try FileManager.default.copyItem(at: root, to: copy)
    try Data("incomplete uncommitted bytes".utf8).write(to: copy.appendingPathComponent("records/.pending-interrupted"))
    let recovered = try FlowPortfolioStore(directory: copy)
    #expect(await recovered.snapshot() == expected)
    try await recovered.markInterruptedRounds()
    #expect(await recovered.snapshot().rounds.first?.id == round.id)
    #expect(await recovered.snapshot().rounds.first?.status == .interrupted)
    try FileManager.default.copyItem(at: root, to: corrupt)
    try Data("wrong source".utf8).write(to: corrupt.appendingPathComponent("objects/" + source.image.sha256))
    #expect(throws: (any Error).self) { try FlowPortfolioStore(directory: corrupt) }
    #expect(FileManager.default.fileExists(atPath: corrupt.appendingPathComponent("portfolio.json").path))
  }

  @Test("Failed commits preserve the acknowledged state and can be retried")
  func failedCommit() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try FlowPortfolioStore(directory: root, purpose: .validationFixture)
    let source = try await store.addSource(data: Self.photo, title: "Source")
    let before = await store.snapshot(), url = root.appendingPathComponent("portfolio.json")
    let head = try Data(contentsOf: url)
    try Data("{}".utf8).write(to: url)
    await #expect(throws: (any Error).self) { try await store.setSourceExcluded(sourceID: source.id, excluded: true) }
    #expect(await store.snapshot() == before)
    try head.write(to: url)
    try await store.setSourceExcluded(sourceID: source.id, excluded: true)
    #expect(await store.snapshot().sources.first?.excluded == true)
  }

  @Test("Refinement lineage and exact inherited masks do not create copied human labels")
  func inheritedSelection() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try FlowPortfolioStore(directory: root, purpose: .validationFixture)
    let source = try await store.addSource(data: Self.photo, title: "Source")
    let otherSource = try await store.addSource(data: Self.photo, title: "Other capture")
    let parentRound = try await store.beginRound(sourceID: source.id, recipes: [.standard])
    let program = try Self.program(), preview = try DrawingPackageLibraryValidation.preview(program).bytes
    let parent = try await store.completeCandidate(roundID: parentRound.id, slot: 0, program: program, raster: Self.raster, previewPNG: preview)
    try await store.finishRound(parentRound.id)
    let edit = try await store.applyPrune(candidateID: parent.id, action: .remove, indices: [1])
    await #expect(throws: (any Error).self) { try await store.beginRound(sourceID: otherSource.id, recipes: [.standard], parentCandidateID: parent.id) }
    let round = try await store.beginRound(sourceID: source.id, recipes: [.standard], parentCandidateID: parent.id)
    let child = try await store.completeCandidate(roundID: round.id, slot: 0, program: program, raster: Self.raster, previewPNG: preview)
    let inherited = try await store.applyPrune(candidateID: child.id, action: .inheritedSelection, indices: [1], inheritedFromRevisionID: edit.id)
    #expect(inherited.undoOperationIDs.isEmpty)
    #expect(inherited.modelID == nil)
    #expect(await store.snapshot().currentCandidateID == parent.id)
    await #expect(throws: (any Error).self) { try await store.applyPrune(candidateID: child.id, action: .remove, indices: [1]) }
    let frozen = try await store.freezeTrainingSnapshot()
    try await store.setExcluded(candidateID: parent.id, excluded: true)
    #expect(try await store.trainingDocument(snapshotID: frozen.id).candidates.first?.excluded == false)
  }

  @Test("One thousand autosaved edits produce bounded delta records and replay exactly")
  func incrementalScale() async throws {
    let root = temporary(), copy = temporary()
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: copy) }
    let store = try FlowPortfolioStore(directory: root, purpose: .validationFixture)
    let source = try await store.addSource(data: Self.photo, title: "Scale fixture")
    let round = try await store.beginRound(sourceID: source.id, recipes: [.standard])
    let program = try Self.program(), preview = try DrawingPackageLibraryValidation.preview(program).bytes
    let candidate = try await store.completeCandidate(roundID: round.id, slot: 0, program: program, raster: Self.raster, previewPNG: preview)
    try await store.finishRound(round.id)
    let started = Date()
    for index in 0..<1_000 {
      _ = try await store.applyPrune(candidateID: candidate.id, action: index.isMultiple(of: 2) ? .remove : .restore, indices: [0])
    }
    let elapsed = Date().timeIntervalSince(started)
    let records = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("records"), includingPropertiesForKeys: [.fileSizeKey])
    let sizes = try records.map { try $0.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 }
    #expect((sizes.max() ?? 0) < 15_000)
    #expect(sizes.reduce(0, +) < 3_000_000)
    try FileManager.default.copyItem(at: root, to: copy)
    let opened = try FlowPortfolioStore(directory: copy)
    #expect(await opened.snapshot() == store.snapshot())
    print("Flow portfolio 1000 edit receipt: \(elapsed)s; \(sizes.reduce(0,+)) operation bytes; max \(sizes.max() ?? 0) bytes")
  }

  @Test("Fit receipts bind frozen included examples; unavailable reports persist and cannot activate")
  func fitProvenance() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try FlowPortfolioStore(directory: root, purpose: .validationFixture)
    let empty = try await store.freezeTrainingSnapshot()
    let unavailable = FlowArtistTraining.fit(examples: [], rankings: [])
    let encoder = DrawingPackageCodec.encoder()
    let noModel = try await store.installFit(checkpoint: nil, report: encoder.encode(unavailable), snapshotID: empty.id)
    #expect(!noModel.hasCheckpoint)
    await #expect(throws: (any Error).self) { try await store.activateModel(noModel.id) }
    let source = try await store.addSource(data: Self.photo, title: "Training fixture")
    let round = try await store.beginRound(sourceID: source.id, recipes: [.standard])
    let program = try Self.program(), preview = try DrawingPackageLibraryValidation.preview(program).bytes
    let candidate = try await store.completeCandidate(roundID: round.id, slot: 0, program: program, raster: Self.raster, previewPNG: preview)
    try await store.finishRound(round.id)
    _ = try await store.applyPrune(candidateID: candidate.id, action: .remove, indices: [0])
    _ = try await store.applyPrune(candidateID: candidate.id, action: .completeTarget)
    let frozen = try await store.freezeTrainingSnapshot()
    let example = FlowArtistExample(id: candidate.id.uuidString, sourceGroupID: source.groupKeys.sorted().joined(separator: "|"), recipe: .standard,
      features: FlowArtistFeatures.drawing(recipe: .standard, program: program, raster: Self.raster),
      strokeFeatures: FlowArtistFeatures.strokes(recipe: .standard, program: program, raster: Self.raster),
      strokeLabels: program.strokes.indices.map { .init(index: $0, removed: $0 == 0, provenance: .completedMask) })
    let report = FlowArtistTraining.fit(examples: [example], rankings: [])
    let checkpoint = try #require(report.checkpoint)
    await #expect(throws: (any Error).self) {
      try await store.installFit(checkpoint: encoder.encode(checkpoint), report: encoder.encode(report), snapshotID: empty.id)
    }
    let fit = try await store.installFit(checkpoint: encoder.encode(checkpoint), report: encoder.encode(report), snapshotID: frozen.id)
    try await store.activateModel(fit.id)
    #expect(await store.snapshot().activeFitID == fit.id)
    try await store.activateModel(nil)
    #expect(await store.snapshot().activeFitID == nil)
    #expect(await store.snapshot().activations.last?.previousFitID == fit.id)
    #expect(try JSONDecoder().decode(FlowArtistFitReport.self, from: await store.fitReportData(fitID: noModel.id)) == unavailable)
  }

  @Test("Pair comparisons deduplicate exact anchors and masks and prefer unseen pairs")
  func usefulRankingPairs() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try FlowPortfolioStore(directory: root, purpose: .validationFixture)
    let source = try await store.addSource(data: Self.photo, title: "Pair fixture")
    let round = try await store.beginRound(sourceID: source.id, recipes: [.standard, .standard])
    let program = try Self.program(), preview = try DrawingPackageLibraryValidation.preview(program).bytes
    let a = try await store.completeCandidate(roundID: round.id, slot: 0, program: program, raster: Self.raster, previewPNG: preview)
    let separatelyRendered = try DrawingProgram(id: ProgramID(), fieldExtent: program.fieldExtent,
      strokes: program.strokes.map { LogicalStroke(id: StrokeID(), path: $0.path, style: $0.style, ordering: $0.ordering) },
      source: .init(kind: "portrait", sourceIdentifier: "independent-render-provenance"))
    #expect(separatelyRendered.contentHash != program.contentHash)
    _ = try await store.completeCandidate(roundID: round.id, slot: 1, program: separatelyRendered, raster: Self.raster, previewPNG: preview)
    try await store.finishRound(round.id)
    await #expect(throws: (any Error).self) { try await store.presentRanking(scope: .round(round.id), count: 2, seed: 1) }
    let removed = try await store.applyPrune(candidateID: a.id, action: .remove, indices: [0])
    _ = try await store.applyPrune(candidateID: a.id, action: .undo)
    _ = try await store.applyPrune(candidateID: a.id, action: .redo)
    let pair = try await store.presentRanking(scope: .round(round.id), count: 2, seed: 1)
    #expect(Set(pair.items.map(\.id)) == [a.id, removed.id])
    _ = try await store.recordRanking(presentationID: pair.id, orderedGroups: pair.items.map { [$0.id] })
    let before = await store.snapshot()
    await #expect(throws: (any Error).self) { try await store.presentRanking(scope: .round(round.id), count: 2, seed: 2) }
    #expect(await store.snapshot() == before)
    let latest = try await store.applyPrune(candidateID: a.id, action: .remove, indices: [1])
    let panel = try await store.presentRoundRanking(round.id, seed: 42)
    #expect(panel.items.count == 2)
    #expect(Set(panel.items.map(\.candidateID)).count == 2)
    #expect(panel.items.first { $0.candidateID == a.id }?.revisionID == latest.id)
    #expect(panel.items.first { $0.candidateID == a.id }?.removedIndices == [0, 1])
    let fresh = try await store.presentRanking(scope: .round(round.id), count: 2, seed: 3)
    #expect(fresh.items.contains { $0.removedIndices == [0, 1] })
    try await store.selectPresentation(pair.id)
    #expect(await store.snapshot().currentPresentationID == pair.id)
    let alteredRound = try await store.beginRound(sourceID: source.id, recipes: [.standard, .standard])
    let first = program.strokes[0]
    var points = first.path.points; points[0] = try Point2(x: points[0].x + 0.01, y: points[0].y)
    var alteredStrokes = program.strokes
    alteredStrokes[0] = LogicalStroke(id: first.id, path: try Polyline(points: points), style: first.style, ordering: first.ordering)
    let altered = try DrawingProgram(id: ProgramID(), fieldExtent: program.fieldExtent, strokes: alteredStrokes, source: program.source)
    _ = try await store.completeCandidate(roundID: alteredRound.id, slot: 0, program: program, raster: Self.raster, previewPNG: preview)
    _ = try await store.completeCandidate(roundID: alteredRound.id, slot: 1, program: altered, raster: Self.raster, previewPNG: preview)
    try await store.finishRound(alteredRound.id)
    #expect(try await store.presentRanking(scope: .round(alteredRound.id), count: 2, seed: 5).items.count == 2)
  }

  private func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("flow-portfolio-" + UUID().uuidString) }
  static let photo = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aY9sAAAAASUVORK5CYII=")!
  static let raster = PortraitRaster(width: 2, height: 2, luminance: [0,1,1,0], provenance: "synthetic-fixture", analysisSummary: "Synthetic geometry; no human quality evidence")
  static func program() throws -> DrawingProgram {
    let style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID())
    let coordinates: [[(Double, Double)]] = [[(10,10),(90,10)],[(10,30),(40,35),(90,30)],[(20,60),(75,70)],[(60,80),(70,90)]]
    return try DrawingProgram(id: ProgramID(), fieldExtent: .init(width: 100, height: 100), strokes: coordinates.enumerated().map { index, points in
      LogicalStroke(id: StrokeID(), path: try Polyline(points: points.map { try Point2(x: $0.0, y: $0.1) }), style: style, ordering: UInt32(index))
    }, source: .init(kind: "portrait", sourceIdentifier: "flow-artist-validation-fixture"))
  }
}
