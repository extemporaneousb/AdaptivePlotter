import CryptoKit
import Foundation
import PlotterModel
import PortraitCore

/// Converts the recorded open cubics. It never closes, joins, clips or reorders them.
public enum SwiftSketchConverter {
  public static let revision = "swiftsketch-cubic-flatten-mm-v1"
  public static let maximumDepth = 18
  public static let maximumPoints = 100_000

  public static func program(raw: Data, fieldWidthMM: Double, fieldHeightMM: Double,
    nominalPenWidthMM: Double, sourceIdentifier: String,
    penProfileID: PenProfileID = PenProfileID(UUID(uuidString: "DB7E0C34-89CB-4DC0-BF23-3ADEA6745E10")!)) throws -> DrawingProgram {
    guard raw.count <= 2 * 1024 * 1024,
      fieldWidthMM.isFinite, fieldHeightMM.isFinite,
      fieldWidthMM > 0, fieldWidthMM <= 2000, fieldHeightMM > 0, fieldHeightMM <= 2000,
      nominalPenWidthMM.isFinite, nominalPenWidthMM > 0, nominalPenWidthMM <= 10,
      !sourceIdentifier.isEmpty, sourceIdentifier.utf8.count <= 4096 else { throw SwiftSketchError.invalid("Invalid conversion material or dimensions.") }
    let document = try JSONDecoder().decode(RawCurves.self, from: raw)
    guard document.schemaVersion == 1, document.coordinateSpace == "image-pixels-y-down",
      document.curveKind == "ordered-open-cubic", document.canvasWidth == 224,
      document.canvasHeight == 224, document.refined.count == 32,
      document.diffusionNormalized.count == 32, document.refinedNormalized.count == 32 else {
      throw SwiftSketchError.invalid("Unsupported SwiftSketch curve schema or stroke count.")
    }
    // Preserve both raw tensors as valid evidence even though only refined pixels are converted.
    for tensor in [document.diffusionNormalized, document.refinedNormalized, document.refined] {
      guard tensor.allSatisfy({ $0.count == 4 && $0.allSatisfy { $0.count == 2 && $0.allSatisfy(\.isFinite) } }) else {
        throw SwiftSketchError.invalid("SwiftSketch requires four finite xy points per cubic.")
      }
    }
    let tolerance = min(0.05, nominalPenWidthMM / 4)
    let scale = min(fieldWidthMM / 224, fieldHeightMM / 224)
    let offsetX = (fieldWidthMM - 224 * scale) / 2
    let offsetY = (fieldHeightMM - 224 * scale) / 2
    let style = try StrokeStyle(nominalLineWidth: nominalPenWidthMM, penProfileID: penProfileID)
    let rawHash = DrawingPackageCodec.sha256(raw)
    let identity = "\(revision)|raw=\(rawHash)|width=\(fieldWidthMM)|height=\(fieldHeightMM)|pen=\(nominalPenWidthMM)|profile=\(penProfileID)|source=\(sourceIdentifier)"
    var count = 0
    let strokes = try document.refined.enumerated().map { index, curve in
      try Task.checkCancellation()
      let points = try curve.map { point -> Point2<FieldSpace> in
        guard point[0] >= 0, point[0] <= 224, point[1] >= 0, point[1] <= 224 else {
          throw SwiftSketchError.invalid("SwiftSketch control point lies outside the declared image field.")
        }
        return try Point2(x: offsetX + point[0] * scale, y: offsetY + (224 - point[1]) * scale)
      }
      var flattened = [points[0]]
      count += 1
      try flatten(points, depth: 0, tolerance: tolerance, result: &flattened, totalCount: &count)
      guard count <= maximumPoints else { throw SwiftSketchError.invalid("Cubic flattening exceeds the point budget.") }
      return LogicalStroke(id: StrokeID(stableID(identity + "|stroke=\(index)")),
        path: try Polyline(points: flattened), style: style, ordering: UInt32(index))
    }
    return try DrawingProgram(id: ProgramID(stableID(identity)),
      fieldExtent: Size2(width: fieldWidthMM, height: fieldHeightMM), strokes: strokes,
      source: DrawingSourceProvenance(kind: "portrait", sourceIdentifier: identity))
  }

  private static func flatten(_ p: [Point2<FieldSpace>], depth: Int, tolerance: Double,
    result: inout [Point2<FieldSpace>], totalCount: inout Int) throws {
    try Task.checkCancellation()
    if max(distance(p[1], to: p[0], p[3]), distance(p[2], to: p[0], p[3])) <= tolerance {
      guard totalCount < maximumPoints else { throw SwiftSketchError.invalid("Cubic flattening exceeds the point budget.") }
      totalCount += 1
      result.append(p[3]); return
    }
    guard depth < maximumDepth else { throw SwiftSketchError.invalid("Cubic flattening cannot meet the physical tolerance.") }
    let a = try midpoint(p[0], p[1]), b = try midpoint(p[1], p[2]), c = try midpoint(p[2], p[3])
    let d = try midpoint(a, b), e = try midpoint(b, c), f = try midpoint(d, e)
    try flatten([p[0], a, d, f], depth: depth + 1, tolerance: tolerance, result: &result, totalCount: &totalCount)
    try flatten([f, e, c, p[3]], depth: depth + 1, tolerance: tolerance, result: &result, totalCount: &totalCount)
  }

  /// Freeze these settings alongside the exact raw curves and resulting DrawingProgram.
  public static func settingsJSON(fieldWidthMM: Double, fieldHeightMM: Double,
    nominalPenWidthMM: Double) throws -> Data {
    guard fieldWidthMM.isFinite, fieldHeightMM.isFinite, nominalPenWidthMM.isFinite,
      fieldWidthMM > 0, fieldHeightMM > 0, nominalPenWidthMM > 0 else {
      throw SwiftSketchError.invalid("Invalid conversion settings.")
    }
    let scale = min(fieldWidthMM / 224, fieldHeightMM / 224)
    return try JSONSerialization.data(withJSONObject: ["revision": revision,
      "field_width_mm": fieldWidthMM, "field_height_mm": fieldHeightMM,
      "nominal_pen_width_mm": nominalPenWidthMM,
      "tolerance_mm": min(0.05, nominalPenWidthMM / 4), "maximum_depth": maximumDepth,
      "maximum_points": maximumPoints, "curve_order": "preserved-open",
      "affine_image_pixels_to_field_mm": [scale, 0, 0, -scale,
        (fieldWidthMM-224*scale)/2, (fieldHeightMM-224*scale)/2+224*scale]], options: [.sortedKeys])
  }

  private static func midpoint(_ a: Point2<FieldSpace>, _ b: Point2<FieldSpace>) throws -> Point2<FieldSpace> {
    try Point2(x: (a.x+b.x)/2, y: (a.y+b.y)/2)
  }
  private static func distance(_ p: Point2<FieldSpace>, to a: Point2<FieldSpace>, _ b: Point2<FieldSpace>) -> Double {
    let dx = b.x-a.x, dy = b.y-a.y, length = dx*dx+dy*dy
    let t = length == 0 ? 0 : max(0, min(1, ((p.x-a.x)*dx+(p.y-a.y)*dy)/length))
    return hypot(p.x-a.x-t*dx, p.y-a.y-t*dy)
  }
  private static func stableID(_ value: String) -> UUID {
    let b = Array(SHA256.hash(data: Data(value.utf8)))
    return UUID(uuid: (b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7],b[8],b[9],b[10],b[11],b[12],b[13],b[14],b[15]))
  }
  private struct RawCurves: Decodable {
    let schemaVersion: Int, canvasWidth: Int, canvasHeight: Int
    let coordinateSpace: String, curveKind: String
    let refined: [[[Double]]], diffusionNormalized: [[[Double]]], refinedNormalized: [[[Double]]]
    enum CodingKeys: String, CodingKey {
      case schemaVersion = "schema_version", canvasWidth = "canvas_width", canvasHeight = "canvas_height"
      case coordinateSpace = "coordinate_space", curveKind = "curve_kind", refined
      case diffusionNormalized = "diffusion_normalized", refinedNormalized = "refined_normalized"
    }
  }
}
