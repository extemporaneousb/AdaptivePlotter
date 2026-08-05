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
        .frame(minWidth: 1_080, minHeight: 740)
    }
  }
}

struct OperatorWorkspaceView: View {
  @Bindable var workspace: OperatorWorkspace

  var body: some View {
    VStack(spacing: 0) {
      CurrentStatusBar(workspace: workspace)

      HStack(alignment: .top, spacing: 10) {
        VStack(spacing: 8) {
          ActionSurface(presentation: workspace.actionSurfacePresentation)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          LayerControls(workspace: workspace)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        ScrollView {
          VStack(spacing: 10) {
            CameraPanel(workspace: workspace)
            MotionPanel(workspace: workspace)
            DevicePanel(workspace: workspace)
          }
        }
        .frame(width: 310)
      }
      .padding(10)
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .task {
      await workspace.refreshSerialDevices()
      await workspace.startPreferredCameraAtStartup()
    }
    .onDisappear { Task { await workspace.shutdown() } }
  }
}

private struct CurrentStatusBar: View {
  @Bindable var workspace: OperatorWorkspace

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 20) {
        fact("SOURCE", workspace.frameMode.rawValue)
        fact("CAMERA", workspace.cameraStateText)
        fact("FRAME AGE", workspace.frameAgeText)
        fact("CONTROLLER", workspace.controllerStateText)
        fact("OPERATION", workspace.currentOperationText)
        Spacer()
      }
      Text(workspace.actionableError ?? "No current error")
        .font(.caption.monospaced())
        .foregroundStyle(workspace.actionableError == nil ? Color.secondary : Color.orange)
        .lineLimit(2)
        .textSelection(.enabled)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .background(Color(nsColor: .controlBackgroundColor))
    .overlay(alignment: .bottom) { Divider() }
  }

  private func fact(_ name: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(name).font(.caption2).foregroundStyle(.secondary)
      Text(value).font(.caption.monospaced()).textSelection(.enabled)
    }
  }
}

private struct CameraPanel: View {
  @Bindable var workspace: OperatorWorkspace

  var body: some View {
    SectionPanel(title: "ACTION SURFACE") {
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
        Text("Deterministic pixels. No physical camera or controller evidence.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      fact("State", workspace.cameraStateText)
      fact("Current frame age", workspace.frameAgeText)
      if let error = workspace.cameraError {
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
        Button("Confirm Pen Is Up") { Task { await workspace.confirmPenUp() } }
          .buttonStyle(.borderedProminent)
          .disabled(workspace.selectedSerialDevice == nil)
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

      if let reason = workspace.motionUnavailableReason {
        Text(reason)
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

private struct LayerControls: View {
  @Bindable var workspace: OperatorWorkspace

  var body: some View {
    HStack(spacing: 14) {
      Text("OVERLAYS").font(.caption2).foregroundStyle(.secondary)
      ForEach(CanvasLayer.allCases) { layer in
        Toggle(
          layer.rawValue,
          isOn: Binding(
            get: { workspace.visibleLayers.contains(layer) },
            set: { workspace.setLayer(layer, visible: $0) }
          )
        )
        .toggleStyle(.checkbox)
        .font(.caption)
      }
      Spacer()
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
    .background(Color(nsColor: .underPageBackgroundColor).opacity(0.45))
    .clipShape(RoundedRectangle(cornerRadius: 7))
  }
}
