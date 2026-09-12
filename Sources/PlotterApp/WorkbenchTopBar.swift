import PlotterRuntime
import PlotterUI
import SwiftUI

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

  init(isAuthorized: Bool) {
    title = isAuthorized ? "Disable Motion" : "Enable Motion"
  }
}

struct WorkbenchMotionUnavailablePresentation: Equatable, Sendable {
  let text: String

  init?(_ reason: String?) {
    guard let reason, !reason.isEmpty else { return nil }
    text = reason
  }
}

struct WorkbenchConnectionActionPresentation: Equatable, Sendable {
  let title: String

  init(action: PlotterControllerConnectionAction) {
    title = action.title
  }
}

/// Session actions and global Stop stay visible independently of control panes.
struct WorkbenchToolbar: ToolbarContent {
  let controllerSession: PlotterControllerSessionProjection
  let plotterUIProjection: PlotterUIProjection
  let plotterUIIntentSink: any PlotterUIIntentSink
  let diagnosticsAreExporting: Bool
  let exportDiagnostics: () -> Void

  var body: some ToolbarContent {
    ToolbarItem(placement: .navigation) {
      let session = controllerSession
      let controllerSlot = WorkbenchControllerSlotPresentation(mode: session.environment)
      let connectionAction = WorkbenchConnectionActionPresentation(
        action: session.connectionAction
      )
      let motionAction = WorkbenchMotionAuthorizationActionPresentation(
        isAuthorized: session.motionAuthorized
      )
      HStack(spacing: 10) {
        if !controllerSlot.isSerialSelectionEnabled {
          Label(controllerSlot.title, systemImage: "cpu")
            .labelStyle(.titleAndIcon)
            .fixedSize()
            .foregroundStyle(.secondary)
            .help("SIMULATED uses the isolated learning simulator, not a serial controller")
        } else {
          Picker(
            "Controller",
            selection: Binding(
              get: { session.selectedSerialDevice },
              set: { device in
                guard let device else { return }
                submit(PlotterAppUIActionID.controllerDevice(device.identifier))
              }
            )
          ) {
            Text("Select Controller").tag(nil as MachineLinkDescriptor?)
            ForEach(session.serialDevices, id: \.identifier) { device in
              Text(device.displayName).tag(Optional(device))
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(width: 180)
          .disabled(session.selectionUnavailableReason != nil)
          .help(session.selectionUnavailableReason ?? "Select one available controller")
        }

        Button(connectionAction.title) {
          WorkbenchRequestTelemetry.nativeActionHandled("workbench.controller.connect")
          submit(PlotterAppUIActionID.controllerConnection)
        }
        .accessibilityIdentifier("workbench.controller.connect")
        .buttonStyle(.borderedProminent).tint(.orange)
        .disabled(session.connectionUnavailableReason != nil)
        .help(
          session.connectionUnavailableReason
            ?? "\(connectionAction.title) the selected controller"
        )

        Button(motionAction.title) {
          WorkbenchRequestTelemetry.nativeActionHandled("workbench.controller.motion")
          submit(PlotterAppUIActionID.controllerMotion)
        }
        .accessibilityIdentifier("workbench.controller.motion")
        .buttonStyle(.borderedProminent).tint(.orange)
        .disabled(session.motionAuthorizationUnavailableReason != nil)
        .help(
          session.motionAuthorizationUnavailableReason
            ?? "\(motionAction.title) for this controller session"
        )
        if let unavailable = WorkbenchMotionUnavailablePresentation(
          session.motionAuthorizationUnavailableReason
        ) {
          HStack(spacing: 4) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(unavailable.text)
              .lineLimit(2)
              .fixedSize(horizontal: false, vertical: true)
          }
          .font(.caption)
          .foregroundStyle(.orange)
          .frame(maxWidth: 280, alignment: .leading)
          .accessibilityElement(children: .combine)
          .accessibilityLabel("Motion unavailable")
          .accessibilityValue(unavailable.text)
          .help(unavailable.text)
        }
      }
    }

    ToolbarItem(placement: .automatic) {
      Button(action: exportDiagnostics) {
        if diagnosticsAreExporting { ProgressView().controlSize(.small) }
        else { Image(systemName: "wrench.and.screwdriver") }
      }
      .disabled(diagnosticsAreExporting)
      .accessibilityLabel("Export Diagnostics")
      .accessibilityIdentifier("workbench.diagnostics")
      .help("Write diagnostics to a file in the background")
      .keyboardShortcut("d", modifiers: [.command, .shift])
    }
    ToolbarItem(placement: .primaryAction) {
      WorkbenchStopControls(projection: plotterUIProjection, sink: plotterUIIntentSink)
        .controlSize(.large)
        .fixedSize()
    }
  }

  private func submit(_ actionID: PlotterUIActionID) {
    Task {
      _ = await plotterUIIntentSink.submitProjectedAction(actionID, in: plotterUIProjection)
    }
  }
}
