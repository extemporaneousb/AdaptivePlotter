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
    learningAuthorityManifestActions: LearningAuthorityManifestComposition.actions,
    liveLearningSurfaceExposureActions: LearningSurfaceExposureComposition.actions,
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
    .commands {
      WorkbenchViewCommands()
    }
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
  private static let announcer = NativeSpeechAnnouncer()

  static let actions = OperatorWorkspace.AnnouncementActions(
    announce: { text in await announcer.announce(text) },
    cancelForShutdown: { await announcer.cancelForShutdown() }
  )
}

struct OperatorWorkspaceView: View {
  @Bindable var workspace: OperatorWorkspace
  @State private var selection = LearningPathSelectionState(current: .stage(.connect))
  @State private var windowState = WorkbenchWindowState()

  var body: some View {
    VStack(spacing: 0) {
      if let notice = workspace.currentOperatorNoticeMessage {
        OperatorNoticeBar(
          message: notice,
          showDiagnostics: { windowState.inspectorSelection = .diagnostics }
        )
      }

      HSplitView {
        VStack(spacing: 0) {
          VSplitView {
            ActionSurface(
              presentation: workspace.actionSurfacePresentation,
              videoPreferences: videoPreferences,
              selectPoint: { selection in
                workspace.selectToolContactPoint(selection)
              }
            )
            .frame(
              minWidth: LearningWorkbenchLayoutPolicy.minimumActionSurfaceWidth,
              minHeight: LearningWorkbenchLayoutPolicy.minimumActionSurfaceHeight
            )

            if windowState.motionIsPresented {
              ScrollView {
                MotionPanel(
                  workspace: workspace,
                  close: { windowState.motionIsPresented = false },
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

        if workspace.learningIsEnabled && windowState.learningExerciseIsPresented {
          LearningExercisePane(
            workspace: workspace,
            selection: $selection,
            close: { windowState.learningExerciseIsPresented = false },
            closeUnavailableReason: learningCollapseUnavailableReason
          )
          .frame(
            minWidth: LearningWorkbenchLayoutPolicy.minimumLearningExerciseWidth,
            idealWidth: LearningWorkbenchLayoutPolicy.idealLearningExerciseWidth,
            maxWidth: LearningWorkbenchLayoutPolicy.maximumLearningExerciseWidth
          )
        }
      }
    }
    .background(Color.black)
    .inspector(isPresented: inspectorIsPresented) {
      Group {
        switch windowState.inspectorSelection {
        case .none:
          EmptyView()
        case .video:
          VideoSettingsPanel(
            workspace: workspace,
            videoPreferences: videoPreferences,
            close: { windowState.closeInspector() }
          )
        case .diagnostics:
          DiagnosticsPanel(
            workspace: workspace,
            videoPreferences: videoPreferences,
            close: { windowState.closeInspector() }
          )
        }
      }
      .inspectorColumnWidth(
        min: WorkbenchInspectorLayoutPolicy.minimumInspectorWidth,
        ideal: WorkbenchInspectorLayoutPolicy.idealInspectorWidth,
        max: WorkbenchInspectorLayoutPolicy.maximumInspectorWidth
      )
    }
    .onChange(of: workspace.currentLearningPathItemID, initial: true) { _, itemID in
      selection.updateCurrent(itemID)
    }
    .focusedSceneValue(
      \.workbenchWindowCommandContext,
      WorkbenchWindowCommandContext(
        state: $windowState,
        learningShowUnavailableReason: workspace.learningIsEnabled
          ? nil : "Turn Learning on before showing the Learning pane.",
        learningHideUnavailableReason: learningCollapseUnavailableReason,
        motionHideUnavailableReason: motionCollapseUnavailableReason
      )
    )
    .toolbar {
      WorkbenchToolbar(
        workspace: workspace,
        windowState: $windowState,
        learningHideUnavailableReason: learningCollapseUnavailableReason,
        motionHideUnavailableReason: motionCollapseUnavailableReason
      )
    }
    .toolbarRole(.editor)
    .task {
      await workspace.performApplicationStartup(AdaptivePlotterLaunchPolicy.current)
    }
  }

  private var inspectorIsPresented: Binding<Bool> {
    Binding(
      get: { windowState.inspectorSelection != .none },
      set: { isPresented in
        if !isPresented { windowState.closeInspector() }
      }
    )
  }

  private var videoPreferences: VideoPresentationPreferences {
    workspace.videoPresentationPreferences
  }

  private var learningCollapseUnavailableReason: String? {
    guard workspace.currentExerciseActionStripPresentation?.mustRemainVisible == true
    else { return nil }
    return "Finish or cancel the active exercise attempt before hiding its controls."
  }

  private var motionCollapseUnavailableReason: String? {
    workspace.manualMotionPresentation.stopAction == nil
      ? nil : "Stop the active manual jog before hiding its Stop control."
  }
}

private struct VideoSettingsPanel: View {
  @Bindable var workspace: OperatorWorkspace
  let videoPreferences: VideoPresentationPreferences
  let close: () -> Void

  var body: some View {
    VStack(spacing: 10) {
      InspectorHeader(title: "Video Settings", close: close)

      ScrollView {
        VideoSettingsContents(
          workspace: workspace,
          videoPreferences: videoPreferences
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
  @Bindable var workspace: OperatorWorkspace
  let videoPreferences: VideoPresentationPreferences

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionPanel(title: "SOURCE") {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
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

        if workspace.frameMode == .live && workspace.cameraDevices.isEmpty {
          Text("No discovered camera.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      analysisViewportControls
      overlayControls
    }
  }

  private var analysisViewportControls: some View {
    let displayedFrame = workspace.actionSurfacePresentation.displayedFrame
    let visibleRect = displayedFrame.flatMap {
      videoPreferences.visibleRect(
        frameWidth: $0.frame.width,
        frameHeight: $0.frame.height
      )
    }
    let regionIsLocked = displayedFrame.map(videoPreferences.isAnalysisLocked(to:)) ?? false
    let fullFrame = displayedFrame.map {
      PixelRect(x: 0, y: 0, width: $0.frame.width, height: $0.frame.height)
    }
    let canLock = visibleRect != nil && visibleRect != fullFrame

    return SectionPanel(title: "VIEW") {
      Picker(
        "Frames per second",
        selection: Binding(
          get: { videoPreferences.cadence },
          set: { cadence in
            Task { await workspace.setVisionAnalysisCadence(cadence) }
          }
        )
      ) {
        ForEach(VisionAnalysisCadence.allCases, id: \.self) { cadence in
          Text("\(cadence.rawValue)").tag(cadence)
        }
      }
      .disabled(workspace.frameMode != .live)

      Slider(
        value: Binding(
          get: { videoPreferences.zoom },
          set: { videoPreferences.setZoom($0) }
        ),
        in: 0...1
      ) {
        Text("Zoom")
      }
      .disabled(displayedFrame == nil || regionIsLocked)
      .help("Zoom changes only the displayed camera pixels until the view is locked.")

      HStack {
        Button("Full Frame") { videoPreferences.showFullFrame() }
          .operatorButton(
            .editValue,
            isEnabled: displayedFrame != nil && !regionIsLocked
          )
        Button("Fit Current Bounds") { videoPreferences.fitCurrentSuggestion() }
          .operatorButton(
            .editValue,
            isEnabled: displayedFrame != nil && videoPreferences.fitSuggestion != nil
              && !regionIsLocked
          )
      }

      Toggle(
        "Lock View for Analysis",
        isOn: Binding(
          get: { regionIsLocked },
          set: { shouldLock in
            guard let displayedFrame else { return }
            if shouldLock {
              Task {
                await workspace.lockVideoAnalysisToCurrentView(for: displayedFrame)
              }
            } else {
              Task {
                await workspace.unlockVideoAnalysisView(for: displayedFrame)
              }
            }
          }
        )
      )
      .disabled(
        displayedFrame == nil || (!regionIsLocked && !canLock)
          || workspace.currentCameraCalibrationBusyReason != nil
      )

      if regionIsLocked, let analysisROI = videoPreferences.analysisROI {
        Label(Self.regionText(analysisROI), systemImage: "lock.fill")
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
      }
    }
  }

  private var overlayControls: some View {
    SectionPanel(title: "OVERLAYS") {
      ForEach(UserSceneOverlay.allCases) { overlay in
        Toggle(
          overlay.title,
          isOn: Binding(
            get: { videoPreferences.enabledOverlays.contains(overlay) },
            set: { enabled in
              workspace.setOverlay(overlay, enabled: enabled)
            }
          )
        )
        .toggleStyle(.switch)
      }
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

  fileprivate static func regionText(_ region: PixelRect) -> String {
    "x \(region.x), y \(region.y), \(region.width) × \(region.height) px"
  }

}

private struct DiagnosticsPanel: View {
  @Bindable var workspace: OperatorWorkspace
  let videoPreferences: VideoPresentationPreferences
  let close: () -> Void

  var body: some View {
    VStack(spacing: 10) {
      InspectorHeader(title: "Diagnostics", close: close)
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          cameraDiagnostics
          overlayDiagnostics
          motionDiagnostics
          learningDiagnostics
        }
      }
    }
    .padding(10)
  }

  private var cameraDiagnostics: some View {
    SectionPanel(title: "CAMERA") {
      diagnosticFact("State", workspace.cameraStateText)
      diagnosticFact("Capture", workspace.captureThroughputText)
      diagnosticFact("Analysis", workspace.visionThroughputText)
      diagnosticFact("Cadence", "\(videoPreferences.cadence.rawValue) fps")
      diagnosticFact(
        "Viewport",
        videoPreferences.analysisROI.map(VideoSettingsContents.regionText)
          ?? "Display-only; backend analysis uses the full frame"
      )
      diagnosticFact("Tip", workspace.actionSurfacePresentation.tipPresentation.statusText)
      if let frame = workspace.actionSurfacePresentation.displayedFrame {
        diagnosticFact(
          "Displayed frame",
          "\(frame.frame.sequence) · \(frame.frame.width)×\(frame.frame.height) · \(frame.frame.id.rawValue)"
        )
      }
      diagnosticError("Camera", workspace.cameraError)
      diagnosticError("Vision", workspace.visionError)
    }
  }

  private var overlayDiagnostics: some View {
    SectionPanel(title: "OVERLAYS") {
      ForEach(UserSceneOverlay.allCases) { overlay in
        let presentation = workspace.overlayCardPresentation(for: overlay)
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text(presentation.title).font(.callout.weight(.semibold))
            Spacer()
            Text(presentation.selectionText)
              .font(.caption.monospaced().bold())
          }
          Text(presentation.statusText)
            .font(.caption)
            .foregroundStyle(overlayStatusColor(presentation.colorToken))
          diagnosticFact("ROI", presentation.roiText)
          diagnosticFact("Analyzed frame", presentation.frameText)
          diagnosticFact("Result age", presentation.resultAgeText)
        }
        .padding(.vertical, 4)
      }

      if let selection = workspace.penCapAppearanceSelection {
        HStack(spacing: 8) {
          Circle()
            .fill(selection.color.swiftUIColor)
            .frame(width: 12, height: 12)
          Text("Pen cap #\(selection.color.hexRGB)")
            .font(.caption.monospaced().bold())
        }
        diagnosticFact(
          "Selection",
          "frame \(selection.frameID.rawValue) · config \(selection.cameraConfigurationID.rawValue) · click \(String(format: "%.1f", selection.clickPoint.x)), \(String(format: "%.1f", selection.clickPoint.y)) px · \(selection.usableSampleCount)/\(selection.totalSampleCount) samples · \(selection.algorithmRevision)"
        )
      }
    }
  }

  private var motionDiagnostics: some View {
    SectionPanel(title: "MOTION") {
      diagnosticFact("Controller link", workspace.controllerConnectionText)
      diagnosticFact("Controller", workspace.controllerStateText)
      diagnosticFact("Controller alert", workspace.controllerAttentionText ?? "none")
      diagnosticFact("Limit inputs", workspace.controllerLimitInputsText)
      diagnosticFact("Alarm unlock", workspace.controllerAlarmUnlockReadinessText)
      diagnosticFact("Motor power", workspace.motorPowerText)
      diagnosticFact("Motion", workspace.motionPermissionText)
      diagnosticFact("MPos", workspace.machinePositionText)
      diagnosticFact("Operation", workspace.currentOperationText)
      diagnosticFact("Last motion", workspace.lastMotionOutcomeText)
      diagnosticFact("Last pen", workspace.lastPenOutcomeText)
    }
  }

  private var learningDiagnostics: some View {
    SectionPanel(title: "LEARNING") {
      diagnosticFact("Mode", workspace.learningIsEnabled ? "on" : "off")
      diagnosticFact(
        "Current step",
        "\(workspace.currentLearningPathItemID.number) \(workspace.currentLearningPathItemID.title)"
      )
      diagnosticError("Discovery", workspace.discoveryError)
      diagnosticError("Drawing", workspace.explorationError)
      diagnosticError("Learning authority", workspace.learningAuthorityError)
      diagnosticError("Authority manifest", workspace.learningAuthorityManifestError)
      diagnosticError("Surface safety", workspace.learningSurfaceExposureError)
      if workspace.frameMode == .simulated {
        diagnosticFact("Simulation", workspace.simulatorEvidenceLabel)
        diagnosticFact("Summary", workspace.simulatorLearningSummary)
      }
    }
  }

  @ViewBuilder
  private func diagnosticError(_ label: String, _ error: String?) -> some View {
    if let error {
      Label("\(label): \(error)", systemImage: "exclamationmark.triangle.fill")
        .font(.caption.monospaced())
        .foregroundStyle(.orange)
        .textSelection(.enabled)
    }
  }

  private func diagnosticFact(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(label.uppercased())
        .font(.caption2.monospaced().bold())
        .foregroundStyle(.secondary)
      Text(value)
        .font(.caption.monospaced())
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
}

private struct InspectorHeader: View {
  let title: String
  let close: () -> Void

  var body: some View {
    HStack {
      Text(title).font(.headline)
      Spacer()
      PanelCloseButton(title: "Hide \(title)", close: close)
    }
  }
}

private struct OperatorNoticeBar: View {
  let message: String
  let showDiagnostics: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      Text(message)
        .font(.callout)
        .lineLimit(2)
      Spacer(minLength: 8)
      Button("Diagnostics", action: showDiagnostics)
        .controlSize(.small)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(Color.orange.opacity(0.12))
    .accessibilityElement(children: .combine)
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
  @Bindable var workspace: OperatorWorkspace
  let close: () -> Void
  let closeUnavailableReason: String?

  var body: some View {
    let presentation = workspace.manualMotionPresentation
    SectionPanel(
      title: "MOTION",
      closeTitle: "Hide Motion",
      close: close,
      closeUnavailableReason: closeUnavailableReason
    ) {
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
        .operatorButton(.interrupt)
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
        .help(workspace.penUnavailableReason(for: .raise) ?? "Raise the pen")
        Button {
          Task { await workspace.requestPenActuation(.lower) }
        } label: {
          Label("Pen Down", systemImage: "arrow.down.to.line")
        }
        .operatorButton(
          isEnabled: workspace.penUnavailableReason(for: .lower) == nil
        )
        .help(workspace.penUnavailableReason(for: .lower) ?? "Lower the pen")
      }

      Text(workspace.penStateText)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      if workspace.controllerAlarmEvidenceText != nil {
        VStack(alignment: .leading, spacing: 5) {
          Button {
            Task { await workspace.clearControllerAlarm() }
          } label: {
            Label(
              workspace.controllerAlarmClearInProgress ? "Clearing Alarm…" : "Clear Alarm",
              systemImage: "exclamationmark.triangle.fill"
            )
          }
          .operatorButton(
            .interrupt,
            isEnabled: workspace.controllerAlarmClearActionUnavailableReason == nil
          )
          .help(
            workspace.controllerAlarmClearActionUnavailableReason
              ?? "Send one explicit alarm-unlock request, then run a fresh passive controller probe"
          )
        }
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
    .help(
      workspace.manualMotionPresentation.jogControlsUnavailableReason
        ?? jogAccessibilityLabel(direction)
    )
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

}

struct PanelCloseButton: View {
  let title: String
  let close: () -> Void
  var unavailableReason: String? = nil

  var body: some View {
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
  let closeTitle: String?
  let close: (() -> Void)?
  let closeUnavailableReason: String?
  @ViewBuilder let content: Content

  init(
    title: String,
    closeTitle: String? = nil,
    close: (() -> Void)? = nil,
    closeUnavailableReason: String? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.closeTitle = closeTitle
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
        if let closeTitle, let close {
          Spacer(minLength: 8)
          PanelCloseButton(
            title: closeTitle,
            close: close,
            unavailableReason: closeUnavailableReason
          )
        }
      }
      .frame(maxWidth: .infinity)
    }
  }
}
