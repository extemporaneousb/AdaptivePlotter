import Foundation
import PortraitLibrary
import PortraitStudioUI
import Testing

@Suite("Flow dojo photo branches and explicit feedback", .serialized)
@MainActor
struct FlowDojoNavigationTests {
  @Test("Browsing a branch never votes; a representative retains the exact judged mask")
  func browsingAndRepresentative() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = FlowDojoModel(directory: directory, purpose: .validationFixture, render: FlowDojoFixture.render)
    do {
      await model.open(); await model.addPhoto(data: FlowDojoFixture.image(1), title: "Frame 0.8s")
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

  @Test("Pair preference, tie and skipped outcome autosave; full panel ranking remains available")
  func explicitComparisons() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = FlowDojoModel(directory: directory, purpose: .validationFixture, render: FlowDojoFixture.render)
    do {
      await model.open(); await model.addPhoto(data: FlowDojoFixture.image(2), title: "Pair fixture")
      model.count = 3; await model.generate(refining: false)
      let round = try #require(model.round)
      await model.presentRanking(scope: .round(round.id), count: 2)
      let first = try #require(model.presentation?.items.first?.id)
      await model.compare(preferred: first)
      #expect(model.trainingProgress?.rankingComparisonCount == 1)
      #expect(model.trainingProgress?.tieComparisonCount == 0)
      await model.compare(preferred: nil)
      #expect(model.trainingProgress?.tieComparisonCount == 1)
      await model.declineRanking(neither: false)
      #expect(model.trainingProgress?.rankingComparisonCount == 0)
      await model.rankCurrentSet()
      #expect(model.presentation?.items.count == 3)
      for (index, item) in (model.presentation?.items ?? []).enumerated() { await model.rank(item: item.id, position: index + 1) }
      #expect(model.trainingProgress?.rankingComparisonCount == 3)
      #expect(model.document?.choices.isEmpty == true)
      #expect(model.trainingProgress?.latestFitRevision == nil)
      await model.presentRanking(scope: .round(round.id), count: 2)
      #expect(model.error != nil && !model.needsRecovery)
      #expect(model.autosaveStatus.hasPrefix("Action unavailable:"))
      #expect(await model.shutdown())
    } catch { await model.shutdown(); throw error }
  }

  @Test("Photo banners expose partial line feedback while Fit reports all six photos")
  func localAndPortfolioFeedback() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = FlowDojoModel(directory: directory, purpose: .validationFixture, render: FlowDojoFixture.render)
    do {
      await model.open(); model.count = 3
      var partialSourceID: UUID?
      for index in 0..<6 {
        await model.addPhoto(data: FlowDojoFixture.image(index), title: "Feedback source \(index + 1)")
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
      for stage in [FlowDojoModel.Stage.explore, .prune, .rank] {
        let local = FlowDojoFeedbackText.coverage(progress, stage: stage, selectedSourceID: sourceID)
        #expect(local.hasPrefix("This photo:") && local.contains("1 remove / 0 keep labels"))
        #expect(local.contains("0 directions") && local.contains("0 comparisons") && local.contains("0 targets"))
      }
      let portfolio = FlowDojoFeedbackText.coverage(progress, stage: .fit, selectedSourceID: sourceID)
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
    let model = FlowDojoModel(directory: directory, purpose: .validationFixture)
    await model.open(); await model.addPhoto(data: FlowDojoFixture.image(3), title: "Before")
    let id = try #require(model.selectedSource?.id), baseline = try #require(model.document?.revision)
    model.queueName(id, photo: true, title: "A")
    model.queueName(id, photo: true, title: "An")
    model.queueName(id, photo: true, title: "Angular face")
    model.queueName(id, photo: true, title: "") // Empty while selecting/retyping is not a destructive edit.
    model.queueSourceCuration(id, subject: "Person A", session: "Morning", excluded: false)
    model.queueSourceCuration(id, subject: "Person A", session: "", excluded: false)
    #expect(model.pendingMetadataCount == 2)
    #expect(model.autosaveStatus == "Saving name and source edits…")
    #expect(model.document?.revision == baseline)
    #expect(await model.shutdown())
    #expect(model.pendingMetadataCount == 0)
    #expect(model.autosaveStatus.hasPrefix("All changes saved"))
    let reopened = FlowDojoModel(directory: directory)
    await reopened.open()
    #expect(reopened.selectedSource?.title == "Angular face")
    #expect(reopened.document?.revision == baseline + 2)
    #expect(reopened.selectedSource?.subjectID == "Person A" && reopened.selectedSource?.sessionID == nil)
    #expect(reopened.document?.choices.isEmpty == true)
    #expect(reopened.trainingProgress?.supervisedCandidateCount == 0)
    #expect(await reopened.shutdown())
  }

  @Test("Shutdown drains metadata admitted after a completed flush while another caller is still joining it")
  func completedMetadataJoinRace() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = MetadataJoinGate()
    let model = FlowDojoModel(directory: directory, purpose: .validationFixture,
      metadataJoinHook: { await gate.pause() })
    await model.open(); await model.addPhoto(data: FlowDojoFixture.image(5), title: "Before")
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
    let reopened = FlowDojoModel(directory: directory)
    await reopened.open()
    #expect(reopened.selectedSource?.title == "Newest admitted draft")
    #expect(reopened.error == nil)
    #expect(await reopened.shutdown())
  }

  @Test("Branch order groups descendants with their parent even when another broad set was created between them")
  func branchOrder() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = FlowDojoModel(directory: directory, purpose: .validationFixture, render: FlowDojoFixture.render)
    do {
      await model.open(); await model.addPhoto(data: FlowDojoFixture.image(4), title: "Branch fixture")
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
