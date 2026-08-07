import PlotterRuntime
import SwiftUI

/// Layout values owned by the top bar itself.
///
/// The host must place `FlushWorkbenchTopBar` directly against the window
/// content's top edge. In particular, the former outer ten-point padding is
/// not part of this component's contract: it exposed the camera between the
/// window chrome and the bar.
enum WorkbenchTopBarLayoutMetrics {
  static let externalTopInset: CGFloat = 0
  static let horizontalContentPadding: CGFloat = 14
  static let verticalContentPadding: CGFloat = 9
  static let rowSpacing: CGFloat = 4
}

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

  func label(isActive: Bool) -> String {
    switch (self, isActive) {
    case (.camera, true): "CAMERA LIVE"
    case (.camera, false): "CAMERA OFF"
    case (.plotter, true): "PLOTTER CONNECTED"
    case (.plotter, false): "PLOTTER DISCONNECTED"
    case (.motionGuard, true): "MOTION READY"
    case (.motionGuard, false): "MOTION BLOCKED"
    }
  }
}

enum WorkbenchTopBarStatusStyle {
  static func systemImage(needsAttention: Bool) -> String {
    needsAttention ? "exclamationmark.triangle" : "info.circle"
  }
}

/// The camera-safe workbench controls and current-state summary.
///
/// This component deliberately fills the available width and draws one
/// continuous material surface all the way to its top edge. Padding is applied
/// only to its contents, so camera pixels cannot appear above the bar.
struct FlushWorkbenchTopBar: View {
  @Bindable var workspace: OperatorWorkspace
  @Binding var layout: WorkbenchLayoutState

  var body: some View {
    VStack(alignment: .leading, spacing: WorkbenchTopBarLayoutMetrics.rowSpacing) {
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

        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
          HStack(spacing: 6) {
            connectionIndicator(.camera, isActive: workspace.cameraIsLive)
            connectionIndicator(.plotter, isActive: workspace.controllerIsConnected)
            connectionIndicator(
              .motionGuard,
              isActive: workspace.motionGuardAllowsCarriageMotion
            )
          }
        }
      }

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
          Text("Select controller").tag(nil as MachineLinkDescriptor?)
          ForEach(workspace.serialDevices, id: \.identifier) { device in
            Text(device.displayName).tag(Optional(device))
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 250)
        .disabled(workspace.controllerSelectionUnavailableReason != nil)

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

        Spacer()

        HStack(spacing: 5) {
          Image(
            systemName: WorkbenchTopBarStatusStyle.systemImage(
              needsAttention: workspace.workbenchStatusNeedsAttention
            )
          )
          Text(workspace.workbenchStatusText)
        }
        .font(.caption.monospaced())
        .foregroundStyle(workspace.workbenchStatusNeedsAttention ? Color.orange : Color.secondary)
        .lineLimit(1)
        .textSelection(.enabled)
      }
    }
    .padding(.horizontal, WorkbenchTopBarLayoutMetrics.horizontalContentPadding)
    .padding(.vertical, WorkbenchTopBarLayoutMetrics.verticalContentPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.ultraThinMaterial)
    .overlay(alignment: .bottom) {
      Divider()
    }
  }

  private func connectionIndicator(
    _ indicator: WorkbenchConnectionIndicator,
    isActive: Bool
  ) -> some View {
    HStack(spacing: 5) {
      ZStack {
        Circle()
          .fill(isActive ? Color.green : Color.red)
          .frame(width: 22, height: 22)
        Image(systemName: indicator.systemImage)
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(.white)
      }
      Text(indicator.label(isActive: isActive))
        .font(.caption2.monospaced().bold())
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 4)
    .background(.black.opacity(0.18), in: Capsule())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(indicator.label(isActive: isActive))
  }
}
