import Foundation
import Observation
import PlotterModel
import PortraitCore
import PortraitLibrary

/// The library owns immutable order, assets and append-only human labels.
/// An admitted action owns its task; another click never cancels a label write.
@Observable @MainActor
final class PortraitStudioReviewModel {
  enum ReviewStatus: String { case unrated, reviewed, skipped }
  struct GroupSelection: Hashable {
    let drawingID: String
    let sourcePhotoID: UUID?
    let transferOrigin: DrawingOriginReference?
    init(_ drawing: SavedDrawing) {
      drawingID = drawing.id
      sourcePhotoID = drawing.sourcePhotoID
      transferOrigin = drawing.transferOrigin
    }
  }
  typealias LabelWriter = @MainActor (UUID, [PortraitReviewDimension: PortraitReviewChoice], String?, UUID?) async throws -> PortraitReviewLabelRevision

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
  private(set) var groupLoadedSelection: GroupSelection?
  var subjectID = ""
  var photoSessionID = ""
  var groupProvenance = ""
  var groupSplit: PortraitReviewDatasetSplit = .unassigned
  private(set) var isLoading = false
  private(set) var hasMore = false
  private(set) var reachedEnd = false
  var error: String?
  var reviewerID = ""
  private var labels: [UUID: PortraitReviewLabelRevision] = [:]
  @ObservationIgnored private let store: PortraitCandidateStore
  @ObservationIgnored private let writeLabel: LabelWriter
  @ObservationIgnored private var operation: Task<Void, Never>?
  @ObservationIgnored private var groupRequestID: UUID?
  private var operationIsDurable = false
  private var isClosing = false

  init(store: PortraitCandidateStore, writeLabel: LabelWriter? = nil) {
    self.store = store
    self.writeLabel = writeLabel ?? { id, choices, reviewer, revision in
      try await store.appendReviewLabel(comparisonID: id, choices: choices,
        reviewerID: reviewer, expectedRevisionID: revision)
    }
  }

  var groupLoadedDrawingID: String? { groupLoadedSelection?.drawingID }
  var currentIndex: Int? { comparison.flatMap { selected in comparisons.firstIndex { $0.id == selected.id } } }
  var canGoPrevious: Bool { !isLoading && !isClosing && (currentIndex ?? 0) > 0 }
  var canGoNext: Bool {
    guard !isLoading, !isClosing, let index = currentIndex else { return false }
    return index + 1 < comparisons.count || hasMore
  }
  var canScore: Bool { !isLoading && !isClosing && comparison != nil && a != nil && b != nil }
  var reviewedCount: Int { comparisons.filter { status(for: $0.id) == .reviewed }.count }
  var skippedCount: Int { comparisons.filter { status(for: $0.id) == .skipped }.count }
  var unratedCount: Int { comparisons.count - reviewedCount - skippedCount }
  var allLoadedReviewed: Bool { !comparisons.isEmpty && !hasMore && unratedCount == 0 }

  func status(for id: UUID) -> ReviewStatus {
    guard let overall = labels[id]?.choices[.overall] else { return .unrated }
    return overall == .skip ? .skipped : .reviewed
  }

  func chooseFirst(_ drawing: SavedDrawing) { firstDrawing = drawing }
  func clearFirst() { firstDrawing = nil }

  /// Busy is set before scheduling, so two events in the same run-loop turn
  /// cannot queue stale selections or duplicate scores.
  private func startOperation(durable: Bool = false,
    _ body: @escaping @MainActor () async throws -> Void) -> Task<Void, Never>? {
    guard !isClosing, !isLoading else { return nil }
    isLoading = true
    operationIsDurable = durable
    error = nil
    let task = Task {
      defer {
        self.isLoading = false
        self.operationIsDurable = false
        self.operation = nil
      }
      do { try await body() }
      catch is CancellationError { }
      catch { self.error = error.localizedDescription }
    }
    operation = task
    return task
  }

  func reload() async {
    await startOperation {
      let selectedID = self.comparison?.id
      let page = try await self.page(offset: 0)
      try Task.checkCancellation()
      self.comparisons = page.comparisons
      self.labels = page.labels
      self.hasMore = page.comparisons.count == 32
      self.reachedEnd = false
      if let selected = page.comparisons.first(where: { $0.id == selectedID }) ?? page.comparisons.first {
        try await self.load(selected)
      } else { self.clearPresentation() }
    }?.value
  }

  @discardableResult func loadNextPage() -> Bool {
    guard hasMore else { return false }
    return startOperation { try await self.appendPage() } != nil
  }

  func loadMore() async {
    guard hasMore else { return }
    await startOperation { try await self.appendPage() }?.value
  }

  private func page(offset: Int) async throws -> (comparisons: [PortraitReviewComparison], labels: [UUID: PortraitReviewLabelRevision]) {
    let page = try await store.reviewComparisonPage(offset: offset, limit: 32)
    var heads: [UUID: PortraitReviewLabelRevision] = [:]
    for comparison in page {
      if let head = try await store.reviewLabelHead(comparisonID: comparison.id) { heads[comparison.id] = head }
    }
    try Task.checkCancellation()
    return (page, heads)
  }

  private func appendPage() async throws {
    let page = try await page(offset: comparisons.count)
    try Task.checkCancellation()
    comparisons += page.comparisons
    labels.merge(page.labels) { _, new in new }
    hasMore = page.comparisons.count == 32
  }

  func compare(with drawing: SavedDrawing, presentationSeed: UInt64 = UInt64.random(in: .min ... .max)) async {
    guard let firstDrawing else { return }
    await startOperation(durable: true) {
      let comparison = try await self.store.createReviewComparison(first: firstDrawing,
        second: drawing, presentationSeed: presentationSeed, rubricVersion: "portrait-review-v1")
      try await self.load(comparison)
      self.firstDrawing = nil
      if !self.comparisons.contains(where: { $0.id == comparison.id }) {
        self.comparisons.insert(comparison, at: 0)
      }
    }?.value
  }

  @discardableResult func selectComparison(_ id: UUID) -> Bool {
    startSelection(id) != nil
  }

  func select(_ id: UUID) async { await startSelection(id)?.value }

  private func startSelection(_ id: UUID) -> Task<Void, Never>? {
    startOperation {
      let comparison = try await self.store.loadReviewComparison(id: id)
      try await self.load(comparison)
    }
  }

  @discardableResult func previous() -> Bool { navigate(-1) }
  @discardableResult func next() -> Bool { navigate(1) }

  private func navigate(_ direction: Int) -> Bool {
    guard let index = currentIndex,
      (direction < 0 ? canGoPrevious : canGoNext) else { return false }
    return startOperation { try await self.move(from: index, direction: direction) } != nil
  }

  private func move(from index: Int, direction: Int) async throws {
    let target = index + direction
    if target >= comparisons.count && hasMore { try await appendPage() }
    guard comparisons.indices.contains(target) else { reachedEnd = true; return }
    try await load(comparisons[target])
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
    self.labels[comparison.id] = label
    reachedEnd = false
  }

  private func clearPresentation() {
    comparison = nil; a = nil; b = nil; label = nil; displayA = nil; displayB = nil
  }

  func loadGroups(for drawing: SavedDrawing) async {
    guard !isClosing, !Task.isCancelled else { return }
    let requestID = UUID()
    groupRequestID = requestID
    clearGroupForm()
    // A new Library selection withdraws the old form immediately. Waiting for
    // an admitted score must never cancel its durable commit.
    while isLoading, let previous = operation {
      await previous.value
      guard !isClosing, !Task.isCancelled, groupRequestID == requestID else { return }
    }
    guard !isClosing, !Task.isCancelled, groupRequestID == requestID else { return }
    guard let task = startOperation({
      try Task.checkCancellation()
      let package = try await self.store.prepareReviewDrawing(drawing)
      try Task.checkCancellation()
      let declaration = try await self.store.reviewGroupDeclaration(origin: package.origin)
      try Task.checkCancellation()
      guard !self.isClosing, self.groupRequestID == requestID else { return }
      self.groupOrigin = package.origin
      self.groupLoadedSelection = GroupSelection(drawing)
      self.groupDeclaration = declaration
      self.subjectID = declaration?.groups.subjectID ?? ""
      self.photoSessionID = declaration?.groups.photoSessionID ?? ""
      self.groupProvenance = declaration?.groups.declaration ?? ""
      self.groupSplit = declaration?.split ?? .unassigned
    }) else { return }
    await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
  }

  private func clearGroupForm() {
    groupOrigin = nil; groupDeclaration = nil; groupLoadedSelection = nil
    subjectID = ""; photoSessionID = ""; groupProvenance = ""
    groupSplit = .unassigned
  }

  var canDeclareGroups: Bool {
    groupOrigin != nil && groupDeclaration == nil && !isLoading
      && (!subjectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !photoSessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      && !groupProvenance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func canDeclareGroups(for drawing: SavedDrawing) -> Bool {
    canDeclareGroups(expectedSelection: GroupSelection(drawing))
  }

  func canDeclareGroups(expectedSelection: GroupSelection) -> Bool {
    canDeclareGroups && groupLoadedSelection == expectedSelection
  }

  func declareGroups() async {
    guard let expectedSelection = groupLoadedSelection else { return }
    await declareGroups(expectedSelection: expectedSelection)
  }

  func declareGroups(expectedSelection: GroupSelection) async {
    guard let groupOrigin, canDeclareGroups(expectedSelection: expectedSelection) else { return }
    func known(_ text: String) -> String? {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    let groups = PortraitReviewGroups(subjectID: known(subjectID), photoSessionID: known(photoSessionID),
      declaration: known(groupProvenance))
    let split = groupSplit
    let requestID = groupRequestID
    await startOperation(durable: true) {
      let declaration = try await self.store.declareReviewGroups(origin: groupOrigin, groups: groups, split: split)
      if !self.isClosing, self.groupRequestID == requestID,
        self.groupLoadedSelection == expectedSelection { self.groupDeclaration = declaration }
    }?.value
  }

  @discardableResult func score(_ choice: PortraitReviewChoice,
    dimension: PortraitReviewDimension = .overall) -> Bool {
    startRating(choice, dimension: dimension) != nil
  }

  func rate(_ choice: PortraitReviewChoice, dimension: PortraitReviewDimension) async {
    await startRating(choice, dimension: dimension)?.value
  }

  private func startRating(_ choice: PortraitReviewChoice,
    dimension: PortraitReviewDimension) -> Task<Void, Never>? {
    guard canScore, let comparison, let index = currentIndex,
      dimension == .overall || (label?.choices[.overall] != nil && label?.choices[.overall] != .skip) else { return nil }
    let expectedRevisionID = label?.id
    var choices = label?.choices ?? [:]
    if dimension == .overall && choice == .skip { choices = [.overall: .skip] }
    else {
      if dimension == .overall && choices[.overall] == .skip { choices = [:] }
      choices[dimension] = choice
    }
    let frozenChoices = choices
    let reviewer = reviewerID.trimmingCharacters(in: .whitespacesAndNewlines)
    return startOperation(durable: true) {
      let committed: PortraitReviewLabelRevision
      do {
        committed = try await self.writeLabel(comparison.id, frozenChoices,
          reviewer.isEmpty ? nil : reviewer, expectedRevisionID)
      } catch {
        // A conflicting external writer can change the head. Keep this exact
        // comparison visible and refresh its persisted status without advancing.
        if let head = try? await self.store.reviewLabelHead(comparisonID: comparison.id) {
          self.label = head; self.labels[comparison.id] = head
        }
        throw error
      }
      self.labels[comparison.id] = committed
      self.label = committed
      guard dimension == .overall, !self.isClosing else { return }
      try await self.move(from: index, direction: 1)
    }
  }

  func waitForOperation() async { await operation?.value }

  func exportDataset(to destination: URL) async throws {
    guard !isClosing, !isLoading else {
      throw DrawingTransferError.unavailable("Review work must settle before exporting.")
    }
    var exportError: Error?
    let task = startOperation(durable: true) {
      do { _ = try await self.store.exportReviewDataset(to: destination) }
      catch { exportError = error }
    }
    await task?.value
    if let exportError { throw exportError }
  }

  func shutdown() async {
    isClosing = true
    groupRequestID = nil
    clearGroupForm()
    if !operationIsDurable { operation?.cancel() }
    await operation?.value
  }
}
