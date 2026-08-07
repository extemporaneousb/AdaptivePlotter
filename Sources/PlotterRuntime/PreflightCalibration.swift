import Foundation
import PlotterModel

public enum PreflightSequenceClass: String, Codable, CaseIterable, Hashable, Sendable {
  case boundaryMeasurement
  case penPositionConfirmation

  public var displayName: String {
    switch self {
    case .boundaryMeasurement: "Boundary measurement"
    case .penPositionConfirmation: "Pen position confirmation"
    }
  }
}

public enum PreflightBoundaryDirection: String, Codable, CaseIterable, Hashable, Sendable {
  case negativeX
  case positiveX
  case negativeY
  case positiveY

  public var displayName: String {
    switch self {
    case .negativeX: "X−"
    case .positiveX: "X+"
    case .negativeY: "Y−"
    case .positiveY: "Y+"
    }
  }

  fileprivate var stableOrder: Int {
    switch self {
    case .negativeX: 0
    case .positiveX: 1
    case .negativeY: 2
    case .positiveY: 3
    }
  }
}

public enum PreflightSequenceID: String, Codable, CaseIterable, Hashable, Sendable {
  case boundaryNegativeX
  case boundaryPositiveX
  case boundaryNegativeY
  case boundaryPositiveY
  case penUpConfirmation
  case penDownConfirmation

  public var sequenceClass: PreflightSequenceClass {
    switch self {
    case .boundaryNegativeX, .boundaryPositiveX, .boundaryNegativeY, .boundaryPositiveY:
      .boundaryMeasurement
    case .penUpConfirmation, .penDownConfirmation:
      .penPositionConfirmation
    }
  }
}

public enum PreflightParticipant: String, Codable, CaseIterable, Hashable, Sendable {
  case application
  case operatorVoice
  case controller
  case camera
  case vision

  public var displayName: String {
    switch self {
    case .application: "AdaptivePlotter"
    case .operatorVoice: "Operator"
    case .controller: "Plotter controller"
    case .camera: "Camera"
    case .vision: "Vision"
    }
  }
}

/// Exact phrases are accepted only while their defining preflight step is current.
public enum PreflightVoiceResponse: String, Codable, CaseIterable, Hashable, Sendable {
  case ready = "READY"
  case stop = "STOP"
  case penIsPhysicallyUp = "PEN IS PHYSICALLY UP"
  case penIsPhysicallyDown = "PEN IS PHYSICALLY DOWN"

  public var exactPhrase: String { rawValue }
}

public struct PreflightVoiceContext: Hashable, Sendable {
  public let sequenceID: PreflightSequenceID
  public let stepID: String
  public let expectedResponse: PreflightVoiceResponse

  public init(
    sequenceID: PreflightSequenceID,
    stepID: String,
    expectedResponse: PreflightVoiceResponse
  ) {
    self.sequenceID = sequenceID
    self.stepID = stepID
    self.expectedResponse = expectedResponse
  }
}

public struct PreflightVoiceResponseParser: Sendable {
  public init() {}

  public func parse(
    _ transcript: String,
    in context: PreflightVoiceContext
  ) -> PreflightVoiceResponse? {
    let normalized = transcript
      .uppercased()
      .unicodeScalars
      .map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : " " }
    let phrase = String(normalized)
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
    return phrase == context.expectedResponse.exactPhrase
      ? context.expectedResponse
      : nil
  }
}

public enum PreflightAction: Hashable, Sendable {
  case startSpeechListening
  case stopSpeechListening
  case speakPrompt(String)
  case awaitVoice(PreflightVoiceResponse)
  case startBoundaryJog(PreflightBoundaryDirection)
  case cancelBoundaryJogAndAwaitIdle(PreflightBoundaryDirection)
  case captureFreshCameraFrame
  case measureBoundary(PreflightBoundaryDirection)
  case adjustDrawingFramePosterior(PreflightBoundaryDirection)
  case actuatePen(PenCommand)
  case awaitPhysicalPenConfirmation(PenState, response: PreflightVoiceResponse)
}

public enum PreflightEventExpectation: Hashable, Sendable {
  case speechListeningStarted
  case speechListeningStopped
  case promptSpoken
  case exactVoiceResponse(PreflightVoiceResponse)
  case boundaryJogStarted(PreflightBoundaryDirection)
  case boundaryJogCancelled(PreflightBoundaryDirection)
  case freshFrameCaptured
  case boundaryMeasured(PreflightBoundaryDirection)
  case drawingFramePosteriorAdjusted(PreflightBoundaryDirection)
  case penCommandSettled(PenCommand)
  case physicalPenConfirmed(PenState, response: PreflightVoiceResponse)

  fileprivate func accepts(_ event: PreflightEvent) -> Bool {
    switch (self, event) {
    case (.speechListeningStarted, .speechListeningStarted):
      true
    case (.speechListeningStopped, .speechListeningStopped):
      true
    case (.promptSpoken, .promptSpoken):
      true
    case (.exactVoiceResponse(let expected), .exactVoiceResponseAccepted(let actual)):
      expected == actual
    case (.boundaryJogStarted(let expected), .boundaryJogStarted(let actual, _)):
      expected == actual
    case (.boundaryJogCancelled(let expected), .boundaryJogCancelled(let actual, _, _)):
      expected == actual
    case (.freshFrameCaptured, .freshFrameCaptured):
      true
    case (.boundaryMeasured(let expected), .boundaryMeasured(let actual, _, _, _, _, _, _)):
      expected == actual
    case (
      .drawingFramePosteriorAdjusted(let expected),
      .drawingFramePosteriorAdjusted(let actual, _, _, _)
    ):
      expected == actual
    case (.penCommandSettled(let expected), .penCommandSettled(let actual, _)):
      expected == actual
    case (
      .physicalPenConfirmed(let expectedState, let expectedResponse),
      .physicalPenConfirmed(let actualState, let actualResponse, _)
    ):
      expectedState == actualState && expectedResponse == actualResponse
    default:
      false
    }
  }
}

public struct PreflightStep: Hashable, Sendable, Identifiable {
  public let id: String
  public let participant: PreflightParticipant
  public let action: PreflightAction
  public let expectedEvent: PreflightEventExpectation

  public init(
    id: String,
    participant: PreflightParticipant,
    action: PreflightAction,
    expectedEvent: PreflightEventExpectation
  ) {
    self.id = id
    self.participant = participant
    self.action = action
    self.expectedEvent = expectedEvent
  }

  public var expectedVoiceResponse: PreflightVoiceResponse? {
    switch action {
    case .awaitVoice(let response), .awaitPhysicalPenConfirmation(_, let response):
      response
    default:
      nil
    }
  }
}

public struct PreflightSequenceDefinition: Hashable, Sendable, Identifiable {
  public let id: PreflightSequenceID
  public let sequenceClass: PreflightSequenceClass
  public let title: String
  public let summary: String
  public let steps: [PreflightStep]

  public init(
    id: PreflightSequenceID,
    title: String,
    summary: String,
    steps: [PreflightStep]
  ) {
    self.id = id
    sequenceClass = id.sequenceClass
    self.title = title
    self.summary = summary
    self.steps = steps
  }

  public var voiceResponses: [PreflightVoiceResponse] {
    steps.compactMap(\.expectedVoiceResponse)
  }
}

public enum PreflightSequenceCatalog {
  public static let title = "Motion Preflight"

  public static let all: [PreflightSequenceDefinition] = PreflightSequenceID.allCases.map {
    definition(for: $0)
  }

  public static func definition(for id: PreflightSequenceID) -> PreflightSequenceDefinition {
    switch id {
    case .boundaryNegativeX:
      boundary(.negativeX, id: id)
    case .boundaryPositiveX:
      boundary(.positiveX, id: id)
    case .boundaryNegativeY:
      boundary(.negativeY, id: id)
    case .boundaryPositiveY:
      boundary(.positiveY, id: id)
    case .penUpConfirmation:
      pen(.up, command: .raise, response: .penIsPhysicallyUp, id: id)
    case .penDownConfirmation:
      pen(.down, command: .lower, response: .penIsPhysicallyDown, id: id)
    }
  }

  private static func boundary(
    _ direction: PreflightBoundaryDirection,
    id: PreflightSequenceID
  ) -> PreflightSequenceDefinition {
    PreflightSequenceDefinition(
      id: id,
      title: "\(direction.displayName) boundary",
      summary: "Motion Preflight voice-mediated jog and exact-frame observation for the \(direction.displayName) edge.",
      steps: [
        PreflightStep(
          id: "start-speech",
          participant: .application,
          action: .startSpeechListening,
          expectedEvent: .speechListeningStarted
        ),
        PreflightStep(
          id: "prompt-ready",
          participant: .application,
          action: .speakPrompt(
            "Check the path toward \(direction.displayName), then say READY. Say STOP at the physical boundary."
          ),
          expectedEvent: .promptSpoken
        ),
        PreflightStep(
          id: "voice-ready",
          participant: .operatorVoice,
          action: .awaitVoice(.ready),
          expectedEvent: .exactVoiceResponse(.ready)
        ),
        PreflightStep(
          id: "start-jog",
          participant: .controller,
          action: .startBoundaryJog(direction),
          expectedEvent: .boundaryJogStarted(direction)
        ),
        PreflightStep(
          id: "voice-stop",
          participant: .operatorVoice,
          action: .awaitVoice(.stop),
          expectedEvent: .exactVoiceResponse(.stop)
        ),
        PreflightStep(
          id: "cancel-and-idle",
          participant: .controller,
          action: .cancelBoundaryJogAndAwaitIdle(direction),
          expectedEvent: .boundaryJogCancelled(direction)
        ),
        PreflightStep(
          id: "capture-frame",
          participant: .camera,
          action: .captureFreshCameraFrame,
          expectedEvent: .freshFrameCaptured
        ),
        PreflightStep(
          id: "measure-boundary",
          participant: .vision,
          action: .measureBoundary(direction),
          expectedEvent: .boundaryMeasured(direction)
        ),
        PreflightStep(
          id: "adjust-posterior",
          participant: .vision,
          action: .adjustDrawingFramePosterior(direction),
          expectedEvent: .drawingFramePosteriorAdjusted(direction)
        ),
        PreflightStep(
          id: "stop-speech",
          participant: .application,
          action: .stopSpeechListening,
          expectedEvent: .speechListeningStopped
        ),
      ]
    )
  }

  private static func pen(
    _ state: PenState,
    command: PenCommand,
    response: PreflightVoiceResponse,
    id: PreflightSequenceID
  ) -> PreflightSequenceDefinition {
    let position = state == .up ? "up" : "down"
    return PreflightSequenceDefinition(
      id: id,
      title: "Confirm pen \(position)",
      summary: "Motion Preflight command and operator physical confirmation for pen \(position).",
      steps: [
        PreflightStep(
          id: "start-speech",
          participant: .application,
          action: .startSpeechListening,
          expectedEvent: .speechListeningStarted
        ),
        PreflightStep(
          id: "prompt-observe",
          participant: .application,
          action: .speakPrompt(
            "Observe the pen after the command, then say \(response.exactPhrase)."
          ),
          expectedEvent: .promptSpoken
        ),
        PreflightStep(
          id: "command-pen",
          participant: .controller,
          action: .actuatePen(command),
          expectedEvent: .penCommandSettled(command)
        ),
        PreflightStep(
          id: "confirm-physical-pen",
          participant: .operatorVoice,
          action: .awaitPhysicalPenConfirmation(state, response: response),
          expectedEvent: .physicalPenConfirmed(state, response: response)
        ),
        PreflightStep(
          id: "capture-paired-frame",
          participant: .camera,
          action: .captureFreshCameraFrame,
          expectedEvent: .freshFrameCaptured
        ),
        PreflightStep(
          id: "stop-speech",
          participant: .application,
          action: .stopSpeechListening,
          expectedEvent: .speechListeningStopped
        ),
      ]
    )
  }
}

public enum PreflightEvidenceKind: String, Codable, CaseIterable, Hashable, Sendable {
  case speechSystem
  case operatorVoice
  case operatorObservation
  case controller
  case camera
  case visionMeasurement
  case observedInk
}

/// Current-transaction evidence only. `observedInk` is deliberately distinct
/// from controller acceptance, camera capture, and inferred vision geometry.
public struct PreflightEvidenceSummary: Hashable, Sendable {
  public let kind: PreflightEvidenceKind
  public let summary: String
  public let frameID: FrameID?
  public let cameraConfigurationID: CameraConfigurationID?

  public init(
    kind: PreflightEvidenceKind,
    summary: String,
    frameID: FrameID? = nil,
    cameraConfigurationID: CameraConfigurationID? = nil
  ) {
    self.kind = kind
    self.summary = summary
    self.frameID = frameID
    self.cameraConfigurationID = cameraConfigurationID
  }
}

public enum PreflightEvent: Hashable, Sendable {
  case speechListeningStarted
  case speechListeningStopped
  case promptSpoken
  case exactVoiceResponseAccepted(PreflightVoiceResponse)
  case boundaryJogStarted(PreflightBoundaryDirection, controllerSummary: String)
  case boundaryJogCancelled(
    PreflightBoundaryDirection,
    finalPosition: MachinePosition,
    controllerSummary: String
  )
  case freshFrameCaptured(FrameID, CameraConfigurationID)
  case boundaryMeasured(
    PreflightBoundaryDirection,
    controllerPosition: MachinePosition,
    observedToolCentroid: Point2<CameraPixelSpace>,
    frameID: FrameID,
    cameraConfigurationID: CameraConfigurationID,
    confidence: Double,
    summary: String
  )
  case drawingFramePosteriorAdjusted(
    PreflightBoundaryDirection,
    frameID: FrameID,
    cameraConfigurationID: CameraConfigurationID,
    observationCount: Int
  )
  case penCommandSettled(PenCommand, controllerSummary: String)
  case physicalPenConfirmed(
    PenState,
    response: PreflightVoiceResponse,
    operatorSummary: String
  )

  fileprivate var evidenceSummary: PreflightEvidenceSummary? {
    switch self {
    case .speechListeningStarted:
      PreflightEvidenceSummary(
        kind: .speechSystem,
        summary: "Speech listening started for this Motion Preflight transaction."
      )
    case .speechListeningStopped:
      PreflightEvidenceSummary(
        kind: .speechSystem,
        summary: "Speech listening stopped for this Motion Preflight transaction."
      )
    case .promptSpoken:
      nil
    case .exactVoiceResponseAccepted(let response):
      PreflightEvidenceSummary(
        kind: .operatorVoice,
        summary: "Accepted exact phrase: \(response.exactPhrase)"
      )
    case .boundaryJogStarted(_, let summary),
      .boundaryJogCancelled(_, _, let summary),
      .penCommandSettled(_, let summary):
      PreflightEvidenceSummary(kind: .controller, summary: summary)
    case .freshFrameCaptured(let frameID, let configurationID):
      PreflightEvidenceSummary(
        kind: .camera,
        summary: "Captured exact preflight frame \(frameID.rawValue).",
        frameID: frameID,
        cameraConfigurationID: configurationID
      )
    case .boundaryMeasured(
      let direction,
      let controllerPosition,
      let observedToolCentroid,
      let frameID,
      let configurationID,
      _,
      let summary
    ):
      PreflightEvidenceSummary(
        kind: .visionMeasurement,
        summary:
          "\(direction.displayName) at controller X \(controllerPosition.point.x) Y \(controllerPosition.point.y), observed tool pixel X \(observedToolCentroid.x) Y \(observedToolCentroid.y): \(summary)",
        frameID: frameID,
        cameraConfigurationID: configurationID
      )
    case .drawingFramePosteriorAdjusted(
      let direction,
      let frameID,
      let configurationID,
      let observationCount
    ):
      PreflightEvidenceSummary(
        kind: .visionMeasurement,
        summary: "\(direction.displayName) adjusted the drawing-frame posterior from \(observationCount) observations.",
        frameID: frameID,
        cameraConfigurationID: configurationID
      )
    case .physicalPenConfirmed(let state, _, let summary):
      PreflightEvidenceSummary(
        kind: .operatorObservation,
        summary: "Pen physically \(state.rawValue): \(summary)"
      )
    }
  }
}

public enum PreflightTransactionState: Hashable, Sendable {
  case notStarted
  case active
  case cancelling
  case succeeded
  case failed(String)
  case cancelled
}

public enum PreflightTransactionError: Error, Equatable, Sendable {
  case alreadyStarted
  case notActive
  case noCurrentStep
  case unexpectedEvent(stepID: String)
  case invalidBoundaryConfidence
  case invalidPosteriorObservationCount
}

/// A small in-memory transaction for driving and presenting one sequence.
/// It has no persistence, replay, or cross-launch authority.
public struct PreflightTransaction: Hashable, Sendable, Identifiable {
  private static let cancellationSpeechStopStep = PreflightStep(
    id: "stop-speech-after-cancel",
    participant: .application,
    action: .stopSpeechListening,
    expectedEvent: .speechListeningStopped
  )

  public let id: UUID
  public let definition: PreflightSequenceDefinition
  public private(set) var state: PreflightTransactionState
  public private(set) var completedStepCount: Int
  public private(set) var evidenceSummaries: [PreflightEvidenceSummary]

  public init(id: UUID = UUID(), definition: PreflightSequenceDefinition) {
    self.id = id
    self.definition = definition
    state = .notStarted
    completedStepCount = 0
    evidenceSummaries = []
  }

  public init(id: UUID = UUID(), sequenceID: PreflightSequenceID) {
    self.init(id: id, definition: PreflightSequenceCatalog.definition(for: sequenceID))
  }

  public var currentStep: PreflightStep? {
    switch state {
    case .active where completedStepCount < definition.steps.count:
      return definition.steps[completedStepCount]
    case .cancelling:
      return Self.cancellationSpeechStopStep
    default:
      return nil
    }
  }

  public var progress: Double {
    guard !definition.steps.isEmpty else { return state == .succeeded ? 1 : 0 }
    return Double(completedStepCount) / Double(definition.steps.count)
  }

  public var voiceContext: PreflightVoiceContext? {
    guard let currentStep, let expectedResponse = currentStep.expectedVoiceResponse else {
      return nil
    }
    return PreflightVoiceContext(
      sequenceID: definition.id,
      stepID: currentStep.id,
      expectedResponse: expectedResponse
    )
  }

  public mutating func begin() throws {
    guard state == .notStarted else { throw PreflightTransactionError.alreadyStarted }
    state = definition.steps.isEmpty ? .succeeded : .active
  }

  public mutating func record(_ event: PreflightEvent) throws {
    if state == .cancelling {
      guard Self.cancellationSpeechStopStep.expectedEvent.accepts(event) else {
        throw PreflightTransactionError.unexpectedEvent(
          stepID: Self.cancellationSpeechStopStep.id
        )
      }
      if let evidence = event.evidenceSummary {
        evidenceSummaries.append(evidence)
      }
      state = .cancelled
      return
    }
    guard state == .active else { throw PreflightTransactionError.notActive }
    guard let step = currentStep else { throw PreflightTransactionError.noCurrentStep }
    try Self.validateEvidence(in: event)
    guard step.expectedEvent.accepts(event) else {
      throw PreflightTransactionError.unexpectedEvent(stepID: step.id)
    }
    if let evidence = event.evidenceSummary {
      evidenceSummaries.append(evidence)
    }
    completedStepCount += 1
    if completedStepCount == definition.steps.count {
      state = .succeeded
    }
  }

  public mutating func fail(_ actionableReason: String) {
    guard state == .active else { return }
    state = .failed(actionableReason)
  }

  public mutating func cancel() {
    switch state {
    case .notStarted:
      state = .cancelled
    case .active where completedStepCount == 0:
      state = .cancelled
    case .active:
      state = .cancelling
    default:
      break
    }
  }

  private static func validateEvidence(in event: PreflightEvent) throws {
    switch event {
    case .boundaryMeasured(_, _, _, _, _, let confidence, _):
      guard confidence.isFinite, confidence >= 0, confidence <= 1 else {
        throw PreflightTransactionError.invalidBoundaryConfidence
      }
    case .drawingFramePosteriorAdjusted(_, _, _, let count):
      guard count > 0 else {
        throw PreflightTransactionError.invalidPosteriorObservationCount
      }
    default:
      break
    }
  }
}

public enum PreflightRehearsalState: Hashable, Sendable {
  case notStarted
  case running
  case completed
  case cancelled
}

public enum PreflightRehearsalError: Error, Equatable, Sendable {
  case alreadyStarted
  case notRunning
}

/// Deterministic presentation-only playback of a Motion Preflight definition.
///
/// A rehearsal advances the same typed steps shown for physical preflight, but
/// it cannot emit controller events, speech transcripts, camera attestations,
/// evidence summaries, or training readiness. The application may use it to
/// explain the workflow while the simulator is selected.
public struct PreflightRehearsal: Hashable, Sendable {
  public let definition: PreflightSequenceDefinition
  public private(set) var state: PreflightRehearsalState
  public private(set) var completedStepCount: Int

  public init(definition: PreflightSequenceDefinition) {
    self.definition = definition
    state = .notStarted
    completedStepCount = 0
  }

  public init(sequenceID: PreflightSequenceID) {
    self.init(definition: PreflightSequenceCatalog.definition(for: sequenceID))
  }

  public var currentStep: PreflightStep? {
    guard state == .running, completedStepCount < definition.steps.count else { return nil }
    return definition.steps[completedStepCount]
  }

  public var progress: Double {
    guard !definition.steps.isEmpty else { return state == .completed ? 1 : 0 }
    return Double(completedStepCount) / Double(definition.steps.count)
  }

  public mutating func start() throws {
    guard state == .notStarted else { throw PreflightRehearsalError.alreadyStarted }
    state = definition.steps.isEmpty ? .completed : .running
  }

  public mutating func advance() throws {
    guard state == .running else { throw PreflightRehearsalError.notRunning }
    completedStepCount += 1
    if completedStepCount == definition.steps.count {
      state = .completed
    }
  }

  public mutating func cancel() {
    guard state == .running else { return }
    state = .cancelled
  }
}

public enum PreflightReadinessPolicyError: Error, Equatable, Sendable {
  case minimumMustBeAtLeastTwo
}

public struct PreflightTrainingReadiness: Hashable, Sendable {
  public let isReady: Bool
  public let successfulSequenceIDs: Set<PreflightSequenceID>
  public let successfulSequenceClasses: Set<PreflightSequenceClass>
  public let missingRequiredClasses: Set<PreflightSequenceClass>
  public let minimumSuccessfulSequenceClasses: Int
  public let currentPenState: PenState
  public let hasSuccessfulPenUpConfirmation: Bool
  public let hasCurrentPenUpConfirmation: Bool
}

public struct PreflightTrainingReadinessPolicy: Hashable, Sendable {
  public static let supervisedTraining = PreflightTrainingReadinessPolicy(
    validatedMinimum: 2,
    requiredSequenceClasses: Set(PreflightSequenceClass.allCases)
  )

  public let minimumSuccessfulSequenceClasses: Int
  public let requiredSequenceClasses: Set<PreflightSequenceClass>

  public init(
    minimumSuccessfulSequenceClasses: Int = 2,
    requiredSequenceClasses: Set<PreflightSequenceClass> = Set(
      PreflightSequenceClass.allCases)
  ) throws {
    guard minimumSuccessfulSequenceClasses >= 2 else {
      throw PreflightReadinessPolicyError.minimumMustBeAtLeastTwo
    }
    self.minimumSuccessfulSequenceClasses = minimumSuccessfulSequenceClasses
    self.requiredSequenceClasses = requiredSequenceClasses
  }

  private init(
    validatedMinimum: Int,
    requiredSequenceClasses: Set<PreflightSequenceClass>
  ) {
    minimumSuccessfulSequenceClasses = validatedMinimum
    self.requiredSequenceClasses = requiredSequenceClasses
  }

  /// Transaction order has no authority. A completed Pen Up transaction proves
  /// the voice-mediated observation occurred, while `currentPenState` supplies
  /// the live train-safe state. Both are required.
  public func evaluate(
    transactions: [PreflightTransaction],
    currentPenState: PenState
  ) -> PreflightTrainingReadiness {
    let successfulTransactions = transactions.filter { $0.state == .succeeded }
    let successfulIDs = Set(successfulTransactions.map(\.definition.id))
    let successfulClasses = Set(successfulIDs.map(\.sequenceClass))
    let missingClasses = requiredSequenceClasses.subtracting(successfulClasses)
    let hasSuccessfulPenUpConfirmation = successfulIDs.contains(.penUpConfirmation)
    let hasCurrentPenUpConfirmation = hasSuccessfulPenUpConfirmation
      && currentPenState == .up
    return PreflightTrainingReadiness(
      isReady: successfulClasses.count >= minimumSuccessfulSequenceClasses
        && missingClasses.isEmpty
        && hasCurrentPenUpConfirmation,
      successfulSequenceIDs: successfulIDs,
      successfulSequenceClasses: successfulClasses,
      missingRequiredClasses: missingClasses,
      minimumSuccessfulSequenceClasses: minimumSuccessfulSequenceClasses,
      currentPenState: currentPenState,
      hasSuccessfulPenUpConfirmation: hasSuccessfulPenUpConfirmation,
      hasCurrentPenUpConfirmation: hasCurrentPenUpConfirmation
    )
  }
}

public struct DrawingFrameBoundaryObservationKey: Hashable, Sendable {
  public let frameID: FrameID
  public let cameraConfigurationID: CameraConfigurationID
  public let direction: PreflightBoundaryDirection

  public init(
    frameID: FrameID,
    cameraConfigurationID: CameraConfigurationID,
    direction: PreflightBoundaryDirection
  ) {
    self.frameID = frameID
    self.cameraConfigurationID = cameraConfigurationID
    self.direction = direction
  }
}

public enum DrawingFramePosteriorError: Error, Equatable, Sendable {
  case invalidObservationConfidence
  case invalidEstimateConfidence
  case invalidBoundaryGeometry
  case topologyMismatch(expectedPointCount: Int, actualPointCount: Int)
}

public struct DrawingFrameBoundaryObservation: Hashable, Sendable {
  public let key: DrawingFrameBoundaryObservationKey
  public let controllerPosition: MachinePosition
  public let observedToolCentroid: Point2<CameraPixelSpace>
  public let estimate: DrawingFrameEstimate
  public let confidence: Double

  public init(
    frameID: FrameID,
    cameraConfigurationID: CameraConfigurationID,
    direction: PreflightBoundaryDirection,
    controllerPosition: MachinePosition,
    observedToolCentroid: Point2<CameraPixelSpace>,
    estimate: DrawingFrameEstimate,
    confidence: Double
  ) throws {
    guard confidence.isFinite, confidence > 0, confidence <= 1 else {
      throw DrawingFramePosteriorError.invalidObservationConfidence
    }
    guard estimate.confidence.isFinite, estimate.confidence >= 0, estimate.confidence <= 1 else {
      throw DrawingFramePosteriorError.invalidEstimateConfidence
    }
    key = DrawingFrameBoundaryObservationKey(
      frameID: frameID,
      cameraConfigurationID: cameraConfigurationID,
      direction: direction
    )
    self.controllerPosition = controllerPosition
    self.observedToolCentroid = observedToolCentroid
    self.estimate = estimate
    self.confidence = confidence
  }
}

/// Immutable current-camera posterior. Each exact frame/configuration/direction
/// key contributes at most once. A camera reconfiguration replaces the prior
/// rather than fusing geometry that no longer addresses the same pixels.
public struct DrawingFramePosterior: Hashable, Sendable {
  public let cameraConfigurationID: CameraConfigurationID
  public let latestObservationKey: DrawingFrameBoundaryObservationKey
  public let observationsByKey: [
    DrawingFrameBoundaryObservationKey: DrawingFrameBoundaryObservation
  ]
  public let estimate: DrawingFrameEstimate

  public init(prior observation: DrawingFrameBoundaryObservation) throws {
    try self.init(
      latestObservationKey: observation.key,
      observationsByKey: [observation.key: observation]
    )
  }

  private init(
    latestObservationKey: DrawingFrameBoundaryObservationKey,
    observationsByKey: [DrawingFrameBoundaryObservationKey: DrawingFrameBoundaryObservation]
  ) throws {
    let observations = Self.stablySorted(Array(observationsByKey.values))
    precondition(!observations.isEmpty)
    let first = observations[0]
    let expectedPointCount = first.estimate.geometry.points.count
    let expectedClosed = first.estimate.geometry.start == first.estimate.geometry.end
    for observation in observations.dropFirst() {
      let actualPointCount = observation.estimate.geometry.points.count
      guard actualPointCount == expectedPointCount,
        (observation.estimate.geometry.start == observation.estimate.geometry.end) == expectedClosed
      else {
        throw DrawingFramePosteriorError.topologyMismatch(
          expectedPointCount: expectedPointCount,
          actualPointCount: actualPointCount
        )
      }
    }
    cameraConfigurationID = first.key.cameraConfigurationID
    self.latestObservationKey = latestObservationKey
    self.observationsByKey = observationsByKey
    estimate = try Self.fuse(observations)
  }

  public var observationCount: Int { observationsByKey.count }

  public var observations: [DrawingFrameBoundaryObservation] {
    Self.stablySorted(Array(observationsByKey.values))
  }

  public func adding(
    _ observation: DrawingFrameBoundaryObservation
  ) throws -> DrawingFramePosterior {
    guard observation.key.cameraConfigurationID == cameraConfigurationID else {
      return try DrawingFramePosterior(prior: observation)
    }
    var updated = observationsByKey
    updated[observation.key] = observation
    return try DrawingFramePosterior(
      latestObservationKey: observation.key,
      observationsByKey: updated
    )
  }

  private static func stablySorted(
    _ observations: [DrawingFrameBoundaryObservation]
  ) -> [DrawingFrameBoundaryObservation] {
    observations.sorted { lhs, rhs in
      if lhs.key.direction.stableOrder != rhs.key.direction.stableOrder {
        return lhs.key.direction.stableOrder < rhs.key.direction.stableOrder
      }
      return lhs.key.frameID.rawValue < rhs.key.frameID.rawValue
    }
  }

  private static func fuse(
    _ observations: [DrawingFrameBoundaryObservation]
  ) throws -> DrawingFrameEstimate {
    let weightSum = observations.reduce(0) { $0 + $1.confidence }
    let pointCount = observations[0].estimate.geometry.points.count
    let anchoredPoints = try observations.map(boundaryAnchoredPoints)
    var points: [Point2<CameraPixelSpace>] = []
    points.reserveCapacity(pointCount)
    for pointIndex in 0..<pointCount {
      let x = observations.indices.reduce(0) {
        $0 + anchoredPoints[$1][pointIndex].x * observations[$1].confidence
      } / weightSum
      let y = observations.indices.reduce(0) {
        $0 + anchoredPoints[$1][pointIndex].y * observations[$1].confidence
      } / weightSum
      points.append(try Point2(x: x, y: y))
    }
    let confidence = observations.reduce(0) {
      $0 + $1.estimate.confidence * $1.confidence
    } / weightSum
    let sourceBases = Set(observations.map(\.estimate.basis)).sorted().joined(separator: " | ")
    return DrawingFrameEstimate(
      geometry: try Polyline(points: points),
      confidence: confidence,
      basis: "confidence-weighted boundary posterior constrained by controller final MPos and exact-frame observed tool centroids; unobserved frame geometry remains inferred; source basis: \(sourceBases)"
    )
  }

  /// Moves the closest side of the inferred quadrilateral along its normal so
  /// it passes through the tool centroid observed at the controller boundary.
  /// The chosen side is an image-space vision decision; direction and final
  /// MPos remain typed evidence on the observation rather than being treated as
  /// interchangeable pixel coordinates.
  private static func boundaryAnchoredPoints(
    _ observation: DrawingFrameBoundaryObservation
  ) throws -> [Point2<CameraPixelSpace>] {
    let source = observation.estimate.geometry.points
    guard source.count == 5, source.first == source.last else {
      throw DrawingFramePosteriorError.invalidBoundaryGeometry
    }
    let uniquePointCount = source.count - 1
    var selectedEdge: Int?
    var selectedDistanceSquared = Double.infinity

    for startIndex in 0..<uniquePointCount {
      let endIndex = (startIndex + 1) % uniquePointCount
      let start = source[startIndex]
      let end = source[endIndex]
      let dx = end.x - start.x
      let dy = end.y - start.y
      let lengthSquared = dx * dx + dy * dy
      guard lengthSquared > 0 else { continue }
      let rawProjection =
        ((observation.observedToolCentroid.x - start.x) * dx
          + (observation.observedToolCentroid.y - start.y) * dy) / lengthSquared
      let projection = min(1, max(0, rawProjection))
      let closestX = start.x + projection * dx
      let closestY = start.y + projection * dy
      let offsetX = observation.observedToolCentroid.x - closestX
      let offsetY = observation.observedToolCentroid.y - closestY
      let distanceSquared = offsetX * offsetX + offsetY * offsetY
      if distanceSquared < selectedDistanceSquared {
        selectedDistanceSquared = distanceSquared
        selectedEdge = startIndex
      }
    }

    guard let startIndex = selectedEdge else {
      throw DrawingFramePosteriorError.invalidBoundaryGeometry
    }
    let endIndex = (startIndex + 1) % uniquePointCount
    let start = source[startIndex]
    let end = source[endIndex]
    let dx = end.x - start.x
    let dy = end.y - start.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0 else {
      throw DrawingFramePosteriorError.invalidBoundaryGeometry
    }
    let projection =
      ((observation.observedToolCentroid.x - start.x) * dx
        + (observation.observedToolCentroid.y - start.y) * dy) / lengthSquared
    let projectedX = start.x + projection * dx
    let projectedY = start.y + projection * dy
    let shiftX = observation.observedToolCentroid.x - projectedX
    let shiftY = observation.observedToolCentroid.y - projectedY

    var adjusted = source
    adjusted[startIndex] = try Point2(x: start.x + shiftX, y: start.y + shiftY)
    adjusted[endIndex] = try Point2(x: end.x + shiftX, y: end.y + shiftY)
    adjusted[uniquePointCount] = adjusted[0]
    return adjusted
  }
}
