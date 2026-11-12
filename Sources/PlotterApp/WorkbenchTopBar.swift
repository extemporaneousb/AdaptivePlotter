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
    title = isAuthorized ? "Disable Motion" : "Enable Motion & Raise Pen"
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

struct WorkbenchSavedLearningPresentation: Equatable {
  let unavailableReason: String?
  var isAvailable: Bool { unavailableReason == nil }

  init(action: PlotterUIAction?, environment: OperatorFrameMode,
    controllerIsSelected: Bool, sessionEstablished: Bool, motionAuthorized: Bool) {
    if action == nil { unavailableReason = "No Saved Learning package is available." }
    else if environment != .live { unavailableReason = "Select LIVE video and connect the plotter to use Saved Learning from the toolbar." }
    else if !controllerIsSelected { unavailableReason = "Select a controller, then Connect before using Saved Learning." }
    else if !sessionEstablished { unavailableReason = "Connect the selected controller before using Saved Learning." }
    else if !motionAuthorized { unavailableReason = "Enable Motion & Raise Pen before using Saved Learning." }
    else { unavailableReason = action?.unavailableReason }
  }
}

/// Session actions and global Stop stay visible independently of control panes.
struct WorkbenchToolbar: ToolbarContent {
  let savedLearningAction: PlotterUIAction?
  let controllerSession: PlotterControllerSessionProjection
  let plotterUIProjection: PlotterUIProjection
  let plotterUIIntentSink: any PlotterUIIntentSink
  let diagnosticsAreExporting: Bool
  let exportDiagnostics: () -> Void

  var body: some ToolbarContent {
    ToolbarItem(id: "workbench.controllerSession", placement: .navigation) {
      let session = controllerSession
      let controllerSlot = WorkbenchControllerSlotPresentation(mode: session.environment)
      let connectionAction = WorkbenchConnectionActionPresentation(
        action: session.connectionAction
      )
      let motionAction = WorkbenchMotionAuthorizationActionPresentation(
        isAuthorized: session.motionAuthorized
      )
      HStack(spacing: 4) {
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
          .frame(width: 120)
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

        Button {
          WorkbenchRequestTelemetry.nativeActionHandled("workbench.controller.motion")
          submit(PlotterAppUIActionID.controllerMotion)
        } label: {
          Text(motionAction.title).fixedSize()
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
          Image(systemName: "exclamationmark.circle.fill")
            .foregroundStyle(.orange)
            .accessibilityLabel("Motion unavailable")
            .accessibilityValue(unavailable.text)
            .help(unavailable.text)
        }
      }
      .controlSize(.small)
      .font(.caption)
    }

    ToolbarItem(id: "workbench.savedLearning", placement: .navigation) {
      savedLearningControl
    }
    ToolbarItem(id: "workbench.diagnostics", placement: .navigation) {
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
    ToolbarItem(id: "workbench.stop", placement: .primaryAction) {
      WorkbenchStopControls(projection: plotterUIProjection, sink: plotterUIIntentSink)
        .labelStyle(.titleAndIcon)
        .controlSize(.regular)
        .fixedSize()
    }
  }

  @ViewBuilder private var savedLearningControl: some View {
    let saved = WorkbenchSavedLearningPresentation(action: savedLearningAction,
      environment: controllerSession.environment,
      controllerIsSelected: controllerSession.selectedSerialDevice != nil,
      sessionEstablished: controllerSession.sessionEstablished,
      motionAuthorized: controllerSession.motionAuthorized)
    Button {
      guard let savedLearningAction else { return }
      WorkbenchRequestTelemetry.nativeActionHandled("workbench.savedLearning")
      submit(savedLearningAction.id)
    } label: {
      VStack(spacing: 2) {
        Image(systemName: "arrow.clockwise.circle")
        Text("Use Saved Learning").font(.caption).multilineTextAlignment(.center)
      }.frame(width: 76).fixedSize(horizontal: false, vertical: true)
    }
    .buttonStyle(.borderless)
    .disabled(!saved.isAvailable)
    .accessibilityIdentifier("workbench.savedLearning")
    .help(saved.unavailableReason ?? "Restore compatible accepted Learning without motion")
  }

  private func submit(_ actionID: PlotterUIActionID) {
    Task {
      _ = await plotterUIIntentSink.submitProjectedAction(actionID, in: plotterUIProjection)
    }
  }
}

/// Persistent flat application navigation keeps all ordinary view routes visible
/// while the native title-bar toolbar reserves space for session actions and Stop.
