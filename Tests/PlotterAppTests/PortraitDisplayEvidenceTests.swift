import Foundation
import PlotterModel
import Testing

@testable import PlotterApp

@Suite("Portrait display evidence", .serialized)
@MainActor
struct PortraitDisplayEvidenceTests {
  @Test("legacy presentation reencodes without added fields or a renderer revision change")
  func legacyEncoding() throws {
    let bytes = Data(#"{"drawingHeightMM":73,"inkWidthIsMeasured":false,"inkWidthMM":0.3,"objective":"screenAesthetic","prompt":"Legacy preview","rendererRevision":"portrait-preview-v1"}"#.utf8)
    let context = try JSONDecoder().decode(PortraitPresentationContext.self, from: bytes)
    #expect(context.displayEvidence == nil)
    #expect(context.rendererRevision == "portrait-preview-v1")
    #expect(try PortraitCandidateCoding.encoder().encode(context) == bytes)
    #expect(try PortraitCandidateCoding.encoder().encode(PortraitPresentationContext(
      drawingHeightMM: 73, inkWidthMM: 0.3, prompt: "Legacy preview")) == bytes)
  }

  @Test("reference ratings remain usable before projection and retain explicit normalization provenance")
  func unplacedRating() async throws {
    let candidate = try portraitPersistenceCandidate()
    let evidence = try PortraitDisplayEvidence(mode: .reference,
      programContentHash: candidate.program.contentHash.description, widthSource: .nominalProgram)
    let context = try PortraitPresentationContext(inkWidthMM: 0.8, displayEvidence: evidence)
    let model = PortraitStudioModel()
    #expect(model.sketches.retain(candidate: candidate, reason: .shortlisted) == nil)
    model.sketches.selectedID = candidate.id
    #expect(model.projectedCandidate == nil)
    #expect(model.canRateSelection)
    #expect(model.rateSelection(4, presentation: context) == nil)
    let label = try #require(model.sketches.labels.last)
    try PortraitArchiveValidation.label(label, candidate: candidate)
    #expect(label.presentation.rendererRevision == "portrait-plane-preview-v2")
    #expect(label.presentation.drawingHeightMM == 100)
    #expect(label.presentation.displayEvidence?.mode == .reference)
    let restored = try JSONDecoder().decode(PortraitLabelRevision.self,
      from: PortraitCandidateCoding.encoder().encode(label))
    #expect(restored == label)
    #expect(PortraitTrainingPresentation(restored.presentation) == PortraitTrainingPresentation(context))
    await model.shutdown()
  }

  @Test("planned presentation retains exact transform and validates candidate height and identity")
  func plannedContext() throws {
    let candidate = try portraitPersistenceCandidate()
    let placement = try DrawingPlacement(
      fieldAnchor: Point2<FieldSpace>(x: 0, y: 0), machineAnchor: Point2<MachineSpace>(x: 20, y: 30),
      uniformScale: 0.4, rotationRadians: .pi / 2)
    let region = try DrawableMachineRegion(bounds: AxisAlignedBounds<MachineSpace>(minX: 0, minY: 0, maxX: 200, maxY: 100))
    let evidence = try PortraitDisplayEvidence(mode: .planned,
      programContentHash: candidate.program.contentHash.description, region: region, placement: placement,
      planContentHash: String(repeating: "a", count: 64), widthSource: .applicableMaterial)
    let context = try PortraitPresentationContext(
      drawingHeightMM: candidate.program.fieldExtent.height * placement.uniformScale,
      inkWidthMM: 0.8, materialRevision: "measured-profile-revision", displayEvidence: evidence)
    let label = try PortraitLabelRevision(candidate: candidate, rating: 5, scope: .screenSketch, presentation: context)
    try PortraitArchiveValidation.label(label, candidate: candidate)
    let restored = try JSONDecoder().decode(PortraitPresentationContext.self,
      from: PortraitCandidateCoding.encoder().encode(context))
    #expect(restored == context)
    #expect(restored.displayEvidence?.placement == placement)
    #expect(restored.displayEvidence?.region == region)
    let wrongHeight = try PortraitPresentationContext(drawingHeightMM: context.drawingHeightMM + 1,
      inkWidthMM: 0.8, displayEvidence: evidence)
    #expect(throws: PortraitCandidateError.self) {
      _ = try PortraitLabelRevision(candidate: candidate, rating: 3, scope: .screenSketch, presentation: wrongHeight)
    }
    let wrongProgram = try PortraitDisplayEvidence(mode: .reference,
      programContentHash: String(repeating: "b", count: 64), widthSource: .nominalProgram)
    #expect(throws: PortraitCandidateError.self) {
      _ = try PortraitLabelRevision(candidate: candidate, rating: 3, scope: .screenSketch,
        presentation: PortraitPresentationContext(displayEvidence: wrongProgram))
    }
  }

  @Test("invalid or contradictory new evidence is rejected without treating reference size as actual")
  func invalidEvidence() throws {
    let hash = String(repeating: "a", count: 64)
    #expect(throws: PortraitCandidateError.self) {
      _ = try PortraitDisplayEvidence(mode: .planned, programContentHash: hash, widthSource: .nominalProgram)
    }
    #expect(throws: PortraitCandidateError.self) {
      _ = try PortraitDisplayEvidence(mode: .reference, programContentHash: hash,
        planContentHash: hash, widthSource: .nominalProgram)
    }
    #expect(throws: PortraitCandidateError.self) {
      _ = try PortraitDisplayEvidence(mode: .reference, programContentHash: "not-a-digest", widthSource: .nominalProgram)
    }
    let reference = try PortraitDisplayEvidence(mode: .reference, programContentHash: hash, widthSource: .nominalProgram)
    #expect(throws: PortraitCandidateError.self) {
      _ = try PortraitPresentationContext(drawingHeightMM: 150, displayEvidence: reference)
    }
    #expect(throws: PortraitCandidateError.self) {
      _ = try PortraitPresentationContext(objective: .physicalRealization, physicalAttemptID: UUID(),
        physicalRecordID: UUID(), physicalMediaSHA256s: [hash], displayEvidence: reference)
    }
    var object = try #require(JSONSerialization.jsonObject(with: PortraitCandidateCoding.encoder().encode(reference)) as? [String: Any])
    object["mode"] = "planned"
    let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    #expect(throws: PortraitCandidateError.self) {
      _ = try JSONDecoder().decode(PortraitDisplayEvidence.self, from: tampered)
    }
  }
}
