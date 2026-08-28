import Foundation
import PlotterModel
import PlotterRuntime

enum SparseTipCalibrationCoordinatorError: Error, Equatable, Sendable {
  case invalidTransition
  case duplicateObservation
}

enum SparseTipCalibrationPhase: Hashable, Sendable {
  case idle
  case drawingBatch
  case revealingBatch
  case awaitingFrozenClicks(FrameID)
  case fittingModel
  case reviewingModel(TipCameraModelForm)
  case committingModel(TipCameraModelForm)
  case accepted
  case possibleInkBlacklisted(BlacklistedToolContactLocation, String)
}

struct BlacklistedToolContactLocation: Hashable, Sendable {
  let calibrationPosition: ToolContactCalibrationPosition
  /// Center of the possible-ink circular mark, not an asserted point contact.
  let machinePosition: MachinePosition
  let markRadiusMM: Double
  /// Possible ink belongs to one replaceable sheet, not to every sheet that
  /// shares the same calibrated contact plane.
  let paperInstance: PaperInstanceRevision
}

/// Pure Exercise 1.4 workflow state. One batch owns all physical marks, one final
/// frame owns all clicks, and model construction follows the atomic four-click
/// association performed by the workspace.
struct SparseTipCalibrationCoordinator: Hashable, Sendable {
  static let orderedPositions = ToolContactCalibrationPosition.sparseTipCornerPositions

  private(set) var phase: SparseTipCalibrationPhase = .idle
  private(set) var acceptedObservations: [AcceptedToolContactObservation] = []
  private(set) var blacklistedLocations: Set<BlacklistedToolContactLocation>
  private(set) var pendingFrame: ExactTipCalibrationFrame?
  private(set) var proposal: TipCalibrationModelSelection?

  init(blacklistedLocations: Set<BlacklistedToolContactLocation> = []) {
    self.blacklistedLocations = blacklistedLocations
    if let location = blacklistedLocations.first {
      phase = .possibleInkBlacklisted(
        location,
        "Possible ink already excludes this exact machine position on the current paper."
      )
    }
  }

  var blacklistedPositions: Set<ToolContactCalibrationPosition> {
    Set(blacklistedLocations.map(\.calibrationPosition))
  }

  mutating func beginBatch() throws {
    guard phase == .idle, acceptedObservations.isEmpty else {
      throw SparseTipCalibrationCoordinatorError.invalidTransition
    }
    phase = .drawingBatch
  }

  mutating func beginReveal() throws {
    guard phase == .drawingBatch else {
      throw SparseTipCalibrationCoordinatorError.invalidTransition
    }
    phase = .revealingBatch
  }

  mutating func awaitFrozenClicks(frame: ExactTipCalibrationFrame) throws {
    guard phase == .revealingBatch else {
      throw SparseTipCalibrationCoordinatorError.invalidTransition
    }
    pendingFrame = frame
    phase = .awaitingFrozenClicks(frame.frameID)
  }

  mutating func beginFitting() throws {
    guard pendingFrame != nil, isAwaitingFrozenClicks else {
      throw SparseTipCalibrationCoordinatorError.invalidTransition
    }
    phase = .fittingModel
  }

  mutating func resumeFrozenClicksAfterCorrection() throws {
    guard let pendingFrame,
      phase == .fittingModel || isReviewingModel || isAwaitingFrozenClicks
    else { throw SparseTipCalibrationCoordinatorError.invalidTransition }
    acceptedObservations = []
    proposal = nil
    phase = .awaitingFrozenClicks(pendingFrame.frameID)
  }

  /// Model construction is atomic with respect to accepted observations. If it
  /// fails, keep the exact frozen frame and all four clicks available for
  /// same-frame correction instead of trapping the attempt in `fittingModel`.
  @discardableResult
  mutating func recoverFromFittingFailure() -> Bool {
    guard phase == .fittingModel,
      let pendingFrame,
      acceptedObservations.isEmpty,
      proposal == nil
    else { return false }
    phase = .awaitingFrozenClicks(pendingFrame.frameID)
    return true
  }

  mutating func acceptAssociatedObservations(
    _ observations: [AcceptedToolContactObservation],
    selectedPoints: [Point2<CameraPixelSpace>]
  ) throws {
    guard phase == .fittingModel,
      observations.count == Self.orderedPositions.count,
      observations.map({ $0.observation.calibrationPosition }) == Self.orderedPositions,
      let pendingFrame,
      observations.allSatisfy({
        $0.observation.postRevealSelectionFrame.frameID == pendingFrame.frameID
      }),
      clickPointsMatch(observations.map { $0.observation.click.point }, selectedPoints)
    else { throw SparseTipCalibrationCoordinatorError.duplicateObservation }
    acceptedObservations = observations
  }

  mutating func blacklistPossibleInk(
    at location: BlacklistedToolContactLocation,
    reason: String
  ) {
    blacklistedLocations.insert(location)
    pendingFrame = nil
    phase = .possibleInkBlacklisted(location, reason)
  }

  mutating func resetBeforeInkFailure() {
    pendingFrame = nil
    phase = .idle
  }

  mutating func stageProposal(
    capCameraFromMachine: AffineTransform2<MachineSpace, CameraPixelSpace>
  ) throws -> TipCalibrationModelSelection {
    guard phase == .fittingModel,
      acceptedObservations.count == Self.orderedPositions.count
    else { throw SparseTipCalibrationCoordinatorError.invalidTransition }
    let selection = try TipCalibrationModelSelection.fitAffineFirst(
      acceptedObservations: acceptedObservations,
      capCameraFromMachine: capCameraFromMachine
    )
    proposal = selection
    phase = .reviewingModel(selection.modelForm)
    return selection
  }

  mutating func beginCommit() throws {
    guard case .reviewingModel(let modelForm) = phase, proposal != nil else {
      throw SparseTipCalibrationCoordinatorError.invalidTransition
    }
    phase = .committingModel(modelForm)
  }

  mutating func markAccepted() throws {
    guard case .committingModel = phase, proposal != nil else {
      throw SparseTipCalibrationCoordinatorError.invalidTransition
    }
    phase = .accepted
  }

  mutating func markCheckpointRevalidated() {
    pendingFrame = nil
    proposal = nil
    phase = .accepted
  }

  private var isAwaitingFrozenClicks: Bool {
    if case .awaitingFrozenClicks = phase { return true }
    return false
  }

  private var isReviewingModel: Bool {
    if case .reviewingModel = phase { return true }
    return false
  }

  private func clickPointsMatch(
    _ lhs: [Point2<CameraPixelSpace>],
    _ rhs: [Point2<CameraPixelSpace>]
  ) -> Bool {
    func sorted(_ points: [Point2<CameraPixelSpace>]) -> [Point2<CameraPixelSpace>] {
      points.sorted { left, right in
        left.x == right.x ? left.y < right.y : left.x < right.x
      }
    }
    return sorted(lhs) == sorted(rhs)
  }
}
