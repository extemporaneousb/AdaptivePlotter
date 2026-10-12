import Foundation
import Observation
import PlotterModel
import PortraitCore
import PortraitLibrary

/// Native selection and presentation only. The library freezes comparison
/// identity, randomized order, assets and append-only human label revisions.
@Observable @MainActor
final class PortraitStudioReviewModel {
  private(set) var comparisons: [PortraitReviewComparison] = []
  private(set) var comparison: PortraitReviewComparison?
  private(set) var a: DrawingPackage?
  private(set) var b: DrawingPackage?
  private(set) var label: PortraitReviewLabelRevision?
  private(set) var displayA: DrawingPackageAsset?
  private(set) var displayB: DrawingPackageAsset?
  private(set) var firstDrawing: SavedDrawing?
  private(set) var groupDeclaration: PortraitReviewGroupDeclaration?
  private(set) var groupOrigin: DrawingOriginReference?
  var subjectID = ""
  var photoSessionID = ""
  var groupProvenance = ""
  var groupSplit: PortraitReviewDatasetSplit = .unassigned
  private(set) var isLoading = false
  private(set) var hasMore = false
  var error: String?
  var reviewerID = ""
  @ObservationIgnored private let store: PortraitCandidateStore
  @ObservationIgnored private var operation: Task<Void, Never>?
  private var isClosing = false

  init(store: PortraitCandidateStore) { self.store = store }

  func chooseFirst(_ drawing: SavedDrawing) { firstDrawing = drawing }
  func clearFirst() { firstDrawing = nil }

  private func perform(_ body: @escaping @MainActor () async throws -> Void) async {
    guard !isClosing else { return }
    let previous = operation
    previous?.cancel()
    let next = Task {
      await previous?.value
      guard !Task.isCancelled else { return }
      self.isLoading = true
      self.error = nil
      defer { self.isLoading = false }
      do { try await body() }
      catch is CancellationError { }
      catch { self.error = error.localizedDescription }
    }
    operation = next
    await withTaskCancellationHandler { await next.value } onCancel: { next.cancel() }
  }

  func reload() async {
    await perform {
      let page = try await self.store.reviewComparisonPage(limit: 32)
      try Task.checkCancellation()
      self.comparisons = page
      self.hasMore = page.count == 32
    }
  }

  func loadMore() async {
    await perform {
      let page = try await self.store.reviewComparisonPage(offset: self.comparisons.count, limit: 32)
      try Task.checkCancellation()
      self.comparisons += page
      self.hasMore = page.count == 32
    }
  }

  func compare(with drawing: SavedDrawing, presentationSeed: UInt64 = UInt64.random(in: .min ... .max)) async {
    guard let firstDrawing else { return }
    await perform {
      let comparison = try await self.store.createReviewComparison(first: firstDrawing,
        second: drawing, presentationSeed: presentationSeed, rubricVersion: "portrait-review-v1")
      try await self.load(comparison)
      try Task.checkCancellation()
      self.firstDrawing = nil
      if !self.comparisons.contains(where: { $0.id == comparison.id }) {
        self.comparisons.insert(comparison, at: 0)
      }
    }
  }

  func select(_ id: UUID) async {
    await perform {
      let comparison = try await self.store.loadReviewComparison(id: id)
      try await self.load(comparison)
    }
  }

  private func load(_ comparison: PortraitReviewComparison) async throws {
    let a = try await store.loadReviewPackage(origin: comparison.a.origin)
    let b = try await store.loadReviewPackage(origin: comparison.b.origin)
    let label = try await store.reviewLabelHead(comparisonID: comparison.id)
    let displayA = try await store.loadReviewDisplayPreview(comparisonID: comparison.id, side: .a)
    let displayB = try await store.loadReviewDisplayPreview(comparisonID: comparison.id, side: .b)
    try Task.checkCancellation()
    self.comparison = comparison
    self.a = a; self.b = b; self.label = label
    self.displayA = displayA; self.displayB = displayB
  }

  func loadGroups(for drawing: SavedDrawing) async {
    await perform {
      self.groupOrigin = nil; self.groupDeclaration = nil
      self.subjectID = ""; self.photoSessionID = ""; self.groupProvenance = ""
      self.groupSplit = .unassigned
      let package = try await self.store.prepareReviewDrawing(drawing)
      let declaration = try await self.store.reviewGroupDeclaration(origin: package.origin)
      try Task.checkCancellation()
      self.groupOrigin = package.origin
      self.groupDeclaration = declaration
      self.subjectID = declaration?.groups.subjectID ?? ""
      self.photoSessionID = declaration?.groups.photoSessionID ?? ""
      self.groupProvenance = declaration?.groups.declaration ?? ""
      self.groupSplit = declaration?.split ?? .unassigned
    }
  }

  var canDeclareGroups: Bool {
    groupOrigin != nil && groupDeclaration == nil && !isLoading
      && (!subjectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !photoSessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      && !groupProvenance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func declareGroups() async {
    guard let groupOrigin, canDeclareGroups else { return }
    func known(_ text: String) -> String? {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    let groups = PortraitReviewGroups(subjectID: known(subjectID), photoSessionID: known(photoSessionID),
      declaration: known(groupProvenance))
    let split = groupSplit
    await perform {
      let declaration = try await self.store.declareReviewGroups(origin: groupOrigin, groups: groups, split: split)
      try Task.checkCancellation()
      self.groupDeclaration = declaration
    }
  }

  func rate(_ choice: PortraitReviewChoice, dimension: PortraitReviewDimension) async {
    guard let comparison else { return }
    let expectedRevisionID = label?.id
    var choices = label?.choices ?? [:]
    if dimension == .overall && choice == .skip { choices = [.overall: .skip] }
    else { choices[dimension] = choice }
    let reviewer = reviewerID.trimmingCharacters(in: .whitespacesAndNewlines)
    await perform {
      let label = try await self.store.appendReviewLabel(comparisonID: comparison.id,
        choices: choices, reviewerID: reviewer.isEmpty ? nil : reviewer,
        expectedRevisionID: expectedRevisionID)
      try Task.checkCancellation()
      self.label = label
    }
  }

  func exportDataset(to destination: URL) async throws {
    guard !isClosing, !isLoading else {
      throw DrawingTransferError.unavailable("Review work must settle before exporting.")
    }
    _ = try await store.exportReviewDataset(to: destination)
  }

  func shutdown() async {
    isClosing = true
    operation?.cancel()
    await operation?.value
  }
}
