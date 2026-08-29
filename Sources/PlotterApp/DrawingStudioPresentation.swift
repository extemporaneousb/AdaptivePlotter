import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import SwiftUI

struct DrawingStudioCatalogItemPresentation: Hashable, Identifiable, Sendable {
  let id: DrawingCatalogEntryID
  let title: String
  let detail: String
  let systemImage: String

  init(
    id: DrawingCatalogEntryID,
    title: String,
    detail: String,
    systemImage: String
  ) {
    self.id = id
    self.title = title
    self.detail = detail
    self.systemImage = systemImage
  }

  init(catalogEntry: DrawingProgramCatalogEntry) {
    id = catalogEntry.id
    title = catalogEntry.displayName
    detail = String(
      format: "Built-in vector program · %.0f × %.0f field units%@",
      catalogEntry.fieldExtent.width,
      catalogEntry.fieldExtent.height,
      catalogEntry.supportsCurveTessellation ? " · deterministic curve tessellation" : ""
    )
    systemImage = Self.systemImage(for: catalogEntry.id)
  }

  private static func systemImage(for id: DrawingCatalogEntryID) -> String {
    switch id {
    case .line: "line.diagonal"
    case .polyline: "scribble"
    case .rectangle: "rectangle"
    case .square: "square"
    case .triangle: "triangle"
    case .regularPolygon: "hexagon"
    case .circle: "circle"
    case .ellipse: "oval"
    case .star: "star"
    case .pyramid: "pyramid"
    case .elephant: "pawprint"
    }
  }
}

struct DrawingStudioPlacementPresentation: Hashable, Sendable {
  let centerCameraPixel: Point2<CameraPixelSpace>?
  let uniformScale: Double
  let allowedScale: ClosedRange<Double>
  let rotationDegrees: Double
  let placementIsEnabled: Bool

  var locationText: String {
    guard let centerCameraPixel else { return "Drag the target onto the video" }
    return String(
      format: "Camera X %.1f Y %.1f", centerCameraPixel.x, centerCameraPixel.y)
  }

  var transformText: String {
    String(format: "Scale %.2f× · Rotation %.1f°", uniformScale, rotationDegrees)
  }
}

enum DrawingStudioTargetPreviewStatus: Hashable, Sendable {
  case unavailable(reason: String)
  case outsideDrawableRegion(reason: String)
  case diagnosticOnly(reason: String)
  case ready

  var label: String {
    switch self {
    case .unavailable: "Target unavailable"
    case .outsideDrawableRegion: "Outside drawable region"
    case .diagnosticOnly: "Target preview only"
    case .ready: "Target preview ready"
    }
  }

  var detail: String? {
    switch self {
    case .unavailable(let reason), .outsideDrawableRegion(let reason),
      .diagnosticOnly(let reason): reason
    case .ready: nil
    }
  }
}

/// Planned target geometry projected onto one exact displayed frame. The same
/// program hash must be carried into execution by the coordinator; this view
/// has no promotion or motion authority.
struct DrawingStudioTargetPreview: Hashable, Sendable {
  let provenance: ExactFrameOverlayProvenance
  let strokes: [Polyline<CameraPixelSpace>]
  let bounds: AxisAlignedBounds<CameraPixelSpace>?
  let programContentHash: String
  let executionPlanContentHash: String?
  let status: DrawingStudioTargetPreviewStatus

  func matches(_ displayedFrame: DisplayedFrame) -> Bool {
    provenance.matches(displayedFrame)
  }
}

struct DrawingStudioCanvasPresentation: Hashable, Sendable {
  let draftProjection: PlotterDrawingDraftProjectionReference
  let placement: DrawingStudioPlacementPresentation
  let targetPreview: DrawingStudioTargetPreview?

  func targetPreview(for displayedFrame: DisplayedFrame?) -> DrawingStudioTargetPreview? {
    guard let displayedFrame, let targetPreview, targetPreview.matches(displayedFrame) else {
      return nil
    }
    return targetPreview
  }
}

enum DrawingStudioRunState: Hashable, Sendable {
  case unavailable(reason: String)
  case ready(detail: String)
  case running(capabilityID: PlotterDrawingRunStopCapabilityID, detail: String)
  case processing(detail: String)
  case terminal(runID: RunID, detail: String)
  case reviewAvailable(runID: RunID, detail: String)
  case reviewing(runID: RunID, detail: String)
  case publicationFailed(
    recoveryCapabilityID: PlotterDrawingRunPublicationRecoveryCapabilityID,
    detail: String
  )

  var title: String {
    switch self {
    case .unavailable: "Run unavailable"
    case .ready: "Ready to run"
    case .running: "Drawing in progress"
    case .processing: "Processing drawing evidence"
    case .terminal: "Drawing run ended"
    case .reviewAvailable: "Run review available"
    case .reviewing: "Reviewing drawing run"
    case .publicationFailed: "Evidence publication failed"
    }
  }

  var detail: String {
    switch self {
    case .unavailable(let reason), .ready(let reason), .running(_, let reason),
      .processing(let reason),
      .terminal(_, let reason), .reviewAvailable(_, let reason),
      .reviewing(_, let reason), .publicationFailed(_, let reason):
      reason
    }
  }
}

struct DrawingStudioControl: Hashable, Identifiable, Sendable {
  let intent: PlotterDrawingRunIntent
  let title: String
  let systemImage: String
  let role: OperatorButtonRole
  let isEnabled: Bool

  var id: PlotterDrawingRunIntent { intent }

  init(
    intent: PlotterDrawingRunIntent,
    title: String,
    systemImage: String,
    role: OperatorButtonRole,
    isEnabled: Bool = true
  ) {
    self.intent = intent
    self.title = title
    self.systemImage = systemImage
    self.role = role
    self.isEnabled = isEnabled
  }
}

struct DrawingStudioPresentation: Hashable, Sendable {
  let catalog: [DrawingStudioCatalogItemPresentation]
  let selectedCatalogItemID: DrawingCatalogEntryID?
  let evidenceRole: DrawingTrialEvidenceRole
  let canvas: DrawingStudioCanvasPresentation
  let editingIsEnabled: Bool
  let runProjection: PlotterDrawingRunProjectionReference?
  let runState: DrawingStudioRunState

  init(
    catalog: [DrawingStudioCatalogItemPresentation],
    selectedCatalogItemID: DrawingCatalogEntryID?,
    evidenceRole: DrawingTrialEvidenceRole,
    canvas: DrawingStudioCanvasPresentation,
    editingIsEnabled: Bool,
    runProjection: PlotterDrawingRunProjectionReference?,
    runState: DrawingStudioRunState
  ) {
    self.catalog = catalog
    self.selectedCatalogItemID = selectedCatalogItemID
    self.evidenceRole = evidenceRole
    self.canvas = DrawingStudioCanvasPresentation(
      draftProjection: canvas.draftProjection,
      placement: DrawingStudioPlacementPresentation(
        centerCameraPixel: canvas.placement.centerCameraPixel,
        uniformScale: canvas.placement.uniformScale,
        allowedScale: canvas.placement.allowedScale,
        rotationDegrees: canvas.placement.rotationDegrees,
        placementIsEnabled: canvas.placement.placementIsEnabled && editingIsEnabled
      ),
      targetPreview: canvas.targetPreview
    )
    self.editingIsEnabled = editingIsEnabled
    self.runProjection = runProjection
    self.runState = runState
  }

  var selectedCatalogItem: DrawingStudioCatalogItemPresentation? {
    guard let selectedCatalogItemID else { return nil }
    return catalog.first { $0.id == selectedCatalogItemID }
  }

  var controls: [DrawingStudioControl] {
    switch runState {
    case .unavailable:
      return []
    case .ready:
      return [
        DrawingStudioControl(
          intent: .start,
          title: "Run Drawing",
          systemImage: "play.fill",
          role: .affirmative,
          isEnabled: editingIsEnabled
        ),
      ]
    case .running(let capabilityID, _):
      return [
        DrawingStudioControl(
          intent: .stop(capabilityID),
          title: "Stop",
          systemImage: "stop.fill",
          role: .negative
        )
      ]
    case .processing:
      return []
    case .terminal(let runID, _):
      return [
        DrawingStudioControl(
          intent: .beginNewRun(runID),
          title: "New Drawing",
          systemImage: "plus",
          role: .affirmative
        )
      ]
    case .reviewAvailable(let runID, _):
      return [
        DrawingStudioControl(
          intent: .pinReview(runID),
          title: "Review Run",
          systemImage: "square.stack.3d.up",
          role: .neutral
        ),
        DrawingStudioControl(
          intent: .beginNewRun(runID),
          title: "New Drawing",
          systemImage: "plus",
          role: .affirmative
        ),
      ]
    case .reviewing(let runID, _):
      return [
        DrawingStudioControl(
          intent: .unpinReview(runID),
          title: "Resume Live Preview",
          systemImage: "video.fill",
          role: .neutral
        ),
        DrawingStudioControl(
          intent: .beginNewRun(runID),
          title: "New Drawing",
          systemImage: "plus",
          role: .affirmative
        ),
      ]
    case .publicationFailed(let recoveryCapabilityID, _):
      return [
        DrawingStudioControl(
          intent: .recoverPublication(recoveryCapabilityID),
          title: "Retry Evidence Save",
          systemImage: "arrow.clockwise",
          role: .affirmative
        )
      ]
    }
  }
}

/// Selection and transform shell for an already-projected drawing program.
/// Every mutation is returned as a typed intent; the view owns no planner,
/// controller, evidence store, or readiness decision.
struct DrawingStudioView: View {
  let presentation: DrawingStudioPresentation
  let drawingDraftIntentSink: any PlotterDrawingDraftIntentSink
  let drawingRunIntentSink: any PlotterDrawingRunIntentSink

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Drawing Studio")
          .font(.title3.bold())
        Text(
          "Select a deterministic drawing program, place its projected target, then run the exact reviewed plan."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      catalog
      if let selected = presentation.selectedCatalogItem {
        Text(selected.detail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      evidenceRole
      placement
      runStatus
      controls
    }
    .padding(12)
    .accessibilityElement(children: .contain)
  }

  private var catalog: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Drawing program").font(.headline)
      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(presentation.catalog) { item in
            Button {
              submitDraft(.selectCatalogItem(item.id))
            } label: {
              VStack(spacing: 5) {
                Image(systemName: item.systemImage)
                  .font(.title2)
                Text(item.title)
                  .font(.caption)
                  .lineLimit(1)
              }
              .frame(minWidth: 76, minHeight: 58)
            }
            .buttonStyle(.bordered)
            .tint(item.id == presentation.selectedCatalogItemID ? .accentColor : .secondary)
            .disabled(!presentation.editingIsEnabled)
            .accessibilityHint(item.detail)
          }
        }
      }
    }
  }

  private var evidenceRole: some View {
    Picker(
      "Evidence role",
      selection: Binding(
        get: { presentation.evidenceRole },
        set: { submitDraft(.setEvidenceRole($0)) }
      )
    ) {
      ForEach(DrawingTrialEvidenceRole.allCases, id: \.rawValue) { role in
        Text(Self.evidenceRoleLabel(role)).tag(role)
      }
    }
    .disabled(!presentation.editingIsEnabled)
    .help("Choose before execution; a holdout cannot become training evidence after inspection.")
  }

  private var placement: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Placement").font(.headline)
      Label(presentation.canvas.placement.locationText, systemImage: "hand.draw")
        .font(.caption)
      HStack {
        Text("Size")
        Slider(
          value: Binding(
            get: { presentation.canvas.placement.uniformScale },
            set: { submitDraft(.setUniformScale($0)) }
          ),
          in: presentation.canvas.placement.allowedScale
        )
        Text(String(format: "%.2f×", presentation.canvas.placement.uniformScale))
          .monospacedDigit()
          .frame(width: 52, alignment: .trailing)
      }
      .disabled(!presentation.editingIsEnabled)
      HStack {
        Text("Rotation")
        Slider(
          value: Binding(
            get: { presentation.canvas.placement.rotationDegrees },
            set: { submitDraft(.setRotationDegrees($0)) }
          ),
          in: -180...180
        )
        Text(String(format: "%.1f°", presentation.canvas.placement.rotationDegrees))
          .monospacedDigit()
          .frame(width: 58, alignment: .trailing)
      }
      .disabled(!presentation.editingIsEnabled)
      Button {
        submitDraft(.centerInDrawableRegion)
      } label: {
        Label("Center Target", systemImage: "scope")
      }
      .operatorButton(.neutral)
      .disabled(!presentation.editingIsEnabled)
    }
  }

  private var runStatus: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(presentation.runState.title).font(.headline)
      Text(presentation.runState.detail)
        .font(.caption)
        .foregroundStyle(.secondary)
      if let preview = presentation.canvas.targetPreview {
        Text("Program \(preview.programContentHash) · \(preview.status.label)")
          .font(.caption2.monospaced())
          .foregroundStyle(preview.status == .ready ? .cyan : .orange)
        if let detail = preview.status.detail {
          Text(detail).font(.caption2).foregroundStyle(.orange)
        }
      }
    }
  }

  private var controls: some View {
    HStack(spacing: 8) {
      ForEach(presentation.controls) { control in
        Button {
          guard let projection = presentation.runProjection else { return }
          drawingRunIntentSink.submitDrawingRun(
            PlotterDrawingRunSubmission(
              projection: projection,
              intent: control.intent
            )
          )
        } label: {
          Label(control.title, systemImage: control.systemImage)
        }
        .operatorButton(control.role)
        .disabled(!control.isEnabled)
      }
    }
  }

  private func submitDraft(_ intent: PlotterDrawingDraftIntent) {
    drawingDraftIntentSink.submitDrawingDraft(
      PlotterDrawingDraftSubmission(
        projection: presentation.canvas.draftProjection,
        intent: intent
      )
    )
  }

  private static func evidenceRoleLabel(_ role: DrawingTrialEvidenceRole) -> String {
    switch role {
    case .ordinaryDrawing: "Ordinary drawing"
    case .training: "Training"
    case .reservedHoldout: "Reserved holdout"
    case .evaluationHoldout: "Evaluation holdout"
    }
  }
}
