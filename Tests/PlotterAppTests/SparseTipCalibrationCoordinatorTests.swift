import Foundation
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Sparse tip calibration coordinator")
struct SparseTipCalibrationCoordinatorTests {
  @Test("one batch hands one frozen frame to the episode-owned point authority")
  func frozenFrameBatchBoundary() throws {
    #expect(
      SparseTipCalibrationCoordinator.orderedPositions == [
        .negativeX, .positiveY, .positiveX, .negativeY,
      ])
    var coordinator = SparseTipCalibrationCoordinator()
    let frame = try exactFrame(id: "frozen-center", hash: "a")
    try coordinator.beginBatch()
    #expect(coordinator.phase == .drawingBatch)
    try coordinator.beginReveal()
    #expect(coordinator.phase == .revealingBatch)
    try coordinator.awaitFrozenClicks(frame: frame)
    #expect(coordinator.phase == .awaitingFrozenClicks(frame.frameID))
    try coordinator.beginFitting()
    #expect(coordinator.phase == .fittingModel)
    #expect(coordinator.pendingFrame == frame)

    let recovered = coordinator.recoverFromFittingFailure()
    #expect(recovered)
    #expect(coordinator.phase == .awaitingFrozenClicks(frame.frameID))
    #expect(coordinator.pendingFrame == frame)
  }

  @Test("fitting cannot begin before the workspace installs a frozen frame")
  func fittingRequiresFrozenFrame() throws {
    var coordinator = SparseTipCalibrationCoordinator()
    let frozen = try exactFrame(id: "frozen", hash: "b")
    try coordinator.beginBatch()
    try coordinator.beginReveal()
    #expect(throws: SparseTipCalibrationCoordinatorError.invalidTransition) {
      try coordinator.beginFitting()
    }
    try coordinator.awaitFrozenClicks(frame: frozen)
    #expect(coordinator.phase == .awaitingFrozenClicks(frozen.frameID))
  }

  @Test("ambiguous circle blacklists one location and never authorizes redraw")
  func ambiguityBlacklistsWithoutRedraw() throws {
    var coordinator = SparseTipCalibrationCoordinator()
    try coordinator.beginBatch()
    let location = BlacklistedToolContactLocation(
      calibrationPosition: .negativeX,
      machinePosition: try MachinePosition(x: -30, y: -30),
      markRadiusMM: 2,
      paperInstance: PaperInstanceRevision(
        rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000903")!
      )
    )
    coordinator.blacklistPossibleInk(at: location, reason: "Pen Up completion unknown")
    #expect(coordinator.blacklistedPositions == [.negativeX])
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
