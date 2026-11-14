import Foundation
import PlotterModel
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary
import PortraitStudioUI
import Testing

@Suite("Effective Flow artist training coverage", .serialized)
struct FlowAuthoringTrainingProgressTests {
  @Test("Unused generated rows disappear from fitting, while complete offered comparisons and exact masks remain")
  func supervisionProjection() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await StudioDrawingFixture.store(directory: root, purpose: .validationFixture)
    let source = try await store.addSource(data: FlowAuthoringFixture.image(1), title: "Fixture photo")
    let unused = try await round(store, source: source.id, count: 1, raster: .init(width: 2, height: 2,
      luminance: [0.2, 0.4, 0.6, 0.8], provenance: "unused-test-only", analysisSummary: "No feedback"))
    let candidates = try await round(store, source: source.id, count: 3)
    let empty = FlowAuthoringTrainingProgress(document: await store.snapshot())
    #expect(empty.exampleCount == 0 && !empty.canAttemptFit)
    #expect(try await DrawingExchangeFeedbackFixture.freezeInputs(store).examples.isEmpty)
    try await store.chooseCandidate(candidates[0].id)
    try await store.chooseCandidate(candidates[0].id)
    _ = try await store.applyPrune(candidateID: candidates[0].id, action: .remove, indices: [0])
    _ = try await store.applyPrune(candidateID: candidates[0].id, action: .completeTarget)
    let presentation = try await store.presentRanking(scope: .candidate(candidates[0].id), count: 2, seed: 1)
    _ = try await store.recordRanking(presentationID: presentation.id, orderedGroups: [presentation.items.map(\.id)])
    let document = await store.snapshot(), progress = FlowAuthoringTrainingProgress(document: document)
    #expect(progress.choiceCount == 1 && progress.choiceComparisonCount == 2)
    #expect(progress.rankingCount == 1 && progress.rankingComparisonCount == 1 && progress.tieComparisonCount == 1)
    #expect(progress.removeLabelCount == 1 && progress.keepLabelCount == 3 && progress.completedTargetCount == 1)
    #expect(progress.feedbackPhotoCount == 1 && progress.generatedDrawingCount == 4)
    #expect(progress.photo(source.id).candidateCount == 4)
    // Move beyond the current/previous panel window without adding geometry or feedback.
    // No extraction should touch an unused generated raster, even if it is unreadable.
    let nextRound = try await store.beginRound(sourceID: source.id, recipes: [.standard])
    try await store.finishRound(nextRound.id, cancelled: true)
    await #expect(throws: FlowPortfolioError.self) { try await store.candidateProgram(unused[0].id) }
    let dataset = try await DrawingExchangeFeedbackFixture.freezeInputs(store)
    #expect(!dataset.examples.contains { $0.id == unused[0].id.uuidString })
    #expect(dataset.examples.count == progress.exampleCount)
    #expect(dataset.rankings.count == progress.choiceCount + progress.rankingCount)
    #expect(dataset.examples.flatMap(\.strokeLabels).count == progress.removeLabelCount + progress.keepLabelCount)
    #expect(dataset.examples.reduce(0) { $0 + $1.features.count + $1.strokeFeatures.reduce(0) { $0 + $1.count } } == progress.featureValueCount)
    #expect(Set(dataset.rankings.flatMap { $0.tiers.flatMap { $0 } }).isSubset(of: Set(dataset.examples.map(\.id))))
  }

  @Test("Undo, inherited masks, unfinished edits and withdrawn ranks never manufacture labels")
  func feedbackSemantics() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await StudioDrawingFixture.store(directory: root, purpose: .validationFixture)
    let source = try await store.addSource(data: FlowAuthoringFixture.image(1), title: "Fixture")
    let candidates = try await round(store, source: source.id, count: 2)
    _ = try await store.applyPrune(candidateID: candidates[0].id, action: .remove, indices: [0])
    _ = try await store.applyPrune(candidateID: candidates[0].id, action: .completeTarget)
    _ = try await store.applyPrune(candidateID: candidates[0].id, action: .remove, indices: [1])
    _ = try await store.applyPrune(candidateID: candidates[0].id, action: .undo)
    var progress = FlowAuthoringTrainingProgress(document: await store.snapshot())
    #expect(progress.completedTargetCount == 0 && progress.removeLabelCount == 1 && progress.keepLabelCount == 0)
    _ = try await store.applyPrune(candidateID: candidates[0].id, action: .undo)
    progress = FlowAuthoringTrainingProgress(document: await store.snapshot())
    #expect(progress.exampleCount == 0 && progress.removeLabelCount == 0 && progress.keepLabelCount == 0)
    let p = try await store.presentRanking(scope: .round(candidates[0].roundID), count: 2, seed: 2)
    _ = try await store.recordRanking(presentationID: p.id, orderedGroups: [[p.items[0].id]])
    #expect(FlowAuthoringTrainingProgress(document: await store.snapshot()).rankingCount == 0)
    let cleared = try await store.recordRanking(presentationID: p.id, orderedGroups: [])
    #expect(cleared.orderedGroups.isEmpty && !cleared.skipped && !cleared.neither)
    #expect(try await DrawingExchangeFeedbackFixture.freezeInputs(store).rankings.isEmpty)
    _ = try await store.recordRanking(presentationID: p.id, orderedGroups: p.items.map { [$0.id] })
    #expect(FlowAuthoringTrainingProgress(document: await store.snapshot()).rankingCount == 1)
    _ = try await store.recordRanking(presentationID: p.id, orderedGroups: [p.items.map(\.id)])
    let tied = FlowAuthoringTrainingProgress(document: await store.snapshot())
    #expect(tied.rankingCount == 1 && tied.tieComparisonCount == 1)
    let neither = try await store.recordRanking(presentationID: p.id, orderedGroups: [], neither: true)
    #expect(neither.neither && !neither.skipped)
    #expect(try await DrawingExchangeFeedbackFixture.freezeInputs(store).rankings.isEmpty)
    let skipped = try await store.recordRanking(presentationID: p.id, orderedGroups: [], skipped: true)
    #expect(skipped.skipped && !skipped.neither)
    #expect(FlowAuthoringTrainingProgress(document: await store.snapshot()).exampleCount == 0)
    #expect(try await DrawingExchangeFeedbackFixture.freezeInputs(store).examples.isEmpty)
  }

  @Test("Excluded unlabelled source bridges still join related photo groups")
  func transitiveGroups() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await StudioDrawingFixture.store(directory: root, purpose: .validationFixture)
    let a = try await store.addSource(data: FlowAuthoringFixture.image(1), title: "A")
    let bridge = try await store.addSource(data: FlowAuthoringFixture.image(2), title: "Bridge")
    let b = try await store.addSource(data: FlowAuthoringFixture.image(3), title: "B")
    try await store.setSourceGroups(sourceID: a.id, subjectID: "declared-subject", sessionID: nil)
    try await store.setSourceGroups(sourceID: bridge.id, subjectID: "declared-subject", sessionID: "declared-session", excluded: true)
    try await store.setSourceGroups(sourceID: b.id, subjectID: nil, sessionID: "declared-session")
    for source in [a, b] {
      let candidate = try await round(store, source: source.id, count: 1)[0]
      _ = try await store.applyPrune(candidateID: candidate.id, action: .remove, indices: [0])
      _ = try await store.applyPrune(candidateID: candidate.id, action: .completeTarget)
    }
    let document = await store.snapshot(), data = try await DrawingExchangeFeedbackFixture.freezeInputs(store)
    #expect(data.examples.count == 2 && Set(data.examples.map(\.sourceGroupID)).count == 1)
    let progress = FlowAuthoringTrainingProgress(document: document)
    #expect(progress.photoCount == 3 && progress.includedPhotoCount == 2)
    #expect(progress.feedbackPhotoCount == 2 && progress.feedbackGroupCount == 1)
  }

  @Test("Photo metadata edits preserve earlier frozen facts and enter only future snapshots")
  func frozenPhotoMetadata() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await StudioDrawingFixture.store(directory: root, purpose: .validationFixture)
    let source = try await store.addSource(data: FlowAuthoringFixture.image(1), title: "Before curation")
    let oldSnapshot = try await store.freezeTrainingSnapshot()
    let oldDocument = try await store.trainingDocument(snapshotID: oldSnapshot.id)
    let before = try #require(oldDocument.sources.first)
    try await store.renameSource(sourceID: source.id, title: "After curation")
    try await store.setSourceGroups(sourceID: source.id, subjectID: "new-subject", sessionID: "new-session", excluded: true)
    let live = try #require(await store.snapshot().sources.first)
    #expect(live.photo == before.photo && live.image == before.image && live.createdAt == before.createdAt)
    #expect(live.title == "After curation" && live.subjectID == "new-subject" && live.sessionID == "new-session" && live.excluded)
    let stillFrozen = try await store.trainingDocument(snapshotID: oldSnapshot.id)
    #expect(stillFrozen == oldDocument)
    #expect(stillFrozen.sources.first?.title == "Before curation")
    #expect(stillFrozen.sources.first?.excluded == false)
    let newSnapshot = try await store.freezeTrainingSnapshot()
    let newDocument = try await store.trainingDocument(snapshotID: newSnapshot.id)
    #expect(newSnapshot.contentSHA256 != oldSnapshot.contentSHA256)
    #expect(newDocument.sources.first == live)
    // This checks the frozen UI projection. Exact feature authority is exercised
    // separately by DrawingExchangeFrozenTrainingTests against hostile locators.
  }

  @Test("Exact frozen comparisons track withdrawals and groups, ignore browsing, and never consume failed fits")
  func fitCutoffs() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await StudioDrawingFixture.store(directory: root, purpose: .validationFixture)
    let source = try await store.addSource(data: FlowAuthoringFixture.image(1), title: "Fixture")
    let candidates = try await round(store, source: source.id, count: 3)
    try await store.chooseCandidate(candidates[0].id)
    _ = try await store.applyPrune(candidateID: candidates[0].id, action: .remove, indices: [0])
    _ = try await store.applyPrune(candidateID: candidates[0].id, action: .completeTarget)
    let snapshot = try await store.freezeTrainingSnapshot()
    let frozen = try await store.trainingDocument(snapshotID: snapshot.id)
    let dataset = try await FlowAuthoringTraining.dataset(store: store, document: frozen)
    let report = FlowArtistTraining.fit(examples: dataset.examples, rankings: dataset.rankings)
    let checkpoint = try #require(report.checkpoint), encoder = DrawingArtifactCoding.encoder()
    let fit = try await store.installFit(checkpoint: encoder.encode(checkpoint), report: encoder.encode(report), snapshotID: snapshot.id)
    try await store.activateModel(fit.id)
    var progress = FlowAuthoringTrainingProgress(document: await store.snapshot(), fittedDocument: frozen, activeDocument: frozen)
    #expect(progress.latestFitRevision == snapshot.portfolioRevision && progress.activeFitRevision == snapshot.portfolioRevision)
    #expect(progress.hasTrainingChanges == false && progress.activeHasTrainingChanges == false)
    #expect(progress.pendingChoiceCount == 0 && progress.pendingLabelCandidateCount == 0)
    try await store.selectCandidate(candidates[1].id)
    try await store.renameSource(sourceID: source.id, title: "Navigation is not feedback")
    _ = try await round(store, source: source.id, count: 1)
    progress = FlowAuthoringTrainingProgress(document: await store.snapshot(), fittedDocument: frozen, activeDocument: frozen)
    #expect(progress.hasTrainingChanges == false)
    try await store.setSourceGroups(sourceID: source.id, subjectID: "explicit-group", sessionID: nil)
    progress = FlowAuthoringTrainingProgress(document: await store.snapshot(), fittedDocument: frozen, activeDocument: frozen)
    #expect(progress.hasTrainingChanges == true)
    try await store.setSourceGroups(sourceID: source.id, subjectID: nil, sessionID: nil)
    _ = try await store.applyPrune(candidateID: candidates[0].id, action: .undo)
    let failedSnapshot = try await store.freezeTrainingSnapshot()
    let unavailable = FlowArtistTraining.fit(examples: [], rankings: [])
    _ = try await store.installFit(checkpoint: nil, report: encoder.encode(unavailable), snapshotID: failedSnapshot.id)
    progress = FlowAuthoringTrainingProgress(document: await store.snapshot(), fittedDocument: frozen, activeDocument: frozen)
    #expect(progress.latestFitAttemptRevision == failedSnapshot.portfolioRevision)
    #expect(progress.latestFitRevision == snapshot.portfolioRevision)
    #expect(progress.pendingLabelCandidateCount == 1 && progress.removeLabelCount == 0)
    #expect(progress.hasTrainingChanges == true && progress.activeHasTrainingChanges == true)
    #expect(FlowAuthoringTrainingProgress(document: await store.snapshot()).hasTrainingChanges == nil)
    try await store.setSourceExcluded(sourceID: source.id, excluded: true)
    progress = FlowAuthoringTrainingProgress(document: await store.snapshot(), fittedDocument: frozen, activeDocument: frozen)
    #expect(progress.hasTrainingChanges == true && progress.pendingChoiceCount == 1 && !progress.canAttemptFit)
  }

  private func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("flow-coverage-" + UUID().uuidString) }
  private func round(_ store: FlowPortfolioStore, source: UUID, count: Int,
    raster: PortraitRaster = FlowPortfolioTests.raster) async throws -> [FlowPortfolioCandidate] {
    let recipes = (0..<count).map { index -> FlowArtistRecipe in
      var values = FlowArtistRecipe.standard.values; values[0] = Double(index) / Double(max(1, count)); return .init(values: values)
    }
    let round = try await store.beginRound(sourceID: source, recipes: recipes)
    let program = try FlowPortfolioTests.program(), preview = try PortraitDrawingPreview.png(program)
    var result: [FlowPortfolioCandidate] = []
    for slot in 0..<count { result.append(try await store.completeCandidate(roundID: round.id, slot: slot, production: StudioDrawingFixture.production(program: program, raster: raster), previewPNG: preview)) }
    try await store.finishRound(round.id); return result
  }
}
