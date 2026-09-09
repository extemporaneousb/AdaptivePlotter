import Foundation
import PlotterEpisodeModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("PlotterControllerSessionEpisodeTests")
struct PlotterControllerSessionEpisodeTests {
  @Test("stale projection cannot start a lower controller effect")
  func staleProjectionIsRefusedBeforeEffect() async throws {
    let lower = try lowerSession()
    let runtime = PlotterControllerSessionRuntime(
      lowerSession: lower.port,
      simulatedSession: SimulatedLearningRuntime(),
      serialDeviceDiscovery: PlotterFixedSerialDeviceDiscoveryAdapter(
        devices: [lower.descriptor]
      )
    )
    let current = reference(revision: 2)
    let request = PlotterControllerSessionRequest(
      reference: reference(revision: 1),
      intent: .toggleConnection
    )
    let result = await runtime.submit(
      request,
      facts: facts(
        reference: current,
        selected: lower.descriptor,
        devices: [lower.descriptor]
      )
    )
    guard case .refused = result else {
      Issue.record("Expected the stale controller-session request to be refused.")
      return
    }
    #expect(await lower.fixture.passiveProbeCallCount == 0)
  }

  @Test("explicit LIVE connect selects once and completes a passive probe")
  func explicitLiveConnectRecordsCurrentFacts() async throws {
    let lower = try lowerSession()
    let runtime = PlotterControllerSessionRuntime(
      lowerSession: lower.port,
      simulatedSession: SimulatedLearningRuntime(),
      serialDeviceDiscovery: PlotterFixedSerialDeviceDiscoveryAdapter(
        devices: [lower.descriptor]
      )
    )
    let projection = reference(revision: 1)
    let result = await runtime.submit(
      PlotterControllerSessionRequest(reference: projection, intent: .toggleConnection),
      facts: facts(
        reference: projection,
        selected: lower.descriptor,
        devices: [lower.descriptor]
      )
    )
    guard case .completed(.liveSession(let snapshot, let probe, let error)) = result else {
      Issue.record("Expected one completed LIVE controller-session transition.")
      return
    }
    #expect(snapshot?.machine.link == lower.descriptor)
    #expect(probe?.link == lower.descriptor)
    #expect(error == nil)
    #expect(await lower.fixture.passiveProbeCallCount == 1)
  }

  @Test("an open probing link projects a semantic red Disconnect before session establishment")
  func probingLinkUsesDisconnectAction() async throws {
    let lower = try lowerSession()
    let projection = reference(revision: 4)
    let machine = MachineSnapshot(
      connection: .probing,
      link: lower.descriptor,
      lastProbe: nil,
      blockers: []
    )
    let snapshot = RunInterpreterSnapshot(
      currentOperation: .passiveProbe,
      machine: machine,
      lastMotionOutcome: nil,
      lastProbe: nil
    )
    let projected = PlotterControllerSessionRules.project(facts(
      reference: projection,
      selected: lower.descriptor,
      devices: [lower.descriptor],
      machineSnapshot: snapshot
    ))

    #expect(!projected.sessionEstablished)
    #expect(projected.connectionAction == .disconnect)
    #expect(
      WorkbenchConnectionActionPresentation(action: projected.connectionAction)
        .role.chrome(isEnabled: true) == .neutralEnabled
    )
  }

  @Test("shutdown closes admission before any later controller request")
  func shutdownClosesAdmission() async throws {
    let lower = try lowerSession()
    let runtime = PlotterControllerSessionRuntime(
      lowerSession: lower.port,
      simulatedSession: SimulatedLearningRuntime(),
      serialDeviceDiscovery: PlotterFixedSerialDeviceDiscoveryAdapter(
        devices: [lower.descriptor]
      )
    )
    await runtime.shutdown()
    let projection = reference(revision: 1)
    let result = await runtime.submit(
      PlotterControllerSessionRequest(reference: projection, intent: .toggleConnection),
      facts: facts(
        reference: projection,
        selected: lower.descriptor,
        devices: [lower.descriptor],
        admissionClosed: true
      )
    )
    guard case .refused = result else {
      Issue.record("Expected shutdown to refuse later controller-session work.")
      return
    }
    #expect(await lower.fixture.passiveProbeCallCount == 0)
  }

  @Test("shutdown cancellation cannot start a blocked controller-session effect")
  func shutdownCancelsBlockedStartBeforeLowerEffect() async throws {
    let lower = try lowerSession()
    let gate = ControllerExecutionCancellationGate()
    let runtime = PlotterControllerSessionRuntime(
      lowerSession: lower.port,
      simulatedSession: SimulatedLearningRuntime(),
      serialDeviceDiscovery: PlotterFixedSerialDeviceDiscoveryAdapter(
        devices: [lower.descriptor]
      ),
      effectAdmission: gate
    )
    let projection = reference(revision: 1)
    let submission = Task {
      await runtime.submit(
        PlotterControllerSessionRequest(reference: projection, intent: .toggleConnection),
        facts: facts(
          reference: projection,
          selected: lower.descriptor,
          devices: [lower.descriptor]
        )
      )
    }

    await gate.waitUntilEntered()
    let shutdown = Task { await runtime.shutdown() }
    await gate.waitUntilCancellationObserved()
    await shutdown.value

    guard case .cancelled = await submission.value else {
      Issue.record("Expected shutdown to cancel the blocked controller-session submission.")
      return
    }
    #expect(await lower.effects.selectCallCount == 0)
    #expect(await lower.effects.snapshotCallCount == 0)
    #expect(await lower.effects.passiveProbeCallCount == 0)
    #expect(await lower.effects.disconnectCallCount == 1)
  }

  @Test("SIMULATED alarm clear is refused without touching the lower session")
  func simulatedAlarmClearIsNonphysical() async throws {
    let lower = try lowerSession()
    let projection = reference(revision: 1)
    let state = facts(
      reference: projection,
      environment: .simulated,
      selected: lower.descriptor,
      devices: [lower.descriptor]
    )
    #expect(
      PlotterControllerSessionRules.refusal(for: .clearAlarm, facts: state)
        == "SIMULATED owns no physical controller alarm."
    )
    #expect(await lower.fixture.passiveProbeCallCount == 0)
  }

  @Test("physical review exports queried status while the lower snapshot remains stale")
  @MainActor
  func physicalReviewUsesQueryEvidenceInsteadOfSnapshotTime() async throws {
    let initial = try LowerMachineSessionFixture(log: EventLog())
    let cached = await initial.snapshot()
    let lower = try lowerSession(retainedSnapshot: cached)
    try await lower.fixture.setPosition(x: 7, y: 9)
    let runtime = PlotterControllerSessionRuntime(lowerSession: lower.port,
      simulatedSession: SimulatedLearningRuntime(),
      serialDeviceDiscovery: PlotterFixedSerialDeviceDiscoveryAdapter(devices: [lower.descriptor]))
    let currentFacts = facts(reference: reference(revision: 4), selected: lower.descriptor,
      devices: [lower.descriptor], machineSnapshot: cached)
    let receipt = try await RunningAppPreviewPerformanceGate.physicalControllerObservation(
      projection: PlotterControllerSessionRules.project(currentFacts),
      sink: PhysicalReviewControllerQuerySink(runtime: runtime, facts: currentFacts))
    #expect(await lower.fixture.passiveProbeCallCount == 1)
    let stillCached = await lower.port.snapshot()
    #expect(stillCached?.machine.position == cached.machine.position)
    #expect(receipt.status.machinePosition == (try MachinePosition(x: 7, y: 9)))
    #expect(receipt.status.machinePosition != stillCached?.machine.position)
    let exchange = try #require(receipt.probe.exchanges.first { $0.query == .status })
    #expect(receipt.statusExchangeCommandID == exchange.commandID)
    #expect(receipt.status == exchange.latestStatusReport)
    // Original query timestamps survive export; no Date() can relabel a cached
    // snapshot as a new controller measurement.
    #expect(receipt.probe.startedAt.monotonicNanoseconds == 1)
    #expect(receipt.probe.completedAt.monotonicNanoseconds == 2)
    let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(receipt)) as? [String: Any])
    let statusJSON = try #require(json["status"] as? [String: Any])
    let exportedStatus = try JSONDecoder().decode(ControllerStatusReport.self,
      from: JSONSerialization.data(withJSONObject: statusJSON))
    #expect(exportedStatus.machinePosition == receipt.status.machinePosition)
    #expect(json["exportedAt"] == nil)
    await runtime.shutdown()
  }

  private func reference(revision: UInt64) -> PlotterControllerSessionReference {
    PlotterControllerSessionReference(revision: revision, capabilityID: UUID())
  }

  private func facts(
    reference: PlotterControllerSessionReference,
    environment: OperatorFrameMode = .live,
    selected: MachineLinkDescriptor?,
    devices: [MachineLinkDescriptor],
    admissionClosed: Bool = false,
    machineSnapshot: RunInterpreterSnapshot? = nil
  ) -> PlotterControllerSessionFacts {
    PlotterControllerSessionFacts(
      reference: reference,
      environment: environment,
      selectedSerialDevice: selected,
      serialDevices: devices,
      machineSnapshot: machineSnapshot,
      passiveProbe: nil,
      simulatedSnapshot: nil,
      machineError: nil,
      admissionClosed: admissionClosed,
      controllerBusyReason: nil,
      discoveryBusyReason: nil,
      foreignOperationInFlight: false,
      frameModeSwitchInProgress: false,
      connectionActionInProgress: false,
      alarmClearInProgress: false,
      motionActionInProgress: false,
      lowerSessionAvailable: true
    )
  }

  private func lowerSession(retainedSnapshot: RunInterpreterSnapshot? = nil) throws -> (
    descriptor: MachineLinkDescriptor,
    fixture: LowerMachineSessionFixture,
    effects: ControllerSessionEffectRecorder,
    port: ClosurePlotterMachineSession
  ) {
    let fixture = try LowerMachineSessionFixture(log: EventLog())
    let effects = ControllerSessionEffectRecorder()
    let descriptor = fixture.descriptor
    let port = ClosurePlotterMachineSession(
      select: { _ in
        await effects.recordSelect()
        return await fixture.snapshot()
      },
      snapshot: {
        await effects.recordSnapshot()
        if let retainedSnapshot { return retainedSnapshot }
        return await fixture.snapshot()
      },
      requestPassiveProbe: {
        await effects.recordPassiveProbe()
        return await fixture.passiveProbeResult()
      },
      requestControllerAlarmClear: { .refused(.noCurrentAlarmEvidence) },
      activateMotionGuard: { await fixture.activateMotionGuard() },
      deactivateMotionGuard: { await fixture.deactivateMotionGuard() },
      beginRelativeJog: { _ in .rejected(.refused(.notConnected)) },
      beginDrawingStroke: { _ in .rejected(.refused(.notConnected)) },
      beginPenActuation: { _, _ in .rejected(.refused(.notConnected)) },
      beginBoundaryMotion: { request, _ in
        .rejected(.needsAttention(
          ownerID: request.ownerID,
          terminal: .refusal(.notConnected)
        ))
      },
      requestJogCancel: { _ in .refused(.noActiveJog) },
      disconnect: { await effects.recordDisconnect() }
    )
    return (descriptor, fixture, effects, port)
  }
}

private struct PhysicalReviewControllerQuerySink: PlotterControllerSessionIntentSink {
  let runtime: PlotterControllerSessionRuntime
  let facts: PlotterControllerSessionFacts

  func submitControllerSessionRequest(_ request: PlotterControllerSessionRequest) async -> PlotterControllerSessionDisposition {
    await runtime.submit(request, facts: facts)
  }
}

private actor ControllerExecutionCancellationGate: PlotterControllerEffectAdmissionPort {
  private var entered = false
  private var cancellationObserved = false

  func awaitEffectAdmission() async {
    entered = true
    while !Task.isCancelled {
      await Task.yield()
    }
    cancellationObserved = true
  }

  func waitUntilEntered() async {
    while !entered {
      await Task.yield()
    }
  }

  func waitUntilCancellationObserved() async {
    while !cancellationObserved {
      await Task.yield()
    }
  }
}

private actor ControllerSessionEffectRecorder {
  private(set) var selectCallCount = 0
  private(set) var snapshotCallCount = 0
  private(set) var passiveProbeCallCount = 0
  private(set) var disconnectCallCount = 0

  func recordSelect() {
    selectCallCount += 1
  }

  func recordSnapshot() {
    snapshotCallCount += 1
  }

  func recordPassiveProbe() {
    passiveProbeCallCount += 1
  }

  func recordDisconnect() {
    disconnectCallCount += 1
  }
}
