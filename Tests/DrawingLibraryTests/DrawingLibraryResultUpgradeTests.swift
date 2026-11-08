import Foundation
@testable import DrawingLibrary
import PortraitCore
import Testing

private enum ResultUpgradeFailure: Error { case boundary }
private extension DrawingLibrary {
  func upgradeFault(_ boundary: LibraryExchangeCatalogBoundary?) throws {
    guard let boundary else { cachedExchangeCatalog?.injectFault = nil; return }
    let catalog = try commonCatalog()
    catalog.injectFault = { if $0 == boundary { throw ResultUpgradeFailure.boundary } }
  }
  func publishResultDomainOperation(_ source: URL, record: DrawingLibraryRecord, intent: UUID) throws {
    let staging = FileManager.default.temporaryDirectory.appendingPathComponent("dx06-domain-result-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: staging) }
    let staged = try DrawingExchangeCarrier.stageDirectory(source, stagingParent: staging)
    let admitted = try ExchangeAdmission.validate(staged)
    let batch = DrawingLibraryRecordBatch(records: [record], removing: [])
    let commit = DrawingLibraryDomainCommit(intent: intent, request: try domainRequest(batch, assets: []), batch: batch, retained: [])
    let catalog = try commonCatalog()
    defer { refreshOwnership() }
    _ = try catalog.publish(admitted, domainCommit: commit)
  }
  func resultTransactionCount(_ ref: DrawingLibraryResultRef) throws -> Int {
    guard let db = try commonReadDatabase() else { return 0 }
    return Int(try db.scalar("SELECT COUNT(*) FROM dx_transaction WHERE index_digest=? AND package_digest=?", [ref.indexDigest.description, ref.packageDigest.description]) ?? "0") ?? 0
  }
}

@Suite("DX06 supported closure upgrade and canonical publication", .serialized)
struct DrawingLibraryResultUpgradeTests {
  private func root() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("dx06-upgrade-" + UUID().uuidString)
  }
  private func authored(_ frozen: FrozenDrawingRecord) throws -> DrawingLibraryResultFixture {
    var fixture = try DrawingLibraryResultFixture(drawing: frozen, marker: "known-authored")
    fixture.index["kind"] = "drawing"
    fixture.index["jobs"] = [String]()
    fixture.index["attempts"] = [String]()
    fixture.payload = fixture.payload.filter { !$0.key.hasPrefix("data/jobs/") && !$0.key.hasPrefix("data/attempts/") }
    return fixture
  }

  @Test("Opaque result followed by explicit known authored import atomically enables the same exact Drawing", arguments: [LibraryExchangeCatalogBoundary.beforeSQLCommit, .afterSQLCommit])
  func authoredUpgrade(boundary: LibraryExchangeCatalogBoundary) async throws {
    let root = root(); defer { try? FileManager.default.removeItem(at: root) }
    let frozen = try DrawingLibraryResultFixture.drawing()
    let opaque = try DrawingLibraryResultFixture(drawing: frozen, features: ["example.opaque-upgrade/1"])
    let opaqueURL = root.appendingPathComponent("opaque")
    try opaque.write(to: opaqueURL)
    let knownURL = root.appendingPathComponent("known")
    try authored(frozen).write(to: knownURL)
    let directory = root.appendingPathComponent("library")
    let owner = DrawingLibrary(directoryURL: directory)
    let resultRef = try await owner.mountResult(from: opaqueURL).reference
    let opaqueBytes = try DrawingLibraryResultFixture.bytes(await owner.result(resultRef))
    #expect(try await owner.drawings().entries.isEmpty)
    await #expect(throws: (any Error).self) { try await owner.drawing(frozen.reference) }
    try await owner.upgradeFault(boundary)
    await #expect(throws: ResultUpgradeFailure.self) { try await owner.importDrawings(from: knownURL) }
    #expect(try await owner.drawings().entries.count == (boundary == .beforeSQLCommit ? 0 : 1))
    #expect(try await owner.results().entries.map(\.reference) == [resultRef])
    try await owner.upgradeFault(nil)
    try await owner.recover()
    #expect(try await owner.importDrawings(from: knownURL) == [frozen.reference])
    #expect(try await owner.drawings().entries.map(\.reference) == [frozen.reference])
    await owner.closeLibrary()
    let reader = DrawingLibrary(directoryURL: directory)
    #expect(try await reader.drawings().entries.map(\.reference) == [frozen.reference])
    let drawing = try await reader.drawing(frozen.reference)
    #expect(drawing.reference == frozen.reference && drawing.program == frozen.drawing.program)
    #expect(drawing.capabilities.supported.contains(.plot))
    let originalResult = try await reader.result(resultRef)
    if case .opaque? = originalResult.drawings[frozen.reference] {} else { Issue.record("Known authored import rewrote opaque result context") }
    #expect(try DrawingLibraryResultFixture.bytes(originalResult) == opaqueBytes)
    let authoredExport = root.appendingPathComponent("authored-export.zip")
    let opaqueExport = root.appendingPathComponent("opaque-export.zip")
    try await reader.exportDrawing(frozen.reference, to: authoredExport)
    try await reader.exportResult(resultRef, to: opaqueExport)
    let offline = DrawingLibrary(directoryURL: root.appendingPathComponent("offline"))
    #expect(try await offline.importDrawings(from: authoredExport) == [frozen.reference])
    let offlineResult = try await offline.mountResult(from: opaqueExport).reference
    #expect(offlineResult == resultRef)
    #expect(try DrawingLibraryResultFixture.bytes(await offline.result(offlineResult)) == opaqueBytes)
    await reader.closeLibrary()
    await offline.closeLibrary()
  }

  @Test("Known closure upgrade respects rename or tombstone made after preparation", arguments: [false, true])
  func upgradeMetadata(deleted: Bool) async throws {
    let root = root(); defer { try? FileManager.default.removeItem(at: root) }
    let frozen = try DrawingLibraryResultFixture.drawing()
    let opaque = try DrawingLibraryResultFixture(drawing: frozen, features: ["example.opaque-metadata/1"])
    let opaqueURL = root.appendingPathComponent("opaque")
    try opaque.write(to: opaqueURL)
    let knownURL = root.appendingPathComponent("known")
    try authored(frozen).write(to: knownURL)
    let staging = root.appendingPathComponent("staging")
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    let admitted = try ExchangeAdmission.validate(DrawingExchangeCarrier.stageDirectory(knownURL, stagingParent: staging))
    guard case .materialized(let known)? = admitted.drawings[frozen.reference] else { Issue.record("Known fixture was not materialized"); return }
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("library"))
    let opaqueRef = try await library.mountResult(from: opaqueURL).reference
    try await library.rename(frozen.reference, title: "Before preparation")
    // A foreign materialized value alone cannot override the local opaque
    // context. Only its explicitly supplied admitted publication may upgrade it.
    await #expect(throws: (any Error).self) {
      try await library.prepareRetention(known.drawing, reason: "bare-value-without-closure")
    }
    let prepared = try await library.prepareRetention(known.drawing, reason: "explicit-import", closure: .init(publication: admitted))
    #expect(prepared.reference == frozen.reference)
    #expect(try await library.drawings().entries.isEmpty)
    await #expect(throws: (any Error).self) { try await library.drawing(frozen.reference) }
    if deleted {
      try await library.delete(frozen.reference)
      do {
        _ = try await library.commitRetention(prepared)
        Issue.record("Upgrade revived a tombstoned Drawing")
      } catch DrawingLibraryError.deleted(let ref) { #expect(ref == frozen.reference) }
      #expect(try await library.drawings().entries.isEmpty)
    } else {
      try await library.rename(frozen.reference, title: "After preparation")
      #expect(try await library.commitRetention(prepared).reference == frozen.reference)
      let entry = try #require(try await library.drawings().entries.first)
      #expect(entry.reference == frozen.reference && entry.title == "After preparation")
      #expect(try await library.drawing(frozen.reference).program == frozen.drawing.program)
    }
    let result = try await library.result(opaqueRef)
    if case .opaque? = result.drawings[frozen.reference] {} else { Issue.record("Upgrade mutated opaque publication") }
    await library.closeLibrary()
  }

  @Test("Same result inventory in another real domain transaction lists once without losing its operation", arguments: [false, true])
  func canonicalPublicationWithDomainOperation(uncertain: Bool) async throws {
    let root = root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryResultFixture()
    let input = root.appendingPathComponent("input")
    try fixture.write(to: input)
    let directory = root.appendingPathComponent("library")
    let library = DrawingLibrary(directoryURL: directory)
    let mounted = try await library.mountResult(from: input)
    let bytes = try DrawingLibraryResultFixture.bytes(await library.result(mounted.reference))
    let operation = DrawingLibraryRecord(kind: "example.result-operation/1", id: UUID(), payload: Data("{\"decision\":\"explicit-domain-publication\"}".utf8), drawings: [fixture.frozen.reference])
    let intent = UUID()
    if uncertain { try await library.upgradeFault(.afterSQLCommit) }
    if uncertain {
      await #expect(throws: ResultUpgradeFailure.self) { try await library.publishResultDomainOperation(input, record: operation, intent: intent) }
    } else { try await library.publishResultDomainOperation(input, record: operation, intent: intent) }
    #expect(try await library.resultTransactionCount(mounted.reference) == 2)
    #expect(try await library.record(operation.key)?.payload == operation.payload)
    #expect(try await library.results().entries.map(\.reference) == [mounted.reference])
    #expect(try await library.results(for: fixture.frozen.reference).entries.map(\.reference) == [mounted.reference])
    try await library.upgradeFault(nil)
    try await library.recover()
    try await library.publishResultDomainOperation(input, record: operation, intent: intent)
    #expect(try await library.resultTransactionCount(mounted.reference) == 2)
    await library.closeLibrary()
    let reopened = DrawingLibrary(directoryURL: directory)
    #expect(try await reopened.results().entries.map(\.reference) == [mounted.reference])
    #expect(try await reopened.results(for: fixture.frozen.reference).entries.map(\.reference) == [mounted.reference])
    #expect(try await reopened.record(operation.key)?.payload == operation.payload)
    #expect(try DrawingLibraryResultFixture.bytes(await reopened.result(mounted.reference)) == bytes)
    let exported = root.appendingPathComponent("canonical.zip")
    try await reopened.exportResult(mounted.reference, to: exported)
    let offline = DrawingLibrary(directoryURL: root.appendingPathComponent("offline"))
    let ref = try await offline.mountResult(from: exported).reference
    #expect(ref == mounted.reference)
    #expect(try DrawingLibraryResultFixture.bytes(await offline.result(ref)) == bytes)
    await reopened.closeLibrary()
    await offline.closeLibrary()
  }
}
