import DrawingLibrary
import PortraitCore
import PortraitLibrary
import PortraitStudioUI
import AppKit
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import PlotterUI
import SwiftUI

@MainActor
struct PlotterEpisodeComposition {
  let application: PlotterApplicationRuntime
  var ownedDrawingLibrary: DrawingLibrary? = nil

  static func production() -> Self {
    let manualMotionComposition = PlotterManualMotionComposition.production
    let penInteractionRuntime = PlotterPenInteractionComposition.makeRuntime(
      machineSession: MachineSessionComposition.session,
      simulatedAdapter: manualMotionComposition.causalSimulatorEffectAdapter
    )
    let boundaryComposition = PlotterBoundaryComposition.make(
      machineSession: MachineSessionComposition.session,
      causalSimulator: manualMotionComposition.causalSimulatorEffectAdapter,
      statePersistencePort: AcceptedArtifactCheckpointComposition.statePersistencePort,
      speechEffectRuntime: SpeechComposition.runtime
    )
    let drawingRunComposition = PlotterDrawingRunComposition.make(
      machineSession: MachineSessionComposition.session,
      observationSession: CameraComposition.observationSession
    )
    let artifactResetComposition = PlotterArtifactResetComposition.make()
    let library = DrawingLibrary(directoryURL: FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/AdaptivePlotter/DrawingLibrary", isDirectory: true),
      payloadValidators: DrawingDestinationResult.payloadValidators)
    let application = PlotterApplicationRuntime(
      machineSession: MachineSessionComposition.session,
      observationSession: CameraComposition.observationSession,
      observationRecordingStore: CameraComposition.recordingStore,
      receivedDrawings: ReceivedDrawingStore(library: library, selectionDefaults: .standard),
      drawingMaterials: DrawingMaterialLibrary(store: DrawingMaterialStore.defaultStore()),
      pointSelectionRuntime: PointSelectionComposition.production.runtime,
      pointSelectionRecordingDiagnostic:
        PointSelectionComposition.production.recordingDiagnostic,
      capPointSelectionComposition: { PointSelectionComposition.makeRuntime() },
      manualMotionComposition: manualMotionComposition,
      penInteractionRuntime: penInteractionRuntime,
      boundaryRuntime: boundaryComposition.runtime,
      speechEffectRuntime: SpeechComposition.runtime,
      statePersistencePort: AcceptedArtifactCheckpointComposition.statePersistencePort,
      artifactResetRuntime: artifactResetComposition.runtime,
      drawingDraftRuntime: PaperCoverageComposition.drawingDraftRuntime,
      drawingRunComposition: drawingRunComposition,
      incidentPackageUIService: PlotterIncidentPackageUIService(
        sourceProvider: PlotterIncidentPackageUIUnavailableSourceProvider()
      ),
      tipCalibrationSemanticIdentities: TipCalibrationSemanticIdentityComposition.state,
      residualEffectPort: MachineSessionComposition.residualEffectPort
    )
    boundaryComposition.install(on: application)
    artifactResetComposition.install(on: application)
    return Self(application: application, ownedDrawingLibrary: library)
  }
}

@MainActor
final class AdaptivePlotterApplicationDelegate: NSObject, NSApplicationDelegate {
  let composition: PlotterEpisodeComposition
  var applicationRuntime: PlotterApplicationRuntime { composition.application }
  private let destinationRoot: URL
  private lazy var destinationFileServer = DrawingDestinationFileServer(service: applicationRuntime.drawingDestination,
    library: applicationRuntime.receivedDrawings.sketches.library, root: destinationRoot)
  private struct PreparationReplyKey: Hashable { let client: UUID; let delivery: UUID }
  private var observedPreparationReplies: Set<PreparationReplyKey> = []
  private var revealPreparedDrawing: DrawingDestinationReveal?
  private var pendingDrawingPreparation: DrawingDestinationReply?
  private var destinationViewRestorationCompleted = false
  private(set) var drawingDestinationRecoveryScanCount = 0
  private var destinationRecoveryTask: Task<Void, Never>?
  private var documentTasks: [Task<Void, Never>] = []
  private var terminationTask: Task<Void, Never>?
  private var didReplyToTermination = false
  var restoreOperatorWindow: (() -> Void)?
  /// AppKit response adapter; termination ownership remains terminationTask.
  var replyToTermination: @MainActor (NSApplication, Bool) -> Void = {
    $0.reply(toApplicationShouldTerminate: $1)
  }
  var drawingPresentationAdmissionIsOpen: Bool {
    terminationTask == nil && applicationRuntime.drawingDestinationRecoveryAdmissionIsOpen
  }

  override init() {
    destinationRoot = DrawingDestinationFiles.defaultRoot
    composition = .production()
    super.init()
  }

  init(composition: PlotterEpisodeComposition, destinationRoot: URL = DrawingDestinationFiles.defaultRoot) {
    self.destinationRoot = destinationRoot
    self.composition = composition
    super.init()
  }

  func application(_ sender: NSApplication, open urls: [URL]) {
    guard terminationTask == nil else { return }
    documentTasks.append(Task {
      guard await waitForDrawingDestinationStartup() else { return }
      for url in urls {
        do {
          if url.pathExtension.lowercased() == "drawingrequest" {
            let delivery = try DrawingDestinationFiles.read(DrawingDestinationDelivery.self, from: url)
            guard case .prepare = delivery.request else { throw DrawingDestinationRefusal.invalidDelivery }
            let responseURL = try await destinationFileServer.receive(url)
            let response = try DrawingDestinationFiles.read(DrawingDestinationResponse.self, from: responseURL)
            observedPreparationReplies.insert(.init(client: response.client, delivery: response.delivery))
            showDrawingPreparation(response.reply, foreground: true)
          } else {
            let refs = try await applicationRuntime.receivedDrawings.sketches.importDrawings(from: url)
            guard let ref = refs.first else { throw DrawingDestinationRefusal.preparationUnavailable }
            showDrawingPreparation(try await applicationRuntime.drawingDestination.handle(.prepare(ref)), foreground: true)
          }
        } catch {
          if drawingPresentationAdmissionIsOpen {
            applicationRuntime.drawingDestinationStatus = "Drawing could not be opened: " + error.localizedDescription
          }
        }
      }
    })
  }

  func completeDrawingDestinationRestoration(_ reveal: @escaping DrawingDestinationReveal) {
    revealPreparedDrawing = reveal
    destinationViewRestorationCompleted = true
  }
  private func showDrawingPreparation(_ reply: DrawingDestinationReply, foreground: Bool) {
    guard drawingPresentationAdmissionIsOpen else {
      // A failed quit may reopen this same window. Keep only its presentation
      // value; the Library and destination still own all durable preparation.
      if terminationTask != nil { pendingDrawingPreparation = reply }
      return
    }
    switch reply {
    case .prepared(let ticket):
      if revealPreparedDrawing?(.prepared(ticket)) == true {
        applicationRuntime.drawingDestinationStatus = "Drawing prepared in the preview. Review it before choosing Draw."
      } else {
        applicationRuntime.drawingDestinationStatus = "Drawing preparation has changed. Prepare it again to review the current preview."
      }
    case .referencePreview(let ref):
      if revealPreparedDrawing?(.unplaced(ref)) == true {
        applicationRuntime.drawingDestinationStatus = applicationRuntime.drawingDraftSnapshot.planningRefusal?.remedy
      } else {
        applicationRuntime.drawingDestinationStatus = "The drawing selection changed. Open it again to review it."
      }
    case .refused:
      applicationRuntime.drawingDestinationStatus = "The drawing could not be prepared. Review the destination preview and readiness."
    default:
      applicationRuntime.drawingDestinationStatus = "The drawing preparation response is unavailable."
    }
    if foreground { restoreOperatorWindow?() }
  }

  private func waitForDrawingDestinationStartup() async -> Bool {
    while !applicationRuntime.drawingDestinationStartupHasSettled || !destinationViewRestorationCompleted {
      guard applicationRuntime.drawingDestinationRecoveryAdmissionIsOpen, !Task.isCancelled else { return false }
      do { try await Task.sleep(for: .milliseconds(25)) } catch { return false }
    }
    return applicationRuntime.drawingDestinationRecoveryAdmissionIsOpen && !Task.isCancelled
  }
  func startDrawingDestinationRecovery() {
    guard terminationTask == nil, destinationRecoveryTask == nil else { return }
    destinationRecoveryTask = Task { [weak self] in
      guard let self, await self.waitForDrawingDestinationStartup() else { return }
      while !Task.isCancelled {
        guard self.applicationRuntime.drawingDestinationRecoveryAdmissionIsOpen else { return }
        let recovery = await self.destinationFileServer.drainPreparations()
        self.drawingDestinationRecoveryScanCount += 1
        // Drain durable work even while a quit attempt is pending, but do not
        // consume its presentation receipt. A canceled quit can still reveal it.
        if self.drawingPresentationAdmissionIsOpen {
          for response in recovery.responses {
            guard self.observedPreparationReplies.insert(.init(client: response.client, delivery: response.delivery)).inserted else { continue }
            self.showDrawingPreparation(response.reply, foreground: false)
          }
          if let failure = recovery.failures.first {
            self.applicationRuntime.drawingDestinationStatus = "Drawing preparation recovery failed: " + failure
          }
        }
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
      }
    }
  }
  func cancelDrawingDestinationRecovery() { destinationRecoveryTask?.cancel() }
  func settleDrawingDestinationRecovery() async {
    destinationRecoveryTask?.cancel()
    await destinationRecoveryTask?.value
    destinationRecoveryTask = nil
  }

  func settleDrawingDocuments() async {
    let admitted = documentTasks
    for task in admitted { await task.value }
  }

  func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool {
    false
  }

  func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool {
    false
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if terminationTask != nil { return .terminateLater }
    didReplyToTermination = false
    terminationTask = Task { [weak self] in
      guard let self else { return }
      self.cancelDrawingDestinationRecovery()
      self.destinationFileServer.closeAdmission()
      await self.applicationRuntime.shutdown()
      await self.settleDrawingDestinationRecovery()
      await self.destinationFileServer.close()
      for task in self.documentTasks { await task.value }
      self.documentTasks = []
      await self.composition.ownedDrawingLibrary?.closeLibrary()
      self.completeTermination(of: sender)
    }
    return .terminateLater
  }

  private func completeTermination(of application: NSApplication) {
    guard !didReplyToTermination else { return }
    didReplyToTermination = true
    terminationTask?.cancel()
    terminationTask = nil
    replyToTermination(application, true)
  }
}

struct PointSelectionRuntimeComposition: Sendable {
  let runtime: PlotterPointSelectionRuntime
  let recordingDiagnostic: String?
}

enum PointSelectionComposition {
  static let production = makeRuntime()

  static func makeRuntime(
    applicationSupportDirectory: () throws -> URL = {
      AdaptivePlotterStoragePaths.production.rootDirectory.deletingLastPathComponent()
    }
  ) -> PointSelectionRuntimeComposition {
    let recordingID = EpisodeRecordingID(rawValue: UUID())
    let manager = FileManager.default
    do {
      let paths = AdaptivePlotterStoragePaths(applicationSupportDirectory: try applicationSupportDirectory())
      let directory = paths.episodeRecordingDirectory(recordingID.rawValue)
      try manager.createDirectory(at: directory, withIntermediateDirectories: true)
      let recordingStore = try EpisodeRecordingStore.open(
        directoryURL: directory,
        recordingID: recordingID,
        schemaRevision: EpisodeRecordingSchemaRevision(
          rawValue: "adaptive-plotter-point-selection-v1"
        ),
        frameRetentionPolicy: EpisodeFrameRetentionPolicy(
          maximumUniqueFrameCount: 64,
          maximumTotalUniqueFrameBytes: 512 * 1_024 * 1_024
        )
      )
      return PointSelectionRuntimeComposition(
        runtime: PlotterPointSelectionRuntime(recordingStore: recordingStore),
        recordingDiagnostic: nil
      )
    } catch {
      let diagnostic =
        "Point-selection recording is unavailable: \(error.localizedDescription)"
      return PointSelectionRuntimeComposition(
        runtime: PlotterPointSelectionRuntime(
          recordingUnavailableDiagnostic: diagnostic
        ),
        recordingDiagnostic: diagnostic
      )
    }
  }
}

@main
@MainActor
struct AdaptivePlotterApp: App {
  @NSApplicationDelegateAdaptor(AdaptivePlotterApplicationDelegate.self)
  private var applicationDelegate

  init() {
    UserDefaults.standard.set(true, forKey: "ApplePersistenceIgnoreState")
    UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
  }

  var body: some Scene {
    Window("AdaptivePlotter", id: AdaptivePlotterScenePolicy.singletonWindowID) {
      AdaptivePlotterOperatorWindow(delegate: applicationDelegate)
    }
    .windowToolbarStyle(.unified)
    .commands { WorkbenchCommands() }
  }
}

private struct AdaptivePlotterOperatorWindow: View {
  @Environment(\.openWindow) private var openWindow
  let delegate: AdaptivePlotterApplicationDelegate
  var body: some View {
    PlotterApplicationRuntimeView(application: delegate.applicationRuntime,
      drawingDestinationRestorationCompleted: delegate.completeDrawingDestinationRestoration)
      .safeAreaInset(edge: .bottom) {
        if let status = delegate.applicationRuntime.drawingDestinationStatus {
          Text(status).font(.caption).foregroundStyle(.secondary).padding(6)
        }
      }
      .frame(minWidth: LearningWorkbenchLayoutPolicy.minimumWindowWidth,
        minHeight: AdaptivePlotterScenePolicy.minimumWindowHeight)
      .onAppear {
        delegate.startDrawingDestinationRecovery()
        delegate.restoreOperatorWindow = {
          openWindow(id: AdaptivePlotterScenePolicy.singletonWindowID)
          NSApp.activate(ignoringOtherApps: true)
        }
      }
  }
}

enum AdaptivePlotterScenePolicy {
  static let singletonWindowID = "operator-application"
  static let minimumWindowHeight: CGFloat = 700
}

enum AdaptivePlotterStartupRoute: Equatable, Sendable {
  case preferredCamera
  case simulated
}

struct AdaptivePlotterLaunchPolicy: Equatable, Sendable {
  static let simulatedArgument = "-AdaptivePlotterStartSimulated"
  let startupRoute: AdaptivePlotterStartupRoute

  init(arguments: [String]) {
    startupRoute =
      arguments.indices.contains { index in
        arguments[index] == Self.simulatedArgument
          && arguments.indices.contains(index + 1)
          && arguments[index + 1].caseInsensitiveCompare("YES") == .orderedSame
      } ? .simulated : .preferredCamera
  }

  static var current: Self {
    Self(arguments: CommandLine.arguments)
  }
}

private enum SpeechComposition {
  static let runtime = PlotterSpeechEffectRuntime(announcer: NativeSpeechAnnouncer(), outputEnabled: false)
}

@MainActor
struct MotionPanel: View {
  @Binding var draft: ManualMotionDraft
  let presentation: ManualMotionPresentation
  let controllerSession: PlotterControllerSessionProjection
  let motionSnapshotReader: MotionReadoutModel.SnapshotReader
  let learningIsEnabled: Bool
  let plotterUIProjection: PlotterUIProjection
  let plotterUIIntentSink: any PlotterUIIntentSink
  var body: some View {
    let session = controllerSession
    let primaryUnavailableReason = presentation.attentionReason
      ?? presentation.jogControlsUnavailableReason
      ?? presentation.penUpUnavailableReason
      ?? presentation.penDownUnavailableReason
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        numericField(
          ManualMotionPresentation.xDistanceLabel,
          text: $draft.xDistanceMM, identifier: "motion.xDistance"
        )
        numericField(
          ManualMotionPresentation.yDistanceLabel,
          text: $draft.yDistanceMM, identifier: "motion.yDistance"
        )
        numericField(
          ManualMotionPresentation.feedLabel,
          text: $draft.feedMMPerMinute, identifier: "motion.feed"
        )
      }

      VStack(spacing: 5) {
        jogButton("Y+", systemImage: "arrow.up", direction: .yPositive)
        HStack(spacing: 5) {
          jogButton("X−", systemImage: "arrow.left", direction: .xNegative)
          jogButton("X+", systemImage: "arrow.right", direction: .xPositive)
        }
        jogButton("Y−", systemImage: "arrow.down", direction: .yNegative)
      }
      .frame(maxWidth: .infinity)

      if let stop = presentation.stopAction {
        Button {
          submit(PlotterAppUIActionID.manualStop)
        } label: {
          Label(stop.title, systemImage: "stop.fill")
            .frame(maxWidth: .infinity)
        }
        .operatorButton(.stop)
        .keyboardShortcut(.cancelAction)
        .help(stop.detail)
        .accessibilityHint(stop.detail)
      }

      if let recovery = presentation.publicationRecovery {
        VStack(alignment: .leading, spacing: 5) {
          Text(recovery.remedy)
            .font(.caption)
            .foregroundStyle(.orange)
          Button {
            submit(PlotterAppUIActionID.manualRecovery)
          } label: {
            Label(recovery.title, systemImage: "arrow.clockwise.circle.fill")
              .frame(maxWidth: .infinity)
          }
          .operatorButton(.affirmative)
          .help(recovery.remedy)
          .accessibilityHint(recovery.remedy)
        }
      }

      if let evidence = presentation.evidenceDisposition {
        VStack(alignment: .leading, spacing: 5) {
          Text(evidence.remedy)
            .font(.caption)
            .foregroundStyle(.orange)
          Button {
            submit(PlotterAppUIActionID.manualEvidence)
          } label: {
            Label(evidence.title, systemImage: "checkmark.shield.fill")
              .frame(maxWidth: .infinity)
          }
          .operatorButton(.affirmative)
          .help(evidence.remedy)
          .accessibilityHint(evidence.remedy)
        }
      }

      HStack(alignment: .top, spacing: 6) {
        OperatorRequestButton(
          title: "Pen Up", request: plotterUIProjection.request(for: PlotterAppUIActionID.manualPenUp),
          unavailableReason: presentation.penUpUnavailableReason, sink: plotterUIIntentSink,
          nativeActionIdentifier: "motion.penUp",
          showsUnavailableReason: presentation.penUpUnavailableReason != primaryUnavailableReason)
          .accessibilityIdentifier("motion.penUp")
        OperatorRequestButton(
          title: "Pen Down", request: plotterUIProjection.request(for: PlotterAppUIActionID.manualPenDown),
          unavailableReason: presentation.penDownUnavailableReason, sink: plotterUIIntentSink,
          showsUnavailableReason: presentation.penDownUnavailableReason != primaryUnavailableReason
            && presentation.penDownUnavailableReason != presentation.penUpUnavailableReason)
          .accessibilityIdentifier("motion.penDown")
      }

      if session.environment == .live {
        MotionReadout(reader: motionSnapshotReader)
      } else {
        Text(presentation.penStateText)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        fact("Controller link", session.controllerConnectionText)
        fact("Controller", session.controllerStateText)
        fact("MPos", session.machinePositionText)
        fact("Limit inputs", session.controllerLimitInputsText)
      }
      if let alert = presentation.controllerAlertText(session.controllerAttentionText) {
        fact("Controller alert", alert)
      }
      fact("Alarm unlock", session.controllerAlarmUnlockReadinessText)
      if let alarm = session.controllerAlarmEvidenceText {
        VStack(alignment: .leading, spacing: 5) {
          Text("Reported alarm: \(alarm)")
            .font(.caption.monospaced())
            .foregroundStyle(.orange)
            .textSelection(.enabled)
          Button {
            submit(PlotterAppUIActionID.controllerClearAlarm)
          } label: {
            Label(
              session.alarmClearInProgress ? "Clearing Alarm…" : "Clear Alarm",
              systemImage: "exclamationmark.triangle.fill"
            )
          }
          .operatorButton(
            .negative,
            isEnabled: session.alarmClearUnavailableReason == nil
          )
          .help(
            session.alarmClearUnavailableReason
              ?? "Send one explicit alarm-unlock request, then run a fresh passive controller probe"
          )
        }
      }
      fact("Motor power", session.motorPowerText)
      fact("Motion", session.motionAuthorized ? "enabled" : "disabled")
      fact("Motion request", presentation.jogControlsUnavailableReason == nil ? "request eligible" : "unavailable")
      fact("Manual mode", presentation.modeText)
      fact("Learning", learningIsEnabled ? "on" : "off — manual operation")
      fact("Operation", session.currentOperationText)
      fact("Previous outcome", session.lastMotionOutcomeText)
      fact("Previous pen outcome", session.lastPenOutcomeText)

      if let reason = primaryUnavailableReason, reason != presentation.attentionReason {
        Text(reason)
          .font(.caption)
          .foregroundStyle(.orange)
      }

    }
    .help("Manual relative motion controls")
  }

  private func jogButton(
    _ label: String,
    systemImage: String,
    direction: JogDirection
  ) -> some View {
    Button {
      WorkbenchRequestTelemetry.nativeActionHandled(actionID(for: direction).rawValue)
      submit(actionID(for: direction))
    } label: {
      Label(label, systemImage: systemImage)
        .frame(minWidth: 64, minHeight: 24)
    }
    .operatorButton(
      isEnabled: presentation.jogControlsUnavailableReason == nil
    )
    .help(jogAccessibilityLabel(direction))
    .accessibilityLabel(jogAccessibilityLabel(direction))
    .accessibilityIdentifier(actionID(for: direction).rawValue)
  }

  private func submit(_ actionID: PlotterUIActionID) {
    Task {
      _ = await plotterUIIntentSink.submitProjectedAction(actionID, in: plotterUIProjection)
    }
  }

  private func actionID(for direction: JogDirection) -> PlotterUIActionID {
    switch direction {
    case .xNegative: PlotterAppUIActionID.manualXNegative
    case .xPositive: PlotterAppUIActionID.manualXPositive
    case .yNegative: PlotterAppUIActionID.manualYNegative
    case .yPositive: PlotterAppUIActionID.manualYPositive
    }
  }

  private func jogAccessibilityLabel(_ direction: JogDirection) -> String {
    switch direction {
    case .xNegative: "Jog X negative"
    case .xPositive: "Jog X positive"
    case .yNegative: "Jog Y negative"
    case .yPositive: "Jog Y positive"
    }
  }

  private func numericField(_ label: String, text: Binding<String>, identifier: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label).font(.caption2).foregroundStyle(.secondary)
      TextField(label, text: Binding(get: { text.wrappedValue }, set: {
        WorkbenchRequestTelemetry.nativeActionHandled(identifier)
        text.wrappedValue = $0
      }))
        .accessibilityIdentifier(identifier)
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
