import Foundation
import DrawingLibrary
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary
import Testing

@Suite("Historical feedback cache verification and budgets", .serialized)
struct FlowFeedbackReadBudgetTests {
  @Test("Evicted JSON remains charged once and is verified again when touched", arguments: [0, 7])
  func evictionRetainsAccounting(maximumCachedBytes: Int) async throws {
    let root = DrawingExchangeFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try await DrawingExchangeFeedbackFixture.make(directory: root, candidateCount: 1)
    let prune = try await fixture.store.applyPrune(candidateID: fixture.candidates[0][0].id, action: .remove, indices: [0])
    let reference = try await fixture.store.feedbackReference(for: prune.id)
    let original = try await fixture.library.feedback(reference.publication)
    var files = try payloadFiles(original)
    let values = [Data("{\"a\":1}".utf8), Data("{\"b\":2}".utf8), Data("{\"c\":3}".utf8)]
    let assets = try values.map { try ExchangeAsset(bytes: $0, mediaType: "application/json", encoding: "utf8-json") }
    let indexBytes = try #require(files["data/exchange.json"])
    var index = try #require(JSONSerialization.jsonObject(with: indexBytes) as? [String: Any])
    var descriptors = try #require(index["assets"] as? [[String: Any]])
    for (asset, bytes) in zip(assets, values) {
      files["data/objects/sha256/" + asset.object.description] = bytes
      descriptors.append(try #require(JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(ExchangeAssetDescriptor(asset: asset))) as? [String: Any]))
    }
    index["assets"] = descriptors; files["data/exchange.json"] = try DrawingExchangeFeedbackFixture.json(index)
    let prepared = try FlowFeedbackCarrier.prepare(files)
    defer { try? FileManager.default.removeItem(at: prepared.temporaryRoot) }
    let budget = FlowFeatureReadBudget(maximumBytes: assets[0].byteLength + assets[1].byteLength, maximumCachedBytes: maximumCachedBytes)
    #expect(try FlowFeedbackReader.exactJSON(assets[0], package: prepared.package, budget: budget) == values[0])
    #expect(try FlowFeedbackReader.exactJSON(assets[1], package: prepared.package, budget: budget) == values[1])
    #expect(try FlowFeedbackReader.exactJSON(assets[0], package: prepared.package, budget: budget) == values[0])
    #expect(throws: (any Error).self) { try FlowFeedbackReader.exactJSON(assets[2], package: prepared.package, budget: budget) }
    _ = try FlowFeedbackReader.exactJSON(assets[1], package: prepared.package, budget: budget)
    let evicted = prepared.package.files.stagingURL.appendingPathComponent("data/objects/sha256/" + assets[0].object.description)
    try Data(repeating: 0x78, count: values[0].count).write(to: evicted, options: .atomic)
    #expect(throws: (any Error).self) { try FlowFeedbackReader.exactJSON(assets[0], package: prepared.package, budget: budget) }
    await fixture.library.closeLibrary()
  }

  @Test("Parsed feature cache cannot borrow another resolver's producer integrity", arguments: [false, true])
  func cachedFeatureRequiresCurrentResolver(missing: Bool) async throws {
    let root = DrawingExchangeFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try await DrawingExchangeFeedbackFixture.make(directory: root, candidateCount: 1)
    let candidate = fixture.candidates[0][0]
    let prune = try await fixture.store.applyPrune(candidateID: candidate.id, action: .remove, indices: [0])
    let reference = try await fixture.store.feedbackReference(for: prune.id)
    let original = try await fixture.library.feedback(reference.publication)
    let feature = try await fixture.store.featureCapsule(candidateID: candidate.id, revisionID: prune.id)
    let asset = try feature.asset
    let budget = FlowFeatureReadBudget(maximumCachedBytes: 0)
    let warmed = try FlowFeedbackReader.feature(asset, package: original, budget: budget)
    #expect(warmed.id == prune.id)
    let copied = try FlowFeedbackCarrier.prepare(payloadFiles(original))
    defer { try? FileManager.default.removeItem(at: copied.temporaryRoot) }
    #expect(copied.package.files !== original.files)
    #expect(try copied.package.files.record(asset.object) == original.files.record(asset.object))
    let producer = copied.package.files.stagingURL.appendingPathComponent("data/objects/sha256/" + feature.producer.record.object.description)
    if missing { try FileManager.default.removeItem(at: producer) }
    else { try Data(repeating: 0x78, count: Int(feature.producer.record.byteLength)).write(to: producer, options: .atomic) }
    #expect(throws: (any Error).self) { try FlowFeedbackReader.feature(asset, package: copied.package, budget: budget) }
    await fixture.library.closeLibrary()
  }

  @Test("Whole-read-set checks survive optimized feature hits and batching is restricted to its exact resolver", arguments: ["none", "same", "different"])
  func finalReadSetValidation(batch: String) async throws {
    let root = DrawingExchangeFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try await DrawingExchangeFeedbackFixture.make(directory: root, candidateCount: 2)
    let first = fixture.candidates[0][0], second = fixture.candidates[0][1]
    let a = try await fixture.store.applyPrune(candidateID: first.id, action: .remove, indices: [0])
    let b = try await fixture.store.applyPrune(candidateID: second.id, action: .remove, indices: [0])
    let aRef = try await fixture.store.feedbackReference(for: a.id)
    let snapshot = try await fixture.store.freezeTrainingSnapshot()
    let original = try await fixture.library.feedback(try #require(snapshot.publication))
    let copied = try FlowFeedbackCarrier.prepare(payloadFiles(original))
    defer { try? FileManager.default.removeItem(at: copied.temporaryRoot) }
    let aAsset = try await fixture.store.featureCapsule(candidateID: first.id, revisionID: a.id).asset
    let bAsset = try await fixture.store.featureCapsule(candidateID: second.id, revisionID: b.id).asset
    let budget = FlowFeatureReadBudget()
    _ = try FlowFeedbackReader.feature(bAsset, package: copied.package, budget: budget)
    let before = try FlowFeedbackReader.value(FlowPortfolioPruneRevision.self, reference: aRef, id: a.id, package: copied.package, budget: budget)
    #expect(before.id == a.id)
    let earlier = copied.package.files.stagingURL.appendingPathComponent("data/objects/sha256/" + bAsset.object.description)
    try Data(repeating: 0x78, count: Int(bAsset.byteLength)).write(to: earlier, options: .atomic)
    // The hot path checks just A's unchanged dependencies. The semantic return
    // boundary must still reject the previously selected B source mutation.
    #expect(try FlowFeedbackReader.feature(aAsset, package: copied.package, budget: budget).id == a.id)
    if batch == "same" { budget.batchedFiles = copied.package.files }
    if batch == "different" { budget.batchedFiles = original.files }
    if batch == "same" {
      #expect(try FlowFeedbackReader.value(FlowPortfolioPruneRevision.self, reference: aRef, id: a.id, package: copied.package, budget: budget).id == a.id)
      #expect(throws: (any Error).self) { try copied.package.files.revalidateSelected() }
    } else {
      #expect(throws: (any Error).self) {
        try FlowFeedbackReader.value(FlowPortfolioPruneRevision.self, reference: aRef, id: a.id, package: copied.package, budget: budget)
      }
    }
    await fixture.library.closeLibrary()
  }

  @Test("Verified encoded root reuse matches full decoding and cold graph loading preserves every answer")
  func encodedRootReuseAndLoadParity() async throws {
    let root = DrawingExchangeFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try await DrawingExchangeFeedbackFixture.make(directory: root, candidateCount: 2)
    let candidate = fixture.candidates[0][0]
    try await fixture.store.chooseCandidate(candidate.id)
    let edit = try await fixture.store.applyPrune(candidateID: candidate.id, action: .remove, indices: [0])
    let presentation = try await fixture.store.presentRoundRanking(candidate.roundID, seed: 19)
    _ = try await fixture.store.recordRanking(presentationID: presentation.id, orderedGroups: presentation.items.map { [$0.id] })
    let restored = try await fixture.store.applyPrune(candidateID: candidate.id, action: .restore, indices: [0])
    let snapshot = try await fixture.store.freezeTrainingSnapshot()
    let package = try await fixture.library.feedback(try #require(snapshot.publication))
    let edited = try await fixture.store.featureCapsule(candidateID: candidate.id, revisionID: edit.id)
    let fast = FlowFeatureReadBudget(), full = FlowFeatureReadBudget(reusesEncodedStrokeBasis: false)
    let a = try FlowFeedbackReader.feature(edited.asset, package: package, budget: fast)
    let b = try FlowFeedbackReader.feature(edited.asset, package: package, budget: full)
    #expect(try DrawingArtifactCoding.encoder().encode(a) == DrawingArtifactCoding.encoder().encode(b))
    #expect(fast.statistics.reusedEncodedStrokeMatrices == 1 && fast.statistics.decodedStrokeMatrices == 1)
    #expect(full.statistics.reusedEncodedStrokeMatrices == 0 && full.statistics.decodedStrokeMatrices == 2)
    #expect(fast.statistics.metadataStrokeBytesSkipped > 0 && full.statistics.metadataStrokeBytesSkipped == 0)
    let baseElements = edited.strokes.reduce(0) { $0 + $1.count }
    let categoryLimit = baseElements + FlowArtistFeatures.drawingCount * 2
    let categories = FlowFeatureReadBudget(maximumElements: categoryLimit)
    _ = try FlowFeedbackReader.feature(edited.asset, package: package, budget: categories)
    try categories.beginNavigationCategory()
    _ = try FlowFeedbackReader.feature(edited.asset, package: package, budget: categories)
    let restoredAsset = try await fixture.store.featureCapsule(candidateID: candidate.id, revisionID: restored.id).asset
    #expect(throws: (any Error).self) { try FlowFeedbackReader.feature(restoredAsset, package: package, budget: categories) }
    #expect(categories.statistics.admittedElements == categoryLimit * 2)
    let expected = await fixture.store.snapshot()
    let expectedDigest = try await fixture.store.feedbackProjectionDigest()
    await fixture.library.closeLibrary()
    let reopened = FlowPortfolioStore(directory: root)
    try await reopened.loadRecords()
    #expect(await reopened.snapshot() == expected)
    #expect(try await reopened.feedbackProjectionDigest(matching: expected) == expectedDigest)
    let statistics = await reopened.lastFeedbackReadStatistics
    #expect(statistics.reusedEncodedStrokeMatrices > 0 && statistics.decodedStrokeMatrices < statistics.decodedCapsules)
    #expect(statistics.admittedBytes <= 3 * 512 * 1024 * 1024 && statistics.admittedElements <= 24_000_000)
    await reopened.closeLibrary()
    let fullDecode = FlowPortfolioStore(directory: root)
    try await fullDecode.loadRecords(reusingEncodedStrokeBasis: false)
    #expect(await fullDecode.snapshot() == expected)
    #expect(try await fullDecode.feedbackProjectionDigest() == expectedDigest)
    #expect(await fullDecode.lastFeedbackReadStatistics.reusedEncodedStrokeMatrices == 0)
    await fullDecode.closeLibrary()
  }

  @Test("Category resets retain exact descriptors and recharge cached feature admission")
  func categoryDescriptorIdentity() throws {
    let asset = try ExchangeAsset(bytes: Data("{}".utf8), mediaType: "application/json", encoding: "utf8-json")
    var json = try #require(JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(asset)) as? [String: Any])
    json["byteLength"] = asset.byteLength + 1
    let conflicting = try JSONDecoder().decode(ExchangeAsset.self, from: JSONSerialization.data(withJSONObject: json))
    let budget = FlowFeatureReadBudget(maximumBytes: asset.byteLength)
    try budget.admit(asset); try budget.beginNavigationCategory(); try budget.admit(asset)
    #expect(budget.statistics.admittedBytes == asset.byteLength * 2)
    #expect(throws: (any Error).self) { try budget.admit(conflicting) }
  }

  @Test("Encoded reuse preserves full-decoder metadata and syntax acceptance",
    arguments: ["pretty", "reordered", "escaped-key", "duplicate-strokes", "trailing",
      "invalid-metadata", "invalid-number", "unknown-invalid", "duplicate-profile", "extra-field"])
  func encodedStrokeFallback(change: String) async throws {
    let root = DrawingExchangeFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try await DrawingExchangeFeedbackFixture.make(directory: root, candidateCount: 1)
    let candidate = fixture.candidates[0][0]
    let edit = try await fixture.store.applyPrune(candidateID: candidate.id, action: .remove, indices: [0])
    let ref = try await fixture.store.feedbackReference(for: edit.id), package = try await fixture.library.feedback(ref.publication)
    let feature = try await fixture.store.featureCapsule(candidateID: candidate.id, revisionID: edit.id)
    let canonical = try DrawingArtifactCoding.encoder().encode(feature)
    var changed: Data
    switch change {
    case "pretty": changed = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: canonical), options: [.prettyPrinted, .sortedKeys])
    case "reordered":
      let object = try #require(JSONSerialization.jsonObject(with: canonical) as? [String: Any])
      let fields = try object.keys.sorted().reversed().map { key -> Data in
        var entry = try JSONSerialization.data(withJSONObject: key, options: [.fragmentsAllowed])
        entry.append(Data(": ".utf8))
        entry.append(try JSONSerialization.data(withJSONObject: object[key]!, options: [.fragmentsAllowed, .prettyPrinted, .sortedKeys]))
        return entry
      }
      changed = Data("{\n".utf8)
      for (index, field) in fields.enumerated() { if index > 0 { changed.append(Data(",\n".utf8)) }; changed.append(field) }
      changed.append(Data("\n}".utf8))
    case "escaped-key":
      let text = try #require(String(data: canonical, encoding: .utf8))
      changed = Data(text.replacingOccurrences(of: "\"strokes\":", with: "\"\\u0073trokes\":").utf8)
    case "duplicate-strokes":
      let values = try DrawingArtifactCoding.encoder().encode(feature.strokes)
      changed = Data(canonical.dropLast()); changed.append(Data(",\"strokes\":".utf8)); changed.append(values); changed.append(125)
    case "invalid-metadata":
      let text = try #require(String(data: canonical, encoding: .utf8))
      changed = Data(text.replacingOccurrences(of: "\"profile\":\"adaptiveplotter.flow-features/3\"", with: "\"profile\":null").utf8)
    case "invalid-number":
      let text = try #require(String(data: canonical, encoding: .utf8))
      changed = Data(text.replacingOccurrences(of: "\"drawing\":[", with: "\"drawing\":[1e,").utf8)
    case "unknown-invalid":
      changed = Data(canonical.dropLast()); changed.append(Data(",\"unused\":NaN}".utf8))
    case "duplicate-profile":
      changed = Data(canonical.dropLast()); changed.append(Data(",\"profile\":\"unsupported\"}".utf8))
    case "extra-field":
      changed = Data(canonical.dropLast())
      changed.append(Data(#","unused":{"quoted":"\"strokes\":null","array":[1,2]}}"#.utf8))
    default: changed = canonical; changed.append(Data(" false".utf8))
    }
    #expect(changed != canonical)
    let asset = try ExchangeAsset(bytes: changed, mediaType: "application/json", encoding: "utf8-json")
    var files = try payloadFiles(package)
    files["data/objects/sha256/" + asset.object.description] = changed
    let indexBytes = try #require(files["data/exchange.json"])
    var index = try #require(JSONSerialization.jsonObject(with: indexBytes) as? [String: Any])
    var descriptors = try #require(index["assets"] as? [[String: Any]])
    descriptors.append(try #require(JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(ExchangeAssetDescriptor(asset: asset))) as? [String: Any]))
    index["assets"] = descriptors; files["data/exchange.json"] = try DrawingExchangeFeedbackFixture.json(index)
    let prepared = try FlowFeedbackCarrier.prepare(files)
    defer { try? FileManager.default.removeItem(at: prepared.temporaryRoot) }
    let fast = FlowFeatureReadBudget(), full = FlowFeatureReadBudget(reusesEncodedStrokeBasis: false)
    let a = Result { try FlowFeedbackReader.feature(asset, package: prepared.package, budget: fast) }
    let b = Result { try FlowFeedbackReader.feature(asset, package: prepared.package, budget: full) }
    switch (a, b) {
    case (.success(let first), .success(let second)):
      #expect(try DrawingArtifactCoding.encoder().encode(first) == DrawingArtifactCoding.encoder().encode(second))
    case (.failure, .failure): break
    default: Issue.record("Optimized and full decoder acceptance differ for \(change)")
    }
    #expect(fast.statistics.reusedEncodedStrokeMatrices == (change == "extra-field" ? 1 : 0))
    if ["trailing", "invalid-metadata", "invalid-number", "unknown-invalid"].contains(change) {
      #expect(throws: (any Error).self) { try a.get() }
      #expect(throws: (any Error).self) { try b.get() }
    }
    if change == "extra-field" { #expect(try a.get().id == feature.id) }
    await fixture.library.closeLibrary()
  }

  private func payloadFiles(_ package: ValidatedExchangePackage) throws -> [String: Data] {
    var result: [String: Data] = [:]
    for path in package.files.entries.keys where path.hasPrefix("data/") { result[path] = try package.files.record(at: path, maximumBytes: 128 * 1024 * 1024) }
    return result
  }
}
