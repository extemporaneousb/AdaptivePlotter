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

  private func payloadFiles(_ package: ValidatedExchangePackage) throws -> [String: Data] {
    var result: [String: Data] = [:]
    for path in package.files.entries.keys where path.hasPrefix("data/") { result[path] = try package.files.record(at: path, maximumBytes: 128 * 1024 * 1024) }
    return result
  }
}
