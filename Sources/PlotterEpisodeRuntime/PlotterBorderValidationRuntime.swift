import Foundation
import PlotterEpisodeModel
import PlotterModel
import PlotterRuntime

public struct PlotterBorderValidationOperationID: RawRepresentable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

public enum BorderValidationStep: Int, CaseIterable, Hashable, Identifiable, Sendable {
  case chooseDrawingBorderPlan = 1
  case captureLocalPreFrameBaseline
  case moveToDrawingBorderStart
  case drawDrawingBorder
  case revealAndObserveNewInk
  case compareIntendedAndObservedGeometry

  public var id: Self { self }

  /// All cases are internal phases of the single visible 2.1 validation.
  public var stepNumber: String { "2.1" }

  public var title: String {
    switch self {
    case .chooseDrawingBorderPlan: "Plan Drawing Border"
    case .captureLocalPreFrameBaseline: "Capture Baseline Frame"
    case .moveToDrawingBorderStart: "Move to Drawing Border Start"
    case .drawDrawingBorder: "Draw Drawing Border"
    case .revealAndObserveNewInk: "Reveal Drawing"
    case .compareIntendedAndObservedGeometry: "Compare Plan with Observed Ink"
    }
  }
}

public enum BorderValidationAssessment: String, Hashable, Sendable {
  case predictionObserved

  public var title: String {
    switch self {
    case .predictionObserved: "Observed frame compared with predicted geometry"
    }
  }
}

public typealias PlotterBorderValidationComparisonHistories =
  [AttemptCompatibility: ExerciseAttemptHistory<BorderValidationAssessment>]

public enum PlotterBorderValidationExecutionState: Hashable, Sendable {
  case notAdmitted
  case completedNaturally
  case possibleInk
}

public enum PlotterBorderValidationPhase: Hashable, Sendable {
  case idle
  case planning(PlotterBorderValidationOperationID)
  case capturingBaseline(PlotterBorderValidationOperationID)
  case movingToStart(PlotterBorderValidationOperationID)
  case executingBorder(PlotterBorderValidationOperationID)
  case revealingAndObserving(PlotterBorderValidationOperationID)
  case reviewingComparison(PlotterBorderValidationOperationID)
  case accepted
  case rejected(String)
  case possibleInk(String)
  case cancelled(String)
  case failed(String)
}

public struct PlotterBorderValidationTerminalRecord: Hashable, Sendable {
  public let operationID: PlotterBorderValidationOperationID?
  public let step: BorderValidationStep
  public let phase: PlotterBorderValidationPhase
  public let detail: String

  public init(
    operationID: PlotterBorderValidationOperationID?,
    step: BorderValidationStep,
    phase: PlotterBorderValidationPhase,
    detail: String
  ) {
    self.operationID = operationID
    self.step = step
    self.phase = phase
    self.detail = detail
  }
}

public struct PlotterBorderValidationSnapshot: Sendable {
  public internal(set) var admissionClosed: Bool
  public internal(set) var activeOperationID: PlotterBorderValidationOperationID?
  public internal(set) var activeStep: BorderValidationStep?
  public internal(set) var executionState: PlotterBorderValidationExecutionState
  public internal(set) var phase: PlotterBorderValidationPhase
  public internal(set) var step: BorderValidationStep
  public internal(set) var localPreFrameBaseline: DisplayedFrame?
  public internal(set) var revealPosition: MachinePosition?
  public internal(set) var tipRegistrationRevisionID: LearningArtifactRevisionID?
  public internal(set) var observationRegion: PixelRect?
  public internal(set) var postFrame: DisplayedFrame?
  public internal(set) var program: DrawingProgram?
  public internal(set) var drawingBorderPlan: ExecutionPlanRevision?
  public internal(set) var drawingOutcome: DrawingPlanOutcome?
  public internal(set) var inkObservation: PlannedDrawingObservation?
  public internal(set) var inkStatus: String
  public internal(set) var lastTravelFeedSelection: TravelFeedSelection?
  public internal(set) var assessment: BorderValidationAssessment?
  public internal(set) var comparisonReviewIsPinned: Bool
  public internal(set) var comparisonAttemptHistories:
    PlotterBorderValidationComparisonHistories
  public internal(set) var group: AttemptGroupIdentity
  public internal(set) var terminalHistory: [PlotterBorderValidationTerminalRecord]

  public init(
    sourceIsSimulated: Bool,
    admissionClosed: Bool = false,
    activeOperationID: PlotterBorderValidationOperationID? = nil,
    activeStep: BorderValidationStep? = nil,
    executionState: PlotterBorderValidationExecutionState = .notAdmitted,
    phase: PlotterBorderValidationPhase = .idle,
    step: BorderValidationStep = .chooseDrawingBorderPlan,
    localPreFrameBaseline: DisplayedFrame? = nil,
    revealPosition: MachinePosition? = nil,
    tipRegistrationRevisionID: LearningArtifactRevisionID? = nil,
    observationRegion: PixelRect? = nil,
    postFrame: DisplayedFrame? = nil,
    program: DrawingProgram? = nil,
    drawingBorderPlan: ExecutionPlanRevision? = nil,
    drawingOutcome: DrawingPlanOutcome? = nil,
    inkObservation: PlannedDrawingObservation? = nil,
    inkStatus: String = "no Drawing Border observation yet",
    lastTravelFeedSelection: TravelFeedSelection? = nil,
    assessment: BorderValidationAssessment? = nil,
    comparisonReviewIsPinned: Bool = false,
    comparisonAttemptHistories: PlotterBorderValidationComparisonHistories = [:],
    group: AttemptGroupIdentity? = nil,
    terminalHistory: [PlotterBorderValidationTerminalRecord] = []
  ) {
    self.admissionClosed = admissionClosed
    self.activeOperationID = activeOperationID
    self.activeStep = activeStep
    self.executionState = executionState
    self.phase = phase
    self.step = step
    self.localPreFrameBaseline = localPreFrameBaseline
    self.revealPosition = revealPosition
    self.tipRegistrationRevisionID = tipRegistrationRevisionID
    self.observationRegion = observationRegion
    self.postFrame = postFrame
    self.program = program
    self.drawingBorderPlan = drawingBorderPlan
    self.drawingOutcome = drawingOutcome
    self.inkObservation = inkObservation
    self.inkStatus = inkStatus
    self.lastTravelFeedSelection = lastTravelFeedSelection
    self.assessment = assessment
    self.comparisonReviewIsPinned = comparisonReviewIsPinned
    self.comparisonAttemptHistories = comparisonAttemptHistories
    self.group = group ?? Self.newGroup(sourceIsSimulated: sourceIsSimulated)
    self.terminalHistory = terminalHistory
  }

  public static func newGroup(sourceIsSimulated: Bool) -> AttemptGroupIdentity {
    AttemptGroupIdentity(
      rawValue: sourceIsSimulated
        ? "simulated-\(UUID().uuidString.lowercased())"
        : UUID().uuidString.lowercased()
    )
  }

  mutating func rewind(from rewindStep: BorderValidationStep, sourceIsSimulated: Bool) {
    if rewindStep == .chooseDrawingBorderPlan {
      program = nil
      drawingBorderPlan = nil
      tipRegistrationRevisionID = nil
      group = Self.newGroup(sourceIsSimulated: sourceIsSimulated)
    }
    if rewindStep.rawValue <= BorderValidationStep.captureLocalPreFrameBaseline.rawValue {
      localPreFrameBaseline = nil
      revealPosition = nil
    }
    if rewindStep.rawValue <= BorderValidationStep.drawDrawingBorder.rawValue {
      drawingOutcome = nil
    }
    if rewindStep.rawValue <= BorderValidationStep.revealAndObserveNewInk.rawValue {
      postFrame = nil
      observationRegion = nil
      inkObservation = nil
      inkStatus = "no Drawing Border observation yet"
    }
    assessment = nil
    comparisonReviewIsPinned = false
    comparisonAttemptHistories = [:]
    lastTravelFeedSelection = nil
    activeOperationID = nil
    activeStep = nil
    executionState = .notAdmitted
    phase = rewindStep == .compareIntendedAndObservedGeometry
      ? .reviewingComparison(PlotterBorderValidationOperationID())
      : .idle
    step = rewindStep
  }
}

public enum PlotterBorderValidationIntent: Hashable, Sendable {
  case begin
  case acceptObservedPrediction
  case reject(String)
}

public enum PlotterBorderValidationStateIntent: Sendable {
  case setComparisonReviewPinned(Bool)
  case rewind(BorderValidationStep)
  case reset
  case restoreAcceptedAssessment(BorderValidationAssessment)
  case installComparisonHistories(PlotterBorderValidationComparisonHistories)
}

public enum PlotterBorderValidationStateDisposition: Hashable, Sendable {
  case applied
  case refused(reason: String, remedy: String)
}

public struct PlotterBorderValidationStateResult: Sendable {
  public let disposition: PlotterBorderValidationStateDisposition
  public let snapshot: PlotterBorderValidationSnapshot

  public init(
    disposition: PlotterBorderValidationStateDisposition,
    snapshot: PlotterBorderValidationSnapshot
  ) {
    self.disposition = disposition
    self.snapshot = snapshot
  }
}

public enum PlotterBorderValidationEffectRequest: Hashable, Sendable {
  case runStep(operationID: PlotterBorderValidationOperationID, step: BorderValidationStep)
  case acceptComparison(
    operationID: PlotterBorderValidationOperationID,
    assessment: BorderValidationAssessment
  )
  case rejectComparison(operationID: PlotterBorderValidationOperationID, reason: String)
}

public enum PlotterBorderValidationEffectFact: Sendable {
  case planned(program: DrawingProgram, plan: ExecutionPlanRevision, revision: LearningArtifactRevisionID)
  case baselineCaptured(DisplayedFrame, revealPosition: MachinePosition)
  case movedToStart(MachinePosition, feed: TravelFeedSelection?)
  case borderExecuted(DrawingPlanOutcome?)
  case observedInk(
    postFrame: DisplayedFrame,
    region: PixelRect,
    observation: PlannedDrawingObservation,
    inkStatus: String
  )
  case comparisonAccepted(
    BorderValidationAssessment,
    histories: PlotterBorderValidationComparisonHistories
  )
  case comparisonRejected(
    String,
    histories: PlotterBorderValidationComparisonHistories
  )
  case possibleInk(String, outcome: DrawingPlanOutcome?)
}

public enum PlotterBorderValidationEffectResult: Sendable {
  case completed(PlotterBorderValidationEffectFact)
  case refused(String)
  case cancelled(String)
  case failed(String)
}

public protocol PlotterBorderValidationEffectPort: AnyObject, Sendable {
  func execute(_ request: PlotterBorderValidationEffectRequest) async
    -> PlotterBorderValidationEffectResult
}

@MainActor
public final class PlotterBorderValidationRuntime {
  public static let terminalHistoryLimit = 16

  private let effectPort: any PlotterBorderValidationEffectPort
  private let sourceIsSimulated: Bool
  private let snapshotDidChange: (@MainActor (PlotterBorderValidationSnapshot) -> Void)?
  private var state: PlotterBorderValidationSnapshot
  private var activeEffect: (
    operationID: PlotterBorderValidationOperationID,
    task: Task<PlotterBorderValidationEffectResult, Never>
  )?

  public init(
    sourceIsSimulated: Bool,
    effectPort: any PlotterBorderValidationEffectPort,
    snapshotDidChange: (@MainActor (PlotterBorderValidationSnapshot) -> Void)? = nil
  ) {
    self.effectPort = effectPort
    self.sourceIsSimulated = sourceIsSimulated
    self.snapshotDidChange = snapshotDidChange
    state = PlotterBorderValidationSnapshot(sourceIsSimulated: sourceIsSimulated)
  }

  public func snapshot() -> PlotterBorderValidationSnapshot { state }

  @discardableResult
  public func apply(
    _ intent: PlotterBorderValidationStateIntent
  ) -> PlotterBorderValidationStateResult {
    guard state.activeOperationID == nil else {
      return stateResult(.refused(
        reason: "Border validation owns an active operation.",
        remedy: "Stop or finish the current Border validation operation first."
      ))
    }
    switch intent {
    case .setComparisonReviewPinned(let isPinned):
      if isPinned,
        state.assessment == nil || state.postFrame == nil || state.inkObservation == nil
      {
        return stateResult(.refused(
          reason: "No completed Border comparison is available for review.",
          remedy: "Complete and accept the current Border comparison first."
        ))
      }
      state.comparisonReviewIsPinned = isPinned
    case .rewind(let step):
      state.rewind(from: step, sourceIsSimulated: sourceIsSimulated)
    case .reset:
      state = PlotterBorderValidationSnapshot(
        sourceIsSimulated: sourceIsSimulated,
        admissionClosed: state.admissionClosed
      )
    case .restoreAcceptedAssessment(let assessment):
      state.assessment = assessment
    case .installComparisonHistories(let histories):
      state.comparisonAttemptHistories = histories
    }
    emitSnapshot()
    return stateResult(.applied)
  }

  public func closeAdmissionAndCancel() async {
    state.admissionClosed = true
    let effect = activeEffect
    effect?.task.cancel()
    if let operationID = state.activeOperationID, let step = state.activeStep {
      state.phase = .cancelled("Admission closed by shutdown/cancel.")
      recordTerminal(operationID: operationID, step: step, detail: "Admission closed by shutdown/cancel.")
    }
    state.activeOperationID = nil
    state.activeStep = nil
    state.executionState = .notAdmitted
    emitSnapshot()
    _ = await effect?.task.value
    if activeEffect?.operationID == effect?.operationID {
      activeEffect = nil
    }
  }

  public func restoreAdmission() {
    state.admissionClosed = false
    emitSnapshot()
  }

  private func beginStep(_ step: BorderValidationStep) -> PlotterBorderValidationOperationID? {
    guard !state.admissionClosed, state.activeOperationID == nil else { return nil }
    let operationID = PlotterBorderValidationOperationID()
    state.activeOperationID = operationID
    state.activeStep = step
    state.executionState = .notAdmitted
    state.phase = phase(for: step, operationID: operationID)
    emitSnapshot()
    return operationID
  }

  private func finishActiveStep() {
    state.activeOperationID = nil
    state.activeStep = nil
    if case .possibleInk = state.phase {
      state.executionState = .possibleInk
    } else {
      state.executionState = .notAdmitted
    }
    emitSnapshot()
  }

  public func submit(_ intent: PlotterBorderValidationIntent) async
    -> PlotterBorderValidationSnapshot
  {
    guard !state.admissionClosed else { return state }
    switch intent {
    case .begin:
      while state.step != .compareIntendedAndObservedGeometry {
        let step = state.step
        guard await submitStep(step) else { return state }
        if case .possibleInk = state.phase { return state }
        advanceAfterSuccess(step)
      }
    case .acceptObservedPrediction:
      _ = await submitAcceptComparison(.predictionObserved)
    case .reject(let reason):
      _ = await submitReject(reason)
    }
    return state
  }

  @discardableResult
  func submitStep(_ step: BorderValidationStep) async -> Bool {
    guard let operationID = beginStep(step) else { return false }
    return await execute(
      .runStep(operationID: operationID, step: step),
      operationID: operationID,
      step: step
    )
  }

  @discardableResult
  func submitAcceptComparison(_ assessment: BorderValidationAssessment) async -> Bool {
    await submitComparison { .acceptComparison(operationID: $0, assessment: assessment) }
  }

  @discardableResult
  func submitReject(_ reason: String) async -> Bool {
    await submitComparison { .rejectComparison(operationID: $0, reason: reason) }
  }

  private func submitComparison(
    _ request: (PlotterBorderValidationOperationID) -> PlotterBorderValidationEffectRequest
  ) async -> Bool {
    guard state.step == .compareIntendedAndObservedGeometry,
      state.activeOperationID == nil,
      case .reviewingComparison = state.phase
    else { return false }
    guard let operationID = beginStep(.compareIntendedAndObservedGeometry) else { return false }
    return await execute(
      request(operationID),
      operationID: operationID,
      step: .compareIntendedAndObservedGeometry
    )
  }

  private func execute(
    _ effect: PlotterBorderValidationEffectRequest,
    operationID: PlotterBorderValidationOperationID,
    step: BorderValidationStep
  ) async -> Bool {
    let task = Task { [effectPort] in await effectPort.execute(effect) }
    activeEffect = (operationID, task)
    let result = await task.value
    guard activeEffect?.operationID == operationID else { return false }
    activeEffect = nil
    return apply(result, operationID: operationID, step: step)
  }

  @discardableResult
  private func apply(
    _ result: PlotterBorderValidationEffectResult,
    operationID: PlotterBorderValidationOperationID,
    step: BorderValidationStep
  ) -> Bool {
    guard !state.admissionClosed,
      state.activeOperationID == operationID,
      state.activeStep == step
    else { return false }
    defer { finishActiveStep() }
    switch result {
    case .completed(let fact):
      apply(fact)
      return true
    case .refused(let detail):
      state.phase = .failed(detail)
      recordTerminal(operationID: operationID, step: step, detail: detail)
      emitSnapshot()
      return false
    case .cancelled(let detail):
      state.phase = .cancelled(detail)
      recordTerminal(operationID: operationID, step: step, detail: detail)
      emitSnapshot()
      return false
    case .failed(let detail):
      state.phase = .failed(detail)
      recordTerminal(operationID: operationID, step: step, detail: detail)
      emitSnapshot()
      return false
    }
  }

  private func apply(_ fact: PlotterBorderValidationEffectFact) {
    switch fact {
    case .planned(let program, let plan, let revision):
      state.program = program
      state.drawingBorderPlan = plan
      state.tipRegistrationRevisionID = revision
    case .baselineCaptured(let frame, let revealPosition):
      state.localPreFrameBaseline = frame
      state.revealPosition = revealPosition
    case .movedToStart(_, let feed):
      state.lastTravelFeedSelection = feed
    case .borderExecuted(let outcome):
      state.drawingOutcome = outcome
      state.executionState = .completedNaturally
    case .observedInk(let postFrame, let region, let observation, let inkStatus):
      state.postFrame = postFrame
      state.observationRegion = region
      state.inkObservation = observation
      state.inkStatus = inkStatus
    case .comparisonAccepted(let assessment, let histories):
      state.assessment = assessment
      state.comparisonAttemptHistories = histories
      state.comparisonReviewIsPinned = true
      state.phase = .accepted
      recordTerminal(
        operationID: state.activeOperationID,
        step: .compareIntendedAndObservedGeometry,
        detail: "Operator accepted the observed Drawing Border comparison."
      )
    case .comparisonRejected(let reason, let histories):
      state.assessment = nil
      state.comparisonAttemptHistories = histories
      state.phase = .rejected(reason)
      recordTerminal(
        operationID: state.activeOperationID,
        step: .compareIntendedAndObservedGeometry,
        detail: reason
      )
    case .possibleInk(let detail, let outcome):
      state.drawingOutcome = outcome
      state.executionState = .possibleInk
      state.phase = .possibleInk(detail)
      if state.activeStep == .drawDrawingBorder {
        state.step = .revealAndObserveNewInk
      }
      recordTerminal(
        operationID: state.activeOperationID,
        step: state.activeStep ?? state.step,
        detail: detail
      )
    }
    emitSnapshot()
  }

  func advanceAfterSuccess(_ step: BorderValidationStep) {
    switch step {
    case .chooseDrawingBorderPlan:
      state.step = .captureLocalPreFrameBaseline
    case .captureLocalPreFrameBaseline:
      state.step = .moveToDrawingBorderStart
    case .moveToDrawingBorderStart:
      state.step = .drawDrawingBorder
    case .drawDrawingBorder:
      state.step = .revealAndObserveNewInk
    case .revealAndObserveNewInk:
      state.step = .compareIntendedAndObservedGeometry
      state.phase = .reviewingComparison(state.activeOperationID ?? PlotterBorderValidationOperationID())
    case .compareIntendedAndObservedGeometry:
      state.phase = .accepted
    }
    emitSnapshot()
  }

  private func emitSnapshot() {
    snapshotDidChange?(state)
  }

  private func stateResult(
    _ disposition: PlotterBorderValidationStateDisposition
  ) -> PlotterBorderValidationStateResult {
    PlotterBorderValidationStateResult(disposition: disposition, snapshot: state)
  }

  private func phase(
    for step: BorderValidationStep,
    operationID: PlotterBorderValidationOperationID
  ) -> PlotterBorderValidationPhase {
    switch step {
    case .chooseDrawingBorderPlan: .planning(operationID)
    case .captureLocalPreFrameBaseline: .capturingBaseline(operationID)
    case .moveToDrawingBorderStart: .movingToStart(operationID)
    case .drawDrawingBorder: .executingBorder(operationID)
    case .revealAndObserveNewInk: .revealingAndObserving(operationID)
    case .compareIntendedAndObservedGeometry: .reviewingComparison(operationID)
    }
  }

  private func recordTerminal(
    operationID: PlotterBorderValidationOperationID?,
    step: BorderValidationStep,
    detail: String
  ) {
    state.terminalHistory.append(PlotterBorderValidationTerminalRecord(
      operationID: operationID,
      step: step,
      phase: state.phase,
      detail: detail
    ))
    if state.terminalHistory.count > Self.terminalHistoryLimit {
      state.terminalHistory.removeFirst(state.terminalHistory.count - Self.terminalHistoryLimit)
    }
  }
}
