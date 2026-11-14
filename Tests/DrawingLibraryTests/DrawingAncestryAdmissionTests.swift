import Foundation
import DrawingLibrary
import PortraitCore
import PlotterModel
import Testing

@Suite("Drawing ancestry admission reuse", .serialized)
struct DrawingAncestryAdmissionTests {
  private static let producerID = "example.ancestry-generator"
  private var validators: DrawingProducerValidators {
    .init([.init(id: Self.producerID, version: "1"): { _, _ in }])
  }

  @Test("Alternating generated and membership ancestry is decoded once per exact Drawing",
    arguments: [3, 7, 11])
  func uniqueAncestry(count: Int) throws {
    let chain = try makeChain(count: count, alternating: true)
    try withPackage(chain.payload) { staged in
      let admitted = try ExchangeAdmission.validate(staged, producerValidators: validators)
      #expect(admitted.drawings.count == chain.records.count)
      #expect(admitted.statistics.programJSONDecodeCalls == UInt64(chain.records.count))
      #expect(admitted.statistics.producerValidatorEntries == UInt64((count + 1) / 2))
      for record in chain.records {
        guard case .materialized(let value) = try #require(admitted.drawings[record.reference]) else {
          Issue.record("Ancestry became opaque"); continue
        }
        #expect(value.reference == record.reference)
        #expect(value.originalJSON == record.originalJSON)
        #expect(value.originalProgramJSON == record.originalProgramJSON)
        #expect(value.drawing.program == record.drawing.program)
        #expect(value.drawing.parent == record.drawing.parent)
        #expect(value.drawing.input == record.drawing.input)
        #expect(value.drawing.capabilities.producerVerified)
      }
      for index in chain.records.indices where index % 2 == 1 {
        #expect(chain.records[index].drawing.program.strokes ==
          Array(chain.records[index - 1].drawing.program.strokes.dropLast()))
      }
    }
  }

  @Test("A cached ancestor cannot conceal a deeper path through the same subtree",
    arguments: [false, true])
  func reusedSubtreeDepth(codecLimit: Bool) throws {
    let depth = codecLimit ? 64 : 3
    var chain = try makeChain(count: depth + 2, alternating: false, withInput: false)
    try setRoots([chain.records[depth].reference, chain.records[depth + 1].reference], in: &chain.payload)
    try withPackage(chain.payload) { staged in
      var limits = ExchangeClosureLimits()
      limits.maximumDepth = codecLimit ? 128 : depth
      #expect(throws: (any Error).self) {
        try ExchangeAdmission.validate(staged, producerValidators: validators, limits: limits)
      }
    }
  }

  @Test("A cached parent does not admit mismatched parent digests or forged membership universes",
    arguments: ["parent-digest", "universe-binding"])
  func malformedAncestry(change: String) throws {
    var chain = try makeChain(count: 4, alternating: true)
    let last = try #require(chain.records.last)
    var drawing = try object(last.originalJSON)
    if change == "parent-digest" {
      let parent = chain.records[2].reference
      let wrong = DrawingRef(issuer: parent.issuer, revision: parent.revision, digest: .hash(Data("wrong".utf8)))
      drawing["parent"] = try DrawingLibraryPhotoFixture.wire(SourceLink<DrawingRef>.present(wrong))
    } else {
      var receipt = try object(last.drawing.producer.originalJSON)
      receipt["universe"] = try DrawingLibraryPhotoFixture.wire(chain.records[0].reference)
      let bytes = try DrawingLibraryPhotoFixture.json(receipt)
      let asset = try ExchangeAsset(bytes: bytes, mediaType: "application/json", encoding: "utf8-json")
      try appendAsset(asset, bytes: bytes, to: &chain.payload)
      var producer = try #require(drawing["producer"] as? [String: Any])
      producer["record"] = asset.object.description
      drawing["producer"] = producer
    }
    let bytes = try DrawingLibraryPhotoFixture.json(drawing)
    chain.payload[path(last.reference)] = bytes
    let changed = DrawingRef(issuer: last.reference.issuer, revision: last.reference.revision, digest: .hash(bytes))
    try setRoots([chain.records[2].reference, changed], in: &chain.payload)
    try withPackage(chain.payload) { staged in
      #expect(throws: (any Error).self) { try ExchangeAdmission.validate(staged, producerValidators: validators) }
    }
  }

  @Test("Reused ancestors retain referenced-file verification when a later validator mutates a dependency")
  func mutationDuringAdmission() throws {
    var chain = try makeChain(count: 3, alternating: true)
    try setRoots([chain.records[1].reference, chain.records[2].reference], in: &chain.payload)
    let first = chain.records[0], trigger = chain.records[2].drawing.producer.record
    try withPackage(chain.payload) { staged in
      let target = staged.files.stagingURL.appendingPathComponent(
        "data/objects/sha256/" + ExchangeDigest.hash(first.originalProgramJSON).description)
      let corrupted = Data(repeating: 0x78, count: first.originalProgramJSON.count)
      let mutating = DrawingProducerValidators([.init(id: Self.producerID, version: "1"): { receipt, _ in
        if receipt.record == trigger { try corrupted.write(to: target, options: .atomic) }
      }])
      #expect(throws: (any Error).self) { try ExchangeAdmission.validate(staged, producerValidators: mutating) }
    }
  }

  @Test("Admission reuse cannot cross independent validator or required-feature contexts")
  func contextIsolation() throws {
    let chain = try makeChain(count: 5, alternating: true)
    try withPackage(chain.payload) { staged in
      let accepted = try ExchangeAdmission.validate(staged, producerValidators: validators)
      #expect(accepted.drawings.count == chain.records.count)
      let refusing = DrawingProducerValidators([.init(id: Self.producerID, version: "1"): { _, _ in
        throw DrawingExchangeError.invalidProducer("Different invocation refuses this producer")
      }])
      #expect(throws: (any Error).self) { try ExchangeAdmission.validate(staged, producerValidators: refusing) }
    }
    var changed = chain.payload
    var index = try object(#require(changed["data/exchange.json"]))
    index["requiredFeatures"] = ["example.unknown-ancestry-context/1"]
    changed["data/exchange.json"] = try DrawingLibraryPhotoFixture.json(index)
    try withPackage(changed) { staged in
      let opaque = try ExchangeAdmission.validate(staged, producerValidators: validators)
      #expect(!opaque.capabilities.supported.contains(.drawing))
      for admission in opaque.drawings.values {
        guard case .opaque = admission else { Issue.record("Unknown context exposed a materialized Drawing"); continue }
      }
    }
  }

  private struct Chain {
    var payload: [String: Data]
    let records: [FrozenDrawingRecord]
  }

  private func makeChain(count: Int, alternating: Bool, withInput: Bool = true) throws -> Chain {
    let source = try DrawingLibraryPhotoFixture()
    let template = try source.drawing().program
    let line = try #require(template.strokes.first)
    let strokes = (0..<3).map { index in
      LogicalStroke(id: StrokeID(), path: line.path, style: line.style, ordering: UInt32(index))
    }
    var records: [FrozenDrawingRecord] = []
    for index in 0..<count {
      let drawing: Drawing
      if alternating, index % 2 == 1, let parent = records.last {
        drawing = try parent.drawing.applying(.remove([strokes[2].id]),
          to: parent.reference, programID: ProgramID())
      } else {
        let program = try DrawingProgram(id: ProgramID(), fieldExtent: template.fieldExtent,
          strokes: strokes, source: template.source)
        let receipt = try DrawingProducerReceipt(id: Self.producerID, version: "1",
          recordJSON: DrawingLibraryPhotoFixture.json(["profile": "example.ancestry-generator/1", "generation": index]))
        drawing = try Drawing(program: program, input: withInput ? .present(source.input.reference) : .none,
          parent: records.last.map { .present($0.reference) } ?? .none, producer: receipt)
      }
      records.append(try DrawingExchangeCodec.freeze(drawing, identity: .init(issuer: UUID()),
        createdAt: Date(timeIntervalSince1970: 1_800_000_000)))
    }
    var payload = withInput ? try source.packagePayload() : [:]
    if !withInput {
      payload["data/exchange.json"] = try DrawingLibraryPhotoFixture.json([
        "profile": "adaptiveplotter.exchange/1", "requiredFeatures": [String](), "kind": "drawing",
        "roots": [String](), "assets": [String](), "attempts": [String](), "assessments": [String](),
        "includedAsOf": "2027-01-15T08:00:00Z"])
    }
    for record in records {
      payload[path(record.reference)] = record.originalJSON
      let program = try ExchangeAsset(bytes: record.originalProgramJSON, mediaType: "application/json",
        encoding: DrawingExchangeCodec.strokeProfile)
      try appendAsset(program, bytes: record.originalProgramJSON, to: &payload)
      let receipt = try ExchangeAsset(bytes: record.drawing.producer.originalJSON, mediaType: "application/json", encoding: "utf8-json")
      try appendAsset(receipt, bytes: record.drawing.producer.originalJSON, to: &payload)
    }
    try setRoots([#require(records.last).reference], in: &payload)
    return Chain(payload: payload, records: records)
  }

  private func appendAsset(_ asset: ExchangeAsset, bytes: Data, to payload: inout [String: Data]) throws {
    let assetPath = "data/objects/sha256/" + asset.object.description
    guard payload[assetPath] == nil else { return }
    payload[assetPath] = bytes
    var index = try object(#require(payload["data/exchange.json"]))
    var assets = try #require(index["assets"] as? [[String: Any]])
    assets.append(try #require(DrawingLibraryPhotoFixture.wire(ExchangeAssetDescriptor(asset: asset)) as? [String: Any]))
    index["assets"] = assets
    payload["data/exchange.json"] = try DrawingLibraryPhotoFixture.json(index)
  }

  private func setRoots(_ roots: [DrawingRef], in payload: inout [String: Data]) throws {
    var index = try object(#require(payload["data/exchange.json"]))
    index["kind"] = "drawing"
    index["roots"] = try DrawingLibraryPhotoFixture.wire(roots)
    payload["data/exchange.json"] = try DrawingLibraryPhotoFixture.json(index)
  }

  private func object(_ bytes: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
  }
  private func path(_ reference: DrawingRef) -> String {
    "data/drawings/\(reference.issuer.uuidString.lowercased())/\(reference.revision.uuidString.lowercased())/drawing.json"
  }
  private func withPackage(_ payload: [String: Data], body: (StagedExchangePackage) throws -> Void) throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source"), stage = root.appendingPathComponent("stage")
    try DrawingLibraryPhotoFixture.write(payload, to: source)
    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
    try body(DrawingExchangeCarrier.stageDirectory(source, stagingParent: stage))
  }
}
