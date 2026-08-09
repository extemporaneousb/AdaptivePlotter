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
    acceptedArtifactCheckpointActions: AcceptedArtifactCheckpointComposition.actions
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
  @State private var utilitiesArePresented = false
  @State private var paneVisibility = WorkbenchPaneVisibility()
  private let utilitiesPolicy = UtilitiesVisibilityPolicy()

  var body: some View {
    GeometryReader { proxy in
      let utilities = utilitiesPolicy.presentation(
        isPresented: utilitiesArePresented,
        availableWindowWidth: proxy.size.width
      )
      HSplitView {
        if paneVisibility.navigatorIsPresented {
          LearningPathNavigator(workspace: workspace, selection: $selection)
            .frame(minWidth: 220, idealWidth: 280, maxWidth: 440)
        }

        VStack(spacing: 0) {
          WorkbenchPaneControls(
            visibility: paneVisibility,
            utilities: utilities,
            exerciseDetailCollapseUnavailableReason:
              exerciseDetailCollapseUnavailableReason,
            motionCollapseUnavailableReason: motionCollapseUnavailableReason,
            togglePane: { pane in
              paneVisibility = paneVisibility.toggling(pane)
            },
            performUtilitiesAction: { action in
              performUtilitiesAction(action, availableWindowWidth: proxy.size.width)
            }
          )

          VSplitView {
            ActionSurface(presentation: workspace.actionSurfacePresentation)
              .frame(
                minWidth: LearningWorkbenchLayoutPolicy.minimumActionSurfaceWidth,
                minHeight: LearningWorkbenchLayoutPolicy.minimumActionSurfaceHeight
              )

            if paneVisibility.motionIsPresented {
              ScrollView {
                MotionPanel(workspace: workspace)
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

        if paneVisibility.exerciseDetailIsPresented {
          LearningPathView(
            workspace: workspace,
            selection: $selection,
            utilities: utilities,
            performUtilitiesAction: { action in
              performUtilitiesAction(action, availableWindowWidth: proxy.size.width)
            }
          )
          .frame(minWidth: 300, idealWidth: 380, maxWidth: 520)
        }
      }
      .onChange(of: proxy.size.width) { _, width in
        if utilitiesArePresented,
          utilitiesPolicy.shouldCollapsePresentedUtilities(
            availableContentWidth: width,
            panes: paneVisibility
          )
        {
          utilitiesArePresented = false
        }
      }
    }
    .background(Color.black)
    .inspector(isPresented: $utilitiesArePresented) {
      WorkbenchUtilities(
        workspace: workspace,
        close: { utilitiesArePresented = false }
      )
      .inspectorColumnWidth(min: 280, ideal: 360, max: 440)
    }
    .onChange(of: workspace.currentLearningPathItemID, initial: true) { _, itemID in
      selection.updateCurrent(itemID)
    }
    .toolbar {
      WorkbenchToolbar(workspace: workspace)
    }
    .toolbarRole(.editor)
    .task {
      await workspace.refreshSerialDevices()
      await workspace.startPreferredCameraAtStartup()
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

  private func performUtilitiesAction(
    _ action: UtilitiesVisibilityAction,
    availableWindowWidth: CGFloat
  ) {
    let willPresent = utilitiesPolicy.transition(
      isPresented: utilitiesArePresented,
      action: action,
      availableWindowWidth: availableWindowWidth
    )
    if willPresent, !utilitiesArePresented {
      paneVisibility = utilitiesPolicy.preparingPanesToShow(
        paneVisibility,
        availableWindowWidth: availableWindowWidth,
        canCollapseExerciseDetail: exerciseDetailCollapseUnavailableReason == nil
      )
    }
    utilitiesArePresented = willPresent
  }
}

private struct WorkbenchPaneControls: View {
  let visibility: WorkbenchPaneVisibility
  let utilities: UtilitiesPresentation
  let exerciseDetailCollapseUnavailableReason: String?
  let motionCollapseUnavailableReason: String?
  let togglePane: (WorkbenchPane) -> Void
  let performUtilitiesAction: (UtilitiesVisibilityAction) -> Void

  var body: some View {
    HStack(spacing: 8) {
      paneButton(
        .navigator,
        title: visibility.navigatorIsPresented ? "Hide Learning Path" : "Show Learning Path",
        systemImage: "sidebar.left"
      )
      paneButton(
        .motion,
        title: visibility.motionIsPresented ? "Hide Motion" : "Show Motion",
        systemImage: "rectangle.bottomthird.inset.filled",
        unavailableReason: motionCollapseUnavailableReason
      )
      paneButton(
        .exerciseDetail,
        title: visibility.exerciseDetailIsPresented ? "Hide Exercise" : "Show Exercise",
        systemImage: "sidebar.right",
        unavailableReason: exerciseDetailCollapseUnavailableReason
      )
      Spacer(minLength: 8)
      Button {
        performUtilitiesAction(utilities.action)
      } label: {
        Label(utilities.actionTitle, systemImage: "slider.horizontal.3")
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .disabled(!utilities.isActionEnabled)
      .help(utilities.unavailableReason ?? utilities.actionTitle)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  @ViewBuilder
  private func paneButton(
    _ pane: WorkbenchPane,
    title: String,
    systemImage: String,
    unavailableReason: String? = nil
  ) -> some View {
    Button {
      togglePane(pane)
    } label: {
      Label(title, systemImage: systemImage)
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
    .disabled(unavailableReason != nil && visibility.isPresented(pane))
    .help(unavailableReason ?? title)
  }
}

private struct WorkbenchUtilities: View {
  @Bindable var workspace: OperatorWorkspace
  let close: () -> Void
  @State private var selectedUtility: WorkbenchUtility = .camera

  var body: some View {
    VStack(spacing: 10) {
      HStack {
        Text("Utilities")
          .font(.headline)
        Spacer()
        Button(action: close) {
          Label("Hide Utilities", systemImage: "xmark")
        }
        .buttonStyle(.bordered)
        .help("Hide Utilities")
      }

      Picker("Utility", selection: $selectedUtility) {
        ForEach(WorkbenchUtility.allCases) { utility in
          Label(utility.title, systemImage: utility.systemImage).tag(utility)
        }
      }
      .pickerStyle(.segmented)
      .disabled(workspace.frameModeSwitchUnavailableReason != nil)
      .help(workspace.frameModeSwitchUnavailableReason ?? "Choose the frame source")

      ScrollView {
        switch selectedUtility {
        case .camera:
          CameraPanel(workspace: workspace)
        case .overlays:
          OverlayPanel(workspace: workspace)
        }
      }
    }
    .padding(10)
  }
}

private enum WorkbenchUtility: CaseIterable, Identifiable {
  case camera
  case overlays

  var id: Self { self }

  var title: String {
    switch self {
    case .camera: "Camera"
    case .overlays: "Overlays"
    }
  }

  var systemImage: String {
    switch self {
    case .camera: "camera"
    case .overlays: "square.3.layers.3d"
    }
  }
}

private struct CameraPanel: View {
  @Bindable var workspace: OperatorWorkspace

  var body: some View {
    let utilityPresentation = workspace.cameraUtilityPresentation
    SectionPanel(title: "CAMERA AND VISION") {
      Picker(
        "Frame source",
        selection: Binding(
          get: { workspace.frameMode },
          set: { mode in Task { await workspace.switchFrameMode(mode) } }
        )
      ) {
        ForEach(OperatorFrameMode.allCases) { mode in
          Text(mode.rawValue).tag(mode)
        }
      }
      .pickerStyle(.segmented)

      cameraUtilityControls(utilityPresentation)

      Picker(
        "Analysis cadence",
        selection: Binding(
          get: { workspace.visionAnalysisCadence },
          set: { cadence in Task { await workspace.updateVisionAnalysisCadence(cadence) } }
        )
      ) {
        ForEach(VisionAnalysisCadence.allCases, id: \.self) { cadence in
          Text("\(cadence.rawValue) Hz").tag(cadence)
        }
      }
      .pickerStyle(.segmented)
      .disabled(
        utilityPresentation.analysisCadenceUnavailableReason != nil
      )
      .help(
        utilityPresentation.analysisCadenceUnavailableReason
          ?? "Select the automatic analysis cadence"
      )

      if let reason = utilityPresentation.analysisCadenceUnavailableReason {
        Label("Analysis cadence: \(reason)", systemImage: "info.circle")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Text(
        "LIVE and SIMULATED use the same operator controls. Unavailable actions name the source capability they require; SIMULATED never invokes camera hardware."
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      if utilityPresentation.mode == .simulated {
        Text(workspace.simulatorEvidenceLabel)
          .font(.caption.monospaced().bold())
          .foregroundStyle(.blue)
        Text(workspace.simulatorLearningSummary)
          .font(.caption)
          .foregroundStyle(.secondary)
        fact("Simulated pen", workspace.simulatorPenState.rawValue)
      } else if workspace.cameraDevices.isEmpty {
        Text("No discovered camera.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ForEach(workspace.cameraDevices) { device in
          Button {
            Task { await workspace.selectCamera(device.id) }
          } label: {
            HStack {
              Image(
                systemName: workspace.selectedCameraID == device.id
                  ? "largecircle.fill.circle" : "circle"
              )
              Text(device.name)
              Spacer()
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(workspace.foregroundVisionOperationUnavailableReason != nil)
          .help(
            workspace.foregroundVisionOperationUnavailableReason
              ?? "Select \(device.name)"
          )
        }
      }

      fact("State", workspace.cameraStateText)
      fact("Current frame age", workspace.frameAgeText)
      fact("Vision", workspace.sceneMeasurementText)
      fact("Capture path", workspace.captureThroughputText)
      fact("Analysis path", workspace.visionThroughputText)
      if let path = workspace.lastCameraSnapshotPath {
        Text(path)
          .font(.caption2.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
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

  private func cameraUtilityControls(
    _ presentation: CameraUtilityPresentation
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(presentation.actions) { action in
        Button {
          Task { await workspace.performCameraUtilityAction(action.kind) }
        } label: {
          Label(action.title, systemImage: action.systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .disabled(!action.isEnabled)
        .help(action.unavailableReason ?? action.title)

        if let reason = action.unavailableReason {
          Text("\(action.title): \(reason)")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private func fact(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label).font(.caption2).foregroundStyle(.secondary)
      Spacer()
      Text(value).font(.caption.monospaced()).multilineTextAlignment(.trailing)
    }
  }
}

private struct MotionPanel: View {
  @Bindable var workspace: OperatorWorkspace

  var body: some View {
    let presentation = workspace.manualMotionPresentation
    SectionPanel(title: "MANUAL RELATIVE MOTION") {
      Text(
        "Manual steps remain finite typed requests. The controller's end-stops and alarms, one-operation serialization, pen-up travel, and ambiguous outcomes are checked directly."
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
          Task { await workspace.stopManualJog(capabilityID: stop.capabilityID) }
        } label: {
          Label(stop.title, systemImage: "stop.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .keyboardShortcut(.cancelAction)
        .help(stop.detail)
        .accessibilityHint(stop.detail)
      }

      ControlGroup {
        Button {
          Task { await workspace.requestPenActuation(.raise) }
        } label: {
          Label("Pen Up", systemImage: "arrow.up.to.line")
        }
        .tint(.blue)
        .disabled(workspace.penUnavailableReason(for: .raise) != nil)
        Button {
          Task { await workspace.requestPenActuation(.lower) }
        } label: {
          Label("Pen Down", systemImage: "arrow.down.to.line")
        }
        .tint(.red)
        .disabled(workspace.penUnavailableReason(for: .lower) != nil)
      }

      Text(workspace.penStateText)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Text("Commanded state is controller evidence only; the camera cannot observe pen height.")
        .font(.caption2)
        .foregroundStyle(.secondary)

      fact("Controller link", workspace.controllerConnectionText)
      fact("Controller", workspace.controllerStateText)
      fact("Motor power", workspace.motorPowerText)
      fact("Motion", workspace.motionGuardIsActive ? "enabled" : "disabled")
      fact("Motion request", workspace.motionPermissionText)
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
    .disabled(workspace.foregroundVisionOperationUnavailableReason != nil)
    .help(
      workspace.foregroundVisionOperationUnavailableReason
        ?? "Manual relative motion controls"
    )
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
    .buttonStyle(.borderedProminent)
    .disabled(workspace.manualMotionPresentation.jogControlsUnavailableReason != nil)
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

private struct OverlayPanel: View {
  @Bindable var workspace: OperatorWorkspace

  var body: some View {
    SectionPanel(title: "SEMANTIC OVERLAYS") {
      Text(
        "Each overlay is tied to the exact displayed frame and labeled by evidence source. Inferred geometry is not presented as a camera measurement."
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      ForEach(CanvasLayer.allCases) { layer in
        VStack(alignment: .leading, spacing: 2) {
          Toggle(
            layer.rawValue,
            isOn: Binding(
              get: { workspace.visibleLayers.contains(layer) },
              set: { workspace.setLayer(layer, visible: $0) }
            )
          )
          .toggleStyle(.switch)
          .controlSize(.small)
          Text(workspace.overlaySummary(for: layer))
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

private struct SectionPanel<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
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
      Text(title.capitalized)
        .font(.headline)
    }
  }
}
