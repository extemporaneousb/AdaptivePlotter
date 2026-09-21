import PlotterModel
import PlotterRuntime

/// Presentation only: retained planned paths never assert controller completion
/// or observed ink, and no current Draft or calibration participates.
struct DrawingReviewGeometry {
  let title: String
  let explanation: String
  let preview: PortraitPlanePreview

  static let unavailableExplanation = "Geometry unavailable: this historical result retains neither an execution plan nor its source program."

  static func resolve(plan: ExecutionPlanRevision?, sourceProgram: DrawingProgram?, completedStrokeCount: Int? = nil) -> Self? {
    if let plan {
      return Self(title: completedStrokeCount == nil ? "Retained execution plan" : "Planned through this stage",
        explanation: "Planned paths and placement retained with this result; not evidence of observed ink.",
        preview: .planned(plan, completedStrokeCount: completedStrokeCount))
    }
    guard let sourceProgram else { return nil }
    return Self(title: "Source reference",
      explanation: "Source program only; historical execution placement and clipping are unavailable.",
      preview: PortraitPlanePreviewSource().resolve(program: sourceProgram,
        nominalWidth: sourceProgram.strokes.first?.style.nominalLineWidth ?? 0.4))
  }

  static func photographExplanation(referenceCount: Int?, failed: Bool) -> String {
    guard let referenceCount else {
      return "This historical result has no retained photograph references. Planned geometry is not a photograph."
    }
    guard referenceCount > 0 else { return "No photograph was retained for this stage of the attempt." }
    return failed ? "The retained photograph could not be loaded. See the image error below."
      : "The retained photograph is unavailable."
  }
}

/// Choose the newest retained photograph, rather than the first acquisition.
enum DrawingReviewPhotographs {
  static func preferredResultIndex(_ frames: [DrawingRunMediaReference]) -> Int {
    frames.indices.max { frames[$0].frame.captureNanoseconds < frames[$1].frame.captureNanoseconds } ?? 0
  }

  static func stageLabels(_ attempt: DrawingRunAttemptEvidence) -> [String] {
    let progress = attempt.progressFrames.map {
      "\($0.progress.completedStrokeIDs.count)/\($0.progress.plannedStrokeCount) strokes"
    }
    let results = attempt.terminalFrames.enumerated().map { index, frame in
      frame.completionCaptureAfterNanoseconds != nil ? "Completed drawing" :
        (frame.captureAfterNanoseconds != nil ? "Result view \(index + 1)" : "Available frame")
    }
    return progress + results
  }

  static func preferredStageIndex(_ attempt: DrawingRunAttemptEvidence) -> Int {
    preferredResultIndex(attempt.progressFrames.map(\.media) + attempt.terminalFrames)
  }

  static func hasResultPhoto(_ record: DrawingRunEvidenceRecord) -> Bool {
    record.attemptEvidence?.terminalFrames.contains {
      $0.completionCaptureAfterNanoseconds != nil || $0.captureAfterNanoseconds != nil
    } == true
  }

  static func status(_ record: DrawingRunEvidenceRecord) -> String? {
    guard let attempt = record.attemptEvidence else { return nil }
    if !hasResultPhoto(record) {
      let available = attempt.terminalFrames.isEmpty ? "" : "The available frame may predate completion. "
      return "Result photo unavailable. " + available
        + (attempt.missingCoverageReason ?? "No result frame was retained.")
    }
    return attempt.missingCoverageReason.map { "Photo retained. " + $0 }
  }
}
