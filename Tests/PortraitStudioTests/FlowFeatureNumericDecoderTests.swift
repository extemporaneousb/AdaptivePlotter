import Foundation
import DrawingLibrary
import PlotterModel
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary
import Testing

@Suite("Primitive feature number decoding preserves Foundation semantics")
struct FlowFeatureNumericDecoderTests {
  @Test("Integer, decimal, exponent, signed zero and finite boundary values retain exact bits")
  func numericForms() throws {
    let tokens = [
      "0", "-0", "0.0", "-0.0", "0e0", "-0e-10", "1", "-1", "100", "-100",
      "1.0", "1e0", "1E+0", "0.1", "0.10000000000000001", "-0.10000000000000001",
      "99.99999999999999", "-99.99999999999999", "1e-308", "-1e-308",
      "5e-324", "-5e-324", "2.2250738585072014e-308", "2.225073858507201e-308",
      "1.7976931348623157e308", "-1.7976931348623157e308",
      "9007199254740991", "9007199254740992", "9007199254740993",
      "1.00000000000000011102230246251565404236316680908203125"
    ]
    let matrix = "[[" + tokens.joined(separator: ",") + "],[],[1,2,3]]"
    try assertParity(capsuleJSON(matrix: matrix), accepts: true)
  }

  @Test("Deterministic finite double corpus round-trips with the synthesized decoder")
  func finiteCorpus() throws {
    var seed: UInt64 = 0x16eb5bd74c3a2901
    var values: [Double] = [0, -0.0, .leastNonzeroMagnitude, -Double.leastNonzeroMagnitude,
      .leastNormalMagnitude, -Double.leastNormalMagnitude, .greatestFiniteMagnitude, -Double.greatestFiniteMagnitude]
    for _ in 0..<4096 {
      seed = seed &* 6364136223846793005 &+ 1442695040888963407
      let value = Double(bitPattern: seed)
      if value.isFinite { values.append(value) }
    }
    let matrix = try #require(String(data: DrawingArtifactCoding.encoder().encode([values]), encoding: .utf8))
    try assertParity(capsuleJSON(matrix: matrix), accepts: true)
  }

  @Test("Invalid numeric types, malformed numbers and malformed matrix nesting retain rejection",
    arguments: ["true", "null", "\"1\"", "{}", "[true]", "[null]", "[\"1\"]",
      "[[true]]", "[[false]]", "[[null]]", "[[\"1\"]]", "[[{}]]", "[[[1]]]",
      "[[NaN]]", "[[Infinity]]", "[[1e309]]", "[[-1e309]]", "[[01]]",
      "[[+1]]", "[[.1]]", "[[1e]]", "[[1e+]]", "[[1]"])
  func invalidMatrix(matrix: String) throws {
    try assertParity(capsuleJSON(matrix: matrix), accepts: false)
  }

  @Test("Trailing comma acceptance remains owned by Foundation", arguments: ["[[1,]]", "[[1],]"])
  func trailingComma(matrix: String) throws {
    try assertParity(capsuleJSON(matrix: matrix), accepts: nil)
  }

  @Test("Field spelling, order, duplicates and unknown fields preserve decoder acceptance",
    arguments: ["reordered", "escaped", "duplicate-valid", "duplicate-invalid-first",
      "duplicate-invalid-last", "unknown", "trailing", "invalid-metadata", "missing-strokes"])
  func envelopeForms(change: String) throws {
    let canonical = try capsuleJSON(matrix: "[[0.1,-0.0,5e-324]]")
    var text = try #require(String(data: canonical, encoding: .utf8))
    var accepts: Bool? = true
    switch change {
    case "reordered":
      let object = try #require(JSONSerialization.jsonObject(with: canonical) as? [String: Any])
      let members = try object.keys.sorted().reversed().map { key in
        let name = try JSONSerialization.data(withJSONObject: key, options: [.fragmentsAllowed])
        let value = try JSONSerialization.data(withJSONObject: object[key]!, options: [.fragmentsAllowed])
        return String(decoding: name, as: UTF8.self) + ":" + String(decoding: value, as: UTF8.self)
      }
      text = "{" + members.joined(separator: ",") + "}"
    case "escaped": text = text.replacingOccurrences(of: "\"strokes\":", with: "\"\\u0073trokes\":")
    case "duplicate-valid": text = String(text.dropLast()) + ",\"strokes\":[[1,2,3]]}"
    case "duplicate-invalid-first": text = "{\"strokes\":null," + String(text.dropFirst()); accepts = nil
    case "duplicate-invalid-last": text = String(text.dropLast()) + ",\"strokes\":null}"; accepts = nil
    case "unknown": text = String(text.dropLast()) + ",\"other\":{\"strokes\":[true,null,\"3\"]}}"
    case "trailing": text += " false"; accepts = false
    case "invalid-metadata":
      text = text.replacingOccurrences(of: "\"profile\":\"adaptiveplotter.flow-features/3\"", with: "\"profile\":null")
      accepts = false
    default:
      text = text.replacingOccurrences(of: ",\"strokes\":[[0.1,-0.0,5e-324]]", with: "")
      accepts = false
    }
    #expect(text != String(decoding: canonical, as: UTF8.self))
    try assertParity(Data(text.utf8), accepts: accepts)
  }

  private func assertParity(_ bytes: Data, accepts: Bool?) throws {
    let fast = Result { try FlowFeedbackReader.decodeFeature(bytes, specialized: true) }
    let original = Result { try FlowFeedbackReader.decodeFeature(bytes, specialized: false) }
    switch (fast, original) {
    case (.success(let a), .success(let b)):
      #expect(accepts != false)
      #expect(a.strokes.map { $0.map(\.bitPattern) } == b.strokes.map { $0.map(\.bitPattern) })
      #expect(a.drawing.map(\.bitPattern) == b.drawing.map(\.bitPattern))
      #expect(try DrawingArtifactCoding.encoder().encode(a) == DrawingArtifactCoding.encoder().encode(b))
    case (.failure, .failure): #expect(accepts != true)
    default: Issue.record("Primitive and synthesized feature decoder acceptance differ")
    }
  }

  private func capsuleJSON(matrix: String) throws -> Data {
    let id = UUID(uuidString: "D1312B3E-D535-48BF-B070-4FEC817E036A")!
    let receipt = try ExchangeAsset(bytes: Data("{}".utf8), mediaType: "application/json", encoding: "utf8-json")
    let provenance = FlowPortfolioFeatureProvenance(id: "decoder-test", version: "1",
      record: receipt, nativeVerified: false)
    let value = FlowPortfolioFeatureCapsule(profile: "adaptiveplotter.flow-features/3",
      id: id, candidateID: id, sourceID: id, programDigest: .hash(Data()), rootFeatures: nil,
      strokeIDs: [], recipe: .standard, producer: provenance, extractor: provenance,
      drawing: [0, -0.0], strokes: [], removedIndices: [])
    let bytes = try DrawingArtifactCoding.encoder().encode(value)
    let text = try #require(String(data: bytes, encoding: .utf8))
    #expect(text.contains("\"strokes\":[]"))
    return Data(text.replacingOccurrences(of: "\"strokes\":[]", with: "\"strokes\":" + matrix).utf8)
  }
}
