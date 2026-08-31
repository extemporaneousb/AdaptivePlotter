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
  private var admissionClosed = false
  private var activeTask: Task<PlotterCameraCalibrationSubmissionOutcome, Never>?
  private var terminalHistory: [PlotterCameraCalibrationTerminalRecord] = []
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
  public init(effectPort: any PlotterCameraCalibrationEffectPort) { self.effectPort = effectPort }

  @discardableResult public func submit(_ intent: PlotterCameraCalibrationIntent) async -> PlotterCameraCalibrationSubmissionOutcome {
    guard !admissionClosed else { return .cancelled }
    guard activeTask == nil else { return refuse(intent, "Camera calibration already has an active operator effect.") }
    guard admits(intent) else { return refuse(intent, refusalReason(for: intent)) }
    let operationID = PlotterCameraCalibrationOperationID()
    activeOperationID = operationID; activeIntent = intent
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
    guard activeOperationID == operationID, activeIntent == intent, !admissionClosed else { return .cancelled }
    activeTask = nil; activeOperationID = nil; activeIntent = nil
    record(operationID: operationID, intent: intent, outcome: outcome)
    return outcome
  }

  /// Close admission before cancelling so Stop/shutdown cannot admit a late fact.
  public func shutdown() async {
    guard !admissionClosed else { return }
    admissionClosed = true
    let operationID = activeOperationID; let intent = activeIntent
    let task = activeTask
    task?.cancel()
    _ = await task?.value
    activeTask = nil; activeOperationID = nil; activeIntent = nil
    if let intent { record(operationID: operationID, intent: intent, outcome: .cancelled) }
  }
  public func snapshot() -> PlotterCameraCalibrationRuntimeSnapshot {
    .init(admissionClosed: admissionClosed, activeOperationID: activeOperationID, activeIntent: activeIntent,
      anchorFrame: anchorFrame, referencePosition: referencePosition, referenceCapAnchor: referenceCapAnchor,
      correspondenceEvidence: correspondenceEvidence, proposedRegistration: proposedRegistration,
      acceptedRegistration: acceptedRegistration, phase: phase, failure: failure, terminalHistory: terminalHistory)
  }
  /// Persistence recovery can restore only an already accepted registration.
  public func restoreAcceptedRegistration(_ registration: MachineCameraRegistration?) { acceptedRegistration = registration }
  /// Transitional App-side fact installation used by the bounded controller/Vision
  /// effect before its matching result is returned to this runtime.
  public func installReference(frame: DisplayedFrame, position: MachinePosition, capAnchor: ToolCapAnchorEstimate) {
    anchorFrame = frame; referencePosition = position; referenceCapAnchor = capAnchor
    correspondenceEvidence = []; proposedRegistration = nil; failure = nil
  }
  public func replaceProposal(_ registration: MachineCameraRegistration?) { proposedRegistration = registration }
  public func replaceCorrespondenceEvidence(_ evidence: [MachineCameraCorrespondenceProvenance]) { correspondenceEvidence = evidence }
  public func replaceFailure(_ failure: PlotterCameraCalibrationFailure?) { self.failure = failure }
  public func clearForReset() {
    anchorFrame = nil; referencePosition = nil; referenceCapAnchor = nil; correspondenceEvidence = []
    proposedRegistration = nil; acceptedRegistration = nil; phase = nil; failure = nil
  }
  /// Progress is reported by the bounded App effect; terminal state remains here.
  public func reportPhase(_ phase: PlotterCameraCalibrationPhase?) { self.phase = phase }

  private func admits(_ intent: PlotterCameraCalibrationIntent) -> Bool {
    switch intent {
    case .captureReference: return phase == nil
    case .buildFivePositionProposal: return phase == nil && acceptedRegistration == nil
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
    case .failed(let failure): self.failure = failure; phase = nil; return .failed(failure.detail)
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
      case .failed(let failure): self.failure = failure; self.phase = nil; return .failed(failure.detail)
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
    phase = .preparing
    let planning = await execute(.fivePositionPlan(operationID, reference: reference))
    if let outcome = failed(planning) { return outcome }
    guard case let .completed(.fivePositionPlan(plan)) = planning,
      plan.samplePositions.count == 5, plan.motionDeltas.count == 5,
      plan.samplePositions[0] == reference
    else { return mismatch("Camera calibration requires a five-sample plan and a return-to-reference delta.") }
    var samples: [MachineCameraCorrespondenceProvenance] = []
    for index in plan.samplePositions.indices {
      if index == 0 {
        phase = .capturing(sample: 1, total: 5, role: "C (fit)")
        let capture = await execute(.captureSample(operationID, sample: index, expected: plan.samplePositions[index]))
        if let outcome = failed(capture) { return outcome }
        guard case let .completed(.sample(sample)) = capture else { return mismatch("Camera capture did not return a correspondence fact.") }
        samples.append(sample)
      } else {
        phase = .moving(sample: index + 1, total: 5)
        let capture = await execute(.moveAndCapture(operationID, sample: index, expected: plan.samplePositions[index], delta: plan.motionDeltas[index - 1]))
        if let outcome = failed(capture) { return outcome }
        guard case let .completed(.sample(sample)) = capture else { return mismatch("Camera move/capture did not return a correspondence fact.") }
        samples.append(sample)
      }
    }
    phase = .returningToReference
    let returned = await execute(.returnToReference(operationID, reference: reference, delta: plan.motionDeltas[4]))
    if let outcome = failed(returned) { return outcome }
    guard case .completed(.returnedToReference) = returned else { return mismatch("Camera calibration did not prove the Pen-Up return to reference.") }
    phase = .fittingAndTestingHoldouts
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
      acceptedRegistration = registration; proposedRegistration = nil; failure = nil; phase = nil; return .completed
    case (.rejectProposal, .rejected):
      proposedRegistration = nil; anchorFrame = nil; referencePosition = nil; referenceCapAnchor = nil
      correspondenceEvidence = []; failure = nil; phase = nil; return .completed
    default: return mismatch("Camera-calibration lower effect returned a fact that does not satisfy the admitted intent.")
    }
  }
  private func mismatch(_ detail: String) -> PlotterCameraCalibrationSubmissionOutcome {
    failure = .init(code: .unexpectedFailure, detail: detail, recovery: .resolveNamedFailure); phase = nil
    return .failed(detail)
  }
  private func refusalReason(for intent: PlotterCameraCalibrationIntent) -> String {
    switch intent {
    case .captureReference: return "Reference capture is unavailable while calibration is active."
    case .buildFivePositionProposal: return "Proposal construction requires no accepted machine-camera registration."
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
  }
}
