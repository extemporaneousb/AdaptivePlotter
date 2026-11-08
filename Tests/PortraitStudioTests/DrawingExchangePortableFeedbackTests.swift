import Foundation
import DrawingLibrary
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary
import Testing

@Suite("DX09 portable canonical feedback", .serialized)
struct DrawingExchangePortableFeedbackTests {
  @Test("Rank is the sole human response; its software marker supersedes within one presentation")
  func canonicalRankingAndMarker() async throws {
    let root = DrawingExchangeFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try await DrawingExchangeFeedbackFixture.make(directory: root)
    let presentation = try await fixture.store.presentRoundRanking(fixture.candidates[0][0].roundID, seed: 42)
    let first = try await fixture.store.recordRanking(presentationID: presentation.id, orderedGroups: [[presentation.items[0].id]])
    let firstRef = try await fixture.store.feedbackReference(for: first.id)
    let original = try await fixture.library.feedback(firstRef.publication)
    let capsuleRef = try #require(firstRef.ranking)
    let capsule = try #require(original.rankingCapsules[capsuleRef])
    #expect(capsule.responseKind == "partial-ranking")
    let targets = try #require(original.assessments[firstRef.assessment]?.targets)
    try #require(targets.count == 1)
    if case .rankingCapsule(let target) = targets[0] { #expect(target == capsuleRef) }
    else { Issue.record("Software marker did not target exact human capsule") }
    let second = try await fixture.store.recordRanking(presentationID: presentation.id, orderedGroups: [], neither: true)
    let secondRef = try await fixture.store.feedbackReference(for: second.id)
    let revised = try await fixture.library.feedback(secondRef.publication)
    #expect(revised.assessments[secondRef.assessment]?.supersedes == [firstRef.assessment])
    #expect(revised.assessments[secondRef.assessment]?.answerType == "adaptiveplotter.recorded-ranking-revision")
    let newCapsule = try #require(secondRef.ranking)
    #expect(revised.rankingCapsules[newCapsule]?.responseKind == "neither")
    #expect(try await fixture.library.feedback(firstRef.publication).rankingCapsules[capsuleRef]?.originalJSON == capsule.originalJSON)
    #expect(try await fixture.library.drawings().entries.isEmpty)
    await fixture.library.closeLibrary()
  }

  @Test("Closed feedback preserves optional display previews and reopens without source records or programs")
  func offlineFeatureOnly() async throws {
    let root = DrawingExchangeFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("original")
    let fixture = try await DrawingExchangeFeedbackFixture.make(directory: directory)
    let presentation = try await fixture.store.presentRoundRanking(fixture.candidates[0][0].roundID, seed: 42)
    let rank = try await fixture.store.recordRanking(presentationID: presentation.id, orderedGroups: presentation.items.map { [$0.id] })
    let ref = try await fixture.store.feedbackReference(for: rank.id)
    let original = try await fixture.library.feedback(ref.publication)
    let originalBytes = try Dictionary(uniqueKeysWithValues: original.files.entries.keys.map { ($0, try original.files.record(at: $0)) })
    let exported = root.appendingPathComponent("feedback.zip")
    try await fixture.store.exportFeedback(judgmentID: rank.id, to: exported)
    await fixture.library.closeLibrary()
    try FileManager.default.removeItem(at: directory)
    let offline = DrawingLibrary(directoryURL: root.appendingPathComponent("offline"))
    let imported = try await offline.mountFeedback(from: exported)
    #expect(imported == ref.publication)
    let package = try await offline.feedback(imported)
    #expect(package.index.originalJSON == original.index.originalJSON)
    #expect(package.drawings.isEmpty)
    #expect(!package.files.entries.keys.contains { $0.hasPrefix("data/photos/") || $0.hasPrefix("data/inputs/") || $0.hasPrefix("data/drawings/") })
    for (path, entry) in original.files.entries {
      #expect(package.files.entries[path]?.digest == entry.digest)
      #expect(try package.files.record(at: path) == originalBytes[path])
    }
    let decoded: FlowPortfolioRanking = try FlowFeedbackReader.value(FlowPortfolioRanking.self, reference: ref, id: rank.id, package: package)
    #expect(decoded.orderedGroups == rank.orderedGroups && !decoded.skipped && !decoded.neither)
    #expect(try await offline.drawings().entries.isEmpty)
    await offline.closeLibrary()
  }
  @Test("A second-phase choice failure retains only the explicitly authorized Drawing while feedback and navigation await recovery")
  func authoredThenFeedbackBoundary() async throws {
    let root = DrawingExchangeFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try await DrawingExchangeFeedbackFixture.make(directory: root)
    let candidate = fixture.candidates[0][0]
    let expectedProgram = try await fixture.store.candidateProgram(candidate.id)
    try await fixture.library.failFeedbackAfterAuthoredRetention()
    await #expect(throws: DrawingExchangeFeedbackFailure.self) { try await fixture.store.chooseCandidate(candidate.id) }
    let retained = try await fixture.library.drawings().entries
    try #require(retained.count == 1)
    #expect(await fixture.store.snapshot().choices.isEmpty)
    #expect(try await fixture.library.records(kind: "adaptiveplotter.flow-choice/2").isEmpty)
    let exact = try await fixture.library.drawing(retained[0].reference)
    #expect(exact.program == expectedProgram)
    try await fixture.library.feedbackFault(nil)
    try await fixture.store.reloadCommittedState()
    let committed = await fixture.store.snapshot()
    try #require(committed.choices.count == 1)
    let ref = try await fixture.store.feedbackReference(for: committed.choices[0].id)
    #expect(try await fixture.library.feedback(ref.publication).assessments[ref.assessment] != nil)
    try await fixture.store.reloadCommittedState()
    #expect(await fixture.store.snapshot().choices.count == 1)
    #expect(try await fixture.library.drawings().entries.map(\.reference) == retained.map(\.reference))
    await fixture.library.closeLibrary()
    let owner = DrawingLibrary(directoryURL: root)
    let reopened = FlowPortfolioStore(directory: root, purpose: .validationFixture, library: owner)
    try await reopened.loadRecords()
    #expect(await reopened.snapshot().choices.count == 1)
    #expect(try await owner.drawing(retained[0].reference).program == exact.program)
    await owner.closeLibrary()
  }

  @Test("Preserved feedback does not acquire Flow meaning through an unknown question, adapter or marker answer", arguments: ["question", "adapter", "answer"])
  func strictTaskReader(field: String) async throws {
    let root = DrawingExchangeFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try await DrawingExchangeFeedbackFixture.make(directory: root)
    let presentation = try await fixture.store.presentRoundRanking(fixture.candidates[0][0].roundID, seed: 42)
    let rank = try await fixture.store.recordRanking(presentationID: presentation.id, orderedGroups: presentation.items.map { [$0.id] })
    let ref = try await fixture.store.feedbackReference(for: rank.id)
    let original = try await fixture.library.feedback(ref.publication)
    var files: [String: Data] = [:]
    for path in original.files.entries.keys where path.hasPrefix("data/") { files[path] = try original.files.record(at: path) }
    let path = "data/assessments/" + ref.assessment.issuer.uuidString.lowercased() + "/" + ref.assessment.revision.uuidString.lowercased() + ".json"
    let prior = try #require(files[path])
    var object = try #require(JSONSerialization.jsonObject(with: prior) as? [String: Any])
    switch field {
    case "question":
      var value = try #require(object["question"] as? [String: Any]); value["id"] = "example.other-question"; object["question"] = value
    case "adapter":
      var value = try #require(object["reviewer"] as? [String: Any]); value["id"] = "example.other-adapter"; object["reviewer"] = value
    default:
      var value = try #require(object["answer"] as? [String: Any]); value["type"] = "example.other-answer"; object["answer"] = value
    }
    let changed = try DrawingExchangeFeedbackFixture.json(object)
    files[path] = changed
    let index = try #require(files["data/exchange.json"])
    files["data/exchange.json"] = Data(String(decoding: index, as: UTF8.self).replacingOccurrences(of: ref.assessment.digest.description, with: ExchangeDigest.hash(changed).description).utf8)
    let prepared = try FlowFeedbackCarrier.prepare(files)
    defer { try? FileManager.default.removeItem(at: prepared.temporaryRoot) }
    let selected = FlowPortfolioFeedbackReference(publication: DrawingLibraryFeedbackRef(publication: prepared.package),
      assessment: .init(issuer: ref.assessment.issuer, revision: ref.assessment.revision, digest: .hash(changed)), ranking: ref.ranking)
    #expect(prepared.package.assessments[selected.assessment]?.originalJSON == changed)
    #expect(throws: (any Error).self) { try FlowFeedbackReader.value(FlowPortfolioRanking.self, reference: selected, id: rank.id, package: prepared.package) }
    await fixture.library.closeLibrary()
  }

  @Test("Feature-only task pruning answers preserve semantic edits without local transport references")
  func pruneAnswerIsSemanticOnly() async throws {
    let root = DrawingExchangeFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try await DrawingExchangeFeedbackFixture.make(directory: root)
    let candidate = fixture.candidates[0][0]
    try await fixture.store.chooseCandidate(candidate.id)
    var revisions: [FlowPortfolioPruneRevision] = []
    let actions: [(FlowPruneAction, [Int])] = [(.remove, [0]), (.restore, [0]), (.undo, []), (.redo, []), (.completeTarget, [])]
    for (action, indices) in actions {
      revisions.append(try await fixture.store.applyPrune(candidateID: candidate.id, action: action, indices: indices))
    }
    let snapshot = try await fixture.store.freezeTrainingSnapshot()
    let publication = try #require(snapshot.publication)
    let task = try await fixture.library.feedback(publication)
    let forbidden: Set<String> = ["drawing", "feedback", "historicalRecord", "publication", "archiveURL", "libraryURL", "affectedIndices", "removedIndices"]
    let basis = try await fixture.store.candidateProgram(candidate.id).strokes.map(\.id)
    func transportKeys(_ value: Any) -> Set<String> {
      if let object = value as? [String: Any] {
        return Set(object.keys).intersection(forbidden).union(object.values.reduce(into: Set<String>()) { $0.formUnion(transportKeys($1)) })
      }
      if let values = value as? [Any] { return values.reduce(into: Set<String>()) { $0.formUnion(transportKeys($1)) } }
      return []
    }
    for revision in revisions {
      let originalRef = try await fixture.store.feedbackReference(for: revision.id)
      let ref = FlowPortfolioFeedbackReference(publication: publication, assessment: originalRef.assessment, ranking: nil)
      let assessment = try #require(task.assessments[ref.assessment])
      let record = try #require(JSONSerialization.jsonObject(with: assessment.originalJSON) as? [String: Any])
      let answer = try #require(record["answer"] as? [String: Any])
      let value = try #require(answer["value"] as? [String: Any])
      #expect(transportKeys(value).isEmpty)
      let semantic = try JSONDecoder().decode(FlowCanonicalPruneAnswer.self, from: DrawingExchangeFeedbackFixture.json(value))
      #expect(semantic.affectedStrokeIDs == revision.affectedIndices.map { basis[$0] })
      #expect(semantic.removedStrokeIDs == revision.removedIndices.map { basis[$0] })
      let decoded: FlowPortfolioPruneRevision = try FlowFeedbackReader.value(FlowPortfolioPruneRevision.self, reference: ref, id: revision.id, package: task)
      #expect(decoded.action == revision.action && decoded.affectedIndices == revision.affectedIndices)
      #expect(decoded.removedIndices == revision.removedIndices && decoded.parentRevisionID == revision.parentRevisionID)
      #expect(decoded.operationID == revision.operationID)
      #expect(decoded.undoOperationIDs == revision.undoOperationIDs && decoded.redoOperationIDs == revision.redoOperationIDs)
      #expect(decoded.drawing == nil && decoded.historicalRecord == nil)
    }
    #expect(task.drawings.isEmpty)
    #expect(!task.files.entries.keys.contains { $0.hasPrefix("data/drawings/") || $0.hasPrefix("data/photos/") || $0.hasPrefix("data/inputs/") })
    #expect(task.index.known?.assets.allSatisfy { !["image/png", "image/jpeg"].contains($0.asset.mediaType) } == true)
    await fixture.library.closeLibrary()
  }

  @Test("A freshly rehashed predecessor chain remains preservable but rejects unsupported or divergent task meaning", arguments: ["required-feature", "response", "presentation-order", "feature-basis"])
  func strictPredecessorChain(mutation: String) async throws {
    let root = DrawingExchangeFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try await DrawingExchangeFeedbackFixture.make(directory: root)
    let shown = try await fixture.store.presentRoundRanking(fixture.candidates[0][0].roundID, seed: 42)
    let first = try await fixture.store.recordRanking(presentationID: shown.id, orderedGroups: shown.items.map { [$0.id] })
    let firstRef = try await fixture.store.feedbackReference(for: first.id)
    let second = try await fixture.store.recordRanking(presentationID: shown.id, orderedGroups: [], neither: true)
    let ref = try await fixture.store.feedbackReference(for: second.id)
    let package = try await fixture.library.feedback(ref.publication)
    let predecessor = try #require(firstRef.ranking)
    var files: [String: Data] = [:]
    for path in package.files.entries.keys where path.hasPrefix("data/") { files[path] = try package.files.record(at: path) }
    let rankingPath = "data/rankings/" + predecessor.issuer.uuidString.lowercased() + "/" + predecessor.revision.uuidString.lowercased() + ".json"
    let old = try #require(files[rankingPath])
    var ranking = try #require(JSONSerialization.jsonObject(with: old) as? [String: Any])
    switch mutation {
    case "required-feature": ranking["requiredFeatures"] = ["example.unknown-predecessor/1"]
    case "response": ranking["response"] = ["kind": "future-response"]
    default:
      var presentations = try #require(ranking["presentations"] as? [[String: Any]])
      try #require(presentations.count >= 2)
      if mutation == "presentation-order" { presentations.swapAt(0, 1) }
      else { presentations[0]["features"] = presentations[1]["features"] }
      ranking["presentations"] = presentations
    }
    let changed = try DrawingExchangeFeedbackFixture.json(ranking)
    files[rankingPath] = changed
    func rewrite(_ path: String, from: ExchangeDigest, to: ExchangeDigest) throws -> ExchangeDigest {
      let old = try #require(files[path])
      let next = Data(String(decoding: old, as: UTF8.self).replacingOccurrences(of: from.description, with: to.description).utf8)
      files[path] = next; return .hash(next)
    }
    let priorPath = "data/assessments/" + firstRef.assessment.issuer.uuidString.lowercased() + "/" + firstRef.assessment.revision.uuidString.lowercased() + ".json"
    let priorDigest = try rewrite(priorPath, from: predecessor.digest, to: .hash(changed))
    let currentPath = "data/assessments/" + ref.assessment.issuer.uuidString.lowercased() + "/" + ref.assessment.revision.uuidString.lowercased() + ".json"
    let currentDigest = try rewrite(currentPath, from: firstRef.assessment.digest, to: priorDigest)
    _ = try rewrite("data/exchange.json", from: ref.assessment.digest, to: currentDigest)
    let rebuilt = try FlowFeedbackCarrier.prepare(files)
    defer { try? FileManager.default.removeItem(at: rebuilt.temporaryRoot) }
    let selected = FlowPortfolioFeedbackReference(publication: DrawingLibraryFeedbackRef(publication: rebuilt.package),
      assessment: .init(issuer: ref.assessment.issuer, revision: ref.assessment.revision, digest: currentDigest), ranking: ref.ranking)
    let exactPredecessor = RankingCapsuleRef(issuer: predecessor.issuer, revision: predecessor.revision, digest: .hash(changed))
    #expect(rebuilt.package.rankingCapsules[exactPredecessor]?.originalJSON == changed)
    #expect(rebuilt.package.assessments[selected.assessment]?.supersedes.first?.digest == priorDigest)
    #expect(throws: (any Error).self) {
      try FlowFeedbackReader.value(FlowPortfolioRanking.self, reference: selected, id: second.id, package: rebuilt.package)
    }
    await fixture.library.closeLibrary()
  }

  @Test("Nested producer descriptors require exact registered JSON semantics despite identical bytes", arguments: ["mediaType", "encoding"])
  func nestedExactAssetDescriptor(field: String) async throws {
    let root = DrawingExchangeFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try await DrawingExchangeFeedbackFixture.make(directory: root)
    let shown = try await fixture.store.presentRoundRanking(fixture.candidates[0][0].roundID, seed: 42)
    let rank = try await fixture.store.recordRanking(presentationID: shown.id, orderedGroups: shown.items.map { [$0.id] })
    let ref = try await fixture.store.feedbackReference(for: rank.id)
    let package = try await fixture.library.feedback(ref.publication)
    let capsule = try await fixture.store.featureCapsule(candidateID: fixture.candidates[0][0].id)
    let asset = try capsule.asset
    let positive = try FlowFeedbackReader.feature(asset, package: package)
    #expect(positive.producer.record == capsule.producer.record)
    let featureBytes = try package.files.record(asset.object)
    let mismatch = try ExchangeAsset(bytes: featureBytes, mediaType: "application/json", encoding: "opaque")
    #expect(mismatch.object == asset.object && mismatch.byteLength == asset.byteLength)
    #expect(throws: (any Error).self) { try FlowFeedbackReader.feature(mismatch, package: package) }
    #expect(throws: (any Error).self) {
      try FlowFeedbackReader.feature(asset, package: package, budget: FlowFeatureReadBudget(maximumBytes: 1))
    }
    var files: [String: Data] = [:]
    for path in package.files.entries.keys where path.hasPrefix("data/") { files[path] = try package.files.record(at: path) }
    let indexBytes = try #require(files["data/exchange.json"])
    var index = try #require(JSONSerialization.jsonObject(with: indexBytes) as? [String: Any])
    var descriptors = try #require(index["assets"] as? [[String: Any]])
    let position = try #require(descriptors.firstIndex { $0["object"] as? String == capsule.producer.record.object.description })
    descriptors[position][field] = field == "mediaType" ? "application/octet-stream" : "opaque"
    index["assets"] = descriptors
    files["data/exchange.json"] = try DrawingExchangeFeedbackFixture.json(index)
    let changed = try FlowFeedbackCarrier.prepare(files)
    defer { try? FileManager.default.removeItem(at: changed.temporaryRoot) }
    // Core can preserve this descriptor and JSON bytes; the owning Flow task
    // must not silently substitute its nested receipt's original descriptor.
    #expect(try changed.package.files.record(capsule.producer.record.object) == package.files.record(capsule.producer.record.object))
    #expect(throws: (any Error).self) { try FlowFeedbackReader.feature(asset, package: changed.package) }
    let selected = FlowPortfolioFeedbackReference(publication: DrawingLibraryFeedbackRef(publication: changed.package), assessment: ref.assessment, ranking: ref.ranking)
    #expect(throws: (any Error).self) {
      try FlowFeedbackReader.value(FlowPortfolioRanking.self, reference: selected, id: rank.id, package: changed.package)
    }
    await fixture.library.closeLibrary()
  }

}
