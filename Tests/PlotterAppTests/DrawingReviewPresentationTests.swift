import Foundation
import PlotterModel
import Testing
@testable import PlotterApp

@Suite("Drawing Reviewer historical evidence")
struct DrawingReviewPresentationTests {
  @Test("retained plan wins over source and remains renderable without program or photographs")
  func retainedPlan() throws {
    let program = try DrawingProgramCatalog.program(for: .rectangle,
      style: StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID()))
    let region = try DrawableMachineRegion(bounds: AxisAlignedBounds(minX: -100, minY: -100, maxX: 100, maxY: 100))
    let placement = try DrawingPlacement(fieldAnchor: Point2(x: 0, y: 0),
      machineAnchor: Point2(x: -40, y: -40), uniformScale: 0.5, rotationRadians: 0.3)
    let plan = try DrawingPlanner.plan(program: program, placement: placement, drawableRegion: region,
      provenance: DrawingPlanningProvenance(modelRevisionID: DrawingModelRevisionID(),
        modelContentHash: program.contentHash, registrationRevisionID: DrawingRegistrationRevisionID(),
        registrationContentHash: program.contentHash))
    for source in [program, nil] {
      let resolved = try #require(DrawingReviewGeometry.resolve(plan: plan, sourceProgram: source))
      #expect(resolved.title == "Retained execution plan")
      #expect(resolved.preview.plannedStrokes == plan.strokes)
      #expect(resolved.preview.evidence?.planContentHash == plan.contentHash.description)
      #expect(resolved.preview.evidence?.placement == plan.placement)
      #expect(resolved.preview.program == nil)
      #expect(resolved.preview.geometry(in: CGSize(width: 400, height: 300)) != nil)
      #expect(resolved.explanation.contains("not evidence of observed ink"))
    }
    let reference = try #require(DrawingReviewGeometry.resolve(plan: nil, sourceProgram: program))
    #expect(reference.title == "Source reference")
    #expect(reference.preview.evidence?.mode == .reference)
    #expect(reference.preview.plannedStrokes == nil)
    #expect(reference.preview.geometry(in: CGSize(width: 400, height: 300)) != nil)
    #expect(DrawingReviewGeometry.resolve(plan: nil, sourceProgram: nil) == nil)
    #expect(DrawingReviewGeometry.unavailableExplanation.contains("neither an execution plan nor its source program"))
  }

  @Test("missing historical media and unreadable retained media have distinct explanations")
  func photoLimitations() {
    #expect(DrawingReviewGeometry.photographExplanation(referenceCount: nil, failed: false)
      .contains("no retained photograph references"))
    #expect(DrawingReviewGeometry.photographExplanation(referenceCount: 0, failed: false)
      .contains("No photograph was retained for this stage"))
    #expect(DrawingReviewGeometry.photographExplanation(referenceCount: 1, failed: true)
      .contains("could not be loaded"))
  }
}
