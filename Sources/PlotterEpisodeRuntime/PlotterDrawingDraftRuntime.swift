import EpisodeCore
import Foundation
import PlotterEpisodeModel
import PlotterModel
import PlotterRuntime

public protocol PlotterDrawingDraftPaperPersistence: Sendable {
  func load() async -> PaperCoverageObservation?
  func save(_ observation: PaperCoverageObservation) async throws
  func clear() async throws
}

public actor PlotterDrawingDraftTransientPaperPersistence:
  PlotterDrawingDraftPaperPersistence
{
  private var observation: PaperCoverageObservation?

  public init(observation: PaperCoverageObservation? = nil) {
    self.observation = observation
  }

  public func load() -> PaperCoverageObservation? { observation }

  public func save(_ observation: PaperCoverageObservation) {
    self.observation = observation
  }

  public func clear() {
    observation = nil
  }
}

public struct PlotterDrawingDraftExternalFactRevisions: Hashable, Sendable {
  public let environment: PlotterEnvironment
  public let interactiveLearningIsComplete: Bool
  public let registrationRevisionID: LearningArtifactRevisionID?
  public let opticalConfiguration: CameraOpticalConfigurationIdentity?
  public let drawableRegion: DrawableMachineRegion?
  public let toolAssemblyRevision: ToolAssemblyRevision
  public let paper: PaperRevisionContext
  public let displayedFrame: PlotterExactFrameReference?
  public let runInProgress: Bool
  public let terminalRequiresNewPlan: Bool
  public let coverageRecordIDs: [DrawingEvidenceRecordID]
  public let drawingArchiveIsAvailable: Bool

  /// Authoring does not interpret pixels. Preserve every semantic identity and
  /// camera configuration while allowing a newer frame from the same stream.
  fileprivate func matchesAuthoring(_ other: Self) -> Bool {
    guard displayedFrame?.source == other.displayedFrame?.source,
      displayedFrame?.cameraConfigurationID == other.displayedFrame?.cameraConfigurationID,
      displayedFrame?.width == other.displayedFrame?.width,
      displayedFrame?.height == other.displayedFrame?.height,
      displayedFrame?.rowBytes == other.displayedFrame?.rowBytes,
      displayedFrame?.pixelFormat == other.displayedFrame?.pixelFormat else { return false }
    return replacingFrame(with: other.displayedFrame) == other
  }

  private func replacingFrame(with frame: PlotterExactFrameReference?) -> Self {
    Self(environment: environment, interactiveLearningIsComplete: interactiveLearningIsComplete,
      registrationRevisionID: registrationRevisionID, opticalConfiguration: opticalConfiguration,
      drawableRegion: drawableRegion, toolAssemblyRevision: toolAssemblyRevision,
      paper: paper, displayedFrame: frame, runInProgress: runInProgress,
      terminalRequiresNewPlan: terminalRequiresNewPlan, coverageRecordIDs: coverageRecordIDs,
      drawingArchiveIsAvailable: drawingArchiveIsAvailable)
  }

  public init(
    environment: PlotterEnvironment,
    interactiveLearningIsComplete: Bool,
    registrationRevisionID: LearningArtifactRevisionID?,
    opticalConfiguration: CameraOpticalConfigurationIdentity?,
    drawableRegion: DrawableMachineRegion?,
    toolAssemblyRevision: ToolAssemblyRevision,
    paper: PaperRevisionContext,
    displayedFrame: PlotterExactFrameReference?,
    runInProgress: Bool,
    terminalRequiresNewPlan: Bool,
    coverageRecordIDs: [DrawingEvidenceRecordID] = [],
    drawingArchiveIsAvailable: Bool = true
  ) {
    self.environment = environment
    self.interactiveLearningIsComplete = interactiveLearningIsComplete
    self.registrationRevisionID = registrationRevisionID
    self.opticalConfiguration = opticalConfiguration
    self.drawableRegion = drawableRegion
    self.toolAssemblyRevision = toolAssemblyRevision
    self.paper = paper
    self.displayedFrame = displayedFrame
    self.runInProgress = runInProgress
    self.terminalRequiresNewPlan = terminalRequiresNewPlan
    self.coverageRecordIDs = coverageRecordIDs
    self.drawingArchiveIsAvailable = drawingArchiveIsAvailable
  }
}

public struct PlotterDrawingDraftExternalFacts: Hashable, Sendable {
  public let revisions: PlotterDrawingDraftExternalFactRevisions
  public let displayedFrame: DisplayedFrame?
  public let registration: TipCameraRegistration?
  /// Existing archive records, including ordinary drawings that may occupy a sheet.
  public let coverageRecords: [DrawingRunEvidenceRecord]

  public init(
    environment: PlotterEnvironment,
    interactiveLearningIsComplete: Bool,
    displayedFrame: DisplayedFrame?,
    opticalConfiguration: CameraOpticalConfigurationIdentity?,
    registration: TipCameraRegistration?,
    drawableRegion: DrawableMachineRegion?,
    toolAssemblyRevision: ToolAssemblyRevision,
    paper: PaperRevisionContext,
    runInProgress: Bool,
    terminalRequiresNewPlan: Bool,
    coverageRecords: [DrawingRunEvidenceRecord] = [],
    drawingArchiveIsAvailable: Bool = true
  ) {
    let exactFrameReference = displayedFrame?.plotterExactFrameReferenceIfMaterialized
    self.displayedFrame = exactFrameReference == nil ? nil : displayedFrame
    self.registration = registration
    self.coverageRecords = coverageRecords
    revisions = PlotterDrawingDraftExternalFactRevisions(
      environment: environment,
      interactiveLearningIsComplete: interactiveLearningIsComplete,
      registrationRevisionID: registration?.acceptedRevisionID,
      opticalConfiguration: opticalConfiguration,
      drawableRegion: drawableRegion,
      toolAssemblyRevision: toolAssemblyRevision,
      paper: paper,
      displayedFrame: exactFrameReference,
      runInProgress: runInProgress,
      terminalRequiresNewPlan: terminalRequiresNewPlan,
      coverageRecordIDs: coverageRecords.map(\.recordID),
      drawingArchiveIsAvailable: drawingArchiveIsAvailable
    )
  }
}

public struct PlotterDrawingDraftProjectionReference: Hashable, Sendable {
  public let environment: PlotterEnvironment
  public let draftRevision: PlotterDrawingDraftRevision
  public let externalFacts: PlotterDrawingDraftExternalFactRevisions

  public init(
    environment: PlotterEnvironment,
    draftRevision: PlotterDrawingDraftRevision,
    externalFacts: PlotterDrawingDraftExternalFactRevisions
  ) {
    self.environment = environment
    self.draftRevision = draftRevision
    self.externalFacts = externalFacts
  }
}

public struct PlotterDrawingDraftSubmission: Hashable, Sendable {
  public let requestID: PlotterDrawingDraftRequestID
  public let projection: PlotterDrawingDraftProjectionReference
  public let intent: PlotterDrawingDraftIntent

  public init(
    requestID: PlotterDrawingDraftRequestID = PlotterDrawingDraftRequestID(),
    projection: PlotterDrawingDraftProjectionReference,
    intent: PlotterDrawingDraftIntent
  ) {
    self.requestID = requestID
    self.projection = projection
    self.intent = intent
  }
}

@MainActor
public protocol PlotterDrawingDraftIntentSink: AnyObject {
  func submitDrawingDraft(_ submission: PlotterDrawingDraftSubmission)
}

public enum PlotterDrawingDraftRefusalReason: Hashable, Sendable {
  case staleProjection
  case studioClosed
  case retainedRunOwnsMutation
  case terminalRunRequiresHandoff
  case exactFrameMismatch
  case registrationUnavailable
  case drawableRegionUnavailable
  case invalidScale
  case invalidRotation
  case coverageExperimentUnavailable
  case planningFailed(String)
  case paperPersistenceFailed(String)
}

public struct PlotterDrawingDraftRefusal: Hashable, Sendable {
  public let requestID: PlotterDrawingDraftRequestID
  public let comparedDraftRevision: PlotterDrawingDraftRevision
  public let comparedExternalFacts: PlotterDrawingDraftExternalFactRevisions
  public let owner: EpisodeAuthorityID
  public let reason: PlotterDrawingDraftRefusalReason
  public let remedy: String

  public init(
    requestID: PlotterDrawingDraftRequestID,
    comparedDraftRevision: PlotterDrawingDraftRevision,
    comparedExternalFacts: PlotterDrawingDraftExternalFactRevisions,
    owner: EpisodeAuthorityID,
    reason: PlotterDrawingDraftRefusalReason,
    remedy: String
  ) {
    self.requestID = requestID
    self.comparedDraftRevision = comparedDraftRevision
    self.comparedExternalFacts = comparedExternalFacts
    self.owner = owner
    self.reason = reason
    self.remedy = remedy
  }
}

public enum PlotterDrawingDraftPreviewStatus: Hashable, Sendable {
  case unavailable(owner: EpisodeAuthorityID, remedy: String)
  case outsideDrawableRegion(reason: String)
  case diagnosticOnly(TipApplicabilityEvidenceLimitation)
  case ready
}

public struct PlotterDrawingDraftPreview: Hashable, Sendable {
  public let displayedFrame: DisplayedFrame
  public let strokes: [Polyline<CameraPixelSpace>]
  public let bounds: AxisAlignedBounds<CameraPixelSpace>?
  public let programContentHash: PlotterModel.Digest
  public let planRevisionID: ExecutionPlanRevisionID?
  public let status: PlotterDrawingDraftPreviewStatus
}

/// Paper polygons are presentation-safe only on the exact frame whose bytes
/// the operator accepted. Assertion currentness is tracked independently.
public struct PlotterDrawingDraftPaperCoverageDisplay: Hashable, Sendable {
  public let observationID: PaperCoverageObservationID
  public let source: FrameSourceIdentity
  public let frame: ExactFrameProvenance
  public let polygon: [Point2<CameraPixelSpace>]
}

public struct PlotterDrawingDraftSnapshot: Hashable, Sendable {
  public let projection: PlotterDrawingDraftProjectionReference
  public let isOpen: Bool
  public let catalog: [DrawingProgramCatalogEntry]
  public let selectedCatalogItemID: DrawingCatalogEntryID?
  public let evidenceRole: BorderValidationEvidenceRole
  public let uniformScale: Double
  public let allowedScale: ClosedRange<Double>
  public let rotationDegrees: Double
  public let machineCenter: Point2<MachineSpace>?
  public let centerCameraPixel: Point2<CameraPixelSpace>?
  public let placementID: UUID
  public let program: DrawingProgram?
  public let plan: ExecutionPlanRevision?
  public let planningRefusal: PlotterDrawingDraftRefusal?
  public let preview: PlotterDrawingDraftPreview?
  public let paperCoverageObservation: PaperCoverageObservation?
  public let paperCoverageIsCurrent: Bool
  public let paperCoverageDisplay: PlotterDrawingDraftPaperCoverageDisplay?
  public let lastSubmissionRefusal: PlotterDrawingDraftRefusal?
  public let coverageExperiment: DrawingCoverageExperiment?
  public let coverageAssessment: DrawingCoverageAssessment?
  public let coverageUnavailableReason: String?

  public static func initial(
    environment: PlotterEnvironment,
    toolAssemblyRevision: ToolAssemblyRevision,
    paper: PaperRevisionContext
  ) -> Self {
    let facts = PlotterDrawingDraftExternalFactRevisions(
      environment: environment,
      interactiveLearningIsComplete: false,
      registrationRevisionID: nil,
      opticalConfiguration: nil,
      drawableRegion: nil,
      toolAssemblyRevision: toolAssemblyRevision,
      paper: paper,
      displayedFrame: nil,
      runInProgress: false,
      terminalRequiresNewPlan: false
    )
    return Self(
      projection: PlotterDrawingDraftProjectionReference(
        environment: environment,
        draftRevision: PlotterDrawingDraftRevision(rawValue: 0),
        externalFacts: facts
      ),
      isOpen: false,
      catalog: DrawingProgramCatalog.entries,
      selectedCatalogItemID: .square,
      evidenceRole: .ordinaryDrawing,
      uniformScale: 0.25,
      allowedScale: 0.02...1,
      rotationDegrees: 0,
      machineCenter: nil,
      centerCameraPixel: nil,
      placementID: UUID(),
      program: nil,
      plan: nil,
      planningRefusal: nil,
      preview: nil,
      paperCoverageObservation: nil,
      paperCoverageIsCurrent: false,
      paperCoverageDisplay: nil,
      lastSubmissionRefusal: nil,
      coverageExperiment: nil, coverageAssessment: nil, coverageUnavailableReason: nil
    )
  }
}

public enum PlotterDrawingDraftSubmissionDisposition: Hashable, Sendable {
  case applied
  case refused(PlotterDrawingDraftRefusal)
}

public struct PlotterDrawingDraftSubmissionResult: Hashable, Sendable {
  public let disposition: PlotterDrawingDraftSubmissionDisposition
  public let snapshot: PlotterDrawingDraftSnapshot
}

public struct PlotterDrawingDraftPlanBuild: Hashable, Sendable {
  public let program: DrawingProgram?
  public let center: Point2<MachineSpace>?
  public let allowedScale: ClosedRange<Double>
  public let plan: ExecutionPlanRevision?
  public let failure: String?
}

/// The only upper-layer route into `DrawingPlanner`. The planner retains all
/// geometry, containment, checkpoint, and content-addressed identity authority.
public enum PlotterDrawingPlanningAdapter {
  public static func buildDraft(
    program: DrawingProgram,
    machineCenter: Point2<MachineSpace>?,
    uniformScale: Double,
    rotationDegrees: Double,
    drawableRegion: DrawableMachineRegion,
    registration: TipCameraRegistration
  ) -> PlotterDrawingDraftPlanBuild {
    let maximum = max(
      0.02,
      min(
        (drawableRegion.effectiveBounds.maxX - drawableRegion.effectiveBounds.minX)
          / program.fieldExtent.width,
        (drawableRegion.effectiveBounds.maxY - drawableRegion.effectiveBounds.minY)
          / program.fieldExtent.height
      ) * 0.9
    )
    let allowedScale = 0.02...maximum
    do {
      let center: Point2<MachineSpace>
      if let machineCenter {
        center = machineCenter
      } else {
        center = try Point2<MachineSpace>(
          x: (drawableRegion.effectiveBounds.minX + drawableRegion.effectiveBounds.maxX) / 2,
          y: (drawableRegion.effectiveBounds.minY + drawableRegion.effectiveBounds.maxY) / 2
        )
      }
      let placement = try DrawingPlacement(
        fieldAnchor: Point2(
          x: program.fieldExtent.width / 2,
          y: program.fieldExtent.height / 2
        ),
        machineAnchor: center,
        uniformScale: uniformScale,
        rotationRadians: rotationDegrees * .pi / 180
      )
      let plan = try DrawingPlanner.plan(
        program: program,
        placement: placement,
        drawableRegion: drawableRegion,
        provenance: try planningProvenance(for: registration)
      )
      return PlotterDrawingDraftPlanBuild(
        program: program,
        center: center,
        allowedScale: allowedScale,
        plan: plan,
        failure: nil
      )
    } catch {
      return PlotterDrawingDraftPlanBuild(
        program: program,
        center: machineCenter,
        allowedScale: allowedScale,
        plan: nil,
        failure: String(describing: error)
      )
    }
  }

  package static func planRetainedDrawingBorder(
    program: DrawingProgram,
    placement: DrawingPlacement,
    drawableRegion: DrawableMachineRegion,
    provenance: DrawingPlanningProvenance
  ) throws -> ExecutionPlanRevision {
    try DrawingPlanner.plan(
      program: program,
      placement: placement,
      drawableRegion: drawableRegion,
      provenance: provenance
    )
  }

  package static func planningProvenance(
    for registration: TipCameraRegistration
  ) throws -> DrawingPlanningProvenance {
    let digest = try registration.drawingEvidenceContentHash()
    return DrawingPlanningProvenance(
      modelRevisionID: DrawingModelRevisionID(registration.acceptedRevisionID.rawValue),
      modelContentHash: digest,
      registrationRevisionID: DrawingRegistrationRevisionID(
        registration.acceptedRevisionID.rawValue
      ),
      registrationContentHash: digest
    )
  }
}

public actor PlotterDrawingDraftRuntime {
  private struct SourceState: Sendable {
    var revision = PlotterDrawingDraftRevision(rawValue: 0)
    var isOpen = false
    var selectedCatalogItemID: DrawingCatalogEntryID = .square
    var suppliedProgram: DrawingProgram?
    var evidenceRole: BorderValidationEvidenceRole = .ordinaryDrawing
    var uniformScale = 0.25
    var rotationDegrees = 0.0
    var machineCenter: Point2<MachineSpace>?
    var placementID = UUID()
    var program: DrawingProgram?
    var plan: ExecutionPlanRevision?
    var planningRefusal: PlotterDrawingDraftRefusal?
    var preview: PlotterDrawingDraftPreview?
    var paperCoverageObservation: PaperCoverageObservation?
    var lastSubmissionRefusal: PlotterDrawingDraftRefusal?
    var coverageExperiment: DrawingCoverageExperiment?
    var coverageAssessment: DrawingCoverageAssessment?
    var coverageRecordIDs: [DrawingEvidenceRecordID]?
    var coverageUnavailableReason: String?
    var derivationKey: DerivationKey?
    var previewDerivationIsAvailable = false
  }

  /// Geometry depends on artwork and calibration, not camera pixels, control
  /// progress, panel visibility, or the current Learning status.
  private struct DerivationKey: Equatable {
    let catalog: DrawingCatalogEntryID
    let suppliedProgramHash: PlotterModel.Digest?
    let center: Point2<MachineSpace>?
    let scale: Double
    let rotation: Double
    let registration: TipCameraRegistration?
    let region: DrawableMachineRegion?
    let tool: ToolAssemblyRevision
    let paper: PaperRevisionContext
    let experiment: DrawingCoverageExperiment?
    let coverageRecords: [DrawingEvidenceRecordID]
    let opticalConfiguration: CameraOpticalConfigurationIdentity?

    init(state: SourceState, facts: PlotterDrawingDraftExternalFacts) {
      catalog = state.selectedCatalogItemID
      suppliedProgramHash = state.suppliedProgram?.contentHash
      center = state.machineCenter
      scale = state.uniformScale
      rotation = state.rotationDegrees
      registration = facts.registration
      region = facts.revisions.drawableRegion
      tool = facts.revisions.toolAssemblyRevision
      paper = facts.revisions.paper
      experiment = state.coverageExperiment
      coverageRecords = facts.revisions.coverageRecordIDs
      opticalConfiguration = facts.revisions.opticalConfiguration
    }
  }

  package private(set) var derivationBuildCount = 0

  private enum Authority {
    static let draft = EpisodeAuthorityID(rawValue: "PlotterDrawingDraftRuntime")
    static let registration = EpisodeAuthorityID(rawValue: "TipCameraRegistration")
    static let region = EpisodeAuthorityID(rawValue: "PlotterModel.DrawableMachineRegion")
    static let camera = EpisodeAuthorityID(rawValue: "CameraEvidenceAuthority")
    static let run = EpisodeAuthorityID(rawValue: "PlotterDrawingRunAuthority")
    static let paper = EpisodeAuthorityID(rawValue: "PlotterPaperCoverageAuthority")
    static let planner = EpisodeAuthorityID(rawValue: "PlotterModel.ExecutionPlanRevision")
  }

  private let paperPersistence: any PlotterDrawingDraftPaperPersistence
  private let clock: any RuntimeClock
  private var states: [PlotterEnvironment: SourceState] = [:]
  private var latestFacts: [PlotterEnvironment: PlotterDrawingDraftExternalFacts] = [:]
  private var loadedPaperCoverage = false
  /// Actor reentrancy must not let a persistence suspension split validation
  /// from publication. Ownership stays with the current turn until it commits
  /// or refuses, and queued callers resume in arrival order.
  private var mutationBoundaryIsOccupied = false
  private var mutationBoundaryWaiters: [CheckedContinuation<Void, Never>] = []

  public init(
    paperPersistence: any PlotterDrawingDraftPaperPersistence =
      PlotterDrawingDraftTransientPaperPersistence(),
    clock: any RuntimeClock = SystemRuntimeClock()
  ) {
    self.paperPersistence = paperPersistence
    self.clock = clock
  }

  public func synchronize(
    _ facts: PlotterDrawingDraftExternalFacts
  ) async -> PlotterDrawingDraftSnapshot {
    await acquireMutationBoundary()
    defer { releaseMutationBoundary() }
    return await synchronizeWithinMutationBoundary(facts)
  }

  private func synchronizeWithinMutationBoundary(
    _ facts: PlotterDrawingDraftExternalFacts
  ) async -> PlotterDrawingDraftSnapshot {
    await loadPaperCoverageIfNeeded()
    let environment = facts.revisions.environment
    latestFacts[environment] = facts
    var state = states[environment] ?? SourceState()
    rebuild(state: &state, facts: facts, requestID: nil)
    states[environment] = state
    return snapshot(state: state, facts: facts)
  }

  public func submit(
    _ submission: PlotterDrawingDraftSubmission,
    facts: PlotterDrawingDraftExternalFacts
  ) async -> PlotterDrawingDraftSubmissionResult {
    await acquireMutationBoundary()
    defer { releaseMutationBoundary() }
    let current = await synchronizeWithinMutationBoundary(facts)
    let environment = facts.revisions.environment
    var state = states[environment] ?? SourceState()
    let projectionMatches: Bool
    switch submission.intent {
    case .open, .close:
      // Panel visibility grants no drawing or evidence authority. Eligibility
      // below uses current facts even while completion is being published.
      projectionMatches = submission.projection.environment == current.projection.environment
        && submission.projection.draftRevision == current.projection.draftRevision
    case .placeAtCameraPoint, .assertPaperCoverage:
      projectionMatches = submission.projection == current.projection
    default:
      projectionMatches = submission.projection.environment == current.projection.environment
        && submission.projection.draftRevision == current.projection.draftRevision
        && submission.projection.externalFacts.matchesAuthoring(current.projection.externalFacts)
    }
    guard projectionMatches else {
      return refuse(
        submission,
        state: &state,
        facts: facts,
        owner: Authority.draft,
        reason: .staleProjection,
        remedy: "Use the current Drawing Studio projection and retry the requested edit."
      )
    }

    if submission.intent != .open {
      guard state.isOpen else {
        return refuse(
          submission,
          state: &state,
          facts: facts,
          owner: Authority.draft,
          reason: .studioClosed,
          remedy: "Open Drawing Studio before changing its draft."
        )
      }
    }

    guard !facts.revisions.runInProgress else {
      return refuse(
        submission,
        state: &state,
        facts: facts,
        owner: Authority.run,
        reason: .retainedRunOwnsMutation,
        remedy: "Wait for the current drawing run and evidence capture to settle."
      )
    }
    if facts.revisions.terminalRequiresNewPlan,
      submission.intent != .open,
      submission.intent != .close
    {
      return refuse(
        submission,
        state: &state,
        facts: facts,
        owner: Authority.run,
        reason: .terminalRunRequiresHandoff,
        remedy: "Use New Drawing to clear the retained terminal before editing a new plan."
      )
    }

    if state.coverageExperiment != nil {
      switch submission.intent {
      case .open, .close, .beginNewPlan, .assertPaperCoverage,
        .nextCoverageTrial, .leaveCoverageExperiment, .prepareCoverageExperiment: break
      default:
        return refuse(submission, state: &state, facts: facts, owner: Authority.draft,
          reason: .coverageExperimentUnavailable,
          remedy: "Coverage geometry and evidence roles are sealed. Leave the experiment to author another drawing.")
      }
    }

    switch submission.intent {
    case .prepareCoverageExperiment, .nextCoverageTrial:
      do {
        guard facts.revisions.drawingArchiveIsAvailable else {
          throw PlotterModelError.invalidValue("Load the drawing archive before preparing or resuming an experiment.")
        }
        guard let registration = facts.registration,
          let region = facts.revisions.drawableRegion else {
          throw PlotterModelError.invalidValue("Restore current tip calibration and Drawing Boundary first.")
        }
        let prior = try PlotterDrawingPlanningAdapter.planningProvenance(for: registration)
        if state.coverageExperiment == nil {
          // Resume from existing immutable source provenance. Never propose a
          // fresh overlapping design on a sheet with earlier experiment ink.
          if facts.coverageRecords.contains(where: {
            $0.paper == facts.revisions.paper && $0.role == .ordinaryDrawing
              && $0.executionFrontiers.commandedStrokeCount > 0
          }) {
            throw PlotterModelError.invalidValue("This sheet already has drawing ink. Replace the sheet before preparing coverage trials.")
          }
          if let priorRecord = facts.coverageRecords.last(where: {
            $0.paper == facts.revisions.paper && $0.program.source?.kind == DrawingCoverageExperiment.sourceKind
          }) {
            guard let descriptor = DrawingCoverageTrialDescriptor.decode(priorRecord.program.source) else {
              throw PlotterModelError.invalidValue("The sheet has unreadable experiment provenance. Use a new sheet.")
            }
            state.coverageExperiment = descriptor.experiment
          } else {
            state.coverageExperiment = try DrawingCoverageExperiment(region: region,
              registration: registration, prior: prior, paper: facts.revisions.paper,
              style: StrokeStyle(nominalLineWidth: 0.4,
                penProfileID: PenProfileID(facts.revisions.toolAssemblyRevision.rawValue)))
          }
          state.coverageRecordIDs = nil
        }
        guard let experiment = state.coverageExperiment,
          experiment.isCurrent(registration: registration, prior: prior,
            region: region, paper: facts.revisions.paper) else {
          throw PlotterModelError.invalidValue("Experiment provenance changed. Leave the experiment and use a new sheet.")
        }
        let assessment = DrawingCoverageAssessment.evaluate(experiment: experiment,
          records: facts.coverageRecords, registration: registration)
        state.coverageAssessment = assessment
        state.coverageRecordIDs = facts.revisions.coverageRecordIDs
        state.coverageUnavailableReason = nil
        if let blocker = assessment.blocker { throw PlotterModelError.invalidValue(blocker) }
        if let trial = assessment.nextTrial ?? experiment.trials.last(where: { assessment.attemptedIndices.contains($0.index) }) {
          state.suppliedProgram = try experiment.program(for: trial)
          state.evidenceRole = trial.role
          state.machineCenter = experiment.center
          state.uniformScale = 1
          state.rotationDegrees = 0
          state.placementID = UUID()
        }
      } catch {
        if state.coverageExperiment != nil {
          state.derivationKey = nil
          state.plan = nil
          state.preview = nil
          state.coverageUnavailableReason = String(describing: error)
        }
        return refuse(submission, state: &state, facts: facts, owner: Authority.draft,
          reason: .coverageExperimentUnavailable, remedy: String(describing: error))
      }
    case .leaveCoverageExperiment:
      state.coverageExperiment = nil
      state.coverageAssessment = nil
      state.coverageRecordIDs = nil
      state.coverageUnavailableReason = nil
      state.suppliedProgram = nil
      state.evidenceRole = .ordinaryDrawing
      state.uniformScale = 0.25
      state.machineCenter = nil
      state.placementID = UUID()
    case .open:
      state.isOpen = true
    case .close:
      state.isOpen = false
    case .selectCatalogItem(let id):
      state.selectedCatalogItemID = id
      state.suppliedProgram = nil
      state.placementID = UUID()
    case .selectProgram(let program):
      state.suppliedProgram = program
      state.uniformScale = min(state.uniformScale, allowedScale(state: state, facts: facts).upperBound)
      state.placementID = UUID()
    case .setEvidenceRole(let role):
      state.evidenceRole = role
    case .placeAtCameraPoint(let placement):
      guard placement.frame == facts.revisions.displayedFrame else {
        return refuse(
          submission,
          state: &state,
          facts: facts,
          owner: Authority.camera,
          reason: .exactFrameMismatch,
          remedy: "Place the target from the currently displayed exact frame."
        )
      }
      guard let registration = facts.registration,
        let inverse = try? registration.cameraFromMachine.inverted(),
        let point = try? inverse.applying(to: placement.point)
      else {
        return refuse(
          submission,
          state: &state,
          facts: facts,
          owner: Authority.registration,
          reason: .registrationUnavailable,
          remedy: "Restore a current accepted pen-tip registration before placing the target."
        )
      }
      state.machineCenter = point
      state.placementID = UUID()
    case .setUniformScale(let scale):
      let allowed = allowedScale(state: state, facts: facts)
      guard scale.isFinite, scale > 0, allowed.contains(scale) else {
        return refuse(
          submission,
          state: &state,
          facts: facts,
          owner: Authority.planner,
          reason: .invalidScale,
          remedy: "Choose a positive finite scale within the published allowed range."
        )
      }
      state.uniformScale = scale
      state.placementID = UUID()
    case .setRotationDegrees(let degrees):
      guard degrees.isFinite else {
        return refuse(
          submission,
          state: &state,
          facts: facts,
          owner: Authority.planner,
          reason: .invalidRotation,
          remedy: "Choose a finite rotation in degrees."
        )
      }
      state.rotationDegrees = Self.normalizedDegrees(degrees)
      state.placementID = UUID()
    case .centerInDrawableRegion:
      guard let bounds = facts.revisions.drawableRegion?.effectiveBounds,
        let center = try? Point2<MachineSpace>(
          x: (bounds.minX + bounds.maxX) / 2,
          y: (bounds.minY + bounds.maxY) / 2
        )
      else {
        return refuse(
          submission,
          state: &state,
          facts: facts,
          owner: Authority.region,
          reason: .drawableRegionUnavailable,
          remedy: "Restore the current accepted Drawing Boundary before centering the target."
        )
      }
      state.machineCenter = center
      state.placementID = UUID()
    case .beginNewPlan:
      state.placementID = UUID()
    case .assertPaperCoverage:
      guard let frame = facts.displayedFrame,
        let registration = facts.registration,
        let bounds = facts.revisions.drawableRegion?.effectiveBounds
      else {
        return refuse(
          submission,
          state: &state,
          facts: facts,
          owner: Authority.paper,
          reason: .registrationUnavailable,
          remedy: "Display a current frame with accepted registration and Drawing Boundary first."
        )
      }
      do {
        let machineCorners: [Point2<MachineSpace>] = try [
          Point2(x: bounds.minX, y: bounds.minY),
          Point2(x: bounds.maxX, y: bounds.minY),
          Point2(x: bounds.maxX, y: bounds.maxY),
          Point2(x: bounds.minX, y: bounds.maxY),
        ]
        let polygon = try machineCorners.map {
          try registration.diagnosticProjection(at: $0).cameraPoint
        }
        let observation = try PaperCoverageObservation(
          paper: facts.revisions.paper,
          source: frame.source,
          frame: ExactFrameProvenance(frame: frame.frame),
          polygon: polygon,
          method: .operatorAccepted,
          observedAt: RuntimeTimestamp(
            monotonicNanoseconds: max(clock.nowNanoseconds(), frame.frame.captureNanoseconds)
          ),
          algorithmRevision: "operator-attested-drawing-boundary-diagnostic-projection-v3"
        )
        if environment == .live {
          try await paperPersistence.save(observation)
        }
        state.paperCoverageObservation = observation
      } catch {
        return refuse(
          submission,
          state: &state,
          facts: facts,
          owner: Authority.paper,
          reason: .paperPersistenceFailed(String(describing: error)),
          remedy: "Resolve paper-coverage persistence and assert the current sheet again."
        )
      }
    }

    state.revision = PlotterDrawingDraftRevision(rawValue: state.revision.rawValue &+ 1)
    state.lastSubmissionRefusal = nil
    rebuild(state: &state, facts: facts, requestID: submission.requestID)
    states[environment] = state
    return PlotterDrawingDraftSubmissionResult(
      disposition: .applied,
      snapshot: snapshot(state: state, facts: facts)
    )
  }

  package func clearPaperCoverageForRetainedPaperLifecycle(
    facts: PlotterDrawingDraftExternalFacts
  ) async -> PlotterDrawingDraftSubmissionResult {
    await acquireMutationBoundary()
    defer { releaseMutationBoundary() }
    let current = await synchronizeWithinMutationBoundary(facts)
    let request = PlotterDrawingDraftSubmission(
      projection: current.projection,
      intent: .assertPaperCoverage
    )
    let environment = facts.revisions.environment
    var state = states[environment] ?? SourceState()
    do {
      if environment == .live { try await paperPersistence.clear() }
      state.paperCoverageObservation = nil
      state.revision = PlotterDrawingDraftRevision(rawValue: state.revision.rawValue &+ 1)
      state.lastSubmissionRefusal = nil
      states[environment] = state
      return PlotterDrawingDraftSubmissionResult(
        disposition: .applied,
        snapshot: snapshot(state: state, facts: facts)
      )
    } catch {
      return refuse(
        request,
        state: &state,
        facts: facts,
        owner: Authority.paper,
        reason: .paperPersistenceFailed(String(describing: error)),
        remedy: "Resolve paper persistence before replacing its retained assertion."
      )
    }
  }

  private func loadPaperCoverageIfNeeded() async {
    guard !loadedPaperCoverage else { return }
    let observation = await paperPersistence.load()
    guard !loadedPaperCoverage else { return }
    loadedPaperCoverage = true
    var live = states[.live] ?? SourceState()
    live.paperCoverageObservation = observation
    states[.live] = live
  }

  private func acquireMutationBoundary() async {
    guard mutationBoundaryIsOccupied else {
      mutationBoundaryIsOccupied = true
      return
    }
    await withCheckedContinuation { mutationBoundaryWaiters.append($0) }
  }

  private func releaseMutationBoundary() {
    guard !mutationBoundaryWaiters.isEmpty else {
      mutationBoundaryIsOccupied = false
      return
    }
    mutationBoundaryWaiters.removeFirst().resume()
  }

  private func rebuild(
    state: inout SourceState,
    facts: PlotterDrawingDraftExternalFacts,
    requestID: PlotterDrawingDraftRequestID?
  ) {
    let key = DerivationKey(state: state, facts: facts)
    if state.derivationKey == key {
      if let refusal = state.planningRefusal {
        state.planningRefusal = issue(requestID: requestID, state: state, facts: facts,
          owner: refusal.owner, reason: refusal.reason, remedy: refusal.remedy)
      }
      guard state.previewDerivationIsAvailable else { return }
      if let frame = facts.displayedFrame, let previous = state.preview,
        previous.displayedFrame.source == frame.source,
        previous.displayedFrame.frame.cameraConfigurationID == frame.frame.cameraConfigurationID,
        previous.displayedFrame.frame.width == frame.frame.width,
        previous.displayedFrame.frame.height == frame.frame.height,
        previous.displayedFrame.frame.pixelFormat == frame.frame.pixelFormat {
        state.preview = PlotterDrawingDraftPreview(displayedFrame: frame,
          strokes: previous.strokes, bounds: previous.bounds,
          programContentHash: previous.programContentHash,
          planRevisionID: previous.planRevisionID, status: previous.status)
      } else {
        state.preview = facts.registration.flatMap {
          makePreview(state: state, facts: facts, registration: $0)
        }
      }
      return
    }
    derivationBuildCount += 1
    state.previewDerivationIsAvailable = false
    // Planning may resolve the default center. Cache its resulting inputs.
    defer { state.derivationKey = DerivationKey(state: state, facts: facts) }
    if let experiment = state.coverageExperiment {
      if let registration = facts.registration,
        let region = facts.revisions.drawableRegion,
        let prior = try? PlotterDrawingPlanningAdapter.planningProvenance(for: registration),
        experiment.isCurrent(registration: registration, prior: prior,
          region: region, paper: facts.revisions.paper) {
        state.coverageUnavailableReason = nil
        if state.coverageRecordIDs != facts.revisions.coverageRecordIDs {
          state.coverageAssessment = DrawingCoverageAssessment.evaluate(experiment: experiment,
            records: facts.coverageRecords, registration: registration)
          state.coverageRecordIDs = facts.revisions.coverageRecordIDs
        }
      } else {
        state.coverageUnavailableReason = "Experiment provenance changed. Leave the experiment and use a new sheet."
        state.plan = nil
        state.preview = nil
        return
      }
    }
    // Artwork is independent of calibration. Retain it while planning is
    // unavailable so an authored portrait survives Learning and revalidation.
    let program = state.suppliedProgram ?? (try? DrawingProgramCatalog.program(
      for: state.selectedCatalogItemID,
      style: StrokeStyle(
        nominalLineWidth: 0.4,
        penProfileID: PenProfileID(facts.revisions.toolAssemblyRevision.rawValue)
      )
    ))
    state.program = program
    if let experiment = state.coverageExperiment,
      DrawingCoverageTrialDescriptor.decode(program?.source)?.experiment != experiment {
      state.plan = nil
      state.preview = nil
      state.planningRefusal = issue(requestID: requestID, state: state, facts: facts,
        owner: Authority.draft, reason: .coverageExperimentUnavailable,
        remedy: state.coverageAssessment?.blocker ?? "Select a current sealed experiment trial or leave the experiment.")
      return
    }
    guard let registration = facts.registration else {
      state.plan = nil
      state.preview = nil
      state.planningRefusal = issue(
        requestID: requestID,
        state: state,
        facts: facts,
        owner: Authority.registration,
        reason: .registrationUnavailable,
        remedy: "Restore a current accepted pen-tip registration."
      )
      return
    }
    guard let region = facts.revisions.drawableRegion else {
      state.plan = nil
      state.preview = nil
      state.planningRefusal = issue(
        requestID: requestID,
        state: state,
        facts: facts,
        owner: Authority.region,
        reason: .drawableRegionUnavailable,
        remedy: "Restore the current accepted Drawing Boundary."
      )
      return
    }
    guard let program else { return }
    if let assessment = state.coverageAssessment,
      let descriptor = DrawingCoverageTrialDescriptor.decode(program.source),
      assessment.blocker != nil || assessment.attemptedIndices.contains(descriptor.trialIndex) {
      state.plan = nil
      state.preview = nil
      state.planningRefusal = issue(requestID: requestID, state: state, facts: facts,
        owner: Authority.draft, reason: .coverageExperimentUnavailable,
        remedy: assessment.blocker ?? "This trial is recorded. Select Next Experiment Trial or leave the experiment.")
      return
    }
    let built = PlotterDrawingPlanningAdapter.buildDraft(
      program: program,
      machineCenter: state.machineCenter,
      uniformScale: state.uniformScale,
      rotationDegrees: state.rotationDegrees,
      drawableRegion: region,
      registration: registration
    )
    state.machineCenter = built.center ?? state.machineCenter
    state.program = built.program
    state.plan = built.plan
    if let failure = built.failure {
      state.planningRefusal = issue(
        requestID: requestID,
        state: state,
        facts: facts,
        owner: Authority.planner,
        reason: .planningFailed(failure),
        remedy: "Move, resize, or rotate the target fully inside the accepted Drawing Boundary."
      )
    } else {
      state.planningRefusal = nil
    }
    state.previewDerivationIsAvailable = true
    state.preview = makePreview(state: state, facts: facts, registration: registration)
  }

  private func makePreview(
    state: SourceState,
    facts: PlotterDrawingDraftExternalFacts,
    registration: TipCameraRegistration
  ) -> PlotterDrawingDraftPreview? {
    guard let frame = facts.displayedFrame, let program = state.program else { return nil }
    guard let opticalConfiguration = facts.revisions.opticalConfiguration,
      opticalConfiguration == registration.applicability.opticalConfiguration,
      frame.source.plotterEnvironment == facts.revisions.environment,
      frame.source == opticalConfiguration.source,
      frame.frame.width == opticalConfiguration.width,
      frame.frame.height == opticalConfiguration.height,
      frame.frame.pixelFormat == opticalConfiguration.pixelFormat
    else {
      return PlotterDrawingDraftPreview(
        displayedFrame: frame,
        strokes: [],
        bounds: nil,
        programContentHash: program.contentHash,
        planRevisionID: state.plan?.revisionID,
        status: .unavailable(
          owner: Authority.camera,
          remedy: "Display a frame from the accepted registration's exact camera configuration."
        )
      )
    }
    guard let plan = state.plan else {
      return PlotterDrawingDraftPreview(
        displayedFrame: frame,
        strokes: [],
        bounds: nil,
        programContentHash: program.contentHash,
        planRevisionID: nil,
        status: .outsideDrawableRegion(
          reason: state.planningRefusal?.remedy
            ?? "Place the target inside the accepted Drawing Boundary."
        )
      )
    }
    do {
      let evidenceProjection = try TipApplicabilityEvidencePolicy.project(
        paths: plan.strokes.map(\.path),
        using: registration
      )
      let projected = try evidenceProjection.attributableCameraPolylines ?? plan.strokes.map { stroke in
        try Polyline(points: stroke.path.points.map {
          try registration.diagnosticProjection(at: $0).cameraPoint
        })
      }
      let points = projected.flatMap(\.points)
      let bounds: AxisAlignedBounds<CameraPixelSpace>?
      if let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
        let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() {
        // Bounds are a display/hit-target rectangle. An axis-aligned line has
        // zero extent on one axis; give that axis a pixel without altering the
        // exact projected path, execution geometry, or evidence applicability.
        let padX = max(0, 1 - (maxX - minX)) / 2
        let padY = max(0, 1 - (maxY - minY)) / 2
        bounds = try AxisAlignedBounds(minX: minX - padX, minY: minY - padY,
                                       maxX: maxX + padX, maxY: maxY + padY)
      } else { bounds = nil }
      return PlotterDrawingDraftPreview(
        displayedFrame: frame,
        strokes: projected,
        bounds: bounds,
        programContentHash: program.contentHash,
        planRevisionID: plan.revisionID,
        status: evidenceProjection.diagnosticLimitation.map {
          .diagnosticOnly($0)
        } ?? .ready
      )
    } catch {
      return PlotterDrawingDraftPreview(
        displayedFrame: frame,
        strokes: [],
        bounds: nil,
        programContentHash: program.contentHash,
        planRevisionID: plan.revisionID,
        status: .unavailable(
          owner: Authority.registration,
          remedy: "The current registration cannot project this exact plan: \(error)"
        )
      )
    }
  }

  private func snapshot(
    state: SourceState,
    facts: PlotterDrawingDraftExternalFacts
  ) -> PlotterDrawingDraftSnapshot {
    let coverageIsCurrent: Bool
    if let coverage = state.paperCoverageObservation,
      let frame = facts.displayedFrame
    {
      // Freshness belongs to the paper/source/config/contact-plane context,
      // not to whichever newer exact frame currently carries that context.
      coverageIsCurrent = coverage.validation(
        against: PaperCoverageValidationContext(
          paper: facts.revisions.paper,
          source: frame.source,
          frameID: coverage.frame.frameID,
          cameraConfigurationID: frame.frame.cameraConfigurationID
        )
      ) == .valid
    } else {
      coverageIsCurrent = false
    }

    let coverageDisplay: PlotterDrawingDraftPaperCoverageDisplay?
    if let coverage = state.paperCoverageObservation,
      let frame = facts.displayedFrame,
      coverage.source == frame.source,
      coverage.frame == ExactFrameProvenance(frame: frame.frame)
    {
      coverageDisplay = PlotterDrawingDraftPaperCoverageDisplay(
        observationID: coverage.id,
        source: coverage.source,
        frame: coverage.frame,
        polygon: coverage.polygon
      )
    } else {
      coverageDisplay = nil
    }

    let centerCameraPixel: Point2<CameraPixelSpace>?
    if let center = state.machineCenter, let registration = facts.registration {
      centerCameraPixel = try? registration.diagnosticProjection(at: center).cameraPoint
    } else {
      centerCameraPixel = nil
    }
    return PlotterDrawingDraftSnapshot(
      projection: PlotterDrawingDraftProjectionReference(
        environment: facts.revisions.environment,
        draftRevision: state.revision,
        externalFacts: facts.revisions
      ),
      isOpen: state.isOpen,
      catalog: DrawingProgramCatalog.entries,
      selectedCatalogItemID: state.suppliedProgram == nil ? state.selectedCatalogItemID : nil,
      evidenceRole: state.evidenceRole,
      uniformScale: state.uniformScale,
      allowedScale: allowedScale(state: state, facts: facts),
      rotationDegrees: state.rotationDegrees,
      machineCenter: state.machineCenter,
      centerCameraPixel: centerCameraPixel,
      placementID: state.placementID,
      program: state.program,
      plan: state.plan,
      planningRefusal: state.planningRefusal,
      preview: state.preview,
      paperCoverageObservation: state.paperCoverageObservation,
      paperCoverageIsCurrent: coverageIsCurrent,
      paperCoverageDisplay: coverageDisplay,
      lastSubmissionRefusal: state.lastSubmissionRefusal,
      coverageExperiment: state.coverageExperiment,
      coverageAssessment: state.coverageAssessment,
      coverageUnavailableReason: state.coverageUnavailableReason
    )
  }

  private func allowedScale(
    state: SourceState,
    facts: PlotterDrawingDraftExternalFacts
  ) -> ClosedRange<Double> {
    if state.coverageExperiment != nil { return 1...1 }
    guard let region = facts.revisions.drawableRegion else { return 0.02...1 }
    let extent = state.suppliedProgram?.fieldExtent
      ?? DrawingProgramCatalog.entry(for: state.selectedCatalogItemID).fieldExtent
    let maximum = max(
      0.02,
      min(
        (region.effectiveBounds.maxX - region.effectiveBounds.minX) / extent.width,
        (region.effectiveBounds.maxY - region.effectiveBounds.minY) / extent.height
      ) * 0.9
    )
    return 0.02...maximum
  }

  private func issue(
    requestID: PlotterDrawingDraftRequestID?,
    state: SourceState,
    facts: PlotterDrawingDraftExternalFacts,
    owner: EpisodeAuthorityID,
    reason: PlotterDrawingDraftRefusalReason,
    remedy: String
  ) -> PlotterDrawingDraftRefusal {
    PlotterDrawingDraftRefusal(
      requestID: requestID ?? PlotterDrawingDraftRequestID(),
      comparedDraftRevision: state.revision,
      comparedExternalFacts: facts.revisions,
      owner: owner,
      reason: reason,
      remedy: remedy
    )
  }

  private func refuse(
    _ submission: PlotterDrawingDraftSubmission,
    state: inout SourceState,
    facts: PlotterDrawingDraftExternalFacts,
    owner: EpisodeAuthorityID,
    reason: PlotterDrawingDraftRefusalReason,
    remedy: String
  ) -> PlotterDrawingDraftSubmissionResult {
    let refusal = issue(
      requestID: submission.requestID,
      state: state,
      facts: facts,
      owner: owner,
      reason: reason,
      remedy: remedy
    )
    state.lastSubmissionRefusal = refusal
    states[facts.revisions.environment] = state
    return PlotterDrawingDraftSubmissionResult(
      disposition: .refused(refusal),
      snapshot: snapshot(state: state, facts: facts)
    )
  }

  private static func normalizedDegrees(_ degrees: Double) -> Double {
    var normalized = degrees.truncatingRemainder(dividingBy: 360)
    if normalized >= 180 { normalized -= 360 }
    if normalized < -180 { normalized += 360 }
    return normalized == 0 ? 0 : normalized
  }
}

public extension DisplayedFrame {
  var plotterExactFrameReferenceIfMaterialized: PlotterExactFrameReference? {
    guard let contentSHA256 = frame.materializedContentSHA256 else { return nil }
    return PlotterExactFrameReference(
      frameID: frame.id.rawValue,
      frameSHA256: contentSHA256,
      source: source.plotterExactFrameSource,
      cameraConfigurationID: frame.cameraConfigurationID,
      captureNanoseconds: frame.captureNanoseconds,
      sequence: frame.sequence,
      width: frame.width,
      height: frame.height,
      rowBytes: frame.rowBytes,
      pixelFormat: PlotterExactFramePixelFormat(rawValue: frame.pixelFormat.rawValue)!
    )
  }

  var plotterExactFrameReference: PlotterExactFrameReference {
    guard let reference = plotterExactFrameReferenceIfMaterialized else {
      preconditionFailure(
        "An exact frame reference requires a frame sealed by analysis or an exact evidence workflow."
      )
    }
    return reference
  }
}

private extension FrameSourceIdentity {
  var plotterExactFrameSource: PlotterExactFrameSource {
    switch self {
    case .live(let deviceID): .live(deviceID: deviceID.rawValue)
    case .simulated: .simulated
    }
  }

  var plotterEnvironment: PlotterEnvironment {
    switch self {
    case .live: .live
    case .simulated: .simulated
    }
  }
}
