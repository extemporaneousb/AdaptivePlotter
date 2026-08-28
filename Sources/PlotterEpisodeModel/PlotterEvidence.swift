import EpisodeCore
import Foundation
import PlotterModel

public enum PlotterEnvironment: String, Codable, CaseIterable, Hashable, Sendable {
  case live
  case simulated
}

public enum PlotterObservationSource: String, Codable, Hashable, Sendable {
  case controller
  case camera
  case causalSimulator
  case operatorAssertion
}

public struct PlotterObservationContext: Codable, Hashable, Sendable {
  public let id: PlotterObservationID
  public let observedAt: Date
  public let environment: PlotterEnvironment
  public let source: PlotterObservationSource
  public let sourceRevision: EpisodeRevisionIdentifier
  public let configurationRevision: EpisodeRevisionIdentifier?
  public let artifactReferences: [EpisodeArtifactReference]

  public init(
    id: PlotterObservationID,
    observedAt: Date,
    environment: PlotterEnvironment,
    source: PlotterObservationSource,
    sourceRevision: EpisodeRevisionIdentifier,
    configurationRevision: EpisodeRevisionIdentifier? = nil,
    artifactReferences: [EpisodeArtifactReference] = []
  ) {
    self.id = id
    self.observedAt = observedAt
    self.environment = environment
    self.source = source
    self.sourceRevision = sourceRevision
    self.configurationRevision = configurationRevision
    self.artifactReferences = artifactReferences
  }
}

public enum PlotterControllerStatus: String, Codable, CaseIterable, Hashable, Sendable {
  case disconnected
  case idle
  case running
  case hold
  case alarm
  case unknown
}

public struct PlotterControllerObservation: Codable, Hashable, Sendable {
  public let context: PlotterObservationContext
  public let status: PlotterControllerStatus
  public let machinePosition: Point2<MachineSpace>?
  public let motionEnabled: Bool

  public init(
    context: PlotterObservationContext,
    status: PlotterControllerStatus,
    machinePosition: Point2<MachineSpace>?,
    motionEnabled: Bool
  ) {
    self.context = context
    self.status = status
    self.machinePosition = machinePosition
    self.motionEnabled = motionEnabled
  }
}

public enum PlotterObservationValidationError: Error, Equatable, Sendable {
  case invalidFrameDimensions
}

public struct PlotterCameraFrameObservation: Codable, Hashable, Sendable {
  public let context: PlotterObservationContext
  public let configurationID: CameraConfigurationID
  public let pixelWidth: UInt32
  public let pixelHeight: UInt32
  public let exactFrame: PlotterExactFrameReference?

  public init(
    context: PlotterObservationContext,
    configurationID: CameraConfigurationID,
    pixelWidth: UInt32,
    pixelHeight: UInt32,
    exactFrame: PlotterExactFrameReference? = nil
  ) throws {
    guard pixelWidth > 0, pixelHeight > 0 else {
      throw PlotterObservationValidationError.invalidFrameDimensions
    }
    self.context = context
    self.configurationID = configurationID
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.exactFrame = exactFrame
  }

  private enum CodingKeys: String, CodingKey {
    case context
    case configurationID
    case pixelWidth
    case pixelHeight
    case exactFrame
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      context: container.decode(PlotterObservationContext.self, forKey: .context),
      configurationID: container.decode(CameraConfigurationID.self, forKey: .configurationID),
      pixelWidth: container.decode(UInt32.self, forKey: .pixelWidth),
      pixelHeight: container.decode(UInt32.self, forKey: .pixelHeight),
      exactFrame: container.decodeIfPresent(
        PlotterExactFrameReference.self,
        forKey: .exactFrame
      )
    )
  }
}

public struct PlotterPointSelectionObservation: Codable, Hashable, Sendable {
  public let context: PlotterObservationContext
  public let selectionID: PlotterPointSelectionID
  public let sourceFrame: PlotterExactFrameReference
  public let point: Point2<CameraPixelSpace>
  public let presentationTransformRevision: PlotterPresentationTransformRevision
  public let ordinal: Int

  public init(
    context: PlotterObservationContext,
    selectionID: PlotterPointSelectionID,
    sourceFrame: PlotterExactFrameReference,
    point: Point2<CameraPixelSpace>,
    presentationTransformRevision: PlotterPresentationTransformRevision,
    ordinal: Int
  ) {
    self.context = context
    self.selectionID = selectionID
    self.sourceFrame = sourceFrame
    self.point = point
    self.presentationTransformRevision = presentationTransformRevision
    self.ordinal = ordinal
  }
}

public enum PlotterObservation: Codable, Hashable, Sendable {
  case controller(PlotterControllerObservation)
  case cameraFrame(PlotterCameraFrameObservation)
  case pointSelection(PlotterPointSelectionObservation)

  public var context: PlotterObservationContext {
    switch self {
    case let .controller(observation):
      return observation.context
    case let .cameraFrame(observation):
      return observation.context
    case let .pointSelection(observation):
      return observation.context
    }
  }
}

public struct PlotterMeasurementContext: Codable, Hashable, Sendable {
  public let id: PlotterMeasurementID
  public let computedAt: Date
  public let sourceObservationIDs: [PlotterObservationID]
  public let algorithmRevision: EpisodeRevisionIdentifier
  public let modelRevision: EpisodeRevisionIdentifier?
  public let diagnosticQualifications: [String]

  public init(
    id: PlotterMeasurementID,
    computedAt: Date,
    sourceObservationIDs: [PlotterObservationID],
    algorithmRevision: EpisodeRevisionIdentifier,
    modelRevision: EpisodeRevisionIdentifier? = nil,
    diagnosticQualifications: [String] = []
  ) throws {
    guard !sourceObservationIDs.isEmpty else {
      throw PlotterMeasurementValidationError.missingSourceObservation
    }
    guard Set(sourceObservationIDs).count == sourceObservationIDs.count else {
      throw PlotterMeasurementValidationError.duplicateSourceObservation
    }
    self.id = id
    self.computedAt = computedAt
    self.sourceObservationIDs = sourceObservationIDs
    self.algorithmRevision = algorithmRevision
    self.modelRevision = modelRevision
    self.diagnosticQualifications = diagnosticQualifications
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case computedAt
    case sourceObservationIDs
    case algorithmRevision
    case modelRevision
    case diagnosticQualifications
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(PlotterMeasurementID.self, forKey: .id),
      computedAt: container.decode(Date.self, forKey: .computedAt),
      sourceObservationIDs: container.decode(
        [PlotterObservationID].self,
        forKey: .sourceObservationIDs
      ),
      algorithmRevision: container.decode(
        EpisodeRevisionIdentifier.self,
        forKey: .algorithmRevision
      ),
      modelRevision: container.decodeIfPresent(
        EpisodeRevisionIdentifier.self,
        forKey: .modelRevision
      ),
      diagnosticQualifications: container.decode(
        [String].self,
        forKey: .diagnosticQualifications
      )
    )
  }
}

public enum PlotterMeasurementValidationError: Error, Equatable, Sendable {
  case missingSourceObservation
  case duplicateSourceObservation
  case invalidUncertainty
  case invalidResidual
  case invalidConfidence
}

public struct PlotterProjectedPointMeasurement: Codable, Hashable, Sendable {
  public let context: PlotterMeasurementContext
  public let machinePoint: Point2<MachineSpace>
  public let uncertaintyRadiusMM: Double?

  public init(
    context: PlotterMeasurementContext,
    machinePoint: Point2<MachineSpace>,
    uncertaintyRadiusMM: Double? = nil
  ) throws {
    if let uncertaintyRadiusMM,
       (!uncertaintyRadiusMM.isFinite || uncertaintyRadiusMM < 0) {
      throw PlotterMeasurementValidationError.invalidUncertainty
    }
    self.context = context
    self.machinePoint = machinePoint
    self.uncertaintyRadiusMM = uncertaintyRadiusMM
  }

  private enum CodingKeys: String, CodingKey {
    case context
    case machinePoint
    case uncertaintyRadiusMM
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      context: container.decode(PlotterMeasurementContext.self, forKey: .context),
      machinePoint: container.decode(Point2<MachineSpace>.self, forKey: .machinePoint),
      uncertaintyRadiusMM: container.decodeIfPresent(Double.self, forKey: .uncertaintyRadiusMM)
    )
  }
}

public struct PlotterResidualMeasurement: Codable, Hashable, Sendable {
  public let context: PlotterMeasurementContext
  public let rootMeanSquareMM: Double
  public let maximumMM: Double

  public init(
    context: PlotterMeasurementContext,
    rootMeanSquareMM: Double,
    maximumMM: Double
  ) throws {
    guard
      rootMeanSquareMM.isFinite, maximumMM.isFinite,
      rootMeanSquareMM >= 0, maximumMM >= rootMeanSquareMM
    else {
      throw PlotterMeasurementValidationError.invalidResidual
    }
    self.context = context
    self.rootMeanSquareMM = rootMeanSquareMM
    self.maximumMM = maximumMM
  }

  private enum CodingKeys: String, CodingKey {
    case context
    case rootMeanSquareMM
    case maximumMM
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      context: container.decode(PlotterMeasurementContext.self, forKey: .context),
      rootMeanSquareMM: container.decode(Double.self, forKey: .rootMeanSquareMM),
      maximumMM: container.decode(Double.self, forKey: .maximumMM)
    )
  }
}

public enum PlotterInkClassification: String, Codable, CaseIterable, Hashable, Sendable {
  case noInk
  case attributableInk
  case possibleInk
  case unclear
}

public struct PlotterInkMeasurement: Codable, Hashable, Sendable {
  public let context: PlotterMeasurementContext
  public let classification: PlotterInkClassification
  public let confidence: Double

  public init(
    context: PlotterMeasurementContext,
    classification: PlotterInkClassification,
    confidence: Double
  ) throws {
    guard confidence.isFinite, (0...1).contains(confidence) else {
      throw PlotterMeasurementValidationError.invalidConfidence
    }
    self.context = context
    self.classification = classification
    self.confidence = confidence
  }

  private enum CodingKeys: String, CodingKey {
    case context
    case classification
    case confidence
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      context: container.decode(PlotterMeasurementContext.self, forKey: .context),
      classification: container.decode(PlotterInkClassification.self, forKey: .classification),
      confidence: container.decode(Double.self, forKey: .confidence)
    )
  }
}

public enum PlotterMeasurement: Codable, Hashable, Sendable {
  case projectedPoint(PlotterProjectedPointMeasurement)
  case residual(PlotterResidualMeasurement)
  case ink(PlotterInkMeasurement)

  public var context: PlotterMeasurementContext {
    switch self {
    case let .projectedPoint(measurement):
      return measurement.context
    case let .residual(measurement):
      return measurement.context
    case let .ink(measurement):
      return measurement.context
    }
  }
}

public enum PlotterEvidenceSubject: Codable, Hashable, Sendable {
  case observation(PlotterObservationID)
  case measurement(PlotterMeasurementID)
}

public enum PlotterEvidenceClass: String, Codable, CaseIterable, Hashable, Sendable {
  case livePhysical
  case simulatedCausal
  case diagnosticOnly
  case operatorAssertion
}

public enum PlotterEvidenceBoundaryError: Error, Equatable, Sendable {
  case simulatedInputCannotBecomeLivePhysicalEvidence
}

public struct PlotterEvidence: Codable, Hashable, Sendable {
  public let id: PlotterEvidenceID
  public let episodeID: EpisodeID
  public let subject: PlotterEvidenceSubject
  public let question: PlotterEvidenceQuestion
  public let inputEnvironment: PlotterEnvironment
  public let evidenceClass: PlotterEvidenceClass
  public let acceptedBy: EpisodeAuthorityID
  public let acceptedAt: Date
  public let applicabilityRevision: EpisodeRevisionIdentifier
  public let artifactReferences: [EpisodeArtifactReference]

  public init(
    id: PlotterEvidenceID,
    episodeID: EpisodeID,
    subject: PlotterEvidenceSubject,
    question: PlotterEvidenceQuestion,
    inputEnvironment: PlotterEnvironment,
    evidenceClass: PlotterEvidenceClass,
    acceptedBy: EpisodeAuthorityID,
    acceptedAt: Date,
    applicabilityRevision: EpisodeRevisionIdentifier,
    artifactReferences: [EpisodeArtifactReference] = []
  ) throws {
    if inputEnvironment == .simulated, evidenceClass == .livePhysical {
      throw PlotterEvidenceBoundaryError.simulatedInputCannotBecomeLivePhysicalEvidence
    }
    self.id = id
    self.episodeID = episodeID
    self.subject = subject
    self.question = question
    self.inputEnvironment = inputEnvironment
    self.evidenceClass = evidenceClass
    self.acceptedBy = acceptedBy
    self.acceptedAt = acceptedAt
    self.applicabilityRevision = applicabilityRevision
    self.artifactReferences = artifactReferences
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case episodeID
    case subject
    case question
    case inputEnvironment
    case evidenceClass
    case acceptedBy
    case acceptedAt
    case applicabilityRevision
    case artifactReferences
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(PlotterEvidenceID.self, forKey: .id),
      episodeID: container.decode(EpisodeID.self, forKey: .episodeID),
      subject: container.decode(PlotterEvidenceSubject.self, forKey: .subject),
      question: container.decode(PlotterEvidenceQuestion.self, forKey: .question),
      inputEnvironment: container.decode(PlotterEnvironment.self, forKey: .inputEnvironment),
      evidenceClass: container.decode(PlotterEvidenceClass.self, forKey: .evidenceClass),
      acceptedBy: container.decode(EpisodeAuthorityID.self, forKey: .acceptedBy),
      acceptedAt: container.decode(Date.self, forKey: .acceptedAt),
      applicabilityRevision: container.decode(
        EpisodeRevisionIdentifier.self,
        forKey: .applicabilityRevision
      ),
      artifactReferences: container.decode(
        [EpisodeArtifactReference].self,
        forKey: .artifactReferences
      )
    )
  }
}

public struct PlotterEvidenceRefusal: Codable, Hashable, Sendable {
  public let subject: PlotterEvidenceSubject
  public let question: PlotterEvidenceQuestion
  public let owner: EpisodeAuthorityID
  public let comparedRevision: EpisodeRevisionIdentifier
  public let reason: String
  public let remedy: String

  public init(
    subject: PlotterEvidenceSubject,
    question: PlotterEvidenceQuestion,
    owner: EpisodeAuthorityID,
    comparedRevision: EpisodeRevisionIdentifier,
    reason: String,
    remedy: String
  ) {
    self.subject = subject
    self.question = question
    self.owner = owner
    self.comparedRevision = comparedRevision
    self.reason = reason
    self.remedy = remedy
  }
}

public enum PlotterEvidenceDecision: Codable, Hashable, Sendable {
  case accepted(PlotterEvidence)
  case refused(PlotterEvidenceRefusal)
}

public enum PlotterOutcomeDisposition: String, Codable, CaseIterable, Hashable, Sendable {
  case completed
  case cancelled
  case ambiguous
  case failed
}

public struct PlotterEpisodeOutcome: Codable, Hashable, Sendable {
  public let id: PlotterOutcomeID
  public let episodeID: EpisodeID
  public let disposition: PlotterOutcomeDisposition
  public let acceptedEvidenceIDs: [PlotterEvidenceID]
  public let recordedAt: Date
  public let summary: String

  public init(
    id: PlotterOutcomeID,
    episodeID: EpisodeID,
    disposition: PlotterOutcomeDisposition,
    acceptedEvidenceIDs: [PlotterEvidenceID],
    recordedAt: Date,
    summary: String
  ) {
    self.id = id
    self.episodeID = episodeID
    self.disposition = disposition
    self.acceptedEvidenceIDs = acceptedEvidenceIDs
    self.recordedAt = recordedAt
    self.summary = summary
  }
}

public enum PlotterCriterionDisposition: String, Codable, CaseIterable, Hashable, Sendable {
  case satisfied
  case unsatisfied
  case indeterminate
}

public struct PlotterCriterionAssessment: Codable, Hashable, Sendable {
  public let criterionID: EpisodeAssessmentCriterionID
  public let disposition: PlotterCriterionDisposition
  public let evidenceIDs: [PlotterEvidenceID]
  public let summary: String

  public init(
    criterionID: EpisodeAssessmentCriterionID,
    disposition: PlotterCriterionDisposition,
    evidenceIDs: [PlotterEvidenceID],
    summary: String
  ) {
    self.criterionID = criterionID
    self.disposition = disposition
    self.evidenceIDs = evidenceIDs
    self.summary = summary
  }
}

public struct PlotterAssessment: Codable, Hashable, Sendable {
  public let id: PlotterAssessmentID
  public let episodeID: EpisodeID
  public let outcomeID: PlotterOutcomeID
  public let goalRevision: EpisodeRevisionIdentifier
  public let assessedAt: Date
  public let criteria: [PlotterCriterionAssessment]

  public init(
    id: PlotterAssessmentID,
    episodeID: EpisodeID,
    outcomeID: PlotterOutcomeID,
    goalRevision: EpisodeRevisionIdentifier,
    assessedAt: Date,
    criteria: [PlotterCriterionAssessment]
  ) {
    self.id = id
    self.episodeID = episodeID
    self.outcomeID = outcomeID
    self.goalRevision = goalRevision
    self.assessedAt = assessedAt
    self.criteria = criteria
  }
}
