import Foundation
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Sparse tip calibration coordinator")
struct SparseTipCalibrationCoordinatorTests {
  @Test("one batch collects five clicks on one frozen frame in arbitrary order")
  func frozenFrameBatchClicks() throws {
    #expect(SparseTipCalibrationCoordinator.orderedPositions == [
      .center, .negativeX, .positiveY, .positiveX, .negativeY,
    ])
    var coordinator = SparseTipCalibrationCoordinator()
    let frame = try exactFrame(id: "frozen-center", hash: "a")
    let revision = PresentationTransformRevision()
    let points = try [
      Point2<CameraPixelSpace>(x: 500, y: 240),
      Point2<CameraPixelSpace>(x: 320, y: 80),
      Point2<CameraPixelSpace>(x: 140, y: 240),
      Point2<CameraPixelSpace>(x: 320, y: 400),
      Point2<CameraPixelSpace>(x: 320, y: 240),
    ]

    try coordinator.beginBatch()
    #expect(coordinator.phase == .drawingBatch)
    try coordinator.beginReveal()
    #expect(coordinator.phase == .revealingBatch)
    try coordinator.awaitFrozenClicks(frame: frame)
    for point in points {
      try coordinator.select(ActionSurfacePointSelection(
        frame: frame,
        point: point,
        presentationTransformRevision: revision
      ))
    }
    #expect(coordinator.phase == .fittingModel)
    #expect(coordinator.collectedClickPoints == points)
    #expect(coordinator.collectedClickCount == 5)
    #expect(coordinator.pendingFrame == frame)

    let recovered = coordinator.recoverFromFittingFailure()
    #expect(recovered)
    #expect(coordinator.phase == .awaitingFrozenClicks(frame.frameID))
    #expect(coordinator.collectedClickPoints == points)
    #expect(coordinator.pendingFrame == frame)

    try coordinator.undoLastClick()
    #expect(coordinator.phase == .awaitingFrozenClicks(frame.frameID))
    #expect(coordinator.collectedClickPoints == Array(points.dropLast()))
    #expect(coordinator.pendingFrame == frame)
    try coordinator.clearClicks()
    #expect(coordinator.collectedClickPoints.isEmpty)
    #expect(coordinator.pendingFrame == frame)
  }

  @Test("selection rejects stale exact-frame provenance")
  func staleFrameRejected() throws {
    var coordinator = SparseTipCalibrationCoordinator()
    let frozen = try exactFrame(id: "frozen", hash: "b")
    let stale = try exactFrame(id: "stale", hash: "c")
    try coordinator.beginBatch()
    try coordinator.beginReveal()
    try coordinator.awaitFrozenClicks(frame: frozen)

    #expect(throws: SparseTipCalibrationCoordinatorError.staleSelection) {
      try coordinator.select(ActionSurfacePointSelection(
        frame: stale,
        point: Point2(x: 1, y: 1),
        presentationTransformRevision: PresentationTransformRevision()
      ))
    }
    #expect(coordinator.phase == .awaitingFrozenClicks(frozen.frameID))
  }

  @Test("ambiguous circle blacklists one location and never authorizes redraw")
  func ambiguityBlacklistsWithoutRedraw() throws {
    var coordinator = SparseTipCalibrationCoordinator()
    try coordinator.beginBatch()
    let location = BlacklistedToolContactLocation(
      calibrationPosition: .center,
      machinePosition: try MachinePosition(x: 0, y: 0),
      markRadiusMM: 2,
      paperContactPlane: PaperContactPlaneRevision(
        rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000903")!
      )
    )
    coordinator.blacklistPossibleInk(at: location, reason: "Pen Up completion unknown")
    #expect(coordinator.blacklistedPositions == [.center])
    #expect(throws: SparseTipCalibrationCoordinatorError.invalidTransition) {
      try coordinator.beginBatch()
    }

    var restored = SparseTipCalibrationCoordinator(
      blacklistedLocations: coordinator.blacklistedLocations
    )
    #expect(restored.blacklistedLocations == [location])
    #expect(throws: SparseTipCalibrationCoordinatorError.invalidTransition) {
      try restored.beginBatch()
    }
  }
}

private func exactFrame(id: String, hash: Character) throws -> ExactTipCalibrationFrame {
  let source = FrameSourceIdentity.simulated
  let optical = try CameraOpticalConfigurationIdentity(
    source: source,
    sensorFormat: "coordinator-test",
    width: 640,
    height: 480,
    pixelFormat: .bgra8,
    orientation: .up,
    mirrored: false,
    digitalZoomFactor: 1,
    lensIdentity: "fixed-lens",
    focusConfiguration: "fixed-focus",
    mountRevision: UUID(uuidString: "00000000-0000-0000-0000-000000000901")!,
    reframingRevision: UUID(uuidString: "00000000-0000-0000-0000-000000000902")!
  )
  return try ExactTipCalibrationFrame(
    frameID: FrameID(rawValue: id),
    frameSHA256: String(repeating: hash, count: 64),
    source: source,
    captureSessionID: CameraCaptureSessionID(),
    opticalConfiguration: optical,
    cameraConfigurationID: CameraConfigurationID(),
    captureNanoseconds: 100,
    width: 640,
    height: 480,
    pixelFormat: .bgra8
  )
}
