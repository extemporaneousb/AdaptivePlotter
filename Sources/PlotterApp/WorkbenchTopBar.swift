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

enum WorkbenchTopBarStatusFact: String, CaseIterable {
  case source
  case camera
  case frame
  case link
  case motor
  case motion
  case operation
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

        fact(.source, workspace.frameMode.rawValue)
        fact(.camera, workspace.cameraStateText)
        fact(.frame, workspace.frameAgeText)
        fact(.link, workspace.controllerConnectionText)
        fact(.motor, workspace.motorPowerText)
        fact(.motion, workspace.motionPermissionText)
        fact(.operation, workspace.currentOperationText)
      }

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
    .padding(.horizontal, WorkbenchTopBarLayoutMetrics.horizontalContentPadding)
    .padding(.vertical, WorkbenchTopBarLayoutMetrics.verticalContentPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.ultraThinMaterial)
    .overlay(alignment: .bottom) {
      Divider()
    }
  }

  private func fact(_ name: WorkbenchTopBarStatusFact, _ value: String) -> some View {
    HStack(spacing: 3) {
      Text(name.rawValue.uppercased())
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.caption2.monospaced())
        .textSelection(.enabled)
    }
  }
}
