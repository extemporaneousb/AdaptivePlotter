import Foundation
import Testing

@testable import PlotterModel

@Suite("Drawing material final-scale feasibility")
struct DrawingMaterialFeasibilityTests {
  @Test("actual scale changes crowding and short strokes; rotation and translation preserve them")
  func actualPlacement() throws {
    let program = try program([[(1, 1), (11, 1)], [(1, 2), (11, 2)], [(20, 20), (20.75, 20)]])
    let profile = try profile(width: 1)
    let small = try DrawingMaterialFeasibility.assess(program: program, placement: placement(), profile: profile)
    let large = try DrawingMaterialFeasibility.assess(program: program, placement: placement(scale: 2), profile: profile)
    let rotated = try DrawingMaterialFeasibility.assess(program: program,
      placement: placement(rotation: 0.71, x: 15, y: -43), profile: profile)
    #expect(small.closeSegmentPairCount == 1)
    #expect(small.shortStrokeCount == 1)
    #expect(large.closeSegmentPairCount == 0)
    #expect(large.shortStrokeCount == 0)
    #expect(small.drawingHeightMM == 100)
    #expect(large.drawingHeightMM == 200)
    #expect(rotated.drawingHeightMM == small.drawingHeightMM)
    #expect(rotated.closeSegmentPairCount == small.closeSegmentPairCount)
    #expect(rotated.shortStrokeCount == small.shortStrokeCount)
    #expect(rotated.placementHash != small.placementHash)
  }

  @Test("measured upper width plus uncertainty sets useful detail and clearance")
  func measuredWidth() throws {
    let program = try program([[(1, 1), (11, 1)], [(1, 2), (11, 2)], [(20, 20), (20.75, 20)]])
    let nominal = try profile(width: 0.4)
    let estimate = try profile(width: 0.4, qualification: .controllerCoordinateEstimate, upper: 0.8, uncertainty: 0.2)
    let first = try DrawingMaterialFeasibility.assess(program: program, placement: placement(), profile: nominal)
    let second = try DrawingMaterialFeasibility.assess(program: program, placement: placement(), profile: estimate)
    #expect(first.closeSegmentPairCount == 0)
    #expect(first.shortStrokeCount == 0)
    #expect(second.conservativeWidthMM == 1)
    #expect(second.minimumClearGapMM == 0.5)
    #expect(second.minimumUsefulLengthMM == 1)
    #expect(second.closeSegmentPairCount == 1)
    #expect(second.shortStrokeCount == 1)
    #expect(first.summary.contains("Nominal"))
    #expect(second.summary.contains("Controller-coordinate"))
    #expect(second.summary.contains("independent physical metric unverified"))
  }

  @Test("physical, bounded and unavailable qualifications remain distinct")
  func qualifications() throws {
    let drawing = try program([[(1, 1), (11, 1)]])
    let measured = try DrawingMaterialFeasibility.assess(program: drawing, placement: placement(),
      profile: profile(width: 1, qualification: .independentlyMeasured, upper: 1.2))
    let bounded = try DrawingMaterialFeasibility.assess(program: drawing, placement: placement(),
      profile: profile(width: 1, qualification: .bounded, upper: 1.2))
    let unavailable = try DrawingMaterialFeasibility.assess(program: drawing, placement: placement(),
      profile: profile(width: 1, qualification: .unavailable))
    #expect(measured.summary.contains("Independently measured"))
    #expect(bounded.summary.contains("Bounded width"))
    #expect(unavailable.summary.contains("unavailable; nominal fallback"))
  }

  @Test("whole-stroke useful length does not count tessellation edges as tiny strokes")
  func continuousStroke() throws {
    let drawing = try program([[(1, 1), (1.2, 1), (1.2, 1), (1.4, 1), (3, 1)]])
    let report = try DrawingMaterialFeasibility.assess(program: drawing, placement: placement(), profile: profile(width: 1))
    #expect(report.shortStrokeCount == 0)
    #expect(report.closeSegmentPairCount == 0)
    #expect(report.examinedSegmentCount == 4)
    #expect(report.analysisIsComplete)
  }

  @Test("parallel overlaps count while intended crosshatch intersections and adjacent vertices do not")
  func crossingsAndOverlaps() throws {
    let material = try profile(width: 1)
    // A shallow-angle actual crossing is excluded even though it is within 15 degrees.
    let crossing = try program([[(1, 5), (21, 5)], [(1, 4), (21, 6)]])
    let crossReport = try DrawingMaterialFeasibility.assess(program: crossing, placement: placement(), profile: material)
    #expect(crossReport.closeSegmentPairCount == 0)
    let overlap = try program([[(1, 5), (21, 5)], [(11, 5), (31, 5)]])
    let overlapReport = try DrawingMaterialFeasibility.assess(program: overlap, placement: placement(), profile: material)
    #expect(overlapReport.closeSegmentPairCount == 1)
    let rotatedOverlapReport = try DrawingMaterialFeasibility.assess(program: overlap,
      placement: placement(rotation: 0.83, x: 20, y: -37), profile: material)
    #expect(rotatedOverlapReport.closeSegmentPairCount == 1)
    // The closing edge and first edge share a vertex but are not numerically adjacent.
    let closed = try program([[(1, 1), (11, 1), (11, 11), (1, 11), (1, 1)]])
    let closedReport = try DrawingMaterialFeasibility.assess(program: closed, placement: placement(), profile: material)
    #expect(closedReport.closeSegmentPairCount == 0)
  }

  @Test("near-parallel policy requires longitudinal overlap and distinguishes endpoint continuation")
  func finiteSegmentGaps() throws {
    let drawing = try program([[(1, 1), (11, 1)], [(11.1, 1), (21, 1)]])
    let report = try DrawingMaterialFeasibility.assess(program: drawing, placement: placement(), profile: profile(width: 1))
    #expect(report.closeSegmentPairCount == 0)
    #expect(report.limitations.contains { $0.contains("Other topology") })
  }

  @Test("work budgets report incomplete counts and exact boundaries report complete")
  func boundedWork() throws {
    let drawing = try program([[(1, 1), (11, 1)], [(1, 2), (11, 2)], [(1, 3), (11, 3)]])
    let material = try profile(width: 1)
    let exact = try DrawingMaterialFeasibility.assess(program: drawing, placement: placement(), profile: material,
      segmentBudget: 3, pairBudget: 3)
    let segmentLimited = try DrawingMaterialFeasibility.assess(program: drawing, placement: placement(), profile: material,
      segmentBudget: 2, pairBudget: 3)
    let pairLimited = try DrawingMaterialFeasibility.assess(program: drawing, placement: placement(), profile: material,
      segmentBudget: 3, pairBudget: 1)
    #expect(exact.analysisIsComplete)
    #expect(exact.closeSegmentPairCount == 2)
    #expect(!segmentLimited.analysisIsComplete)
    #expect(segmentLimited.examinedSegmentCount == 2)
    #expect(segmentLimited.limitations.contains { $0.contains("Segment budget exhausted") })
    #expect(!pairLimited.analysisIsComplete)
    #expect(pairLimited.closeSegmentPairCount == 1)
    #expect(pairLimited.limitations.contains { $0.contains("Pair budget exhausted") })
    #expect(pairLimited.summary.contains("Incomplete analysis"))
  }

  @Test("already cancelled tasks refuse assessment")
  func cancellation() async throws {
    let drawing = try program([[(1, 1), (11, 1)]])
    let acceptedPlacement = try placement()
    let material = try profile(width: 1)
    let assessment = Task.detached {
      withUnsafeCurrentTask { $0?.cancel() }
      return try DrawingMaterialFeasibility.assess(program: drawing, placement: acceptedPlacement, profile: material)
    }
    do {
      _ = try await assessment.value
      Issue.record("Cancelled feasibility assessment unexpectedly returned a report")
    } catch is CancellationError {
      // Cancellation remains distinct from an incomplete-but-valid diagnostic.
    }
  }

  @Test("large paths poll cancellation during traversal and pair analysis")
  func cooperativeCancellation() throws {
    let drawing = try program([(0...600).map { index in (Double(index % 100), Double(index % 2)) }])
    var checks = 0
    #expect(throws: CancellationError.self) {
      _ = try DrawingMaterialFeasibility.assess(program: drawing, placement: placement(), profile: profile(width: 1),
        segmentBudget: 1_000, pairBudget: 250_000, cancellationCheck: {
          checks += 1
          if checks == 4 { throw CancellationError() }
        })
    }
    #expect(checks == 4)
    checks = 0
    #expect(throws: CancellationError.self) {
      _ = try DrawingMaterialFeasibility.assess(program: drawing, placement: placement(), profile: profile(width: 1),
        segmentBudget: 1_000, pairBudget: 250_000, cancellationCheck: {
          checks += 1
          // Entry + five traversal checks precede pair checks.
          if checks == 9 { throw CancellationError() }
        })
    }
    #expect(checks == 9)
  }

  @Test("reports bind immutable inputs and retain deterministic identity across encoding")
  func immutableIdentity() throws {
    let drawing = try program([[(1, 1), (11, 1)], [(1, 2), (11, 2)]])
    let acceptedPlacement = try placement(rotation: 0.4)
    let material = try profile(width: 1)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let originalDrawing = try encoder.encode(drawing)
    let originalPlacement = try encoder.encode(acceptedPlacement)
    let originalMaterial = try encoder.encode(material)
    let report = try DrawingMaterialFeasibility.assess(program: drawing, placement: acceptedPlacement, profile: material)
    let repeated = try DrawingMaterialFeasibility.assess(program: drawing, placement: acceptedPlacement, profile: material)
    let restored = try JSONDecoder().decode(DrawingMaterialFeasibilityReport.self, from: encoder.encode(report))
    #expect(report == repeated)
    #expect(report == restored)
    #expect(try canonicalDigest(of: report) == canonicalDigest(of: restored))
    #expect(report.programHash == drawing.contentHash.description)
    #expect(report.placementHash == (try canonicalDigest(of: acceptedPlacement)).description)
    #expect(report.profileKey == material.key)
    #expect(try encoder.encode(drawing) == originalDrawing)
    #expect(try encoder.encode(acceptedPlacement) == originalPlacement)
    #expect(try encoder.encode(material) == originalMaterial)
  }

  private func program(_ paths: [[(Double, Double)]]) throws -> DrawingProgram {
    let style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: IDs.pen)
    let strokes = try paths.enumerated().map { index, points in
      LogicalStroke(id: StrokeID(uuid(String(format: "00000000-0000-0000-0000-%012d", index + 100))),
        path: try Polyline(points: points.map { try fieldPoint($0.0, $0.1) }), style: style,
        ordering: UInt32(index))
    }
    return try DrawingProgram(id: IDs.program, fieldExtent: Size2(width: 100, height: 100), strokes: strokes,
      source: DrawingSourceProvenance(kind: "material-feasibility-fixture", sourceIdentifier: "v1"))
  }

  private func placement(scale: Double = 1, rotation: Double = 0, x: Double = 0, y: Double = 0) throws -> DrawingPlacement {
    try DrawingPlacement(fieldAnchor: fieldPoint(0, 0), machineAnchor: machinePoint(x, y),
      uniformScale: scale, rotationRadians: rotation)
  }

  private func profile(width: Double, qualification: MaterialWidthQualification = .nominal,
    upper: Double? = nil, uncertainty: Double = 0) throws -> DrawingMaterialProfileRevision {
    let distribution = try upper.map {
      try DepositedWidthDistribution(medianMM: $0, lowerBoundMM: $0, upperBoundMM: $0,
        uncertaintyMM: uncertainty, sampleCount: 10)
    }
    return try DrawingMaterialProfileRevision(id: uuid("E7D2F780-78D2-4C1C-884A-B1485118B936"),
      name: "Fixture material", nominalWidthMM: width, qualification: qualification,
      depositedWidth: distribution, measurementEvidenceID: distribution == nil ? nil : IDs.program.rawValue,
      physicalMetricRevision: qualification == .independentlyMeasured ? "independent-fixture-metric-1" : nil,
      createdAt: Date(timeIntervalSince1970: 0))
  }
}
