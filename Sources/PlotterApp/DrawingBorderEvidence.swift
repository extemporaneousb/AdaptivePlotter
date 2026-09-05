import Foundation
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime

/// Constructs the existing durable drawing record from a completed controller
/// outcome. Observation quality is retained independently of Learning completion.
enum DrawingBorderEvidence {
  static func record(
    snapshot: PlotterBorderValidationSnapshot,
    attemptID: ExerciseAttemptID,
    registration: TipCameraRegistration,
    paper: PaperRevisionContext,
    nowNanoseconds: UInt64
  ) throws -> DrawingRunEvidenceRecord? {
    guard let program = snapshot.program, let plan = snapshot.drawingBorderPlan,
      case .completed(let progress, _) = snapshot.drawingOutcome
    else { return nil }
    let observation: DrawingRunObservationOutcome
    let disposition: BorderValidationEvidenceDisposition
    if let measured = snapshot.inkObservation {
      observation = .observed(measured.evidence)
      disposition = .attributable
    } else if let rejection = snapshot.observationRejection {
      observation = .rejected(rejection)
      disposition = .visionUnclear
    } else { return nil }
    let provenance = try PlotterDrawingPlanningAdapter.planningProvenance(
      for: registration
    )
    let registrationSHA = provenance.registrationContentHash.description
    return try DrawingRunEvidenceRecord(
      runID: RunID(attemptID.rawValue),
      requestID: attemptID.rawValue,
      role: .evaluationHoldout,
      evidenceDisposition: disposition,
      requestFrontier: .admitted,
      executionFrontiers: DrawingRunExecutionFrontiers(
        plannedStrokeCount: UInt32(progress.plannedStrokeCount),
        commandedStrokeCount: UInt32(progress.commandedStrokeCount),
        controllerCompletedStrokeCount: UInt32(progress.controllerCompletedStrokeCount),
        inkVerifiedStrokeCount: disposition == .attributable ? 1 : 0
      ),
      executionDisposition: .completed,
      program: DrawingProgramEvidenceReference(program: program),
      placement: DrawingPlacementEvidenceReference(
        placementID: attemptID.rawValue,
        placement: plan.placement
      ),
      plan: DrawingExecutionPlanEvidenceReference(plan: plan),
      planningProvenance: provenance,
      tipCalibration: DrawingTipCalibrationEvidenceReference(
        acceptedRevisionID: registration.acceptedRevisionID,
        registrationEvidenceSHA256: registrationSHA,
        applicability: registration.applicability,
        estimatorRevision: registration.estimatorRevision
      ),
      paper: paper,
      observation: observation,
      recordedAt: RuntimeTimestamp(
        monotonicNanoseconds: max(
          nowNanoseconds, snapshot.postFrame?.frame.captureNanoseconds ?? 0
        )
      )
    )
  }
}
