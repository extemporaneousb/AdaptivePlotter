import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import PlotterUI
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
  let evidenceRole: BorderValidationEvidenceRole
  let canvas: DrawingStudioCanvasPresentation
  let editingIsEnabled: Bool
  let runProjection: PlotterDrawingRunProjectionReference?
  let runState: DrawingStudioRunState

  init(
    catalog: [DrawingStudioCatalogItemPresentation],
    selectedCatalogItemID: DrawingCatalogEntryID?,
    evidenceRole: BorderValidationEvidenceRole,
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
  let plotterUIProjection: PlotterUIProjection
  let plotterUIIntentSink: any PlotterUIIntentSink
  var plotterCameraID: CameraDeviceID? = nil
  var portraitStrokeStyle: PlotterModel.StrokeStyle? = nil
  var usePortrait: (DrawingProgram) async -> String? = { _ in "Portrait input is unavailable." }
  @State private var portrait = PortraitStudioModel()
  @State private var portraitIsPresented = false
  @State private var requestRefusal: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Drawing Studio")
          .font(.title3.bold())
        Text(
          "Choose a drawing or create a portrait, place its target, then run the reviewed plan."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      if let requestRefusal {
        Label(requestRefusal, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .textSelection(.enabled)
      }

      HStack {
        Button { portraitIsPresented = true } label: {
          Label("Create Portrait…", systemImage: "person.crop.rectangle")
        }
        .disabled(!presentation.editingIsEnabled || portraitStrokeStyle == nil)
        if presentation.selectedCatalogItemID == nil {
          Text("Portrait selected").font(.caption).foregroundStyle(.secondary)
        }
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
    .sheet(isPresented: $portraitIsPresented) {
      if let portraitStrokeStyle {
        PortraitStudioView(model: portrait, plotterCameraID: plotterCameraID,
                           strokeStyle: portraitStrokeStyle, useProgram: usePortrait)
      }
    }
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
            .disabled(
              !presentation.editingIsEnabled
                || draftRequest(.selectCatalogItem(item.id)) == nil
            )
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
      ForEach(BorderValidationEvidenceRole.allCases, id: \.rawValue) { role in
        Text(Self.evidenceRoleLabel(role)).tag(role)
      }
    }
    .disabled(
      !presentation.editingIsEnabled
        || draftRequest(.setEvidenceRole(presentation.evidenceRole)) == nil
    )
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
            set: { submitDraft(.setUniformScale(($0 * 100).rounded() / 100)) }
          ),
          in: presentation.canvas.placement.allowedScale,
          step: 0.01
        )
        Text(String(format: "%.2f×", presentation.canvas.placement.uniformScale))
          .monospacedDigit()
          .frame(width: 52, alignment: .trailing)
      }
      .disabled(
        !presentation.editingIsEnabled
          || draftRequest(.setUniformScale(presentation.canvas.placement.uniformScale)) == nil
      )
      HStack {
        Text("Rotation")
        Slider(
          value: Binding(
            get: { presentation.canvas.placement.rotationDegrees },
            set: { submitDraft(.setRotationDegrees($0.rounded())) }
          ),
          in: -180...180,
          step: 1
        )
        Text(String(format: "%.1f°", presentation.canvas.placement.rotationDegrees))
          .monospacedDigit()
          .frame(width: 58, alignment: .trailing)
      }
      .disabled(
        !presentation.editingIsEnabled
          || draftRequest(
            .setRotationDegrees(presentation.canvas.placement.rotationDegrees)
          ) == nil
      )
      Button {
        submitDraft(.centerInDrawableRegion)
      } label: {
        Label("Center Target", systemImage: "scope")
      }
      .operatorButton(.neutral)
      .disabled(
        !presentation.editingIsEnabled || draftRequest(.centerInDrawableRegion) == nil
      )
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
        let intent = PlotterUIIntent.drawingRun(control.intent)
        let request = plotterUIProjection.request(matching: intent)
        Button {
          submit(intent)
        } label: {
          Label(control.title, systemImage: control.systemImage)
        }
        .operatorButton(control.role)
        .disabled(!control.isEnabled || request == nil)
        .help(request == nil ? "Refresh the current Drawing Studio control." : control.title)
      }
    }
  }

  private func submitDraft(_ intent: PlotterDrawingDraftIntent) {
    submit(.drawingDraft(intent))
  }

  private func draftRequest(_ intent: PlotterDrawingDraftIntent) -> PlotterUIRequest? {
    plotterUIProjection.request(matching: .drawingDraft(intent))
  }

  private func submit(_ intent: PlotterUIIntent) {
    guard let request = plotterUIProjection.request(matching: intent) else {
      requestRefusal = "Refresh the current Drawing Studio control before retrying."
      return
    }
    Task { @MainActor in
      let disposition = await plotterUIIntentSink.submitPlotterUIRequest(request)
      if case .refused(let refusal) = disposition {
        requestRefusal = refusal.remedy
      } else {
        requestRefusal = nil
      }
    }
  }

  private static func evidenceRoleLabel(_ role: BorderValidationEvidenceRole) -> String {
    switch role {
    case .ordinaryDrawing: "Ordinary drawing"
    case .training: "Training"
    case .reservedHoldout: "Reserved holdout"
    case .evaluationHoldout: "Evaluation holdout"
    }
  }
}
