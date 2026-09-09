import PlotterRuntime
import PlotterUI
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

struct WorkbenchMotionUnavailablePresentation: Equatable, Sendable {
  let text: String

  init?(_ reason: String?) {
    guard let reason, !reason.isEmpty else { return nil }
    text = reason
  }
}

struct WorkbenchConnectionActionPresentation: Equatable, Sendable {
  let title: String
  let role: OperatorButtonRole

  init(action: PlotterControllerConnectionAction) {
    title = action.title
    role = action == .disconnect ? .negative : .affirmative
  }
}

/// Native macOS window-toolbar controls for the camera-first workbench.
///
/// Only controller/session controls and compact truthful status live here.
/// Exercise Stop and utility-panel launchers belong to the workbench content.
struct WorkbenchToolbar: ToolbarContent {
  let controllerSession: PlotterControllerSessionProjection
  let application: PlotterApplicationRuntime
  let motionRequestStatus: MotionRequestStatusPresentation
  let plotterUIProjection: PlotterUIProjection
  let plotterUIIntentSink: any PlotterUIIntentSink
  let capabilityPresentation: WorkbenchCapabilityPresentation?

  init(
    controllerSession: PlotterControllerSessionProjection,
    application: PlotterApplicationRuntime,
    motionRequestStatus: MotionRequestStatusPresentation,
    plotterUIProjection: PlotterUIProjection,
    plotterUIIntentSink: any PlotterUIIntentSink,
    capabilityPresentation: WorkbenchCapabilityPresentation? = nil
  ) {
    self.controllerSession = controllerSession
    self.application = application
    self.motionRequestStatus = motionRequestStatus
    self.plotterUIProjection = plotterUIProjection
    self.plotterUIIntentSink = plotterUIIntentSink
    self.capabilityPresentation = capabilityPresentation
  }

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
      HStack(spacing: 8) {
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
        .operatorButton(
          connectionAction.role,
          isEnabled: session.connectionUnavailableReason == nil
        )
        .help(
          session.connectionUnavailableReason
            ?? "\(connectionAction.title) the selected controller"
        )

        Button(motionAction.title) {
          WorkbenchRequestTelemetry.nativeActionHandled("workbench.controller.motion")
          submit(PlotterAppUIActionID.controllerMotion)
        }
        .accessibilityIdentifier("workbench.controller.motion")
        .operatorButton(
          motionAction.role,
          isEnabled: session.motionAuthorizationUnavailableReason == nil
        )
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

    ToolbarItem(placement: .primaryAction) {
      let session = controllerSession
      HStack(spacing: 12) {
        WorkbenchCameraStatus(application: application)
        WorkbenchStatusIndicator(
          indicator: .plotter,
          label: WorkbenchConnectionIndicator.plotter.label(
            isActive: session.sessionEstablished
          ),
          color: session.sessionEstablished ? .green : .red
        )
        WorkbenchStatusIndicator(
          indicator: .motionGuard,
          label: WorkbenchConnectionIndicator.motionGuard.label(
            isActive: session.motionAuthorized
          ),
          color: session.motionAuthorized ? .green : .red
        )
        MotionRequestStatusView(presentation: motionRequestStatus)
        if let capabilityPresentation {
          Divider().frame(height: 20)
          WorkbenchCapabilityIndicator(presentation: capabilityPresentation)
        }
      }
    }
  }

  private func submit(_ actionID: PlotterUIActionID) {
    Task {
      _ = await plotterUIIntentSink.submitProjectedAction(actionID, in: plotterUIProjection)
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

/// Time-based camera health is read in this small view. Its clock must not
/// publish semantic revisions or invalidate Learning and Drawing Studio.
private struct WorkbenchCameraStatus: View {
  let application: PlotterApplicationRuntime

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
      let portrait = application.workbenchCameraRole == .portrait
      let simulated = !portrait && application.frameMode == .simulated
      let live = portrait ? application.portraitStudio.cameraIsRunning : application.cameraIsLive
      let switching = application.cameraRoleIsTransitioning
      let delayed = !portrait && !simulated && !switching
        && application.cameraSnapshot?.state == .running && !live
      let error = application.cameraRoleError
        ?? (portrait ? application.portraitStudio.cameraStatus : application.cameraError)
      let label = switching ? "Switching camera"
        : portrait ? (live ? "Portrait Camera Live" : "Portrait Camera Off")
        : simulated ? "Simulator" : delayed ? "Plotter camera delayed"
        : WorkbenchConnectionIndicator.camera.label(isActive: live)
      WorkbenchStatusIndicator(
        indicator: .camera,
        label: label,
        color: switching ? .gray : simulated ? .blue : live ? .green : error != nil || delayed ? .red : .gray
      )
      .help(error ?? (delayed ? "No plotter preview frame received within one second." : label))
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
    }
    .fixedSize()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .help(label)
  }
}
