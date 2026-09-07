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
  let coverageExperiment: DrawingCoverageExperiment?
  let coverageAssessment: DrawingCoverageAssessment?
  let coverageUnavailableReason: String?
  let coverageSelectedTrial: Int?

  var authoringIsEnabled: Bool { authoringUnavailableReason == nil }
  var authoringUnavailableReason: String? {
    guard editingIsEnabled else { return runState.detail }
    return coverageExperiment == nil ? nil : "Leave the coverage experiment before editing its sealed geometry."
  }

  var coverageControls: [(intent: PlotterDrawingDraftIntent, title: String, unavailableReason: String?)] {
    let busy = editingIsEnabled ? nil : runState.detail
    guard coverageExperiment != nil else {
      return [(.prepareCoverageExperiment, "Prepare Coverage Experiment", busy)]
    }
    var controls: [(PlotterDrawingDraftIntent, String, String?)] = []
    if let assessment = coverageAssessment, assessment.nextTrial != nil {
      let currentIsUnattempted = coverageSelectedTrial.map { !assessment.attemptedIndices.contains($0) } ?? false
      controls.append((.nextCoverageTrial, "Next Experiment Trial",
        busy ?? coverageUnavailableReason ?? assessment.blocker
          ?? (currentIsUnattempted ? "Run or leave the currently proposed trial first." : nil)))
    }
    controls.append((.leaveCoverageExperiment, "Leave Experiment", busy))
    return controls
  }

  init(
    catalog: [DrawingStudioCatalogItemPresentation],
    selectedCatalogItemID: DrawingCatalogEntryID?,
    evidenceRole: BorderValidationEvidenceRole,
    canvas: DrawingStudioCanvasPresentation,
    editingIsEnabled: Bool,
    runProjection: PlotterDrawingRunProjectionReference?,
    runState: DrawingStudioRunState,
    coverageExperiment: DrawingCoverageExperiment? = nil,
    coverageAssessment: DrawingCoverageAssessment? = nil,
    coverageUnavailableReason: String? = nil,
    coverageSelectedTrial: Int? = nil
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
    self.coverageExperiment = coverageExperiment
    self.coverageAssessment = coverageAssessment
    self.coverageUnavailableReason = coverageUnavailableReason
    self.coverageSelectedTrial = coverageSelectedTrial
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
          presentation.coverageExperiment == nil
            ? "Choose a drawing or create a portrait, place its target, then run the reviewed plan."
            : "Review the proposed coverage line, then run its exact plan."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }

      if let requestRefusal {
        Label(requestRefusal, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .textSelection(.enabled)
      }

      if presentation.coverageExperiment == nil {
        HStack {
          Button { portraitIsPresented = true } label: {
            Label("Create Portrait…", systemImage: "person.crop.rectangle")
          }
          .disabled(!presentation.authoringIsEnabled || portraitStrokeStyle == nil)
          if presentation.selectedCatalogItemID == nil {
            Text("Portrait selected").font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      coverageExperiment
      if presentation.coverageExperiment == nil {
        catalog
        if let selected = presentation.selectedCatalogItem {
          Text(selected.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        evidenceRole
        placement
      }
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

  private var coverageExperiment: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Active Learning").font(.headline)
      if let experiment = presentation.coverageExperiment {
        if experiment.tip.applicability.opticalConfiguration.source == .simulated {
          Text("SIMULATED — NOT PHYSICAL EVIDENCE").font(.caption.bold()).foregroundStyle(.orange)
        }
        Text("32 training lines · 16 reserved holdouts · 4 regions · X± / Y±")
          .font(.caption).foregroundStyle(.secondary)
        Text(String(format: "Applicable area %.1f × %.1f mm · correction bound 2 mm",
          experiment.extent.width, experiment.extent.height)).font(.caption)
        if let index = presentation.coverageSelectedTrial {
          Text(experiment.trials[index].label).font(.caption.bold())
        }
        if let reason = presentation.coverageUnavailableReason {
          Text(reason).font(.caption).foregroundStyle(.orange)
        }
        if let assessment = presentation.coverageAssessment {
          Text("Measured: \(assessment.trainingCount)/32 training · \(assessment.holdoutCount)/16 holdouts")
            .font(.caption.monospacedDigit())
          if let blocker = assessment.blocker {
            Text(blocker).font(.caption).foregroundStyle(.orange)
          }
          if let candidate = assessment.candidate {
            Text("Candidate fitted · affine prior remains current").font(.caption.bold())
            Text(String(format: "Fit standard error: X %.3f mm · Y %.3f mm",
              candidate.vertical.residualStandardErrorMM, candidate.horizontal.residualStandardErrorMM))
              .font(.caption)
            DisclosureGroup("Position and direction coefficients") {
              Text("Cross-track only. Coefficients: intercept, normalized X, normalized Y, signed direction.")
                .font(.caption2)
              Text("X: " + candidate.vertical.coefficients.map { String(format: "%.4f", $0) }.joined(separator: ", "))
              Text("Y: " + candidate.horizontal.coefficients.map { String(format: "%.4f", $0) }.joined(separator: ", "))
            }.font(.caption.monospaced())
          }
          if let comparison = assessment.comparison {
            Text(comparison.passed ? "Held-out prediction comparison passed" : "Held-out comparison failed — retain prior")
              .font(.caption.bold()).foregroundStyle(comparison.passed ? .green : .orange)
            Text(String(format: "Trial-mean RMS: training %.3f → %.3f mm · holdout %.3f → %.3f mm",
              comparison.training.priorRMSMM, comparison.training.candidateRMSMM,
              comparison.holdout.priorRMSMM, comparison.holdout.candidateRMSMM)).font(.caption)
            DisclosureGroup("Holdout regions and directions") {
              ForEach(comparison.groups, id: \.label) { metric in
                Text(String(format: "%@: %.3f → %.3f mm", metric.label,
                  metric.priorRMSMM, metric.candidateRMSMM)).font(.caption2.monospacedDigit())
              }
            }
            Text("Prediction evidence only. Corrected execution and shape holdouts are required before model acceptance.")
              .font(.caption).foregroundStyle(.secondary)
          }
        }
      } else {
        Text("Select informative lines and fit bounded spatial and direction-dependent cross-track error. Requires a clear sheet inside the calibrated area.")
          .font(.caption).foregroundStyle(.secondary)
      }
      ForEach(presentation.coverageControls, id: \.intent) { control in
        Button(control.title) { submitDraft(control.intent) }
          .disabled(control.unavailableReason != nil || draftRequest(control.intent) == nil)
          .help(control.unavailableReason ?? control.title)
      }
      if presentation.coverageExperiment != nil {
        Text("Review and Run each proposed line. After its evidence settles, use New Drawing, then Next Experiment Trial. Stop ends the current trial; an inconclusive trial halts the experiment.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
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
              !presentation.authoringIsEnabled
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
      !presentation.authoringIsEnabled
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
            set: {
              let allowed = presentation.canvas.placement.allowedScale
              submitDraft(.setUniformScale(min(allowed.upperBound,
                max(allowed.lowerBound, ($0 * 100).rounded() / 100))))
            }
          ),
          in: presentation.canvas.placement.allowedScale,
          step: 0.01
        )
        Text(String(format: "%.2f×", presentation.canvas.placement.uniformScale))
          .monospacedDigit()
          .frame(width: 52, alignment: .trailing)
      }
      .disabled(
        !presentation.authoringIsEnabled
          || draftRequest(.setUniformScale(presentation.canvas.placement.allowedScale.lowerBound)) == nil
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
        !presentation.authoringIsEnabled
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
        !presentation.authoringIsEnabled || draftRequest(.centerInDrawableRegion) == nil
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
