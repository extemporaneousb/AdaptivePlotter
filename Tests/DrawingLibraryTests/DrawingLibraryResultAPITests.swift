import Foundation
import DrawingLibrary
import PortraitCore
import Testing

private enum ResultPublicationFailure: Error { case boundary }
private extension DrawingLibrary {
  func resultFailAt(_ boundary: LibraryExchangeCatalogBoundary?) throws {
    guard let boundary else { cachedExchangeCatalog?.injectFault = nil; return }
    let catalog = try commonCatalog()
    catalog.injectFault = { actual in
      if actual == boundary { throw ResultPublicationFailure.boundary }
    }
  }
}

@Suite("DX06 inert result public API", .serialized)
struct DrawingLibraryResultAPITests {
  private func root() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("dx06-results-" + UUID().uuidString)
  }
  private func input(_ fixture: DrawingLibraryResultFixture, at root: URL, name: String = "input") throws -> URL {
    let url = root.appendingPathComponent(name)
    try fixture.write(to: url)
    return url
  }

  @Test("Sequence N mounts into an empty owner as a finite unsealed chain and exports offline exact bytes")
  func finiteChainOffline() async throws {
    let root = root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryResultFixture()
    let source = try input(fixture, at: root)
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("library"))
    let mounted = try await library.mountResult(from: source)
    #expect(!mounted.wasAlreadyMounted)
    let result = try await library.result(mounted.reference)
    let original = try DrawingLibraryResultFixture.bytes(result)
    #expect(result.index.originalJSON == (try DrawingLibraryResultFixture.json(fixture.index)))
    #expect(Set(result.attempts.keys) == Set(fixture.snapshots))
    #expect(result.receipts[fixture.job]?.drawing == fixture.frozen.reference)
    #expect(result.attempts.values.allSatisfy { !$0.sealed && $0.state == "running" && $0.job == fixture.job && $0.drawing == fixture.frozen.reference })
    for (position, ref) in fixture.snapshots.enumerated() {
      #expect(result.attempts[ref]?.previous == (position == 0 ? nil : fixture.snapshots[position - 1].digest))
    }
    #expect(try result.files.record(fixture.media.object) == fixture.payload["data/objects/sha256/" + fixture.media.object.description])
    #expect(!result.capabilities.supported.contains(.interpretResults))
    #expect(!result.capabilities.supported.contains(.physicalInterpretation))
    let page = try await library.results(for: fixture.frozen.reference)
    #expect(page.entries.map(\.reference) == [mounted.reference])
    #expect(page.entries.first?.drawingReferences == [fixture.frozen.reference])
    #expect(page.entries.first?.jobReferences == [fixture.job])
    #expect(page.entries.first?.attemptReferences == Array(fixture.snapshots.suffix(1)))
    let export = root.appendingPathComponent("offline.zip")
    try await library.exportResult(mounted.reference, to: export)
    await library.closeLibrary()
    try FileManager.default.removeItem(at: root.appendingPathComponent("library"))
    try FileManager.default.removeItem(at: source)
    let offline = DrawingLibrary(directoryURL: root.appendingPathComponent("offline"))
    let imported = try await offline.mountResult(from: export)
    #expect(imported.reference == mounted.reference)
    #expect(try DrawingLibraryResultFixture.bytes(await offline.result(imported.reference)) == original)
    await offline.closeLibrary()
  }

  @Test("Refused job preserves its exact receipt with zero attempts and no invented run")
  func refusedJob() async throws {
    let root = root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryResultFixture(refused: true)
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("library"))
    let mounted = try await library.mountResult(from: input(fixture, at: root))
    let result = try await library.result(mounted.reference)
    #expect(result.attempts.isEmpty)
    #expect(result.receipts.count == 1)
    #expect(result.receipts[fixture.job]?.disposition == "refused")
    #expect(result.receipts[fixture.job]?.issuance == nil)
    #expect(try await library.results(for: fixture.frozen.reference).entries.first?.attemptReferences.isEmpty == true)
    await library.closeLibrary()
  }

  @Test("Identical delivery and uncertain COMMIT retry keep one publication identity", arguments: [false, true])
  func duplicateAndUncertainCommit(inject: Bool) async throws {
    let root = root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryResultFixture()
    let source = try input(fixture, at: root)
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("library"))
    try await library.open()
    if inject {
      try await library.resultFailAt(.afterSQLCommit)
      await #expect(throws: ResultPublicationFailure.self) { try await library.mountResult(from: source) }
      #expect(try await library.results(for: fixture.frozen.reference).entries.count == 1)
      try await library.resultFailAt(nil)
      try await library.recover()
    }
    let first = try await library.mountResult(from: source)
    let second = try await library.mountResult(from: source)
    #expect(first.wasAlreadyMounted == inject)
    #expect(second.wasAlreadyMounted)
    #expect(first.reference == second.reference)
    #expect(try await library.drawings().entries.map(\.reference) == [fixture.frozen.reference])
    #expect(try await library.results(for: fixture.frozen.reference).entries.map(\.reference) == [first.reference])
    await library.closeLibrary()
    let reopened = DrawingLibrary(directoryURL: root.appendingPathComponent("library"))
    #expect(try await reopened.result(first.reference).attempts.count == 3)
    await reopened.closeLibrary()
  }

  @Test("Pre-SQL failure publishes no visible partial result and explicit recovery publishes all", arguments: [LibraryExchangeCatalogBoundary.beforeSQLPublication, .beforeSQLCommit])
  func atomicRecovery(boundary: LibraryExchangeCatalogBoundary) async throws {
    let root = root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryResultFixture()
    let source = try input(fixture, at: root)
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("library"))
    try await library.open()
    try await library.resultFailAt(boundary)
    await #expect(throws: ResultPublicationFailure.self) { try await library.mountResult(from: source) }
    #expect(try await library.results(for: fixture.frozen.reference).entries.isEmpty)
    #expect(try await library.drawings().entries.isEmpty)
    try await library.resultFailAt(nil)
    try await library.recover()
    let entry = try #require(try await library.results(for: fixture.frozen.reference).entries.first)
    let result = try await library.result(entry.reference)
    #expect(Set(result.attempts.keys) == Set(fixture.snapshots))
    #expect(try await library.drawings().entries.map(\.reference) == [fixture.frozen.reference])
    #expect(result.receipts.count == 1)
    #expect(try await library.mountResult(from: source).wasAlreadyMounted)
    await library.closeLibrary()
  }

  @Test("Divergent sequence or receipt is quarantined while the prior publication remains unchanged", arguments: ["sequence", "receipt"])
  func conflicts(kind: String) async throws {
    let root = root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryResultFixture(refused: kind == "receipt")
    let source = try input(fixture, at: root)
    let libraryRoot = root.appendingPathComponent("library")
    let library = DrawingLibrary(directoryURL: libraryRoot)
    let prior = try await library.mountResult(from: source)
    let bytes = try DrawingLibraryResultFixture.bytes(await library.result(prior.reference))
    var changed = fixture
    if kind == "sequence" {
      try changed.rewriteTip { $0["fixtureExtension"] = "different immutable sequence bytes" }
    } else {
      changed = try DrawingLibraryResultFixture(drawing: fixture.frozen, refused: true, marker: "divergent", jobID: fixture.job.handle)
    }
    let changedSource = try input(changed, at: root, name: "changed")
    do {
      _ = try await library.mountResult(from: changedSource)
      Issue.record("Divergent immutable identity was accepted")
    } catch DrawingLibraryError.quarantinedConflict(let preserved) {
      #expect(FileManager.default.fileExists(atPath: preserved.path))
    }
    #expect(try await library.results(for: fixture.frozen.reference).entries.map(\.reference) == [prior.reference])
    #expect(try DrawingLibraryResultFixture.bytes(await library.result(prior.reference)) == bytes)
    await library.closeLibrary()
  }

  @Test("Invalid closed result dependencies refuse before any visible publication", arguments: ["predecessor", "media", "drawing", "job", "refusal-attempt", "accepted-zero", "index-profile"])
  func invalidClosure(kind: String) async throws {
    let root = root(); defer { try? FileManager.default.removeItem(at: root) }
    var fixture = try DrawingLibraryResultFixture(count: kind == "accepted-zero" ? 0 : 3)
    switch kind {
    case "predecessor": fixture.payload.removeValue(forKey: DrawingLibraryResultFixture.snapshotPath(fixture.snapshots[0]))
    case "media": fixture.payload.removeValue(forKey: "data/objects/sha256/" + fixture.media.object.description)
    case "drawing":
      let different = DrawingRef(issuer: fixture.frozen.reference.issuer, revision: UUID(), digest: fixture.frozen.reference.digest)
      try fixture.rewriteTip { object in
        object["drawing"] = try DrawingLibraryResultFixture.wire(different)
      }
    case "job":
      let different = JobReceiptRef(handle: .init(engine: UUID(), job: UUID()), receiptDigest: fixture.job.receiptDigest)
      try fixture.rewriteTip { $0["job"] = try DrawingLibraryResultFixture.wire(different) }
    case "refusal-attempt":
      fixture = try DrawingLibraryResultFixture(refused: true, includeRefusedAttempts: true)
    case "index-profile": fixture.index["profile"] = "adaptiveplotter.exchange/9"
    default: break
    }
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("library"))
    await #expect(throws: (any Error).self) { try await library.mountResult(from: input(fixture, at: root)) }
    #expect(try await library.results(for: fixture.frozen.reference).entries.isEmpty)
    await library.closeLibrary()
  }

  @Test("Unknown required feature is preserved and exported without interpreted result authority")
  func unsupportedFeatures() async throws {
    let root = root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryResultFixture(features: ["example.required-result/1"])
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("library"))
    let mounted = try await library.mountResult(from: input(fixture, at: root))
    let result = try await library.result(mounted.reference)
    #expect(result.capabilities.supported.contains(.inspect))
    #expect(result.capabilities.supported.contains(.preserve))
    #expect(!result.capabilities.supported.contains(.interpretResults))
    #expect(!result.capabilities.supported.contains(.physicalInterpretation))
    #expect(result.capabilities.unsupportedReasons.contains { $0.contains("example.required-result/1") })
    let bytes = try DrawingLibraryResultFixture.bytes(result)
    let export = root.appendingPathComponent("unsupported")
    try await library.exportResult(mounted.reference, to: export)
    let other = DrawingLibrary(directoryURL: root.appendingPathComponent("other"))
    let again = try await other.mountResult(from: export)
    #expect(again.reference == mounted.reference)
    #expect(try DrawingLibraryResultFixture.bytes(await other.result(again.reference)) == bytes)
    await library.closeLibrary(); await other.closeLibrary()
  }
}
