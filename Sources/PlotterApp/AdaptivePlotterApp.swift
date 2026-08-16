import AppKit
import PlotterModel
import PlotterRuntime
import SwiftUI

@MainActor
final class AdaptivePlotterApplicationDelegate: NSObject, NSApplicationDelegate {
  let workspace = OperatorWorkspace(
    machineActions: MachineSessionComposition.actions,
    cameraActions: CameraComposition.actions,
    announcementActions: SpeechComposition.actions,
    acceptedArtifactCheckpointActions: AcceptedArtifactCheckpointComposition.actions,
    acceptedTipCalibrationCheckpointActions:
      AcceptedArtifactCheckpointComposition.tipCalibrationActions,
    tipCalibrationSemanticIdentities: TipCalibrationSemanticIdentityComposition.state,
    persistPaperContactPlaneRevision: {
      TipCalibrationSemanticIdentityComposition.persistPaperContactPlane($0)
    },
    workflowTelemetryActions: MachineSessionComposition.workflowTelemetryActions
  )
  private var terminationTask: Task<Void, Never>?
  private var terminationDeadlineTask: Task<Void, Never>?
  private var didReplyToTermination = false

  static let terminationDeadlineNanoseconds: UInt64 = 3_000_000_000

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
      await self.workspace.shutdown()
      self.completeTermination(of: sender)
    }
    terminationDeadlineTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: Self.terminationDeadlineNanoseconds)
      } catch {
        return
      }
      self?.completeTermination(of: sender)
    }
    return .terminateLater
  }

  private func completeTermination(of application: NSApplication) {
    guard !didReplyToTermination else { return }
    didReplyToTermination = true
    terminationTask?.cancel()
    terminationDeadlineTask?.cancel()
    terminationTask = nil
    terminationDeadlineTask = nil
    application.reply(toApplicationShouldTerminate: true)
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
      OperatorWorkspaceView(workspace: applicationDelegate.workspace)
        .frame(
          minWidth: LearningWorkbenchLayoutPolicy.minimumWindowWidth,
          minHeight: AdaptivePlotterScenePolicy.minimumWindowHeight
        )
    }
    .windowToolbarStyle(.unifiedCompact)
  }
}

enum AdaptivePlotterScenePolicy {
  static let singletonWindowID = "operator-workspace"
  static let minimumWindowHeight: CGFloat = 760
}

enum AdaptivePlotterStartupRoute: Equatable, Sendable {
  case preferredCamera
  case simulated
}

struct AdaptivePlotterLaunchPolicy: Equatable, Sendable {
  static let simulatedArgument = "-AdaptivePlotterStartSimulated"
  let startupRoute: AdaptivePlotterStartupRoute

  init(arguments: [String]) {
    startupRoute = arguments.indices.contains { index in
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
  private static let announcer = NativeSpeechAnnouncer()

  static let actions = OperatorWorkspace.AnnouncementActions(
    announce: { text in await announcer.announce(text) },
    cancelForShutdown: { await announcer.cancelForShutdown() }
  )
}

struct OperatorWorkspaceView: View {
  @Bindable var workspace: OperatorWorkspace
  @State private var selection = LearningPathSelectionState(current: .stage(.connect))
  @State private var videoSettingsVisibility = VideoSettingsVisibilityState()
  @State private var paneVisibility = WorkbenchPaneVisibility()
  @State private var actionSurfaceViewport = ActionSurfaceViewportState()
  private let videoSettingsPolicy = VideoSettingsVisibilityPolicy()

  var body: some View {
    GeometryReader { proxy in
      let videoSettings = videoSettingsPolicy.presentation(
        isPresented: videoSettingsVisibility.isPresented,
        availableWindowWidth: proxy.size.width
      )
      HSplitView {
        if workspace.learningIsEnabled && paneVisibility.navigatorIsPresented {
          LearningPathNavigator(
            workspace: workspace,
            selection: $selection,
            close: { paneVisibility.navigatorIsPresented = false }
          )
          .frame(minWidth: 220, idealWidth: 280, maxWidth: 440)
        }

        VStack(spacing: 0) {
          WorkbenchPaneControls(
            visibility: paneVisibility,
            videoSettings: videoSettings,
            exerciseDetailCollapseUnavailableReason:
              exerciseDetailCollapseUnavailableReason,
            motionCollapseUnavailableReason: motionCollapseUnavailableReason,
            learningIsEnabled: workspace.learningIsEnabled,
            learningActionTitle: workspace.learningModeActionTitle,
            learningChangeUnavailableReason: workspace.learningModeChangeUnavailableReason,
            toggleLearning: workspace.toggleLearningMode,
            togglePane: { pane in
              paneVisibility = paneVisibility.toggling(pane)
            },
            performVideoSettingsAction: { action in
              performVideoSettingsAction(action, availableWindowWidth: proxy.size.width)
            }
          )

          VSplitView {
            ActionSurface(
              presentation: workspace.actionSurfacePresentation,
              viewport: $actionSurfaceViewport,
              selectPoint: { selection in
                workspace.selectToolContactPoint(selection)
              }
            )
            .frame(
              minWidth: LearningWorkbenchLayoutPolicy.minimumActionSurfaceWidth,
              minHeight: LearningWorkbenchLayoutPolicy.minimumActionSurfaceHeight
            )

            if paneVisibility.motionIsPresented {
              ScrollView {
                MotionPanel(
                  workspace: workspace,
                  close: { paneVisibility.motionIsPresented = false },
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

        if workspace.learningIsEnabled && paneVisibility.exerciseDetailIsPresented {
          LearningPathView(
            workspace: workspace,
            selection: $selection,
            close: { paneVisibility.exerciseDetailIsPresented = false },
            closeUnavailableReason: exerciseDetailCollapseUnavailableReason
          )
          .frame(minWidth: 300, idealWidth: 380, maxWidth: 520)
        }
      }
      .onChange(of: proxy.size.width) { _, width in
        videoSettingsVisibility.collapseIfNeeded(
          availableContentWidth: width,
          panes: paneVisibility,
          policy: videoSettingsPolicy
        )
      }
    }
    .background(Color.black)
    .inspector(
      isPresented: Binding(
        get: { videoSettingsVisibility.isPresented },
        set: { isPresented in
          if !isPresented { videoSettingsVisibility.hide() }
        }
      )
    ) {
      VideoSettingsPanel(
        workspace: workspace,
        viewport: $actionSurfaceViewport,
        close: { videoSettingsVisibility.hide() }
      )
      .inspectorColumnWidth(
        min: OverlayCardLayoutPolicy.minimumInspectorWidth,
        ideal: OverlayCardLayoutPolicy.idealInspectorWidth,
        max: OverlayCardLayoutPolicy.maximumInspectorWidth
      )
    }
    .onChange(of: workspace.currentLearningPathItemID, initial: true) { _, itemID in
      selection.updateCurrent(itemID)
    }
    .toolbar {
      WorkbenchToolbar(workspace: workspace)
    }
    .toolbarRole(.editor)
    .task {
      await workspace.performApplicationStartup(AdaptivePlotterLaunchPolicy.current)
    }
  }

  private var exerciseDetailCollapseUnavailableReason: String? {
    guard workspace.currentExerciseActionStripPresentation?.mustRemainVisible == true
    else { return nil }
    return "Finish or cancel the active exercise attempt before hiding its controls."
  }

  private var motionCollapseUnavailableReason: String? {
    workspace.manualMotionPresentation.stopAction == nil
      ? nil : "Stop the active manual jog before hiding its Stop control."
  }

  private func performVideoSettingsAction(
    _ action: VideoSettingsVisibilityAction,
    availableWindowWidth: CGFloat
  ) {
    guard videoSettingsVisibility.request(
      action,
      policy: videoSettingsPolicy,
      availableWindowWidth: availableWindowWidth
    ) else { return }
    paneVisibility = videoSettingsPolicy.preparingPanesToShow(
      paneVisibility,
      availableWindowWidth: availableWindowWidth,
      canCollapseExerciseDetail: exerciseDetailCollapseUnavailableReason == nil
    )
    Task { @MainActor in
      await Task.yield()
      videoSettingsVisibility.commitPendingShow()
    }
  }
}

private struct WorkbenchPaneControls: View {
  let visibility: WorkbenchPaneVisibility
  let videoSettings: VideoSettingsPresentation
  let exerciseDetailCollapseUnavailableReason: String?
  let motionCollapseUnavailableReason: String?
  let learningIsEnabled: Bool
  let learningActionTitle: String
  let learningChangeUnavailableReason: String?
  let toggleLearning: () -> Void
  let togglePane: (WorkbenchPane) -> Void
  let performVideoSettingsAction: (VideoSettingsVisibilityAction) -> Void

  var body: some View {
    HStack(spacing: 8) {
      Button(action: toggleLearning) {
        Label(
          learningActionTitle,
          systemImage: learningIsEnabled ? "graduationcap.fill" : "graduationcap"
        )
      }
      .operatorButton(isEnabled: learningChangeUnavailableReason == nil)
      .controlSize(.small)
      .help(
        learningChangeUnavailableReason
          ?? "Learning is ergonomic workflow guidance; turning it off preserves learned evidence and leaves direct machine controls available."
      )
      if learningIsEnabled {
        paneButton(
          .navigator,
          panel: .learningPath
        )
      }
      paneButton(
        .motion,
        panel: .motion,
        unavailableReason: motionCollapseUnavailableReason
      )
      if learningIsEnabled {
        paneButton(
          .exerciseDetail,
          panel: .exercise,
          unavailableReason: exerciseDetailCollapseUnavailableReason
        )
      }
      Button {
        performVideoSettingsAction(videoSettings.action)
      } label: {
        Label(
          videoSettings.actionTitle,
          systemImage: WorkbenchPanel.videoSettings.systemImage
        )
      }
      .operatorButton(isEnabled: videoSettings.isActionEnabled)
      .controlSize(.small)
      .help(videoSettings.unavailableReason ?? videoSettings.actionTitle)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  @ViewBuilder
  private func paneButton(
    _ pane: WorkbenchPane,
    panel: WorkbenchPanel,
    unavailableReason: String? = nil
  ) -> some View {
    let title = panel.actionTitle(isPresented: visibility.isPresented(pane))
    Button {
      togglePane(pane)
    } label: {
      Label(title, systemImage: panel.systemImage)
    }
    .operatorButton(
      isEnabled: unavailableReason == nil || !visibility.isPresented(pane)
    )
    .controlSize(.small)
    .help(unavailableReason ?? title)
  }
}

private struct VideoSettingsPanel: View {
  @Bindable var workspace: OperatorWorkspace
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
        VideoSettingsContents(workspace: workspace, viewport: $viewport)
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
  @Bindable var workspace: OperatorWorkspace
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
            ForEach(workspace.cameraDevices) { device in
              Text(device.name).tag(Optional(VideoSourceChoice.live(device.id)))
            }
          }
          .labelsHidden()
          .frame(maxWidth: .infinity)
          .disabled(workspace.frameModeSwitchUnavailableReason != nil)
          .help(workspace.frameModeSwitchUnavailableReason ?? "Choose the video source")

          Button {
            Task { await workspace.refreshVideoSources() }
          } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
          }
          .operatorButton(isEnabled: workspace.currentCameraCalibrationBusyReason == nil)
          .help(workspace.currentCameraCalibrationBusyReason ?? "Refresh camera choices")
        }

        if workspace.frameMode == .simulated {
          Text(workspace.simulatorEvidenceLabel)
            .font(.caption.monospaced().bold())
            .foregroundStyle(.blue)
          Text(workspace.simulatorLearningSummary)
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if workspace.cameraDevices.isEmpty {
          Text("No discovered camera.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

      }

      analysisViewportControls
      overlayControls

      SectionPanel(title: "STATUS") {
        fact("State", workspace.cameraStateText)
        fact("Capture path", workspace.captureThroughputText)
        fact("Analysis path", workspace.visionThroughputText)
        if let error = workspace.cameraError {
          Text(error)
            .font(.caption.monospaced())
            .foregroundStyle(.orange)
            .textSelection(.enabled)
        }
        if let error = workspace.visionError {
          Text(error)
            .font(.caption.monospaced())
            .foregroundStyle(.orange)
            .textSelection(.enabled)
        }

      }
    }
  }

  private var analysisViewportControls: some View {
    let displayedFrame = workspace.actionSurfacePresentation.displayedFrame
    let region = displayedFrame.flatMap {
      viewport.selectedRegion(frameWidth: $0.frame.width, frameHeight: $0.frame.height)
    }
    let regionIsLocked =
      displayedFrame.map {
        workspace.videoAnalysisRegionLock?.matches($0) == true
      } ?? false

    return SectionPanel(title: "ANALYSIS VIEWPORT") {
      Picker(
        "Frames per second",
        selection: Binding(
          get: { workspace.visionAnalysisCadence },
          set: { cadence in Task { await workspace.setVisionAnalysisCadence(cadence) } }
        )
      ) {
        ForEach(VisionAnalysisCadence.allCases, id: \.self) { cadence in
          Text("\(cadence.rawValue)").tag(cadence)
        }
      }
      .disabled(workspace.frameMode != .live)

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
          set: { shouldLock in
            guard let displayedFrame else { return }
            Task {
              await workspace.setVideoAnalysisRegion(
                shouldLock ? region : nil,
                for: displayedFrame
              )
            }
          }
        )
      )
      .disabled(
        displayedFrame == nil || region == nil
          || workspace.currentCameraCalibrationBusyReason != nil
      )

      Text(
        regionIsLocked
          ? "Only this camera-pixel region is admitted to scene analysis. Unlock it before zooming or dragging."
          : "Zoom, then drag the video to position the region. Locking copies that camera-pixel rectangle into the analysis policy; it does not crop or rewrite the exact frame."
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
  }

  private var overlayControls: some View {
    SectionPanel(title: "OVERLAYS") {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(UserSceneOverlay.allCases) { overlay in
          overlayCard(workspace.overlayCardPresentation(for: overlay))
        }
      }

      if let selection = workspace.penCapAppearanceSelection {
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

  private func overlayCard(_ presentation: OverlayCardPresentation) -> some View {
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
            get: { workspace.overlayPreferenceState.enabled.contains(presentation.overlay) },
            set: { workspace.setOverlay(presentation.overlay, enabled: $0) }
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
    Binding(
      get: {
        switch workspace.frameMode {
        case .simulated: .simulated
        case .live: workspace.selectedCameraID.map(VideoSourceChoice.live)
        }
      },
      set: { selection in
        guard let selection else { return }
        Task {
          switch selection {
          case .simulated:
            await workspace.switchFrameMode(.simulated)
          case .live(let id):
            await workspace.selectAndStartCamera(id)
          }
        }
      }
    )
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

private extension PenCapColor {
  var swiftUIColor: Color {
    Color(
      red: Double(red) / 255,
      green: Double(green) / 255,
      blue: Double(blue) / 255
    )
  }

}

private struct MotionPanel: View {
  @Bindable var workspace: OperatorWorkspace
  let close: () -> Void
  let closeUnavailableReason: String?

  var body: some View {
    let presentation = workspace.manualMotionPresentation
    SectionPanel(
      title: "MANUAL RELATIVE MOTION",
      panel: .motion,
      close: close,
      closeUnavailableReason: closeUnavailableReason
    ) {
      Text(
        "Manual steps remain finite typed requests. Pen Up routes to carriage travel; Pen Down routes to a bounded drawing stroke. End-stops, alarms, one-operation serialization, commanded pen state, and ambiguous outcomes are checked directly."
      )
      .font(.caption2)
      .foregroundStyle(.secondary)

      HStack(spacing: 8) {
        numericField(ManualMotionPresentation.xDistanceLabel, text: $workspace.xStepText)
        numericField(ManualMotionPresentation.yDistanceLabel, text: $workspace.yStepText)
        numericField(ManualMotionPresentation.feedLabel, text: $workspace.feedText)
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
          Task { await workspace.stopManualMotion(capabilityID: stop.capabilityID) }
        } label: {
          Label(stop.title, systemImage: "stop.fill")
            .frame(maxWidth: .infinity)
        }
        .operatorButton(.negative)
        .keyboardShortcut(.cancelAction)
        .help(stop.detail)
        .accessibilityHint(stop.detail)
      }

      HStack(spacing: 6) {
        Button {
          Task { await workspace.requestPenActuation(.raise) }
        } label: {
          Label("Pen Up", systemImage: "arrow.up.to.line")
        }
        .operatorButton(
          isEnabled: workspace.penUnavailableReason(for: .raise) == nil
        )
        Button {
          Task { await workspace.requestPenActuation(.lower) }
        } label: {
          Label("Pen Down", systemImage: "arrow.down.to.line")
        }
        .operatorButton(
          isEnabled: workspace.penUnavailableReason(for: .lower) == nil
        )
      }

      Text(workspace.penStateText)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Text("Commanded state is controller evidence only; the camera cannot observe pen height.")
        .font(.caption2)
        .foregroundStyle(.secondary)

      fact("Controller link", workspace.controllerConnectionText)
      fact("Controller", workspace.controllerStateText)
      fact("Controller alert", workspace.controllerAttentionText ?? "none reported")
      fact("Limit inputs", workspace.controllerLimitInputsText)
      fact("Alarm unlock", workspace.controllerAlarmUnlockReadinessText)
      if let alarm = workspace.controllerAlarmEvidenceText {
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
            Task { await workspace.clearControllerAlarm() }
          } label: {
            Label(
              workspace.controllerAlarmClearInProgress ? "Clearing Alarm…" : "Clear Alarm",
              systemImage: "exclamationmark.triangle.fill"
            )
          }
          .operatorButton(
            .negative,
            isEnabled: workspace.controllerAlarmClearActionUnavailableReason == nil
          )
          .help(
            workspace.controllerAlarmClearActionUnavailableReason
              ?? "Send one explicit alarm-unlock request, then run a fresh passive controller probe"
          )
        }
      }
      fact("Motor power", workspace.motorPowerText)
      fact("Motion", workspace.motionGuardIsActive ? "enabled" : "disabled")
      fact("Motion request", workspace.motionPermissionText)
      fact("Manual mode", workspace.manualMotionModeText)
      fact("Learning", workspace.learningIsEnabled ? "on" : "off — manual operation")
      fact("MPos", workspace.machinePositionText)
      fact("Operation", workspace.currentOperationText)
      fact("Last outcome", workspace.lastMotionOutcomeText)
      fact("Last pen", workspace.lastPenOutcomeText)

      if let reason = presentation.jogControlsUnavailableReason {
        Text(reason)
          .font(.caption)
          .foregroundStyle(.orange)
      }
      if let reason = workspace.penUnavailableReason(for: .lower) {
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
      Task { await workspace.requestJog(direction) }
    } label: {
      Label(label, systemImage: systemImage)
        .frame(minWidth: 64, minHeight: 24)
    }
    .operatorButton(
      isEnabled: workspace.manualMotionPresentation.jogControlsUnavailableReason == nil
    )
    .help(jogAccessibilityLabel(direction))
    .accessibilityLabel(jogAccessibilityLabel(direction))
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
