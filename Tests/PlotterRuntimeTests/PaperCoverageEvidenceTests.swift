import Foundation
import PlotterModel
@testable import PlotterRuntime
import Testing

@Suite("Paper coverage evidence")
struct PaperCoverageEvidenceTests {
  @Test("coverage remains exact-frame paper evidence")
  func exactFrameValidation() throws {
    let paper = PaperRevisionContext(
      instance: PaperInstanceRevision(),
      contactPlane: PaperContactPlaneRevision()
    )
    let frame = try coverageFrame()
    let observation = try PaperCoverageObservation(
      paper: paper,
      source: .simulated,
      frame: ExactFrameProvenance(frame: frame),
      polygon: try coveragePolygon(),
      method: .visionMeasured,
      observedAt: RuntimeTimestamp(monotonicNanoseconds: 101),
      algorithmRevision: "paper-coverage-v1"
    )

    #expect(observation.validation(against: PaperCoverageValidationContext(
      paper: paper,
      source: .simulated,
      frameID: frame.id,
      cameraConfigurationID: frame.cameraConfigurationID
    )) == .valid)

    guard case .rejected(let reasons) = observation.validation(
      against: PaperCoverageValidationContext(
        paper: PaperRevisionContext(
          instance: PaperInstanceRevision(),
          contactPlane: PaperContactPlaneRevision()
        ),
        source: .live(CameraDeviceID(rawValue: "different-camera")),
        frameID: FrameID(),
        cameraConfigurationID: CameraConfigurationID()
      )
    ) else {
      Issue.record("incompatible paper/frame context must be rejected")
      return
    }
    #expect(Set(reasons) == Set(PaperCoverageValidationRejection.allMismatchReasons))
  }

  @Test("coverage polygon must be nondegenerate and inside the exact frame")
  func invalidCoverageRejected() throws {
    let frame = try coverageFrame()
    let paper = PaperRevisionContext(
      instance: PaperInstanceRevision(),
      contactPlane: PaperContactPlaneRevision()
    )
    let line = [
      try Point2<CameraPixelSpace>(x: 1, y: 1),
      try Point2<CameraPixelSpace>(x: 2, y: 2),
      try Point2<CameraPixelSpace>(x: 3, y: 3),
    ]
    #expect(throws: PaperCoverageObservationError.invalidPolygon) {
      try PaperCoverageObservation(
        paper: paper,
        source: .simulated,
        frame: ExactFrameProvenance(frame: frame),
        polygon: line,
        method: .operatorAccepted,
        observedAt: RuntimeTimestamp(monotonicNanoseconds: 101),
        algorithmRevision: "paper-coverage-v1"
      )
    }

    var outside = try coveragePolygon()
    outside[0] = try Point2(x: 100, y: 1)
    #expect(throws: PaperCoverageObservationError.pointOutsideFrame) {
      try PaperCoverageObservation(
        paper: paper,
        source: .simulated,
        frame: ExactFrameProvenance(frame: frame),
        polygon: outside,
        method: .operatorAccepted,
        observedAt: RuntimeTimestamp(monotonicNanoseconds: 101),
        algorithmRevision: "paper-coverage-v1"
      )
    }
  }
}

private extension PaperCoverageValidationRejection {
  static let allMismatchReasons: [Self] = [
    .paperInstanceMismatch,
    .paperContactPlaneMismatch,
    .sourceMismatch,
    .frameMismatch,
    .cameraConfigurationMismatch,
  ]
}

private func coveragePolygon() throws -> [Point2<CameraPixelSpace>] {
  [
    try Point2(x: 1, y: 1),
    try Point2(x: 8, y: 1),
    try Point2(x: 8, y: 6),
    try Point2(x: 1, y: 6),
  ]
}

private func coverageFrame() throws -> StampedFrame {
  try StampedFrame(
    id: FrameID(rawValue: "paper-frame"),
    sequence: 1,
    captureNanoseconds: 100,
    cameraConfigurationID: CameraConfigurationID(),
    width: 10,
    height: 8,
    rowBytes: 10,
    pixelFormat: .gray8,
    bytes: OwnedFrameBytes(Array(repeating: 255, count: 80))
  )
}
