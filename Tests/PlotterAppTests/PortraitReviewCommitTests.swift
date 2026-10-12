import Foundation
import PortraitCore
import Testing
@testable import PortraitArtists
@testable import PortraitLibrary

private struct PortraitReviewCommitFixture {
  let store: PortraitCandidateStore
  let request: PortraitReviewGenerationRequest
  let package: DrawingPackage
  let photo: PortraitPhoto

  static func make(at root: URL) async throws -> Self {
    let store = PortraitCandidateStore(directoryURL: root)
    let producer = try await store.reviewLibraryIdentity()
    let template = try transferTestPackage(libraryID: producer)
    let photo = PortraitPhoto(id: template.origin.captureID, data: template.source.bytes,
      label: "Commit fixture", capturedAt: Date(), pose: .front)
    try await store.save(snapshot: .init(sourcePhotos: [photo]))
    let material = PortraitReviewMaterial(widthMM: template.program.fieldExtent.width,
      heightMM: template.program.fieldExtent.height,
      nominalLineWidthMM: template.program.strokes[0].style.nominalLineWidth)
    let request = try PortraitReviewGenerationRequest(captureID: photo.id, acquisitionID: photo.captureSessionID,
      source: template.source, inputs: [.init(role: "artist-input", asset: template.artistInput)], artist: template.artist,
      environmentJSON: Data("{}".utf8), conversionJSON: Data("{}".utf8), seed: nil, material: material)
    try await store.beginReviewGeneration(request)
    let package = try DrawingPackage(origin: template.origin, program: template.program, createdAt: request.createdAt,
      title: template.title, resultRecordJSON: template.resultRecordJSON, source: template.source,
      artistInput: template.artistInput, artist: template.artist, preview: template.preview)
    return .init(store: store, request: request, package: package, photo: photo)
  }
}

private final class PortraitReviewCommitCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var task: Task<PortraitReviewCommittedResult, Error>?
  private var requested = false
  func install(_ task: Task<PortraitReviewCommittedResult, Error>) {
    let cancel = lock.withLock { self.task = task; return requested }
    if cancel { task.cancel() }
  }
  func cancel() {
    let task = lock.withLock { requested = true; return self.task }
    task?.cancel()
  }
}

private final class PortraitReviewCommitFaultCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var commits = 0
  func inspect(_ fault: PortraitLibraryDatabase.Fault) throws {
    try lock.withLock {
      if fault == .afterCommit { commits += 1 }
      else if commits > 0 { throw NSError(domain: NSPOSIXErrorDomain, code: 28) }
    }
  }
}

private extension PortraitCandidateStore {
  func installReviewCommitFault(_ fault: (@Sendable (PortraitLibraryDatabase.Fault) throws -> Void)?) throws {
    try libraryDatabase().injectFault = fault
  }
}

@Suite("Experimental canonical commit admission", .serialized)
struct PortraitReviewCommitTests {
  @Test("An already cancelled queued caller cannot publish a canonical result")
  func cancelledCallerRefusesCommit() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try await PortraitReviewCommitFixture.make(at: root)
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await fixture.store.commitExperimentalReviewResult(requestID: fixture.request.id,
        package: fixture.package, sourceAdmission: .init())
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    await #expect(throws: (any Error).self) { try await fixture.store.loadDrawing(fixture.package.origin.drawingID) }
    #expect(try await fixture.store.reviewGenerationPage().first?.status == nil)
  }

  @Test("Synchronous source-epoch withdrawal refuses commit while its original photo remains live")
  func sourceEpochWithdrawal() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try await PortraitReviewCommitFixture.make(at: root), token = PortraitReviewSourceAdmissionToken()
    token.cancel()
    await #expect(throws: CancellationError.self) {
      try await fixture.store.commitExperimentalReviewResult(requestID: fixture.request.id, package: fixture.package, sourceAdmission: token)
    }
    #expect(try await fixture.store.librarySnapshot().photos.map(\.id) == [fixture.photo.id])
    await #expect(throws: (any Error).self) { try await fixture.store.loadDrawing(fixture.package.origin.drawingID) }
  }

  @Test("Deleting the exact capture refuses publication even when another live capture has identical bytes")
  func deletedSourceOccurrence() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try await PortraitReviewCommitFixture.make(at: root)
    let other = PortraitPhoto(id: UUID(), data: fixture.photo.data, label: "Independent occurrence",
      capturedAt: Date(), pose: .front)
    var archive = await fixture.store.load().archive
    archive.sourcePhotos = [other]
    archive.tombstones.append(.init(id: UUID(), kind: .photo, identity: fixture.photo.id.uuidString,
      affectedCandidateIDs: [], assetSHA256s: [], createdAt: Date()))
    try await fixture.store.save(snapshot: archive)
    await #expect(throws: (any Error).self) {
      try await fixture.store.commitExperimentalReviewResult(requestID: fixture.request.id,
        package: fixture.package, sourceAdmission: .init())
    }
    #expect(try await fixture.store.librarySnapshot().photos.map(\.id) == [other.id])
    await #expect(throws: (any Error).self) { try await fixture.store.loadDrawing(fixture.package.origin.drawingID) }
    #expect(try await fixture.store.reviewGenerationPage().first?.status == nil)
  }

  @Test("A wrong source package cannot create a saved row")
  func mismatchedSource() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try await PortraitReviewCommitFixture.make(at: root)
    var alternateEncoding = fixture.package.source.bytes
    alternateEncoding.append(0) // Valid decoded image, different original bytes and SHA.
    let unrelated = DrawingPackageAsset(mediaType: "image/png", bytes: alternateEncoding, pixelWidth: 1, pixelHeight: 1)
    try DrawingPackageLibraryValidation.validateImage(unrelated)
    let package = try DrawingPackage(origin: fixture.package.origin, program: fixture.package.program,
      createdAt: fixture.package.createdAt, title: fixture.package.title, resultRecordJSON: fixture.package.resultRecordJSON,
      source: unrelated, artistInput: fixture.package.artistInput, artist: fixture.package.artist, preview: fixture.package.preview)
    await #expect(throws: (any Error).self) {
      try await fixture.store.commitExperimentalReviewResult(requestID: fixture.request.id, package: package, sourceAdmission: .init())
    }
    await #expect(throws: (any Error).self) { try await fixture.store.loadDrawing(package.origin.drawingID) }
  }

  @Test("Cancellation after the canonical database commit preserves saved drawing and succeeded outcome")
  func lateCancellationIsCommittedSuccess() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try await PortraitReviewCommitFixture.make(at: root), token = PortraitReviewSourceAdmissionToken()
    let control = PortraitReviewCommitCancellation()
    try await fixture.store.installReviewCommitFault { point in
      if point == .afterCommit { token.cancel(); control.cancel() }
    }
    let task = Task {
      try await fixture.store.commitExperimentalReviewResult(requestID: fixture.request.id,
        package: fixture.package, sourceAdmission: token)
    }
    control.install(task)
    let committed = try await task.value
    #expect(task.isCancelled && token.isCancelled)
    #expect(committed.drawing.transferredPackage == fixture.package)
    #expect(committed.outcome?.status == .succeeded && committed.evidenceError == nil)
    #expect(try await fixture.store.reviewGenerationPage().first?.status == .succeeded)
    #expect(try await PortraitCandidateStore(directoryURL: root).loadDrawing(fixture.package.origin.drawingID) == committed.drawing)
    await #expect(throws: (any Error).self) {
      try await fixture.store.finishReviewGeneration(id: fixture.request.id, status: .cancelled, reason: "late cancel")
    }
  }

  @Test("A journal failure after import returns explicit saved evidence-pending state and can finalize later")
  func partialJournalFailureIsNotNoResult() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try await PortraitReviewCommitFixture.make(at: root), counter = PortraitReviewCommitFaultCounter()
    try await fixture.store.installReviewCommitFault { try counter.inspect($0) }
    let committed = try await fixture.store.commitExperimentalReviewResult(requestID: fixture.request.id,
      package: fixture.package, sourceAdmission: .init())
    #expect(committed.drawing.transferredPackage == fixture.package)
    #expect(committed.outcome == nil && committed.evidenceError != nil)
    #expect(try await fixture.store.loadDrawing(fixture.package.origin.drawingID) == committed.drawing)
    #expect(try await fixture.store.reviewGenerationPage().first?.status == nil)
    try await fixture.store.installReviewCommitFault(nil)
    let recovered = try await fixture.store.commitExperimentalReviewResult(requestID: fixture.request.id,
      package: fixture.package, sourceAdmission: .init())
    #expect(recovered.outcome?.status == .succeeded && recovered.evidenceError == nil)
    #expect(recovered.drawing == committed.drawing)
  }
}
