import AppKit
import PlotterModel
import PlotterRuntime
import SwiftUI

@MainActor
final class AdaptivePlotterApplicationDelegate: NSObject, NSApplicationDelegate {
  let workspace = OperatorWorkspace(
    machineActions: MachineSessionComposition.actions,
    cameraActions: CameraComposition.actions,
    voiceActions: VoiceComposition.actions
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
    Window("AdaptivePlotter", id: "operator-workspace") {
      OperatorWorkspaceView(workspace: applicationDelegate.workspace)
        .frame(minWidth: 1_180, minHeight: 760)
    }
  }
}

private enum VoiceComposition {
  private static let driver = NativeVoiceInteractionDriver(
    recognitionPolicy: .onDeviceRequired
  )
  private static let speech = NativeVoiceSpeechOutput()

  static let actions = OperatorWorkspace.VoiceActions(
    requestAuthorization: { await driver.requestAuthorization() },
    startListening: {
      await driver.startListening()
      switch await driver.snapshot().listeningState {
      case .listening:
        return
      case .failed(let error):
        throw error
      case .stopped, .requestingPermission:
        throw VoiceInteractionError.recognition(
          "The recognizer did not enter the listening state."
        )
      }
    },
    stopListening: { await driver.stopListening() },
    snapshot: { await driver.snapshot() },
    transcripts: { await driver.transcripts() },
    speak: { text in await speech.speak(text) },
    stopSpeaking: { await speech.stopSpeaking() },
    signal: { await MainActor.run { NSSound.beep() } }
  )
}

struct OperatorWorkspaceView: View {
  @Bindable var workspace: OperatorWorkspace
  @State private var layout = WorkbenchLayoutState()

  var body: some View {
    VStack(spacing: WorkbenchTopBarLayoutMetrics.externalTopInset) {
      FlushWorkbenchTopBar(workspace: workspace, layout: $layout)

      GeometryReader { proxy in
        let geometry = layout.geometry(
          in: proxy.size,
          preferredDockWidth: 390,
          spacing: 8,
          minimumActionSurfaceWidth: 360
        )
        ZStack(alignment: .topLeading) {
          ActionSurface(presentation: workspace.actionSurfacePresentation)
            .frame(
              width: geometry.actionSurface.width,
              height: geometry.actionSurface.height
            )
            .position(
              x: geometry.actionSurface.midX,
              y: geometry.actionSurface.midY
            )

          if let dock = geometry.leftDock {
            dockColumn(side: .left)
              .frame(width: dock.width, height: dock.height)
              .position(x: dock.midX, y: dock.midY)
          }

          if let dock = geometry.rightDock {
            dockColumn(side: .right)
              .frame(width: dock.width, height: dock.height)
              .position(x: dock.midX, y: dock.midY)
          }
        }
      }
    }
    .background(Color.black)
    .task {
      await workspace.refreshSerialDevices()
      await workspace.startPreferredCameraAtStartup()
    }
  }

  private func dockColumn(side: WorkbenchDockSide) -> some View {
    ScrollView {
      LazyVStack(spacing: 8) {
        ForEach(layout.visiblePanels(in: side)) { panel in
          DockedWorkbenchPanel(panel: panel, layout: $layout) {
            panelContent(panel)
          }
        }
      }
      .padding(8)
    }
    .scrollIndicators(.visible)
    .background(.black.opacity(0.32))
  }

  @ViewBuilder
  private func panelContent(_ panel: WorkbenchPanel) -> some View {
    switch panel {
    case .motion: MotionPanel(workspace: workspace)
    case .camera: CameraPanel(workspace: workspace)
    case .overlays: OverlayPanel(workspace: workspace)
    case .learning: LearningPanel(workspace: workspace)
    case .controller: DevicePanel(workspace: workspace)
    }
  }
}

enum SpeechMovementTestPresentation {
  static let title = "SPEECH MOVEMENT TEST"

  static let cameraSteps = [
    "Confirm the PLOTTER CONNECTED indicator is green.",
    "In Motion, apply Typed Limits and press COMMAND PEN UP.",
    "Turn Speech On and confirm Listening says listening.",
    "In Motion, press one Start X−, X+, Y−, or Y+ Test button to arm that direction.",
    "After the signal, say READY. While the carriage is moving, say STOP.",
  ]

  static func startButtonLabel(for direction: JogDirection) -> String {
    "Start \(direction.shortLabel) Test"
  }
}

private struct DockedWorkbenchPanel<Content: View>: View {
  let panel: WorkbenchPanel
  @Binding var layout: WorkbenchLayoutState
  @ViewBuilder let content: Content

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 7) {
        Image(systemName: panel.systemImage)
        Text(panel.rawValue.uppercased())
          .font(.caption.monospaced().bold())
        Spacer()
        Button {
          layout.toggleCollapsed(panel)
        } label: {
          Image(systemName: layout[panel].isCollapsed ? "chevron.down" : "chevron.up")
        }
        .buttonStyle(.plain)
        Button {
          layout.hide(panel)
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 10)
      .frame(height: 42)

      if !layout[panel].isCollapsed {
        Divider()
        content.padding(8)
      }
    }
    .frame(maxWidth: .infinity, alignment: .top)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))
    .overlay {
      RoundedRectangle(cornerRadius: 11)
        .stroke(.white.opacity(0.2), lineWidth: 1)
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
        HStack {
          Button("Refresh Cameras") { Task { await workspace.discoverCameras() } }
          Button("Start Capture") { Task { await workspace.startCamera() } }
          Button("Stop Capture") { Task { await workspace.stopCamera() } }
          Button("Restart Capture") { Task { await workspace.restartCamera() } }
        }
        .controlSize(.small)

        HStack {
          Button(workspace.analysisFrameHeld ? "Resume Preview" : "Analyze Frame") {
            Task {
              if workspace.analysisFrameHeld {
                await workspace.resumeLivePreview()
              } else {
                await workspace.inspectLatestScene()
              }
            }
          }
          .disabled(workspace.sceneInspectionInProgress || workspace.automaticVisionEnabled)
          Button("Save Snapshot") { Task { await workspace.captureCameraSnapshot() } }
        }
        .controlSize(.small)

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

      Divider()

      Text("SPEECH")
        .font(.caption.monospaced().bold())
        .foregroundStyle(.secondary)

      HStack {
        Button("Speech On") { Task { await workspace.startVoiceListening() } }
          .buttonStyle(.borderedProminent)
          .disabled(workspace.voiceListeningUnavailableReason != nil)
        Button("Speech Off") { Task { await workspace.stopVoiceListening() } }
          .disabled(!workspace.voiceListening)
      }
      .controlSize(.small)

      VStack(alignment: .leading, spacing: 4) {
        Text("NEXT: \(SpeechMovementTestPresentation.title)")
          .font(.caption.monospaced().bold())
        ForEach(SpeechMovementTestPresentation.cameraSteps.indices, id: \.self) { index in
          Text("\(index + 1). \(SpeechMovementTestPresentation.cameraSteps[index])")
            .font(.caption2)
        }
        Text("Until a direction is armed, speech has no motion meaning.")
          .font(.caption2.monospaced().bold())
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(8)
      .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))

      fact("Permission", workspace.voicePermissionText)
      fact("Listening", workspace.voiceListeningText)
      fact("Transcript", workspace.voiceTranscriptText)
      fact("Understood", workspace.lastVoiceIntentText)
      fact("Voice result", workspace.lastVoiceActionableResultText)
      fact("Last spoken", workspace.lastSpokenFeedbackText)

      if let reason = workspace.voiceListeningUnavailableReason,
        !workspace.voiceListening
      {
        Text(reason).font(.caption).foregroundStyle(.orange)
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
    SectionPanel(title: "BOUNDED RELATIVE MOTION") {
      Text(SpeechMovementTestPresentation.title)
        .font(.caption.monospaced().bold())
        .foregroundStyle(.secondary)

      Text(
        "First connect the plotter, apply Typed Limits, command Pen Up, and turn Speech On. Speech does nothing until one direction is armed here. Press one Start Test button, wait for the signal, then say READY. Say STOP only while that test is moving. A cancelled jog's final MPos is a boundary observation, not calibration."
      )
      .font(.caption2)
      .foregroundStyle(.secondary)

      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
        ForEach(JogDirection.allCases) { direction in
          Button(SpeechMovementTestPresentation.startButtonLabel(for: direction)) {
            Task { await workspace.beginBoundaryTeaching(direction) }
          }
          .buttonStyle(.borderedProminent)
          .disabled(workspace.boundaryTeachingUnavailableReason != nil)
        }
      }

      if workspace.boundaryTeachingState != .idle {
        Button("Cancel Speech Movement Test") {
          Task { await workspace.cancelBoundaryTeaching() }
        }
        .buttonStyle(.bordered)
        .tint(.orange)
      }

      fact("Test state", workspace.boundaryTeachingStateText)
      fact("Test result", workspace.boundaryTeachingResultText)
      ForEach(JogDirection.allCases) { direction in
        fact("Boundary \(direction.shortLabel)", workspace.boundaryPositionText(for: direction))
      }

      if let reason = workspace.boundaryTeachingUnavailableReason,
        workspace.boundaryTeachingState == .idle
      {
        Text("Setup required: \(reason)").font(.caption).foregroundStyle(.orange)
      }

      Divider()

      Text("MANUAL MOTION AND SETUP")
        .font(.caption.monospaced().bold())
        .foregroundStyle(.secondary)

      HStack(spacing: 8) {
        numericField("X step", text: $workspace.xStepText)
        numericField("Y step", text: $workspace.yStepText)
        numericField("Feed", text: $workspace.feedText)
      }

      VStack(spacing: 5) {
        jogButton("Y+", direction: .yPositive)
        HStack(spacing: 5) {
          jogButton("X−", direction: .xNegative)
          jogButton("X+", direction: .xPositive)
        }
        jogButton("Y−", direction: .yNegative)
      }
      .frame(maxWidth: .infinity)

      HStack {
        Button("COMMAND PEN UP") { Task { await workspace.requestPenActuation(.raise) } }
          .buttonStyle(.bordered)
          .tint(.blue)
          .disabled(workspace.penUnavailableReason(for: .raise) != nil)
        Button("COMMAND PEN DOWN") { Task { await workspace.requestPenActuation(.lower) } }
          .buttonStyle(.bordered)
          .tint(.red)
          .disabled(workspace.penUnavailableReason(for: .lower) != nil)
      }

      Text(workspace.penStateText.uppercased())
        .font(.caption.monospaced().bold())
        .foregroundStyle(.secondary)
      Text("Commanded state is controller evidence only; the camera cannot observe pen height.")
        .font(.caption2)
        .foregroundStyle(.secondary)

      DisclosureGroup("Session motion limits") {
        VStack(spacing: 6) {
          Text(
            "Session-local safety envelope. The visible wood rails reduce usable Y: enter MachineSpace bounds that stay inside their inner edges. Camera pixels are not converted into trusted motion bounds. Review all values before applying."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          HStack(spacing: 8) {
            numericField("X min", text: $workspace.minimumXText)
            numericField("X max", text: $workspace.maximumXText)
          }
          HStack(spacing: 8) {
            numericField("Y min", text: $workspace.minimumYText)
            numericField("Y max", text: $workspace.maximumYText)
          }
          HStack(spacing: 8) {
            numericField("Max distance", text: $workspace.maximumDistanceText)
            numericField("Max feed", text: $workspace.maximumFeedText)
          }
          Button("Apply Typed Limits") { Task { await workspace.applyMotionLimits() } }
            .disabled(workspace.limitsUnavailableReason != nil)
          if let reason = workspace.limitsUnavailableReason {
            Text(reason).font(.caption).foregroundStyle(.orange)
          }
        }
        .padding(.top, 6)
      }

      fact("Controller link", workspace.controllerConnectionText)
      fact("Controller", workspace.controllerStateText)
      fact("Motor power", workspace.motorPowerText)
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

      Button("Cancel Current Jog") {
        Task { await workspace.requestJogCancel() }
      }
      .buttonStyle(.bordered)
      .tint(.orange)
      .disabled(workspace.jogCancelUnavailableReason != nil)

      fact("Jog cancel", workspace.lastJogCancelOutcomeText)

      if let reason = workspace.jogCancelUnavailableReason {
        Text("Cancel jog: \(reason)").font(.caption).foregroundStyle(.orange)
      }
    }
  }

  private func jogButton(_ label: String, direction: JogDirection) -> some View {
    Button(label) { Task { await workspace.requestJog(direction) } }
      .buttonStyle(.borderedProminent)
      .disabled(workspace.motionUnavailableReason != nil)
      .frame(minWidth: 64)
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

private struct DevicePanel: View {
  @Bindable var workspace: OperatorWorkspace

  var body: some View {
    SectionPanel(title: "CONTROLLER SESSION") {
      Picker(
        "Device",
        selection: Binding(
          get: { workspace.selectedSerialDevice },
          set: { device in
            guard let device else { return }
            Task { await workspace.selectSerialDevice(device) }
          }
        )
      ) {
        Text("Select a serial device").tag(nil as MachineLinkDescriptor?)
        ForEach(workspace.serialDevices, id: \.identifier) { device in
          Text(device.displayName).tag(Optional(device))
        }
      }
      .pickerStyle(.menu)
      .disabled(
        workspace.serialDevices.isEmpty
          || workspace.passiveProbeInProgress
          || workspace.jogRequestInProgress
      )

      Button("Connect") {
        Task { await workspace.connectSelectedController() }
      }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .disabled(
          workspace.passiveProbeUnavailableReason != nil || workspace.controllerIsConnected
        )

      Text(
        "Connect opens the selected serial session and passively reads identity, controller state, MPos, pins, and limits. It issues no motion or pen command."
      )
      .font(.caption2)
      .foregroundStyle(.secondary)

      fact(
        "Link",
        workspace.controllerIsConnected ? "CONNECTED" : workspace.controllerConnectionText
      )
      fact("Controller", workspace.controllerStateText)
      fact("Motor power", workspace.motorPowerText)
      fact("Motion request", workspace.motionPermissionText)

      if let reason = workspace.passiveProbeUnavailableReason {
        Text(reason).font(.caption).foregroundStyle(.orange)
      }
      if let result = workspace.passiveProbeResult {
        ControllerInspectionSummary(
          result: result,
          controllerIsConnected: workspace.controllerIsConnected
        )
      }
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

private struct ControllerInspectionSummary: View {
  let result: PassiveProbeResult
  let controllerIsConnected: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(controllerIsConnected ? "CONTROLLER CONNECTED" : "CONNECTION NEEDS ATTENTION")
        .font(.caption.monospaced().bold())
        .foregroundStyle(controllerIsConnected ? Color.secondary : Color.orange)
      Text("\(result.exchanges.count) exchanges")
        .font(.caption2.monospaced())
      ForEach(Array(result.blockers.enumerated()), id: \.offset) { entry in
        Text(machineBlockerLabel(entry.element))
          .font(.caption2.monospaced())
          .foregroundStyle(.orange)
      }
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

private struct LearningPanel: View {
  @Bindable var workspace: OperatorWorkspace

  var body: some View {
    SectionPanel(title: "JOG OBSERVATIONS") {
      Text(
        "Physical jog samples require one successful bounded motion plus exact live cap measurements before and after it. The camera does not observe pen height."
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      Text("DIAGNOSTIC — NOT MOTION AUTHORITY")
        .font(.caption.monospaced().bold())
        .foregroundStyle(.orange)

      Toggle(
        "Record Jog Observations",
        isOn: Binding(
          get: { workspace.recordJogObservations },
          set: { workspace.setRecordJogObservations($0) }
        )
      )
      .toggleStyle(.switch)
      .disabled(workspace.jogRequestInProgress)

      Picker(
        "Fixed assignment for next sample",
        selection: Binding(
          get: { workspace.selectedObservationSplit },
          set: { workspace.selectObservationSplit($0) }
        )
      ) {
        Text("TRAINING").tag(ModelObservationSplit.training)
        Text("HOLDOUT").tag(ModelObservationSplit.holdout)
      }
      .pickerStyle(.segmented)
      .disabled(workspace.jogRequestInProgress)

      Text("The selected assignment is copied into the request and cannot change on a recorded sample.")
        .font(.caption2)
        .foregroundStyle(.secondary)

      Button("Clear Samples") { workspace.clearJogObservationSamples() }
        .disabled(workspace.clearJogObservationSamplesUnavailableReason != nil)

      if let reason = workspace.clearJogObservationSamplesUnavailableReason {
        Text(reason)
          .font(.caption)
          .foregroundStyle(.orange)
      }

      if workspace.frameMode == .simulated {
        Text("SIMULATED — no physical observation can be recorded")
          .font(.caption.monospaced().bold())
          .foregroundStyle(.blue)
        Text(workspace.simulatorLearningSummary)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      fact("Samples", workspace.physicalJogObservationCountText)
      fact("Dataset", workspace.jogResponseDatasetCountText)
      fact("Response matrix", workspace.jogResponseMatrixText)
      fact("Training residual", workspace.jogResponseTrainingResidualText)
      fact("Holdout residual", workspace.jogResponseHoldoutResidualText)
      fact("Last result", workspace.lastPhysicalJogObservationResultText)
      fact("Start / final MPos", workspace.lastPhysicalJogPositionsText)
      fact("Camera delta", workspace.lastPhysicalJogCameraDeltaText)
      fact("Cap confidence", workspace.lastPhysicalJogConfidenceText)

      if let failure = workspace.lastPhysicalJogFailureText {
        Text(failure)
          .font(.caption)
          .foregroundStyle(.orange)
          .textSelection(.enabled)
      } else if let learnerError = workspace.jogResponseLearnerError {
        Text(learnerError)
          .font(.caption)
          .foregroundStyle(.orange)
          .textSelection(.enabled)
      } else if workspace.recordJogObservations,
        let reason = workspace.motionUnavailableReason
      {
        Text(reason)
          .font(.caption)
          .foregroundStyle(.orange)
      }
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

private struct SectionPanel<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.caption.monospaced().bold())
        .foregroundStyle(.secondary)
      content
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .padding(10)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .stroke(.white.opacity(0.14), lineWidth: 1)
    }
  }
}
