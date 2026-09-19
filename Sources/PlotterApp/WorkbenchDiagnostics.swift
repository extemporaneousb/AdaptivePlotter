import AppKit
import Foundation
import PlotterEpisodeModel
import PlotterModel
import PlotterRuntime
import ImageIO
import PlotterUI
import Observation

/// An on-demand copy of existing records and projections. It records no new
/// events and does not claim to be a complete replay archive or ink evidence.
struct WorkbenchDebugSnapshot: Codable, Identifiable, Sendable {
  struct Transition: Codable, Sendable {
    let sequence: UInt64
    let source: String
    let request: String
    let result: String
    let before: UInt64
    let after: UInt64
    let currentItem: String
  }
  struct Action: Codable, Sendable {
    let id: String
    let title: String
    let intent: String
    let unavailableReason: String?
  }
  let id: UUID
  let format: String
  let capturedAt: Date
  let processID: Int32
  let executablePath: String?
  let source: String
  let semanticRevision: UInt64
  let uiRevision: UInt64
  let runtimeRevisions: [PlotterUIRuntimeRevision]
  let learningEpisodeID: UUID
  let transitions: [Transition]
  let actions: [Action]
  let diagnostics: [String]
  let limitations: [String]
  let camera: WorkbenchDiagnosticCamera?
  let drawing: WorkbenchDiagnosticDrawing

  @MainActor
  init(application: PlotterApplicationRuntime, projection: PlotterUIProjection) {
    self.init(capture: WorkbenchDiagnosticCapture(application: application, projection: projection))
  }

  init(capture: WorkbenchDiagnosticCapture) {
    id = capture.id
    format = "adaptiveplotter.debug-snapshot.v2"
    capturedAt = capture.capturedAt
    processID = capture.processID
    executablePath = capture.executablePath
    source = capture.source
    semanticRevision = capture.semanticRevision
    uiRevision = capture.projection.revision.rawValue
    runtimeRevisions = capture.projection.runtimeRevisions
    let record = capture.record
    let projection = capture.projection
    learningEpisodeID = record.episodeID.rawValue
    transitions = record.entries.map {
      Transition(
        sequence: $0.sequence, source: $0.environment.rawValue,
        request: String(describing: $0.request), result: String(describing: $0.result),
        before: $0.preStateRevision.rawValue, after: $0.postStateRevision.rawValue,
        currentItem: $0.postTransitionProjection.currentItem.rawValue
      )
    }
    actions = projection.actions.map {
      Action(id: $0.id.rawValue, title: $0.title, intent: String(describing: $0.intent),
             unavailableReason: $0.unavailableReason)
    }
    diagnostics = capture.diagnostics
    camera = capture.frame.map { WorkbenchDiagnosticCamera(frame: $0, visibleRegion: capture.visibleRegion, stem: capture.fileStem) }
    drawing = capture.drawing
    limitations = [
      "Snapshot of current owners and the existing bounded Learning record (up to 128 retained transitions).",
      "Feature journals retain their own identities; no unrelated journals are merged.",
      "Only the displayed camera pixels are copied on demand; no camera capture, analysis, or motion is requested.",
      "A displayed frame may be frozen or stale. Its monotonic capture time and source are retained; export time is not capture time.",
      "Raw controller traffic, audio, and older or in-flight Learning transitions are not included.",
      "This diagnostic snapshot is not a replay archive or a claim of attended physical evidence."
    ]
  }

  func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(self)
  }
}

/// Only this bounded immutable copy crosses MainActor. Transition/request
/// reflection and JSON formatting happen later on the file worker.
struct WorkbenchDiagnosticCapture: Sendable {
  let id = UUID()
  let capturedAt = Date()
  let processID = ProcessInfo.processInfo.processIdentifier
  let executablePath = Bundle.main.executableURL?.path
  let source: String
  let semanticRevision: UInt64
  let projection: PlotterUIProjection
  let record: PlotterLearningEpisodeRecord
  let diagnostics: [String]
  let frame: DisplayedFrame?
  let visibleRegion: PixelRect?
  let drawing: WorkbenchDiagnosticDrawing

  var fileStem: String {
    let stamp = ISO8601DateFormatter().string(from: capturedAt).replacingOccurrences(of: ":", with: "-")
    return "diagnostics-\(stamp)-\(id.uuidString)"
  }

  @MainActor
  init(application: PlotterApplicationRuntime, projection: PlotterUIProjection,
       viewport: ActionSurfaceViewportState = .init()) {
    frame = application.actionSurfacePreview.displayedFrame
    visibleRegion = frame.flatMap { viewport.visibleRegion(frameWidth: $0.frame.width, frameHeight: $0.frame.height) }
    drawing = WorkbenchDiagnosticDrawing(application: application)
    source = application.frameMode == .live ? "LIVE" : "SIMULATED"
    semanticRevision = application.semanticPresentationRevision
    self.projection = projection
    record = application.learningEpisodeRecord
    var details = projection.diagnostics.map(\.summary)
    details += [application.cameraError, application.visionError, application.explorationError,
      application.drawingEvidenceError].compactMap { $0 }
    let border = application.borderValidationSnapshot
    details += border.terminalHistory.map(\.detail)
    details += ["Drawing Border phase: \(border.phase)",
      "Drawing Border step: \(border.step.title)",
      "Drawing outcome: \(String(describing: border.drawingOutcome))", border.inkStatus]
    let drawing = application.drawingStudioPresentation.runState
    details.append("Drawing run: \(drawing.title). \(drawing.detail)")
    for refusal in [application.drawingDraftSnapshot.planningRefusal,
                    application.drawingDraftSnapshot.lastSubmissionRefusal] {
      if let refusal { details.append("Drawing Draft: \(refusal.reason). \(refusal.remedy)") }
    }
    self.diagnostics = details
  }
}

enum WorkbenchDiagnosticFileWriter {
  static func write(_ capture: WorkbenchDiagnosticCapture, directory: URL) async throws -> URL {
    try await Task.detached(priority: .utility) {
      let snapshot = WorkbenchDebugSnapshot(capture: capture)
      let data = try snapshot.encoded()
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      // Publish JSON last: a successful manifest never points at half-written assets.
      if let frame = capture.frame, let camera = snapshot.camera {
        try frame.frame.bytes.data.write(to: directory.appendingPathComponent(camera.pixelsFile), options: .atomic)
        guard let image = FrameImageFactory.image(from: frame.frame),
          let png = CFDataCreateMutable(nil, 0),
          let destination = CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        try (png as Data).write(to: directory.appendingPathComponent(camera.imageFile), options: .atomic)
      }
      let url = directory.appendingPathComponent(capture.fileStem + ".json")
      try data.write(to: url, options: .atomic)
      return url
    }.value
  }
}

@MainActor @Observable
final class WorkbenchDiagnosticExporter {
  private(set) var isExporting = false
  private(set) var status: String?
  private(set) var savedURL: URL?
  @ObservationIgnored private let directory: URL
  @ObservationIgnored private let write: @Sendable (WorkbenchDiagnosticCapture, URL) async throws -> URL

  init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/AdaptivePlotter/Diagnostics", isDirectory: true),
    write: @escaping @Sendable (WorkbenchDiagnosticCapture, URL) async throws -> URL = { capture, directory in try await WorkbenchDiagnosticFileWriter.write(capture, directory: directory) }) {
    self.directory = directory
    self.write = write
  }

  func export(_ capture: WorkbenchDiagnosticCapture) {
    guard !isExporting else { return }
    isExporting = true
    status = "Writing diagnostics…"
    savedURL = nil
    Task {
      do {
        let url = try await write(capture, directory)
        savedURL = url
        status = "Saved \(url.lastPathComponent)"
      } catch { status = "Diagnostics export failed: \(error.localizedDescription)" }
      isExporting = false
    }
  }

  func dismissStatus() { if !isExporting { status = nil } }
}
