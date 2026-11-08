import Foundation
import DrawingLibrary
import PortraitCore
import Testing

private enum NeutralFeedbackFailure: Error { case boundary }
private extension DrawingLibrary {
  func neutralFeedbackFault(_ boundary: LibraryExchangeCatalogBoundary?) throws {
    guard let boundary else { cachedExchangeCatalog?.injectFault = nil; return }
    let catalog = try commonCatalog()
    catalog.injectFault = { if $0 == boundary { throw NeutralFeedbackFailure.boundary } }
  }
}
private struct NeutralFeedbackFixture {
  let publication: ValidatedExchangePackage
  let ranking: RankingCapsuleRef
  let assessment: AssessmentRef
  static func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("dx09-neutral-" + UUID().uuidString) }
  static func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) }
  static func wire<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(value)) }
  init(root: URL, marker: String = "first") throws {
    var files: [String: Data] = [:], descriptors: [ExchangeAssetDescriptor] = []
    func asset(_ bytes: Data) throws -> ExchangeAsset {
      let asset = try ExchangeAsset(bytes: bytes, mediaType: "application/json", encoding: "utf8-json")
      files["data/objects/sha256/" + asset.object.description] = bytes
      descriptors.append(.init(asset: asset)); return asset
    }
    let features = try asset(Self.json(["profile":"example.neutral-features/1", "values":[0.25,0.75], "marker":marker]))
    let receipt = try asset(Self.json(["profile":"example.neutral-receipt/1", "marker":marker]))
    let ids = [UUID(), UUID()]
    let identity = ExchangeIdentity(issuer: UUID())
    let question: [String: Any] = ["id":"example.neutral-question", "version":"1", "text":"Synthetic ordering only"]
    let producer: [String: Any] = ["id":"example.neutral-producer", "version":"1", "record":receipt.object.description]
    let rankingJSON: [String: Any] = ["profile":"adaptiveplotter.feature-ranking/1", "requiredFeatures":[String](),
      "ref":try Self.wire(identity), "createdAt":try Self.wire(ExchangeTimestamp(wallTime:"2027-01-15T08:00:00Z")),
      "geometry":"omitted", "limitations":"Features only; no geometry re-extraction or arbitrary future image labels.",
      "reviewer":["kind":"human","id":"synthetic-neutral-reviewer"], "question":question,
      "presentations":try ids.map { ["id":$0.uuidString.lowercased(),"features":try Self.wire(features),"producer":producer,"extractor":producer] },
      "response":["kind":"ranking","groups":ids.map { [$0.uuidString.lowercased()] }]]
    let rankingBytes = try Self.json(rankingJSON)
    let ranking = RankingCapsuleRef(issuer: identity.issuer, revision: identity.revision, digest: .hash(rankingBytes))
    files["data/rankings/\(identity.issuer.uuidString.lowercased())/\(identity.revision.uuidString.lowercased()).json"] = rankingBytes
    let assessmentID = ExchangeIdentity(issuer: UUID())
    let assessmentJSON: [String: Any] = ["profile":"adaptiveplotter.assessment/1", "requiredFeatures":[String](),
      "ref":try Self.wire(assessmentID), "targets":[["kind":"ranking-capsule","ref":try Self.wire(ranking)]],
      "reviewer":["kind":"algorithm","id":"example.neutral-administration","version":"1"], "question":question,
      "time":try Self.wire(ExchangeTimestamp(wallTime:"2027-01-15T08:00:00Z")),
      "answer":["type":"example.neutral-administrative-marker/1","value":["marker":marker]],
      "supportingAssets":[String](),"supersedes":[String]()]
    let assessmentBytes = try Self.json(assessmentJSON)
    let assessment = AssessmentRef(issuer: assessmentID.issuer, revision: assessmentID.revision, digest: .hash(assessmentBytes))
    files["data/assessments/\(assessmentID.issuer.uuidString.lowercased())/\(assessmentID.revision.uuidString.lowercased()).json"] = assessmentBytes
    let index: [String: Any] = ["profile":"adaptiveplotter.exchange/1","requiredFeatures":[String](),"kind":"feedback", "roots":[String](),
      "includedAsOf":"2027-01-15T08:00:00Z","assets":try Self.wire(descriptors),"attempts":[String](),
      "assessments":try Self.wire([assessment]),"rankingCapsules":try Self.wire([ranking])]
    files["data/exchange.json"] = try Self.json(index)
    files["bagit.txt"] = Data("BagIt-Version: 1.0\nTag-File-Character-Encoding: UTF-8\n".utf8)
    files["manifest-sha256.txt"] = Data(files.keys.filter { $0.hasPrefix("data/") }.sorted().map { ExchangeDigest.hash(files[$0]!).description + "  " + $0 + "\n" }.joined().utf8)
    files["tagmanifest-sha256.txt"] = Data(["bagit.txt","manifest-sha256.txt"].map { ExchangeDigest.hash(files[$0]!).description + "  " + $0 + "\n" }.joined().utf8)
    let source = root.appendingPathComponent("source"), stage = root.appendingPathComponent("stage")
    for (path, bytes) in files {
      let target = source.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      try bytes.write(to: target)
    }
    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
    self.ranking = ranking; self.assessment = assessment
    publication = try ExchangeAdmission.validate(DrawingExchangeCarrier.stageDirectory(source, stagingParent: stage))
  }
  static func bytes(_ publication: ValidatedExchangePackage) throws -> [String: Data] {
    try Dictionary(uniqueKeysWithValues: publication.files.entries.keys.map { ($0, try publication.files.record(at: $0)) })
  }
}

@Suite("DX09 neutral atomic canonical feedback", .serialized)
struct DrawingLibraryFeedbackTests {
  @Test("Public feedback commit, selected read and offline export preserve exact closure without retaining geometry")
  func publicPortableClosure() async throws {
    let root = NeutralFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try NeutralFeedbackFixture(root: root.appendingPathComponent("fixture"))
    let original = try NeutralFeedbackFixture.bytes(fixture.publication)
    let directory = root.appendingPathComponent("library")
    let library = DrawingLibrary(directoryURL: directory)
    let ref = try await library.commitFeedback(fixture.publication)
    #expect(try await library.drawings().entries.isEmpty)
    let read = try await library.feedback(ref)
    #expect(read.rankingCapsules[fixture.ranking] != nil && read.assessments[fixture.assessment] != nil)
    #expect(!read.capabilities.supported.contains(.train) && !read.capabilities.supported.contains(.interpretResults))
    #expect(try NeutralFeedbackFixture.bytes(read) == original)
    let exported = root.appendingPathComponent("feedback.zip")
    try await library.exportFeedback(ref, to: exported)
    await library.closeLibrary()
    try FileManager.default.removeItem(at: directory)
    try FileManager.default.removeItem(at: root.appendingPathComponent("fixture"))
    let offline = DrawingLibrary(directoryURL: root.appendingPathComponent("offline"))
    let imported = try await offline.mountFeedback(from: exported)
    #expect(imported == ref)
    #expect(try NeutralFeedbackFixture.bytes(await offline.feedback(imported)) == original)
    #expect(try await offline.drawings().entries.isEmpty)
    await offline.closeLibrary()
  }

  @Test("Feedback and navigation commit together, retry once and bind intent to publication plus records", arguments: [LibraryExchangeCatalogBoundary.beforeSQLPublication, .afterSQLCommit])
  func atomicNavigation(boundary: LibraryExchangeCatalogBoundary) async throws {
    let root = NeutralFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try NeutralFeedbackFixture(root: root.appendingPathComponent("first"))
    let changed = try NeutralFeedbackFixture(root: root.appendingPathComponent("changed"), marker: "different")
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("library"))
    let row = DrawingLibraryRecord(kind: "example.feedback-navigation/1", id: UUID(), payload: Data("{\"selected\":1}".utf8))
    let intent = DrawingLibraryCommitIntent()
    try await library.open(); try await library.neutralFeedbackFault(boundary)
    await #expect(throws: NeutralFeedbackFailure.self) { try await library.commitFeedback(fixture.publication, records: [row], intent: intent) }
    #expect((try await library.record(row.key) != nil) == (boundary == .afterSQLCommit))
    try await library.neutralFeedbackFault(nil); try await library.recover()
    let ref = try await library.commitFeedback(fixture.publication, records: [row], intent: intent)
    #expect(try await library.commitFeedback(fixture.publication, records: [row], intent: intent) == ref)
    #expect(try await library.record(row.key)?.payload == row.payload)
    await #expect(throws: (any Error).self) { try await library.commitFeedback(changed.publication, records: [row], intent: intent) }
    let next = DrawingLibraryRecord(kind: row.kind, id: row.id, payload: Data("{\"selected\":2}".utf8))
    await #expect(throws: (any Error).self) { try await library.commitFeedback(fixture.publication, records: [next], intent: intent) }
    try await library.commitRecords([next])
    _ = try await library.commitFeedback(fixture.publication, records: [row], intent: intent)
    #expect(try await library.record(row.key)?.payload == next.payload)
    #expect(try await library.drawings().entries.isEmpty)
    await library.closeLibrary()
  }

  @Test("Feedback selectors require both digests and propagate selected index corruption")
  func exactPublicationIntegrity() async throws {
    let root = NeutralFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let first = try NeutralFeedbackFixture(root: root.appendingPathComponent("first"))
    let second = try NeutralFeedbackFixture(root: root.appendingPathComponent("second"), marker: "second")
    let directory = root.appendingPathComponent("library")
    let library = DrawingLibrary(directoryURL: directory)
    let a = try await library.commitFeedback(first.publication), b = try await library.commitFeedback(second.publication)
    let wrong = DrawingLibraryFeedbackRef(indexDigest: a.indexDigest, packageDigest: b.packageDigest)
    await #expect(throws: (any Error).self) { try await library.feedback(wrong) }
    let refused = root.appendingPathComponent("refused.zip")
    await #expect(throws: (any Error).self) { try await library.exportFeedback(wrong, to: refused) }
    #expect(!FileManager.default.fileExists(atPath: refused.path))
    let index = directory.appendingPathComponent("objects/sha256/" + a.indexDigest.description)
    let bytes = try Data(contentsOf: index)
    try Data(repeating: 0x78, count: bytes.count).write(to: index, options: .atomic)
    do { _ = try await library.feedback(a); Issue.record("Corrupt exact feedback accepted") }
    catch DrawingExchangeError.digestMismatch { }
    try bytes.write(to: index, options: .atomic)
    #expect(try await library.feedback(a).index.originalJSON == first.publication.index.originalJSON)
    await library.closeLibrary()
  }
  @Test("Same-intent retry verifies selected engine assets even while the original external carrier remains valid", arguments: ["missing", "corrupt"])
  func retryVerifiesEngineClosure(damage: String) async throws {
    let root = NeutralFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try NeutralFeedbackFixture(root: root.appendingPathComponent("external"))
    let directory = root.appendingPathComponent("engine")
    let library = DrawingLibrary(directoryURL: directory)
    let intent = DrawingLibraryCommitIntent()
    let row = DrawingLibraryRecord(kind: "example.feedback-navigation/1", id: UUID(), payload: Data("{\"selected\":1}".utf8))
    let ref = try await library.commitFeedback(fixture.publication, records: [row], intent: intent)
    let later = DrawingLibraryRecord(kind: row.kind, id: row.id, payload: Data("{\"selected\":2}".utf8))
    try await library.commitRecords([later])
    let asset = try #require(fixture.publication.index.known?.assets.first?.asset)
    let path = directory.appendingPathComponent("objects/sha256/" + asset.object.description)
    let bytes = try Data(contentsOf: path)
    if damage == "missing" { try FileManager.default.removeItem(at: path) }
    else { try Data(repeating: 0x78, count: bytes.count).write(to: path, options: .atomic) }
    // The supplied carrier still proves the original bytes. It must not repair
    // or conceal corruption in the already-published engine closure on retry.
    #expect(try fixture.publication.files.record(asset.object) == bytes)
    await #expect(throws: (any Error).self) {
      try await library.commitFeedback(fixture.publication, records: [row], intent: intent)
    }
    #expect(try await library.record(row.key)?.payload == later.payload)
    try bytes.write(to: path, options: .atomic)
    #expect(try await library.commitFeedback(fixture.publication, records: [row], intent: intent) == ref)
    #expect(try await library.record(row.key)?.payload == later.payload)
    #expect(try await library.drawings().entries.isEmpty)
    await library.closeLibrary()
  }

}
