import Foundation
import Testing

@testable import PlotterModel

@Suite("Built-in vector drawing catalog")
struct DrawingProgramCatalogTests {
  @Test("catalog covers every declared source and generates valid deterministic programs")
  func completeDeterministicCatalog() throws {
    #expect(DrawingProgramCatalog.entries.map(\.id) == DrawingCatalogEntryID.allCases)
    let style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: IDs.pen)

    for entry in DrawingProgramCatalog.entries {
      let first = try DrawingProgramCatalog.program(for: entry.id, style: style)
      let second = try DrawingProgramCatalog.program(for: entry.id, style: style)
      #expect(first.id == second.id)
      #expect(first.contentHash == second.contentHash)
      #expect(first.strokes.map(\.id) == second.strokes.map(\.id))
      #expect(first.fieldExtent == entry.fieldExtent)
      #expect(first.source.kind == "built-in-vector-catalog")
    }

    let pyramid = try DrawingProgramCatalog.program(for: .pyramid, style: style)
    let elephant = try DrawingProgramCatalog.program(for: .elephant, style: style)
    let baselineLine = try DrawingProgramCatalog.program(for: .line, style: style)
    #expect(pyramid.strokes.count == 4)
    #expect(elephant.strokes.count == 5)
    let restyled = try DrawingProgramCatalog.program(
      for: .line,
      style: StrokeStyle(nominalLineWidth: 0.8, penProfileID: IDs.pen)
    )
    #expect(restyled.id != baselineLine.id)
  }

  @Test("circle flattening honors the declared chord-error bound")
  func circleChordError() throws {
    let policy = try CurveTessellationPolicy(maximumChordError: 0.1)
    let program = try DrawingProgramCatalog.program(
      for: .circle,
      style: StrokeStyle(nominalLineWidth: 0.4, penProfileID: IDs.pen),
      tessellation: policy
    )
    let points = program.strokes[0].path.points
    #expect(points.first == points.last)
    for (start, end) in zip(points, points.dropFirst()) {
      let midpointRadius = hypot((start.x + end.x) / 2 - 50, (start.y + end.y) / 2 - 50)
      #expect(48 - midpointRadius <= policy.maximumChordError + 1e-12)
    }
    #expect(program.source.sourceIdentifier.contains("tess-1"))
  }

  @Test("unsupported or unbounded tessellation policies are refused")
  func tessellationValidation() {
    #expect(throws: PlotterModelError.invalidValue("unsupported curve tessellation revision")) {
      _ = try CurveTessellationPolicy(maximumChordError: 0.1, algorithmRevision: 2)
    }
    #expect(throws: PlotterModelError.invalidValue("maximumChordError must be positive and finite"))
    {
      _ = try CurveTessellationPolicy(maximumChordError: .nan)
    }
    #expect(throws: DrawingProgramCatalogError.excessiveTessellation(maximum: 12)) {
      let policy = try CurveTessellationPolicy(
        maximumChordError: 0.000_001,
        maximumSegments: 12
      )
      _ = try DrawingProgramCatalog.program(
        for: .circle,
        style: StrokeStyle(nominalLineWidth: 0.4, penProfileID: IDs.pen),
        tessellation: policy
      )
    }
  }
}

@Suite("Placed drawing execution plans")
struct DrawingExecutionPlanTests {
  @Test("placement has an explicit stable anchor, scale, and rotation")
  func placementTransform() throws {
    let placement = try DrawingPlacement(
      fieldAnchor: fieldPoint(50, 50),
      machineAnchor: machinePoint(100, 75),
      uniformScale: 2,
      rotationRadians: .pi / 2
    )
    let anchor = try placement.applying(to: fieldPoint(50, 50))
    let right = try placement.applying(to: fieldPoint(60, 50))
    #expect(anchor.distance(to: try machinePoint(100, 75)) < 1e-12)
    #expect(right.distance(to: try machinePoint(100, 95)) < 1e-12)

    let fullTurn = try DrawingPlacement(
      fieldAnchor: fieldPoint(0, 0),
      machineAnchor: machinePoint(0, 0),
      uniformScale: 1,
      rotationRadians: 2 * .pi
    )
    #expect(fullTurn.rotationRadians == 0)
  }

  @Test("planner emits one deterministic checkpoint-ending machine stroke per logical stroke")
  func boundedPlan() throws {
    let style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: IDs.pen)
    let program = try DrawingProgramCatalog.program(for: .pyramid, style: style)
    let placement = try DrawingPlacement(
      fieldAnchor: fieldPoint(50, 50),
      machineAnchor: machinePoint(100, 100),
      uniformScale: 0.5,
      rotationRadians: .pi / 4
    )
    let region = try DrawableMachineRegion(
      bounds: AxisAlignedBounds(minX: 0, minY: 0, maxX: 200, maxY: 200),
      edgeClearance: 10
    )
    let first = try DrawingPlanner.plan(
      program: program,
      placement: placement,
      drawableRegion: region,
      provenance: planningProvenance()
    )
    let second = try DrawingPlanner.plan(
      program: program,
      placement: placement,
      drawableRegion: region,
      provenance: planningProvenance()
    )

    #expect(first.revisionID == second.revisionID)
    #expect(first.contentHash == second.contentHash)
    #expect(first.sourceProgramContentHash == program.contentHash)
    #expect(first.strokes.count == program.strokes.count)
    #expect(first.checkpoints.count == program.strokes.count)
    #expect(
      zip(first.strokes, first.checkpoints).allSatisfy {
        $0.logicalStrokeID == $1.afterStrokeID && $0.endingCheckpointID == $1.id
      })
    #expect(first.strokes.allSatisfy { region.contains($0.path) })

    let roundTrip = try JSONDecoder().decode(
      ExecutionPlanRevision.self,
      from: JSONEncoder().encode(first)
    )
    #expect(roundTrip == first)
  }

  @Test("planner refuses any placed point outside the effective drawable region")
  func refusesOutsideRegion() throws {
    let program = try DrawingProgramCatalog.program(
      for: .square,
      style: StrokeStyle(nominalLineWidth: 0.4, penProfileID: IDs.pen)
    )
    let placement = try DrawingPlacement(
      fieldAnchor: fieldPoint(50, 50),
      machineAnchor: machinePoint(10, 10),
      uniformScale: 1
    )
    let region = try DrawableMachineRegion(
      bounds: AxisAlignedBounds(minX: 0, minY: 0, maxX: 100, maxY: 100),
      edgeClearance: 5
    )

    #expect(throws: DrawingPlanningError.self) {
      _ = try DrawingPlanner.plan(
        program: program,
        placement: placement,
        drawableRegion: region,
        provenance: planningProvenance()
      )
    }
  }
}

@Suite("Typed drawing readiness")
struct DrawingReadinessTests {
  @Test("ready is derived only from complete attributable evidence")
  func derivesReady() throws {
    let evidence = DrawingReadinessRequirement.allCases.enumerated().map { index, _ in
      DrawingEvidenceReference(
        recordID: evidenceID(index),
        role: index == 1 ? .training : .reservedHoldout,
        disposition: .attributable
      )
    }
    let requirements = try DrawingReadinessRequirement.allCases.enumerated().map { index, item in
      try DrawingReadinessRequirementResult(
        requirement: item,
        disposition: .passed,
        evidenceRecordIDs: [evidenceID(index)]
      )
    }
    let assessment = try DrawingReadinessAssessment(
      provenance: planningProvenance(),
      applicability: readinessRegion(),
      requirements: Array(requirements.reversed()),
      evidence: Array(evidence.reversed())
    )

    #expect(assessment.state == .ready)
    #expect(assessment.requirements.map(\.requirement) == DrawingReadinessRequirement.allCases)
    #expect(
      try JSONDecoder().decode(
        DrawingReadinessAssessment.self,
        from: JSONEncoder().encode(assessment)
      ) == assessment)
  }

  @Test("possible ink cannot produce a ready assessment")
  func possibleInkIsNotReady() throws {
    let evidence = DrawingReadinessRequirement.allCases.enumerated().map { index, _ in
      DrawingEvidenceReference(
        recordID: evidenceID(index),
        role: .reservedHoldout,
        disposition: index == 3 ? .possibleInk : .attributable
      )
    }
    let requirements = try DrawingReadinessRequirement.allCases.enumerated().map { index, item in
      try DrawingReadinessRequirementResult(
        requirement: item,
        disposition: .passed,
        evidenceRecordIDs: [evidenceID(index)]
      )
    }
    let assessment = try DrawingReadinessAssessment(
      provenance: planningProvenance(),
      applicability: readinessRegion(),
      requirements: requirements,
      evidence: evidence
    )
    #expect(assessment.state == .notReady)
  }
}

private func planningProvenance() throws -> DrawingPlanningProvenance {
  DrawingPlanningProvenance(
    modelRevisionID: DrawingModelRevisionID(uuid("10000000-0000-0000-0000-000000000001")),
    modelContentHash: try digest(0x11),
    registrationRevisionID: DrawingRegistrationRevisionID(
      uuid("20000000-0000-0000-0000-000000000002")
    ),
    registrationContentHash: try digest(0x22)
  )
}

private func readinessRegion() throws -> DrawableMachineRegion {
  try DrawableMachineRegion(
    bounds: AxisAlignedBounds(minX: 0, minY: 0, maxX: 200, maxY: 200),
    edgeClearance: 5
  )
}

private func evidenceID(_ index: Int) -> DrawingEvidenceRecordID {
  DrawingEvidenceRecordID(
    uuid(String(format: "30000000-0000-0000-0000-%012x", index + 1))
  )
}

private func digest(_ byte: UInt8) throws -> Digest {
  try Digest(bytes: Array(repeating: byte, count: Digest.byteCount))
}
