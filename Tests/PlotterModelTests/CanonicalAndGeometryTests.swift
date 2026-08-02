import Foundation
import Testing

@testable import PlotterModel

private struct CanonicalGoldenFixture: CanonicalEncodable {
  let text: String
  let id: UUID
  let signedZero: Double

  func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendString(text)
    encoder.appendUUID(id)
    encoder.appendUInt16(0x1234)
    try encoder.appendDouble(signedZero)
  }
}

@Suite("Canonical identity")
struct CanonicalIdentityTests {
  @Test("canonical bytes and digest have byte-level goldens")
  func golden() throws {
    let fixture = CanonicalGoldenFixture(
      text: "Cafe\u{301}",
      id: uuid("00112233-4455-6677-8899-aabbccddeeff"),
      signedZero: -0.0
    )
    let bytes = try canonicalBytes(of: fixture)
    #expect(
      bytes.map { String(format: "%02x", $0) }.joined()
        == "41504342000100000005436166c3a900112233445566778899aabbccddeeff12340000000000000000")
    #expect(
      try canonicalDigest(of: fixture).description
        == "541eccf1f035961feab35abd5c6e555f97abaf78960b99aa9fd0c9378e7269fc")
  }

  @Test("NFC strings and signed zero normalize")
  func normalization() throws {
    let composed = CanonicalGoldenFixture(
      text: "Café",
      id: uuid("00112233-4455-6677-8899-aabbccddeeff"),
      signedZero: 0
    )
    let decomposed = CanonicalGoldenFixture(
      text: "Cafe\u{301}",
      id: uuid("00112233-4455-6677-8899-aabbccddeeff"),
      signedZero: -0.0
    )
    #expect(try canonicalBytes(of: composed) == canonicalBytes(of: decomposed))
  }

  @Test("non-finite values are rejected", arguments: [Double.nan, .infinity, -.infinity])
  func rejectsNonFinite(value: Double) {
    #expect(throws: CanonicalEncodingError.nonFiniteDouble) {
      _ = try canonicalBytes(
        of: CanonicalGoldenFixture(
          text: "x",
          id: UUID(),
          signedZero: value
        ))
    }
  }

  @Test("program hash is stable and source strings normalize")
  func programHash() throws {
    let first = try drawingProgram()
    let stroke = first.strokes[0]
    let second = try DrawingProgram(
      id: IDs.program,
      fieldExtent: Size2(width: 100, height: 100),
      strokes: [stroke],
      source: DrawingSourceProvenance(kind: "cafe\u{301}", sourceIdentifier: "probe-1")
    )
    #expect(first.contentHash == second.contentHash)
    #expect(try canonicalBytes(of: first) == canonicalBytes(of: second))
  }
}

@Suite("Typed geometry")
struct TypedGeometryTests {
  @Test("points reject non-finite coordinates")
  func pointRejectsNonFinite() {
    #expect(throws: GeometryError.nonFiniteCoordinate) {
      _ = try Point2<FieldSpace>(x: .nan, y: 0)
    }
  }

  @Test("polyline rejects a zero-length path")
  func polylineRejectsDegenerate() throws {
    let point = try fieldPoint(1, 1)
    #expect(throws: GeometryError.degenerateGeometry) {
      _ = try Polyline(points: [point, point])
    }
  }

  @Test("affine inverse round trips without a preview-space route")
  func affineRoundTrip() throws {
    let transform = try AffineTransform2<MachineSpace, FieldSpace>(
      m11: 2, m12: 0.5, m21: -0.25, m22: 1.5, tx: 3, ty: -4
    )
    let input = try machinePoint(12, 8)
    let output = try transform.applying(to: input)
    let recovered = try transform.inverted().applying(to: output)
    #expect(recovered.distance(to: input) < 1e-10)
  }

  @Test("singular affine maps are refused")
  func singularRefused() {
    #expect(throws: GeometryError.singularTransform) {
      _ = try AffineTransform2<MachineSpace, FieldSpace>(
        m11: 1, m12: 2, m21: 2, m22: 4, tx: 0, ty: 0
      )
    }
  }
}
