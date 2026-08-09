import AppKit
import PlotterModel
import PlotterRuntime
import SwiftUI

@MainActor
final class AdaptivePlotterApplicationDelegate: NSObject, NSApplicationDelegate {
  let workspace = OperatorWorkspace(
    machineActions: MachineSessionComposition.actions,
    cameraActions: CameraComposition.actions,
    announcementActions: SpeechComposition.actions
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
  static let windowCount = 1
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

  var body: some View {
    GeometryReader { proxy in
      HSplitView {
        LearningPathNavigator(workspace: workspace, selection: $selection)
          .frame(minWidth: 220, idealWidth: 280, maxWidth: 440)

        VSplitView {
          ActionSurface(presentation: workspace.actionSurfacePresentation)
            .frame(minWidth: 640, minHeight: 420)

          ScrollView {
            MotionPanel(workspace: workspace)
              .padding(10)
          }
          .frame(minHeight: 220, idealHeight: 260, maxHeight: 360)
          .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)

        LearningPathView(
          workspace: workspace,
          selection: $selection,
          showUtilities: { utilitiesArePresented = true }
        )
        .frame(minWidth: 300, idealWidth: 380, maxWidth: 520)
      }
      .onChange(of: proxy.size.width) { _, width in
        if utilitiesArePresented,
          width < LearningWorkbenchLayoutPolicy.minimumWindowWidth
        {
          utilitiesArePresented = false
        }
      }
    }
    .background(Color.black)
    .inspector(isPresented: $utilitiesArePresented) {
      WorkbenchUtilities(workspace: workspace)
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
}

private struct WorkbenchUtilities: View {
  @Bindable var workspace: OperatorWorkspace
  @State private var selectedUtility: WorkbenchUtility = .camera

  var body: some View {
    VStack(spacing: 10) {
      Picker("Utility", selection: $selectedUtility) {
        ForEach(WorkbenchUtility.allCases) { utility in
          Label(utility.title, systemImage: utility.systemImage).tag(utility)
        }
      }
      .pickerStyle(.segmented)

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

      if workspace.frameMode == .live {
        ControlGroup {
          Button {
            Task { await workspace.discoverCameras() }
          } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
          }
          Button {
            Task { await workspace.startCamera() }
          } label: {
            Label("Start", systemImage: "play.fill")
          }
          Button {
            Task { await workspace.stopCamera() }
          } label: {
            Label("Stop Camera", systemImage: "stop.fill")
          }
          Button {
            Task { await workspace.restartCamera() }
          } label: {
            Label("Restart", systemImage: "arrow.clockwise")
          }
        }

        ControlGroup {
          Button {
            Task {
              if workspace.analysisFrameHeld {
                await workspace.resumeLivePreview()
              } else {
                await workspace.inspectLatestScene()
              }
            }
          } label: {
            Label(
              workspace.analysisFrameHeld ? "Resume Preview" : "Analyze Frame",
              systemImage: workspace.analysisFrameHeld ? "play" : "viewfinder"
            )
          }
          .disabled(workspace.sceneInspectionInProgress || workspace.automaticVisionEnabled)
          Button {
            Task { await workspace.captureCameraSnapshot() }
          } label: {
            Label("Save Snapshot", systemImage: "camera")
          }
        }

        Toggle(
          "Auto Analyze",
          isOn: Binding(
            get: { workspace.automaticVisionEnabled },
            set: { enabled in Task { await workspace.setAutomaticVisionAnalysis(enabled) } }
          )
        )
        .toggleStyle(.switch)

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

        Text(
          "Preview and analysis are independent. Vision keeps one active frame and one newest pending frame; older pending work is replaced."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        if workspace.cameraDevices.isEmpty {
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
          }
        }
      } else {
        Picker(
          "Model",
          selection: Binding(
            get: { workspace.simulatorModelMode },
            set: { mode in Task { await workspace.selectSimulatorModelMode(mode) } }
          )
        ) {
          ForEach(SimulatorModelMode.allCases) { mode in
            Text(mode.rawValue).tag(mode)
          }
        }
        .pickerStyle(.segmented)

        Text(workspace.simulatorEvidenceLabel)
          .font(.caption.monospaced().bold())
          .foregroundStyle(.blue)
        Text(workspace.simulatorLearningSummary)
          .font(.caption)
          .foregroundStyle(.secondary)
        fact("Simulated pen", workspace.simulatorPenState.rawValue)
      }

      fact("State", workspace.cameraStateText)
      fact("Current frame age", workspace.frameAgeText)
      if workspace.frameMode == .live {
        fact("Vision", workspace.sceneMeasurementText)
        fact("Capture path", workspace.captureThroughputText)
        fact("Analysis path", workspace.visionThroughputText)
        if let path = workspace.lastCameraSnapshotPath {
          Text(path)
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
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
    SectionPanel(title: "RELATIVE MOTION") {
      Text(
        "Manual steps remain finite typed requests. The controller's end-stops and alarms, one-operation serialization, pen-up travel, and ambiguous outcomes are checked directly."
      )
      .font(.caption2)
      .foregroundStyle(.secondary)

      Text("Manual Motion")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)

      HStack(spacing: 8) {
        numericField("X step", text: $workspace.xStepText)
        numericField("Y step", text: $workspace.yStepText)
        numericField("Feed", text: $workspace.feedText)
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

      if let reason = workspace.motionUnavailableReason {
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
        .labelStyle(.iconOnly)
        .frame(width: 32, height: 24)
    }
      .buttonStyle(.borderedProminent)
      .disabled(workspace.motionUnavailableReason != nil)
      .help("Jog \(label)")
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
