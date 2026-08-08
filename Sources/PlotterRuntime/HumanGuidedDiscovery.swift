import Foundation
import PlotterModel

public enum BoundaryDirection: String, Codable, CaseIterable, Hashable, Sendable {
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

public enum DiscoverySequenceID: String, Codable, CaseIterable, Hashable, Sendable {
  case boundaryNegativeX
  case boundaryPositiveX
  case boundaryNegativeY
  case boundaryPositiveY
  case penInteraction
}

public enum DiscoveryParticipant: String, Codable, CaseIterable, Hashable, Sendable {
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

/// Short answers are accepted only while their defining discovery question is
/// current. A response has no ambient controller meaning.
public enum OperatorChoice: String, Codable, CaseIterable, Hashable, Sendable {
  case yes = "YES"
  case no = "NO"

  public var exactPhrase: String { rawValue }
}

public struct DiscoveryQuestion: Hashable, Sendable {
  public let prompt: String
  public let choices: [OperatorChoice]
  public let advancingChoices: Set<OperatorChoice>
  public let negativeAcknowledgement: String

  public init(
    prompt: String,
    choices: [OperatorChoice] = [.yes, .no],
    advancingChoices: Set<OperatorChoice> = [.yes],
    negativeAcknowledgement: String
  ) {
    precondition(!choices.isEmpty)
    precondition(advancingChoices.isSubset(of: Set(choices)))
    self.prompt = prompt
    self.choices = choices
    self.advancingChoices = advancingChoices
    self.negativeAcknowledgement = negativeAcknowledgement
  }

  public var choiceLabel: String {
    choices.map(\.exactPhrase).joined(separator: " / ")
  }
}

public enum DiscoveryAction: Hashable, Sendable {
  case askQuestion(DiscoveryQuestion)
  case awaitOperatorChoice(DiscoveryQuestion)
  case announce(String)
  case startBoundaryJog(BoundaryDirection)
  case awaitContextualStop(BoundaryDirection)
  case cancelBoundaryJogAndAwaitIdle(BoundaryDirection)
  case captureFreshCameraFrame
  case measureBoundary(BoundaryDirection)
  case adjustDrawingFramePosterior(BoundaryDirection)
  case actuatePen(PenCommand)
  case awaitPhysicalPenConfirmation(PenState, question: DiscoveryQuestion)
}

public enum DiscoveryEventExpectation: Hashable, Sendable {
  case questionPresented
  case operatorChoice(Set<OperatorChoice>)
  case announcementCompleted
  case boundaryJogStarted(BoundaryDirection)
  case operatorStopRequested(BoundaryDirection)
  case boundaryJogCancelled(BoundaryDirection)
  case freshFrameCaptured
  case boundaryMeasured(BoundaryDirection)
  case drawingFramePosteriorAdjusted(BoundaryDirection)
  case penCommandSettled(PenCommand)
  case physicalPenConfirmed(PenState, response: OperatorChoice)

  fileprivate func accepts(_ event: DiscoveryEvent) -> Bool {
    switch (self, event) {
    case (.questionPresented, .questionPresented):
      true
    case (.operatorChoice(let expected), .operatorChoiceAccepted(let actual)):
      expected.contains(actual)
    case (.announcementCompleted, .announcementCompleted):
      true
    case (.boundaryJogStarted(let expected), .boundaryJogStarted(let actual, _)):
      expected == actual
    case (.operatorStopRequested(let expected), .operatorStopRequested(let actual)):
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

public struct DiscoveryStep: Hashable, Sendable, Identifiable {
  public let id: String
  public let participant: DiscoveryParticipant
  public let action: DiscoveryAction
  public let expectedEvent: DiscoveryEventExpectation

  public init(
    id: String,
    participant: DiscoveryParticipant,
    action: DiscoveryAction,
    expectedEvent: DiscoveryEventExpectation
  ) {
    self.id = id
    self.participant = participant
    self.action = action
    self.expectedEvent = expectedEvent
  }

  public var question: DiscoveryQuestion? {
    switch action {
    case .awaitOperatorChoice(let question), .awaitPhysicalPenConfirmation(_, let question):
      question
    default:
      nil
    }
  }
}

public struct DiscoverySequenceDefinition: Hashable, Sendable, Identifiable {
  public let id: DiscoverySequenceID
  public let title: String
  public let summary: String
  public let steps: [DiscoveryStep]

  public init(
    id: DiscoverySequenceID,
    title: String,
    summary: String,
    steps: [DiscoveryStep]
  ) {
    self.id = id
    self.title = title
    self.summary = summary
    self.steps = steps
  }

  public var questions: [DiscoveryQuestion] {
    steps.compactMap(\.question)
  }
}

public enum DiscoverySequenceCatalog {
  public static let title = "Human-Guided Discovery"

  public static let all: [DiscoverySequenceDefinition] = DiscoverySequenceID.allCases.map {
    definition(for: $0)
  }

  public static func definition(for id: DiscoverySequenceID) -> DiscoverySequenceDefinition {
    switch id {
    case .boundaryNegativeX:
      boundary(.negativeX, id: id)
    case .boundaryPositiveX:
      boundary(.positiveX, id: id)
    case .boundaryNegativeY:
      boundary(.negativeY, id: id)
    case .boundaryPositiveY:
      boundary(.positiveY, id: id)
    case .penInteraction:
      penInteraction(id: id)
    }
  }

  private static func boundary(
    _ direction: BoundaryDirection,
    id: DiscoverySequenceID
  ) -> DiscoverySequenceDefinition {
    let readyQuestion = DiscoveryQuestion(
      prompt: "Is the path clear and are you ready to move toward \(direction.displayName)?",
      negativeAcknowledgement: "Okay. No motion will start. I will wait."
    )
    return DiscoverySequenceDefinition(
      id: id,
      title: "\(direction.displayName) Boundary Discovery",
      summary: "Move toward \(direction.displayName), Stop at the observed boundary, and update one exact-frame side observation.",
      steps: [
        DiscoveryStep(
          id: "question-ready",
          participant: .application,
          action: .askQuestion(readyQuestion),
          expectedEvent: .questionPresented
        ),
        DiscoveryStep(
          id: "answer-ready",
          participant: .operatorChoice,
          action: .awaitOperatorChoice(readyQuestion),
          expectedEvent: .operatorChoice(readyQuestion.advancingChoices)
        ),
        DiscoveryStep(
          id: "announce-jog",
          participant: .application,
          action: .announce("Moving toward \(direction.displayName) boundary."),
          expectedEvent: .announcementCompleted
        ),
        DiscoveryStep(
          id: "start-jog",
          participant: .controller,
          action: .startBoundaryJog(direction),
          expectedEvent: .boundaryJogStarted(direction)
        ),
        DiscoveryStep(
          id: "stop-boundary",
          participant: .operatorChoice,
          action: .awaitContextualStop(direction),
          expectedEvent: .operatorStopRequested(direction)
        ),
        DiscoveryStep(
          id: "cancel-and-idle",
          participant: .controller,
          action: .cancelBoundaryJogAndAwaitIdle(direction),
          expectedEvent: .boundaryJogCancelled(direction)
        ),
        DiscoveryStep(
          id: "capture-frame",
          participant: .camera,
          action: .captureFreshCameraFrame,
          expectedEvent: .freshFrameCaptured
        ),
        DiscoveryStep(
          id: "measure-boundary",
          participant: .vision,
          action: .measureBoundary(direction),
          expectedEvent: .boundaryMeasured(direction)
        ),
        DiscoveryStep(
          id: "adjust-posterior",
          participant: .vision,
          action: .adjustDrawingFramePosterior(direction),
          expectedEvent: .drawingFramePosteriorAdjusted(direction)
        ),
      ]
    )
  }

  private static func penInteraction(id: DiscoverySequenceID) -> DiscoverySequenceDefinition {
    let initiallyUp = DiscoveryQuestion(
      prompt: "Is the pen currently up?",
      negativeAcknowledgement:
        "The sequence needs an observed up position before it can continue. I will wait."
    )
    let clearToLower = DiscoveryQuestion(
      prompt: "Are we clear to put it down?",
      negativeAcknowledgement: "Okay. I will not lower it. I will wait."
    )
    let currentlyDown = DiscoveryQuestion(
      prompt: "Is the pen currently down?",
      negativeAcknowledgement:
        "The down position was not confirmed. I will command Pen Up and end this cycle."
    )
    let finallyUp = DiscoveryQuestion(
      prompt: "Is the pen up?",
      negativeAcknowledgement: "The final up position was not confirmed. I will wait."
    )
    return DiscoverySequenceDefinition(
      id: id,
      title: "Pen Interaction",
      summary:
        "Confirm up, authorize down, observe down, retract, and confirm up using YES or NO answers.",
      steps: [
        DiscoveryStep(
          id: "question-initially-up",
          participant: .application,
          action: .askQuestion(initiallyUp),
          expectedEvent: .questionPresented
        ),
        DiscoveryStep(
          id: "answer-initially-up",
          participant: .operatorChoice,
          action: .awaitPhysicalPenConfirmation(.up, question: initiallyUp),
          expectedEvent: .physicalPenConfirmed(.up, response: .yes)
        ),
        DiscoveryStep(
          id: "question-clear-to-lower",
          participant: .application,
          action: .askQuestion(clearToLower),
          expectedEvent: .questionPresented
        ),
        DiscoveryStep(
          id: "answer-clear-to-lower",
          participant: .operatorChoice,
          action: .awaitOperatorChoice(clearToLower),
          expectedEvent: .operatorChoice(clearToLower.advancingChoices)
        ),
        DiscoveryStep(
          id: "announce-down",
          participant: .application,
          action: .announce("Lowering the pen."),
          expectedEvent: .announcementCompleted
        ),
        DiscoveryStep(
          id: "command-down",
          participant: .controller,
          action: .actuatePen(.lower),
          expectedEvent: .penCommandSettled(.lower)
        ),
        DiscoveryStep(
          id: "question-currently-down",
          participant: .application,
          action: .askQuestion(currentlyDown),
          expectedEvent: .questionPresented
        ),
        DiscoveryStep(
          id: "answer-currently-down",
          participant: .operatorChoice,
          action: .awaitPhysicalPenConfirmation(.down, question: currentlyDown),
          expectedEvent: .physicalPenConfirmed(.down, response: .yes)
        ),
        DiscoveryStep(
          id: "capture-down-frame",
          participant: .camera,
          action: .captureFreshCameraFrame,
          expectedEvent: .freshFrameCaptured
        ),
        DiscoveryStep(
          id: "announce-up",
          participant: .application,
          action: .announce("Raising the pen."),
          expectedEvent: .announcementCompleted
        ),
        DiscoveryStep(
          id: "command-up",
          participant: .controller,
          action: .actuatePen(.raise),
          expectedEvent: .penCommandSettled(.raise)
        ),
        DiscoveryStep(
          id: "question-finally-up",
          participant: .application,
          action: .askQuestion(finallyUp),
          expectedEvent: .questionPresented
        ),
        DiscoveryStep(
          id: "answer-finally-up",
          participant: .operatorChoice,
          action: .awaitPhysicalPenConfirmation(.up, question: finallyUp),
          expectedEvent: .physicalPenConfirmed(.up, response: .yes)
        ),
        DiscoveryStep(
          id: "capture-up-frame",
          participant: .camera,
          action: .captureFreshCameraFrame,
          expectedEvent: .freshFrameCaptured
        ),
      ]
    )
  }
}

public enum DiscoveryEvidenceKind: String, Codable, CaseIterable, Hashable, Sendable {
  case operatorChoice
  case operatorObservation
  case controller
  case camera
  case visionMeasurement
  case observedInk
}

/// Current-transaction evidence only. `observedInk` is deliberately distinct
/// from controller acceptance, camera capture, and inferred vision geometry.
public struct DiscoveryEvidenceSummary: Hashable, Sendable {
  public let kind: DiscoveryEvidenceKind
  public let summary: String
  public let frameID: FrameID?
  public let cameraConfigurationID: CameraConfigurationID?

  public init(
    kind: DiscoveryEvidenceKind,
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

public enum DiscoveryEvent: Hashable, Sendable {
  case questionPresented
  case operatorChoiceAccepted(OperatorChoice)
  case announcementCompleted
  case boundaryJogStarted(BoundaryDirection, controllerSummary: String)
  case operatorStopRequested(BoundaryDirection)
  case boundaryJogCancelled(
    BoundaryDirection,
    finalPosition: MachinePosition,
    controllerSummary: String
  )
  case freshFrameCaptured(FrameID, CameraConfigurationID)
  case boundaryMeasured(
    BoundaryDirection,
    controllerPosition: MachinePosition,
    observedToolCentroid: Point2<CameraPixelSpace>,
    frameID: FrameID,
    cameraConfigurationID: CameraConfigurationID,
    confidence: Double,
    summary: String
  )
  case drawingFramePosteriorAdjusted(
    BoundaryDirection,
    frameID: FrameID,
    cameraConfigurationID: CameraConfigurationID,
    observationCount: Int
  )
  case penCommandSettled(PenCommand, controllerSummary: String)
  case physicalPenConfirmed(
    PenState,
    response: OperatorChoice,
    operatorSummary: String
  )

  fileprivate var evidenceSummary: DiscoveryEvidenceSummary? {
    switch self {
    case .questionPresented, .announcementCompleted:
      nil
    case .operatorChoiceAccepted(let response):
      DiscoveryEvidenceSummary(
        kind: .operatorChoice,
        summary: "Accepted contextual choice: \(response.exactPhrase)"
      )
    case .operatorStopRequested(let direction):
      DiscoveryEvidenceSummary(
        kind: .operatorChoice,
        summary: "Operator requested Stop during \(direction.displayName) Boundary Discovery."
      )
    case .boundaryJogStarted(_, let summary),
      .boundaryJogCancelled(_, _, let summary),
      .penCommandSettled(_, let summary):
      DiscoveryEvidenceSummary(kind: .controller, summary: summary)
    case .freshFrameCaptured(let frameID, let configurationID):
      DiscoveryEvidenceSummary(
        kind: .camera,
        summary: "Captured exact discovery frame \(frameID.rawValue).",
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
      DiscoveryEvidenceSummary(
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
      DiscoveryEvidenceSummary(
        kind: .visionMeasurement,
        summary: "\(direction.displayName) adjusted the drawing-frame posterior from \(observationCount) observations.",
        frameID: frameID,
        cameraConfigurationID: configurationID
      )
    case .physicalPenConfirmed(let state, _, let summary):
      DiscoveryEvidenceSummary(
        kind: .operatorObservation,
        summary: "Pen physically \(state.rawValue): \(summary)"
      )
    }
  }
}

public enum DiscoveryTransactionState: Hashable, Sendable {
  case notStarted
  case active
  case cancelling
  case succeeded
  case failed(String)
  case cancelled
}

public enum DiscoveryTransactionError: Error, Equatable, Sendable {
  case alreadyStarted
  case notActive
  case noCurrentStep
  case unexpectedEvent(stepID: String)
  case invalidBoundaryConfidence
  case invalidPosteriorObservationCount
}

/// A small in-memory transaction for driving and presenting one sequence.
/// It has no persistence, replay, or cross-launch authority.
public struct DiscoveryTransaction: Hashable, Sendable, Identifiable {
  public let id: UUID
  public let definition: DiscoverySequenceDefinition
  public private(set) var state: DiscoveryTransactionState
  public private(set) var completedStepCount: Int
  public private(set) var evidenceSummaries: [DiscoveryEvidenceSummary]

  public init(id: UUID = UUID(), definition: DiscoverySequenceDefinition) {
    self.id = id
    self.definition = definition
    state = .notStarted
    completedStepCount = 0
    evidenceSummaries = []
  }

  public init(id: UUID = UUID(), sequenceID: DiscoverySequenceID) {
    self.init(id: id, definition: DiscoverySequenceCatalog.definition(for: sequenceID))
  }

  public var currentStep: DiscoveryStep? {
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

  public mutating func begin() throws {
    guard state == .notStarted else { throw DiscoveryTransactionError.alreadyStarted }
    state = definition.steps.isEmpty ? .succeeded : .active
  }

  public mutating func record(_ event: DiscoveryEvent) throws {
    guard state == .active else { throw DiscoveryTransactionError.notActive }
    guard let step = currentStep else { throw DiscoveryTransactionError.noCurrentStep }
    try Self.validateEvidence(in: event)
    guard step.expectedEvent.accepts(event) else {
      throw DiscoveryTransactionError.unexpectedEvent(stepID: step.id)
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

  private static func validateEvidence(in event: DiscoveryEvent) throws {
    switch event {
    case .boundaryMeasured(_, _, _, _, _, let confidence, _):
      guard confidence.isFinite, confidence >= 0, confidence <= 1 else {
        throw DiscoveryTransactionError.invalidBoundaryConfidence
      }
    case .drawingFramePosteriorAdjusted(_, _, _, let count):
      guard count > 0 else {
        throw DiscoveryTransactionError.invalidPosteriorObservationCount
      }
    default:
      break
    }
  }
}

public struct DrawingFrameBoundaryObservationKey: Hashable, Sendable {
  public let frameID: FrameID
  public let cameraConfigurationID: CameraConfigurationID
  public let direction: BoundaryDirection

  public init(
    frameID: FrameID,
    cameraConfigurationID: CameraConfigurationID,
    direction: BoundaryDirection
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
    direction: BoundaryDirection,
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
  public let machineSide: BoundaryDirection
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
  public let sidePosteriors: [BoundaryDirection: DrawingFrameSidePosterior]
  public let associations: [BoundaryDirection: DrawingFrameSideAssociation]
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
  ) throws -> [BoundaryDirection: DrawingFrameSidePosterior] {
    var fitted: [BoundaryDirection: DrawingFrameSidePosterior] = [:]
    var claimedCandidateEdges: [Int: BoundaryDirection] = [:]
    for direction in BoundaryDirection.allCases {
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
    from sides: [BoundaryDirection: DrawingFrameSidePosterior]
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
    from sides: [BoundaryDirection: DrawingFrameSidePosterior],
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
