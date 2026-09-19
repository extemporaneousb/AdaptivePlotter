import Foundation
import PlotterModel
import PlotterRuntime

/// Exact pixel identity, separate from the rendered window and its overlays.
struct WorkbenchDiagnosticCamera: Codable, Sendable {
  let source: FrameSourceIdentity
  let frameID: FrameID
  let sequence: UInt64
  let captureNanoseconds: UInt64
  let cameraConfigurationID: CameraConfigurationID
  let width: Int
  let height: Int
  let rowBytes: Int
  let pixelFormat: FramePixelFormat
  let contentSHA256: String
  let visibleRegion: PixelRect?
  let pixelsFile: String
  let imageFile: String

  init(frame: DisplayedFrame, visibleRegion: PixelRect?, stem: String) {
    let pixels = frame.frame.materializingContentHash(for: .serialization)
    source = frame.source
    frameID = pixels.id
    sequence = pixels.sequence
    captureNanoseconds = pixels.captureNanoseconds
    cameraConfigurationID = pixels.cameraConfigurationID
    width = pixels.width; height = pixels.height; rowBytes = pixels.rowBytes
    pixelFormat = pixels.pixelFormat
    contentSHA256 = pixels.contentSHA256
    self.visibleRegion = visibleRegion
    pixelsFile = stem + ".pixels"
    imageFile = stem + ".png"
  }
}

struct WorkbenchDiagnosticDrawing: Codable, Sendable {
  let draftRevision: UInt64
  let targetIsVisible: Bool
  let drawBorder: Bool
  let selectedProgram: DrawingProgram?
  let draftPlan: ExecutionPlanRevision?
  let retainedExecutionPlan: ExecutionPlanRevision?
  /// Current mapping, explicitly separate from the retained run plan's registration identity.
  let currentTipRegistration: TipCameraRegistration?
  let runPlanContentHash: String?
  let runID: RunID?
  let phase: String?
  let terminalDisposition: String?
  let terminalDetail: String
  let progress: DrawingPlanProgressSnapshot?

  @MainActor init(application: PlotterApplicationRuntime) {
    let draft = application.drawingDraftSnapshot
    let run = application.drawingRunSnapshot
    draftRevision = draft.projection.draftRevision.rawValue
    targetIsVisible = draft.isTargetVisible
    drawBorder = draft.drawBorder
    selectedProgram = draft.program
    draftPlan = draft.plan
    retainedExecutionPlan = run?.retainedExecutionPlan
    currentTipRegistration = application.tipCameraRegistration
    runPlanContentHash = run?.retainedExecutionPlan?.contentHash.description
    if case .intentPublicationIncomplete(let retainedRunID, _) = run?.evidencePersistence {
      runID = retainedRunID
      terminalDisposition = "publicationIncomplete"
    } else {
      runID = run?.activeRunID ?? run?.terminal?.runID
      terminalDisposition = run?.terminal.map { String(describing: $0.disposition) }
    }
    phase = run.map { String(describing: $0.phase) }
    terminalDetail = application.drawingStudioPresentation.runState.detail
    progress = run?.progress
  }
}
