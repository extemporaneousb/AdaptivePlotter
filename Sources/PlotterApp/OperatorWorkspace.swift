import EpisodeCore
import EpisodeRuntime
import Foundation
import Observation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import PlotterUI

private extension PlotterBoundaryDirection {
  var runtimeDirection: BoundaryDirection {
    BoundaryDirection(rawValue: rawValue)!
  }
}

enum FixedCameraOpticalSettlingPolicy {
  // Image-pair ink alignment has its own policy. Cap acquisition below keeps
  // exact identities and observed spread, with no numerical spread veto.
  // Controller settlement remains independently authoritative.
  static let alignmentSearchRadiusPixels = 3
  static let maximumAlignmentShiftPixels = 2
  static let requiredCentroidFrameCount = 3
  static let maximumBackgroundMeanAbsoluteDifference: Double = 4

  static func newestCompatibleCapSample(
    _ samples: [StableWorkflowCapInspection]
  ) throws -> StableWorkflowCapInspection {
    guard samples.count == requiredCentroidFrameCount else {
      throw LearningPathOperationError.requiredState(
        "Pen-cap settlement requires exactly \(requiredCentroidFrameCount) exact frames."
      )
    }
    for sample in samples {
      guard
        sample.inspection.measurement.frameID
          == sample.inspection.displayedFrame.frame.id,
        sample.inspection.measurement.cameraConfigurationID
          == sample.inspection.displayedFrame.frame.cameraConfigurationID,
        sample.inspection.measurement.frameSHA256
          == sample.inspection.displayedFrame.frame.contentSHA256
      else {
        throw LearningPathOperationError.requiredState(
          "Pen-cap settlement result did not belong to its exact displayed frame."
        )
      }
    }
    for (previous, current) in zip(samples, samples.dropFirst()) {
      guard
        previous.inspection.displayedFrame.source == current.inspection.displayedFrame.source,
        previous.inspection.displayedFrame.frame.cameraConfigurationID
          == current.inspection.displayedFrame.frame.cameraConfigurationID
      else {
        throw LearningPathOperationError.requiredState(
          "Camera source or configuration changed during cap settlement."
        )
      }
      guard
        current.inspection.displayedFrame.frame.captureNanoseconds
          > previous.inspection.displayedFrame.frame.captureNanoseconds
      else {
        throw LearningPathOperationError.freshFrameUnavailable
      }
    }
    let maximumSpread =
      samples.enumerated().flatMap { leftIndex, left in
        samples.dropFirst(leftIndex + 1).map {
          left.cap.centroid.distance(to: $0.cap.centroid)
        }
      }.max() ?? 0
    let newest = samples[samples.index(before: samples.endIndex)]
    return StableWorkflowCapInspection(
      inspection: newest.inspection,
      cap: newest.cap,
      centroidSpreadPixels: maximumSpread
    )
  }
}

struct VideoAnalysisRegionLock: Hashable, Sendable {
  let source: FrameSourceIdentity
  let cameraConfigurationID: CameraConfigurationID
  let region: PixelRect

  func matches(_ displayedFrame: DisplayedFrame) -> Bool {
    source == displayedFrame.source
      && cameraConfigurationID == displayedFrame.frame.cameraConfigurationID
  }
}

enum OperatorFrameMode: String, CaseIterable, Hashable, Identifiable, Sendable {
  case live = "LIVE"
  case simulated = "SIMULATED"

  var id: Self { self }
}

enum AcceptedArtifactCheckpointStatus: Equatable, Sendable {
  case unavailable
  case cleared
  case awaitingOperatorDecision(sideCount: Int, hasTipCalibration: Bool)
  case appliedByOperator(sideCount: Int, hasTipCalibration: Bool)
  case retainedForLater(sideCount: Int, hasTipCalibration: Bool)
  case quarantined(sideCount: Int)
  case saved(sideCount: Int, centerArrival: Bool)
  case restored(sideCount: Int, centerArrival: Bool, reportedPositionDeltaMM: Double)
  case incompatible(String)
  case rejected(String)
}

enum ControllerPoseApplicability: Equatable, Sendable {
  case currentSession
  case requiresVisualRevalidation(reportedPositionDeltaMM: Double)
  case visuallyRevalidated(frameID: FrameID, residualPixels: Double)
}

enum JogDirection: String, CaseIterable, Identifiable, Sendable {
  case xNegative
  case xPositive
  case yNegative
  case yPositive

  var id: Self { self }

  var shortLabel: String {
    switch self {
    case .xNegative: "X−"
    case .xPositive: "X+"
    case .yNegative: "Y−"
    case .yPositive: "Y+"
    }
  }
}

enum ContextualStopTarget: Hashable, Sendable {
  case exerciseMotion(
    capabilityID: ContextualStopCapabilityID,
    operationOwner: ContextualMotionOwnerID,
    ownerID: LearningPathItemID,
    action: LearningMotionAction
  )
  case borderValidation(
    capabilityID: ContextualStopCapabilityID, operationOwner: ContextualMotionOwnerID)
  case positionRecovery(capabilityID: ContextualStopCapabilityID)
  case sparseTipBatch(
    capabilityID: ContextualStopCapabilityID,
    attemptID: ExerciseAttemptID
  )
  case sparseTipBatchSegment(
    capabilityID: ContextualStopCapabilityID,
    operationOwner: ContextualMotionOwnerID,
    location: BlacklistedToolContactLocation
  )

  var capabilityID: ContextualStopCapabilityID {
    switch self {
    case .exerciseMotion(let capabilityID, _, _, _),
      .borderValidation(let capabilityID, _),
      .positionRecovery(let capabilityID),
      .sparseTipBatch(let capabilityID, _),
      .sparseTipBatchSegment(let capabilityID, _, _):
      capabilityID
    }
  }

  var operationOwner: ContextualMotionOwnerID? {
    switch self {
    case .exerciseMotion(_, let owner, _, _),
      .borderValidation(_, let owner),
      .sparseTipBatchSegment(_, let owner, _):
      owner
    case .sparseTipBatch, .positionRecovery:
      nil
    }
  }
}

/// Semantic identity for every supervised Learning Path travel. These values
/// cross admission, Stop ownership, settlement, telemetry, and presentation;
/// callers cannot silently invent a new lifecycle action with display text.
enum LearningMotionAction: Hashable, Sendable {
  case cameraCalibrationSample(index: Int, total: Int)
  case returnFromCameraCalibration
  case sparseTipApproach(ToolContactCalibrationPosition)
  case sparseTipCircleStart(ToolContactCalibrationPosition)
  case sparseTipBatchReveal
  case moveToDrawingBorderStart
  case confirmDrawingBorderStart
  case returnToLocalRevealPose

  var title: String {
    switch self {
    case .cameraCalibrationSample(let index, let total):
      "Current-Camera Calibration Sample \(index) of \(total)"
    case .returnFromCameraCalibration: "Return from Current-Camera Calibration"
    case .sparseTipApproach(let position):
      "Sparse Tip Mark \(position.sparseTipBatchLocationTitle) Approach"
    case .sparseTipCircleStart(let position):
      "Sparse Tip Circle \(position.sparseTipBatchLocationTitle) Start"
    case .sparseTipBatchReveal: "Reveal Four Corner Tip Circles"
    case .moveToDrawingBorderStart: "Move to Drawing Border Start"
    case .confirmDrawingBorderStart: "Confirm Drawing Border Start"
    case .returnToLocalRevealPose: "Return to Local Reveal Pose"
    }
  }
}

private extension ToolContactCalibrationPosition {
  var sparseTipBatchLocationTitle: String {
    switch self {
    case .center: "Center"
    case .negativeX: "Minimum-X / Minimum-Y Corner"
    case .positiveY: "Minimum-X / Maximum-Y Corner"
    case .positiveX: "Maximum-X / Maximum-Y Corner"
    case .negativeY: "Maximum-X / Minimum-Y Corner"
    }
  }
}

enum ContextualMotionOwnerID: Hashable, Sendable {
  case liveOperation(UUID)
  case simulated(PlotterCausalSimulatorOperation)
}

struct ContextualStopPresentation: Hashable, Sendable {
  let capabilityID: ContextualStopCapabilityID
  let title: String
  let detail: String
}

struct ContextualStopAuditRecord: Hashable, Sendable {
  let capabilityID: ContextualStopCapabilityID
  let actor: String
  let action: String
  let disposition: JogCancelIntent
  let outcome: String
}

private struct ContextualStopDispositionLatch: Hashable, Sendable {
  let capabilityID: ContextualStopCapabilityID
  let intent: JogCancelIntent
  let actor: String
}

private enum ContextualStopLifecycleState: Hashable {
  case available
  case latched(ContextualStopDispositionLatch, cancellationRequestInProgress: Bool)

  var latch: ContextualStopDispositionLatch? {
    switch self {
    case .available: nil
    case .latched(let latch, _): latch
    }
  }

  var cancellationRequestInProgress: Bool {
    if case .latched(_, let inProgress) = self { return inProgress }
    return false
  }
}

private enum PlotterRetainedStopHandle {
  case boundary(Task<Void, Never>)
  case batch(Task<Void, Never>)
  case motion(Task<MotionOutcome, Never>)
  case drawing(Task<DrawingStrokeOutcome, Never>)
  case drawingPlan(Task<DrawingPlanOutcome, Never>)
  case simulated(Task<PlotterCausalSimulatorOperationOutcome, Never>)

  func settle() async {
    switch self {
    case .boundary(let task): await task.value
    case .batch(let task): await task.value
    case .motion(let task): _ = await task.value
    case .drawing(let task): _ = await task.value
    case .drawingPlan(let task): _ = await task.value
    case .simulated(let task): _ = await task.value
    }
  }

  func cancelBatch() {
    guard case .batch(let task) = self else { return }
    task.cancel()
  }

  var drawingMayHaveInk: Bool {
    switch self {
    case .drawing, .drawingPlan, .simulated: true
    case .boundary, .batch, .motion: false
    }
  }
}

private struct PlotterRetainedStopSegment {
  let target: ContextualStopTarget
  let owner: PlotterRetainedStopHandle
}

private struct PlotterRetainedStopRegistration {
  let target: ContextualStopTarget
  let owner: PlotterRetainedStopHandle
  var segment: PlotterRetainedStopSegment? = nil
  var possibleInkLocation: BlacklistedToolContactLocation? = nil
  var state: ContextualStopLifecycleState = .available

  var presentationSignature: PlotterRetainedStopPresentationSignature {
    PlotterRetainedStopPresentationSignature(target: target, state: state)
  }
}

/// Only the root capability and its public cancellation lifecycle are projected.
/// Sparse-tip segment owners and the possible-ink slot remain runtime safety
/// state and must not make an unchanged Stop button rebuild Learning.
private struct PlotterRetainedStopPresentationSignature: Hashable {
  let target: ContextualStopTarget
  let state: ContextualStopLifecycleState
}

enum LearningPathOperationError: LocalizedError, Sendable {
  case freshFrameUnavailable
  case controllerRefused(String)
  case controllerCancelled(String)
  case controllerAmbiguous(String)
  case controllerFailed(String)
  case possibleInk(String)
  case controllerContextChanged(ControllerCheckpointContextComparison)
  case inkRejected(String)
  case requiredState(String)

  var errorDescription: String? {
    switch self {
    case .freshFrameUnavailable:
      "A strictly newer exact camera frame was unavailable."
    case .controllerRefused(let detail), .controllerCancelled(let detail),
      .controllerAmbiguous(let detail), .controllerFailed(let detail), .possibleInk(let detail),
      .inkRejected(let detail), .requiredState(let detail):
      detail
    case .controllerContextChanged(let comparison):
      "Controller context changed during calibration: \(comparison.actionableDescription) The sample was discarded without motion retry."
    }
  }
}

enum WorkflowFailureKind: String, Codable, Hashable, Sendable {
  case refused
  case unclear
  case ambiguous
  case cancelled
  case failed
  case possibleInk
}

struct WorkflowFailure: Error, Hashable, Sendable {
  let kind: WorkflowFailureKind
  let detail: String
  let recovery: WorkflowTelemetryRecovery

  static func failed(_ detail: String) -> Self {
    Self(kind: .failed, detail: detail, recovery: .resolveNamedFailure)
  }

  static func refused(_ detail: String) -> Self {
    Self(kind: .refused, detail: detail, recovery: .resolveNamedFailure)
  }

  static func ambiguous(_ detail: String) -> Self {
    Self(kind: .ambiguous, detail: detail, recovery: .resolveNamedFailure)
  }

  var attemptDisposition: ExerciseAttemptDisposition {
    switch kind {
    case .refused: .refused(detail)
    case .unclear: .unclear(detail)
    case .ambiguous, .possibleInk: .ambiguous(detail)
    case .cancelled: .cancelled
    case .failed: .failed(detail)
    }
  }

}

typealias CurrentCameraCalibrationPhase = PlotterCameraCalibrationPhase
private typealias CurrentCameraCalibrationFailure = PlotterCameraCalibrationFailure

private struct CalibrationMachineObservation: Sendable {
  let position: MachinePosition
  let contextBaseline: ControllerContextBaseline?
}

private struct CalibrationCapAnchorCapture: Sendable {
  let evidence: MachineCameraCorrespondenceProvenance
  let contextBaseline: ControllerContextBaseline?
  let passiveProbe: PassiveProbeResult?
  let displayedFrame: DisplayedFrame
  let capAnchor: ToolCapAnchorEstimate
}

/// Non-restorable, batch-local proof that the exact sparse-tip operation most
/// recently completed a typed Pen-Up command. It authorizes only consecutive
/// Pen-Up travel/capture segments owned by that same public batch.
private struct SparseTipPenUpAuthorization: Hashable, Sendable {
  let attemptID: ExerciseAttemptID
  let capabilityID: ContextualStopCapabilityID
  let controllerSessionID: UUID
  let coordinateRevision: UInt64
  let paperInstanceRevision: UUID
  let source: OperatorFrameMode
}

private struct PendingToolContactEvidence: Sendable {
  let attemptID: ExerciseAttemptID
  let paperInstance: PaperInstanceRevision
  let operationID: ToolContactOperationID
  let position: ToolContactCalibrationPosition
  let intendedMarkPosition: MachinePosition
  let actualSettledPosition: MachinePosition
  let controllerContextEvidence: ControllerContextEvidenceReference
  let markGeometry: ToolContactMarkGeometryEvidence
  let penDown: PenActuationEvidence
  let penUp: PenActuationEvidence
  let preMarkFrame: ExactTipCalibrationFrame
  let preMarkCapEstimate: ToolCapAnchorEstimate
  let revealEvidence: ToolContactRevealEvidence
  let capMapPredictionAtMark: Point2<CameraPixelSpace>
}

private struct DrawnToolContactEvidence: Sendable {
  let attemptID: ExerciseAttemptID
  let operationID: ToolContactOperationID
  let position: ToolContactCalibrationPosition
  let intendedMarkPosition: MachinePosition
  let actualSettledPosition: MachinePosition
  let controllerContextEvidence: ControllerContextEvidenceReference
  let markGeometry: ToolContactMarkGeometryEvidence
  let penDown: PenActuationEvidence
  let penUp: PenActuationEvidence
  let preMarkFrame: ExactTipCalibrationFrame
  let preMarkCapEstimate: ToolCapAnchorEstimate
  let capMapPredictionAtMark: Point2<CameraPixelSpace>
}

struct LiveSceneInspection: Sendable {
  let displayedFrame: DisplayedFrame
  let measurement: PlotterSceneMeasurement
}

struct StableWorkflowCapInspection: Sendable {
  let inspection: LiveSceneInspection
  let cap: PenCapMeasurement
  let centroidSpreadPixels: Double

  init(inspection: LiveSceneInspection, cap: PenCapMeasurement,
    centroidSpreadPixels: Double = 0) {
    self.inspection = inspection
    self.cap = cap
    self.centroidSpreadPixels = centroidSpreadPixels
  }
}

struct StableWorkflowCapCaptureRequest: Sendable {
  let newerThanNanoseconds: UInt64
  var searchCenter: Point2<CameraPixelSpace>? = nil
}

protocol StableWorkflowCapCapturePort: Sendable {
  func captureStableWorkflowCap(
    _ request: StableWorkflowCapCaptureRequest
  ) async throws -> StableWorkflowCapInspection
}

struct ProtocolPoseSettlement: Hashable, Sendable {
  let action: LearningMotionAction
  let target: MachinePosition
  let actual: MachinePosition
  let residualMM: Double
  let toleranceMM: Double
  let controllerSessionID: UUID
  let coordinateRevision: UInt64
  let toolPaperRevision: UUID
}

struct TipCalibrationSemanticIdentityState: Hashable, Sendable {
  let machineGeometry: MachineGeometryIdentity
  let toolAssembly: ToolAssemblyRevision
  let penContactProfile: PenContactProfileRevision
  let paperInstance: PaperInstanceRevision
  let paperContactPlane: PaperContactPlaneRevision
  let cameraMountRevision: UUID
  let cameraReframingRevision: UUID

  static func ephemeral() -> Self {
    Self(
      machineGeometry: MachineGeometryIdentity(),
      toolAssembly: ToolAssemblyRevision(),
      penContactProfile: PenContactProfileRevision(),
      paperInstance: PaperInstanceRevision(),
      paperContactPlane: PaperContactPlaneRevision(),
      cameraMountRevision: UUID(),
      cameraReframingRevision: UUID()
    )
  }
}

enum PlotterApplicationRuntimeComputationPhase: Hashable, Sendable {
  case began
  case ended
}

enum PlotterApplicationRuntimeComputationEvent: Hashable, Sendable {
  case penRequest(PenCommand, PlotterApplicationRuntimeComputationPhase)
  case boundaryMotion(BoundaryDirection, PlotterApplicationRuntimeComputationPhase)
  case supervisedTravel(LearningMotionAction, PlotterApplicationRuntimeComputationPhase)
  case visionAnalysisRevision(
    revision: UInt64,
    phase: PlotterSceneAnalysisPhase,
    latestResultFrameID: FrameID?,
    lastError: String?
  )
  case learningActionStripChanged(
    ownerID: LearningPathItemID?,
    actions: [PlotterLearningAction]
  )
  case actionSurfaceChanged(
    frameID: FrameID?,
    overlayCount: Int,
    pointSelectionPurpose: PlotterExactPointSelectionPurpose?
  )
}

/// Observation-ignored counters and a bounded event trace for deterministic
/// presentation-computation tests. These diagnostics never participate in
/// workflow authority, presentation state, motion, Vision, or persistence.
struct PlotterApplicationRuntimeComputationDiagnostics: Equatable, Sendable {
  static let maximumRetainedEventCount = 256

  fileprivate(set) var learningSessionReadCount = 0
  fileprivate(set) var learningSessionWriteCount = 0
  fileprivate(set) var learningSnapshotWithoutResetBuildCount = 0
  fileprivate(set) var learningSnapshotWithResetBuildCount = 0
  fileprivate(set) var currentLearningItemBuildCount = 0
  fileprivate(set) var learningProjectionBuildCount = 0
  fileprivate(set) var learningProjectionCacheHitCount = 0
  fileprivate(set) var selectedLearningProjectionBuildCount = 0
  fileprivate(set) var selectedLearningProjectionCacheHitCount = 0
  fileprivate(set) var learningResetPlanBuildCount = 0
  fileprivate(set) var plotterUIProjectionBuildCount = 0
  fileprivate(set) var actionSurfaceBuildCount = 0
  fileprivate(set) var actionSurfaceCacheHitCount = 0
  fileprivate(set) var drawingDraftSynchronizationCount = 0
  fileprivate(set) var stoppableOperationMutationCount = 0
  fileprivate(set) var stoppableOperationSemanticInvalidationCount = 0
  fileprivate(set) var visionAnalysisRevisionCount = 0
  fileprivate(set) var semanticPresentationRevision: UInt64 = 0
  fileprivate(set) var droppedEventCount = 0
  fileprivate(set) var events: [PlotterApplicationRuntimeComputationEvent] = []

  fileprivate mutating func record(_ event: PlotterApplicationRuntimeComputationEvent) {
    if events.count == Self.maximumRetainedEventCount {
      events.removeFirst()
      droppedEventCount += 1
    }
    events.append(event)
  }
}

/// Narrow counters used by deterministic preview-isolation regressions and the
/// opt-in running-app performance gate. This snapshot owns no runtime policy.
struct PlotterPreviewIsolationDiagnostics: Equatable, Sendable {
  let previewPublicationCount: UInt64
  let latestPreviewSource: FrameSourceIdentity?
  let latestPreviewFrameID: FrameID?
  let latestPreviewSequence: UInt64?
  let latestPreviewCaptureNanoseconds: UInt64?
  let latestPreviewCameraConfigurationID: CameraConfigurationID?
  let semanticPresentationRevision: UInt64
  let plotterUIProjectionBuildCount: Int
  let learningProjectionBuildCount: Int
  let drawingDraftSynchronizationCount: Int
  let overlayCanvasDrawCount: Int
  let overlayCanvasBuildCount: Int
  let overlayPresentationRevision: UInt64
}

struct LearningModePresentation: Hashable, Sendable {
  let isEnabled: Bool
  let actionTitle: String
  let refusalRequirement: PlotterIntentRequirement?
  let refusalOwner: EpisodeAuthorityID?
  let remedy: String?
  let recordingDiagnostic: String?
}

private final class LearningPresentationBase {
  let revision: UInt64
  let cameraIsLive: Bool
  let snapshot: PlotterLearningPresentationFacts
  let actionability: PlotterUILearningActionabilityProjection
  let currentItemID: LearningPathItemID
  let currentProjection: LearningPathProjection

  init(
    revision: UInt64,
    cameraIsLive: Bool,
    snapshot: PlotterLearningPresentationFacts,
    actionability: PlotterUILearningActionabilityProjection,
    currentItemID: LearningPathItemID,
    currentProjection: LearningPathProjection
  ) {
    self.revision = revision
    self.cameraIsLive = cameraIsLive
    self.snapshot = snapshot
    self.actionability = actionability
    self.currentItemID = currentItemID
    self.currentProjection = currentProjection
  }
}

private struct SelectedLearningProjectionCache {
  let revision: UInt64
  let cameraIsLive: Bool
  let selectedItemID: LearningPathItemID
  let projection: LearningPathProjection
}

private struct ActionSurfacePresentationCache {
  let revision: UInt64
  let presentation: ActionSurfacePresentation
}

private struct LearningVacatePlans {
  let plansByAnchor: [LearningPathItemID: LearningVacatePlan]
  let resetAllPlan: LearningVacatePlan
}

private extension PlotterLearningPresentationFacts {
  func replacingReset(_ reset: ResetFacts) -> Self {
    Self(
      source: source,
      learningEnabled: learningEnabled,
      penInteractionCompleted: penInteractionCompleted,
      penInteraction: penInteraction,
      penActuationProfile: penActuationProfile,
      selectedBoundaryDirection: selectedBoundaryDirection,
      controller: controller,
      boundary: boundary,
      cameraCalibration: cameraCalibration,
      sparseCalibration: sparseCalibration,
      drawing: drawing,
      operations: operations,
      discovery: discovery,
      startUnavailableReasons: startUnavailableReasons,
      acceptedCheckpointStatus: acceptedCheckpointStatus,
      savedTrainingCandidate: savedTrainingCandidate,
      reset: reset
    )
  }
}

private struct LearningActionStripDiagnosticSignature: Equatable {
  let ownerID: LearningPathItemID?
  let actions: [PlotterLearningAction]
}

private struct ActionSurfaceDiagnosticSignature: Equatable {
  let frameID: FrameID?
  let overlayCount: Int
  let pointSelectionPurpose: PlotterExactPointSelectionPurpose?
}

/// Root-owned effects that do not belong to one of the typed feature
/// runtimes. The protocol is deliberately behavioral: composition supplies a
/// nominal adapter, never a bag of stored closures.
protocol PlotterApplicationResidualEffectPort:
  PlotterControllerSerialDeviceDiscoveryPort, Sendable
{
  func nowNanoseconds() -> UInt64
  func recordWorkflowTelemetry(_ event: WorkflowTelemetryEvent) async
}

extension PlotterApplicationResidualEffectPort {
  func discoverSerialDevices() -> [MachineLinkDescriptor] {
    SerialPortDiscovery.discover()
  }

  func nowNanoseconds() -> UInt64 {
    UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
  }

  func recordWorkflowTelemetry(_ event: WorkflowTelemetryEvent) async {}
}

struct PlotterApplicationDefaultResidualEffectPort: PlotterApplicationResidualEffectPort {}

/// The one durable boundary for source-indexed application state. A missing
/// port means the composition has no LIVE persistence capability; SIMULATED
/// state can never reach this port.
protocol PlotterApplicationStatePersistencePort: Sendable {
  func loadAcceptedLearningPathCheckpoint() -> AcceptedLearningPathCheckpointLoadResult
  func saveAcceptedLearningPathCheckpoint(
    _ checkpoint: AcceptedLearningPathCheckpoint
  ) throws
  func clearAcceptedLearningPathCheckpoint() throws
  func persistPaperRevisionContext(_ context: PaperRevisionContext) throws
  func persistMachineGeometryIdentity(_ identity: MachineGeometryIdentity) throws
}

extension PlotterApplicationStatePersistencePort {
  func persistMachineGeometryIdentity(_ identity: MachineGeometryIdentity) throws {
    throw AxisMetricLearningTransitionError.persistenceUnavailable
  }
}

private struct PlotterApplicationEffectLease: Hashable, Sendable {
  let id: UUID
}

private struct PlotterApplicationLearningTask {
  let transitionID: PlotterLearningTransitionID
  let task: Task<String?, Never>
}

@MainActor
@Observable
final class PlotterApplicationRuntime:
  PlotterUIIntentSink,
  PlotterControllerSessionIntentSink,
  PlotterLearningActivityFactProviding,
  PlotterPenInteractionProjectionSink,
  PlotterPointSelectionContinuationPort,
  PlotterBorderValidationEffectPort,
  PlotterArtifactResetEffectPort,
  PlotterArtifactResetPersistencePort
{
  private enum AdmissionState: Equatable, Sendable {
    case open
    case closing
    case closed
  }

  private enum StartupState: Equatable, Sendable {
    case notStarted
    case starting
    case started
    case cancelled
  }

  private enum ExerciseAttemptMode: Equatable, Sendable {
    case normal
    case replacement
    case additional
  }

  private struct SavedTrainingOpticalComparisonIdentity: Hashable, Sendable {
    let checkpointID: UUID
    let cameraConfigurationID: CameraConfigurationID

    var artifactRuntimeValue: String {
      "\(checkpointID.uuidString):\(cameraConfigurationID.rawValue.uuidString)"
    }
  }

  private enum ExerciseAttemptLifecycle {
    case idle
    case active(id: ExerciseAttemptID, ownerID: LearningPathItemID, mode: ExerciseAttemptMode)

    var id: ExerciseAttemptID? {
      guard case .active(let id, _, _) = self else { return nil }
      return id
    }

    var ownerID: LearningPathItemID? {
      guard case .active(_, let ownerID, _) = self else { return nil }
      return ownerID
    }

    var mode: ExerciseAttemptMode? {
      guard case .active(_, _, let mode) = self else { return nil }
      return mode
    }

    mutating func begin(ownerID: LearningPathItemID, mode: ExerciseAttemptMode) -> Bool {
      guard case .idle = self else { return false }
      self = .active(id: ExerciseAttemptID(), ownerID: ownerID, mode: mode)
      return true
    }

    mutating func finish() {
      self = .idle
    }
  }

  private enum DrawingStrokeExecutionState: Hashable, Sendable {
    case notAdmitted
    case completedNaturally
    case possibleInk
  }

  private final class BorderDrawingEffectProgress {
    var strokeState: DrawingStrokeExecutionState = .notAdmitted
    var outcome: DrawingPlanOutcome?
  }

  /// One complete learning authority value. LIVE and SIMULATED use the same
  /// contract while retaining independent storage and independent lifetimes.
  private struct PlotterApplicationEnvironmentState {
    var selectedDiscoverySequenceID: DiscoverySequenceID = .penInteraction
    var discoveryTransactions: [DiscoverySequenceID: DiscoveryTransaction] = [:]
    var discoveryError: String?
    var lastContextualStopAuditRecord: ContextualStopAuditRecord?
    var lastProtocolPoseSettlement: ProtocolPoseSettlement?
    var explorationError: String?
    var learningArtifactGraph = LearningDependencyGraph()
    var exerciseAttempt: ExerciseAttemptLifecycle = .idle
    var restartableExerciseItemID: LearningPathItemID?
    var acceptedArtifactCheckpointStatus: AcceptedArtifactCheckpointStatus = .unavailable
    var drawingReadinessAssessment: DrawingReadinessAssessment?
    var activeMachineArtifactCheckpoint: AcceptedMachineArtifactCheckpoint?
    var activeMachineCameraCheckpoint: AcceptedMachineCameraCheckpoint?
    var activeStageFourCheckpoint: AcceptedStageFourCheckpoint?
    var controllerPoseApplicability: ControllerPoseApplicability = .currentSession
    var learningAuthorityError: String?
    var acceptedAttemptSequence: UInt64 = 0
    var controllerSessionID = UUID()
    var explorationCoordinateRevision: UInt64 = 0
    var explorationPaperInstanceRevision: UUID
    var explorationPaperContactPlaneRevision: UUID

    init(
      source: OperatorFrameMode,
      paperInstanceRevision: UUID,
      paperContactPlaneRevision: UUID
    ) {
      explorationPaperInstanceRevision = paperInstanceRevision
      explorationPaperContactPlaneRevision = paperContactPlaneRevision
    }

  }

  /// Canonical mutable application state. Feature runtimes retain their own
  /// typed operational state; this value owns only source-indexed residual
  /// application facts.
  private struct PlotterApplicationState {
    var environmentStates: [OperatorFrameMode: PlotterApplicationEnvironmentState]

    init(
      live: PlotterApplicationEnvironmentState,
      simulated: PlotterApplicationEnvironmentState
    ) {
      environmentStates = [.live: live, .simulated: simulated]
    }
  }

  private enum MotionPriors {
    static let stepMM = "50"
    static let feedMMPerMinute = "500"
    /// Finite GRBL wire segment used only for renewal under one logical owner.
    /// Reaching this distance is never a Boundary Discovery result.
    static let boundaryWireSegmentMM = 50.0
    static let boundaryFeedMMPerMinute =
      PlotterMotionThroughput.applicationXYFeedMMPerMinute
  }

  private(set) var livePenCapAppearanceSelection: PenCapAppearanceSelection? {
    didSet { invalidateActionSurfacePresentation() }
  }
  private(set) var simulatedPenCapAppearanceSelection: PenCapAppearanceSelection? {
    didSet { invalidateActionSurfacePresentation() }
  }
  private(set) var persistedPenCapAppearanceLoadState: PersistedPenCapAppearanceLoadState
  var penCapAppearanceSelection: PenCapAppearanceSelection? {
    frameMode == .live ? livePenCapAppearanceSelection : simulatedPenCapAppearanceSelection
  }
  private var livePenCapColor: PenCapColor? { livePenCapAppearanceSelection?.color }
  private(set) var overlayPreferenceState: OverlayPreferenceState {
    didSet { invalidateActionSurfacePresentation() }
  }
  private(set) var visionAnalysisCadence = VisionAnalysisCadence.twoFPS
  private(set) var videoAnalysisRegionLock: VideoAnalysisRegionLock? {
    didSet { invalidateActionSurfacePresentation() }
  }
  var frameMode: OperatorFrameMode = .live {
    didSet {
      guard oldValue != frameMode else { return }
      markSemanticPresentationChanged()
    }
  }
  var learningIsEnabled: Bool { pointSelectionEpisodeProjection.learningIsEnabled }
  var drawingTargetIsVisible: Bool { drawingDraftSnapshot.isTargetVisible }

  private(set) var serialDevices: [MachineLinkDescriptor] = []
  private(set) var selectedSerialDevice: MachineLinkDescriptor? {
    didSet {
      guard oldValue != selectedSerialDevice else { return }
      markSemanticPresentationChanged()
    }
  }
  private(set) var passiveProbeResult: PassiveProbeResult? {
    didSet {
      guard oldValue != passiveProbeResult else { return }
      markSemanticPresentationChanged()
    }
  }
  private(set) var machineSnapshot: RunInterpreterSnapshot? {
    didSet {
      guard oldValue != machineSnapshot else { return }
      // The controller uses connection state to describe connected operations
      // too. Those known operations preserve physical coordinate continuity.
      let previouslyConnected = switch oldValue?.machine.connection {
      case .connected, .probing, .moving, .actuatingPen: true
      case .disconnected, .connecting, .blocked, nil: false
      }
      let currentlyConnected = switch machineSnapshot?.machine.connection {
      case .connected, .probing, .moving, .actuatingPen: true
      case .disconnected, .connecting, .blocked, nil: false
      }
      if previouslyConnected, !currentlyConnected {
        requireVisualPositionRevalidation()
      }
      markSemanticPresentationChanged(invalidatesActionSurface: false)
    }
  }
  private(set) var machineError: String? {
    didSet {
      guard oldValue != machineError else { return }
      markSemanticPresentationChanged(invalidatesActionSurface: false)
    }
  }
  private(set) var controllerAlarmClearInProgress = false {
    didSet {
      guard oldValue != controllerAlarmClearInProgress else { return }
      markSemanticPresentationChanged()
    }
  }
  private(set) var controllerConnectionActionInProgress = false {
    didSet {
      guard oldValue != controllerConnectionActionInProgress else { return }
      markSemanticPresentationChanged()
    }
  }
  private(set) var passiveProbeInProgress = false {
    didSet {
      guard oldValue != passiveProbeInProgress else { return }
      markSemanticPresentationChanged()
    }
  }
  private(set) var jogRequestInProgress = false {
    didSet {
      guard oldValue != jogRequestInProgress else { return }
      markSemanticPresentationChanged()
    }
  }
  /// App-retained Pen normalization outside PlotterPenInteractionRuntime. Typed
  /// Pen Interaction submissions never write this foreign-owner fact.
  private(set) var retainedPenRequestInProgress = false {
    didSet {
      guard oldValue != retainedPenRequestInProgress else { return }
      markSemanticPresentationChanged(invalidatesActionSurface: false)
    }
  }
  var learningResetInProgress: Bool {
    guard case .reset = artifactResetRuntime.snapshot().activeIntent else { return false }
    return true
  }
  private(set) var semanticPresentationRevision: UInt64 = 0
  @ObservationIgnored private var learningPresentationBaseCache: LearningPresentationBase?
  @ObservationIgnored private var selectedLearningProjectionCache:
    SelectedLearningProjectionCache?
  @ObservationIgnored private var actionSurfacePresentationRevision: UInt64 = 0
  @ObservationIgnored private var actionSurfacePresentationCache:
    ActionSurfacePresentationCache?
  @ObservationIgnored private var computationDiagnostics =
    PlotterApplicationRuntimeComputationDiagnostics()
  @ObservationIgnored private var lastLearningActionStripDiagnosticSignature:
    LearningActionStripDiagnosticSignature?
  @ObservationIgnored private var lastActionSurfaceDiagnosticSignature:
    ActionSurfaceDiagnosticSignature?
  @ObservationIgnored private var currentPlotterUIProjection: PlotterUIProjection?
  @ObservationIgnored private var rootProjectionCache:
    (inputs: PlotterAppUIProjectionInputs, projection: PlotterAppUIProjection)?
  @ObservationIgnored private var currentPlotterUIBindingSemanticRevision: UInt64?
  @ObservationIgnored private var currentVideoPreviewProjection: PlotterUIProjection?
  @ObservationIgnored private var currentVideoPreviewBindingSemanticRevision: UInt64?
  @ObservationIgnored private var admissionState: AdmissionState = .open
  @ObservationIgnored private var startupState: StartupState = .notStarted
  @ObservationIgnored private(set) var learningEpisodeRecord = PlotterLearningEpisodeRecord()
  @ObservationIgnored private var activeLearningActionTask: PlotterApplicationLearningTask?
  @ObservationIgnored private var semanticPresentationUpdateDepth = 0
  @ObservationIgnored private var semanticPresentationChangeIsPending = false
  @ObservationIgnored private var actionSurfaceInvalidationIsPending = false
  @ObservationIgnored private var pendingSavedTrainingOpticalComparisonIdentities:
    Set<SavedTrainingOpticalComparisonIdentity> = []
  @ObservationIgnored private var lastCompletedSavedTrainingOpticalComparisonIdentity:
    SavedTrainingOpticalComparisonIdentity?
  private(set) var frameModeSwitchInProgress = false {
    didSet {
      guard oldValue != frameModeSwitchInProgress else { return }
      markSemanticPresentationChanged()
    }
  }
  private(set) var motionAuthorizationActionInProgress = false {
    didSet {
      guard oldValue != motionAuthorizationActionInProgress else { return }
      markSemanticPresentationChanged()
    }
  }
  private(set) var lastMotionGuardActivationText = "not activated"
  private(set) var lastContextualStopAuditRecord: ContextualStopAuditRecord? {
    get { currentEnvironmentState.lastContextualStopAuditRecord }
    set { currentEnvironmentState.lastContextualStopAuditRecord = newValue }
  }

  @ObservationIgnored private(set) var cameraSnapshot: CameraCaptureSnapshot? {
    didSet {
      guard cameraSnapshotChangesLearningPresentation(oldValue, cameraSnapshot) else { return }
      markSemanticPresentationChanged()
    }
  }
  @ObservationIgnored let actionSurfacePreview = ActionSurfacePreviewModel()
  @ObservationIgnored private(set) var displayedFrame: DisplayedFrame? {
    didSet {
      publishActionSurfacePreview(displayedFrame)
      let isAvailable = displayedFrame != nil
      if displayedFrameAvailable != isAvailable {
        displayedFrameAvailable = isAvailable
      }
    }
  }
  private(set) var displayedFrameAvailable = false {
    didSet {
      guard oldValue != displayedFrameAvailable else { return }
      markSemanticPresentationChanged()
    }
  }
  @ObservationIgnored private(set) var latestLiveCameraFrame: DisplayedFrame? {
    didSet {
      let identityChanged = (oldValue == nil) != (latestLiveCameraFrame == nil)
        || oldValue?.source != latestLiveCameraFrame?.source
        || oldValue?.frame.cameraConfigurationID
          != latestLiveCameraFrame?.frame.cameraConfigurationID
      guard identityChanged else { return }
      markSemanticPresentationChanged()
    }
  }
  @ObservationIgnored private(set) var overlayResultChannels = OverlayResultChannels() {
    didSet { invalidateActionSurfacePresentation() }
  }
  private(set) var cameraError: String? {
    didSet {
      guard oldValue != cameraError else { return }
      markSemanticPresentationChanged()
    }
  }
  private(set) var visionError: String? {
    didSet {
      guard oldValue != visionError else { return }
      markSemanticPresentationChanged()
    }
  }
  private(set) var exactWorkflowVisionOwner: ExactWorkflowVisionOwner? {
    didSet {
      guard oldValue != exactWorkflowVisionOwner else { return }
      markSemanticPresentationChanged()
    }
  }
  @ObservationIgnored private(set) var visionAnalysisSnapshot: PlotterSceneAnalysisSnapshot = .stopped {
    didSet {
      invalidateActionSurfacePresentation()
      guard oldValue.phase != visionAnalysisSnapshot.phase else { return }
      markSemanticPresentationChanged()
    }
  }
  @ObservationIgnored private(set) var videoVisionDiagnostics: CameraSourceSessionVisionDiagnostics? {
    didSet { actionSurfacePreview.invalidatePresentation() }
  }
  @ObservationIgnored private(set) var lastSceneMeasurement: PlotterSceneMeasurement?
  private(set) var simulatorPenState: PenState = .unknown
  private(set) var simulatorLearningSummary = "Switch to SIMULATED to inspect model behavior."
  private(set) var simulatedLearningSnapshot: SimulatedLearningSnapshot? {
    didSet {
      guard simulatedSnapshotChangesLearningPresentation(oldValue, simulatedLearningSnapshot)
      else { return }
      markSemanticPresentationChanged(invalidatesActionSurface: false)
    }
  }
  private(set) var simulatedAnnotations: [SimulatedLearningAnnotation] = [] {
    didSet { invalidateActionSurfacePresentation() }
  }
  private(set) var simulatedViewportID: SimulatedCameraViewportID? {
    didSet { invalidateActionSurfacePresentation() }
  }
  var simulatedAnnotationsAreVisible = true {
    didSet { invalidateActionSurfacePresentation() }
  }
  /// Canonical residual application state is source-indexed in one root value.
  /// Typed feature projections remain owned by their respective runtimes and
  /// are read when compiling the immutable application projection.
  @ObservationIgnored private var applicationState: PlotterApplicationState
  @ObservationIgnored
  private lazy var liveTipCalibrationRuntime = PlotterTipCalibrationRuntime(effectPort: self)
  @ObservationIgnored
  private lazy var simulatedTipCalibrationRuntime = PlotterTipCalibrationRuntime(effectPort: self)
  @ObservationIgnored
  private(set) var tipCalibrationRuntime: PlotterTipCalibrationRuntime {
    get {
      frameMode == .live ? liveTipCalibrationRuntime : simulatedTipCalibrationRuntime
    }
    set {
      if frameMode == .live {
        liveTipCalibrationRuntime = newValue
      } else {
        simulatedTipCalibrationRuntime = newValue
      }
    }
  }
  @ObservationIgnored
  private lazy var liveBorderValidationRuntime = PlotterBorderValidationRuntime(
    sourceIsSimulated: false,
    effectPort: self
  ) { [weak self] snapshot in
    self?.installBorderValidationRuntimeProjection(snapshot, source: .live)
  }
  @ObservationIgnored
  private lazy var simulatedBorderValidationRuntime = PlotterBorderValidationRuntime(
    sourceIsSimulated: true,
    effectPort: self
  ) { [weak self] snapshot in
    self?.installBorderValidationRuntimeProjection(snapshot, source: .simulated)
  }
  @ObservationIgnored
  var borderValidationRuntime: PlotterBorderValidationRuntime {
    frameMode == .live ? liveBorderValidationRuntime : simulatedBorderValidationRuntime
  }
  var borderValidationSnapshot: PlotterBorderValidationSnapshot {
    borderValidationRuntime.snapshot()
  }
  @ObservationIgnored
  private var currentEnvironmentState: PlotterApplicationEnvironmentState {
    _read {
      computationDiagnostics.learningSessionReadCount += 1
      guard let state = applicationState.environmentStates[frameMode] else {
        preconditionFailure("Missing canonical application state for \(frameMode).")
      }
      yield state
    }
    _modify {
      computationDiagnostics.learningSessionWriteCount += 1
      defer { markSemanticPresentationChanged() }
      guard var state = applicationState.environmentStates[frameMode] else {
        preconditionFailure("Missing canonical application state for \(frameMode).")
      }
      defer { applicationState.environmentStates[frameMode] = state }
      yield &state
    }
  }

  @discardableResult
  private func mutateActiveLearningSession<Result>(
    invalidatesActionSurface: Bool = true,
    _ transition: (inout PlotterApplicationEnvironmentState) throws -> Result
  ) rethrows -> Result {
    computationDiagnostics.learningSessionWriteCount += 1
    defer {
      markSemanticPresentationChanged(
        invalidatesActionSurface: invalidatesActionSurface
      )
    }
    guard var state = applicationState.environmentStates[frameMode] else {
      preconditionFailure("Missing canonical application state for \(frameMode).")
    }
    let result = try transition(&state)
    applicationState.environmentStates[frameMode] = state
    return result
  }

  var computationDiagnosticsForTesting: PlotterApplicationRuntimeComputationDiagnostics {
    computationDiagnostics
  }

  func resetComputationDiagnosticsForTesting() {
    computationDiagnostics = PlotterApplicationRuntimeComputationDiagnostics()
    computationDiagnostics.semanticPresentationRevision = semanticPresentationRevision
    lastLearningActionStripDiagnosticSignature = nil
    lastActionSurfaceDiagnosticSignature = nil
    learningPresentationBaseCache = nil
    selectedLearningProjectionCache = nil
    actionSurfacePresentationCache = nil
  }

  var previewIsolationDiagnostics: PlotterPreviewIsolationDiagnostics {
    let preview = actionSurfacePreview.displayedFrame
    return PlotterPreviewIsolationDiagnostics(
      previewPublicationCount: actionSurfacePreview.publicationCount,
      latestPreviewSource: preview?.source,
      latestPreviewFrameID: preview?.frame.id,
      latestPreviewSequence: preview?.frame.sequence,
      latestPreviewCaptureNanoseconds: preview?.frame.captureNanoseconds,
      latestPreviewCameraConfigurationID: preview?.frame.cameraConfigurationID,
      semanticPresentationRevision: semanticPresentationRevision,
      plotterUIProjectionBuildCount: computationDiagnostics.plotterUIProjectionBuildCount,
      learningProjectionBuildCount: computationDiagnostics.learningProjectionBuildCount,
      drawingDraftSynchronizationCount: computationDiagnostics.drawingDraftSynchronizationCount,
      overlayCanvasDrawCount: actionSurfacePreview.overlayCanvasDrawCount,
      overlayCanvasBuildCount: actionSurfacePreview.overlayCanvasBuildCount,
      overlayPresentationRevision: actionSurfacePreview.presentationRevision
    )
  }

  func resetPreviewIsolationDiagnostics() {
    resetComputationDiagnosticsForTesting()
    actionSurfacePreview.resetPublicationCount()
  }

  func markSemanticPresentationChangedForTesting() {
    markSemanticPresentationChanged()
  }

  private func withBatchedSemanticPresentationUpdate<Result>(
    _ update: () throws -> Result
  ) rethrows -> Result {
    semanticPresentationUpdateDepth += 1
    defer {
      semanticPresentationUpdateDepth -= 1
      if semanticPresentationUpdateDepth == 0,
        semanticPresentationChangeIsPending
      {
        let invalidatesActionSurface = actionSurfaceInvalidationIsPending
        semanticPresentationChangeIsPending = false
        actionSurfaceInvalidationIsPending = false
        commitSemanticPresentationChange(
          invalidatesActionSurface: invalidatesActionSurface
        )
      }
    }
    return try update()
  }

  private func markSemanticPresentationChanged(
    invalidatesActionSurface: Bool = true
  ) {
    guard semanticPresentationUpdateDepth == 0 else {
      semanticPresentationChangeIsPending = true
      actionSurfaceInvalidationIsPending =
        actionSurfaceInvalidationIsPending || invalidatesActionSurface
      return
    }
    commitSemanticPresentationChange(
      invalidatesActionSurface: invalidatesActionSurface
    )
  }

  private func commitSemanticPresentationChange(
    invalidatesActionSurface: Bool
  ) {
    semanticPresentationRevision &+= 1
    computationDiagnostics.semanticPresentationRevision = semanticPresentationRevision
    learningPresentationBaseCache = nil
    selectedLearningProjectionCache = nil
    currentVideoPreviewProjection = nil
    currentVideoPreviewBindingSemanticRevision = nil
    if invalidatesActionSurface {
      invalidateActionSurfacePresentation()
    }
    scheduleDrawingDraftSynchronization()
  }

  private func invalidateActionSurfacePresentation() {
    actionSurfacePresentationRevision &+= 1
    actionSurfacePresentationCache = nil
    actionSurfacePreview.invalidatePresentation()
  }

  private func publishActionSurfacePreview(_ frame: DisplayedFrame?) {
    guard actionSurfacePreview.publish(frame) else { return }
    currentVideoPreviewProjection = nil
    currentVideoPreviewBindingSemanticRevision = nil
  }

  private func cameraSnapshotChangesLearningPresentation(
    _ oldValue: CameraCaptureSnapshot?,
    _ newValue: CameraCaptureSnapshot?
  ) -> Bool {
    oldValue?.selectedDeviceID != newValue?.selectedDeviceID
      || oldValue?.devices != newValue?.devices
      || oldValue?.state != newValue?.state
      || oldValue?.error != newValue?.error
      || oldValue?.diagnostics.deliveryLimitOutcome != newValue?.diagnostics.deliveryLimitOutcome
      || oldValue?.diagnostics.previewPublicationPaused
        != newValue?.diagnostics.previewPublicationPaused
  }

  private func simulatedSnapshotChangesLearningPresentation(
    _ oldValue: SimulatedLearningSnapshot?,
    _ newValue: SimulatedLearningSnapshot?
  ) -> Bool {
    oldValue?.session != newValue?.session
      || oldValue?.motionAuthorization != newValue?.motionAuthorization
      || oldValue?.penPose != newValue?.penPose
      || oldValue?.mpos != newValue?.mpos
      || oldValue?.currentOperation != newValue?.currentOperation
      || oldValue?.stickyAmbiguity != newValue?.stickyAmbiguity
  }
  var selectedDiscoverySequenceID: DiscoverySequenceID {
    get { currentEnvironmentState.selectedDiscoverySequenceID }
    set { currentEnvironmentState.selectedDiscoverySequenceID = newValue }
  }
  private(set) var discoveryTransactions: [DiscoverySequenceID: DiscoveryTransaction] {
    get { currentEnvironmentState.discoveryTransactions }
    set { currentEnvironmentState.discoveryTransactions = newValue }
  }
  private(set) var discoveryError: String? {
    get { currentEnvironmentState.discoveryError }
    set { currentEnvironmentState.discoveryError = newValue }
  }
  private var acceptedBoundaryAggregates: [BoundaryDirection: BoundarySideAggregate] {
    currentBoundarySnapshot?.acceptedAggregates ?? [:]
  }
  private(set) var cameraCalibrationAnchorFrame: DisplayedFrame? {
    get { cameraCalibrationRuntime.anchorFrame }
    set { }
  }
  private(set) var cameraCalibrationReferencePosition: MachinePosition? {
    get { cameraCalibrationRuntime.referencePosition }
    set { }
  }
  private(set) var cameraCalibrationReferenceCapAnchor: ToolCapAnchorEstimate? {
    get { cameraCalibrationRuntime.referenceCapAnchor }
    set { }
  }
  var proposedMachineCameraRegistration: MachineCameraRegistration? {
    get { cameraCalibrationRuntime.proposedRegistration }
  }
  private(set) var machineCameraRegistration: MachineCameraRegistration? {
    get { cameraCalibrationRuntime.acceptedRegistration }
    set { cameraCalibrationRuntime.restoreAcceptedRegistration(newValue) }
  }
  private(set) var tipCameraRegistration: TipCameraRegistration? {
    get { tipCalibrationRuntime.acceptedRegistration }
    set { tipCalibrationRuntime.restoreAcceptedRegistration(newValue) }
  }
  private(set) var proposedTipCameraRegistration: TipCameraRegistration? {
    get { tipCalibrationRuntime.proposedRegistration }
    set { if newValue == nil { tipCalibrationRuntime.discardProposal() } }
  }
  private(set) var frozenPointSelectionFrame: DisplayedFrame? {
    didSet { invalidateActionSurfacePresentation() }
  }
  private var pendingToolContactClickFrame: ExactTipCalibrationFrame?
  private var pendingToolContactEvidence: [PendingToolContactEvidence] = []
  var pointSelectionRequest: PlotterPointSelectionRequest? {
    guard pointSelectionEpisodeProjection.exactPointSelection.phase == .collecting else {
      return nil
    }
    return pointSelectionEpisodeProjection.exactPointSelection.request
  }
  var selectedToolContactPoints: [Point2<CameraPixelSpace>] {
    guard pointSelectionRequest?.purpose == .toolContact else { return [] }
    return pointSelectionEpisodeProjection.exactPointSelection.selectedPoints
  }
  private var machineGeometryIdentity: MachineGeometryIdentity
  private let toolAssemblyRevision: ToolAssemblyRevision
  private let penContactProfileRevision: PenContactProfileRevision
  private let cameraMountRevision: UUID
  private let cameraReframingRevision: UUID
  private(set) var blacklistedToolContactLocations: Set<BlacklistedToolContactLocation> {
    get { tipCalibrationRuntime.blacklistedLocations }
    set { tipCalibrationRuntime.replaceBlacklistedLocations(newValue) }
  }
  var explicitRegistrationCapAnchorEvidence: [MachineCameraCorrespondenceProvenance] {
    get { cameraCalibrationRuntime.correspondenceEvidence }
  }
  var cameraCalibrationRuntimePhase: CurrentCameraCalibrationPhase? {
    get { cameraCalibrationRuntime.phase }
  }
  private var currentCameraCalibrationFailure: CurrentCameraCalibrationFailure? {
    get { cameraCalibrationRuntime.failure }
  }
  private(set) var lastProtocolPoseSettlement: ProtocolPoseSettlement? {
    get { currentEnvironmentState.lastProtocolPoseSettlement }
    set { currentEnvironmentState.lastProtocolPoseSettlement = newValue }
  }
  private(set) var explorationError: String? {
    get { currentEnvironmentState.explorationError }
    set { currentEnvironmentState.explorationError = newValue }
  }
  private(set) var lastAnnouncementResultText = "No announcement has run."
  private(set) var learningArtifactGraph: LearningDependencyGraph {
    get { currentEnvironmentState.learningArtifactGraph }
    set { currentEnvironmentState.learningArtifactGraph = newValue }
  }
  private var currentPenInteractionSnapshot: PlotterPenInteractionRuntimeSnapshot? {
    frameMode == .live ? livePenInteractionSnapshot : simulatedPenInteractionSnapshot
  }
  private var currentPenActuationProfile: PenActuationProfile {
    currentPenInteractionSnapshot?.profile ?? .initialDefaults
  }
  private var effectivePenActuationProfile: PenActuationProfile {
    currentPenActuationProfile
  }

  private var penInteractionEnvironment: PlotterEnvironment {
    frameMode == .simulated ? .simulated : .live
  }

  private func penInteractionAdmissionFacts(
    environment: PlotterEnvironment
  ) -> PlotterPenInteractionAdmissionFacts {
    PlotterPenInteractionAdmissionFacts(
      environment: environment,
      learningEnabled: learningIsEnabled,
      controllerSessionEstablished: sessionEstablished,
      motionAuthorized: sessionMotionAuthorized,
      lowerOperationInFlight: retainedPenRequestInProgress
        || machineSnapshot?.machine.operationInFlight == true,
      stickyAmbiguity: learningStickyAmbiguityReason,
      capSelectionAvailable: applicationAdmissionIsOpen
        && (displayedFrameAvailable || observationRuntime != nil || frameMode == .simulated)
    )
  }

  private func installPenInteractionSnapshot(
    _ snapshot: PlotterPenInteractionRuntimeSnapshot
  ) {
    if snapshot.projection.reference.environment == .simulated {
      simulatedPenInteractionSnapshot = snapshot
    } else {
      livePenInteractionSnapshot = snapshot
    }
    if let settlement = snapshot.lastSettlement {
      if let machine = settlement.machineSnapshot { machineSnapshot = machine }
      if let truth = settlement.simulatedTruth {
        simulatedLearningSnapshot = truth.runtime
        simulatorPenState = simulatorPenState(from: truth.penPose)
        simulatorLearningSummary =
          "Pen Interaction settled in the causal simulator. \(truth.evidenceNotice.label)"
      }
    }
    markSemanticPresentationChanged()
  }

  func publishPenInteractionSnapshot(
    _ snapshot: PlotterPenInteractionRuntimeSnapshot
  ) {
    installPenInteractionSnapshot(snapshot)
  }

  @discardableResult
  private func submitPenInteraction(
    _ intent: PlotterPenInteractionIntent,
    environment explicitEnvironment: PlotterEnvironment? = nil
  ) async -> PlotterPenInteractionDisposition {
    let environment = explicitEnvironment ?? penInteractionEnvironment
    // Runtime publication, not an App observer task, keeps admitted, active,
    // cancelling, and terminal Pen truth synchronized with semantic UI facts.
    await penInteractionRuntime.installProjectionSink(self)
    let current = await penInteractionRuntime.snapshot(environment: environment)
    // A fresh-environment reset reads the exact bound revision without first
    // publishing that environment's stale prior-session projection.
    if explicitEnvironment == nil { installPenInteractionSnapshot(current) }
    let facts = penInteractionAdmissionFacts(environment: environment)
    let disposition = await penInteractionRuntime.submit(PlotterPenInteractionSubmission(
      projection: current.projection.reference,
      facts: facts,
      intent: intent
    ))
    installPenInteractionSnapshot(await penInteractionRuntime.snapshot(environment: environment))
    if case .refused(let refusal) = disposition {
      discoveryError = penInteractionRefusalText(refusal)
    }
    return disposition
  }

  private func penInteractionRefusalText(
    _ refusal: PlotterPenInteractionRefusal
  ) -> String {
    "Pen Interaction refused by \(refusal.owner): \(refusal.reason). Remedy: \(refusal.remedy)."
  }
  var activeExerciseAttemptID: ExerciseAttemptID? {
    currentEnvironmentState.exerciseAttempt.id
  }
  var activeExerciseAttemptOwnerID: LearningPathItemID? {
    currentEnvironmentState.exerciseAttempt.ownerID
  }
  private(set) var restartableExerciseItemID: LearningPathItemID? {
    get { currentEnvironmentState.restartableExerciseItemID }
    set { currentEnvironmentState.restartableExerciseItemID = newValue }
  }
  private(set) var acceptedArtifactCheckpointStatus: AcceptedArtifactCheckpointStatus {
    get { currentEnvironmentState.acceptedArtifactCheckpointStatus }
    set { currentEnvironmentState.acceptedArtifactCheckpointStatus = newValue }
  }
  private(set) var recoverableTipCalibrationCheckpoint: AcceptedTipCalibrationCheckpoint? {
    get { tipCalibrationRuntime.recoverableCheckpoint }
    set { tipCalibrationRuntime.installRecoverableCheckpoint(newValue) }
  }
  private var savedLearningState: PlotterArtifactResetSavedLearningState {
    frameMode == .live ? artifactResetRuntime.snapshot().savedLearning : .absent
  }
  private var savedLearningApplicationCandidate: (
    checkpoint: AcceptedLearningPathCheckpoint, opticalComparison: String
  )? {
    if let candidate = savedLearningState.candidate { return candidate }
    guard tipCameraRegistration == nil,
      let candidate = savedLearningState.applicationCandidate,
      candidate.checkpoint.tipCalibration != nil,
      savedLearningRecoveryUnavailableReason(candidate.checkpoint) == nil else { return nil }
    return (candidate.checkpoint,
      "Accepted calibration is absent from this session. Use Saved Learning to restore the compatible accepted package; no motion or retraining is required.")
  }

  private func savedLearningRecoveryUnavailableReason(
    _ checkpoint: AcceptedLearningPathCheckpoint
  ) -> String? {
    let saved = checkpoint.semanticIdentity
    let current = currentLearningPathSemanticIdentity
    guard saved.machineGeometry == current.machineGeometry,
      saved.toolAssembly == current.toolAssembly,
      saved.penContactProfile == current.penContactProfile,
      saved.paperContactPlane == current.paperContactPlane,
      saved.cameraMountRevision == current.cameraMountRevision,
      saved.cameraReframingRevision == current.cameraReframingRevision else {
      return "Saved calibration does not match the current machine, tool, contact plane, or camera mounting. Restore the changed dependency before using this package."
    }
    guard let frame = displayedFrame,
      let optical = try? exactTipCalibrationFrame(frame).opticalConfiguration,
      checkpoint.tipCalibration?.registration.applicability.opticalConfiguration == optical else {
      return "Show the compatible Plotter Video camera before restoring saved calibration."
    }
    guard checkpoint.machineArtifacts?.coordinateRevision == explorationCoordinateRevision,
      checkpoint.machineCamera?.registration == machineCameraRegistration else {
      return "Restore the matching machine boundary and camera Learning before restoring saved tip calibration."
    }
    guard let restored = try? checkpoint.restoredLearningGraph() else {
      return "Saved Learning validation failed. Inspect the accepted package in diagnostics."
    }
    for revision in learningArtifactGraph.revisions where revision.state == .current {
      switch revision.kind {
      case .penInteraction, .boundarySideAggregate, .estimatedMachineCenter,
        .centerArrival, .machineCameraRegistration:
        guard restored.currentRevision(for: revision.kind)?.id == revision.id else {
          return "Current accepted Learning changed after this package was saved. Restore the matching dependency before using saved tip calibration."
        }
      default: break
      }
    }
    return nil
  }

  var artifactResetEpisodeSnapshot: PlotterArtifactResetSnapshot {
    artifactResetRuntime.snapshot()
  }
  private var acceptedLearningPathCheckpoint: AcceptedLearningPathCheckpoint? {
    savedLearningState.appliedCheckpoint
  }
  private var activeMachineCameraCheckpoint: AcceptedMachineCameraCheckpoint? {
    get { currentEnvironmentState.activeMachineCameraCheckpoint }
    set { currentEnvironmentState.activeMachineCameraCheckpoint = newValue }
  }
  private var activeStageFourCheckpoint: AcceptedStageFourCheckpoint? {
    get { currentEnvironmentState.activeStageFourCheckpoint }
    set { currentEnvironmentState.activeStageFourCheckpoint = newValue }
  }
  private(set) var controllerPoseApplicability: ControllerPoseApplicability {
    get { currentEnvironmentState.controllerPoseApplicability }
    set { currentEnvironmentState.controllerPoseApplicability = newValue }
  }
  private(set) var learningAuthorityError: String? {
    get { currentEnvironmentState.learningAuthorityError }
    set { currentEnvironmentState.learningAuthorityError = newValue }
  }

  @ObservationIgnored private let machineSession: (any PlotterMachineSession)?
  @ObservationIgnored private let controllerSessionRuntime: PlotterControllerSessionRuntime
  @ObservationIgnored private let observationRuntime: PlotterObservationConfigurationRuntime?
  let drawingMaterials: DrawingMaterialLibrary
  var materialPaperStock = ""
  var materialUsesBorderImages = true
  var materialInspection: DrawingMaterialInspection?
  var materialMeasurementStatus: String?
  private var materialFeasibilityReceipt: (plan: Digest, profile: String, summary: String)?
  var materialFeasibilityStatus: String? {
    guard let receipt = materialFeasibilityReceipt else { return nil }
    guard receipt.plan == drawingDraftSnapshot.plan?.contentHash, receipt.profile == drawingMaterials.activeKey else {
      return "Drawing scale, geometry or material changed. Assess the current drawing again."
    }
    return receipt.summary
  }
  let portraitStudio: PortraitStudioModel
  private var workbenchCameraSnapshot = PlotterWorkbenchCameraSnapshot()
  var workbenchCameraRole: WorkbenchCameraRole { workbenchCameraSnapshot.role }
  var cameraRoleIsTransitioning: Bool { workbenchCameraSnapshot.isTransitioning }
  var cameraRoleError: String? { workbenchCameraSnapshot.error }
  @ObservationIgnored private let pointSelectionRuntime: PlotterPointSelectionRuntime
  @ObservationIgnored private let manualMotionRuntime: PlotterManualMotionRuntime
  @ObservationIgnored private let penInteractionRuntime: PlotterPenInteractionRuntime
  @ObservationIgnored private let boundaryRuntime: PlotterBoundaryRuntime
  @ObservationIgnored private let drawingDraftRuntime: PlotterDrawingDraftRuntime
  @ObservationIgnored private let drawingRunRuntime: PlotterDrawingRunRuntime
  @ObservationIgnored private let incidentPackageUIService: PlotterIncidentPackageUIService
  @ObservationIgnored private let observationPreferences: any PlotterObservationPreferencePort
  @ObservationIgnored let speechEffectRuntime: PlotterSpeechEffectRuntime
  @ObservationIgnored private let workbenchVoiceListener: (any SpeechListening)?
  @ObservationIgnored private var retainedWorkbenchVoiceController: WorkbenchVoiceController?

  /// One application-owned switch survives native view reconstruction. Audio
  /// levels/transcripts remain local to its observable controller.
  var workbenchVoiceController: WorkbenchVoiceController {
    if let retainedWorkbenchVoiceController { return retainedWorkbenchVoiceController }
    let controller = WorkbenchVoiceController(speech: speechEffectRuntime,
      listener: workbenchVoiceListener) { [weak self] request in
      guard let self else {
        return .refused(PlotterUIRequestRefusal(requestID: request.id,
          reason: .retainedOwnerRefused, owner: "Voice application",
          submittedUIRevision: request.uiRevision, currentUIRevision: request.uiRevision,
          submittedRuntimeRevisions: request.runtimeRevisions, currentRuntimeRevisions: [],
          remedy: "The application owning this Voice request is no longer available."))
      }
      return await self.submitPlotterUIRequest(request)
    }
    retainedWorkbenchVoiceController = controller
    return controller
  }
  @ObservationIgnored private var artifactResetRuntime: PlotterArtifactResetRuntime!
  @ObservationIgnored private lazy var cameraCalibrationRuntime = PlotterCameraCalibrationRuntime(
    effectPort: PlotterApplicationRuntimeCameraCalibrationEffectPort(application: self),
    onStateChange: { [weak self] in self?.markSemanticPresentationChanged() }
  )
  /// These ports are capabilities of the LIVE learning session only. The
  /// active accessors deliberately return nil for SIMULATED before any
  /// workflow can load, save, or clear physical durable authority.
  @ObservationIgnored private let statePersistencePort:
    (any PlotterApplicationStatePersistencePort)?
  @ObservationIgnored let drawingEvidencePort: DrawingRunEvidencePort
  @ObservationIgnored var drawingMaterialHashCache: (key: String, digest: PlotterModel.Digest)?
  private(set) var drawingEvidenceArchive = DrawingRunEvidenceArchive()
  private(set) var drawingEvidenceError: String?
  private(set) var axisCalibrationProposal: ControllerAxisCalibrationProposal?
  private(set) var axisMetricStatus: String?
  private(set) var axisCalibrationInProgress = false {
    didSet { if oldValue != axisCalibrationInProgress { markSemanticPresentationChanged() } }
  }
  private(set) var axisMetricRecoveryError: String?
  @ObservationIgnored private var pendingAxisCalibrationTerminal: ControllerAxisCalibrationTerminal?
  private(set) var incidentPackageUIState: PlotterUIIncidentPackageState = .unavailable(
    reason: "No complete incident-package source provider is configured."
  ) {
    didSet {
      guard oldValue != incidentPackageUIState else { return }
      markSemanticPresentationChanged(invalidatesActionSurface: false)
    }
  }

  var currentBoundarySnapshot: PlotterBoundaryRuntimeSnapshot? {
    frameMode == .simulated ? simulatedBoundarySnapshot : liveBoundarySnapshot
  }

  func currentBoundaryExternalFacts(
    for environment: PlotterEnvironment
  ) async -> PlotterBoundaryExternalFacts {
    let isCurrentEnvironment = environment == penInteractionEnvironment
    let liveSnapshot = environment == .live
      ? await refreshControllerSessionSnapshot()
      : nil
    let position: MachinePosition? = if environment == .simulated {
      if let snapshot = simulatedLearningSnapshot {
        try? MachinePosition(x: snapshot.mpos.xMM, y: snapshot.mpos.yMM)
      } else {
        nil
      }
    } else {
      liveSnapshot?.machine.position
    }
    return PlotterBoundaryExternalFacts(
      environment: environment,
      learningEnabled: isCurrentEnvironment && learningIsEnabled && applicationAdmissionIsOpen,
      controllerSessionEstablished: isCurrentEnvironment && sessionEstablished,
      motionAuthorized: isCurrentEnvironment && sessionMotionAuthorized,
      foreignLowerOperationInFlight: isCurrentEnvironment
        && (retainedPenRequestInProgress
          || (liveSnapshot?.machine.operationInFlight == true
            && currentBoundarySnapshot?.projection.reference.operationID == nil)),
      stickyAmbiguity: isCurrentEnvironment ? learningStickyAmbiguityReason : nil,
      controllerSessionID: controllerSessionID,
      coordinateRevision: explorationCoordinateRevision,
      machinePosition: position,
      interpreterIsIdle: environment == .simulated
        || liveSnapshot?.currentOperation == .idle,
      passiveProbe: environment == .live ? passiveProbeResult : nil,
      penActuationProfile: currentPenActuationProfile,
      semanticIdentity: currentLearningPathSemanticIdentity,
      physicalPositionUnavailableReason: isCurrentEnvironment ? retainedPoseApplicabilityRefusal : nil
    )
  }

  /// Refreshes the existing controller-session projection from its lower
  /// owner. `machineSnapshot` is a presentation cache; effect-bearing code
  /// must call this boundary instead of treating that cache as current MPos.
  @discardableResult
  func refreshControllerSessionSnapshot() async -> RunInterpreterSnapshot? {
    guard let machineSession else { return machineSnapshot }
    let snapshot = await machineSession.snapshot()
    machineSnapshot = snapshot
    return snapshot
  }

  func installBoundarySnapshot(_ snapshot: PlotterBoundaryRuntimeSnapshot) {
    guard !positionRebasePublicationIsPending else { return }
    let priorTerminal = liveBoundarySnapshot?.projection.terminal
    if snapshot.projection.reference.environment == .simulated {
      simulatedBoundarySnapshot = snapshot
    } else {
      liveBoundarySnapshot = snapshot
    }
    if snapshot.projection.reference.environment == penInteractionEnvironment {
      installBoundaryDependencyProjection(snapshot)
    }
    if snapshot.projection.reference.environment == .live,
      snapshot.projection.terminal?.disposition == .accepted,
      snapshot.projection.terminal != priorTerminal {
      reconcilePublishedBoundaryCheckpoint(snapshot)
    }
    markSemanticPresentationChanged()
  }

  private func installBoundaryDependencyProjection(
    _ snapshot: PlotterBoundaryRuntimeSnapshot
  ) {
    let orderedKinds = BoundaryDirection.allCases.map(LearningArtifactKind.boundarySideAggregate)
      + [.estimatedMachineCenter, .centerArrival]
    let desired = Dictionary(uniqueKeysWithValues: snapshot.currentRevisions.map { ($0.kind, $0) })
    var graph = learningArtifactGraph
    let staleKinds = Set(orderedKinds.filter {
      graph.currentRevision(for: $0)?.id != desired[$0]?.id
    })
    let invalidation = graph.invalidateCurrentRevisions(rootKinds: staleKinds)
    learningArtifactGraph = graph
    applyArtifactInvalidations(invalidation.allInvalidatedRevisionIDs)
    graph = learningArtifactGraph
    do {
      for kind in orderedKinds {
        guard let revision = desired[kind], graph.currentRevision(for: kind)?.id != revision.id
        else { continue }
        _ = try graph.commitReplacement(
          LearningArtifactRevision(
            id: revision.id,
            kind: revision.kind,
            attemptID: revision.attemptID,
            disposition: revision.disposition,
            consumedRevisionIDs: revision.consumedRevisionIDs
          )
        )
      }
      learningArtifactGraph = graph
      if snapshot.projection.reference.environment == .live {
        activeMachineArtifactCheckpoint = snapshot.acceptedMachineArtifacts
      }
      if let checkpoint = snapshot.acceptedMachineArtifacts {
        explorationCoordinateRevision = checkpoint.coordinateRevision
        acceptedAttemptSequence = max(
          acceptedAttemptSequence,
          checkpoint.acceptedAttemptSequence
        )
      }
    } catch {
      acceptedArtifactCheckpointStatus = .rejected(
        "Boundary dependency projection could not be installed: \(error)"
      )
    }
  }

  @discardableResult
  func submitBoundaryIntent(_ intent: PlotterBoundaryIntent) async
    -> PlotterBoundaryDisposition?
  {
    guard applicationAdmissionIsOpen else { return nil }
    guard let reference = currentBoundarySnapshot?.projection.reference else { return nil }
    return await boundaryRuntime.submit(
      PlotterBoundarySubmission(projection: reference, intent: intent)
    )
  }
  private var activeStatePersistencePort:
    (any PlotterApplicationStatePersistencePort)?
  {
    frameMode == .live ? statePersistencePort : nil
  }
  @ObservationIgnored private let residualEffectPort: any PlotterApplicationResidualEffectPort
  @ObservationIgnored private let simulatedLearningRuntime: SimulatedLearningRuntime
  @ObservationIgnored private let causalSimulatorEffectAdapter:
    PlotterCausalSimulatorEffectAdapter
  @ObservationIgnored private var livePenInteractionSnapshot:
    PlotterPenInteractionRuntimeSnapshot?
  @ObservationIgnored private var simulatedPenInteractionSnapshot:
    PlotterPenInteractionRuntimeSnapshot?
  @ObservationIgnored private var liveBoundarySnapshot: PlotterBoundaryRuntimeSnapshot?
  @ObservationIgnored private var simulatedBoundarySnapshot: PlotterBoundaryRuntimeSnapshot?
  @ObservationIgnored private var observationProjectionTask: Task<Void, Never>?
  @ObservationIgnored private var drawingRunProjectionTask: Task<Void, Never>?
  private(set) var pointSelectionEpisodeProjection: PlotterEpisodeProjection
  private(set) var pointSelectionRecordingDiagnostic: String?
  private(set) var manualMotionEpisodeSnapshot: PlotterManualMotionRuntimeSnapshot?
  private(set) var drawingDraftSnapshot: PlotterDrawingDraftSnapshot {
    didSet {
      guard oldValue != drawingDraftSnapshot else { return }
      if oldValue.isTargetVisible != drawingDraftSnapshot.isTargetVisible
        || oldValue.residualRecords != drawingDraftSnapshot.residualRecords
        || oldValue.residualAnalysis != drawingDraftSnapshot.residualAnalysis {
        markSemanticPresentationChanged(invalidatesActionSurface: false)
      }
      guard oldValue.isTargetVisible || drawingDraftSnapshot.isTargetVisible else { return }
      invalidateActionSurfacePresentation()
    }
  }
  private(set) var drawingRunSnapshot: PlotterDrawingRunSnapshot?
  // One Drawing Run runtime owns this application lifetime. Its per-source
  // revisions continue across new-run/reset handoffs and source switches.
  @ObservationIgnored private var drawingRunSeenPublications:
    [PlotterEnvironment: (revision: PlotterDrawingRunRevision,
      activeRunID: RunID?, progress: DrawingPlanProgressSnapshot?)] = [:]
  @ObservationIgnored private var drawingDraftSynchronizationGeneration: UInt64 = 0
  @ObservationIgnored private(set) var drawingDraftSynchronizationTask: Task<Void, Never>?
  @ObservationIgnored private var positionRebasePublicationIsPending = false
  @ObservationIgnored private var drawingEvidenceReloadTask: Task<Void, Never>?
  @ObservationIgnored private var learningActivityFactRevision: UInt64 = 0
  private var controllerSessionID: UUID {
    get { currentEnvironmentState.controllerSessionID }
    set { currentEnvironmentState.controllerSessionID = newValue }
  }
  private var explorationCoordinateRevision: UInt64 {
    get { currentEnvironmentState.explorationCoordinateRevision }
    set { currentEnvironmentState.explorationCoordinateRevision = newValue }
  }
  private var explorationPaperInstanceRevision: UUID {
    get { currentEnvironmentState.explorationPaperInstanceRevision }
    set { currentEnvironmentState.explorationPaperInstanceRevision = newValue }
  }
  private var explorationPaperContactPlaneRevision: UUID {
    get { currentEnvironmentState.explorationPaperContactPlaneRevision }
    set { currentEnvironmentState.explorationPaperContactPlaneRevision = newValue }
  }
  @ObservationIgnored private var retainedStopRegistration: PlotterRetainedStopRegistration? {
    didSet {
      computationDiagnostics.stoppableOperationMutationCount += 1
      guard oldValue?.presentationSignature != retainedStopRegistration?.presentationSignature
      else { return }
      computationDiagnostics.stoppableOperationSemanticInvalidationCount += 1
      markSemanticPresentationChanged()
    }
  }
  @ObservationIgnored private var sparseTipPenUpAuthorization: SparseTipPenUpAuthorization?
  private var activeStopTarget: ContextualStopTarget? { retainedStopRegistration?.target }
  private var stopDispositionLatch: ContextualStopDispositionLatch? {
    retainedStopRegistration?.state.latch
  }
  private var jogCancelRequestInProgress: Bool {
    retainedStopRegistration?.state.cancellationRequestInProgress == true
  }
  @ObservationIgnored private var admittedApplicationEffects: Set<UUID> = []
  @ObservationIgnored private var applicationEffectSettlementWaiters:
    [CheckedContinuation<Void, Never>] = []
  @ObservationIgnored private var shutdownSettlementWaiters:
    [CheckedContinuation<Void, Never>] = []
  private var applicationAdmissionIsOpen: Bool { admissionState == .open }
  private var applicationAdmissionIsClosed: Bool { admissionState != .open }
  private var activeExerciseAttemptMode: ExerciseAttemptMode? {
    currentEnvironmentState.exerciseAttempt.mode
  }
  private var acceptedAttemptSequence: UInt64 {
    get { currentEnvironmentState.acceptedAttemptSequence }
    set { currentEnvironmentState.acceptedAttemptSequence = newValue }
  }
  @ObservationIgnored private var lastSimulatedProtocolCaptureNanoseconds: UInt64 = 0
  private var activeMachineArtifactCheckpoint: AcceptedMachineArtifactCheckpoint? {
    get { currentEnvironmentState.activeMachineArtifactCheckpoint }
    set { currentEnvironmentState.activeMachineArtifactCheckpoint = newValue }
  }

  init(
    machineSession: (any PlotterMachineSession)? = nil,
    observationSession: (any PlotterObservationCameraSessionPort)? = nil,
    observationRecordingStore: EpisodeRecordingStore? = nil,
    portraitStudio: PortraitStudioModel? = nil,
    drawingMaterials: DrawingMaterialLibrary? = nil,
    pointSelectionRuntime: PlotterPointSelectionRuntime = PlotterPointSelectionRuntime(),
    pointSelectionRecordingDiagnostic: String? = nil,
    manualMotionComposition: PlotterManualMotionRuntimeComposition? = nil,
    penInteractionRuntime: PlotterPenInteractionRuntime,
    boundaryRuntime: PlotterBoundaryRuntime,
    speechEffectRuntime: PlotterSpeechEffectRuntime = PlotterSpeechEffectRuntime(),
    workbenchVoiceListener: (any SpeechListening)? = nil,
    statePersistencePort: (any PlotterApplicationStatePersistencePort)? = nil,
    artifactResetRuntime: PlotterArtifactResetRuntime? = nil,
    drawingDraftRuntime: PlotterDrawingDraftRuntime,
    drawingRunComposition: PlotterDrawingRunComposition,
    incidentPackageUIService: PlotterIncidentPackageUIService,
    tipCalibrationSemanticIdentities: TipCalibrationSemanticIdentityState = .ephemeral(),
    residualEffectPort: any PlotterApplicationResidualEffectPort =
      PlotterApplicationDefaultResidualEffectPort(),
    serialDevices: [MachineLinkDescriptor] = [],
    observationPreferences: any PlotterObservationPreferencePort =
      UserDefaultsObservationPreferencePort()
  ) {
    let resolvedManualMotionComposition: PlotterManualMotionRuntimeComposition
    if let manualMotionComposition {
      resolvedManualMotionComposition = manualMotionComposition
    } else {
      let simulatedRuntime = SimulatedLearningRuntime()
      resolvedManualMotionComposition = PlotterManualMotionComposition.makeRuntimeComposition(
        journalFileURL: FileManager.default.temporaryDirectory.appendingPathComponent(
          "plotter-manual-motion-\(UUID().uuidString).json"
        ),
        machineSession: machineSession,
        simulatedRuntime: simulatedRuntime,
        simulatedExecutionPacing: SimulatedLearningInteractivePacing()
      )
    }
    self.drawingDraftRuntime = drawingDraftRuntime
    drawingRunRuntime = drawingRunComposition.runtime
    self.incidentPackageUIService = incidentPackageUIService
    drawingEvidencePort = drawingRunComposition.evidencePort
    drawingDraftSnapshot = PlotterDrawingDraftSnapshot.initial(
      environment: .live,
      toolAssemblyRevision: tipCalibrationSemanticIdentities.toolAssembly,
      paper: PaperRevisionContext(
        instance: tipCalibrationSemanticIdentities.paperInstance,
        contactPlane: tipCalibrationSemanticIdentities.paperContactPlane
      )
    )
    overlayPreferenceState = .loaded(observationPreferences.loadOverlayPreference())
    applicationState = PlotterApplicationState(
      live: PlotterApplicationEnvironmentState(
        source: .live,
        paperInstanceRevision: tipCalibrationSemanticIdentities.paperInstance.rawValue,
        paperContactPlaneRevision: tipCalibrationSemanticIdentities.paperContactPlane.rawValue
      ),
      simulated: PlotterApplicationEnvironmentState(
        source: .simulated,
        paperInstanceRevision: tipCalibrationSemanticIdentities.paperInstance.rawValue,
        paperContactPlaneRevision: tipCalibrationSemanticIdentities.paperContactPlane.rawValue
      )
    )
    self.machineSession = machineSession
    let resolvedPortraitStudio = portraitStudio ?? PortraitStudioModel()
    self.portraitStudio = resolvedPortraitStudio
    self.drawingMaterials = drawingMaterials ?? DrawingMaterialLibrary()
    if let observationSession {
      observationRuntime = PlotterObservationConfigurationRuntime(
        lower: observationSession,
        recordingStore: observationRecordingStore,
        portrait: resolvedPortraitStudio
      )
    } else {
      observationRuntime = nil
    }
    self.pointSelectionRuntime = pointSelectionRuntime
    manualMotionRuntime = resolvedManualMotionComposition.runtime
    self.penInteractionRuntime = penInteractionRuntime
    self.boundaryRuntime = boundaryRuntime
    self.pointSelectionRecordingDiagnostic = pointSelectionRecordingDiagnostic
    let pointSelectionEpisodeID = EpisodeID(rawValue: UUID())
    let pointSelectionInitialState = PlotterEpisodeState(
      episodeID: pointSelectionEpisodeID,
      canonicalDigest: EpisodeStateDigest(rawValue: "uncommitted-initial-projection")
    )
    pointSelectionEpisodeProjection = PlotterEpisodeProjector.project(
      state: pointSelectionInitialState,
      availabilities: [],
      revision: PlotterProjectionRevision(rawValue: 0),
      projectedAt: Date()
    )
    let loadedLegacyPenCapAppearance = observationPreferences.loadLegacyPenCapAppearance()
    let legacyPenCapAppearance = loadedLegacyPenCapAppearance.flatMap {
      $0.persistedLiveRejectionReason == nil ? $0 : nil
    }
    if statePersistencePort == nil, let legacyPenCapAppearance {
      // Isolated/test compositions without durable checkpoint capability may
      // inject an ephemeral selection. Production always supplies the package
      // port and never treats this as a second persistence authority.
      livePenCapAppearanceSelection = legacyPenCapAppearance
      persistedPenCapAppearanceLoadState = .accepted
    } else if statePersistencePort == nil,
      let reason = loadedLegacyPenCapAppearance?.persistedLiveRejectionReason
    {
      livePenCapAppearanceSelection = nil
      persistedPenCapAppearanceLoadState = .refused(reason)
    } else {
      livePenCapAppearanceSelection = nil
      persistedPenCapAppearanceLoadState = .absent
    }
    simulatedPenCapAppearanceSelection = nil
    self.observationPreferences = observationPreferences
    // The former UserDefaults value is migration input only. The accepted
    // Learning package is now the sole durable appearance owner.
    if statePersistencePort != nil {
      try? observationPreferences.clearLegacyPenCapAppearance()
    }
    self.speechEffectRuntime = speechEffectRuntime
    self.workbenchVoiceListener = workbenchVoiceListener
    self.artifactResetRuntime = artifactResetRuntime
    self.statePersistencePort = statePersistencePort
    machineGeometryIdentity = tipCalibrationSemanticIdentities.machineGeometry
    toolAssemblyRevision = tipCalibrationSemanticIdentities.toolAssembly
    penContactProfileRevision = tipCalibrationSemanticIdentities.penContactProfile
    cameraMountRevision = tipCalibrationSemanticIdentities.cameraMountRevision
    cameraReframingRevision = tipCalibrationSemanticIdentities.cameraReframingRevision
    self.residualEffectPort = residualEffectPort
    simulatedLearningRuntime = resolvedManualMotionComposition.simulatedRuntime
    controllerSessionRuntime = PlotterControllerSessionRuntime(
      lowerSession: machineSession,
      simulatedSession: resolvedManualMotionComposition.simulatedRuntime,
      serialDeviceDiscovery: residualEffectPort
    )
    causalSimulatorEffectAdapter =
      resolvedManualMotionComposition.causalSimulatorEffectAdapter
    self.serialDevices = serialDevices
    if self.artifactResetRuntime == nil {
      self.artifactResetRuntime = PlotterArtifactResetRuntime(
        effectPort: self,
        persistencePort: self
      )
    }
    if let statePersistencePort {
      do {
        let identity = try AxisMetricLearningTransition.reconcile(
          archive: drawingEvidencePort.loadSnapshot(), identity: currentLearningPathSemanticIdentity,
          persistence: statePersistencePort)
        machineGeometryIdentity = identity.machineGeometry
      } catch {
        axisMetricRecoveryError = "Axis calibration evidence/identity recovery failed: \(error)"
      }
      if let error = axisMetricRecoveryError {
        self.artifactResetRuntime.installSavedLearningFact(.rejected(error))
        acceptedArtifactCheckpointStatus = .rejected(error)
      } else {
      switch statePersistencePort.loadAcceptedLearningPathCheckpoint() {
      case .absent:
        self.artifactResetRuntime.installSavedLearningFact(.absent)
        acceptedArtifactCheckpointStatus = .unavailable
      case .loaded(let loadedCheckpoint):
        do {
          let checkpoint: AcceptedLearningPathCheckpoint
          if loadedCheckpoint.penCapAppearance == nil,
            let legacyPenCapAppearance
          {
            checkpoint = try AcceptedLearningPathCheckpoint(
              checkpointID: loadedCheckpoint.checkpointID,
              semanticIdentity: loadedCheckpoint.semanticIdentity,
              penInteraction: loadedCheckpoint.penInteraction,
              machineArtifacts: loadedCheckpoint.machineArtifacts,
              machineCamera: loadedCheckpoint.machineCamera,
              tipCalibration: loadedCheckpoint.tipCalibration,
              stageFour: loadedCheckpoint.stageFour,
              penCapAppearance: legacyPenCapAppearance.acceptedCheckpoint(),
              referenceFrame: loadedCheckpoint.referenceFrame
            )
            try statePersistencePort.saveAcceptedLearningPathCheckpoint(checkpoint)
          } else {
            checkpoint = loadedCheckpoint
          }
          if checkpoint.semanticIdentity == currentLearningPathSemanticIdentity {
            self.artifactResetRuntime.installSavedLearningFact(.awaitingOperatorDecision(
              checkpoint,
              opticalComparison: "Waiting for a compatible current camera frame. No saved value has been applied."
            ))
            acceptedArtifactCheckpointStatus = .awaitingOperatorDecision(
              sideCount: checkpoint.machineArtifacts?.acceptedBoundaryAggregates.count ?? 0,
              hasTipCalibration: checkpoint.tipCalibration != nil
            )
          } else {
            self.artifactResetRuntime.installSavedLearningFact(.rejected(
              "Saved machine, tool, paper-plane, or camera-mount identity changed."
            ))
            acceptedArtifactCheckpointStatus = .incompatible(
              "Saved machine, tool, paper-plane, or camera-mount identity changed."
            )
          }
        } catch {
          let reason = "Learning package migration failed: \(error)"
          self.artifactResetRuntime.installSavedLearningFact(.rejected(reason))
          acceptedArtifactCheckpointStatus = .rejected(reason)
        }
      case .rejected(let reason):
        self.artifactResetRuntime.installSavedLearningFact(.rejected(reason))
        acceptedArtifactCheckpointStatus = .rejected(reason)
      }
    }
    }
    drawingRunComposition.install(on: self)
    drawingRunProjectionTask = Task { [weak self, drawingRunRuntime] in
      let snapshots = await drawingRunRuntime.snapshots(environment: .live)
      for await snapshot in snapshots {
        guard !Task.isCancelled, let self else { return }
        self.installDrawingRunSnapshot(snapshot)
      }
    }
    if let observationRuntime {
      observationProjectionTask = Task { @MainActor [weak self, observationRuntime] in
        let updates = await observationRuntime.updates()
        for await event in updates {
          guard !Task.isCancelled, let self else { return }
          self.installObservationEvent(event)
        }
      }
    }
  }

  private func submitObservationIntent(
    _ intent: PlotterObservationConfigurationIntent
  ) async -> PlotterObservationConfigurationDisposition? {
    guard let observationRuntime else { return nil }
    let reference = await observationRuntime.reference()
    return await observationRuntime.submit(.init(reference: reference, intent: intent))
  }

  private func installObservationEvent(_ event: PlotterObservationRuntimeEvent) {
    switch event {
    case .cameraRole(let snapshot):
      guard workbenchCameraSnapshot != snapshot else { return }
      workbenchCameraSnapshot = snapshot
      if snapshot.role == .portrait {
        clearAutomaticVisionPresentation()
        displayedFrame = nil
        latestLiveCameraFrame = nil
      }
      markSemanticPresentationChanged()
    case .camera(let snapshot):
      cameraSnapshot = snapshot
      if workbenchCameraRole == .plotter, let latest = snapshot.latestFrame { receive(latest) }
      updateCameraError()
    case .frame(let frame):
      receive(frame)
    case .analysis(let snapshot):
      guard workbenchCameraRole == .plotter, !cameraRoleIsTransitioning else { return }
      guard snapshot.revision != visionAnalysisSnapshot.revision else { return }
      let priorFrameID = visionAnalysisSnapshot.latestResult?.displayedFrame.frame.id
      visionAnalysisSnapshot = snapshot
      if visionError != snapshot.lastError { visionError = snapshot.lastError }
      computationDiagnostics.visionAnalysisRevisionCount += 1
      computationDiagnostics.record(.visionAnalysisRevision(
        revision: snapshot.revision,
        phase: snapshot.phase,
        latestResultFrameID: snapshot.latestResult?.displayedFrame.frame.id,
        lastError: snapshot.lastError
      ))
      if priorFrameID != snapshot.latestResult?.displayedFrame.frame.id,
        let result = snapshot.latestResult
      {
        receiveVision(result)
      }
    case .diagnostics(let diagnostics):
      videoVisionDiagnostics = diagnostics
    case .failure(let detail):
      cameraError = detail
    }
  }

  func replaceSimulatedExecutionPacingForTesting(
    _ pacing: any SimulatedLearningExecutionPacing
  ) {
    causalSimulatorEffectAdapter.replaceExecutionPacing(pacing)
  }

  func replaceSimulatedTipCalibrationCheckpointForTesting(
    _ checkpoint: AcceptedTipCalibrationCheckpoint?
  ) {
    guard frameMode == .simulated else { return }
    recoverableTipCalibrationCheckpoint = checkpoint
    restoreTipCalibrationForSimulatedTest(against: displayedFrame)
    markSemanticPresentationChanged()
  }

  func simulateUnchangedApplicationTipReloadForTesting(
    _ checkpoint: AcceptedTipCalibrationCheckpoint
  ) throws {
    guard frameMode == .simulated else { return }
    var retained = learningArtifactGraph.revisions.filter { revision in
      guard revision.state == .current else { return false }
      switch revision.kind {
      case .penInteraction, .boundarySideAggregate, .estimatedMachineCenter,
        .centerArrival, .machineCameraRegistration:
        return true
      default:
        return false
      }
    }
    var rebuilt = LearningDependencyGraph()
    while !retained.isEmpty {
      guard let index = retained.firstIndex(where: { revision in
        revision.consumedRevisionIDs.allSatisfy {
          rebuilt.revision(id: $0)?.state == .current
        }
      }) else {
        throw LearningDependencyGraphError.invalidDependencyShape(.tipCameraRegistration)
      }
      let revision = retained.remove(at: index)
      _ = try rebuilt.commitReplacement(
        LearningArtifactRevision(
          id: revision.id,
          kind: revision.kind,
          attemptID: revision.attemptID,
          disposition: revision.disposition,
          consumedRevisionIDs: revision.consumedRevisionIDs
        )
      )
    }
    learningArtifactGraph = rebuilt
    tipCameraRegistration = nil
    proposedTipCameraRegistration = nil
    recoverableTipCalibrationCheckpoint = checkpoint
    restoreTipCalibrationForSimulatedTest(against: displayedFrame)
  }

  /// Test-only simulated shortcut. Production application restarts use the
  /// explicit saved-package decision and never reach this helper.
  private func restoreTipCalibrationForSimulatedTest(
    against frame: DisplayedFrame?
  ) {
    guard frameMode == .simulated,
      tipCameraRegistration == nil,
      let checkpoint = recoverableTipCalibrationCheckpoint,
      let machineRegistration = machineCameraRegistration,
      let machineRevision = learningArtifactGraph.currentRevision(
        for: .machineCameraRegistration
      )?.id,
      let frame
    else { return }

    do {
      try checkpoint.validate()
      let registration = checkpoint.registration
      let currentOptical = try exactTipCalibrationFrame(frame).opticalConfiguration
      guard registration.applicability.opticalConfiguration == currentOptical else {
        if frameMode == .live {
          invalidateCameraDependentLearningAuthority()
          explorationError =
            "Saved camera-dependent learning was invalidated because the current camera source or semantic optical configuration changed."
        }
        return
      }
      guard registration.machineCameraRegistrationRevisionID == machineRevision,
        machineRegistration.opticalConfiguration == currentOptical,
        registration.applicability.machineGeometry == machineGeometryIdentity,
        registration.applicability.machineCoordinateFrame.rawValue
          == explorationCoordinateRevision,
        registration.applicability.toolAssembly == toolAssemblyRevision,
        registration.applicability.penContactProfile == penContactProfileRevision,
        registration.applicability.paperContactPlane
          == currentPaperRevisionContext.contactPlane
      else { return }

      var graph = learningArtifactGraph
      for revision in try checkpoint.restoredGraphRevisions() {
        _ = try graph.commitReplacement(revision)
      }
      learningArtifactGraph = graph
      tipCameraRegistration = registration
      proposedTipCameraRegistration = nil
      recoverableTipCalibrationCheckpoint = nil
      controllerPoseApplicability = .currentSession
      restoreInteractiveLearningCompletionFromEvidence()
      explorationError = nil
    } catch {
      learningAuthorityError =
        "Saved tip calibration could not be restored from durable authority: \(error)"
    }
  }

  private func reconcileCameraDependentLearningAuthority(
    with frame: DisplayedFrame?
  ) {
    guard let frame else { return }
    updateSavedTrainingOpticalComparison(with: frame)
  }

  private func updateSavedTrainingOpticalComparison(
    with frame: DisplayedFrame
  ) {
    guard case .awaitingOperatorDecision(let checkpoint, _) = savedLearningState
    else { return }
    let identity = SavedTrainingOpticalComparisonIdentity(
      checkpointID: checkpoint.checkpointID,
      cameraConfigurationID: frame.frame.cameraConfigurationID
    )
    guard identity != lastCompletedSavedTrainingOpticalComparisonIdentity,
      !pendingSavedTrainingOpticalComparisonIdentities.contains(identity)
    else { return }
    pendingSavedTrainingOpticalComparisonIdentities.insert(identity)
    Task { @MainActor [weak self] in
      guard let self else { return }
      let before = self.savedLearningState
      let applied = await self.artifactResetRuntime.submit(
        .compareSavedLearning(
          checkpoint,
          comparisonIdentity: identity.artifactRuntimeValue
        ),
        facts: self.artifactResetAdmissionFacts
      )
      self.pendingSavedTrainingOpticalComparisonIdentities.remove(identity)
      guard applied else { return }
      self.lastCompletedSavedTrainingOpticalComparisonIdentity = identity
      guard self.savedLearningState != before else { return }
      self.markSemanticPresentationChanged()
    }
  }

  private var durableAcceptedLiveCameraDeviceID: CameraDeviceID? {
    let optical =
      tipCameraRegistration?.applicability.opticalConfiguration
      ?? recoverableTipCalibrationCheckpoint?.registration.applicability.opticalConfiguration
      ?? machineCameraRegistration?.opticalConfiguration
      ?? activeMachineCameraCheckpoint?.registration.opticalConfiguration
    guard case .live(let deviceID) = optical?.source else { return nil }
    return deviceID
  }

  /// A passive fallback only; never install it as an observation or select the
  /// simulated execution environment when the real camera becomes unavailable.
  func canvasSimulationPreview() async -> DisplayedFrame? {
    try? await simulatedLearningRuntime.previewSceneFrame().get().displayedFrame
  }

  var actionSurfacePresentation: ActionSurfacePresentation {
    let revision = actionSurfacePresentationRevision
    if let cached = actionSurfacePresentationCache, cached.revision == revision {
      computationDiagnostics.actionSurfaceCacheHitCount += 1
      return cached.presentation
    }
    computationDiagnostics.actionSurfaceBuildCount += 1
    let retainedFrame =
      frozenPointSelectionFrame
      ?? (borderValidationSnapshot.comparisonReviewIsPinned
        ? borderValidationSnapshot.postFrame
        : nil)
      ?? ({
        guard let run = drawingRunSnapshot else { return nil }
        if case .pinned = run.review { return run.postFrame }
        return nil
      }())
    let surfaceFrame = retainedFrame ?? displayedFrame
    let overlayComposition = OverlayPresentationComposer.compose(
      preference: overlayPreferenceState,
      channels: overlayResultChannels,
      displayedFrame: surfaceFrame,
      sceneState: visionAnalysisSnapshot,
      sceneIsAvailable: sceneOverlayIsAvailable,
      workflowVisionIsExclusive: exactWorkflowVisionOwner != nil
    )
    let fittedRegion = surfaceFrame.flatMap(learnedBoundsPresentationRegion)
    let viewportContext = surfaceFrame.map {
      ActionSurfaceViewportContext(
        source: $0.source,
        cameraConfigurationID: $0.frame.cameraConfigurationID,
        frameWidth: $0.frame.width,
        frameHeight: $0.frame.height,
        fittedRegion: fittedRegion,
        preferredInitialZoom: 0,
        presentationRevisionToken: machineCameraRegistration.map {
          "machine-cap-\($0.correspondenceFrameIDs.map(\.rawValue).sorted().joined(separator: "-"))"
        } ?? "post-boundary-presentation"
      )
    }
    let surfacePointSelectionRequest = pointSelectionRequest.flatMap { request in
      surfaceFrame.map(request.matchesExactDisplayedFrame) == true ? request : nil
    }
    let tipPresentation: ActionSurfaceTipPresentation =
      if let pointSelectionRequest = surfacePointSelectionRequest,
        pointSelectionRequest.purpose == .toolContact
      {
        .collectingClicks(
          prompt: pointSelectionRequest.prompt,
          clicks: selectedToolContactPoints
        )
      } else if let pointSelectionRequest = surfacePointSelectionRequest {
        .awaitingClick(pointSelectionRequest.prompt)
      } else if tipCameraRegistration != nil {
        .calibrated(prediction: nil)
      } else {
        .notCalibrated
      }
    let presentation = ActionSurfacePresentation(
      displayedFrame: surfaceFrame,
      usesAmbientPreviewFrame: retainedFrame == nil,
      overlays: overlayComposition.overlays
        + (surfaceFrame.map(learnedDrawingOverlays) ?? [])
        + (surfaceFrame.map(borderValidationPredictionOverlays) ?? []),
      simulatedAnnotations: simulatedAnnotations,
      simulatedViewportID: simulatedViewportID,
      simulatedAnnotationsAreVisible: simulatedAnnotationsAreVisible,
      viewportContext: viewportContext,
      analysisRegionIsLocked: surfaceFrame.map {
        videoAnalysisRegionLock?.matches($0) == true
      } ?? false,
      analyzedOverlayFrame: overlayComposition.analyzedFrame,
      pointSelectionRequest: surfacePointSelectionRequest,
      tipPresentation: tipPresentation,
      completedComparisonReview: completedComparisonReviewPresentation,
      drawingStudioCanvas: drawingTargetIsVisible ? drawingStudioPresentation.canvas : nil
    )
    let signature = ActionSurfaceDiagnosticSignature(
      frameID: presentation.displayedFrame?.frame.id,
      overlayCount: presentation.overlays.count,
      pointSelectionPurpose: presentation.pointSelectionRequest?.purpose
    )
    if signature != lastActionSurfaceDiagnosticSignature {
      lastActionSurfaceDiagnosticSignature = signature
      computationDiagnostics.record(
        .actionSurfaceChanged(
          frameID: signature.frameID,
          overlayCount: signature.overlayCount,
          pointSelectionPurpose: signature.pointSelectionPurpose
        )
      )
    }
    actionSurfacePresentationCache = ActionSurfacePresentationCache(
      revision: revision,
      presentation: presentation
    )
    return presentation
  }

  var currentPaperRevisionContext: PaperRevisionContext {
    PaperRevisionContext(
      instance: PaperInstanceRevision(rawValue: explorationPaperInstanceRevision),
      contactPlane: PaperContactPlaneRevision(
        rawValue: explorationPaperContactPlaneRevision
      )
    )
  }

  var paperCoverageIsCurrent: Bool {
    drawingDraftSnapshot.paperCoverageIsCurrent
  }

  var currentMaterialApplicability: DrawingMaterialApplicability? {
    guard let registration = tipCameraRegistration,
      let optical = drawingDraftSnapshot.projection.externalFacts.opticalConfiguration,
      learningArtifactGraph.currentRevision(for: .tipCameraRegistration)?.id == registration.acceptedRevisionID,
      registration.applicability == TipCalibrationApplicabilityContext(
        opticalConfiguration: optical, machineGeometry: machineGeometryIdentity,
        machineCoordinateFrame: MachineCoordinateFrameRevision(rawValue: explorationCoordinateRevision),
        toolAssembly: toolAssemblyRevision, penContactProfile: penContactProfileRevision,
        paperContactPlane: PaperContactPlaneRevision(rawValue: explorationPaperContactPlaneRevision))
    else { return nil }
    return try? DrawingMaterialApplicability(registration: registration, paperStock: materialPaperStock,
      drawingFeedMMPerMinute: PlotterMotionThroughput.applicationXYFeedMMPerMinute,
      penActuationProfile: currentPenActuationProfile)
  }

  /// Capture existing owned images only. Inspecting material never moves the
  /// controller, switches cameras, or creates another calibration mark.
  func prepareMaterialInspection() async -> String? {
    guard let profile = drawingMaterials.activeRecord?.profile,
      let registration = tipCameraRegistration, let applicability = currentMaterialApplicability
    else { return "Select a material and enter paper stock with current pen-tip calibration and plotter camera." }
    do {
      if materialUsesBorderImages {
        let snapshot = borderValidationSnapshot
        guard let baseline = snapshot.localPreFrameBaseline, let post = snapshot.postFrame,
          let pose = snapshot.revealPosition, let plan = snapshot.drawingBorderPlan,
          snapshot.tipRegistrationRevisionID == registration.acceptedRevisionID,
          snapshot.inkObservation != nil, snapshot.activeOperationID == nil
        else { return "Completed Drawing Border images at the same observation pose are unavailable." }
        materialInspection = DrawingMaterialInspection(profile: profile, applicability: applicability,
          registration: registration, baseline: SamePoseFrameSample(displayedFrame: baseline, controllerPosition: pose),
          result: SamePoseFrameSample(displayedFrame: post, controllerPosition: pose), paths: plan.strokes.map(\.path))
      } else {
        guard let frame = displayedFrame, let position = machineSnapshot?.machine.position,
          machineSnapshot?.currentOperation == .idle,
          SparseTipCircularMarkPlan.supportsRestoredGeometry(for: registration.estimatorRevision)
        else { return "An existing plotter frame, idle controller position and supported calibration-mark geometry are required." }
        let inverse = try registration.cameraFromMachine.inverted()
        let paths = try registration.observationEvidence.map { observation in
          // predictedPoint is the accepted fit evaluated at the commanded mark
          // centre; observedPoint would incorrectly incorporate fitting residual.
          let center = try inverse.applying(to: observation.predictedPoint)
          return try Polyline<MachineSpace>(points: (0...SparseTipCircularMarkPlan.chordCount).map { index in
            let angle = 2 * Double.pi * Double(index % SparseTipCircularMarkPlan.chordCount) / Double(SparseTipCircularMarkPlan.chordCount)
            return try Point2(x: center.x + SparseTipCircularMarkPlan.radiusMM*cos(angle),
              y: center.y + SparseTipCircularMarkPlan.radiusMM*sin(angle))
          })
        }
        materialInspection = DrawingMaterialInspection(profile: profile, applicability: applicability,
          registration: registration, baseline: nil,
          result: SamePoseFrameSample(displayedFrame: frame, controllerPosition: position), paths: paths)
      }
      return nil
    } catch { return error.localizedDescription }
  }

  func confirmMaterialInspection(_ inspected: DrawingMaterialInspection) async -> String? {
    guard materialInspection?.id == inspected.id else { return "This image inspection has been replaced." }
    do {
      let visible = [Bool](repeating: false, count: inspected.result.frame.width * inspected.result.frame.height)
      let evidence = DrawingMaterialVisibilityEvidence(
        inspectedFrames: (inspected.baseline.map { [ExactFrameProvenance(frame: $0.frame)] } ?? [])
          + [ExactFrameProvenance(frame: inspected.result.frame)], source: inspected.result.source, confirmedAt: Date())
      let worker = VisionWorker()
      let measurement: DrawingMaterialMeasurement
      if let baseline = inspected.baseline {
        measurement = try await worker.measureDepositedWidth(DrawingMaterialMeasurementRequest(
          baseline: baseline, result: inspected.result, registration: inspected.registration,
          intendedPaths: inspected.paths, occlusionMask: visible,
          currentApplicability: inspected.applicability.calibration, visibilityEvidence: evidence))
      } else {
        measurement = try await worker.measureDepositedWidth(DrawingMaterialExistingInkMeasurementRequest(
          result: inspected.result, registration: inspected.registration, intendedPaths: inspected.paths,
          occlusionMask: visible, maximumWidthMM: min(1.5, max(0.25, inspected.profile.nominalWidthMM*3)),
          currentApplicability: inspected.applicability.calibration, visibilityEvidence: evidence))
      }
      let prior = inspected.profile
      guard let revision = drawingMaterials.nextRevision(for: prior.id) else {
        return "This material has exhausted its revision range. Create a new material identity."
      }
      let profile = try DrawingMaterialProfileRevision(id: prior.id, revision: revision, name: prior.name,
        nominalWidthMM: prior.nominalWidthMM, qualification: measurement.qualification,
        depositedWidth: measurement.distribution, measurementEvidenceID: measurement.id,
        measurementLimitations: measurement.limitations)
      var ownedMedia: [DrawingRunMediaReference] = []
      if let baseline = inspected.baseline {
        ownedMedia.append(try await drawingEvidencePort.installMedia(frame: baseline.frame, source: baseline.source))
      }
      ownedMedia.append(try await drawingEvidencePort.installMedia(frame: inspected.result.frame, source: inspected.result.source))
      let record = try DrawingMaterialRecord(profile: profile, applicability: inspected.applicability, measurement: measurement,
        conditionsOrigin: "operator-confirmed-existing-mark-conditions-v1", ownedMedia: ownedMedia)
      if let error = drawingMaterials.add(record) { return error }
      if currentMaterialApplicability == inspected.applicability, drawingMaterials.activeKey == prior.key {
        if let error = drawingMaterials.activate(key: profile.key) { return error }
      }
      await drawingMaterials.flush()
      materialMeasurementStatus = measurement.qualification == .unavailable
        ? "Deposited width unavailable: " + measurement.limitations.joined(separator: " ")
        : "Controller-coordinate width estimated from \(measurement.samples.count) samples. Original inspected images are durably retained. Independent physical accuracy remains unverified."
      if materialInspection?.id == inspected.id { materialInspection = nil }
      return drawingMaterials.persistenceError
    } catch { return error.localizedDescription }
  }

  func assessCurrentMaterial() async -> String? {
    guard let profile = drawingMaterials.activeRecord?.profile,
      let program = drawingDraftSnapshot.program, let plan = drawingDraftSnapshot.plan
    else { return "Select a material and project a drawing first." }
    do {
      let report = try await Task.detached {
        try DrawingMaterialFeasibility.assess(program: program, placement: plan.placement, profile: profile)
      }.value
      guard drawingDraftSnapshot.plan?.contentHash == plan.contentHash,
        drawingMaterials.activeKey == profile.key else { return "Drawing scale or material changed during analysis; assess the current drawing again." }
      materialFeasibilityReceipt = (plan.contentHash, profile.key, report.summary + " " + report.limitations.joined(separator: " "))
      return nil
    } catch { return error.localizedDescription }
  }

  var drawingStrokeStyle: StrokeStyle {
    drawingDraftSnapshot.program?.strokes.first?.style
      ?? (try! StrokeStyle(nominalLineWidth: 0.4,
        penProfileID: PenProfileID(drawingDraftSnapshot.projection.externalFacts.toolAssemblyRevision.rawValue)))
  }

  func drawingMaterialSelectionDidChange() {
    commitSemanticPresentationChange(invalidatesActionSurface: true)
  }

  var drawingDraftExternalFacts: PlotterDrawingDraftExternalFacts {
    let opticalConfiguration = displayedFrame.flatMap {
      try? exactTipCalibrationFrame($0).opticalConfiguration
    }
    return PlotterDrawingDraftExternalFacts(
      environment: manualMotionEnvironment,
      interactiveLearningIsComplete: interactiveLearningIsComplete,
      displayedFrame: displayedFrame,
      opticalConfiguration: opticalConfiguration,
      registration: tipCameraRegistration,
      drawableRegion: currentDrawableMachineRegion,
      toolAssemblyRevision: toolAssemblyRevision,
      paper: currentPaperRevisionContext,
      runInProgress: drawingRunIsActive,
      terminalRequiresNewPlan: drawingRunRequiresNewPlan,
      coverageRecords: drawingEvidenceArchive.records,
      drawingArchiveIsAvailable: manualMotionEnvironment == .simulated || {
        guard let snapshot = drawingRunSnapshot,
          case .available = snapshot.evidenceArchiveAvailability else { return false }
        return true
      }(),
      drawingBorderBounds: currentDrawingBorderBounds,
      materialContextHash: currentDrawingMaterialContextHash
    )
  }

  private func performDrawingDraftSubmission(
    _ submission: PlotterDrawingDraftSubmission
  ) async {
    guard applicationAdmissionIsOpen else { return }
    installDrawingRunSnapshot(
      await drawingRunRuntime.snapshot(environment: manualMotionEnvironment)
    )
    let result = await drawingDraftRuntime.submit(
      submission,
      facts: drawingDraftExternalFacts
    )
    installDrawingDraftSnapshot(result.snapshot)
    switch result.disposition {
    case .applied:
      drawingEvidenceError = nil
      if submission.intent == .showTarget {
        let reviewResult = borderValidationRuntime.apply(.setComparisonReviewPinned(false))
        if case .refused(let reason, let remedy) = reviewResult.disposition {
          drawingEvidenceError = "\(reason) Remedy: \(remedy)"
        }
      }
      await synchronizeDrawingRunProjection()
    case .refused(let refusal):
      drawingEvidenceError = refusal.remedy
    }
  }

  private func synchronizeDrawingDraft() async {
    let snapshot = await drawingDraftRuntime.synchronize(drawingDraftExternalFacts)
    installDrawingDraftSnapshot(snapshot)
  }

  private func scheduleDrawingDraftSynchronization() {
    // Closing feature owners still publish their final semantic state. Those
    // notifications must not recreate work after shutdown canceled this chain.
    guard applicationAdmissionIsOpen else { return }
    computationDiagnostics.drawingDraftSynchronizationCount += 1
    drawingDraftSynchronizationGeneration &+= 1
    let generation = drawingDraftSynchronizationGeneration
    let facts = drawingDraftExternalFacts
    let previous = drawingDraftSynchronizationTask
    previous?.cancel()
    drawingDraftSynchronizationTask = Task { @MainActor [weak self] in
      // A predecessor may already be inside Run's nested Draft fact read.
      // Cancellation alone does not join that publication tail. The retained
      // replacement completes only after its predecessors have settled.
      await previous?.value
      guard !Task.isCancelled, let self,
        generation == self.drawingDraftSynchronizationGeneration else { return }
      let snapshot = await self.drawingDraftRuntime.synchronize(facts)
      guard !Task.isCancelled, generation == self.drawingDraftSynchronizationGeneration else { return }
      self.installDrawingDraftSnapshot(snapshot)
      await self.synchronizeDrawingRunProjection()
    }
  }

  private func installDrawingDraftSnapshot(_ snapshot: PlotterDrawingDraftSnapshot) {
    guard snapshot.projection.environment == manualMotionEnvironment else { return }
    guard snapshot != drawingDraftSnapshot else { return }
    drawingDraftSnapshot = snapshot
  }

  var interactiveLearningIsComplete: Bool {
    axisMetricRecoveryError == nil && !axisCalibrationInProgress
      && (borderValidationSnapshot.assessment != nil || retainedLearningCompletion != nil)
  }

  private var retainedLearningCompletion: BorderValidationAssessment? {
    guard let registration = tipCameraRegistration else { return nil }
    let record = drawingEvidenceArchive.records.last { record in
      record.role == .evaluationHoldout
        && record.executionDisposition == .completed
        && [.attributable, .visionUnclear].contains(record.evidenceDisposition)
        && registration.matchesDrawingValidationRevision(
          record.tipCalibration.acceptedRevisionID
        )
        && record.paper.contactPlane == currentPaperRevisionContext.contactPlane
    }
    return record.map { $0.evidenceDisposition == .attributable ? .predictionObserved : .drawingCompleted }
  }

  var workbenchCapabilityPresentation: WorkbenchCapabilityPresentation {
    let learning: WorkbenchLearningCapabilityState
    if currentEnvironmentState.drawingReadinessAssessment?.state == .ready {
      learning = .adaptiveDrawingReady
    } else if interactiveLearningIsComplete {
      learning = .interactiveLearningComplete
    } else if tipCameraRegistration != nil {
      learning = .mapReady
    } else if recoverableTipCalibrationCheckpoint != nil {
      learning = .savedMapNeedsRevalidation
    } else {
      learning = .learningNeeded
    }
    let paper: WorkbenchPaperSetupState =
      paperCoverageIsCurrent
      ? .current(
        detail: "Operator assertion: this sheet covers the outline; paper edges were not measured."
      )
      : .setupRequired(
        reason:
          "Place the current sheet over the outlined Drawing Boundary and assert that it covers the outline."
      )
    return WorkbenchCapabilityPresentation(learning: learning, paper: paper)
  }

  private var drawingRunIsActive: Bool {
    guard let snapshot = drawingRunSnapshot else { return false }
    return snapshot.activeRunID != nil || snapshot.phase == .appendingEvidence
  }

  private var drawingRunRequiresNewPlan: Bool {
    guard let snapshot = drawingRunSnapshot else { return false }
    if snapshot.terminal != nil { return true }
    switch snapshot.noRedraw {
    // Archive availability gates Run, not creation of an unexecuted draft.
    case .clear, .archiveUnavailable: return false
    case .newPlanRequired, .planMayContainInk: return true
    }
  }

  func latestMotionReadoutSnapshot() async -> MachineSnapshot? {
    guard frameMode == .live else { return nil }
    return await machineSession?.snapshot()?.machine
  }

  var paperReplacementStatus: String? {
    guard !drawingRunIsActive, drawingRunSnapshot?.terminal == nil,
      drawingEvidenceError == nil, explorationError == nil,
      !drawingDraftSnapshot.paperCoverageIsCurrent,
      let plan = artifactResetRuntime.snapshot().lastResetPlan,
      let replacement = plan.paperReplacement,
      replacement.current == currentPaperRevisionContext else { return nil }
    if case .unavailable(let issue) = drawingRunSnapshot?.readiness,
      ![.learningIncomplete, .paperCoverageNotCurrent, .exactPlanUnavailable].contains(issue.reason) {
      return nil
    }
    if let registration = tipCameraRegistration {
      guard let frame = displayedFrame,
        (try? exactTipCalibrationFrame(frame).opticalConfiguration) == registration.applicability.opticalConfiguration else {
        return "Show the compatible Plotter Video camera, then confirm sheet coverage. Calibration remains retained."
      }
      return "New sheet recorded. Calibration retained. Confirm sheet coverage."
    }
    if replacement.tipCalibrationApplicabilityChange != nil {
      return "Contact plane changed. Repeat pen-tip calibration for this plane; machine boundaries and camera Learning are retained."
    }
    if savedLearningApplicationCandidate != nil {
      return "New sheet recorded. Use Saved Learning to restore compatible calibration, then confirm sheet coverage."
    }
    if let checkpoint = savedLearningState.applicationCandidate?.checkpoint,
      checkpoint.tipCalibration != nil {
      return savedLearningRecoveryUnavailableReason(checkpoint)
    }
    return "Pen-tip calibration is unavailable for this sheet's contact plane. Complete pen-tip calibration using the retained machine and camera Learning."
  }

  private var paperReplacementInProgressReason: String? {
    guard case .paperReplaced = artifactResetRuntime.snapshot().activeIntent else { return nil }
    return "Wait for the current paper replacement transaction to finish."
  }

  var paperManagementUnavailableReason: String? {
    if let reason = paperReplacementInProgressReason { return reason }
    if tipCalibrationRuntime.activeOperationID != nil {
      return "Wait for position verification or pen-tip calibration to finish, or use Stop before changing paper."
    }
    return drawingRunIsActive
      ? "Paper identity cannot change while Drawing Run owns execution or evidence capture."
      : nil
  }

  var drawingStudioPresentation: DrawingStudioPresentation {
    let draft = drawingDraftSnapshot
    let run = drawingRunSnapshot
    let editingIsEnabled = run?.activeRunID == nil && run?.terminal == nil
    let placement = DrawingStudioPlacementPresentation(
      centerCameraPixel: draft.centerCameraPixel,
      uniformScale: draft.uniformScale,
      allowedScale: draft.allowedScale,
      rotationDegrees: draft.rotationDegrees,
      placementIsEnabled: editingIsEnabled && !drawingRunRequiresNewPlan && draft.coverageExperiment == nil
    )
    return DrawingStudioPresentation(
      canvas: DrawingStudioCanvasPresentation(
        draftProjection: draft.projection,
        placement: placement,
        targetPreview: drawingStudioTargetPreview(from: draft.preview)
      ),
      editingIsEnabled: editingIsEnabled && !drawingRunRequiresNewPlan,
      runProjection: run?.projection,
      runState: drawingStudioRunState(run),
      coverageExperiment: draft.coverageExperiment,
      coverageAssessment: draft.coverageAssessment,
      coverageUnavailableReason: draft.coverageUnavailableReason,
      coverageSelectedTrial: DrawingCoverageTrialDescriptor.decode(draft.program?.source)?.trialIndex,
      residualRecords: draft.residualRecords,
      residualAnalysis: draft.residualAnalysis,
      drawBorder: draft.drawBorder,
      paperReplacementStatus: paperReplacementStatus
    )
  }

  private func drawingStudioRunState(
    _ snapshot: PlotterDrawingRunSnapshot?
  ) -> DrawingStudioRunState {
    guard let snapshot else {
      return .unavailable(reason: "Drawing Run is synchronizing the exact EA-08A plan.")
    }
    if let capabilityID = snapshot.stopCapabilityID, snapshot.activeRunID != nil {
      return .running(
        capabilityID: capabilityID,
        detail: drawingRunPhaseDetail(snapshot.phase)
      )
    }
    if snapshot.activeRunID != nil {
      return .processing(detail: drawingRunPhaseDetail(snapshot.phase))
    }
    if case .failed(_, let recoveryCapabilityID, let detail) =
      snapshot.evidencePersistence
    {
      return .publicationFailed(
        recoveryCapabilityID: recoveryCapabilityID,
        detail: "Evidence append failed. No successful record was published: \(detail)"
      )
    }
    if case .intentPublicationIncomplete(_, let detail) = snapshot.evidencePersistence {
      return .unavailable(reason: "The durable attempt remains unresolved: " + detail)
    }
    if let terminal = snapshot.terminal {
      let detail = drawingRunTerminalDetail(terminal)
      switch snapshot.review {
      case .pinned:
        return .reviewing(runID: terminal.runID, detail: detail)
      case .available:
        return .reviewAvailable(runID: terminal.runID, detail: detail)
      case .livePreview:
        return .terminal(runID: terminal.runID, detail: detail)
      }
    }
    switch snapshot.readiness {
    case .synchronizing:
      return .unavailable(reason: "Checking the current drawing and controller.")
    case .unavailable(let issue):
      return .unavailable(reason: issue.detail)
    case .ready:
      if let previewStatus = drawingDraftSnapshot.preview?.status,
        case .diagnosticOnly(let limitation) = previewStatus {
        return .ready(detail: tipApplicabilityDiagnosticDetail(limitation))
      }
      return .ready(detail: "Ready to draw. Pen Up is established before travel.")
    }
  }

  func drawingRunPhaseDetail(_ phase: PlotterDrawingRunPhase) -> String {
    switch phase {
    case .idle: "Waiting for a reviewed exact plan."
    case .validating: "Revalidating the exact EA-08A plan and current facts."
    case .stagingIntent: "Saving the exact physical attempt before motion."
    case .stagingBaseline: "Saving original baseline images before ink dispatch."
    case .markingInkDispatchPossible: "Recording ink-dispatch intent."
    case .positioningForPostObservation: "Returning Pen Up to the matched observation pose."
    case .normalizingPenUp: "Normalizing Pen Up through RunInterpreter."
    case .positioningForBaseline: "Moving to the exact observation pose."
    case .capturingBaseline: "Capturing the exact pre-drawing frame."
    case .executingPlan: "Executing the checkpointed drawing plan."
    case .capturingPostFrame: "Capturing a newer exact post-drawing frame."
    case .observingInk: "Vision is comparing intended and observed ink."
    case .appendingEvidence: "Appending immutable run evidence before publication."
    case .terminal: "The run has settled."
    }
  }

  private func drawingRunRefusalDetail(_ refusal: PlotterDrawingRunRefusal) -> String {
    refusal.detail ?? "Drawing Run refused \(String(describing: refusal.reason)); remedy: \(String(describing: refusal.remedy))."
  }

  private func drawingRunTerminalDetail(_ terminal: PlotterDrawingRunTerminal) -> String {
    switch terminal.disposition {
    case .refused: "The request was refused before attributable ink evidence."
    case .cancelled: "Operator Stop settled the run. The plan will not be redrawn."
    case .ambiguous: "Controller settlement is ambiguous. The plan will not be redrawn."
    case .possibleInk: "The run may contain ink. The plan will not be redrawn."
    case .nonAttributable:
      "Controller execution completed outside tip applicability; no camera/ink attribution was claimed."
    case .visionRejected: "Controller execution completed; Vision evidence was rejected."
    case .succeeded: "Controller execution and planned-ink evidence were durably published."
    case .publicationIncomplete:
      "The terminal fact is retained, but successful publication is incomplete."
    }
  }

  private func tipApplicabilityDiagnosticDetail(
    _ limitation: TipApplicabilityEvidenceLimitation
  ) -> String {
    let bounds = limitation.recordedApplicabilityRectangle
    let point = limitation.firstOutsideMachinePoint
    return String(
      format:
        "Runnable inside the accepted Drawing Boundary, but point X %.3f Y %.3f is outside tip-registration %@ applicability X %.3f…%.3f Y %.3f…%.3f. Preview remains diagnostic; this run cannot produce attributable camera/ink evidence.",
      point.x,
      point.y,
      limitation.registrationRevisionID.rawValue.uuidString,
      bounds.minX,
      bounds.maxX,
      bounds.minY,
      bounds.maxY
    )
  }

  private func drawingStudioTargetPreview(
    from preview: PlotterDrawingDraftPreview?
  ) -> DrawingStudioTargetPreview? {
    guard let preview else { return nil }
    let status: DrawingStudioTargetPreviewStatus = switch preview.status {
    case .unavailable(_, let remedy): .unavailable(reason: remedy)
    case .outsideDrawableRegion(let reason): .outsideDrawableRegion(reason: reason)
    case .diagnosticOnly(let limitation):
      .diagnosticOnly(reason: tipApplicabilityDiagnosticDetail(limitation))
    case .ready: .ready
    }
    return DrawingStudioTargetPreview(
      provenance: ExactFrameOverlayProvenance(preview.displayedFrame),
      strokes: preview.strokes,
      bounds: preview.bounds,
      programContentHash: preview.programContentHash.description,
      executionPlanContentHash: preview.planRevisionID?.description,
      status: status
    )
  }

  func currentDrawingRunFacts(
    for environment: PlotterEnvironment
  ) async -> PlotterDrawingRunExternalFacts {
    guard environment == manualMotionEnvironment else {
      return PlotterDrawingRunExternalFacts(
        environment: environment,
        interactiveLearningIsComplete: false,
        plan: nil,
        paperCoverageIsCurrent: false,
        displayedFrame: nil,
        interpreter: nil,
        penActuationProfile: currentPenActuationProfile
      )
    }
    let capturedFacts = drawingDraftExternalFacts
    let draft = await drawingDraftRuntime.synchronize(capturedFacts)
    installDrawingDraftSnapshot(draft)
    // Projection consumes the existing published controller truth. Drawing
    // Run start/pre-effect admission obtains its own fresh lower snapshot;
    // semantic Learning updates must not poll the controller for this cache.
    let interpreter = environment == .live ? machineSnapshot : nil
    let runPlan: PlotterDrawingRunPlan?
    if let program = draft.program,
      let plan = draft.plan,
      let paperCoverage = draft.paperCoverageObservation,
      draft.paperCoverageIsCurrent,
      let registration = capturedFacts.registration
    {
      runPlan = PlotterDrawingRunPlan(
        draftRevision: draft.projection.draftRevision,
        program: program,
        placementID: draft.placementID,
        plan: plan,
        evidenceRole: draft.evidenceRole,
        paperCoverage: paperCoverage,
        registration: registration,
        candidate: portraitStudio.projectedReference(for: program),
        materialProfile: drawingMaterials.activeRecord?.profile,
        materialApplicability: drawingMaterials.activeRecord?.applicability,
        paperStock: materialPaperStock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : materialPaperStock
      )
    } else {
      runPlan = nil
    }
    return PlotterDrawingRunExternalFacts(
      environment: environment,
      interactiveLearningIsComplete: interactiveLearningIsComplete,
      plan: runPlan,
      paperCoverageIsCurrent: draft.paperCoverageIsCurrent,
      displayedFrame: capturedFacts.displayedFrame,
      interpreter: interpreter,
      penActuationProfile: currentPenActuationProfile,
      physicalPositionUnavailableReason: retainedPoseApplicabilityRefusal,
      acceptedMovementBounds: try? SparseTipBatchMarkPlan.boundaryEnvelope(for: acceptedBoundaryAggregates)
    )
  }

  @discardableResult
  func submitDrawingRun(_ submission: PlotterDrawingRunSubmission) async -> PlotterDrawingRunSubmissionResult? {
    guard applicationAdmissionIsOpen else { return nil }
    let result = await drawingRunRuntime.submit(submission)
    guard applicationAdmissionIsOpen else { return result }
    installDrawingRunSnapshot(result.snapshot)
    guard case .applied = result.disposition,
      case .beginNewRun = submission.intent
    else { return result }
    overlayResultChannels.clearWorkflow(source: frameMode, owner: .drawingStudio)
    let synchronized = await drawingDraftRuntime.synchronize(drawingDraftExternalFacts)
    installDrawingDraftSnapshot(synchronized)
    await performDrawingDraftSubmission(
      PlotterDrawingDraftSubmission(
        projection: synchronized.projection,
        intent: .beginNewPlan
      )
    )
    await synchronizeDrawingRunProjection()
    return result
  }

  private func synchronizeDrawingRunProjection() async {
    let snapshot = await drawingRunRuntime.synchronize(
      environment: manualMotionEnvironment
    )
    installDrawingRunSnapshot(snapshot)
  }

  func installDrawingRunSnapshot(_ snapshot: PlotterDrawingRunSnapshot) {
    let environment = snapshot.projection.environment
    let revision = snapshot.projection.runRevision
    // Awaited submissions and the buffered stream share this publication
    // owner. A queued earlier phase must not replace the returned terminal.
    // Equal revisions can carry fresh progress and remain admissible.
    if let seen = drawingRunSeenPublications[environment] {
      guard revision >= seen.revision else { return }
      if revision == seen.revision, let activeRunID = seen.activeRunID,
        snapshot.activeRunID == activeRunID, let previous = seen.progress {
        guard let progress = snapshot.progress,
          progress.isExecutionFrontier(atLeastAsAdvancedAs: previous)
        else { return }
      }
    }
    drawingRunSeenPublications[environment] = (revision, snapshot.activeRunID, snapshot.progress)
    guard environment == manualMotionEnvironment else { return }
    guard snapshot != drawingRunSnapshot else { return }
    let previousPersistence = drawingRunSnapshot?.evidencePersistence
    drawingRunSnapshot = snapshot
    if let post = snapshot.postFrame,
      let observation = snapshot.presentationObservation
    {
      overlayResultChannels.publishWorkflow(
        OverlayChannelResult(displayedFrame: post, overlays: observation.overlays),
        source: frameMode,
        owner: .drawingStudio
      )
    }
    if case .persisted(_, let revision) = snapshot.evidencePersistence,
      snapshot.evidencePersistence != previousPersistence,
      revision > drawingEvidenceArchive.revision, applicationAdmissionIsOpen {
      let previousReload = drawingEvidenceReloadTask
      previousReload?.cancel()
      drawingEvidenceReloadTask = Task { [weak self, drawingEvidencePort] in
        await previousReload?.value
        guard !Task.isCancelled, let self, self.applicationAdmissionIsOpen else { return }
        switch await drawingEvidencePort.load() {
        case .loaded(let archive):
          guard !Task.isCancelled, self.applicationAdmissionIsOpen,
            archive != self.drawingEvidenceArchive else { return }
          self.drawingEvidenceArchive = archive
          self.drawingEvidenceError = nil
          self.scheduleDrawingDraftSynchronization()
        case .absent:
          break
        case .rejected(let rejection):
          guard !Task.isCancelled, self.applicationAdmissionIsOpen else { return }
          self.drawingEvidenceError = "Saved drawing evidence was rejected: \(rejection)"
        }
      }
    }
    invalidateActionSurfacePresentation()
  }

  private func plannedDrawingObservationRegion(
    _ intended: [Polyline<CameraPixelSpace>],
    frameWidth: Int,
    frameHeight: Int
  ) -> PixelRect {
    let points = intended.flatMap(\.points)
    let margin = 8
    let minX = max(0, Int(floor(points.map(\.x).min() ?? 0)) - margin)
    let minY = max(0, Int(floor(points.map(\.y).min() ?? 0)) - margin)
    let maxX = min(frameWidth - 1, Int(ceil(points.map(\.x).max() ?? 0)) + margin)
    let maxY = min(frameHeight - 1, Int(ceil(points.map(\.y).max() ?? 0)) + margin)
    return PixelRect(
      x: minX,
      y: minY,
      width: max(1, maxX - minX + 1),
      height: max(1, maxY - minY + 1)
    )
  }

  var currentDrawableMachineRegion: DrawableMachineRegion? {
    guard tipCameraRegistration != nil else { return nil }
    return try? drawableMachineRegion()
  }

  private var currentDrawingBorderBounds: AxisAlignedBounds<MachineSpace>? {
    guard let registration = tipCameraRegistration else { return nil }
    return try? drawingBorderBounds(for: registration,
      acceptedBoundary: try? SparseTipBatchMarkPlan.boundaryEnvelope(for: acceptedBoundaryAggregates))
  }

  private func drawableMachineRegion() throws -> DrawableMachineRegion {
    try DrawableMachineRegion(
      bounds: SparseTipBatchMarkPlan.boundaryEnvelope(for: acceptedBoundaryAggregates)
    )
  }

  private func drawingBorderBounds(
    for registration: TipCameraRegistration,
    acceptedBoundary: AxisAlignedBounds<MachineSpace>?
  ) throws -> AxisAlignedBounds<MachineSpace> {
    if registration.estimatorRevision == SparseTipCircularMarkPlan.registrationEstimatorRevision {
      guard let acceptedBoundary else {
        throw CurrentCameraCalibrationPlanningError.incompleteBoundaryEnvelope
      }
      return try SparseTipBatchMarkPlan.drawingBorderBounds(for: acceptedBoundary)
    }
    if registration.estimatorRevision
      == SparseTipCircularMarkPlan.insetFiveCircleRegistrationEstimatorRevision
    {
      return try SparseTipBatchMarkPlan.legacyInsetFiveCirclePictureRectangle(
        framedByMarkCenters: registration.applicabilityRectangle
      )
    }
    return registration.applicabilityRectangle
  }

  private func learnedDrawingOverlays(
    on displayedFrame: DisplayedFrame
  ) -> [CameraOverlayMeasurement] {
    let savedCandidate = savedLearningApplicationCandidate?.checkpoint
    let context: (
      registration: TipCameraRegistration,
      acceptedBoundaryAggregates: [BoundaryDirection: BoundarySideAggregate],
      isProposed: Bool
    )?
    if let proposedTipCameraRegistration {
      context = (proposedTipCameraRegistration, acceptedBoundaryAggregates, true)
    } else if let tipCameraRegistration {
      context = (tipCameraRegistration, acceptedBoundaryAggregates, false)
    } else if let savedCandidate,
      let registration = savedCandidate.tipCalibration?.registration
    {
      context = (
        registration,
        Dictionary(
          uniqueKeysWithValues: (savedCandidate.machineArtifacts?.acceptedBoundaryAggregates ?? [])
            .map { ($0.direction, $0) }
        ),
        false
      )
    } else {
      context = nil
    }
    guard let context else { return [] }
    let registration = context.registration
    guard
      displayedFrame.source == registration.applicability.opticalConfiguration.source,
      displayedFrame.frame.width == registration.applicability.opticalConfiguration.width,
      displayedFrame.frame.height == registration.applicability.opticalConfiguration.height,
      displayedFrame.frame.pixelFormat
        == registration.applicability.opticalConfiguration.pixelFormat
    else { return [] }

    let boundary: AxisAlignedBounds<MachineSpace>? =
      if context.acceptedBoundaryAggregates.values.allSatisfy({
        $0.coordinateRevision == registration.applicability.machineCoordinateFrame.rawValue
      }) {
        try? SparseTipBatchMarkPlan.boundaryEnvelope(for: context.acceptedBoundaryAggregates)
      } else {
        nil
      }
    guard let bounds = try? drawingBorderBounds(
      for: registration,
      acceptedBoundary: boundary
    ) else { return [] }
    var overlays: [CameraOverlayMeasurement] = []
    if let boundary,
      let boundaryOutline = try? closedMachineRectanglePositions(bounds: boundary),
      let projectedBoundary = try? Polyline<CameraPixelSpace>(
        points: boundaryOutline.map {
          try registration.diagnosticProjection(at: $0.point).cameraPoint
        }
      )
    {
      overlays.append(
        CameraOverlayMeasurement(
          frameID: displayedFrame.frame.id,
          cameraConfigurationID: displayedFrame.frame.cameraConfigurationID,
          geometry: .polyline(projectedBoundary),
          provenance: CameraMeasurementProvenance(
            kind: .acceptedBoundary,
            source: .inferred,
            algorithmRevision: "accepted-drawing-boundary-tip-extrapolation-v2"
          )
        )
      )
    }
    if let drawingBorder = try? DrawingBorderPlan(bounds: bounds),
      let projectedBorder = try? Polyline<CameraPixelSpace>(
        points: drawingBorder.pathPositions.map { try registration.tipPixel(at: $0.point) }
      )
    {
      overlays.append(
        CameraOverlayMeasurement(
          frameID: displayedFrame.frame.id,
          cameraConfigurationID: displayedFrame.frame.cameraConfigurationID,
          geometry: .polyline(projectedBorder),
          provenance: CameraMeasurementProvenance(
            kind: context.isProposed ? .intendedPath : .drawingBorder,
            source: context.isProposed ? .planned : .inferred,
            algorithmRevision: context.isProposed
              ? "proposed-tip-drawing-border-preview-v2"
              : "accepted-tip-drawing-border-region-v3"
          )
        )
      )
    }
    if let savedCandidate,
      let machineCamera = savedCandidate.machineCamera?.registration,
      let position = try? currentMachinePosition(),
      let capPoint = try? machineCamera.fit.cameraPoint(from: position.point)
    {
      overlays.append(
        CameraOverlayMeasurement(
          frameID: displayedFrame.frame.id,
          cameraConfigurationID: displayedFrame.frame.cameraConfigurationID,
          geometry: .point(capPoint),
          provenance: CameraMeasurementProvenance(
            kind: .penCap,
            source: .diagnostic,
            algorithmRevision: "saved-machine-cap-projection-v1"
          )
        )
      )
    }
    if let savedCandidate {
      for record in drawingEvidenceArchive.records
      where Self.savedDrawingEvidenceIsCurrentForPresentation(
        record.paper,
        savedIdentity: savedCandidate.semanticIdentity,
        exactPointSelectionIsActive: pointSelectionRequest != nil
      ) {
        // Immutable records retain their original machine-coordinate frame.
        // A current translated map must never reinterpret those old numbers.
        guard record.tipCalibration.applicability == registration.applicability,
          let plan = record.plan.executionPlan else { continue }
        for stroke in plan.strokes {
          guard let projected = try? Polyline(
            points: stroke.path.points.map {
              try registration.diagnosticProjection(at: $0).cameraPoint
            }
          ) else { continue }
          overlays.append(
            CameraOverlayMeasurement(
              frameID: displayedFrame.frame.id,
              cameraConfigurationID: displayedFrame.frame.cameraConfigurationID,
              geometry: .polyline(projected),
              provenance: CameraMeasurementProvenance(
                kind: .intendedPath,
                source: .diagnostic,
                algorithmRevision: "saved-drawing-plan-projection-v1"
              )
            )
          )
        }
      }
    }
    if let coverage = drawingDraftSnapshot.paperCoverageDisplay,
      coverage.source == displayedFrame.source,
      coverage.frame == ExactFrameProvenance(frame: displayedFrame.frame),
      let polygon = try? Polyline(points: coverage.polygon + [coverage.polygon[0]])
    {
      overlays.append(
        CameraOverlayMeasurement(
          frameID: displayedFrame.frame.id,
          cameraConfigurationID: displayedFrame.frame.cameraConfigurationID,
          geometry: .polyline(polygon),
          provenance: CameraMeasurementProvenance(
            kind: .paperCoverage,
            source: .diagnostic,
            algorithmRevision: "drawing-draft-paper-coverage-exact-frame-v1"
          )
        )
      )
    }
    return overlays
  }

  nonisolated static func savedDrawingEvidenceIsCurrentForPresentation(
    _ recordPaper: PaperRevisionContext,
    savedIdentity: LearningPathSemanticIdentity,
    exactPointSelectionIsActive: Bool
  ) -> Bool {
    !exactPointSelectionIsActive
      && recordPaper.instance == savedIdentity.paperInstance
      && recordPaper.contactPlane == savedIdentity.paperContactPlane
  }

  var completedComparisonReviewPresentation: CompletedComparisonReviewPresentation {
    guard !drawingRunIsActive,
      completedDrawingComparisonReviewIsAvailable,
      let frame = borderValidationSnapshot.postFrame
    else {
      return .unavailable
    }
    let provenance = ExactFrameOverlayProvenance(frame)
    return CompletedComparisonReviewPresentation(
      state: completedDrawingComparisonReviewIsPinned
        ? .reviewingExactFrame(provenance)
        : .available(provenance),
      drawingDraftProjection: borderValidationSnapshot.assessment == .predictionObserved
        ? drawingDraftSnapshot.projection : nil
    )
  }

  var completedDrawingComparisonReviewIsAvailable: Bool {
    borderValidationSnapshot.assessment != nil
      && borderValidationSnapshot.postFrame != nil
      && borderValidationSnapshot.inkObservation != nil
  }

  var completedDrawingComparisonReviewIsPinned: Bool {
    borderValidationSnapshot.comparisonReviewIsPinned
  }

  func submitCompletedComparisonReview(_ intent: CompletedComparisonReviewIntent) {
    guard applicationAdmissionIsOpen else { return }
    switch intent {
    case .reviewComparison:
      Task { @MainActor [weak self] in
        await self?.reviewCompletedDrawingComparison()
      }
    case .resumeLivePreview:
      resumeLivePreviewAfterDrawingComparison()
    }
  }

  func reviewCompletedDrawingComparison() async {
    guard applicationAdmissionIsOpen,
      completedDrawingComparisonReviewIsAvailable,
      !drawingRunIsActive
    else { return }
    if drawingTargetIsVisible {
      await performDrawingDraftSubmission(
        PlotterDrawingDraftSubmission(
          projection: drawingDraftSnapshot.projection,
          intent: .hideTarget
        )
      )
      guard !drawingTargetIsVisible else { return }
    }
    let result = borderValidationRuntime.apply(.setComparisonReviewPinned(true))
    if case .refused(let reason, let remedy) = result.disposition {
      drawingEvidenceError = "\(reason) Remedy: \(remedy)"
    }
  }

  func resumeLivePreviewAfterDrawingComparison() {
    let result = borderValidationRuntime.apply(.setComparisonReviewPinned(false))
    if case .refused(let reason, let remedy) = result.disposition {
      drawingEvidenceError = "\(reason) Remedy: \(remedy)"
    }
  }

  private func borderValidationPredictionOverlays(
    on displayedFrame: DisplayedFrame
  ) -> [CameraOverlayMeasurement] {
    guard borderValidationSnapshot.inkObservation == nil,
      let registration = tipCameraRegistration,
      displayedFrame.source == registration.applicability.opticalConfiguration.source,
      displayedFrame.frame.width == registration.applicability.opticalConfiguration.width,
      displayedFrame.frame.height == registration.applicability.opticalConfiguration.height,
      displayedFrame.frame.pixelFormat
        == registration.applicability.opticalConfiguration.pixelFormat,
      let currentRevision = learningArtifactGraph.currentRevision(for: .tipCameraRegistration)?.id,
      currentRevision == registration.acceptedRevisionID,
      borderValidationSnapshot.tipRegistrationRevisionID == currentRevision,
      let plan = borderValidationSnapshot.drawingBorderPlan,
      let path = plan.strokes.first?.path,
      let predictedBorder = try? Polyline(
        points: path.points.map { try registration.tipPixel(at: $0) }
      )
    else { return [] }
    return [
      CameraOverlayMeasurement(
        frameID: displayedFrame.frame.id,
        cameraConfigurationID: displayedFrame.frame.cameraConfigurationID,
        geometry: .polyline(predictedBorder),
        provenance: CameraMeasurementProvenance(
          kind: .intendedPath,
          source: .planned,
          algorithmRevision: "tip-registration-drawing-border-preview-v1"
        )
      )
    ]
  }

  func overlayStatus(for overlay: UserSceneOverlay) -> OverlayLayerStatus {
    if frameMode == .live,
      overlayPreferenceState.enabled.contains(overlay),
      livePenCapAppearanceSelection == nil
    {
      return OverlayLayerStatus(
        state: .unavailable,
        message: persistedPenCapAppearanceLoadState.unavailableMessage,
        provenance: nil
      )
    }
    let surfaceFrame = frozenPointSelectionFrame ?? displayedFrame
    return OverlayPresentationComposer.compose(
      preference: overlayPreferenceState,
      channels: overlayResultChannels,
      displayedFrame: surfaceFrame,
      sceneState: visionAnalysisSnapshot,
      sceneIsAvailable: sceneOverlayIsAvailable,
      workflowVisionIsExclusive: exactWorkflowVisionOwner != nil
    ).statuses[overlay]!
  }

  private var sceneOverlayIsAvailable: Bool {
    guard frameMode == .live, case .running = cameraSnapshot?.state else { return false }
    return true
  }

  private func learnedBoundsPresentationRegion(_ frame: DisplayedFrame) -> PixelRect? {
    guard let registration = machineCameraRegistration,
      let negativeX = acceptedBoundaryAggregates[.negativeX]?.estimateMM,
      let positiveX = acceptedBoundaryAggregates[.positiveX]?.estimateMM,
      let negativeY = acceptedBoundaryAggregates[.negativeY]?.estimateMM,
      let positiveY = acceptedBoundaryAggregates[.positiveY]?.estimateMM
    else { return nil }
    let corners = [
      try? Point2<MachineSpace>(x: negativeX, y: negativeY),
      try? Point2<MachineSpace>(x: negativeX, y: positiveY),
      try? Point2<MachineSpace>(x: positiveX, y: negativeY),
      try? Point2<MachineSpace>(x: positiveX, y: positiveY),
    ].compactMap { $0 }.compactMap { try? registration.fit.cameraPoint(from: $0) }
    guard corners.count == 4 else { return nil }
    let minX = Int(floor(corners.map(\.x).min()!))
    let minY = Int(floor(corners.map(\.y).min()!))
    let maxX = Int(ceil(corners.map(\.x).max()!))
    let maxY = Int(ceil(corners.map(\.y).max()!))
    return cameraFrameIntersection(
      PixelRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY)),
      frameWidth: frame.frame.width,
      frameHeight: frame.frame.height
    )
  }

  var cameraDevices: [CameraDevice] { cameraSnapshot?.devices ?? [] }
  var selectedCameraID: CameraDeviceID? { cameraSnapshot?.selectedDeviceID }
  var isShutdown: Bool { applicationAdmissionIsClosed }

  var currentCameraCalibrationBusyReason: String? {
    if case .positionRecovery = activeStopTarget {
      return "Position verification owns the camera and controller sample. Use Stop before changing either source."
    }
    return cameraCalibrationRuntimePhase.map {
      "Automatic camera calibration is in progress (\($0.description)). Use Stop during active motion."
    }
  }

  var cameraIsLive: Bool {
    guard frameMode == .live, case .running = cameraSnapshot?.state,
      let latestLiveCameraFrame, case .live(let deviceID) = latestLiveCameraFrame.source,
      deviceID == selectedCameraID
    else { return false }
    if cameraSnapshot?.diagnostics.previewPublicationPaused == true { return true }
    let now = nowNanoseconds()
    guard now >= latestLiveCameraFrame.frame.captureNanoseconds else { return false }
    return now - latestLiveCameraFrame.frame.captureNanoseconds <= 1_000_000_000
  }

  var controllerIsConnected: Bool {
    guard passiveProbeResult?.blockers.isEmpty == true,
      let machine = machineSnapshot?.machine,
      machine.connection == .connected,
      machine.controllerState?.isRecognized == true,
      machine.stickyAmbiguity == nil
    else { return false }
    return true
  }

  /// Immutable controller/session UI contract. All controller controls render
  /// this one value and submit its exact revision/capability-bound requests.
  var controllerSessionProjection: PlotterControllerSessionProjection {
    PlotterControllerSessionRules.project(controllerSessionFacts)
  }

  private var controllerSessionFacts: PlotterControllerSessionFacts {
    let discoveryBusyReason: String? = if let activeDiscoverySequenceID,
      !activePenInteractionNeedsControllerSetup
    {
      "Finish \(DiscoverySequenceCatalog.definition(for: activeDiscoverySequenceID).title) first."
    } else {
      nil
    }
    return PlotterControllerSessionFacts(
      reference: PlotterControllerSessionReference(
        revision: semanticPresentationRevision,
        capabilityID: controllerSessionID
      ),
      environment: frameMode,
      selectedSerialDevice: selectedSerialDevice,
      serialDevices: serialDevices,
      machineSnapshot: machineSnapshot,
      passiveProbe: passiveProbeResult,
      simulatedSnapshot: simulatedLearningSnapshot,
      machineError: machineError,
      admissionClosed: applicationAdmissionIsClosed,
      controllerBusyReason: positionRebasePublicationIsPending
        ? "Wait for the committed position update to publish."
        : paperReplacementInProgressReason ?? currentCameraCalibrationBusyReason,
      discoveryBusyReason: discoveryBusyReason,
      foreignOperationInFlight: axisCalibrationInProgress || passiveProbeInProgress || jogRequestInProgress
        || retainedPenRequestInProgress || jogCancelRequestInProgress
        || borderValidationSnapshot.activeOperationID != nil
        || machineSnapshot?.machine.operationInFlight == true,
      frameModeSwitchInProgress: frameModeSwitchInProgress,
      connectionActionInProgress: controllerConnectionActionInProgress,
      alarmClearInProgress: controllerAlarmClearInProgress,
      motionActionInProgress: motionAuthorizationActionInProgress,
      lowerSessionAvailable: machineSession != nil,
      axisCalibrationProposal: axisCalibrationProposal
    )
  }

  private var rawSessionEstablished: Bool {
    if frameMode == .simulated { return simulatedLearningSnapshot?.session == .connected }
    guard passiveProbeResult?.blockers.isEmpty == true,
      let machine = machineSnapshot?.machine,
      machine.controllerState?.isRecognized == true,
      machine.stickyAmbiguity == nil
    else { return false }
    switch machine.connection {
    case .connected, .moving, .actuatingPen: return true
    case .disconnected, .connecting, .probing, .blocked: return false
    }
  }

  private var sessionEstablished: Bool { controllerSessionProjection.sessionEstablished }
  private var sessionMotionAuthorized: Bool { controllerSessionProjection.motionAuthorized }

  var cameraStateText: String {
    guard frameMode == .live else { return "causal simulated frame" }
    guard let state = cameraSnapshot?.state else { return "not started" }
    return switch state {
    case .stopped: "stopped"
    case .discovering: "discovering"
    case .ready: "ready"
    case .starting: "starting"
    case .running: "running"
    case .interrupted(let reason): "interrupted: \(reason)"
    case .failed(let error): "failed: \(error.actionableDescription)"
    }
  }

  var frameAgeText: String {
    guard let frame = displayedFrame?.frame else { return "no frame" }
    let now = nowNanoseconds()
    guard now >= frame.captureNanoseconds else { return "clock mismatch" }
    return String(format: "%.2f s", Double(now - frame.captureNanoseconds) / 1_000_000_000)
  }

  var captureThroughputText: String {
    let diagnostics = videoVisionDiagnostics?.capture ?? cameraSnapshot?.diagnostics ?? .zero
    let held = diagnostics.previewPublicationPaused
      ? " · preview publication paused by calibration image analysis"
      : ""
    let deliveryLimit: String = switch diagnostics.deliveryLimitOutcome {
    case .notRequested: ""
    case .applied(let rate):
      " · device delivery capped at \(String(format: "%.0f", rate)) FPS"
    case .unapplied(let requested, let reason):
      " · device cap \(String(format: "%.0f", requested)) FPS unapplied (\(reason))"
    }
    return
      "received \(diagnostics.receivedFrameCount) · preview \(diagnostics.previewMaterializedFrameCount) · exact \(diagnostics.exactMaterializedFrameCount) · analysis hashes \(diagnostics.analysisContentHashComputationCount) · exact hashes \(diagnostics.exactContentHashComputationCount) · serialization hashes \(diagnostics.serializationContentHashComputationCount)\(deliveryLimit)\(held)"
  }

  var visionThroughputText: String {
    let snapshot = visionAnalysisSnapshot
    let cadence: String
    switch snapshot.state {
    case .stopped: cadence = "stopped"
    case .running(let value): cadence = "target \(value.rawValue) frames per second"
    }
    guard let diagnostics = videoVisionDiagnostics?.pipeline else {
      return "\(cadence) · diagnostics not refreshed"
    }
    let duration = diagnostics.latestResult.map {
      String(format: "%.1f ms", Double($0.analysisDurationNanoseconds) / 1_000_000)
    } ?? "no timing"
    return "\(cadence) · analyzed \(diagnostics.analyzedFrameCount) · superseded \(diagnostics.supersededFrameCount) · \(duration)"
  }

  var videoAnalysisIsActive: Bool {
    if case .running = visionAnalysisSnapshot.phase.state { return true }
    return false
  }

  var videoAnalysisRegionText: String {
    guard let lock = videoAnalysisRegionLock else {
      return "Full frame · unlocked/default analysis"
    }
    let region = lock.region
    return "x \(region.x), y \(region.y), \(region.width) × \(region.height) px · locked"
  }

  var currentOperationText: String {
    if let intent = manualMotionEpisodeSnapshot?.activeOperation?.intent {
      return switch intent {
      case .jog(let request):
        request.routing == .drawingStroke ? "manual drawing stroke" : "manual jog"
      case .setPen(let request):
        "manual Pen \(request.position == .raised ? "raise" : "lower")"
      }
    }
    if frameMode == .simulated {
      guard let operation = simulatedLearningSnapshot?.currentOperation else {
        return "simulated idle"
      }
      return switch operation.kind {
      case .manualJog: "simulated manual jog"
      case .boundary: "simulated Boundary Discovery motion"
      case .drawing: "simulated drawing stroke"
      }
    }
    guard let operation = machineSnapshot?.currentOperation else { return "none" }
    return switch operation {
    case .idle: "idle"
    case .passiveProbe: "controller inspection"
    case .alarmClear: "clearing controller alarm"
    case .axisCalibration: "applying measured axis calibration"
    case .relativeJog: "relative jog"
    case .boundaryMotion: "Boundary Discovery motion"
    case .drawingStroke: "single drawing stroke"
    case .drawingPlan: "drawing execution plan"
    case .penActuation(let command): "pen \(command.rawValue)"
    }
  }

  var controllerStateText: String {
    if frameMode == .simulated {
      return simulatedLearningSnapshot?.currentOperation == nil
        ? "simulated Idle" : "simulated active"
    }
    return machineSnapshot?.machine.controllerState?.rawValue ?? "unknown"
  }

  var controllerConnectionText: String {
    if frameMode == .simulated {
      return sessionEstablished ? "simulator connected" : "simulator disconnected"
    }
    guard selectedSerialDevice != nil else { return "not selected" }
    if controllerIsConnected { return "connected" }
    guard let machine = machineSnapshot?.machine else { return "not connected" }
    switch machine.connection {
    case .connected:
      return passiveProbeInProgress ? "connecting" : "not connected"
    case .disconnected:
      return "disconnected"
    case .connecting:
      return "connecting"
    case .probing:
      return "probing"
    case .moving:
      return "command in flight"
    case .actuatingPen:
      return "pen command in flight"
    case .blocked:
      return "blocked"
    }
  }

  /// grblHAL status proves that its USB-side controller is responsive. The
  /// BlackBox does not report whether motor supply current is present, so the
  /// UI must not turn a responsive serial link into a powered-motors claim.
  var motorPowerText: String {
    if frameMode == .simulated { return "not present — nonphysical simulator" }
    guard machineSnapshot?.machine.connection == .connected else { return "unverified" }
    return "not reported by controller"
  }

  var motionPermissionText: String {
    manualMotionRuntimePresentation.jogControlsUnavailableReason == nil
      ? "request eligible" : "unavailable"
  }

  var motionGuardIsActive: Bool {
    sessionMotionAuthorized
  }

  var motionGuardStateText: String {
    motionGuardIsActive ? "active" : "inactive"
  }

  private var activePenInteractionNeedsControllerSetup: Bool {
    guard !rawSessionEstablished,
      activeDiscoverySequenceID == .penInteraction,
      let step = discoveryTransactions[.penInteraction]?.currentStep
    else { return false }
    if case .awaitPhysicalPenConfirmation = step.action { return true }
    return false
  }

  var controllerAlarmEvidenceText: String? {
    guard frameMode == .live else { return nil }
    return machineSnapshot?.machine.blockers.compactMap { blocker in
      if case .controllerAlarm(let detail) = blocker { return detail }
      return nil
    }.first
  }

  var controllerAttentionText: String? {
    if let machineError { return machineError }
    if let blocker = machineSnapshot?.machine.blockers.first {
      return machineBlockerLabel(blocker)
    }
    guard let outcome = machineSnapshot?.machine.lastAlarmClearOutcome else { return nil }
    switch outcome {
    case .acknowledged:
      return nil
    case .refused, .controllerRejected, .unconfirmed:
      return outcome.actionableDescription
    }
  }

  var controllerLimitInputsText: String {
    guard frameMode == .live, let machine = machineSnapshot?.machine else {
      return "unknown — no LIVE controller sample"
    }
    switch machine.controllerAlarmClearReadiness {
    case .armed:
      return "clear — sampled Pn has no X/Y/Z"
    case .blockedByAxisLimit(let pins):
      return "asserted — Pn:\(pins)"
    case .limitStateUnknown:
      return "unknown — Connect to resample"
    case .unavailable:
      guard let status = machine.lastProbe?.latestStatusReport else {
        return "unknown — Connect to sample"
      }
      return status.controllerPins.hasAxisLimitAsserted
        ? "asserted — Pn:\(status.controllerPins.rawValue)"
        : "clear — sampled Pn has no X/Y/Z"
    }
  }

  var controllerAlarmUnlockReadinessText: String {
    guard frameMode == .live, let readiness = machineSnapshot?.machine.controllerAlarmClearReadiness
    else { return "not armed — no LIVE controller" }
    switch readiness {
    case .armed:
      return "armed — manual clear available"
    case .blockedByAxisLimit(let pins):
      return "blocked — Pn:\(pins) is physically asserted"
    case .limitStateUnknown:
      return "not armed — limit inputs unknown"
    case .unavailable:
      return "not armed — no current alarm"
    }
  }

  private var observationSourceChangeUnavailableReason: String? {
    if positionRebasePublicationIsPending { return "Wait for the committed position update to publish." }
    if let reason = paperReplacementInProgressReason { return reason }
    if observationRuntime == nil {
      return "The retained observation runtime is unavailable."
    }
    if let reason = currentCameraCalibrationBusyReason { return reason }
    if frameModeSwitchInProgress { return "A frame source switch is already in progress." }
    if activeExerciseAttemptOwnerID != nil {
      return "Finish or Cancel the active Learning Path attempt before changing frame source."
    }
    if activeDiscoverySequenceID != nil {
      return "Finish the active Plotter Calibration attempt first."
    }
    if borderValidationSnapshot.activeOperationID != nil {
      return "Wait for the current learning action before changing frame source."
    }
    if axisCalibrationInProgress || passiveProbeInProgress || jogRequestInProgress || retainedPenRequestInProgress
      || jogCancelRequestInProgress || machineSnapshot?.machine.operationInFlight == true
    {
      return "Wait for the current controller operation before changing frame source."
    }
    return nil
  }

  var activeDiscoverySequenceID: DiscoverySequenceID? {
    discoveryTransactions.first { _, transaction in
      switch transaction.state {
      case .active, .cancelling: true
      case .notStarted, .succeeded, .failed, .cancelled: false
      }
    }?.key
  }

  var penInteractionCompleted: Bool {
    // Accepted calibration survives a restart and ordinary Pen Down commands.
    // Current pen pose belongs to execution settlement, not Learning progress.
    learningArtifactGraph.currentRevision(for: .penInteraction) != nil
  }

  var relevantBoundaryObservationCount: Int {
    BoundaryDirection.allCases.filter {
      learningArtifactGraph.currentRevision(for: .boundarySideAggregate($0)) != nil
    }.count
  }

  var humanGuidedDiscoveryCurrentStep: HumanGuidedDiscoveryStep {
    switch learningPresentationBase().currentItemID {
    case .humanGuidedDiscovery(let step): step
    case .stage(.humanGuidedDiscovery): .penInteraction
    case .stage(.borderValidations), .borderValidation:
      .calibratePenContactFromSparseMarks
    }
  }

  var currentLearningPathItemID: LearningPathItemID {
    learningPresentationBase().currentItemID
  }

  var learningPathItemPresentations: [LearningPathItemPresentation] {
    learningPresentationBase().currentProjection.items
  }

  var resetAllLearningPlan: LearningVacatePlan? {
    learningPresentationBase().snapshot.reset.resetAllPlan
  }

  func learningVacatePlan(from itemID: LearningPathItemID) -> LearningVacatePlan? {
    guard let anchor = itemID.learningRewindAnchor else { return nil }
    return learningPresentationBase().snapshot.reset.plansByAnchor[anchor]
  }

  private var artifactResetLowerOwnerBlocker: String? {
    if let boundary = currentBoundarySnapshot?.projection {
      if boundary.publicationRecoveryCapabilityID != nil {
        return "Boundary publication is incomplete. Retry its exact publication before resetting Learning."
      }
      if boundary.resetCapabilityID != nil {
        return "Wait for the exact Boundary reset transaction to commit or abort."
      }
      if case .needsAttention(let detail) = boundary.phase {
        return "Resolve the retained Boundary terminal truth before resetting Learning: \(detail)"
      }
    }
    if let learningStickyAmbiguityReason {
      return
        "Resolve the sticky motion ambiguity before resetting learning: \(learningStickyAmbiguityReason)"
    }
    return nil
  }

  private var artifactResetAdmissionFacts: PlotterArtifactResetAdmissionFacts {
    PlotterArtifactResetAdmissionFacts(
      environment: manualMotionEnvironment,
      possibleInkBlocked: retainedStopRegistration?.possibleInkLocation != nil
        || borderValidationSnapshot.executionState == .possibleInk,
      activeStopBlocked: activeStopTarget != nil
        || borderValidationSnapshot.activeOperationID != nil,
      motionSettlementBlocked: axisCalibrationInProgress || passiveProbeInProgress || jogRequestInProgress
        || retainedPenRequestInProgress || jogCancelRequestInProgress
        || machineSnapshot?.machine.operationInFlight == true || admittedApplicationEffects.count > 0,
      lowerOwnerBlocker: artifactResetLowerOwnerBlocker
    )
  }

  var artifactResetUnavailableReason: String? {
    artifactResetRuntime.resetAdmissionRefusal(facts: artifactResetAdmissionFacts)
  }

  @discardableResult
  func performLearningVacate(_ plan: LearningVacatePlan) async -> Bool {
    guard applicationAdmissionIsOpen else { return false }
    return await submitArtifactReset(plan)
  }

  /// Cancels and settles only Learning-owned work before clearing the selected
  /// source's complete Learning authority. Independent manual controller work
  /// is neither cancelled nor used as a reset gate.
  @discardableResult
  func submitResetAllLearning(_ previewPlan: LearningVacatePlan) async -> Bool {
    guard applicationAdmissionIsOpen,
      previewPlan.scope == .all,
      previewPlan.source == (frameMode == .live ? .live : .simulated)
    else {
      learningAuthorityError =
        "Reset All Learning no longer matches the current Learning source. Review it and try again."
      return false
    }

    return await submitArtifactReset(previewPlan)
  }

  private func submitArtifactReset(_ plan: LearningVacatePlan) async -> Bool {
    let priorLearningAuthorityError = learningAuthorityError
    learningAuthorityError = nil
    let accepted = await artifactResetRuntime.submit(
      .reset(artifactResetPlan(plan)),
      facts: artifactResetAdmissionFacts
    )
    if !accepted {
      learningAuthorityError =
        artifactResetRuntime.snapshot().phase.detail ?? priorLearningAuthorityError
    }
    markSemanticPresentationChanged()
    return accepted
  }

  private func cancelAndSettleLearningForReset() async -> Bool {
    let learningTask = activeLearningActionTask
    learningTask?.task.cancel()

    await cameraCalibrationRuntime.cancelActiveOperation()

    if let selectionID = pointSelectionEpisodeProjection.exactPointSelection.request?.id {
      await pointSelectionRuntime.cancelContinuation(selectionID: selectionID)
    }
    if let ownerID = activeExerciseAttemptOwnerID {
      await cancelExerciseAttempt(ownerID)
    } else if let operation = retainedStopRegistration {
      await cancelAndSettleStoppableOperation(operation, intent: .cancelAttempt)
    }
    let boundarySettled = await cancelAndSettleBoundaryForReset()
    _ = await learningTask?.task.value
    if activeLearningActionTask?.transitionID == learningTask?.transitionID {
      activeLearningActionTask = nil
    }
    guard boundarySettled else { return false }
    let learningStopStillActive = activeStopTarget != nil
    guard activeExerciseAttemptID == nil,
      activeDiscoverySequenceID == nil,
      borderValidationSnapshot.activeOperationID == nil,
      cameraCalibrationRuntimePhase == nil,
      !learningStopStillActive
    else {
      learningAuthorityError =
        "The active Learning operation did not settle, so no Learning state was reset."
      return false
    }
    return true
  }

  private func applyLearningVacateEffect(_ plan: LearningVacatePlan) async -> Bool {
    let rootKinds = Set(
      learningArtifactGraph.revisions.compactMap { revision -> LearningArtifactKind? in
        guard plan.expectedCurrentRevisionIDs.contains(revision.id), revision.state == .current
        else { return nil }
        return revision.kind
      }
    )
    var graph = learningArtifactGraph
    let invalidation = graph.invalidateCurrentRevisions(rootKinds: rootKinds)
    learningArtifactGraph = graph
    applyArtifactInvalidations(invalidation.allInvalidatedRevisionIDs)

    switch plan.anchor {
    case .humanGuidedDiscovery(.penInteraction):
      await clearPenLearningForRewind()
      clearBoundaryLearningForRewind()
      clearCalibrationLearningForRewind()
      clearDrawingLearningForRewind(from: .chooseDrawingBorderPlan)
      if plan.scope == .all {
        controllerPoseApplicability = .currentSession
      }
    case .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering):
      clearBoundaryLearningForRewind()
      controllerPoseApplicability = .currentSession
      clearCalibrationLearningForRewind()
      clearDrawingLearningForRewind(from: .chooseDrawingBorderPlan)
    case .humanGuidedDiscovery(.calibrateCameraAndVisibleCap):
      clearCalibrationLearningForRewind(from: .calibrateCameraAndVisibleCap)
      clearDrawingLearningForRewind(from: .chooseDrawingBorderPlan)
    case .humanGuidedDiscovery(.calibratePenContactFromSparseMarks):
      clearCalibrationLearningForRewind(from: .calibratePenContactFromSparseMarks)
      clearDrawingLearningForRewind(from: .chooseDrawingBorderPlan)
    case .borderValidation(let step):
      clearDrawingLearningForRewind(from: step)
    case .stage:
      learningAuthorityError = "The requested Learning Path row is not a rewind anchor."
      return false
    }

    // Every supported rewind removes the completed Border suffix, just as the
    // persisted Learning prefix does. Retaining its active checkpoint could
    // reintroduce the old registration after a geometry change.
    activeStageFourCheckpoint = nil
    currentEnvironmentState.exerciseAttempt.finish()
    restartableExerciseItemID = nil
    explorationError = nil
    learningAuthorityError = nil

    if plan.scope == .all {
      activeMachineArtifactCheckpoint = nil
      activeMachineCameraCheckpoint = nil
      acceptedArtifactCheckpointStatus = .cleared
      recoverableTipCalibrationCheckpoint = nil
      activeStageFourCheckpoint = nil
    } else {
      if plan.removesDurableMachineCheckpoint {
        activeMachineArtifactCheckpoint = nil
        activeMachineCameraCheckpoint = nil
        acceptedArtifactCheckpointStatus = .cleared
      }
      if plan.removesDurableTipCheckpoint {
        recoverableTipCalibrationCheckpoint = nil
      }
    }
    return true
  }

  private enum PersistedLearningPrefix {
    case unchanged
    case cleared
    case saved(AcceptedLearningPathCheckpoint)
  }

  private func persistLearningPathPrefixBeforeVacate(
    _ plan: LearningVacatePlan,
    axisCalibration: ControllerAxisCalibrationProposal? = nil
  ) -> PersistedLearningPrefix? {
    guard frameMode == .live, let actions = activeStatePersistencePort else {
      return .unchanged
    }
    do {
      if plan.anchor == .humanGuidedDiscovery(.penInteraction) {
        try actions.clearAcceptedLearningPathCheckpoint()
        return .cleared
      }

      let order = LearningPathItemID.learningExerciseOrder
      let anchorIndex = order.firstIndex(of: plan.anchor)!
      let boundaryIndex = order.firstIndex(
        of: .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
      )!
      let cameraIndex = order.firstIndex(
        of: .humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
      )!
      let tipIndex = order.firstIndex(
        of: .humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
      )!
      let identity = axisCalibration.map {
        AxisMetricLearningTransition.replacingGeometry(in: currentLearningPathSemanticIdentity,
          with: $0.proposedMachineGeometry)
      } ?? currentLearningPathSemanticIdentity
      let checkpoint = try AcceptedLearningPathCheckpoint(
        semanticIdentity: identity,
        penInteraction: currentAcceptedPenInteractionCheckpoint(),
        machineArtifacts: anchorIndex > boundaryIndex
          ? activeMachineArtifactCheckpoint : nil,
        machineCamera: anchorIndex > cameraIndex
          ? currentAcceptedMachineCameraCheckpoint() ?? activeMachineCameraCheckpoint : nil,
        tipCalibration: anchorIndex > tipIndex
          ? acceptedLearningPathCheckpoint?.tipCalibration
            ?? recoverableTipCalibrationCheckpoint : nil,
        stageFour: nil
      )
      if let proposal = axisCalibration {
        guard proposal.oldMachineGeometry == machineGeometryIdentity else {
          throw AxisMetricLearningTransitionError.staleProposal
        }
        let previous = actions.loadAcceptedLearningPathCheckpoint()
        try actions.saveAcceptedLearningPathCheckpoint(checkpoint)
        do { try actions.persistMachineGeometryIdentity(proposal.proposedMachineGeometry) }
        catch {
          do {
            try actions.persistMachineGeometryIdentity(proposal.oldMachineGeometry)
            if case .loaded(let old) = previous { try actions.saveAcceptedLearningPathCheckpoint(old) }
            else { try actions.clearAcceptedLearningPathCheckpoint() }
          } catch {
            axisMetricRecoveryError = "Geometry identity/checkpoint persistence requires recovery before Learning: \(error)"
            machineGeometryIdentity = proposal.proposedMachineGeometry
          }
          throw error
        }
        machineGeometryIdentity = proposal.proposedMachineGeometry
      } else { try actions.saveAcceptedLearningPathCheckpoint(checkpoint) }
      return .saved(checkpoint)
    } catch {
      learningAuthorityError =
        "The durable Learning Path checkpoint could not be updated; no reset was applied: \(error)"
      return nil
    }
  }

  private func makeLearningVacatePlans(
    currentItemID: LearningPathItemID
  ) -> LearningVacatePlans {
    computationDiagnostics.learningResetPlanBuildCount += 1
    let order = LearningPathItemID.learningExerciseOrder
    var revisionIDsByAnchor = Dictionary(
      uniqueKeysWithValues: order.map { ($0, Set<LearningArtifactRevisionID>()) }
    )
    var maximumRevisionIndex: Int?
    let currentRevisions = learningArtifactGraph.revisions.filter { $0.state == .current }
    // Traverse each current graph revision exactly once. A revision contributes
    // to every earlier rewind anchor whose suffix would invalidate it.
    for revision in currentRevisions {
      guard let item = learningPathItemID(for: revision.kind),
        let index = order.firstIndex(of: item)
      else { continue }
      maximumRevisionIndex = max(maximumRevisionIndex ?? index, index)
      for anchorIndex in order.indices where anchorIndex <= index {
        revisionIDsByAnchor[order[anchorIndex], default: []].insert(revision.id)
      }
    }

    let currentIndex = currentItemID.learningRewindAnchor.flatMap {
      order.firstIndex(of: $0)
    }
    var payloadIndexes = Set<Int>()
    func recordPayload(_ item: LearningPathItemID, when condition: Bool) {
      guard condition, let index = order.firstIndex(of: item) else { return }
      payloadIndexes.insert(index)
    }
    recordPayload(
      .humanGuidedDiscovery(.penInteraction),
      when: (currentPenInteractionSnapshot?.acceptedHistory.records.isEmpty == false)
        || discoveryTransactions[.penInteraction] != nil
    )
    recordPayload(
      .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
      when: !(currentBoundarySnapshot?.acceptedEvidence.isEmpty ?? true)
        || !acceptedBoundaryAggregates.isEmpty
        || currentBoundarySnapshot?.centerArrivalPosition != nil
    )
    recordPayload(
      .humanGuidedDiscovery(.calibrateCameraAndVisibleCap),
      when: cameraCalibrationAnchorFrame != nil || proposedMachineCameraRegistration != nil
    )
    recordPayload(
      .humanGuidedDiscovery(.calibratePenContactFromSparseMarks),
      when: tipCameraRegistration != nil || proposedTipCameraRegistration != nil
        || recoverableTipCalibrationCheckpoint != nil
        || !tipCalibrationRuntime.acceptedObservations.isEmpty
    )
    recordPayload(
      .borderValidation(.chooseDrawingBorderPlan),
      when: borderValidationSnapshot.drawingBorderPlan != nil
        || borderValidationSnapshot.localPreFrameBaseline != nil
        || borderValidationSnapshot.drawingOutcome != nil
        || borderValidationSnapshot.postFrame != nil
        || borderValidationSnapshot.assessment != nil
        || !borderValidationSnapshot.comparisonAttemptHistories.isEmpty
    )

    let source: LearningVacateSource = frameMode == .live ? .live : .simulated
    let boundaryIndex = order.firstIndex(
      of: .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    )!
    let tipIndex = order.firstIndex(
      of: .humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    )!
    let removesDurableMachineAuthority = activeMachineArtifactCheckpoint != nil
      || savedLearningState.checkpoint?.machineArtifacts != nil
    let removesDurableTipAuthority = recoverableTipCalibrationCheckpoint != nil
      || tipCameraRegistration != nil
      || savedLearningState.checkpoint?.tipCalibration != nil
    let physicalInkMayRemain =
      (borderValidationSnapshot.drawingOutcome?.progress.commandedStrokeCount ?? 0) > 0
      || borderValidationSnapshot.inkObservation != nil

    func makePlan(
      scope: LearningVacateScope,
      anchor: LearningPathItemID,
      anchorIndex: Int
    ) -> LearningVacatePlan? {
      let revisionIDs = revisionIDsByAnchor[anchor, default: []]
      let hasPayload = payloadIndexes.contains(where: { $0 >= anchorIndex })
        || currentIndex.map { $0 > anchorIndex } == true
      guard scope == .all || !revisionIDs.isEmpty || hasPayload else { return nil }

      let endIndex: Int
      if scope == .all {
        endIndex = order.index(before: order.endIndex)
      } else {
        endIndex = max(
          anchorIndex,
          max(maximumRevisionIndex ?? anchorIndex, currentIndex ?? anchorIndex)
        )
      }
      return LearningVacatePlan(
        scope: scope,
        source: source,
        anchor: anchor,
        affectedItems: Array(order[anchorIndex...endIndex]),
        expectedCurrentRevisionIDs: revisionIDs,
        expectedAcceptedAttemptSequence: acceptedAttemptSequence,
        removesDurableMachineCheckpoint:
          source == .live && anchorIndex <= boundaryIndex && removesDurableMachineAuthority,
        removesDurableTipCheckpoint:
          source == .live && anchorIndex <= tipIndex && removesDurableTipAuthority,
        physicalInkMayRemain: physicalInkMayRemain
      )
    }

    let plansByAnchor = Dictionary(
      uniqueKeysWithValues: order.indices.compactMap { index in
        let anchor = order[index]
        return makePlan(scope: .from(anchor), anchor: anchor, anchorIndex: index).map {
          (anchor, $0)
        }
      }
    )
    let resetAnchor = order[order.startIndex]
    return LearningVacatePlans(
      plansByAnchor: plansByAnchor,
      resetAllPlan: makePlan(
        scope: .all,
        anchor: resetAnchor,
        anchorIndex: order.startIndex
      )!
    )
  }

  private func learningPathItemID(for kind: LearningArtifactKind) -> LearningPathItemID? {
    switch kind {
    case .penInteraction:
      .humanGuidedDiscovery(.penInteraction)
    case .boundarySideAggregate, .estimatedMachineCenter, .centerArrival:
      .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    case .machineCameraRegistration:
      .humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    case .toolContactObservation, .tipCameraRegistration:
      .humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    case .linePlan, .localPreLineBaseline, .lineExecution, .postLineFrame,
      .inkObservation, .residual, .comparison:
      .borderValidation(.chooseDrawingBorderPlan)
    }
  }

  var contextualStopPresentation: ContextualStopPresentation? {
    learningPresentationBase().currentProjection.contextualStop
  }

  func manualMotionEpisodePresentation(for draft: ManualMotionDraft) -> ManualMotionPresentation {
    let activeIntent = manualMotionEpisodeSnapshot?.activeOperation?.intent
    let publicationRecovery = manualMotionPublicationRecoveryPresentation
    let evidenceDisposition = manualMotionEvidenceDispositionPresentation
    let stopAction = publicationRecovery == nil && evidenceDisposition == nil
      ? manualMotionEpisodeSnapshot?.activeOperation?.stopCapabilityID.map {
      capabilityID in
      let draws: Bool
      if case .jog(let request) = activeIntent, request.routing == .drawingStroke {
        draws = true
      } else {
        draws = false
      }
      return ManualMotionStopActionPresentation(
        capabilityID: capabilityID,
        title: draws ? "Stop Manual Drawing" : "Stop Manual Jog",
        detail: draws
          ? "Stop only this typed manual drawing effect; settlement requires controller Idle and Pen Up."
          : "Stop only this typed manual jog effect and wait for controller settlement."
      )
    } : nil
    let pendingReason = publicationRecovery?.remedy ?? evidenceDisposition?.remedy
    let draftReason = pendingReason ?? manualMotionDraftUnavailableReason(for: draft)
    let jogReason = draftReason ?? manualMotionRequirementReason(
      for: .jog(manualJogRequestPrototype(draft: draft))
    )
    let penUpReason = pendingReason ?? manualMotionRequirementReason(
      for: .setPen(manualPenRequest(position: .raised))
    )
    let penDownReason = pendingReason ?? manualMotionRequirementReason(
      for: .setPen(manualPenRequest(position: .lowered))
    )
    return ManualMotionPresentation(
      stopAction: stopAction,
      publicationRecovery: publicationRecovery,
      evidenceDisposition: evidenceDisposition,
      jogUnavailableReason: jogReason,
      penUpUnavailableReason: penUpReason,
      penDownUnavailableReason: penDownReason,
      penStateText: manualEpisodePenStateText,
      modeText: manualEpisodeModeText,
      recordingDiagnostic: manualMotionEpisodeSnapshot?.recordingDiagnostic
    )
  }

  private var manualMotionRuntimePresentation: ManualMotionPresentation {
    manualMotionEpisodePresentation(for: ManualMotionDraft())
  }

  func requestManualMotionStop(
    capabilityID: PlotterManualMotionStopCapabilityID
  ) async {
    guard manualMotionEpisodeSnapshot?.terminalPublicationIssue == nil else { return }
    let result = await manualMotionRuntime.stop(using: capabilityID)
    installManualMotionSnapshot(result.snapshot)
    await refreshManualEnvironmentSnapshot()
  }

  func recoverManualMotionPublication(
    capabilityID: PlotterManualMotionPublicationRecoveryCapabilityID
  ) async {
    guard manualMotionEpisodeSnapshot?.terminalPublicationIssue?.recoveryCapabilityID
      == capabilityID else { return }
    let result = await manualMotionRuntime.recoverTerminalPublication(using: capabilityID)
    installManualMotionSnapshot(result.snapshot)
    await refreshManualEnvironmentSnapshot()
  }

  func resolveManualMotionEvidence(
    using action: PlotterManualMotionEvidenceDispositionAction
  ) async {
    guard manualMotionEpisodeSnapshot?.evidenceDispositionAction == action else { return }
    do {
      let result = try await manualMotionRuntime.resolveTerminalEvidence(using: action)
      installManualMotionSnapshot(result.snapshot)
      await refreshManualEnvironmentSnapshot()
    } catch {
      machineError = actionableDescription(error)
    }
  }

  var motionRequestStatusPresentation: MotionRequestStatusPresentation {
    if let reason = manualMotionRuntimePresentation.attentionReason {
      return .needsAttention(reason)
    }
    if frameMode == .simulated {
      if manualMotionEpisodeSnapshot?.activeOperation != nil
        || simulatedLearningSnapshot?.currentOperation != nil || jogRequestInProgress
        || retainedPenRequestInProgress || jogCancelRequestInProgress || activeStopTarget != nil
      {
        return .busy(currentOperationText)
      }
      if let reason = manualMotionRuntimePresentation.jogControlsUnavailableReason {
        return .unavailable(reason)
      }
      return .ready
    }
    if let ambiguity = machineSnapshot?.machine.stickyAmbiguity {
      return .needsAttention(ambiguity.actionableDescription)
    }
    if let controllerAttentionText { return .needsAttention(controllerAttentionText) }
    if manualMotionEpisodeSnapshot?.activeOperation != nil
      || jogRequestInProgress || retainedPenRequestInProgress || jogCancelRequestInProgress
      || activeStopTarget != nil
    {
      return .busy(currentOperationText)
    }
    if let reason = manualMotionRuntimePresentation.jogControlsUnavailableReason {
      return .unavailable(reason)
    }
    return .ready
  }

  var observationConfigurationProjection: PlotterObservationConfigurationProjection {
    .init(
      reference: .init(revision: semanticPresentationRevision, capabilityID: controllerSessionID),
      frameMode: frameMode,
      cameraDevices: cameraDevices,
      selectedCameraID: selectedCameraID,
      cameraIsLive: cameraIsLive,
      sourceChangeUnavailableReason: observationSourceChangeUnavailableReason,
      calibrationBusyReason: currentCameraCalibrationBusyReason,
      cadence: visionAnalysisCadence,
      regionLock: videoAnalysisRegionLock,
      enabledOverlays: overlayPreferenceState.enabled
    )
  }

  @discardableResult
  func submitObservationConfiguration(
    _ submission: PlotterObservationOperatorSubmission
  ) async -> String? {
    guard applicationAdmissionIsOpen else { return "Observation configuration is shut down." }
    guard submission.reference.revision == semanticPresentationRevision,
      submission.reference.capabilityID == controllerSessionID
    else { return "The observation projection changed; use the current action." }
    switch submission.intent {
    case .selectSource, .selectCameraRole:
      if let reason = observationSourceChangeUnavailableReason { return reason }
    default: break
    }
    switch submission.intent {
    case .selectCameraRole(let role):
      if let reason = observationSourceChangeUnavailableReason { return reason }
      let result = await submitObservationIntent(.selectCameraRole(role))
      guard applicationAdmissionIsOpen else { return "Camera selection was cancelled during application shutdown." }
      guard let observationRuntime else { return "The camera runtime is unavailable." }
      installObservationEvent(.cameraRole(await observationRuntime.workbenchCameraSnapshot()))
      cameraSnapshot = await observationRuntime.snapshot()
      if workbenchCameraRole == .plotter, !cameraRoleIsTransitioning {
        frameMode = .live
        displayedFrame = cameraSnapshot?.latestFrame
        latestLiveCameraFrame = cameraSnapshot.flatMap { validatedLiveCameraFrame(in: $0) }
        reconcileCameraDependentLearningAuthority(with: displayedFrame)
        updateCameraError()
        if let exactFrame = try? await observationRuntime.captureFrame(newerThanNanoseconds: 0),
          workbenchCameraRole == .plotter, !cameraRoleIsTransitioning
        {
          receive(exactFrame)
        }
        await reconcileAutomaticVisionAnalysis()
      }
      switch result {
      case .failed(let detail)?, .refused(let detail)?: return detail
      case .stale?: return "The camera selection changed; use the current camera action."
      default: return nil
      }
    case .refresh:
      await refreshObservationSources()
    case .selectSource(.simulated, _):
      await transitionObservationSource(.simulated)
    case .selectSource(.live, let cameraID):
      guard let cameraID else {
        await transitionObservationSource(.live)
        return nil
      }
      guard !cameraID.isEmpty else { return "Select a current camera before retrying." }
      let id = CameraDeviceID(rawValue: cameraID)
      await selectCamera(id)
      guard selectedCameraID == id, cameraError == nil else {
        return cameraError ?? "The selected camera is no longer available."
      }
      await startCamera()
    case .stopLiveSource:
      await stopCamera()
    case .restartLiveSource:
      await restartCamera()
    case .setCadence(let framesPerSecond):
      guard let cadence = VisionAnalysisCadence(rawValue: framesPerSecond) else {
        return "Select a supported camera-analysis cadence."
      }
      guard visionAnalysisCadence != cadence else { return nil }
      visionAnalysisCadence = cadence
      markSemanticPresentationChanged()
      await reconcileAutomaticVisionAnalysis()
    case .setRegion(let region, let identity):
      guard let displayedFrame = actionSurfacePreview.displayedFrame,
        displayedFrame.frame.id.rawValue == identity.frameID,
        displayedFrame.frame.sequence == identity.sequence,
        displayedFrame.frame.captureNanoseconds == identity.captureNanoseconds,
        displayedFrame.frame.cameraConfigurationID.rawValue.uuidString
          == identity.cameraConfigurationID
      else { return "Refresh the exact displayed frame before changing its analysis region." }
      await applyVideoAnalysisRegion(
        region.map { PixelRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) },
        for: displayedFrame
      )
    case .setOverlay(let identifier, let enabled):
      guard let overlay = UserSceneOverlay(rawValue: identifier) else {
        return "Refresh the current overlay controls before retrying."
      }
      let prior = overlayPreferenceState
      overlayPreferenceState.applyOperatorSelection(overlay, enabled: enabled)
      do {
        try observationPreferences.persistOverlayPreference(overlayPreferenceState.enabled)
      } catch {
        overlayPreferenceState = prior
        visionError = "Overlay preference was not saved: \(actionableDescription(error))"
        return visionError
      }
      markSemanticPresentationChanged()
      await reconcileAutomaticVisionAnalysis()
    case .requestDiagnostics:
      await requestVideoDiagnostics()
    }
    return nil
  }

  private func refreshObservationSources() async {
    if frameMode == .simulated {
      await refreshSimulatedContent()
    } else {
      await discoverCameras()
    }
    await requestVideoDiagnostics()
  }

  /// Pull-only operational diagnostics for the Video Settings surface. This
  /// cache is deliberately absent from Learning projection revisions and does
  /// not create a high-rate observation stream.
  private func requestVideoDiagnostics() async {
    guard frameMode == .live, observationRuntime != nil else {
      videoVisionDiagnostics = nil
      return
    }
    _ = await submitObservationIntent(.requestDiagnostics)
  }

  private func applyVideoAnalysisRegion(
    _ region: PixelRect?,
    for displayedFrame: DisplayedFrame
  ) async {
    guard
      region == nil
        || cameraFrameIntersection(
          region!,
          frameWidth: displayedFrame.frame.width,
          frameHeight: displayedFrame.frame.height
        ) == region
    else {
      cameraError = "The requested analysis region is outside the current camera frame."
      return
    }
    let fullFrame = PixelRect(
      x: 0,
      y: 0,
      width: displayedFrame.frame.width,
      height: displayedFrame.frame.height
    )
    let canonicalRegion = region == fullFrame ? nil : region
    videoAnalysisRegionLock = canonicalRegion.map {
      VideoAnalysisRegionLock(
        source: displayedFrame.source,
        cameraConfigurationID: displayedFrame.frame.cameraConfigurationID,
        region: $0
      )
    }
    markSemanticPresentationChanged()
    await reconcileAutomaticVisionAnalysis()
  }

  var currentExerciseActionStripPresentation: PlotterUILearningActionStripDecision? {
    learningPresentationBase().currentProjection.currentActionStrip
  }

  func selectedOperatorActionPresentation(
    for itemID: LearningPathItemID
  ) -> OperatorActionPresentation {
    learningPathProjection(selectedItemID: itemID).selectedAction
  }

  func learningPathProjection(
    selectedItemID: LearningPathItemID
  ) -> LearningPathProjection {
    let base = learningPresentationBase()
    if selectedItemID == base.currentItemID {
      computationDiagnostics.learningProjectionCacheHitCount += 1
      return base.currentProjection
    }
    if let cached = selectedLearningProjectionCache,
      cached.revision == base.revision,
      cached.cameraIsLive == base.cameraIsLive,
      cached.selectedItemID == selectedItemID
    {
      computationDiagnostics.selectedLearningProjectionCacheHitCount += 1
      return cached.projection
    }
    computationDiagnostics.learningProjectionBuildCount += 1
    computationDiagnostics.selectedLearningProjectionBuildCount += 1
    let actionability = PlotterLearningActionabilityFactAdapter().compile(
      base.snapshot,
      selectedItemID: selectedItemID
    )
    let projection = PlotterLearningDetailedPresentationNormalizer().project(
      base.snapshot,
      selectedItemID: selectedItemID,
      actionability: actionability
    )
    selectedLearningProjectionCache = SelectedLearningProjectionCache(
      revision: base.revision,
      cameraIsLive: base.cameraIsLive,
      selectedItemID: selectedItemID,
      projection: projection
    )
    recordLearningActionStripDiagnostic(projection)
    return projection
  }

  func plotterUIProjection(
    selectedItemID: LearningPathItemID,
    manualDraft: ManualMotionDraft,
    includesLearningPath: Bool,
    pendingDrawingProgram: DrawingProgram? = nil,
    pendingDrawingPlacement: PlotterDrawingDraftCameraPlacement? = nil,
    pendingPointSelection: PlotterPointSelectionSubmission? = nil,
    observationViewport: ActionSurfaceViewportState? = nil
  ) -> PlotterAppUIProjection {
    let runtimeRevisions = currentPlotterUIRuntimeRevisions()
    let inputs = PlotterAppUIProjectionInputs(
      semanticRevision: semanticPresentationRevision,
      cameraIsLive: cameraIsLive,
      actionSurfaceRevision: actionSurfacePresentationRevision,
      runtimeRevisions: runtimeRevisions,
      drawingDraftReference: drawingDraftSnapshot.projection,
      selectedItemID: selectedItemID,
      manualDraft: manualDraft,
      includesLearningPath: includesLearningPath,
      pendingDrawingProgramHash: pendingDrawingProgram?.contentHash.description,
      pendingDrawingPlacement: pendingDrawingPlacement,
      pendingPointSelection: pendingPointSelection,
      observationViewport: observationViewport
    )
    if let cached = rootProjectionCache, cached.inputs == inputs {
      return cached.projection
    }
    if let cached = rootProjectionCache {
      var semanticInputs = inputs
      semanticInputs.actionSurfaceRevision = cached.inputs.actionSurfaceRevision
      let currentSurface = actionSurfacePresentation
      let selectionAdmissionUnchanged = pendingPointSelection.map {
        currentSurface.acceptsPendingPointSelection($0)
          == cached.projection.actionSurface.acceptsPendingPointSelection($0)
      } ?? true
      if semanticInputs == cached.inputs, selectionAdmissionUnchanged {
        // New measured overlays need a new video presentation, not a new set
        // of control requests or a rebuild of Learning and Drawing controls.
        var projection = cached.projection
        projection.actionSurface = currentSurface
        rootProjectionCache = (inputs, projection)
        return projection
      }
    }
    computationDiagnostics.plotterUIProjectionBuildCount += 1
    let learningPath = includesLearningPath
      ? learningPathProjection(selectedItemID: selectedItemID) : nil
    let currentLearning = learningPresentationBase()
    let manual = manualMotionEpisodePresentation(for: manualDraft)
    let drawing = drawingStudioPresentation
    let controller = controllerSessionProjection
    let observation = observationConfigurationProjection
    let actionSurface = actionSurfacePresentation
    let currentPendingPointSelection = pendingPointSelection.flatMap {
      actionSurface.acceptsPendingPointSelection($0) ? $0 : nil
    }
    var candidates: [PlotterUIActionCandidate] = []
    func appendApplicationCandidate(
      id: PlotterUIActionID,
      title: String,
      intent: PlotterUIIntent,
      unavailableReason: String? = nil,
      owner: String
    ) {
      candidates.append(uiCandidate(
        id: id,
        title: title,
        intent: intent,
        unavailableReason: unavailableReason,
        owner: owner
      ))
    }
    appendApplicationCandidate(
      id: PlotterAppUIActionID.controllerRefresh,
      title: "Refresh controllers",
      intent: .controller(controller.request(.refreshSerialDevices)),
      owner: "PlotterControllerSessionRuntime"
    )
    for device in controller.serialDevices {
      appendApplicationCandidate(
        id: PlotterAppUIActionID.controllerDevice(device.identifier),
        title: "Select \(device.displayName)",
        intent: .controller(controller.request(.selectSerialDevice(.init(
          identifier: device.identifier,
          displayName: device.displayName,
          bsdPath: device.bsdPath,
          transport: device.transport.rawValue
        )))),
        unavailableReason: controller.selectionUnavailableReason,
        owner: "PlotterControllerSessionRuntime"
      )
    }
    appendApplicationCandidate(
      id: PlotterAppUIActionID.controllerConnection,
      title: controller.connectionAction.title,
      intent: .controller(controller.request(.toggleConnection)),
      unavailableReason: controller.connectionUnavailableReason,
      owner: "PlotterControllerSessionRuntime"
    )
    appendApplicationCandidate(
      id: PlotterAppUIActionID.controllerMotion,
      title: controller.motionAuthorized ? "Disable Motion" : "Enable Motion & Raise Pen",
      intent: .controller(controller.request(.toggleMotionAuthorization)),
      unavailableReason: controller.motionAuthorizationUnavailableReason,
      owner: "PlotterControllerSessionRuntime"
    )
    appendApplicationCandidate(
      id: PlotterAppUIActionID.controllerClearAlarm,
      title: "Clear Alarm",
      intent: .controller(controller.request(.clearAlarm)),
      unavailableReason: controller.alarmClearUnavailableReason,
      owner: "PlotterControllerSessionRuntime"
    )
    appendApplicationCandidate(
      id: PlotterAppUIActionID.observationRefresh,
      title: "Refresh cameras",
      intent: .observation(observation.request(.refresh)),
      owner: "PlotterObservationConfigurationRuntime"
    )
    for role in WorkbenchCameraRole.allCases {
      appendApplicationCandidate(
        id: PlotterAppUIActionID.observationCameraRole(role),
        title: role == .portrait ? "Use portrait camera" : "Show on Plotter Video",
        intent: .observation(observation.request(.selectCameraRole(role))),
        unavailableReason: observation.sourceChangeUnavailableReason,
        owner: "PlotterObservationConfigurationRuntime"
      )
    }
    appendApplicationCandidate(
      id: PlotterAppUIActionID.observationSimulated,
      title: "Use simulated source",
      intent: .observation(observation.request(.selectSource(.simulated, cameraID: nil))),
      unavailableReason: observation.sourceChangeUnavailableReason,
      owner: "PlotterObservationConfigurationRuntime"
    )
    for camera in observation.cameraDevices {
      appendApplicationCandidate(
        id: PlotterAppUIActionID.observationCamera(camera.id.rawValue),
        title: "Use \(camera.name)",
        intent: .observation(observation.request(.selectSource(
          .live,
          cameraID: camera.id.rawValue
        ))),
        unavailableReason: observation.sourceChangeUnavailableReason,
        owner: "PlotterObservationConfigurationRuntime"
      )
    }
    appendApplicationCandidate(
      id: PlotterAppUIActionID.observationDiagnostics,
      title: "Refresh observation diagnostics",
      intent: .observation(observation.request(.requestDiagnostics)),
      owner: "PlotterObservationConfigurationRuntime"
    )
    for cadence in VisionAnalysisCadence.allCases {
      appendApplicationCandidate(
        id: PlotterAppUIActionID.observationCadence(cadence),
        title: "Set analysis cadence to \(cadence.displayValue)",
        intent: .observation(observation.request(.setCadence(
          framesPerSecond: cadence.rawValue
        ))),
        unavailableReason: observation.frameMode == .live ? nil : "SIMULATED owns its cadence.",
        owner: "PlotterObservationConfigurationRuntime"
      )
    }
    for overlay in UserSceneOverlay.allCases {
      let enabled = !observation.enabledOverlays.contains(overlay)
      appendApplicationCandidate(
        id: PlotterAppUIActionID.observationOverlay(overlay.rawValue, enabled: enabled),
        title: "\(enabled ? "Enable" : "Disable") \(overlay.rawValue) overlay",
        intent: .observation(observation.request(.setOverlay(
          identifier: overlay.rawValue,
          enabled: enabled
        ))),
        owner: "PlotterObservationConfigurationRuntime"
      )
    }
    appendApplicationCandidate(
      id: PlotterAppUIActionID.paperNewSheet,
      title: "New sheet on current contact plane",
      intent: .paper(.newSheetOnCurrentPlane),
      unavailableReason: paperManagementUnavailableReason,
      owner: "PlotterApplicationRuntime"
    )
    appendApplicationCandidate(
      id: PlotterAppUIActionID.paperContactPlane,
      title: "Paper contact plane changed",
      intent: .paper(.contactPlaneChanged),
      unavailableReason: paperManagementUnavailableReason,
      owner: "PlotterApplicationRuntime"
    )
    candidates.append(uiCandidate(
      id: PlotterAppUIActionID.learningMode,
      title: learningModePresentation.actionTitle,
      intent: .learning(.setEnabled(!learningIsEnabled)),
      unavailableReason: learningModePresentation.remedy,
      owner: "PlotterPointSelectionRuntime"
    ))
    candidates.append(contentsOf: manualUIActions(draft: manualDraft, presentation: manual).map {
      uiCandidate(action: $0, owner: "PlotterManualMotionRuntime")
    })
    if let pendingPointSelection = currentPendingPointSelection {
      candidates.append(uiCandidate(
        id: PlotterAppUIActionID.pointSelection(pendingPointSelection),
        title: "Apply exact-frame Learning point",
        intent: .pointSelection(pendingPointSelection),
        unavailableReason: nil,
        owner: "PlotterPointSelectionRuntime"
      ))
    }
    candidates.append(uiCandidate(
      id: PlotterAppUIActionID.drawingDraft(drawingTargetIsVisible ? .hideTarget : .showTarget),
      title: drawingTargetIsVisible ? "Hide Drawing Target" : "Show Drawing Target",
      intent: .drawingDraft(drawingTargetIsVisible ? .hideTarget : .showTarget),
      unavailableReason: nil,
      owner: "PlotterDrawingDraftRuntime"
    ))
    do {
      for control in drawing.coverageControls {
        candidates.append(uiCandidate(
          id: PlotterAppUIActionID.drawingDraft(control.intent), title: control.title,
          intent: .drawingDraft(control.intent), unavailableReason: control.unavailableReason,
          owner: "PlotterDrawingDraftRuntime"))
      }
      if let pendingDrawingProgram {
        let intent = PlotterDrawingDraftIntent.selectProgram(pendingDrawingProgram)
        candidates.append(uiCandidate(
          id: PlotterAppUIActionID.drawingDraft(intent),
          title: "Use Portrait",
          intent: .drawingDraft(intent),
          unavailableReason: drawing.authoringUnavailableReason,
          owner: "PlotterDrawingDraftRuntime"
        ))
      }
      for record in drawing.residualRecords {
        let intent = PlotterDrawingDraftIntent.selectResidualRecord(record.recordID, selected: !record.isSelected)
        candidates.append(uiCandidate(id: PlotterAppUIActionID.drawingDraft(intent),
          title: "Select archived \(record.title)", intent: .drawingDraft(intent),
          unavailableReason: nil, owner: "PlotterDrawingDraftRuntime"))
      }
      let analyzeIntent = PlotterDrawingDraftIntent.analyzeSelectedResiduals
      candidates.append(uiCandidate(id: PlotterAppUIActionID.drawingDraft(analyzeIntent),
        title: "Analyze for Learning", intent: .drawingDraft(analyzeIntent),
        unavailableReason: drawing.residualRecords.contains(where: \.isSelected) ? nil : "Select an archived drawing first.",
        owner: "PlotterDrawingDraftRuntime"))
      let borderIntent = PlotterDrawingDraftIntent.setDrawBorder(!drawing.drawBorder)
      candidates.append(uiCandidate(id: PlotterAppUIActionID.drawingDraft(borderIntent),
        title: "Draw border", intent: .drawingDraft(borderIntent),
        unavailableReason: drawing.authoringUnavailableReason, owner: "PlotterDrawingDraftRuntime"))
      let fitIntent = PlotterDrawingDraftIntent.fitInDrawableRegion
      candidates.append(uiCandidate(id: PlotterAppUIActionID.drawingDraft(fitIntent),
        title: "Fit Target", intent: .drawingDraft(fitIntent),
        unavailableReason: drawing.authoringUnavailableReason, owner: "PlotterDrawingDraftRuntime"))
      let centerIntent = PlotterDrawingDraftIntent.centerInDrawableRegion
      candidates.append(uiCandidate(
        id: PlotterAppUIActionID.drawingDraft(centerIntent),
        title: "Center Target",
        intent: .drawingDraft(centerIntent),
        unavailableReason: drawing.authoringUnavailableReason,
        owner: "PlotterDrawingDraftRuntime"
      ))
      if let pendingDrawingPlacement {
        let placementIntent = PlotterDrawingDraftIntent.placeAtCameraPoint(
          pendingDrawingPlacement
        )
        candidates.append(uiCandidate(
          id: PlotterAppUIActionID.drawingDraft(placementIntent),
          title: "Apply exact-frame drawing placement",
          intent: .drawingDraft(placementIntent),
          unavailableReason: drawing.canvas.placement.placementIsEnabled
            ? nil : drawing.runState.detail,
          owner: "PlotterDrawingDraftRuntime"
        ))
      }
      let paperIntent = PlotterDrawingDraftIntent.assertPaperCoverage
      candidates.append(uiCandidate(
        id: PlotterAppUIActionID.drawingDraft(paperIntent),
        title: "Assert sheet covers outline",
        intent: .drawingDraft(paperIntent),
        unavailableReason: paperManagementUnavailableReason,
        owner: "PlotterDrawingDraftRuntime"
      ))
      let allowedScale = drawing.canvas.placement.allowedScale
      let minimumScaleStep = Int(ceil(allowedScale.lowerBound * 100))
      let maximumScaleStep = Int(floor(allowedScale.upperBound * 100))
      // A program change may clamp to a fractional bound between slider steps.
      // Preserve that exact bound in the projection instead of rounding it out
      // of the runtime's admissible range and disabling the Size control.
      var scales: Set<Double> = [allowedScale.lowerBound, allowedScale.upperBound]
      if minimumScaleStep <= maximumScaleStep {
        scales.formUnion((minimumScaleStep...maximumScaleStep).prefix(2_000).map { Double($0) / 100 })
      }
      candidates.append(contentsOf: scales.sorted().map { scale in
        let intent = PlotterDrawingDraftIntent.setUniformScale(scale)
        return uiCandidate(
          id: PlotterAppUIActionID.drawingDraft(intent),
          title: "Set scale \(scale)",
          intent: .drawingDraft(intent),
          unavailableReason: drawing.authoringUnavailableReason,
          owner: "PlotterDrawingDraftRuntime"
        )
      })
      candidates.append(contentsOf: (-180...180).map { degrees in
        let intent = PlotterDrawingDraftIntent.setRotationDegrees(Double(degrees))
        return uiCandidate(
          id: PlotterAppUIActionID.drawingDraft(intent),
          title: "Set rotation \(degrees) degrees",
          intent: .drawingDraft(intent),
          unavailableReason: drawing.authoringUnavailableReason,
          owner: "PlotterDrawingDraftRuntime"
        )
      })
      candidates.append(contentsOf: drawing.controls.map { control in
        uiCandidate(
          id: PlotterAppUIActionID.drawingRun(control.intent),
          title: control.title,
          intent: .drawingRun(control.intent),
          unavailableReason: control.isEnabled ? nil : drawing.runState.detail,
          owner: "PlotterDrawingRunRuntime"
        )
      })
    }
    candidates.append(contentsOf: actionSurfacePresentation.completedComparisonReview.controls.map {
      control in
      let intent: PlotterUIRetainedComparisonIntent =
        control.intent == .reviewComparison ? .reviewExactFrame : .resumeLivePreview
      return uiCandidate(
        id: PlotterAppUIActionID.retainedComparison(intent),
        title: control.title,
        intent: .retainedComparisonReview(intent),
        unavailableReason: nil,
        owner: "DrawingBorderRetainedWorkflow"
      )
    })
    if includesLearningPath {
      let adapter = PlotterLearningActionabilityFactAdapter()
      let actionability = adapter.compile(
        currentLearning.snapshot,
        selectedItemID: selectedItemID
      )
      candidates.append(contentsOf: actionability.strips.flatMap { strip in
        strip.requestDecisions().map { $0.candidate() }
      })
    }
    if recoverableTipCalibrationCheckpoint != nil || tipCalibrationRuntime.positionRecoveryIsAvailable {
      let recovery = PlotterUILearningActionDecision(
        itemID: plotterUILearningOwnerID(.humanGuidedDiscovery(.calibratePenContactFromSparseMarks)),
        action: .tipCalibration(.revalidateCheckpoint),
        unavailableReason: positionRevalidationUnavailableReason
      ).candidate()
      candidates.removeAll { $0.id == recovery.id }
      candidates.append(recovery)
    }
    if let plan = learningPath?.resetSurface.selectedPlan {
      candidates.append(.learningReset(
        request: plan.modelRequest,
        title: plan.title,
        unavailableReason: learningPath?.resetSurface.unavailableReason
      ))
    }
    if let plan = learningPath?.menu.resetAllPlan {
      candidates.append(.learningReset(
        request: plan.modelRequest,
        title: plan.title,
        unavailableReason: nil
      ))
    }
    candidates.append(uiCandidate(
      id: PlotterAppUIActionID.incidentPackage,
      title: "Create Incident Package",
      intent: .requestIncidentPackage,
      unavailableReason: incidentPackageUIActionUnavailableReason,
      owner: "PlotterIncidentPackageUIService"
    ))

    if applicationAdmissionIsClosed {
      candidates = candidates.map { candidate in
        PlotterUIActionCandidate(
          id: candidate.id,
          title: candidate.title,
          intent: candidate.intent,
          reachability: candidate.reachability,
          requirements: candidate.requirements + [PlotterUIRequirement(
            id: "application.admission.closed",
            isSatisfied: false,
            owner: "PlotterApplicationRuntime",
            remedy: "The application is shutting down; no successor effect can start."
          )]
        )
      }
    }

    let semantic = PlotterUICompiler().compile(PlotterUICompilerInput(
      revision: plotterUIRevision(
        selectedItemID: selectedItemID,
        manualDraft: manualDraft,
        includesLearningPath: includesLearningPath,
        cameraIsLive: inputs.cameraIsLive,
        pendingDrawingProgramHash: pendingDrawingProgram?.contentHash.description,
        pendingDrawingPlacement: pendingDrawingPlacement,
        pendingPointSelection: currentPendingPointSelection,
        observationViewport: observationViewport
      ),
      runtimeRevisions: runtimeRevisions,
      candidates: candidates,
      learning: plotterUILearningFacts(currentLearning.snapshot),
      incidentPackage: incidentPackageUIState
    ))
    currentPlotterUIProjection = semantic
    currentPlotterUIBindingSemanticRevision = semanticPresentationRevision
    let projection = PlotterAppUIProjection(
      semantic: semantic,
      actionSurface: actionSurface,
      learningMode: learningModePresentation,
      learningPath: learningPath,
      currentLearningPathItemID: plotterUILearningItemID(
        semantic.learning?.currentOwnerID
      ) ?? currentLearning.currentItemID,
      learningIsEnabled: learningIsEnabled,
      manualMotion: manual,
      drawingStudio: drawing,
      drawingTargetIsVisible: drawingTargetIsVisible,
      drawingDraftProjection: drawingDraftSnapshot.projection,
      workbenchCapability: workbenchCapabilityPresentation,
      incidentPackage: semantic.incidentPackage,
      controllerSession: controller,
      observationConfiguration: observation,
      paperManagementUnavailableReason: paperManagementUnavailableReason,
      motionRequestStatus: motionRequestStatusPresentation
    )
    rootProjectionCache = (inputs, projection)
    return projection
  }

  func videoPreviewProjection(
    displayedFrame: DisplayedFrame?,
    observationViewport: ActionSurfaceViewportState
  ) -> PlotterUIProjection {
    let observation = observationConfigurationProjection
    var candidates: [PlotterUIActionCandidate] = []
    if let displayedFrame,
      actionSurfacePreview.displayedFrame.map({
        $0.source == displayedFrame.source
          && $0.frame.id == displayedFrame.frame.id
          && $0.frame.sequence == displayedFrame.frame.sequence
          && $0.frame.captureNanoseconds == displayedFrame.frame.captureNanoseconds
          && $0.frame.cameraConfigurationID == displayedFrame.frame.cameraConfigurationID
      }) == true,
      let region = observationViewport.selectedRegion(
        frameWidth: displayedFrame.frame.width,
        frameHeight: displayedFrame.frame.height
      )
    {
      let nextRegion = observation.regionLock?.matches(displayedFrame) == true ? nil : region
      candidates.append(uiCandidate(
        id: PlotterAppUIActionID.observationRegion,
        title: nextRegion == nil ? "Unlock analysis region" : "Lock analysis region",
        intent: .observation(observation.request(.setRegion(
          nextRegion.map {
            PlotterObservationRegion(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
          },
          displayedFrame: .init(
            frameID: displayedFrame.frame.id.rawValue,
            sequence: displayedFrame.frame.sequence,
            captureNanoseconds: displayedFrame.frame.captureNanoseconds,
            cameraConfigurationID: displayedFrame.frame.cameraConfigurationID.rawValue.uuidString
          )
        ))),
        unavailableReason: observation.calibrationBusyReason,
        owner: "PlotterObservationConfigurationRuntime"
      ))
    }
    let projection = PlotterUICompiler().compile(PlotterUICompilerInput(
      revision: videoPreviewUIRevision(
        displayedFrame: displayedFrame,
        observationViewport: observationViewport
      ),
      runtimeRevisions: currentPlotterUIRuntimeRevisions(),
      candidates: candidates
    ))
    currentVideoPreviewProjection = projection
    currentVideoPreviewBindingSemanticRevision = semanticPresentationRevision
    return projection
  }

  private func uiCandidate(
    action: PlotterUIAction,
    owner: String,
    reachability: PlotterUIActionReachability = .global
  ) -> PlotterUIActionCandidate {
    uiCandidate(
      id: action.id,
      title: action.title,
      intent: action.intent,
      unavailableReason: action.unavailableReason,
      owner: owner,
      reachability: reachability
    )
  }

  private func uiCandidate(
    id: PlotterUIActionID,
    title: String,
    intent: PlotterUIIntent,
    unavailableReason: String?,
    owner: String,
    reachability: PlotterUIActionReachability = .global
  ) -> PlotterUIActionCandidate {
    PlotterUIActionCandidate(
      id: id,
      title: title,
      intent: intent,
      reachability: reachability,
      requirements: unavailableReason.map {
        [PlotterUIRequirement(
          id: "\(id.rawValue).availability",
          isSatisfied: false,
          owner: owner,
          remedy: $0
        )]
      } ?? []
    )
  }

  private func plotterUILearningOwnerID(_ item: LearningPathItemID) -> String {
    "\(item.number)-\(item.title)"
  }

  private func plotterUILearningItemID(_ ownerID: String?) -> LearningPathItemID? {
    guard let ownerID else { return nil }
    return LearningPathItemID.learningExerciseOrder.first {
      plotterUILearningOwnerID($0) == ownerID
    }
  }

  private func plotterUILearningFacts(
    _ facts: PlotterLearningPresentationFacts
  ) -> PlotterUILearningFacts {
    PlotterUILearningFacts(
      isEnabled: facts.learningEnabled,
      activeOwnerID: facts.operations.activeAttemptOwner.map(plotterUILearningOwnerID),
      orderedMilestones: [
        PlotterUILearningMilestone(
          ownerID: plotterUILearningOwnerID(.humanGuidedDiscovery(.penInteraction)),
          isComplete: facts.penInteractionCompleted
        ),
        PlotterUILearningMilestone(
          ownerID: plotterUILearningOwnerID(
            .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
          ),
          isComplete: facts.boundary.isComplete && facts.boundary.centerArrival != nil
        ),
        PlotterUILearningMilestone(
          ownerID: plotterUILearningOwnerID(
            .humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
          ),
          isComplete: facts.cameraCalibration.acceptedIsCurrent
        ),
        PlotterUILearningMilestone(
          ownerID: plotterUILearningOwnerID(
            .humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
          ),
          isComplete: facts.sparseCalibration.acceptedIsCurrent
        ),
        PlotterUILearningMilestone(
          ownerID: plotterUILearningOwnerID(
            .borderValidation(.chooseDrawingBorderPlan)
          ),
          isComplete: false
        ),
      ]
    )
  }

  private func plotterUIRevision(
    selectedItemID: LearningPathItemID,
    manualDraft: ManualMotionDraft,
    includesLearningPath: Bool,
    cameraIsLive: Bool,
    pendingDrawingProgramHash: String?,
    pendingDrawingPlacement: PlotterDrawingDraftCameraPlacement?,
    pendingPointSelection: PlotterPointSelectionSubmission?,
    observationViewport: ActionSurfaceViewportState?
  ) -> PlotterUIRevision {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in "\(semanticPresentationRevision)|\(selectedItemID)|\(manualDraft.xDistanceMM)|\(manualDraft.yDistanceMM)|\(manualDraft.feedMMPerMinute)|\(includesLearningPath)|\(cameraIsLive)|\(pendingDrawingProgramHash ?? "")|\(String(describing: pendingDrawingPlacement))|\(String(describing: pendingPointSelection))|\(String(describing: observationViewport))".utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return PlotterUIRevision(rawValue: hash)
  }

  private func videoPreviewUIRevision(
    displayedFrame: DisplayedFrame?,
    observationViewport: ActionSurfaceViewportState
  ) -> PlotterUIRevision {
    let identity = [
      "video-preview",
      String(semanticPresentationRevision),
      String(describing: displayedFrame?.source),
      displayedFrame?.frame.id.rawValue ?? "none",
      String(displayedFrame?.frame.sequence ?? 0),
      String(displayedFrame?.frame.captureNanoseconds ?? 0),
      displayedFrame?.frame.cameraConfigurationID.rawValue.uuidString ?? "none",
      String(describing: observationViewport),
    ].joined(separator: "|")
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in identity.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return PlotterUIRevision(rawValue: hash)
  }

  private func currentPlotterUIRuntimeRevisions() -> [PlotterUIRuntimeRevision] {
    var revisions = [
      PlotterUIRuntimeRevision(
        owner: "PlotterPointSelectionRuntime",
        token: String(pointSelectionEpisodeProjection.projectionRevision.rawValue)
      ),
      PlotterUIRuntimeRevision(
        owner: "PlotterDrawingDraftRuntime",
        token: String(drawingDraftSnapshot.projection.draftRevision.rawValue)
      ),
    ]
    if let manualMotionEpisodeSnapshot {
      revisions.append(PlotterUIRuntimeRevision(
        owner: "PlotterManualMotionRuntime",
        token: String(manualMotionEpisodeSnapshot.projection.projectionRevision.rawValue)
      ))
    }
    if let penInteraction = currentPenInteractionSnapshot {
      revisions.append(PlotterUIRuntimeRevision(
        owner: "PlotterPenInteractionRuntime",
        token: String(penInteraction.projection.reference.revision.rawValue)
      ))
    }
    if let boundary = currentBoundarySnapshot {
      revisions.append(PlotterUIRuntimeRevision(
        owner: "PlotterBoundaryRuntime",
        token: String(boundary.projection.reference.revision.rawValue)
      ))
    }
    revisions.append(PlotterUIRuntimeRevision(
      owner: "PlotterCameraCalibrationRuntime",
      token: String(cameraCalibrationRuntime.snapshot().revision)
    ))
    if let drawingRunSnapshot {
      revisions.append(PlotterUIRuntimeRevision(
        owner: "PlotterDrawingRunRuntime",
        token: String(drawingRunSnapshot.projection.runRevision.rawValue)
      ))
    }
    revisions.append(PlotterUIRuntimeRevision(
      owner: "PlotterControllerSessionRuntime",
      token: String(controllerSessionProjection.reference.revision)
    ))
    revisions.append(PlotterUIRuntimeRevision(
      owner: "PlotterObservationConfigurationRuntime",
      token: String(observationConfigurationProjection.reference.revision)
    ))
    return revisions
  }

  private var incidentPackageUIActionUnavailableReason: String? {
    switch incidentPackageUIState {
    case .loading:
      return "Wait for the active incident-package availability request to finish."
    case .unavailable(let reason):
      return reason
    case .refused(let reason, let remedy):
      return "\(reason) \(remedy)"
    case .available, .completed:
      return nil
    }
  }

  func submitPlotterUIRequest(
    _ request: PlotterUIRequest
  ) async -> PlotterUIRequestDisposition {
    let title = currentPlotterUIProjection?.action(id: request.actionID)?.title ?? "Unavailable action"
    let started = ContinuousClock.now
    WorkbenchRequestTelemetry.received(request, title: title)
    let result = await submitRecordedPlotterUIRequest(request)
    WorkbenchRequestTelemetry.finished(request, title: title, disposition: result,
      duration: started.duration(to: .now))
    return result
  }

  private func submitRecordedPlotterUIRequest(
    _ request: PlotterUIRequest
  ) async -> PlotterUIRequestDisposition {
    let learningRecordRequest: PlotterLearningRecordRequest
    switch request.intent {
    case .learningAction(let learningRequest):
      learningRecordRequest = .action(learningRequest)
    case .learningReset(let resetRequest):
      learningRecordRequest = .reset(resetRequest)
    default:
      return await submitUnrecordedPlotterUIRequest(request, learningTransitionID: nil)
    }
    let reservation = learningEpisodeRecord.reserve(
      learningRecordRequest,
      environment: frameMode == .live ? .live : .simulated,
      preStateRevision: .init(rawValue: semanticPresentationRevision)
    )
    let disposition = await submitUnrecordedPlotterUIRequest(
      request,
      learningTransitionID: reservation.transitionID
    )
    learningEpisodeRecord.publish(
      reservation,
      result: learningEpisodeResult(disposition, request: learningRecordRequest),
      postTransitionProjection: learningPostTransitionProjection()
    )
    return disposition
  }

  private func submitUnrecordedPlotterUIRequest(
    _ request: PlotterUIRequest,
    learningTransitionID: PlotterLearningTransitionID?
  ) async -> PlotterUIRequestDisposition {
    let selectedProjection: (projection: PlotterUIProjection, semanticRevision: UInt64?)? =
      if request.actionID == PlotterAppUIActionID.observationRegion,
        let currentVideoPreviewProjection,
        currentVideoPreviewProjection.revision == request.uiRevision
      {
        (currentVideoPreviewProjection, currentVideoPreviewBindingSemanticRevision)
      } else if let currentPlotterUIProjection {
        (currentPlotterUIProjection, currentPlotterUIBindingSemanticRevision)
      } else {
        nil
      }
    guard let selectedProjection else {
      return plotterUIRefusal(
        request,
        reason: .staleUIRevision,
        currentUIRevision: PlotterUIRevision(rawValue: 0),
        currentRuntimeRevisions: currentPlotterUIRuntimeRevisions(),
        remedy: "Render the current bounded UI projection before submitting."
      )
    }
    let currentProjection = selectedProjection.projection
    let currentUIRevision = currentProjection.revision
    let currentRuntimeRevisions = currentPlotterUIRuntimeRevisions().sorted { $0.owner < $1.owner }
    let submittedRuntimeRevisions = request.runtimeRevisions.sorted { $0.owner < $1.owner }
    if applicationAdmissionIsClosed {
      return plotterUIRefusal(
        request,
        reason: .retainedOwnerRefused,
        currentUIRevision: currentUIRevision,
        currentRuntimeRevisions: currentRuntimeRevisions,
        remedy: "The root application runtime is shut down; no successor effect can start."
      )
    }
    let isImmediateStop: Bool = if case .learningAction(let action) = request.intent {
      action.action.isImmediateStop
    } else { false }
    if !isImmediateStop && (request.uiRevision != currentUIRevision
      || selectedProjection.semanticRevision != semanticPresentationRevision)
    {
      return plotterUIRefusal(
        request,
        reason: .staleUIRevision,
        currentUIRevision: currentUIRevision,
        currentRuntimeRevisions: currentRuntimeRevisions,
        remedy: "Refresh the current UI projection before retrying."
      )
    }
    if !isImmediateStop && submittedRuntimeRevisions != currentRuntimeRevisions {
      return plotterUIRefusal(
        request,
        reason: .staleRuntimeRevision,
        currentUIRevision: currentUIRevision,
        currentRuntimeRevisions: currentRuntimeRevisions,
        remedy: "Refresh the changed episode runtime projection before retrying."
      )
    }
    guard let reachedAction = currentProjection.action(id: request.actionID) else {
      return plotterUIRefusal(
        request,
        reason: .unknownAction,
        currentUIRevision: currentUIRevision,
        currentRuntimeRevisions: currentRuntimeRevisions,
        remedy: "Use an action reached by the current bounded projection."
      )
    }
    guard reachedAction.intent == request.intent else {
      return plotterUIRefusal(
        request,
        reason: .mismatchedIntent,
        currentUIRevision: currentUIRevision,
        currentRuntimeRevisions: currentRuntimeRevisions,
        remedy: "Use the exact intent bound to the reached action."
      )
    }
    guard reachedAction.isAvailable else {
      return plotterUIRefusal(
        request,
        reason: .unavailableAction,
        currentUIRevision: currentUIRevision,
        currentRuntimeRevisions: currentRuntimeRevisions,
        remedy: reachedAction.unavailableReason ?? "Resolve the named action requirement."
      )
    }

    if case .paperReplaced = artifactResetRuntime.snapshot().activeIntent {
      switch request.intent {
      case .drawingRun(.start), .drawingDraft, .paper, .manualMotion,
        .learningAction, .boundary, .pointSelection:
        return plotterUIRefusal(request, reason: .unavailableAction,
          currentUIRevision: currentUIRevision, currentRuntimeRevisions: currentRuntimeRevisions,
          remedy: "Wait for the current paper replacement transaction to finish.")
      default: break
      }
    }

    switch request.intent {
    case .learning(.setEnabled(let target)) where request.actionID == PlotterAppUIActionID.learningMode:
      await setLearningEnabledFromPlotterUI(target)
    case .pointSelection(let submission)
      where request.actionID == PlotterAppUIActionID.pointSelection(submission):
      submitPointSelection(submission)
    case .manualMotion(let intent):
      let settled = await submitManualMotionIntent(intent)
      if case .setPen(let pen) = intent, pen.position == .raised,
        settled?.projection.lastTerminalEffect?.result.disposition != .completed
          || settled?.terminalPublicationIssue != nil || settled?.evidenceDispositionAction != nil {
        return plotterUIRefusal(request, reason: .retainedOwnerRefused,
          currentUIRevision: currentPlotterUIProjection?.revision ?? currentUIRevision,
          currentRuntimeRevisions: currentPlotterUIRuntimeRevisions(),
          remedy: settled?.projection.remedy ?? machineError
            ?? "The pen did not settle. Use the current Raise Pen control to retry.")
      }
    case .manualStop(let rawID) where request.actionID == PlotterAppUIActionID.manualStop:
      await requestManualMotionStop(
        capabilityID: PlotterManualMotionStopCapabilityID(rawValue: rawID)
      )
    case .manualPublicationRecovery(let rawID)
      where request.actionID == PlotterAppUIActionID.manualRecovery:
      await recoverManualMotionPublication(
        capabilityID: PlotterManualMotionPublicationRecoveryCapabilityID(rawValue: rawID)
      )
    case .manualEvidenceDisposition(let effectID, let environment, let observationID, let disposition)
      where request.actionID == PlotterAppUIActionID.manualEvidence:
      let action = PlotterManualMotionEvidenceDispositionAction(
        effectID: EpisodeEffectID(rawValue: effectID),
        environment: environment,
        observationID: PlotterObservationID(rawValue: observationID),
        disposition: disposition == .acknowledgeAmbiguity
          ? .acknowledgeAmbiguity : .acknowledgePossibleInk,
        summary: manualMotionEpisodeSnapshot?.evidenceDispositionAction?.summary ?? ""
      )
      await resolveManualMotionEvidence(using: action)
    case .drawingDraft(let intent)
      where request.actionID == PlotterAppUIActionID.drawingDraft(intent):
      if intent == .assertPaperCoverage {
        // Ambient analysis does not recompile the controls. Bind this explicit
        // operator assertion to the exact frame available at the click, then
        // retain Draft's full-reference admission through the submission.
        let referenceAtClick = drawingDraftSnapshot.projection
        guard let visibleFrame = actionSurfacePreview.displayedFrame else {
          return plotterUIRefusal(request, reason: .retainedOwnerRefused,
            currentUIRevision: currentUIRevision, currentRuntimeRevisions: currentRuntimeRevisions,
            remedy: "Show the current Plotter Video frame before confirming sheet coverage.")
        }
        // Preview pixels are normally unsealed. Only this explicit evidence
        // action materializes their identity; passive video does no hashing.
        displayedFrame = DisplayedFrame(source: visibleFrame.source,
          frame: visibleFrame.frame.materializingEvidenceContentHash())
        let factsAtClick = drawingDraftExternalFacts
        let prepared = await drawingDraftRuntime.synchronize(factsAtClick)
        guard prepared.projection.environment == referenceAtClick.environment,
          prepared.projection.draftRevision == referenceAtClick.draftRevision,
          factsAtClick.revisions == drawingDraftExternalFacts.revisions else {
          return plotterUIRefusal(
            request, reason: .retainedOwnerRefused, currentUIRevision: currentUIRevision,
            currentRuntimeRevisions: currentRuntimeRevisions,
            remedy: "The drawing context changed while preparing sheet confirmation. Review the current target and retry.")
        }
        installDrawingDraftSnapshot(prepared)
      }
      await performDrawingDraftSubmission(PlotterDrawingDraftSubmission(
        projection: drawingDraftSnapshot.projection,
        intent: intent
      ))
      if let refusal = drawingDraftSnapshot.lastSubmissionRefusal {
        return plotterUIRefusal(
          request, reason: .retainedOwnerRefused, currentUIRevision: currentUIRevision,
          currentRuntimeRevisions: currentRuntimeRevisions, remedy: refusal.remedy)
      }
    case .drawingRun(let intent)
      where request.actionID == PlotterAppUIActionID.drawingRun(intent):
      guard let drawingRunSnapshot else {
        return plotterUIRefusal(
          request,
          reason: .retainedOwnerRefused,
          currentUIRevision: currentUIRevision,
          currentRuntimeRevisions: currentRuntimeRevisions,
          remedy: "Wait for Drawing Run projection synchronization."
        )
      }
      let result = await submitDrawingRun(PlotterDrawingRunSubmission(
        projection: drawingRunSnapshot.projection,
        intent: intent
      ))
      if case .refused(let refusal) = result?.disposition {
        return plotterUIRefusal(request, reason: .retainedOwnerRefused,
          currentUIRevision: currentUIRevision, currentRuntimeRevisions: currentRuntimeRevisions,
          remedy: drawingRunRefusalDetail(refusal))
      }
    case .penInteraction(let intent):
      if case .stop = intent,
        let selectionID = pointSelectionEpisodeProjection.exactPointSelection.request?.id
      {
        // Exact Pen Stop also settles the already-admitted exact-frame
        // continuation before the Pen runtime publishes terminal state. This
        // prevents that retained continuation from reviving the cancelled
        // Learning attempt; it does not choose or issue a Pen effect.
        await pointSelectionRuntime.cancelContinuation(selectionID: selectionID)
      }
      let disposition = await submitPenInteraction(intent)
      if case .refused(let refusal) = disposition {
        return plotterUIRefusal(
          request,
          reason: .retainedOwnerRefused,
          currentUIRevision: currentPlotterUIProjection?.revision ?? currentUIRevision,
          currentRuntimeRevisions: currentPlotterUIRuntimeRevisions(),
          remedy: penInteractionRefusalText(refusal)
        )
      }
      if case .stop = intent,
        case .applied(let projection) = disposition,
        projection.reference.operationID == nil
      {
        await cancelExerciseAttempt(.humanGuidedDiscovery(.penInteraction))
      }
    case .boundary(let intent):
      guard let reference = currentBoundarySnapshot?.projection.reference else {
        return plotterUIRefusal(
          request,
          reason: .retainedOwnerRefused,
          currentUIRevision: currentUIRevision,
          currentRuntimeRevisions: currentRuntimeRevisions,
          remedy: "Wait for PlotterBoundaryRuntime projection synchronization."
        )
      }
      let disposition = await boundaryRuntime.submit(
        PlotterBoundarySubmission(projection: reference, intent: intent)
      )
      if case .refused(let refusal) = disposition {
        return plotterUIRefusal(
          request,
          reason: .retainedOwnerRefused,
          currentUIRevision: currentPlotterUIProjection?.revision ?? currentUIRevision,
          currentRuntimeRevisions: currentPlotterUIRuntimeRevisions(),
          remedy: "Boundary refused by \(refusal.owner): \(refusal.reason). Remedy: \(refusal.remedy)."
        )
      }
      installBoundarySnapshot(await boundaryRuntime.snapshot(for: reference.environment))
    case .learningAction(let learningRequest)
      where request.actionID == PlotterUIActionID(learningRequest: learningRequest):
      guard let learningTransitionID else {
        return plotterUIRefusal(
          request,
          reason: .mismatchedIntent,
          currentUIRevision: currentUIRevision,
          currentRuntimeRevisions: currentRuntimeRevisions,
          remedy: "Submit Learning actions through the model-owned episode boundary."
        )
      }
      let adapter = PlotterLearningActionabilityFactAdapter()
      guard let owner = adapter.itemID(learningRequest.item.rawValue) else {
        return plotterUIRefusal(
          request,
          reason: .unknownAction,
          currentUIRevision: currentUIRevision,
          currentRuntimeRevisions: currentRuntimeRevisions,
          remedy: "Refresh the Learning projection and use its exact current item identity."
        )
      }
      if let remedy = await submitProjectionBoundLearningAction(
        learningRequest.action,
        for: owner,
        transitionID: learningTransitionID
      ) {
        return plotterUIRefusal(
          request,
          reason: .retainedOwnerRefused,
          currentUIRevision: currentPlotterUIProjection?.revision ?? currentUIRevision,
          currentRuntimeRevisions: currentPlotterUIRuntimeRevisions(),
          remedy: remedy
        )
      }
    case .learningReset(let resetRequest)
      where request.actionID == PlotterUIActionID(rawValue: resetRequest.identity):
      guard learningTransitionID != nil else {
        return plotterUIRefusal(
          request,
          reason: .mismatchedIntent,
          currentUIRevision: currentUIRevision,
          currentRuntimeRevisions: currentRuntimeRevisions,
          remedy: "Submit Learning resets through the model-owned episode boundary."
        )
      }
      guard let plan = learningVacatePlan(resetRequest) else {
        return plotterUIRefusal(
          request,
          reason: .mismatchedIntent,
          currentUIRevision: currentUIRevision,
          currentRuntimeRevisions: currentRuntimeRevisions,
          remedy: "Refresh the exact typed Learning reset request before retrying."
        )
      }
      let succeeded: Bool
      if plan.scope == .all {
        succeeded = await submitResetAllLearning(plan)
      } else {
        succeeded = await performLearningVacate(plan)
      }
      guard succeeded else {
        return plotterUIRefusal(
          request,
          reason: .retainedOwnerRefused,
          currentUIRevision: currentUIRevision,
          currentRuntimeRevisions: currentRuntimeRevisions,
          remedy: learningAuthorityError
            ?? "Refresh the Learning reset preview and resolve the named refusal."
        )
      }
    case .retainedComparisonReview(let intent)
      where request.actionID == PlotterAppUIActionID.retainedComparison(intent):
      submitCompletedComparisonReview(
        intent == .reviewExactFrame ? .reviewComparison : .resumeLivePreview
      )
    case .controller(let controllerRequest):
      let disposition = await submitControllerSessionRequest(controllerRequest)
      let refusal: String? = switch disposition {
      case .completed: nil
      case .refused(let reason): reason
      case .cancelled: "The controller action was cancelled; preparation did not complete. Use the current control to retry."
      }
      if let refusal {
        return plotterUIRefusal(
          request,
          reason: .retainedOwnerRefused,
          currentUIRevision: currentPlotterUIProjection?.revision ?? currentUIRevision,
          currentRuntimeRevisions: currentPlotterUIRuntimeRevisions(),
          remedy: refusal
        )
      }
    case .observation(let observationRequest):
      if let reason = await submitObservationConfiguration(observationRequest) {
        return plotterUIRefusal(
          request,
          reason: .retainedOwnerRefused,
          currentUIRevision: currentPlotterUIProjection?.revision ?? currentUIRevision,
          currentRuntimeRevisions: currentPlotterUIRuntimeRevisions(),
          remedy: reason
        )
      }
    case .paper(let declaration):
      let contactPlaneChanged: Bool = switch declaration {
      case .newSheetOnCurrentPlane: false
      case .contactPlaneChanged: true
      }
      if let remedy = await recordPaperReplacement(contactPlaneChanged: contactPlaneChanged) {
        return plotterUIRefusal(
          request, reason: .retainedOwnerRefused,
          currentUIRevision: currentPlotterUIProjection?.revision ?? currentUIRevision,
          currentRuntimeRevisions: currentPlotterUIRuntimeRevisions(), remedy: remedy)
      }
    case .requestIncidentPackage where request.actionID == PlotterAppUIActionID.incidentPackage:
      await requestIncidentPackageFromPlotterUI()
    default:
      return plotterUIRefusal(
        request,
        reason: .mismatchedIntent,
        currentUIRevision: currentUIRevision,
        currentRuntimeRevisions: currentRuntimeRevisions,
        remedy: "Use the intent bound to the current action identity."
      )
    }
    return .accepted(requestID: request.id)
  }

  private func learningEpisodeResult(
    _ disposition: PlotterUIRequestDisposition,
    request: PlotterLearningRecordRequest
  ) -> PlotterLearningEpisodeResult {
    let owner = learningRecordOwner(request)
    switch disposition {
    case .accepted:
      return .accepted(owner: owner)
    case .refused(let refusal):
      let reason: PlotterLearningEpisodeRefusalReason = switch refusal.reason {
      case .staleUIRevision: .staleUIRevision
      case .staleRuntimeRevision: .staleRuntimeRevision
      case .unknownAction: .unknownAction
      case .mismatchedIntent: .mismatchedIntent
      case .unavailableAction: .unavailableAction
      case .unavailableIncidentSource, .retainedOwnerRefused: .ownerRefused
      }
      return .refused(
        reason: reason,
        owner: refusal.reason == .retainedOwnerRefused
          ? owner : EpisodeAuthorityID(rawValue: refusal.owner),
        remedy: refusal.remedy
      )
    }
  }

  private func learningRecordOwner(
    _ request: PlotterLearningRecordRequest
  ) -> EpisodeAuthorityID {
    switch request {
    case .action(let actionRequest):
      return learningActionOwner(actionRequest.action)
    case .reset:
      return EpisodeAuthorityID(rawValue: "PlotterArtifactResetRuntime")
    }
  }

  private func learningPostTransitionProjection() -> PlotterLearningPostTransitionProjection {
    let currentLearning = learningPresentationBase()
    let snapshot = currentLearning.snapshot
    return PlotterLearningPostTransitionProjection(
      stateRevision: .init(rawValue: semanticPresentationRevision),
      currentItem: .init(rawValue: plotterUILearningOwnerID(currentLearning.currentItemID)),
      activeOwner: snapshot.operations.activeAttemptOwner.map { owner in
        PlotterLearningItemIdentity(rawValue: plotterUILearningOwnerID(owner))
      },
      learningIsEnabled: snapshot.learningEnabled
    )
  }

  private func learningActionOwner(_ action: PlotterLearningAction) -> EpisodeAuthorityID {
    let rawValue: String = switch action {
    case .setPenSetpoint, .stopPenInteraction: "PlotterPenInteractionRuntime"
    case .boundary: "PlotterBoundaryRuntime"
    case .cameraCalibration: "PlotterCameraCalibrationRuntime"
    case .tipCalibration: "PlotterTipCalibrationRuntime"
    case .borderValidation: "PlotterBorderValidationRuntime"
    case .pointSelectionCorrection: "PlotterPointSelectionRuntime"
    case .applySavedLearning, .startNewLearning, .redoThisStep, .recordAnotherAttempt:
      "PlotterArtifactResetRuntime"
    case .start, .choice, .cancel, .stop, .restart, .paperReplaced:
      "PlotterApplicationRuntime"
    }
    return EpisodeAuthorityID(rawValue: rawValue)
  }

  private func requestIncidentPackageFromPlotterUI() async {
    let admission = await incidentPackageUIService.startUnavailable(
      PlotterIncidentPackageUINoSourceRequest()
    )
    switch admission {
    case .refused(let refusal):
      incidentPackageUIState = .refused(
        reason: incidentPackageNoSourceReason(refusal.reason),
        remedy: incidentPackageRemedy(refusal.remedy)
      )
    case .accepted(let updates):
      for await update in updates {
        switch update {
        case .checkingAvailability:
          incidentPackageUIState = .loading(
            phase: "Checking exact incident source availability",
            completedUnitCount: 0,
            totalUnitCount: 1
          )
        case .terminal(let refusal):
          incidentPackageUIState = .refused(
            reason: incidentPackageNoSourceReason(refusal.reason),
            remedy: incidentPackageRemedy(refusal.remedy)
          )
        }
      }
    }
  }

  private func incidentPackageNoSourceReason(
    _ reason: PlotterIncidentPackageUINoSourceRefusalReason
  ) -> String {
    switch reason {
    case .requestInProgress:
      "An incident-package availability request is already active."
    case .noCompleteSourceProvider:
      "No complete incident-package source provider is configured."
    }
  }

  private func incidentPackageRemedy(_ remedy: PlotterIncidentPackageUIRemedy) -> String {
    switch remedy {
    case .waitForActiveRequest:
      "Wait for the active request to publish its terminal result."
    case .provideCompleteSource:
      "Provide one complete, identity-bound incident source before retrying."
    case .refreshExactSource:
      "Refresh the exact incident source and retry."
    case .repairExactSource:
      "Repair the exact incident source and retry."
    case .reduceSourceToBoundedLimits:
      "Reduce the exact source to the published bounded limits."
    case .reportRuntimeIntegrityFailure:
      "Report the runtime integrity failure without treating the package as complete."
    }
  }

  private func plotterUIRefusal(
    _ request: PlotterUIRequest,
    reason: PlotterUIRequestRefusalReason,
    currentUIRevision: PlotterUIRevision,
    currentRuntimeRevisions: [PlotterUIRuntimeRevision],
    remedy: String
  ) -> PlotterUIRequestDisposition {
    .refused(PlotterUIRequestRefusal(
      requestID: request.id,
      reason: reason,
      owner: "PlotterUIIntentSink",
      submittedUIRevision: request.uiRevision,
      currentUIRevision: currentUIRevision,
      submittedRuntimeRevisions: request.runtimeRevisions,
      currentRuntimeRevisions: currentRuntimeRevisions,
      remedy: remedy
    ))
  }

  private func learningVacatePlan(
    _ request: PlotterLearningResetRequest
  ) -> LearningVacatePlan? {
    let adapter = PlotterLearningActionabilityFactAdapter()
    guard let anchor = adapter.itemID(request.anchor.rawValue) else { return nil }
    let affectedItems = request.affectedItems.compactMap { adapter.itemID($0.rawValue) }
    guard affectedItems.count == request.affectedItems.count else { return nil }
    let revisions = request.expectedCurrentRevisionIDs.compactMap { UUID(uuidString: $0) }
    guard revisions.count == request.expectedCurrentRevisionIDs.count else { return nil }
    let scope: LearningVacateScope
    switch request.scope {
    case .all:
      scope = .all
    case .from(let item):
      guard let start = adapter.itemID(item.rawValue), start == anchor else { return nil }
      scope = .from(start)
    }
    return LearningVacatePlan(
      scope: scope,
      source: request.source == .live ? .live : .simulated,
      anchor: anchor,
      affectedItems: affectedItems,
      expectedCurrentRevisionIDs: Set(revisions.map { LearningArtifactRevisionID(rawValue: $0) }),
      expectedAcceptedAttemptSequence: request.expectedAcceptedAttemptSequence,
      removesDurableMachineCheckpoint: request.removesDurableMachineCheckpoint,
      removesDurableTipCheckpoint: request.removesDurableTipCheckpoint,
      physicalInkMayRemain: request.physicalInkMayRemain
    )
  }

  private func manualUIActions(
    draft: ManualMotionDraft,
    presentation: ManualMotionPresentation
  ) -> [PlotterUIAction] {
    let jogs: [(PlotterUIActionID, String, JogDirection)] = [
      (PlotterAppUIActionID.manualXNegative, "Jog X negative", .xNegative),
      (PlotterAppUIActionID.manualXPositive, "Jog X positive", .xPositive),
      (PlotterAppUIActionID.manualYNegative, "Jog Y negative", .yNegative),
      (PlotterAppUIActionID.manualYPositive, "Jog Y positive", .yPositive),
    ]
    var actions = jogs.map { id, title, direction in
      let intent = manualJogIntent(direction, draft: draft)
      return PlotterUIAction(
        id: id,
        title: title,
        intent: intent.map(PlotterUIIntent.manualMotion) ?? .unavailableLocalInput(id),
        unavailableReason: presentation.jogControlsUnavailableReason
          ?? (intent == nil ? "Enter finite positive jog distance and feed values." : nil)
      )
    }
    let raisingPen: Bool = if case .setPen(let request) = manualMotionEpisodeSnapshot?.activeOperation?.intent {
      request.position == .raised
    } else { false }
    actions.append(PlotterUIAction(
      id: PlotterAppUIActionID.manualPenUp,
      title: raisingPen ? "Raising Pen…" : "Raise Pen",
      intent: .manualMotion(manualPenIntent(.raise)),
      unavailableReason: presentation.penUpUnavailableReason
    ))
    actions.append(PlotterUIAction(
      id: PlotterAppUIActionID.manualPenDown,
      title: "Pen Down",
      intent: .manualMotion(manualPenIntent(.lower)),
      unavailableReason: presentation.penDownUnavailableReason
    ))
    if let stop = presentation.stopAction {
      actions.append(PlotterUIAction(
        id: PlotterAppUIActionID.manualStop,
        title: stop.title,
        intent: .manualStop(capabilityID: stop.capabilityID.rawValue)
      ))
    }
    if let recovery = presentation.publicationRecovery {
      actions.append(PlotterUIAction(
        id: PlotterAppUIActionID.manualRecovery,
        title: recovery.title,
        intent: .manualPublicationRecovery(capabilityID: recovery.capabilityID.rawValue)
      ))
    }
    if let evidence = presentation.evidenceDisposition {
      let disposition: PlotterUIManualEvidenceDisposition =
        evidence.action.disposition == .acknowledgeAmbiguity
        ? .acknowledgeAmbiguity : .acknowledgePossibleInk
      actions.append(PlotterUIAction(
        id: PlotterAppUIActionID.manualEvidence,
        title: evidence.title,
        intent: .manualEvidenceDisposition(
          effectID: evidence.action.effectID.rawValue,
          environment: evidence.action.environment,
          observationID: evidence.action.observationID.rawValue,
          disposition: disposition
        )
      ))
    }
    return actions
  }

  func uncachedLearningPathProjectionForTesting(
    selectedItemID: LearningPathItemID
  ) -> LearningPathProjection {
    let base = buildLearningPresentationBase(revision: semanticPresentationRevision)
    if selectedItemID == base.currentItemID { return base.currentProjection }
    computationDiagnostics.learningProjectionBuildCount += 1
    computationDiagnostics.selectedLearningProjectionBuildCount += 1
    let actionability = PlotterLearningActionabilityFactAdapter().compile(
      base.snapshot,
      selectedItemID: selectedItemID
    )
    return PlotterLearningDetailedPresentationNormalizer().project(
      base.snapshot,
      selectedItemID: selectedItemID,
      actionability: actionability
    )
  }

  private func learningPresentationBase() -> LearningPresentationBase {
    let currentCameraIsLive = cameraIsLive
    if let cached = learningPresentationBaseCache,
      cached.revision == semanticPresentationRevision,
      cached.cameraIsLive == currentCameraIsLive
    {
      computationDiagnostics.learningProjectionCacheHitCount += 1
      return cached
    }
    // Reading presentation cannot publish semantic state or schedule planning.
    // Freshness is an explicit cache input; frame arrival publishes transitions.
    let revision = semanticPresentationRevision
    let base = buildLearningPresentationBase(revision: revision)
    learningPresentationBaseCache = base
    return base
  }

  private func buildLearningPresentationBase(revision: UInt64) -> LearningPresentationBase {
    computationDiagnostics.learningSnapshotWithoutResetBuildCount += 1
    let resetFreeSnapshot = learningPathProjectionSnapshot()
    computationDiagnostics.currentLearningItemBuildCount += 1
    let factAdapter = PlotterLearningActionabilityFactAdapter()
    let resetFreeActionability = factAdapter.compile(
      resetFreeSnapshot,
      selectedItemID: .humanGuidedDiscovery(.penInteraction)
    )
    let currentItemID = factAdapter.itemID(resetFreeActionability.learning.currentOwnerID)
      ?? .humanGuidedDiscovery(.penInteraction)
    let plans = makeLearningVacatePlans(currentItemID: currentItemID)
    let completeSnapshot = resetFreeSnapshot.replacingReset(
      .init(
        plansByAnchor: plans.plansByAnchor,
        resetAllPlan: plans.resetAllPlan,
        unavailableReason: artifactResetUnavailableReason,
        authorityError: learningAuthorityError
      )
    )
    computationDiagnostics.learningSnapshotWithResetBuildCount += 1
    computationDiagnostics.learningProjectionBuildCount += 1
    let actionability = factAdapter.compile(
      completeSnapshot,
      selectedItemID: currentItemID
    )
    let projection = PlotterLearningDetailedPresentationNormalizer().project(
      completeSnapshot,
      selectedItemID: currentItemID,
      actionability: actionability
    )
    recordLearningActionStripDiagnostic(projection)
    return LearningPresentationBase(
      revision: revision,
      cameraIsLive: cameraIsLive,
      snapshot: completeSnapshot,
      actionability: actionability,
      currentItemID: currentItemID,
      currentProjection: projection
    )
  }

  private func recordLearningActionStripDiagnostic(_ projection: LearningPathProjection) {
    let signature = LearningActionStripDiagnosticSignature(
      ownerID: PlotterLearningActionabilityFactAdapter().itemID(
        projection.currentActionStrip?.ownerID
      ),
      actions: projection.currentActionStrip?.actions.map(\.kind) ?? []
    )
    if signature != lastLearningActionStripDiagnosticSignature {
      lastLearningActionStripDiagnosticSignature = signature
      computationDiagnostics.record(
        .learningActionStripChanged(
          ownerID: signature.ownerID,
          actions: signature.actions
        )
      )
    }
  }

  private func learningPathProjectionSnapshot() -> PlotterLearningPresentationFacts {
    let borderValidation = borderValidationSnapshot
    let boundarySnapshot = currentBoundarySnapshot
    let acceptedBoundaryAggregates = boundarySnapshot?.acceptedAggregates ?? [:]
    let acceptedBoundaryEvidence = Dictionary(uniqueKeysWithValues:
      (boundarySnapshot?.acceptedEvidence ?? []).map { ($0.attemptID, $0) }
    )
    let boundaryProgress = boundarySnapshot?.pairedProgress ?? PairedBoundaryProgress()
    let selectedBoundary = boundarySnapshot?.projection.selectedDirection
      .runtimeDirection ?? .positiveX
    let currentPosition = try? currentMachinePosition()
    let centerTravelFeed: TravelFeedSelection? =
      if let center = boundarySnapshot?.estimatedCenter,
        let currentPosition,
        let delta = try? Vector2<MachineSpace>(
          dx: center.point.x - currentPosition.point.x,
          dy: center.point.y - currentPosition.point.y
        )
      {
        travelFeedSelection(for: delta)
      } else { nil }
    let boundaryTravelFeeds = Dictionary(
      uniqueKeysWithValues: BoundaryDirection.allCases.map {
        ($0, boundaryTravelFeedSelection())
      }
    )
    let stopOwner: PlotterLearningPresentationFacts.StopOwner? = {
      guard let target = activeStopTarget else { return nil }
      switch target {
      case .exerciseMotion(let id, let owner, _, let action):
        _ = owner
        return .exercise(id, action, boundaryOwner: false)
      case .borderValidation(let id, _): return .borderValidation(id)
      case .positionRecovery(let id): return .positionRecovery(id)
      case .sparseTipBatch(let id, _), .sparseTipBatchSegment(let id, _, _):
        return .sparseTipBatch(id)
      }
    }()
    let savedCheckpointMatchesPaper =
      recoverableTipCalibrationCheckpoint.map {
        $0.registration.applicability.paperContactPlane.rawValue
          == explorationPaperContactPlaneRevision
      } ?? tipCalibrationRuntime.positionRecoveryIsAvailable
    let itemStartReasons = Dictionary(
      uniqueKeysWithValues: LearningPathItemID.learningExerciseOrder.compactMap {
        itemID -> (LearningPathItemID, String)? in
        let reason: String?
        switch itemID {
        case .humanGuidedDiscovery(.penInteraction):
          reason = activeDiscoverySequenceID == .penInteraction
            ? learningConnectionAndMotionUnavailableReason
            : discoveryStartUnavailableReason(for: .penInteraction)
        case .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering):
          reason = retainedPoseApplicabilityRefusal ?? boundarySnapshot?.projection.lastRefusal.map {
            "Boundary refused: \($0.reason). Remedy: \($0.remedy)."
          }
        case .humanGuidedDiscovery(.calibrateCameraAndVisibleCap):
          reason = learningExerciseMotionUnavailableReason(requiresCamera: true)
        case .humanGuidedDiscovery(.calibratePenContactFromSparseMarks):
          // Marking owns an initial settled Pen Up; capture-only checkpoint
          // revalidation still requires the current pen to already be up.
          reason = savedCheckpointMatchesPaper
            ? positionRevalidationUnavailableReason
            : learningExerciseMotionUnavailableReason(requiresCamera: true, normalizesPenUp: true)
        case .borderValidation(let step):
          reason = borderValidationActionUnavailableReason(
            for: step == .chooseDrawingBorderPlan ? borderValidation.step : step
          )
        case .stage:
          reason = nil
        }
        return reason.map { (itemID, $0) }
      }
    )
    let savedTrainingCandidate = savedLearningApplicationCandidate.map { candidate in
      PlotterLearningPresentationFacts.SavedTrainingFacts(
        checkpointID: candidate.checkpoint.checkpointID,
        artifactSummary: savedTrainingArtifactSummary(candidate.checkpoint),
        opticalComparison: candidate.opticalComparison
      )
    }
    return PlotterLearningPresentationFacts(
      source: frameMode,
      learningEnabled: learningIsEnabled,
      penInteractionCompleted: penInteractionCompleted,
      penInteraction: currentPenInteractionSnapshot?.projection,
      penActuationProfile: effectivePenActuationProfile,
      selectedBoundaryDirection: selectedBoundary,
      controller: .init(
        sessionEstablished: sessionEstablished,
        motionAuthorized: sessionMotionAuthorized,
        cameraStateText: cameraStateText,
        cameraDeliveryLimitOutcome: cameraSnapshot?.diagnostics.deliveryLimitOutcome
          ?? .notRequested,
        machineError: controllerAttentionText,
        controllerTravelUnavailableReason: learningCarriageMotionUnavailableReason
      ),
      boundary: .init(
        projection: boundarySnapshot?.projection,
        acceptedDirections: boundaryProgress.acceptedDirections,
        allowedDirections: boundaryProgress.allowedDirections,
        isComplete: boundaryProgress.isComplete,
        aggregates: acceptedBoundaryAggregates,
        attemptEvidence: acceptedBoundaryEvidence,
        estimatedCenter: boundarySnapshot?.estimatedCenter,
        localFrame: boundarySnapshot?.localCoordinateFrame,
        centerArrival: boundarySnapshot?.centerArrivalPosition,
        centerArrivalRetryRequired: boundarySnapshot?.projection.centerArrivalRetryRequired ?? false,
        currentPosition: currentPosition,
        centerTravelFeed: centerTravelFeed,
        boundaryTravelFeeds: boundaryTravelFeeds
      ),
      cameraCalibration: .init(
        accepted: machineCameraRegistration,
        proposed: proposedMachineCameraRegistration,
        acceptedIsCurrent: machineCameraRegistration != nil
          && learningArtifactGraph.currentRevision(for: .machineCameraRegistration) != nil,
        hasProposal: proposedMachineCameraRegistration != nil,
        phase: cameraCalibrationRuntimePhase,
        failure: currentCameraCalibrationFailure,
        lastOutcome: cameraCalibrationRuntime.snapshot().terminalHistory.last?.outcome
      ),
      sparseCalibration: .init(
        accepted: tipCameraRegistration,
        proposed: proposedTipCameraRegistration,
        acceptedIsCurrent:
          tipCameraRegistration.map {
            learningArtifactGraph.currentRevision(for: .tipCameraRegistration)?.id
              == $0.acceptedRevisionID
          } ?? false,
        phase: tipCalibrationRuntime.phase,
        acceptedObservationCount: tipCalibrationRuntime.acceptedObservations.count,
        collectedClickCount: selectedToolContactPoints.count,
        blacklistedPositionCount: tipCalibrationRuntime.blacklistedPositions.count,
        savedCheckpointMatchesPaper: savedCheckpointMatchesPaper
      ),
      drawing: .init(
        currentStep: borderValidation.step,
        phase: borderValidation.phase,
        decisionIsInFlight:
          borderValidation.activeStep == .compareIntendedAndObservedGeometry,
        drawingBorderPath: borderValidation.drawingBorderPlan?.strokes.first?.path.points.map(
          MachinePosition.init(point:)
        ) ?? [],
        localBaselineFrameID: borderValidation.localPreFrameBaseline?.frame.id.rawValue,
        drawingBorderSettled: borderValidation.drawingOutcome.map {
          if case .completed = $0 { return true }
          return false
        } ?? false,
        inkStatus: borderValidation.inkStatus,
        assessment: borderValidation.assessment,
        lastTravelFeed: borderValidation.lastTravelFeedSelection
      ),
      operations: .init(
        activeAttemptOwner: activeExerciseAttemptOwnerID,
        restartableItem: restartableExerciseItemID,
        stopOwner: stopOwner,
        stopDispositionLatched: stopDispositionLatch != nil,
        stickyAmbiguityReason: learningStickyAmbiguityReason,
        explorationFailure: explorationError.map(WorkflowFailure.failed),
        discoveryFailure: discoveryError.map(WorkflowFailure.failed),
        lastStopAudit: lastContextualStopAuditRecord,
        exactWorkflowVisionOwner: exactWorkflowVisionOwner,
        visionState: visionAnalysisSnapshot.phase.state
      ),
      discovery: discoveryTransactions.mapValues { transaction in
        PlotterLearningPresentationFacts.DiscoveryFacts(
          id: transaction.id,
          sequenceID: transaction.definition.id,
          title: transaction.definition.title,
          state: transaction.state,
          currentStep: transaction.currentStep,
          completedStepCount: transaction.completedStepCount,
          totalStepCount: transaction.definition.steps.count,
          evidenceSummaries: transaction.evidenceSummaries.map(\.summary)
        )
      },
      startUnavailableReasons: itemStartReasons,
      acceptedCheckpointStatus: acceptedArtifactCheckpointStatus,
      savedTrainingCandidate: savedTrainingCandidate,
      reset: .init()
    )
  }

  func answerCurrentQuestion(_ choice: OperatorChoice) async {
    guard applicationAdmissionIsOpen, let sequenceID = activeDiscoverySequenceID else { return }
    await answerDiscoverySequence(choice, for: sequenceID)
  }

  private func submitProjectionBoundLearningAction(
    _ kind: PlotterLearningAction,
    for ownerID: LearningPathItemID,
    transitionID: PlotterLearningTransitionID
  ) async -> String? {
    guard learningIsEnabled else { return "Enable Learning before retrying." }
    guard !learningResetInProgress else { return "Wait for the Learning reset to settle." }
    guard applicationAdmissionIsOpen else {
      return "The application is shutting down; no successor Learning effect can start."
    }

    switch kind {
    case .setPenSetpoint(let command, let value):
      let disposition = await submitPenInteraction(.setpoint(
        command: command == .raise ? .raise : .lower,
        value: value
      ))
      if case .refused(let refusal) = disposition { return penInteractionRefusalText(refusal) }
      return nil
    case .stopPenInteraction(let capability):
      if let selectionID = pointSelectionEpisodeProjection.exactPointSelection.request?.id {
        await pointSelectionRuntime.cancelContinuation(selectionID: selectionID)
      }
      let disposition = await submitPenInteraction(.stop(capability))
      if case .refused(let refusal) = disposition { return penInteractionRefusalText(refusal) }
      if case .applied(let projection) = disposition, projection.reference.operationID == nil {
        await cancelExerciseAttempt(.humanGuidedDiscovery(.penInteraction))
      }
      return nil
    case .boundary(let intent):
      guard let reference = currentBoundarySnapshot?.projection.reference else {
        return "Wait for PlotterBoundaryRuntime projection synchronization."
      }
      let disposition = await boundaryRuntime.submit(
        PlotterBoundarySubmission(projection: reference, intent: intent)
      )
      if case .refused(let refusal) = disposition {
        return "Boundary refused by \(refusal.owner): \(refusal.reason). Remedy: \(refusal.remedy)."
      }
      installBoundarySnapshot(await boundaryRuntime.snapshot(for: reference.environment))
      return nil
    case .cameraCalibration(let action):
      let intent: PlotterCameraCalibrationIntent = switch action {
      case .buildFivePositionProposal: .buildFivePositionProposal
      case .acceptProposal: .acceptProposal
      case .rejectProposal: .rejectProposal
      }
      let outcome = await cameraCalibrationRuntime.submit(intent)
      markSemanticPresentationChanged()
      switch outcome {
      case .completed: return nil
      case .refused(let reason), .failed(let reason): return reason
      case .cancelled: return "Camera calibration was cancelled. Refresh before retrying."
      }
    case .tipCalibration(let action):
      let intent: PlotterTipCalibrationIntent = switch action {
      case .beginFourMarkBatch: .beginFourMarkBatch
      case .captureNewClickFrame(let count):
        .captureNewClickFrame(retainedPointCount: count)
      case .revalidateCheckpoint: .revalidateCheckpoint
      case .acceptProposal: .acceptProposal
      case .rejectProposal: .rejectProposal
      case .retryCommit: .retryCommit
      }
      let outcome: PlotterTipCalibrationSubmissionOutcome
      if case .revalidateCheckpoint = intent {
        let target = ContextualStopTarget.positionRecovery(capabilityID: ContextualStopCapabilityID())
        var result: PlotterTipCalibrationSubmissionOutcome?
        let task = Task { @MainActor in
          result = await self.tipCalibrationRuntime.submit(intent)
        }
        installStoppableOperation(target: target, owner: .batch(task))
        await task.value
        clearStoppableOperation(matching: target)
        outcome = result ?? .cancelled
      } else {
        outcome = await tipCalibrationRuntime.submit(intent)
      }
      markSemanticPresentationChanged()
      switch outcome {
      case .completed: return nil
      case .refused(let reason), .failed(let reason): return reason
      case .cancelled: return "Pen-tip calibration was cancelled. Refresh before retrying."
      }
    case .borderValidation(let action):
      let intent: PlotterBorderValidationIntent = switch action {
      case .acceptObservedPrediction: .acceptObservedPrediction
      case .reject(let reason): .reject(reason)
      }
      await submitBorderValidationDecision(intent)
      return nil
    case .pointSelectionCorrection(let intent):
      await performPointSelectionCorrection(intent)
      markSemanticPresentationChanged()
      return nil
    case .cancel:
      await cancelExerciseAttempt(ownerID)
      return nil
    case .stop(let capabilityID):
      guard ownerID == activeExerciseAttemptOwnerID else {
        return "Refresh the current Learning owner before stopping."
      }
      await stopCurrentOperation(capabilityID: capabilityID)
      return nil
    default:
      break
    }

    guard activeLearningActionTask == nil else {
      return "Wait for the active Learning action to settle before retrying."
    }
    let task: Task<String?, Never> = Task { @MainActor [weak self] in
      guard let self else { return "The Learning owner was released before admission." }
      return await self.performAdmittedExerciseAction(kind, for: ownerID)
    }
    activeLearningActionTask = PlotterApplicationLearningTask(
      transitionID: transitionID,
      task: task
    )
    let remedy = await task.value
    if activeLearningActionTask?.transitionID == transitionID {
      activeLearningActionTask = nil
    }
    return remedy
  }

  private func performAdmittedExerciseAction(
    _ kind: PlotterLearningAction,
    for ownerID: LearningPathItemID
  ) async -> String? {
    guard applicationAdmissionIsOpen, !Task.isCancelled else {
      return "The Learning action was cancelled before its owner settled."
    }
    switch kind {
    case .boundary:
      return "Refresh the exact Boundary request before retrying."
    case .applySavedLearning:
      guard await artifactResetRuntime.submit(
        .applySavedLearning,
        facts: artifactResetAdmissionFacts
      ) else { return artifactResetRuntime.snapshot().phase.detail }
    case .startNewLearning:
      guard await artifactResetRuntime.submit(
        .retainSavedLearning,
        facts: artifactResetAdmissionFacts
      ) else { return artifactResetRuntime.snapshot().phase.detail }
    case .start:
      await startExercise(ownerID, mode: .normal)
    case .choice(let choice):
      guard ownerID == activeExerciseAttemptOwnerID else {
        return "Refresh the current Learning owner before answering."
      }
      await answerCurrentQuestion(PlotterLearningActionabilityFactAdapter().operatorChoice(choice))
    case .cancel, .stop:
      return "Refresh the exact Learning cancellation request before retrying."
    case .restart:
      guard restartableExerciseItemID == ownerID else {
        return "The Learning item is no longer restartable; refresh before retrying."
      }
      restartableExerciseItemID = nil
      await startExercise(ownerID, mode: .normal)
    case .redoThisStep:
      guard await artifactResetRuntime.submit(
        .redoStep(PlotterArtifactResetStepID(rawValue: ownerID.number)),
        facts: artifactResetAdmissionFacts
      ) else { return artifactResetRuntime.snapshot().phase.detail }
    case .recordAnotherAttempt:
      guard await artifactResetRuntime.submit(
        .recordAnotherAttempt(PlotterArtifactResetStepID(rawValue: ownerID.number)),
        facts: artifactResetAdmissionFacts
      ) else { return artifactResetRuntime.snapshot().phase.detail }
    case .cameraCalibration, .setPenSetpoint, .stopPenInteraction:
      return "Refresh the exact feature-runtime Learning request before retrying."
    case .tipCalibration, .borderValidation, .pointSelectionCorrection:
      return "Refresh the exact feature-runtime Learning request before retrying."
    case .paperReplaced:
      await recordPaperReplacement(contactPlaneChanged: false)
    }
    guard !Task.isCancelled else { return "The Learning action was cancelled before settlement." }
    markSemanticPresentationChanged()
    return nil
  }

  private func applySavedLearningEffect() async throws -> (
    AcceptedLearningPathCheckpoint, String
  ) {
    guard let candidate = savedLearningState.applicationCandidate else {
      throw LearningPathOperationError.requiredState("No accepted Saved Learning package is available.")
    }
    let (checkpoint, opticalComparison) = candidate
    if savedLearningState.candidate == nil {
      guard tipCameraRegistration == nil else {
        throw LearningPathOperationError.requiredState("Accepted calibration is already active.")
      }
      if let reason = savedLearningRecoveryUnavailableReason(checkpoint) {
        throw LearningPathOperationError.requiredState(reason)
      }
    }
      let restoredGraph = try checkpoint.restoredLearningGraph()
      let restoredPenProfile = checkpoint.penInteraction?.evidence.actuationProfile ?? .initialDefaults
      // Validate the complete package before changing any current owner. A
      // changed accepted profile invalidates commanded pen knowledge only;
      // loading Saved Learning never actuates the pen or moves the carriage.
      if let machineSession {
        let priorSelection = selectedSerialDevice?.identifier
        let priorSession = controllerSessionID
        let ownsPublishedSnapshot = priorSelection != nil
          && machineSnapshot?.machine.link.identifier == priorSelection
        guard await machineSession.reconcilePenActuationProfile(restoredPenProfile) else {
          throw LearningPathOperationError.requiredState(
            "Wait for the current controller operation to finish before applying Saved Learning."
          )
        }
        // Loading settings cannot claim an unselected lower controller for this
        // application. Refresh only the already-published matching session.
        if ownsPublishedSnapshot {
          let refreshed = await machineSession.snapshot()
          if frameMode == .live, controllerSessionID == priorSession,
            selectedSerialDevice?.identifier == priorSelection,
            refreshed == nil || refreshed?.machine.link.identifier == priorSelection {
            machineSnapshot = refreshed
          }
        }
      }
      await penInteractionRuntime.restore(checkpoint.penInteraction, environment: .live)
      installPenInteractionSnapshot(
        await penInteractionRuntime.snapshot(environment: .live)
      )
      let machine = checkpoint.machineArtifacts
      if let machine {
        try await boundaryRuntime.restore(machine, environment: .live)
        installBoundarySnapshot(await boundaryRuntime.snapshot(for: .live))
      }

      // All fallible validation and dependency reconstruction has completed.
      // Install the exact saved prefix as one selected-session transition,
      // without motion, command replay, ownership restoration, or Pen-pose
      // restoration.
      mutateActiveLearningSession { session in
        session.learningArtifactGraph = restoredGraph
        session.activeMachineArtifactCheckpoint = machine
        session.activeMachineCameraCheckpoint = checkpoint.machineCamera
        session.activeStageFourCheckpoint = checkpoint.stageFour
        if let machine {
          session.explorationCoordinateRevision = machine.coordinateRevision
          session.acceptedAttemptSequence = max(
            session.acceptedAttemptSequence,
            machine.acceptedAttemptSequence
          )
        }
        if let pen = checkpoint.penInteraction {
          session.acceptedAttemptSequence = max(
            session.acceptedAttemptSequence,
            pen.acceptedSequence
          )
        }
        session.acceptedArtifactCheckpointStatus = .appliedByOperator(
          sideCount: machine?.acceptedBoundaryAggregates.count ?? 0,
          hasTipCalibration: checkpoint.tipCalibration != nil
        )
        session.learningAuthorityError = nil
        session.explorationError = nil
      }
      tipCameraRegistration = checkpoint.tipCalibration?.registration
      proposedTipCameraRegistration = nil
      machineCameraRegistration = checkpoint.machineCamera?.registration
      if let appearance = checkpoint.penCapAppearance {
        let selection = PenCapAppearanceSelection(checkpoint: appearance)
        livePenCapAppearanceSelection = selection
        persistedPenCapAppearanceLoadState = .accepted
        await reconcileAutomaticVisionAnalysis()
      }
      restoreInteractiveLearningCompletionFromEvidence()
      requireVisualPositionRevalidation(checkpoint: checkpoint.tipCalibration)
      return (checkpoint, opticalComparison)
  }

  private func retainSavedLearningEffect() throws -> AcceptedLearningPathCheckpoint {
    guard let checkpoint = savedLearningState.applicationCandidate?.checkpoint
    else { throw LearningPathOperationError.requiredState("No Saved Learning decision is pending.") }
    acceptedArtifactCheckpointStatus = .retainedForLater(
      sideCount: checkpoint.machineArtifacts?.acceptedBoundaryAggregates.count ?? 0,
      hasTipCalibration: checkpoint.tipCalibration != nil
    )
    learningAuthorityError = nil
    explorationError = nil
    return checkpoint
  }

  private func startPenInteractionEpisode(mode: ExerciseAttemptMode) async {
    guard discoveryStartUnavailableReason(for: .penInteraction) == nil else { return }
    if let selectionID = pointSelectionEpisodeProjection.exactPointSelection.request?.id {
      await pointSelectionRuntime.cancelContinuation(selectionID: selectionID)
    }
    beginExerciseAttempt(
      ownerID: .humanGuidedDiscovery(.penInteraction),
      mode: mode
    )
    guard let attemptID = activeExerciseAttemptID else { return }
    let admission = await submitPenInteraction(.start(
      mode: penInteractionAttemptMode(mode),
      attemptID: attemptID.rawValue
    ))
    guard case .applied = admission else {
      finishActiveExerciseAttempt(disposition: .refused(discoveryError ?? "Pen Interaction refused."))
      return
    }
    do {
      let boundary = displayedFrame?.frame.captureNanoseconds ?? 0
      var frame: DisplayedFrame?
      if frameMode == .live, livePenCapAppearanceSelection != nil, sceneAnalysisIsRequested {
        do {
          if let inspection = try await inspectWorkflowScene(
            owner: .penCapAppearance,
            newerThan: boundary,
            requestedFeatures: requestedSceneFeatures,
            analysisRegion: videoAnalysisRegionLock?.region
          ) {
            frame = inspection.displayedFrame
            displayedFrame = inspection.displayedFrame
            latestLiveCameraFrame = inspection.displayedFrame
            lastSceneMeasurement = inspection.measurement
            overlayResultChannels.publishScene(
              overlayChannelResult(
                displayedFrame: inspection.displayedFrame,
                measurement: inspection.measurement
              )
            )
          }
        } catch {
          visionError =
            "Frozen-frame overlay analysis failed — \(actionableDescription(error))"
        }
      }
      if frame == nil {
        frame = try await captureProtocolFrame(newerThan: boundary)
      }
      guard let frame else {
        throw LearningPathOperationError.freshFrameUnavailable
      }
      let staged = try await pointSelectionRuntime.stage(
        frame: frame,
        presentationTransformRevision: PlotterPresentationTransformRevision(),
        prompt: "Click the pen cap body—not the tip—on the current camera frame.",
        purpose: .penCapAppearance,
        requiredPointCount: 1
      )
      installPointSelectionProjection(staged.projection)
      pendingToolContactEvidence = []
      pendingToolContactClickFrame = nil
      frozenPointSelectionFrame = frame
      pointSelectionRecordingDiagnostic =
        staged.recordingDiagnostic ?? pointSelectionRecordingDiagnostic
      discoveryError = nil
    } catch {
      discoveryError =
        "Identify Pen Cap could not freeze an exact frame: \(actionableDescription(error))"
      _ = await submitPenInteraction(.finish(.failed(String(describing: error))))
      finishActiveExerciseAttempt(disposition: .failed(String(describing: error)))
      restartableExerciseItemID = .humanGuidedDiscovery(.penInteraction)
    }
  }

  private func penInteractionAttemptMode(
    _ mode: ExerciseAttemptMode
  ) -> PlotterPenInteractionAttemptMode {
    switch mode {
    case .normal: .normal
    case .replacement: .replacement
    case .additional: .additional
    }
  }

  private func penInteractionTerminalDisposition(
    _ disposition: ExerciseAttemptDisposition
  ) -> PlotterPenInteractionTerminalDisposition {
    switch disposition {
    case .succeeded:
      .failed("A successful Pen Interaction must publish accepted evidence atomically.")
    case .refused(let reason): .refused(reason)
    case .unclear(let reason): .unclear(reason)
    case .cancelled: .cancelled
    case .ambiguous(let reason): .ambiguous(reason)
    case .failed(let reason): .failed(reason)
    }
  }

  private func captureProtocolFrame(newerThan boundary: UInt64) async throws -> DisplayedFrame {
    guard let observationRuntime else { throw LearningPathOperationError.freshFrameUnavailable }
    if frameMode == .simulated {
      let scene = try await captureSimulatedProtocolScene(newerThan: boundary)
      guard
        scene.displayedFrame.frame.captureNanoseconds
          > lastSimulatedProtocolCaptureNanoseconds
      else {
        throw LearningPathOperationError.freshFrameUnavailable
      }
      lastSimulatedProtocolCaptureNanoseconds = scene.displayedFrame.frame.captureNanoseconds
      applySimulatedProtocolScene(scene)
      return scene.displayedFrame
    }
    guard let frame = try await observationRuntime.captureFrame(newerThanNanoseconds: boundary),
      frame.frame.captureNanoseconds > boundary
    else { throw LearningPathOperationError.freshFrameUnavailable }
    displayedFrame = frame
    latestLiveCameraFrame = frame
    return frame
  }

  private func captureSimulatedProtocolScene(
    newerThan captureNanoseconds: UInt64 = 0
  ) async throws -> SimulatedLearningSceneFrame {
    let evidenceByAttemptID = Dictionary(
      uniqueKeysWithValues: (currentBoundarySnapshot?.acceptedEvidence ?? []).map {
        ($0.attemptID, $0)
      }
    )
    let acceptedPositions = Dictionary(
      uniqueKeysWithValues: acceptedBoundaryAggregates.compactMap {
        direction, aggregate -> (BoundaryDirection, SimulatedLearningMPos)? in
        guard let attemptID = aggregate.includedAttemptIDs.last,
          let evidence = evidenceByAttemptID[attemptID],
          let position = try? SimulatedLearningMPos(
            xMM: evidence.finalPosition.point.x,
            yMM: evidence.finalPosition.point.y
          )
        else { return nil }
        return (direction, position)
      })
    let learnedCenter = currentBoundarySnapshot?.estimatedCenter.flatMap {
      try? SimulatedLearningMPos(xMM: $0.point.x, yMM: $0.point.y)
    }
    let scene = try await simulatedLearningRuntime.captureSceneFrame(
      annotationContext: SimulatedLearningAnnotationContext(
        acceptedBoundaryPositions: acceptedPositions,
        learnedCenter: learnedCenter
      ),
      newerThanCaptureNanoseconds: captureNanoseconds
    ).result.get()
    simulatedLearningSnapshot = await simulatedLearningRuntime.snapshot()
    return scene
  }

  private func applySimulatedProtocolScene(_ scene: SimulatedLearningSceneFrame) {
    displayedFrame = scene.displayedFrame
    simulatedAnnotations = scene.annotations
    simulatedViewportID = scene.viewportID
    let provenance = ExactFrameOverlayProvenance(scene.displayedFrame)
    let overlays = [
      CameraOverlayMeasurement(
        frameID: scene.displayedFrame.frame.id,
        cameraConfigurationID: scene.displayedFrame.frame.cameraConfigurationID,
        geometry: .point(scene.capAnchorPoint),
        provenance: CameraMeasurementProvenance(
          kind: .penCap,
          source: .simulated,
          algorithmRevision: "causal-learning-simulator-v1"
        )
      ),
      CameraOverlayMeasurement(
        frameID: scene.displayedFrame.frame.id,
        cameraConfigurationID: scene.displayedFrame.frame.cameraConfigurationID,
        geometry: .bounds(scene.armatureBounds),
        provenance: CameraMeasurementProvenance(
          kind: .armatureEstimate,
          source: .simulated,
          algorithmRevision: "causal-learning-simulator-v1"
        )
      ),
    ]
    let frameSequence = scene.displayedFrame.frame.sequence
    let statuses: [UserSceneOverlay: OverlayLayerStatus] = [
      .penCap: OverlayLayerStatus(
        state: .available,
        message: OverlayStatusGrammar.simulatedPenCapAvailable(frame: frameSequence),
        provenance: provenance
      ),
      .armatureEnvelope: OverlayLayerStatus(
        state: .available,
        message: OverlayStatusGrammar.simulatedArmatureAvailable(frame: frameSequence),
        provenance: provenance
      ),
    ]
    overlayResultChannels.publishSimulation(
      OverlayChannelResult(
        displayedFrame: scene.displayedFrame,
        overlays: overlays,
        statuses: statuses
      )
    )
    simulatorPenState = simulatedLearningSnapshot?.penPose == .down ? .down : .up
    simulatorLearningSummary =
      "causal scene · MPos X \(scene.controllerPosition.xMM) Y \(scene.controllerPosition.yMM) · persistent ink segments \(scene.inkSegmentCount)"
  }

  func executeCameraCalibrationEffect(
    _ request: PlotterCameraCalibrationEffectRequest
  ) async -> PlotterCameraCalibrationEffectResult {
    guard applicationAdmissionIsOpen else { return .cancelled }
    switch request {
    case .captureReference:
      do {
        let reference = try await captureCameraCalibrationReferenceEffect()
        return .completed(.reference(
          frame: reference.frame,
          position: reference.position,
          capAnchor: reference.capAnchor
        ))
      } catch {
        return .failed(cameraCalibrationEffectFailure(actionableDescription(error)))
      }
    case .buildFivePositionProposal:
      return .failed(cameraCalibrationEffectFailure("The runtime must request the individual five-position facts."))
    case .acceptProposal(_, let registration):
      do {
        try acceptCameraCalibrationProposalEffect(registration)
        return .completed(.accepted(registration))
      } catch {
        return .failed(cameraCalibrationEffectFailure(actionableDescription(error)))
      }
    case .rejectProposal:
      rejectCameraCalibrationProposalEffect()
      return .completed(.rejected)
    case .fivePositionPlan(_, let reference):
      do {
        let plan = try CurrentCameraCalibrationPlan(
          targetPosition: reference,
          acceptedBoundaryAggregates: acceptedBoundaryAggregates,
          controllerSessionID: controllerSessionID,
          coordinateRevision: explorationCoordinateRevision
        )
        guard let frame = cameraCalibrationAnchorFrame else {
          return .failed(cameraCalibrationEffectFailure("The exact reference frame is unavailable."))
        }
        return .completed(.fivePositionPlan(.init(
          samplePositions: plan.samplePositions,
          motionDeltas: plan.motionDeltas,
          applicabilityRectangle: plan.applicabilityRectangle,
          opticalConfiguration: try exactTipCalibrationFrame(frame).opticalConfiguration,
          machineGeometry: machineGeometryIdentity,
          controllerSessionID: controllerSessionID,
          coordinateRevision: explorationCoordinateRevision
        )))
      } catch { return .failed(cameraCalibrationEffectFailure(actionableDescription(error))) }
    case .captureSample(let operationID, _, let expected):
      do {
        guard MachinePositionAcceptancePolicy.accepts(
          try await currentSettledMachinePositionForEffect(),
          target: expected
        )
        else {
          throw LearningPathOperationError.requiredState("Camera calibration is not at its required sample position.")
        }
        let capture = try await captureCurrentCameraCapAnchorEvidence(
          contextBaseline: nil, operationID: operationID.rawValue
        )
        return .completed(.sample(capture.evidence))
      } catch { return .failed(cameraCalibrationEffectFailure(actionableDescription(error))) }
    case .moveAndCapture(let operationID, let sample, let expected, let delta):
      do {
        let ownerID = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
        let final = try await performSupervisedPenUpTravel(
          delta: delta, ownerID: ownerID,
          action: .cameraCalibrationSample(index: sample + 1, total: 5)
        )
        guard recordProtocolPoseSettlement(
          action: .cameraCalibrationSample(index: sample + 1, total: 5), target: expected, actual: final
        ) else { throw LearningPathOperationError.controllerFailed("Calibration travel did not settle at its exact sample.") }
        let capture = try await captureCurrentCameraCapAnchorEvidence(
          contextBaseline: nil, operationID: operationID.rawValue
        )
        return .completed(.sample(capture.evidence))
      } catch { return .failed(cameraCalibrationEffectFailure(actionableDescription(error))) }
    case .returnToReference(_, let reference, let delta):
      do {
        let final = try await performSupervisedPenUpTravel(
          delta: delta,
          ownerID: .humanGuidedDiscovery(.calibrateCameraAndVisibleCap),
          action: .returnFromCameraCalibration
        )
        guard recordProtocolPoseSettlement(action: .returnFromCameraCalibration, target: reference, actual: final) else {
          throw LearningPathOperationError.controllerFailed("Calibration return did not settle at the reference pose.")
        }
        return .completed(.returnedToReference)
      } catch { return .failed(cameraCalibrationEffectFailure(actionableDescription(error))) }
    }
  }

  private func cameraCalibrationEffectFailure(
    _ detail: String?
  ) -> PlotterCameraCalibrationFailure {
    .init(
      code: .unexpectedFailure,
      detail: detail ?? "Camera-calibration effect did not produce the required terminal fact.",
      recovery: .resolveNamedFailure
    )
  }

  func captureCameraCalibrationReferenceEffect() async throws -> (
    frame: DisplayedFrame,
    position: MachinePosition,
    capAnchor: ToolCapAnchorEstimate
  ) {
    let ownerID = LearningPathItemID.humanGuidedDiscovery(
      .calibrateCameraAndVisibleCap
    )
    if activeExerciseAttemptID == nil {
      beginExerciseAttempt(ownerID: ownerID, mode: activeExerciseAttemptMode ?? .normal)
    }
    guard let acceptedCenter = currentBoundarySnapshot?.centerArrivalPosition else {
      throw LearningPathOperationError.requiredState(
        "An accepted Boundary center arrival is required before camera calibration."
      )
    }
    let freshObservation = try await freshCalibrationMachineObservation()
    guard MachinePositionAcceptancePolicy.accepts(
      freshObservation.position,
      target: acceptedCenter
    ) else {
      throw LearningPathOperationError.requiredState(
        "Fresh controller MPos did not match the accepted Boundary center arrival. Return Pen Up to the accepted center before starting camera calibration."
      )
    }
    let targetMachinePosition = freshObservation.position
    let frame = try await captureProtocolFrame(
      newerThan: cameraCalibrationAnchorFrame?.frame.captureNanoseconds ?? 0
    )
    let centroid: Point2<CameraPixelSpace>
    let bounds: AxisAlignedBounds<CameraPixelSpace>
    let confidence: Double
    var registrationFrame = frame
    if frameMode == .simulated {
        guard
          let point = overlayResultChannels.simulation?.overlays.compactMap({
            overlay -> Point2<CameraPixelSpace>? in
            guard overlay.provenance.kind == .penCap, case .point(let point) = overlay.geometry
            else { return nil }
            return point
          }).first,
          let armatureBounds = overlayResultChannels.simulation?.overlays.compactMap({
            overlay
              -> AxisAlignedBounds<CameraPixelSpace>? in
            guard overlay.provenance.kind == .armatureEstimate,
              case .bounds(let bounds) = overlay.geometry
            else { return nil }
            return bounds
          }).first
        else {
          throw LearningPathOperationError.requiredState(
            "Cap-anchor and armature overlays are unavailable."
          )
        }
        bounds = armatureBounds
        centroid = try Point2(
          x: (armatureBounds.minX + armatureBounds.maxX) / 2,
          y: (armatureBounds.minY + armatureBounds.maxY) / 2
        )
        guard abs(point.x - centroid.x) <= 0.001,
          abs(point.y - armatureBounds.maxY) <= 0.001
        else {
          throw LearningPathOperationError.requiredState(
            "The causal simulator cap anchor does not match the armature bottom-center."
          )
        }
        confidence = 1
    } else {
      let stable = try await captureStableWorkflowCap(
        newerThan: frame.frame.captureNanoseconds - 1
      )
      let inspection = stable.inspection
      let cap = stable.cap
      centroid = cap.centroid
      bounds = try AxisAlignedBounds(
        minX: Double(cap.boundingBox.x),
        minY: Double(cap.boundingBox.y),
        maxX: Double(cap.boundingBox.x + cap.boundingBox.width),
        maxY: Double(cap.boundingBox.y + cap.boundingBox.height)
      )
      confidence = cap.confidence
      displayedFrame = inspection.displayedFrame
      registrationFrame = inspection.displayedFrame
      publishWorkflowInspection(inspection, owner: .cameraCalibration)
    }
    let capAnchor = try ToolCapAnchorEstimate(
      componentCentroid: centroid,
      componentBounds: bounds,
      confidence: confidence,
      estimatorRevision: penCapAnchorEstimatorRevision,
      source: registrationFrame.source,
      frameID: registrationFrame.frame.id,
      cameraConfigurationID: registrationFrame.frame.cameraConfigurationID
    )
    return (registrationFrame, targetMachinePosition, capAnchor)
  }

  private var penCapAnchorEstimatorRevision: String {
    "selected-cap-\(penCapAppearanceSelection?.color.hexRGB ?? "UNLEARNED")-bottom-center-anchor-v3"
  }

  /// Makes the reviewed five-sample cap-map proposal authoritative atomically.
  func acceptCameraCalibrationProposalEffect(
    _ registration: MachineCameraRegistration
  ) throws {
    guard let attemptID = activeExerciseAttemptID,
      activeExerciseAttemptOwnerID == .humanGuidedDiscovery(.calibrateCameraAndVisibleCap),
      let centerArrival = learningArtifactGraph.currentRevision(for: .centerArrival)?.id,
      registration == proposedMachineCameraRegistration
    else {
      throw LearningPathOperationError.requiredState(
        "Camera-calibration acceptance no longer matches the reviewed proposal and active attempt."
      )
    }
    var graph = learningArtifactGraph
    let previousGraph = learningArtifactGraph
    let previousCheckpoint = activeMachineCameraCheckpoint
    do {
      let machineRegistrationCandidate = LearningArtifactRevision(
        kind: .machineCameraRegistration,
        attemptID: attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: Set(
          registration.correspondenceProvenance.map(\.artifactRevisionID)
            + [centerArrival]
        )
      )
      let machineRegistration = try graph.commitReplacement(machineRegistrationCandidate)
      learningArtifactGraph = graph
      guard let revision = graph.currentRevision(for: .machineCameraRegistration) else {
        throw LearningPathOperationError.requiredState(
          "The accepted machine-camera graph revision was not published."
        )
      }
      let acceptedCheckpoint = try AcceptedMachineCameraCheckpoint(
        revision: revision,
        registration: registration
      )
      activeMachineCameraCheckpoint = acceptedCheckpoint
      guard persistAcceptedLearningPathCheckpoint(
        machineCamera: acceptedCheckpoint,
        clearTip: true,
        clearStageFour: true
      ) else {
        learningArtifactGraph = previousGraph
        activeMachineCameraCheckpoint = previousCheckpoint
        throw LearningPathOperationError.requiredState(
          learningAuthorityError ?? "The accepted camera calibration could not be persisted."
        )
      }
      applyArtifactInvalidations(
        machineRegistration.invalidatedRevisionIDs,
        preservingCameraCalibrationRuntime: true
      )
      finishActiveExerciseAttempt(disposition: .succeeded)
    } catch {
      learningArtifactGraph = previousGraph
      activeMachineCameraCheckpoint = previousCheckpoint
      throw error
    }
  }

  /// Captures one exact current-camera machine/cap-anchor correspondence. Motion,
  /// sequencing, and target return remain owned by the automatic calibration.
  private func captureCurrentCameraCapAnchorEvidence(
    contextBaseline: ControllerContextBaseline?,
    operationID: UUID,
    newerThanNanoseconds: UInt64? = nil,
    requiresCurrentCaptureIdentity: Bool = false
  ) async throws -> CalibrationCapAnchorCapture {
    try requireCalibrationContinuation()
    guard let attemptID = activeExerciseAttemptID else {
      throw LearningPathOperationError.requiredState(
        "No active machine-camera calibration attempt owns this sample."
      )
    }
    guard
      let centerArrivalRevisionID = learningArtifactGraph.currentRevision(
        for: .centerArrival
      )?.id
    else {
      throw LearningPathOperationError.requiredState(
        "The accepted center-arrival coordinate artifact is unavailable."
      )
    }
    let beforeCapture = try await freshCalibrationMachineObservation(
      contextBaseline: contextBaseline,
      operationID: operationID
    )
    try requireCalibrationContinuation()
    let boundary = max(
      displayedFrame?.frame.captureNanoseconds ?? 0,
      newerThanNanoseconds ?? 0
    )
    let frame = try await captureProtocolFrame(newerThan: boundary)
    try requireCalibrationContinuation()
    let centroid: Point2<CameraPixelSpace>
    let bounds: AxisAlignedBounds<CameraPixelSpace>
    let confidence: Double
    var evidenceFrame = frame
    if frameMode == .simulated {
      guard
        let point = overlayResultChannels.simulation?.overlays.compactMap({
          overlay -> Point2<CameraPixelSpace>? in
          guard overlay.provenance.kind == .penCap, case .point(let point) = overlay.geometry
          else { return nil }
          return point
        }).first,
        let armatureBounds = overlayResultChannels.simulation?.overlays.compactMap({
          overlay -> AxisAlignedBounds<CameraPixelSpace>? in
          guard overlay.provenance.kind == .armatureEstimate,
            case .bounds(let bounds) = overlay.geometry
          else { return nil }
          return bounds
        }).first
      else {
        throw LearningPathOperationError.requiredState(
          "Cap-anchor and armature overlays are unavailable."
        )
      }
      centroid = try Point2(
        x: (armatureBounds.minX + armatureBounds.maxX) / 2,
        y: (armatureBounds.minY + armatureBounds.maxY) / 2
      )
      guard abs(point.x - centroid.x) <= 0.001,
        abs(point.y - armatureBounds.maxY) <= 0.001
      else {
        throw LearningPathOperationError.requiredState(
          "The causal simulator cap anchor does not match the armature bottom-center."
        )
      }
      bounds = armatureBounds
      confidence = 1
    } else {
      let stable = try await captureStableWorkflowCap(
        newerThan: frame.frame.captureNanoseconds
      )
      let inspection = stable.inspection
      if requiresCurrentCaptureIdentity {
        guard inspection.displayedFrame.source == frame.source,
          inspection.displayedFrame.frame.cameraConfigurationID == frame.frame.cameraConfigurationID else {
          throw LearningPathOperationError.requiredState(
            "The position frame came from a different camera or capture configuration. Restore the current camera session and retry.")
        }
        guard inspection.displayedFrame.frame.captureNanoseconds > frame.frame.captureNanoseconds else {
          throw LearningPathOperationError.requiredState(
            "The position frame is stale. Wait for a new frame from the current camera and retry.")
        }
      }
      let cap = stable.cap
      try requireCalibrationContinuation()
      centroid = cap.centroid
      bounds = try AxisAlignedBounds(
        minX: Double(cap.boundingBox.x),
        minY: Double(cap.boundingBox.y),
        maxX: Double(cap.boundingBox.x + cap.boundingBox.width),
        maxY: Double(cap.boundingBox.y + cap.boundingBox.height)
      )
      confidence = cap.confidence
      evidenceFrame = inspection.displayedFrame
      displayedFrame = inspection.displayedFrame
      publishWorkflowInspection(inspection, owner: .cameraCalibration)
    }
    let capAnchor = try ToolCapAnchorEstimate(
      componentCentroid: centroid,
      componentBounds: bounds,
      confidence: confidence,
      estimatorRevision: penCapAnchorEstimatorRevision,
      source: evidenceFrame.source,
      frameID: evidenceFrame.frame.id,
      cameraConfigurationID: evidenceFrame.frame.cameraConfigurationID
    )
    let afterCapture = try await freshCalibrationMachineObservation(
      contextBaseline: beforeCapture.contextBaseline,
      operationID: operationID
    )
    try requireCalibrationContinuation()
    guard MachinePositionAcceptancePolicy.accepts(
      beforeCapture.position,
      target: afterCapture.position
    ) else {
      throw LearningPathOperationError.controllerFailed(
        "Controller MPos changed while the camera sample was being captured; the sample was discarded."
      )
    }
    return CalibrationCapAnchorCapture(
      evidence: MachineCameraCorrespondenceProvenance(
        machinePoint: afterCapture.position.point,
        capAnchorPoint: capAnchor.point,
        source: evidenceFrame.source,
        controllerSessionID: controllerSessionID,
        coordinateRevision: explorationCoordinateRevision,
        frameID: evidenceFrame.frame.id,
        frameSHA256: evidenceFrame.frame.contentSHA256,
        captureNanoseconds: evidenceFrame.frame.captureNanoseconds,
        cameraConfigurationID: evidenceFrame.frame.cameraConfigurationID,
        attemptID: attemptID,
        capAnchorEstimatorRevision: capAnchor.estimatorRevision,
        algorithmRevision:
          "automatic-current-camera-cap-anchor-v4:cap-\(penCapAppearanceSelection?.color.hexRGB ?? "UNLEARNED")",
        capAnchorConfidence: capAnchor.confidence,
        artifactRevisionID: centerArrivalRevisionID
      ),
      contextBaseline: afterCapture.contextBaseline,
      passiveProbe: nil,
      displayedFrame: evidenceFrame,
      capAnchor: capAnchor
    )
  }

  /// Exercise 1.4 already has typed travel settlement. Capture therefore needs one
  /// post-frame passive probe, not the current-camera helper's before/after pair.
  /// The probe both supplies the exact evidence MPos and proves that controller
  /// context remained compatible with the preceding sparse capture.
  private func captureSparseTipCapAnchorEvidence(
    contextBaseline: ControllerContextBaseline?,
    expectedSettledPosition: MachinePosition,
    operationID: UUID,
    newerThanNanoseconds: UInt64? = nil
  ) async throws -> CalibrationCapAnchorCapture {
    try requireSparseTipBatchContinuation()
    guard sparseTipPenUpAuthorizationIsCurrent else {
      throw LearningPathOperationError.requiredState(
        "Sparse-tip capture lost its batch-local Pen-Up authorization."
      )
    }
    guard let attemptID = activeExerciseAttemptID,
      let centerArrivalRevisionID = learningArtifactGraph.currentRevision(for: .centerArrival)?.id
    else {
      throw LearningPathOperationError.requiredState(
        "The active sparse-tip attempt or accepted center-arrival artifact is unavailable."
      )
    }

    let boundary = max(
      displayedFrame?.frame.captureNanoseconds ?? 0,
      newerThanNanoseconds ?? 0
    )
    let frame = try await captureProtocolFrame(newerThan: boundary)
    try requireSparseTipBatchContinuation()
    guard sparseTipPenUpAuthorizationIsCurrent else {
      throw LearningPathOperationError.requiredState(
        "Sparse-tip capture lost its batch-local Pen-Up authorization."
      )
    }

    let centroid: Point2<CameraPixelSpace>
    let bounds: AxisAlignedBounds<CameraPixelSpace>
    let confidence: Double
    var evidenceFrame = frame
    if frameMode == .simulated {
      guard
        let point = overlayResultChannels.simulation?.overlays.compactMap({
          overlay -> Point2<CameraPixelSpace>? in
          guard overlay.provenance.kind == .penCap, case .point(let point) = overlay.geometry
          else { return nil }
          return point
        }).first,
        let armatureBounds = overlayResultChannels.simulation?.overlays.compactMap({
          overlay -> AxisAlignedBounds<CameraPixelSpace>? in
          guard overlay.provenance.kind == .armatureEstimate,
            case .bounds(let bounds) = overlay.geometry
          else { return nil }
          return bounds
        }).first
      else {
        throw LearningPathOperationError.requiredState(
          "Cap-anchor and armature overlays are unavailable."
        )
      }
      centroid = try Point2(
        x: (armatureBounds.minX + armatureBounds.maxX) / 2,
        y: (armatureBounds.minY + armatureBounds.maxY) / 2
      )
      guard abs(point.x - centroid.x) <= 0.001,
        abs(point.y - armatureBounds.maxY) <= 0.001
      else {
        throw LearningPathOperationError.requiredState(
          "The causal simulator cap anchor does not match the armature bottom-center."
        )
      }
      bounds = armatureBounds
      confidence = 1
    } else {
      let stable = try await captureStableWorkflowCap(
        newerThan: frame.frame.captureNanoseconds,
        owner: .sparseTipCalibration,
        searchCenter: try? machineCameraRegistration?.fit.cameraPoint(
          from: expectedSettledPosition.point
        )
      )
      let inspection = stable.inspection
      let cap = stable.cap
      try requireSparseTipBatchContinuation()
      guard sparseTipPenUpAuthorizationIsCurrent else {
        throw LearningPathOperationError.requiredState(
          "Sparse-tip capture lost its batch-local Pen-Up authorization."
        )
      }
      centroid = cap.centroid
      bounds = try AxisAlignedBounds(
        minX: Double(cap.boundingBox.x),
        minY: Double(cap.boundingBox.y),
        maxX: Double(cap.boundingBox.x + cap.boundingBox.width),
        maxY: Double(cap.boundingBox.y + cap.boundingBox.height)
      )
      confidence = cap.confidence
      evidenceFrame = inspection.displayedFrame
      displayedFrame = inspection.displayedFrame
      publishWorkflowInspection(inspection, owner: .sparseTipCalibration)
    }
    let capAnchor = try ToolCapAnchorEstimate(
      componentCentroid: centroid,
      componentBounds: bounds,
      confidence: confidence,
      estimatorRevision: penCapAnchorEstimatorRevision,
      source: evidenceFrame.source,
      frameID: evidenceFrame.frame.id,
      cameraConfigurationID: evidenceFrame.frame.cameraConfigurationID
    )

    let observedPosition: MachinePosition
    let refreshedBaseline: ControllerContextBaseline?
    let passiveProbe: PassiveProbeResult?
    if frameMode == .simulated {
      let snapshot = await simulatedLearningRuntime.snapshot()
      try requireSparseTipBatchContinuation()
      guard snapshot.currentOperation == nil, snapshot.stickyAmbiguity == nil,
        snapshot.penPose == .up
      else {
        throw LearningPathOperationError.controllerFailed(
          "The simulated sparse-tip capture did not settle Idle and Pen Up."
        )
      }
      observedPosition = try MachinePosition(x: snapshot.mpos.xMM, y: snapshot.mpos.yMM)
      refreshedBaseline = nil
      passiveProbe = nil
    } else {
      guard let machineSession else {
        throw LearningPathOperationError.requiredState(
          "A connected controller session is required for sparse-tip evidence."
        )
      }
      let probe = try await machineSession.requestPassiveProbe()
      try requireSparseTipBatchContinuation()
      guard sparseTipPenUpAuthorizationIsCurrent,
        probe.blockers.isEmpty,
        let status = probe.latestStatusReport,
        status.controllerState == .idle,
        let position = status.machinePosition
      else {
        throw LearningPathOperationError.controllerFailed(
          "The post-capture probe did not prove an unambiguous Idle MPos under the current Pen-Up authorization."
        )
      }
      let refreshed = try ControllerContextBaseline(probe: probe)
      if let contextBaseline {
        let comparison = contextBaseline.context.comparison(with: refreshed.context)
        guard comparison.isCompatible else {
          throw LearningPathOperationError.controllerContextChanged(comparison)
        }
      }
      observedPosition = position
      refreshedBaseline = refreshed
      passiveProbe = probe
    }
    guard MachinePositionAcceptancePolicy.accepts(
      observedPosition,
      target: expectedSettledPosition
    ) else {
      throw LearningPathOperationError.controllerFailed(
        "Controller MPos changed while sparse-tip evidence was being captured."
      )
    }

    return CalibrationCapAnchorCapture(
      evidence: MachineCameraCorrespondenceProvenance(
        machinePoint: observedPosition.point,
        capAnchorPoint: capAnchor.point,
        source: evidenceFrame.source,
        controllerSessionID: controllerSessionID,
        coordinateRevision: explorationCoordinateRevision,
        frameID: evidenceFrame.frame.id,
        frameSHA256: evidenceFrame.frame.contentSHA256,
        captureNanoseconds: evidenceFrame.frame.captureNanoseconds,
        cameraConfigurationID: evidenceFrame.frame.cameraConfigurationID,
        attemptID: attemptID,
        capAnchorEstimatorRevision: capAnchor.estimatorRevision,
        algorithmRevision:
          "sparse-tip-post-capture-probe-v1:cap-\(penCapAppearanceSelection?.color.hexRGB ?? "UNLEARNED")",
        capAnchorConfidence: capAnchor.confidence,
        artifactRevisionID: centerArrivalRevisionID
      ),
      contextBaseline: refreshedBaseline,
      passiveProbe: passiveProbe,
      displayedFrame: evidenceFrame,
      capAnchor: capAnchor
    )
  }

  private func requireCalibrationContinuation() throws {
    guard applicationAdmissionIsOpen, !Task.isCancelled else {
      throw LearningPathOperationError.requiredState(
        "Application shutdown cancelled automatic current-camera calibration."
      )
    }
  }

  private func freshCalibrationMachineObservation(
    contextBaseline: ControllerContextBaseline?,
    operationID: UUID
  ) async throws -> CalibrationMachineObservation {
    let observation = try await freshCalibrationMachineObservation()
    guard let refreshedBaseline = observation.contextBaseline else { return observation }
    if let contextBaseline {
      let comparison = contextBaseline.context.comparison(with: refreshedBaseline.context)
      await recordWorkflowTelemetry(
        WorkflowTelemetryEvent(
          operationID: operationID,
          operation: .currentCameraCalibration,
          phase: .controllerContextCompared,
          attemptID: activeExerciseAttemptID,
          detail: comparison.actionableDescription,
          controllerContext: WorkflowControllerContextTelemetry(
            baselineProbeID: contextBaseline.probeID,
            refreshedProbeID: refreshedBaseline.probeID,
            comparison: comparison
          ),
          failureCode: comparison.isCompatible ? nil : .controllerContextChanged,
          recovery: comparison.isCompatible ? .none : .revalidateControllerContext
        )
      )
      guard comparison.isCompatible else {
        throw LearningPathOperationError.controllerContextChanged(comparison)
      }
    } else {
      await recordWorkflowTelemetry(
        WorkflowTelemetryEvent(
          operationID: operationID,
          operation: .currentCameraCalibration,
          phase: .controllerContextEstablished,
          attemptID: activeExerciseAttemptID,
          detail:
            "The first fresh passive probe established this calibration operation's controller-context baseline.",
          controllerContext: WorkflowControllerContextTelemetry(
            baselineProbeID: nil,
            refreshedProbeID: refreshedBaseline.probeID,
            comparison: nil
          )
        )
      )
    }
    return observation
  }

  /// Acquires exact settled controller/simulator truth without claiming a
  /// calibration-operation baseline. The automatic five-sample operation owns
  /// its later baseline establishment and comparison telemetry.
  private func freshCalibrationMachineObservation() async throws
    -> CalibrationMachineObservation
  {
    try requireCalibrationContinuation()
    if frameMode == .simulated {
      let snapshot = await simulatedLearningRuntime.snapshot()
      try requireCalibrationContinuation()
      guard snapshot.currentOperation == nil, snapshot.stickyAmbiguity == nil,
        snapshot.penPose == .up
      else {
        throw LearningPathOperationError.controllerFailed(
          "The simulated controller was not settled at an unambiguous Pen-Up position."
        )
      }
      simulatedLearningSnapshot = snapshot
      return CalibrationMachineObservation(
        position: try MachinePosition(x: snapshot.mpos.xMM, y: snapshot.mpos.yMM),
        contextBaseline: nil
      )
    }

    guard let machineSession else {
      throw LearningPathOperationError.requiredState(
        "A connected controller session is required for exact calibration evidence."
      )
    }
    let probe = try await machineSession.requestPassiveProbe()
    try requireCalibrationContinuation()
    let refreshedBaseline = try ControllerContextBaseline(probe: probe)
    let snapshot = await machineSession.snapshot()
    try requireCalibrationContinuation()
    guard let snapshot, snapshot.currentOperation == .idle,
      snapshot.machine.connection == .connected,
      snapshot.machine.controllerState == .idle,
      snapshot.machine.stickyAmbiguity == nil,
      snapshot.machine.penState == .up,
      let position = snapshot.machine.position
    else {
      throw LearningPathOperationError.controllerFailed(
        "Fresh controller status did not prove an unambiguous Idle Pen-Up MPos."
      )
    }
    passiveProbeResult = probe
    machineSnapshot = snapshot
    return CalibrationMachineObservation(
      position: position,
      contextBaseline: refreshedBaseline
    )
  }

  func rejectCameraCalibrationProposalEffect() {
    // The calibration runtime owns the typed `.completed(.rejected)` terminal.
    // Rejection does not create a second generic workflow failure.
  }

  func submitPointSelection(_ submission: PlotterPointSelectionSubmission) {
    guard applicationAdmissionIsOpen else { return }
    Task { @MainActor [weak self] in
      await self?.performPointSelectionSubmission(submission)
    }
  }

  private func performPointSelectionSubmission(
    _ submission: PlotterPointSelectionSubmission
  ) async {
    let submittedRequest = pointSelectionEpisodeProjection.exactPointSelection.request
    let submittedPurpose = submittedRequest?.purpose
    do {
      let result = try await pointSelectionRuntime.submit(submission)
      switch result {
      case let .refused(projection, reason):
        installPointSelectionProjection(projection)
        if submittedPurpose == .penCapAppearance {
          discoveryError = "Identify Pen Cap rejected the click: \(reason)"
        } else {
          explorationError = "Corner-mark selection failed without motion or redraw: \(reason)"
        }
      case let .acceptedPoint(projection):
        installPointSelectionProjection(projection)
        explorationError = nil
      case let .acceptedPenCap(sample, acceptedFrame, projection):
        guard activeExerciseAttemptOwnerID == .humanGuidedDiscovery(.penInteraction),
          activeExerciseAttemptID != nil,
          activeExerciseAttemptMode != nil
        else {
          _ = await pointSelectionRuntime.cancel(selectionID: submission.selectionID)
          return
        }
        installPointSelectionProjection(projection)
        let learned = PenCapAppearanceSelection(
          sample: sample,
          frame: acceptedFrame
        )
        switch learned.source {
        case .live:
          livePenCapAppearanceSelection = learned
          persistedPenCapAppearanceLoadState = .accepted
        case .simulated:
          simulatedPenCapAppearanceSelection = learned
        }
        frozenPointSelectionFrame = nil
        pendingToolContactEvidence = []
        pendingToolContactClickFrame = nil
        discoveryError = nil
        try await pointSelectionRuntime.beginPenCapContinuation(
          selectionID: submission.selectionID,
          sample: sample,
          port: self
        )
        installPointSelectionProjection(await pointSelectionRuntime.currentProjection())
      case let .acceptedBatch(points, presentationRevision, projection):
        installPointSelectionProjection(projection)
        do {
          guard let submittedRequest else {
            throw LearningPathOperationError.requiredState(
              "The completed point-selection batch had no matching request."
            )
          }
          let completedSelection = PlotterTipCalibrationCompletedPointSelection(
            selectionID: submittedRequest.id,
            exactFrame: submittedRequest.frame,
            presentationTransformRevision: presentationRevision,
            points: points
          )
          let outcome = await tipCalibrationRuntime.submit(
            .consumeCompletedPointSelection(completedSelection)
          )
          guard outcome == .completed else {
            throw TipCalibrationEffectOutcomeError(outcome: outcome)
          }
          explorationError = nil
        } catch {
          explorationError =
            "Pen-tip calibration construction failed without motion or redraw: \(actionableDescription(error)). Use Undo Last Click or Clear Clicks on This Frame to correct the same frozen frame."
        }
      }
    } catch {
      if submittedPurpose == .penCapAppearance {
        discoveryError = "Identify Pen Cap rejected the click: \(actionableDescription(error))"
      } else {
        explorationError =
          "Corner-mark selection failed without motion or redraw: \(actionableDescription(error))"
      }
    }
  }

  func beginPenCapDiscovery(selectionID: PlotterPointSelectionID) async throws {
    guard !Task.isCancelled,
      pointSelectionEpisodeProjection.exactPointSelection.request?.id == selectionID,
      activeExerciseAttemptOwnerID == .humanGuidedDiscovery(.penInteraction),
      activeDiscoverySequenceID == nil,
      penCapAppearanceSelection != nil
    else { throw CancellationError() }
    await startDiscoverySequence(.penInteraction)
    guard !Task.isCancelled,
      pointSelectionEpisodeProjection.exactPointSelection.request?.id == selectionID,
      activeExerciseAttemptOwnerID == .humanGuidedDiscovery(.penInteraction)
    else { throw CancellationError() }
  }

  func configurePenCapVision(
    selectionID: PlotterPointSelectionID,
    sample: PlotterAcceptedPenCapSample
  ) async throws {
    guard !Task.isCancelled,
      pointSelectionEpisodeProjection.exactPointSelection.request?.id == selectionID,
      activeExerciseAttemptOwnerID == .humanGuidedDiscovery(.penInteraction),
      let selection = penCapAppearanceSelection,
      selection.color.red == sample.red,
      selection.color.green == sample.green,
      selection.color.blue == sample.blue
    else { throw CancellationError() }
    guard frameMode == .live else { return }
    await reconcileAutomaticVisionAnalysis()
    guard !Task.isCancelled,
      pointSelectionEpisodeProjection.exactPointSelection.request?.id == selectionID
    else { throw CancellationError() }
    await reconcileAutomaticVisionAnalysis()
  }

  private func installPointSelectionProjection(_ projection: PlotterEpisodeProjection) {
    guard pointSelectionEpisodeProjection != projection else { return }
    pointSelectionEpisodeProjection = projection
    markSemanticPresentationChanged()
  }

  private func cancelPointSelectionRequest() async {
    guard let selectionID = pointSelectionEpisodeProjection.exactPointSelection.request?.id else {
      frozenPointSelectionFrame = nil
      pendingToolContactEvidence = []
      pendingToolContactClickFrame = nil
      return
    }
    installPointSelectionProjection(
      await pointSelectionRuntime.cancel(selectionID: selectionID)
    )
    frozenPointSelectionFrame = nil
    pendingToolContactEvidence = []
    pendingToolContactClickFrame = nil
  }

  private func drawSparseTipCircles() async throws -> PlotterTipCalibrationMarkBatchFact {
    let ownerID = LearningPathItemID.humanGuidedDiscovery(
      .calibratePenContactFromSparseMarks
    )
    if let reason = retainedPoseApplicabilityRefusal {
      explorationError = reason
      throw LearningPathOperationError.requiredState(reason)
    }
    if activeExerciseAttemptOwnerID == nil {
      await startExercise(ownerID, mode: .normal)
    }
    guard activeExerciseAttemptOwnerID == ownerID,
      let attemptID = activeExerciseAttemptID
    else {
      throw LearningPathOperationError.requiredState(
        "Pen-tip calibration did not own the active Learning attempt."
      )
    }

    let target = ContextualStopTarget.sparseTipBatch(
      capabilityID: ContextualStopCapabilityID(),
      attemptID: attemptID
    )
    var result: Result<PlotterTipCalibrationMarkBatchFact, any Error>?
    let task = Task { @MainActor [weak self] in
      guard let self else {
        result = .failure(CancellationError())
        return
      }
      do {
        result = .success(try await self.executeFourCornerTipCircles(
          ownerID: ownerID,
          attemptID: attemptID
        ))
      } catch {
        result = .failure(error)
      }
    }
    sparseTipPenUpAuthorization = nil
    installStoppableOperation(target: target, owner: .batch(task))
    defer {
      sparseTipPenUpAuthorization = nil
      clearStoppableOperation(matching: target)
    }
    await task.value
    return try result?.get() ?? {
      throw LearningPathOperationError.requiredState(
        "Pen-tip calibration batch ended without a terminal fact."
      )
    }()
  }

  private func executeFourCornerTipCircles(
    ownerID: LearningPathItemID,
    attemptID: ExerciseAttemptID
  ) async throws -> PlotterTipCalibrationMarkBatchFact {
    guard activeExerciseAttemptOwnerID == ownerID,
      activeExerciseAttemptID == attemptID,
      let machineRegistration = machineCameraRegistration,
      let machineRegistrationRevision = learningArtifactGraph.currentRevision(
        for: .machineCameraRegistration
      )?.id
    else {
      throw LearningPathOperationError.requiredState(
        "Pen-tip calibration requires accepted machine-camera registration."
      )
    }

    let batchTelemetryOperationID = UUID()
    var batchTelemetryAdmitted = false
    var batchTelemetryTotalCircleCount = 0
    var completedLocations: [BlacklistedToolContactLocation] = []
    var activeLocation: BlacklistedToolContactLocation?
    do {
      try requireSparseTipBatchContinuation()
      let batchPlan = try SparseTipBatchMarkPlan(
        acceptedBoundaryAggregates: acceptedBoundaryAggregates
      )
      batchTelemetryTotalCircleCount = batchPlan.marks.count
      let physicalLocations = batchPlan.marks.map { mark in
        BlacklistedToolContactLocation(
          calibrationPosition: mark.position,
          machinePosition: mark.machinePosition,
          markRadiusMM: SparseTipCircularMarkPlan.radiusMM,
          paperInstance: PaperInstanceRevision(
            rawValue: explorationPaperInstanceRevision
          )
        )
      }
      guard
        physicalLocations.allSatisfy({
          !blacklistedToolContactLocations.contains($0)
        })
      else {
        throw LearningPathOperationError.requiredState(
          "Possible ink already excludes one of the four calibration-circle locations on the current paper."
        )
      }
      batchTelemetryAdmitted = true
      await recordWorkflowTelemetry(
        WorkflowTelemetryEvent(
          operationID: batchTelemetryOperationID,
          operation: .sparseTipCalibration,
          phase: .batchAdmitted,
          attemptID: attemptID,
          detail: "Four-circle pen-tip calibration started.",
          sparseTipProgress: SparseTipWorkflowProgress(
            stage: .batchAdmitted,
            completedCircleCount: 0,
            totalCircleCount: batchPlan.marks.count
          )
        )
      )
      let initialPenUp = try await normalizeSparseTipBatchPenUp()
      var drawnEvidence: [DrawnToolContactEvidence] = []
      var batchPosition = try await currentSettledMachinePositionForEffect()
      var finalPenUpTimestamp = initialPenUp.timestamp
      var controllerContextBaseline: ControllerContextBaseline?

      for (markIndex, plannedMark) in batchPlan.marks.enumerated() {
        try requireSparseTipBatchContinuation()
        let position = plannedMark.position
        let physicalLocation = physicalLocations[markIndex]
        activeLocation = physicalLocation
        let current = batchPosition
        let settled: MachinePosition
        if let delta = try Self.supervisedTravelDelta(
          from: current,
          to: plannedMark.machinePosition
        ) {
          settled = try await performSupervisedPenUpTravel(
            delta: delta,
            ownerID: ownerID,
            action: .sparseTipApproach(position)
          )
        } else {
          settled = current
        }
        try requireSparseTipBatchContinuation()
        guard MachinePositionAcceptancePolicy.accepts(
          settled,
          target: plannedMark.machinePosition
        ) else {
          throw LearningPathOperationError.controllerFailed(
            String(
              format: "Sparse mark approach did not settle within %.3f mm.",
              MachinePositionAcceptancePolicy.toleranceMM
            )
          )
        }
        batchPosition = settled

        let operationUUID = UUID()
        let preCapture = try await captureSparseTipCapAnchorEvidence(
          contextBaseline: controllerContextBaseline,
          expectedSettledPosition: settled,
          operationID: operationUUID
        )
        controllerContextBaseline = preCapture.contextBaseline
        try requireSparseTipBatchContinuation()
        let exactPreFrame = try exactTipCalibrationFrame(preCapture.displayedFrame)
        let capPredictionAtMark = try machineRegistration.fit.cameraPoint(
          from: settled.point
        )
        let controllerEvidence = try controllerContextEvidenceReference(
          preCapture.contextBaseline,
          operationID: operationUUID
        )
        let markStartDelta = try Vector2<MachineSpace>(
          dx: plannedMark.circle.startPosition.point.x - settled.point.x,
          dy: plannedMark.circle.startPosition.point.y - settled.point.y
        )
        let markStartSettled = try await performSupervisedPenUpTravel(
          delta: markStartDelta,
          ownerID: ownerID,
          action: .sparseTipCircleStart(position)
        )
        try requireSparseTipBatchContinuation()
        guard MachinePositionAcceptancePolicy.accepts(
          markStartSettled,
          target: plannedMark.circle.startPosition
        ) else {
          throw LearningPathOperationError.controllerFailed(
            String(
              format: "Sparse circle start did not settle within %.3f mm.",
              MachinePositionAcceptancePolicy.toleranceMM
            )
          )
        }
        batchPosition = markStartSettled
        let mark = try await performCircularContactMark(
          plan: plannedMark.circle,
          at: physicalLocation,
          after: exactPreFrame.captureNanoseconds
        )
        try requireSparseTipBatchContinuation()
        completedLocations.append(physicalLocation)
        batchPosition = mark.finalPosition
        finalPenUpTimestamp = mark.penUp.timestamp
        drawnEvidence.append(
          DrawnToolContactEvidence(
            attemptID: attemptID,
            operationID: ToolContactOperationID(rawValue: operationUUID),
            position: position,
            intendedMarkPosition: plannedMark.machinePosition,
            actualSettledPosition: settled,
            controllerContextEvidence: controllerEvidence,
            markGeometry: plannedMark.circle.geometry,
            penDown: mark.penDown,
            penUp: mark.penUp,
            preMarkFrame: exactPreFrame,
            preMarkCapEstimate: preCapture.capAnchor,
            capMapPredictionAtMark: capPredictionAtMark
          )
        )
        await recordWorkflowTelemetry(
          WorkflowTelemetryEvent(
            operationID: batchTelemetryOperationID,
            operation: .sparseTipCalibration,
            phase: .circleCompleted,
            attemptID: attemptID,
            detail:
              "Completed sparse-tip circle \(drawnEvidence.count) of \(batchPlan.marks.count) as one 16-chord semantic unit.",
            sparseTipProgress: SparseTipWorkflowProgress(
              stage: .circleCompleted,
              completedCircleCount: drawnEvidence.count,
              totalCircleCount: batchPlan.marks.count,
              circlePosition: position,
              chordCount: plannedMark.circle.geometry.chordCount
            )
          )
        )
      }

      try requireSparseTipBatchContinuation()
      let revealTarget = batchPlan.finalRevealPosition
      let revealSettled: MachinePosition
      if let revealDelta = try Self.supervisedTravelDelta(
        from: batchPosition,
        to: revealTarget
      ) {
        revealSettled = try await performSupervisedPenUpTravel(
          delta: revealDelta,
          ownerID: ownerID,
          action: .sparseTipBatchReveal
        )
      } else {
        revealSettled = batchPosition
      }
      try requireSparseTipBatchContinuation()
      guard MachinePositionAcceptancePolicy.accepts(revealSettled, target: revealTarget) else {
        throw LearningPathOperationError.controllerFailed(
          String(
            format: "Sparse mark reveal did not settle within %.3f mm.",
            MachinePositionAcceptancePolicy.toleranceMM
          )
        )
      }
      let revealSettledAt = RuntimeTimestamp(
        monotonicNanoseconds: frameMode == .simulated
          ? finalPenUpTimestamp.monotonicNanoseconds + 1
          : max(nowNanoseconds(), finalPenUpTimestamp.monotonicNanoseconds + 1)
      )
      let revealOperationID = UUID()
      let revealCapture = try await captureSparseTipCapAnchorEvidence(
        contextBaseline: controllerContextBaseline,
        expectedSettledPosition: revealSettled,
        operationID: revealOperationID,
        newerThanNanoseconds: revealSettledAt.monotonicNanoseconds
      )
      controllerContextBaseline = revealCapture.contextBaseline
      try requireSparseTipBatchContinuation()
      if frameMode == .simulated {
        simulatedLearningSnapshot = await simulatedLearningRuntime.snapshot()
      } else if let machineSession {
        let finalSnapshot = await machineSession.snapshot()
        guard finalSnapshot?.currentOperation == .idle,
          finalSnapshot?.machine.controllerState == .idle,
          finalSnapshot?.machine.penState == .up,
          let finalPosition = finalSnapshot?.machine.position,
          MachinePositionAcceptancePolicy.accepts(finalPosition, target: revealSettled)
        else {
          machineSnapshot = finalSnapshot
          throw LearningPathOperationError.controllerFailed(
            "Final sparse-tip reveal snapshot did not retain Idle, Pen Up, and the probed reveal MPos."
          )
        }
        withBatchedSemanticPresentationUpdate {
          machineSnapshot = finalSnapshot
          passiveProbeResult = revealCapture.passiveProbe
        }
      }
      guard recordProtocolPoseSettlement(
        action: .sparseTipBatchReveal,
        target: revealTarget,
        actual: revealSettled
      ) else {
        throw LearningPathOperationError.controllerFailed(
          "Final sparse-tip reveal evidence fell outside its accepted MPos tolerance."
        )
      }
      let exactRevealFrame = try exactTipCalibrationFrame(revealCapture.displayedFrame)
      let revealPrediction = try machineRegistration.fit.cameraPoint(
        from: revealSettled.point
      )
      let controllerEvidence = try controllerContextEvidenceReference(
        revealCapture.contextBaseline,
        operationID: revealOperationID
      )
      let revealEvidence = try ToolContactRevealEvidence(
        intendedPosition: revealTarget,
        actualSettledPosition: revealSettled,
        settledAt: revealSettledAt,
        controllerContextEvidence: controllerEvidence,
        frame: exactRevealFrame,
        capEstimate: revealCapture.capAnchor,
        capMapPrediction: revealPrediction
      )
      await recordWorkflowTelemetry(
        WorkflowTelemetryEvent(
          operationID: batchTelemetryOperationID,
          operation: .sparseTipCalibration,
          phase: .revealCompleted,
          attemptID: attemptID,
          detail: "Completed the final Pen-Up sparse-tip reveal and exact-frame capture.",
          sparseTipProgress: SparseTipWorkflowProgress(
            stage: .revealCompleted,
            completedCircleCount: drawnEvidence.count,
            totalCircleCount: batchPlan.marks.count
          )
        )
      )
      let pendingEvidence = drawnEvidence.map { drawn in
        PendingToolContactEvidence(
          attemptID: drawn.attemptID,
          paperInstance: PaperInstanceRevision(
            rawValue: explorationPaperInstanceRevision
          ),
          operationID: drawn.operationID,
          position: drawn.position,
          intendedMarkPosition: drawn.intendedMarkPosition,
          actualSettledPosition: drawn.actualSettledPosition,
          controllerContextEvidence: drawn.controllerContextEvidence,
          markGeometry: drawn.markGeometry,
          penDown: drawn.penDown,
          penUp: drawn.penUp,
          preMarkFrame: drawn.preMarkFrame,
          preMarkCapEstimate: drawn.preMarkCapEstimate,
          revealEvidence: revealEvidence,
          capMapPredictionAtMark: drawn.capMapPredictionAtMark
        )
      }
      let staged = try await pointSelectionRuntime.stage(
        frame: revealCapture.displayedFrame,
        presentationTransformRevision: PlotterPresentationTransformRevision(),
        prompt: "Click the four corner-circle centers in any order",
        purpose: .toolContact,
        requiredPointCount: PlotterTipCalibrationRuntime.orderedPositions.count
      )
      let expectedSelection = PlotterTipCalibrationExpectedPointSelection(
        selectionID: staged.request.id,
        exactFrame: staged.request.frame,
        presentationTransformRevision: staged.request.presentationTransformRevision
      )
      installPointSelectionProjection(staged.projection)
      pendingToolContactEvidence = pendingEvidence
      pendingToolContactClickFrame = exactRevealFrame
      frozenPointSelectionFrame = revealCapture.displayedFrame
      pointSelectionRecordingDiagnostic =
        staged.recordingDiagnostic ?? pointSelectionRecordingDiagnostic
      explorationError = nil
      await recordWorkflowTelemetry(
        WorkflowTelemetryEvent(
          operationID: batchTelemetryOperationID,
          operation: .sparseTipCalibration,
          phase: .completed,
          attemptID: attemptID,
          detail: "Four calibration circles are complete; click their centers on the frozen frame.",
          sparseTipProgress: SparseTipWorkflowProgress(
            stage: .terminal,
            completedCircleCount: drawnEvidence.count,
            totalCircleCount: batchPlan.marks.count,
            terminalDisposition: .completed
          )
        )
      )
      _ = machineRegistrationRevision
      return PlotterTipCalibrationMarkBatchFact(
        expectedSelection: expectedSelection,
        controllerEvidenceIDs: [controllerEvidence.passiveProbeID.uuidString.lowercased()],
        captureEvidenceIDs: [exactRevealFrame.frameID.rawValue]
      )
    } catch {
      sparseTipPenUpAuthorization = nil
      let failure = workflowFailure(for: error)
      var locationsToBlacklist = completedLocations
      if let activeLocation,
        blacklistedToolContactLocations.contains(activeLocation)
          || failure.kind == .ambiguous || failure.kind == .possibleInk
      {
        locationsToBlacklist.append(activeLocation)
      }
      if locationsToBlacklist.isEmpty {
      } else {
        for location in Set(locationsToBlacklist) {
          blacklistedToolContactLocations.insert(location)
        }
        restartableExerciseItemID = nil
      }
      if batchTelemetryAdmitted {
        let possibleInkTerminal = !locationsToBlacklist.isEmpty || failure.kind == .possibleInk
        let terminalDisposition: SparseTipWorkflowTerminalDisposition =
          if possibleInkTerminal {
            .possibleInk
          } else {
            switch failure.kind {
            case .refused: .refused
            case .unclear: .unclear
            case .ambiguous: .ambiguous
            case .cancelled: .cancelled
            case .failed: .failed
            case .possibleInk: .possibleInk
            }
          }
        await recordWorkflowTelemetry(
          WorkflowTelemetryEvent(
            operationID: batchTelemetryOperationID,
            operation: .sparseTipCalibration,
            phase: failure.kind == .cancelled && !possibleInkTerminal ? .cancelled : .failed,
            attemptID: attemptID,
            detail: failure.detail,
            recovery: failure.recovery,
            sparseTipProgress: SparseTipWorkflowProgress(
              stage: .terminal,
              completedCircleCount: completedLocations.count,
              totalCircleCount: batchTelemetryTotalCircleCount,
              terminalDisposition: terminalDisposition
            )
          )
        )
      }
      await cancelPointSelectionRequest()
      explorationError =
        "Sparse tip calibration stopped without automatic retry: \(failure.detail)"
      if let possibleInkLocation = activeLocation ?? locationsToBlacklist.first,
        !locationsToBlacklist.isEmpty || failure.kind == .possibleInk
      {
        throw TipCalibrationPossibleInkEffectError(
          fact: PlotterTipCalibrationPossibleInkFact(
            location: possibleInkLocation,
            reason: failure.detail,
            persistenceEvidenceID: possibleInkLocation.persistenceEvidenceID
          ),
          underlying: error
        )
      }
      throw error
    }
  }

  private func performCircularContactMark(
    plan: SparseTipCircularMarkPlan,
    at location: BlacklistedToolContactLocation,
    after captureNanoseconds: UInt64
  ) async throws -> (
    penDown: PenActuationEvidence,
    penUp: PenActuationEvidence,
    finalPosition: MachinePosition
  ) {
    sparseTipPenUpAuthorization = nil
    let lower: PenOutcome
    if frameMode == .simulated {
      let simulatedOutcome = await causalSimulatorEffectAdapter.executeRetainedWorkflowPen(
        .down,
        owner: EpisodeAuthorityID(rawValue: "PlotterApplicationRuntime.sparseTipCalibration")
      )
      applySimulatedCausalImmediateOutcome(
        simulatedOutcome,
        action: "Lower simulated pen for sparse-tip calibration"
      )
      if let refusal = simulatedOutcome.refusal { throw refusal }
      lower = .commandedAndSettled(command: .lower, commandedState: .down)
    } else {
      guard let machineSession else {
        throw LearningPathOperationError.requiredState("Machine composition is unavailable.")
      }
      lower = await PlotterManualMotionComposition.settleNativePenCommand(
        using: machineSession,
        command: .lower,
        profile: currentPenActuationProfile
      )
    }
    guard case .commandedAndSettled(command: .lower, commandedState: .down) = lower else {
      if frameMode == .live, let machineSession {
        machineSnapshot = await machineSession.snapshot()
      }
      switch lower {
      case .ambiguous:
        blacklistedToolContactLocations.insert(location)
        throw LearningPathOperationError.possibleInk(String(describing: lower))
      case .refused:
        throw LearningPathOperationError.controllerRefused(String(describing: lower))
      case .commandedAndSettled:
        preconditionFailure("The successful Pen Down outcome was handled by the guard.")
      }
    }
    setSparseTipBatchPossibleInkLocation(location)
    try requireSparseTipBatchContinuation()

    let downTime = RuntimeTimestamp(
      monotonicNanoseconds: frameMode == .simulated
        ? captureNanoseconds + 1
        : max(nowNanoseconds(), captureNanoseconds + 1)
    )

    var finalPosition = plan.startPosition
    do {
      for (index, delta) in plan.pathDeltas.enumerated() {
        try requireSparseTipBatchContinuation()
        let expected = plan.pathPositions[index + 1]
        if frameMode == .simulated {
          let admission = await causalSimulatorEffectAdapter.admitRetainedWorkflowDrawing(
            delta: try SimulatedLearningMotionVector(dxMM: delta.dx, dyMM: delta.dy),
            owner: EpisodeAuthorityID(rawValue: "PlotterApplicationRuntime.sparseTipCalibration")
          )
          let operation: PlotterCausalSimulatorOperation
          switch admission {
          case let .admitted(value):
            operation = value
          case let .refused(refusal):
            throw LearningPathOperationError.controllerFailed(
              "Simulated sparse-tip drawing was refused: \(refusal.refusal)."
            )
          }
          let target = ContextualStopTarget.sparseTipBatchSegment(
            capabilityID: try sparseTipBatchCapabilityID(),
            operationOwner: .simulated(operation),
            location: location
          )
          let task = Task { [causalSimulatorEffectAdapter] in
            await causalSimulatorEffectAdapter.executeNaturally(operation)
          }
          installStoppableOperation(target: target, owner: .simulated(task))
          defer { clearStoppableOperation(matching: target) }
          try await cancelSparseTipSegmentIfRequested(target: target, owner: .simulated(task))
          let outcome = await task.value
          try requireSparseTipBatchContinuation()
          guard outcome.disposition == .naturallyCompleted else {
            throw LearningPathOperationError.possibleInk(
              "The 2 mm calibration circle stopped after contact; possible ink exists."
            )
          }
          finalPosition = try MachinePosition(
            x: outcome.finalMPos.xMM,
            y: outcome.finalMPos.yMM
          )
        } else {
          guard let machineSession else {
            throw LearningPathOperationError.requiredState(
              "Machine composition is unavailable."
            )
          }
          let request = DrawingStrokeRequest(
            delta: delta,
            feedMMPerMinute: min(
              plan.geometry.maximumFeedMMPerMinute,
              machineSnapshot?.machine.controllerAxisFeedLimits?
                .applicableFeedCeiling(for: delta)
                ?? plan.geometry.maximumFeedMMPerMinute
            )
          )
          let operation: DrawingStrokeOperation
          switch await machineSession.beginDrawingStroke(request) {
          case .admitted(let admitted):
            operation = admitted
          case .rejected(let outcome):
            throw operationError(for: outcome, possibleInk: true)
          }
          let target = ContextualStopTarget.sparseTipBatchSegment(
            capabilityID: try sparseTipBatchCapabilityID(),
            operationOwner: .liveOperation(operation.id),
            location: location
          )
          let task = Task { await operation.outcome() }
          installStoppableOperation(target: target, owner: .drawing(task))
          defer { clearStoppableOperation(matching: target) }
          try await cancelSparseTipSegmentIfRequested(target: target, owner: .drawing(task))
          let outcome = await task.value
          try requireSparseTipBatchContinuation()
          switch outcome {
          case .completed(let evidence):
            finalPosition = evidence.finalPosition
          case .cancelled(_, let penRaiseOutcome):
            machineSnapshot = await machineSession.snapshot()
            throw LearningPathOperationError.possibleInk(
              "The calibration circle was stopped; Pen Up outcome: \(penRaiseOutcome)"
            )
          case .ambiguous(let ambiguity):
            machineSnapshot = await machineSession.snapshot()
            throw LearningPathOperationError.possibleInk(
              ambiguity.actionableDescription
            )
          case .refused(let refusal):
            machineSnapshot = await machineSession.snapshot()
            throw LearningPathOperationError.controllerRefused(String(describing: refusal))
          }
        }
        guard MachinePositionAcceptancePolicy.accepts(finalPosition, target: expected) else {
          if frameMode == .simulated {
            simulatedLearningSnapshot = await simulatedLearningRuntime.snapshot()
          } else if let machineSession {
            machineSnapshot = await machineSession.snapshot()
          }
          throw LearningPathOperationError.controllerFailed(
            String(
              format: "A 2 mm calibration-circle chord did not settle within %.3f mm.",
              MachinePositionAcceptancePolicy.toleranceMM
            )
          )
        }
      }
    } catch {
      blacklistedToolContactLocations.insert(location)
      await raisePenAfterKnownCircleFailureIfNeeded()
      throw error
    }

    let raise: PenOutcome
    if frameMode == .simulated {
      let simulatedOutcome = await causalSimulatorEffectAdapter.executeRetainedWorkflowPen(
        .up,
        owner: EpisodeAuthorityID(rawValue: "PlotterApplicationRuntime.sparseTipCalibration")
      )
      applySimulatedCausalImmediateOutcome(
        simulatedOutcome,
        action: "Raise simulated pen after sparse-tip calibration"
      )
      if let refusal = simulatedOutcome.refusal { throw refusal }
      raise = .commandedAndSettled(command: .raise, commandedState: .up)
    } else {
      guard let machineSession else {
        throw LearningPathOperationError.requiredState("Machine composition is unavailable.")
      }
      raise = await PlotterManualMotionComposition.settleNativePenCommand(
        using: machineSession,
        command: .raise,
        profile: currentPenActuationProfile
      )
    }
    guard case .commandedAndSettled(command: .raise, commandedState: .up) = raise else {
      if frameMode == .live, let machineSession {
        machineSnapshot = await machineSession.snapshot()
      }
      blacklistedToolContactLocations.insert(location)
      throw operationError(for: raise, possibleInk: true)
    }
    try requireSparseTipBatchContinuation()
    try authorizeSparseTipPenUp()
    clearSparseTipBatchPossibleInkLocation(matching: location)
    let upTime = RuntimeTimestamp(
      monotonicNanoseconds: frameMode == .simulated
        ? downTime.monotonicNanoseconds + 1
        : max(nowNanoseconds(), downTime.monotonicNanoseconds + 1)
    )
    return (
      PenActuationEvidence(
        outcome: lower,
        profile: currentPenActuationProfile,
        timestamp: downTime
      ),
      PenActuationEvidence(
        outcome: raise,
        profile: currentPenActuationProfile,
        timestamp: upTime
      ),
      finalPosition
    )
  }

  private func raisePenAfterKnownCircleFailureIfNeeded() async {
    sparseTipPenUpAuthorization = nil
    if frameMode == .simulated {
      let truth = await causalSimulatorEffectAdapter.truthSnapshot()
      if truth.penPose == .down {
        let outcome = await causalSimulatorEffectAdapter.executeRetainedWorkflowPen(
          .up,
          owner: EpisodeAuthorityID(rawValue: "PlotterApplicationRuntime.sparseTipCalibration")
        )
        applySimulatedCausalImmediateOutcome(
          outcome,
          action: "Raise simulated pen after sparse-tip failure"
        )
      } else {
        simulatedLearningSnapshot = truth.runtime
      }
      return
    }
    guard let machineSession,
      machineSnapshot?.machine.stickyAmbiguity == nil
    else { return }
    _ = await PlotterManualMotionComposition.settleNativePenCommand(
      using: machineSession,
      command: .raise,
      profile: currentPenActuationProfile
    )
    machineSnapshot = await machineSession.snapshot()
  }

  private func undoSparseTipClick() async {
    guard let selectionID = pointSelectionEpisodeProjection.exactPointSelection.request?.id else {
      return
    }
    discardStagedTipObservationArtifacts()
    do {
      installPointSelectionProjection(try await pointSelectionRuntime.undo(selectionID: selectionID))
      explorationError = nil
    } catch {
      explorationError = actionableDescription(error)
    }
  }

  private func performPointSelectionCorrection(
    _ intent: PlotterLearningPointSelectionCorrectionAction
  ) async {
    switch intent {
    case .undoLastPoint:
      await undoSparseTipClick()
    case .clearPoints:
      await clearSparseTipClicks()
    }
  }

  private func clearSparseTipClicks() async {
    guard let selectionID = pointSelectionEpisodeProjection.exactPointSelection.request?.id else {
      return
    }
    discardStagedTipObservationArtifacts()
    do {
      installPointSelectionProjection(try await pointSelectionRuntime.clear(selectionID: selectionID))
      explorationError = nil
    } catch {
      explorationError = actionableDescription(error)
    }
  }

  private func rejectTipCalibration() async {
    await clearSparseTipClicks()
    if explorationError == nil {
      explorationError =
        "The proposed pen-tip calibration was rejected. No calibration was accepted; reselect the four corner points on the same frozen frame."
    }
  }

  private func discardStagedTipObservationArtifacts() {
    let rootKinds = Set(
      tipCalibrationRuntime.acceptedObservations.map {
        LearningArtifactKind.toolContactObservation($0.observation.id)
      }
    )
    if !rootKinds.isEmpty {
      var graph = learningArtifactGraph
      let invalidation = graph.invalidateCurrentRevisions(rootKinds: rootKinds)
      learningArtifactGraph = graph
      applyArtifactInvalidations(invalidation.allInvalidatedRevisionIDs)
    }
    proposedTipCameraRegistration = nil
  }

  private func captureNewSparseTipClickFrame(
    expectedSelection: PlotterTipCalibrationExpectedPointSelection
  ) async throws -> PlotterTipCalibrationExpectedPointSelection {
    let ownerID = LearningPathItemID.humanGuidedDiscovery(
      .calibratePenContactFromSparseMarks
    )
    guard activeExerciseAttemptOwnerID == ownerID,
      let attemptID = activeExerciseAttemptID,
      let currentRequest = pointSelectionEpisodeProjection.exactPointSelection.request,
      pointSelectionEpisodeProjection.exactPointSelection.phase == .collecting,
      pointSelectionEpisodeProjection.exactPointSelection.selectedPoints.isEmpty,
      currentRequest.id == expectedSelection.selectionID,
      currentRequest.frame == expectedSelection.exactFrame,
      currentRequest.presentationTransformRevision
        == expectedSelection.presentationTransformRevision,
      currentRequest.purpose == .toolContact,
      pendingToolContactEvidence.count == PlotterTipCalibrationRuntime.requiredPointCount,
      pendingToolContactEvidence.allSatisfy({ evidence in
        evidence.attemptID == attemptID
          && evidence.paperInstance.rawValue == explorationPaperInstanceRevision
      }),
      let priorClickFrame = pendingToolContactClickFrame,
      let priorDisplayedFrame = frozenPointSelectionFrame,
      exactTipClickFrame(priorClickFrame, matches: currentRequest.frame),
      priorDisplayedFrame.frame.id == priorClickFrame.frameID
    else {
      throw LearningPathOperationError.requiredState(
        "Capture New Click Frame requires the current empty four-mark point-selection request, unchanged Learning attempt, and unchanged paper."
      )
    }

    try await requireCurrentSettledPenUpForClickFrameReplacement()
    let replacementDisplayedFrame = try await captureProtocolFrame(
      newerThan: max(
        priorClickFrame.captureNanoseconds,
        priorDisplayedFrame.frame.captureNanoseconds
      )
    )
    let replacementClickFrame = try exactTipCalibrationFrame(replacementDisplayedFrame)
    guard replacementClickFrame.captureNanoseconds > priorClickFrame.captureNanoseconds,
      replacementClickFrame.frameID != priorClickFrame.frameID,
      replacementClickFrame.source == priorClickFrame.source,
      replacementClickFrame.opticalConfiguration == priorClickFrame.opticalConfiguration
    else {
      throw LearningPathOperationError.requiredState(
        "The camera owner did not publish a strictly newer frame with the same source and semantic optical identity."
      )
    }

    // Every await above is a reentrancy boundary. Reacquire both controller
    // truth and the point-selection/paper identities immediately before the
    // atomic supersession.
    try await requireCurrentSettledPenUpForClickFrameReplacement()
    guard activeExerciseAttemptOwnerID == ownerID,
      activeExerciseAttemptID == attemptID,
      pointSelectionEpisodeProjection.exactPointSelection.request == currentRequest,
      pointSelectionEpisodeProjection.exactPointSelection.phase == .collecting,
      pointSelectionEpisodeProjection.exactPointSelection.selectedPoints.isEmpty,
      pendingToolContactEvidence.allSatisfy({ evidence in
        evidence.attemptID == attemptID
          && evidence.paperInstance.rawValue == explorationPaperInstanceRevision
      })
    else {
      throw LearningPathOperationError.requiredState(
        "The click-frame request, Learning attempt, or paper changed before replacement could be committed."
      )
    }

    let staged = try await pointSelectionRuntime.replace(
      currentRequest: currentRequest,
      with: replacementDisplayedFrame,
      presentationTransformRevision: PlotterPresentationTransformRevision()
    )
    let replacement = PlotterTipCalibrationExpectedPointSelection(
      selectionID: staged.request.id,
      exactFrame: staged.request.frame,
      presentationTransformRevision: staged.request.presentationTransformRevision
    )
    guard exactTipClickFrame(replacementClickFrame, matches: staged.request.frame) else {
      throw LearningPathOperationError.requiredState(
        "The staged point-selection request did not retain the captured replacement-frame identity."
      )
    }
    installPointSelectionProjection(staged.projection)
    pendingToolContactClickFrame = replacementClickFrame
    frozenPointSelectionFrame = replacementDisplayedFrame
    pointSelectionRecordingDiagnostic =
      staged.recordingDiagnostic ?? pointSelectionRecordingDiagnostic
    explorationError = nil
    return replacement
  }

  private func requireCurrentSettledPenUpForClickFrameReplacement() async throws {
    if frameMode == .simulated {
      let snapshot = await simulatedLearningRuntime.snapshot()
      guard snapshot.session == .connected,
        snapshot.currentOperation == nil,
        snapshot.stickyAmbiguity == nil,
        snapshot.penPose == .up
      else {
        throw LearningPathOperationError.requiredState(
          "The simulated controller did not publish current connected, idle, unambiguous Pen-Up state."
        )
      }
      simulatedLearningSnapshot = snapshot
      return
    }
    guard let snapshot = await refreshControllerSessionSnapshot(),
      snapshot.currentOperation == .idle,
      snapshot.machine.connection == .connected,
      snapshot.machine.controllerState == .idle,
      !snapshot.machine.operationInFlight,
      snapshot.machine.stickyAmbiguity == nil,
      snapshot.machine.penState == .up
    else {
      throw LearningPathOperationError.requiredState(
        "The controller-session owner did not publish current connected, idle, unambiguous Pen-Up state."
      )
    }
  }

  private func exactTipClickFrame(
    _ clickFrame: ExactTipCalibrationFrame,
    matches selectionFrame: PlotterExactFrameReference
  ) -> Bool {
    let sourceMatches: Bool = switch (clickFrame.source, selectionFrame.source) {
    case (.simulated, .simulated): true
    case (.live(let deviceID), .live(let selectionDeviceID)):
      deviceID.rawValue == selectionDeviceID
    default: false
    }
    return sourceMatches
      && clickFrame.frameID.rawValue == selectionFrame.frameID
      && clickFrame.frameSHA256 == selectionFrame.frameSHA256
      && clickFrame.cameraConfigurationID == selectionFrame.cameraConfigurationID
      && clickFrame.captureNanoseconds == selectionFrame.captureNanoseconds
      && clickFrame.width == selectionFrame.width
      && clickFrame.height == selectionFrame.height
      && clickFrame.pixelFormat.rawValue == selectionFrame.pixelFormat.rawValue
  }

  private func acceptSparseTipBatchClicks(
    batch: PlotterTipCalibrationCompletedPointSelection
  ) throws -> PlotterTipCalibrationRetainedDomainEvidence {
    let points = batch.points
    let presentationRevision = PresentationTransformRevision(
      rawValue: batch.presentationTransformRevision.rawValue
    )
    guard
      pendingToolContactEvidence.count == PlotterTipCalibrationRuntime.orderedPositions.count,
      points.count == PlotterTipCalibrationRuntime.orderedPositions.count,
      let machineRegistration = machineCameraRegistration,
      let machineRegistrationRevision = learningArtifactGraph.currentRevision(
        for: .machineCameraRegistration
      )?.id,
      let attemptID = activeExerciseAttemptID,
      let optical = pendingToolContactEvidence.first?.revealEvidence.frame.opticalConfiguration,
      let exactClickFrame = pendingToolContactClickFrame,
      exactTipClickFrame(exactClickFrame, matches: batch.exactFrame),
      pendingToolContactEvidence.allSatisfy({ evidence in
        evidence.attemptID == attemptID
          && evidence.paperInstance.rawValue == explorationPaperInstanceRevision
      })
    else {
      throw LearningPathOperationError.requiredState(
        "Pen-tip calibration fitting requires four pending marks, four clicks, and accepted machine-camera registration."
      )
    }

    let associations = try associateSparseTipClicks(
      using: machineRegistration.fit,
      knownMachinePositions: pendingToolContactEvidence.map {
        SparseTipKnownMachinePosition(
          calibrationPosition: $0.position,
          machinePosition: $0.intendedMarkPosition
        )
      },
      clicks: points
    )
    let pendingByPosition = Dictionary(
      uniqueKeysWithValues: pendingToolContactEvidence.map { ($0.position, $0) }
    )
    let clickTimestamp = RuntimeTimestamp(
      monotonicNanoseconds: max(
        nowNanoseconds(),
        exactClickFrame.captureNanoseconds + 1
      )
    )
    var graph = learningArtifactGraph
    var accepted: [AcceptedToolContactObservation] = []
    for association in associations {
      guard let pending = pendingByPosition[association.calibrationPosition] else {
        throw LearningPathOperationError.requiredState(
          "Pen-tip calibration fitting could not match a clicked position to pending evidence."
        )
      }
      let click = try ToolContactClickEvidence(
        point: association.clickedCameraPoint,
        pointingUncertaintyPixels: Vector2(dx: 1.5, dy: 1.5),
        timestamp: clickTimestamp,
        presentationTransformRevision: presentationRevision,
        exactFrame: exactClickFrame
      )
      let observation = try ToolContactObservation(
        attemptID: pending.attemptID,
        operationID: pending.operationID,
        calibrationPosition: pending.position,
        intendedMarkPosition: pending.intendedMarkPosition,
        actualSettledPosition: pending.actualSettledPosition,
        machineGeometry: machineGeometryIdentity,
        controllerSessionID: controllerSessionID,
        machineCoordinateFrame: MachineCoordinateFrameRevision(
          rawValue: explorationCoordinateRevision
        ),
        controllerContextEvidence: pending.controllerContextEvidence,
        markGeometry: pending.markGeometry,
        penDown: pending.penDown,
        penUp: pending.penUp,
        toolAssembly: toolAssemblyRevision,
        penContactProfile: penContactProfileRevision,
        paperContactPlane: PaperContactPlaneRevision(
          rawValue: explorationPaperContactPlaneRevision
        ),
        preMarkFrame: pending.preMarkFrame,
        preMarkCapEstimate: pending.preMarkCapEstimate,
        revealEvidence: pending.revealEvidence,
        click: click,
        capMapPredictionAtMark: pending.capMapPredictionAtMark,
        disposition: .accepted,
        consumedLearningArtifactRevisionIDs: [machineRegistrationRevision],
        algorithmRevisions: [
          try AlgorithmRevisionEvidence(
            component: "sparse-tip-workspace",
            revision: "boundary-10mm-inset-four-circle-batch-unordered-global-association-v7"
          ),
          try AlgorithmRevisionEvidence(
            component: "pen-actuation",
            revision: currentPenActuationProfile.revision
          ),
        ]
      )
      let revision = LearningArtifactRevision(
        kind: .toolContactObservation(observation.id),
        attemptID: pending.attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: [machineRegistrationRevision]
      )
      _ = try graph.commitReplacement(revision)
      accepted.append(
        try AcceptedToolContactObservation(
          artifactRevisionID: revision.id,
          observation: observation
        )
      )
    }

    let selection = try TipCalibrationModelSelection.fitAffineFirst(
      acceptedObservations: accepted,
      capCameraFromMachine: machineRegistration.fit.cameraFromMachine
    )
    let registrationRevisionID = LearningArtifactRevisionID()
    let proposal = try TipCameraRegistration(
      modelForm: selection.modelForm,
      cameraFromMachine: selection.finalCameraFromMachine,
      modelSelectionEvidence: selection.evidence,
      uncertainty: selection.uncertainty,
      applicabilityRectangle: try SparseTipBatchMarkPlan.applicabilityRectangle(
        for: accepted.map { $0.observation.markGeometry }
      ),
      acceptedObservations: accepted,
      applicability: TipCalibrationApplicabilityContext(
        opticalConfiguration: optical,
        machineGeometry: machineGeometryIdentity,
        machineCoordinateFrame: MachineCoordinateFrameRevision(
          rawValue: explorationCoordinateRevision
        ),
        toolAssembly: toolAssemblyRevision,
        penContactProfile: penContactProfileRevision,
        paperContactPlane: PaperContactPlaneRevision(
          rawValue: explorationPaperContactPlaneRevision
        )
      ),
      acceptedRevisionID: registrationRevisionID,
      machineCameraRegistrationRevisionID: machineRegistrationRevision,
      estimatorRevision: SparseTipCircularMarkPlan.registrationEstimatorRevision,
      acceptedAt: RuntimeTimestamp(monotonicNanoseconds: nowNanoseconds())
    )
    _ = attemptID
    learningArtifactGraph = graph
    return PlotterTipCalibrationRetainedDomainEvidence(
      acceptedObservations: accepted,
      modelSelection: selection,
      proposedRegistration: proposal,
      retainedEvidenceIDs: Set(accepted.map { $0.artifactRevisionID.rawValue.uuidString.lowercased() })
    )
  }

  @discardableResult
  private func commitTipCalibration(actor: String) throws -> TipCameraRegistration {
    guard let proposal = proposedTipCameraRegistration,
      let attemptID = activeExerciseAttemptID,
      activeExerciseAttemptOwnerID
        == .humanGuidedDiscovery(
          .calibratePenContactFromSparseMarks
        )
    else {
      throw LearningPathOperationError.requiredState(
        "Tip-calibration commit requires an active reviewed proposal."
      )
    }
    do {
      let candidate = LearningArtifactRevision(
        id: proposal.acceptedRevisionID,
        kind: .tipCameraRegistration,
        attemptID: attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: proposal.consumedArtifactRevisionIDs
      )
      var graph = learningArtifactGraph
      let commit = try graph.commitReplacement(candidate)
      let acceptedTimestamp = RuntimeTimestamp(monotonicNanoseconds: nowNanoseconds())
      let acceptanceEvent = try TipCalibrationAcceptanceEvent(
        acceptedRevisionID: proposal.acceptedRevisionID,
        timestamp: acceptedTimestamp,
        actor: actor
      )
      let checkpoint = try AcceptedTipCalibrationCheckpoint(
        registration: proposal,
        acceptanceEvent: acceptanceEvent
      )
      learningArtifactGraph = graph
      applyArtifactInvalidations(commit.invalidatedRevisionIDs)
      restoreInteractiveLearningCompletionFromEvidence()
      frozenPointSelectionFrame = nil
      pendingToolContactEvidence = []
      pendingToolContactClickFrame = nil
      Task { @MainActor [weak self] in await self?.cancelPointSelectionRequest() }
      persistAcceptedLearningPathCheckpoint(tipCalibration: checkpoint, clearStageFour: true)
      finishActiveExerciseAttempt(disposition: .succeeded)
      explorationError = nil
      return proposal
    } catch {
      explorationError =
        "Tip-calibration commit failed atomically: \(actionableDescription(error))"
      throw error
    }
  }

  private func revalidateTipCalibration() async throws -> TipCameraRegistration? {
    let ownerID = LearningPathItemID.humanGuidedDiscovery(
      .calibratePenContactFromSparseMarks
    )
    if activeExerciseAttemptOwnerID == nil {
      beginExerciseAttempt(ownerID: ownerID, mode: .normal)
    }
    guard activeExerciseAttemptOwnerID == ownerID,
      let attemptID = activeExerciseAttemptID,
      var machineRegistration = machineCameraRegistration,
      let machineRegistrationRevision = learningArtifactGraph.currentRevision(
        for: .machineCameraRegistration
      )?.id,
      machineRegistration.opticalConfiguration.mountRevision == cameraMountRevision,
      machineRegistration.opticalConfiguration.reframingRevision == cameraReframingRevision
    else {
      throw LearningPathOperationError.requiredState(
        "Saved tip calibration revalidation requires the active owner, checkpoint, and current machine-camera registration."
      )
    }

    let operationID = UUID()
    var checkpoint = recoverableTipCalibrationCheckpoint
    let originalCheckpoint = checkpoint
    let originalMachineRegistration = machineRegistration
    let expectedSession = controllerSessionID
    let expectedSource = frameMode
    let expectedIdentity = currentLearningPathSemanticIdentity
    let expectedGraph = Set(learningArtifactGraph.revisions.filter { $0.state == .current }.map(\.id))
    let originalMachineCheckpoint = activeMachineArtifactCheckpoint
    let priorPackage = acceptedLearningPathCheckpoint
    let environment = penInteractionEnvironment
    func requireCurrentPositionRecovery() throws {
      guard applicationAdmissionIsOpen, !Task.isCancelled, frameMode == expectedSource,
        controllerSessionID == expectedSession,
        currentLearningPathSemanticIdentity == expectedIdentity,
        recoverableTipCalibrationCheckpoint == originalCheckpoint,
        machineCameraRegistration == originalMachineRegistration,
        activeMachineArtifactCheckpoint == originalMachineCheckpoint,
        Set(learningArtifactGraph.revisions.filter { $0.state == .current }.map(\.id)) == expectedGraph,
        activeExerciseAttemptID == attemptID, !drawingRunIsActive
      else { throw LearningPathOperationError.requiredState(
        "Position verification lost its camera, controller session, accepted dependencies, or active owner. Retry from the current position.") }
    }
    do {
      try requireCurrentPositionRecovery()
      let capture = try await captureCurrentCameraCapAnchorEvidence(
        contextBaseline: nil,
        operationID: operationID,
        requiresCurrentCaptureIdentity: true
      )
      try requireCurrentPositionRecovery()
      let exactFrame = try exactTipCalibrationFrame(capture.displayedFrame)
      if let originalCheckpoint,
        exactFrame.opticalConfiguration != originalCheckpoint.registration.applicability.opticalConfiguration {
        throw LearningPathOperationError.requiredState(
          "The current camera geometry does not match the accepted tip calibration. Restore that camera setup before re-establishing position.")
      }
      guard exactFrame.opticalConfiguration == originalMachineRegistration.opticalConfiguration else {
        throw LearningPathOperationError.requiredState(
          "The current camera geometry does not match the accepted machine/cap map. Restore that camera setup before re-establishing position.")
      }
      guard capture.capAnchor.estimatorRevision == originalMachineRegistration.capAnchorEstimatorRevision else {
        throw LearningPathOperationError.requiredState(
          "The learned cap appearance or anchor estimator changed (current \(capture.capAnchor.estimatorRevision), accepted \(originalMachineRegistration.capAnchorEstimatorRevision)). Restore the accepted cap appearance or repeat Camera Calibration for the changed cap.")
      }
      if expectedSource == .live {
        guard let baseline = capture.contextBaseline, let originalMachineCheckpoint else {
          throw LearningPathOperationError.requiredState(
            "Position recovery requires the accepted machine checkpoint and fresh controller context. Restore compatible Saved Learning and reconnect the controller before retrying.")
        }
        let controllerComparison = originalMachineCheckpoint.controllerContext.comparison(with: baseline.context)
        guard controllerComparison.isCompatible else {
          throw LearningPathOperationError.controllerContextChanged(controllerComparison)
        }
      }
      var effectiveCoordinateRevision = explorationCoordinateRevision
      var rebasedMachineCheckpoint: AcceptedMachineArtifactCheckpoint?
      var rebasedMachineCameraCheckpoint: AcceptedMachineCameraCheckpoint?
      var coordinateTranslation = try Vector2<MachineSpace>(dx: 0, dy: 0)
      let initialCapPrediction = try machineRegistration.fit.cameraPoint(
        from: capture.evidence.machinePoint
      )
      let initialCapResidual = initialCapPrediction.distance(to: capture.capAnchor.point)
      if case .requiresVisualRevalidation = controllerPoseApplicability,
        initialCapResidual > 8
      {
        guard let acceptedMachineCheckpoint = activeMachineArtifactCheckpoint else {
          throw LearningPathOperationError.requiredState(
            "The carriage moved relative to the saved cap map, but no accepted machine checkpoint is available to rebase."
          )
        }
        let formerMachinePoint = try machineRegistration.fit.machinePoint(
          from: capture.capAnchor.point
        )
        let physicalBoundary = try SparseTipBatchMarkPlan.boundaryEnvelope(for: acceptedBoundaryAggregates)
        guard physicalBoundary.contains(formerMachinePoint) else {
          throw LearningPathOperationError.requiredState(
            "The observed cap is outside the accepted physical machine extent. Verify the camera and pen-cap identity before retrying position recovery.")
        }
        let delta = try formerMachinePoint.vector(to: capture.evidence.machinePoint)
        coordinateTranslation = delta
        effectiveCoordinateRevision &+= 1
        let machineCheckpoint = try acceptedMachineCheckpoint
          .rebasedForKnownMachineCoordinateChange(
            to: effectiveCoordinateRevision,
            delta: delta
          )
        machineRegistration = try machineRegistration.rebasedForKnownMachineCoordinateChange(
          to: effectiveCoordinateRevision,
          delta: delta
        )
        let machineCameraCheckpoint = try AcceptedMachineCameraCheckpoint(
          revision: activeMachineCameraCheckpoint?.revision
            ?? LearningArtifactRevision(
              id: machineRegistrationRevision,
              kind: .machineCameraRegistration,
              attemptID: attemptID,
              disposition: .succeeded,
              consumedRevisionIDs: machineRegistration.correspondenceRevisionIDs
            ),
          registration: machineRegistration
        )
        if let priorTip = checkpoint {
          let rebasedTipRegistration = try priorTip.registration.rebasedForKnownMachineCoordinateChange(
            to: MachineCoordinateFrameRevision(rawValue: effectiveCoordinateRevision), delta: delta)
          checkpoint = try AcceptedTipCalibrationCheckpoint(
            registration: rebasedTipRegistration, acceptanceEvent: priorTip.acceptanceEvent)
        }
        rebasedMachineCheckpoint = machineCheckpoint
        rebasedMachineCameraCheckpoint = machineCameraCheckpoint
      }
      let capPrediction = try machineRegistration.fit.cameraPoint(
        from: capture.evidence.machinePoint
      )
      let controllerEvidence = try controllerContextEvidenceReference(
        capture.contextBaseline,
        operationID: operationID
      )
      var graph = learningArtifactGraph
      var restoredRegistration: TipCameraRegistration?
      var refreshedCheckpoint: AcceptedTipCalibrationCheckpoint?
      if let checkpoint {
        let currentApplicability = TipCalibrationApplicabilityContext(
          opticalConfiguration: exactFrame.opticalConfiguration,
          machineGeometry: machineGeometryIdentity,
          machineCoordinateFrame: MachineCoordinateFrameRevision(
            rawValue: effectiveCoordinateRevision
          ),
          toolAssembly: toolAssemblyRevision,
          penContactProfile: penContactProfileRevision,
          paperContactPlane: PaperContactPlaneRevision(
            rawValue: explorationPaperContactPlaneRevision
          )
        )
        let evidenceTimestamp = RuntimeTimestamp(
          monotonicNanoseconds: max(
            nowNanoseconds(),
            exactFrame.captureNanoseconds + 1
          )
        )
        let evidence = try TipCalibrationRevalidationEvidence(
          currentApplicability: currentApplicability,
          currentMachineCameraRegistrationRevisionID: machineRegistrationRevision,
          controllerContextEvidence: controllerEvidence,
          frame: exactFrame,
          capEstimate: capture.capAnchor,
          capMapPrediction: capPrediction,
          maximumCapMapResidualPixels: 8,
          timestamp: evidenceTimestamp,
          algorithmRevision: "explicit-tip-checkpoint-revalidation-and-coordinate-rebase-v2"
        )
        guard case .restored = checkpoint.revalidate(with: evidence) else {
          throw LearningPathOperationError.requiredState(
            "The saved pen-tip calibration is unavailable because it does not match the current machine, camera, tool, paper, or new pen-cap evidence."
          )
        }

        var rebuiltObservationRevisions: [ToolContactObservationID: LearningArtifactRevisionID] = [:]
        for observation in checkpoint.registration.observationEvidence {
          let revision = LearningArtifactRevision(
            kind: .toolContactObservation(observation.observationID),
            attemptID: attemptID,
            disposition: .succeeded,
            consumedRevisionIDs: [machineRegistrationRevision]
          )
          _ = try graph.commitReplacement(revision)
          rebuiltObservationRevisions[observation.observationID] = revision.id
        }
        let acceptedRevisionID = LearningArtifactRevisionID()
        let acceptedAt = RuntimeTimestamp(
          monotonicNanoseconds: max(
            nowNanoseconds(),
            evidenceTimestamp.monotonicNanoseconds + 1
          )
        )
        let acceptedRegistration = try checkpoint.registration.revalidatedFromCheckpoint(
          evidence: evidence,
          acceptedRevisionID: acceptedRevisionID,
          machineCameraRegistrationRevisionID: machineRegistrationRevision,
          observationArtifactRevisionIDs: rebuiltObservationRevisions,
          acceptedAt: acceptedAt
        )
        let tipRevision = LearningArtifactRevision(
          id: acceptedRevisionID,
          kind: .tipCameraRegistration,
          attemptID: attemptID,
          disposition: .succeeded,
          consumedRevisionIDs: acceptedRegistration.consumedArtifactRevisionIDs
        )
        _ = try graph.commitReplacement(tipRevision)
        let acceptanceEvent = try TipCalibrationAcceptanceEvent(
          acceptedRevisionID: acceptedRevisionID,
          timestamp: acceptedAt,
          actor: "operator-checkpoint-revalidation"
        )
        refreshedCheckpoint = try AcceptedTipCalibrationCheckpoint(
          registration: acceptedRegistration,
          acceptanceEvent: acceptanceEvent
        )
        restoredRegistration = acceptedRegistration
      }
      if expectedSource == .simulated {
        // The existing causal simulator revalidates its own checkpoint without
        // a hardware probe or any publication into the LIVE saved package.
        try requireCurrentPositionRecovery()
        withBatchedSemanticPresentationUpdate {
          learningArtifactGraph = graph
          tipCameraRegistration = restoredRegistration
          tipCalibrationRuntime.installPositionRecoveryAvailability(false)
          restoreInteractiveLearningCompletionFromEvidence()
          controllerPoseApplicability = .visuallyRevalidated(
            frameID: exactFrame.frameID, residualPixels: capPrediction.distance(to: capture.capAnchor.point))
          finishActiveExerciseAttempt(disposition: .succeeded)
          explorationError = nil
        }
        return restoredRegistration
      }
      guard let finalMachine = rebasedMachineCheckpoint ?? originalMachineCheckpoint else {
        throw LearningPathOperationError.requiredState("The accepted machine checkpoint became unavailable before position publication.")
      }
      let finalCamera = rebasedMachineCameraCheckpoint ?? activeMachineCameraCheckpoint
      let finalPackage = try AcceptedLearningPathCheckpoint(
        semanticIdentity: expectedIdentity,
        penInteraction: currentAcceptedPenInteractionCheckpoint(),
        machineArtifacts: finalMachine,
        machineCamera: finalCamera,
        tipCalibration: refreshedCheckpoint,
        stageFour: activeStageFourCheckpoint ?? priorPackage?.stageFour,
        penCapAppearance: try livePenCapAppearanceSelection?.acceptedCheckpoint() ?? priorPackage?.penCapAppearance,
        referenceFrame: try AcceptedLearningReferenceFrame(
          opticalConfiguration: exactFrame.opticalConfiguration, frame: capture.displayedFrame.frame)
      )
      _ = try finalPackage.restoredLearningGraph()
      try requireCurrentPositionRecovery()
      positionRebasePublicationIsPending = true
      defer { positionRebasePublicationIsPending = false }
      guard let reservation = await reserveBoundaryResetBeforePersistence() else {
        throw LearningPathOperationError.requiredState("Boundary ownership could not reserve the position update. Finish its current operation and retry.")
      }
      var durabilityCommitted = false
      let finalBoundary: PlotterBoundaryRuntimeSnapshot
      do {
        try requireCurrentPositionRecovery()
        if let actions = activeStatePersistencePort {
          do {
            try actions.saveAcceptedLearningPathCheckpoint(finalPackage)
          } catch {
            // A writer may throw after replacement. Restore the exact prior
            // immutable package rather than publishing any staged authority.
            if let priorPackage { try actions.saveAcceptedLearningPathCheckpoint(priorPackage) }
            throw error
          }
        }
        durabilityCommitted = true
        // No cancellation after the durable commit: this no-motion publication
        // must finish even if shutdown closes new UI admission meanwhile.
        finalBoundary = try await boundaryRuntime.commitRebasedMachineArtifacts(
          finalMachine, reservation: reservation, environment: environment)
      } catch {
        if durabilityCommitted, let actions = activeStatePersistencePort, let priorPackage {
          try actions.saveAcceptedLearningPathCheckpoint(priorPackage)
        }
        let reserved = await boundaryRuntime.snapshot(for: environment)
        _ = await boundaryRuntime.submit(.init(projection: reserved.projection.reference, intent: .abortReset(reservation)))
        throw error
      }
      withBatchedSemanticPresentationUpdate {
        positionRebasePublicationIsPending = false
        installBoundarySnapshot(finalBoundary)
        activeMachineArtifactCheckpoint = finalMachine
        activeMachineCameraCheckpoint = finalCamera
        machineCameraRegistration = finalCamera?.registration
        explorationCoordinateRevision = effectiveCoordinateRevision
        learningArtifactGraph = graph
        tipCameraRegistration = restoredRegistration
        tipCalibrationRuntime.installPositionRecoveryAvailability(false)
        artifactResetRuntime.installSavedLearningFact(.applied(finalPackage,
          opticalComparison: "Physical position re-established from a fresh stable cap and matching controller reports."))
        activeStageFourCheckpoint = finalPackage.stageFour
        controllerPoseApplicability = .visuallyRevalidated(
          frameID: exactFrame.frameID, residualPixels: capPrediction.distance(to: capture.capAnchor.point))
        acceptedArtifactCheckpointStatus = .restored(
          sideCount: finalMachine.acceptedBoundaryAggregates.count,
          centerArrival: finalMachine.centerArrivalPosition != nil,
          reportedPositionDeltaMM: hypot(coordinateTranslation.dx, coordinateTranslation.dy))
        restoreInteractiveLearningCompletionFromEvidence()
        finishActiveExerciseAttempt(disposition: .succeeded)
        explorationError = nil
      }
      return restoredRegistration
    } catch {
      finishActiveExerciseAttempt(disposition: .failed(actionableDescription(error)))
      explorationError =
        "Physical position was not re-established: \(actionableDescription(error))"
      throw error
    }
  }

  private func exactTipCalibrationFrame(_ displayed: DisplayedFrame) throws
    -> ExactTipCalibrationFrame
  {
    guard let contentSHA256 = displayed.frame.materializedContentSHA256 else {
      throw LearningPathOperationError.requiredState(
        "The current camera frame is preview-only. Wait for automatic analysis or capture an exact frame before using exact-frame Learning evidence."
      )
    }
    let configurationRevision = displayed.frame.cameraConfigurationID.rawValue
    let optical = try CameraOpticalConfigurationIdentity(
      source: displayed.source,
      sensorFormat: "runtime-\(displayed.frame.pixelFormat.rawValue)",
      width: displayed.frame.width,
      height: displayed.frame.height,
      pixelFormat: displayed.frame.pixelFormat,
      orientation: .up,
      mirrored: false,
      digitalZoomFactor: 1,
      lensIdentity: "runtime-unreported-lens",
      focusConfiguration: "runtime-unreported-focus",
      mountRevision: cameraMountRevision,
      reframingRevision: cameraReframingRevision
    )
    return try ExactTipCalibrationFrame(
      frameID: displayed.frame.id,
      frameSHA256: contentSHA256,
      source: displayed.source,
      captureSessionID: CameraCaptureSessionID(rawValue: configurationRevision),
      opticalConfiguration: optical,
      cameraConfigurationID: displayed.frame.cameraConfigurationID,
      captureNanoseconds: displayed.frame.captureNanoseconds,
      width: displayed.frame.width,
      height: displayed.frame.height,
      pixelFormat: displayed.frame.pixelFormat
    )
  }

  private func controllerContextEvidenceReference(
    _ baseline: ControllerContextBaseline?,
    operationID: UUID
  ) throws -> ControllerContextEvidenceReference {
    let data: Data
    let probeID: UUID
    if let baseline {
      data = try JSONEncoder().encode(baseline)
      probeID = baseline.probeID
    } else {
      data = Data("simulated-sparse-tip-\(controllerSessionID.uuidString)".utf8)
      probeID = operationID
    }
    return try ControllerContextEvidenceReference(
      passiveProbeID: probeID,
      evidenceSHA256: RunLedger.sha256Hex(data),
      algorithmRevision: "sparse-tip-controller-context-v1"
    )
  }

  private func recordPaperReplaced() async {
    await recordPaperReplacement(contactPlaneChanged: false)
  }

  func recordNewPaperSheetOnCurrentPlane() async {
    await recordPaperReplacement(contactPlaneChanged: false)
  }

  /// Records a new sheet on a changed support/stock/contact plane. Ordinary
  /// sheet replacement uses `recordPaperReplaced()` and deliberately retains
  /// current tip calibration.
  func recordPaperContactPlaneChanged() async {
    await recordPaperReplacement(contactPlaneChanged: true)
  }

  /// Nil means this declaration applied; otherwise return its own actionable
  /// failure to the existing UI refusal channel, independently of old warnings.
  @discardableResult
  private func recordPaperReplacement(contactPlaneChanged: Bool) async -> String? {
    do {
      let plan = try makePaperReplacementPlan(contactPlaneChanged: contactPlaneChanged)
      let intent = PlotterArtifactResetIntent.paperReplaced(plan)
      guard await artifactResetRuntime.submit(intent, facts: artifactResetAdmissionFacts) else {
        let remedy = artifactResetRuntime.snapshot().terminalHistory.last {
          $0.intent == intent
        }?.detail ?? "Paper replacement was not applied. Review the current paper transaction in Diagnostics and retry."
        explorationError = remedy
        return remedy
      }
      return nil
    } catch {
      let remedy = "Paper replacement was refused: \(actionableDescription(error))"
      explorationError = remedy
      return remedy
    }
  }

  private func makePaperReplacementPlan(
    contactPlaneChanged: Bool
  ) throws -> PlotterArtifactResetPlan {
    let transition: PaperReplacementTransition?
    if frameMode == .live {
      let declaration: PaperContactPlaneReplacementDeclaration = contactPlaneChanged
        ? .changed(to: PaperContactPlaneRevision())
        : .explicitlyUnchanged(currentPaperRevisionContext.contactPlane)
      transition = try PaperReplacementTransition(
        previous: currentPaperRevisionContext,
        newPaperInstance: PaperInstanceRevision(),
        contactPlaneDeclaration: declaration
      )
    } else {
      // Simulated paper is a causal-scene fact, not a claim that LIVE identity
      // or checkpoint persistence occurred.
      transition = nil
    }
    return PlotterArtifactResetPlan(
      id: "paper-replaced-\(frameMode.rawValue)-\(UUID().uuidString)",
      expectedCurrentRevisionIDs: Set(learningArtifactGraph.revisions.filter { $0.state == .current }.map(\.id)),
      expectedAcceptedAttemptSequence: acceptedAttemptSequence,
      sourceIsSimulated: frameMode == .simulated,
      resetAll: false,
      removesDurableMachineCheckpoint: false,
      removesDurableTipCheckpoint: false,
      physicalInkMayRemain: true,
      paperReplacement: transition,
      previousAcceptedCheckpoint: {
        guard frameMode == .live, let actions = activeStatePersistencePort,
          case .loaded(let checkpoint) = actions.loadAcceptedLearningPathCheckpoint() else { return nil }
        return checkpoint
      }(),
      expectedControllerSessionID: controllerSessionID
    )
  }

  func runBorderValidation() async {
    guard tipCameraRegistration != nil,
      borderValidationSnapshot.activeOperationID == nil
    else { return }
    if activeExerciseAttemptOwnerID == nil {
      beginExerciseAttempt(
        ownerID: .borderValidation(.chooseDrawingBorderPlan),
        mode: activeExerciseAttemptMode ?? .normal
      )
    }
    explorationError = nil
    restartableExerciseItemID = nil
    let snapshot = await borderValidationRuntime.submit(.begin)
    switch snapshot.phase {
    case .accepted:
      finishActiveExerciseAttempt(disposition: .succeeded)
    case .possibleInk(let detail):
      explorationError = detail
      finishActiveExerciseAttempt(
        disposition: .failed("Ink may exist; automatic redraw is prohibited.")
      )
      restartableExerciseItemID = nil
    case .cancelled(let detail):
      explorationError = detail
      finishActiveExerciseAttempt(disposition: .cancelled)
      restartableExerciseItemID = .borderValidation(.chooseDrawingBorderPlan)
    case .failed(let detail), .rejected(let detail):
      explorationError = detail
      finishActiveExerciseAttempt(disposition: .failed(detail))
      restartableExerciseItemID = .borderValidation(.chooseDrawingBorderPlan)
    case .idle, .planning, .capturingBaseline, .movingToStart, .executingBorder,
      .revealingAndObserving, .reviewingComparison:
      break
    }
  }

  private func submitBorderValidationDecision(
    _ intent: PlotterBorderValidationIntent
  ) async {
    guard activeExerciseAttemptOwnerID
      == .borderValidation(.chooseDrawingBorderPlan)
    else { return }
    switch intent {
    case .acceptObservedPrediction, .reject:
      break
    case .begin:
      return
    }
    guard borderValidationRuntime.snapshot().activeOperationID == nil,
      case .reviewingComparison = borderValidationRuntime.snapshot().phase
    else { return }

    let snapshot = await borderValidationRuntime.submit(intent)
    switch snapshot.phase {
    case .accepted:
      explorationError = nil
      restartableExerciseItemID = nil
      finishActiveExerciseAttempt(disposition: .succeeded)
    case .rejected(let detail):
      explorationError = detail
      restartableExerciseItemID = nil
      finishActiveExerciseAttempt(disposition: .failed(detail))
    case .failed(let detail):
      explorationError = detail
      restartableExerciseItemID = nil
      finishActiveExerciseAttempt(disposition: .failed(detail))
    case .cancelled(let detail):
      explorationError = detail
      restartableExerciseItemID = nil
      finishActiveExerciseAttempt(disposition: .cancelled)
    case .possibleInk(let detail):
      explorationError = detail
      restartableExerciseItemID = nil
      finishActiveExerciseAttempt(
        disposition: .failed("Ink may exist; automatic redraw is prohibited.")
      )
    case .idle, .planning, .capturingBaseline, .movingToStart, .executingBorder,
      .revealingAndObserving, .reviewingComparison:
      break
    }
  }

  private var learningConnectionAndMotionUnavailableReason: String? {
    if !sessionEstablished {
      let target = frameMode == .simulated ? "learning simulator" : "selected plotter"
      let detail = controllerAttentionText.map { " Current controller state: \($0)" } ?? ""
      return
        "Blocked by controller connection. Use Connect for the \(target) in the workbench toolbar; Enable Motion depends on a connected session.\(detail)"
    }
    if !sessionMotionAuthorized {
      return
        "Blocked by Motion authorization. Use Enable Motion in the workbench toolbar for this connected session."
    }
    return nil
  }

  private func learningExerciseMotionUnavailableReason(
    requiresCamera: Bool,
    normalizesPenUp: Bool = false
  ) -> String? {
    if let reason = learningConnectionAndMotionUnavailableReason { return reason }
    if frameMode == .simulated {
      if simulatedLearningSnapshot?.currentOperation != nil {
        return "Stop or finish the current simulated operation first."
      }
      if requiresCamera, observationRuntime == nil {
        return "The simulator camera composition is unavailable."
      }
      return nil
    }
    if let reason = retainedPoseApplicabilityRefusal { return reason }
    if let reason = normalizesPenUp
      ? retainedCarriageSafetyRefusal : controllerCarriageTravelUnavailableReason
    { return reason }
    if requiresCamera, !cameraIsLive { return "A current LIVE camera frame is required." }
    return nil
  }

  func discoveryStartUnavailableReason(for sequenceID: DiscoverySequenceID) -> String? {
    if learningResetInProgress { return "Reset All Learning is in progress." }
    if let activeDiscoverySequenceID {
      return
        "Finish \(DiscoverySequenceCatalog.definition(for: activeDiscoverySequenceID).title); use Stop while its motion is active."
    }
    if sequenceID == .penInteraction {
      guard displayedFrame != nil else {
        return "A current exact camera or simulated frame is required to Identify Pen Cap."
      }
      return nil
    }
    if let reason = learningConnectionAndMotionUnavailableReason { return reason }
    if frameMode == .simulated {
      if simulatedLearningSnapshot?.currentOperation != nil {
        return "Stop or finish the current simulated operation first."
      }
      switch sequenceID {
      case .boundaryNegativeX, .boundaryPositiveX, .boundaryNegativeY, .boundaryPositiveY:
        return nil
      case .penInteraction:
        return nil
      }
    }
    switch sequenceID {
    case .boundaryNegativeX, .boundaryPositiveX, .boundaryNegativeY, .boundaryPositiveY:
      return learningCarriageMotionUnavailableReason
    case .penInteraction:
      return learningPenCommandUnavailableReason(for: .lower)
    }
  }

  private func installBorderValidationRuntimeProjection(
    _ snapshot: PlotterBorderValidationSnapshot,
    source: OperatorFrameMode
  ) {
    guard frameMode == source else { return }
    switch snapshot.phase {
    case .possibleInk(let detail):
      explorationError = detail
      restartableExerciseItemID = nil
    default:
      break
    }
    markSemanticPresentationChanged()
  }

  var workbenchStatusText: String {
    if let actionableError { return actionableError }
    if !sessionEstablished {
      return frameMode == .simulated
        ? "Press Connect to start the nonphysical learning simulator session."
        : "Select the remembered controller and press Connect."
    }
    if !sessionMotionAuthorized {
      return frameMode == .simulated
        ? "Simulator connected. Enable Motion before this action."
        : "Plotter connected. Enable Motion before this action."
    }
    return switch manualControllerPenState {
    case .raised:
      "Motion enabled; manual controls will move with the commanded pen Up."
    case .lowered:
      "Motion enabled; manual controls will draw with the commanded pen Down."
    case .unknown:
      "Motion enabled; manual controls may move with possible ink because pen state is unknown."
    }
  }

  private var manualEpisodeModeText: String {
    switch manualControllerPenState {
    case .raised: "travel — commanded Pen Up"
    case .lowered: "drawing — commanded Pen Down"
    case .unknown: "manual move — possible ink; pen state unknown"
    }
  }

  var learningModePresentation: LearningModePresentation {
    let availability = PlotterLearningIntentRules.modeAvailability(
      targetIsEnabled: !learningIsEnabled,
      exactPointSelection: pointSelectionEpisodeProjection.exactPointSelection,
      activityFact: learningActivityFact(revision: learningActivityFactRevision)
    )
    return LearningModePresentation(
      isEnabled: learningIsEnabled,
      actionTitle: learningIsEnabled ? "Turn Learning Off" : "Turn Learning On",
      refusalRequirement: availability.refusalRequirement,
      refusalOwner: availability.refusalOwner,
      remedy: availability.refusalRemedy,
      recordingDiagnostic: pointSelectionRecordingDiagnostic
    )
  }

  private func setLearningEnabledFromPlotterUI(_ target: Bool) async {
    guard target != learningIsEnabled else { return }
    let pointSelectionOwner = activePointSelectionActivityOwner
    do {
      let projection = try await pointSelectionRuntime.setLearningEnabled(
        target,
        activityFactProvider: self
      )
      let retainedExactOwner = activePointSelectionActivityOwner == pointSelectionOwner
      installPointSelectionProjection(projection)
      if !target, !projection.learningIsEnabled {
        frozenPointSelectionFrame = nil
        pendingToolContactEvidence = []
        pendingToolContactClickFrame = nil
        if let pointSelectionOwner,
          retainedExactOwner,
          let pointSelectionOwnerID = activeExerciseAttemptOwnerID
        {
          await cancelExerciseAttempt(
            pointSelectionOwnerID,
            expectedAttemptID: ExerciseAttemptID(
              rawValue: pointSelectionOwner.exerciseAttemptID
            )
          )
        }
      }
    } catch {
      learningAuthorityError = actionableDescription(error)
    }
  }

  func currentLearningActivityFact() async -> PlotterLearningActivityFact {
    learningActivityFactRevision &+= 1
    return learningActivityFact(revision: learningActivityFactRevision)
  }

  private func learningActivityFact(revision: UInt64) -> PlotterLearningActivityFact {
    return PlotterLearningActivityFact(
      owner: EpisodeAuthorityID(rawValue: "PlotterApplicationRuntime.LearningActivityAdapter"),
      revision: CapabilityFactRevision(rawValue: revision),
      activeCameraCalibration: cameraCalibrationRuntimePhase != nil,
      activeAttempt: activeExerciseAttemptOwnerID != nil,
      activeDiscovery: activeDiscoverySequenceID != nil,
      activeExploration: borderValidationSnapshot.activeOperationID != nil,
      activeLearningMotion: activeStopTarget != nil,
      pointSelectionOwner: activePointSelectionActivityOwner
    )
  }

  private var activePointSelectionActivityOwner: PlotterPointSelectionActivityOwner? {
    let exactSelection = pointSelectionEpisodeProjection.exactPointSelection
    let exactSelectionIsCancellable = exactSelection.phase == .collecting
      || (exactSelection.phase == .continuing && exactSelection.continuationIsActive)
    guard
      exactSelectionIsCancellable,
      let selectionID = exactSelection.request?.id,
      let attemptID = activeExerciseAttemptID,
      activeExerciseAttemptOwnerID == .humanGuidedDiscovery(.penInteraction)
        || activeExerciseAttemptOwnerID
          == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    else { return nil }
    return PlotterPointSelectionActivityOwner(
      selectionID: selectionID,
      exerciseAttemptID: attemptID.rawValue
    )
  }

  var machinePositionText: String {
    if frameMode == .simulated, let mpos = simulatedLearningSnapshot?.mpos {
      return String(format: "simulated X %.3f   Y %.3f", mpos.xMM, mpos.yMM)
    }
    guard let point = machineSnapshot?.machine.position?.point else { return "unknown" }
    return String(format: "X %.3f   Y %.3f", point.x, point.y)
  }

  var penStateText: String {
    if frameMode == .simulated, let pose = simulatedLearningSnapshot?.penPose {
      return "simulated \(pose.rawValue) — not a physical observation"
    }
    return switch machineSnapshot?.machine.penState ?? .unknown {
    case .unknown:
      "unknown — no physical pose assumed"
    case .up:
      "commanded up — not visually observed"
    case .down:
      "commanded down — not visually observed"
    }
  }

  var lastMotionOutcomeText: String {
    if frameMode == .simulated {
      return lastContextualStopAuditRecord?.outcome ?? "no simulated motion outcome"
    }
    let lastManualJogRouting: PlotterManualJogRouting? = {
      guard let result = manualMotionEpisodeSnapshot?.projection.lastTerminalEffect?.result,
        case .manualMotion(.jog(let request)) = result.context.intent
      else { return nil }
      return request.routing
    }()
    if lastManualJogRouting == .drawingStroke,
      let outcome = machineSnapshot?.lastDrawingStrokeOutcome
    {
      return switch outcome {
      case .completed(let evidence):
        String(
          format: "drawing completed at X %.3f Y %.3f",
          evidence.finalPosition.point.x,
          evidence.finalPosition.point.y
        )
      case .cancelled(let evidence, let penRaiseOutcome):
        String(
          format: "drawing stopped at X %.3f Y %.3f; Pen Up: %@",
          evidence.finalPosition.point.x,
          evidence.finalPosition.point.y,
          String(describing: penRaiseOutcome)
        )
      case .refused(let refusal):
        "drawing refused: \(refusal.actionableDescription)"
      case .ambiguous(let ambiguity):
        "drawing ambiguous: \(ambiguity.actionableDescription)"
      }
    }
    guard let outcome = machineSnapshot?.lastMotionOutcome else { return "none" }
    switch outcome {
    case .refused(let reason):
      return "refused: \(reason.actionableDescription)"
    case .acceptedThenCompleted(let finalPosition):
      return String(
        format: lastManualJogRouting == .possibleInk
          ? "completed at X %.3f Y %.3f; possible ink"
          : "completed at X %.3f Y %.3f",
        finalPosition.point.x,
        finalPosition.point.y
      )
    case .cancelled(let finalPosition):
      return String(
        format: lastManualJogRouting == .possibleInk
          ? "cancelled at X %.3f Y %.3f; possible ink"
          : "cancelled at X %.3f Y %.3f",
        finalPosition.point.x,
        finalPosition.point.y
      )
    case .ambiguous(let ambiguity):
      return "ambiguous: \(ambiguity.actionableDescription)"
    }
  }

  var lastPenOutcomeText: String {
    if frameMode == .simulated, let pose = simulatedLearningSnapshot?.penPose {
      return "simulated \(pose.rawValue); not physical evidence"
    }
    guard let outcome = machineSnapshot?.lastPenOutcome else { return "none" }
    switch outcome {
    case .refused(let reason):
      return "refused: \(reason.actionableDescription)"
    case .commandedAndSettled(let command, let commandedState):
      return "\(command.rawValue) acknowledged; commanded \(commandedState.rawValue)"
    case .ambiguous(let ambiguity):
      return "ambiguous: \(ambiguity.actionableDescription)"
    }
  }

  var actionableError: String? {
    if let cameraError { return cameraError }
    if let visionError { return visionError }
    if frameMode == .simulated { return discoveryError ?? explorationError }
    if let machineError { return machineError }
    if let blocker = machineSnapshot?.machine.blockers.first {
      return machineBlockerLabel(blocker)
    }
    if case .refused(let refusal) = machineSnapshot?.lastMotionOutcome {
      return refusal.actionableDescription
    }
    if case .ambiguous(let ambiguity) = machineSnapshot?.lastMotionOutcome {
      return ambiguity.actionableDescription
    }
    if case .refused(let refusal) = machineSnapshot?.lastPenOutcome {
      return refusal.actionableDescription
    }
    if case .ambiguous(let ambiguity) = machineSnapshot?.lastPenOutcome {
      return ambiguity.actionableDescription
    }
    return nil
  }

  private func manualMotionDraftUnavailableReason(for draft: ManualMotionDraft) -> String? {
    guard let x = inputNumber(draft.xDistanceMM),
      let y = inputNumber(draft.yDistanceMM),
      let feed = inputNumber(draft.feedMMPerMinute)
    else { return "Enter numeric X distance, Y distance, and feed values." }
    guard x > 0, y > 0 else {
      return "X and Y distance magnitudes must be greater than zero."
    }
    guard feed > 0 else { return "Feed must be greater than zero." }
    return nil
  }

  private var manualControllerPenState: PlotterControllerPenState {
    if frameMode == .simulated {
      guard let pose = simulatedLearningSnapshot?.penPose else { return .unknown }
      return switch pose {
      case .unknown: .unknown
      case .up: .raised
      case .down: .lowered
      }
    }
    return switch machineSnapshot?.machine.penState ?? .unknown {
    case .unknown: .unknown
    case .up: .raised
    case .down: .lowered
    }
  }

  private var manualMotionEnvironment: PlotterEnvironment {
    frameMode == .live ? .live : .simulated
  }

  private var manualEpisodePenStateText: String {
    switch manualControllerPenState {
    case .unknown:
      return manualMotionEnvironment == .live
        ? "unknown — no physical pose assumed"
        : "simulated unknown — not physical evidence"
    case .raised:
      return manualMotionEnvironment == .live
        ? "commanded up — not visually observed"
        : "simulated up — not physical evidence"
    case .lowered:
      return manualMotionEnvironment == .live
        ? "commanded down — not visually observed"
        : "simulated down — not physical evidence"
    }
  }

  private func manualJogRequestPrototype(draft: ManualMotionDraft) -> PlotterJogRequest {
    try! PlotterJogRequest(
      direction: .positiveX,
      distanceMM: max(1, inputNumber(draft.xDistanceMM) ?? 1),
      feedMMPerMinute: max(1, inputNumber(draft.feedMMPerMinute) ?? 1),
      routing: manualControllerPenState.requiredJogRouting
    )
  }

  private func manualPenRequest(position: PlotterPenPosition) -> PlotterPenActuationRequest {
    PlotterPenActuationRequest(
      position: position,
      profile: try! PlotterManualPenActuationProfile(
        raisedSpindleValue: currentPenActuationProfile.raisedSpindleValue,
        loweredSpindleValue: currentPenActuationProfile.loweredSpindleValue,
        settleSeconds: currentPenActuationProfile.settleSeconds,
        revision: EpisodeRevisionIdentifier(rawValue: currentPenActuationProfile.revision)
      )
    )
  }

  private var manualMotionPublicationRecoveryPresentation:
    ManualMotionPublicationRecoveryPresentation?
  {
    guard let issue = manualMotionEpisodeSnapshot?.terminalPublicationIssue else { return nil }
    let intent = manualMotionEpisodeSnapshot?.activeOperation?.intent
    let title: String
    let remedy: String
    switch intent {
    case let .jog(request):
      if request.routing == .drawingStroke {
        title = "Retry Manual Drawing Publication"
        remedy =
          "The manual drawing terminal result was not durably published. Retry this exact publication; the drawing command will not be issued again."
      } else {
        title = "Retry Manual Jog Publication"
        remedy =
          "The manual jog terminal result was not durably published. Retry this exact publication; the jog command will not be issued again."
      }
    case let .setPen(request):
      let pose = request.position == .raised ? "Pen Up" : "Pen Down"
      title = "Retry \(pose) Publication"
      remedy =
        "The \(pose) terminal result was not durably published. Retry this exact publication; the Pen command will not be issued again."
    case nil:
      title = "Retry Manual Result Publication"
      remedy =
        "The manual-operation terminal result was not durably published. Retry this exact publication; no controller command will be issued again."
    }
    return ManualMotionPublicationRecoveryPresentation(
      capabilityID: issue.recoveryCapabilityID,
      title: title,
      remedy: remedy
    )
  }

  private var manualMotionEvidenceDispositionPresentation:
    ManualMotionEvidenceDispositionPresentation?
  {
    guard let action = manualMotionEpisodeSnapshot?.evidenceDispositionAction else { return nil }
    switch action.disposition {
    case .acknowledgePossibleInk:
      return ManualMotionEvidenceDispositionPresentation(
        action: action,
        title: "Acknowledge Possible Ink",
        remedy:
          "Review the exact ambiguous manual-motion observation and acknowledge that ink may exist. This records only the operator disposition; it will not redraw or reissue controller work."
      )
    case .acknowledgeAmbiguity:
      return ManualMotionEvidenceDispositionPresentation(
        action: action,
        title: "Acknowledge Ambiguous Outcome",
        remedy:
          "Review the exact ambiguous manual-motion observation before continuing. This records only the operator disposition; it will not retry or reissue controller work."
      )
    }
  }

  private func manualMotionRequirementReason(
    for intent: PlotterManualMotionIntent
  ) -> String? {
    let episodeID = manualMotionEpisodeSnapshot?.projection.episodeID
      ?? EpisodeID(rawValue: UUID())
    let state = PlotterEpisodeState(
      episodeID: episodeID,
      canonicalDigest: EpisodeStateDigest(rawValue: "manual-motion-presentation"),
      phase: manualMotionEpisodeSnapshot?.projection.phase ?? .ready
    )
    return PlotterManualMotionIntentRules.requirements(
      for: intent,
      state: state,
      capabilityFacts: manualMotionCapabilityFacts(environment: manualMotionEnvironment),
      environment: manualMotionEnvironment
    ).first(where: { !$0.isSatisfied })?.remedy
  }

  private func manualMotionCapabilityFacts(
    environment: PlotterEnvironment
  ) -> [PlotterCapabilityFact] {
    let owner = EpisodeAuthorityID(rawValue: "MachineController")
    let revision = CapabilityFactRevision(rawValue: semanticPresentationRevision)
    let isConnected: Bool
    let motionEnabled: Bool
    let position: Point2<MachineSpace>?
    let isSettled: Bool
    let operationIsActive: Bool
    if environment == .simulated {
      let snapshot = simulatedLearningSnapshot
      isConnected = snapshot?.session == .connected
      motionEnabled = snapshot?.motionAuthorization == .enabled
      position = snapshot.flatMap { try? Point2(x: $0.mpos.xMM, y: $0.mpos.yMM) }
      operationIsActive = snapshot?.currentOperation != nil
      isSettled = !operationIsActive
    } else {
      let snapshot = machineSnapshot
      isConnected = snapshot?.machine.connection == .connected
      motionEnabled = snapshot?.machine.motionGuardState == .active
      position = snapshot?.machine.position?.point
      operationIsActive = snapshot?.machine.operationInFlight == true
        || snapshot?.currentOperation != .idle
      isSettled = !operationIsActive && snapshot?.machine.controllerState == .idle
    }
    return [
      .connection(PlotterConnectionFact(
        owner: owner,
        revision: revision,
        environment: environment,
        isConnected: isConnected
      )),
      .motion(PlotterMotionFact(
        owner: owner,
        revision: revision,
        environment: environment,
        isEnabled: motionEnabled
      )),
      .pose(PlotterPoseFact(
        owner: owner,
        revision: revision,
        environment: environment,
        machinePosition: position,
        isSettled: isSettled,
        settlementPolicyRevision: EpisodeRevisionIdentifier(
          rawValue: environment == .live
            ? "native-controller-settlement-v1" : "causal-simulator-settlement-v1"
        )
      )),
      .manualController(PlotterManualControllerFact(
        owner: owner,
        revision: revision,
        environment: environment,
        penState: manualControllerPenState,
        operationIsActive: operationIsActive,
        penActuationProfileRevision: EpisodeRevisionIdentifier(
          rawValue: currentPenActuationProfile.revision
        )
      )),
    ]
  }

  private func installManualMotionSnapshot(_ snapshot: PlotterManualMotionRuntimeSnapshot) {
    let previousAttentionRemedy = manualMotionRuntimePresentation.attentionReason
      ?? manualMotionEpisodeSnapshot?.projection.remedy
    manualMotionEpisodeSnapshot = snapshot
    if snapshot.terminalPublicationIssue == nil,
       snapshot.evidenceDispositionAction == nil,
       machineError == previousAttentionRemedy {
      machineError = nil
    }
    if let remedy = manualMotionRuntimePresentation.attentionReason
      ?? snapshot.projection.remedy {
      machineError = remedy
    }
  }

  private func refreshManualEnvironmentSnapshot() async {
    if frameMode == .simulated {
      simulatedLearningSnapshot = await simulatedLearningRuntime.snapshot()
    } else if let machineSession {
      machineSnapshot = await machineSession.snapshot()
    }
  }

  private var learningStickyAmbiguityReason: String? {
    if frameMode == .simulated, let ambiguity = simulatedLearningSnapshot?.stickyAmbiguity {
      return
        "Sticky simulated ambiguity at \(String(describing: ambiguity.context)). Disconnect and reconnect before any machine-affecting action."
    }
    if let ambiguity = machineSnapshot?.machine.stickyAmbiguity {
      return
        "\(ambiguity.actionableDescription) Disconnect and reconnect before any machine-affecting action."
    }
    return nil
  }

  private var controllerCarriageTravelUnavailableReason: String? {
    if let reason = retainedCarriageSafetyRefusal { return reason }
    guard let machine = machineSnapshot?.machine else {
      return MotionRefusal.notConnected.actionableDescription
    }
    if machine.penState != .up {
      return MotionRefusal.penNotUp(machine.penState).actionableDescription
    }
    return nil
  }

  private var learningCarriageMotionUnavailableReason: String? {
    if let reason = retainedPoseApplicabilityRefusal { return reason }
    return controllerCarriageTravelUnavailableReason
  }

  private var retainedCarriageSafetyRefusal: String? {
    if jogRequestInProgress { return "A relative jog is already in progress." }
    if frameModeSwitchInProgress { return "Wait for the frame source switch to finish." }
    if frameMode == .simulated {
      return "SIMULATED source cannot issue physical machine commands. Switch to LIVE first."
    }
    if machineSession == nil { return "Native machine composition is unavailable." }
    if selectedSerialDevice == nil { return "Select and connect one serial device." }
    guard let snapshot = machineSnapshot else {
      return MotionRefusal.notConnected.actionableDescription
    }
    let machine = snapshot.machine
    if let ambiguity = machine.stickyAmbiguity {
      return MotionRefusal.stickyAmbiguity(ambiguity).actionableDescription
    }
    if machine.operationInFlight || snapshot.currentOperation != .idle {
      return MotionRefusal.operationInFlight.actionableDescription
    }
    if machine.connection != .connected {
      return MotionRefusal.notConnected.actionableDescription
    }
    guard let controllerState = machine.controllerState, controllerState.isRecognized else {
      return MotionRefusal.controllerStateUnknown.actionableDescription
    }
    if controllerState.isAlarm {
      return MotionRefusal.controllerAlarm("controller is in Alarm").actionableDescription
    }
    if controllerState != .idle {
      return MotionRefusal.controllerNotIdle(controllerState).actionableDescription
    }
    if machine.pins.hasRelevantLimitAsserted {
      return MotionRefusal.relevantLimitAsserted(machine.pins.rawValue).actionableDescription
    }
    if machine.position == nil {
      return MotionRefusal.machinePositionUnknown.actionableDescription
    }
    if machine.motionGuardState != .active {
      return MotionRefusal.motionGuardInactive.actionableDescription
    }
    return nil
  }

  private func requireVisualPositionRevalidation(checkpoint: AcceptedTipCalibrationCheckpoint? = nil) {
    guard frameMode == .live, activeMachineArtifactCheckpoint != nil else { return }
    if case .requiresVisualRevalidation = controllerPoseApplicability { return }
    recoverableTipCalibrationCheckpoint = checkpoint ?? acceptedLearningPathCheckpoint?.tipCalibration
    tipCalibrationRuntime.installPositionRecoveryAvailability(machineCameraRegistration != nil)
    controllerPoseApplicability = .requiresVisualRevalidation(reportedPositionDeltaMM: 0)
    markSemanticPresentationChanged()
  }

  var positionRevalidationUnavailableReason: String? {
    if case .setPen(let request) = manualMotionEpisodeSnapshot?.activeOperation?.intent,
      request.position == .raised {
      return "Raising the pen. Wait for it to finish, then use the camera to find its position."
    }
    if positionRebasePublicationIsPending || tipCalibrationRuntime.activeOperationID != nil {
      return "Position verification is in progress."
    }
    if drawingRunIsActive { return "Stop or finish the current drawing before re-establishing position." }
    if frameMode == .simulated { return nil }
    if !cameraIsLive { return "Show the current Plotter Video camera." }
    // This is capture-only recovery. It may inspect a position whose physical
    // alignment is unknown, but must never start travel or normalize the pen.
    guard let snapshot = machineSnapshot, snapshot.machine.connection == .connected else {
      return "Connect the controller before re-establishing position."
    }
    guard snapshot.currentOperation == .idle, snapshot.machine.controllerState == .idle,
      snapshot.machine.stickyAmbiguity == nil, !snapshot.machine.operationInFlight,
      snapshot.machine.position != nil else {
      return "Wait for an unambiguous Idle controller position before re-establishing position."
    }
    return snapshot.machine.penState == .up ? nil
      : "Raise the pen first, then use the camera to find its position. Enable Motion raises it automatically."
  }

  private var retainedPoseApplicabilityRefusal: String? {
    guard frameMode == .live else { return nil }
    if case .requiresVisualRevalidation = controllerPoseApplicability {
      if machineCameraRegistration == nil {
        return "Saved Boundary coordinates have no retained camera/cap map for position recovery. Redo Boundary Positioning, then Camera Calibration; accepted Pen Learning remains available."
      }
      return
        "Physical position is unverified after controller continuity was lost. Raise Pen here if needed, then Re-establish Position from Camera before drawing. Accepted Learning is retained."
    }
    return nil
  }

  func learningPenCommandUnavailableReason(for command: PenCommand) -> String? {
    if retainedPenRequestInProgress { return "A retained pen command is already in progress." }
    if frameModeSwitchInProgress { return "Wait for the frame source switch to finish." }
    if frameMode == .simulated {
      if !sessionEstablished { return "Connect the learning simulator first." }
      if !sessionMotionAuthorized { return "Enable simulated Motion first." }
      if simulatedLearningSnapshot?.currentOperation != nil {
        return "Stop or finish the current simulated operation first."
      }
      return nil
    }
    if machineSession == nil { return "Native machine composition is unavailable." }
    if selectedSerialDevice == nil { return "Select and connect one serial device." }
    guard let snapshot = machineSnapshot else {
      return PenRefusal.notConnected.actionableDescription
    }
    let machine = snapshot.machine
    if let ambiguity = machine.stickyAmbiguity {
      return PenRefusal.stickyAmbiguity(ambiguity).actionableDescription
    }
    if machine.operationInFlight || snapshot.currentOperation != .idle {
      return PenRefusal.operationInFlight.actionableDescription
    }
    if machine.connection != .connected {
      return PenRefusal.notConnected.actionableDescription
    }
    if machine.motionGuardState != .active {
      return PenRefusal.motionGuardInactive.actionableDescription
    }
    guard let controllerState = machine.controllerState, controllerState.isRecognized else {
      return PenRefusal.controllerStateUnknown.actionableDescription
    }
    if controllerState.isAlarm {
      return PenRefusal.controllerAlarm("controller is in Alarm").actionableDescription
    }
    if controllerState != .idle {
      return PenRefusal.controllerNotIdle(controllerState).actionableDescription
    }
    guard command == .lower else { return nil }
    if machine.pins.hasRelevantLimitAsserted {
      return PenRefusal.relevantLimitAsserted(machine.pins.rawValue).actionableDescription
    }
    guard machine.position != nil else {
      return PenRefusal.machinePositionUnknown.actionableDescription
    }
    return nil
  }

  private var sceneAnalysisIsRequested: Bool {
    !overlayPreferenceState.enabled.isEmpty
  }

  private var requestedSceneFeatures: SceneFeatureSet {
    SceneFeatureSet(preference: overlayPreferenceState)
  }

  private var automaticVisionAnalysisShouldRun: Bool {
    guard workbenchCameraRole == .plotter, !cameraRoleIsTransitioning,
      frameMode == .live, livePenCapAppearanceSelection != nil, sceneAnalysisIsRequested,
      case .running = cameraSnapshot?.state
    else { return false }
    return true
  }

  private func reconcileAutomaticVisionAnalysis() async {
    guard applicationAdmissionIsOpen, let observationRuntime else { return }
    if automaticVisionAnalysisShouldRun {
      _ = await submitObservationIntent(.configureAutomaticAnalysis(
        cadence: visionAnalysisCadence,
        features: requestedSceneFeatures,
        region: videoAnalysisRegionLock?.region,
        penCapColor: livePenCapColor
      ))
      let snapshot = await observationRuntime.snapshot()
      guard applicationAdmissionIsOpen, frameMode == .live else { return }
      cameraSnapshot = snapshot
      return
    }

    _ = await submitObservationIntent(.configureAutomaticAnalysis(
      cadence: nil,
      features: [],
      region: nil,
      penCapColor: livePenCapColor
    ))
    let cameraSnapshot = await observationRuntime.snapshot()
    self.cameraSnapshot = cameraSnapshot
    if let latest = cameraSnapshot.latestFrame { displayedFrame = latest }
  }

  func refreshSerialDevices() async {
    _ = await submitControllerSessionRequest(
      controllerSessionProjection.request(.refreshSerialDevices)
    )
  }

  func performApplicationStartup(_ policy: AdaptivePlotterLaunchPolicy) async {
    guard applicationAdmissionIsOpen, startupState == .notStarted else { return }
    startupState = .starting
    await loadDrawingEvidenceArchive()
    guard applicationAdmissionIsOpen, !Task.isCancelled else {
      startupState = .cancelled
      return
    }
    await refreshSerialDevices()
    guard applicationAdmissionIsOpen, !Task.isCancelled else {
      startupState = .cancelled
      return
    }
    switch policy.startupRoute {
    case .preferredCamera:
      await startPreferredCameraAtStartup()
    case .simulated:
      await submitObservationConfiguration(
        observationConfigurationProjection.request(.selectSource(.simulated, cameraID: nil))
      )
    }
    guard applicationAdmissionIsOpen, !Task.isCancelled else {
      startupState = .cancelled
      return
    }
    await synchronizeDrawingDraft()
    await synchronizeDrawingRunProjection()
    guard applicationAdmissionIsOpen, !Task.isCancelled else {
      startupState = .cancelled
      return
    }
    startupState = .started
  }

  private func loadDrawingEvidenceArchive() async {
    let loadResult = await drawingEvidencePort.load()
    let restored = await drawingRunRuntime.restoreNoRedrawTruth(
      from: loadResult,
      paper: currentPaperRevisionContext,
      environment: .live
    )
    installDrawingRunSnapshot(restored.snapshot)
    switch restored.disposition {
    case .available(let archive):
      drawingEvidenceArchive = archive
      drawingEvidenceError = nil
      restoreInteractiveLearningCompletionFromEvidence()
      restoreAxisMetricProposal()
    case .rejected(let detail):
      drawingEvidenceError =
        "Saved drawing evidence was rejected; Drawing Run remains unavailable: \(detail)"
    }
  }

  private func restoreInteractiveLearningCompletionFromEvidence() {
    guard frameMode == .live, let assessment = retainedLearningCompletion else { return }
    let result = borderValidationRuntime.apply(.restoreAcceptedAssessment(assessment))
    if case .refused(let reason, let remedy) = result.disposition {
      drawingEvidenceError = "\(reason) Remedy: \(remedy)"
    }
  }

  private func persistCompletedPictureFrameEvidence() async {
    guard frameMode == .live, let attemptID = activeExerciseAttemptID,
      let registration = tipCameraRegistration else { return }
    do {
      guard let record = try DrawingBorderEvidence.record(
        snapshot: borderValidationSnapshot, attemptID: attemptID,
        registration: registration, paper: currentPaperRevisionContext,
        nowNanoseconds: nowNanoseconds()
      ) else { return }
      drawingEvidenceArchive = try await drawingEvidencePort.append(record)
      let stageFourCheckpoint = AcceptedStageFourCheckpoint(
        recordID: record.recordID,
        tipCalibrationRevisionID: registration.acceptedRevisionID,
        paperContactPlane: currentPaperRevisionContext.contactPlane
      )
      activeStageFourCheckpoint = stageFourCheckpoint
      persistAcceptedLearningPathCheckpoint(stageFour: stageFourCheckpoint)
      drawingEvidenceError = nil
    } catch {
      drawingEvidenceError = "Completed Drawing Border could not be retained: \(error)"
    }
  }

  func submitControllerSessionRequest(
    _ request: PlotterControllerSessionRequest
  ) async -> PlotterControllerSessionDisposition {
    guard applicationAdmissionIsOpen else { return .cancelled }
    guard !axisCalibrationInProgress else { return .refused("Wait for axis calibration to settle.") }
    let facts = controllerSessionFacts
    let resetPlan = learningVacatePlan(from: .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering))
    let resetFacts = artifactResetAdmissionFacts
    let enablesMotion = request.intent == .toggleMotionAuthorization
      && !PlotterControllerSessionRules.project(facts).motionAuthorized
    guard request.reference == facts.reference else {
      return .refused("The controller-session projection changed; use the current action.")
    }
    switch request.intent {
    case .applyAxisCalibration:
      guard axisMetricApplyUnavailableReason == nil else {
        return .refused(axisMetricApplyUnavailableReason ?? "Axis calibration is unavailable.")
      }
      axisCalibrationInProgress = true
    case .refreshSerialDevices, .selectSerialDevice:
      break
    case .toggleConnection:
      controllerConnectionActionInProgress = true
    case .requestPassiveProbe:
      passiveProbeInProgress = true
    case .clearAlarm:
      controllerAlarmClearInProgress = true
    case .toggleMotionAuthorization:
      motionAuthorizationActionInProgress = true
    }
    defer {
      axisCalibrationInProgress = false
      controllerConnectionActionInProgress = false
      passiveProbeInProgress = false
      controllerAlarmClearInProgress = false
      motionAuthorizationActionInProgress = false
    }
    let callbacks = PlotterAxisCalibrationCallbacks(
      prepare: { [self] proposal in
        guard let resetPlan else { throw AxisMetricLearningTransitionError.staleProposal }
        try await self.prepareAxisCalibration(proposal, resetPlan: resetPlan, admission: resetFacts)
      },
      retainTerminal: { [self] proposal, outcome in
        try await self.retainAxisCalibrationTerminal(proposal, outcome: outcome)
      })
    let disposition = await controllerSessionRuntime.submit(request, facts: facts,
      axisCalibrationCallbacks: callbacks)
    guard applicationAdmissionIsOpen else { return .cancelled }
    guard case .completed(let result) = disposition else {
      if case .refused(let reason) = disposition { machineError = reason }
      return disposition
    }
    if enablesMotion {
      // A completed authorization remains controller truth after caller
      // cancellation. Publish it for this owner before suppressing Pen Up.
      guard applicationAdmissionIsOpen,
        frameMode == facts.environment, controllerSessionID == facts.reference.capabilityID
      else { return .cancelled }
    }
    await applyControllerSessionResult(result)
    guard enablesMotion else { return disposition }
    // Authorization and pen preparation have separate retained owners. Only
    // this explicit enable request may hand off to the existing Manual owner;
    // passive connection/probe results never acquire a pen side effect.
    guard !Task.isCancelled, applicationAdmissionIsOpen,
      frameMode == facts.environment, controllerSessionID == facts.reference.capabilityID
    else { return .cancelled }
    let enableFailure: String? = switch result {
    case .liveSession(_, _, let error): error
    case .simulated(_, _, let refusal): refusal
    default: "Motion authorization did not complete."
    }
    if let enableFailure { return .refused(enableFailure) }
    guard controllerSessionProjection.motionAuthorized else {
      return .refused("Motion authorization did not become active; the pen was not raised.")
    }
    guard manualControllerPenState != .raised else { return disposition }
    guard let settled = await submitManualMotionIntent(manualPenIntent(.raise)) else {
      if Task.isCancelled || !applicationAdmissionIsOpen { return .cancelled }
      return .refused(machineError ?? "Motion is enabled, but the pen did not settle. Use Raise Pen beside Re-establish Position from Camera.")
    }
    guard settled.projection.lastTerminalEffect?.result.disposition == .completed,
      settled.terminalPublicationIssue == nil,
      settled.evidenceDispositionAction == nil,
      manualControllerPenState == .raised
    else {
      let reason = settled.projection.remedy ?? machineError
        ?? "The pen did not settle. Use Raise Pen beside Re-establish Position from Camera."
      machineError = reason
      return .refused(reason)
    }
    switch facts.environment {
    case .live:
      return .completed(.liveSession(snapshot: machineSnapshot, probe: passiveProbeResult, error: nil))
    case .simulated:
      guard let snapshot = simulatedLearningSnapshot else { return .cancelled }
      return .completed(.simulated(snapshot, action: "Enable simulated motion and raise pen", refusal: nil))
    }
  }

  private func applyControllerSessionResult(
    _ result: PlotterControllerSessionEffectResult
  ) async {
    switch result {
    case .axisCalibrated(_, let outcome, let snapshot, let persistenceError):
      machineSnapshot = snapshot
      if let probe = outcome.verificationProbe ?? outcome.baselineProbe { passiveProbeResult = probe }
      axisMetricStatus = outcome.reason + (persistenceError.map { " Terminal persistence failed: " + $0 } ?? "")
      machineError = outcome.status == .applied ? nil : outcome.reason
      if outcome.status == .applied { axisCalibrationProposal = nil }
      await synchronizeDrawingDraft()
      await synchronizeDrawingRunProjection()
    case .discovered(let devices, let retiredLowerSession):
      serialDevices = devices
      if retiredLowerSession { await clearMachineAuthority(clearSelection: true) }
    case .selected(let descriptor, let retiredLowerSession):
      if retiredLowerSession { await clearMachineAuthority(clearSelection: false) }
      selectedSerialDevice = descriptor
      machineError = nil
    case .liveSession(let snapshot, let probe, let error):
      machineSnapshot = snapshot
      passiveProbeResult = probe
      machineError = error
      lastMotionGuardActivationText = snapshot?.machine.motionGuardState == .active
        ? "activated for this controller session" : "not activated"
      if let probe {
        await revalidateParkedAcceptedArtifactCheckpoint(
          with: probe,
          currentPosition: snapshot?.machine.position
        )
      }
    case .liveDisconnected:
      await clearMachineAuthority(clearSelection: false)
    case .simulated(let snapshot, let action, let refusal):
      simulatedLearningSnapshot = snapshot
      simulatorPenState = simulatorPenState(from: snapshot.penPose)
      simulatorLearningSummary = refusal.map {
        "\(action) refused: \($0). Simulation is nonphysical evidence."
      } ?? "\(action) completed. Simulation is nonphysical evidence."
    }
  }

  /// Test support still uses the production typed selection/connection seam;
  /// it cannot directly invoke the lower machine session.
  func establishMachineSession(_ descriptor: MachineLinkDescriptor) async {
    _ = await submitControllerSessionRequest(
      controllerSessionProjection.request(.selectSerialDevice(.init(
        identifier: descriptor.identifier,
        displayName: descriptor.displayName,
        bsdPath: descriptor.bsdPath,
        transport: descriptor.transport.rawValue
      )))
    )
    _ = await submitControllerSessionRequest(
      controllerSessionProjection.request(.toggleConnection)
    )
  }

  @discardableResult
  func executeLearningPenCommand(_ command: PenCommand) async -> PenOutcome? {
    await executeLearningPenCommand(command, profile: currentPenActuationProfile)
  }

  /// Every travel owner normalizes Pen Up from the existing actuation-profile
  /// authority. Command knowledge is deliberately ignored: a redundant raise
  /// is cheap, idempotent, and safer than treating a prior process state as
  /// physical proof.
  private func ensurePenUpForTravel() async -> Bool {
    let outcome = await executeLearningPenCommand(
      .raise,
      profile: currentPenActuationProfile
    )
    guard let outcome,
      case .commandedAndSettled(command: .raise, commandedState: .up) = outcome
    else {
      machineError = "Pen Up normalization did not settle; travel did not start."
      return false
    }
    return true
  }

  @discardableResult
  private func executeLearningPenCommand(
    _ command: PenCommand,
    profile: PenActuationProfile
  ) async -> PenOutcome? {
    if frameMode == .simulated {
      guard learningPenCommandUnavailableReason(for: command) == nil else {
        return nil
      }
      withBatchedSemanticPresentationUpdate {
        retainedPenRequestInProgress = true
        computationDiagnostics.record(.penRequest(command, .began))
      }
      let pose: SimulatedLearningPenPose = command.commandedState == .up ? .up : .down
      let simulatedOutcome = await causalSimulatorEffectAdapter.executeRetainedWorkflowPen(
        pose,
        owner: EpisodeAuthorityID(rawValue: "PlotterApplicationRuntime.retainedPenNormalization")
      )
      let outcome: PenOutcome? = if let refusal = simulatedOutcome.refusal {
        .refused(.controllerRejected("causal simulator refusal: \(refusal)"))
      } else {
        .commandedAndSettled(
          command: command,
          commandedState: command.commandedState
        )
      }
      withBatchedSemanticPresentationUpdate {
        applySimulatedCausalImmediateOutcome(
          simulatedOutcome,
          action: "Set simulated pen \(pose.rawValue)"
        )
        retainedPenRequestInProgress = false
        computationDiagnostics.record(.penRequest(command, .ended))
      }
      return outcome
    }
    guard let generation = beginApplicationEffect() else {
      return nil
    }
    var hardwareIntentRequiresEnd = true
    defer {
      if hardwareIntentRequiresEnd { settleApplicationEffect(generation) }
    }
    guard learningPenCommandUnavailableReason(for: command) == nil, let machineSession else {
      return nil
    }
    withBatchedSemanticPresentationUpdate {
      retainedPenRequestInProgress = true
      machineError = nil
      computationDiagnostics.record(.penRequest(command, .began))
    }
    let outcome = await PlotterManualMotionComposition.settleNativePenCommand(
      using: machineSession,
      command: command,
      profile: profile
    )
    let snapshot = await machineSession.snapshot()
    guard applicationEffectCanCommit(generation) else {
      withBatchedSemanticPresentationUpdate {
        retainedPenRequestInProgress = false
        computationDiagnostics.record(.penRequest(command, .ended))
        settleApplicationEffect(generation)
        hardwareIntentRequiresEnd = false
      }
      return nil
    }
    withBatchedSemanticPresentationUpdate {
      machineSnapshot = snapshot
      retainedPenRequestInProgress = false
      computationDiagnostics.record(.penRequest(command, .ended))
      settleApplicationEffect(generation)
      hardwareIntentRequiresEnd = false
    }
    return outcome
  }

  private func stagedPenSettlementTransaction(
    sequenceID: DiscoverySequenceID?,
    command: PenCommand,
    controllerSummary: String?,
    outcome: PenOutcome?
  ) -> (transaction: DiscoveryTransaction?, failure: String?) {
    guard let sequenceID,
      let controllerSummary,
      let outcome,
      case .commandedAndSettled = outcome
    else { return (nil, nil) }
    guard var transaction = discoveryTransactions[sequenceID] else {
      return (nil, "The active discovery transaction is unavailable after Pen settlement.")
    }
    do {
      try transaction.recordPenCommandSettledAndPresentFollowingQuestion(
        command,
        controllerSummary: controllerSummary
      )
      return (transaction, nil)
    } catch {
      return (nil, "The settled Pen command could not publish its next question: \(error)")
    }
  }

  private func penOutcomeText(_ outcome: PenOutcome) -> String {
    switch outcome {
    case .refused(let reason):
      "refused: \(reason.actionableDescription)"
    case .commandedAndSettled(let command, let commandedState):
      "\(command.rawValue) acknowledged; commanded \(commandedState.rawValue)"
    case .ambiguous(let ambiguity):
      "ambiguous: \(ambiguity.actionableDescription)"
    }
  }

  func startDiscoverySequence(_ sequenceID: DiscoverySequenceID) async {
    guard applicationAdmissionIsOpen, !Task.isCancelled else { return }
    guard discoveryStartUnavailableReason(for: sequenceID) == nil else { return }
    if sequenceID == .penInteraction {
      let exactPointSelection = pointSelectionEpisodeProjection.exactPointSelection
      let isCollectingPenCapSelection =
        exactPointSelection.request?.purpose == .penCapAppearance
        && exactPointSelection.phase == .collecting
      guard penCapAppearanceSelection != nil,
        !isCollectingPenCapSelection
      else {
        let reason =
          "Identify Pen Cap must be completed before pen-position calibration begins."
        discoveryError = reason
        if activeExerciseAttemptOwnerID == .humanGuidedDiscovery(.penInteraction) {
          _ = await submitPenInteraction(.finish(.refused(reason)))
          finishActiveExerciseAttempt(disposition: .refused(reason))
          restartableExerciseItemID = nil
        }
        return
      }
    }
    if sequenceID == .penInteraction {
      // Pen Interaction admission already created the exact retained attempt.
      // A completed point-selection continuation may race exact runtime Stop;
      // it must never revive that cancelled attempt through the legacy
      // discovery fallback below.
      guard activeExerciseAttemptOwnerID == .humanGuidedDiscovery(.penInteraction)
      else { return }
    } else if activeExerciseAttemptOwnerID == nil {
      beginExerciseAttempt(
        ownerID: learningPathItemID(for: sequenceID),
        mode: .normal
      )
    }
    selectedDiscoverySequenceID = sequenceID
    discoveryError = nil
    if sequenceID == .penInteraction {
      guard case .applied = await submitPenInteraction(.capSelectionAccepted) else {
        finishActiveExerciseAttempt(disposition: .refused(discoveryError ?? "Pen cap selection refused."))
        return
      }
      guard applicationAdmissionIsOpen, !Task.isCancelled else { return }
    }
    var transaction = DiscoveryTransaction(sequenceID: sequenceID)
    do {
      try transaction.begin()
      discoveryTransactions[sequenceID] = transaction
      await advanceDiscoverySequence(sequenceID)
    } catch {
      discoveryError = "Plotter Calibration could not start: \(error)"
      if sequenceID == .penInteraction {
        _ = await submitPenInteraction(.finish(.failed(String(describing: error))))
      }
      finishActiveExerciseAttempt(disposition: .failed(String(describing: error)))
      restartableExerciseItemID = learningPathItemID(for: sequenceID)
    }
  }

  private func advanceDiscoverySequence(_ sequenceID: DiscoverySequenceID) async {
    while applicationAdmissionIsOpen, activeDiscoverySequenceID == sequenceID,
      let step = discoveryTransactions[sequenceID]?.currentStep
    {
      switch step.action {
      case .askQuestion:
        guard recordDiscovery(.questionPresented, for: sequenceID) else { return }

      case .awaitOperatorChoice:
        return

      case .awaitPhysicalPenConfirmation:
        return

      case .announce(let message):
        if step.expectedEvent == .announcementDispatched {
          _ = await dispatchSpeechEffect(message)
        } else {
          _ = await performSpeechEffect(message)
        }
        guard activeDiscoverySequenceID == sequenceID,
          discoveryTransactions[sequenceID]?.currentStep?.id == step.id
        else { return }
        let event: DiscoveryEvent = step.expectedEvent == .announcementDispatched
          ? .announcementDispatched : .announcementCompleted
        guard recordDiscovery(event, for: sequenceID) else { return }

      case .startBoundaryJog:
        // Retained checkpoint decoding may still contain this legacy step,
        // but only PlotterBoundaryRuntime may admit Boundary motion.
        return

      case .awaitContextualStop:
        return

      case .cancelBoundaryJogAndAwaitIdle:
        // `stopCurrentOperation()` owns the one cancel byte and then awaits the
        // original boundary-motion task. The motion owner records final MPos.
        return

      case .actuatePen(let command):
        let episodeCommand: PlotterPenInteractionCommand = command == .raise ? .raise : .lower
        guard case .applied = await submitPenInteraction(.actuate(episodeCommand)) else {
          await failDiscovery(
            sequenceID,
            failure: .refused(discoveryError ?? "Pen Interaction actuation was refused.")
          )
          return
        }
        guard let outcome = currentPenInteractionSnapshot?.lastSettlement?.outcome,
          case .commandedAndSettled = outcome
        else {
          let detail = currentPenInteractionSnapshot?.lastSettlement.map {
            penOutcomeText($0.outcome)
          } ?? lastPenOutcomeText
          let failure: WorkflowFailure =
            if case .ambiguous? = currentPenInteractionSnapshot?.lastSettlement?.outcome {
              .ambiguous(detail)
            } else {
              .refused(detail)
            }
          await failDiscovery(sequenceID, failure: failure)
          return
        }
        let staged = stagedPenSettlementTransaction(
          sequenceID: sequenceID,
          command: command,
          controllerSummary: penOutcomeText(outcome),
          outcome: outcome
        )
        guard let transaction = staged.transaction else {
          await failDiscovery(
            sequenceID,
            failure: .failed(staged.failure ?? "Pen settlement publication failed.")
          )
          return
        }
        discoveryTransactions[sequenceID] = transaction
      case .commitBoundaryObservation:
        return
      }
    }
  }

  private func recordDiscovery(_ event: DiscoveryEvent, for sequenceID: DiscoverySequenceID) -> Bool
  {
    guard var transaction = discoveryTransactions[sequenceID] else { return false }
    do {
      try transaction.record(event)
      discoveryTransactions[sequenceID] = transaction
      if transaction.state == .succeeded {
        commitSuccessfulDiscoveryAttempt(sequenceID)
      }
      return true
    } catch {
      transaction.fail("Unexpected discovery event: \(error)")
      discoveryTransactions[sequenceID] = transaction
      discoveryError = "Unexpected Plotter Calibration event: \(error)"
      return false
    }
  }

  private func failDiscovery(_ sequenceID: DiscoverySequenceID, failure: WorkflowFailure) async {
    let reason = failure.detail
    if var transaction = discoveryTransactions[sequenceID] {
      transaction.fail(reason)
      discoveryTransactions[sequenceID] = transaction
    }
    discoveryError = reason
    let disposition = failure.attemptDisposition
    if sequenceID == .penInteraction,
      currentPenInteractionSnapshot?.projection.reference.operationID != nil
    {
      _ = await submitPenInteraction(.finish(penInteractionTerminalDisposition(disposition)))
    }
    finishActiveExerciseAttempt(disposition: disposition)
    if machineSnapshot?.machine.stickyAmbiguity == nil {
      restartableExerciseItemID = learningPathItemID(for: sequenceID)
    } else {
      restartableExerciseItemID = nil
    }
    retainedStopRegistration = nil
  }

  func stopCurrentOperation(capabilityID: ContextualStopCapabilityID) async {
    guard !jogCancelRequestInProgress,
      let operation = retainedStopRegistration,
      operation.target.capabilityID == capabilityID,
      latchContextualStopDisposition(
        for: operation.target,
        intent: .operatorStop,
        actor: "Operator",
        action: "Stop"
      )
    else { return }
    let target = operation.target
    switch target {
    case .exerciseMotion(_, _, let ownerID, _):
      await requestSingleJogCancel(for: target, intent: .operatorStop)
      await operation.owner.settle()
      if ownerID != .humanGuidedDiscovery(.calibrateCameraAndVisibleCap) {
        finishActiveExerciseAttempt(disposition: .cancelled)
        restartableExerciseItemID = ownerID
      }

    case .borderValidation:
      let inkMayExist = operation.owner.drawingMayHaveInk
      await requestSingleJogCancel(for: target, intent: .operatorStop)
      await operation.owner.settle()
      finishActiveExerciseAttempt(disposition: .cancelled)
      if inkMayExist {
        explorationError =
          "Drawing stopped after stroke admission; physical ink may exist. Draw is unavailable. Continue with return/observation."
        restartableExerciseItemID = nil
      } else {
        restartableExerciseItemID = .borderValidation(.chooseDrawingBorderPlan)
      }

    case .positionRecovery:
      await tipCalibrationRuntime.stop()
      await operation.owner.settle()
      finishActiveExerciseAttempt(disposition: .cancelled)

    case .sparseTipBatch:
      if let location = operation.possibleInkLocation {
        blacklistedToolContactLocations.insert(location)
      }
      await cancelAndSettleStoppableOperation(operation, intent: .operatorStop)
      if tipCalibrationRuntime.blacklistedPositions.isEmpty {
        if activeExerciseAttemptOwnerID
          == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
        {
          finishActiveExerciseAttempt(disposition: .cancelled)
        }
        restartableExerciseItemID = .humanGuidedDiscovery(
          .calibratePenContactFromSparseMarks
        )
      } else {
        explorationError =
          "The four-circle calibration stopped after possible ink. Every affected paper location is excluded from automatic redraw."
        restartableExerciseItemID = nil
      }

    case .sparseTipBatchSegment(_, _, let location):
      blacklistedToolContactLocations.insert(location)
      await requestSingleJogCancel(for: target, intent: .operatorStop)
      await operation.owner.settle()
      restartableExerciseItemID = nil
    }
  }

  private func requestSingleJogCancel(
    for target: ContextualStopTarget,
    intent: JogCancelIntent
  ) async {
    guard let operationOwner = target.operationOwner else { return }
    if case .simulated(let operation) = operationOwner {
      guard beginCancellationRequest(for: target, intent: intent) else { return }
      defer { finishCancellationRequest(for: target) }
      let simulatedIntent: SimulatedLearningOperationIntent =
        switch intent {
        case .operatorStop: .stop
        case .cancelAttempt: .cancel
        case .shutdown: .shutdown
        }
      let outcome = await causalSimulatorEffectAdapter.request(
        simulatedIntent,
        for: operation
      )
      simulatedLearningSnapshot = outcome.truth.runtime
      updateContextualStopAudit(
        for: target,
        outcome:
          "\(outcome.disposition.rawValue); final simulated MPos X \(outcome.finalMPos.xMM) Y \(outcome.finalMPos.yMM); \(outcome.evidenceNotice.label)"
      )
      return
    }
    guard let machineSession else { return }
    let generation: PlotterApplicationEffectLease?
    if intent == .shutdown {
      // Shutdown has already closed new hardware admission. This cancel is the
      // settlement of the exact owner admitted before that boundary, so it
      // must not attempt to reopen ordinary command admission.
      generation = nil
    } else {
      guard let admittedGeneration = beginApplicationEffect() else { return }
      generation = admittedGeneration
    }
    defer {
      if let generation { settleApplicationEffect(generation) }
    }
    guard beginCancellationRequest(for: target, intent: intent) else { return }
    defer { finishCancellationRequest(for: target) }
    let outcome = await machineSession.requestJogCancel(intent)
    updateContextualStopAudit(for: target, outcome: String(describing: outcome))
    let snapshot = await machineSession.snapshot()
    if let generation {
      guard applicationEffectCanCommit(generation) else { return }
      machineSnapshot = snapshot
    }
  }

  private func latchContextualStopDisposition(
    for target: ContextualStopTarget,
    intent: JogCancelIntent,
    actor: String,
    action: String
  ) -> Bool {
    guard var operation = retainedStopRegistration,
      operation.target.capabilityID == target.capabilityID,
      case .available = operation.state
    else { return false }
    let latch = ContextualStopDispositionLatch(
      capabilityID: target.capabilityID,
      intent: intent,
      actor: actor
    )
    operation.state = .latched(latch, cancellationRequestInProgress: false)
    if case .sparseTipBatch = operation.target {
      sparseTipPenUpAuthorization = nil
    }
    retainedStopRegistration = operation
    lastContextualStopAuditRecord = ContextualStopAuditRecord(
      capabilityID: target.capabilityID,
      actor: actor,
      action: action,
      disposition: intent,
      outcome: "requested; waiting for active motion"
    )
    return true
  }

  private func installStoppableOperation(
    target: ContextualStopTarget,
    owner: PlotterRetainedStopHandle
  ) {
    if var operation = retainedStopRegistration,
      case .sparseTipBatch = operation.target,
      operation.target.capabilityID == target.capabilityID
    {
      precondition(operation.segment == nil, "Only one sparse-tip batch segment may be active.")
      operation.segment = PlotterRetainedStopSegment(target: target, owner: owner)
      retainedStopRegistration = operation
      return
    }
    precondition(retainedStopRegistration == nil, "Only one contextual Stop owner may exist.")
    retainedStopRegistration = PlotterRetainedStopRegistration(target: target, owner: owner)
  }

  private func clearStoppableOperation(matching target: ContextualStopTarget) {
    guard var operation = retainedStopRegistration else { return }
    if operation.target == target {
      retainedStopRegistration = nil
      return
    }
    guard operation.segment?.target == target else { return }
    operation.segment = nil
    retainedStopRegistration = operation
  }

  private func sparseTipBatchCapabilityID() throws -> ContextualStopCapabilityID {
    guard let target = activeStopTarget,
      case .sparseTipBatch(let capabilityID, _) = target
    else {
      throw LearningPathOperationError.requiredState(
        "The four-corner calibration batch no longer owns its Stop capability."
      )
    }
    return capabilityID
  }

  private func supervisedTravelStopCapabilityID(
    ownerID: LearningPathItemID
  ) throws -> ContextualStopCapabilityID {
    if ownerID == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks) {
      return try sparseTipBatchCapabilityID()
    }
    return ContextualStopCapabilityID()
  }

  private func requireSparseTipBatchContinuation() throws {
    guard !Task.isCancelled,
      let operation = retainedStopRegistration,
      case .sparseTipBatch = operation.target,
      operation.state.latch == nil
    else {
      throw LearningPathOperationError.controllerCancelled(
        "The four-circle calibration was stopped; no later segment started."
      )
    }
  }

  private var sparseTipPenUpAuthorizationIsCurrent: Bool {
    guard let authorization = sparseTipPenUpAuthorization,
      authorization.source == frameMode,
      authorization.controllerSessionID == controllerSessionID,
      authorization.coordinateRevision == explorationCoordinateRevision,
      authorization.paperInstanceRevision == explorationPaperInstanceRevision,
      activeExerciseAttemptID == authorization.attemptID,
      let operation = retainedStopRegistration,
      case .sparseTipBatch(let capabilityID, let attemptID) = operation.target,
      attemptID == authorization.attemptID,
      capabilityID == authorization.capabilityID,
      operation.state.latch == nil,
      !Task.isCancelled,
      applicationAdmissionIsOpen
    else { return false }
    return true
  }

  private func authorizeSparseTipPenUp() throws {
    guard let attemptID = activeExerciseAttemptID,
      let operation = retainedStopRegistration,
      case .sparseTipBatch(let capabilityID, let ownedAttemptID) = operation.target,
      attemptID == ownedAttemptID,
      operation.state.latch == nil
    else {
      throw LearningPathOperationError.requiredState(
        "The sparse-tip batch cannot own a Pen-Up authorization."
      )
    }
    sparseTipPenUpAuthorization = SparseTipPenUpAuthorization(
      attemptID: attemptID,
      capabilityID: capabilityID,
      controllerSessionID: controllerSessionID,
      coordinateRevision: explorationCoordinateRevision,
      paperInstanceRevision: explorationPaperInstanceRevision,
      source: frameMode
    )
  }

  private func normalizeSparseTipBatchPenUp() async throws -> PenActuationEvidence {
    sparseTipPenUpAuthorization = nil
    let outcome: PenOutcome
    if frameMode == .simulated {
      let simulatedOutcome = await causalSimulatorEffectAdapter.executeRetainedWorkflowPen(
        .up,
        owner: EpisodeAuthorityID(rawValue: "PlotterApplicationRuntime.sparseTipCalibration")
      )
      applySimulatedCausalImmediateOutcome(
        simulatedOutcome,
        action: "Normalize simulated Pen Up for sparse-tip calibration"
      )
      if let refusal = simulatedOutcome.refusal { throw refusal }
      outcome = .commandedAndSettled(command: .raise, commandedState: .up)
    } else {
      guard let machineSession else {
        throw LearningPathOperationError.requiredState("Machine composition is unavailable.")
      }
      outcome = await PlotterManualMotionComposition.settleNativePenCommand(
        using: machineSession,
        command: .raise,
        profile: currentPenActuationProfile
      )
      guard case .commandedAndSettled(command: .raise, commandedState: .up) = outcome else {
        machineSnapshot = await machineSession.snapshot()
        throw operationError(for: outcome, possibleInk: false)
      }
    }
    try requireSparseTipBatchContinuation()
    try authorizeSparseTipPenUp()
    return PenActuationEvidence(
      outcome: outcome,
      profile: currentPenActuationProfile,
      timestamp: RuntimeTimestamp(monotonicNanoseconds: nowNanoseconds())
    )
  }

  private func cancelSparseTipSegmentIfRequested(
    target: ContextualStopTarget,
    owner: PlotterRetainedStopHandle
  ) async throws {
    guard let operation = retainedStopRegistration,
      case .sparseTipBatch = operation.target,
      operation.segment?.target == target,
      let latch = operation.state.latch
    else { return }
    await requestSingleJogCancel(for: target, intent: latch.intent)
    await owner.settle()
    throw LearningPathOperationError.controllerCancelled(
      "The four-corner calibration batch was stopped during segment admission."
    )
  }

  private func setSparseTipBatchPossibleInkLocation(
    _ location: BlacklistedToolContactLocation
  ) {
    guard var operation = retainedStopRegistration,
      case .sparseTipBatch = operation.target
    else { return }
    operation.possibleInkLocation = location
    retainedStopRegistration = operation
  }

  private func clearSparseTipBatchPossibleInkLocation(
    matching location: BlacklistedToolContactLocation
  ) {
    guard var operation = retainedStopRegistration,
      case .sparseTipBatch = operation.target,
      operation.possibleInkLocation == location
    else { return }
    operation.possibleInkLocation = nil
    retainedStopRegistration = operation
  }

  private func cancelAndSettleStoppableOperation(
    _ operation: PlotterRetainedStopRegistration,
    intent: JogCancelIntent
  ) async {
    if case .positionRecovery = operation.target {
      await tipCalibrationRuntime.stop()
      await operation.owner.settle()
      return
    }
    if case .sparseTipBatch = operation.target {
      operation.owner.cancelBatch()
      if let segment = operation.segment {
        await requestSingleJogCancel(for: segment.target, intent: intent)
        await segment.owner.settle()
      }
      await operation.owner.settle()
      return
    }
    await requestSingleJogCancel(for: operation.target, intent: intent)
    await operation.owner.settle()
  }

  private func beginCancellationRequest(
    for target: ContextualStopTarget,
    intent: JogCancelIntent
  ) -> Bool {
    guard var operation = retainedStopRegistration,
      operation.target.capabilityID == target.capabilityID,
      case .latched(let latch, false) = operation.state,
      latch.intent == intent
    else { return false }
    operation.state = .latched(latch, cancellationRequestInProgress: true)
    retainedStopRegistration = operation
    return true
  }

  private func finishCancellationRequest(for target: ContextualStopTarget) {
    guard var operation = retainedStopRegistration,
      operation.target.capabilityID == target.capabilityID,
      case .latched(let latch, true) = operation.state
    else { return }
    operation.state = .latched(latch, cancellationRequestInProgress: false)
    retainedStopRegistration = operation
  }

  private func updateContextualStopAudit(
    for target: ContextualStopTarget,
    outcome: String
  ) {
    guard let latch = stopDispositionLatch,
      latch.capabilityID == target.capabilityID
    else { return }
    let action =
      switch latch.intent {
      case .operatorStop: "Stop"
      case .cancelAttempt: "Cancel Attempt"
      case .shutdown: "Shutdown"
      }
    lastContextualStopAuditRecord = ContextualStopAuditRecord(
      capabilityID: target.capabilityID,
      actor: latch.actor,
      action: action,
      disposition: latch.intent,
      outcome: outcome
    )
  }

  private func manualJogIntent(
    _ direction: JogDirection,
    draft: ManualMotionDraft
  ) -> PlotterManualMotionIntent? {
    guard manualMotionDraftUnavailableReason(for: draft) == nil else { return nil }
    do {
      let distance: Double
      let episodeDirection: PlotterJogDirection
      switch direction {
      case .xNegative:
        distance = inputNumber(draft.xDistanceMM)!
        episodeDirection = .negativeX
      case .xPositive:
        distance = inputNumber(draft.xDistanceMM)!
        episodeDirection = .positiveX
      case .yNegative:
        distance = inputNumber(draft.yDistanceMM)!
        episodeDirection = .negativeY
      case .yPositive:
        distance = inputNumber(draft.yDistanceMM)!
        episodeDirection = .positiveY
      }
      let request = try PlotterJogRequest(
        direction: episodeDirection,
        distanceMM: distance,
        feedMMPerMinute: inputNumber(draft.feedMMPerMinute)!,
        routing: manualControllerPenState.requiredJogRouting
      )
      return .jog(request)
    } catch {
      return nil
    }
  }

  private func manualPenIntent(_ command: PenCommand) -> PlotterManualMotionIntent {
    let position: PlotterPenPosition = command == .raise ? .raised : .lowered
    return .setPen(manualPenRequest(position: position))
  }

  @discardableResult
  func submitManualMotionIntent(
    _ intent: PlotterManualMotionIntent
  ) async -> PlotterManualMotionRuntimeSnapshot? {
    guard applicationAdmissionIsOpen, !Task.isCancelled else { return nil }
    if let reason = manualMotionRuntimePresentation.attentionReason {
      machineError = reason
      return nil
    }
    do {
      let environment = manualMotionEnvironment
      let telemetry = environment == .live ? manualMotionTelemetry(for: intent) : nil
      let refusedOperationID = UUID()
      let submission = try await manualMotionRuntime.submit(
        intent,
        capabilityFacts: manualMotionCapabilityFacts(environment: environment),
        environment: environment
      )
      installManualMotionSnapshot(submission.snapshot)
      await refreshManualEnvironmentSnapshot()
      guard submission.disposition == .accepted,
        let effectID = submission.snapshot.activeOperation?.context.effectID
      else {
        if let telemetry {
          await recordWorkflowTelemetry(WorkflowTelemetryEvent(
            operationID: refusedOperationID,
            operation: telemetry.operation,
            phase: .failed,
            detail: submission.snapshot.projection.remedy
              ?? "Manual motion admission was refused by the typed episode evaluator.",
            motionIntent: telemetry.motionIntent,
            failureCode: telemetry.admissionFailureCode,
            recovery: .resolveNamedFailure
          ))
        }
        return nil
      }
      if let telemetry {
        await recordWorkflowTelemetry(WorkflowTelemetryEvent(
          operationID: effectID.rawValue,
          operation: telemetry.operation,
          phase: .intentAccepted,
          detail: telemetry.acceptedDetail,
          motionIntent: telemetry.motionIntent
        ))
      }
      let settlement: PlotterManualMotionRuntimeSnapshot?
      switch intent {
      case .setPen:
        // The admitted finite pen owner has no cancellation capability. Keep
        // its existing presentation observation joined even if this UI caller
        // is cancelled; actual settlement still has to retire cached busy state.
        let observation = Task { @MainActor in
          await self.observeManualMotionSettlement(effectID: effectID)
        }
        settlement = await observation.value
      case .jog:
        settlement = await observeManualMotionSettlement(effectID: effectID)
      }
      guard let settled = settlement else { return nil }
      if let telemetry,
        let terminal = settled.projection.lastTerminalEffect,
        terminal.result.context.effectID == effectID
      {
        let terminalTelemetry = manualMotionTerminalTelemetry(
          terminal.result,
          operation: telemetry.operation
        )
        await recordWorkflowTelemetry(WorkflowTelemetryEvent(
          operationID: effectID.rawValue,
          operation: telemetry.operation,
          phase: terminalTelemetry.phase,
          detail: terminalTelemetry.detail,
          motionIntent: telemetry.motionIntent,
          failureCode: terminalTelemetry.failureCode,
          recovery: terminalTelemetry.recovery
        ))
      }
      guard !Task.isCancelled,
        settled.projection.lastTerminalEffect?.result.context.effectID == effectID else {
        return nil
      }
      return settled
    } catch {
      machineError = actionableDescription(error)
      return nil
    }
  }

  private func observeManualMotionSettlement(
    effectID: EpisodeEffectID
  ) async -> PlotterManualMotionRuntimeSnapshot? {
    while !Task.isCancelled, applicationAdmissionIsOpen {
      try? await Task.sleep(nanoseconds: 20_000_000)
      let snapshot = await manualMotionRuntime.currentSnapshot()
      installManualMotionSnapshot(snapshot)
      if snapshot.activeOperation?.context.effectID != effectID {
        await refreshManualEnvironmentSnapshot()
        return snapshot
      }
    }
    return nil
  }

  private func manualMotionTelemetry(
    for intent: PlotterManualMotionIntent
  ) -> (
    operation: WorkflowTelemetryOperation,
    motionIntent: WorkflowMotionIntent,
    acceptedDetail: String,
    admissionFailureCode: WorkflowTelemetryFailureCode
  )? {
    guard case let .jog(request) = intent else { return nil }
    let deltaXMM: Double
    let deltaYMM: Double
    switch request.direction {
    case .positiveX: (deltaXMM, deltaYMM) = (request.distanceMM, 0)
    case .negativeX: (deltaXMM, deltaYMM) = (-request.distanceMM, 0)
    case .positiveY: (deltaXMM, deltaYMM) = (0, request.distanceMM)
    case .negativeY: (deltaXMM, deltaYMM) = (0, -request.distanceMM)
    }
    let motionIntent = WorkflowMotionIntent(
      deltaXMM: deltaXMM,
      deltaYMM: deltaYMM,
      feedMMPerMinute: request.feedMMPerMinute
    )
    if request.routing == .drawingStroke {
      return (
        .manualDrawingStroke,
        motionIntent,
        "An operator-authored Pen Down manual drawing stroke started.",
        .manualDrawingAdmissionRejected
      )
    }
    return (
      .manualJog,
      motionIntent,
      request.routing == .possibleInk
        ? "An operator-authored manual jog started with unknown pen state and was recorded as possible ink."
        : "An operator-authored manual jog started.",
      .manualJogAdmissionRejected
    )
  }

  private func manualMotionTerminalTelemetry(
    _ result: PlotterEffectResult,
    operation: WorkflowTelemetryOperation
  ) -> (
    phase: WorkflowTelemetryPhase,
    detail: String,
    failureCode: WorkflowTelemetryFailureCode?,
    recovery: WorkflowTelemetryRecovery
  ) {
    let detail = "Manual motion settled as \(result.disposition.rawValue)."
    switch result.disposition {
    case .completed:
      return (.completed, detail, nil, .none)
    case .cancelled:
      return (.cancelled, detail, nil, .none)
    case .refused:
      return (
        .failed,
        detail,
        operation == .manualDrawingStroke ? .manualDrawingRefused : .manualJogRefused,
        .resolveNamedFailure
      )
    case .ambiguous:
      return (
        .failed,
        detail,
        operation == .manualDrawingStroke ? .manualDrawingAmbiguous : .manualJogAmbiguous,
        .resolveNamedFailure
      )
    case .timedOut, .evidenceUnavailable, .failed:
      return (.failed, detail, nil, .resolveNamedFailure)
    }
  }

  private func discoverCameras() async {

    guard currentCameraCalibrationBusyReason == nil else { return }
    guard let generation = beginApplicationEffect() else { return }
    defer { settleApplicationEffect(generation) }
    guard observationRuntime != nil else {
      cameraError = "Native camera composition is unavailable."
      return
    }
    _ = await submitObservationIntent(.refreshSources)
    guard let snapshot = await observationRuntime?.snapshot() else { return }
    guard applicationEffectCanCommit(generation) else { return }
    cameraSnapshot = snapshot
    updateCameraError()
  }

  private func startPreferredCameraAtStartup() async {
    await discoverCameras()
    guard applicationAdmissionIsOpen, cameraError == nil else { return }
    let preferred =
      cameraDevices.first(where: {
        $0.name.localizedCaseInsensitiveContains("C920")
          || $0.name.localizedCaseInsensitiveContains("HD Pro Webcam")
      })
      ?? cameraDevices.onlyElement
    guard let preferred else { return }
    if selectedCameraID != preferred.id {
      await selectCamera(preferred.id)
    }
    guard applicationAdmissionIsOpen, cameraError == nil, selectedCameraID == preferred.id else { return }
    await startCamera()
  }

  private func selectCamera(_ id: CameraDeviceID) async {
    guard currentCameraCalibrationBusyReason == nil else {
      cameraError = currentCameraCalibrationBusyReason
      return
    }
    guard let generation = beginApplicationEffect() else { return }
    defer { settleApplicationEffect(generation) }
    guard observationRuntime != nil, activeDiscoverySequenceID == nil,
      borderValidationSnapshot.activeOperationID == nil
    else {
      cameraError =
        "Finish the current discovery or learning action before changing camera configuration."
      return
    }
    clearAutomaticVisionPresentation()
    videoAnalysisRegionLock = nil
    let changesAcceptedDevice =
      if let selectedCameraID {
        selectedCameraID != id
      } else if let durableAcceptedLiveCameraDeviceID {
        durableAcceptedLiveCameraDeviceID != id
      } else {
        false
      }
    if changesAcceptedDevice {
      invalidateCameraDependentLearningAuthority()
    }
    cameraError = nil
    do {
      let disposition = await submitObservationIntent(.selectLiveSource(id))
      switch disposition {
      case .failed(let detail)?, .refused(let detail)?:
        throw LearningPathOperationError.requiredState(detail)
      case .applied(_)?, .stale?, nil:
        break
      }
      guard let snapshot = await observationRuntime?.snapshot() else {
        throw LearningPathOperationError.freshFrameUnavailable
      }
      guard applicationEffectCanCommit(generation) else { return }
      cameraSnapshot = snapshot
      displayedFrame = nil
      latestLiveCameraFrame = nil
    } catch {
      let snapshot = await observationRuntime?.snapshot()
      guard applicationEffectCanCommit(generation) else { return }
      cameraError = actionableDescription(error)
      cameraSnapshot = snapshot
    }
  }

  private func startCamera() async {

    guard currentCameraCalibrationBusyReason == nil else { return }
    guard let generation = beginApplicationEffect() else { return }
    defer { settleApplicationEffect(generation) }
    guard observationRuntime != nil else { return }
    _ = await submitObservationIntent(.startLiveSource)
    guard let snapshot = await observationRuntime?.snapshot() else { return }
    guard applicationEffectCanCommit(generation) else { return }
    frameMode = .live
    cameraSnapshot = snapshot
    displayedFrame = cameraSnapshot?.latestFrame
    latestLiveCameraFrame = validatedLiveCameraFrame(in: snapshot)
    reconcileCameraDependentLearningAuthority(with: displayedFrame)
    updateCameraError()
    await reconcileAutomaticVisionAnalysis()
  }

  private func stopCamera() async {

    guard currentCameraCalibrationBusyReason == nil else { return }
    guard let generation = beginApplicationEffect() else { return }
    defer { settleApplicationEffect(generation) }
    clearAutomaticVisionPresentation()
    guard observationRuntime != nil else { return }
    _ = await submitObservationIntent(.stopLiveSource)
    guard let snapshot = await observationRuntime?.snapshot() else { return }
    guard applicationEffectCanCommit(generation) else { return }
    cameraSnapshot = snapshot
    latestLiveCameraFrame = nil
    updateCameraError()
  }

  private func restartCamera() async {

    guard currentCameraCalibrationBusyReason == nil else { return }
    guard let generation = beginApplicationEffect() else { return }
    defer { settleApplicationEffect(generation) }
    guard activeDiscoverySequenceID == nil,
      borderValidationSnapshot.activeOperationID == nil
    else {
      cameraError = "Finish the current discovery or learning action before restarting the camera."
      return
    }
    clearAutomaticVisionPresentation()
    videoAnalysisRegionLock = nil
    guard observationRuntime != nil else { return }
    _ = await submitObservationIntent(.restartLiveSource)
    guard let snapshot = await observationRuntime?.snapshot() else { return }
    guard applicationEffectCanCommit(generation) else { return }
    frameMode = .live
    cameraSnapshot = snapshot
    displayedFrame = cameraSnapshot?.latestFrame
    latestLiveCameraFrame = validatedLiveCameraFrame(in: snapshot)
    reconcileCameraDependentLearningAuthority(with: displayedFrame)
    lastSceneMeasurement = nil
    updateCameraError()
    await reconcileAutomaticVisionAnalysis()
  }

  private func inspectWorkflowScene(
    owner: ExactWorkflowVisionOwner,
    newerThan boundary: UInt64,
    requestedFeatures: SceneFeatureSet = [.penCap],
    analysisRegion: PixelRect? = nil
  ) async throws -> LiveSceneInspection? {
    try beginExactWorkflowVision(owner)
    defer { endExactWorkflowVision(owner) }
    return try await requestWorkflowScene(
      newerThan: boundary,
      requestedFeatures: requestedFeatures,
      analysisRegion: analysisRegion
    )
  }

  private func requestWorkflowScene(
    newerThan boundary: UInt64,
    requestedFeatures: SceneFeatureSet,
    analysisRegion: PixelRect?
  ) async throws -> LiveSceneInspection? {
    guard let observationRuntime else { return nil }
    if frameMode == .live, livePenCapAppearanceSelection == nil,
      !requestedFeatures.intersection([.penCap, .armatureEnvelope]).isEmpty
    {
      throw LearningPathOperationError.requiredState(
        "Use Identify Pen Cap before requesting LIVE pen-cap analysis."
      )
    }
    return try await observationRuntime.inspectWorkflowScene(
      newerThanNanoseconds: boundary,
      requestedFeatures: requestedFeatures,
      analysisRegion: analysisRegion
    )
  }

  private func observePlannedDrawingInk(
    owner: ExactWorkflowVisionOwner,
    request: PlannedDrawingObservationRequest,
    using observer: any PlotterDrawingRunVisionPort
  ) async throws -> PlannedDrawingObservationOutcome {
    try beginExactWorkflowVision(owner)
    defer { endExactWorkflowVision(owner) }
    return await observer.observePlannedDrawingInk(request)
  }

  func captureStableWorkflowCap(
    newerThan initialBoundary: UInt64,
    owner: ExactWorkflowVisionOwner = .cameraCalibration,
    searchCenter: Point2<CameraPixelSpace>? = nil
  ) async throws -> StableWorkflowCapInspection {
    try beginExactWorkflowVision(owner)
    defer { endExactWorkflowVision(owner) }
    if frameMode == .live, livePenCapAppearanceSelection == nil {
      throw LearningPathOperationError.requiredState(
        "Use Identify Pen Cap before requesting LIVE pen-cap analysis."
      )
    }
    guard let observationRuntime else {
      throw LearningPathOperationError.freshFrameUnavailable
    }
    return try await observationRuntime.captureStableWorkflowCap(
      StableWorkflowCapCaptureRequest(
        newerThanNanoseconds: initialBoundary, searchCenter: searchCenter
      )
    )
  }

  private func beginExactWorkflowVision(_ owner: ExactWorkflowVisionOwner) throws {
    if let activeOwner = exactWorkflowVisionOwner {
      throw LearningPathOperationError.requiredState(
        "Camera analysis is busy with \(activeOwner.operatorLabel)."
      )
    }
    exactWorkflowVisionOwner = owner
  }

  private func endExactWorkflowVision(_ owner: ExactWorkflowVisionOwner) {
    precondition(
      exactWorkflowVisionOwner == owner,
      "Only the active exact-workflow Vision owner may settle its request."
    )
    exactWorkflowVisionOwner = nil
  }

  private func transitionObservationSource(_ mode: OperatorFrameMode) async {

    guard let generation = beginApplicationEffect() else { return }
    defer { settleApplicationEffect(generation) }
    guard mode != frameMode || displayedFrame == nil else { return }
    if let reason = observationSourceChangeUnavailableReason {
      cameraError = reason
      return
    }
    await cancelPointSelectionRequest()
    guard observationRuntime != nil else { return }
    frameModeSwitchInProgress = true
    defer { frameModeSwitchInProgress = false }
    clearAutomaticVisionPresentation()
    videoAnalysisRegionLock = nil
    cameraError = nil
    switch mode {
    case .live:
      _ = await submitObservationIntent(.startLiveSource)
      guard let snapshot = await observationRuntime?.snapshot() else { return }
      guard applicationEffectCanCommit(generation) else { return }
      frameMode = .live
      cameraSnapshot = snapshot
      displayedFrame = cameraSnapshot?.latestFrame
      latestLiveCameraFrame = validatedLiveCameraFrame(in: snapshot)
      updateCameraError()
      await reconcileAutomaticVisionAnalysis()
    case .simulated:
      _ = await submitObservationIntent(.stopLiveSource)
      guard let snapshot = await observationRuntime?.snapshot() else { return }
      guard applicationEffectCanCommit(generation) else { return }
      let penReset = await submitPenInteraction(.reset, environment: .simulated)
      guard case .applied = penReset else {
        if case .refused(let refusal) = penReset {
          cameraError = penInteractionRefusalText(refusal)
        }
        return
      }
      cameraSnapshot = snapshot
      latestLiveCameraFrame = nil
      let simulatedBorderReset = simulatedBorderValidationRuntime.apply(.reset)
      guard case .applied = simulatedBorderReset.disposition else {
        if case .refused(let reason, let remedy) = simulatedBorderReset.disposition {
          cameraError = "\(reason) Remedy: \(remedy)"
        }
        return
      }
      let retainedContactPlane = applicationState.environmentStates[.simulated]?
        .explorationPaperContactPlaneRevision ?? UUID()
      applicationState.environmentStates[.simulated] = PlotterApplicationEnvironmentState(
        source: .simulated,
        paperInstanceRevision: UUID(),
        paperContactPlaneRevision: retainedContactPlane
      )
      markSemanticPresentationChanged()
      frameMode = .simulated
      do {
        let scene = try await captureSimulatedProtocolScene()
        guard applicationEffectCanCommit(generation) else { return }
        lastSimulatedProtocolCaptureNanoseconds = scene.displayedFrame.frame.captureNanoseconds
        applySimulatedProtocolScene(scene)
        explorationPaperInstanceRevision = scene.toolPaperRevision
      } catch {
        guard applicationEffectCanCommit(generation) else { return }
        displayedFrame = nil
        cameraError = actionableDescription(error)
      }
    }
  }

  private func refreshSimulatedContent() async {
    guard frameMode == .simulated else { return }
    do {
      let priorCameraConfigurationID = displayedFrame?.frame.cameraConfigurationID
      let scene = try await captureSimulatedProtocolScene()
      lastSimulatedProtocolCaptureNanoseconds = scene.displayedFrame.frame.captureNanoseconds
      applySimulatedProtocolScene(scene)
      if let priorCameraConfigurationID,
        scene.displayedFrame.frame.cameraConfigurationID != priorCameraConfigurationID
      {
        invalidateCameraDependentLearningAuthority()
      }
    } catch {
      cameraError = actionableDescription(error)
    }
  }

  private func applySimulatedCausalImmediateOutcome(
    _ outcome: PlotterCausalSimulatorImmediateOutcome,
    action: String
  ) {
    simulatedLearningSnapshot = outcome.truth.runtime
    simulatorPenState = simulatorPenState(from: outcome.truth.penPose)
    if let refusal = outcome.refusal {
      simulatorLearningSummary =
        "\(action) refused: \(refusal). \(outcome.evidenceNotice.label)"
    } else {
      simulatorLearningSummary =
        "\(action) completed. \(outcome.evidenceNotice.label)"
    }
  }

  private func simulatorPenState(from pose: SimulatedLearningPenPose) -> PenState {
    switch pose {
    case .unknown: .unknown
    case .up: .up
    case .down: .down
    }
  }

  func shutdown() async {
    switch admissionState {
    case .closed:
      return
    case .closing:
      await withCheckedContinuation { continuation in
        shutdownSettlementWaiters.append(continuation)
      }
      return
    case .open:
      break
    }
    // Close every public/root admission path and cancel the exact retained
    // model episode before the first suspension. Feature owners close before
    // the task is joined, so a suspended request cannot outlive its owner.
    admissionState = .closing
    retainedWorkbenchVoiceController?.setEnabled(false)
    startupState = .cancelled
    markSemanticPresentationChanged()
    let learningTask = activeLearningActionTask
    learningTask?.task.cancel()
    let observationSubscription = observationProjectionTask
    let drawingSubscription = drawingRunProjectionTask
    let draftSynchronization = drawingDraftSynchronizationTask
    let evidenceReload = drawingEvidenceReloadTask
    observationSubscription?.cancel()
    drawingSubscription?.cancel()
    draftSynchronization?.cancel()
    evidenceReload?.cancel()
    observationProjectionTask = nil
    drawingRunProjectionTask = nil
    drawingDraftSynchronizationTask = nil
    drawingEvidenceReloadTask = nil
    await liveBorderValidationRuntime.closeAdmissionAndCancel()
    await simulatedBorderValidationRuntime.closeAdmissionAndCancel()
    await artifactResetRuntime.shutdown()
    await liveTipCalibrationRuntime.shutdown()
    await simulatedTipCalibrationRuntime.shutdown()
    // Close the Pen semantic owner before joining retained UI work. A Confirm
    // request can be suspended inside that retained work; the runtime must
    // first publish cancellation so the request cannot later commit evidence
    // or advance its discovery transaction during shutdown.
    await penInteractionRuntime.shutdown()

    _ = await learningTask?.task.value
    if activeLearningActionTask?.transitionID == learningTask?.transitionID {
      activeLearningActionTask = nil
    }
    await observationSubscription?.value
    await drawingSubscription?.value
    await draftSynchronization?.value
    await evidenceReload?.value
    await controllerSessionRuntime.shutdown()
    installDrawingRunSnapshot(
      await drawingRunRuntime.beginShutdown(environment: .live)
    )
    if let selectionID = pointSelectionEpisodeProjection.exactPointSelection.request?.id {
      await pointSelectionRuntime.cancelContinuation(selectionID: selectionID)
    }
    await cameraCalibrationRuntime.shutdown()
    await pointSelectionRuntime.shutdown()
    await boundaryRuntime.beginShutdown()
    await retainedWorkbenchVoiceController?.shutdown()
    await speechEffectRuntime.shutdown()
    await boundaryRuntime.shutdown()
    await manualMotionRuntime.shutdown()
    await stopAndSettleActiveMotionForShutdown()
    await awaitApplicationEffectsSettlement()
    if let observationRuntime {
      await observationRuntime.shutdown()
    } else {
      await portraitStudio.shutdown()
    }
    await drawingMaterials.flush()
    // Persistence occurs only after admission is closed and every effect owner
    // has settled, while the source-indexed semantic state is still intact.
    persistAcceptedLearningPathCheckpoint()
    await clearCameraAuthority()
    await clearMachineAuthority(clearSelection: true)
    admissionState = .closed
    let waiters = shutdownSettlementWaiters
    shutdownSettlementWaiters.removeAll(keepingCapacity: false)
    for waiter in waiters { waiter.resume() }
  }

  private func receive(
    _ frame: DisplayedFrame,
    generation: PlotterApplicationEffectLease? = nil
  ) {
    guard applicationAdmissionIsOpen, frameMode == .live,
      workbenchCameraRole == .plotter, !cameraRoleIsTransitioning else { return }
    if let generation, !applicationEffectCanCommit(generation) { return }
    guard case .live(let deviceID) = frame.source, deviceID == selectedCameraID else { return }
    if let latestLiveCameraFrame,
      latestLiveCameraFrame.source == frame.source,
      latestLiveCameraFrame.frame.cameraConfigurationID == frame.frame.cameraConfigurationID,
      frame.frame.captureNanoseconds < latestLiveCameraFrame.frame.captureNanoseconds {
      return
    }
    publishActionSurfacePreview(frame)
    let hadLiveFrame = latestLiveCameraFrame != nil
    // Compare with the state actually projected to controls. Re-evaluating
    // the previous frame's age here invents a stale -> live transition on
    // every delayed delivery, even while controls still show Live. That
    // feedback rebuilds the whole workbench and delays the next frame again.
    // Freshness reads and effect admission still enforce the existing limit.
    let cameraWasLive = rootProjectionCache?.inputs.cameraIsLive ?? cameraIsLive
    latestLiveCameraFrame = frame
    if hadLiveFrame, cameraWasLive != cameraIsLive {
      markSemanticPresentationChanged()
    }
    reconcileCameraDependentLearningAuthority(with: frame)
    if let lock = videoAnalysisRegionLock, !lock.matches(frame) {
      videoAnalysisRegionLock = nil
      Task {
        await reconcileAutomaticVisionAnalysis()
      }
    }

    guard case .stopped = visionAnalysisSnapshot.phase.state else { return }
    displayedFrame = frame
  }

  private func answerDiscoverySequence(
    _ choice: OperatorChoice,
    for sequenceID: DiscoverySequenceID
  ) async {
    guard let transaction = discoveryTransactions[sequenceID],
      transaction.state == .active,
      let step = transaction.currentStep,
      let question = step.question,
      question.choices.contains(choice)
    else { return }

    guard question.advancingChoices.contains(choice) else {
      _ = await performSpeechEffect(question.negativeAcknowledgement)
      if case .awaitPhysicalPenConfirmation(.down, _) = step.action {
        _ = await performSpeechEffect("Raising the pen.")
        if let capability = currentPenInteractionSnapshot?.projection
          .cancellationCapabilityID
        {
          _ = await submitPenInteraction(.abortAndRaise(capability))
        }
        await failDiscovery(sequenceID, failure: .refused(question.negativeAcknowledgement))
      }
      return
    }

    switch step.action {
    case .awaitOperatorChoice:
      guard recordDiscovery(.operatorChoiceAccepted(choice), for: sequenceID) else { return }
    case .awaitPhysicalPenConfirmation(let state, _):
      let command: PenCommand = state == .down ? .lower : .raise
      let episodeCommand: PlotterPenInteractionCommand = command == .raise ? .raise : .lower
      let claimedOperationID = currentPenInteractionSnapshot?.projection.reference.operationID
      guard case .applied(let confirmedProjection) = await submitPenInteraction(
        .confirm(command: episodeCommand)
      ),
        currentPenInteractionSnapshot?.projection == confirmedProjection,
        penConfirmationReachedExactSuccessor(
          command: episodeCommand,
          claimedOperationID: claimedOperationID,
          projection: confirmedProjection
        )
      else {
        return
      }
      let profile = effectivePenActuationProfile
      let setpoint = profile.value(for: command)
      let execution = currentPenInteractionSnapshot?.lastExecutionByCommand[command].flatMap {
        $0.profile.value(for: command) == setpoint ? $0 : nil
      }
      let position = execution?.position ?? (try? currentMachinePosition())
      let operatorSummary = position.map {
        String(
          format: "Operator confirmed Pen %@ at S%d and MPos X %.3f Y %.3f.",
          state.rawValue,
          setpoint,
          $0.point.x,
          $0.point.y
        )
      } ?? "Operator confirmed Pen \(state.rawValue) at S\(setpoint); current MPos was unavailable."
      guard recordDiscovery(
        .physicalPenConfirmed(state, response: choice, operatorSummary: operatorSummary),
        for: sequenceID
      ) else { return }
    default:
      return
    }
    await advanceDiscoverySequence(sequenceID)
  }

  private func penConfirmationReachedExactSuccessor(
    command: PlotterPenInteractionCommand,
    claimedOperationID: PlotterPenInteractionOperationID?,
    projection: PlotterPenInteractionProjection
  ) -> Bool {
    switch (command, projection.phase) {
    case (.raise, .awaitingControllerCommand(.lower)),
      (.lower, .awaitingControllerCommand(.raise)):
      return claimedOperationID != nil
        && projection.reference.operationID == claimedOperationID
    case (.raise, .succeeded):
      return claimedOperationID != nil
        && projection.reference.operationID == nil
    default:
      return false
    }
  }

  private func startExercise(
    _ ownerID: LearningPathItemID,
    mode: ExerciseAttemptMode
  ) async {
    guard activeExerciseAttemptOwnerID == nil else { return }
    restartableExerciseItemID = nil
    switch ownerID {
    case .humanGuidedDiscovery(.penInteraction):
      await startPenInteractionEpisode(mode: mode)
    case .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering):
      let boundaryMode: PlotterBoundaryAttemptMode = switch mode {
      case .normal: .normal
      case .replacement: .replacement
      case .additional: .additional
      }
      if let direction = currentBoundarySnapshot?.projection.selectedDirection {
        _ = await submitBoundaryIntent(.acquire(direction: direction, mode: boundaryMode))
      }
    case .humanGuidedDiscovery(.calibrateCameraAndVisibleCap):
      beginExerciseAttempt(ownerID: ownerID, mode: mode)
    case .humanGuidedDiscovery(.calibratePenContactFromSparseMarks):
      beginExerciseAttempt(ownerID: ownerID, mode: mode)
    case .borderValidation(.chooseDrawingBorderPlan):
      beginExerciseAttempt(ownerID: ownerID, mode: mode)
      await runBorderValidation()
    case .borderValidation:
      break
    case .stage:
      break
    }
  }

  private func cancelExerciseAttempt(
    _ ownerID: LearningPathItemID,
    expectedAttemptID: ExerciseAttemptID? = nil
  ) async {
    guard activeExerciseAttemptOwnerID == ownerID,
      expectedAttemptID.map({ activeExerciseAttemptID == $0 }) ?? true
    else { return }
    let isPreSequencePenInteraction =
      ownerID == .humanGuidedDiscovery(.penInteraction)
      && activeDiscoverySequenceID == nil
      && pointSelectionEpisodeProjection.exactPointSelection.request?.purpose
        == .penCapAppearance
    if ownerID == .humanGuidedDiscovery(.penInteraction) {
      if let selectionID = pointSelectionEpisodeProjection.exactPointSelection.request?.id {
        await pointSelectionRuntime.cancelContinuation(selectionID: selectionID)
      }
      if let capability = currentPenInteractionSnapshot?.projection
        .cancellationCapabilityID
      {
        _ = await submitPenInteraction(.cancel(capability))
      }
    }
    let learningStopTarget = activeStopTarget
    if let sequenceID = activeDiscoverySequenceID,
      var transaction = discoveryTransactions[sequenceID]
    {
      if let target = learningStopTarget,
        !latchContextualStopDisposition(
          for: target,
          intent: .cancelAttempt,
          actor: "Operator",
          action: "Cancel Attempt"
        )
      {
        return
      }
      transaction.cancel()
      discoveryTransactions[sequenceID] = transaction
      if let target = learningStopTarget {
        await requestSingleJogCancel(for: target, intent: .cancelAttempt)
      }
    } else if isPreSequencePenInteraction {
      // The exact runtime cancellation capability above owns provenance and
      // waits for any in-flight Pen command before this App projection clears.
    } else if let target = activeStopTarget {
      guard
        latchContextualStopDisposition(
          for: target,
          intent: .cancelAttempt,
          actor: "Operator",
          action: "Cancel Attempt"
        )
      else { return }
      if let operation = retainedStopRegistration {
        await cancelAndSettleStoppableOperation(operation, intent: .cancelAttempt)
      }
    }
    if ownerID == .borderValidation(.chooseDrawingBorderPlan),
      borderValidationSnapshot.step == .compareIntendedAndObservedGeometry
    {
      do {
        let histories = try recordComparisonAttempt(
          assessment: nil,
          disposition: .cancelled
        )
        let result = borderValidationRuntime.apply(.installComparisonHistories(histories))
        if case .refused(let reason, let remedy) = result.disposition {
          explorationError = "\(reason) Remedy: \(remedy)"
        }
      } catch {
        explorationError = "Comparison cancellation provenance could not be recorded: \(error)"
      }
    }
    finishActiveExerciseAttempt(disposition: .cancelled)
    restartableExerciseItemID = ownerID
    await cancelPointSelectionRequest()
  }

  private func beginExerciseAttempt(
    ownerID: LearningPathItemID,
    mode: ExerciseAttemptMode
  ) {
    _ = currentEnvironmentState.exerciseAttempt.begin(ownerID: ownerID, mode: mode)
  }

  private func finishActiveExerciseAttempt(disposition: ExerciseAttemptDisposition) {
    if activeExerciseAttemptOwnerID == .humanGuidedDiscovery(.penInteraction) {
      frozenPointSelectionFrame = nil
      pendingToolContactEvidence = []
      pendingToolContactClickFrame = nil
      Task { @MainActor [weak self] in await self?.cancelPointSelectionRequest() }
    }
    if activeExerciseAttemptOwnerID
      == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    {
      frozenPointSelectionFrame = nil
      pendingToolContactEvidence = []
      pendingToolContactClickFrame = nil
      Task { @MainActor [weak self] in await self?.cancelPointSelectionRequest() }
    }
    currentEnvironmentState.exerciseAttempt.finish()
  }

  private func recordAttempt<Value: Hashable & Sendable>(
    _ attempt: ExerciseAttempt<Value>,
    in history: inout ExerciseAttemptHistory<Value>,
    replacingAttemptID: ExerciseAttemptID?
  ) throws {
    if activeExerciseAttemptMode == .replacement {
      guard let replacingAttemptID else {
        throw LearningPathOperationError.requiredState(
          "The accepted attempt selected for replacement is unavailable."
        )
      }
      try history.recordReplacement(attempt, replacing: replacingAttemptID)
    } else {
      try history.record(attempt)
    }
  }

  /// Stages replacement across compatibility-bound histories without pooling.
  /// An incompatible successful Redo supersedes the accepted source sample and
  /// records the new value in its own history; an unsuccessful Redo records only
  /// excluded provenance and leaves the old accepted sample included.
  private func recordAttempt<Value: Hashable & Sendable>(
    _ attempt: ExerciseAttempt<Value>,
    in histories: inout [AttemptCompatibility: ExerciseAttemptHistory<Value>],
    replacingAttemptID: ExerciseAttemptID?
  ) throws {
    var targetHistory =
      try histories[attempt.compatibility]
      ?? ExerciseAttemptHistory(compatibility: attempt.compatibility)
    guard activeExerciseAttemptMode == .replacement else {
      try targetHistory.record(attempt)
      histories[attempt.compatibility] = targetHistory
      return
    }
    guard let replacingAttemptID else {
      throw LearningPathOperationError.requiredState(
        "The accepted attempt selected for replacement is unavailable."
      )
    }

    if targetHistory.records.contains(where: { $0.attempt.id == replacingAttemptID }) {
      try targetHistory.recordReplacement(attempt, replacing: replacingAttemptID)
      histories[attempt.compatibility] = targetHistory
      return
    }

    guard
      let sourceCompatibility = histories.first(where: { _, history in
        history.records.contains(where: { $0.attempt.id == replacingAttemptID })
      })?.key
    else {
      throw ExerciseAttemptError.replacementTargetNotFound(replacingAttemptID)
    }
    try targetHistory.record(attempt)
    if attempt.disposition.contributesSuccessfulValue {
      var sourceHistory = histories[sourceCompatibility]!
      try sourceHistory.supersedeIncludedAttempt(replacingAttemptID, by: attempt.id)
      histories[sourceCompatibility] = sourceHistory
    }
    histories[attempt.compatibility] = targetHistory
  }

  private func commitSuccessfulDiscoveryAttempt(_ sequenceID: DiscoverySequenceID) {
    guard let attemptID = activeExerciseAttemptID else { return }
    do {
      switch sequenceID {
      case .penInteraction:
        guard let runtimeSnapshot = currentPenInteractionSnapshot,
          runtimeSnapshot.acceptedHistory.includedSuccessfulAttempts.contains(where: {
            $0.id == attemptID
          })
        else {
          throw LearningPathOperationError.requiredState(
            "Pen Interaction runtime did not publish exact accepted attempt evidence."
          )
        }
        var graph = learningArtifactGraph
        let commit = try graph.commitReplacement(
          LearningArtifactRevision(
            kind: .penInteraction,
            attemptID: attemptID,
            disposition: .succeeded
          )
        )
        acceptedAttemptSequence = max(
          acceptedAttemptSequence,
          runtimeSnapshot.acceptedSequence
        )
        learningArtifactGraph = graph
        applyArtifactInvalidations(commit.invalidatedRevisionIDs)
        persistAcceptedLearningPathCheckpoint(clearTip: true, clearStageFour: true)

      case .boundaryNegativeX, .boundaryPositiveX, .boundaryNegativeY, .boundaryPositiveY:
        // Boundary sequences commit their complete staged authority directly in
        // `commitBoundaryObservation`; reaching this callback would split the
        // transaction from its accepted aggregate.
        return
      }
      discoveryError = nil
      restartableExerciseItemID = nil
      finishActiveExerciseAttempt(disposition: .succeeded)
    } catch {
      discoveryError = "The accepted Learning result could not be saved: \(error)"
      restartableExerciseItemID = learningPathItemID(for: sequenceID)
      finishActiveExerciseAttempt(disposition: .failed(String(describing: error)))
    }
  }

  var currentPenInteractionAggregate: LatestStateAggregate<PenInteractionAttemptEvidence>? {
    currentPenInteractionSnapshot.flatMap {
      try? LatestStateAggregate(history: $0.acceptedHistory)
    }
  }

  private func recordComparisonAttempt(
    assessment: BorderValidationAssessment?,
    disposition: ExerciseAttemptDisposition
  ) throws -> PlotterBorderValidationComparisonHistories {
    guard let attemptID = activeExerciseAttemptID else {
      throw LearningPathOperationError.requiredState("No active Learning Path attempt.")
    }
    let compatibility = AttemptCompatibility(
      cameraConfigurationID: borderValidationSnapshot.postFrame?.frame.cameraConfigurationID,
      coordinateSpace: .categorical,
      units: .categorical,
      group: borderValidationSnapshot.group,
      algorithmRevision: "typed-trial-comparison-v1"
    )
    var histories = borderValidationSnapshot.comparisonAttemptHistories
    let sequence = acceptedAttemptSequence &+ 1
    let replacingAttemptID = learningArtifactGraph.currentRevision(
      for: .comparison(borderValidationSnapshot.group)
    )?.attemptID
    try recordAttempt(
      ExerciseAttempt(
        id: attemptID,
        disposition: disposition,
        compatibility: compatibility,
        acceptedSequence: sequence,
        value: assessment
      ),
      in: &histories,
      replacingAttemptID: replacingAttemptID
    )
    acceptedAttemptSequence = sequence
    return histories
  }

  private func commitDrawingArtifact(for step: BorderValidationStep) throws {
    guard let attemptID = activeExerciseAttemptID else {
      throw LearningPathOperationError.requiredState("No active Learning Path attempt.")
    }
    let group = borderValidationSnapshot.group
    var graph = learningArtifactGraph
    func required(_ kind: LearningArtifactKind) throws -> LearningArtifactRevisionID {
      guard let id = graph.currentRevision(for: kind)?.id else {
        throw LearningPathOperationError.requiredState("Required artifact \(kind) is unavailable.")
      }
      return id
    }
    let kind: LearningArtifactKind
    let dependencies: Set<LearningArtifactRevisionID>
    switch step {
    case .chooseDrawingBorderPlan:
      kind = .linePlan(group)
      dependencies = [try required(.tipCameraRegistration)]
    case .captureLocalPreFrameBaseline:
      kind = .localPreLineBaseline(group)
      dependencies = [try required(.tipCameraRegistration)]
    case .moveToDrawingBorderStart:
      return
    case .drawDrawingBorder:
      kind = .lineExecution(group)
      dependencies = [try required(.linePlan(group))]
    case .revealAndObserveNewInk:
      kind = .postLineFrame(group)
      dependencies = [
        try required(.lineExecution(group)),
        try required(.localPreLineBaseline(group)),
        try required(.tipCameraRegistration),
      ]
    case .compareIntendedAndObservedGeometry:
      kind = .comparison(group)
      dependencies = [
        try required(.inkObservation(group)), try required(.residual(group)),
      ]
    }
    let primary = try graph.commitReplacement(
      LearningArtifactRevision(
        kind: kind,
        attemptID: attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: dependencies
      )
    )
    var invalidated = primary.invalidatedRevisionIDs

    if step == .revealAndObserveNewInk {
      let baseline = try required(.localPreLineBaseline(group))
      let line = try required(.lineExecution(group))
      let post = try required(.postLineFrame(group))
      let tip = try required(.tipCameraRegistration)
      let ink = try graph.commitReplacement(
        LearningArtifactRevision(
          kind: .inkObservation(group),
          attemptID: attemptID,
          disposition: .succeeded,
          consumedRevisionIDs: [baseline, line, post, tip]
        )
      )
      let residual = try graph.commitReplacement(
        LearningArtifactRevision(
          kind: .residual(group),
          attemptID: attemptID,
          disposition: .succeeded,
          consumedRevisionIDs: [ink.currentRevision.id]
        )
      )
      invalidated.formUnion(ink.invalidatedRevisionIDs)
      invalidated.formUnion(residual.invalidatedRevisionIDs)
    }
    learningArtifactGraph = graph
    applyArtifactInvalidations(invalidated)
  }

  private func commitComparisonAttemptAndArtifact(
    _ assessment: BorderValidationAssessment
  ) throws -> PlotterBorderValidationComparisonHistories {
    guard let attemptID = activeExerciseAttemptID else {
      throw LearningPathOperationError.requiredState("No active Learning Path attempt.")
    }
    let compatibility = AttemptCompatibility(
      cameraConfigurationID: borderValidationSnapshot.postFrame?.frame.cameraConfigurationID,
      coordinateSpace: .categorical,
      units: .categorical,
      group: borderValidationSnapshot.group,
      algorithmRevision: "typed-trial-comparison-v1"
    )
    var histories = borderValidationSnapshot.comparisonAttemptHistories
    let sequence = acceptedAttemptSequence &+ 1
    let comparisonKind = LearningArtifactKind.comparison(borderValidationSnapshot.group)
    let replacingAttemptID = learningArtifactGraph.currentRevision(for: comparisonKind)?.attemptID
    try recordAttempt(
      ExerciseAttempt(
        id: attemptID,
        disposition: .succeeded,
        compatibility: compatibility,
        acceptedSequence: sequence,
        value: assessment
      ),
      in: &histories,
      replacingAttemptID: replacingAttemptID
    )

    var graph = learningArtifactGraph
    guard let ink = graph.currentRevision(for: .inkObservation(borderValidationSnapshot.group))?.id,
      let residual = graph.currentRevision(for: .residual(borderValidationSnapshot.group))?.id
    else {
      throw LearningPathOperationError.requiredState(
        "Observed ink and residual artifacts are required.")
    }
    let commit = try graph.commitReplacement(
      LearningArtifactRevision(
        kind: comparisonKind,
        attemptID: attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: [ink, residual]
      )
    )
    acceptedAttemptSequence = sequence
    learningArtifactGraph = graph
    applyArtifactInvalidations(commit.invalidatedRevisionIDs)
    return histories
  }

  private func applyArtifactInvalidations(
    _ revisionIDs: Set<LearningArtifactRevisionID>,
    preservingCameraCalibrationRuntime: Bool = false
  ) {
    var borderRewindStep: BorderValidationStep?
    func requireBorderRewind(_ step: BorderValidationStep) {
      guard let current = borderRewindStep else {
        borderRewindStep = step
        return
      }
      if step.rawValue < current.rawValue { borderRewindStep = step }
    }
    for revisionID in revisionIDs {
      guard let revision = learningArtifactGraph.revision(id: revisionID) else { continue }
      switch revision.kind {
      case .penInteraction, .boundarySideAggregate, .estimatedMachineCenter, .centerArrival:
        // Boundary authority is invalidated or rebased only through its typed
        // runtime transaction, never by mutating a workspace projection.
        break
      case .machineCameraRegistration:
        if !preservingCameraCalibrationRuntime { machineCameraRegistration = nil }
      case .toolContactObservation:
        break
      case .tipCameraRegistration:
        tipCameraRegistration = nil
        proposedTipCameraRegistration = nil
        requireBorderRewind(.chooseDrawingBorderPlan)
      case .localPreLineBaseline:
        requireBorderRewind(.captureLocalPreFrameBaseline)
      case .linePlan:
        requireBorderRewind(.chooseDrawingBorderPlan)
      case .lineExecution:
        requireBorderRewind(.drawDrawingBorder)
      case .postLineFrame:
        requireBorderRewind(.revealAndObserveNewInk)
      case .inkObservation, .residual:
        requireBorderRewind(.revealAndObserveNewInk)
      case .comparison:
        requireBorderRewind(.compareIntendedAndObservedGeometry)
      }
    }
    if let required = borderRewindStep {
      let snapshot = borderValidationSnapshot
      // An admitted Border effect publishes its replacement through the exact
      // typed result. Redo admission already rewound the model before the
      // effect began, so a second state intent here would be refused as a
      // competing mutation while the operation is active.
      guard snapshot.activeOperationID == nil else { return }
      let result = borderValidationRuntime.apply(
        .rewind(required.rawValue < snapshot.step.rawValue ? required : snapshot.step)
      )
      if case .refused(let reason, let remedy) = result.disposition {
        learningAuthorityError = "\(reason) Remedy: \(remedy)"
      }
    }
  }

  private func learningPathItemID(for sequenceID: DiscoverySequenceID) -> LearningPathItemID {
    sequenceID == .penInteraction
      ? .humanGuidedDiscovery(.penInteraction)
      : .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
  }

  private func jogDirection(for sequenceID: DiscoverySequenceID) -> JogDirection? {
    switch sequenceID {
    case .boundaryNegativeX: .xNegative
    case .boundaryPositiveX: .xPositive
    case .boundaryNegativeY: .yNegative
    case .boundaryPositiveY: .yPositive
    case .penInteraction: nil
    }
  }

  private func jogDirection(from direction: BoundaryDirection) -> JogDirection {
    switch direction {
    case .negativeX: .xNegative
    case .positiveX: .xPositive
    case .negativeY: .yNegative
    case .positiveY: .yPositive
    }
  }

  private func boundaryDirection(from direction: JogDirection)
    -> BoundaryDirection
  {
    switch direction {
    case .xNegative: .negativeX
    case .xPositive: .positiveX
    case .yNegative: .negativeY
    case .yPositive: .positiveY
    }
  }

  private func receiveVision(_ result: PlotterSceneAnalysisResult) {
    guard frameMode == .live, case .running = visionAnalysisSnapshot.phase.state else { return }
    if let lock = videoAnalysisRegionLock, !lock.matches(result.displayedFrame) {
      videoAnalysisRegionLock = nil
      Task {
        await reconcileAutomaticVisionAnalysis()
      }
    }
    if let current = displayedFrame,
      current.source == result.displayedFrame.source,
      current.frame.cameraConfigurationID == result.displayedFrame.frame.cameraConfigurationID,
      current.frame.captureNanoseconds > result.displayedFrame.frame.captureNanoseconds {
      // Keep the exact frame selected by a newer operator action. Scene
      // measurements below still retain their own original frame identity.
    } else {
      displayedFrame = result.displayedFrame
    }
    lastSceneMeasurement = result.measurement
    overlayResultChannels.publishScene(
      overlayChannelResult(
        displayedFrame: result.displayedFrame,
        measurement: result.measurement
      )
    )
  }

  private func publishWorkflowInspection(
    _ inspection: LiveSceneInspection,
    owner: WorkflowOverlayOwner
  ) {
    overlayResultChannels.publishWorkflow(
      overlayChannelResult(
        displayedFrame: inspection.displayedFrame,
        measurement: inspection.measurement
      ),
      source: frameMode,
      owner: owner
    )
  }

  private func overlayChannelResult(
    displayedFrame: DisplayedFrame,
    measurement: PlotterSceneMeasurement
  ) -> OverlayChannelResult {
    let provenance = ExactFrameOverlayProvenance(displayedFrame)
    let capStateAndMessage: (OverlayRunState, String) =
      switch measurement.penCap {
      case .notRequested:
        (.unavailable, "Pen-cap analysis was not requested.")
      case .found(let cap, _):
        (
          .available,
          OverlayStatusGrammar.found(
            pixelCount: cap.pixelCount,
            confidence: cap.confidence,
            frame: displayedFrame.frame.sequence
          )
        )
      case .notFound:
        (.unavailable, OverlayStatusGrammar.notFound)
      case .ambiguous(let counts, _):
        (.ambiguous, OverlayStatusGrammar.ambiguous(candidateSizes: counts))
      case .failed(let reason):
        (.failed, "Failed — \(reason)")
      }
    let capStatus = OverlayLayerStatus(
      state: capStateAndMessage.0,
      message: capStateAndMessage.1,
      provenance: provenance
    )
    let armatureStateAndMessage: (OverlayRunState, String) =
      switch measurement.armatureEnvelope {
      case .notRequested:
        (.unavailable, "Armature-envelope analysis was not requested.")
      case .available:
        (.available, OverlayStatusGrammar.armatureAvailable)
      case .unavailableBecausePenCap(let capResult):
        (
          .unavailable,
          OverlayStatusGrammar.armatureUnavailable(reason: capResult.diagnosticReason)
        )
      case .failed(let reason):
        (.failed, "Failed — \(reason)")
      }
    let armatureStatus = OverlayLayerStatus(
      state: armatureStateAndMessage.0,
      message: armatureStateAndMessage.1,
      provenance: provenance
    )
    return OverlayChannelResult(
      displayedFrame: displayedFrame,
      overlays: measurement.overlays,
      statuses: [.penCap: capStatus, .armatureEnvelope: armatureStatus]
    )
  }

  private func updateCameraError() {
    cameraError = cameraSnapshot?.error?.actionableDescription
  }

  private func validatedLiveCameraFrame(in snapshot: CameraCaptureSnapshot) -> DisplayedFrame? {
    guard let frame = snapshot.latestFrame,
      case .live(let deviceID) = frame.source,
      deviceID == snapshot.selectedDeviceID
    else { return nil }
    return frame
  }

  private func clearMachineAuthority(clearSelection: Bool) async {
    if applicationAdmissionIsOpen {
      let settled = machineCameraRegistration != nil
        ? await cancelAndSettleLearningForReset() : await clearDiscoveryAuthority()
      guard settled else {
        machineError = learningAuthorityError
        return
      }
    }
    if clearSelection { selectedSerialDevice = nil }
    requireVisualPositionRevalidation()
    passiveProbeResult = nil
    machineSnapshot = nil
    machineError = nil
    controllerAlarmClearInProgress = false
    passiveProbeInProgress = false
    jogRequestInProgress = false
    retainedPenRequestInProgress = false
    motionAuthorizationActionInProgress = false
    lastMotionGuardActivationText = "not activated"
    if let activeMachineArtifactCheckpoint {
      acceptedArtifactCheckpointStatus = .quarantined(
        sideCount: activeMachineArtifactCheckpoint.acceptedBoundaryAggregates.count
      )
    }
  }

  private func currentAcceptedPenInteractionCheckpoint()
    -> AcceptedPenInteractionCheckpoint?
  {
    guard let revision = learningArtifactGraph.currentRevision(for: .penInteraction),
      let attempt = currentPenInteractionSnapshot?.acceptedHistory
        .includedSuccessfulAttempts.max(by: {
        $0.acceptedSequence < $1.acceptedSequence
      }),
      let evidence = attempt.value
    else { return nil }
    return try? AcceptedPenInteractionCheckpoint(
      revision: revision,
      acceptedSequence: attempt.acceptedSequence,
      evidence: evidence
    )
  }

  private func savedTrainingArtifactSummary(
    _ checkpoint: AcceptedLearningPathCheckpoint
  ) -> String {
    var artifacts: [String] = []
    if checkpoint.penInteraction != nil { artifacts.append("pen calibration") }
    if let machine = checkpoint.machineArtifacts {
      artifacts.append("\(machine.acceptedBoundaryAggregates.count) Drawing Boundary sides and center")
    }
    if checkpoint.machineCamera != nil { artifacts.append("camera/cap registration") }
    if checkpoint.tipCalibration != nil { artifacts.append("four-corner pen-tip calibration") }
    if checkpoint.stageFour != nil { artifacts.append("Drawing Border validation") }
    if checkpoint.penCapAppearance != nil { artifacts.append("pen-cap appearance") }
    let drawingCount = drawingEvidenceArchive.records.count
    if drawingCount > 0 { artifacts.append("\(drawingCount) archived drawing plan(s)") }
    let contents = artifacts.isEmpty ? "no accepted Learning artifacts" : artifacts.joined(separator: ", ")
    return "Saved Learning \(checkpoint.checkpointID.uuidString.prefix(8)) contains \(contents). It is preview-only until you choose Use Saved Learning."
  }

  private func currentAcceptedMachineCameraCheckpoint()
    -> AcceptedMachineCameraCheckpoint?
  {
    guard let registration = machineCameraRegistration,
      let revision = learningArtifactGraph.currentRevision(for: .machineCameraRegistration)
    else { return nil }
    return try? AcceptedMachineCameraCheckpoint(
      revision: revision,
      registration: registration
    )
  }

  private var currentLearningPathSemanticIdentity: LearningPathSemanticIdentity {
    LearningPathSemanticIdentity(
      machineGeometry: machineGeometryIdentity,
      toolAssembly: toolAssemblyRevision,
      penContactProfile: penContactProfileRevision,
      paperInstance: currentPaperRevisionContext.instance,
      paperContactPlane: currentPaperRevisionContext.contactPlane,
      cameraMountRevision: cameraMountRevision,
      cameraReframingRevision: cameraReframingRevision
    )
  }

  @discardableResult
  private func persistAcceptedLearningPathCheckpoint(
    machineCamera: AcceptedMachineCameraCheckpoint? = nil,
    tipCalibration: AcceptedTipCalibrationCheckpoint? = nil,
    stageFour: AcceptedStageFourCheckpoint? = nil,
    clearTip: Bool = false,
    clearStageFour: Bool = false
  ) -> Bool {
    guard frameMode == .live, let actions = activeStatePersistencePort else {
      return true
    }
    // Do not manufacture an empty startup candidate merely because an
    // untrained application shut down cleanly. A package begins with an
    // accepted dependency revision and grows from that canonical graph.
    guard !learningArtifactGraph.revisions.isEmpty else { return true }
    do {
      let checkpoint = try makeAcceptedLearningPathCheckpoint(
        machineArtifacts: activeMachineArtifactCheckpoint,
        machineCamera: machineCamera, tipCalibration: tipCalibration, stageFour: stageFour,
        clearTip: clearTip, clearStageFour: clearStageFour
      )
      if try shouldPreserveRetainedLearning(checkpoint, using: actions) { return true }
      try actions.saveAcceptedLearningPathCheckpoint(checkpoint)
      artifactResetRuntime.installSavedLearningFact(.applied(
        checkpoint,
        opticalComparison: "Saved from the current accepted Learning prefix."
      ))
      activeMachineCameraCheckpoint = checkpoint.machineCamera
      activeStageFourCheckpoint = checkpoint.stageFour
      return true
    } catch {
      learningAuthorityError = "Learning Path checkpoint could not be saved: \(error)"
      return false
    }
  }

  /// Build the staged Boundary prefix without publishing any candidate authority.
  /// Inactive Saved Learning remains a separate retained package, never a source
  /// of camera/tip descendants for the replacement session.
  func persistStagedBoundaryCheckpoint(_ candidate: PlotterBoundaryPersistenceCandidate,
    using actions: any PlotterApplicationStatePersistencePort) throws {
    guard candidate.environment == .live, frameMode == .live,
      candidate.semanticIdentity == currentLearningPathSemanticIdentity else {
      throw LearningPathOperationError.requiredState("Boundary checkpoint context changed before persistence.")
    }
    if case .retainedForLater = savedLearningState {
      // The shared policy below verifies the exact retained disk package before
      // either preserving it or allowing its completed replacement.
    } else {
      switch actions.loadAcceptedLearningPathCheckpoint() {
      case .absent: break
      case .loaded(let existing):
        guard existing.semanticIdentity == candidate.semanticIdentity else {
          throw LearningPathOperationError.requiredState("Saved Learning identity changed before Boundary persistence.")
        }
      case .rejected(let detail):
        throw LearningPathOperationError.requiredState("Boundary checkpoint is unavailable: \(detail)")
      }
    }
    let preservesDescendants = activeMachineArtifactCheckpoint.map {
      $0.coordinateRevision == candidate.machineArtifacts.coordinateRevision
        && Set($0.acceptedRevisions.map(\.id)) == Set(candidate.machineArtifacts.acceptedRevisions.map(\.id))
    } ?? false
    let checkpoint = try makeAcceptedLearningPathCheckpoint(
      machineArtifacts: candidate.machineArtifacts, retainingMachineDescendants: preservesDescendants)
    if try shouldPreserveRetainedLearning(checkpoint, using: actions) { return }
    try actions.saveAcceptedLearningPathCheckpoint(checkpoint)
  }

  private func makeAcceptedLearningPathCheckpoint(
    machineArtifacts: AcceptedMachineArtifactCheckpoint?,
    retainingMachineDescendants: Bool = true,
    machineCamera: AcceptedMachineCameraCheckpoint? = nil,
    tipCalibration: AcceptedTipCalibrationCheckpoint? = nil,
    stageFour: AcceptedStageFourCheckpoint? = nil,
    clearTip: Bool = false, clearStageFour: Bool = false
  ) throws -> AcceptedLearningPathCheckpoint {
    let retainedCamera = retainingMachineDescendants
      ? machineCamera ?? currentAcceptedMachineCameraCheckpoint() ?? activeMachineCameraCheckpoint : nil
    let retainedTip = clearTip || !retainingMachineDescendants ? nil
      : tipCalibration ?? acceptedLearningPathCheckpoint?.tipCalibration ?? recoverableTipCalibrationCheckpoint
    let retainedStage = clearStageFour || !retainingMachineDescendants ? nil
      : stageFour ?? acceptedLearningPathCheckpoint?.stageFour ?? activeStageFourCheckpoint
    return try AcceptedLearningPathCheckpoint(
      semanticIdentity: currentLearningPathSemanticIdentity,
      penInteraction: currentAcceptedPenInteractionCheckpoint(), machineArtifacts: machineArtifacts,
      machineCamera: retainedCamera, tipCalibration: retainedTip, stageFour: retainedStage,
      penCapAppearance: try livePenCapAppearanceSelection?.acceptedCheckpoint()
        ?? acceptedLearningPathCheckpoint?.penCapAppearance,
      referenceFrame: currentAcceptedLearningReferenceFrame() ?? acceptedLearningPathCheckpoint?.referenceFrame)
  }

  private func shouldPreserveRetainedLearning(_ replacement: AcceptedLearningPathCheckpoint,
    using actions: any PlotterApplicationStatePersistencePort) throws -> Bool {
    guard case .retainedForLater(let retained) = savedLearningState else { return false }
    guard case .loaded(let stored) = actions.loadAcceptedLearningPathCheckpoint(), stored == retained else {
      throw LearningPathOperationError.requiredState("The retained Saved Learning package changed or is unavailable on disk.")
    }
    // Existing single-package policy: incomplete replacement progress remains
    // session-only while the previously complete package is retained durably.
    return !replacementCheckpoint(replacement, hasReachedCompletenessOf: retained)
  }

  private func reconcilePublishedBoundaryCheckpoint(_ snapshot: PlotterBoundaryRuntimeSnapshot) {
    guard frameMode == .live, let actions = activeStatePersistencePort,
      let accepted = snapshot.acceptedMachineArtifacts,
      case .loaded(let stored) = actions.loadAcceptedLearningPathCheckpoint(),
      stored.semanticIdentity == currentLearningPathSemanticIdentity,
      stored.machineArtifacts == accepted else { return }
    // This runs only after the Boundary owner has installed accepted authority.
    // A preserved inactive package cannot match the new Boundary artifacts.
    artifactResetRuntime.installSavedLearningFact(.applied(stored,
      opticalComparison: "Saved from the current accepted Learning prefix."))
    activeMachineCameraCheckpoint = stored.machineCamera
    activeStageFourCheckpoint = stored.stageFour
  }

  private func replacementCheckpoint(
    _ replacement: AcceptedLearningPathCheckpoint,
    hasReachedCompletenessOf retained: AcceptedLearningPathCheckpoint
  ) -> Bool {
    (retained.penInteraction == nil || replacement.penInteraction != nil)
      && (retained.machineArtifacts == nil || replacement.machineArtifacts != nil)
      && (retained.machineCamera == nil || replacement.machineCamera != nil)
      && (retained.tipCalibration == nil || replacement.tipCalibration != nil)
      && (retained.stageFour == nil || replacement.stageFour != nil)
  }

  private func currentAcceptedLearningReferenceFrame()
    -> AcceptedLearningReferenceFrame?
  {
    guard frameMode == .live, let frame = displayedFrame,
      let optical = try? exactTipCalibrationFrame(frame).opticalConfiguration
    else { return nil }
    return try? AcceptedLearningReferenceFrame(
      opticalConfiguration: optical,
      frame: frame.frame
    )
  }

  private func revalidateParkedAcceptedArtifactCheckpoint(
    with probe: PassiveProbeResult,
    currentPosition: MachinePosition?
  ) async {
    guard frameMode == .live,
      acceptedBoundaryAggregates.isEmpty,
      let checkpoint = activeMachineArtifactCheckpoint,
      let currentPosition
    else { return }
    do {
      let context = try ControllerCheckpointContext(probe: probe)
      switch checkpoint.compatibility(with: context, currentPosition: currentPosition) {
      case .incompatible(let reason):
        acceptedArtifactCheckpointStatus = .incompatible(reason)
      case .compatible(let reportedPositionDeltaMM):
        try checkpoint.validate()
        var graph = learningArtifactGraph
        let orderedKinds: [LearningArtifactKind] =
          BoundaryDirection.allCases.map(LearningArtifactKind.boundarySideAggregate)
          + [.estimatedMachineCenter, .centerArrival]
        for kind in orderedKinds {
          guard let revision = checkpoint.acceptedRevisions.first(where: { $0.kind == kind })
          else { continue }
          _ = try graph.commitReplacement(
            LearningArtifactRevision(
              id: revision.id,
              kind: revision.kind,
              attemptID: revision.attemptID,
              disposition: revision.disposition,
              consumedRevisionIDs: revision.consumedRevisionIDs
            )
          )
        }
        if let machineCamera = activeMachineCameraCheckpoint {
          let revision = machineCamera.revision
          _ = try graph.commitReplacement(
            LearningArtifactRevision(
              id: revision.id,
              kind: revision.kind,
              attemptID: revision.attemptID,
              disposition: revision.disposition,
              consumedRevisionIDs: revision.consumedRevisionIDs
            )
          )
          machineCameraRegistration = machineCamera.registration
        }
        try await boundaryRuntime.restore(checkpoint, environment: .live)
        installBoundarySnapshot(await boundaryRuntime.snapshot(for: .live))
        learningArtifactGraph = graph
        controllerSessionID = checkpoint.controllerSessionID
        explorationCoordinateRevision = checkpoint.coordinateRevision
        acceptedAttemptSequence = max(acceptedAttemptSequence, checkpoint.acceptedAttemptSequence)
        requireVisualPositionRevalidation()
        acceptedArtifactCheckpointStatus = .restored(
          sideCount: checkpoint.acceptedBoundaryAggregates.count,
          centerArrival: checkpoint.centerArrivalPosition != nil,
          reportedPositionDeltaMM: reportedPositionDeltaMM
        )
      }
    } catch {
      acceptedArtifactCheckpointStatus = .rejected(
        "Fresh controller revalidation failed: \(error)"
      )
    }
  }

  private func invalidateCameraDependentLearningAuthority() {
    var graph = learningArtifactGraph
    let invalidation = graph.invalidateForCameraChange(
      rootKinds: [.machineCameraRegistration, .tipCameraRegistration]
    )
    learningArtifactGraph = graph
    applyArtifactInvalidations(invalidation.allInvalidatedRevisionIDs)
    cameraCalibrationRuntime.clearForReset()
    activeMachineCameraCheckpoint = nil
    tipCameraRegistration = nil
    proposedTipCameraRegistration = nil
    resetTipCalibrationRuntimeForCurrentPaper()
    frozenPointSelectionFrame = nil
    pendingToolContactEvidence = []
    pendingToolContactClickFrame = nil
    Task { @MainActor [weak self] in await self?.cancelPointSelectionRequest() }
    recoverableTipCalibrationCheckpoint = nil
    persistAcceptedLearningPathCheckpoint(clearTip: true, clearStageFour: true)
    clearDrawingLearningForRewind(from: .chooseDrawingBorderPlan)
    explorationError = nil
    overlayResultChannels.clearWorkflow(source: frameMode)
    // Pen current state, accepted boundary controller MPos revisions, estimated
    // center, and accepted center arrival belong to the unchanged controller
    // session/coordinate authority and deliberately survive camera replacement.
  }

  private func clearPenLearningForRewind() async {
    frozenPointSelectionFrame = nil
    pendingToolContactEvidence = []
    pendingToolContactClickFrame = nil
    Task { @MainActor [weak self] in await self?.cancelPointSelectionRequest() }
    discoveryTransactions.removeValue(forKey: .penInteraction)
    _ = await submitPenInteraction(.reset)
    selectedDiscoverySequenceID = .penInteraction
  }

  private func clearBoundaryLearningForRewind() {
    discoveryTransactions = discoveryTransactions.filter { key, _ in
      key == .penInteraction
    }
    discoveryError = nil
  }

  private func clearCalibrationLearningForRewind() {
    clearCalibrationLearningForRewind(from: .calibrateCameraAndVisibleCap)
  }

  private func clearCalibrationLearningForRewind(from step: HumanGuidedDiscoveryStep) {
    if step.rawValue <= HumanGuidedDiscoveryStep.calibrateCameraAndVisibleCap.rawValue {
      cameraCalibrationRuntime.clearForReset()
    }
    if step.rawValue <= HumanGuidedDiscoveryStep.calibratePenContactFromSparseMarks.rawValue {
      tipCameraRegistration = nil
      proposedTipCameraRegistration = nil
      resetTipCalibrationRuntimeForCurrentPaper()
      frozenPointSelectionFrame = nil
      pendingToolContactEvidence = []
      pendingToolContactClickFrame = nil
      Task { @MainActor [weak self] in await self?.cancelPointSelectionRequest() }
    }
    overlayResultChannels.clearWorkflow(source: frameMode, owner: .cameraCalibration)
    overlayResultChannels.clearWorkflow(source: frameMode, owner: .sparseTipCalibration)
  }

  private func resetTipCalibrationRuntimeForCurrentPaper() {
    tipCalibrationRuntime.resetForPaper(
      PaperInstanceRevision(rawValue: explorationPaperInstanceRevision)
    )
    // Tip/contact-plane invalidation does not remove the retained cap map's
    // ability to establish position before learning the new contact plane.
    if case .requiresVisualRevalidation = controllerPoseApplicability {
      tipCalibrationRuntime.installPositionRecoveryAvailability(machineCameraRegistration != nil)
    }
  }

  private func clearDrawingLearningForRewind(from step: BorderValidationStep) {
    if step.rawValue <= BorderValidationStep.moveToDrawingBorderStart.rawValue {
      lastProtocolPoseSettlement = nil
    }
    if step.rawValue <= BorderValidationStep.revealAndObserveNewInk.rawValue {
      overlayResultChannels.clearWorkflow(source: frameMode, owner: .borderValidation)
    }
    let result = borderValidationRuntime.apply(.rewind(step))
    if case .refused(let reason, let remedy) = result.disposition {
      learningAuthorityError = "\(reason) Remedy: \(remedy)"
    }
  }

  private func cancelAndSettleBoundaryForReset() async -> Bool {
    guard let projection = currentBoundarySnapshot?.projection else {
      learningAuthorityError =
        "The exact Boundary runtime projection is unavailable, so no Learning state was reset."
      return false
    }
    if projection.publicationRecoveryCapabilityID != nil {
      learningAuthorityError =
        "Boundary publication is incomplete. Retry its exact publication before resetting Learning."
      return false
    }
    guard projection.reference.operationID != nil else { return true }
    guard let capability = projection.cancellationCapabilityID else {
      learningAuthorityError =
        "PlotterBoundaryRuntime owns an operation without its exact cancellation capability. No Learning state was reset."
      return false
    }
    let disposition = await boundaryRuntime.submit(
      PlotterBoundarySubmission(
        projection: projection.reference,
        intent: .cancel(capability)
      )
    )
    guard case .applied = disposition else {
      if case .refused(let refusal) = disposition {
        learningAuthorityError =
          "Boundary cancellation was refused by \(refusal.owner): \(refusal.reason). Remedy: \(refusal.remedy)."
      } else {
        learningAuthorityError =
          "The exact Boundary cancellation did not settle, so no Learning state was reset."
      }
      return false
    }
    let settled = await boundaryRuntime.snapshot(for: projection.reference.environment)
    installBoundarySnapshot(settled)
    guard settled.projection.reference.operationID == nil,
      settled.projection.publicationRecoveryCapabilityID == nil
    else {
      learningAuthorityError =
        "The exact Boundary owner did not finish terminal publication, so no Learning state was reset."
      return false
    }
    return true
  }

  private func reserveBoundaryResetBeforePersistence() async
    -> PlotterBoundaryResetCapabilityID?
  {
    guard let projection = currentBoundarySnapshot?.projection else {
      learningAuthorityError =
        "The exact Boundary runtime projection is unavailable, so no Learning state was reset."
      return nil
    }
    let disposition = await boundaryRuntime.submit(
      PlotterBoundarySubmission(projection: projection.reference, intent: .reserveReset)
    )
    guard case .applied(let reservedProjection) = disposition,
      let capability = reservedProjection.resetCapabilityID,
      reservedProjection.reference.operationID == nil,
      reservedProjection.publicationRecoveryCapabilityID == nil
    else {
      if case .refused(let refusal) = disposition {
        learningAuthorityError =
          "Boundary reset reservation was refused by \(refusal.owner): \(refusal.reason). Remedy: \(refusal.remedy)."
      } else {
        learningAuthorityError =
          "PlotterBoundaryRuntime did not publish an exact reset reservation. No local Boundary state was cleared."
      }
      return nil
    }
    installBoundarySnapshot(await boundaryRuntime.snapshot(for: projection.reference.environment))
    return capability
  }

  private func commitBoundaryResetBeforeLocalCleanup(
    _ capability: PlotterBoundaryResetCapabilityID
  ) async -> Bool {
    guard let projection = currentBoundarySnapshot?.projection else {
      learningAuthorityError =
        "The exact Boundary reset reservation is unavailable. No local Boundary state was cleared."
      return false
    }
    let disposition = await boundaryRuntime.submit(
      PlotterBoundarySubmission(
        projection: projection.reference,
        intent: .commitReset(capability)
      )
    )
    guard case .applied(let resetProjection) = disposition,
      resetProjection.resetCapabilityID == nil,
      resetProjection.reference.operationID == nil,
      resetProjection.publicationRecoveryCapabilityID == nil
    else {
      if case .refused(let refusal) = disposition {
        learningAuthorityError =
          "Boundary reset commit was refused by \(refusal.owner): \(refusal.reason). Remedy: \(refusal.remedy)."
      } else {
        learningAuthorityError =
          "PlotterBoundaryRuntime did not publish an exact committed reset. No local Boundary state was cleared."
      }
      return false
    }
    installBoundarySnapshot(await boundaryRuntime.snapshot(for: projection.reference.environment))
    return true
  }

  private func abortBoundaryResetAfterPersistenceRefusal(
    _ capability: PlotterBoundaryResetCapabilityID
  ) async {
    guard let projection = currentBoundarySnapshot?.projection else {
      learningAuthorityError =
        "Durable Learning persistence failed and the exact Boundary reset reservation could not be inspected. Boundary authority was not committed."
      return
    }
    let disposition = await boundaryRuntime.submit(
      PlotterBoundarySubmission(
        projection: projection.reference,
        intent: .abortReset(capability)
      )
    )
    guard case .applied(let restoredProjection) = disposition,
      restoredProjection.resetCapabilityID == nil
    else {
      if case .refused(let refusal) = disposition {
        learningAuthorityError =
          "Durable Learning persistence failed; Boundary reset abort was refused by \(refusal.owner): \(refusal.reason). Remedy: \(refusal.remedy)."
      }
      return
    }
    installBoundarySnapshot(await boundaryRuntime.snapshot(for: projection.reference.environment))
  }

  private func clearDiscoveryAuthority() async -> Bool {
    guard await cancelAndSettleBoundaryForReset(),
      let resetCapability = await reserveBoundaryResetBeforePersistence(),
      await commitBoundaryResetBeforeLocalCleanup(resetCapability)
    else { return false }
    await cancelPointSelectionRequest()
    selectedDiscoverySequenceID = .penInteraction
    discoveryTransactions = [:]
    discoveryError = nil
    cameraCalibrationRuntime.clearForReset()
    tipCameraRegistration = nil
    proposedTipCameraRegistration = nil
    resetTipCalibrationRuntimeForCurrentPaper()
    lastProtocolPoseSettlement = nil
    let borderReset = borderValidationRuntime.apply(.reset)
    if case .refused(let reason, let remedy) = borderReset.disposition {
      learningAuthorityError = "\(reason) Remedy: \(remedy)"
      return false
    }
    learningArtifactGraph = LearningDependencyGraph()
    _ = await submitPenInteraction(.reset)
    currentEnvironmentState.exerciseAttempt.finish()
    restartableExerciseItemID = nil
    return true
  }

  /// Shutdown first closes the admission boundary, then settles the already
  /// latched motion owner. This bypasses normal intent admission without
  /// exposing a second cancellation route to the UI.
  private func stopAndSettleActiveMotionForShutdown() async {
    guard let operation = retainedStopRegistration else { return }
    let target = operation.target
    switch target {
    case .exerciseMotion, .borderValidation, .positionRecovery, .sparseTipBatch, .sparseTipBatchSegment:
      break
    }

    if case .sparseTipBatch = target,
      let location = operation.possibleInkLocation
    {
      blacklistedToolContactLocations.insert(location)
    }

    if stopDispositionLatch == nil,
      latchContextualStopDisposition(
        for: target,
        intent: .shutdown,
        actor: "Application",
        action: "Shutdown"
      )
    {
      await cancelAndSettleStoppableOperation(operation, intent: .shutdown)
    } else {
      await operation.owner.settle()
    }
    clearStoppableOperation(matching: target)
  }

  private func clearCameraAuthority() async {
    if applicationAdmissionIsOpen {
      guard await clearDiscoveryAuthority() else {
        cameraError = learningAuthorityError
        return
      }
    }
    frameMode = .live
    cameraSnapshot = nil
    displayedFrame = nil
    latestLiveCameraFrame = nil
    cameraError = nil
    visionError = nil
    visionAnalysisSnapshot = .stopped
    videoVisionDiagnostics = nil
    lastSceneMeasurement = nil
    simulatorPenState = .unknown
    simulatorLearningSummary = "Switch to SIMULATED to inspect model behavior."
  }

  private func performSpeechEffect(_ message: String) async -> SpeechAnnouncementOutcome {
    let outcome = await speechEffectRuntime.perform(.init(message: message))
    lastAnnouncementResultText =
      switch outcome {
      case .completed: "Announcement completed."
      case .failed(let reason): "Announcement failed: \(reason). Continuing."
      case .timedOut: "Announcement timed out. Continuing."
      case .cancelled: "Announcement cancelled or disabled."
      }
    return outcome
  }

  private func dispatchSpeechEffect(_ message: String) async -> PlotterSpeechEffectAdmission {
    let admission = await speechEffectRuntime.start(.init(message: message))
    lastAnnouncementResultText =
      switch admission {
      case .admitted:
        "Announcement dispatched; playback is advisory and does not delay the next step."
      case .refused(let reason):
        "Announcement dispatch was refused: \(reason). Continuing."
      case .cancelled:
        "Announcement dispatch was cancelled or disabled."
      }
    return admission
  }

  private func positiveFallbackTravelFeed() -> Double {
    guard let feed = inputNumber(MotionPriors.feedMMPerMinute), feed > 0 else {
      return PlotterMotionThroughput.applicationXYFeedMMPerMinute
    }
    return feed
  }

  private func boundaryTravelFeedSelection() -> TravelFeedSelection {
    TravelFeedSelection(
      requestedFeedMMPerMinute: MotionPriors.boundaryFeedMMPerMinute,
      source: .existingFallback
    )
  }

  private func travelFeedSelection(
    for delta: Vector2<MachineSpace>
  ) -> TravelFeedSelection {
    if let ceiling = machineSnapshot?.machine.controllerAxisFeedLimits?
      .applicableFeedCeiling(for: delta)
    {
      return TravelFeedSelection(
        requestedFeedMMPerMinute: ceiling,
        source: .controllerReportedCeiling
      )
    }
    return TravelFeedSelection(
      requestedFeedMMPerMinute: positiveFallbackTravelFeed(),
      source: .existingFallback
    )
  }

  private func sequenceID(for direction: BoundaryDirection) -> DiscoverySequenceID {
    switch direction {
    case .negativeX: .boundaryNegativeX
    case .positiveX: .boundaryPositiveX
    case .negativeY: .boundaryNegativeY
    case .positiveY: .boundaryPositiveY
    }
  }

  private func boundaryDirection(for sequenceID: DiscoverySequenceID) -> BoundaryDirection? {
    switch sequenceID {
    case .boundaryNegativeX: .negativeX
    case .boundaryPositiveX: .positiveX
    case .boundaryNegativeY: .negativeY
    case .boundaryPositiveY: .positiveY
    case .penInteraction: nil
    }
  }

  private func borderValidationActionUnavailableReason(
    for step: BorderValidationStep
  ) -> String? {
    if borderValidationSnapshot.activeOperationID != nil {
      return "The current learning action is still in progress."
    }
    if let reason = learningConnectionAndMotionUnavailableReason { return reason }
    if frameMode == .simulated {
      if observationRuntime == nil { return "The simulator camera composition is unavailable." }
      if simulatedLearningSnapshot?.currentOperation != nil {
        return "Stop or finish the current simulated operation first."
      }
      return nil
    }
    if let reason = retainedPoseApplicabilityRefusal { return reason }
    if step != .compareIntendedAndObservedGeometry,
      machineSnapshot?.machine.penState != .up
    {
      return "The current commanded pen state must be Up."
    }
    switch step {
    case .chooseDrawingBorderPlan, .captureLocalPreFrameBaseline, .revealAndObserveNewInk:
      if !cameraIsLive { return "A current LIVE camera frame is required." }
    case .moveToDrawingBorderStart, .drawDrawingBorder, .compareIntendedAndObservedGeometry:
      break
    }
    if step == .chooseDrawingBorderPlan || step == .moveToDrawingBorderStart
      || step == .drawDrawingBorder,
      machineSnapshot?.machine.position == nil
    {
      return "A current controller MPos is required."
    }
    return nil
  }

  private func recordDrawingBorderPlan() throws -> (
    program: DrawingProgram,
    plan: ExecutionPlanRevision,
    revision: LearningArtifactRevisionID
  ) {
    guard let registration = tipCameraRegistration,
      learningArtifactGraph.currentRevision(for: .tipCameraRegistration)?.id
        == registration.acceptedRevisionID
    else {
      throw LearningPathOperationError.requiredState(
        "A current accepted TipCameraRegistration revision is required."
      )
    }
    let acceptedBoundary = try SparseTipBatchMarkPlan.boundaryEnvelope(
      for: acceptedBoundaryAggregates
    )
    let drawingBorderBounds = try drawingBorderBounds(
      for: registration,
      acceptedBoundary: acceptedBoundary
    )
    let drawingBorder = try DrawingBorderPlan(bounds: drawingBorderBounds)
    let style = try StrokeStyle(
      nominalLineWidth: 0.4,
      penProfileID: PenProfileID(toolAssemblyRevision.rawValue)
    )
    let program = try DrawingProgram(
      id: ProgramID(),
      fieldExtent: drawingBorder.fieldExtent,
      strokes: [
        LogicalStroke(
          id: StrokeID(),
          path: drawingBorder.fieldPath,
          style: style,
          semanticRole: .trainingProbe,
          ordering: 0
        )
      ],
      source: DrawingSourceProvenance(
        kind: "learning-path-drawing-border",
        sourceIdentifier:
          registration.estimatorRevision
            == SparseTipCircularMarkPlan.registrationEstimatorRevision
          ? "accepted-boundary-10mm-inset-drawing-border-v2"
          : "retained-registration-drawing-border-v1"
      )
    )
    let placement = try DrawingPlacement(
      fieldAnchor: try Point2(x: 0, y: 0),
      machineAnchor: drawingBorder.startPosition.point,
      uniformScale: 1,
      rotationRadians: 0
    )
    let plan = try PlotterDrawingPlanningAdapter.planRetainedDrawingBorder(
      program: program,
      placement: placement,
      drawableRegion: try DrawableMachineRegion(bounds: acceptedBoundary),
      provenance: try PlotterDrawingPlanningAdapter.planningProvenance(
        for: registration
      )
    )
    return (program, plan, registration.acceptedRevisionID)
  }

  private func captureLocalPreFrameBaseline() async throws -> (
    frame: DisplayedFrame,
    revealPosition: MachinePosition
  ) {
    guard let registration = tipCameraRegistration,
      let currentRevision = learningArtifactGraph.currentRevision(for: .tipCameraRegistration)?.id,
      currentRevision == registration.acceptedRevisionID,
      borderValidationSnapshot.tipRegistrationRevisionID == currentRevision,
      controllerIsPenUpAndIdle
    else {
      throw LearningPathOperationError.requiredState(
        "A current accepted pen-tip calibration and settled Pen-Up position are required."
      )
    }
    let revealPosition = try await currentSettledMachinePositionForEffect()
    let frame = try await captureProtocolFrame(
      newerThan: displayedFrame?.frame.captureNanoseconds ?? 0
    )
    return (frame, revealPosition)
  }

  private func moveToRecordedDrawingBorderStart() async throws -> (
    position: MachinePosition,
    feed: TravelFeedSelection?
  ) {
    guard let destination = borderValidationSnapshot.drawingBorderPlan?
      .strokes.first?.path.points.first.map(
      MachinePosition.init(point:)
    ) else {
      throw LearningPathOperationError.requiredState("The Drawing Border plan is unavailable.")
    }
    let current = try await currentSettledMachinePositionForEffect()
    var feed: TravelFeedSelection?
    if let delta = try Self.supervisedTravelDelta(from: current, to: destination) {
      feed = travelFeedSelection(for: delta)
      let final = try await performSupervisedPenUpTravel(
        delta: delta,
        ownerID: .borderValidation(.moveToDrawingBorderStart),
        action: .moveToDrawingBorderStart
      )
      guard
        recordProtocolPoseSettlement(
          action: .moveToDrawingBorderStart,
          target: destination,
          actual: final
        )
      else {
        throw LearningPathOperationError.controllerFailed(
          "Move to Drawing Border Start settled at an incompatible MPos."
        )
      }
    }
    return (try await currentSettledMachinePositionForEffect(), feed)
  }

  private func currentMachinePosition() throws -> MachinePosition {
    // Presentation-only projection of the last published lower-owner fact.
    // Motion/evidence effects must use currentSettledMachinePositionForEffect().
    if frameMode == .simulated, let position = simulatedLearningSnapshot?.mpos {
      return try MachinePosition(x: position.xMM, y: position.yMM)
    }
    guard let position = machineSnapshot?.machine.position else {
      throw LearningPathOperationError.requiredState("Current controller MPos is unavailable.")
    }
    return position
  }

  private func currentSettledMachinePositionForEffect() async throws -> MachinePosition {
    if frameMode == .simulated, let snapshot = simulatedLearningSnapshot {
      guard snapshot.session == .connected,
        snapshot.currentOperation == nil,
        snapshot.stickyAmbiguity == nil
      else {
        throw LearningPathOperationError.requiredState(
          "The simulated controller did not publish a current settled MPos."
        )
      }
      return try MachinePosition(x: snapshot.mpos.xMM, y: snapshot.mpos.yMM)
    }
    guard let snapshot = await refreshControllerSessionSnapshot(),
      snapshot.currentOperation == .idle,
      snapshot.machine.connection == .connected,
      snapshot.machine.controllerState == .idle,
      !snapshot.machine.operationInFlight,
      snapshot.machine.stickyAmbiguity == nil,
      let position = snapshot.machine.position
    else {
      throw LearningPathOperationError.requiredState(
        "The controller-session owner did not publish a current settled Idle/MPos."
      )
    }
    return position
  }

  private var controllerIsPenUpAndIdle: Bool {
    if frameMode == .simulated {
      guard let snapshot = simulatedLearningSnapshot else { return false }
      return snapshot.session == .connected
        && snapshot.penPose == .up
        && snapshot.currentOperation == nil
        && snapshot.stickyAmbiguity == nil
    }
    guard let snapshot = machineSnapshot else { return false }
    return snapshot.currentOperation == .idle
      && snapshot.machine.controllerState == .idle
      && snapshot.machine.penState == .up
      && !snapshot.machine.operationInFlight
      && snapshot.machine.stickyAmbiguity == nil
  }

  static func supervisedTravelDelta(
    from current: MachinePosition,
    to target: MachinePosition
  ) throws -> Vector2<MachineSpace>? {
    guard !MachinePositionAcceptancePolicy.accepts(current, target: target) else {
      return nil
    }
    return try Vector2(
      dx: target.point.x - current.point.x,
      dy: target.point.y - current.point.y
    )
  }

  private func recordProtocolPoseSettlement(
    action: LearningMotionAction,
    target: MachinePosition,
    actual: MachinePosition
  ) -> Bool {
    let residual = MachinePositionAcceptancePolicy.residualMM(actual, from: target)
    lastProtocolPoseSettlement = ProtocolPoseSettlement(
      action: action,
      target: target,
      actual: actual,
      residualMM: residual,
      toleranceMM: MachinePositionAcceptancePolicy.toleranceMM,
      controllerSessionID: controllerSessionID,
      coordinateRevision: explorationCoordinateRevision,
      toolPaperRevision: explorationPaperInstanceRevision
    )
    return MachinePositionAcceptancePolicy.accepts(residualMM: residual)
  }

  /// One explicit, finite, Pen-Up exercise travel. This shares the runtime's
  /// capability-bound cancel route but accepts no artifact unless the original
  /// owner naturally completes at its reported final MPos.
  private func performSupervisedPenUpTravel(
    delta: Vector2<MachineSpace>,
    ownerID: LearningPathItemID,
    action: LearningMotionAction
  ) async throws -> MachinePosition {
    computationDiagnostics.record(.supervisedTravel(action, .began))
    defer { computationDiagnostics.record(.supervisedTravel(action, .ended)) }
    return try await executeSupervisedPenUpTravel(
      delta: delta,
      ownerID: ownerID,
      action: action
    )
  }

  private func executeSupervisedPenUpTravel(
    delta: Vector2<MachineSpace>,
    ownerID: LearningPathItemID,
    action: LearningMotionAction
  ) async throws -> MachinePosition {
    guard applicationAdmissionIsOpen, !Task.isCancelled else {
      throw LearningPathOperationError.requiredState(
        "Application shutdown closed admission for supervised Pen-Up travel."
      )
    }
    let isSparseTipBatchTravel =
      ownerID == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    if isSparseTipBatchTravel {
      guard sparseTipPenUpAuthorizationIsCurrent else {
        throw LearningPathOperationError.requiredState(
          "Sparse-tip travel lost its batch-local Pen-Up authorization."
        )
      }
    } else if !(await ensurePenUpForTravel()) {
      throw LearningPathOperationError.requiredState(
        "Supervised travel did not start because Pen Up did not settle."
      )
    }
    let selection = travelFeedSelection(for: delta)
    if frameMode == .simulated {
      let admission = await causalSimulatorEffectAdapter.admitRetainedWorkflowTravel(
        delta: try SimulatedLearningMotionVector(dxMM: delta.dx, dyMM: delta.dy),
        owner: EpisodeAuthorityID(rawValue: "PlotterApplicationRuntime.supervisedPenUpTravel")
      )
      let operation: PlotterCausalSimulatorOperation
      switch admission {
      case let .admitted(value):
        operation = value
      case let .refused(refusal):
        throw LearningPathOperationError.controllerFailed(
          "Simulated supervised Pen-Up travel was refused: \(refusal.refusal)."
        )
      }
      let capabilityID = try supervisedTravelStopCapabilityID(ownerID: ownerID)
      let target = ContextualStopTarget.exerciseMotion(
        capabilityID: capabilityID,
        operationOwner: .simulated(operation),
        ownerID: ownerID,
        action: action
      )
      let owner = Task<PlotterCausalSimulatorOperationOutcome, Never> {
        [causalSimulatorEffectAdapter] in
        await causalSimulatorEffectAdapter.executeNaturally(operation)
      }
      installStoppableOperation(target: target, owner: .simulated(owner))
      defer { clearStoppableOperation(matching: target) }
      try await cancelSparseTipSegmentIfRequested(target: target, owner: .simulated(owner))
      if applicationAdmissionIsClosed || Task.isCancelled {
        _ = latchContextualStopDisposition(
          for: target,
          intent: .shutdown,
          actor: "Application",
          action: "Shutdown"
        )
        await requestSingleJogCancel(for: target, intent: .shutdown)
        simulatedLearningSnapshot = await simulatedLearningRuntime.snapshot()
        throw LearningPathOperationError.requiredState(
          "Application shutdown cancelled supervised Pen-Up travel before execution."
        )
      }
      let outcome = await owner.value
      guard outcome.disposition == .naturallyCompleted else {
        simulatedLearningSnapshot = outcome.truth.runtime
        throw LearningPathOperationError.controllerCancelled(
          "Simulated exercise travel did not complete naturally."
        )
      }
      if !isSparseTipBatchTravel {
        simulatedLearningSnapshot = outcome.truth.runtime
      }
      return try MachinePosition(x: outcome.finalMPos.xMM, y: outcome.finalMPos.yMM)
    }

    guard let machineSession else {
      throw LearningPathOperationError.requiredState("Machine composition is unavailable.")
    }
    let request = RelativeJogRequest(
      delta: delta,
      feedMMPerMinute: selection.requestedFeedMMPerMinute
    )
    let operation: RelativeJogOperation
    switch await PlotterManualMotionComposition.beginNativeRelativeMotion(
      using: machineSession,
      request: request
    ) {
    case .admitted(let admitted):
      operation = admitted
    case .rejected(let outcome):
      throw operationError(for: outcome, action: action.title)
    }
    let capabilityID = try supervisedTravelStopCapabilityID(ownerID: ownerID)
    let target = ContextualStopTarget.exerciseMotion(
      capabilityID: capabilityID,
      operationOwner: .liveOperation(operation.id),
      ownerID: ownerID,
      action: action
    )
    let owner = Task { await operation.outcome() }
    installStoppableOperation(target: target, owner: .motion(owner))
    defer { clearStoppableOperation(matching: target) }
    try await cancelSparseTipSegmentIfRequested(target: target, owner: .motion(owner))
    if applicationAdmissionIsClosed || Task.isCancelled {
      _ = latchContextualStopDisposition(
        for: target,
        intent: .shutdown,
        actor: "Application",
        action: "Shutdown"
      )
      await requestSingleJogCancel(for: target, intent: .shutdown)
      _ = await owner.value
      machineSnapshot = await machineSession.snapshot()
      throw LearningPathOperationError.requiredState(
        "Application shutdown cancelled supervised Pen-Up travel during admission."
      )
    }
    let outcome = await owner.value
    switch outcome {
    case .acceptedThenCompleted(let finalPosition):
      if !isSparseTipBatchTravel {
        machineSnapshot = await machineSession.snapshot()
      }
      return finalPosition
    case .cancelled:
      machineSnapshot = await machineSession.snapshot()
      throw LearningPathOperationError.controllerCancelled(
        "\(action.title) was stopped or cancelled; no arrival artifact was accepted."
      )
    case .ambiguous(let ambiguity):
      machineSnapshot = await machineSession.snapshot()
      throw LearningPathOperationError.controllerAmbiguous(ambiguity.actionableDescription)
    case .refused(let refusal):
      machineSnapshot = await machineSession.snapshot()
      throw LearningPathOperationError.controllerRefused(refusal.actionableDescription)
    }
  }

  private func drawDrawingBorderTrial(
    progress: BorderDrawingEffectProgress
  ) async throws {
    guard let plan = borderValidationSnapshot.drawingBorderPlan,
      let startPoint = plan.strokes.first?.path.points.first
    else {
      throw LearningPathOperationError.requiredState("The Drawing Border plan is unavailable.")
    }
    let start = MachinePosition(point: startPoint)
    let current = try await currentSettledMachinePositionForEffect()
    guard
      recordProtocolPoseSettlement(
        action: .confirmDrawingBorderStart,
        target: start,
        actual: current
      )
    else {
      throw LearningPathOperationError.requiredState(
        "Move to the recorded Drawing Border start before drawing."
      )
    }
    if frameMode == .simulated {
      let lowered = await causalSimulatorEffectAdapter.executeRetainedWorkflowPen(
        .down,
        owner: EpisodeAuthorityID(rawValue: "PlotterApplicationRuntime.drawingBorderTrial")
      )
      applySimulatedCausalImmediateOutcome(
        lowered,
        action: "Lower simulated pen for Drawing Border"
      )
      if let refusal = lowered.refusal { throw refusal }
      progress.strokeState = .possibleInk
      do {
        let points = plan.strokes[0].path.points
        for pair in zip(points, points.dropFirst()) {
          let delta = try pair.0.vector(to: pair.1)
          let admission = await causalSimulatorEffectAdapter.admitRetainedWorkflowDrawing(
            delta: try SimulatedLearningMotionVector(dxMM: delta.dx, dyMM: delta.dy),
            owner: EpisodeAuthorityID(rawValue: "PlotterApplicationRuntime.drawingBorderTrial")
          )
          let operation: PlotterCausalSimulatorOperation
          switch admission {
          case let .admitted(value):
            operation = value
          case let .refused(refusal):
            throw LearningPathOperationError.controllerFailed(
              "Simulated Drawing Border motion was refused: \(refusal.refusal)."
            )
          }
          let target = ContextualStopTarget.borderValidation(
            capabilityID: ContextualStopCapabilityID(),
            operationOwner: .simulated(operation)
          )
          let task = Task { [causalSimulatorEffectAdapter] in
            await causalSimulatorEffectAdapter.executeNaturally(operation)
          }
          installStoppableOperation(target: target, owner: .simulated(task))
          let outcome = await task.value
          clearStoppableOperation(matching: target)
          guard outcome.disposition == .naturallyCompleted else {
            throw LearningPathOperationError.possibleInk(
              "The simulated Drawing Border operation lost a naturally completed segment."
            )
          }
          simulatedLearningSnapshot = outcome.truth.runtime
        }
      } catch {
        let raised = await causalSimulatorEffectAdapter.executeRetainedWorkflowPen(
          .up,
          owner: EpisodeAuthorityID(rawValue: "PlotterApplicationRuntime.drawingBorderTrial")
        )
        applySimulatedCausalImmediateOutcome(
          raised,
          action: "Raise simulated pen after incomplete Drawing Border"
        )
        throw error
      }
      progress.strokeState = .completedNaturally
      let raised = await causalSimulatorEffectAdapter.executeRetainedWorkflowPen(
        .up,
        owner: EpisodeAuthorityID(rawValue: "PlotterApplicationRuntime.drawingBorderTrial")
      )
      applySimulatedCausalImmediateOutcome(
        raised,
        action: "Raise simulated pen after Drawing Border"
      )
      if let refusal = raised.refusal { throw refusal }
      // Aggregate only the causal segments that completed above. This outcome
      // belongs to the SIMULATED session and never becomes live ink evidence.
      let stroke = plan.strokes[0]
      let segmentCount = stroke.path.points.count - 1
      progress.outcome = .completed(
        progress: DrawingPlanProgressSnapshot(
          operationID: DrawingPlanOperationID(), planRevisionID: plan.revisionID,
          plannedStrokeCount: 1, plannedSegmentCount: segmentCount,
          commandedStrokeCount: 1, controllerCompletedStrokeCount: 1,
          submittedSegmentCount: segmentCount, controllerCompletedSegmentCount: segmentCount,
          completedStrokeIDs: [stroke.logicalStrokeID],
          completedCheckpointIDs: [stroke.endingCheckpointID],
          activeStrokeID: nil, activeSegmentIndex: nil
        ),
        finalPosition: try await currentSettledMachinePositionForEffect()
      )
      return
    }
    let operationID = DrawingPlanOperationID()
    let request = try DrawingPlanRequest(
      operationID: operationID,
      plan: plan,
      travelFeedMMPerMinute: PlotterMotionThroughput.applicationXYFeedMMPerMinute,
      drawingFeedMMPerMinute: PlotterMotionThroughput.applicationXYFeedMMPerMinute,
      penActuationProfile: currentPenActuationProfile
    )
    guard let machineSession else {
      throw LearningPathOperationError.requiredState(
        "Native machine composition is unavailable for Drawing Border execution."
      )
    }
    _ = await performSpeechEffect("Drawing the four-edge Drawing Border.")
    let operation: DrawingPlanOperation
    switch await machineSession.beginDrawingPlan(request) {
    case .admitted(let admitted):
      operation = admitted
    case .rejected(let outcome):
      progress.outcome = outcome
      throw LearningPathOperationError.controllerRefused(
        "Drawing Border plan was refused before execution: \(outcome)"
      )
    }
    let target = ContextualStopTarget.borderValidation(
      capabilityID: ContextualStopCapabilityID(),
      operationOwner: .liveOperation(operation.id.rawValue)
    )
    let owner = Task { await operation.outcome() }
    progress.strokeState = .possibleInk
    installStoppableOperation(target: target, owner: .drawingPlan(owner))
    defer { clearStoppableOperation(matching: target) }
    let outcome = await owner.value
    progress.outcome = outcome
    machineSnapshot = await machineSession.snapshot()
    switch outcome {
    case .completed:
      progress.strokeState = .completedNaturally
    case .refused(_, let reason):
      progress.strokeState = .notAdmitted
      throw LearningPathOperationError.controllerRefused(String(describing: reason))
    case .cancelled(_, _, _, _, let penRaiseOutcome):
      throw LearningPathOperationError.possibleInk(
        "Drawing Border operation stopped; controller Pen Up outcome: \(String(describing: penRaiseOutcome))"
      )
    case .ambiguous(_, let reason):
      throw LearningPathOperationError.possibleInk(String(describing: reason))
    case .possibleInk(_, let reason, let penRaiseOutcome):
      throw LearningPathOperationError.possibleInk(
        "Drawing Border operation may contain ink: \(reason); Pen Up: \(String(describing: penRaiseOutcome))"
      )
    }
  }

  private func revealAndObserveTrialInk() async throws -> (
    postFrame: DisplayedFrame,
    region: PixelRect,
    outcome: PlannedDrawingObservationOutcome
  ) {
    guard let baseline = borderValidationSnapshot.localPreFrameBaseline,
      let revealPosition = borderValidationSnapshot.revealPosition,
      let plan = borderValidationSnapshot.drawingBorderPlan,
      let registration = tipCameraRegistration,
      let registrationRevisionID = borderValidationSnapshot.tipRegistrationRevisionID,
      registration.acceptedRevisionID == registrationRevisionID,
      learningArtifactGraph.currentRevision(for: .tipCameraRegistration)?.id
        == registrationRevisionID
    else {
      throw LearningPathOperationError.requiredState(
        "The local baseline, reveal position, Drawing Border plan, and current accepted pen-tip calibration are required."
      )
    }
    let current = try await currentSettledMachinePositionForEffect()
    if !MachinePositionAcceptancePolicy.accepts(current, target: revealPosition) {
      let delta = try Vector2<MachineSpace>(
        dx: revealPosition.point.x - current.point.x,
        dy: revealPosition.point.y - current.point.y
      )
      let final = try await performSupervisedPenUpTravel(
        delta: delta,
        ownerID: .borderValidation(.revealAndObserveNewInk),
        action: .returnToLocalRevealPose
      )
      guard
        recordProtocolPoseSettlement(
          action: .returnToLocalRevealPose,
          target: revealPosition,
          actual: final
        )
      else {
        throw LearningPathOperationError.controllerFailed(
          "Return to the local reveal pose settled at an incompatible MPos."
        )
      }
    }
    let post = try await captureProtocolFrame(newerThan: baseline.frame.captureNanoseconds)
    displayedFrame = post
    // Tip projection uses the shared drawing-containment policy, including
    // field/machine round-trip residue at the closed calibration boundary.
    let intended = try plan.strokes.map { stroke in
      try Polyline(points: stroke.path.points.map { try registration.tipPixel(at: $0) })
    }
    let trialRegion = plannedDrawingObservationRegion(
      intended,
      frameWidth: post.frame.width,
      frameHeight: post.frame.height
    )
    let frames = try DrawingObservationFramePair(
      source: post.source,
      baseline: ExactFrameProvenance(frame: baseline.frame),
      post: ExactFrameProvenance(frame: post.frame)
    )
    guard let observationRuntime else {
      throw LearningPathOperationError.freshFrameUnavailable
    }
    let outcome = try await observePlannedDrawingInk(
      owner: .borderValidation,
      request: PlannedDrawingObservationRequest(
        frames: frames,
        localPreDrawingBaseline: SamePoseFrameSample(
          displayedFrame: baseline,
          controllerPosition: revealPosition
        ),
        postDrawing: SamePoseFrameSample(
          displayedFrame: post,
          controllerPosition: revealPosition
        ),
        region: trialRegion,
        intendedCameraPolylines: intended,
        thresholds: InkPixelThresholds(minimumLuminanceDecrease: 20),
        controllerPositionToleranceMM: MachinePositionAcceptancePolicy.toleranceMM,
        alignmentSearchRadiusPixels:
          FixedCameraOpticalSettlingPolicy.alignmentSearchRadiusPixels,
        maximumAlignmentShiftPixels:
          FixedCameraOpticalSettlingPolicy.maximumAlignmentShiftPixels,
        maximumBackgroundMeanAbsoluteDifference:
          FixedCameraOpticalSettlingPolicy.maximumBackgroundMeanAbsoluteDifference,
        observerRevision: try AlgorithmRevisionEvidence(
          component: "planned-drawing-border-observer",
          revision: VisionWorker.plannedDrawingObserverRevision
        ),
        additionalAlgorithmRevisions: [
          try AlgorithmRevisionEvidence(
            component: "drawing-border-plan-runner",
            revision: "accepted-boundary-10mm-inset-border-v1"
          )
        ]
      ),
      using: observationRuntime
    )
    switch outcome {
    case .observed(let observation):
      overlayResultChannels.publishWorkflow(
        OverlayChannelResult(displayedFrame: post, overlays: observation.overlays),
        source: frameMode,
        owner: .borderValidation
      )
      return (
        post,
        trialRegion,
        .observed(observation)
      )
    case .rejected(let rejection):
      overlayResultChannels.clearWorkflow(source: frameMode, owner: .borderValidation)
      if rejection.reason == .computationCancelled { throw CancellationError() }
      return (post, trialRegion, .rejected(rejection))
    }
  }

  private func clearAutomaticVisionPresentation() {
    visionAnalysisSnapshot = .stopped
    videoVisionDiagnostics = nil
    visionError = nil
    lastSceneMeasurement = nil
  }

  private func beginApplicationEffect() -> PlotterApplicationEffectLease? {
    guard applicationAdmissionIsOpen else { return nil }
    let lease = PlotterApplicationEffectLease(id: UUID())
    admittedApplicationEffects.insert(lease.id)
    return lease
  }

  private func settleApplicationEffect(_ lease: PlotterApplicationEffectLease) {
    precondition(admittedApplicationEffects.remove(lease.id) != nil)
    guard admittedApplicationEffects.count == 0 else { return }
    let waiters = applicationEffectSettlementWaiters
    applicationEffectSettlementWaiters.removeAll(keepingCapacity: false)
    for waiter in waiters { waiter.resume() }
  }

  private func applicationEffectCanCommit(_ lease: PlotterApplicationEffectLease) -> Bool {
    applicationAdmissionIsOpen && admittedApplicationEffects.contains(lease.id)
  }

  private func awaitApplicationEffectsSettlement() async {
    guard admittedApplicationEffects.count > 0 else { return }
    await withCheckedContinuation { continuation in
      applicationEffectSettlementWaiters.append(continuation)
    }
  }

  private func inputNumber(_ text: String) -> Double? {
    guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)),
      value.isFinite
    else { return nil }
    return value
  }

  private func actionableDescription(_ error: any Error) -> String {
    if let cameraError = error as? CameraCaptureError {
      return cameraError.actionableDescription
    }
    if let localized = error as? LocalizedError,
      let description = localized.errorDescription
    {
      return description
    }
    return String(describing: error)
  }

  private func workflowFailure(for error: any Error) -> WorkflowFailure {
    let detail = actionableDescription(error)
    guard let operationError = error as? LearningPathOperationError else {
      return WorkflowFailure(kind: .failed, detail: detail, recovery: .resolveNamedFailure)
    }
    switch operationError {
    case .controllerRefused:
      return WorkflowFailure(kind: .refused, detail: detail, recovery: .resolveNamedFailure)
    case .controllerCancelled:
      return WorkflowFailure(kind: .cancelled, detail: detail, recovery: .none)
    case .controllerAmbiguous:
      return WorkflowFailure(kind: .ambiguous, detail: detail, recovery: .resolveNamedFailure)
    case .possibleInk:
      return WorkflowFailure(kind: .possibleInk, detail: detail, recovery: .resolveNamedFailure)
    case .inkRejected:
      return WorkflowFailure(kind: .unclear, detail: detail, recovery: .resolveNamedFailure)
    case .freshFrameUnavailable, .controllerFailed, .controllerContextChanged, .requiredState:
      return WorkflowFailure(kind: .failed, detail: detail, recovery: .resolveNamedFailure)
    }
  }

  private func operationError(
    for outcome: MotionOutcome,
    action: String
  ) -> LearningPathOperationError {
    switch outcome {
    case .refused(let refusal): .controllerRefused(refusal.actionableDescription)
    case .ambiguous(let ambiguity): .controllerAmbiguous(ambiguity.actionableDescription)
    case .cancelled:
      .controllerCancelled(
        "\(action) was stopped or cancelled before an arrival artifact could be accepted.")
    case .acceptedThenCompleted:
      .controllerFailed(
        "\(action) completed before its active-operation handle was returned.")
    }
  }

  private func operationError(
    for outcome: DrawingStrokeOutcome,
    possibleInk: Bool
  ) -> LearningPathOperationError {
    switch outcome {
    case .refused(let refusal): .controllerRefused(String(describing: refusal))
    case .ambiguous(let ambiguity):
      possibleInk
        ? .possibleInk(ambiguity.actionableDescription)
        : .controllerAmbiguous(ambiguity.actionableDescription)
    case .cancelled(_, let penRaiseOutcome):
      possibleInk
        ? .possibleInk("Drawing was cancelled; Pen Up outcome: \(penRaiseOutcome)")
        : .controllerCancelled("Drawing was cancelled before contact authority existed.")
    case .completed:
      .controllerFailed("Drawing completed before its active-operation handle was returned.")
    }
  }

  private func operationError(
    for outcome: PenOutcome,
    possibleInk: Bool
  ) -> LearningPathOperationError {
    switch outcome {
    case .refused(let refusal): .controllerRefused(String(describing: refusal))
    case .ambiguous(let ambiguity):
      possibleInk
        ? .possibleInk(ambiguity.actionableDescription)
        : .controllerAmbiguous(ambiguity.actionableDescription)
    case .commandedAndSettled:
      .controllerFailed("A settled Pen outcome reached a failure-only conversion path.")
    }
  }

  private func recordWorkflowTelemetry(_ event: WorkflowTelemetryEvent) async {
    await residualEffectPort.recordWorkflowTelemetry(event)
  }

  private func nowNanoseconds() -> UInt64 {
    residualEffectPort.nowNanoseconds()
  }

}

extension PlotterApplicationRuntime {
  func execute(_ request: PlotterArtifactResetEffectRequest) async
    -> PlotterArtifactResetEffectResult
  {
    await executeArtifactResetEffect(request)
  }

  func persist(_ request: PlotterArtifactResetPersistenceRequest) async
    -> PlotterArtifactResetPersistenceResult
  {
    await persistArtifactReset(request)
  }

  func execute(
    _ request: PlotterBorderValidationEffectRequest
  ) async -> PlotterBorderValidationEffectResult {
    do {
      switch request {
      case .runStep(_, let step):
        return try await executeBorderValidationStep(step)
      case .acceptComparison(_, let assessment):
        let histories = try assessment == .predictionObserved
          ? commitComparisonAttemptAndArtifact(assessment)
          : recordComparisonAttempt(assessment: assessment, disposition: .succeeded)
        await persistCompletedPictureFrameEvidence()
        return .completed(.comparisonAccepted(assessment, histories: histories))
      case .rejectComparison(_, let reason):
        let histories = try recordComparisonAttempt(
          assessment: nil,
          disposition: .failed("Operator rejected Border validation: \(reason)")
        )
        return .completed(.comparisonRejected(reason, histories: histories))
      }
    } catch is CancellationError {
      return .cancelled("Border validation was cancelled.")
    } catch let error as LearningPathOperationError {
      return .failed(workflowFailure(for: error).detail)
    } catch {
      return .failed(actionableDescription(error))
    }
  }

  private func executeBorderValidationStep(
    _ step: BorderValidationStep
  ) async throws -> PlotterBorderValidationEffectResult {
    switch step {
    case .chooseDrawingBorderPlan:
      let planned = try recordDrawingBorderPlan()
      try commitDrawingArtifact(for: step)
      return .completed(.planned(
        program: planned.program,
        plan: planned.plan,
        revision: planned.revision
      ))
    case .captureLocalPreFrameBaseline:
      let baseline = try await captureLocalPreFrameBaseline()
      try commitDrawingArtifact(for: step)
      return .completed(.baselineCaptured(
        baseline.frame,
        revealPosition: baseline.revealPosition
      ))
    case .moveToDrawingBorderStart:
      let movement = try await moveToRecordedDrawingBorderStart()
      return .completed(.movedToStart(movement.position, feed: movement.feed))
    case .drawDrawingBorder:
      let priorOutcome = borderValidationSnapshot.drawingOutcome
      let progress = BorderDrawingEffectProgress()
      do {
        try await drawDrawingBorderTrial(progress: progress)
        try commitDrawingArtifact(for: step)
        return .completed(.borderExecuted(progress.outcome))
      } catch {
        if progress.outcome != priorOutcome || progress.strokeState != .notAdmitted {
          var commitFailure: String?
          if progress.strokeState == .completedNaturally {
            do {
              try commitDrawingArtifact(for: .drawDrawingBorder)
            } catch {
              commitFailure = String(describing: error)
            }
          }
          let base =
            "Drawing Border execution produced controller evidence, so physical ink may exist. Drawing will not restart; Resume Border Validation Observation will return Pen Up and inspect the existing camera frame."
          let detail =
            commitFailure.map {
              "\(base) The frame-execution artifact also needs attention: \($0)"
            } ?? "\(base) Post-stroke settlement needs attention: \(error)"
          return .completed(.possibleInk(detail, outcome: progress.outcome))
        }
        throw error
      }
    case .revealAndObserveNewInk:
      let observation = try await revealAndObserveTrialInk()
      switch observation.outcome {
      case .observed(let measured):
        try commitDrawingArtifact(for: step)
        return .completed(.observedInk(
          postFrame: observation.postFrame, region: observation.region,
          observation: measured, inkStatus: measured.diagnosticSummary
        ))
      case .rejected(let rejection):
        if case .completed = borderValidationSnapshot.drawingOutcome {
          return .completed(.observationUnclear(
            postFrame: observation.postFrame, region: observation.region, rejection: rejection
          ))
        }
        throw LearningPathOperationError.inkRejected(rejection.diagnosticSummary)
      }
    case .compareIntendedAndObservedGeometry:
      return .completed(.comparisonAccepted(
        .predictionObserved,
        histories: borderValidationSnapshot.comparisonAttemptHistories
      ))
    }
  }
}

extension PlotterApplicationRuntime {
  func executeArtifactResetEffect(
    _ request: PlotterArtifactResetEffectRequest
  ) async -> PlotterArtifactResetEffectResult {
    do {
      switch request {
      case .compareSavedLearning(_, let checkpoint):
        let message: String
        guard let reference = checkpoint.referenceFrame else {
          return .completed(.savedLearningCompared(
            checkpoint,
            opticalComparison: "Unavailable: this legacy saved package has no bounded reference frame. Inspect the projected overlays and decide manually."
          ))
        }
        guard let frame = displayedFrame else {
          return .completed(.savedLearningCompared(
            checkpoint,
            opticalComparison: "Unavailable: no current camera frame exists. Inspect overlays and decide manually."
          ))
        }
        do {
          let optical = try exactTipCalibrationFrame(frame).opticalConfiguration
          let comparison = await Task.detached {
            reference.compare(with: frame, opticalConfiguration: optical)
          }.value
          switch comparison {
          case .compared(let alignment):
            message = String(
              format: "Current frame versus saved reference: shift x=%d px, y=%d px; background mean absolute difference %.3f across %d evaluated pixels. This is advisory, not a pass/fail gate.",
              alignment.shiftX,
              alignment.shiftY,
              alignment.backgroundMeanAbsoluteDifference,
              alignment.evaluatedPixelCount
            )
          case .unavailable(let reason):
            message = "Unavailable for this frame (\(reason.rawValue)). Inspect the compatible projected overlays and decide manually."
          }
        } catch {
          message = "Unavailable: current camera identity could not be evaluated (\(error)). Inspect overlays and decide manually."
        }
        return .completed(.savedLearningCompared(checkpoint, opticalComparison: message))

      case .applySavedLearning(_, let checkpoint, _, let environment):
        guard environment == .live,
          savedLearningState.applicationCandidate?.checkpoint.checkpointID == checkpoint.checkpointID
        else { return .refused("The Saved Learning candidate changed before application.") }
        let applied = try await applySavedLearningEffect()
        return .completed(.savedLearningApplied(applied.0, opticalComparison: applied.1))

      case .retainSavedLearning(_, let checkpoint):
        guard savedLearningState.applicationCandidate?.checkpoint.checkpointID == checkpoint.checkpointID else {
          return .refused("The Saved Learning candidate changed before retention.")
        }
        return .completed(.savedLearningRetained(try retainSavedLearningEffect()))

      case .rejectSavedLearning(_, let reason):
        acceptedArtifactCheckpointStatus = .rejected(reason)
        learningAuthorityError = nil
        explorationError = nil
        return .completed(.savedLearningRejected(reason))

      case .redoStep(_, let stepID):
        guard let owner = artifactResetOwner(stepID) else {
          return .refused("The requested Learning step no longer exists.")
        }
        await startExercise(owner, mode: .replacement)
        return .completed(.replacementAttemptPrepared(stepID))

      case .recordAnotherAttempt(_, let stepID):
        guard let owner = artifactResetOwner(stepID) else {
          return .refused("The requested Learning step no longer exists.")
        }
        await startExercise(owner, mode: .additional)
        return .completed(.additionalAttemptPrepared(stepID))

      case .settleForPaperReplacement(_, let plan):
        guard paperReplacementIsFresh(plan) else {
          return .refused("Paper identity changed while replacement was being prepared.")
        }
        let snapshot = await drawingRunRuntime.snapshot(environment: manualMotionEnvironment)
        guard !drawingRunIsActive else {
          return .refused(
            "Paper identity cannot change until the current drawing run and evidence capture settle."
          )
        }
        switch snapshot.evidencePersistence {
        case .appending, .failed, .intentPublicationIncomplete:
          return .refused("Drawing Run evidence must settle before changing paper identity.")
        case .none, .persisted:
          break
        }
        return .completed(.paperReplacementSettled(plan))

      case .applyInMemoryPaperReplacement(_, let plan):
        guard paperReplacementIsFresh(plan) else {
          return .failed("Paper identity changed after durable replacement was committed.")
        }
        // Coverage removal changes the current plan identity. Obtain the
        // owner's synchronized reference before its exact terminal handoff,
        // including when shutdown has already stopped ambient projections.
        let drawingSnapshot = await drawingRunRuntime.synchronize(environment: manualMotionEnvironment)
        guard !drawingRunIsActive else {
          return .failed("Drawing Run became active before paper replacement could be projected.")
        }
        if let terminal = drawingSnapshot.terminal {
          let result = await drawingRunRuntime.submit(
            PlotterDrawingRunSubmission(
              projection: drawingSnapshot.projection,
              intent: .beginNewRun(terminal.runID)
            )
          )
          guard case .applied = result.disposition else {
            let detail = result.snapshot.lastRefusal.map(drawingRunRefusalDetail)
              ?? "Resolve Drawing Run evidence publication before changing paper identity."
            return .failed(detail)
          }
          installDrawingRunSnapshot(result.snapshot)
        }
        let transition = plan.paperReplacement
        let contactPlaneChanged = transition?.tipCalibrationApplicabilityChange != nil
        if plan.sourceIsSimulated {
          let replacementSnapshot = try await simulatedLearningRuntime.recordPaperReplaced().result.get()
          simulatedLearningSnapshot = replacementSnapshot
          explorationPaperInstanceRevision = replacementSnapshot.toolPaperRevision
        } else if let transition {
          explorationPaperInstanceRevision = transition.current.instance.rawValue
          explorationPaperContactPlaneRevision = transition.current.contactPlane.rawValue
        } else {
          return .failed("LIVE paper replacement is missing its immutable paper transition.")
        }
        if case .available = drawingSnapshot.evidenceArchiveAvailability {
          // The Run owner indexes possible ink by the complete paper identity.
          // Rebuild that index from immutable records for the new sheet; merely
          // clearing its terminal does not retire the old sheet's blocked plans.
          let restored = await drawingRunRuntime.restoreNoRedrawTruth(
            from: drawingEvidenceArchive, paper: currentPaperRevisionContext,
            environment: manualMotionEnvironment)
          installDrawingRunSnapshot(restored)
        }
        if let owner = activeExerciseAttemptOwnerID,
          owner != .humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
        {
          finishActiveExerciseAttempt(disposition: .cancelled)
        }
        if contactPlaneChanged {
          var graph = learningArtifactGraph
          let invalidation = graph.invalidateCurrentRevisions(rootKinds: [.tipCameraRegistration])
          learningArtifactGraph = graph
          applyArtifactInvalidations(invalidation.allInvalidatedRevisionIDs)
          tipCameraRegistration = nil
          proposedTipCameraRegistration = nil
        }
        if contactPlaneChanged {
          resetTipCalibrationRuntimeForCurrentPaper()
          activeStageFourCheckpoint = nil
        } else {
          tipCalibrationRuntime.clearPaperTransients(currentPaperRevisionContext.instance)
        }
        proposedTipCameraRegistration = nil
        frozenPointSelectionFrame = nil
        pendingToolContactEvidence = []
        pendingToolContactClickFrame = nil
        await cancelPointSelectionRequest()
        let priorAssessment = borderValidationSnapshot.assessment
        clearDrawingLearningForRewind(from: .chooseDrawingBorderPlan)
        if !contactPlaneChanged, let priorAssessment {
          _ = borderValidationRuntime.apply(.restoreAcceptedAssessment(priorAssessment))
        }
        if !plan.sourceIsSimulated, let actions = activeStatePersistencePort {
          let checkpoint: AcceptedLearningPathCheckpoint?
          if case .loaded(let loaded) = actions.loadAcceptedLearningPathCheckpoint() {
            checkpoint = loaded
          } else { checkpoint = nil }
          artifactResetRuntime.installPaperReplacementCheckpoint(checkpoint, plan: plan)
        }
        overlayResultChannels.clearWorkflow(source: frameMode, owner: .drawingStudio)
        overlayResultChannels.clearWorkflow(source: frameMode, owner: .sparseTipCalibration)
        await synchronizeDrawingRunProjection()
        await synchronizeDrawingDraft()
        let newPlan = await drawingDraftRuntime.submit(
          PlotterDrawingDraftSubmission(projection: drawingDraftSnapshot.projection, intent: .beginNewPlan),
          facts: drawingDraftExternalFacts)
        installDrawingDraftSnapshot(newPlan.snapshot)
        guard case .applied = newPlan.disposition else {
          return .failed("Paper was recorded, but the settled Drawing Run could not prepare its next plan. Review New Drawing.")
        }
        await synchronizeDrawingRunProjection()
        learningAuthorityError = nil
        explorationError = nil
        return .completed(.inMemoryPaperReplacementApplied(plan))

      case .settleForReset(_, let runtimePlan):
        guard let plan = admittedLearningVacatePlan(runtimePlan) else {
          return .refused("The admitted Learning reset transaction is invalid.")
        }
        if plan.scope == .all, !(await cancelAndSettleLearningForReset()) {
          return .failed(learningAuthorityError ?? "Learning-owned work did not settle.")
        }
        return .completed(.resetSettled(runtimePlan))

      case .applyInMemoryReset(_, let runtimePlan):
        guard let plan = admittedLearningVacatePlan(runtimePlan) else {
          return .failed("The persisted Learning reset transaction could not be projected.")
        }
        guard await applyLearningVacateEffect(plan) else {
          return .failed(learningAuthorityError ?? "Learning reset projection failed.")
        }
        return .completed(.inMemoryResetApplied(runtimePlan))
      }
    } catch is CancellationError {
      return .cancelled("Artifact/reset effect was cancelled.")
    } catch {
      return .failed(actionableDescription(error))
    }
  }

  func persistArtifactReset(
    _ request: PlotterArtifactResetPersistenceRequest
  ) async -> PlotterArtifactResetPersistenceResult {
    switch request {
    case .persistPaperReplacement(_, let plan):
      guard paperReplacementIsFresh(plan) else {
        return .refused("Paper identity changed while replacement was being persisted.")
      }
      guard plan.sourceIsSimulated == (frameMode == .simulated) else {
        return .refused("Paper replacement source no longer matches the active workspace.")
      }
      guard !plan.sourceIsSimulated else {
        let cleared = await drawingDraftRuntime.clearPaperCoverageForRetainedPaperLifecycle(
          facts: drawingDraftExternalFacts)
        guard case .applied = cleared.disposition else {
          return .failed("Sheet coverage cleanup did not settle; paper identity was retained.")
        }
        installDrawingDraftSnapshot(cleared.snapshot)
        return .completed(.paperReplacementPersisted(plan))
      }
      guard let transition = plan.paperReplacement,
        let actions = activeStatePersistencePort
      else {
        return .failed("LIVE paper replacement requires durable identity and checkpoint authority.")
      }
      func restorePreviousPaperAuthority() throws {
        try actions.persistPaperRevisionContext(transition.previous)
        if let previous = plan.previousAcceptedCheckpoint {
          try actions.saveAcceptedLearningPathCheckpoint(previous)
        } else { try actions.clearAcceptedLearningPathCheckpoint() }
      }
      do {
        try actions.persistPaperRevisionContext(transition.current)
      } catch {
        do { try restorePreviousPaperAuthority() }
        catch {
          return .failed("Paper identity durable write/read-back failed and rollback failed: \(actionableDescription(error))")
        }
        return .failed("Paper identity durable write/read-back failed; previous authority was restored: \(actionableDescription(error))")
      }
      do {
        if learningArtifactGraph.revisions.isEmpty {
          // An absent in-memory graph cannot support a replacement checkpoint;
          // clear any old-paper package rather than retain stale durable
          // authority across the committed paper identity.
          try actions.clearAcceptedLearningPathCheckpoint()
        } else {
          try actions.saveAcceptedLearningPathCheckpoint(
            try paperReplacementCheckpoint(for: transition)
          )
        }
      } catch {
        do {
          try restorePreviousPaperAuthority()
        } catch {
          return .failed(
            "Canonical checkpoint save failed and paper identity rollback failed: \(actionableDescription(error))"
          )
        }
        return .failed("Canonical checkpoint save failed; paper identity was rolled back: \(actionableDescription(error))")
      }
      let cleared = await drawingDraftRuntime.clearPaperCoverageForRetainedPaperLifecycle(
        facts: drawingDraftExternalFacts)
      guard case .applied = cleared.disposition else {
        do {
          try restorePreviousPaperAuthority()
        } catch {
          return .failed("Sheet coverage cleanup failed and durable paper rollback failed: \(actionableDescription(error))")
        }
        return .failed("Sheet coverage persistence failed; paper identity and accepted Learning were rolled back. Retry New Sheet after resolving paper persistence.")
      }
      installDrawingDraftSnapshot(cleared.snapshot)
      return .completed(.paperReplacementPersisted(plan))

    case .persistReset(_, let runtimePlan):
      guard let plan = admittedLearningVacatePlan(runtimePlan) else {
        return .refused("The admitted Learning reset transaction is invalid.")
      }
      let freshPlan: LearningVacatePlan? = switch plan.scope {
      case .from: learningVacatePlan(from: plan.anchor)
      case .all: resetAllLearningPlan
      }
      guard freshPlan == plan else {
        return .refused(
          "Learning changed while the reset summary was open. Review it and try again."
        )
      }
      let invalidatesBoundary: Bool = switch plan.anchor {
      case .humanGuidedDiscovery(.penInteraction),
        .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering): true
      default: false
      }
      let capability: PlotterBoundaryResetCapabilityID?
      if invalidatesBoundary {
        guard let reserved = await reserveBoundaryResetBeforePersistence() else {
          return .failed(learningAuthorityError ?? "Boundary reset reservation failed.")
        }
        capability = reserved
      } else {
        capability = nil
      }
      if let proposal = runtimePlan.axisCalibration {
        guard proposal == axisCalibrationProposal,
          runtimePlan.expectedControllerSessionID == controllerSessionID,
          plan.anchor == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
          !runtimePlan.sourceIsSimulated else {
          if let capability { await abortBoundaryResetAfterPersistenceRefusal(capability) }
          return .refused("The measured geometry transition changed before persistence.")
        }
      }
      guard let prefix = persistLearningPathPrefixBeforeVacate(plan,
        axisCalibration: runtimePlan.axisCalibration) else {
        if let capability { await abortBoundaryResetAfterPersistenceRefusal(capability) }
        return .failed(learningAuthorityError ?? "Durable Learning prefix update failed.")
      }
      if let capability, !(await commitBoundaryResetBeforeLocalCleanup(capability)) {
        return .failed(learningAuthorityError ?? "Boundary reset publication failed.")
      }
      let state: PlotterArtifactResetSavedLearningState = switch prefix {
      case .unchanged: artifactResetRuntime.snapshot().savedLearning
      case .cleared: .absent
      case .saved(let checkpoint):
        .applied(checkpoint, opticalComparison: "Saved from the current accepted Learning prefix.")
      }
      return .completed(.resetPersisted(runtimePlan, savedLearning: state))
    }
  }

  private func paperReplacementIsFresh(_ plan: PlotterArtifactResetPlan) -> Bool {
    guard plan.sourceIsSimulated == (frameMode == .simulated),
      plan.expectedControllerSessionID == controllerSessionID,
      plan.expectedAcceptedAttemptSequence == acceptedAttemptSequence,
      plan.expectedCurrentRevisionIDs == Set(learningArtifactGraph.revisions.filter { $0.state == .current }.map(\.id))
    else { return false }
    guard !plan.sourceIsSimulated else { return plan.paperReplacement == nil }
    guard let transition = plan.paperReplacement else { return false }
    return transition.previous == currentPaperRevisionContext
  }

  private func paperReplacementCheckpoint(
    for transition: PaperReplacementTransition
  ) throws -> AcceptedLearningPathCheckpoint {
    let semanticIdentity = LearningPathSemanticIdentity(
      machineGeometry: machineGeometryIdentity,
      toolAssembly: toolAssemblyRevision,
      penContactProfile: penContactProfileRevision,
      paperInstance: transition.current.instance,
      paperContactPlane: transition.current.contactPlane,
      cameraMountRevision: cameraMountRevision,
      cameraReframingRevision: cameraReframingRevision
    )
    let changedPlane = transition.tipCalibrationApplicabilityChange != nil
    return try AcceptedLearningPathCheckpoint(
      semanticIdentity: semanticIdentity,
      penInteraction: currentAcceptedPenInteractionCheckpoint(),
      machineArtifacts: activeMachineArtifactCheckpoint,
      machineCamera: currentAcceptedMachineCameraCheckpoint() ?? activeMachineCameraCheckpoint,
      tipCalibration: changedPlane ? nil : acceptedLearningPathCheckpoint?.tipCalibration
        ?? recoverableTipCalibrationCheckpoint,
      stageFour: changedPlane ? nil : activeStageFourCheckpoint,
      penCapAppearance: try livePenCapAppearanceSelection?.acceptedCheckpoint()
        ?? acceptedLearningPathCheckpoint?.penCapAppearance,
      referenceFrame: currentAcceptedLearningReferenceFrame()
        ?? acceptedLearningPathCheckpoint?.referenceFrame
    )
  }

  private func artifactResetPlan(_ plan: LearningVacatePlan,
    axisCalibration: ControllerAxisCalibrationProposal? = nil) -> PlotterArtifactResetPlan {
    PlotterArtifactResetPlan(
      id: plan.id,
      anchorStepID: PlotterArtifactResetStepID(rawValue: plan.anchor.number),
      affectedStepIDs: plan.affectedItems.map {
        PlotterArtifactResetStepID(rawValue: $0.number)
      },
      expectedCurrentRevisionIDs: plan.expectedCurrentRevisionIDs,
      expectedAcceptedAttemptSequence: plan.expectedAcceptedAttemptSequence,
      sourceIsSimulated: plan.source == .simulated,
      resetAll: plan.scope == .all,
      removesDurableMachineCheckpoint: plan.removesDurableMachineCheckpoint,
      removesDurableTipCheckpoint: plan.removesDurableTipCheckpoint,
      physicalInkMayRemain: plan.physicalInkMayRemain,
      expectedControllerSessionID: axisCalibration == nil ? nil : controllerSessionID,
      axisCalibration: axisCalibration
    )
  }

  private func admittedLearningVacatePlan(
    _ runtimePlan: PlotterArtifactResetPlan
  ) -> LearningVacatePlan? {
    guard let anchorStepID = runtimePlan.anchorStepID,
      let anchor = LearningPathItemID.learningExerciseOrder.first(where: {
        $0.number == anchorStepID.rawValue
      })
    else { return nil }
    let affectedItems = runtimePlan.affectedStepIDs.compactMap { stepID in
      LearningPathItemID.learningExerciseOrder.first { $0.number == stepID.rawValue }
    }
    guard affectedItems.count == runtimePlan.affectedStepIDs.count else { return nil }
    let source: LearningVacateSource = runtimePlan.sourceIsSimulated ? .simulated : .live
    let scope: LearningVacateScope = runtimePlan.resetAll ? .all : .from(anchor)
    let plan = LearningVacatePlan(
      scope: scope,
      source: source,
      anchor: anchor,
      affectedItems: affectedItems,
      expectedCurrentRevisionIDs: runtimePlan.expectedCurrentRevisionIDs,
      expectedAcceptedAttemptSequence: runtimePlan.expectedAcceptedAttemptSequence,
      removesDurableMachineCheckpoint: runtimePlan.removesDurableMachineCheckpoint,
      removesDurableTipCheckpoint: runtimePlan.removesDurableTipCheckpoint,
      physicalInkMayRemain: runtimePlan.physicalInkMayRemain
    )
    return plan.id == runtimePlan.id ? plan : nil
  }

  private func artifactResetOwner(_ id: PlotterArtifactResetStepID) -> LearningPathItemID? {
    LearningPathItemID.learningExerciseOrder.first { $0.number == id.rawValue }
  }
}

extension PlotterApplicationRuntime: PlotterTipCalibrationEffectPort {
  func execute(
    _ request: PlotterTipCalibrationEffectRequest
  ) async -> PlotterTipCalibrationEffectResult {
    do {
      switch request {
      case .runFourMarkBatch:
        return .completed(.markBatch(try await drawSparseTipCircles()))
      case .captureNewClickFrame(_, let expectedSelection):
        return .completed(.clickFrameReplaced(
          try await captureNewSparseTipClickFrame(
            expectedSelection: expectedSelection
          )
        ))
      case .fitProposal(_, let batch):
        return .completed(.proposal(try acceptSparseTipBatchClicks(batch: batch)))
      case .revalidateCheckpoint:
        return .completed(.revalidated(try await revalidateTipCalibration()))
      case .commitProposal(_, let isRetry):
        return .completed(.committed(try commitTipCalibration(
          actor: isRetry ? "operator-retry" : "operator-accepted-proposal"
        )))
      case .rejectProposal:
        await rejectTipCalibration()
        return .completed(.proposalRejected)
      }
    } catch let error as TipCalibrationPossibleInkEffectError {
      return .completed(.possibleInk(error.fact))
    } catch is CancellationError {
      return .cancelled
    } catch let error as LearningPathOperationError {
      let failure = workflowFailure(for: error)
      if failure.kind == .possibleInk || failure.kind == .ambiguous,
        let location = retainedStopRegistration?.possibleInkLocation
      {
        return .completed(.possibleInk(PlotterTipCalibrationPossibleInkFact(
          location: location,
          reason: failure.detail,
          persistenceEvidenceID: location.persistenceEvidenceID
        )))
      }
      return .failed(failure.detail)
    } catch {
      return .failed(actionableDescription(error))
    }
  }
}

private struct TipCalibrationPossibleInkEffectError: Error {
  let fact: PlotterTipCalibrationPossibleInkFact
  let underlying: any Error
}

private struct TipCalibrationEffectOutcomeError: Error, CustomStringConvertible {
  let outcome: PlotterTipCalibrationSubmissionOutcome
  var description: String { String(describing: outcome) }
}

private extension BlacklistedToolContactLocation {
  var persistenceEvidenceID: String {
    "\(paperInstance.rawValue.uuidString.lowercased())-\(calibrationPosition.rawValue)"
  }
}

extension Array {
  fileprivate var onlyElement: Element? { count == 1 ? self[0] : nil }
}

func machineBlockerLabel(_ blocker: MachineBlocker) -> String {
  switch blocker {
  case .noSerialDevice: "No serial device is selected."
  case .multipleSerialDevices(let devices): "Select one of \(devices.count) serial devices."
  case .transport(let reason): "Controller transport: \(reason)"
  case .timeout(let query): "Controller timed out during \(query.rawValue)."
  case .invalidReply(let query, let reason): "Invalid \(query.rawValue) reply: \(reason)"
  case .responseLimitExceeded(let query, let maximumBytes, let maximumChunks):
    "\(query.rawValue) exceeded \(maximumBytes) bytes or \(maximumChunks) chunks."
  case .controllerAlarm(let code): "Controller alarm: \(code)"
  case .controllerError(let code): "Controller error: \(code)"
  }
}

extension PlotterApplicationRuntime {
  private var axisMetricSourceCheckpoint: AcceptedLearningPathCheckpoint? {
    if let checkpoint = savedLearningState.checkpoint, let stage = checkpoint.stageFour,
      drawingEvidenceArchive.records.contains(where: { $0.recordID == stage.recordID }) {
      return checkpoint
    }
    return drawingEvidenceArchive.axisMetricMeasurements.last?.sourceCheckpoint
  }

  var axisMetricFrame: LearningFrameMetricGeometry? {
    guard let recordID = axisMetricSourceCheckpoint?.stageFour?.recordID,
      let record = drawingEvidenceArchive.records.first(where: { $0.recordID == recordID }) else { return nil }
    return try? LearningFrameMetricGeometry.extract(record: record)
  }

  var latestAxisMetricMeasurement: ControllerAxisMetricMeasurement? {
    guard let frame = axisMetricFrame else { return nil }
    return drawingEvidenceArchive.axisMetricMeasurements.last { $0.geometry == frame }
  }

  var axisMetricApplyUnavailableReason: String? {
    if axisCalibrationInProgress { return "Axis calibration is in progress." }
    guard activeStatePersistencePort != nil else { return "Durable Learning identity persistence is unavailable." }
    if let error = axisMetricRecoveryError { return error }
    if pendingAxisCalibrationTerminal != nil { return "Retain the pending terminal evidence before another calibration." }
    guard frameMode == .live, let proposal = axisCalibrationProposal,
      let measurement = latestAxisMetricMeasurement, proposal.validates(measurement: measurement) else {
      return "Save confirmed measurements for both directions of both axes to review a calibration."
    }
    guard proposal.oldMachineGeometry == machineGeometryIdentity,
      measurement.sourceCheckpoint.semanticIdentity == currentLearningPathSemanticIdentity,
      activeStageFourCheckpoint?.recordID == measurement.geometry.recordID,
      tipCameraRegistration == measurement.sourceCheckpoint.tipCalibration?.registration else {
      return "Apply the exact Learning package associated with this measured frame, or measure the current frame."
    }
    guard !drawingEvidenceArchive.axisCalibrationAttempts.contains(where: { $0.proposal.proposalID == proposal.proposalID }) else {
      return "This calibration was already attempted. Its receipt cannot replay settings."
    }
    if let reason = artifactResetUnavailableReason { return reason }
    guard activeExerciseAttemptID == nil, activeDiscoverySequenceID == nil,
      learningVacatePlan(from: .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)) != nil else {
      return "Finish the active Learning action before applying axis calibration."
    }
    return PlotterControllerSessionRules.refusal(for: .applyAxisCalibration(proposalID: proposal.proposalID),
      facts: controllerSessionFacts)
  }

  func saveAxisMetricMeasurement(_ edges: [ControllerAxisRulerMeasurement], method: String,
    axesConfirmed: Bool) async {
    guard applicationAdmissionIsOpen, !axisCalibrationInProgress,
      let frame = axisMetricFrame, let checkpoint = axisMetricSourceCheckpoint else { return }
    do {
      let measurement = try ControllerAxisMetricMeasurement(recordedAt: Date(), geometry: frame,
        sourceCheckpoint: checkpoint, edges: edges, method: method,
        operatorAxisAssociationConfirmed: axesConfirmed,
        supersedesMeasurementID: latestAxisMetricMeasurement?.measurementID)
      drawingEvidenceArchive = try await drawingEvidencePort.appendAxisMetricMeasurement(measurement)
      guard applicationAdmissionIsOpen else { return }
      axisCalibrationProposal = nil
      do {
        axisCalibrationProposal = try ControllerAxisCalibrationProposal(measurement: measurement)
        axisMetricStatus = "Measurements retained. Review the proposed settings; physical holdouts remain required."
      } catch {
        axisMetricStatus = "Measurements retained; calibration proposal unavailable: \(error)."
      }
    } catch { axisMetricStatus = "Measurements could not be retained: \(error). The prior evidence is unchanged." }
  }

  private func restoreAxisMetricProposal() {
    guard let measurement = latestAxisMetricMeasurement,
      measurement.sourceCheckpoint.semanticIdentity.machineGeometry == machineGeometryIdentity,
      !drawingEvidenceArchive.axisCalibrationAttempts.contains(where: { $0.proposal.measurementID == measurement.measurementID }) else { return }
    axisCalibrationProposal = try? ControllerAxisCalibrationProposal(measurement: measurement)
  }

  func applyAxisMetricCalibration() async {
    guard let proposal = axisCalibrationProposal else { return }
    let disposition = await submitControllerSessionRequest(
      controllerSessionProjection.request(.applyAxisCalibration(proposalID: proposal.proposalID)))
    if case .refused(let reason) = disposition { axisMetricStatus = reason }
  }

  private func prepareAxisCalibration(_ proposal: ControllerAxisCalibrationProposal,
    resetPlan: LearningVacatePlan, admission: PlotterArtifactResetAdmissionFacts) async throws {
    guard applicationAdmissionIsOpen, !Task.isCancelled, axisCalibrationInProgress,
      proposal == axisCalibrationProposal, proposal.oldMachineGeometry == machineGeometryIdentity,
      resetPlan == learningVacatePlan(from: resetPlan.anchor),
      let measurement = latestAxisMetricMeasurement, proposal.validates(measurement: measurement),
      measurement.sourceCheckpoint.semanticIdentity == currentLearningPathSemanticIdentity else {
      throw AxisMetricLearningTransitionError.staleProposal
    }
    // This callback runs only after the lower owner has obtained a fresh matching
    // controller context, while it still excludes every other controller effect.
    drawingEvidenceArchive = try await drawingEvidencePort.prepareAxisCalibration(
      ControllerAxisCalibrationAttempt(proposal: proposal))
    guard applicationAdmissionIsOpen, !Task.isCancelled else { throw CancellationError() }
    let accepted = await artifactResetRuntime.submit(
      .reset(artifactResetPlan(resetPlan, axisCalibration: proposal)), facts: admission)
    markSemanticPresentationChanged()
    guard accepted, machineGeometryIdentity == proposal.proposedMachineGeometry,
      activeMachineArtifactCheckpoint == nil, tipCameraRegistration == nil,
      activeStageFourCheckpoint == nil else {
      throw AxisMetricLearningTransitionError.incompleteReset(
        artifactResetRuntime.snapshot().phase.detail ?? learningAuthorityError ?? "Dependent Learning did not reset.")
    }
    await synchronizeDrawingDraft()
    await synchronizeDrawingRunProjection()
    guard applicationAdmissionIsOpen, !Task.isCancelled else { throw CancellationError() }
    axisMetricStatus = "Prior geometry retained as evidence; dependent Learning reset. Applying the reviewed settings."
  }

  private func retainAxisCalibrationTerminal(_ proposal: ControllerAxisCalibrationProposal,
    outcome: ControllerAxisCalibrationOutcome) async throws {
    // A preflight refusal has no prepared transaction. The immutable measurement
    // remains available; it is never converted into a claim of firmware change.
    let terminal = ControllerAxisCalibrationTerminal(proposalID: proposal.proposalID, outcome: outcome)
    pendingAxisCalibrationTerminal = terminal
    let latest = await drawingEvidencePort.load()
    guard case .loaded(let archive) = latest else {
      throw AxisMetricLearningTransitionError.evidenceRejected("Calibration archive unavailable while retaining the terminal outcome.")
    }
    guard archive.axisCalibrationAttempts.contains(where: { $0.proposal == proposal }) else {
      pendingAxisCalibrationTerminal = nil
      return
    }
    do {
      drawingEvidenceArchive = try await drawingEvidencePort.appendAxisCalibrationTerminal(terminal)
      pendingAxisCalibrationTerminal = nil
    } catch {
      axisMetricStatus = "Firmware outcome retained in this session; durable publication failed: \(error). Retry evidence only."
      throw error
    }
  }

  func retryAxisMetricEvidencePublication() async {
    guard let terminal = pendingAxisCalibrationTerminal else { return }
    do {
      drawingEvidenceArchive = try await drawingEvidencePort.appendAxisCalibrationTerminal(terminal)
      pendingAxisCalibrationTerminal = nil
      axisMetricStatus = terminal.outcome.reason + " Terminal evidence retained; no settings were replayed."
    } catch { axisMetricStatus = "Terminal evidence retry failed: \(error)." }
  }

  var axisMetricHasPendingPublication: Bool { pendingAxisCalibrationTerminal != nil }
}
