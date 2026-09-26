import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import PlotterUI
import SwiftUI

struct DrawingStudioPlacementPresentation: Hashable, Sendable {
  let centerCameraPixel: Point2<CameraPixelSpace>?
  let uniformScale: Double
  let allowedScale: ClosedRange<Double>
  let rotationDegrees: Double
  let placementIsEnabled: Bool

  var locationText: String {
    guard let centerCameraPixel else { return "Choose Move Drawing on the video, then drag to place" }
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

/// Planned target geometry projected through compatible camera optics. The same
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
    // Predicted artwork is independent of the observation frame's pixels.
    // Exact clicks and measured ink keep their separate exact-frame matching.
    provenance.source == displayedFrame.source
      && provenance.cameraConfigurationID == displayedFrame.frame.cameraConfigurationID
      && provenance.width == displayedFrame.frame.width
      && provenance.height == displayedFrame.frame.height
      && provenance.pixelFormat == displayedFrame.frame.pixelFormat
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
  case publicationIncomplete(detail: String)
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
    case .publicationIncomplete: "Drawing evidence unresolved"
    case .publicationFailed: "Evidence publication failed"
    }
  }

  var detail: String {
    switch self {
    case .unavailable(let reason), .ready(let reason), .running(_, let reason),
      .processing(let reason),
      .terminal(_, let reason), .reviewAvailable(_, let reason),
      .reviewing(_, let reason), .publicationIncomplete(let reason), .publicationFailed(_, let reason):
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
  let canvas: DrawingStudioCanvasPresentation
  let drawingPreview: DrawingStudioPreview?
  let paperReplacementStatus: String?
  let drawBorder: Bool
  let editingIsEnabled: Bool
  let runProjection: PlotterDrawingRunProjectionReference?
  let runState: DrawingStudioRunState
  let coverageExperiment: DrawingCoverageExperiment?
  let coverageAssessment: DrawingCoverageAssessment?
  let coverageUnavailableReason: String?
  let coverageSelectedTrial: Int?
  let residualRecords: [DrawingResidualRecordSummary]
  let residualAnalysis: DrawingRetrospectiveResidualAnalysis?

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
    canvas: DrawingStudioCanvasPresentation,
    editingIsEnabled: Bool,
    runProjection: PlotterDrawingRunProjectionReference?,
    runState: DrawingStudioRunState,
    coverageExperiment: DrawingCoverageExperiment? = nil,
    coverageAssessment: DrawingCoverageAssessment? = nil,
    coverageUnavailableReason: String? = nil,
    coverageSelectedTrial: Int? = nil,
    residualRecords: [DrawingResidualRecordSummary] = [],
    residualAnalysis: DrawingRetrospectiveResidualAnalysis? = nil,
    drawBorder: Bool = false,
    paperReplacementStatus: String? = nil,
    drawingPreview: DrawingStudioPreview? = nil
  ) {
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
    self.paperReplacementStatus = paperReplacementStatus
    self.drawingPreview = drawingPreview
    self.drawBorder = drawBorder
    self.editingIsEnabled = editingIsEnabled
    self.runProjection = runProjection
    self.runState = runState
    self.coverageExperiment = coverageExperiment
    self.coverageAssessment = coverageAssessment
    self.coverageUnavailableReason = coverageUnavailableReason
    self.coverageSelectedTrial = coverageSelectedTrial
    self.residualRecords = residualRecords
    self.residualAnalysis = residualAnalysis
  }

  var controls: [DrawingStudioControl] {
    switch runState {
    case .unavailable, .publicationIncomplete:
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
          title: "Prepare Next Drawing",
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
          title: "Prepare Next Drawing",
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
          title: "Prepare Next Drawing",
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

/// Local request feedback is attributable to the authoring context that failed.
/// Camera frame traffic is intentionally absent: only changed authoring or
/// dependency facts supersede the message, even before Draw becomes ready.
/// A refusal may refine the displayed blocker text; that publication alone does
/// not supersede its own feedback. Captured submission facts also prevent a
/// delayed response from reviving feedback after its dependency was recovered.
struct DrawingStudioRequestRefusal: Equatable {
  let message: String
  private let draftRevision: PlotterDrawingDraftRevision
  private let environment: PlotterEnvironment
  private let registration: LearningArtifactRevisionID?
  private let region: DrawableMachineRegion?
  private let paper: PaperRevisionContext
  private let optics: CameraOpticalConfigurationIdentity?
  private let runInProgress: Bool
  private let terminalRequiresNewPlan: Bool
  private let tool: ToolAssemblyRevision
  private let learningIsComplete: Bool

  init(_ message: String, presentation: DrawingStudioPresentation) {
    self.message = message
    let projection = presentation.canvas.draftProjection
    draftRevision = projection.draftRevision
    environment = projection.environment
    registration = projection.externalFacts.registrationRevisionID
    region = projection.externalFacts.drawableRegion
    paper = projection.externalFacts.paper
    optics = projection.externalFacts.opticalConfiguration
    runInProgress = projection.externalFacts.runInProgress
    terminalRequiresNewPlan = projection.externalFacts.terminalRequiresNewPlan
    tool = projection.externalFacts.toolAssemblyRevision
    learningIsComplete = projection.externalFacts.interactiveLearningIsComplete
  }

  func currentMessage(in presentation: DrawingStudioPresentation) -> String? {
    self == Self(message, presentation: presentation) ? message : nil
  }
}

/// Selection and transform shell for an already-projected drawing program.
/// Every mutation is returned as a typed intent; the view owns no planner,
/// controller, evidence store, or readiness decision.
struct DrawingStudioView<BeforeRun: View>: View {
  let presentation: DrawingStudioPresentation
  let plotterUIProjection: PlotterUIProjection
  let plotterUIIntentSink: any PlotterUIIntentSink
  let panel: WorkbenchPanel
  private let beforeRun: BeforeRun
  private let openReviewer: (() -> Void)?
  @State private var requestRefusal: DrawingStudioRequestRefusal?
  @State private var draftFeedback = OperatorRequestFeedback()
  @State private var scaleDraft: Double?
  @State private var rotationDraft: Double?
  @State private var scaleIsEditing = false
  @State private var rotationIsEditing = false

  init(
    presentation: DrawingStudioPresentation,
    plotterUIProjection: PlotterUIProjection,
    plotterUIIntentSink: any PlotterUIIntentSink,
    panel: WorkbenchPanel = .activeLearning,
    openReviewer: (() -> Void)? = nil,
    @ViewBuilder beforeRun: () -> BeforeRun
  ) {
    self.presentation = presentation
    self.plotterUIProjection = plotterUIProjection
    self.plotterUIIntentSink = plotterUIIntentSink
    self.panel = panel
    self.openReviewer = openReviewer
    self.beforeRun = beforeRun()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if draftFeedback.isPending {
        HStack {
          ProgressView().controlSize(.small)
          Text("Updating drawing")
        }
      }
      if let message = requestRefusal?.currentMessage(in: presentation),
        message != presentation.runState.detail {
        Label(message, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .textSelection(.enabled)
      }

      if panel == .activeLearning {
        coverageExperiment.disabled(draftFeedback.isPending)
        retrospectiveLearning.disabled(draftFeedback.isPending)
      }
      if panel == .drawing || presentation.coverageExperiment != nil {
        if presentation.coverageExperiment == nil {
          VStack(alignment: .leading, spacing: 0) {
            placement.disabled(draftFeedback.isPending)
          }
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier("drawing.section.placement")
        }
        if panel == .drawing {
          beforeRun
        }
        VStack(alignment: .leading, spacing: 8) {
          runStatus
          controls
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawing.section.run")
      }
    }
    .accessibilityElement(children: .contain)
  }

  private var retrospectiveLearning: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Learn from Drawing results").font(.headline)
      if presentation.residualRecords.isEmpty {
        Text("Drawing results will appear here for residual analysis.")
          .font(.caption).foregroundStyle(.secondary)
      }
      ForEach(presentation.residualRecords, id: \.recordID) { record in
        Toggle(isOn: Binding(get: { record.isSelected }, set: {
          WorkbenchRequestTelemetry.nativeActionHandled("learning.record.\(record.recordID.rawValue.uuidString)")
          submitDraft(.selectResidualRecord(record.recordID, selected: $0))
        })) {
          VStack(alignment: .leading, spacing: 2) {
            Text(record.title)
            Text(record.detail).font(.caption).foregroundStyle(.secondary)
          }
        }
        .accessibilityIdentifier("learning.record.\(record.recordID.rawValue.uuidString)")
      }
      if !presentation.residualRecords.isEmpty {
        Button("Analyze for Learning") {
          WorkbenchRequestTelemetry.nativeActionHandled("learning.analyzeDrawings")
          submitDraft(.analyzeSelectedResiduals)
        }
          .disabled(draftRequest(.analyzeSelectedResiduals) == nil)
          .accessibilityIdentifier("learning.analyzeDrawings")
      }
      if let analysis = presentation.residualAnalysis {
        Text(analysis.summary).font(.caption).textSelection(.enabled)
          .accessibilityIdentifier("learning.residualResult")
          .accessibilityValue(analysis.summary)
      }
    }
  }

  private var coverageExperiment: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Coverage Exercises").font(.headline)
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
          .accessibilityIdentifier(control.intent == .prepareCoverageExperiment ? "learning.coverage.prepare"
            : control.intent == .nextCoverageTrial ? "learning.coverage.next" : "learning.coverage.leave")
      }
      if presentation.coverageExperiment != nil {
        Text("Review and Run each proposed line. After its evidence settles, use Prepare Next Drawing, then Next Experiment Trial. Stop ends the current trial; an inconclusive trial halts the experiment.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private var placement: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Placement").font(.headline)
      HStack {
        Menu("Geometry", systemImage: "ruler") {
          nominalScaleAction
          Divider()
          ForEach([DrawingCatalogEntryID.square, .circle], id: \.self) { id in
            Button("Camera " + DrawingProgramCatalog.entry(for: id).displayName) {
              WorkbenchRequestTelemetry.nativeActionHandled("drawing.testTarget." + id.rawValue)
              submitDraft(.selectCatalogItem(id))
            }
            .disabled(!presentation.authoringIsEnabled || draftRequest(.selectCatalogItem(id)) == nil)
            .accessibilityIdentifier("drawing.testTarget." + id.rawValue)
          }
          Divider()
          ForEach([DrawingCatalogEntryID.metricSquare40, .metricRectangle40x20], id: \.self) { id in
            Button(DrawingProgramCatalog.entry(for: id).displayName) {
              WorkbenchRequestTelemetry.nativeActionHandled("drawing.testTarget." + id.rawValue)
              submitDraft(.selectCatalogItem(id))
            }
            .disabled(!presentation.authoringIsEnabled || draftRequest(.selectCatalogItem(id)) == nil)
            .accessibilityIdentifier("drawing.testTarget." + id.rawValue)
          }
          Divider()
          Button("Show Target") { submitDraft(.showTarget) }
            .disabled(draftRequest(.showTarget) == nil)
            .accessibilityIdentifier("drawing.testTarget.show")
        }
        .accessibilityIdentifier("drawing.testTarget")
        StudioHelpButton("Geometry", text: "Nominal Scale sets the selected drawing to its declared controller dimensions. Physical accuracy requires measurement. Camera square and circle use Guided Learning to preserve visible proportions. Metric targets retain controller distances.")
      }
      Toggle("Draw border", isOn: Binding(
        get: { presentation.drawBorder },
        set: { submitDraft(.setDrawBorder($0)) }))
        .disabled(!presentation.authoringIsEnabled
          || draftRequest(.setDrawBorder(!presentation.drawBorder)) == nil)
        .accessibilityIdentifier("drawing.drawBorder")
        .help("Ink the calibrated Drawing Border as part of this drawing. The outline stays visible when off.")
      StudioHelpButton("Placement", text: presentation.canvas.placement.locationText)
      HStack {
        Text("Size")
        Slider(
          value: Binding(
            get: { scaleDraft ?? presentation.canvas.placement.uniformScale },
            set: {
              WorkbenchRequestTelemetry.nativeActionHandled("drawing.scale")
              let allowed = presentation.canvas.placement.allowedScale
              scaleDraft = min(allowed.upperBound,
                max(allowed.lowerBound, ($0 * 100).rounded() / 100))
              if !scaleIsEditing { commitScale() }
            }
          ),
          in: presentation.canvas.placement.allowedScale,
          onEditingChanged: { editing in
            scaleIsEditing = editing
            if !editing { commitScale() }
          }
        )
        .accessibilityIdentifier("drawing.scale")
        Text(String(format: "%.2f×", scaleDraft ?? presentation.canvas.placement.uniformScale))
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
            get: { rotationDraft ?? presentation.canvas.placement.rotationDegrees },
            set: {
              WorkbenchRequestTelemetry.nativeActionHandled("drawing.rotation")
              rotationDraft = $0.rounded()
              if !rotationIsEditing { commitRotation() }
            }
          ),
          in: -180...180,
          onEditingChanged: { editing in
            rotationIsEditing = editing
            if !editing { commitRotation() }
          }
        )
        .accessibilityIdentifier("drawing.rotation")
        Text(String(format: "%.1f°", rotationDraft ?? presentation.canvas.placement.rotationDegrees))
          .monospacedDigit()
          .frame(width: 58, alignment: .trailing)
      }
      .disabled(
        !presentation.authoringIsEnabled
          || draftRequest(
            .setRotationDegrees(presentation.canvas.placement.rotationDegrees)
          ) == nil
      )
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 8) { placementActions }
        VStack(alignment: .leading, spacing: 8) { placementActions }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("drawing.placement")
    .accessibilityValue("\(presentation.canvas.placement.locationText); scale \(presentation.canvas.placement.uniformScale); rotation \(presentation.canvas.placement.rotationDegrees) degrees")
  }

  private var nominalScaleAction: some View {
    Button("Nominal Scale (100%)") {
      WorkbenchRequestTelemetry.nativeActionHandled("drawing.scale100")
      scaleDraft = nil
      submitDraft(.setUniformScale(1))
    }
    .disabled(!presentation.authoringIsEnabled
      || !presentation.canvas.placement.allowedScale.contains(1)
      || draftRequest(.setUniformScale(1)) == nil)
    .accessibilityIdentifier("drawing.scale100")
    .help("Set the target to its declared dimensions in controller millimeters. Physical accuracy requires measurement.")
  }

  @ViewBuilder
  private var placementActions: some View {
    Button {
      submitDraft(.centerInDrawableRegion)
    } label: {
      Label("Center Drawing", systemImage: "scope")
    }
    .operatorButton(.neutral)
    .disabled(
      !presentation.authoringIsEnabled || draftRequest(.centerInDrawableRegion) == nil
    )
    Button("Fit to Drawing Area") {
      WorkbenchRequestTelemetry.nativeActionHandled("drawing.fit")
      submitDraft(.fitInDrawableRegion)
    }
    .disabled(draftRequest(.fitInDrawableRegion) == nil)
    .accessibilityIdentifier("drawing.fit")
  }

  private var runStatus: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(presentation.paperReplacementStatus == nil ? presentation.runState.title : "Sheet recorded")
        .font(.headline)
      StudioHelpButton("Drawing status", text: presentation.paperReplacementStatus ?? presentation.runState.detail)
    }
  }

  var positionRecoveryButton: OperatorRequestButton? {
    guard let action = plotterUIProjection.actions.first(where: {
      guard case .learningAction(let request) = $0.intent else { return false }
      return request.action == .tipCalibration(.revalidateCheckpoint)
    }) else { return nil }
    return OperatorRequestButton(title: "Re-establish Position from Camera", role: .affirmative,
      request: plotterUIProjection.request(for: action.id),
      unavailableReason: action.isAvailable ? nil
        : action.unavailableReason ?? "Refresh position verification availability.",
      sink: plotterUIIntentSink, showsUnavailableReason: false)
  }

  private var positionPenPreparation: PositionPenPreparationControls {
    PositionPenPreparationControls(plotterUIProjection: plotterUIProjection,
      plotterUIIntentSink: plotterUIIntentSink)
  }

  var positionRaisePenButton: OperatorRequestButton? {
    positionRecoveryButton == nil ? nil : positionPenPreparation.raisePenButton
  }

  private var controls: some View {
    VStack(alignment: .leading, spacing: 8) {
      if positionRecoveryButton != nil {
        positionPenPreparation
      }
      if let positionRecoveryButton {
        positionRecoveryButton.accessibilityIdentifier("drawing.reestablishPosition")
      }
      // Keep each request button at one structural identity across resizing;
      // its pending/result feedback must survive a narrow panel.
      runActions
    }
  }

  @ViewBuilder
  private var runActions: some View {
    if case .unavailable(let reason) = presentation.runState {
      OperatorRequestButton(title: "Draw", role: .affirmative, request: nil,
        unavailableReason: reason, sink: plotterUIIntentSink, showsUnavailableReason: false)
        .accessibilityIdentifier("drawing.draw")
    }
    ForEach(presentation.controls) { control in
      let intent = PlotterUIIntent.drawingRun(control.intent)
      let request = plotterUIProjection.request(matching: intent)
      if case .pinReview = control.intent, let openReviewer {
        Button("Review Run", action: openReviewer)
          .accessibilityIdentifier("drawing.Review Run")
      } else {
        OperatorRequestButton(
          title: control.intent == .start ? "Draw" : control.title, role: control.role,
          request: control.isEnabled ? request : nil,
          unavailableReason: request == nil ? "Refresh the current Drawing Studio control." : nil,
          sink: plotterUIIntentSink,
          nativeActionIdentifier: control.intent == .start ? "drawing.draw" : nil
        )
        .accessibilityIdentifier(control.intent == .start ? "drawing.draw" : "drawing.\(control.title)")
      }
    }
  }

  private func commitScale() {
    guard let value = scaleDraft else { return }
    scaleDraft = nil
    guard value != presentation.canvas.placement.uniformScale else { return }
    submitDraft(.setUniformScale(value))
  }

  private func commitRotation() {
    guard let value = rotationDraft else { return }
    rotationDraft = nil
    guard value != presentation.canvas.placement.rotationDegrees else { return }
    submitDraft(.setRotationDegrees(value))
  }

  private func submitDraft(_ intent: PlotterDrawingDraftIntent) {
    submit(.drawingDraft(intent))
  }

  private func draftRequest(_ intent: PlotterDrawingDraftIntent) -> PlotterUIRequest? {
    plotterUIProjection.request(matching: .drawingDraft(intent))
  }

  private func submit(_ intent: PlotterUIIntent) {
    guard let request = plotterUIProjection.request(matching: intent) else {
      requestRefusal = DrawingStudioRequestRefusal(
        "Refresh the current Drawing Studio control before retrying.", presentation: presentation)
      return
    }
    guard draftFeedback.begin() else { return }
    requestRefusal = nil
    Task { @MainActor in
      let disposition = await plotterUIIntentSink.submitPlotterUIRequest(request)
      draftFeedback.finish(disposition)
      if case .refused(let refusal) = disposition {
        requestRefusal = DrawingStudioRequestRefusal(refusal.remedy, presentation: presentation)
      } else {
        requestRefusal = nil
      }
    }
  }

}

extension DrawingStudioView where BeforeRun == EmptyView {
  init(
    presentation: DrawingStudioPresentation,
    plotterUIProjection: PlotterUIProjection,
    plotterUIIntentSink: any PlotterUIIntentSink,
    panel: WorkbenchPanel = .activeLearning
  ) {
    self.init(presentation: presentation, plotterUIProjection: plotterUIProjection,
      plotterUIIntentSink: plotterUIIntentSink, panel: panel) { EmptyView() }
  }
}

/// Both recovery surfaces forward the same current finite Manual pen operation.
/// No local Stop is offered because that owner awaits finite pen settlement.
struct PositionPenPreparationControls: View {
  let plotterUIProjection: PlotterUIProjection
  let plotterUIIntentSink: any PlotterUIIntentSink

  var raisePenButton: OperatorRequestButton? {
    guard let action = plotterUIProjection.action(id: PlotterAppUIActionID.manualPenUp) else { return nil }
    return OperatorRequestButton(title: action.title, role: .affirmative,
      request: plotterUIProjection.request(for: action.id),
      unavailableReason: action.isAvailable ? nil : action.unavailableReason,
      sink: plotterUIIntentSink, showsUnavailableReason: false)
  }

  var prerequisiteText: String {
    let recovery = plotterUIProjection.actions.first {
      guard case .learningAction(let request) = $0.intent else { return false }
      return request.action == .tipCalibration(.revalidateCheckpoint)
    }
    return recovery?.unavailableReason ?? "The pen is raised. Use the camera to find its position."
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if let raisePenButton {
        raisePenButton.accessibilityIdentifier("positionRecovery.raisePen")
      }
      HStack {
        Text("Position verification").font(.caption).foregroundStyle(.secondary)
        StudioHelpButton("Position verification", text: prerequisiteText)
      }
    }
  }
}
