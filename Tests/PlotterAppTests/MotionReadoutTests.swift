import AppKit
import Foundation
import Observation
import SwiftUI
import PlotterRuntime
import PlotterTestSupport
import Testing

@testable import PlotterApp

@Suite("Motion readout", .serialized)
@MainActor
struct MotionReadoutTests {
  @Test("coherent report values retain receipt age and label stale disconnected missing data")
  func freshnessAndCoherence() throws {
    let model = MotionReadoutModel()
    let snapshot = try sampleSnapshot(sequence: 4, received: 100, x: 12, pins: "X")
    model.refresh(snapshot: snapshot, nowNanoseconds: 100)
    #expect(model.presentation.freshness == .live)
    #expect(model.presentation.position == "X 12.000   Y 2.000")
    #expect(model.presentation.controller == "jog")
    #expect(model.presentation.limits == "Pn:X")
    #expect(model.presentation.commandedPen == "up")
    let receipt = model.presentation.receipt
    model.refresh(snapshot: snapshot, nowNanoseconds: 3_000_000_100)
    #expect(model.presentation.freshness == .stale)
    #expect(model.presentation.receipt == receipt)
    #expect(model.presentation.sequence == 4)
    // A genuinely received identical numeric report is fresh, with a new identity.
    model.refresh(snapshot: try sampleSnapshot(sequence: 5, received: 3_000_000_100, x: 12, pins: "X"),
      nowNanoseconds: 3_000_000_100)
    #expect(model.presentation.freshness == .live)
    #expect(model.presentation.sequence == 5)
    model.refresh(snapshot: try sampleSnapshot(sequence: 5, received: 100, x: 12, disconnected: true),
      nowNanoseconds: 101)
    #expect(model.presentation.freshness == .disconnected)
    #expect(model.presentation.position == "unavailable")
    model.refresh(snapshot: nil, nowNanoseconds: 102)
    #expect(model.presentation.freshness == .unavailable)
    model.refresh(snapshot: snapshot, nowNanoseconds: 99)
    #expect(model.presentation.freshness == .stale)
  }

  @Test("visible task refreshes immediately and cancellation stops reads until reopening")
  func visibilityLifetime() async throws {
    let model = MotionReadoutModel()
    let source = MotionReadoutTestSource(snapshot: try sampleSnapshot(sequence: 1, received: 1, x: 1))
    let first = Task { await model.observe(reader: { await source.read() }) }
    try await waitUntil { model.presentation.sequence == 1 }
    first.cancel()
    await first.value
    #expect(!model.isRefreshing)
    let hiddenReads = await source.reads
    await source.set(try sampleSnapshot(sequence: 2, received: 2, x: 2))
    for _ in 0..<20 { await Task.yield() }
    #expect(await source.reads == hiddenReads)
    #expect(model.presentation.sequence == 1)
    let reopened = Task { await model.observe(reader: { await source.read() }) }
    try await waitUntil { model.presentation.sequence == 2 }
    reopened.cancel()
    await reopened.value
    #expect(await source.reads == hiddenReads + 1)
    #expect(model.presentation.position == "X 2.000   Y 2.000")
  }

  @Test("native Motion pane removal stops its task and reopening resumes bounded reads")
  func nativePaneVisibilityLifetime() async throws {
    _ = NSApplication.shared
    let model = NativeMotionModel(snapshot: try sampleSnapshot(sequence: 1, received: 1, x: 1))
    let host = NSHostingView(rootView: NativeMotionHarness(model: model))
    let window = NSWindow(
      contentRect: NSRect(x: -10000, y: -10000, width: 1000, height: 700),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFront(nil)
    defer { window.close() }

    try await waitUntil {
      host.layoutSubtreeIfNeeded()
      return model.readTimes.count >= 3
    }
    #expect(hasNativeMotionPane(host))
    // The bound applies to adjacent actual reads, so slow CI rendering cannot
    // fail an exact-count or upper-latency expectation. Small clock tolerance
    // still catches a presentation loop running materially faster than 5 Hz.
    for (earlier, later) in zip(model.readTimes, model.readTimes.dropFirst()) {
      #expect(later - earlier >= 190_000_000)
    }

    model.layout.setPresented(.motion, false)
    try await waitUntil {
      host.layoutSubtreeIfNeeded()
      return !hasNativeMotionPane(host)
    }
    for _ in 0..<10 { await Task.yield() }
    let hiddenReads = model.readTimes.count
    let hiddenUntil = DispatchTime.now().uptimeNanoseconds
      + 3 * MotionReadoutModel.refreshIntervalNanoseconds
    while DispatchTime.now().uptimeNanoseconds < hiddenUntil {
      try await Task.sleep(for: .milliseconds(10))
      #expect(model.readTimes.count == hiddenReads)
    }

    model.layout.setPresented(.motion, true)
    try await waitUntil {
      host.layoutSubtreeIfNeeded()
      return hasNativeMotionPane(host) && model.readTimes.count > hiddenReads
    }
    #expect(model.readTimes.count > hiddenReads)
    // Ending the window also removes the real native presentation owner.
    // No explicit model task or cancellation is used anywhere in this test.
    window.close()
  }

  @Observable @MainActor
  final class NativeMotionModel {
    var layout = WorkbenchLayoutState(presented: [.motion])
    @ObservationIgnored var readTimes: [UInt64] = []
    @ObservationIgnored let snapshot: MachineSnapshot
    init(snapshot: MachineSnapshot) { self.snapshot = snapshot }
    func read() -> MachineSnapshot {
      readTimes.append(DispatchTime.now().uptimeNanoseconds)
      return snapshot
    }
  }

  private struct NativeMotionHarness: View {
    @Bindable var model: NativeMotionModel
    var body: some View {
      WorkbenchPanels(layout: $model.layout, autosavePrefix: nil) { panel in
        if panel == .motion {
          MotionReadout(reader: { model.read() })
        } else { Text(panel.title) }
      } canvas: { Color.black }
    }
  }

  private func hasNativeMotionPane(_ view: NSView) -> Bool {
    if let split = view as? WorkbenchNativeSplit.NativeView,
      split.hosts[WorkbenchPanel.motion.rawValue] != nil { return true }
    return view.subviews.contains(where: hasNativeMotionPane)
  }

  @Test("cancelling a hidden pane rejects a snapshot that arrives after cancellation")
  func hiddenInFlightReadCannotPublish() async throws {
    let model = MotionReadoutModel()
    let gate = MotionReadoutSnapshotGate(snapshot: try sampleSnapshot(sequence: 9, received: 9, x: 9))
    let task = Task { await model.observe(reader: { await gate.read() }) }
    while !(await gate.isWaiting) { await Task.yield() }
    task.cancel()
    await gate.release()
    await task.value
    #expect(model.presentation.sequence == nil)
    #expect(!model.isRefreshing)
  }

  @Test("production accessor reads owner reports without rebuilding Learning or Drawing projections")
  func productionProjectionIsolation() async throws {
    let clock = DeterministicRuntimeClock()
    let exchanges = (0..<3).flatMap { x in
      var probe = ControllerTranscriptFixtures.successfulPassiveProbe(delayNanoseconds: 1)
      probe[2] = ControllerTranscriptFixtures.exchange(.status,
        chunks: ["<Idle|MPos:\(x).000,2.000,0.000>\r\n"], delay: 1)
      return probe
    }
    let link = SimulatedGRBLLink(exchanges: exchanges, clock: clock)
    let controller = MachineController(link: link, clock: clock, queryTimeoutNanoseconds: 1_000)
    let interpreter = RunInterpreter(machineController: controller)
    let session = readoutSession(interpreter: interpreter, controller: controller)
    let draftRuntime = nominalDrawingDraftRuntime()
    let runComposition = nominalDrawingRunComposition(machineSession: session)
    let workspace = PlotterApplicationRuntime(
      machineSession: session,
      penInteractionRuntime: nominalPenInteractionRuntime(machineSession: session),
      boundaryRuntime: nominalBoundaryRuntime(),
      statePersistencePort: TestApplicationStatePersistencePort(),
      drawingDraftRuntime: draftRuntime,
      drawingRunComposition: runComposition,
      incidentPackageUIService: nominalIncidentPackageUIService(),
      residualEffectPort: TestApplicationResidualEffectPort(
        discoverDevices: { [] }, readNanoseconds: { clock.nowNanoseconds() }),
      observationPreferences: TestObservationPreferencePort())
    // Join the owner's complete Draft/Run bootstrap tail, then synchronize
    // through the production Run fact source (which awaits nested Draft facts).
    // A nonnil Run snapshot alone can still be its pre-synchronization revision 0.
    await workspace.drawingDraftSynchronizationTask?.value
    let initialRun = await runComposition.runtime.synchronize(environment: .live)
    try await waitUntil {
      workspace.drawingRunSnapshot?.projection == initialRun.projection
    }
    let initialDraft = await draftRuntime.synchronize(workspace.drawingDraftExternalFacts)
    #expect(workspace.drawingDraftSnapshot.projection == initialDraft.projection)
    #expect(await controller.snapshot().latestStatusSample == nil)
    _ = workspace.testPlotterUIProjection(includesLearningPath: true)
    let baseline = workspace.computationDiagnosticsForTesting
    let model = MotionReadoutModel()
    for x in 0..<3 {
      _ = try await interpreter.requestPassiveProbe()
      let writes = link.completedWriteCount
      model.refresh(snapshot: await workspace.latestMotionReadoutSnapshot(),
        nowNanoseconds: clock.nowNanoseconds())
      #expect(model.presentation.position == "X \(x).000   Y 2.000")
      #expect(model.presentation.sequence == UInt64(x + 1))
      #expect(link.completedWriteCount == writes)
      _ = workspace.testPlotterUIProjection(includesLearningPath: true)
    }
    let after = workspace.computationDiagnosticsForTesting
    #expect(after.semanticPresentationRevision == baseline.semanticPresentationRevision)
    #expect(after.learningProjectionBuildCount == baseline.learningProjectionBuildCount)
    #expect(after.plotterUIProjectionBuildCount == baseline.plotterUIProjectionBuildCount)
    #expect(after.drawingDraftSynchronizationCount == baseline.drawingDraftSynchronizationCount)
    #expect(workspace.drawingRunSnapshot?.projection.runRevision == initialRun.projection.runRevision)
    #expect(workspace.machineSnapshot == nil)
    await workspace.shutdown()
  }

  private func sampleSnapshot(
    sequence: UInt64, received: UInt64, x: Double, pins: String = "", disconnected: Bool = false
  ) throws -> MachineSnapshot {
    MachineSnapshot(connection: disconnected ? .disconnected : .moving,
      link: MachineLinkDescriptor(identifier: "motion-test", displayName: "Motion test", bsdPath: nil,
        transport: .simulated), lastProbe: nil, blockers: [],
      controllerState: .idle, position: try MachinePosition(x: -99, y: -99),
      penState: .up,
      latestStatusSample: ControllerStatusSample(
        report: ControllerStatusReport(state: "Jog", fields: [], pins: pins,
          machinePosition: try MachinePosition(x: x, y: 2)),
        receivedAt: RuntimeTimestamp(monotonicNanoseconds: received), sequence: sequence))
  }

  private func readoutSession(interpreter: RunInterpreter, controller: MachineController)
    -> any PlotterMachineSession {
    ClosurePlotterMachineSession(
      select: { _ in await interpreter.snapshot() },
      snapshot: { await interpreter.snapshot() },
      requestPassiveProbe: { try await interpreter.requestPassiveProbe() },
      requestControllerAlarmClear: { .refused(.noCurrentAlarmEvidence) },
      activateMotionGuard: { await controller.activateMotionGuard() },
      deactivateMotionGuard: { await controller.deactivateMotionGuard() },
      beginRelativeJog: { _ in .rejected(.refused(.notConnected)) },
      beginDrawingStroke: { _ in .rejected(.refused(.notConnected)) },
      beginPenActuation: { _, _ in .rejected(.refused(.notConnected)) },
      beginBoundaryMotion: { request, _ in
        .rejected(.needsAttention(ownerID: request.ownerID, terminal: .refusal(.notConnected)))
      },
      requestJogCancel: { _ in .refused(.noActiveJog) },
      disconnect: { await controller.disconnect() })
  }
}

private actor MotionReadoutTestSource {
  var snapshot: MachineSnapshot?
  private(set) var reads = 0
  init(snapshot: MachineSnapshot?) { self.snapshot = snapshot }
  func read() -> MachineSnapshot? { reads += 1; return snapshot }
  func set(_ snapshot: MachineSnapshot?) { self.snapshot = snapshot }
}

private actor MotionReadoutSnapshotGate {
  let snapshot: MachineSnapshot
  private(set) var isWaiting = false
  private var continuation: CheckedContinuation<MachineSnapshot?, Never>?
  init(snapshot: MachineSnapshot) { self.snapshot = snapshot }
  func read() async -> MachineSnapshot? {
    await withCheckedContinuation { continuation = $0; isWaiting = true }
  }
  func release() { continuation?.resume(returning: snapshot); continuation = nil }
}
