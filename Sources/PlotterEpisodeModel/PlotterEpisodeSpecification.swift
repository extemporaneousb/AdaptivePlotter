import EpisodeCore
import Foundation
import PlotterModel

public struct PlotterDrawingRevisionReference: Codable, Hashable, Sendable {
  public let programID: ProgramID
  public let contentHash: Digest

  public init(programID: ProgramID, contentHash: Digest) {
    self.programID = programID
    self.contentHash = contentHash
  }
}

public struct PlotterExecutionPlanReference: Codable, Hashable, Sendable {
  public let revisionID: ExecutionPlanRevisionID
  public let contentHash: Digest

  public init(revisionID: ExecutionPlanRevisionID, contentHash: Digest) {
    self.revisionID = revisionID
    self.contentHash = contentHash
  }
}

public struct PlotterCalibrationReference: Codable, Hashable, Sendable {
  public let revisionID: DrawingRegistrationRevisionID
  public let contentHash: Digest

  public init(revisionID: DrawingRegistrationRevisionID, contentHash: Digest) {
    self.revisionID = revisionID
    self.contentHash = contentHash
  }
}

public struct PlotterDrawingModelReference: Codable, Hashable, Sendable {
  public let revisionID: DrawingModelRevisionID
  public let contentHash: Digest

  public init(revisionID: DrawingModelRevisionID, contentHash: Digest) {
    self.revisionID = revisionID
    self.contentHash = contentHash
  }
}

public struct PlotterEpisodeInitialContext: Codable, Hashable, Sendable {
  public let initialStateRevision: EpisodeStateRevision
  public let initialStateDigest: EpisodeStateDigest
  public let drawing: PlotterDrawingRevisionReference?
  public let executionPlan: PlotterExecutionPlanReference?
  public let calibration: PlotterCalibrationReference?
  public let paperRevision: EpisodeRevisionIdentifier
  public let environmentRevision: EpisodeRevisionIdentifier

  public init(
    initialStateRevision: EpisodeStateRevision = .initial,
    initialStateDigest: EpisodeStateDigest,
    drawing: PlotterDrawingRevisionReference? = nil,
    executionPlan: PlotterExecutionPlanReference? = nil,
    calibration: PlotterCalibrationReference? = nil,
    paperRevision: EpisodeRevisionIdentifier,
    environmentRevision: EpisodeRevisionIdentifier
  ) {
    self.initialStateRevision = initialStateRevision
    self.initialStateDigest = initialStateDigest
    self.drawing = drawing
    self.executionPlan = executionPlan
    self.calibration = calibration
    self.paperRevision = paperRevision
    self.environmentRevision = environmentRevision
  }
}

public enum PlotterIntentFamily: String, Codable, CaseIterable, Hashable, Sendable {
  case session
  case observation
  case pointSelection
  case manualMotion
  case drawing
  case learning
  case evidence
}

public struct PlotterIntentGrammar: Codable, Hashable, Sendable {
  public let permittedFamilies: [PlotterIntentFamily]

  public init(permittedFamilies: [PlotterIntentFamily]) {
    self.permittedFamilies = Array(Set(permittedFamilies)).sorted { $0.rawValue < $1.rawValue }
  }
}

public struct PlotterAssessmentRule: Codable, Hashable, Sendable {
  public let id: EpisodeAssessmentRuleID
  public let criterionIDs: [EpisodeAssessmentCriterionID]
  public let summary: String

  public init(
    id: EpisodeAssessmentRuleID,
    criterionIDs: [EpisodeAssessmentCriterionID],
    summary: String
  ) {
    self.id = id
    self.criterionIDs = criterionIDs
    self.summary = summary
  }
}

public struct PlotterEpisodeDomainManifest: Codable, Hashable, Sendable {
  public let drawing: PlotterDrawingRevisionReference?
  public let executionPlan: PlotterExecutionPlanReference?
  public let calibration: PlotterCalibrationReference?
  public let paperRevision: EpisodeRevisionIdentifier
  public let environmentRevision: EpisodeRevisionIdentifier
  public let drawingModel: PlotterDrawingModelReference?
  public let cameraConfigurationID: CameraConfigurationID?
  public let cameraConfigurationRevision: EpisodeRevisionIdentifier?

  public init(
    drawing: PlotterDrawingRevisionReference? = nil,
    executionPlan: PlotterExecutionPlanReference? = nil,
    calibration: PlotterCalibrationReference? = nil,
    paperRevision: EpisodeRevisionIdentifier,
    environmentRevision: EpisodeRevisionIdentifier,
    drawingModel: PlotterDrawingModelReference? = nil,
    cameraConfigurationID: CameraConfigurationID? = nil,
    cameraConfigurationRevision: EpisodeRevisionIdentifier? = nil
  ) {
    self.drawing = drawing
    self.executionPlan = executionPlan
    self.calibration = calibration
    self.paperRevision = paperRevision
    self.environmentRevision = environmentRevision
    self.drawingModel = drawingModel
    self.cameraConfigurationID = cameraConfigurationID
    self.cameraConfigurationRevision = cameraConfigurationRevision
  }
}

public typealias PlotterEpisodeDefinition = EpisodeDefinition<PlotterIntent>
public typealias PlotterEpisodeManifest = EpisodeManifest<PlotterEpisodeDomainManifest>
