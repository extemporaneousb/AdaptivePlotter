import Foundation
import DrawingLibrary
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary
import Testing

@Suite("Shared immutable prune feature basis", .serialized)
struct DrawingExchangeSharedFeatureTests {
@Test("Distinct prune answers share a verified immutable stroke basis within the materialization budget")
func sharedPruneStrokeBasis() async throws {
  let root = DrawingExchangeFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
  let fixture = try await DrawingExchangeFeedbackFixture.make(directory: root, candidateCount: 1)
  let candidate = fixture.candidates[0][0]
  let first = try await fixture.store.applyPrune(candidateID: candidate.id, action: .remove, indices: [0])
  let second = try await fixture.store.applyPrune(candidateID: candidate.id, action: .restore, indices: [0])
  let snapshot = try await fixture.store.freezeTrainingSnapshot()
  let package = try await fixture.library.feedback(try #require(snapshot.publication))
  let base = try await fixture.store.featureCapsule(candidateID: candidate.id)
  let a = try await fixture.store.featureCapsule(candidateID: candidate.id, revisionID: first.id)
  let b = try await fixture.store.featureCapsule(candidateID: candidate.id, revisionID: second.id)
  let budget = FlowFeatureReadBudget(maximumElements: base.strokes.count * FlowArtistFeatures.strokeCount + FlowArtistFeatures.drawingCount * 3)
  let rootValue = try FlowFeedbackReader.feature(base.asset, package: package, budget: budget)
  let firstValue = try FlowFeedbackReader.feature(a.asset, package: package, budget: budget)
  let secondValue = try FlowFeedbackReader.feature(b.asset, package: package, budget: budget)
  #expect(firstValue.id != secondValue.id && firstValue.removedIndices != secondValue.removedIndices)
  let p0 = rootValue.strokes.withUnsafeBufferPointer { Int(bitPattern: $0.baseAddress) }
  let p1 = firstValue.strokes.withUnsafeBufferPointer { Int(bitPattern: $0.baseAddress) }
  let p2 = secondValue.strokes.withUnsafeBufferPointer { Int(bitPattern: $0.baseAddress) }
  #expect(p0 == p1 && p0 == p2)
  #expect(package.assessments.count == 2)
  await fixture.library.closeLibrary()
}

@Test("Root reuse preserves observed verification status but requires exact producer identity and receipt",
  arguments: ["observed-status", "producer-id", "producer-version", "producer-receipt"])
func provenanceBasis(change: String) async throws {
  let root = DrawingExchangeFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
  let fixture = try await DrawingExchangeFeedbackFixture.make(directory: root, candidateCount: 1)
  let candidate = fixture.candidates[0][0]
  let prune = try await fixture.store.applyPrune(candidateID: candidate.id, action: .remove, indices: [0])
  let ref = try await fixture.store.feedbackReference(for: prune.id)
  let original = try await fixture.library.feedback(ref.publication)
  let base = try await fixture.store.featureCapsule(candidateID: candidate.id)
  let mask = try await fixture.store.featureCapsule(candidateID: candidate.id, revisionID: prune.id)
  var object = try ExchangeJSON.validate(DrawingArtifactCoding.encoder().encode(mask))
  var producer = try #require(object["producer"] as? [String: Any])
  switch change {
  case "observed-status":
    producer["nativeVerified"] = !mask.producer.nativeVerified
    var extractor = try #require(object["extractor"] as? [String: Any])
    extractor["nativeVerified"] = !mask.extractor.nativeVerified
    object["extractor"] = extractor
  case "producer-id": producer["id"] = mask.producer.id + ".different"
  case "producer-version": producer["version"] = mask.producer.version + ".different"
  default:
    producer["record"] = try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(mask.extractor.record))
  }
  object["producer"] = producer
  let changed = try JSONDecoder().decode(FlowPortfolioFeatureCapsule.self, from: DrawingExchangeFeedbackFixture.json(object))
  let asset = try changed.asset
  var files: [String: Data] = [:]
  for entry in original.files.entries.values where entry.path.hasPrefix("data/") {
    files[entry.path] = try original.files.record(at: entry.path, maximumBytes: 128 * 1024 * 1024)
  }
  files["data/objects/sha256/" + asset.object.description] = try DrawingArtifactCoding.encoder().encode(changed)
  var index = try ExchangeJSON.validate(try #require(files["data/exchange.json"]))
  var descriptors = try #require(index["assets"] as? [[String: Any]])
  descriptors.append(try #require(JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(ExchangeAssetDescriptor(asset: asset))) as? [String: Any]))
  index["assets"] = descriptors
  files["data/exchange.json"] = try DrawingExchangeFeedbackFixture.json(index)
  let prepared = try FlowFeedbackCarrier.prepare(files)
  defer { try? FileManager.default.removeItem(at: prepared.temporaryRoot) }
  if change == "observed-status" {
    let value = try FlowFeedbackReader.feature(asset, package: prepared.package)
    #expect(value.strokes == base.strokes)
    #expect(value.producer.nativeVerified != base.producer.nativeVerified)
    #expect(value.extractor.nativeVerified != base.extractor.nativeVerified)
    #expect(value.producer.record == base.producer.record)
  } else {
    #expect(throws: (any Error).self) { try FlowFeedbackReader.feature(asset, package: prepared.package) }
  }
  await fixture.library.closeLibrary()
}

@Test("A mask capsule cannot substitute different vectors or shape for its pinned root", arguments: [false, true])
func mismatchedSharedPruneBasis(shape: Bool) async throws {
  let root = DrawingExchangeFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
  let fixture = try await DrawingExchangeFeedbackFixture.make(directory: root, candidateCount: 1)
  let candidate = fixture.candidates[0][0]
  let prune = try await fixture.store.applyPrune(candidateID: candidate.id, action: .remove, indices: [0])
  let ref = try await fixture.store.feedbackReference(for: prune.id)
  let original = try await fixture.library.feedback(ref.publication)
  var bad = try await fixture.store.featureCapsule(candidateID: candidate.id, revisionID: prune.id)
  if shape { bad.strokes.removeLast() } else { bad.strokes[0][0] += 0.125 }
  let bytes = try DrawingArtifactCoding.encoder().encode(bad), asset = try bad.asset
  var files: [String: Data] = [:]
  for entry in original.files.entries.values where entry.path.hasPrefix("data/") {
    files[entry.path] = try original.files.record(at: entry.path, maximumBytes: 128 * 1024 * 1024)
  }
  files["data/objects/sha256/" + asset.object.description] = bytes
  var index = try ExchangeJSON.validate(try #require(files["data/exchange.json"]))
  var descriptors = try #require(index["assets"] as? [[String: Any]])
  descriptors.append(try #require(JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(ExchangeAssetDescriptor(asset: asset))) as? [String: Any]))
  index["assets"] = descriptors
  files["data/exchange.json"] = try DrawingExchangeFeedbackFixture.json(index)
  let prepared = try FlowFeedbackCarrier.prepare(files)
  defer { try? FileManager.default.removeItem(at: prepared.temporaryRoot) }
  #expect(throws: (any Error).self) { try FlowFeedbackReader.feature(asset, package: prepared.package) }
  await fixture.library.closeLibrary()
}

}
