import Foundation
@testable import DrawingLibrary
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary
import Testing

@Suite("Selection-neutral acquisition and recoverable source adoption", .serialized)
struct FlowSourceAdoptionTests {
  private func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("flow-adoption-" + UUID().uuidString) }
  @Test("Source and independent capture retention never adopt when selecting is false, including replay and cold reload")
  func neutralRetention() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await StudioDrawingFixture.store(directory: root, purpose: .validationFixture)
    let first = try await store.addSource(data: FlowPortfolioTests.photo, title: "Current")
    let candidates = try await DrawingExchangeFeedbackFixture.round(store: store, source: first.id)
    try await store.selectCandidate(candidates[1].id)
    let before = await store.snapshot()
    let imported = try await store.addSource(data: FlowAuthoringFixture.image(2), title: "Retained only", selecting: false)
    let photo = PortraitPhoto(id: UUID(), data: FlowPortfolioTests.photo, label: "Exact capture", capturedAt: Date(), pose: .front)
    let captured = try await store.addCapturedSource(photo: photo, title: "Retained capture", selecting: false)
    let retry = try await store.addCapturedSource(photo: photo, title: "Retry", selecting: false)
    #expect(retry.id == captured.id && captured.photo != first.photo && imported.photo != first.photo)
    let secondPhoto = PortraitPhoto(id: UUID(), data: photo.data, label: photo.label, capturedAt: photo.capturedAt, pose: .front)
    let second = try await store.addCapturedSource(photo: secondPhoto, title: "Independent capture", selecting: false)
    #expect(second.photo != captured.photo && second.captureProvenance?.photoID != captured.captureProvenance?.photoID)
    let after = await store.snapshot()
    #expect(FlowPortfolioSelection(after) == FlowPortfolioSelection(before))
    #expect(after.sources.count == before.sources.count + 3 && after.choices == before.choices && after.pruneRevisions == before.pruneRevisions)
    try await store.reloadCommittedState()
    #expect(FlowPortfolioSelection(await store.snapshot()) == FlowPortfolioSelection(before))
    await store.closeLibrary()
    let reopened = try await StudioDrawingFixture.store(directory: root)
    #expect(FlowPortfolioSelection(await reopened.snapshot()) == FlowPortfolioSelection(before))
    #expect(try await reopened.sourceData(captured.id) == photo.data)
    await reopened.closeLibrary()
  }
  @Test("Existing Photo acquisition is selection-neutral for new and repeated occurrences and preserves the adoption owner")
  func neutralExistingPhoto() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await StudioDrawingFixture.store(directory: root)
    let first = try await store.addSource(data: FlowPortfolioTests.photo, title: "Current")
    let candidates = try await DrawingExchangeFeedbackFixture.round(store: store, source: first.id)
    try await store.selectCandidate(candidates[1].id)
    let next = try await store.addSource(data: FlowAuthoringFixture.image(2), title: "Adopt later", selecting: false)
    let before = await store.snapshot(), lease = try await store.prepareSourceAdoption(next.id)
    let existing = try await store.adoptExistingPhoto(try #require(first.photo), selecting: false)
    #expect(existing.id == first.id)
    let photo = try PortraitDrawingImages.photo(data: FlowAuthoringFixture.image(3), issuer: UUID(), captureID: UUID(),
      capturedAt: nil, importedAt: Date())
    try await store.library.commitRecords([], closure: .init(photo: photo))
    let acquired = try await store.adoptExistingPhoto(photo.reference, selecting: false)
    let repeated = try await store.adoptExistingPhoto(photo.reference, selecting: false)
    #expect(acquired.id == repeated.id && acquired.photo == photo.reference)
    #expect(FlowPortfolioSelection(await store.snapshot()) == FlowPortfolioSelection(before))
    // Successful use of the pre-acquisition lease proves owner neutrality too.
    try await store.selectSourceForPresentation(lease)
    _ = try await store.adoptExistingPhoto(photo.reference, selecting: false)
    #expect(try await store.restoreSelectionIfUnchanged(lease))
    try await store.reloadCommittedState()
    #expect(FlowPortfolioSelection(await store.snapshot()) == FlowPortfolioSelection(before))
    #expect(await store.snapshot().sources.contains { $0.id == acquired.id })
    await store.closeLibrary()
  }
  @Test("Validation rejection before publication preserves the adoption and compensation lease for retry")
  func preadmissionFailure() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await StudioDrawingFixture.store(directory: root)
    let first = try await store.addSource(data: FlowPortfolioTests.photo, title: "Current")
    let next = try await store.addSource(data: FlowAuthoringFixture.image(2), title: "Other", selecting: false)
    let lease = try await store.prepareSourceAdoption(next.id)
    await store.setAdoptionValidationTitle(first.id, title: "")
    await #expect(throws: FlowPortfolioError.self) { try await store.selectSourceForPresentation(lease) }
    #expect(await store.pendingGraphWrite == nil)
    await store.setAdoptionValidationTitle(first.id, title: first.title)
    try await store.selectSourceForPresentation(lease)
    #expect(await store.snapshot().selectedSourceID == next.id)
    await store.setAdoptionValidationTitle(first.id, title: "")
    await #expect(throws: FlowPortfolioError.self) { try await store.restoreSelectionIfUnchanged(lease) }
    #expect(await store.pendingGraphWrite == nil)
    await store.setAdoptionValidationTitle(first.id, title: first.title)
    #expect(try await store.restoreSelectionIfUnchanged(lease))
    #expect(try await store.restoreSelectionIfUnchanged(lease))
    try await store.reloadCommittedState()
    #expect(await store.snapshot().selectedSourceID == first.id)
    await store.closeLibrary()
  }
  @Test("Admitted uncertain adoption and compensation recover durably without losing retained data", arguments: [LibraryExchangeCatalogBoundary.beforeSQLPublication, .afterSQLCommit])
  func pendingFailure(_ boundary: LibraryExchangeCatalogBoundary) async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await StudioDrawingFixture.store(directory: root)
    let first = try await store.addSource(data: FlowPortfolioTests.photo, title: "Current")
    let next = try await store.addSource(data: FlowAuthoringFixture.image(2), title: "Other", selecting: false)
    let before = await store.snapshot(), lease = try await store.prepareSourceAdoption(next.id)
    try await store.library.feedbackFault(boundary)
    await #expect(throws: (any Error).self) { try await store.selectSourceForPresentation(lease) }
    #expect(await store.pendingGraphWrite != nil)
    try await store.library.feedbackFault(nil); try await store.reloadCommittedState()
    try await store.selectSourceForPresentation(lease) // Idempotent recovery replay.
    try await store.library.feedbackFault(boundary)
    await #expect(throws: (any Error).self) { try await store.restoreSelectionIfUnchanged(lease) }
    try await store.library.feedbackFault(nil); try await store.reloadCommittedState()
    #expect(try await store.restoreSelectionIfUnchanged(lease))
    let after = await store.snapshot()
    #expect(FlowPortfolioSelection(after) == FlowPortfolioSelection(before))
    #expect(after.sources.map(\.id) == before.sources.map(\.id) && after.choices.isEmpty && after.rankings.isEmpty)
    await store.closeLibrary()
    let reopened = try await StudioDrawingFixture.store(directory: root)
    #expect(await reopened.snapshot().selectedSourceID == first.id)
    await reopened.closeLibrary()
  }
  @Test("Newer same-source ownership and away-and-back selection prevent stale compensation")
  func navigationOwnership() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await StudioDrawingFixture.store(directory: root)
    let first = try await store.addSource(data: FlowPortfolioTests.photo, title: "Current")
    let next = try await store.addSource(data: FlowAuthoringFixture.image(2), title: "Other", selecting: false)
    let lease = try await store.prepareSourceAdoption(next.id)
    try await store.selectSourceForPresentation(lease)
    try await store.selectSource(next.id)
    #expect(try await store.restoreSelectionIfUnchanged(lease) == false)
    try await store.selectSource(first.id); try await store.selectSource(next.id)
    #expect(try await store.restoreSelectionIfUnchanged(lease) == false)
    try await store.reloadCommittedState()
    #expect(await store.snapshot().selectedSourceID == next.id)
    await store.closeLibrary()
  }
}

private extension FlowPortfolioStore {
  /// Inject an invalid graph before the real commit's validation/admission boundary.
  func setAdoptionValidationTitle(_ id: UUID, title: String) {
    if let index = state.sources.firstIndex(where: { $0.id == id }) { state.sources[index].title = title }
  }
}
