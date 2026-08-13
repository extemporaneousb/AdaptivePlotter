import Foundation
import PlotterModel
import PlotterRuntime

enum SparseTipCalibrationCoordinatorError: Error, Equatable, Sendable {
  case invalidTransition
  case locationBlacklisted(ToolContactCalibrationPosition)
  case staleSelection
  case selectionUnavailable
  case duplicateObservation
}

enum SparseTipCalibrationPhase: Hashable, Sendable {
  case idle
  case preparingMark(ToolContactCalibrationPosition)
  case tapping(ToolContactCalibrationPosition)
  case revealing(
    mark: ToolContactCalibrationPosition,
    reveal: ToolContactCalibrationPosition
  )
  case awaitingFrozenClick(ToolContactCalibrationPosition, FrameID)
  case reviewingClick(ToolContactCalibrationPosition, FrameID)
  case fittingCandidates
  case reviewingFinalProposal(TipCameraModelForm)
  case accepted
  case possibleInkBlacklisted(BlacklistedToolContactLocation, String)
  case holdoutFailed(String)
  case rejected(String)
}

struct BlacklistedToolContactLocation: Hashable, Sendable {
  let calibrationPosition: ToolContactCalibrationPosition
  let machinePosition: MachinePosition
  let paperContactPlane: PaperContactPlaneRevision
}

/// Pure workflow state. It owns ordering and no-redraw transitions; physical
/// motion, generic Pen Down/Up, exact capture, and artifact commits stay with
/// `OperatorWorkspace` and the existing runtime owners.
struct SparseTipCalibrationCoordinator: Hashable, Sendable {
  static let orderedPositions: [ToolContactCalibrationPosition] = [
    .center, .negativeX, .positiveY, .positiveX, .negativeY,
  ]

  private(set) var phase: SparseTipCalibrationPhase = .idle
  private(set) var acceptedObservations: [AcceptedToolContactObservation] = []
  private(set) var blacklistedLocations: Set<BlacklistedToolContactLocation>
  private(set) var pendingFrame: ExactTipCalibrationFrame?
  private(set) var selectedPoint: Point2<CameraPixelSpace>?
  private(set) var selectedPresentationRevision: PresentationTransformRevision?
  private(set) var proposal: TipCalibrationModelSelection?

  init(blacklistedLocations: Set<BlacklistedToolContactLocation> = []) {
    self.blacklistedLocations = blacklistedLocations
    if let location = blacklistedLocations.first {
      phase = .possibleInkBlacklisted(
        location,
        "Possible ink already blacklists this exact machine position on the current paper."
      )
    }
  }

  var blacklistedPositions: Set<ToolContactCalibrationPosition> {
    Set(blacklistedLocations.map(\.calibrationPosition))
  }

  var selectedPresentationRevisionForCommit: PresentationTransformRevision? {
    selectedPresentationRevision
  }

  var nextPosition: ToolContactCalibrationPosition? {
    Self.orderedPositions.first { position in
      !acceptedObservations.contains { $0.observation.calibrationPosition == position }
        && !blacklistedPositions.contains(position)
    }
  }

  mutating func prepareNextMark() throws -> ToolContactCalibrationPosition {
    guard case .idle = phase, let position = nextPosition else {
      throw SparseTipCalibrationCoordinatorError.invalidTransition
    }
    guard !blacklistedPositions.contains(position) else {
      throw SparseTipCalibrationCoordinatorError.locationBlacklisted(position)
    }
    phase = .preparingMark(position)
    return position
  }

  mutating func beganTap(at position: ToolContactCalibrationPosition) throws {
    guard phase == .preparingMark(position), !blacklistedPositions.contains(position) else {
      throw SparseTipCalibrationCoordinatorError.invalidTransition
    }
    phase = .tapping(position)
  }

  mutating func beganReveal(
    from mark: ToolContactCalibrationPosition,
    to reveal: ToolContactCalibrationPosition
  ) throws {
    guard phase == .tapping(mark) else {
      throw SparseTipCalibrationCoordinatorError.invalidTransition
    }
    phase = .revealing(mark: mark, reveal: reveal)
  }

  mutating func awaitFrozenClick(
    for mark: ToolContactCalibrationPosition,
    frame: ExactTipCalibrationFrame
  ) throws {
    guard case .revealing(let activeMark, _) = phase, activeMark == mark else {
      throw SparseTipCalibrationCoordinatorError.invalidTransition
    }
    pendingFrame = frame
    selectedPoint = nil
    selectedPresentationRevision = nil
    phase = .awaitingFrozenClick(mark, frame.frameID)
  }

  mutating func select(_ selection: ActionSurfacePointSelection) throws {
    guard case .awaitingFrozenClick(let position, let frameID) = phase,
      let pendingFrame,
      frameID == pendingFrame.frameID,
      selection.frame == pendingFrame,
      selection.presentationTransformRevision == selectedPresentationRevision
        || selectedPresentationRevision == nil
    else { throw SparseTipCalibrationCoordinatorError.staleSelection }
    selectedPoint = selection.point
    selectedPresentationRevision = selection.presentationTransformRevision
    phase = .reviewingClick(position, frameID)
  }

  mutating func reClickSameFrame() throws {
    guard case .reviewingClick(let position, let frameID) = phase,
      pendingFrame?.frameID == frameID
    else { throw SparseTipCalibrationCoordinatorError.invalidTransition }
    selectedPoint = nil
    selectedPresentationRevision = nil
    phase = .awaitingFrozenClick(position, frameID)
  }

  mutating func acceptObservation(_ observation: AcceptedToolContactObservation) throws {
    guard case .reviewingClick(let position, let frameID) = phase,
      observation.observation.calibrationPosition == position,
      observation.observation.postRevealSelectionFrame.frameID == frameID,
      observation.observation.click.point == selectedPoint,
      observation.observation.click.presentationTransformRevision
        == selectedPresentationRevision,
      !acceptedObservations.contains(where: {
        $0.observation.calibrationPosition == position
      })
    else { throw SparseTipCalibrationCoordinatorError.duplicateObservation }
    acceptedObservations.append(observation)
    pendingFrame = nil
    selectedPoint = nil
    selectedPresentationRevision = nil
    phase = acceptedObservations.count == Self.orderedPositions.count
      ? .fittingCandidates : .idle
  }

  mutating func blacklistPossibleInk(
    at location: BlacklistedToolContactLocation,
    reason: String
  ) {
    blacklistedLocations.insert(location)
    pendingFrame = nil
    selectedPoint = nil
    selectedPresentationRevision = nil
    phase = .possibleInkBlacklisted(location, reason)
  }

  mutating func resetBeforeInkFailure() {
    pendingFrame = nil
    selectedPoint = nil
    selectedPresentationRevision = nil
    phase = .idle
  }

  mutating func stageProposal(
    capCameraFromMachine: AffineTransform2<MachineSpace, CameraPixelSpace>,
    maximumHoldoutResidualPixels: Double
  ) throws -> TipCalibrationModelSelection {
    guard case .fittingCandidates = phase else {
      throw SparseTipCalibrationCoordinatorError.invalidTransition
    }
    do {
      let selection = try TipCalibrationModelSelection.selectSmallestPassingModel(
        acceptedObservations: acceptedObservations,
        capCameraFromMachine: capCameraFromMachine,
        maximumHoldoutResidualPixels: maximumHoldoutResidualPixels
      )
      proposal = selection
      phase = .reviewingFinalProposal(selection.modelForm)
      return selection
    } catch {
      phase = .holdoutFailed(String(describing: error))
      throw error
    }
  }

  mutating func markAccepted() throws {
    guard case .reviewingFinalProposal = phase, proposal != nil else {
      throw SparseTipCalibrationCoordinatorError.invalidTransition
    }
    phase = .accepted
  }

  mutating func markCheckpointRevalidated() {
    pendingFrame = nil
    selectedPoint = nil
    selectedPresentationRevision = nil
    proposal = nil
    phase = .accepted
  }

  mutating func markRejected(reason: String) throws {
    guard case .reviewingFinalProposal = phase, proposal != nil,
      !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw SparseTipCalibrationCoordinatorError.invalidTransition }
    proposal = nil
    phase = .rejected(reason)
  }
}
