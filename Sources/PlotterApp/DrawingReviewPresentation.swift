import PortraitLibrary
import PortraitStudioUI
import Foundation
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

/// Selection identity carries the capture occurrence through every UI route.
enum PortraitLibraryBrowseItem: Hashable {
  case photo(UUID), drawing(PortraitDrawingIdentity), work(String)
}

extension PortraitLibraryBrowsePresentation {
  static func filterTitle(_ filter: PortraitLibraryFilter) -> String {
    switch filter {
    case .allPhotos: "All photos"
    case .photosWithPlottedWorks: "Photos with plotted works"
    case .photosWithoutPlottedWorks: "Photos without plotted works"
    case .plottedWorks: "Plotted works"
    }
  }

  static func photoTitle(_ photo: PortraitLibraryPhoto) -> String {
    "Photo · " + captureDescription(photo)
  }
  static func drawingTitle(_ drawing: PortraitLibraryDrawing) -> String {
    let date = drawing.isRenderable
      ? drawing.summary.createdAt.formatted(date: .abbreviated, time: .shortened)
      : "Creation time unknown"
    return "\(drawing.summary.title) · \(drawing.summary.strokeCount) strokes · \(date) · \(drawing.identity.candidateID.prefix(8))"
  }
  static func workTitle(_ work: PortraitLibraryWork) -> String {
    work.drawingTitle?.isEmpty == false ? work.drawingTitle! : "Portrait drawing"
  }
  static func workDate(_ work: PortraitLibraryWork) -> String {
    work.recordedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Run time unknown"
  }
  static func workStatus(_ work: PortraitLibraryWork) -> String {
    if work.status.hasPrefix("completed") { return "Controller completed" }
    if work.status.hasPrefix("cancelled") { return "Stopped" }
    if work.status.hasPrefix("failed") { return "Failed" }
    if work.status.hasPrefix("refused") { return "Refused before completion" }
    if work.status.hasPrefix("ambiguous") { return "Uncertain controller outcome" }
    return work.executedOrPossibleInk ? "Unfinished · possible ink" : "Prepared · no ink dispatch"
  }
  static func thumbnailChoice(_ media: [PortraitLibraryMedia]) -> PortraitLibraryThumbnailChoice {
    let available = media.filter(\.isAvailable)
    let terminals = available.filter { $0.stage.hasPrefix("terminal-") }
    let progress = available.filter { $0.stage.hasPrefix("progress-") }
    let choices = !terminals.isEmpty ? terminals : progress
    guard let selected = choices.max(by: {
      if $0.reference.frame.captureNanoseconds != $1.reference.frame.captureNanoseconds {
        return $0.reference.frame.captureNanoseconds < $1.reference.frame.captureNanoseconds
      }
      return $0.id < $1.id
    }) else { return .source }
    return .media(selected.id)
  }
  static func mediaLabel(_ media: PortraitLibraryMedia) -> String {
    if media.stage.hasPrefix("progress-") { return "Progress" }
    if media.reference.completionCaptureAfterNanoseconds != nil || media.reference.captureAfterNanoseconds != nil { return "Result" }
    return "Terminal"
  }
  static func selectionAfterReload(current: PortraitLibraryBrowseItem?,
    previousFilter: PortraitLibraryFilter?, filter: PortraitLibraryFilter,
    initialPhotoID: UUID?, photos: [PortraitLibraryPhoto], works: [PortraitLibraryWork]) -> PortraitLibraryBrowseItem? {
    if previousFilter == filter, let current { return current }
    if previousFilter == nil, filter == .allPhotos, let initialPhotoID { return .photo(initialPhotoID) }
    return photos.first.map { .photo($0.id) } ?? works.first.map { .work($0.id) }
  }
}

enum PortraitLibraryThumbnailChoice: Equatable {
  case media(String), source
}
