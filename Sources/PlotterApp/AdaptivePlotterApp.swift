import AppKit
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import PlotterUI
import SwiftUI

@MainActor
struct PlotterEpisodeComposition {
  let application: PlotterApplicationRuntime

  static func production() -> Self {
    let manualMotionComposition = PlotterManualMotionComposition.production
    let penInteractionRuntime = PlotterPenInteractionComposition.makeRuntime(
      machineSession: MachineSessionComposition.session,
      simulatedAdapter: manualMotionComposition.causalSimulatorEffectAdapter
    )
    let boundaryComposition = PlotterBoundaryComposition.make(
      machineSession: MachineSessionComposition.session,
      causalSimulator: manualMotionComposition.causalSimulatorEffectAdapter,
      statePersistencePort: AcceptedArtifactCheckpointComposition.statePersistencePort,
      speechEffectRuntime: SpeechComposition.runtime
    )
    let drawingRunComposition = PlotterDrawingRunComposition.make(
      machineSession: MachineSessionComposition.session,
      observationSession: CameraComposition.observationSession
    )
    let artifactResetComposition = PlotterArtifactResetComposition.make()
    let application = PlotterApplicationRuntime(
      machineSession: MachineSessionComposition.session,
      observationSession: CameraComposition.observationSession,
      observationRecordingStore: CameraComposition.recordingStore,
      pointSelectionRuntime: PointSelectionComposition.production.runtime,
      pointSelectionRecordingDiagnostic:
        PointSelectionComposition.production.recordingDiagnostic,
      manualMotionComposition: manualMotionComposition,
      penInteractionRuntime: penInteractionRuntime,
      boundaryRuntime: boundaryComposition.runtime,
      speechEffectRuntime: SpeechComposition.runtime,
      statePersistencePort: AcceptedArtifactCheckpointComposition.statePersistencePort,
      artifactResetRuntime: artifactResetComposition.runtime,
      drawingDraftRuntime: PaperCoverageComposition.drawingDraftRuntime,
      drawingRunComposition: drawingRunComposition,
      incidentPackageUIService: PlotterIncidentPackageUIService(
        sourceProvider: PlotterIncidentPackageUIUnavailableSourceProvider()
      ),
      tipCalibrationSemanticIdentities: TipCalibrationSemanticIdentityComposition.state,
      residualEffectPort: MachineSessionComposition.residualEffectPort
    )
    boundaryComposition.install(on: application)
    artifactResetComposition.install(on: application)
    return Self(application: application)
  }
}

@MainActor
final class AdaptivePlotterApplicationDelegate: NSObject, NSApplicationDelegate {
  let composition: PlotterEpisodeComposition
  var applicationRuntime: PlotterApplicationRuntime { composition.application }
  private var terminationTask: Task<Void, Never>?
  private var didReplyToTermination = false

  override init() {
    composition = .production()
    super.init()
  }

  func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool {
    false
  }

  func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool {
    false
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if terminationTask != nil { return .terminateLater }
    didReplyToTermination = false
    terminationTask = Task { [weak self] in
      guard let self else { return }
      await self.applicationRuntime.shutdown()
      self.completeTermination(of: sender)
    }
    return .terminateLater
  }

  private func completeTermination(of application: NSApplication) {
    guard !didReplyToTermination else { return }
    didReplyToTermination = true
    terminationTask?.cancel()
    terminationTask = nil
    application.reply(toApplicationShouldTerminate: true)
  }
}

struct PointSelectionRuntimeComposition: Sendable {
  let runtime: PlotterPointSelectionRuntime
  let recordingDiagnostic: String?
}

enum PointSelectionComposition {
  static let production = makeRuntime()

  static func makeRuntime(
    applicationSupportDirectory: () throws -> URL = {
      try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
    }
  ) -> PointSelectionRuntimeComposition {
    let recordingID = EpisodeRecordingID(rawValue: UUID())
    let manager = FileManager.default
    do {
      let applicationSupport = try applicationSupportDirectory()
      let directory = applicationSupport
        .appendingPathComponent("AdaptivePlotter", isDirectory: true)
        .appendingPathComponent("EpisodeRecordings", isDirectory: true)
        .appendingPathComponent(recordingID.rawValue.uuidString, isDirectory: true)
      try manager.createDirectory(at: directory, withIntermediateDirectories: true)
      let recordingStore = try EpisodeRecordingStore.open(
        directoryURL: directory,
        recordingID: recordingID,
        schemaRevision: EpisodeRecordingSchemaRevision(
          rawValue: "adaptive-plotter-point-selection-v1"
        ),
        frameRetentionPolicy: EpisodeFrameRetentionPolicy(
          maximumUniqueFrameCount: 64,
          maximumTotalUniqueFrameBytes: 512 * 1_024 * 1_024
        )
      )
      return PointSelectionRuntimeComposition(
        runtime: PlotterPointSelectionRuntime(recordingStore: recordingStore),
        recordingDiagnostic: nil
      )
    } catch {
      let diagnostic =
        "Point-selection recording is unavailable: \(error.localizedDescription)"
      return PointSelectionRuntimeComposition(
        runtime: PlotterPointSelectionRuntime(
          recordingUnavailableDiagnostic: diagnostic
        ),
        recordingDiagnostic: diagnostic
      )
    }
  }
}

@main
@MainActor
struct AdaptivePlotterApp: App {
  @NSApplicationDelegateAdaptor(AdaptivePlotterApplicationDelegate.self)
  private var applicationDelegate

  init() {
    UserDefaults.standard.set(true, forKey: "ApplePersistenceIgnoreState")
    UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
  }

  var body: some Scene {
    Window("AdaptivePlotter", id: AdaptivePlotterScenePolicy.singletonWindowID) {
      PlotterApplicationRuntimeView(application: applicationDelegate.applicationRuntime)
        .frame(
          minWidth: LearningWorkbenchLayoutPolicy.minimumWindowWidth,
          minHeight: AdaptivePlotterScenePolicy.minimumWindowHeight
        )
    }
    .windowToolbarStyle(.unifiedCompact)
  }
}

enum AdaptivePlotterScenePolicy {
  static let singletonWindowID = "operator-application"
  static let minimumWindowHeight: CGFloat = 700
}

enum AdaptivePlotterStartupRoute: Equatable, Sendable {
  case preferredCamera
  case simulated
}

struct AdaptivePlotterLaunchPolicy: Equatable, Sendable {
  static let simulatedArgument = "-AdaptivePlotterStartSimulated"
  let startupRoute: AdaptivePlotterStartupRoute

  init(arguments: [String]) {
    startupRoute =
      arguments.indices.contains { index in
        arguments[index] == Self.simulatedArgument
          && arguments.indices.contains(index + 1)
          && arguments[index + 1].caseInsensitiveCompare("YES") == .orderedSame
      } ? .simulated : .preferredCamera
  }

  static var current: Self {
    Self(arguments: CommandLine.arguments)
  }
}

private enum SpeechComposition {
  static let runtime = PlotterSpeechEffectRuntime(announcer: NativeSpeechAnnouncer())
}

struct VideoSettingsOperatorActionDisposition: Equatable {
  let layout: WorkbenchLayoutState
  let shouldRefreshDiagnostics: Bool
}

func videoSettingsOperatorActionDisposition(
  from layout: WorkbenchLayoutState,
  action: VideoSettingsVisibilityAction,
  availableWindowWidth: CGFloat,
  exerciseDetailMustRemainVisible: Bool,
  policy: VideoSettingsVisibilityPolicy
) -> VideoSettingsOperatorActionDisposition? {
  guard
    let nextLayout = policy.transition(
      from: layout,
      action: action,
      availableWindowWidth: availableWindowWidth,
      exerciseDetailMustRemainVisible: exerciseDetailMustRemainVisible
    )
  else { return nil }
  return VideoSettingsOperatorActionDisposition(
    layout: nextLayout,
    shouldRefreshDiagnostics:
      !layout.videoSettingsIsPresented && nextLayout.videoSettingsIsPresented
  )
}

struct PlotterApplicationRuntimeView: View {
  @Bindable var application: PlotterApplicationRuntime
  @State private var selection = LearningPathSelectionState(
    current: .humanGuidedDiscovery(.penInteraction)
  )
  @State private var layout = WorkbenchLayoutState()
  @State private var actionSurfaceViewport = ActionSurfaceViewportState()
  @State private var manualMotionDraft = ManualMotionDraft()
  @State private var debugSnapshot: WorkbenchDebugSnapshot?
  @State private var pendingDrawingPlacement: PlotterDrawingDraftCameraPlacement?
  @State private var pendingPointSelection: PlotterPointSelectionSubmission?
  private let videoSettingsPolicy = VideoSettingsVisibilityPolicy()

  var body: some View {
    let ui = application.plotterUIProjection(
      selectedItemID: selection.selected,
      manualDraft: manualMotionDraft,
      includesLearningPath:
        layout.panes.navigatorIsPresented || layout.panes.exerciseDetailIsPresented,
      pendingDrawingPlacement: pendingDrawingPlacement,
      pendingPointSelection: pendingPointSelection,
      observationViewport: actionSurfaceViewport
    )
    let actionSurfacePresentation = ui.actionSurface
    let exercisePaneProtection = ui.exercisePaneProtection
    let learningMode = ui.learningMode
    let learningProjection = ui.learningPath
    let motionCollapseUnavailableReason = ui.manualMotion.stopAction == nil
      ? nil : "Stop the active manual jog before hiding its Stop control."

    GeometryReader { proxy in
      let exerciseCollapseReason =
        exerciseDetailCollapseUnavailableReason(exercisePaneProtection)
      let videoSettings = videoSettingsPolicy.presentation(
        layout: layout,
        availableWindowWidth: proxy.size.width,
        exerciseDetailMustRemainVisible: exercisePaneProtection.mustRemainVisible
      )
      VStack(spacing: 0) {
          WorkbenchPaneControls(
            visibility: layout.panes,
            videoSettings: videoSettings,
            exerciseDetailCollapseUnavailableReason:
              exerciseCollapseReason,
            motionCollapseUnavailableReason: motionCollapseUnavailableReason,
            learningIsEnabled: learningMode.isEnabled,
            learningActionTitle: learningMode.actionTitle,
            learningModeRemedy: learningMode.remedy,
            learningRecordingDiagnostic: learningMode.recordingDiagnostic,
            drawingStudioIsAvailable: ui.workbenchCapability.drawingStudioIsAvailable,
            drawingStudioIsPresented: ui.drawingStudioIsPresented,
            drawingStudioChangeUnavailableReason: ui.drawingStudioPanelChangeUnavailableReason,
            showDiagnostics: { debugSnapshot = WorkbenchDebugSnapshot(application: application, projection: ui.semantic) },
            plotterUIProjection: ui.semantic,
            plotterUIIntentSink: application,
            togglePane: { pane in
              layout = layout.toggling(pane)
            },
            performVideoSettingsAction: { action in
              performVideoSettingsAction(
                action,
                availableWindowWidth: proxy.size.width,
                exercisePaneProtection: exercisePaneProtection,
                projection: ui.semantic
              )
            }
          )

      Divider()
      HSplitView {
        if ui.learningIsEnabled, layout.panes.navigatorIsPresented,
          let learningProjection
        {
          LearningPathNavigator(
            selection: $selection,
            projection: learningProjection,
            currentLearningPathItemID: ui.currentLearningPathItemID,
            plotterUIProjection: ui.semantic,
            plotterUIIntentSink: application,
            close: { layout = layout.toggling(.navigator) }
          )
          .frame(minWidth: 220, idealWidth: 240, maxWidth: 300)
        }

        VStack(spacing: 0) {

          VSplitView {
            PreviewingActionSurface(
              preview: application.actionSurfacePreview,
              presentation: actionSurfacePresentation,
              viewport: $actionSurfaceViewport,
              plotterUIProjection: ui.semantic,
              plotterUIIntentSink: application,
              pendingDrawingPlacement: $pendingDrawingPlacement,
              pendingPointSelection: $pendingPointSelection
            )
            .frame(
              minWidth: LearningWorkbenchLayoutPolicy.minimumActionSurfaceWidth,
              minHeight: LearningWorkbenchLayoutPolicy.minimumActionSurfaceHeight
            )

            if layout.panes.motionIsPresented {
              ScrollView {
                MotionPanel(
                  draft: $manualMotionDraft,
                  presentation: ui.manualMotion,
                  controllerSession: ui.controllerSession,
                  learningIsEnabled: ui.learningIsEnabled,
                  plotterUIProjection: ui.semantic,
                  plotterUIIntentSink: application,
                  close: { layout = layout.toggling(.motion) },
                  closeUnavailableReason: motionCollapseUnavailableReason
                )
                .padding(10)
              }
              .frame(minHeight: 220, idealHeight: 260, maxHeight: 360)
              .background(Color(nsColor: .controlBackgroundColor))
            }
          }
        }
        .frame(
          minWidth: LearningWorkbenchLayoutPolicy.minimumActionSurfaceWidth,
          maxWidth: .infinity,
          maxHeight: .infinity
        )

        if ui.drawingStudioIsPresented {
          VStack(spacing: 0) {
            HStack {
              Text("Drawing Studio").font(.headline)
              Spacer()
              Button {
                submitPlotterUIAction(PlotterAppUIActionID.drawingClose, in: ui.semantic)
              } label: {
                Image(systemName: "xmark")
              }
              .buttonStyle(.plain)
              .disabled(ui.drawingStudioPanelChangeUnavailableReason != nil)
              .help(
                ui.drawingStudioPanelChangeUnavailableReason
                  ?? "Close Drawing Studio"
              )
            }
            .padding(12)

            Divider()
            VStack(alignment: .leading, spacing: 8) {
              Text(ui.workbenchCapability.paper.title)
                .font(.subheadline.bold())
              Text(ui.workbenchCapability.paper.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
              HStack {
                Button("Assert Sheet Covers Outline") {
                  submitPlotterUIAction(
                    PlotterAppUIActionID.drawingDraft(.assertPaperCoverage),
                    in: ui.semantic
                  )
                }
                .operatorButton(.affirmative)
                .disabled(ui.paperManagementUnavailableReason != nil)
                Menu("Paper Management") {
                  Button("New Sheet — Same Contact Plane") {
                    submitPlotterUIAction(PlotterAppUIActionID.paperNewSheet, in: ui.semantic)
                  }
                  Button("Contact Plane Changed") {
                    submitPlotterUIAction(PlotterAppUIActionID.paperContactPlane, in: ui.semantic)
                  }
                }
                .disabled(ui.paperManagementUnavailableReason != nil)
              }
              .help(
                ui.paperManagementUnavailableReason
                  ?? "Confirm or deliberately change the current physical paper context."
              )
            }
            .padding(12)
            Divider()
            ScrollView {
              DrawingStudioView(
                presentation: ui.drawingStudio,
                plotterUIProjection: ui.semantic,
                plotterUIIntentSink: application
              )
            }
          }
          .frame(minWidth: 340, idealWidth: 390, maxWidth: 500)
          .background(Color(nsColor: .controlBackgroundColor))
        }

        if ui.learningIsEnabled, layout.panes.exerciseDetailIsPresented,
          let learningProjection
        {
          LearningPathView(
            selection: $selection,
            projection: learningProjection,
            currentLearningPathItemID: ui.currentLearningPathItemID,
            plotterUIProjection: ui.semantic,
            plotterUIIntentSink: application,
            close: { layout = layout.toggling(.exerciseDetail) },
            closeUnavailableReason: exerciseCollapseReason,
            speechRuntime: application.speechEffectRuntime
          )
          .frame(minWidth: 300, idealWidth: 340, maxWidth: 460)
        }
      }
      }
      .onChange(of: proxy.size.width) { _, width in
        layout = layout.collapsingVideoSettingsIfNeeded(
          availableContentWidth: width,
          policy: videoSettingsPolicy
        )
      }
    }
    .inspector(
      isPresented: Binding(
        get: { layout.videoSettingsIsPresented },
        set: { isPresented in
          if !isPresented { layout = layout.hidingVideoSettings() }
        }
      )
    ) {
      VideoSettingsPanel(
        projection: ui.observationConfiguration,
        plotterUIProjection: ui.semantic,
        plotterUIIntentSink: application,
        application: application,
        preview: application.actionSurfacePreview,
        actionSurfacePresentation: actionSurfacePresentation,
        viewport: $actionSurfaceViewport,
        close: { layout = layout.hidingVideoSettings() }
      )
      .inspectorColumnWidth(
        min: OverlayCardLayoutPolicy.minimumInspectorWidth,
        ideal: OverlayCardLayoutPolicy.idealInspectorWidth,
        max: OverlayCardLayoutPolicy.maximumInspectorWidth
      )
    }
    .onChange(of: ui.currentLearningPathItemID, initial: true) { _, itemID in
      selection.updateCurrent(itemID)
    }
    .toolbar {
      WorkbenchToolbar(
        controllerSession: ui.controllerSession,
        observationConfiguration: ui.observationConfiguration,
        motionRequestStatus: ui.motionRequestStatus,
        plotterUIProjection: ui.semantic,
        plotterUIIntentSink: application,
        capabilityPresentation: ui.workbenchCapability
      )
    }
    .toolbarRole(.editor)
    .sheet(item: $debugSnapshot) { WorkbenchDiagnosticsView(snapshot: $0) }
    .task {
      await application.performApplicationStartup(AdaptivePlotterLaunchPolicy.current)
      await RunningAppPreviewPerformanceGate.runIfRequested(application: application)
    }
  }

  private func exerciseDetailCollapseUnavailableReason(
    _ presentation: ExercisePaneProtectionPresentation
  ) -> String? {
    guard presentation.mustRemainVisible else { return nil }
    return "Finish or cancel the active exercise attempt before hiding its controls."
  }

  private func submitPlotterUIAction(
    _ actionID: PlotterUIActionID,
    in projection: PlotterUIProjection
  ) {
    Task { _ = await application.submitProjectedAction(actionID, in: projection) }
  }

  private func performVideoSettingsAction(
    _ action: VideoSettingsVisibilityAction,
    availableWindowWidth: CGFloat,
    exercisePaneProtection: ExercisePaneProtectionPresentation,
    projection: PlotterUIProjection
  ) {
    guard
      let disposition = videoSettingsOperatorActionDisposition(
        from: layout,
        action: action,
        availableWindowWidth: availableWindowWidth,
        exerciseDetailMustRemainVisible: exercisePaneProtection.mustRemainVisible,
        policy: videoSettingsPolicy
      )
    else { return }
    layout = disposition.layout
    guard disposition.shouldRefreshDiagnostics else { return }
    submitPlotterUIAction(PlotterAppUIActionID.observationDiagnostics, in: projection)
  }
}

private struct WorkbenchPaneControls: View {
  @State private var requestRefusal: String?
  let visibility: WorkbenchPaneVisibility
  let videoSettings: VideoSettingsPresentation
  let exerciseDetailCollapseUnavailableReason: String?
  let motionCollapseUnavailableReason: String?
  let learningIsEnabled: Bool
  let learningActionTitle: String
  let learningModeRemedy: String?
  let learningRecordingDiagnostic: String?
  let drawingStudioIsAvailable: Bool
  let drawingStudioIsPresented: Bool
  let drawingStudioChangeUnavailableReason: String?
  let showDiagnostics: () -> Void
  let plotterUIProjection: PlotterUIProjection
  let plotterUIIntentSink: any PlotterUIIntentSink
  let togglePane: (WorkbenchPane) -> Void
  let performVideoSettingsAction: (VideoSettingsVisibilityAction) -> Void

  var body: some View {
    let learningRequest = plotterUIProjection.request(
      matching: .learning(.setEnabled(!learningIsEnabled))
    )
    HStack(spacing: 8) {
      Button {
        submit(PlotterAppUIActionID.learningMode)
      } label: {
        Label(
          learningActionTitle,
          systemImage: "book"
        )
      }
      .operatorButton(isEnabled: learningModeRemedy == nil && learningRequest != nil)
      .controlSize(.small)
      .help(
        learningModeRemedy
          ?? "Learning is ergonomic workflow guidance; turning it off preserves learned evidence and leaves direct machine controls available."
      )
      if let learningModeRemedy {
        Label(learningModeRemedy, systemImage: "exclamationmark.triangle.fill")
          .font(.caption2)
          .foregroundStyle(.orange)
          .lineLimit(1)
          .help(learningModeRemedy)
      }
      if let requestRefusal {
        Label(requestRefusal, systemImage: "exclamationmark.triangle.fill")
          .font(.caption2)
          .foregroundStyle(.orange)
          .lineLimit(2)
          .help(requestRefusal)
      }
      if let learningRecordingDiagnostic {
        Label(learningRecordingDiagnostic, systemImage: "externaldrive.badge.exclamationmark")
          .font(.caption2)
          .foregroundStyle(.orange)
          .lineLimit(1)
          .help(learningRecordingDiagnostic)
      }
      Spacer(minLength: 12)
      Menu {
        if learningIsEnabled {
          paneToggle(.navigator, panel: .learningPath)
          paneToggle(
            .exerciseDetail, panel: .exercise,
            unavailableReason: exerciseDetailCollapseUnavailableReason
          )
        }
        paneToggle(.motion, panel: .motion, unavailableReason: motionCollapseUnavailableReason)
        Toggle(WorkbenchPanel.videoSettings.title, isOn: Binding(
          get: { videoSettings.isPresented },
          set: { _ in performVideoSettingsAction(videoSettings.action) }
        ))
        .disabled(!videoSettings.isActionEnabled)
        .help(videoSettings.unavailableReasonText ?? "Camera configuration and measured overlays")
        if drawingStudioIsAvailable {
          Toggle("Drawing Studio", isOn: Binding(
            get: { drawingStudioIsPresented },
            set: { presented in
              submit(presented ? PlotterAppUIActionID.drawingOpen : PlotterAppUIActionID.drawingClose)
            }
          ))
          .disabled(drawingStudioChangeUnavailableReason != nil)
        }
        Divider()
        Button("Diagnostics…", action: showDiagnostics)
          .keyboardShortcut("d", modifiers: [.command, .shift])
      } label: {
        Label("View", systemImage: "rectangle.split.3x1")
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  @ViewBuilder
  private func paneToggle(
    _ pane: WorkbenchPane,
    panel: WorkbenchPanel,
    unavailableReason: String? = nil
  ) -> some View {
    Toggle(panel.title, isOn: Binding(
      get: { visibility.isPresented(pane) },
      set: { _ in togglePane(pane) }
    ))
    .disabled(unavailableReason != nil && visibility.isPresented(pane))
    .help(unavailableReason ?? panel.title)
  }

  private func submit(_ actionID: PlotterUIActionID) {
    Task { @MainActor in
      guard let disposition = await plotterUIIntentSink.submitProjectedAction(
        actionID,
        in: plotterUIProjection
      ) else {
        requestRefusal = "Refresh the current action before retrying."
        return
      }
      if case .refused(let refusal) = disposition {
        requestRefusal = refusal.remedy
      } else {
        requestRefusal = nil
      }
    }
  }


}

private struct VideoSettingsPanel: View {
  let projection: PlotterObservationConfigurationProjection
  let plotterUIProjection: PlotterUIProjection
  let plotterUIIntentSink: any PlotterUIIntentSink
  let application: PlotterApplicationRuntime
  let preview: ActionSurfacePreviewModel
  let actionSurfacePresentation: ActionSurfacePresentation
  @Binding var viewport: ActionSurfaceViewportState
  let close: () -> Void

  var body: some View {
    VStack(spacing: 10) {
      HStack {
        Text("Video Settings")
          .font(.headline)
        Spacer()
        PanelCloseButton(panel: .videoSettings, close: close)
      }

      ScrollView {
        VideoSettingsContents(
          projection: projection,
          plotterUIProjection: plotterUIProjection,
          plotterUIIntentSink: plotterUIIntentSink,
          application: application,
          preview: preview,
          actionSurfacePresentation: actionSurfacePresentation,
          viewport: $viewport
        )
      }
    }
    .padding(10)
  }
}

private enum VideoSourceChoice: Hashable {
  case simulated
  case live(CameraDeviceID)
}

private struct VideoSettingsContents: View {
  let projection: PlotterObservationConfigurationProjection
  let plotterUIProjection: PlotterUIProjection
  let plotterUIIntentSink: any PlotterUIIntentSink
  let application: PlotterApplicationRuntime
  let preview: ActionSurfacePreviewModel
  let actionSurfacePresentation: ActionSurfacePresentation
  @Binding var viewport: ActionSurfaceViewportState

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionPanel(title: "CAMERA") {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text("Camera")
            .font(.caption)
            .foregroundStyle(.secondary)
          Picker("Camera", selection: sourceSelection) {
            Text("Simulator").tag(Optional(VideoSourceChoice.simulated))
            ForEach(projection.cameraDevices) { device in
              Text(device.name).tag(Optional(VideoSourceChoice.live(device.id)))
            }
          }
          .labelsHidden()
          .frame(maxWidth: .infinity)
          .disabled(projection.sourceChangeUnavailableReason != nil)
          .help(projection.sourceChangeUnavailableReason ?? "Choose the video source")

          Button {
            submit(PlotterAppUIActionID.observationRefresh)
          } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
          }
          .operatorButton(isEnabled: projection.calibrationBusyReason == nil)
          .help(projection.calibrationBusyReason ?? "Refresh camera choices")
        }

        if projection.frameMode == .simulated {
          Text(projection.simulatorEvidenceLabel)
            .font(.caption.monospaced().bold())
            .foregroundStyle(.blue)
          Text(projection.simulatorSummary)
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if projection.cameraDevices.isEmpty {
          Text("No discovered camera.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

      }

      analysisViewportControls
      overlayControls

      SectionPanel(title: "STATUS") {
        fact("State", projection.cameraStateText)
        fact("Capture path", projection.captureThroughputText)
        fact("Analysis path", projection.visionThroughputText)
        if let error = projection.cameraError {
          Text(error)
            .font(.caption.monospaced())
            .foregroundStyle(.orange)
            .textSelection(.enabled)
        }
        if let error = projection.visionError {
          Text(error)
            .font(.caption.monospaced())
            .foregroundStyle(.orange)
            .textSelection(.enabled)
        }

      }
    }
  }

  private var analysisViewportControls: some View {
    let displayedFrame = actionSurfacePresentation
      .resolvingAmbientPreviewFrame(preview.displayedFrame)
      .displayedFrame
    let previewProjection = application.videoPreviewProjection(
      displayedFrame: actionSurfacePresentation.usesAmbientPreviewFrame ? displayedFrame : nil,
      observationViewport: viewport
    )
    let regionRequest = previewProjection.request(for: PlotterAppUIActionID.observationRegion)
    let region = displayedFrame.flatMap {
      viewport.selectedRegion(frameWidth: $0.frame.width, frameHeight: $0.frame.height)
    }
    let regionIsLocked =
      displayedFrame.map {
        projection.regionLock?.matches($0) == true
      } ?? false

    return SectionPanel(title: "ANALYSIS VIEWPORT") {
      Picker(
        "Frames per second",
        selection: Binding(
          get: { projection.cadence },
          set: { cadence in
            submit(PlotterAppUIActionID.observationCadence(cadence))
          }
        )
      ) {
        ForEach(VisionAnalysisCadence.allCases, id: \.self) { cadence in
          Text(cadence.displayValue).tag(cadence)
        }
      }
      .disabled(projection.frameMode != .live)

      Slider(value: $viewport.zoom, in: 0...1) {
        Text("Zoom")
      } minimumValueLabel: {
        Text("Full")
      } maximumValueLabel: {
        Text("Near")
      }
      .disabled(displayedFrame == nil || regionIsLocked)
      .help("Zoom the displayed camera pixels, then drag the video to position the region.")

      fact("Region", region.map(Self.regionText) ?? "No current frame")

      Toggle(
        "Lock analysis region",
        isOn: Binding(
          get: { regionIsLocked },
          set: { _ in
            guard regionRequest != nil else { return }
            submit(PlotterAppUIActionID.observationRegion, in: previewProjection)
          }
        )
      )
      .disabled(
        displayedFrame == nil || region == nil
          || regionRequest == nil
      )

      Text(
        regionIsLocked
          ? "Only this camera-pixel region is included in scene analysis. Unlock it before zooming or dragging."
          : "Zoom, then drag the video to position the region. Locking copies that camera-pixel rectangle into the analysis policy; it does not crop or rewrite the exact frame."
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
  }

  private var overlayControls: some View {
    return SectionPanel(title: "OVERLAYS") {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(projection.overlayCards, id: \.overlay) { presentation in
          overlayCard(presentation, projection: projection)
        }
      }

      if let selection = projection.penCapAppearance {
        HStack(spacing: 8) {
          Circle()
            .fill(selection.color.swiftUIColor)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(.primary.opacity(0.35), lineWidth: 1))
          Text("Learned pen-cap color #\(selection.color.hexRGB)")
            .font(.caption.monospaced())
        }
        Text(
          "Frame \(selection.frameID.rawValue) · config \(selection.cameraConfigurationID.rawValue) · click \(String(format: "%.1f", selection.clickPoint.x)), \(String(format: "%.1f", selection.clickPoint.y)) px · \(selection.usableSampleCount)/\(selection.totalSampleCount) usable · \(selection.algorithmRevision)"
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
      } else {
        Text("Not learned — use Identify Pen Cap")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }

      Text(
        "Pen-cap and inferred armature-envelope selections directly run bounded scene analysis after Identify Pen Cap learns a color. No separate Analyze or Resume action is required."
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
  }

  private func overlayCard(
    _ presentation: OverlayCardPresentation,
    projection: PlotterObservationConfigurationProjection
  ) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .center, spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text(presentation.title)
            .font(.callout.weight(.semibold))
          Text("Persistent scene preference")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 8)
        Text(presentation.selectionText)
          .font(.caption.monospaced().bold())
          .foregroundStyle(presentation.isOn ? Color.green : Color.red)
        Toggle(
          presentation.title,
          isOn: Binding(
            get: { projection.enabledOverlays.contains(presentation.overlay) },
            set: { enabled in
              submit(PlotterAppUIActionID.observationOverlay(
                presentation.overlay.rawValue,
                enabled: enabled
              ))
            }
          )
        )
        .labelsHidden()
        .toggleStyle(.switch)
        .accessibilityLabel("\(presentation.title) overlay preference")
        .accessibilityValue(presentation.selectionText)
        .accessibilityHint("Changes only the persistent scene-overlay preference.")
      }

      VStack(alignment: .leading, spacing: 4) {
        Text("STATUS")
          .font(.caption2.monospaced().bold())
          .foregroundStyle(.secondary)
        Text(presentation.statusText)
          .font(.caption)
          .foregroundStyle(overlayStatusColor(presentation.colorToken))
          .lineLimit(nil)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      }

      overlayFact("ROI", presentation.roiText)
      overlayFact("Cadence", presentation.cadenceText)
      overlayFact("Analyzed frame", presentation.frameText)
      overlayFact("Result age", presentation.resultAgeText)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    .accessibilityElement(children: .contain)
    .accessibilityLabel(presentation.accessibilityLabel)
    .accessibilityValue(presentation.accessibilityValue)
    .help(presentation.helpText)
  }

  private func overlayFact(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(label.uppercased())
        .font(.caption2.monospaced().bold())
        .foregroundStyle(.secondary)
      Text(value)
        .font(.caption2)
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }
  }

  private func overlayStatusColor(_ token: OverlayStatusColorToken) -> Color {
    switch token {
    case .affirmativeGreen: .green
    case .negativeRed: .red
    case .neutralGray: Color(red: 0.46, green: 0.48, blue: 0.51)
    case .unavailableDarkGray: Color(red: 0.20, green: 0.21, blue: 0.23)
    }
  }

  private var sourceSelection: Binding<VideoSourceChoice?> {
    return Binding(
      get: {
        switch projection.frameMode {
        case .simulated: return VideoSourceChoice.simulated
        case .live: return projection.selectedCameraID.map(VideoSourceChoice.live)
        }
      },
      set: { selection in
        guard let selection else { return }
        switch selection {
        case .simulated:
          submit(PlotterAppUIActionID.observationSimulated)
        case .live(let id):
          submit(PlotterAppUIActionID.observationCamera(id.rawValue))
        }
      }
    )
  }

  private func submit(_ actionID: PlotterUIActionID) {
    Task {
      _ = await plotterUIIntentSink.submitProjectedAction(actionID, in: plotterUIProjection)
    }
  }

  private func submit(_ actionID: PlotterUIActionID, in projection: PlotterUIProjection) {
    Task {
      _ = await plotterUIIntentSink.submitProjectedAction(actionID, in: projection)
    }
  }

  private static func regionText(_ region: PixelRect) -> String {
    "x \(region.x), y \(region.y), \(region.width) × \(region.height) px"
  }

  private func fact(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label).font(.caption2).foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .font(.caption.monospaced())
        .multilineTextAlignment(.trailing)
        .textSelection(.enabled)
    }
  }
}

extension PenCapColor {
  fileprivate var swiftUIColor: Color {
    Color(
      red: Double(red) / 255,
      green: Double(green) / 255,
      blue: Double(blue) / 255
    )
  }

}

private struct MotionPanel: View {
  @Binding var draft: ManualMotionDraft
  let presentation: ManualMotionPresentation
  let controllerSession: PlotterControllerSessionProjection
  let learningIsEnabled: Bool
  let plotterUIProjection: PlotterUIProjection
  let plotterUIIntentSink: any PlotterUIIntentSink
  let close: () -> Void
  let closeUnavailableReason: String?

  var body: some View {
    let session = controllerSession
    SectionPanel(
      title: "MANUAL RELATIVE MOTION",
      panel: .motion,
      close: close,
      closeUnavailableReason: closeUnavailableReason
    ) {
      Text(
        "Manual steps remain finite, bounded requests. Pen Up routes to carriage travel; Pen Down routes to a bounded drawing stroke. End-stops, alarms, one-operation serialization, commanded pen state, and ambiguous outcomes are checked directly."
      )
      .font(.caption2)
      .foregroundStyle(.secondary)

      HStack(spacing: 8) {
        numericField(
          ManualMotionPresentation.xDistanceLabel,
          text: $draft.xDistanceMM
        )
        numericField(
          ManualMotionPresentation.yDistanceLabel,
          text: $draft.yDistanceMM
        )
        numericField(
          ManualMotionPresentation.feedLabel,
          text: $draft.feedMMPerMinute
        )
      }

      VStack(spacing: 5) {
        jogButton("Y+", systemImage: "arrow.up", direction: .yPositive)
        HStack(spacing: 5) {
          jogButton("X−", systemImage: "arrow.left", direction: .xNegative)
          jogButton("X+", systemImage: "arrow.right", direction: .xPositive)
        }
        jogButton("Y−", systemImage: "arrow.down", direction: .yNegative)
      }
      .frame(maxWidth: .infinity)

      if let stop = presentation.stopAction {
        Button {
          submit(PlotterAppUIActionID.manualStop)
        } label: {
          Label(stop.title, systemImage: "stop.fill")
            .frame(maxWidth: .infinity)
        }
        .operatorButton(.negative)
        .keyboardShortcut(.cancelAction)
        .help(stop.detail)
        .accessibilityHint(stop.detail)
      }

      if let recovery = presentation.publicationRecovery {
        VStack(alignment: .leading, spacing: 5) {
          Text(recovery.remedy)
            .font(.caption)
            .foregroundStyle(.orange)
          Button {
            submit(PlotterAppUIActionID.manualRecovery)
          } label: {
            Label(recovery.title, systemImage: "arrow.clockwise.circle.fill")
              .frame(maxWidth: .infinity)
          }
          .operatorButton(.affirmative)
          .help(recovery.remedy)
          .accessibilityHint(recovery.remedy)
        }
      }

      if let evidence = presentation.evidenceDisposition {
        VStack(alignment: .leading, spacing: 5) {
          Text(evidence.remedy)
            .font(.caption)
            .foregroundStyle(.orange)
          Button {
            submit(PlotterAppUIActionID.manualEvidence)
          } label: {
            Label(evidence.title, systemImage: "checkmark.shield.fill")
              .frame(maxWidth: .infinity)
          }
          .operatorButton(.affirmative)
          .help(evidence.remedy)
          .accessibilityHint(evidence.remedy)
        }
      }

      HStack(spacing: 6) {
        Button {
          submit(PlotterAppUIActionID.manualPenUp)
        } label: {
          Label("Pen Up", systemImage: "arrow.up.to.line")
        }
        .operatorButton(
          isEnabled: presentation.penUpUnavailableReason == nil
        )
        Button {
          submit(PlotterAppUIActionID.manualPenDown)
        } label: {
          Label("Pen Down", systemImage: "arrow.down.to.line")
        }
        .operatorButton(
          isEnabled: presentation.penDownUnavailableReason == nil
        )
      }

      Text(presentation.penStateText)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Text("Commanded state is controller evidence only; the camera cannot observe pen height.")
        .font(.caption2)
        .foregroundStyle(.secondary)

      fact("Controller link", session.controllerConnectionText)
      fact("Controller", session.controllerStateText)
      fact("Controller alert", session.controllerAttentionText ?? "none reported")
      fact("Limit inputs", session.controllerLimitInputsText)
      fact("Alarm unlock", session.controllerAlarmUnlockReadinessText)
      if let alarm = session.controllerAlarmEvidenceText {
        VStack(alignment: .leading, spacing: 5) {
          Text("Reported alarm: \(alarm)")
            .font(.caption.monospaced())
            .foregroundStyle(.orange)
            .textSelection(.enabled)
          Text(
            "Clear Alarm is armed only when a sampled controller status reports Alarm with no X/Y/Z limit input asserted. The action checks those inputs again immediately before unlock. It does not home, recover position, enable Motion, or prove that movement is safe."
          )
          .font(.caption2)
          .foregroundStyle(.secondary)
          Button {
            submit(PlotterAppUIActionID.controllerClearAlarm)
          } label: {
            Label(
              session.alarmClearInProgress ? "Clearing Alarm…" : "Clear Alarm",
              systemImage: "exclamationmark.triangle.fill"
            )
          }
          .operatorButton(
            .negative,
            isEnabled: session.alarmClearUnavailableReason == nil
          )
          .help(
            session.alarmClearUnavailableReason
              ?? "Send one explicit alarm-unlock request, then run a fresh passive controller probe"
          )
        }
      }
      fact("Motor power", session.motorPowerText)
      fact("Motion", session.motionAuthorized ? "enabled" : "disabled")
      fact("Motion request", presentation.jogControlsUnavailableReason == nil ? "request eligible" : "unavailable")
      fact("Manual mode", presentation.modeText)
      fact("Learning", learningIsEnabled ? "on" : "off — manual operation")
      fact("MPos", session.machinePositionText)
      fact("Operation", session.currentOperationText)
      fact("Last outcome", session.lastMotionOutcomeText)
      fact("Last pen", session.lastPenOutcomeText)

      if let reason = presentation.jogControlsUnavailableReason {
        Text(reason)
          .font(.caption)
          .foregroundStyle(.orange)
      }
      if let reason = presentation.penDownUnavailableReason {
        Text("Pen down: \(reason)")
          .font(.caption)
          .foregroundStyle(.orange)
      }

    }
    .help("Manual relative motion controls")
  }

  private func jogButton(
    _ label: String,
    systemImage: String,
    direction: JogDirection
  ) -> some View {
    Button {
      submit(actionID(for: direction))
    } label: {
      Label(label, systemImage: systemImage)
        .frame(minWidth: 64, minHeight: 24)
    }
    .operatorButton(
      isEnabled: presentation.jogControlsUnavailableReason == nil
    )
    .help(jogAccessibilityLabel(direction))
    .accessibilityLabel(jogAccessibilityLabel(direction))
  }

  private func submit(_ actionID: PlotterUIActionID) {
    Task {
      _ = await plotterUIIntentSink.submitProjectedAction(actionID, in: plotterUIProjection)
    }
  }

  private func actionID(for direction: JogDirection) -> PlotterUIActionID {
    switch direction {
    case .xNegative: PlotterAppUIActionID.manualXNegative
    case .xPositive: PlotterAppUIActionID.manualXPositive
    case .yNegative: PlotterAppUIActionID.manualYNegative
    case .yPositive: PlotterAppUIActionID.manualYPositive
    }
  }

  private func jogAccessibilityLabel(_ direction: JogDirection) -> String {
    switch direction {
    case .xNegative: "Jog X negative"
    case .xPositive: "Jog X positive"
    case .yNegative: "Jog Y negative"
    case .yPositive: "Jog Y positive"
    }
  }

  private func numericField(_ label: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label).font(.caption2).foregroundStyle(.secondary)
      TextField(label, text: text)
        .textFieldStyle(.roundedBorder)
        .font(.caption.monospaced())
    }
  }

  private func fact(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label).font(.caption2).foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .font(.caption.monospaced())
        .multilineTextAlignment(.trailing)
        .textSelection(.enabled)
    }
  }
}

struct PanelCloseButton: View {
  let panel: WorkbenchPanel
  let close: () -> Void
  var unavailableReason: String? = nil

  var body: some View {
    let title = panel.actionTitle(isPresented: true)
    Button(action: close) {
      Image(systemName: "xmark")
    }
    .operatorButton(isEnabled: unavailableReason == nil)
    .controlSize(.small)
    .accessibilityLabel(title)
    .help(unavailableReason ?? title)
  }
}

private struct SectionPanel<Content: View>: View {
  let title: String
  let panel: WorkbenchPanel?
  let close: (() -> Void)?
  let closeUnavailableReason: String?
  @ViewBuilder let content: Content

  init(
    title: String,
    panel: WorkbenchPanel? = nil,
    close: (() -> Void)? = nil,
    closeUnavailableReason: String? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.panel = panel
    self.close = close
    self.closeUnavailableReason = closeUnavailableReason
    self.content = content()
  }

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        content
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .padding(.top, 2)
    } label: {
      HStack(spacing: 8) {
        Text(title.capitalized)
          .font(.headline)
        if let panel, let close {
          Spacer(minLength: 8)
          PanelCloseButton(
            panel: panel,
            close: close,
            unavailableReason: closeUnavailableReason
          )
        }
      }
      .frame(maxWidth: .infinity)
    }
  }
}
