import Foundation
import DrawingLibrary
import PortraitCore
import PortraitArtists
import PlotterModel

package struct FlowPortfolioFeedbackReference: Codable, Equatable, Sendable {
  package let publication: DrawingLibraryFeedbackRef
  package let assessment: AssessmentRef
  package let ranking: RankingCapsuleRef?
}
struct FlowFeedbackNavigation: Codable, Identifiable {
  let id: UUID
  let feedback: FlowPortfolioFeedbackReference
  let drawing: DrawingRef?
}
struct FlowPreparedFeedback: Sendable {
  let package: ValidatedExchangePackage
  let temporaryRoot: URL
}
package struct FlowFeatureExtractorConfiguration: Codable, Equatable, Sendable {
  package let profile: String
  package let revision: String
  package let drawingCount: Int
  package let strokeCount: Int
  package var requiredFeatures: [String] = []
  package static let current = Self(profile: "adaptiveplotter.flow-extractor/1", revision: FlowArtistFeatures.revision,
    drawingCount: FlowArtistFeatures.drawingCount, strokeCount: FlowArtistFeatures.strokeCount)
}
struct FlowRankingNavigation: Codable {
  let id: UUID
  let createdAt: Date
  let presentationID: UUID
  let supersedesID: UUID?
}

/// Canonical answers contain semantic observations only. Authored Drawing and
/// local publication pointers belong exclusively to navigation rows.
struct FlowCanonicalChoiceAnswer: Codable {
  let id: UUID
  let createdAt: Date
  let roundID: UUID
  let candidateID: UUID
  let offeredCandidateIDs: [UUID]
  let selectedItemID: UUID
  let offeredItems: [FlowPortfolioPresentationItem]
  let purpose: String
  init(_ value: FlowPortfolioChoice) {
    id = value.id; createdAt = value.createdAt; roundID = value.roundID; candidateID = value.candidateID
    offeredCandidateIDs = value.offeredCandidateIDs; selectedItemID = value.selectedItemID
    offeredItems = value.offeredItems; purpose = value.purpose
  }
  var projection: FlowPortfolioChoice {
    .init(id: id, createdAt: createdAt, roundID: roundID, candidateID: candidateID,
      offeredCandidateIDs: offeredCandidateIDs, selectedItemID: selectedItemID, offeredItems: offeredItems, purpose: purpose)
  }
}
struct FlowCanonicalPruneAnswer: Codable {
  let id: UUID
  let createdAt: Date
  let candidateID: UUID
  let parentRevisionID: UUID?
  let action: FlowPruneAction
  let affectedStrokeIDs: [StrokeID]
  let removedStrokeIDs: [StrokeID]
  let operationID: UUID?
  let undoOperationIDs: [UUID]
  let redoOperationIDs: [UUID]
  init(_ value: FlowPortfolioPruneRevision, basis: [StrokeID]) {
    id = value.id; createdAt = value.createdAt; candidateID = value.candidateID; parentRevisionID = value.parentRevisionID
    action = value.action; affectedStrokeIDs = value.affectedIndices.map { basis[$0] }; removedStrokeIDs = value.removedIndices.map { basis[$0] }
    operationID = value.operationID; undoOperationIDs = value.undoOperationIDs; redoOperationIDs = value.redoOperationIDs
  }
  func projection(basis: [StrokeID]) throws -> FlowPortfolioPruneRevision {
    let positions = Dictionary(uniqueKeysWithValues: basis.enumerated().map { ($0.element, $0.offset) })
    func indices(_ ids: [StrokeID]) throws -> [Int] {
      guard Set(ids).count == ids.count else { throw FlowPortfolioError.invalid("Duplicate canonical stroke label.") }
      return try ids.map { id in guard let index = positions[id] else { throw FlowPortfolioError.invalid("Foreign canonical stroke label.") }; return index }.sorted()
    }
    return try .init(id: id, createdAt: createdAt, candidateID: candidateID, parentRevisionID: parentRevisionID,
      action: action, affectedIndices: indices(affectedStrokeIDs), removedIndices: indices(removedStrokeIDs), modelID: nil,
      operationID: operationID, inheritedFromRevisionID: nil, historicalRecord: nil, probabilities: nil, threshold: nil,
      policy: nil, undoOperationIDs: undoOperationIDs, redoOperationIDs: redoOperationIDs)
  }
}

extension FlowPortfolioStore {
  func featureSupport(_ bytes: Data) throws -> ExchangeAsset {
    let asset = try ExchangeAsset(bytes: bytes, mediaType: "application/json", encoding: "utf8-json")
    featureSupportingAssets[asset.object] = bytes
    return asset
  }
  func featureClosureAssets() throws -> [DrawingLibraryClosureAsset] {
    var result = try featureSupportingAssets.values.map { bytes in
      DrawingLibraryClosureAsset(descriptor: .init(asset: try ExchangeAsset(bytes: bytes, mediaType: "application/json", encoding: "utf8-json")), bytes: bytes)
    }
    for capsule in featureCapsules.values {
      result.append(.init(descriptor: .init(asset: try capsule.asset), bytes: try DrawingArtifactCoding.encoder().encode(capsule)))
    }
    return result
  }
  func readFeature(_ asset: ExchangeAsset, expectedID: UUID? = nil, candidateID: UUID? = nil) async throws -> FlowPortfolioFeatureCapsule {
    let bytes = try await storage.library.asset(asset.object, maximumBytes: 128 * 1024 * 1024)
    try asset.validate(bytes, maximumBytes: 128 * 1024 * 1024)
    let value = try JSONDecoder().decode(FlowPortfolioFeatureCapsule.self, from: bytes)
    guard value.profile == "adaptiveplotter.flow-features/3", value.requiredFeatures.isEmpty, expectedID == nil || value.id == expectedID,
      candidateID == nil || value.candidateID == candidateID,
      value.strokeIDs.count == value.strokes.count, Set(value.strokeIDs).count == value.strokeIDs.count,
      value.drawing.count == FlowArtistFeatures.drawingCount, value.strokes.count <= 10_000,
      value.strokes.allSatisfy({ $0.count == FlowArtistFeatures.strokeCount }),
      (value.drawing + value.strokes.flatMap { $0 }).allSatisfy({ $0.isFinite && abs($0) <= 100 }),
      Set(value.removedIndices).count == value.removedIndices.count,
      value.removedIndices.allSatisfy({ value.strokeIDs.indices.contains($0) }),
      value.extractor.id == "adaptiveplotter.flow-features", value.extractor.version == FlowArtistFeatures.revision else {
      throw FlowPortfolioError.invalid("Unsupported or malformed frozen feature basis.")
    }
    let configuration = try await readFeedbackAsset(value.extractor.record)
    guard try JSONDecoder().decode(FlowFeatureExtractorConfiguration.self, from: configuration) == .current else {
      throw FlowPortfolioError.unavailable("Frozen feature extractor configuration is unsupported.")
    }
    _ = try ExchangeJSON.validate(await readFeedbackAsset(value.producer.record))
    return value
  }
  func readFeedbackAsset(_ asset: ExchangeAsset) async throws -> Data {
    let bytes = try await storage.library.asset(asset.object, maximumBytes: 128 * 1024 * 1024)
    try asset.validate(bytes, maximumBytes: 128 * 1024 * 1024); return bytes
  }

  /// Resolve immutable feature assets on this actor. The caller assembles its
  /// local closure after the await; no async helper captures mutable buffers.
  private func feedbackFeatureAssets(_ item: FlowPortfolioPresentationItem) async throws
    -> (value: FlowPortfolioFeatureCapsule, assets: [(ExchangeAsset, Data)]) {
    let value = try await featureCapsule(candidateID: item.candidateID, revisionID: item.revisionID)
    var assets = [(try value.asset, try DrawingArtifactCoding.encoder().encode(value))]
    if let root = value.rootFeatures {
      let original = try await featureCapsule(candidateID: value.candidateID)
      guard try original.asset == root else { throw FlowPortfolioError.invalid("Exact root feature basis changed.") }
      assets.append((root, try DrawingArtifactCoding.encoder().encode(original)))
    }
    for asset in [value.producer.record, value.extractor.record] {
      let bytes: Data
      if let local = featureSupportingAssets[asset.object] { bytes = local }
      else { bytes = try await readFeedbackAsset(asset) }
      assets.append((asset, bytes))
    }
    return (value, assets)
  }

  /// Build only the canonical human response closure, never the portfolio/photos
  /// or compared Drawing geometry. Local navigation is committed separately in
  /// the same Library transaction by the owner below.
  func prepareFeedback(next: inout FlowPortfolioSnapshot) async throws -> FlowPreparedFeedback? {
    let newChoices = next.choices.filter { $0.feedback == nil }
    let newRanks = next.rankings.filter { $0.feedback == nil }
    let newPrunes = next.pruneRevisions.filter { $0.feedback == nil && $0.action != .modelProposal && $0.action != .inheritedSelection }
    guard !newChoices.isEmpty || !newRanks.isEmpty || !newPrunes.isEmpty else { return nil }
    var files: [String: Data] = [:], descriptors: [ExchangeDigest: ExchangeAssetDescriptor] = [:]
    var assessments: [AssessmentRef] = [], rankings: [RankingCapsuleRef] = []
    var pointers: [UUID: (AssessmentRef, RankingCapsuleRef?)] = [:]
    func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(value)) }
    func json(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) }
    func addAsset(_ asset: ExchangeAsset, bytes: Data) throws {
      try asset.validate(bytes, maximumBytes: 128 * 1024 * 1024)
      let descriptor = ExchangeAssetDescriptor(asset: asset)
      if let old = descriptors[asset.object], old != descriptor { throw FlowPortfolioError.invalid("Feedback asset descriptor conflict.") }
      descriptors[asset.object] = descriptor; files["data/objects/sha256/" + asset.object.description] = bytes
    }
    func localAsset(_ bytes: Data) throws -> ExchangeAsset {
      let asset = try ExchangeAsset(bytes: bytes, mediaType: "application/json", encoding: "utf8-json")
      try addAsset(asset, bytes: bytes); return asset
    }
    func identity(_ id: UUID) throws -> Any { try object(ExchangeIdentity(issuer: state.id, revision: id)) }
    func timestamp(_ date: Date) throws -> Any { try object(ExchangeTimestamp(wallTime: ISO8601DateFormatter().string(from: date))) }
    func question(_ id: String, _ text: String) -> [String: Any] { ["id": id, "version": "1", "text": text] }
    let human: [String: Any] = ["kind": "human", "id": "local-operator"]
    func assessment(id: UUID, date: Date, target: [String: Any], answerType: String, answer: Any,
      support: [ExchangeAsset], region: ExchangeAsset? = nil, previous: [AssessmentRef] = [], administrative: Bool = false) throws -> AssessmentRef {
      let reviewer: [String: Any]
      if administrative { reviewer = ["kind": "algorithm", "id": "adaptiveplotter.flow-feedback-adapter", "version": "1"] }
      else { reviewer = human }
      let questionID = administrative ? "adaptiveplotter.recorded-ranking-revision" : answerType
      let questionText: String
      if administrative { questionText = "Recorded ranking revision" }
      else if answerType == "adaptiveplotter.flow-choice" { questionText = "Which offered direction did you choose?" }
      else { questionText = "Which original strokes should remain?" }
      let wireIdentity = try identity(id)
      let wireTime = try timestamp(date)
      let wireSupport = try object(support)
      let wirePrevious = try object(previous)
      let wireQuestion = question(questionID, questionText)
      let wireAnswer: [String: Any] = ["type": answerType, "value": answer]
      var record: [String: Any] = ["profile": "adaptiveplotter.assessment/1", "requiredFeatures": [String](),
        "ref": wireIdentity, "targets": [target], "reviewer": reviewer, "question": wireQuestion,
        "time": wireTime, "answer": wireAnswer, "supportingAssets": wireSupport, "supersedes": wirePrevious]
      if let region { record["regionOrStrokes"] = try object(region) }
      let bytes = try json(record), ref = AssessmentRef(issuer: state.id, revision: id, digest: .hash(bytes))
      _ = try ExchangeAssessment(originalJSON: bytes)
      files["data/assessments/" + state.id.uuidString.lowercased() + "/" + id.uuidString.lowercased() + ".json"] = bytes
      assessments.append(ref); return ref
    }
    for choice in newChoices {
      var support: [ExchangeAsset] = []
      for item in choice.offeredItems {
        let resolved = try await feedbackFeatureAssets(item)
        for (asset, bytes) in resolved.assets { try addAsset(asset, bytes: bytes) }
        support.append(try resolved.value.asset)
      }
      guard let selected = choice.offeredItems.firstIndex(where: { $0.id == choice.selectedItemID }) else { throw FlowPortfolioError.invalid("Choice target missing.") }
      let ref = try assessment(id: choice.id, date: choice.createdAt, target: ["kind": "asset", "asset": try object(support[selected])],
        answerType: "adaptiveplotter.flow-choice", answer: object(FlowCanonicalChoiceAnswer(choice)), support: support)
      pointers[choice.id] = (ref, nil)
    }
    for prune in newPrunes {
      guard let candidate = next.candidates.first(where: { $0.id == prune.candidateID }) else { throw FlowPortfolioError.invalid("Prune candidate missing.") }
      let baseAssets = try await feedbackFeatureAssets(.init(id: candidate.id, candidateID: candidate.id, revisionID: nil, sourceID: candidate.sourceID, removedIndices: []))
      for (asset, bytes) in baseAssets.assets { try addAsset(asset, bytes: bytes) }
      let base = baseAssets.value
      let editedAssets = try await feedbackFeatureAssets(.init(id: prune.id, candidateID: candidate.id, revisionID: prune.id, sourceID: candidate.sourceID, removedIndices: prune.removedIndices))
      for (asset, bytes) in editedAssets.assets { try addAsset(asset, bytes: bytes) }
      let edited = editedAssets.value
      let region = try localAsset(DrawingArtifactCoding.encoder().encode(base.strokeIDs))
      let ref = try assessment(id: prune.id, date: prune.createdAt, target: ["kind": "asset", "asset": try object(base.asset)],
        answerType: "adaptiveplotter.flow-pruning", answer: object(FlowCanonicalPruneAnswer(prune, basis: base.strokeIDs)), support: [base.asset, edited.asset], region: region)
      pointers[prune.id] = (ref, nil)
    }
    for rank in newRanks {
      guard let presentation = next.presentations.first(where: { $0.id == rank.presentationID }) else { throw FlowPortfolioError.invalid("Ranking presentation missing.") }
      var shown: [[String: Any]] = []
      for item in presentation.items {
        let resolved = try await feedbackFeatureAssets(item)
        for (asset, bytes) in resolved.assets { try addAsset(asset, bytes: bytes) }
        let value = resolved.value
        shown.append(["id": item.id.uuidString.lowercased(), "features": try object(value.asset),
          "producer": ["id": value.producer.id, "version": value.producer.version, "record": value.producer.record.object.description],
          "extractor": ["id": value.extractor.id, "version": value.extractor.version, "record": value.extractor.record.object.description]])
      }
      let navigation = FlowRankingNavigation(id: rank.id, createdAt: rank.createdAt, presentationID: rank.presentationID, supersedesID: rank.supersedesID)
      let ranked = Set(rank.orderedGroups.flatMap { $0 }), all = Set(presentation.items.map(\.id))
      let response: [String: Any], required: [String]
      if rank.neither { response = ["kind": "neither"]; required = [ExchangeRankingCapsule.neitherFeature] }
      else if rank.skipped { response = ["kind": "skip", "reason": "Operator skipped this presentation."]; required = [] }
      else if ranked == all { response = ["kind": "ranking", "groups": rank.orderedGroups.map { $0.map { $0.uuidString.lowercased() } }]; required = [] }
      else { response = ["kind": "partial-ranking", "groups": rank.orderedGroups.map { $0.map { $0.uuidString.lowercased() } }, "unranked": presentation.items.filter { !ranked.contains($0.id) }.map { $0.id.uuidString.lowercased() }]; required = [ExchangeRankingCapsule.partialRankingFeature] }
      let record: [String: Any] = ["profile": "adaptiveplotter.feature-ranking/1", "requiredFeatures": required, "ref": try identity(rank.id),
        "geometry": "omitted", "limitations": "Features only; no geometry re-extraction or arbitrary future image labels.", "createdAt": try timestamp(rank.createdAt), "reviewer": human,
        "question": question("adaptiveplotter.flow-ranking", "Which offered directions do you prefer?"), "presentations": shown, "response": response,
        "flowNavigation": try object(navigation), "flowPresentation": try object(presentation)]
      let bytes = try json(record), capsule = RankingCapsuleRef(issuer: state.id, revision: rank.id, digest: .hash(bytes))
      _ = try ExchangeRankingCapsule(originalJSON: bytes)
      files["data/rankings/" + state.id.uuidString.lowercased() + "/" + rank.id.uuidString.lowercased() + ".json"] = bytes; rankings.append(capsule)
      var previous: [AssessmentRef] = []
      if let supersedes = rank.supersedesID {
        guard let prior = next.rankings.first(where: { $0.id == supersedes }), prior.presentationID == rank.presentationID,
          let exact = prior.feedback else { throw FlowPortfolioError.invalid("Ranking supersession scope or prior marker unavailable.") }
        let package = try await storage.library.feedback(exact.publication)
        for entry in package.files.entries.values where entry.path.hasPrefix("data/") && entry.path != "data/exchange.json" {
          let old = try package.files.record(at: entry.path, maximumBytes: 128 * 1024 * 1024)
          if let existing = files[entry.path], existing != old { throw FlowPortfolioError.invalid("Feedback closure conflict.") }; files[entry.path] = old
        }
        for descriptor in package.index.known?.assets ?? [] {
          if let old = descriptors[descriptor.asset.object], old != descriptor { throw FlowPortfolioError.invalid("Feedback descriptor conflict.") }; descriptors[descriptor.asset.object] = descriptor
        }
        previous = [exact.assessment]
      }
      let marker = try assessment(id: UUID(), date: rank.createdAt, target: ["kind": "ranking-capsule", "ref": try object(capsule)],
        answerType: "adaptiveplotter.recorded-ranking-revision", answer: object(capsule), support: [], previous: previous, administrative: true)
      pointers[rank.id] = (marker, capsule)
    }
    // Display-only previews preserve reopening visuals. Canonical feedback and
    // training manifests never reference them; task export selects its own closure.
    for value in try await storage.closureAssets(previewArtifacts.values.map(\.image)) {
      let asset = value.descriptor.asset
      if let old = descriptors[asset.object], old != value.descriptor { throw FlowPortfolioError.invalid("Preview descriptor conflict.") }
      try asset.validate(value.bytes, maximumBytes: 128 * 1024 * 1024)
      descriptors[asset.object] = value.descriptor; files["data/objects/sha256/" + asset.object.description] = value.bytes
    }
    let index: [String: Any] = ["profile": "adaptiveplotter.exchange/1", "requiredFeatures": [String](), "kind": "feedback", "roots": [String](),
      "includedAsOf": ISO8601DateFormatter().string(from: Date()), "attempts": [String](), "assessments": try object(assessments),
      "rankingCapsules": try object(rankings), "assets": try object(descriptors.values.sorted { $0.asset.object.description < $1.asset.object.description })]
    files["data/exchange.json"] = try json(index)
    let prepared = try FlowFeedbackCarrier.prepare(files)
    let publication = DrawingLibraryFeedbackRef(publication: prepared.package)
    for (id, refs) in pointers {
      let pointer = FlowPortfolioFeedbackReference(publication: publication, assessment: refs.0, ranking: refs.1)
      if let i = next.choices.firstIndex(where: { $0.id == id }) { next.choices[i].feedback = pointer }
      if let i = next.pruneRevisions.firstIndex(where: { $0.id == id }) { next.pruneRevisions[i].feedback = pointer }
      if let i = next.rankings.firstIndex(where: { $0.id == id }) { next.rankings[i].feedback = pointer }
    }
    return prepared
  }
}

enum FlowFeedbackCarrier {
  static func prepare(_ files: [String: Data]) throws -> FlowPreparedFeedback {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("flow-feedback-" + UUID().uuidString.lowercased(), isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    var success = false; defer { if !success { try? FileManager.default.removeItem(at: root) } }
    let bag = root.appendingPathComponent("bag", isDirectory: true)
    for (path, bytes) in files {
      guard path.hasPrefix("data/"), !path.split(separator: "/").contains("..") else { throw FlowPortfolioError.invalid("Feedback path.") }
      let target = bag.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      try bytes.write(to: target, options: .atomic)
    }
    let bagit = Data("BagIt-Version: 1.0\nTag-File-Character-Encoding: UTF-8\n".utf8)
    let manifest = Data(files.keys.sorted().map { ExchangeDigest.hash(files[$0]!).description + "  " + $0 + "\n" }.joined().utf8)
    try bagit.write(to: bag.appendingPathComponent("bagit.txt")); try manifest.write(to: bag.appendingPathComponent("manifest-sha256.txt"))
    try Data((ExchangeDigest.hash(bagit).description + "  bagit.txt\n" + ExchangeDigest.hash(manifest).description + "  manifest-sha256.txt\n").utf8).write(to: bag.appendingPathComponent("tagmanifest-sha256.txt"))
    let staged = try DrawingExchangeCarrier.stageDirectory(bag, stagingParent: root)
    let package = try ExchangeAdmission.validate(staged); success = true
    return .init(package: package, temporaryRoot: root)
  }
}

extension FlowPortfolioStore {
  func canonicalValue<T: Decodable>(_ type: T.Type, reference: FlowPortfolioFeedbackReference,
    id: UUID) async throws -> T {
    let package = try await storage.library.feedback(reference.publication)
    return try autoreleasepool { try FlowFeedbackReader.value(type, reference: reference, id: id, package: package) }
  }
  package func feedbackReference(for judgmentID: UUID) throws -> FlowPortfolioFeedbackReference {
    guard let ref = state.rankings.first(where: { $0.id == judgmentID })?.feedback
      ?? state.choices.first(where: { $0.id == judgmentID })?.feedback
      ?? state.pruneRevisions.first(where: { $0.id == judgmentID })?.feedback else {
      throw FlowPortfolioError.unavailable("Canonical feedback is unavailable.")
    }; return ref
  }
  package func exportFeedback(judgmentID: UUID, to destination: URL) async throws {
    try await storage.library.exportFeedback(feedbackReference(for: judgmentID).publication, to: destination)
  }
  func feedbackRows<T: Codable>(_ type: T.Type, name: String, budget: FlowFeatureReadBudget = .init()) async throws -> [T] {
    try budget.beginNavigationCategory()
    let key = kind(name), records = try await storage.library.records(kind: key)
    var values: [(Int, T)] = []
    let ordered = try records.map { row -> (DrawingLibraryRecord, [String: Any], Int) in
      let json = try ExchangeJSON.validate(row.payload)
      guard let ordinal = json["ordinal"] as? Int, ordinal >= 0 else { throw FlowPortfolioError.invalid("Feedback navigation order.") }
      return (row, json, ordinal)
    }.sorted { $0.2 < $1.2 }
    // One bounded read invocation reuses exact immutable contexts. Chronological
    // rows from a feedback batch are adjacent; eight contexts cap open roots.
    var publications: [DrawingLibraryFeedbackRef: ValidatedExchangePackage] = [:]
    var publicationOrder: [DrawingLibraryFeedbackRef] = []
    for (row, json, _) in ordered {
      if type == FlowPortfolioPruneRevision.self, let raw = json["value"] as? [String: Any], raw["feedback"] == nil {
        let attributed = try JSONDecoder().decode(FlowLibraryEntity<FlowPortfolioPruneRevision>.self, from: row.payload)
        guard attributed.profile == key, attributed.ordinal >= 0, attributed.value.id == row.id,
          attributed.value.action == .modelProposal || attributed.value.action == .inheritedSelection,
          let typed = attributed.value as? T else { throw FlowPortfolioError.invalid("Human pruning has no canonical assessment.") }
        values.append((attributed.ordinal, typed)); committedRecords.insert(row.key); continue
      }
      let locator = try JSONDecoder().decode(FlowLibraryEntity<FlowFeedbackNavigation>.self, from: row.payload)
      guard locator.profile == key, locator.ordinal >= 0, locator.value.id == row.id else { throw FlowPortfolioError.invalid("Feedback navigation identity.") }
      let reference = locator.value.feedback
      let package: ValidatedExchangePackage
      if let cached = publications[reference.publication] { package = cached }
      else {
        package = try await storage.library.feedback(reference.publication)
        if publicationOrder.count == 8 { publications.removeValue(forKey: publicationOrder.removeFirst()) }
        publications[reference.publication] = package; publicationOrder.append(reference.publication)
      }
      let value = try autoreleasepool { try FlowFeedbackReader.value(type, reference: reference, id: locator.value.id, package: package, budget: budget) }
      if var edit = value as? FlowPortfolioPruneRevision {
        edit.drawing = locator.value.drawing; edit.feedback = locator.value.feedback
        guard let typed = edit as? T else { throw FlowPortfolioError.invalid("Pruning navigation type.") }; values.append((locator.ordinal, typed))
      } else { values.append((locator.ordinal, value)) }
      committedRecords.insert(row.key)
    }
    guard Set(values.map { $0.0 }).count == values.count else { throw FlowPortfolioError.invalid("Feedback navigation order.") }
    return values.sorted { $0.0 < $1.0 }.map { $0.1 }
  }
}

/// Invocation-local limits, shared by all historical judgments in one task read.
/// This is not a durable cache or an interpretation registry.
package struct FlowFeatureReadStatistics: Codable, Equatable, Sendable {
  package var decodedCapsules = 0
  package var decodedStrokeMatrices = 0
  package var reusedEncodedStrokeMatrices = 0
  package var metadataStrokeBytesSkipped: UInt64 = 0
  package var admittedBytes: UInt64 = 0
  package var admittedElements = 0
}
final class FlowFeatureReadBudget {
  private let maximumBytes: UInt64
  private let maximumElements: Int
  private var assets: [ExchangeDigest: ExchangeAsset] = [:]
  private var seenDescriptors: [ExchangeDigest: ExchangeAsset] = [:]
  private var usedBytes: UInt64 = 0
  private var countedFeatures = Set<ExchangeDigest>()
  private var sharedStrokeBases = Set<ExchangeDigest>()
  private var usedElements = 0
  private var navigationCategories = 0
  fileprivate var features: [ExchangeDigest: FlowPortfolioFeatureCapsule] = [:]
  fileprivate var rootStrokeJSONDigests: [ExchangeDigest: ExchangeDigest] = [:]
  var statistics = FlowFeatureReadStatistics()
  fileprivate let reusesEncodedStrokeBasis: Bool
  fileprivate var verifiedBytes: [ExchangeDigest: Data] = [:]
  private let maximumCachedBytes: Int
  private var cachedByteCount = 0
  private var cachedByteOrder: [ExchangeDigest] = []
  private final class Context {
    weak var files: VerifiedExchangeFiles?
    var assets = Set<ExchangeDigest>()
    init(_ files: VerifiedExchangeFiles) { self.files = files }
  }
  private var contexts: [ObjectIdentifier: Context] = [:]
  /// Only one resolver's enclosing task read may defer its final whole-read-set
  /// check. Default standalone answer/ranking reads settle their own read set.
  weak var batchedFiles: VerifiedExchangeFiles?
  init(maximumBytes: UInt64 = 512 * 1024 * 1024, maximumElements: Int = 8_000_000,
    maximumCachedBytes: Int = 64 * 1024 * 1024, reusesEncodedStrokeBasis: Bool = true) {
    self.maximumBytes = maximumBytes; self.maximumElements = maximumElements
    self.maximumCachedBytes = max(0, maximumCachedBytes)
    self.reusesEncodedStrokeBasis = reusesEncodedStrokeBasis
  }
  /// Loading choices, pruning and rankings keeps their original independent
  /// admission ceilings. Only verified immutable parse results cross categories.
  /// Thus one graph load retains at most three 8m-element category bases, while
  /// raw-byte reuse remains capped separately at 64MiB.
  func beginNavigationCategory() throws {
    guard navigationCategories < 3 else { throw FlowPortfolioError.unavailable("Too many feedback navigation categories in one load.") }
    navigationCategories += 1
    assets.removeAll(keepingCapacity: true); usedBytes = 0
    countedFeatures.removeAll(keepingCapacity: true); sharedStrokeBases.removeAll(keepingCapacity: true); usedElements = 0
  }
  func cacheVerified(_ bytes: Data, digest: ExchangeDigest) {
    guard verifiedBytes[digest] == nil, bytes.count <= maximumCachedBytes else { return }
    while cachedByteCount + bytes.count > maximumCachedBytes, !cachedByteOrder.isEmpty {
      let old = cachedByteOrder.removeFirst()
      if let removed = verifiedBytes.removeValue(forKey: old) { cachedByteCount -= removed.count }
    }
    verifiedBytes[digest] = bytes; cachedByteCount += bytes.count; cachedByteOrder.append(digest)
  }
  func verified(_ asset: ExchangeAsset, in files: VerifiedExchangeFiles) -> Bool {
    let context = contexts[ObjectIdentifier(files)]
    return context?.files === files && context?.assets.contains(asset.object) == true
  }
  func remember(_ asset: ExchangeAsset, in files: VerifiedExchangeFiles) {
    let key = ObjectIdentifier(files)
    let context: Context
    if let old = contexts[key], old.files === files { context = old }
    else { context = Context(files); contexts[key] = context }
    context.assets.insert(asset.object)
  }
  func admit(_ asset: ExchangeAsset) throws {
    if let old = seenDescriptors[asset.object], old != asset {
      throw FlowPortfolioError.invalid("Conflicting exact JSON asset descriptor across feedback categories.")
    }
    if let old = assets[asset.object] {
      guard old == asset else { throw FlowPortfolioError.invalid("Conflicting exact JSON asset descriptor.") }; return
    }
    guard asset.byteLength <= maximumBytes - usedBytes else { throw FlowPortfolioError.unavailable("Frozen feature materialization budget exceeded.") }
    usedBytes += asset.byteLength; assets[asset.object] = asset; seenDescriptors[asset.object] = asset
    statistics.admittedBytes += asset.byteLength
  }
  func admitFeature(_ asset: ExchangeAsset, value: FlowPortfolioFeatureCapsule) throws {
    guard !countedFeatures.contains(asset.object) else { return }
    let basis = value.rootFeatures?.object ?? asset.object
    let count = value.drawing.count + (sharedStrokeBases.contains(basis) ? 0 : value.strokes.reduce(0) { $0 + $1.count })
    guard count <= maximumElements - usedElements else { throw FlowPortfolioError.unavailable("Frozen historical feature budget exceeded.") }
    usedElements += count; countedFeatures.insert(asset.object); sharedStrokeBases.insert(basis)
    statistics.admittedElements += count
  }
}

enum FlowFeedbackReader {
  static func rankingFacts(_ capsule: ExchangeRankingCapsule, id: UUID, package: ValidatedExchangePackage, budget: FlowFeatureReadBudget = .init()) throws
    -> (navigation: FlowRankingNavigation, presentation: FlowPortfolioPresentation, groups: [[UUID]], features: [ExchangeAsset]) {
    guard capsule.unsupportedReasons.isEmpty,
      Set(capsule.requiredFeatures).isSubset(of: [ExchangeRankingCapsule.partialRankingFeature, ExchangeRankingCapsule.neitherFeature]) else {
      throw FlowPortfolioError.unavailable("Unsupported ranking capsule semantics.")
    }
    let json = try ExchangeJSON.validate(capsule.originalJSON)
    let nav = try decodeJSON(json["flowNavigation"], FlowRankingNavigation.self)
    let shown = try decodeJSON(json["flowPresentation"], FlowPortfolioPresentation.self)
    guard nav.id == id, shown.id == nav.presentationID, shown.items.map(\.id) == capsule.presentationIDs,
      let q = json["question"] as? [String: Any], q["id"] as? String == "adaptiveplotter.flow-ranking", q["version"] as? String == "1",
      q["text"] as? String == "Which offered directions do you prefer?",
      let r = json["reviewer"] as? [String: Any], r["kind"] as? String == "human", r["id"] as? String == "local-operator",
      let response = json["response"] as? [String: Any] else { throw FlowPortfolioError.invalid("Ranking task identity/question.") }
    guard let presentations = json["presentations"] as? [[String: Any]], presentations.count == shown.items.count else { throw FlowPortfolioError.invalid("Ranking feature presentation count.") }
    for (item, presented) in zip(shown.items, presentations) {
      let feature = try Self.feature(decodeJSON(presented["features"], ExchangeAsset.self), package: package, budget: budget)
      guard feature.id == item.id, feature.candidateID == item.candidateID, feature.sourceID == item.sourceID,
        feature.removedIndices == item.removedIndices,
        let producer = presented["producer"] as? [String: Any], producer["id"] as? String == feature.producer.id,
        producer["version"] as? String == feature.producer.version, producer["record"] as? String == feature.producer.record.object.description,
        let extractor = presented["extractor"] as? [String: Any], extractor["id"] as? String == feature.extractor.id,
        extractor["version"] as? String == feature.extractor.version, extractor["record"] as? String == feature.extractor.record.object.description else {
        throw FlowPortfolioError.invalid("Ranking feature/provenance basis mismatch.")
      }
    }
    let groups = try (response["groups"].map { try decodeJSON($0, [[UUID]].self) }) ?? []
    if budget.batchedFiles !== package.files { try package.files.revalidateSelected() }
    return (nav, shown, groups, try presentations.map { try decodeJSON($0["features"], ExchangeAsset.self) })
  }
  static func value<T: Decodable>(_ type: T.Type, reference: FlowPortfolioFeedbackReference, id: UUID,
    package: ValidatedExchangePackage, budget: FlowFeatureReadBudget = .init()) throws -> T {
    guard let index = package.index.known, index.kind == "feedback", index.requiredFeatures.isEmpty,
      index.roots.isEmpty, index.jobs.isEmpty, index.attempts.isEmpty,
      let assessment = package.assessments[reference.assessment], assessment.requiredFeatures.isEmpty,
      assessment.unsupportedReasons.isEmpty, assessment.identity == reference.assessment.identity else {
      throw FlowPortfolioError.unavailable("Unsupported exact feedback context.")
    }
    let record = try ExchangeJSON.validate(assessment.originalJSON)
    guard let question = record["question"] as? [String: Any], question["version"] as? String == "1",
      let reviewer = record["reviewer"] as? [String: Any], let answer = record["answer"] as? [String: Any],
      let answerType = answer["type"] as? String else { throw FlowPortfolioError.invalid("Feedback envelope fields.") }
    func decode<V: Decodable>(_ value: Any?, _ type: V.Type) throws -> V {
      guard let value else { throw FlowPortfolioError.invalid("Feedback field unavailable.") }
      return try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]))
    }
    func finish(_ value: T) throws -> T {
      if budget.batchedFiles !== package.files { try package.files.revalidateSelected() }
      return value
    }
    if type == FlowPortfolioRanking.self {
      guard answerType == "adaptiveplotter.recorded-ranking-revision", question["id"] as? String == answerType,
        question["text"] as? String == "Recorded ranking revision", reviewer["kind"] as? String == "algorithm",
        reviewer["id"] as? String == "adaptiveplotter.flow-feedback-adapter", reviewer["version"] as? String == "1",
        let exact = reference.ranking, try decode(answer["value"], RankingCapsuleRef.self) == exact,
        assessment.targets.count == 1, case .rankingCapsule(let target) = assessment.targets[0], target == exact,
        let capsule = package.rankingCapsules[exact], capsule.unsupportedReasons.isEmpty,
        Set(capsule.requiredFeatures).isSubset(of: [ExchangeRankingCapsule.partialRankingFeature, ExchangeRankingCapsule.neitherFeature]) else {
        throw FlowPortfolioError.invalid("Ranking administrative marker/target disagreement.")
      }
      let facts = try rankingFacts(capsule, id: id, package: package, budget: budget)
      let nav = facts.navigation, shown = facts.presentation, groups = facts.groups
      let rank = FlowPortfolioRanking(id: nav.id, createdAt: nav.createdAt, presentationID: nav.presentationID,
        orderedGroups: groups, skipped: capsule.responseKind == "skip", neither: capsule.responseKind == "neither", supersedesID: nav.supersedesID, feedback: reference)
      // Follow only this explicitly selected chain. Every predecessor must name
      // the same logical presentation and exact prior marker, without cycles.
      var current = assessment, expected = nav.supersedesID, seen = Set<AssessmentRef>([reference.assessment])
      while let priorID = expected {
        guard current.supersedes.count == 1, let priorRef = current.supersedes.first, seen.insert(priorRef).inserted,
          let prior = package.assessments[priorRef], prior.answerType == answerType, prior.requiredFeatures.isEmpty,
          prior.targets.count == 1, case .rankingCapsule(let priorCapsuleRef) = prior.targets[0],
          let priorCapsule = package.rankingCapsules[priorCapsuleRef] else { throw FlowPortfolioError.invalid("Ranking revision chain.") }
        let priorJSON = try ExchangeJSON.validate(prior.originalJSON)
        guard let a = priorJSON["answer"] as? [String: Any], try decode(a["value"], RankingCapsuleRef.self) == priorCapsuleRef,
          let reviewer = priorJSON["reviewer"] as? [String: Any], reviewer["kind"] as? String == "algorithm", reviewer["id"] as? String == "adaptiveplotter.flow-feedback-adapter", reviewer["version"] as? String == "1",
          let question = priorJSON["question"] as? [String: Any], question["id"] as? String == answerType,
          question["version"] as? String == "1", question["text"] as? String == "Recorded ranking revision" else { throw FlowPortfolioError.invalid("Prior ranking marker.") }
        let predecessor = try rankingFacts(priorCapsule, id: priorID, package: package, budget: budget)
        guard predecessor.navigation.presentationID == nav.presentationID,
          predecessor.presentation == shown, predecessor.features == facts.features else { throw FlowPortfolioError.invalid("Ranking supersession presentation/feature basis changed.") }
        current = prior; expected = predecessor.navigation.supersedesID
      }
      guard current.supersedes.isEmpty, let result = rank as? T else { throw FlowPortfolioError.invalid("Ranking revision origin.") }; return try finish(result)
    }
    let expected = type == FlowPortfolioChoice.self ? "adaptiveplotter.flow-choice" : "adaptiveplotter.flow-pruning"
    guard answerType == expected, question["id"] as? String == expected,
      question["text"] as? String == (type == FlowPortfolioChoice.self ? "Which offered direction did you choose?" : "Which original strokes should remain?"),
      reviewer["kind"] as? String == "human", reviewer["id"] as? String == "local-operator", assessment.supersedes.isEmpty,
      assessment.targets.count == 1, case .asset = assessment.targets[0] else { throw FlowPortfolioError.invalid("Feedback task answer/question.") }
    guard case .asset(let target) = assessment.targets[0] else { throw FlowPortfolioError.invalid("Feedback target.") }
    guard let semantic = answer["value"] as? [String: Any] else { throw FlowPortfolioError.invalid("Feedback answer shape.") }
    if type == FlowPortfolioChoice.self {
      guard Set(semantic.keys) == Set(["id", "createdAt", "roundID", "candidateID", "offeredCandidateIDs", "selectedItemID", "offeredItems", "purpose"]) else { throw FlowPortfolioError.unavailable("Unsupported choice answer fields.") }
      var choice = try decode(answer["value"], FlowCanonicalChoiceAnswer.self).projection
      guard choice.id == id, choice.offeredItems.count == assessment.supportingAssets.count,
        choice.offeredItems.map(\.candidateID) == choice.offeredCandidateIDs,
        Set(choice.offeredItems.map(\.id)).count == choice.offeredItems.count,
        let selected = choice.offeredItems.firstIndex(where: { $0.id == choice.selectedItemID }),
        assessment.supportingAssets[selected] == target else { throw FlowPortfolioError.invalid("Choice exact ordered offered basis.") }
      for (item, asset) in zip(choice.offeredItems, assessment.supportingAssets) {
        let feature = try Self.feature(asset, package: package, budget: budget)
        guard feature.id == item.id, feature.candidateID == item.candidateID, feature.sourceID == item.sourceID,
          feature.removedIndices == item.removedIndices else { throw FlowPortfolioError.invalid("Choice feature basis.") }
      }
      choice.feedback = reference
      guard let typed = choice as? T else { throw FlowPortfolioError.invalid("Choice type.") }; return try finish(typed)
    } else if type == FlowPortfolioPruneRevision.self {
      guard Set(semantic.keys).isSubset(of: Set(["id", "createdAt", "candidateID", "parentRevisionID", "action", "affectedStrokeIDs", "removedStrokeIDs", "operationID", "undoOperationIDs", "redoOperationIDs"])) else { throw FlowPortfolioError.unavailable("Unsupported pruning answer fields.") }
      let rootBasis = try Self.feature(target, package: package, budget: budget)
      var prune = try decode(answer["value"], FlowCanonicalPruneAnswer.self).projection(basis: rootBasis.strokeIDs)
      guard prune.id == id, assessment.supportingAssets.count == 2,
        assessment.supportingAssets[0] == target else { throw FlowPortfolioError.invalid("Prune identity/feature target.") }
      let root = try Self.feature(target, package: package, budget: budget), edit = try Self.feature(assessment.supportingAssets[1], package: package, budget: budget)
      let region = try decode(record["regionOrStrokes"], ExchangeAsset.self)
      let regionBytes = try exactJSON(region, package: package, budget: budget, maximumBytes: 1024 * 1024)
      guard root.id == prune.candidateID, root.candidateID == prune.candidateID, root.removedIndices.isEmpty,
        edit.id == prune.id, edit.candidateID == prune.candidateID, edit.programDigest == root.programDigest,
        edit.strokeIDs == root.strokeIDs, edit.strokes == root.strokes, edit.removedIndices == prune.removedIndices,
        try JSONDecoder().decode([StrokeID].self, from: regionBytes) == root.strokeIDs,
        prune.affectedIndices.allSatisfy({ root.strokeIDs.indices.contains($0) }),
        prune.action != .modelProposal, prune.action != .inheritedSelection else { throw FlowPortfolioError.invalid("Prune stable-stroke feature basis.") }
      prune.feedback = reference
      guard let typed = prune as? T else { throw FlowPortfolioError.invalid("Prune type.") }; return try finish(typed)
    } else { throw FlowPortfolioError.invalid("Unknown feedback task type.") }
  }
}

extension FlowFeedbackReader {
  private static func requireJSONContext(_ asset: ExchangeAsset, package: ValidatedExchangePackage,
    budget: FlowFeatureReadBudget, maximumBytes: Int) throws {
    guard maximumBytes >= 0, asset.byteLength <= UInt64(maximumBytes),
      let index = package.index.known, index.kind == "feedback", index.requiredFeatures.isEmpty,
      asset.mediaType == "application/json", asset.encoding == "utf8-json",
      let indexed = index.assets.first(where: { $0.asset.object == asset.object }), indexed.asset == asset else {
      throw FlowPortfolioError.unavailable("Unsupported or unindexed exact JSON asset descriptor.")
    }
    try Task.checkCancellation(); try budget.admit(asset)
  }
  static func exactJSON(_ asset: ExchangeAsset, package: ValidatedExchangePackage,
    budget: FlowFeatureReadBudget, maximumBytes: Int = 128 * 1024 * 1024) throws -> Data {
    try requireJSONContext(asset, package: package, budget: budget, maximumBytes: maximumBytes)
    if let bytes = budget.verifiedBytes[asset.object], budget.verified(asset, in: package.files) {
      // ValidatedExchangePackage established these fingerprints through carrier
      // or catalog admission. Recheck this context before reusing exact bytes.
      try package.files.verify(asset.object)
      return bytes
    }
    let bytes = try package.files.record(asset.object, maximumBytes: maximumBytes)
    try asset.validate(bytes, maximumBytes: maximumBytes)
    budget.remember(asset, in: package.files)
    budget.cacheVerified(bytes, digest: asset.object)
    return bytes
  }
  static func feature(_ asset: ExchangeAsset, package: ValidatedExchangePackage, budget: FlowFeatureReadBudget = .init(), allowRootReference: Bool = true) throws -> FlowPortfolioFeatureCapsule {
    let cacheKey = asset.object
    let cached = budget.features[cacheKey]
    var value: FlowPortfolioFeatureCapsule
    var decodedBytes: Data?
    var verifiedBase: FlowPortfolioFeatureCapsule?
    var members: [String: Range<Int>]?
    if let cached {
      try requireJSONContext(asset, package: package, budget: budget, maximumBytes: 128 * 1024 * 1024)
      if budget.verified(asset, in: package.files) { try package.files.verify(asset.object) }
      else { _ = try exactJSON(asset, package: package, budget: budget) }
      value = cached
    } else {
      let bytes = try exactJSON(asset, package: package, budget: budget)
      decodedBytes = bytes
      members = budget.reusesEncodedStrokeBasis ? FlowFeatureJSON.members(bytes) : nil
      if let rootRange = members?["rootFeatures"], let strokeRange = members?["strokes"],
        bytes[rootRange.lowerBound] != 110 {
        let root = try JSONDecoder().decode(ExchangeAsset.self, from: bytes.subdata(in: rootRange))
        guard allowRootReference, root.object != asset.object else { throw FlowPortfolioError.invalid("Cyclic root feature basis.") }
        let base = try feature(root, package: package, budget: budget, allowRootReference: false)
        verifiedBase = base
        if let rootDigest = budget.rootStrokeJSONDigests[root.object],
          ExchangeDigest.hash(bytes.subdata(in: strokeRange)) == rootDigest {
          // The exact range is already syntax/type checked by the root's
          // full decode. Validate every remaining byte without parsing the
          // same large numeric matrix again for each retained mask.
          let metadata = FlowFeatureJSON.replacingVerifiedStrokeRange(strokeRange, in: bytes)
          value = try JSONDecoder().decode(FlowFeatureMetadata.self, from: metadata).capsule(strokes: base.strokes)
          budget.statistics.reusedEncodedStrokeMatrices += 1
          budget.statistics.metadataStrokeBytesSkipped += UInt64(strokeRange.count)
        } else {
          value = try JSONDecoder().decode(FlowPortfolioFeatureCapsule.self, from: bytes)
          budget.statistics.decodedStrokeMatrices += 1
        }
      } else {
        value = try JSONDecoder().decode(FlowPortfolioFeatureCapsule.self, from: bytes)
        budget.statistics.decodedStrokeMatrices += 1
      }
      budget.statistics.decodedCapsules += 1
    }
    let config = try exactJSON(value.extractor.record, package: package, budget: budget, maximumBytes: 1024 * 1024)
    let receipt = try exactJSON(value.producer.record, package: package, budget: budget, maximumBytes: 1024 * 1024)
    if let root = value.rootFeatures {
      guard allowRootReference, root.object != asset.object else { throw FlowPortfolioError.invalid("Cyclic root feature basis.") }
      let base = try verifiedBase ?? feature(root, package: package, budget: budget, allowRootReference: false)
      guard base.rootFeatures == nil, base.id == value.candidateID, base.candidateID == value.candidateID,
        base.sourceID == value.sourceID, base.programDigest == value.programDigest, base.strokeIDs == value.strokeIDs,
        base.recipe == value.recipe,
        base.producer.id == value.producer.id, base.producer.version == value.producer.version, base.producer.record == value.producer.record,
        base.extractor.id == value.extractor.id, base.extractor.version == value.extractor.version, base.extractor.record == value.extractor.record,
        base.strokes == value.strokes else { throw FlowPortfolioError.invalid("Edited features differ from their exact stable stroke basis.") }
      // Native verification can be established after temporary capture, during
      // retention/admission. Keep each observed flag; the exact basis receipts
      // and numerical vectors above must still agree.
      // Value-semantic arrays share the verified root's storage. Distinct mask
      // drawing features/answers remain independently cached and validated.
      value.strokes = base.strokes
    }
    if cached == nil {
      guard value.profile == "adaptiveplotter.flow-features/3", value.requiredFeatures.isEmpty,
        (value.rootFeatures == nil) == (value.id == value.candidateID),
        value.id != value.candidateID || value.removedIndices.isEmpty, value.strokeIDs.count == value.strokes.count,
        Set(value.strokeIDs).count == value.strokeIDs.count, value.strokes.count <= 10_000,
        value.drawing.count == FlowArtistFeatures.drawingCount,
        value.strokes.allSatisfy({ $0.count == FlowArtistFeatures.strokeCount }),
        value.drawing.allSatisfy({ $0.isFinite && abs($0) <= 100 }),
        value.strokes.allSatisfy({ $0.allSatisfy { $0.isFinite && abs($0) <= 100 } }),
        value.recipe.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
        Set(value.removedIndices).count == value.removedIndices.count,
        value.removedIndices.allSatisfy({ value.strokeIDs.indices.contains($0) }),
        value.extractor.id == "adaptiveplotter.flow-features", value.extractor.version == FlowArtistFeatures.revision,
        !value.producer.id.isEmpty, !value.producer.version.isEmpty else { throw FlowPortfolioError.invalid("Malformed or unsupported feature basis.") }
      guard try JSONDecoder().decode(FlowFeatureExtractorConfiguration.self, from: config) == .current else { throw FlowPortfolioError.unavailable("Unsupported extractor configuration.") }
      _ = try ExchangeJSON.validate(receipt)
      if value.rootFeatures == nil, let bytes = decodedBytes,
        let strokeRange = members?["strokes"] {
        budget.rootStrokeJSONDigests[asset.object] = .hash(bytes.subdata(in: strokeRange))
      }
    }
    // Charge the current category even when another category verified the
    // cached capsule. Reuse never expands any category's admission authority.
    try budget.admitFeature(asset, value: value)
    budget.features[cacheKey] = value
    return value
  }
  static func featureAssets(_ package: ValidatedExchangePackage, budget: FlowFeatureReadBudget = .init()) throws -> [ExchangeAsset] {
    var assets: [ExchangeAsset] = []
    for capsule in package.rankingCapsules.values {
      try Task.checkCancellation()
      let json = try ExchangeJSON.validate(capsule.originalJSON)
      guard let shown = json["presentations"] as? [[String: Any]] else { throw FlowPortfolioError.invalid("Ranking presentations.") }
      for value in shown { assets.append(try decodeJSON(value["features"], ExchangeAsset.self)) }
    }
    for assessment in package.assessments.values where ["adaptiveplotter.flow-choice", "adaptiveplotter.flow-pruning"].contains(assessment.answerType) {
      for asset in assessment.supportingAssets {
        _ = try feature(asset, package: package, budget: budget)
        assets.append(asset)
      }
    }
    for asset in assets {
      try Task.checkCancellation()
      let value = try feature(asset, package: package, budget: budget)
      if let root = value.rootFeatures { assets.append(root) }
    }
    if budget.batchedFiles !== package.files { try package.files.revalidateSelected() }
    return Array(Set(assets)).sorted { $0.object.description < $1.object.description }
  }
  static func decodeJSON<T: Decodable>(_ value: Any?, _ type: T.Type) throws -> T {
    guard let value else { throw FlowPortfolioError.invalid("Canonical field unavailable.") }
    return try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]))
  }
}

/// A mask's numerical stroke basis is already present in its verified root. The
/// metadata decoder parses all remaining JSON after the exact matrix bytes match
/// the fully decoded and validated root. The original carrier remains the digest,
/// integrity and admission authority; the compact view is never retained.
private struct FlowFeatureMetadata: Decodable {
  let profile: String
  let id: UUID
  let candidateID: UUID
  let sourceID: UUID
  let programDigest: ExchangeDigest
  let rootFeatures: ExchangeAsset?
  let strokeIDs: [StrokeID]
  let recipe: FlowArtistRecipe
  let producer: FlowPortfolioFeatureProvenance
  let extractor: FlowPortfolioFeatureProvenance
  let drawing: [Double]
  let removedIndices: [Int]
  let requiredFeatures: [String]
  func capsule(strokes: [[Double]]) -> FlowPortfolioFeatureCapsule {
    .init(profile: profile, id: id, candidateID: candidateID, sourceID: sourceID,
      programDigest: programDigest, rootFeatures: rootFeatures, strokeIDs: strokeIDs, recipe: recipe,
      producer: producer, extractor: extractor, drawing: drawing, strokes: strokes,
      removedIndices: removedIndices, requiredFeatures: requiredFeatures)
  }
}

/// Finds byte ranges only; JSONDecoder remains the syntax/type authority. Any
/// unusual top-level key spelling, duplicate key, malformed container or trailing
/// content declines this optimization and takes the original full decoder path.
private enum FlowFeatureJSON {
  /// Call only after this complete value range matches the validated root's
  /// matrix digest. Replacing its value preserves every surrounding delimiter,
  /// key and metadata byte for the ordinary JSONDecoder syntax/type checks.
  static func replacingVerifiedStrokeRange(_ range: Range<Int>, in bytes: Data) -> Data {
    var result = Data()
    result.reserveCapacity(bytes.count - range.count + 2)
    result.append(bytes[..<range.lowerBound])
    result.append(contentsOf: [0x5b, 0x5d])
    result.append(bytes[range.upperBound...])
    return result
  }

  static func members(_ data: Data) -> [String: Range<Int>]? {
    data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> [String: Range<Int>]? in
      var offset = 0
      func whitespace(_ value: UInt8) -> Bool { value == 32 || value == 9 || value == 10 || value == 13 }
      func space() { while offset < bytes.count && whitespace(bytes[offset]) { offset += 1 } }
      space(); guard offset < bytes.count, bytes[offset] == 123 else { return nil }; offset += 1
      var result: [String: Range<Int>] = [:]
      while true {
        space(); guard offset < bytes.count else { return nil }
        if bytes[offset] == 125 {
          offset += 1; space(); return offset == bytes.count ? result : nil
        }
        guard bytes[offset] == 34 else { return nil }; offset += 1
        let keyStart = offset
        while offset < bytes.count && bytes[offset] != 34 {
          // Escaped/non-ASCII keys remain supported through the full decoder.
          guard bytes[offset] >= 32, bytes[offset] < 128, bytes[offset] != 92 else { return nil }
          offset += 1
        }
        guard offset < bytes.count else { return nil }
        let key = String(decoding: bytes[keyStart..<offset], as: UTF8.self)
        guard result[key] == nil else { return nil }
        offset += 1; space(); guard offset < bytes.count, bytes[offset] == 58 else { return nil }
        offset += 1; space(); let start = offset
        var stack: [UInt8] = [], string = false, escaped = false
        while offset < bytes.count {
          let byte = bytes[offset]
          if string {
            if escaped { escaped = false }
            else if byte == 92 { escaped = true }
            else if byte == 34 { string = false }
          } else if byte == 34 { string = true }
          else if byte == 91 || byte == 123 {
            guard stack.count < 64 else { return nil }; stack.append(byte)
          } else if byte == 93 || byte == 125 {
            if stack.isEmpty { break }
            guard stack.removeLast() == (byte == 93 ? 91 : 123) else { return nil }
          } else if byte == 44 && stack.isEmpty { break }
          offset += 1
        }
        guard !string, stack.isEmpty else { return nil }
        var end = offset
        while end > start && whitespace(bytes[end - 1]) { end -= 1 }
        guard end > start else { return nil }; result[key] = start..<end
        space(); guard offset < bytes.count else { return nil }
        if bytes[offset] == 44 {
          offset += 1; space()
          guard offset < bytes.count, bytes[offset] != 125 else { return nil }
        } else if bytes[offset] != 125 { return nil }
      }
    }
  }
}

private struct FlowFeedbackProjection: Encodable {
  let choices: [FlowPortfolioChoice]
  let pruneRevisions: [FlowPortfolioPruneRevision]
  let rankings: [FlowPortfolioRanking]
}
extension FlowPortfolioStore {
  /// Diagnostic digest of typed canonical answers plus their exact navigation.
  /// A frozen original snapshot limits this to preexisting judgments, so adding
  /// new generated candidates/model masks cannot hide a changed historical row.
  package func feedbackProjectionDigest(matching original: FlowPortfolioSnapshot? = nil) throws -> String {
    let choiceIDs = original.map { Set($0.choices.map(\.id)) }
    let pruneIDs = original.map { Set($0.pruneRevisions.map(\.id)) }
    let rankingIDs = original.map { Set($0.rankings.map(\.id)) }
    let projection = FlowFeedbackProjection(
      choices: state.choices.filter { choiceIDs?.contains($0.id) ?? true },
      pruneRevisions: state.pruneRevisions.filter { pruneIDs?.contains($0.id) ?? true },
      rankings: state.rankings.filter { rankingIDs?.contains($0.id) ?? true })
    if let original {
      guard projection.choices.count == original.choices.count,
        projection.pruneRevisions.count == original.pruneRevisions.count,
        projection.rankings.count == original.rankings.count else {
        throw FlowPortfolioError.invalid("A preexisting feedback row is missing from the projection.")
      }
    }
    return DrawingArtifactCoding.sha256(try DrawingArtifactCoding.encoder().encode(projection))
  }
}
