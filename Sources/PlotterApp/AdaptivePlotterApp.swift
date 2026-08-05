import PlotterRuntime
import SwiftUI

@main
@MainActor
struct AdaptivePlotterApp: App {
  @State private var workspace = OperatorWorkspace(
    machineActions: MachineSessionComposition.actions,
    cameraActions: CameraComposition.actions
  )

  var body: some Scene {
    WindowGroup("AdaptivePlotter") {
      OperatorWorkspaceView(workspace: workspace)
        .frame(minWidth: 1_180, minHeight: 760)
    }
  }
}

struct OperatorWorkspaceView: View {
  @Bindable var workspace: OperatorWorkspace
  @State private var layout = WorkbenchLayoutState()

  private let topInset: CGFloat = 72

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .top) {
        ActionSurface(presentation: workspace.actionSurfacePresentation)
          .frame(maxWidth: .infinity, maxHeight: .infinity)

        ForEach(WorkbenchPanel.allCases) { panel in
          if layout[panel].isVisible {
            FloatingWorkbenchPanel(
              panel: panel,
              layout: $layout,
              containerSize: proxy.size,
              topInset: topInset
            ) {
              panelContent(panel)
            }
            .zIndex(layout.zIndex(for: panel))
          }
        }

        WorkbenchTopBar(workspace: workspace, layout: $layout)
          .padding(10)
          .zIndex(1_000)
      }
    }
    .background(Color.black)
    .task {
      await workspace.refreshSerialDevices()
      await workspace.startPreferredCameraAtStartup()
    }
    .onDisappear { Task { await workspace.shutdown() } }
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

private struct WorkbenchTopBar: View {
  @Bindable var workspace: OperatorWorkspace
  @Binding var layout: WorkbenchLayoutState

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        ForEach(WorkbenchPanel.allCases) { panel in
          Button {
            layout.toggleVisibility(panel)
          } label: {
            Label(panel.rawValue, systemImage: panel.systemImage)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .tint(layout[panel].isVisible ? .accentColor : .secondary)
        }

        Button("Hide All") { layout.hideAll() }
          .buttonStyle(.borderless)
          .controlSize(.small)

        Spacer()

        fact("source", workspace.frameMode.rawValue)
        fact("camera", workspace.cameraStateText)
        fact("frame", workspace.frameAgeText)
        fact("controller", workspace.controllerStateText)
        fact("operation", workspace.currentOperationText)
      }

      HStack(spacing: 5) {
        Image(systemName: workspace.actionableError == nil ? "checkmark.circle" : "exclamationmark.triangle")
        Text(workspace.actionableError ?? "No current error")
      }
        .font(.caption.monospaced())
        .foregroundStyle(workspace.actionableError == nil ? Color.secondary : Color.orange)
        .lineLimit(1)
        .textSelection(.enabled)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .stroke(.white.opacity(0.16), lineWidth: 1)
    }
  }

  private func fact(_ name: String, _ value: String) -> some View {
    HStack(spacing: 3) {
      Text(name.uppercased()).font(.caption2).foregroundStyle(.secondary)
      Text(value).font(.caption2.monospaced()).textSelection(.enabled)
    }
  }
}

private struct FloatingWorkbenchPanel<Content: View>: View {
  let panel: WorkbenchPanel
  @Binding var layout: WorkbenchLayoutState
  let containerSize: CGSize
  let topInset: CGFloat
  @ViewBuilder let content: Content

  @State private var dragStart: WorkbenchPanelPresentation?

  private var panelSize: CGSize {
    let preferred = panel.preferredSize
    return CGSize(
      width: min(preferred.width, max(280, containerSize.width - 24)),
      height: layout[panel].isCollapsed
        ? 42
        : min(preferred.height, max(160, containerSize.height - topInset - 12))
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 7) {
        Image(systemName: "line.3.horizontal")
          .foregroundStyle(.secondary)
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
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 3)
          .onChanged { value in
            if dragStart == nil {
              dragStart = layout[panel]
              layout.bringToFront(panel)
            }
            guard let dragStart else { return }
            layout.move(
              panel,
              from: dragStart,
              translation: value.translation,
              in: containerSize,
              panelSize: panelSize,
              topInset: topInset
            )
          }
          .onEnded { _ in dragStart = nil }
      )

      if !layout[panel].isCollapsed {
        Divider()
        ScrollView {
          content
            .padding(8)
        }
        .scrollIndicators(.visible)
      }
    }
    .frame(width: panelSize.width, height: panelSize.height, alignment: .top)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))
    .overlay {
      RoundedRectangle(cornerRadius: 11)
        .stroke(.white.opacity(0.2), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.4), radius: 12, y: 5)
    .position(
      layout.center(
        for: panel,
        in: containerSize,
        panelSize: panelSize,
        topInset: topInset
      )
    )
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
        Button("PEN UP") { Task { await workspace.requestPenActuation(.raise) } }
          .buttonStyle(.borderedProminent)
          .disabled(workspace.penUnavailableReason(for: .raise) != nil)
        Button("PEN DOWN") { Task { await workspace.requestPenActuation(.lower) } }
          .buttonStyle(.bordered)
          .tint(.red)
          .disabled(workspace.penUnavailableReason(for: .lower) != nil)
        Spacer()
        Text(workspace.penStateText.uppercased())
          .font(.caption.monospaced().bold())
      }

      DisclosureGroup("Session motion limits") {
        VStack(spacing: 6) {
          Text(
            "Provisional local priors: 1 mm jogs, 100 mm/min, 5 mm command cap, and a conservative X −100…100 / Y −40…40 window around the observed session-start zero. Review before applying."
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

      fact("MPos", workspace.machinePositionText)
      fact("Controller", workspace.controllerStateText)
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
      Button("Refresh Serial Devices") { Task { await workspace.refreshSerialDevices() } }
        .disabled(workspace.passiveProbeInProgress || workspace.jogRequestInProgress)

      if workspace.serialDevices.isEmpty {
        Text("No discovered /dev/cu.* serial devices.")
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
      } else {
        ForEach(workspace.serialDevices, id: \.identifier) { device in
          Button {
            Task { await workspace.selectSerialDevice(device) }
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(device.displayName)
              Text(device.bsdPath ?? device.identifier)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.plain)
          .padding(6)
          .background(
            workspace.selectedSerialDevice?.identifier == device.identifier
              ? Color.accentColor.opacity(0.18) : Color.clear
          )
          .clipShape(RoundedRectangle(cornerRadius: 5))
        }
      }

      Button("Request Passive Probe") { Task { await workspace.requestPassiveProbe() } }
        .disabled(workspace.passiveProbeUnavailableReason != nil)

      Button("Disconnect Session") { Task { await workspace.disconnectMachineSession() } }
        .disabled(
          workspace.selectedSerialDevice == nil
            || workspace.passiveProbeInProgress
            || workspace.jogRequestInProgress
            || workspace.penRequestInProgress
        )

      if let reason = workspace.passiveProbeUnavailableReason {
        Text(reason).font(.caption).foregroundStyle(.orange)
      }
      if let result = workspace.passiveProbeResult {
        ProbeSummary(result: result)
      }
    }
  }
}

private struct ProbeSummary: View {
  let result: PassiveProbeResult

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(result.blockers.isEmpty ? "PROBE COMPLETE" : "PROBE NEEDS ATTENTION")
        .font(.caption.monospaced().bold())
        .foregroundStyle(result.blockers.isEmpty ? Color.secondary : Color.orange)
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
    SectionPanel(title: "EXPLICIT MODEL-LEARNING LOOP") {
      Text(
        "This is an inspectable research sequence, not a readiness wizard. Physical evidence and simulated evidence remain separate."
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      ForEach(workspace.learningWorkbenchSteps) { step in
        HStack(alignment: .top, spacing: 8) {
          Text("\(step.number)")
            .font(.caption.monospaced().bold())
            .frame(width: 20, height: 20)
            .background(stepColor(step.state).opacity(0.2), in: Circle())
          VStack(alignment: .leading, spacing: 2) {
            HStack {
              Text(step.title).font(.caption.bold())
              Spacer()
              Text(step.state.rawValue.uppercased())
                .font(.caption2.monospaced())
                .foregroundStyle(stepColor(step.state))
            }
            Text(step.detail)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
      }

      Divider()
      Text(
        "Next boundary: record timestamped frame/configuration, recognized camera geometry, controller MPos, registration identity, algorithm revision, and a fixed train/holdout assignment. Candidate fitting never changes the accepted model until an explicit pen-up acceptance."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private func stepColor(_ state: LearningWorkbenchStepState) -> Color {
    switch state {
    case .available: .secondary
    case .observed: .green
    case .simulated: .blue
    case .notWired: .orange
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
