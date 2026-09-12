import Foundation
import PlotterEpisodeModel
import PlotterRuntime

public struct PlotterArtifactResetOperationID: RawRepresentable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

public struct PlotterArtifactResetStepID: RawRepresentable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

public enum PlotterArtifactResetSavedLearningState: Hashable, Sendable {
  case absent
  case awaitingOperatorDecision(
    AcceptedLearningPathCheckpoint,
    opticalComparison: String
  )
  case applied(AcceptedLearningPathCheckpoint, opticalComparison: String)
  case retainedForLater(AcceptedLearningPathCheckpoint)
  case rejected(String)

  public var checkpoint: AcceptedLearningPathCheckpoint? {
    switch self {
    case .awaitingOperatorDecision(let checkpoint, _),
      .applied(let checkpoint, _),
      .retainedForLater(let checkpoint):
      checkpoint
    case .absent, .rejected:
      nil
    }
  }

  public var candidate: (checkpoint: AcceptedLearningPathCheckpoint, opticalComparison: String)? {
    guard case .awaitingOperatorDecision(let checkpoint, let comparison) = self else {
      return nil
    }
    return (checkpoint, comparison)
  }

  /// Applying an already accepted package is a bounded recovery operation;
  /// the effect owner must revalidate its current dependencies before mutation.
  public var applicationCandidate: (checkpoint: AcceptedLearningPathCheckpoint, opticalComparison: String)? {
    if let candidate { return candidate }
    guard case .applied(let checkpoint, let comparison) = self else { return nil }
    return (checkpoint, comparison)
  }

  public var appliedCheckpoint: AcceptedLearningPathCheckpoint? {
    guard case .applied(let checkpoint, _) = self else { return nil }
    return checkpoint
  }
}

public struct PlotterArtifactResetPlan: Hashable, Sendable {
  public let id: String
  public let anchorStepID: PlotterArtifactResetStepID?
  public let affectedStepIDs: [PlotterArtifactResetStepID]
  public let expectedCurrentRevisionIDs: Set<LearningArtifactRevisionID>
  public let expectedAcceptedAttemptSequence: UInt64
  public let sourceIsSimulated: Bool
  public let resetAll: Bool
  public let removesDurableMachineCheckpoint: Bool
  public let removesDurableTipCheckpoint: Bool
  public let physicalInkMayRemain: Bool
  /// Present only for a LIVE paper replacement. It freezes both the expected
  /// current identity and the operator-declared replacement identity before
  /// the persistence transaction starts.
  public let paperReplacement: PaperReplacementTransition?
  /// Exact durable predecessor retained only for transaction rollback.
  public let previousAcceptedCheckpoint: AcceptedLearningPathCheckpoint?
  public let expectedControllerSessionID: UUID?

  public init(
    id: String,
    anchorStepID: PlotterArtifactResetStepID? = nil,
    affectedStepIDs: [PlotterArtifactResetStepID] = [],
    expectedCurrentRevisionIDs: Set<LearningArtifactRevisionID> = [],
    expectedAcceptedAttemptSequence: UInt64 = 0,
    sourceIsSimulated: Bool,
    resetAll: Bool,
    removesDurableMachineCheckpoint: Bool,
    removesDurableTipCheckpoint: Bool,
    physicalInkMayRemain: Bool,
    paperReplacement: PaperReplacementTransition? = nil,
    previousAcceptedCheckpoint: AcceptedLearningPathCheckpoint? = nil,
    expectedControllerSessionID: UUID? = nil
  ) {
    self.id = id
    self.anchorStepID = anchorStepID
    self.affectedStepIDs = affectedStepIDs
    self.expectedCurrentRevisionIDs = expectedCurrentRevisionIDs
    self.expectedAcceptedAttemptSequence = expectedAcceptedAttemptSequence
    self.sourceIsSimulated = sourceIsSimulated
    self.resetAll = resetAll
    self.removesDurableMachineCheckpoint = removesDurableMachineCheckpoint
    self.removesDurableTipCheckpoint = removesDurableTipCheckpoint
    self.physicalInkMayRemain = physicalInkMayRemain
    self.paperReplacement = paperReplacement
    self.previousAcceptedCheckpoint = previousAcceptedCheckpoint
    self.expectedControllerSessionID = expectedControllerSessionID
  }
}

public struct PlotterArtifactResetAdmissionFacts: Hashable, Sendable {
  public let environment: PlotterEnvironment
  public let possibleInkBlocked: Bool
  public let activeStopBlocked: Bool
  public let motionSettlementBlocked: Bool
  public let lowerOwnerBlocker: String?

  public init(
    environment: PlotterEnvironment,
    possibleInkBlocked: Bool = false,
    activeStopBlocked: Bool = false,
    motionSettlementBlocked: Bool = false,
    lowerOwnerBlocker: String? = nil
  ) {
    self.environment = environment
    self.possibleInkBlocked = possibleInkBlocked
    self.activeStopBlocked = activeStopBlocked
    self.motionSettlementBlocked = motionSettlementBlocked
    self.lowerOwnerBlocker = lowerOwnerBlocker
  }
}

public enum PlotterArtifactResetIntent: Hashable, Sendable {
  case compareSavedLearning(AcceptedLearningPathCheckpoint, comparisonIdentity: String)
  case applySavedLearning
  case retainSavedLearning
  case rejectSavedLearning(String)
  case redoStep(PlotterArtifactResetStepID)
  case recordAnotherAttempt(PlotterArtifactResetStepID)
  case paperReplaced(PlotterArtifactResetPlan)
  case reset(PlotterArtifactResetPlan)
}

private extension PlotterArtifactResetIntent {
  var isReset: Bool {
    if case .reset = self { return true }
    return false
  }
}

public enum PlotterArtifactResetPhase: Hashable, Sendable {
  case idle
  case comparingSavedLearning(PlotterArtifactResetOperationID)
  case applyingSavedLearning(PlotterArtifactResetOperationID)
  case retainingSavedLearning(PlotterArtifactResetOperationID)
  case rejectingSavedLearning(PlotterArtifactResetOperationID)
  case preparingReplacementAttempt(PlotterArtifactResetOperationID)
  case preparingAdditionalAttempt(PlotterArtifactResetOperationID)
  case replacingPaper(PlotterArtifactResetOperationID)
  case persistingPaperReplacement(PlotterArtifactResetOperationID)
  case applyingInMemoryPaperReplacement(PlotterArtifactResetOperationID)
  case settlingReset(PlotterArtifactResetOperationID)
  case persistingReset(PlotterArtifactResetOperationID)
  case applyingInMemoryReset(PlotterArtifactResetOperationID)
  case completed
  case failed(String)
  case refused(String)
  case cancelled(String)

  public var detail: String? {
    switch self {
    case .failed(let detail), .refused(let detail), .cancelled(let detail): detail
    default: nil
    }
  }
}

public enum PlotterArtifactResetEffectRequest: Hashable, Sendable {
  case compareSavedLearning(
    operationID: PlotterArtifactResetOperationID,
    checkpoint: AcceptedLearningPathCheckpoint
  )
  case applySavedLearning(
    operationID: PlotterArtifactResetOperationID,
    checkpoint: AcceptedLearningPathCheckpoint,
    opticalComparison: String,
    environment: PlotterEnvironment
  )
  case retainSavedLearning(
    operationID: PlotterArtifactResetOperationID,
    checkpoint: AcceptedLearningPathCheckpoint
  )
  case rejectSavedLearning(operationID: PlotterArtifactResetOperationID, reason: String)
  case redoStep(operationID: PlotterArtifactResetOperationID, stepID: PlotterArtifactResetStepID)
  case recordAnotherAttempt(
    operationID: PlotterArtifactResetOperationID,
    stepID: PlotterArtifactResetStepID
  )
  case settleForPaperReplacement(
    operationID: PlotterArtifactResetOperationID,
    plan: PlotterArtifactResetPlan
  )
  case applyInMemoryPaperReplacement(
    operationID: PlotterArtifactResetOperationID,
    plan: PlotterArtifactResetPlan
  )
  case settleForReset(operationID: PlotterArtifactResetOperationID, plan: PlotterArtifactResetPlan)
  case applyInMemoryReset(
    operationID: PlotterArtifactResetOperationID,
    plan: PlotterArtifactResetPlan
  )
}

public enum PlotterArtifactResetEffectFact: Hashable, Sendable {
  case savedLearningCompared(AcceptedLearningPathCheckpoint, opticalComparison: String)
  case savedLearningApplied(AcceptedLearningPathCheckpoint, opticalComparison: String)
  case savedLearningRetained(AcceptedLearningPathCheckpoint)
  case savedLearningRejected(String)
  case replacementAttemptPrepared(PlotterArtifactResetStepID)
  case additionalAttemptPrepared(PlotterArtifactResetStepID)
  case paperReplacementSettled(PlotterArtifactResetPlan)
  case inMemoryPaperReplacementApplied(PlotterArtifactResetPlan)
  case resetSettled(PlotterArtifactResetPlan)
  case inMemoryResetApplied(PlotterArtifactResetPlan)
}

public enum PlotterArtifactResetEffectResult: Hashable, Sendable {
  case completed(PlotterArtifactResetEffectFact)
  case refused(String)
  case cancelled(String)
  case failed(String)
}

public protocol PlotterArtifactResetEffectPort: AnyObject, Sendable {
  func execute(_ request: PlotterArtifactResetEffectRequest) async
    -> PlotterArtifactResetEffectResult
}

public enum PlotterArtifactResetPersistenceRequest: Hashable, Sendable {
  case persistPaperReplacement(
    operationID: PlotterArtifactResetOperationID,
    plan: PlotterArtifactResetPlan
  )
  case persistReset(
    operationID: PlotterArtifactResetOperationID,
    plan: PlotterArtifactResetPlan
  )
}

public enum PlotterArtifactResetPersistenceFact: Hashable, Sendable {
  case paperReplacementPersisted(PlotterArtifactResetPlan)
  case resetPersisted(
    PlotterArtifactResetPlan,
    savedLearning: PlotterArtifactResetSavedLearningState
  )
}

public enum PlotterArtifactResetPersistenceResult: Hashable, Sendable {
  case completed(PlotterArtifactResetPersistenceFact)
  case refused(String)
  case cancelled(String)
  case failed(String)
}

public protocol PlotterArtifactResetPersistencePort: AnyObject, Sendable {
  func persist(_ request: PlotterArtifactResetPersistenceRequest) async
    -> PlotterArtifactResetPersistenceResult
}

public struct PlotterArtifactResetTerminalRecord: Hashable, Sendable {
  public let operationID: PlotterArtifactResetOperationID?
  public let intent: PlotterArtifactResetIntent
  public let phase: PlotterArtifactResetPhase
  public let detail: String

  public init(
    operationID: PlotterArtifactResetOperationID?,
    intent: PlotterArtifactResetIntent,
    phase: PlotterArtifactResetPhase,
    detail: String
  ) {
    self.operationID = operationID
    self.intent = intent
    self.phase = phase
    self.detail = detail
  }
}

public struct PlotterArtifactResetSnapshot: Hashable, Sendable {
  public let admissionClosed: Bool
  public let activeOperationID: PlotterArtifactResetOperationID?
  public let activeIntent: PlotterArtifactResetIntent?
  public let phase: PlotterArtifactResetPhase
  public let savedLearning: PlotterArtifactResetSavedLearningState
  public let lastResetPlan: PlotterArtifactResetPlan?
  public let terminalHistory: [PlotterArtifactResetTerminalRecord]
}

@MainActor
public final class PlotterArtifactResetRuntime {
  public static let terminalHistoryLimit = 16

  private let effectPort: any PlotterArtifactResetEffectPort
  private let persistencePort: any PlotterArtifactResetPersistencePort
  private var admissionClosed = false
  private var activeOperationID: PlotterArtifactResetOperationID?
  private var activeIntent: PlotterArtifactResetIntent?
  private var phase: PlotterArtifactResetPhase = .idle
  private var savedLearning: PlotterArtifactResetSavedLearningState = .absent
  private var lastResetPlan: PlotterArtifactResetPlan?
  private var lastComparisonIdentity: String?
  private var terminalHistory: [PlotterArtifactResetTerminalRecord] = []
  private var activeTask: Task<Void, Never>?
  private var operationSettlementWaiters: [CheckedContinuation<Void, Never>] = []

  public init(
    effectPort: any PlotterArtifactResetEffectPort,
    persistencePort: any PlotterArtifactResetPersistencePort
  ) {
    self.effectPort = effectPort
    self.persistencePort = persistencePort
  }

  public func snapshot() -> PlotterArtifactResetSnapshot {
    PlotterArtifactResetSnapshot(
      admissionClosed: admissionClosed,
      activeOperationID: activeOperationID,
      activeIntent: activeIntent,
      phase: phase,
      savedLearning: savedLearning,
      lastResetPlan: lastResetPlan,
      terminalHistory: terminalHistory
    )
  }

  public func installSavedLearningFact(_ state: PlotterArtifactResetSavedLearningState) {
    guard activeOperationID == nil, !admissionClosed else { return }
    savedLearning = state
  }

  /// Publish the checkpoint already durably committed by the admitted paper
  /// transaction. No outside caller can replace authority during another task.
  public func installPaperReplacementCheckpoint(
    _ checkpoint: AcceptedLearningPathCheckpoint?, plan: PlotterArtifactResetPlan
  ) {
    guard activeIntent == .paperReplaced(plan),
      case .applyingInMemoryPaperReplacement = phase else { return }
    savedLearning = checkpoint.map {
      .applied($0, opticalComparison: "Retained accepted Learning across paper replacement.")
    } ?? .absent
  }

  public func admissionRefusal(
    for intent: PlotterArtifactResetIntent,
    facts: PlotterArtifactResetAdmissionFacts
  ) -> String? {
    admissionRefusal(allowsLearningSettlement: intent.isReset, facts: facts)
  }

  public func resetAdmissionRefusal(
    facts: PlotterArtifactResetAdmissionFacts
  ) -> String? {
    admissionRefusal(allowsLearningSettlement: true, facts: facts)
  }

  private func admissionRefusal(
    allowsLearningSettlement: Bool,
    facts: PlotterArtifactResetAdmissionFacts
  ) -> String? {
    if admissionClosed { return "Artifact/reset admission is closed." }
    if activeOperationID != nil { return "Artifact/reset already has an active operation." }
    if facts.possibleInkBlocked {
      return "Possible ink must be reviewed before artifact/reset mutation."
    }
    if allowsLearningSettlement {
      return facts.lowerOwnerBlocker
    }
    if facts.activeStopBlocked || facts.motionSettlementBlocked {
      return "Active Stop-sensitive work must settle before artifact/reset mutation."
    }
    return facts.lowerOwnerBlocker
  }

  public func shutdown() async {
    admissionClosed = true
    activeTask?.cancel()
    await awaitActiveOperationSettlement()
  }

  @discardableResult
  public func submit(
    _ intent: PlotterArtifactResetIntent,
    facts: PlotterArtifactResetAdmissionFacts
  ) async -> Bool {
    if let blocker = admissionRefusal(for: intent, facts: facts) {
      refuse(intent, blocker)
      return false
    }

    let operationID = PlotterArtifactResetOperationID()
    activeOperationID = operationID
    activeIntent = intent
    defer { finishActiveOperation() }

    switch intent {
    case .compareSavedLearning(let checkpoint, let comparisonIdentity):
      guard comparisonIdentity != lastComparisonIdentity else { return true }
      lastComparisonIdentity = comparisonIdentity
      phase = .comparingSavedLearning(operationID)
      return await executeEffect(
        .compareSavedLearning(operationID: operationID, checkpoint: checkpoint),
        intent: intent
      )
    case .applySavedLearning:
      guard let candidate = savedLearning.applicationCandidate else {
        refuse(intent, "No Saved Learning candidate is awaiting an operator decision.")
        return false
      }
      guard facts.environment == .live else {
        refuse(intent, "SIMULATED Saved Learning cannot write LIVE durable authority.")
        return false
      }
      phase = .applyingSavedLearning(operationID)
      return await executeEffect(.applySavedLearning(
        operationID: operationID,
        checkpoint: candidate.checkpoint,
        opticalComparison: candidate.opticalComparison,
        environment: facts.environment
      ), intent: intent)
    case .retainSavedLearning:
      guard let candidate = savedLearning.applicationCandidate else {
        refuse(intent, "No Saved Learning candidate is awaiting an operator decision.")
        return false
      }
      phase = .retainingSavedLearning(operationID)
      return await executeEffect(.retainSavedLearning(
        operationID: operationID,
        checkpoint: candidate.checkpoint
      ), intent: intent)
    case .rejectSavedLearning(let reason):
      phase = .rejectingSavedLearning(operationID)
      return await executeEffect(
        .rejectSavedLearning(operationID: operationID, reason: reason),
        intent: intent
      )
    case .redoStep(let stepID):
      phase = .preparingReplacementAttempt(operationID)
      return await executeEffect(.redoStep(operationID: operationID, stepID: stepID), intent: intent)
    case .recordAnotherAttempt(let stepID):
      phase = .preparingAdditionalAttempt(operationID)
      return await executeEffect(
        .recordAnotherAttempt(operationID: operationID, stepID: stepID),
        intent: intent
      )
    case .paperReplaced(let plan):
      phase = .replacingPaper(operationID)
      guard await executeEffect(
        .settleForPaperReplacement(operationID: operationID, plan: plan),
        intent: intent
      ) else {
        return false
      }
      phase = .persistingPaperReplacement(operationID)
      guard await executePersistence(
        .persistPaperReplacement(operationID: operationID, plan: plan),
        intent: intent
      ) else {
        return false
      }
      phase = .applyingInMemoryPaperReplacement(operationID)
      return await executeEffect(
        .applyInMemoryPaperReplacement(operationID: operationID, plan: plan),
        intent: intent
      )
    case .reset(let plan):
      lastResetPlan = plan
      guard await executeEffect(
        .settleForReset(operationID: operationID, plan: plan),
        intent: intent
      ) else {
        return false
      }
      phase = .persistingReset(operationID)
      guard await executePersistence(
        .persistReset(operationID: operationID, plan: plan),
        intent: intent
      ) else {
        return false
      }
      phase = .applyingInMemoryReset(operationID)
      return await executeEffect(
        .applyInMemoryReset(operationID: operationID, plan: plan),
        intent: intent
      )
    }
  }

  private func executeEffect(
    _ request: PlotterArtifactResetEffectRequest,
    intent: PlotterArtifactResetIntent
  ) async -> Bool {
    var result: PlotterArtifactResetEffectResult?
    let task = Task { [effectPort] in result = await effectPort.execute(request) }
    activeTask = task
    await task.value
    let committedPaperProjection: Bool
    if case .applyInMemoryPaperReplacement = request { committedPaperProjection = true }
    else { committedPaperProjection = false }
    guard !admissionClosed || committedPaperProjection else {
      phase = .cancelled("Artifact/reset admission closed.")
      recordTerminal(intent: intent, detail: "Artifact/reset admission closed.")
      return false
    }
    guard let result else { return false }
    switch result {
    case .completed(let fact):
      apply(fact)
      return true
    case .refused(let detail):
      phase = .refused(detail)
      recordTerminal(intent: intent, detail: detail)
      return false
    case .cancelled(let detail):
      phase = .cancelled(detail)
      recordTerminal(intent: intent, detail: detail)
      return false
    case .failed(let detail):
      phase = .failed(detail)
      recordTerminal(intent: intent, detail: detail)
      return false
    }
  }

  private func executePersistence(
    _ request: PlotterArtifactResetPersistenceRequest,
    intent: PlotterArtifactResetIntent
  ) async -> Bool {
    var result: PlotterArtifactResetPersistenceResult?
    let task = Task { [persistencePort] in result = await persistencePort.persist(request) }
    activeTask = task
    await task.value
    let committedPaper: Bool
    if case .completed(.paperReplacementPersisted) = result { committedPaper = true }
    else { committedPaper = false }
    guard !admissionClosed || committedPaper else {
      phase = .cancelled("Artifact/reset admission closed.")
      recordTerminal(intent: intent, detail: "Artifact/reset admission closed.")
      return false
    }
    guard let result else { return false }
    switch result {
    case .completed(let fact):
      apply(fact)
      return true
    case .refused(let detail):
      phase = .refused(detail)
      recordTerminal(intent: intent, detail: detail)
      return false
    case .cancelled(let detail):
      phase = .cancelled(detail)
      recordTerminal(intent: intent, detail: detail)
      return false
    case .failed(let detail):
      phase = .failed(detail)
      recordTerminal(intent: intent, detail: detail)
      return false
    }
  }

  private func awaitActiveOperationSettlement() async {
    guard activeOperationID != nil else { return }
    await withCheckedContinuation { continuation in
      operationSettlementWaiters.append(continuation)
    }
  }

  private func finishActiveOperation() {
    activeOperationID = nil
    activeIntent = nil
    activeTask = nil
    let waiters = operationSettlementWaiters
    operationSettlementWaiters.removeAll(keepingCapacity: false)
    for waiter in waiters { waiter.resume() }
  }

  private func apply(_ fact: PlotterArtifactResetEffectFact) {
    switch fact {
    case .savedLearningCompared(let checkpoint, let opticalComparison):
      savedLearning = .awaitingOperatorDecision(
        checkpoint,
        opticalComparison: opticalComparison
      )
      phase = .completed
    case .savedLearningApplied(let checkpoint, let opticalComparison):
      savedLearning = .applied(checkpoint, opticalComparison: opticalComparison)
      phase = .completed
    case .savedLearningRetained(let checkpoint):
      savedLearning = .retainedForLater(checkpoint)
      phase = .completed
    case .savedLearningRejected(let reason):
      savedLearning = .rejected(reason)
      phase = .completed
    case .replacementAttemptPrepared, .additionalAttemptPrepared:
      phase = .completed
    case .paperReplacementSettled, .resetSettled:
      break
    case .inMemoryPaperReplacementApplied(let plan):
      lastResetPlan = plan
      phase = .completed
    case .inMemoryResetApplied(let plan):
      lastResetPlan = plan
      phase = .completed
    }
  }

  private func apply(_ fact: PlotterArtifactResetPersistenceFact) {
    switch fact {
    case .paperReplacementPersisted:
      break
    case .resetPersisted(let plan, let savedLearning):
      lastResetPlan = plan
      self.savedLearning = savedLearning
    }
  }

  private func refuse(_ intent: PlotterArtifactResetIntent, _ detail: String) {
    phase = .refused(detail)
    recordTerminal(intent: intent, detail: detail)
  }

  private func recordTerminal(intent: PlotterArtifactResetIntent, detail: String) {
    terminalHistory.append(PlotterArtifactResetTerminalRecord(
      operationID: activeOperationID,
      intent: intent,
      phase: phase,
      detail: detail
    ))
    if terminalHistory.count > Self.terminalHistoryLimit {
      terminalHistory.removeFirst(terminalHistory.count - Self.terminalHistoryLimit)
    }
  }
}
