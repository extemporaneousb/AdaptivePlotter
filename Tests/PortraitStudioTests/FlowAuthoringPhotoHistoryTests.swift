import Foundation
import DrawingLibrary
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary
import PortraitStudioUI
import Testing

private extension FlowPortfolioStore {
  /// Historical import can retain another domain source identity for an exact
  /// Photo which Studio had already adopted. Preserve both source records.
  func addSamePhotoHistoryAlias(of original: FlowPortfolioSource) async throws -> FlowPortfolioSource {
    let alias = FlowPortfolioSource(id: UUID(), createdAt: Date(), title: "Existing Studio proxy",
      image: original.image, subjectID: original.subjectID, sessionID: original.sessionID,
      photo: original.photo)
    var next = state
    next.sources.insert(alias, at: 0); next.selectedSourceID = alias.id
    next.currentRoundID = nil; next.currentCandidateID = nil; next.currentPruneRevisionID = nil
    try await commit(next, operation: "historical-source-alias-fixture", subjectID: alias.id)
    return alias
  }
}

@Suite("Exact Photo history across retained source occurrences", .serialized)
@MainActor
struct FlowAuthoringPhotoHistoryTests {
  @Test("Photo proxy exposes historical branches, representatives, feedback and ranking without merging IDs or equal pixels")
  func samePhotoHistory() async throws {
    let root = DrawingExchangeFeedbackFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    await model.open()
    let store = try #require(model.store)
    do {
      let pixels = FlowAuthoringFixture.image(1)
      await model.addPhoto(data: pixels, title: "Archived source")
      let original = try #require(model.selectedSource), photo = try #require(original.photo)
      model.count = 2; await model.generate(refining: false)
      let historicalRound = try #require(model.round), historical = model.roundCandidates
      await model.selectCandidate(historical[0].id, prune: true)
      await model.edit(.remove, ids: [try #require(model.program?.strokes.first?.id)])
      let frozenChoice = try #require(model.document?.choices.first)
      let frozenPrune = try #require(model.document?.pruneRevisions.first)
      let alias = try await store.addSamePhotoHistoryAlias(of: original)
      #expect(alias.id != original.id && alias.photo == original.photo)
      #expect(await model.selectPhoto(photo) == nil)
      #expect(model.selectedSource?.id == alias.id)
      model.count = 2; await model.generate(refining: false)
      let proxyRound = try #require(model.round), proxyCandidates = model.roundCandidates
      let other = try await store.addSource(data: pixels, title: "Different Photo with equal pixels")
      #expect(other.image == original.image && other.photo != original.photo)
      let otherCandidates = try await DrawingExchangeFeedbackFixture.round(store: store, source: other.id, count: 2)
      #expect(await model.selectPhoto(photo) == nil)
      let document = try #require(model.document)
      #expect(document.photoSourceIDs(for: alias.id) == [alias.id, original.id])
      #expect(document.photoSourceIDs(for: other.id) == [other.id])
      #expect(Set(model.branches(for: alias.id).map(\.id)) == [historicalRound.id, proxyRound.id])
      #expect(Set(model.branches(for: original.id).map(\.id)) == [historicalRound.id, proxyRound.id])
      let representative = try #require(model.representative(for: alias.id))
      #expect(representative.sourceID == original.id && representative.candidateID == historical[0].id)
      #expect(await model.representativeThumbnail(alias)?.isEmpty == false)
      let progress = try #require(model.trainingProgress)
      #expect(progress.photoCount == 2 && progress.includedPhotoCount == 2)
      #expect(progress.photo(alias.id) == progress.photo(original.id))
      #expect(progress.photo(alias.id).candidateCount == historical.count + proxyCandidates.count)
      #expect(progress.photo(other.id).candidateCount == otherCandidates.count)
      #expect(progress.photo(alias.id).choiceCount == 1 && progress.photo(alias.id).removeLabelCount == 1)
      #expect(progress.photo(other.id).choiceCount == 0 && progress.photo(other.id).removeLabelCount == 0)
      await model.presentRanking(scope: .source(alias.id), count: 24)
      let shown = try #require(model.presentation)
      #expect(Set(shown.items.map(\.sourceID)) == [original.id, alias.id])
      #expect(Set(shown.items.map(\.candidateID)) == Set((historical + proxyCandidates).map(\.id)))
      #expect(!shown.items.contains { otherCandidates.map(\.id).contains($0.candidateID) })
      await model.selectRound(historicalRound.id)
      #expect(model.selectedSource?.id == original.id && model.currentPhotoRef == photo)
      #expect(model.roundCandidates.map(\.id) == historical.map(\.id))
      #expect(model.document?.choices.first == frozenChoice && model.document?.pruneRevisions.first == frozenPrune)
      let nilA = FlowPortfolioSource(id: UUID(), createdAt: Date(), title: "Legacy A", image: original.image)
      let nilB = FlowPortfolioSource(id: UUID(), createdAt: Date(), title: "Legacy B", image: original.image)
      var legacy = document; legacy.sources += [nilA, nilB]
      #expect(legacy.photoSourceIDs(for: nilA.id) == [nilA.id])
      #expect(legacy.photoSourceIDs(for: nilB.id) == [nilB.id])
      #expect(await model.shutdown())
    } catch { _ = await model.shutdown(); throw error }
  }
}
