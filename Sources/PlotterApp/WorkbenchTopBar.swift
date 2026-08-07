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
    case (.motionGuard, true): "Motion Ready"
    case (.motionGuard, false): "Motion Blocked"
    }
  }
}

enum WorkbenchTopBarStatusStyle {
  static func systemImage(needsAttention: Bool) -> String {
    needsAttention ? "exclamationmark.triangle.fill" : "info.circle"
  }
}

/// Native macOS window-toolbar controls for the camera-first workbench.
///
/// The controller picker, connection actions, panel access, and three truthful
/// status indicators stay in the window chrome instead of consuming camera
/// pixels in a custom two-row strip.
struct WorkbenchToolbar: ToolbarContent {
  @Bindable var workspace: OperatorWorkspace
  @Binding var layout: WorkbenchLayoutState

  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .navigation) {
      ForEach(WorkbenchPanel.allCases) { panel in
        Button {
          layout.toggleVisibility(panel)
        } label: {
          Label(panel.rawValue, systemImage: panel.systemImage)
        }
        .help(layout[panel].isVisible ? "Hide \(panel.rawValue)" : "Show \(panel.rawValue)")
      }

      Menu {
        Button("Hide All Panels") { layout.hideAll() }
        Divider()
        ForEach(WorkbenchPanel.allCases) { panel in
          Button(layout[panel].isVisible ? "Hide \(panel.rawValue)" : "Show \(panel.rawValue)") {
            layout.toggleVisibility(panel)
          }
        }
      } label: {
        Label("Panel Options", systemImage: "ellipsis.circle")
      }
    }

    ToolbarItem(placement: .principal) {
      HStack(spacing: 8) {
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

        Button("Connect") {
          Task { await workspace.connectSelectedController() }
        }
        .buttonStyle(.borderedProminent)
        .disabled(
          workspace.passiveProbeUnavailableReason != nil || workspace.controllerIsConnected
        )

        Button("Activate Motion") {
          Task { await workspace.activateMotionGuard() }
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .disabled(workspace.motionGuardActivationUnavailableReason != nil)
      }
    }

    ToolbarItem(placement: .primaryAction) {
      TimelineView(.periodic(from: .now, by: 0.25)) { _ in
        HStack(spacing: 12) {
          WorkbenchStatusIndicator(
            indicator: .camera,
            label: workspace.frameMode == .simulated
              ? "Simulator"
              : WorkbenchConnectionIndicator.camera.label(isActive: workspace.cameraIsLive),
            color: workspace.frameMode == .simulated
              ? .blue
              : workspace.cameraIsLive ? .green : .red
          )
          WorkbenchStatusIndicator(
            indicator: .plotter,
            label: WorkbenchConnectionIndicator.plotter.label(
              isActive: workspace.controllerIsConnected
            ),
            color: workspace.controllerIsConnected ? .green : .red
          )
          WorkbenchStatusIndicator(
            indicator: .motionGuard,
            label: WorkbenchConnectionIndicator.motionGuard.label(
              isActive: workspace.motionGuardAllowsCarriageMotion
            ),
            color: workspace.motionGuardAllowsCarriageMotion ? .green : .red
          )
        }
      }
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
      Text(indicator.title)
        .font(.caption)
    }
    .fixedSize()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .help(label)
  }
}

struct WorkbenchStatusBanner: View {
  @Bindable var workspace: OperatorWorkspace

  var body: some View {
    Label(
      workspace.workbenchStatusText,
      systemImage: WorkbenchTopBarStatusStyle.systemImage(
        needsAttention: workspace.workbenchStatusNeedsAttention
      )
    )
    .font(.caption)
    .foregroundStyle(workspace.workbenchStatusNeedsAttention ? Color.orange : Color.secondary)
    .lineLimit(2)
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    .textSelection(.enabled)
  }
}
