import Foundation
import Testing
@testable import PortraitCore

@Suite("DX09 profile-local ranking responses", .serialized)
struct DrawingExchangeRankingResponseTests {
  private let a = "550e8400-e29b-41d4-a716-446655440010"
  private let b = "550e8400-e29b-41d4-a716-446655440011"
  private let c = "550e8400-e29b-41d4-a716-446655440012"
  private var root: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  }
  private func bytes(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
  private func object(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
  private func example() throws -> [String: Any] {
    let schema = try object(Data(contentsOf: root.appendingPathComponent("Resources/DrawingExchange/v1/schema.json")))
    let definitions = try #require(schema["$defs"] as? [String: Any])
    let definition = try #require(definitions["FeatureRankingCapsule"] as? [String: Any])
    var result = try #require((definition["examples"] as? [[String: Any]])?.first)
    var presentations = try #require(result["presentations"] as? [[String: Any]])
    presentations[0]["id"] = a; presentations[1]["id"] = b
    result["presentations"] = presentations
    return result
  }
  private func capsule(_ response: [String: Any], features: [String]) throws -> ExchangeRankingCapsule {
    var value = try example(); value["response"] = response; value["requiredFeatures"] = features
    return try ExchangeRankingCapsule(originalJSON: bytes(value))
  }

  @Test func validResponsesPreserveExactBytes() throws {
    let responses: [([String: Any], [String])] = [
      (["kind": "ranking", "groups": [[a], [b]]], []),
      (["kind": "ranking", "groups": [[a, b]]], []),
      (["kind": "skip", "reason": "No judgment"], []),
      (["kind": "partial-ranking", "groups": [[a]], "unranked": [b]], [ExchangeRankingCapsule.partialRankingFeature]),
      (["kind": "partial-ranking", "groups": [], "unranked": [a, b]], [ExchangeRankingCapsule.partialRankingFeature]),
      (["kind": "partial-ranking", "groups": [[a, b]], "unranked": []], [ExchangeRankingCapsule.partialRankingFeature]),
      (["kind": "neither"], [ExchangeRankingCapsule.neitherFeature]),
    ]
    for (response, features) in responses {
      let value = try capsule(response, features: features)
      #expect(value.responseKind == (response["kind"] as? String))
      #expect(value.requiredFeatures == features)
      #expect(value.unsupportedReasons.isEmpty)
      let savedResponse = try #require(try object(value.originalJSON)["response"] as? [String: Any])
      #expect(try bytes(savedResponse) == bytes(response))
    }
    let future = try capsule(["kind": "future", "vendor": ["opaque": true]], features: ["example.future/1"])
    #expect(future.unsupportedReasons == ["Unsupported ranking response: future"])
    let futureResponse = try #require(try object(future.originalJSON)["response"] as? [String: Any])
    #expect(try bytes(futureResponse) == bytes(["kind": "future", "vendor": ["opaque": true]]))
  }

  @Test func malformedResponsesCannotBecomeLabels() throws {
    let partial = ExchangeRankingCapsule.partialRankingFeature, neither = ExchangeRankingCapsule.neitherFeature
    let invalid: [([String: Any], [String])] = [
      (["kind": "partial-ranking", "groups": [[a]], "unranked": [b]], []),
      (["kind": "partial-ranking", "groups": [[a]], "unranked": [b]], [neither]),
      (["kind": "partial-ranking", "groups": [[]], "unranked": [a, b]], [partial]),
      (["kind": "partial-ranking", "groups": [[a]], "unranked": [a, b]], [partial]),
      (["kind": "partial-ranking", "groups": [[a]], "unranked": []], [partial]),
      (["kind": "partial-ranking", "groups": [], "unranked": [a, a]], [partial]),
      (["kind": "partial-ranking", "groups": [[a]], "unranked": [c]], [partial]),
      (["kind": "partial-ranking", "groups": [[a], [a]], "unranked": [b]], [partial]),
      (["kind": "partial-ranking", "groups": [], "unranked": [a, "invalid"]], [partial]),
      (["kind": "partial-ranking", "groups": []], [partial]),
      (["kind": "partial-ranking", "groups": [], "unranked": [a, b], "reason": "extra"], [partial]),
      (["kind": "neither"], []),
      (["kind": "neither"], [partial]),
      (["kind": "neither", "groups": []], [neither]),
      (["kind": "ranking", "groups": [[a]]], []),
      (["kind": "ranking", "groups": []], []),
      (["kind": "skip", "reason": ""], []),
    ]
    for (response, features) in invalid {
      #expect(throws: (any Error).self) { try capsule(response, features: features) }
    }
  }

  // Rebuild fresh carrier manifests around mutated records; old fixture bytes remain untouched.
  private func withCarrier(_ fixture: String, change: (inout [String: Data]) throws -> Void,
    body: (StagedExchangePackage) throws -> Void) throws {
    let staging = try DrawingExchangeCarrierTestBag(); defer { staging.dispose() }
    let original = try DrawingExchangeCarrier.stageZIP(root.appendingPathComponent("Tests/Fixtures/DrawingExchange/" + fixture), stagingParent: staging.root)
    var payload: [String: Data] = [:]
    for path in original.files.entries.keys where path.hasPrefix("data/") {
      payload[path] = try original.files.record(at: path)
    }
    try change(&payload)
    let rebuilt = try DrawingExchangeCarrierTestBag(files: payload); defer { rebuilt.dispose() }
    try body(DrawingExchangeCarrier.stageDirectory(rebuilt.source, stagingParent: rebuilt.root))
  }
  private func replaceRanking(_ payload: inout [String: Data], response: [String: Any], features: [String]) throws {
    let path = try #require(payload.keys.first { $0.hasPrefix("data/rankings/") })
    let original = try #require(payload[path]); var record = try object(original)
    record["response"] = response; record["requiredFeatures"] = features
    let revised = try bytes(record); payload[path] = revised
    let index = try #require(payload["data/exchange.json"])
    payload["data/exchange.json"] = Data(String(decoding: index, as: UTF8.self)
      .replacingOccurrences(of: ExchangeDigest.hash(original).description, with: ExchangeDigest.hash(revised).description).utf8)
  }

  @Test func carrierAdmitsOnlyKnownLocalSemantics() throws {
    for kind in ["partial-ranking", "neither", "future"] {
      try withCarrier("dx03/closure/ranking.zip", change: { payload in
        let path = try #require(payload.keys.first { $0.hasPrefix("data/rankings/") })
        let record = try object(#require(payload[path]))
        let presentations = try #require(record["presentations"] as? [[String: Any]])
        let ids = try presentations.map { try #require($0["id"] as? String) }
        let response: [String: Any] = kind == "partial-ranking" ? ["kind": kind, "groups": [], "unranked": ids] : ["kind": kind]
        try replaceRanking(&payload, response: response, features: [kind == "neither" ? ExchangeRankingCapsule.neitherFeature : ExchangeRankingCapsule.partialRankingFeature])
      }, body: { staged in
        let admitted = try ExchangeAdmission.validate(staged)
        #expect(admitted.rankingCapsules.values.first?.responseKind == kind)
        #expect(admitted.knownClosureSemanticsSupported == (kind != "future"))
        #expect(!admitted.capabilities.supported.contains(.train))
        let output = staged.stagingURL.deletingLastPathComponent().appendingPathComponent("copy.zip")
        try DrawingExchangeCarrier.preserveZIP(admitted.files, to: output)
        let restored = try DrawingExchangeCarrier.stageZIP(output, stagingParent: staged.stagingURL.deletingLastPathComponent())
        #expect(restored.files.entries.mapValues(\.digest) == staged.files.entries.mapValues(\.digest))
      })
    }
    try withCarrier("dx03/closure/ranking.zip", change: { payload in
      try replaceRanking(&payload, response: ["kind": "neither"], features: [])
    }, body: { staged in
      #expect(throws: (any Error).self) { try ExchangeAdmission.validate(staged) }
    })
  }

  @Test func reservedFeaturesCannotBlessIndexOrDrawing() throws {
    for feature in ExchangeRankingCapsule.localFeatures {
      for target in ["index", "drawing"] {
        try withCarrier("v1/source-free.zip", change: { payload in
          let path = target == "index" ? "data/exchange.json" : try #require(payload.keys.first { $0.hasSuffix("/drawing.json") })
          let original = try #require(payload[path]); var record = try object(original)
          record["requiredFeatures"] = [feature]; let revised = try bytes(record); payload[path] = revised
          if target == "drawing" {
            let index = try #require(payload["data/exchange.json"])
            payload["data/exchange.json"] = Data(String(decoding: index, as: UTF8.self)
              .replacingOccurrences(of: ExchangeDigest.hash(original).description, with: ExchangeDigest.hash(revised).description).utf8)
          }
        }, body: { staged in
          let admitted = try ExchangeAdmission.validate(staged, supportedFeatures: [feature])
          #expect(!admitted.capabilities.supported.contains(.drawing))
          if target == "drawing" {
            let path = try #require(staged.files.entries.keys.first { $0.hasSuffix("/drawing.json") })
            let direct = try DrawingExchangeCodec.decode(staged.files.record(at: path), files: staged.files, supportedFeatures: [feature])
            guard case .materialized(let value) = direct else { Issue.record("Expected known drawing"); return }
            #expect(!value.drawing.capabilities.supported.contains(.plot))
          }
        })
      }
    }
  }

  @Test func carrierRejectsMalformedPartitionsAndPreservesUnknownRequirements() throws {
    for mode in ["overlap", "missing", "unknown-feature", "unknown-profile"] {
      try withCarrier("dx03/closure/ranking.zip", change: { payload in
        let path = try #require(payload.keys.first { $0.hasPrefix("data/rankings/") })
        var record = try object(#require(payload[path]))
        let presentations = try #require(record["presentations"] as? [[String: Any]])
        let ids = try presentations.map { try #require($0["id"] as? String) }
        let response: [String: Any] = ["kind": "partial-ranking", "groups": mode == "overlap" ? [[ids[0]]] : [],
          "unranked": mode == "missing" ? [ids[0]] : ids]
        try replaceRanking(&payload, response: response, features: [ExchangeRankingCapsule.partialRankingFeature] + (mode == "unknown-feature" ? ["example.future/1"] : []))
        if mode == "unknown-profile" {
          let original = try #require(payload[path]); record = try object(original)
          record["profile"] = "adaptiveplotter.feature-ranking/9"
          let revised = try bytes(record); payload[path] = revised
          let index = try #require(payload["data/exchange.json"])
          payload["data/exchange.json"] = Data(String(decoding: index, as: UTF8.self)
            .replacingOccurrences(of: ExchangeDigest.hash(original).description, with: ExchangeDigest.hash(revised).description).utf8)
        }
      }, body: { staged in
        if mode == "overlap" || mode == "missing" {
          #expect(throws: (any Error).self) { try ExchangeAdmission.validate(staged) }
        } else {
          let admitted = try ExchangeAdmission.validate(staged, supportedFeatures: ExchangeRankingCapsule.localFeatures)
          #expect(!admitted.knownClosureSemanticsSupported)
          #expect(admitted.capabilities.supported == [.preserve, .inspect])
          if mode == "unknown-profile" { #expect(admitted.rankingCapsules.isEmpty && !admitted.opaqueRecords.isEmpty) }
        }
      })
    }
  }

  @Test func reservedFeaturesCannotBlessPhotoOrInput() throws {
    let issuer = UUID(), photoID = UUID(), inputID = UUID()
    let pixels = Data([10, 20]), parameters = Data("{}".utf8)
    let raster = try ExchangeAsset(bytes: pixels, mediaType: "application/octet-stream", encoding: "raw-gray8")
    let parameter = try ExchangeAsset(bytes: parameters, mediaType: "application/json", encoding: "example.parameters/1")
    let layout = try ExchangeRasterLayout(width: 2, height: 1, bytesPerPixel: 1, rowStride: 2)
    let descriptor = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ExchangeAssetDescriptor(asset: raster, pixelLayout: layout)))
    let parameterObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(parameter))
    for feature in ExchangeRankingCapsule.localFeatures {
      for target in ["none", "photo", "input"] {
        let photo = try bytes([
          "profile": "adaptiveplotter.photo/1", "requiredFeatures": target == "photo" ? [feature] : [],
          "ref": ["issuer": issuer.uuidString.lowercased(), "revision": photoID.uuidString.lowercased()],
          "original": descriptor, "dimensions": ["width": 2, "height": 1],
          "acquired": ["state": "unknown", "provenance": "not recorded"],
          "imported": ["state": "unknown", "provenance": "not recorded"],
        ])
        let photoRef = PhotoRef(issuer: issuer, revision: photoID, digest: .hash(photo))
        let photoObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(photoRef))
        let input = try bytes([
          "profile": "adaptiveplotter.image-input/1", "requiredFeatures": target == "input" ? [feature] : [],
          "ref": ["issuer": issuer.uuidString.lowercased(), "revision": inputID.uuidString.lowercased()], "photo": photoObject,
          "pixelBasis": ["dimensions": ["width": 2, "height": 1], "orientation": "up", "origin": "top-left", "xAxis": "right", "yAxis": "down", "pixelEdges": "integer", "pixelCenters": "half-integer"],
          "sourceToInput": [1,0,0,0,1,0,0,0,1], "inputToField": [1,0,0,0,1,0,0,0,1],
          "raster": descriptor, "mask": ["state": "none"],
          "operations": [["kind": "identity", "parameters": parameterObject]],
          "preparation": ["id": "example.preparation", "version": "1", "record": parameter.object.description],
        ])
        let objects: [ExchangeDigest: Data] = [.hash(photo): photo, .hash(input): input, raster.object: pixels, parameter.object: parameters]
        let admittedPhoto = try DrawingImageAdmission.photo(photoRef, objects: objects, supportedFeatures: [feature])
        let inputRef = ImageInputRef(issuer: issuer, revision: inputID, digest: .hash(input))
        let admittedInput = try DrawingImageAdmission.input(inputRef, objects: objects, supportedFeatures: [feature])
        #expect(admittedPhoto.supportedSemantics == (target != "photo"))
        #expect(admittedInput.supportedSemantics == (target == "none"))
      }
    }
  }
}
