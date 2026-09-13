import Foundation

/// A diagnostic of an immutable program at one exact accepted placement. Counts
/// describe examined geometry; they are lower bounds when analysis is incomplete.
/// The gap and useful-length fields are policy requirements, not observed minima.
public struct DrawingMaterialFeasibilityReport: Codable, Hashable, Sendable, CanonicalEncodable {
  public let profileKey: String
  public let programHash: String
  public let placementHash: String
  public let conservativeWidthMM: Double
  /// Authored field height after uniform scale, independent of rotation.
  public let drawingHeightMM: Double
  public let minimumClearGapMM: Double
  public let minimumUsefulLengthMM: Double
  public let shortStrokeCount: Int
  public let closeSegmentPairCount: Int
  public let examinedSegmentCount: Int
  public let analysisIsComplete: Bool
  public let limitations: [String]
  public let summary: String

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendString("DrawingMaterialFeasibilityReport-v1")
    for value in [profileKey, programHash, placementHash] { try encoder.appendString(value) }
    for value in [conservativeWidthMM, drawingHeightMM, minimumClearGapMM, minimumUsefulLengthMM] {
      try encoder.appendDouble(value)
    }
    for value in [shortStrokeCount, closeSegmentPairCount, examinedSegmentCount] {
      try encoder.appendCount(value)
    }
    encoder.appendBool(analysisIsComplete)
    try encoder.appendCount(limitations.count)
    for value in limitations { try encoder.appendString(value) }
    try encoder.appendString(summary)
  }
}

public enum DrawingMaterialFeasibility {
  /// Bounds apply even to degenerate/repeated input segments and pairs discarded
  /// by geometric filters. Work is O(maximumSegments + maximumPairChecks).
  public static let maximumSegments = 20_000
  public static let maximumPairChecks = 250_000

  public static func assess(
    program: DrawingProgram, placement: DrawingPlacement, profile: DrawingMaterialProfileRevision
  ) throws -> DrawingMaterialFeasibilityReport {
    try assess(program: program, placement: placement, profile: profile,
      segmentBudget: maximumSegments, pairBudget: maximumPairChecks)
  }

  // Smaller budgets let tests verify exact boundary behavior without enormous fixtures.
  static func assess(
    program: DrawingProgram, placement: DrawingPlacement, profile: DrawingMaterialProfileRevision,
    segmentBudget: Int, pairBudget: Int,
    cancellationCheck: () throws -> Void = { try Task.checkCancellation() }
  ) throws -> DrawingMaterialFeasibilityReport {
    try cancellationCheck()
    try profile.validate()
    guard segmentBudget > 0, pairBudget >= 0 else {
      throw PlotterModelError.invalidValue("Invalid material feasibility work budget")
    }
    let width = profile.conservativeWidthMM
    let height = program.fieldExtent.height * placement.uniformScale
    let centerlineRequirement = width * 1.5
    let fieldDiagonal = hypot(program.fieldExtent.width * placement.uniformScale, height)
    guard height.isFinite, height > 0, fieldDiagonal.isFinite, centerlineRequirement.isFinite else {
      throw PlotterModelError.invalidValue("Material feasibility geometry overflow")
    }
    let transform = try placement.fieldToMachineTransform
    var segments: [Segment] = []
    var examinedSegments = 0
    var shortStrokes = 0
    var complete = true
    var limitations = [
      "Policy: clear edge gap at least 0.5 times conservative width; centerline spacing at least 1.5 times width; whole-stroke length at least width.",
      "Crowding counts overlapping near-parallel segment pairs within 15 degrees. Adjacent continuous segments and intersecting crossings are excluded; collinear overlaps count. Other topology and intentional parallel overlap are not classified.",
      "Conservative isotropic width envelope is used for every direction. Counts do not predict ink pooling, paper behavior, likeness or attended drawing quality.",
      "Material applicability to current mount, contact, paper and feed is checked by the run owner, not this geometric assessment."
    ]

    strokeLoop: for (strokeIndex, stroke) in program.strokes.enumerated() {
      var length = 0.0
      var nonzeroOrdinal = 0
      var start = try transform.applying(to: stroke.path.points[0])
      for pointIndex in 1..<stroke.path.points.count {
        if examinedSegments == segmentBudget {
          complete = false
          limitations.append("Segment budget exhausted; remaining strokes and crowding were not examined. Reported issue counts are lower bounds.")
          break strokeLoop
        }
        if examinedSegments.isMultiple(of: 128) { try cancellationCheck() }
        let end = try transform.applying(to: stroke.path.points[pointIndex])
        let segmentLength = hypot(end.x - start.x, end.y - start.y)
        guard segmentLength.isFinite, (length + segmentLength).isFinite else {
          throw PlotterModelError.invalidValue("Material feasibility geometry overflow")
        }
        length += segmentLength
        examinedSegments += 1
        if segmentLength > 0 {
          segments.append(Segment(start: start, end: end, length: segmentLength,
            strokeIndex: strokeIndex, ordinal: nonzeroOrdinal))
          nonzeroOrdinal += 1
        }
        start = end
      }
      if length < width { shortStrokes += 1 }
    }

    var closePairs = 0
    var pairChecks = 0
    pairLoop: for firstIndex in segments.indices {
      for secondIndex in (firstIndex + 1)..<segments.count {
        if pairChecks == pairBudget {
          complete = false
          limitations.append("Pair budget exhausted; remaining crowding was not examined. Reported close-pair count is a lower bound.")
          break pairLoop
        }
        if pairChecks.isMultiple(of: 128) { try cancellationCheck() }
        pairChecks += 1
        let first = segments[firstIndex]
        let second = segments[secondIndex]
        if first.strokeIndex == second.strokeIndex && (
          abs(first.ordinal - second.ordinal) == 1 || first.sharesEndpoint(with: second)
        ) { continue }
        if first.isCrowded(by: second, centerlineRequirement: centerlineRequirement) {
          closePairs += 1
        }
      }
    }
    try cancellationCheck()
    let qualification: String
    switch profile.qualification {
    case .nominal:
      qualification = "Nominal width; deposited behavior unmeasured"
    case .controllerCoordinateEstimate:
      qualification = "Controller-coordinate width estimate; independent physical metric unverified"
    case .independentlyMeasured:
      qualification = "Independently measured width for the recorded physical metric"
    case .bounded:
      qualification = "Bounded width; no resolved independent physical-width estimate"
    case .unavailable:
      qualification = profile.depositedWidth == nil
        ? "Width measurement unavailable; nominal fallback"
        : "Width measurement unavailable; retained width bound used"
    }
    let result = complete
      ? "\(shortStrokes) short strokes; \(closePairs) close parallel pairs"
      : "Incomplete analysis: at least \(shortStrokes) short strokes and \(closePairs) close parallel pairs"
    return DrawingMaterialFeasibilityReport(
      profileKey: profile.key, programHash: program.contentHash.description,
      placementHash: try canonicalDigest(of: placement).description,
      conservativeWidthMM: width, drawingHeightMM: height,
      minimumClearGapMM: width * 0.5, minimumUsefulLengthMM: width,
      shortStrokeCount: shortStrokes, closeSegmentPairCount: closePairs,
      examinedSegmentCount: examinedSegments, analysisIsComplete: complete,
      limitations: limitations + profile.measurementLimitations,
      summary: "\(qualification). Conservative width \(width) mm at authored height \(height) mm. \(result).")
  }

  private struct Segment {
    let start: Point2<MachineSpace>
    let end: Point2<MachineSpace>
    let length: Double
    let strokeIndex: Int
    let ordinal: Int

    var ux: Double { (end.x - start.x) / length }
    var uy: Double { (end.y - start.y) / length }

    func sharesEndpoint(with other: Self) -> Bool {
      start == other.start || start == other.end || end == other.start || end == other.end
    }

    func isCrowded(by other: Self, centerlineRequirement: Double) -> Bool {
      // Work in a segment-local orthonormal basis, preserving rotation invariance
      // and avoiding squared lengths/large machine-anchor coordinates.
      guard abs(ux * other.ux + uy * other.uy) >= cos(.pi / 12) else { return false }
      let ax = (other.start.x - start.x) * ux + (other.start.y - start.y) * uy
      let ay = -(other.start.x - start.x) * uy + (other.start.y - start.y) * ux
      let bx = (other.end.x - start.x) * ux + (other.end.y - start.y) * uy
      let by = -(other.end.x - start.x) * uy + (other.end.y - start.y) * ux
      guard min(length, max(ax, bx)) > max(0, min(ax, bx)) else { return false }
      // Opposite sides imply an actual crossing only if its intersection lies
      // on this finite segment. Preserve collinear duplicate/overlapping lines.
      let collinearTolerance = 1e-10 * max(1, length, other.length)
      if (ay <= 0 && by >= 0 || by <= 0 && ay >= 0), ay != by,
        max(abs(ay), abs(by)) > collinearTolerance {
        let fraction = -ay / (by - ay)
        let intersectionX = ax + fraction * (bx - ax)
        if intersectionX >= 0 && intersectionX <= length { return false }
      }
      let distance = min(
        pointDistance(x: ax, y: ay, endX: length, endY: 0),
        pointDistance(x: bx, y: by, endX: length, endY: 0),
        pointDistance(x: -ax, y: -ay, endX: bx - ax, endY: by - ay),
        pointDistance(x: length - ax, y: -ay, endX: bx - ax, endY: by - ay))
      return distance < centerlineRequirement
    }

    private func pointDistance(x: Double, y: Double, endX: Double, endY: Double) -> Double {
      let segmentLength = hypot(endX, endY)
      guard segmentLength > 0 else { return hypot(x, y) }
      let directionX = endX / segmentLength
      let directionY = endY / segmentLength
      let projection = min(segmentLength, max(0, x * directionX + y * directionY))
      return hypot(x - projection * directionX, y - projection * directionY)
    }
  }
}
