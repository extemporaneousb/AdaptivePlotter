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

/// Toolbar destinations describe visible surfaces, not retained dock membership.
enum WorkbenchToolbarDestination: String, CaseIterable, Identifiable {
  case plotter, portraitStudio, drawings, drawing, motion, video

  var id: String { rawValue }
  var title: String {
    switch self {
    case .plotter: "Plotter"
    case .portraitStudio: "Portrait Studio"
    case .drawings: "Drawings"
    case .drawing: "Drawing"
    case .motion: "Motion"
    case .video: "Video"
    }
  }
  var systemImage: String {
    switch self {
    case .plotter: "video"
    case .portraitStudio: "person.crop.rectangle"
    case .drawings: "square.grid.2x2"
    case .drawing: WorkbenchPanel.drawing.systemImage
    case .motion: WorkbenchPanel.motion.systemImage
    case .video: WorkbenchPanel.videoSettings.systemImage
    }
  }
  var panel: WorkbenchPanel? {
    switch self {
    case .portraitStudio: .portraitStudio
    case .drawing: .drawing
    case .motion: .motion
    case .video: .videoSettings
    case .plotter, .drawings: nil
    }
  }
  func isSelected(layout: WorkbenchLayoutState, reviewerIsPresented: Bool) -> Bool {
    if self == .drawings { return reviewerIsPresented }
    if self == .plotter { return !layout.isPresented(.portraitStudio) }
    guard let panel else { return false }
    return layout.isPresented(panel)
      && (panel == .portraitStudio || !layout.isPresented(.portraitStudio))
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
struct WorkbenchNavigationControls: View {
  let layout: WorkbenchLayoutState
  let reviewerIsPresented: Bool
  let selectDestination: (WorkbenchToolbarDestination) -> Void

  var body: some View {
    HStack(spacing: 12) {
      ForEach(WorkbenchToolbarDestination.allCases) { destination in
        destinationControl(destination)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("workbench.navigation")
  }

  private func destinationControl(_ destination: WorkbenchToolbarDestination) -> some View {
    Toggle(isOn: Binding(
      get: { destination.isSelected(layout: layout, reviewerIsPresented: reviewerIsPresented) },
      set: { _ in selectDestination(destination) }
    )) {
      Label(destination.title, systemImage: destination.systemImage)
        .labelStyle(.titleAndIcon)
        .font(.callout)
        .fontWeight(destination.isSelected(layout: layout,
          reviewerIsPresented: reviewerIsPresented) ? .semibold : .regular)
        .fixedSize()
    }
    .toggleStyle(.button)
    .buttonStyle(.borderless)
    .foregroundStyle(destination.isSelected(layout: layout,
      reviewerIsPresented: reviewerIsPresented) ? Color.accentColor : Color.primary)
    .accessibilityIdentifier("workbench.destination.\(destination.rawValue)")
    .accessibilityValue(destination.isSelected(layout: layout,
      reviewerIsPresented: reviewerIsPresented) ? "Shown" : "Hidden")
    .help(destination.title)
  }

}
