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
  case penCycleConfirmation

  public var sequenceClass: PreflightSequenceClass {
    switch self {
    case .boundaryNegativeX, .boundaryPositiveX, .boundaryNegativeY, .boundaryPositiveY:
      .boundaryMeasurement
    case .penCycleConfirmation:
      .penPositionConfirmation
    }
  }
}

public enum PreflightParticipant: String, Codable, CaseIterable, Hashable, Sendable {
  case application
  case operatorChoice
  case controller
  case camera
  case vision

  public var displayName: String {
    switch self {
    case .application: "AdaptivePlotter"
    case .operatorChoice: "Operator"
    case .controller: "Plotter controller"
    case .camera: "Camera"
    case .vision: "Vision"
    }
  }
}

/// Short answers are accepted only while their defining preflight question is
/// current. A response has no ambient controller meaning.
public enum PreflightVoiceResponse: String, Codable, CaseIterable, Hashable, Sendable {
  case yes = "YES"
  case no = "NO"
  case stop = "STOP"

  public var exactPhrase: String { rawValue }
}

public struct PreflightVoiceQuestion: Hashable, Sendable {
  public let prompt: String
  public let choices: [PreflightVoiceResponse]
  public let advancingResponses: Set<PreflightVoiceResponse>
  public let negativeAcknowledgement: String

  public init(
    prompt: String,
    choices: [PreflightVoiceResponse] = [.yes, .no],
    advancingResponses: Set<PreflightVoiceResponse> = [.yes],
    negativeAcknowledgement: String
  ) {
    precondition(!choices.isEmpty)
    precondition(advancingResponses.isSubset(of: Set(choices)))
    self.prompt = prompt
    self.choices = choices
    self.advancingResponses = advancingResponses
    self.negativeAcknowledgement = negativeAcknowledgement
  }

  public var choiceLabel: String {
    choices.map(\.exactPhrase).joined(separator: " / ")
  }
}

public struct PreflightVoiceContext: Hashable, Sendable {
  public let sequenceID: PreflightSequenceID
  public let stepID: String
  public let question: PreflightVoiceQuestion

  public init(
    sequenceID: PreflightSequenceID,
    stepID: String,
    question: PreflightVoiceQuestion
  ) {
    self.sequenceID = sequenceID
    self.stepID = stepID
    self.question = question
  }

  public var expectedResponses: Set<PreflightVoiceResponse> {
    question.advancingResponses
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
    return context.question.choices.first { phrase == $0.exactPhrase }
  }
}

public enum PreflightAction: Hashable, Sendable {
  case askQuestion(PreflightVoiceQuestion)
  case awaitVoiceChoice(PreflightVoiceQuestion)
  case startBoundaryJog(PreflightBoundaryDirection)
  case cancelBoundaryJogAndAwaitIdle(PreflightBoundaryDirection)
  case captureFreshCameraFrame
  case measureBoundary(PreflightBoundaryDirection)
  case adjustDrawingFramePosterior(PreflightBoundaryDirection)
  case actuatePen(PenCommand)
  case awaitPhysicalPenConfirmation(PenState, question: PreflightVoiceQuestion)
}

public enum PreflightEventExpectation: Hashable, Sendable {
  case questionPresented
  case exactVoiceResponse(Set<PreflightVoiceResponse>)
  case boundaryJogStarted(PreflightBoundaryDirection)
  case boundaryJogCancelled(PreflightBoundaryDirection)
  case freshFrameCaptured
  case boundaryMeasured(PreflightBoundaryDirection)
  case drawingFramePosteriorAdjusted(PreflightBoundaryDirection)
  case penCommandSettled(PenCommand)
  case physicalPenConfirmed(PenState, response: PreflightVoiceResponse)

  fileprivate func accepts(_ event: PreflightEvent) -> Bool {
    switch (self, event) {
    case (.questionPresented, .questionPresented):
      true
    case (.exactVoiceResponse(let expected), .exactVoiceResponseAccepted(let actual)):
      expected.contains(actual)
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

  public var voiceQuestion: PreflightVoiceQuestion? {
    switch action {
    case .awaitVoiceChoice(let question), .awaitPhysicalPenConfirmation(_, let question):
      question
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

  public var voiceQuestions: [PreflightVoiceQuestion] {
    steps.compactMap(\.voiceQuestion)
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
    case .penCycleConfirmation:
      penCycle(id: id)
    }
  }

  private static func boundary(
    _ direction: PreflightBoundaryDirection,
    id: PreflightSequenceID
  ) -> PreflightSequenceDefinition {
    let readyQuestion = PreflightVoiceQuestion(
      prompt: "Is the path clear and are you ready to move toward \(direction.displayName)?",
      negativeAcknowledgement: "Okay. No motion will start. I will wait."
    )
    let boundaryQuestion = PreflightVoiceQuestion(
      prompt: "Are we at the \(direction.displayName) boundary?",
      choices: [.yes, .no, .stop],
      advancingResponses: [.yes, .stop],
      negativeAcknowledgement: "Continuing the bounded movement."
    )
    return PreflightSequenceDefinition(
      id: id,
      title: "\(direction.displayName) boundary",
      summary: "Motion Preflight question-guided jog and exact-frame observation for the \(direction.displayName) edge.",
      steps: [
        PreflightStep(
          id: "question-ready",
          participant: .application,
          action: .askQuestion(readyQuestion),
          expectedEvent: .questionPresented
        ),
        PreflightStep(
          id: "answer-ready",
          participant: .operatorChoice,
          action: .awaitVoiceChoice(readyQuestion),
          expectedEvent: .exactVoiceResponse(readyQuestion.advancingResponses)
        ),
        PreflightStep(
          id: "start-jog",
          participant: .controller,
          action: .startBoundaryJog(direction),
          expectedEvent: .boundaryJogStarted(direction)
        ),
        PreflightStep(
          id: "question-boundary",
          participant: .application,
          action: .askQuestion(boundaryQuestion),
          expectedEvent: .questionPresented
        ),
        PreflightStep(
          id: "answer-boundary",
          participant: .operatorChoice,
          action: .awaitVoiceChoice(boundaryQuestion),
          expectedEvent: .exactVoiceResponse(boundaryQuestion.advancingResponses)
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
      ]
    )
  }

  private static func penCycle(id: PreflightSequenceID) -> PreflightSequenceDefinition {
    let initiallyUp = PreflightVoiceQuestion(
      prompt: "Is the pen currently up?",
      negativeAcknowledgement:
        "The sequence needs an observed up position before it can continue. I will wait."
    )
    let clearToLower = PreflightVoiceQuestion(
      prompt: "Are we clear to put it down?",
      negativeAcknowledgement: "Okay. I will not lower it. I will wait."
    )
    let currentlyDown = PreflightVoiceQuestion(
      prompt: "Is the pen currently down?",
      negativeAcknowledgement:
        "The down position was not confirmed. I will command Pen Up and end this cycle."
    )
    let finallyUp = PreflightVoiceQuestion(
      prompt: "Is the pen up?",
      negativeAcknowledgement: "The final up position was not confirmed. I will wait."
    )
    return PreflightSequenceDefinition(
      id: id,
      title: "Pen cycle",
      summary:
        "Confirm up, authorize down, observe down, retract, and confirm up using YES or NO answers.",
      steps: [
        PreflightStep(
          id: "question-initially-up",
          participant: .application,
          action: .askQuestion(initiallyUp),
          expectedEvent: .questionPresented
        ),
        PreflightStep(
          id: "answer-initially-up",
          participant: .operatorChoice,
          action: .awaitPhysicalPenConfirmation(.up, question: initiallyUp),
          expectedEvent: .physicalPenConfirmed(.up, response: .yes)
        ),
        PreflightStep(
          id: "question-clear-to-lower",
          participant: .application,
          action: .askQuestion(clearToLower),
          expectedEvent: .questionPresented
        ),
        PreflightStep(
          id: "answer-clear-to-lower",
          participant: .operatorChoice,
          action: .awaitVoiceChoice(clearToLower),
          expectedEvent: .exactVoiceResponse(clearToLower.advancingResponses)
        ),
        PreflightStep(
          id: "command-down",
          participant: .controller,
          action: .actuatePen(.lower),
          expectedEvent: .penCommandSettled(.lower)
        ),
        PreflightStep(
          id: "question-currently-down",
          participant: .application,
          action: .askQuestion(currentlyDown),
          expectedEvent: .questionPresented
        ),
        PreflightStep(
          id: "answer-currently-down",
          participant: .operatorChoice,
          action: .awaitPhysicalPenConfirmation(.down, question: currentlyDown),
          expectedEvent: .physicalPenConfirmed(.down, response: .yes)
        ),
        PreflightStep(
          id: "capture-down-frame",
          participant: .camera,
          action: .captureFreshCameraFrame,
          expectedEvent: .freshFrameCaptured
        ),
        PreflightStep(
          id: "command-up",
          participant: .controller,
          action: .actuatePen(.raise),
          expectedEvent: .penCommandSettled(.raise)
        ),
        PreflightStep(
          id: "question-finally-up",
          participant: .application,
          action: .askQuestion(finallyUp),
          expectedEvent: .questionPresented
        ),
        PreflightStep(
          id: "answer-finally-up",
          participant: .operatorChoice,
          action: .awaitPhysicalPenConfirmation(.up, question: finallyUp),
          expectedEvent: .physicalPenConfirmed(.up, response: .yes)
        ),
        PreflightStep(
          id: "capture-up-frame",
          participant: .camera,
          action: .captureFreshCameraFrame,
          expectedEvent: .freshFrameCaptured
        ),
      ]
    )
  }
}

public enum PreflightEvidenceKind: String, Codable, CaseIterable, Hashable, Sendable {
  case speechSystem
  case operatorChoice
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
  case questionPresented
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
    case .questionPresented:
      nil
    case .exactVoiceResponseAccepted(let response):
      PreflightEvidenceSummary(
        kind: .operatorChoice,
        summary: "Accepted contextual choice: \(response.exactPhrase)"
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
    default:
      return nil
    }
  }

  public var progress: Double {
    guard !definition.steps.isEmpty else { return state == .succeeded ? 1 : 0 }
    return Double(completedStepCount) / Double(definition.steps.count)
  }

  public var voiceContext: PreflightVoiceContext? {
    guard let currentStep, let question = currentStep.voiceQuestion else {
      return nil
    }
    return PreflightVoiceContext(
      sequenceID: definition.id,
      stepID: currentStep.id,
      question: question
    )
  }

  public mutating func begin() throws {
    guard state == .notStarted else { throw PreflightTransactionError.alreadyStarted }
    state = definition.steps.isEmpty ? .succeeded : .active
  }

  public mutating func record(_ event: PreflightEvent) throws {
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
    case .active:
      state = .cancelled
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
/// it cannot emit controller events, camera attestations, evidence summaries,
/// or training readiness. An application may use `voiceContext` to advance an
/// operator step from a real transcript while still keeping the rehearsal
/// completely outside physical and learning authority.
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

  public var voiceContext: PreflightVoiceContext? {
    guard let currentStep, let question = currentStep.voiceQuestion else {
      return nil
    }
    return PreflightVoiceContext(
      sequenceID: definition.id,
      stepID: currentStep.id,
      question: question
    )
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

  /// Transaction order has no authority. A completed Pen Cycle proves the
  /// operator confirmed the final up state, while `currentPenState` supplies
  /// the live train-safe state. Both are required.
  public func evaluate(
    transactions: [PreflightTransaction],
    currentPenState: PenState
  ) -> PreflightTrainingReadiness {
    let successfulTransactions = transactions.filter { $0.state == .succeeded }
    let successfulIDs = Set(successfulTransactions.map(\.definition.id))
    let successfulClasses = Set(successfulIDs.map(\.sequenceClass))
    let missingClasses = requiredSequenceClasses.subtracting(successfulClasses)
    let hasSuccessfulPenUpConfirmation = successfulIDs.contains(.penCycleConfirmation)
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
  case invalidObservationVariance
  case invalidAssociationDistanceMargin
  case invalidBroadPriorVariance
  case invalidEstimateConfidence
  case invalidBoundaryGeometry
  case ambiguousEdgeAssociation(
    nearestDistance: Double,
    runnerUpDistance: Double,
    requiredMargin: Double
  )
  case candidateEdgeAlreadyAssociated(candidateEdgeIndex: Int)
}

public struct DrawingFrameBoundaryObservation: Hashable, Sendable {
  public let key: DrawingFrameBoundaryObservationKey
  public let frameSHA256: String
  public let captureNanoseconds: UInt64
  public let controllerPosition: MachinePosition
  public let observedToolCentroid: Point2<CameraPixelSpace>
  public let estimate: DrawingFrameEstimate
  public let observationVariance: Double
  public let associationDistanceMargin: Double
  public let broadPriorVariance: Double

  public init(
    frameID: FrameID,
    frameSHA256: String,
    captureNanoseconds: UInt64,
    cameraConfigurationID: CameraConfigurationID,
    direction: PreflightBoundaryDirection,
    controllerPosition: MachinePosition,
    observedToolCentroid: Point2<CameraPixelSpace>,
    estimate: DrawingFrameEstimate,
    observationVariance: Double,
    associationDistanceMargin: Double,
    broadPriorVariance: Double
  ) throws {
    guard observationVariance.isFinite, observationVariance > 0 else {
      throw DrawingFramePosteriorError.invalidObservationVariance
    }
    guard associationDistanceMargin.isFinite, associationDistanceMargin >= 0 else {
      throw DrawingFramePosteriorError.invalidAssociationDistanceMargin
    }
    guard broadPriorVariance.isFinite, broadPriorVariance > 0 else {
      throw DrawingFramePosteriorError.invalidBroadPriorVariance
    }
    guard estimate.confidence.isFinite, estimate.confidence >= 0, estimate.confidence <= 1 else {
      throw DrawingFramePosteriorError.invalidEstimateConfidence
    }
    key = DrawingFrameBoundaryObservationKey(
      frameID: frameID,
      cameraConfigurationID: cameraConfigurationID,
      direction: direction
    )
    self.frameSHA256 = frameSHA256
    self.captureNanoseconds = captureNanoseconds
    self.controllerPosition = controllerPosition
    self.observedToolCentroid = observedToolCentroid
    self.estimate = estimate
    self.observationVariance = observationVariance
    self.associationDistanceMargin = associationDistanceMargin
    self.broadPriorVariance = broadPriorVariance
  }
}

public struct DrawingFrameSideAssociation: Hashable, Sendable {
  public let machineSide: PreflightBoundaryDirection
  public let candidateEdgeIndex: Int
  public let referenceStart: Point2<CameraPixelSpace>
  public let referenceEnd: Point2<CameraPixelSpace>
  public let initializedFromFrameID: FrameID
}

public struct DrawingFrameSidePosterior: Hashable, Sendable {
  public let association: DrawingFrameSideAssociation
  public let orientationRadians: Double
  public let orientationVariance: Double
  public let offsetPixels: Double
  public let offsetVariance: Double
  public let observationCount: Int

  public var standardDeviationPixels: Double { sqrt(offsetVariance) }

  public var geometry: Polyline<CameraPixelSpace> {
    let line = Self.lineComponents(for: association)
    let shiftX = line.normalX * offsetPixels
    let shiftY = line.normalY * offsetPixels
    return try! Polyline(points: [
      Point2(
        x: association.referenceStart.x + shiftX,
        y: association.referenceStart.y + shiftY
      ),
      Point2(
        x: association.referenceEnd.x + shiftX,
        y: association.referenceEnd.y + shiftY
      ),
    ])
  }

  fileprivate static func lineComponents(
    for association: DrawingFrameSideAssociation
  ) -> (tangentX: Double, tangentY: Double, normalX: Double, normalY: Double) {
    let dx = association.referenceEnd.x - association.referenceStart.x
    let dy = association.referenceEnd.y - association.referenceStart.y
    let length = hypot(dx, dy)
    return (dx / length, dy / length, -dy / length, dx / length)
  }
}

public enum DrawingFrameCorner: Int, Codable, CaseIterable, Hashable, Sendable {
  case candidateVertex0
  case candidateVertex1
  case candidateVertex2
  case candidateVertex3
}

/// Immutable current-camera posterior. The sequence direction is the machine-
/// side identity. Its first unambiguous observation establishes a persistent
/// camera-edge association; later exact centroids update only that side's
/// image-space offset. Controller MPos remains stored provenance only.
public struct DrawingFramePosterior: Hashable, Sendable {
  public let cameraConfigurationID: CameraConfigurationID
  public let latestObservationKey: DrawingFrameBoundaryObservationKey
  public let observationsByKey: [
    DrawingFrameBoundaryObservationKey: DrawingFrameBoundaryObservation
  ]
  public let sidePosteriors: [PreflightBoundaryDirection: DrawingFrameSidePosterior]
  public let associations: [PreflightBoundaryDirection: DrawingFrameSideAssociation]
  public let derivedCorners: [DrawingFrameCorner: Point2<CameraPixelSpace>]
  public let estimate: DrawingFrameEstimate?

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
    cameraConfigurationID = first.key.cameraConfigurationID
    self.latestObservationKey = latestObservationKey
    self.observationsByKey = observationsByKey
    let fitted = try Self.fitSides(observations)
    sidePosteriors = fitted
    associations = fitted.mapValues(\.association)
    derivedCorners = Self.corners(from: fitted)
    estimate = try Self.closedEstimate(from: fitted, corners: derivedCorners)
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
      if lhs.captureNanoseconds != rhs.captureNanoseconds {
        return lhs.captureNanoseconds < rhs.captureNanoseconds
      }
      return lhs.key.frameID.rawValue < rhs.key.frameID.rawValue
    }
  }

  private static func fitSides(
    _ observations: [DrawingFrameBoundaryObservation]
  ) throws -> [PreflightBoundaryDirection: DrawingFrameSidePosterior] {
    var fitted: [PreflightBoundaryDirection: DrawingFrameSidePosterior] = [:]
    var claimedCandidateEdges: [Int: PreflightBoundaryDirection] = [:]
    for direction in PreflightBoundaryDirection.allCases {
      let sideObservations = observations.filter { $0.key.direction == direction }
      guard let first = sideObservations.first else { continue }
      let association = try associate(first)
      if let owner = claimedCandidateEdges[association.candidateEdgeIndex], owner != direction {
        throw DrawingFramePosteriorError.candidateEdgeAlreadyAssociated(
          candidateEdgeIndex: association.candidateEdgeIndex
        )
      }
      claimedCandidateEdges[association.candidateEdgeIndex] = direction
      let line = DrawingFrameSidePosterior.lineComponents(for: association)
      var precision = 1 / first.broadPriorVariance
      var weightedOffset = 0.0
      for observation in sideObservations {
        let measuredOffset =
          (observation.observedToolCentroid.x - association.referenceStart.x) * line.normalX
          + (observation.observedToolCentroid.y - association.referenceStart.y) * line.normalY
        let observationPrecision = 1 / observation.observationVariance
        precision += observationPrecision
        weightedOffset += measuredOffset * observationPrecision
      }
      let dx = association.referenceEnd.x - association.referenceStart.x
      let dy = association.referenceEnd.y - association.referenceStart.y
      fitted[direction] = DrawingFrameSidePosterior(
        association: association,
        orientationRadians: atan2(dy, dx),
        orientationVariance: first.broadPriorVariance,
        offsetPixels: weightedOffset / precision,
        offsetVariance: 1 / precision,
        observationCount: sideObservations.count
      )
    }
    return fitted
  }

  private static func associate(
    _ observation: DrawingFrameBoundaryObservation
  ) throws -> DrawingFrameSideAssociation {
    let points = observation.estimate.geometry.points
    guard points.count == 5, points.first == points.last else {
      throw DrawingFramePosteriorError.invalidBoundaryGeometry
    }
    var candidates: [(index: Int, distance: Double)] = []
    for index in 0..<4 {
      let start = points[index]
      let end = points[index + 1]
      let distance = segmentDistance(
        from: observation.observedToolCentroid,
        start: start,
        end: end
      )
      candidates.append((index: index, distance: distance))
    }
    candidates.sort { lhs, rhs in
      lhs.distance == rhs.distance ? lhs.index < rhs.index : lhs.distance < rhs.distance
    }
    guard candidates.count >= 2,
      candidates[0].distance.isFinite,
      candidates[1].distance.isFinite
    else {
      throw DrawingFramePosteriorError.invalidBoundaryGeometry
    }
    guard candidates[1].distance - candidates[0].distance
      >= observation.associationDistanceMargin
    else {
      throw DrawingFramePosteriorError.ambiguousEdgeAssociation(
        nearestDistance: candidates[0].distance,
        runnerUpDistance: candidates[1].distance,
        requiredMargin: observation.associationDistanceMargin
      )
    }
    let index = candidates[0].index
    return DrawingFrameSideAssociation(
      machineSide: observation.key.direction,
      candidateEdgeIndex: index,
      referenceStart: points[index],
      referenceEnd: points[index + 1],
      initializedFromFrameID: observation.key.frameID
    )
  }

  private static func segmentDistance(
    from point: Point2<CameraPixelSpace>,
    start: Point2<CameraPixelSpace>,
    end: Point2<CameraPixelSpace>
  ) -> Double {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0 else { return .infinity }
    let raw = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
    let projection = min(1, max(0, raw))
    return hypot(
      point.x - (start.x + projection * dx),
      point.y - (start.y + projection * dy)
    )
  }

  private static func corners(
    from sides: [PreflightBoundaryDirection: DrawingFrameSidePosterior]
  ) -> [DrawingFrameCorner: Point2<CameraPixelSpace>] {
    let byEdge = Dictionary(uniqueKeysWithValues: sides.values.map {
      ($0.association.candidateEdgeIndex, $0)
    })
    var result: [DrawingFrameCorner: Point2<CameraPixelSpace>] = [:]
    for vertex in DrawingFrameCorner.allCases {
      let incomingIndex = (vertex.rawValue + 3) % 4
      let outgoingIndex = vertex.rawValue
      guard let incoming = byEdge[incomingIndex], let outgoing = byEdge[outgoingIndex],
        let intersection = lineIntersection(incoming.geometry, outgoing.geometry)
      else { continue }
      result[vertex] = intersection
    }
    return result
  }

  private static func lineIntersection(
    _ first: Polyline<CameraPixelSpace>,
    _ second: Polyline<CameraPixelSpace>
  ) -> Point2<CameraPixelSpace>? {
    let p = first.start
    let rX = first.end.x - first.start.x
    let rY = first.end.y - first.start.y
    let q = second.start
    let sX = second.end.x - second.start.x
    let sY = second.end.y - second.start.y
    let denominator = rX * sY - rY * sX
    guard abs(denominator) > 1e-12 else { return nil }
    let t = ((q.x - p.x) * sY - (q.y - p.y) * sX) / denominator
    return try? Point2(x: p.x + t * rX, y: p.y + t * rY)
  }

  private static func closedEstimate(
    from sides: [PreflightBoundaryDirection: DrawingFrameSidePosterior],
    corners: [DrawingFrameCorner: Point2<CameraPixelSpace>]
  ) throws -> DrawingFrameEstimate? {
    guard sides.count == 4, corners.count == 4 else { return nil }
    let ordered = DrawingFrameCorner.allCases.compactMap { corners[$0] }
    guard ordered.count == 4 else { return nil }
    let averageVariance = sides.values.reduce(0) { $0 + $1.offsetVariance } / 4
    return DrawingFrameEstimate(
      geometry: try Polyline(points: ordered + [ordered[0]]),
      confidence: 1 / (1 + sqrt(averageVariance)),
      basis: "per-side image-space offset posterior; exact tool centroids update variance; controller final MPos retained as provenance only"
    )
  }
}
