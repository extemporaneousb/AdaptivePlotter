import Foundation
import PlotterModel
import PlotterRuntime

public enum PlotterCameraCalibrationPhase: Codable, Hashable, Sendable {
  case preparing
  case capturing(sample: Int, total: Int, role: String?)
  case moving(sample: Int, total: Int)
  case returningToReference
  case fittingAndTestingHoldouts
  public var description: String {
    switch self {
    case .preparing: return "Preparing bounded calibration"
    case .capturing(let sample, let total, let role): return "Capturing exact sample \(sample) of \(total)\(role.map { " at \($0)" } ?? "")"
    case .moving(let sample, let total): return "Moving Pen Up to exact sample \(sample) of \(total)"
    case .returningToReference: return "Returning Pen Up to the recorded calibration reference pose"
    case .fittingAndTestingHoldouts: return "Checking two independent cap positions and building the five-position camera calibration"
    }
  }
}

public struct PlotterCameraCalibrationFailure: Hashable, Sendable {
  public let code: WorkflowTelemetryFailureCode
  public let detail: String
  public let recovery: WorkflowTelemetryRecovery
  public init(code: WorkflowTelemetryFailureCode, detail: String, recovery: WorkflowTelemetryRecovery) {
    self.code = code; self.detail = detail; self.recovery = recovery
  }
}

public struct PlotterCameraCalibrationOperationID: RawRepresentable, Hashable, Sendable {
  public let rawValue: UUID
  public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public enum PlotterCameraCalibrationIntent: Hashable, Sendable {
  case captureReference, buildFivePositionProposal, acceptProposal, rejectProposal
}
public enum PlotterCameraCalibrationSubmissionOutcome: Hashable, Sendable {
  case completed, refused(String), cancelled, failed(String)
}

/// Immutable facts from controller/camera/Vision or the one accepted-artifact
/// transaction. The App cannot mutate calibration state directly.
public enum PlotterCameraCalibrationEffectFact: Hashable, Sendable {
  case reference(frame: DisplayedFrame, position: MachinePosition, capAnchor: ToolCapAnchorEstimate)
  case proposal(registration: MachineCameraRegistration, correspondenceEvidence: [MachineCameraCorrespondenceProvenance])
  case accepted(MachineCameraRegistration)
  case rejected
  case fivePositionPlan(PlotterCameraCalibrationFivePositionPlan)
  case sample(MachineCameraCorrespondenceProvenance)
  case returnedToReference
}
public struct PlotterCameraCalibrationFivePositionPlan: Hashable, Sendable {
  public let samplePositions: [MachinePosition]
  public let motionDeltas: [Vector2<MachineSpace>]
  public let applicabilityRectangle: AxisAlignedBounds<MachineSpace>
  public let opticalConfiguration: CameraOpticalConfigurationIdentity
  public let machineGeometry: MachineGeometryIdentity
  public let controllerSessionID: UUID
  public let coordinateRevision: UInt64
  public init(samplePositions: [MachinePosition], motionDeltas: [Vector2<MachineSpace>], applicabilityRectangle: AxisAlignedBounds<MachineSpace>, opticalConfiguration: CameraOpticalConfigurationIdentity, machineGeometry: MachineGeometryIdentity, controllerSessionID: UUID, coordinateRevision: UInt64) {
    self.samplePositions = samplePositions; self.motionDeltas = motionDeltas; self.applicabilityRectangle = applicabilityRectangle; self.opticalConfiguration = opticalConfiguration; self.machineGeometry = machineGeometry; self.controllerSessionID = controllerSessionID; self.coordinateRevision = coordinateRevision
  }
}
public enum PlotterCameraCalibrationEffectRequest: Hashable, Sendable {
  case captureReference(PlotterCameraCalibrationOperationID)
  case buildFivePositionProposal(PlotterCameraCalibrationOperationID)
  case acceptProposal(PlotterCameraCalibrationOperationID, registration: MachineCameraRegistration)
  case rejectProposal(PlotterCameraCalibrationOperationID)
  case fivePositionPlan(PlotterCameraCalibrationOperationID, reference: MachinePosition)
  case captureSample(PlotterCameraCalibrationOperationID, sample: Int, expected: MachinePosition)
  case moveAndCapture(PlotterCameraCalibrationOperationID, sample: Int, expected: MachinePosition, delta: Vector2<MachineSpace>)
  case returnToReference(PlotterCameraCalibrationOperationID, reference: MachinePosition, delta: Vector2<MachineSpace>)
}
public enum PlotterCameraCalibrationEffectResult: Hashable, Sendable {
  case completed(PlotterCameraCalibrationEffectFact), refused(String), cancelled, failed(PlotterCameraCalibrationFailure)
}
public protocol PlotterCameraCalibrationEffectPort: AnyObject, Sendable {
  func execute(_ request: PlotterCameraCalibrationEffectRequest) async -> PlotterCameraCalibrationEffectResult
}
public struct PlotterCameraCalibrationTerminalRecord: Hashable, Sendable {
  public let operationID: PlotterCameraCalibrationOperationID?
  public let intent: PlotterCameraCalibrationIntent
  public let outcome: PlotterCameraCalibrationSubmissionOutcome
}
public struct PlotterCameraCalibrationRuntimeSnapshot: Hashable, Sendable {
  public let revision: UInt64
  public let admissionClosed: Bool
  public let activeOperationID: PlotterCameraCalibrationOperationID?
  public let activeIntent: PlotterCameraCalibrationIntent?
  public let anchorFrame: DisplayedFrame?
  public let referencePosition: MachinePosition?
  public let referenceCapAnchor: ToolCapAnchorEstimate?
  public let correspondenceEvidence: [MachineCameraCorrespondenceProvenance]
  public let proposedRegistration: MachineCameraRegistration?
  public let acceptedRegistration: MachineCameraRegistration?
  public let phase: PlotterCameraCalibrationPhase?
  public let failure: PlotterCameraCalibrationFailure?
  public let terminalHistory: [PlotterCameraCalibrationTerminalRecord]
}

/// The runtime owns admission, reviewed proposal state, and terminal outcomes.
/// Its lower port returns explicit facts, never completion inferred from a void
/// workspace call.
@MainActor public final class PlotterCameraCalibrationRuntime {
  public static let terminalHistoryLimit = 16
  private let effectPort: any PlotterCameraCalibrationEffectPort
  private let onStateChange: @MainActor @Sendable () -> Void
  private var admissionClosed = false
  private var shutdownRequested = false
  private var cancellationDepth = 0
  private var replacementPrepared = false
  private var pendingReset = false
  private var settlementWaiters: [CheckedContinuation<Void, Never>] = []
  private var activeTask: Task<PlotterCameraCalibrationSubmissionOutcome, Never>?
  private var terminalHistory: [PlotterCameraCalibrationTerminalRecord] = []
  public private(set) var revision: UInt64 = 0
  public private(set) var activeOperationID: PlotterCameraCalibrationOperationID?
  public private(set) var activeIntent: PlotterCameraCalibrationIntent?
  public private(set) var anchorFrame: DisplayedFrame?
  public private(set) var referencePosition: MachinePosition?
  public private(set) var referenceCapAnchor: ToolCapAnchorEstimate?
  public private(set) var correspondenceEvidence: [MachineCameraCorrespondenceProvenance] = []
  public private(set) var proposedRegistration: MachineCameraRegistration?
  public private(set) var acceptedRegistration: MachineCameraRegistration?
  public private(set) var phase: PlotterCameraCalibrationPhase?
  public private(set) var failure: PlotterCameraCalibrationFailure?
  public init(
    effectPort: any PlotterCameraCalibrationEffectPort,
    onStateChange: @escaping @MainActor @Sendable () -> Void = {}
  ) {
    self.effectPort = effectPort
    self.onStateChange = onStateChange
  }

  @discardableResult public func submit(_ intent: PlotterCameraCalibrationIntent) async -> PlotterCameraCalibrationSubmissionOutcome {
    guard !admissionClosed else { return .cancelled }
    guard activeTask == nil else { return refuse(intent, "Camera calibration already has an active operator effect.") }
    guard admits(intent) else { return refuse(intent, refusalReason(for: intent)) }
    let operationID = PlotterCameraCalibrationOperationID()
    activeOperationID = operationID; activeIntent = intent
    defer { finishOperation(operationID) }
    // Admission must immediately replace the action that produced this
    // request. Otherwise the same green control remains clickable while the
    // lower camera/controller effect is suspended.
    phase = .preparing
    if intent == .buildFivePositionProposal {
      // A previous attempt may have stopped after moving away from its
      // reference. Every operator retry binds a new frame and current pose.
      anchorFrame = nil; referencePosition = nil; referenceCapAnchor = nil
      correspondenceEvidence = []; proposedRegistration = nil; failure = nil
    }
    publishStateChange()
    let task: Task<PlotterCameraCalibrationSubmissionOutcome, Never> = Task { @MainActor [weak self, effectPort] in
      guard let self, self.canExecute(operationID: operationID) else { return .cancelled }
      if intent == .buildFivePositionProposal {
        return await self.buildFivePositionProposal(operationID: operationID)
      }
      let result = await effectPort.execute(self.request(for: intent, operationID: operationID))
      guard self.canExecute(operationID: operationID) else { return .cancelled }
      return self.apply(result, intent: intent)
    }
    activeTask = task
    let outcome = await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
    guard activeOperationID == operationID, activeIntent == intent, !admissionClosed else {
      record(operationID: operationID, intent: intent, outcome: .cancelled)
      return .cancelled
    }
    phase = nil
    record(operationID: operationID, intent: intent, outcome: outcome)
    return outcome
  }

  /// Explicit attempt preparation never moves or discards accepted fallback.
  public func prepareForNewAttempt() async {
    await settleAttempt(preparingNewAttempt: true)
  }

  public func cancelAttempt() async {
    await settleAttempt(preparingNewAttempt: false)
  }

  public func stop() async { await cancelAttempt() }

  /// Compatibility entrypoint used by reset; cancellation remains reusable.
  public func cancelActiveOperation() async { await cancelAttempt() }

  public func shutdown() async {
    shutdownRequested = true
    await settleAttempt(preparingNewAttempt: false)
  }

  private func settleAttempt(preparingNewAttempt: Bool) async {
    cancellationDepth += 1
    admissionClosed = true
    publishStateChange()
    defer {
      cancellationDepth -= 1
      if cancellationDepth == 0, !shutdownRequested { admissionClosed = false }
      publishStateChange()
    }
    activeTask?.cancel()
    if activeOperationID != nil {
      await withCheckedContinuation { settlementWaiters.append($0) }
    }
    clearAttemptTransients()
    replacementPrepared = preparingNewAttempt && !shutdownRequested
  }

  private func clearAttemptTransients() {
    anchorFrame = nil; referencePosition = nil; referenceCapAnchor = nil
    correspondenceEvidence = []; proposedRegistration = nil; phase = nil; failure = nil
  }

  private func finishOperation(_ operationID: PlotterCameraCalibrationOperationID) {
    guard activeOperationID == operationID else { return }
    activeTask = nil; activeOperationID = nil; activeIntent = nil
    if pendingReset {
      pendingReset = false
      clearAttemptTransients()
      if cancellationDepth == 0, !shutdownRequested { admissionClosed = false }
    }
    let waiters = settlementWaiters
    settlementWaiters.removeAll()
    for waiter in waiters { waiter.resume() }
    publishStateChange()
  }
  public func snapshot() -> PlotterCameraCalibrationRuntimeSnapshot {
    .init(revision: revision, admissionClosed: admissionClosed, activeOperationID: activeOperationID, activeIntent: activeIntent,
      anchorFrame: anchorFrame, referencePosition: referencePosition, referenceCapAnchor: referenceCapAnchor,
      correspondenceEvidence: correspondenceEvidence, proposedRegistration: proposedRegistration,
      acceptedRegistration: acceptedRegistration, phase: phase, failure: failure, terminalHistory: terminalHistory)
  }
  /// Persistence recovery can restore only an already accepted registration.
  public func restoreAcceptedRegistration(_ registration: MachineCameraRegistration?) {
    acceptedRegistration = registration
    replacementPrepared = false
    proposedRegistration = nil
    correspondenceEvidence = []
    failure = nil
    phase = nil
    publishStateChange()
  }
  public func clearForReset() {
    acceptedRegistration = nil
    replacementPrepared = false
    clearAttemptTransients()
    if activeOperationID != nil {
      pendingReset = true
      admissionClosed = true
      activeTask?.cancel()
    }
    publishStateChange()
  }

  private func admits(_ intent: PlotterCameraCalibrationIntent) -> Bool {
    switch intent {
    case .captureReference: return phase == nil
    case .buildFivePositionProposal: return phase == nil && (acceptedRegistration == nil || replacementPrepared)
    case .acceptProposal, .rejectProposal: return phase == nil && proposedRegistration != nil
    }
  }
  private func canExecute(operationID: PlotterCameraCalibrationOperationID) -> Bool {
    !Task.isCancelled && !admissionClosed && activeOperationID == operationID
  }
  private func request(for intent: PlotterCameraCalibrationIntent, operationID: PlotterCameraCalibrationOperationID) -> PlotterCameraCalibrationEffectRequest {
    switch intent {
    case .captureReference: return .captureReference(operationID)
    case .buildFivePositionProposal: return .buildFivePositionProposal(operationID)
    case .acceptProposal: return .acceptProposal(operationID, registration: proposedRegistration!)
    case .rejectProposal: return .rejectProposal(operationID)
    }
  }
  private func apply(_ result: PlotterCameraCalibrationEffectResult, intent: PlotterCameraCalibrationIntent) -> PlotterCameraCalibrationSubmissionOutcome {
    switch result {
    case .refused(let detail): return .refused(detail)
    case .cancelled: return .cancelled
    case .failed(let failure): self.failure = failure; phase = nil; publishStateChange(); return .failed(failure.detail)
    case .completed(let fact): return apply(fact, intent: intent)
    }
  }
  private func buildFivePositionProposal(operationID: PlotterCameraCalibrationOperationID) async -> PlotterCameraCalibrationSubmissionOutcome {
    func execute(_ request: PlotterCameraCalibrationEffectRequest) async -> PlotterCameraCalibrationEffectResult {
      guard canExecute(operationID: operationID) else { return .cancelled }
      let result = await effectPort.execute(request)
      guard canExecute(operationID: operationID) else { return .cancelled }
      return result
    }
    func failed(_ result: PlotterCameraCalibrationEffectResult) -> PlotterCameraCalibrationSubmissionOutcome? {
      switch result {
      case .failed(let failure): self.failure = failure; self.phase = nil; publishStateChange(); return .failed(failure.detail)
      case .refused(let detail): return .refused(detail)
      case .cancelled: return .cancelled
      case .completed: return nil
      }
    }
    if anchorFrame == nil || referencePosition == nil || referenceCapAnchor == nil {
      let result = await execute(.captureReference(operationID))
      if let outcome = failed(result) { return outcome }
      guard case let .completed(.reference(frame, position, capAnchor)) = result else {
        return mismatch("Reference capture did not return an exact camera fact.")
      }
      anchorFrame = frame; referencePosition = position; referenceCapAnchor = capAnchor
    }
    guard let reference = referencePosition else { return mismatch("No reference pose is available for five-position calibration.") }
    updatePhase(.preparing)
    let planning = await execute(.fivePositionPlan(operationID, reference: reference))
    if let outcome = failed(planning) { return outcome }
    guard case let .completed(.fivePositionPlan(plan)) = planning,
      plan.samplePositions.count == 5, plan.motionDeltas.count == 5,
      plan.samplePositions[0] == reference
    else { return mismatch("Camera calibration requires a five-sample plan and a return-to-reference delta.") }
    var samples: [MachineCameraCorrespondenceProvenance] = []
    for index in plan.samplePositions.indices {
      if index == 0 {
        updatePhase(.capturing(sample: 1, total: 5, role: "C (fit)"))
        let capture = await execute(.captureSample(operationID, sample: index, expected: plan.samplePositions[index]))
        if let outcome = failed(capture) { return outcome }
        guard case let .completed(.sample(sample)) = capture else { return mismatch("Camera capture did not return a correspondence fact.") }
        samples.append(sample)
      } else {
        updatePhase(.moving(sample: index + 1, total: 5))
        let capture = await execute(.moveAndCapture(operationID, sample: index, expected: plan.samplePositions[index], delta: plan.motionDeltas[index - 1]))
        if let outcome = failed(capture) { return outcome }
        guard case let .completed(.sample(sample)) = capture else { return mismatch("Camera move/capture did not return a correspondence fact.") }
        samples.append(sample)
      }
    }
    updatePhase(.returningToReference)
    let returned = await execute(.returnToReference(operationID, reference: reference, delta: plan.motionDeltas[4]))
    if let outcome = failed(returned) { return outcome }
    guard case .completed(.returnedToReference) = returned else { return mismatch("Camera calibration did not prove the Pen-Up return to reference.") }
    updatePhase(.fittingAndTestingHoldouts)
    do {
      let fitSamples = Array(samples.prefix(3)); let holdouts = Array(samples.suffix(2))
      let candidate = try MachineCameraRegistrationFit.fit(correspondences: fitSamples.map { .init(machine: $0.machinePoint, camera: $0.capAnchorPoint) }, weights: fitSamples.map { max(0.01, $0.capAnchorConfidence * $0.capAnchorConfidence) })
      let residuals = try holdouts.map { try candidate.cameraPoint(from: $0.machinePoint).distance(to: $0.capAnchorPoint) }
      guard residuals.allSatisfy({ $0 <= 8 }) else { return mismatch("Independent cap holdouts failed. No camera proposal was staged.") }
      let final = try MachineCameraRegistrationFit.fit(correspondences: samples.map { .init(machine: $0.machinePoint, camera: $0.capAnchorPoint) }, weights: samples.map { max(0.01, $0.capAnchorConfidence * $0.capAnchorConfidence) })
      let registration = try MachineCameraRegistration(candidateFit: candidate, fit: final, source: anchorFrame!.source, opticalConfiguration: plan.opticalConfiguration, machineGeometry: plan.machineGeometry, controllerSessionID: plan.controllerSessionID, coordinateRevision: plan.coordinateRevision, cameraConfigurationID: anchorFrame!.frame.cameraConfigurationID, fitCorrespondenceProvenance: fitSamples, holdoutCorrespondenceProvenance: holdouts, maximumHoldoutResidualPixels: 8, estimatorRevision: "five-cap-affine-three-fit-two-holdout-v2:cap-\(samples[0].capAnchorEstimatorRevision)", uncertaintyPixels: max(final.maximumErrorPixels, residuals.max() ?? 0), applicabilityRectangle: plan.applicabilityRectangle, applicabilityDerivation: .boundaryEnvelopeInsetAndSymmetricallyReduced(safetyMarginMM: 10, maximumHalfSpanMM: 30))
      correspondenceEvidence = samples; proposedRegistration = registration; failure = nil; phase = nil
      return .completed
    } catch {
      return mismatch("Machine-camera registration failed: \(error)")
    }
  }
  private func apply(_ fact: PlotterCameraCalibrationEffectFact, intent: PlotterCameraCalibrationIntent) -> PlotterCameraCalibrationSubmissionOutcome {
    switch (intent, fact) {
    case let (.captureReference, .reference(frame, position, capAnchor)):
      anchorFrame = frame; referencePosition = position; referenceCapAnchor = capAnchor
      correspondenceEvidence = []; proposedRegistration = nil; failure = nil; phase = nil; return .completed
    case let (.buildFivePositionProposal, .proposal(registration, evidence)):
      guard evidence.count == 5, registration.correspondenceProvenance == evidence else {
        return mismatch("Five-position calibration must return exactly the five fitted correspondence facts.")
      }
      correspondenceEvidence = evidence; proposedRegistration = registration; failure = nil; phase = nil; return .completed
    case let (.acceptProposal, .accepted(registration)):
      guard registration == proposedRegistration else { return mismatch("Acceptance returned a registration different from the reviewed proposal.") }
      acceptedRegistration = registration; replacementPrepared = false; proposedRegistration = nil; failure = nil; phase = nil; return .completed
    case (.rejectProposal, .rejected):
      proposedRegistration = nil; anchorFrame = nil; referencePosition = nil; referenceCapAnchor = nil
      correspondenceEvidence = []; failure = nil; phase = nil; return .completed
    default: return mismatch("Camera-calibration lower effect returned a fact that does not satisfy the admitted intent.")
    }
  }
  private func mismatch(_ detail: String) -> PlotterCameraCalibrationSubmissionOutcome {
    failure = .init(code: .unexpectedFailure, detail: detail, recovery: .resolveNamedFailure); phase = nil
    publishStateChange()
    return .failed(detail)
  }
  private func updatePhase(_ newPhase: PlotterCameraCalibrationPhase) {
    phase = newPhase
    publishStateChange()
  }
  private func refusalReason(for intent: PlotterCameraCalibrationIntent) -> String {
    switch intent {
    case .captureReference: return "Reference capture is unavailable while calibration is active."
    case .buildFivePositionProposal: return "Prepare an explicit replacement attempt before rebuilding accepted camera calibration."
    case .acceptProposal: return "Acceptance requires one explicit reviewable camera proposal."
    case .rejectProposal: return "Rejection requires one explicit reviewable camera proposal."
    }
  }
  private func refuse(_ intent: PlotterCameraCalibrationIntent, _ detail: String) -> PlotterCameraCalibrationSubmissionOutcome {
    let outcome: PlotterCameraCalibrationSubmissionOutcome = .refused(detail); record(operationID: nil, intent: intent, outcome: outcome); return outcome
  }
  private func record(operationID: PlotterCameraCalibrationOperationID?, intent: PlotterCameraCalibrationIntent, outcome: PlotterCameraCalibrationSubmissionOutcome) {
    terminalHistory.append(.init(operationID: operationID, intent: intent, outcome: outcome))
    if terminalHistory.count > Self.terminalHistoryLimit { terminalHistory.removeFirst(terminalHistory.count - Self.terminalHistoryLimit) }
    publishStateChange()
  }
  private func publishStateChange() {
    revision &+= 1
    onStateChange()
  }
}
