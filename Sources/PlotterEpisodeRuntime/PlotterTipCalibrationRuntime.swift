import Foundation
import PlotterEpisodeModel
import PlotterModel
import PlotterRuntime

/// Identity for one operator-admitted tip-calibration operation. It is owned
/// by this runtime, rather than by a controller task or point-selection UI.
public struct PlotterTipCalibrationOperationID: RawRepresentable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

/// Immutable completed batch published by `PlotterPointSelectionRuntime`.
/// This runtime verifies and retains it; it has no click add, undo, or clear API.
public struct PlotterTipCalibrationCompletedPointSelection: Hashable, Sendable {
  public let selectionID: PlotterPointSelectionID
  public let exactFrame: PlotterExactFrameReference
  public let presentationTransformRevision: PlotterPresentationTransformRevision
  public let points: [Point2<CameraPixelSpace>]

  public init(
    selectionID: PlotterPointSelectionID,
    exactFrame: PlotterExactFrameReference,
    presentationTransformRevision: PlotterPresentationTransformRevision,
    points: [Point2<CameraPixelSpace>]
  ) {
    self.selectionID = selectionID
    self.exactFrame = exactFrame
    self.presentationTransformRevision = presentationTransformRevision
    self.points = points
  }
}

/// Exact batch the lower composition asked the point-selection owner to collect.
public struct PlotterTipCalibrationExpectedPointSelection: Hashable, Sendable {
  public let selectionID: PlotterPointSelectionID
  public let exactFrame: PlotterExactFrameReference
  public let presentationTransformRevision: PlotterPresentationTransformRevision

  public init(
    selectionID: PlotterPointSelectionID,
    exactFrame: PlotterExactFrameReference,
    presentationTransformRevision: PlotterPresentationTransformRevision
  ) {
    self.selectionID = selectionID
    self.exactFrame = exactFrame
    self.presentationTransformRevision = presentationTransformRevision
  }
}

/// Fact returned after supervised Pen-Up / mark / capture work has completed.
/// The App composition owns acquisition and persistence of these facts.
public struct PlotterTipCalibrationMarkBatchFact: Hashable, Sendable {
  public let expectedSelection: PlotterTipCalibrationExpectedPointSelection
  public let controllerEvidenceIDs: Set<String>
  public let captureEvidenceIDs: Set<String>

  public init(
    expectedSelection: PlotterTipCalibrationExpectedPointSelection,
    controllerEvidenceIDs: Set<String>,
    captureEvidenceIDs: Set<String>
  ) {
    self.expectedSelection = expectedSelection
    self.controllerEvidenceIDs = controllerEvidenceIDs
    self.captureEvidenceIDs = captureEvidenceIDs
  }
}

/// Existing authority objects are retained whole. This runtime neither fits a
/// model nor constructs a registration/checkpoint from their fields.
public struct PlotterTipCalibrationRetainedDomainEvidence: Hashable, Sendable {
  public let acceptedObservations: [AcceptedToolContactObservation]
  public let modelSelection: TipCalibrationModelSelection?
  public let proposedRegistration: TipCameraRegistration?
  public let retainedEvidenceIDs: Set<String>

  public init(
    acceptedObservations: [AcceptedToolContactObservation],
    modelSelection: TipCalibrationModelSelection?,
    proposedRegistration: TipCameraRegistration?,
    retainedEvidenceIDs: Set<String>
  ) {
    self.acceptedObservations = acceptedObservations
    self.modelSelection = modelSelection
    self.proposedRegistration = proposedRegistration
    self.retainedEvidenceIDs = retainedEvidenceIDs
  }
}

public struct BlacklistedToolContactLocation: Hashable, Sendable {
  public let calibrationPosition: ToolContactCalibrationPosition
  /// Center of a possible-ink mark, never asserted as a point contact.
  public let machinePosition: MachinePosition
  public let markRadiusMM: Double
  public let paperInstance: PaperInstanceRevision

  public init(
    calibrationPosition: ToolContactCalibrationPosition,
    machinePosition: MachinePosition,
    markRadiusMM: Double,
    paperInstance: PaperInstanceRevision
  ) {
    self.calibrationPosition = calibrationPosition
    self.machinePosition = machinePosition
    self.markRadiusMM = markRadiusMM
    self.paperInstance = paperInstance
  }
}

/// Possible ink is a terminal disposition, never a redraw or retry token.
public struct PlotterTipCalibrationPossibleInkFact: Hashable, Sendable {
  public let location: BlacklistedToolContactLocation
  public let reason: String
  public let persistenceEvidenceID: String

  public init(location: BlacklistedToolContactLocation, reason: String, persistenceEvidenceID: String) {
    self.location = location
    self.reason = reason
    self.persistenceEvidenceID = persistenceEvidenceID
  }
}

public enum PlotterTipCalibrationIntent: Hashable, Sendable {
  case beginFourMarkBatch
  case captureNewClickFrame(retainedPointCount: Int)
  case consumeCompletedPointSelection(PlotterTipCalibrationCompletedPointSelection)
  case revalidateCheckpoint
  case acceptProposal
  case rejectProposal
  case retryCommit
}

public enum PlotterTipCalibrationPhase: Hashable, Sendable {
  case idle
  case marking(PlotterTipCalibrationOperationID)
  case awaitingCompletedPointSelection(PlotterTipCalibrationExpectedPointSelection)
  case capturingNewClickFrame(
    PlotterTipCalibrationOperationID,
    PlotterTipCalibrationExpectedPointSelection
  )
  case fitting(PlotterTipCalibrationOperationID, PlotterPointSelectionID)
  case reviewingProposal
  case revalidating(PlotterTipCalibrationOperationID)
  case committing(PlotterTipCalibrationOperationID, isRetry: Bool)
  case accepted
  case rejected
  case possibleInkBlacklisted(BlacklistedToolContactLocation, String)
}

public enum PlotterTipCalibrationSubmissionOutcome: Hashable, Sendable {
  case completed
  case refused(String)
  case cancelled
  case failed(String)
}

/// The lower composition owns controller/camera effects and authority calls;
/// the runtime owns admission and all semantic transitions.
public enum PlotterTipCalibrationEffectRequest: Hashable, Sendable {
  case runFourMarkBatch(operationID: PlotterTipCalibrationOperationID)
  case captureNewClickFrame(
    operationID: PlotterTipCalibrationOperationID,
    expectedSelection: PlotterTipCalibrationExpectedPointSelection
  )
  case fitProposal(operationID: PlotterTipCalibrationOperationID, batch: PlotterTipCalibrationCompletedPointSelection)
  case revalidateCheckpoint(operationID: PlotterTipCalibrationOperationID)
  case commitProposal(operationID: PlotterTipCalibrationOperationID, isRetry: Bool)
  case rejectProposal(operationID: PlotterTipCalibrationOperationID)
}

public enum PlotterTipCalibrationEffectFact: Hashable, Sendable {
  case markBatch(PlotterTipCalibrationMarkBatchFact)
  case clickFrameReplaced(PlotterTipCalibrationExpectedPointSelection)
  case proposal(PlotterTipCalibrationRetainedDomainEvidence)
  case revalidated(TipCameraRegistration)
  case committed(TipCameraRegistration)
  case proposalRejected
  case possibleInk(PlotterTipCalibrationPossibleInkFact)
}

public enum PlotterTipCalibrationEffectResult: Hashable, Sendable {
  case completed(PlotterTipCalibrationEffectFact)
  case refused(String)
  case cancelled
  case failed(String)
}

public protocol PlotterTipCalibrationEffectPort: AnyObject, Sendable {
  func execute(_ request: PlotterTipCalibrationEffectRequest) async -> PlotterTipCalibrationEffectResult
}

public struct PlotterTipCalibrationTerminalRecord: Hashable, Sendable {
  public let operationID: PlotterTipCalibrationOperationID?
  public let intent: PlotterTipCalibrationIntent
  public let outcome: PlotterTipCalibrationSubmissionOutcome
  public let phase: PlotterTipCalibrationPhase
}

public struct PlotterTipCalibrationRuntimeSnapshot: Hashable, Sendable {
  public let admissionClosed: Bool
  public let activeOperationID: PlotterTipCalibrationOperationID?
  public let activeIntent: PlotterTipCalibrationIntent?
  public let phase: PlotterTipCalibrationPhase
  public let expectedSelection: PlotterTipCalibrationExpectedPointSelection?
  public let completedSelection: PlotterTipCalibrationCompletedPointSelection?
  public let retainedDomainEvidence: PlotterTipCalibrationRetainedDomainEvidence?
  public let acceptedRegistration: TipCameraRegistration?
  public let recoverableCheckpoint: AcceptedTipCalibrationCheckpoint?
  public let blacklistedLocations: Set<BlacklistedToolContactLocation>
  public let terminalHistory: [PlotterTipCalibrationTerminalRecord]
}

/// Pure unintegrated EA-10D scaffold. It references no App/workspace type and
/// is not itself accepted tip-calibration authority.
@MainActor
public final class PlotterTipCalibrationRuntime {
  public static let orderedPositions = ToolContactCalibrationPosition.sparseTipCornerPositions
  public static let requiredPointCount = ToolContactCalibrationPosition.sparseTipCornerPositions.count
  public static let terminalHistoryLimit = 16

  private let effectPort: any PlotterTipCalibrationEffectPort
  private var admissionClosed = false
  private var activeTask: Task<PlotterTipCalibrationEffectResult, Never>?
  private var operationSettlementWaiters: [CheckedContinuation<Void, Never>] = []
  private var terminalHistory: [PlotterTipCalibrationTerminalRecord] = []

  public private(set) var activeOperationID: PlotterTipCalibrationOperationID?
  public private(set) var activeIntent: PlotterTipCalibrationIntent?
  public private(set) var phase: PlotterTipCalibrationPhase = .idle
  public private(set) var expectedSelection: PlotterTipCalibrationExpectedPointSelection?
  public private(set) var completedSelection: PlotterTipCalibrationCompletedPointSelection?
  public private(set) var retainedDomainEvidence: PlotterTipCalibrationRetainedDomainEvidence?
  public private(set) var acceptedRegistration: TipCameraRegistration?
  public private(set) var recoverableCheckpoint: AcceptedTipCalibrationCheckpoint?
  public private(set) var blacklistedLocations: Set<BlacklistedToolContactLocation> = []

  public init(effectPort: any PlotterTipCalibrationEffectPort) { self.effectPort = effectPort }

  public var acceptedObservations: [AcceptedToolContactObservation] {
    retainedDomainEvidence?.acceptedObservations ?? []
  }

  public var proposedRegistration: TipCameraRegistration? {
    retainedDomainEvidence?.proposedRegistration
  }

  public var blacklistedPositions: Set<ToolContactCalibrationPosition> {
    Set(blacklistedLocations.map(\.calibrationPosition))
  }

  public func replaceBlacklistedLocations(_ locations: Set<BlacklistedToolContactLocation>) {
    blacklistedLocations = locations
    if let location = locations.first {
      phase = .possibleInkBlacklisted(
        location,
        "Possible ink already excludes this exact machine position on the current paper."
      )
    }
  }

  public func restoreAcceptedRegistration(_ registration: TipCameraRegistration?) {
    acceptedRegistration = registration
    if registration != nil { recoverableCheckpoint = nil }
    if registration == nil, retainedDomainEvidence == nil, expectedSelection == nil {
      phase = .idle
    } else if registration != nil {
      phase = .accepted
    }
  }

  public func installRecoverableCheckpoint(_ checkpoint: AcceptedTipCalibrationCheckpoint?) {
    recoverableCheckpoint = checkpoint
  }

  public func discardProposal() {
    retainedDomainEvidence = nil
    completedSelection = nil
    phase = expectedSelection.map { .awaitingCompletedPointSelection($0) } ?? .idle
  }

  public func resetForPaper(_ paperInstance: PaperInstanceRevision) {
    activeTask?.cancel()
    activeTask = nil
    activeOperationID = nil
    activeIntent = nil
    expectedSelection = nil
    completedSelection = nil
    retainedDomainEvidence = nil
    acceptedRegistration = nil
    recoverableCheckpoint = nil
    blacklistedLocations = blacklistedLocations.filter { $0.paperInstance == paperInstance }
    if let location = blacklistedLocations.first {
      phase = .possibleInkBlacklisted(
        location,
        "Possible ink already excludes this exact machine position on the current paper."
      )
    } else {
      phase = .idle
    }
  }

  @discardableResult
  public func submit(_ intent: PlotterTipCalibrationIntent) async -> PlotterTipCalibrationSubmissionOutcome {
    guard !admissionClosed else { return .cancelled }
    guard activeTask == nil else {
      return recordRefusal(intent, "Pen-tip calibration already has an active operation.")
    }
    guard validatesAdmission(intent) else { return recordRefusal(intent, refusalReason(for: intent)) }

    let operationID = PlotterTipCalibrationOperationID()
    activeOperationID = operationID
    activeIntent = intent
    defer { finishActiveOperation(operationID: operationID) }
    phase = phaseForAdmission(intent, operationID: operationID)
    let request = request(for: intent, operationID: operationID)
    let task: Task<PlotterTipCalibrationEffectResult, Never> = Task { @MainActor [weak self, effectPort] in
      guard let self,
        !Task.isCancelled,
        !self.admissionClosed,
        self.activeOperationID == operationID
      else { return .cancelled }
      return await effectPort.execute(request)
    }
    activeTask = task
    let result = await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })

    guard activeOperationID == operationID, activeIntent == intent, !admissionClosed else {
      if admissionClosed, activeOperationID == operationID, activeIntent == intent {
        record(operationID: operationID, intent: intent, outcome: .cancelled)
      }
      return .cancelled
    }
    let outcome = apply(result, for: intent)
    record(operationID: operationID, intent: intent, outcome: outcome)
    return outcome
  }

  /// Close admission before cancelling and joining the exact active task.
  public func stop() async { await closeAdmission() }
  public func shutdown() async { await closeAdmission() }

  public func snapshot() -> PlotterTipCalibrationRuntimeSnapshot {
    PlotterTipCalibrationRuntimeSnapshot(
      admissionClosed: admissionClosed,
      activeOperationID: activeOperationID,
      activeIntent: activeIntent,
      phase: phase,
      expectedSelection: expectedSelection,
      completedSelection: completedSelection,
      retainedDomainEvidence: retainedDomainEvidence,
      acceptedRegistration: acceptedRegistration,
      recoverableCheckpoint: recoverableCheckpoint,
      blacklistedLocations: blacklistedLocations,
      terminalHistory: terminalHistory
    )
  }

  private func validatesAdmission(_ intent: PlotterTipCalibrationIntent) -> Bool {
    switch intent {
    case .beginFourMarkBatch: phase == .idle
    case .captureNewClickFrame(let retainedPointCount):
      retainedPointCount == 0
        && expectedSelection.map { phase == .awaitingCompletedPointSelection($0) } == true
    case .consumeCompletedPointSelection(let batch): validates(batch)
    case .revalidateCheckpoint:
      recoverableCheckpoint != nil && activeOperationID == nil
    case .acceptProposal, .retryCommit:
      retainedDomainEvidence?.proposedRegistration != nil && phase == .reviewingProposal
    case .rejectProposal: retainedDomainEvidence != nil && phase == .reviewingProposal
    }
  }

  private func request(
    for intent: PlotterTipCalibrationIntent,
    operationID: PlotterTipCalibrationOperationID
  ) -> PlotterTipCalibrationEffectRequest {
    switch intent {
    case .beginFourMarkBatch: .runFourMarkBatch(operationID: operationID)
    case .captureNewClickFrame:
      .captureNewClickFrame(
        operationID: operationID,
        expectedSelection: expectedSelection!
      )
    case .consumeCompletedPointSelection(let batch): .fitProposal(operationID: operationID, batch: batch)
    case .revalidateCheckpoint: .revalidateCheckpoint(operationID: operationID)
    case .acceptProposal: .commitProposal(operationID: operationID, isRetry: false)
    case .retryCommit: .commitProposal(operationID: operationID, isRetry: true)
    case .rejectProposal: .rejectProposal(operationID: operationID)
    }
  }

  private func phaseForAdmission(
    _ intent: PlotterTipCalibrationIntent,
    operationID: PlotterTipCalibrationOperationID
  ) -> PlotterTipCalibrationPhase {
    switch intent {
    case .beginFourMarkBatch: .marking(operationID)
    case .captureNewClickFrame:
      .capturingNewClickFrame(operationID, expectedSelection!)
    case .consumeCompletedPointSelection(let batch): .fitting(operationID, batch.selectionID)
    case .revalidateCheckpoint: .revalidating(operationID)
    case .acceptProposal: .committing(operationID, isRetry: false)
    case .retryCommit: .committing(operationID, isRetry: true)
    case .rejectProposal: .reviewingProposal
    }
  }

  private func apply(
    _ result: PlotterTipCalibrationEffectResult,
    for intent: PlotterTipCalibrationIntent
  ) -> PlotterTipCalibrationSubmissionOutcome {
    switch result {
    case .refused(let reason): phase = stablePhase(after: intent); return .refused(reason)
    case .cancelled: phase = stablePhase(after: intent); return .cancelled
    case .failed(let detail): phase = stablePhase(after: intent); return .failed(detail)
    case .completed(let fact): return applyCompletedFact(fact, for: intent)
    }
  }

  private func applyCompletedFact(
    _ fact: PlotterTipCalibrationEffectFact,
    for intent: PlotterTipCalibrationIntent
  ) -> PlotterTipCalibrationSubmissionOutcome {
    if case .possibleInk(let possibleInk) = fact {
      blacklistedLocations.insert(possibleInk.location)
      phase = .possibleInkBlacklisted(possibleInk.location, possibleInk.reason)
      return .completed
    }
    switch (intent, fact) {
    case (.beginFourMarkBatch, .markBatch(let markBatch)):
      expectedSelection = markBatch.expectedSelection
      completedSelection = nil
      retainedDomainEvidence = nil
      phase = .awaitingCompletedPointSelection(markBatch.expectedSelection)
      return .completed
    case (.captureNewClickFrame, .clickFrameReplaced(let replacement)):
      guard let prior = expectedSelection,
        replacement.selectionID != prior.selectionID,
        replacement.exactFrame.captureNanoseconds > prior.exactFrame.captureNanoseconds
      else { return factMismatch(intent) }
      expectedSelection = replacement
      completedSelection = nil
      retainedDomainEvidence = nil
      phase = .awaitingCompletedPointSelection(replacement)
      return .completed
    case (.consumeCompletedPointSelection(let batch), .proposal(let evidence)):
      guard validates(batch) else { return factMismatch(intent) }
      completedSelection = batch
      retainedDomainEvidence = evidence
      phase = .reviewingProposal
      return .completed
    case (.revalidateCheckpoint, .revalidated(let registration)):
      acceptedRegistration = registration
      recoverableCheckpoint = nil
      expectedSelection = nil
      completedSelection = nil
      retainedDomainEvidence = nil
      phase = .accepted
      return .completed
    case (.acceptProposal, .committed(let registration)), (.retryCommit, .committed(let registration)):
      acceptedRegistration = registration
      recoverableCheckpoint = nil
      expectedSelection = nil
      completedSelection = nil
      retainedDomainEvidence = nil
      phase = .accepted
      return .completed
    case (.rejectProposal, .proposalRejected):
      retainedDomainEvidence = nil
      phase = .rejected
      return .completed
    default: return factMismatch(intent)
    }
  }

  private func factMismatch(_ intent: PlotterTipCalibrationIntent) -> PlotterTipCalibrationSubmissionOutcome {
    phase = stablePhase(after: intent)
    return .failed("Tip-calibration lower effect returned a fact that does not satisfy the admitted intent.")
  }

  private func stablePhase(after intent: PlotterTipCalibrationIntent) -> PlotterTipCalibrationPhase {
    switch intent {
    case .beginFourMarkBatch: .idle
    case .captureNewClickFrame:
      expectedSelection.map { .awaitingCompletedPointSelection($0) } ?? .idle
    case .consumeCompletedPointSelection: expectedSelection.map { .awaitingCompletedPointSelection($0) } ?? .idle
    case .revalidateCheckpoint: acceptedRegistration == nil ? .idle : .accepted
    case .acceptProposal, .retryCommit, .rejectProposal:
      retainedDomainEvidence == nil ? .idle : .reviewingProposal
    }
  }

  private func validates(_ batch: PlotterTipCalibrationCompletedPointSelection) -> Bool {
    guard let expectedSelection else { return false }
    return batch.selectionID == expectedSelection.selectionID
      && batch.exactFrame == expectedSelection.exactFrame
      && batch.presentationTransformRevision == expectedSelection.presentationTransformRevision
      && batch.points.count == Self.requiredPointCount
  }

  private func refusalReason(for intent: PlotterTipCalibrationIntent) -> String {
    switch intent {
    case .captureNewClickFrame(let retainedPointCount):
      retainedPointCount == 0
        ? "A new click frame requires the current exact point-selection request."
        : "Clear every retained click before capturing a new click frame."
    case .consumeCompletedPointSelection:
      "The completed point-selection batch must match the current exact frame, selection identity, transform, and four-point requirement."
    case .revalidateCheckpoint:
      "Revalidation requires a recoverable accepted tip-calibration checkpoint."
    case .acceptProposal, .retryCommit: "Commit requires an explicit retained registration proposal."
    case .rejectProposal: "Reject requires an explicit retained proposal."
    case .beginFourMarkBatch: "A new four-mark batch is not admitted from the current tip-calibration phase."
    }
  }

  private func recordRefusal(_ intent: PlotterTipCalibrationIntent, _ reason: String) -> PlotterTipCalibrationSubmissionOutcome {
    let outcome = PlotterTipCalibrationSubmissionOutcome.refused(reason)
    record(operationID: nil, intent: intent, outcome: outcome)
    return outcome
  }

  private func closeAdmission() async {
    admissionClosed = true
    activeTask?.cancel()
    await awaitActiveOperationSettlement()
  }

  private func awaitActiveOperationSettlement() async {
    guard activeOperationID != nil else { return }
    await withCheckedContinuation { continuation in
      operationSettlementWaiters.append(continuation)
    }
  }

  private func finishActiveOperation(operationID: PlotterTipCalibrationOperationID) {
    guard activeOperationID == operationID else { return }
    activeTask = nil
    activeOperationID = nil
    activeIntent = nil
    let waiters = operationSettlementWaiters
    operationSettlementWaiters.removeAll(keepingCapacity: false)
    for waiter in waiters { waiter.resume() }
  }

  private func record(
    operationID: PlotterTipCalibrationOperationID?,
    intent: PlotterTipCalibrationIntent,
    outcome: PlotterTipCalibrationSubmissionOutcome
  ) {
    terminalHistory.append(.init(operationID: operationID, intent: intent, outcome: outcome, phase: phase))
    if terminalHistory.count > Self.terminalHistoryLimit {
      terminalHistory.removeFirst(terminalHistory.count - Self.terminalHistoryLimit)
    }
  }
}
