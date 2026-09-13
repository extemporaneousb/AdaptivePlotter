import Foundation
import PlotterModel
import PlotterRuntime
import Testing
@testable import PlotterApp

@Suite("Durable drawing materials")
@MainActor
struct DrawingMaterialLibraryTests {
  @Test("queued creation and selection survive restart without FIFO removal")
  func restart() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let library = DrawingMaterialLibrary(store: .init(directoryURL: directory))
    for index in 0..<40 {
      #expect(library.createNominal(name: "Pen \(index)", widthMM: 0.4 + Double(index) / 100) == nil)
    }
    let expected = library.records
    let active = library.activeKey
    await library.flush()
    #expect(library.persistenceError == nil)
    #expect(library.pendingMutationCount == 0)
    let restored = DrawingMaterialLibrary(store: .init(directoryURL: directory))
    await restored.load()
    #expect(restored.records == expected)
    #expect(restored.records.count == 40)
    #expect(restored.activeKey == active)
  }

  @Test("immutable revision cannot be changed in memory or on disk")
  func immutableRevision() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let record = try DrawingMaterialRecord(profile: .init(name: "Marker", nominalWidthMM: 0.8))
    let conflict = try DrawingMaterialRecord(profile: .init(id: record.profile.id,
      name: "Changed", nominalWidthMM: 1.2, createdAt: record.profile.createdAt))
    let store = DrawingMaterialStore(directoryURL: directory)
    let library = DrawingMaterialLibrary(store: store)
    #expect(library.add(record) == nil)
    #expect(library.add(record) == nil)
    #expect(library.add(conflict) != nil)
    await library.flush()
    do {
      try await store.save(.init(records: [conflict]))
      Issue.record("Conflicting revision must be refused")
    } catch {}
    #expect(try await store.load().records == [record])
  }

  @Test("pending add merges with loaded records and preserves their selection")
  func queuedLoadMerge() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let saved = try DrawingMaterialRecord(profile: .init(name: "Saved", nominalWidthMM: 1))
    let added = try DrawingMaterialRecord(profile: .init(name: "New", nominalWidthMM: 0.5))
    let store = DrawingMaterialStore(directoryURL: directory)
    try await store.save(.init(records: [saved], activeKey: saved.profile.key))
    let library = DrawingMaterialLibrary(store: store)
    #expect(library.add(added) == nil)
    await library.flush()
    #expect(library.records == [saved, added])
    #expect(library.activeKey == saved.profile.key)
  }

  @Test("corrupt index is preserved and blocks pending save")
  func corruption() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let index = directory.appendingPathComponent("index-v1.json")
    let damaged = Data("corrupt archive".utf8)
    try damaged.write(to: index)
    let library = DrawingMaterialLibrary(store: .init(directoryURL: directory))
    #expect(library.createNominal(name: "Pending", widthMM: 1) == nil)
    await library.flush()
    #expect(library.persistenceError != nil)
    #expect(library.pendingMutationCount == 2)
    #expect(try Data(contentsOf: index) == damaged)
    await library.retry()
    #expect(library.persistenceError != nil)
    #expect(try Data(contentsOf: index) == damaged)
  }

  @Test("disk failure stays pending and retry persists exact mutation")
  func failedSaveRetry() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let obstruction = directory.appendingPathComponent("fail-write")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data().write(to: obstruction)
    let store = DrawingMaterialStore(directoryURL: directory, write: { bytes, url in
      if FileManager.default.fileExists(atPath: obstruction.path) {
        throw CocoaError(.fileWriteOutOfSpace)
      }
      try bytes.write(to: url, options: .atomic)
    })
    let library = DrawingMaterialLibrary(store: store)
    #expect(library.createNominal(name: "Keep exactly", widthMM: 0.7) == nil)
    let records = library.records
    await library.flush()
    #expect(library.persistenceError != nil)
    #expect(library.pendingMutationCount == 2)
    #expect(!library.isSaving)
    try FileManager.default.removeItem(at: obstruction)
    await library.retry()
    #expect(library.persistenceError == nil)
    #expect(library.pendingMutationCount == 0)
    #expect(try await store.load().records == records)
  }

  @Test("explicit deletion clears active selection and preserves other revisions")
  func deletion() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let library = DrawingMaterialLibrary(store: .init(directoryURL: directory))
    #expect(library.createNominal(name: "One", widthMM: 0.5) == nil)
    let one = try #require(library.activeRecord)
    #expect(library.createNominal(name: "Two", widthMM: 1) == nil)
    let two = try #require(library.activeRecord)
    await library.flush()
    #expect(library.delete(key: two.profile.key) == nil)
    await library.flush()
    let restored = DrawingMaterialLibrary(store: .init(directoryURL: directory))
    await restored.load()
    #expect(restored.records == [one])
    #expect(restored.activeRecord == nil)
    #expect(restored.activate(key: "missing") != nil)
    #expect(restored.activate(key: one.profile.key) == nil)
    await restored.flush()
    #expect(try await DrawingMaterialStore(directoryURL: directory).load().activeKey == one.profile.key)
  }

  @Test("deleted revision identity cannot be reused with changed data after restart")
  func deletedIdentity() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let library = DrawingMaterialLibrary(store: .init(directoryURL: directory))
    #expect(library.createNominal(name: "Original", widthMM: 1) == nil)
    let original = try #require(library.activeRecord)
    await library.flush()
    #expect(library.delete(key: original.profile.key) == nil)
    await library.flush()
    let restored = DrawingMaterialLibrary(store: .init(directoryURL: directory))
    await restored.load()
    let changed = try DrawingMaterialRecord(profile: .init(id: original.profile.id,
      name: "Changed", nominalWidthMM: 2, createdAt: original.profile.createdAt))
    #expect(restored.add(changed) != nil)
    #expect(restored.records.isEmpty)
    #expect(restored.add(original) == nil)
    await restored.flush()
    #expect(restored.records == [original])
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("drawing-material-\(UUID().uuidString)", isDirectory: true)
  }
}
