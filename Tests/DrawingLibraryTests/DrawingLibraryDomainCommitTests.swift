import DrawingLibrary
import Foundation
import PortraitCore
import Testing

@Suite("Drawing-first domain transaction identity", .serialized)
struct DrawingLibraryDomainCommitTests {
  private func root() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("drawing-domain-" + UUID().uuidString)
  }
  private func row(id: UUID, value: Int) -> DrawingLibraryRecord {
    .init(kind: "example.rank/1", id: id, payload: Data("{\"value\":\(value)}".utf8))
  }

  @Test("Record-only batches retain distinct operation identity even without media")
  func independentEmptyAssetCommits() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let library = DrawingLibrary(directoryURL: directory)
    let first = row(id: UUID(), value: 1), second = row(id: UUID(), value: 2)
    // Empty media produces the same semantic exchange index regardless of batch.
    try await library.commitRecords([first])
    try await library.commitRecords([second])
    let records = try await library.records(kind: first.kind)
    #expect(Set(records.map(\.id)) == Set([first.id, second.id]))
    #expect(records.first(where: { $0.id == first.id })?.payload == first.payload)
    #expect(records.first(where: { $0.id == second.id })?.payload == second.payload)
    await library.closeLibrary()
  }

  @Test("Exact committed retry cannot overwrite a newer entity; changed payload conflicts")
  func requestBoundRetry() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let library = DrawingLibrary(directoryURL: directory)
    let id = UUID(), intent = DrawingLibraryCommitIntent()
    let original = row(id: id, value: 1), updated = row(id: id, value: 2)
    try await library.commitRecords([original], intent: intent)
    try await library.commitRecords([updated])
    try await library.commitRecords([original], intent: intent)
    #expect(try await library.records(kind: original.kind).first?.payload == updated.payload)
    await #expect(throws: (any Error).self) {
      try await library.commitRecords([row(id: id, value: 3)], intent: intent)
    }
    #expect(try await library.records(kind: original.kind).count == 1)
    #expect(try await library.records(kind: original.kind).first?.payload == updated.payload)
    await library.closeLibrary()
  }

  @Test("Independent asset reads do not acquire a writer or initialize an empty root")
  func pureAssetReader() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let bytes = Data("current-format media".utf8), digest = ExchangeDigest.hash(bytes)
    let empty = DrawingLibrary(directoryURL: directory)
    await #expect(throws: (any Error).self) { try await empty.asset(digest) }
    #expect(!FileManager.default.fileExists(atPath: directory.path))
    await empty.closeLibrary()
    let writer = DrawingLibrary(directoryURL: directory)
    let asset = try ExchangeAsset(bytes: bytes, mediaType: "application/octet-stream", encoding: "example.bytes/1")
    let row = DrawingLibraryRecord(kind: "example.asset/1", id: UUID(), payload: Data("{}".utf8), assets: [digest])
    try await writer.commitRecords([row], assets: [.init(descriptor: .init(asset: asset), bytes: bytes)])
    let reader = DrawingLibrary(directoryURL: directory)
    #expect(try await reader.asset(digest) == bytes)
    await reader.closeLibrary()
    #expect(try await writer.records(kind: row.kind).count == 1)
    await writer.closeLibrary()
  }
}
