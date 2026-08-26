import EpisodeCore
import Foundation
import PlotterModel

public enum PlotterSessionIntent: Codable, Hashable, Sendable {
  case begin
  case finish
}

public enum PlotterObservationIntent: Codable, Hashable, Sendable {
  case captureExactFrame(configurationID: CameraConfigurationID)
}

public struct PlotterPointSelectionRequest: Codable, Hashable, Sendable {
  public let point: Point2<MachineSpace>
  public let sourceObservationID: PlotterObservationID

  public init(point: Point2<MachineSpace>, sourceObservationID: PlotterObservationID) {
    self.point = point
    self.sourceObservationID = sourceObservationID
  }
}

public enum PlotterPointSelectionIntent: Codable, Hashable, Sendable {
  case select(PlotterPointSelectionRequest)
  case clear
}

public enum PlotterJogDirection: String, Codable, CaseIterable, Hashable, Sendable {
  case positiveX
  case negativeX
  case positiveY
  case negativeY
}

public enum PlotterPenPosition: String, Codable, Hashable, Sendable {
  case raised
  case lowered
}

public enum PlotterIntentValidationError: Error, Equatable, Sendable {
  case invalidJogDistance
}

public struct PlotterJogRequest: Codable, Hashable, Sendable {
  public let direction: PlotterJogDirection
  public let distanceMM: Double

  public init(direction: PlotterJogDirection, distanceMM: Double) throws {
    guard distanceMM.isFinite, distanceMM > 0 else {
      throw PlotterIntentValidationError.invalidJogDistance
    }
    self.direction = direction
    self.distanceMM = distanceMM
  }

  private enum CodingKeys: String, CodingKey {
    case direction
    case distanceMM
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      direction: container.decode(PlotterJogDirection.self, forKey: .direction),
      distanceMM: container.decode(Double.self, forKey: .distanceMM)
    )
  }
}

public enum PlotterManualMotionIntent: Codable, Hashable, Sendable {
  case jog(PlotterJogRequest)
  case setPen(PlotterPenPosition)
}

public enum PlotterDrawingIntent: Codable, Hashable, Sendable {
  case execute(planRevisionID: ExecutionPlanRevisionID)
  case captureResult(configurationID: CameraConfigurationID)
}

public enum PlotterLearningIntent: Codable, Hashable, Sendable {
  case captureSample(configurationID: CameraConfigurationID)
  case acceptModel(revisionID: DrawingModelRevisionID)
}

public enum PlotterEvidenceQuestion: String, Codable, CaseIterable, Hashable, Sendable {
  case pointIdentity
  case motionSettlement
  case drawingOutcome
  case modelFitness
}

public enum PlotterEvidenceIntent: Codable, Hashable, Sendable {
  case accept(subject: PlotterEvidenceSubject, question: PlotterEvidenceQuestion)
  case assess(outcomeID: PlotterOutcomeID)
}

public enum PlotterIntent: EpisodeIntent {
  public typealias InitialContext = PlotterEpisodeInitialContext
  public typealias Grammar = PlotterIntentGrammar
  public typealias AssessmentRule = PlotterAssessmentRule

  case session(PlotterSessionIntent)
  case observation(PlotterObservationIntent)
  case pointSelection(PlotterPointSelectionIntent)
  case manualMotion(PlotterManualMotionIntent)
  case drawing(PlotterDrawingIntent)
  case learning(PlotterLearningIntent)
  case evidence(PlotterEvidenceIntent)

  public var family: PlotterIntentFamily {
    switch self {
    case .session:
      return .session
    case .observation:
      return .observation
    case .pointSelection:
      return .pointSelection
    case .manualMotion:
      return .manualMotion
    case .drawing:
      return .drawing
    case .learning:
      return .learning
    case .evidence:
      return .evidence
    }
  }

  public var requiresExternalEffect: Bool {
    switch self {
    case .pointSelection, .evidence:
      return false
    case .session, .observation, .manualMotion, .drawing, .learning:
      return true
    }
  }
}
