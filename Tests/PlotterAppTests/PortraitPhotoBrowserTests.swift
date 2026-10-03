import Foundation
import PlotterModel
import Testing
@testable import PlotterApp

@Suite("Bounded retained photo browser", .serialized)
@MainActor
struct PortraitPhotoBrowserTests {
  @Test("metadata pages are newest first, bounded to 100 and leave the complete archive unloaded")
  func metadataPaging() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let photos = (0..<205).map { photo(index: $0) }
    let store = PortraitCandidateStore(directoryURL: directory)
    try await store.save(snapshot: .init(sourcePhotos: photos))
    let index = directory.appendingPathComponent("index-v1.json")
    let committed = try Data(contentsOf: index)
    let reader = PortraitCandidateStore(directoryURL: directory)
    let collection = PortraitSketchCollection(store: reader)
    await collection.loadPhotoBrowser()
    #expect(collection.photoReferences.map(\.id) == Array(photos.reversed().prefix(100)).map(\.id))
    #expect(collection.photoHasMore && !collection.historyLoadHasCompleted)
    #expect(collection.entries.isEmpty && collection.sourcePhotos.isEmpty)
    #expect(await reader.assetBytesVerified == 0)
    await collection.loadMorePhotos()
    #expect(collection.photoReferences.count == 200 && collection.photoHasMore)
    await collection.loadMorePhotos()
    #expect(collection.photoReferences.count == 205 && !collection.photoHasMore)
    #expect(collection.photoReferences.map(\.id) == photos.reversed().map(\.id))
    #expect(try Data(contentsOf: index) == committed)
    let selected = try await collection.photoForBrowsing(photos[7].id)
    #expect(selected == photos[7])
  }

  @Test("browsing needs neither candidate records nor raster or original bytes; selecting corrupt pixels refuses")
  func noGeometryOrAssetMaterialization() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let candidate = try portraitPersistenceCandidate()
    let store = PortraitCandidateStore(directoryURL: directory)
    try await store.save(snapshot: .init(entries: [.init(candidate: candidate, reasons: [])]))
    try FileManager.default.removeItem(at: directory.appendingPathComponent("records"))
    let asset = directory.appendingPathComponent("assets").appendingPathComponent(candidate.sourceSHA256)
    try Data([4, 3, 2, 1]).write(to: asset)
    let reader = PortraitCandidateStore(directoryURL: directory)
    let page = try reader.loadPhotoPage()
    #expect(page.photos.map(\.id) == [candidate.photoID])
    #expect(page.candidateRecordsRead == 0)
    #expect(throws: (any Error).self) { try reader.loadPhoto(page.photos[0]) }
    #expect(!(await reader.load()).canWrite)
  }

  @Test("pre-catalog indexes expose standalone photos first then scan at most 100 candidate metadata records per page")
  func legacyBoundedFallback() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let candidates = try (0..<205).map { try portraitPersistenceCandidate(seed: UInt64($0)) }
    let original = photo(index: 300)
    try await PortraitCandidateStore(directoryURL: directory).save(snapshot: .init(
      entries: candidates.map { .init(candidate: $0, reasons: []) }, sourcePhotos: [original]))
    try removePhotoCatalog(directory)
    let index = directory.appendingPathComponent("index-v1.json")
    let before = try Data(contentsOf: index)
    let reader = PortraitCandidateStore(directoryURL: directory)
    var page = try reader.loadPhotoPage()
    #expect(page.photos.map(\.id) == [original.id] && page.candidateRecordsRead == 0)
    var sources = page.photos
    var counts: [Int] = []
    while let cursor = page.next {
      page = try reader.loadPhotoPage(after: cursor)
      counts.append(page.candidateRecordsRead)
      sources += page.photos
    }
    #expect(counts == [100, 100, 5])
    #expect(Set(sources.map(\.id)) == Set(candidates.map(\.photoID) + [original.id]))
    let reference = try #require(sources.first { $0.id == candidates[4].photoID })
    #expect(try reader.loadPhoto(reference).data == candidates[4].sourceData)
    #expect(await reader.assetBytesVerified == 0)
    #expect(try Data(contentsOf: index) == before)
  }

  @Test("saving from a partially browsed collection preserves every source and historical candidate")
  func partialBrowseCannotReplaceArchive() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let photos = (0..<205).map { photo(index: $0) }
    let candidate = try portraitPersistenceCandidate()
    try await PortraitCandidateStore(directoryURL: directory).save(snapshot: .init(
      entries: [.init(candidate: candidate, reasons: [.init(reason: .shortlisted)])], sourcePhotos: photos))
    let collection = PortraitSketchCollection(store: .init(directoryURL: directory))
    await collection.loadPhotoBrowser()
    #expect(collection.photoReferences.count == 100 && collection.entries.isEmpty)
    let added = PortraitPhoto(id: UUID(), data: Data([9]), label: "New capture",
      capturedAt: Date(), frameID: nil, captureNanoseconds: nil, pose: .front)
    collection.retainSourcePhoto(added)
    await collection.awaitPersistence()
    let restored = await PortraitCandidateStore(directoryURL: directory).load()
    #expect(restored.canWrite && restored.archive.sourcePhotos?.count == 206)
    #expect(restored.archive.entries.map(\.id) == [candidate.id])
    #expect(Set(restored.archive.sourcePhotos?.map(\.id) ?? []) == Set(photos.map(\.id) + [added.id]))
    // The old cursor cannot mix snapshots after that canonical commit.
    await collection.loadMorePhotos()
    #expect(collection.photoReferences.count == 100)
    #expect(collection.photoReferences.first?.id == added.id)
  }

  @Test("embedded and bulk legacy browsing skips program geometry and stays read-only", arguments: [1, 2])
  func embeddedLegacyCatalog(version: Int) async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let candidate = try portraitPersistenceCandidate()
    try await PortraitCandidateStore(directoryURL: directory).save(snapshot: .init(
      entries: [.init(candidate: candidate, reasons: [])]))
    let records = directory.appendingPathComponent("records")
    let file = try #require(FileManager.default.contentsOfDirectory(at: records, includingPropertiesForKeys: nil)
      .first { (try? JSONSerialization.jsonObject(with: Data(contentsOf: $0)) as? [String: Any])?["program"] != nil })
    var stored = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    var program = try #require(stored["program"] as? [String: Any])
    program["strokes"] = "Intentionally not decodable Drawing geometry"
    stored["program"] = program
    let bulk = try JSONSerialization.data(withJSONObject: ["schemaVersion": version,
      "entries": [["candidate": stored, "reasons": []]], "labels": [], "tombstones": []])
    var payload = bulk
    if version == 2 {
      let hash = PortraitCandidateCoding.digest(bulk)
      try bulk.write(to: records.appendingPathComponent(hash))
      payload = try JSONSerialization.data(withJSONObject: ["recordSHA256": hash])
    }
    let bytes = try JSONSerialization.data(withJSONObject: ["schemaVersion": version,
      "sha256": PortraitCandidateCoding.digest(payload), "payload": payload.base64EncodedString()])
    let index = directory.appendingPathComponent("index-v1.json")
    try bytes.write(to: index)
    let reader = PortraitCandidateStore(directoryURL: directory)
    let page = try reader.loadPhotoPage()
    let reference = try #require(page.photos.first)
    #expect(reference.id == candidate.photoID && reference.pose == candidate.renderPose)
    #expect(try reader.loadPhoto(reference).data == candidate.sourceData)
    #expect(try Data(contentsOf: index) == bytes)
  }

  @Test("a canonical provenance upgrade keeps a visible source readable by exact ID and byte identity")
  func provenanceRefresh() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let candidate = try portraitPersistenceCandidate()
    let store = PortraitCandidateStore(directoryURL: directory)
    var archive = PortraitCandidateArchive(entries: [.init(candidate: candidate, reasons: [])])
    try await store.save(snapshot: archive)
    let old = try #require(store.loadPhotoPage().photos.first)
    let original = PortraitPhoto(id: candidate.photoID, data: candidate.sourceData, label: "Exact original",
      capturedAt: candidate.createdAt.addingTimeInterval(-1), frameID: nil, captureNanoseconds: 456,
      pose: .front, sourcePixelExtent: candidate.sourcePixelExtent, captureSessionID: candidate.captureSessionID)
    archive.sourcePhotos = [original]
    try await store.save(snapshot: archive)
    #expect(try store.loadPhoto(old) == original)
  }

  @Test("source deletion from metadata covers unloaded attempts, refuses stale references and preserves later reimport")
  func deletionFromUnloadedHistory() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let candidate = try portraitPersistenceCandidate()
    let record = try PortraitAttemptRecord.prepare(candidate: candidate, pen: portraitTestStyle())
    let original = PortraitPhoto(id: candidate.photoID, data: candidate.sourceData, label: "Original",
      capturedAt: candidate.createdAt, frameID: nil, captureNanoseconds: nil, pose: .front,
      captureSessionID: candidate.captureSessionID)
    try await PortraitCandidateStore(directoryURL: directory).save(snapshot: .init(
      entries: [.init(candidate: candidate, reasons: [], attempt: record)], sourcePhotos: [original]))
    let model = PortraitStudioModel(renderer: ExplorationTestRenderer(), candidateStore: .init(directoryURL: directory))
    let collection = model.sketches
    await model.loadPhotoBrowser()
    let reference = try #require(collection.photoReferences.first)
    #expect(collection.entries.isEmpty)
    model.deleteRetainedSource(original.id, strokeStyle: try portraitTestStyle())
    #expect(collection.photoReferences.isEmpty)
    await collection.awaitPersistence()
    let reader = PortraitCandidateStore(directoryURL: directory)
    #expect(throws: (any Error).self) { try reader.loadPhoto(reference) }
    let deleted = await reader.load()
    #expect(deleted.canWrite && deleted.archive.entries.isEmpty && deleted.archive.sourcePhotos?.isEmpty == true)
    #expect(deleted.archive.tombstones.first?.affectedCandidateIDs == [candidate.id])
    let reimport = PortraitPhoto(id: UUID(), data: original.data, label: "Imported again",
      capturedAt: Date(), frameID: nil, captureNanoseconds: nil, pose: .front)
    collection.retainSourcePhoto(reimport)
    await collection.awaitPersistence()
    #expect(collection.photoReferences.map(\.id) == [reimport.id])
    #expect(try reader.loadPhotoPage().photos.map(\.id) == [reimport.id])
    await model.shutdown()
  }

  @Test("retained pixel selection is asynchronous, preserves source identity and cannot finish after deletion")
  func asynchronousSelection() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let original = photo(index: 1)
    try await PortraitCandidateStore(directoryURL: directory).save(snapshot: .init(sourcePhotos: [original]))
    let model = PortraitStudioModel(renderer: ExplorationTestRenderer(), candidateStore: .init(directoryURL: directory))
    let pen = try portraitTestStyle()
    await model.loadPhotoBrowser()
    model.selectPhoto(original.id, strokeStyle: pen)
    await model.awaitPhotoSelection()
    await model.awaitRendering()
    #expect(model.selectedPhotoID == original.id && model.selectedCandidate?.sourceData == original.data)
    #expect(model.selectedCandidate?.photoID == original.id)
    await model.shutdown()
    let cancelled = PortraitStudioModel(renderer: ExplorationTestRenderer(), candidateStore: .init(directoryURL: directory))
    await cancelled.loadPhotoBrowser()
    cancelled.selectPhoto(original.id, strokeStyle: pen)
    await cancelled.cancelRendering()
    await cancelled.awaitPhotoSelection()
    #expect(cancelled.selectedPhotoID == nil && cancelled.selectedCandidate == nil)
    await cancelled.shutdown()
    let next = PortraitStudioModel(renderer: ExplorationTestRenderer(), candidateStore: .init(directoryURL: directory))
    await next.loadPhotoBrowser()
    next.selectPhoto(original.id, strokeStyle: pen)
    next.deleteRetainedSource(original.id, strokeStyle: pen)
    await next.awaitPhotoSelection()
    await next.awaitRendering()
    #expect(next.selectedPhotoID == nil && next.selectedCandidate == nil && next.loadingPhotoID == nil)
    await next.shutdown()
  }

  @Test("index corruption refuses browsing without rewriting retained bytes")
  func corruptIndex() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let index = directory.appendingPathComponent("index-v1.json")
    let original = Data("damaged operator evidence".utf8)
    try original.write(to: index)
    let collection = PortraitSketchCollection(store: .init(directoryURL: directory))
    await collection.loadPhotoBrowser()
    guard case .failed = collection.photoBrowserState else { Issue.record("Corrupt index was accepted"); return }
    guard case .failed = collection.savedStylesState else { Issue.record("Unavailable recipes stayed loading"); return }
    #expect(collection.photoReferences.isEmpty && !collection.historyLoadHasCompleted)
    #expect(try Data(contentsOf: index) == original)
  }

  @Test("disposable retained archive measures catalog and one bounded legacy page", .enabled(if:
    ProcessInfo.processInfo.environment["PORTRAIT_PHOTO_BROWSER_BENCHMARK_DIR"] != nil))
  func retainedArchiveCatalogPerformance() throws {
    let path = try #require(ProcessInfo.processInfo.environment["PORTRAIT_PHOTO_BROWSER_BENCHMARK_DIR"])
    try #require(path.hasPrefix("/tmp/adaptiveplotter-photo-browser-") || path.hasPrefix("/private/tmp/adaptiveplotter-photo-browser-"))
    let directory = URL(fileURLWithPath: path)
    let index = directory.appendingPathComponent("index-v1.json")
    let before = try Data(contentsOf: index)
    let reader = PortraitCandidateStore(directoryURL: directory)
    let start = ProcessInfo.processInfo.systemUptime
    let page = try reader.loadPhotoPage()
    let firstMS = (ProcessInfo.processInfo.systemUptime - start) * 1000
    let moreStart = ProcessInfo.processInfo.systemUptime
    let more = try page.next.map { try reader.loadPhotoPage(after: $0) }
    let moreMS = (ProcessInfo.processInfo.systemUptime - moreStart) * 1000
    let sourceStart = ProcessInfo.processInfo.systemUptime
    let source = try page.photos.first.map { try reader.loadPhoto($0) }
    let sourceMS = (ProcessInfo.processInfo.systemUptime - sourceStart) * 1000
    print("Photo browser: first_photos=\(page.photos.count) first_ms=\(firstMS) first_candidate_records=\(page.candidateRecordsRead) next_photos=\(more?.photos.count ?? 0) next_ms=\(moreMS) next_candidate_records=\(more?.candidateRecordsRead ?? 0) page_asset_bytes_read=0 selected_source_bytes=\(source?.data.count ?? 0) selected_source_ms=\(sourceMS)")
    #expect(try Data(contentsOf: index) == before)
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("portrait-photo-pages-\(UUID())")
  }
  private func photo(index: Int) -> PortraitPhoto {
    PortraitPhoto(id: UUID(), data: Data([1, 2, 3, 4, UInt8(index % 255)]), label: "Source \(index)",
      capturedAt: Date(timeIntervalSince1970: Double(index)), frameID: nil, captureNanoseconds: UInt64(index),
      pose: .front, sourcePixelExtent: try? .init(widthPixels: 40, heightPixels: 40))
  }

  private func removePhotoCatalog(_ directory: URL) throws {
    let url = directory.appendingPathComponent("index-v1.json")
    var envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let encoded = try #require(envelope["payload"] as? String)
    let payload = try #require(Data(base64Encoded: encoded))
    var index = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
    index.removeValue(forKey: "photoCatalog")
    let revised = try JSONSerialization.data(withJSONObject: index, options: [.sortedKeys])
    envelope["payload"] = revised.base64EncodedString()
    envelope["sha256"] = PortraitCandidateCoding.digest(revised)
    try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]).write(to: url, options: .atomic)
  }
}
