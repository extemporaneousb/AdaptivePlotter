import Foundation
@testable import PlotterRuntime
import Testing

@Suite("Paper instance and contact-plane semantics")
struct PaperRevisionSemanticsTests {
  @Test("sheet replacement retains the plane only through an explicit declaration")
  func explicitSamePlaneReplacement() throws {
    let plane = PaperContactPlaneRevision()
    let previous = PaperRevisionContext(
      instance: PaperInstanceRevision(),
      contactPlane: plane
    )

    let transition = try PaperReplacementTransition(
      previous: previous,
      newPaperInstance: PaperInstanceRevision(),
      contactPlaneDeclaration: .explicitlyUnchanged(plane)
    )

    #expect(transition.current.instance != previous.instance)
    #expect(transition.current.contactPlane == plane)
    #expect(transition.tipCalibrationApplicabilityChange == nil)
  }

  @Test("changed plane emits the existing calibration-quarantining change")
  func changedPlaneReplacement() throws {
    let previous = PaperRevisionContext(
      instance: PaperInstanceRevision(),
      contactPlane: PaperContactPlaneRevision()
    )
    let changedPlane = PaperContactPlaneRevision()
    let transition = try PaperReplacementTransition(
      previous: previous,
      newPaperInstance: PaperInstanceRevision(),
      contactPlaneDeclaration: .changed(to: changedPlane)
    )

    guard case .paperContactPlaneChanged(let revision) =
      transition.tipCalibrationApplicabilityChange
    else {
      Issue.record("changed contact plane must route through calibration applicability")
      return
    }
    #expect(revision == changedPlane)
  }

  @Test("contradictory replacement declarations are rejected")
  func contradictoryReplacementDeclarations() {
    let plane = PaperContactPlaneRevision()
    let paper = PaperInstanceRevision()
    let previous = PaperRevisionContext(instance: paper, contactPlane: plane)

    #expect(throws: PaperReplacementTransitionError.paperInstanceDidNotChange) {
      try PaperReplacementTransition(
        previous: previous,
        newPaperInstance: paper,
        contactPlaneDeclaration: .explicitlyUnchanged(plane)
      )
    }
    #expect(
      throws: PaperReplacementTransitionError.unchangedDeclarationDoesNotMatchCurrentPlane
    ) {
      try PaperReplacementTransition(
        previous: previous,
        newPaperInstance: PaperInstanceRevision(),
        contactPlaneDeclaration: .explicitlyUnchanged(PaperContactPlaneRevision())
      )
    }
    #expect(throws: PaperReplacementTransitionError.changedDeclarationReusesCurrentPlane) {
      try PaperReplacementTransition(
        previous: previous,
        newPaperInstance: PaperInstanceRevision(),
        contactPlaneDeclaration: .changed(to: plane)
      )
    }
  }

  @Test("new overlay identities are semantic and Codable")
  func semanticOverlayKinds() throws {
    let kinds: [CameraOverlayKind] = [
      .calibratedDrawableRegion,
      .paperCoverage,
      .predictedContactPoint,
      .intendedPath,
    ]
    let decoded = try JSONDecoder().decode(
      [CameraOverlayKind].self,
      from: JSONEncoder().encode(kinds)
    )
    #expect(decoded == kinds)
  }
}
