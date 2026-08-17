import PlotterRuntime
import SwiftUI

enum WorkbenchConnectionIndicator: CaseIterable, Hashable, Identifiable {
  case camera
  case plotter
  case motionGuard

  var id: Self { self }

  var systemImage: String {
    switch self {
    case .camera: "video.fill"
    case .plotter: "printer.fill"
    case .motionGuard: "bolt.shield.fill"
    }
  }

  var title: String {
    switch self {
    case .camera: "Camera"
    case .plotter: "Plotter"
    case .motionGuard: "Motion"
    }
  }

  func label(isActive: Bool) -> String {
    switch (self, isActive) {
    case (.camera, true): "Camera Live"
    case (.camera, false): "Camera Off"
    case (.plotter, true): "Plotter Connected"
    case (.plotter, false): "Plotter Disconnected"
    case (.motionGuard, true): "Motion Enabled"
    case (.motionGuard, false): "Motion Disabled"
    }
  }
}

enum WorkbenchTopBarStatusStyle {
  static func systemImage(needsAttention: Bool) -> String {
    needsAttention ? "exclamationmark.triangle.fill" : "info.circle"
  }
}

struct WorkbenchControllerSlotPresentation: Equatable, Sendable {
  let title: String
  let isSerialSelectionEnabled: Bool

  init(mode: OperatorFrameMode) {
    switch mode {
    case .live:
      title = "Controller"
      isSerialSelectionEnabled = true
    case .simulated:
      title = "Learning Simulator"
      isSerialSelectionEnabled = false
    }
  }
}

struct WorkbenchMotionAuthorizationActionPresentation: Equatable, Sendable {
  let title: String
  let role: OperatorButtonRole

  init(isAuthorized: Bool) {
    title = isAuthorized ? "Disable Motion" : "Enable Motion"
    role = isAuthorized ? .negative : .affirmative
  }
}

/// Native macOS window-toolbar controls for the camera-first workbench.
///
/// Only controller/session controls and compact truthful status live here.
/// Exercise Stop and utility-panel launchers belong to the workbench content.
struct WorkbenchToolbar: ToolbarContent {
  @Bindable var workspace: OperatorWorkspace
  let capabilityPresentation: WorkbenchCapabilityPresentation?

  init(
    workspace: OperatorWorkspace,
    capabilityPresentation: WorkbenchCapabilityPresentation? = nil
  ) {
    self.workspace = workspace
    self.capabilityPresentation = capabilityPresentation
  }

  var body: some ToolbarContent {
    ToolbarItem(placement: .principal) {
      let controllerSlot = WorkbenchControllerSlotPresentation(mode: workspace.frameMode)
      let motionAction = WorkbenchMotionAuthorizationActionPresentation(
        isAuthorized: workspace.motionAuthorizationEnabled
      )
      HStack(spacing: 8) {
        if !controllerSlot.isSerialSelectionEnabled {
          Label(controllerSlot.title, systemImage: "cpu")
            .frame(width: 220)
            .foregroundStyle(.secondary)
            .help("SIMULATED uses the isolated learning simulator, not a serial controller")
        } else {
          Picker(
            "Controller",
            selection: Binding(
              get: { workspace.selectedSerialDevice },
              set: { device in
                guard let device else { return }
                Task { await workspace.selectSerialDevice(device) }
              }
            )
          ) {
            Text("Select Controller").tag(nil as MachineLinkDescriptor?)
            ForEach(workspace.serialDevices, id: \.identifier) { device in
              Text(device.displayName).tag(Optional(device))
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(width: 220)
          .disabled(workspace.controllerSelectionUnavailableReason != nil)
          .help("Controller selection is remembered between launches")
        }

        Button(workspace.controllerConnectionActionTitle) {
          Task { await workspace.performControllerConnectionAction() }
        }
        .operatorButton(
          workspace.controllerSessionEstablished ? .negative : .affirmative,
          isEnabled: workspace.controllerConnectionActionUnavailableReason == nil
        )
        .help(
          workspace.controllerConnectionActionUnavailableReason
            ?? "\(workspace.controllerConnectionActionTitle) the selected controller"
        )

        Button(motionAction.title) {
          Task { await workspace.performMotionAuthorizationAction() }
        }
        .operatorButton(
          motionAction.role,
          isEnabled: workspace.motionAuthorizationActionUnavailableReason == nil
        )
        .help(
          workspace.motionAuthorizationActionUnavailableReason
            ?? "\(motionAction.title) for this controller session"
        )
      }
    }

    ToolbarItem(placement: .primaryAction) {
      HStack(spacing: 12) {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
          WorkbenchStatusIndicator(
            indicator: .camera,
            label: workspace.frameMode == .simulated
              ? "Simulator"
              : WorkbenchConnectionIndicator.camera.label(isActive: workspace.cameraIsLive),
            color: workspace.frameMode == .simulated
              ? .blue
              : workspace.cameraIsLive ? .green : .red
          )
        }
        WorkbenchStatusIndicator(
          indicator: .plotter,
          label: WorkbenchConnectionIndicator.plotter.label(
            isActive: workspace.controllerSessionEstablished
          ),
          color: workspace.controllerSessionEstablished ? .green : .red
        )
        WorkbenchStatusIndicator(
          indicator: .motionGuard,
          label: WorkbenchConnectionIndicator.motionGuard.label(
            isActive: workspace.motionAuthorizationEnabled
          ),
          color: workspace.motionAuthorizationEnabled ? .green : .red
        )
        MotionRequestStatusView(presentation: workspace.motionRequestStatusPresentation)
        if let capabilityPresentation {
          Divider().frame(height: 20)
          WorkbenchCapabilityIndicator(presentation: capabilityPresentation)
        }
      }
    }
  }
}

private struct MotionRequestStatusView: View {
  let presentation: MotionRequestStatusPresentation

  var body: some View {
    Label(presentation.label, systemImage: systemImage)
      .font(.caption)
      .foregroundStyle(color)
      .fixedSize()
      .accessibilityLabel("Motion request \(presentation.label)")
      .accessibilityValue(presentation.detail ?? "Eligible now")
      .help(presentation.detail ?? "An ordinary carriage request is eligible now")
  }

  private var systemImage: String {
    switch presentation {
    case .ready: "checkmark.circle.fill"
    case .busy: "arrow.triangle.2.circlepath"
    case .unavailable: "pause.circle.fill"
    case .needsAttention:
      WorkbenchTopBarStatusStyle.systemImage(needsAttention: true)
    }
  }

  private var color: Color {
    switch presentation {
    case .ready: .green
    case .busy: .accentColor
    case .unavailable: .secondary
    case .needsAttention: .orange
    }
  }
}

private struct WorkbenchStatusIndicator: View {
  let indicator: WorkbenchConnectionIndicator
  let label: String
  let color: Color

  var body: some View {
    HStack(spacing: 4) {
      ZStack {
        Circle()
          .fill(color)
          .frame(width: 17, height: 17)
        Image(systemName: indicator.systemImage)
          .font(.system(size: 8, weight: .semibold))
          .foregroundStyle(.white)
      }
      Text(label)
        .font(.caption)
    }
    .fixedSize()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .help(label)
  }
}
