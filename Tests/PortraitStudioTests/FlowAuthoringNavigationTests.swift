import Foundation
import DrawingLibrary
import PortraitLibrary
import PortraitStudioUI
import Testing

@Suite("Flow authoring photo branches and explicit feedback", .serialized)
@MainActor
struct FlowAuthoringNavigationTests {
  @Test("Browsing a branch never votes; a representative retains the exact judged mask")
  func browsingAndRepresentative() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = FlowAuthoringModel(directory: directory, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    do {
      await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(1), title: "Frame 0.8s")
      model.count = 3; await model.generate(refining: false)
      let source = try #require(model.selectedSource), values = model.roundCandidates
      #expect(model.photoName(source).hasPrefix("Photo 1"))
      await model.browseCandidate(values[0].id, prune: true)
      #expect(model.document?.choices.isEmpty == true)
      #expect(model.trainingProgress?.supervisedCandidateCount == 0)
      let strokes = try #require(model.program?.strokes)
      await model.edit(.remove, ids: [strokes[0].id])
      await model.selectCandidate(values[0].id)
      let frozen = try #require(model.representative(for: source.id))
      #expect(frozen.removedIndices == [0])
      let key = model.representativeKey(source)
      await model.edit(.remove, ids: [strokes[1].id])
      #expect(model.representative(for: source.id) == frozen)
      #expect(model.representativeKey(source) == key)
      await model.browseCandidate(values[1].id)
      #expect(model.document?.choices.count == 1)
      let before = model.document?.revision
      let thumbnail = await model.representativeThumbnail(source)
      #expect(thumbnail?.isEmpty == false)
      #expect(model.document?.revision == before)
      await model.renameCandidate(values[0].id, title: "Angular portrait")
      #expect(model.drawingName(try #require(model.document?.candidates.first)) == "Angular portrait")
      #expect(await model.shutdown())
    } catch { await model.shutdown(); throw error }
  }

  @Test("Title/navigation reuse supervision, while neutral grouping/exclusion and feedback invalidate it")
  func semanticRefreshCache() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = FlowAuthoringModel(directory: directory, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(1), title: "Before")
    model.count = 3; await model.generate(refining: false)
    let candidate = try #require(model.roundCandidates.first), source = try #require(model.selectedSource)
    let library = try #require(model.drawingLibrary), photo = try #require(source.photo)
    let baseline = model.trainingSummaryBuildCount
    await model.renameSource(source.id, title: "After")
    await model.renameCandidate(candidate.id, title: "Drawing title")
    await model.browseCandidate(candidate.id)
    #expect(model.trainingSummaryBuildCount == baseline && model.checkpointDecodeCount == 0)
    #expect(model.trainingProgress?.revision == model.document?.revision)
    try await library.updatePhotoMetadata(photo, patch: .init(title: .set("Neutral title")))
    await model.selectSource(source.id)
    #expect(model.selectedSource?.title == "Neutral title" && model.trainingSummaryBuildCount == baseline)
    try await library.updatePhotoMetadata(photo, patch: .init(subjectID: .set("subject"), sessionID: .set("session")))
    await model.selectSource(source.id)
    #expect(model.trainingSummaryBuildCount == baseline + 1)
    try await library.updatePhotoMetadata(photo, patch: .init(excluded: true))
    await model.selectSource(source.id)
    #expect(model.trainingSummaryBuildCount == baseline + 2 && model.trainingProgress?.includedPhotoCount == 0)
    try await library.updatePhotoMetadata(photo, patch: .init(subjectID: .set(nil), sessionID: .set(nil), excluded: false))
    await model.selectSource(source.id)
    await model.selectCandidate(candidate.id, prune: true)
    let beforeEdit = model.trainingSummaryBuildCount
    await model.edit(.remove, ids: [try #require(model.program?.strokes.first?.id)])
    #expect(model.trainingSummaryBuildCount == beforeEdit + 1)
    #expect(model.trainingProgress == FlowAuthoringTrainingProgress(document: try #require(model.document)))
    #expect(await model.shutdown())
  }

  @Test("Pair preference, tie and skipped outcome autosave; full panel ranking remains available")
  func explicitComparisons() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = FlowAuthoringModel(directory: directory, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    do {
      await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(2), title: "Pair fixture")
      model.count = 3; await model.generate(refining: false)
      let round = try #require(model.round)
      await model.presentRanking(scope: .round(round.id), count: 2)
      let earlier = try #require(model.presentation?.id)
      let first = try #require(model.presentation?.items.first?.id)
      await model.compare(preferred: first)
      #expect(model.trainingProgress?.rankingComparisonCount == 1)
      #expect(model.trainingProgress?.tieComparisonCount == 0)
      await model.compare(preferred: nil)
      #expect(model.trainingProgress?.tieComparisonCount == 1)
      await model.declineRanking(neither: false)
      #expect(model.trainingProgress?.rankingComparisonCount == 2)
      await model.rankCurrentSet()
      #expect(model.presentation?.items.count == 3)
      for (index, item) in (model.presentation?.items ?? []).enumerated() { await model.rank(item: item.id, position: index + 1) }
      #expect(model.trainingProgress?.rankingComparisonCount == 5)
      #expect(model.document?.choices.isEmpty == true)
      #expect(model.trainingProgress?.latestFitRevision == nil)
      await model.presentRanking(scope: .round(round.id), count: 2)
      #expect(model.error != nil && !model.needsRecovery)
      #expect(model.autosaveStatus.hasPrefix("Action unavailable:"))
      await model.selectPresentation(earlier)
      #expect(Set(model.rankingPreviews.keys) == Set(try #require(model.presentation).items.map(\.id)))
      #expect(await model.shutdown())
    } catch { await model.shutdown(); throw error }
  }

  @Test("Photo banners expose partial line feedback while Fit reports all six photos")
  func localAndPortfolioFeedback() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = FlowAuthoringModel(directory: directory, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    do {
      await model.open(); model.count = 3
      var partialSourceID: UUID?
      for index in 0..<6 {
        await model.addPhoto(data: FlowAuthoringFixture.image(index), title: "Feedback source \(index + 1)")
        await model.generate(refining: false)
        let candidate = try #require(model.roundCandidates.first)
        if index == 0 {
          partialSourceID = model.selectedSource?.id
          await model.browseCandidate(candidate.id, prune: true)
        } else { await model.selectCandidate(candidate.id, prune: true) }
        await model.edit(.remove, ids: [try #require(model.program?.strokes.first?.id)])
        if index > 0 { await model.edit(.completeTarget) }
      }
      await model.presentRanking(scope: .round(try #require(model.round?.id)), count: 2)
      await model.compare(preferred: try #require(model.presentation?.items.first?.id))
      let sourceID = try #require(partialSourceID)
      await model.selectSource(sourceID)
      let progress = try #require(model.trainingProgress)
      #expect(model.error == nil && progress.feedbackPhotoCount == 6)
      #expect(progress.photo(sourceID).partialCorrectionCount == 1)
      #expect(progress.photo(sourceID).choiceCount == 0 && progress.photo(sourceID).rankingCount == 0)
      #expect(progress.photo(sourceID).completedTargetCount == 0)
      for stage in [FlowAuthoringModel.Stage.explore, .prune, .rank] {
        let local = FlowAuthoringFeedbackText.coverage(progress, stage: stage, selectedSourceID: sourceID)
        #expect(local.hasPrefix("This photo:") && local.contains("1 remove / 0 keep labels"))
        #expect(local.contains("0 directions") && local.contains("0 comparisons") && local.contains("0 targets"))
      }
      let portfolio = FlowAuthoringFeedbackText.coverage(progress, stage: .fit, selectedSourceID: sourceID)
      #expect(portfolio.hasPrefix("Portfolio: 6 photos with feedback"))
      #expect(portfolio.contains("5 directions") && portfolio.contains("1 comparisons"))
      #expect(portfolio.contains("6 remove / 75 keep labels"))
      #expect(await model.shutdown())
    } catch { await model.shutdown(); throw error }
  }

  @Test("Valid name drafts coalesce and shutdown flushes the final edit without Save")
  func nameDraftShutdown() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = FlowAuthoringModel(directory: directory, purpose: .validationFixture)
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(3), title: "Before")
    let id = try #require(model.selectedSource?.id), baseline = try #require(model.document?.revision)
    model.queueName(id, photo: true, title: "A")
    model.queueName(id, photo: true, title: "An")
    model.queueName(id, photo: true, title: "Angular face")
    model.queueName(id, photo: true, title: "") // Empty while selecting/retyping is not a destructive edit.
    #expect(model.pendingMetadataCount == 1)
    #expect(model.autosaveStatus == "Saving names…")
    #expect(model.document?.revision == baseline)
    #expect(await model.shutdown())
    #expect(model.pendingMetadataCount == 0)
    #expect(model.autosaveStatus.hasPrefix("All changes saved"))
    let reopened = FlowAuthoringModel(directory: directory)
    await reopened.open()
    #expect(reopened.selectedSource?.title == "Angular face")
    #expect(reopened.document?.revision == baseline + 1)
    #expect(reopened.document?.choices.isEmpty == true)
    #expect(reopened.trainingProgress?.supervisedCandidateCount == 0)
    #expect(await reopened.shutdown())
  }

  @Test("Shutdown drains metadata admitted after a completed flush while another caller is still joining it")
  func completedMetadataJoinRace() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = MetadataJoinGate()
    let model = FlowAuthoringModel(directory: directory, purpose: .validationFixture,
      metadataJoinHook: { await gate.pause() })
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(5), title: "Before")
    let id = try #require(model.selectedSource?.id)
    model.queueName(id, photo: true, title: "First draft")
    let firstJoin = Task { await model.flushMetadataEdits() }
    do { try await gate.waitUntilPaused() }
    catch { await gate.release(); await firstJoin.value; await model.shutdown(); throw error }
    // Worker one is complete, but its original joining caller is paused. This
    // interleaving previously left a stale completed handle and lost this edit.
    model.queueName(id, photo: true, title: "Newest admitted draft")
    #expect(model.pendingMetadataCount == 1)
    #expect(await model.shutdown())
    #expect(model.pendingMetadataCount == 0)
    await gate.release(); await firstJoin.value
    let reopened = FlowAuthoringModel(directory: directory)
    await reopened.open()
    #expect(reopened.selectedSource?.title == "Newest admitted draft")
    #expect(reopened.error == nil)
    #expect(await reopened.shutdown())
  }

  @Test("Branch order groups descendants with their parent even when another broad set was created between them")
  func branchOrder() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = FlowAuthoringModel(directory: directory, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    do {
      await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(4), title: "Branch fixture")
      let source = try #require(model.selectedSource)
      model.count = 3; await model.generate(refining: false)
      let first = try #require(model.round), parent = try #require(model.roundCandidates.first)
      await model.generate(refining: false)
      let second = try #require(model.round)
      await model.browseCandidate(parent.id)
      await model.generate(refining: true)
      let child = try #require(model.round)
      #expect(model.branches(for: source.id).map(\.id) == [first.id, child.id, second.id])
      #expect(model.branchAncestors.map(\.id) == [parent.id])
      #expect(model.document?.choices.isEmpty == true)
      #expect(await model.shutdown())
    } catch { await model.shutdown(); throw error }
  }
}

private actor MetadataJoinGate {
  private var paused = false
  private var released = false
  private var continuation: CheckedContinuation<Void, Never>?
  func pause() async {
    paused = true
    guard !released else { return }
    await withCheckedContinuation { continuation = $0 }
  }
  func waitUntilPaused() async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while !paused {
      guard ContinuousClock.now < deadline else { throw CocoaError(.fileReadUnknown) }
      try await Task.sleep(for: .milliseconds(5))
    }
  }
  func release() { released = true; continuation?.resume(); continuation = nil }
}
