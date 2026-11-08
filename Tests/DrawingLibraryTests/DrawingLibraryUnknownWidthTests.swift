import Foundation
import PortraitCore
import Testing

@Suite("DX05 unknown width compatibility")
struct DrawingLibraryUnknownWidthTests {
  private var fixture: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Fixtures/DrawingExchange/drawing-first/unknown-width-v1")
  }
  private func read() throws -> (Data, [ExchangeDigest: Data], DrawingRef) {
    struct Manifest: Decodable { let drawing: DrawingRef }
    let raw = try Data(contentsOf: fixture.appendingPathComponent("drawing.json"))
    let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: fixture.appendingPathComponent("manifest.json")))
    var objects: [ExchangeDigest: Data] = [:]
    for url in try FileManager.default.contentsOfDirectory(at: fixture.appendingPathComponent("objects"), includingPropertiesForKeys: nil) {
      objects[try ExchangeDigest(url.lastPathComponent)] = try Data(contentsOf: url)
    }
    return (raw, objects, manifest.drawing)
  }

  @Test("Current freeze emits the reproducible widthless v1 fixture without adding a wire field")
  func currentWriterMatchesFixture() throws {
    let (raw, objects, reference) = try read()
    let admission = try DrawingExchangeCodec.decode(raw, objects: objects, expected: reference)
    guard case .materialized(let retained) = admission else { Issue.record("Expected known stroke representation"); return }
    let fresh = try Drawing(program: retained.drawing.program, input: retained.drawing.input,
      parent: retained.drawing.parent, producer: retained.drawing.producer, units: DrawingUnits())
    let date = try #require(ISO8601DateFormatter().date(from: "2026-11-07T20:00:00Z"))
    let emitted = try DrawingExchangeCodec.freeze(fresh, identity: reference.identity,
      createdAt: date, originalProgramJSON: retained.originalProgramJSON)
    #expect(emitted.originalJSON == raw)
    #expect(emitted.reference == reference)
    #expect(emitted.originalProgramJSON == retained.originalProgramJSON)
    #expect(emitted.drawing.units.nominalPenWidthMM == nil)
    #expect(emitted.drawing.units.historical == nil)
    let json = try #require(JSONSerialization.jsonObject(with: raw) as? [String: Any])
    let representation = try #require(json["representation"] as? [String: Any])
    #expect(representation["nominalPenWidthMillimeters"] == nil)
    #expect(representation["historicalUnits"] == nil)
  }

  @Test("Declared nominal width stays distinct and must be positive finite")
  func declaredWidthValidation() throws {
    #expect(try DrawingUnits(nominalPenWidthMM: 0.35).nominalPenWidthMM == 0.35)
    for invalid in [0.0, -1.0, Double.nan, Double.infinity] {
      #expect(throws: (any Error).self) { try DrawingUnits(nominalPenWidthMM: invalid) }
    }
    #expect(try DrawingUnits().nominalPenWidthMM == nil)
  }
}
