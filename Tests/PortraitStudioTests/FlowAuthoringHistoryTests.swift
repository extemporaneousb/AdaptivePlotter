import Foundation
@testable import DrawingLibrary
import PlotterModel
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary
import Testing

@Suite("Exact bounded private authoring history", .serialized)
struct FlowAuthoringHistoryTests {
  private func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("flow-history-" + UUID().uuidString) }
  private func open(_ root: URL, policy: FlowAuthoringHistoryPolicy = .init()) async throws -> FlowPortfolioStore {
    let store = FlowPortfolioStore(directory: root, purpose: .validationFixture, historyPolicy: policy)
    try await store.loadRecords(); return store
  }
  private func production(_ store: FlowPortfolioStore, source: FlowPortfolioSource,
    options: PortraitAnalysisOptions = .init(cropToFace: false, removeBackground: false)) async throws -> DrawingProduction<PortraitRenderResult> {
    let bytes = try await store.sourceData(source.id), photo = try await store.sourcePhoto(source.id)
    let raster = try PortraitImageAnalyzer.analyze(data: bytes, options: options, maximumDimension: 8)
    let program = try FlowPortfolioTests.program()
    return try PortraitFlowDrawingProducer.admit(result: .init(raster: raster, program: program),
      input: .init(data: bytes, photo: photo), settings: .init(recipe: .standard, analysisOptions: options,
        strokeStyle: program.strokes[0].style, nominalPenWidthMM: 0.35), origin: .providedArtifacts)
  }
  private func panel(_ store: FlowPortfolioStore, source: UUID, count: Int,
    production: DrawingProduction<PortraitRenderResult>) async throws -> [FlowPortfolioCandidate] {
    let claim = try JSONDecoder().decode(PortraitFlowProducerClaim.self, from: production.drawing.producer.originalJSON)
    let round = try await store.beginRound(sourceID: source, recipes: Array(repeating: .standard, count: count), analysisOptions: claim.settings.analysisOptions)
    var result: [FlowPortfolioCandidate] = []
    for slot in 0..<count {
      result.append(try await store.completeCandidate(roundID: round.id, slot: slot, production: production,
        previewPNG: PortraitDrawingPreview.png(production.drawing.program)))
    }
    try await store.finishRound(round.id); return result
  }
  private func equalInput(_ actual: FrozenImageInputRecord, _ expected: FrozenImageInputRecord) {
    #expect(actual.reference == expected.reference && actual.record.originalJSON == expected.record.originalJSON)
    #expect(actual.photo.reference == expected.photo.reference && actual.photo.record.originalJSON == expected.photo.record.originalJSON)
    #expect(assetClosure(actual) == assetClosure(expected))
  }
  private struct ExactAsset: Equatable {
    let descriptor: ExchangeAssetDescriptor
    let bytes: Data
  }
  private func assetClosure(_ input: FrozenImageInputRecord) -> [ExchangeDigest: ExactAsset] {
    var result: [ExchangeDigest: ExactAsset] = [:]
    for asset in input.assets + input.photo.assets {
      let digest = asset.descriptor.asset.object
      let exact = ExactAsset(descriptor: asset.descriptor, bytes: asset.bytes)
      if let prior = result[digest] {
        // Repeated operation parameters and shared Photo assets are legitimate;
        // equal digests must still carry equal complete descriptors and bytes.
        #expect(prior == exact)
      } else { result[digest] = exact }
    }
    return result
  }

  @Test("RAM pressure, source and region switches and cold reopen preserve exact producer and nonnil input without gallery expansion")
  func pressureAndReopen() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await open(root)
    let source = try await store.addSource(data: FlowPortfolioTests.photo, title: "Exact source")
    let produced = try await production(store, source: source)
    let frozenInput = try #require(produced.artifacts.drawingInput)
    let first = try await panel(store, source: source.id, count: 12, production: produced)
    let middle = try await panel(store, source: source.id, count: 12, production: produced)
    let last = try await panel(store, source: source.id, count: 12, production: produced)
    #expect(try await store.library.drawings().entries.isEmpty)
    let initial = try await store.historyStatistics(), audited = try await store.auditHistoryStatistics()
    #expect(initial.entryCount == 36 && initial.byteCount == audited.byteCount && initial.entryCount == audited.entryCount)
    let clock = ContinuousClock(), start = clock.now
    for _ in 0..<100 { _ = try await store.historyStatistics() }
    print("FLOW_HISTORY_ACCOUNTED_STATS_36_ENTRIES_100_READS=\(start.duration(to: clock.now))")
    try await store.setAuthoringOptions(sourceID: source.id, options: .init(manualRegion: .init(x: 0.2, y: 0.2, width: 0.6, height: 0.6)))
    _ = try await store.addSource(data: FlowAuthoringFixture.image(2), title: "Other source")
    #expect(await store.transientCacheStatistics().temporaryDrawingCount == 0)
    let beforeReads = await store.snapshot()
    for candidate in [first[5], middle[7], last[11]] {
      #expect(try await store.candidateUnavailableReason(candidate.id) == nil)
      let drawing = try await store.candidateDrawing(candidate.id)
      #expect(drawing.program == produced.drawing.program && drawing.producer == produced.drawing.producer)
      #expect(drawing.units == produced.drawing.units && drawing.input == produced.drawing.input && drawing.parent == produced.drawing.parent)
      #expect(drawing.capabilities.producerVerified == produced.drawing.capabilities.producerVerified)
      equalInput(try #require(try await store.candidateInput(candidate.id)), frozenInput)
      #expect(try await store.candidateRaster(candidate.id) == produced.artifacts.raster)
      #expect(try await store.candidatePreview(candidate.id) == PortraitDrawingPreview.png(produced.drawing.program))
      let hot = await store.transientCacheStatistics()
      #expect(hot.temporaryDrawingCount <= FlowPortfolioStore.maximumTemporaryDrawings)
      #expect(hot.temporaryDrawingBytes <= FlowPortfolioStore.maximumTemporaryDrawingBytes)
      #expect(hot.artifactCount <= FlowAuthoringArtifacts.maximumCount && hot.artifactBytes <= FlowAuthoringArtifacts.maximumBytes)
    }
    #expect(await store.snapshot() == beforeReads)
    #expect(try await store.library.drawings().entries.isEmpty)
    await store.closeLibrary()
    let reopened = try await open(root)
    for candidate in [first[5], middle[7], last[11]] {
      let drawing = try await reopened.candidateDrawing(candidate.id)
      #expect(drawing.program == produced.drawing.program && drawing.producer == produced.drawing.producer)
      #expect(drawing.units == produced.drawing.units && drawing.input == produced.drawing.input && drawing.parent == produced.drawing.parent)
      equalInput(try #require(try await reopened.candidateInput(candidate.id)), frozenInput)
    }
    #expect(try await reopened.library.drawings().entries.isEmpty)
    try await reopened.selectRound(first[5].roundID)
    try await reopened.chooseCandidate(first[5].id)
    let retained = try await reopened.retainedDrawing(candidateID: first[5].id)
    #expect(retained.producer == produced.drawing.producer && retained.input == produced.drawing.input && retained.units == produced.drawing.units)
    let edit = try await reopened.applyPrune(candidateID: first[5].id, action: .remove, indices: [0])
    let child = try await reopened.retainedDrawing(candidateID: first[5].id, revisionID: edit.id)
    #expect(child.parent == .present(try #require(retained.reference)))
    #expect(child.input == retained.input && child.units == retained.units)
    #expect(await reopened.snapshot().choices.count == 1)
    await reopened.closeLibrary()
  }
  @Test("Large original Photos with small prepared inputs force byte eviction below the count limit and rehydrate exactly")
  func photoClosureBytePressure() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await open(root)
    let bytes = Self.paddedPNG(FlowPortfolioTests.photo, payloadBytes: 31 * 1024 * 1024)
    #expect(bytes.count < DrawingArtifactLimits.sourceBytes)
    let source = try await store.addSource(data: bytes, title: "Large Photo byte-pressure fixture")
    let produced = try await production(store, source: source)
    let expectedInput = try #require(produced.artifacts.drawingInput)
    #expect(expectedInput.photo.assets.reduce(0) { $0 + $1.bytes.count } >= 31 * 1024 * 1024)
    #expect(produced.artifacts.raster.width <= 8 && produced.artifacts.raster.height <= 8)
    let first = try await panel(store, source: source.id, count: 2, production: produced)
    let before = await store.transientCacheStatistics()
    #expect(before.temporaryDrawingCount == 2 && before.temporaryDrawingBytes > 120 * 1024 * 1024)
    let second = try await panel(store, source: source.id, count: 3, production: produced)
    let after = await store.transientCacheStatistics()
    // Five entries cannot hit the25-count cap. The original Photo closure alone
    // requires eviction under the256MiB byte cap, including cold-owner copies.
    #expect(first.count + second.count < FlowPortfolioStore.maximumTemporaryDrawings)
    #expect(after.temporaryDrawingCount < first.count + second.count)
    #expect(after.temporaryDrawingBytes <= FlowPortfolioStore.maximumTemporaryDrawingBytes)
    #expect(try await store.historyStatistics().entryCount == 5)
    #expect(try await store.historyStatistics().byteCount < 5 * 64 * 1024 * 1024)
    try await store.selectCandidate(first[1].id)
    let exact = try await store.candidateDrawing(first[1].id)
    #expect(exact.program == produced.drawing.program && exact.producer == produced.drawing.producer && exact.units == produced.drawing.units)
    equalInput(try #require(try await store.candidateInput(first[1].id)), expectedInput)
    #expect(await store.transientCacheStatistics().temporaryDrawingBytes <= FlowPortfolioStore.maximumTemporaryDrawingBytes)
    #expect(try await store.library.drawings().entries.isEmpty)
    await store.closeLibrary()
    let reopened = try await open(root)
    equalInput(try #require(try await reopened.candidateInput(second[0].id)), expectedInput)
    #expect(await reopened.transientCacheStatistics().temporaryDrawingBytes <= FlowPortfolioStore.maximumTemporaryDrawingBytes)
    #expect(try await reopened.library.drawings().entries.isEmpty)
    await reopened.closeLibrary()
  }
  /// Valid PNG ancillary text chunk; tiny decoded pixels, large immutable original.
  private static func paddedPNG(_ original: Data, payloadBytes: Int) -> Data {
    precondition(original.count >= 12)
    var chunk = Data("tEXtHistory fixture\0".utf8)
    chunk.append(Data(repeating: 120, count: payloadBytes))
    let table: [UInt32] = (0..<256).map { index in
      var value = UInt32(index)
      for _ in 0..<8 { value = (value & 1) == 1 ? (value >> 1) ^ 0xedb88320 : value >> 1 }
      return value
    }
    var crc = UInt32.max
    chunk.withUnsafeBytes { raw in
      for byte in raw { crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8) }
    }
    crc ^= UInt32.max
    var length = UInt32(chunk.count - 4).bigEndian, checksum = crc.bigEndian
    var result = Data(original.dropLast(12))
    withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
    result.append(chunk)
    withUnsafeBytes(of: &checksum) { result.append(contentsOf: $0) }
    result.append(original.suffix(12)); return result
  }
  @Test("Quota rejects new work without deleting incumbent history and counts complete orphans while removing incomplete staging")
  func quotaAndOrphans() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await open(root, policy: .init(maximumEntries: 2))
    let source = try await store.addSource(data: FlowPortfolioTests.photo, title: "Source")
    let produced = try await production(store, source: source)
    let candidate = try #require(try await panel(store, source: source.id, count: 1, production: produced).first)
    let before = await store.snapshot()
    await store.closeLibrary()
    let spool = root.appendingPathComponent("flow-authoring-history-v1")
    try FileManager.default.copyItem(at: spool.appendingPathComponent(candidate.id.uuidString.lowercased()),
      to: spool.appendingPathComponent(UUID().uuidString.lowercased()))
    let partial = spool.appendingPathComponent(".partial-" + UUID().uuidString.lowercased())
    try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: false)
    try Data([1,2,3]).write(to: partial.appendingPathComponent("incomplete.part"))
    let reopened = try await open(root, policy: .init(maximumEntries: 2))
    #expect(!FileManager.default.fileExists(atPath: partial.path))
    #expect(try await reopened.historyStatistics().entryCount == 2)
    await #expect(throws: FlowPortfolioError.self) { try await reopened.beginRound(sourceID: source.id, recipes: [.standard]) }
    #expect(await reopened.snapshot() == before)
    #expect(try await reopened.candidateDrawing(candidate.id).producer == produced.drawing.producer)
    #expect(try await reopened.library.drawings().entries.isEmpty)
    await reopened.closeLibrary()
  }
  @Test("Atomic write failure keeps incumbent entries and retry publishes one complete exact candidate", arguments: [FlowAuthoringHistoryBoundary.afterParts, .beforePublish])
  func writeFailure(_ boundary: FlowAuthoringHistoryBoundary) async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await open(root)
    let source = try await store.addSource(data: FlowPortfolioTests.photo, title: "Source")
    let produced = try await production(store, source: source)
    let old = try #require(try await panel(store, source: source.id, count: 1, production: produced).first)
    let baseline = try await store.historyStatistics()
    let claim = try JSONDecoder().decode(PortraitFlowProducerClaim.self, from: produced.drawing.producer.originalJSON)
    let round = try await store.beginRound(sourceID: source.id, recipes: [.standard], analysisOptions: claim.settings.analysisOptions)
    await store.setHistoryFault { if $0 == boundary { throw POSIXError(.EIO) } }
    await #expect(throws: POSIXError.self) {
      try await store.completeCandidate(roundID: round.id, slot: 0, production: produced, previewPNG: PortraitDrawingPreview.png(produced.drawing.program))
    }
    let after = try await store.auditHistoryStatistics()
    #expect(after.entryCount == baseline.entryCount && after.byteCount == baseline.byteCount)
    #expect(await store.snapshot().candidates.count == 1)
    #expect(try await store.candidateProgram(old.id) == produced.drawing.program)
    await store.setHistoryFault(nil)
    let new = try await store.completeCandidate(roundID: round.id, slot: 0, production: produced, previewPNG: PortraitDrawingPreview.png(produced.drawing.program))
    try await store.finishRound(round.id)
    #expect(try await store.candidateInput(new.id)?.reference == produced.artifacts.drawingInput?.reference)
    #expect(try await store.historyStatistics().entryCount == 2)
    await store.closeLibrary()
  }
  @Test("Pending graph publication recovers the already durable spool entry exactly once")
  func pendingPublication() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await open(root)
    let source = try await store.addSource(data: FlowPortfolioTests.photo, title: "Source")
    let produced = try await production(store, source: source)
    let claim = try JSONDecoder().decode(PortraitFlowProducerClaim.self, from: produced.drawing.producer.originalJSON)
    let round = try await store.beginRound(sourceID: source.id, recipes: [.standard], analysisOptions: claim.settings.analysisOptions)
    try await store.library.feedbackFault(.afterSQLCommit)
    await #expect(throws: (any Error).self) {
      try await store.completeCandidate(roundID: round.id, slot: 0, production: produced, previewPNG: PortraitDrawingPreview.png(produced.drawing.program))
    }
    #expect(await store.pendingGraphWrite != nil)
    #expect(try await store.historyStatistics().entryCount == 1)
    try await store.library.feedbackFault(nil)
    try await store.reloadCommittedState()
    let candidate = try #require(await store.snapshot().candidates.first)
    #expect(try await store.candidateDrawing(candidate.id).producer == produced.drawing.producer)
    #expect(try await store.candidateInput(candidate.id)?.reference == produced.artifacts.drawingInput?.reference)
    #expect(await store.snapshot().candidates.count == 1)
    try await store.finishRound(round.id)
    await store.closeLibrary()
  }
  @Test("Missing, changed and malformed private material refuses action without feedback or stale geometry", arguments: [0,1,2])
  func corruptClosure(_ fault: Int) async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await open(root)
    let source = try await store.addSource(data: FlowPortfolioTests.photo, title: "Source")
    let produced = try await production(store, source: source)
    let candidates = try await panel(store, source: source.id, count: 2, production: produced)
    await store.closeLibrary()
    let folder = root.appendingPathComponent("flow-authoring-history-v1/" + candidates[0].id.uuidString.lowercased())
    let part = try #require(try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first { $0.pathExtension == "part" })
    if fault == 0 { try FileManager.default.removeItem(at: part) }
    else if fault == 1 { var data = try Data(contentsOf: part); data[0] ^= 1; try data.write(to: part) }
    else { try Data("{}".utf8).write(to: folder.appendingPathComponent("manifest.json")) }
    let reopened = try await open(root)
    let before = await reopened.snapshot()
    #expect(try await reopened.candidateUnavailableReason(candidates[0].id) != nil)
    await #expect(throws: (any Error).self) { try await reopened.chooseCandidate(candidates[0].id) }
    await #expect(throws: (any Error).self) { try await reopened.candidateProgram(candidates[0].id) }
    #expect(await reopened.snapshot() == before)
    #expect(try await reopened.candidateDrawing(candidates[1].id).producer == produced.drawing.producer)
    #expect(try await reopened.library.drawings().entries.isEmpty)
    await reopened.closeLibrary()
  }
}
