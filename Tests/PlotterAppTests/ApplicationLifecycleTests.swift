import AppKit
import Foundation
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Local application lifecycle")
struct ApplicationLifecycleTests {
  @Test("operator window has a stable restoration identifier")
  func singletonOperatorWindow() {
    #expect(AdaptivePlotterScenePolicy.singletonWindowID == "operator-application")
  }

  @Test("closing the last window terminates the local application")
  @MainActor
  func lastWindowCloseTerminates() async throws {
    let fixture = try isolatedApplicationDelegate()
    let delegate = fixture.delegate
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    await delegate.applicationRuntime.shutdown()
  }

  @Test("saved window state cannot suppress a fresh operator window")
  @MainActor
  func savedApplicationStateIsDisabled() async throws {
    let fixture = try isolatedApplicationDelegate()
    let delegate = fixture.delegate
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    #expect(!delegate.applicationShouldRestoreApplicationState(NSApplication.shared))
    #expect(!delegate.applicationShouldSaveApplicationState(NSApplication.shared))
    await delegate.applicationRuntime.shutdown()
  }

  @Test("application composition injects artifact reset runtime and shutdown closes admission")
  @MainActor
  func applicationOwnsArtifactResetRuntimeLifecycle() async throws {
    let fixture = try isolatedApplicationDelegate()
    let delegate = fixture.delegate
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    #expect(!delegate.applicationRuntime.artifactResetEpisodeSnapshot.admissionClosed)
    await delegate.applicationRuntime.shutdown()
    #expect(delegate.applicationRuntime.artifactResetEpisodeSnapshot.admissionClosed)
  }

  @Test("recording startup failure remains a visible diagnostic-only fallback")
  @MainActor
  func pointSelectionRecordingStartupFailureIsVisible() {
    let composition = PointSelectionComposition.makeRuntime {
      throw ApplicationLifecycleRecordingError.unavailable
    }
    let diagnostic = composition.recordingDiagnostic
    #expect(diagnostic?.contains("Point-selection recording is unavailable") == true)

    let workspace = PlotterApplicationRuntime(
      pointSelectionRuntime: composition.runtime,
      pointSelectionRecordingDiagnostic: diagnostic,
      penInteractionRuntime: nominalPenInteractionRuntime(),
      boundaryRuntime: nominalBoundaryRuntime(),
      drawingDraftRuntime: nominalDrawingDraftRuntime(),
      drawingRunComposition: nominalDrawingRunComposition(),
      incidentPackageUIService: nominalIncidentPackageUIService()
    )
    #expect(workspace.testLearningModePresentation.recordingDiagnostic == diagnostic)
    #expect(workspace.testLearningIsEnabled)
    #expect(workspace.pointSelectionEpisodeProjection.runtimeStateRevision.rawValue == 0)
  }

  @Test("launch policy recognizes only the explicit nonpersistent simulated argument")
  func launchPolicy() {
    #expect(AdaptivePlotterLaunchPolicy(arguments: []).startupRoute == .preferredCamera)
    #expect(
      AdaptivePlotterLaunchPolicy(arguments: ["AdaptivePlotter"]).startupRoute
        == .preferredCamera
    )
    #expect(
      AdaptivePlotterLaunchPolicy(arguments: [
        "AdaptivePlotter", "-AdaptivePlotterStartSimulated", "YES",
      ]).startupRoute == .simulated
    )
    #expect(
      AdaptivePlotterLaunchPolicy(arguments: [
        "AdaptivePlotter", "-AdaptivePlotterStartSimulated", "NO",
      ]).startupRoute == .preferredCamera
    )
  }

  @Test("simulated startup bypasses camera discovery selection and start")
  @MainActor
  func simulatedStartupIsCameraSafe() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let workspace = plotterApplicationRuntime(machine: machine, camera: camera, log: log)
    let policy = AdaptivePlotterLaunchPolicy(arguments: [
      "AdaptivePlotter", "-AdaptivePlotterStartSimulated", "YES",
    ])

    await workspace.performApplicationStartup(policy)

    #expect(camera.startupActionCounts.discover == 0)
    #expect(camera.startupActionCounts.select == 0)
    #expect(camera.startupActionCounts.start == 0)
    #expect(workspace.frameMode == .simulated)
    #expect(workspace.displayedFrame?.source == .simulated)
    #expect(workspace.overlayStatus(for: .penCap).state == .available)
    #expect(
      workspace.overlayStatus(for: .penCap).message.contains("causal simulated pen-cap geometry")
    )
    #expect(await log.values.isEmpty)
    await workspace.shutdown()
  }

  @Test("normal startup retains preferred-camera discovery and start")
  @MainActor
  func normalStartupRemainsCameraFirst() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let workspace = plotterApplicationRuntime(machine: machine, camera: camera, log: log)

    await workspace.performApplicationStartup(
      AdaptivePlotterLaunchPolicy(arguments: ["AdaptivePlotter"])
    )

    #expect(camera.startupActionCounts.discover == 1)
    #expect(camera.startupActionCounts.select == 0)
    #expect(camera.startupActionCounts.start == 1)
    #expect(workspace.frameMode == .live)
    #expect(workspace.displayedFrame?.source == .live(camera.device.id))
    #expect(await log.values.isEmpty)
    await workspace.shutdown()
  }

  @Test("machine session withdraws telemetry access before teardown suspends")
  func machineSessionWithdrawsBeforeTeardown() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "adaptiveplotter-session-drain-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let databaseURL = directory.appendingPathComponent("run.sqlite")
    let ledger = try RunLedger(databaseURL: databaseURL)
    let runID = LedgerRunID()
    _ = try await ledger.createRun(
      id: runID,
      buildID: "test",
      createdAt: RuntimeTimestamp(monotonicNanoseconds: 1)
    )
    let closeGate = ApplicationLifecycleCloseGate()
    let link = ApplicationLifecycleCloseBlockingLink(gate: closeGate)
    let controller = MachineController(link: link, ledger: ledger, runID: runID)
    let interpreter = RunInterpreter(machineController: controller)
    let session = PersistentMachineSession(
      selectedDescriptor: link.descriptor,
      interpreter: interpreter,
      ledger: ledger
    )
    let accepted = applicationLifecycleTelemetryEvent(
      phase: .batchAdmitted,
      detail: "accepted before session withdrawal"
    )
    let rejected = applicationLifecycleTelemetryEvent(
      phase: .failed,
      detail: "rejected after session withdrawal"
    )

    #expect(await session.recordWorkflowTelemetry(accepted))
    let disconnectTask = Task { await session.disconnect() }
    await closeGate.waitUntilBlockedClose()

    #expect(await session.snapshot() == nil)
    #expect(!(await session.recordWorkflowTelemetry(rejected)))

    await closeGate.release()
    await disconnectTask.value
    #expect(!(await session.recordWorkflowTelemetry(rejected)))

    let reader = try RunLedger.openReadOnly(databaseURL: databaseURL)
    let events = try await reader.events(runID: runID)
    let workflowEvents = events.filter {
      $0.kind.hasPrefix("workflow.")
    }
    await reader.close()
    #expect(
      workflowEvents.map(\.kind) == [
        "workflow.sparseTipCalibration.batchAdmitted"
      ]
    )
    #expect(
      try workflowEvents.map {
        try JSONDecoder().decode(WorkflowTelemetryEvent.self, from: $0.payload)
      } == [accepted]
    )

    let settled = await interpreter.snapshot()
    #expect(settled.currentOperation == .idle)
    #expect(settled.machine.connection == .disconnected)
  }
}

private enum ApplicationLifecycleRecordingError: LocalizedError {
  case unavailable

  var errorDescription: String? { "injected recording-directory failure" }
}

private func applicationLifecycleTelemetryEvent(
  phase: WorkflowTelemetryPhase,
  detail: String
) -> WorkflowTelemetryEvent {
  WorkflowTelemetryEvent(
    operationID: UUID(),
    operation: .sparseTipCalibration,
    phase: phase,
    detail: detail,
    sparseTipProgress: SparseTipWorkflowProgress(
      stage: phase == .batchAdmitted ? .batchAdmitted : .terminal,
      completedCircleCount: 0,
      totalCircleCount: 4,
      terminalDisposition: phase == .failed ? .failed : nil
    )
  )
}

private actor ApplicationLifecycleCloseGate {
  private var closeWasReached = false
  private var releaseWasRequested = false
  private var reachedWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  func block() async {
    closeWasReached = true
    let pendingReachedWaiters = reachedWaiters
    reachedWaiters.removeAll(keepingCapacity: false)
    for waiter in pendingReachedWaiters { waiter.resume() }
    guard !releaseWasRequested else { return }
    await withCheckedContinuation { releaseWaiters.append($0) }
  }

  func waitUntilBlockedClose() async {
    guard !closeWasReached else { return }
    await withCheckedContinuation { reachedWaiters.append($0) }
  }

  func release() {
    releaseWasRequested = true
    let pendingReleaseWaiters = releaseWaiters
    releaseWaiters.removeAll(keepingCapacity: false)
    for waiter in pendingReleaseWaiters { waiter.resume() }
  }
}

private final class ApplicationLifecycleCloseBlockingLink: MachineLink, @unchecked Sendable {
  let descriptor = MachineLinkDescriptor(
    identifier: "application-lifecycle-close-gate",
    displayName: "Application Lifecycle Close Gate",
    bsdPath: nil,
    transport: .simulated
  )
  private let gate: ApplicationLifecycleCloseGate

  init(gate: ApplicationLifecycleCloseGate) {
    self.gate = gate
  }

  func open() async throws -> MachineLinkOpenReceipt {
    MachineLinkOpenReceipt(
      appliedConfiguration: .simulated(identifier: descriptor.identifier)
    )
  }

  func close() async throws { await gate.block() }

  func discardPendingInput() async throws -> MachineLinkDiscardReceipt {
    throw MachineLinkError.notOpen
  }

  func write(_: Data) async throws -> MachineLinkWriteReceipt {
    throw MachineLinkError.notOpen
  }

  func read(
    maximumBytes _: Int,
    timeoutNanoseconds _: UInt64
  ) async throws -> MachineLinkReadReceipt {
    throw MachineLinkError.notOpen
  }
}

@MainActor
private func isolatedApplicationDelegate() throws -> (delegate: AdaptivePlotterApplicationDelegate, directory: URL) {
  let log = EventLog()
  let machine = try LowerMachineSessionFixture(log: log)
  let camera = try TestObservationCameraSession()
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "application-lifecycle-\(UUID().uuidString)", isDirectory: true)
  let evidence = DrawingRunEvidencePort(store: DrawingRunEvidenceStore(
    fileURL: directory.appendingPathComponent("evidence.json")))
  let workspace = plotterApplicationRuntime(machine: machine, camera: camera,
    drawingEvidencePort: evidence, log: log)
  let delegate = AdaptivePlotterApplicationDelegate(
    composition: PlotterEpisodeComposition(application: workspace))
  #expect(delegate.applicationRuntime === workspace)
  return (delegate, directory)
}
