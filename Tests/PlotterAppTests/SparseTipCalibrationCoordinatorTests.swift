import Foundation
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Sparse tip calibration coordinator")
struct SparseTipCalibrationCoordinatorTests {
  @Test("workflow uses the fixed five-position order and re-clicks one frozen frame")
  func frozenFrameReClick() throws {
    #expect(SparseTipCalibrationCoordinator.orderedPositions == [
      .center, .negativeX, .positiveY, .positiveX, .negativeY,
    ])
    var coordinator = SparseTipCalibrationCoordinator()
    let frame = try exactFrame(id: "frozen-center", hash: "a")
    let revision = PresentationTransformRevision()
    let point = try Point2<CameraPixelSpace>(x: 320, y: 240)

    #expect(try coordinator.prepareNextMark() == .center)
    try coordinator.beganMark(at: .center)
    try coordinator.beganReveal(from: .center, to: MachinePosition(x: 90, y: 0))
    try coordinator.awaitFrozenClick(for: .center, frame: frame)
    try coordinator.select(ActionSurfacePointSelection(
      frame: frame,
      point: point,
      presentationTransformRevision: revision
    ))
    #expect(coordinator.phase == .reviewingClick(.center, frame.frameID))

    try coordinator.reClickSameFrame()
    #expect(coordinator.phase == .awaitingFrozenClick(.center, frame.frameID))
    #expect(coordinator.pendingFrame == frame)
  }

  @Test("selection rejects stale exact-frame provenance")
  func staleFrameRejected() throws {
    var coordinator = SparseTipCalibrationCoordinator()
    let frozen = try exactFrame(id: "frozen", hash: "b")
    let stale = try exactFrame(id: "stale", hash: "c")
    _ = try coordinator.prepareNextMark()
    try coordinator.beganMark(at: .center)
    try coordinator.beganReveal(from: .center, to: MachinePosition(x: 90, y: 0))
    try coordinator.awaitFrozenClick(for: .center, frame: frozen)

    #expect(throws: SparseTipCalibrationCoordinatorError.staleSelection) {
      try coordinator.select(ActionSurfacePointSelection(
        frame: stale,
        point: Point2(x: 1, y: 1),
        presentationTransformRevision: PresentationTransformRevision()
      ))
    }
    #expect(coordinator.phase == .awaitingFrozenClick(.center, frozen.frameID))
  }

  @Test("ambiguous circle blacklists one location and never authorizes redraw")
  func ambiguityBlacklistsWithoutRedraw() throws {
    var coordinator = SparseTipCalibrationCoordinator()
    #expect(try coordinator.prepareNextMark() == .center)
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
    #expect(coordinator.nextPosition == .negativeX)
    #expect(throws: SparseTipCalibrationCoordinatorError.invalidTransition) {
      _ = try coordinator.prepareNextMark()
    }

    var restored = SparseTipCalibrationCoordinator(
      blacklistedLocations: coordinator.blacklistedLocations
    )
    #expect(restored.blacklistedLocations == [location])
    #expect(throws: SparseTipCalibrationCoordinatorError.invalidTransition) {
      _ = try restored.prepareNextMark()
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
