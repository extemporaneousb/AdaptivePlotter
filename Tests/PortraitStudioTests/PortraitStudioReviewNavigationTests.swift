import Foundation
import PlotterModel
import PortraitCore
import PortraitLibrary
import Testing
@testable import PortraitStudio

@Suite("Review navigation and durable scoring", .serialized)
@MainActor
struct PortraitStudioReviewNavigationTests {
  @Test("Next browses without a label; committed score advances and Previous restores exact order and head")
  func navigationAndPersistedProgress() async throws {
    let fixture = try await ReviewNavigationFixture.make(count: 3)
    defer { fixture.remove() }
    let model = PortraitStudioReviewModel(store: fixture.store)
    await model.reload()
    let first = try #require(model.comparison)
    let firstA = try #require(model.displayA)
    let firstB = try #require(model.displayB)
    #expect(model.currentIndex == 0)
    #expect(model.unratedCount == 3)
    #expect(!model.previous())
    #expect(model.next())
    #expect(model.isLoading)
    #expect(!model.next())
    await model.waitForOperation()
    #expect(model.currentIndex == 1)
    #expect(try await fixture.store.reviewLabelHead(comparisonID: first.id) == nil)
    #expect(model.previous())
    await model.waitForOperation()
    #expect(model.comparison == first)
    #expect(model.score(.a))
    await model.waitForOperation()
    #expect(model.currentIndex == 1)
    #expect(model.reviewedCount == 1 && model.skippedCount == 0 && model.unratedCount == 2)
    #expect(model.previous())
    await model.waitForOperation()
    #expect(model.comparison == first)
    #expect(model.displayA == firstA && model.displayB == firstB)
    #expect(model.label?.choices == [.overall: .a])
    #expect(model.score(.b, dimension: .likeness))
    await model.waitForOperation()
    #expect(model.comparison?.id == first.id)
    #expect(model.label?.choices == [.overall: .a, .likeness: .b])
    #expect(model.next())
    await model.waitForOperation()
    #expect(model.score(.skip))
    await model.waitForOperation()
    #expect(model.currentIndex == 2)
    #expect(model.reviewedCount == 1 && model.skippedCount == 1 && model.unratedCount == 1)
    #expect(model.score(.neither))
    await model.waitForOperation()
    #expect(model.currentIndex == 2 && model.reachedEnd)
    #expect(model.allLoadedReviewed)
    #expect(!model.next())
    await model.shutdown()
    let reopened = PortraitStudioReviewModel(store: fixture.store)
    await reopened.reload()
    #expect(reopened.reviewedCount == 2 && reopened.skippedCount == 1 && reopened.unratedCount == 0)
    #expect(reopened.comparisons == model.comparisons)
    await reopened.shutdown()
  }

  @Test("An admitted score freezes identity and reviewer immediately and rejects queued actions until durable commit")
  func immediateAdmissionAndCallerCancellation() async throws {
    let fixture = try await ReviewNavigationFixture.make(count: 2)
    defer { fixture.remove() }
    let gate = ReviewWriteGate()
    let model = PortraitStudioReviewModel(store: fixture.store) { id, choices, reviewer, revision in
      await gate.pause()
      return try await fixture.store.appendReviewLabel(comparisonID: id, choices: choices,
        reviewerID: reviewer, expectedRevisionID: revision)
    }
    await model.reload()
    let first = try #require(model.comparison)
    let second = model.comparisons[1]
    model.reviewerID = "explicit-fixture-reviewer"
    let caller = Task { await model.rate(.b, dimension: .overall) }
    await gate.waitForEntry()
    caller.cancel()
    model.reviewerID = "later-edit"
    #expect(model.isLoading)
    #expect(!model.selectComparison(second.id))
    #expect(!model.next() && !model.previous())
    #expect(!model.score(.a))
    #expect(model.comparison?.id == first.id)
    gate.release()
    await caller.value
    #expect(model.comparison?.id == second.id)
    let committed = try #require(try await fixture.store.reviewLabelHead(comparisonID: first.id))
    #expect(committed.choices == [.overall: .b])
    #expect(committed.reviewerID == "explicit-fixture-reviewer")
    #expect(try await fixture.store.reviewLabelHead(comparisonID: second.id) == nil)
    await model.shutdown()
  }

  @Test("Shutdown joins an admitted write and retains its committed label without navigation")
  func shutdownJoinsCommit() async throws {
    let fixture = try await ReviewNavigationFixture.make(count: 2)
    defer { fixture.remove() }
    let gate = ReviewWriteGate()
    let model = PortraitStudioReviewModel(store: fixture.store) { id, choices, reviewer, revision in
      await gate.pause()
      return try await fixture.store.appendReviewLabel(comparisonID: id, choices: choices,
        reviewerID: reviewer, expectedRevisionID: revision)
    }
    await model.reload()
    let first = try #require(model.comparison)
    #expect(model.score(.tie))
    #expect(model.isLoading)
    await gate.waitForEntry()
    let closing = Task { await model.shutdown() }
    await Task.yield()
    gate.release()
    await closing.value
    #expect(model.comparison?.id == first.id)
    #expect(model.label?.choices == [.overall: .tie])
    #expect(try await fixture.store.reviewLabelHead(comparisonID: first.id)?.choices == [.overall: .tie])
    #expect(!model.score(.a))
  }

  @Test("Conflicting revision remains on the same immutable comparison, with durable head and an error")
  func conflictDoesNotAdvance() async throws {
    let fixture = try await ReviewNavigationFixture.make(count: 2)
    defer { fixture.remove() }
    let model = PortraitStudioReviewModel(store: fixture.store)
    await model.reload()
    let comparison = try #require(model.comparison)
    let a = model.displayA, b = model.displayB
    _ = try await fixture.store.appendReviewLabel(comparisonID: comparison.id,
      choices: [.overall: .neither], reviewerID: "other-explicit-fixture-reviewer", expectedRevisionID: nil)
    #expect(model.score(.a))
    await model.waitForOperation()
    #expect(model.error != nil)
    #expect(model.comparison == comparison)
    #expect(model.displayA == a && model.displayB == b)
    #expect(model.label?.choices == [.overall: .neither])
    #expect(model.reviewedCount == 1 && model.unratedCount == 1)
    await model.shutdown()
  }

  @Test("A new group form is cleared while a durable score settles, then loads the selected origin")
  func groupsWaitWithoutCancellingScore() async throws {
    let fixture = try await ReviewNavigationFixture.make(count: 2)
    defer { fixture.remove() }
    let gate = ReviewWriteGate()
    let model = PortraitStudioReviewModel(store: fixture.store) { id, choices, reviewer, revision in
      await gate.pause()
      return try await fixture.store.appendReviewLabel(comparisonID: id, choices: choices,
        reviewerID: reviewer, expectedRevisionID: revision)
    }
    await model.reload()
    await model.loadGroups(for: fixture.drawings[0])
    model.subjectID = "explicit-unsaved-fixture-subject"
    model.groupProvenance = "Unsaved fixture text"
    #expect(model.canDeclareGroups)
    let comparisonID = try #require(model.comparison?.id)
    #expect(model.score(.a))
    await gate.waitForEntry()
    let groupTask = Task { await model.loadGroups(for: fixture.drawings[1]) }
    await Task.yield()
    #expect(model.groupOrigin == nil && model.groupDeclaration == nil)
    #expect(model.subjectID.isEmpty && model.groupProvenance.isEmpty)
    #expect(!model.canDeclareGroups && model.isLoading)
    gate.release()
    await groupTask.value
    #expect(model.groupOrigin == fixture.drawings[1].transferOrigin)
    #expect(model.groupDeclaration == nil && model.subjectID.isEmpty)
    #expect(try await fixture.store.reviewLabelHead(comparisonID: comparisonID)?.choices == [.overall: .a])
    #expect(model.reviewedCount == 1)
    await model.shutdown()
  }

  @Test("Rapid group selections publish only the newest origin and never revive a canceled older request")
  func latestGroupSelectionWins() async throws {
    let fixture = try await ReviewNavigationFixture.make(count: 2)
    defer { fixture.remove() }
    let gate = ReviewWriteGate()
    let model = PortraitStudioReviewModel(store: fixture.store) { id, choices, reviewer, revision in
      await gate.pause()
      return try await fixture.store.appendReviewLabel(comparisonID: id, choices: choices,
        reviewerID: reviewer, expectedRevisionID: revision)
    }
    await model.reload()
    #expect(model.score(.b))
    await gate.waitForEntry()
    let old = Task { await model.loadGroups(for: fixture.drawings[0]) }
    await Task.yield()
    let newest = Task { await model.loadGroups(for: fixture.drawings[1]) }
    await Task.yield()
    old.cancel()
    #expect(model.groupOrigin == nil && !model.canDeclareGroups)
    gate.release()
    await old.value; await newest.value
    #expect(model.groupOrigin == fixture.drawings[1].transferOrigin)
    #expect(model.groupOrigin != fixture.drawings[0].transferOrigin)
    #expect(model.reviewedCount == 1 && model.error == nil)
    await model.shutdown()
  }

  @Test("Cancellation of a waiting group task keeps its form withdrawn and preserves the admitted score")
  func canceledGroupWaitDoesNotPublish() async throws {
    let fixture = try await ReviewNavigationFixture.make(count: 2)
    defer { fixture.remove() }
    let gate = ReviewWriteGate()
    let model = PortraitStudioReviewModel(store: fixture.store) { id, choices, reviewer, revision in
      await gate.pause()
      return try await fixture.store.appendReviewLabel(comparisonID: id, choices: choices,
        reviewerID: reviewer, expectedRevisionID: revision)
    }
    await model.reload()
    await model.loadGroups(for: fixture.drawings[0])
    let comparisonID = try #require(model.comparison?.id)
    #expect(model.score(.tie))
    await gate.waitForEntry()
    let groupTask = Task { await model.loadGroups(for: fixture.drawings[1]) }
    await Task.yield()
    groupTask.cancel()
    gate.release()
    await groupTask.value; await model.waitForOperation()
    #expect(model.groupOrigin == nil && model.groupDeclaration == nil)
    #expect(!model.canDeclareGroups)
    #expect(try await fixture.store.reviewLabelHead(comparisonID: comparisonID)?.choices == [.overall: .tie])
    await model.shutdown()
  }

  @Test("Group Save is bound to the displayed drawing before its load task can enter")
  func displayedDrawingAdmission() async throws {
    let fixture = try await ReviewNavigationFixture.make(count: 2)
    defer { fixture.remove() }
    let model = PortraitStudioReviewModel(store: fixture.store)
    await model.loadGroups(for: fixture.drawings[0])
    model.subjectID = "explicit-fixture-subject"
    model.photoSessionID = "explicit-fixture-session"
    model.groupProvenance = "Explicit fixture declaration"
    #expect(model.groupLoadedDrawingID == fixture.drawings[0].id)
    #expect(model.canDeclareGroups(for: fixture.drawings[0]))
    let differentDisplayed = PortraitStudioReviewModel.GroupSelection(fixture.drawings[1])
    #expect(!model.canDeclareGroups(expectedSelection: differentDisplayed))
    await model.declareGroups(expectedSelection: differentDisplayed)
    #expect(model.groupDeclaration == nil)
    #expect(try await fixture.store.reviewGroupDeclaration(origin: fixture.drawings[0].transferOrigin!) == nil)
    #expect(try await fixture.store.reviewGroupDeclaration(origin: fixture.drawings[1].transferOrigin!) == nil)
    await model.declareGroups(expectedSelection: PortraitStudioReviewModel.GroupSelection(fixture.drawings[0]))
    #expect(model.groupDeclaration?.origin == fixture.drawings[0].transferOrigin)
    #expect(model.groupDeclaration?.groups.subjectID == "explicit-fixture-subject")
    await model.shutdown()
  }

  @Test("Next loads at most one32-record page and end-of-list is distinct from all-rated completion")
  func boundedPageBoundary() async throws {
    let fixture = try await ReviewNavigationFixture.make(count: 33)
    defer { fixture.remove() }
    let model = PortraitStudioReviewModel(store: fixture.store)
    await model.reload()
    #expect(model.comparisons.count == 32 && model.hasMore)
    await model.select(model.comparisons[31].id)
    #expect(model.next())
    await model.waitForOperation()
    #expect(model.comparisons.count == 33 && !model.hasMore)
    #expect(model.currentIndex == 32)
    #expect(model.score(.skip))
    await model.waitForOperation()
    #expect(model.reachedEnd && !model.allLoadedReviewed)
    #expect(model.skippedCount == 1 && model.unratedCount == 32)
    #expect(!model.next())
    await model.shutdown()
  }
}

@MainActor
struct ReviewNavigationFixture {
  let root: URL
  let store: PortraitCandidateStore
  let drawings: [SavedDrawing]

  static func make(count: Int) async throws -> Self {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = PortraitCandidateStore(directoryURL: root.appendingPathComponent("library"))
    let capture = UUID(), producer = UUID()
    let first = try await store.importDrawingPackage(DrawingPackageCodec.encode(
      PortraitStudioReviewTests.package(captureID: capture, libraryID: producer, resultID: "first", shape: .square)), restoreDeleted: true)
    let second = try await store.importDrawingPackage(DrawingPackageCodec.encode(
      PortraitStudioReviewTests.package(captureID: capture, libraryID: producer, resultID: "second", shape: .triangle)), restoreDeleted: true)
    for index in 0..<count {
      _ = try await store.createReviewComparison(first: first, second: second,
        presentationSeed: UInt64(index), rubricVersion: "explicit-navigation-fixture-v1")
    }
    return .init(root: root, store: store, drawings: [first, second])
  }
  func remove() { try? FileManager.default.removeItem(at: root) }
}

@MainActor
private final class ReviewWriteGate {
  private var entered = false
  private var entryWaiter: CheckedContinuation<Void, Never>?
  private var releaseWaiter: CheckedContinuation<Void, Never>?
  func pause() async {
    entered = true
    entryWaiter?.resume(); entryWaiter = nil
    await withCheckedContinuation { releaseWaiter = $0 }
  }
  func waitForEntry() async {
    if !entered { await withCheckedContinuation { entryWaiter = $0 } }
  }
  func release() { releaseWaiter?.resume(); releaseWaiter = nil }
}
