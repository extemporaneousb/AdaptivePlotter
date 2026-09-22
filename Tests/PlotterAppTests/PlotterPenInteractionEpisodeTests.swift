import Foundation
import PlotterEpisodeModel
import PlotterModel
import PlotterTestSupport
import PlotterUI
import Testing

@testable import PlotterApp
@testable import PlotterEpisodeRuntime
@testable import PlotterRuntime

@Suite("Plotter Pen Interaction episode", .serialized)
struct PlotterPenInteractionEpisodeTests {
  @Test("exact Up and Down values settle before atomic accepted evidence")
  func exactValuesAndAtomicSuccessEvidence() async throws {
    let port = PenInteractionPortFixture()
    let runtime = PlotterPenInteractionRuntime(port: port)
    try await startReady(runtime)

    _ = await submit(runtime, .setpoint(command: .raise, value: 55))
    #expect((await runtime.snapshot(environment: .live)).projection.phase == .awaitingConfirmation(.raise))
    _ = await submit(runtime, .confirm(command: .raise))
    _ = await submit(runtime, .actuate(.lower))
    _ = await submit(runtime, .setpoint(command: .lower, value: 805))
    _ = await submit(runtime, .confirm(command: .lower))
    _ = await submit(runtime, .actuate(.raise))

    let beforeFinalConfirmation = await runtime.snapshot(environment: .live)
    #expect(beforeFinalConfirmation.projection.phase == .awaitingConfirmation(.raise))
    #expect(beforeFinalConfirmation.acceptedHistory.records.isEmpty)
    _ = await submit(runtime, .confirm(command: .raise))

    let accepted = await runtime.snapshot(environment: .live)
    let evidence = try #require(accepted.acceptedHistory.includedSuccessfulAttempts.first?.value)
    #expect(accepted.projection.phase == .succeeded)
    #expect(accepted.projection.evidenceCount == 1)
    #expect(accepted.profile.raisedSpindleValue == 55)
    #expect(accepted.profile.loweredSpindleValue == 805)
    #expect(evidence.confirmedUpSpindleValues == [55, 55])
    #expect(evidence.confirmedDownSpindleValues == [805])
    #expect(evidence.confirmedUpControllerOutcomes.allSatisfy { $0 != nil })
    #expect(evidence.confirmedDownControllerOutcomes.allSatisfy { $0 != nil })
    #expect(!accepted.projection.physicalEvidenceClaimed)
    #expect(await port.requests.map(\.profile.raisedSpindleValue) == [55, 55, 55, 55])
    #expect(await port.requests.map(\.profile.loweredSpindleValue) == [760, 760, 805, 805])
  }

  @Test("stale and foreign operation projections refuse without lower dispatch")
  func staleAndForeignOperationIdentityRefuse() async throws {
    let port = PenInteractionPortFixture()
    let runtime = PlotterPenInteractionRuntime(port: port)
    let idle = await runtime.snapshot(environment: .live).projection.reference
    try await startReady(runtime)

    let stale = await runtime.submit(submission(
      projection: idle,
      intent: .setpoint(command: .raise, value: 52)
    ))
    guard case .refused(let staleRefusal) = stale else {
      Issue.record("Expected the obsolete projection to be refused.")
      return
    }
    #expect(staleRefusal.reason == .staleProjection)
    #expect(staleRefusal.remedy == .useCurrentProjection)

    let current = await runtime.snapshot(environment: .live).projection.reference
    let foreign = PlotterPenInteractionProjectionReference(
      environment: current.environment,
      revision: current.revision,
      operationID: PlotterPenInteractionOperationID()
    )
    let foreignDisposition = await runtime.submit(submission(
      projection: foreign,
      intent: .setpoint(command: .raise, value: 53)
    ))
    guard case .refused(let foreignRefusal) = foreignDisposition else {
      Issue.record("Expected the foreign operation identity to be refused.")
      return
    }
    #expect(foreignRefusal.reason == .staleProjection)
    #expect(await port.requests.isEmpty)
  }

  @Test("duplicate admission preserves the exact active operation")
  func duplicateAdmissionPreservesOwner() async throws {
    let port = PenInteractionPortFixture()
    let runtime = PlotterPenInteractionRuntime(port: port)
    try await startReady(runtime)
    let active = await runtime.snapshot(environment: .live)

    let duplicate = await submit(runtime, .start(mode: .additional, attemptID: UUID()))
    guard case .refused(let refusal) = duplicate else {
      Issue.record("Expected duplicate admission to be refused.")
      return
    }
    #expect(refusal.reason == .interactionAlreadyActive)
    #expect(refusal.remedy == .finishOrCancelCurrentInteraction)
    #expect((await runtime.snapshot(environment: .live)).projection.reference.operationID
      == active.projection.reference.operationID)
    #expect(await port.requests.isEmpty)
  }

  @MainActor
  @Test("Confirm publishes a non-clickable revision before any publication wait")
  func confirmationClaimsProjectionBeforeAwaiting() async throws {
    let port = PenInteractionPortFixture()
    let gate = PlotterPenInteractionConfirmationAdmissionGate()
    let runtime = PlotterPenInteractionRuntime(
      port: port,
      confirmationAdmissionGate: gate
    )
    try await startReady(runtime)
    _ = await submit(runtime, .setpoint(command: .raise, value: 58))
    let before = await runtime.snapshot(environment: .live).projection
    #expect(before.phase == .awaitingConfirmation(.raise))

    let first = Task {
      await runtime.submit(submission(
        projection: before.reference,
        intent: .confirm(command: .raise)
      ))
    }
    await gate.waitUntilHeld()

    let admitted = await runtime.snapshot(environment: .live).projection
    #expect(admitted.phase == .confirming(.raise))
    #expect(admitted.reference.revision > before.reference.revision)

    let duplicate = Task {
      await runtime.submit(submission(
        projection: before.reference,
        intent: .confirm(command: .raise)
      ))
    }
    await gate.release()
    guard case .applied = await first.value else {
      Issue.record("Expected the first exact Confirm request to apply.")
      return
    }
    guard case .refused(let refusal) = await duplicate.value else {
      Issue.record("Expected the obsolete second click to be refused.")
      return
    }
    #expect(refusal.reason == .staleProjection)
    #expect((await runtime.snapshot(environment: .live)).projection.phase
      == .awaitingControllerCommand(.lower))
    #expect(await port.requests.count == 1)
  }

  @MainActor
  @Test("Stop supersedes a held Confirm without recording operator evidence")
  func stopSupersedesHeldConfirmation() async throws {
    let port = PenInteractionPortFixture()
    let gate = PlotterPenInteractionConfirmationAdmissionGate()
    let runtime = PlotterPenInteractionRuntime(
      port: port,
      confirmationAdmissionGate: gate
    )
    try await startReady(runtime)
    _ = await submit(runtime, .setpoint(command: .raise, value: 58))
    let before = await runtime.snapshot(environment: .live).projection.reference
    let confirmation = Task {
      await runtime.submit(submission(
        projection: before,
        intent: .confirm(command: .raise)
      ))
    }
    await gate.waitUntilHeld()
    let capability = try #require(
      (await runtime.snapshot(environment: .live)).projection.cancellationCapabilityID
    )

    guard case .applied = await submit(runtime, .stop(capability)) else {
      Issue.record("Expected exact Stop to settle the held Confirm owner.")
      return
    }
    await gate.release()
    guard case .superseded(let projection) = await confirmation.value else {
      Issue.record("A Confirm displaced by Stop must not report applied.")
      return
    }

    #expect(projection.reference.operationID == nil)
    #expect(projection.evidenceCount == 0)
    let terminal = await runtime.snapshot(environment: .live)
    #expect(terminal.acceptedHistory.records.count == 1)
    #expect(terminal.acceptedHistory.attempts.first?.disposition == .cancelled)
    #expect(!terminal.projection.physicalEvidenceClaimed)
  }

  @MainActor
  @Test("shutdown supersedes a held Confirm and closes admission")
  func shutdownSupersedesHeldConfirmation() async throws {
    let port = PenInteractionPortFixture()
    let gate = PlotterPenInteractionConfirmationAdmissionGate()
    let runtime = PlotterPenInteractionRuntime(
      port: port,
      confirmationAdmissionGate: gate
    )
    try await startReady(runtime)
    _ = await submit(runtime, .setpoint(command: .raise, value: 58))
    let before = await runtime.snapshot(environment: .live).projection.reference
    let confirmation = Task {
      await runtime.submit(submission(
        projection: before,
        intent: .confirm(command: .raise)
      ))
    }
    await gate.waitUntilHeld()

    await runtime.shutdown()
    await gate.release()
    guard case .superseded(let projection) = await confirmation.value else {
      Issue.record("A Confirm displaced by shutdown must not report applied.")
      return
    }

    #expect(projection.reference.operationID == nil)
    #expect(projection.evidenceCount == 0)
    #expect((await runtime.snapshot(environment: .live)).acceptedHistory.attempts.first?.disposition
      == .cancelled)
    #expect(!(await runtime.snapshot(environment: .live)).projection.physicalEvidenceClaimed)
  }

  @Test("effect state publishes before the held lower actuation returns")
  func outputPrecedesActuationSettlement() async throws {
    let port = PenInteractionPortFixture()
    await port.holdNext()
    let runtime = PlotterPenInteractionRuntime(port: port)
    try await startReady(runtime)

    let setpoint = Task { await submit(runtime, .setpoint(command: .raise, value: 61)) }
    await port.waitUntilHeld()
    let held = await runtime.snapshot(environment: .live)

    #expect(held.projection.phase == .settling(.raise))
    #expect(held.projection.profile.raisedSpindleValue == 61)
    #expect(held.lastSettlement == nil)
    #expect(held.acceptedHistory.records.isEmpty)
    #expect(await port.requests.map(\.command) == [.raise])

    await port.release()
    _ = await setpoint.value
    #expect((await runtime.snapshot(environment: .live)).projection.phase == .awaitingConfirmation(.raise))
  }

  @Test("latest admitted setpoint replaces the pending value before drain")
  func latestOnlySetpointCoalescing() async throws {
    let port = PenInteractionPortFixture()
    await port.holdNext()
    let admissionGate = PlotterPenInteractionSetpointAdmissionGate()
    let runtime = PlotterPenInteractionRuntime(
      port: port,
      setpointAdmissionGate: admissionGate
    )
    try await startReady(runtime)

    let first = Task { await submit(runtime, .setpoint(command: .raise, value: 55)) }
    await port.waitUntilHeld()
    #expect(await port.requests.map(\.profile.raisedSpindleValue) == [55])

    await admissionGate.holdNextAdmittedSetpoint()
    let second = Task { await submit(runtime, .setpoint(command: .raise, value: 56)) }
    await admissionGate.waitUntilHeld()
    let refreshed = await runtime.snapshot(environment: .live)
    #expect(refreshed.projection.phase == .drainingSetpoint(.raise))
    #expect(refreshed.projection.profile.raisedSpindleValue == 56)
    let thirdProjection = refreshed.projection.reference

    await admissionGate.release()
    await admissionGate.holdNextAdmittedSetpoint()
    let third = Task {
      await runtime.submit(submission(
        projection: thirdProjection,
        intent: .setpoint(command: .raise, value: 57)
      ))
    }
    await admissionGate.waitUntilHeld()
    let latestAdmitted = await runtime.snapshot(environment: .live)
    #expect(latestAdmitted.projection.profile.raisedSpindleValue == 57)
    #expect(await port.requests.map(\.profile.raisedSpindleValue) == [55])

    await admissionGate.release()
    await port.release()
    _ = await first.value
    _ = await second.value
    _ = await third.value

    let settled = await runtime.snapshot(environment: .live)
    #expect(settled.projection.phase == .awaitingConfirmation(.raise))
    #expect(settled.projection.profile.raisedSpindleValue == 57)
    #expect(await port.requests.map(\.profile.raisedSpindleValue) == [55, 57])
  }

  @MainActor
  @Test("wrong Stop capability refuses and exact Stop settles the held owner once")
  func exactStopCapabilityAndSettlement() async throws {
    let port = PenInteractionPortFixture()
    await port.holdNext()
    let runtime = PlotterPenInteractionRuntime(port: port)
    let projectionProbe = PenInteractionCancellationPublicationProbe()
    await runtime.installProjectionSink(projectionProbe)
    try await startReady(runtime)
    let effect = Task { await submit(runtime, .setpoint(command: .raise, value: 62)) }
    await port.waitUntilHeld()

    let wrong = await submit(runtime, .stop(PlotterPenInteractionCancellationCapabilityID()))
    guard case .refused(let refusal) = wrong else {
      Issue.record("Expected a foreign Stop capability to be refused.")
      return
    }
    #expect(refusal.reason == .cancellationCapabilityMismatch)
    let capability = try #require(
      (await runtime.snapshot(environment: .live)).projection.cancellationCapabilityID
    )
    let stop = Task { await submit(runtime, .stop(capability)) }
    await projectionProbe.waitUntilCancelling()
    await port.release()
    _ = await effect.value
    guard case .applied(let stoppedProjection) = await stop.value else {
      Issue.record("Expected the admitted exact Stop to settle and publish terminal truth.")
      return
    }
    #expect(stoppedProjection.reference.operationID == nil)

    let terminal = await runtime.snapshot(environment: .live)
    #expect(terminal.projection.reference.operationID == nil)
    #expect(terminal.projection.cancellationCapabilityID == nil)
    #expect(terminal.acceptedHistory.records.count == 1)
    #expect(terminal.acceptedHistory.attempts.first?.disposition == .cancelled)
    guard case .possiblePhysicalChange = terminal.projection.phase else {
      Issue.record("A settled command followed by Stop must retain possible-change truth.")
      return
    }
    #expect(await port.requests.count == 1)
    #expect(!terminal.projection.physicalEvidenceClaimed)
  }

  @Test("controller refusal and ambiguity retain distinct terminal truth")
  func refusalAndAmbiguityRemainDistinct() async throws {
    let refusedPort = PenInteractionPortFixture(outcomes: [.refused(.controllerRejected("fixture"))])
    let refusedRuntime = PlotterPenInteractionRuntime(port: refusedPort)
    try await startReady(refusedRuntime)
    _ = await submit(refusedRuntime, .setpoint(command: .raise, value: 63))
    #expect((await refusedRuntime.snapshot(environment: .live)).projection.phase
      == .refused(.lowerRefused(PenRefusal.controllerRejected("fixture").actionableDescription)))

    let ambiguousPort = PenInteractionPortFixture(
      outcomes: [.ambiguous(.transport("write acknowledgement lost"))]
    )
    let ambiguousRuntime = PlotterPenInteractionRuntime(port: ambiguousPort)
    try await startReady(ambiguousRuntime)
    _ = await submit(ambiguousRuntime, .setpoint(command: .raise, value: 64))
    let ambiguous = await ambiguousRuntime.snapshot(environment: .live)
    guard case .possiblePhysicalChange(let detail) = ambiguous.projection.phase else {
      Issue.record("Expected possible physical change after ambiguous lower settlement.")
      return
    }
    #expect(detail.contains("write acknowledgement lost"))
    #expect(!ambiguous.projection.physicalEvidenceClaimed)
  }

  @Test("LIVE and SIMULATED histories and lower provenance remain separate")
  func liveAndSimulatedTruthRemainSeparate() async throws {
    let port = PenInteractionPortFixture()
    let runtime = PlotterPenInteractionRuntime(port: port)
    try await startReady(runtime, environment: .simulated)
    _ = await submit(runtime, .setpoint(command: .raise, value: 65), environment: .simulated)
    _ = await submit(runtime, .confirm(command: .raise), environment: .simulated)

    let live = await runtime.snapshot(environment: .live)
    let simulated = await runtime.snapshot(environment: .simulated)
    #expect(live.projection.phase == .idle)
    #expect(live.acceptedHistory.records.isEmpty)
    #expect(simulated.projection.reference.environment == .simulated)
    #expect(simulated.acceptedHistory.compatibility.group.rawValue == "simulated-pen-interaction")
    #expect(await port.requests.map(\.environment) == [.simulated])
    #expect(simulated.lastSettlement?.machineSnapshot == nil)
    #expect(!simulated.projection.physicalEvidenceClaimed)
  }

  @Test("terminal publication is indivisible from cached settlement truth")
  func terminalPublicationIsAtomic() async throws {
    let port = PenInteractionPortFixture()
    let gate = PlotterPenInteractionTerminalPublicationGate()
    await gate.holdNextPublication()
    let runtime = PlotterPenInteractionRuntime(port: port, terminalPublicationGate: gate)
    try await startReady(runtime)

    let setpoint = Task { await submit(runtime, .setpoint(command: .raise, value: 66)) }
    await gate.waitUntilHeld()
    let held = await runtime.snapshot(environment: .live)
    #expect(held.projection.phase == .settling(.raise))
    #expect(held.lastSettlement == nil)
    #expect(held.lastExecutionByCommand.isEmpty)

    await gate.release()
    _ = await setpoint.value
    let published = await runtime.snapshot(environment: .live)
    #expect(published.projection.phase == .awaitingConfirmation(.raise))
    #expect(published.lastSettlement?.operationID == published.projection.reference.operationID)
    #expect(published.lastExecutionByCommand[.raise]?.profile.raisedSpindleValue == 66)
  }

  @Test("shutdown waits for the held effect, settles once, and closes admission")
  func heldEffectShutdownIsQuiescent() async throws {
    let port = PenInteractionPortFixture()
    await port.holdNext()
    let runtime = PlotterPenInteractionRuntime(port: port)
    try await startReady(runtime)
    let effect = Task { await submit(runtime, .setpoint(command: .raise, value: 67)) }
    await port.waitUntilHeld()

    let shutdown = Task { await runtime.shutdown() }
    await port.release()
    _ = await effect.value
    await shutdown.value

    let closed = await runtime.snapshot(environment: .live)
    #expect(closed.projection.reference.operationID == nil)
    #expect(closed.acceptedHistory.attempts.first?.disposition == .cancelled)
    #expect(await port.requests.count == 1)
    let rejected = await submit(runtime, .start(mode: .normal, attemptID: UUID()))
    guard case .refused(let refusal) = rejected else {
      Issue.record("Expected shutdown to close future admission.")
      return
    }
    #expect(refusal.reason == .admissionClosed)
    #expect(refusal.remedy == .restartApplication)
    #expect(await port.requests.count == 1)
    #expect(!closed.projection.physicalEvidenceClaimed)
  }

  @MainActor
  @Test("production UI coalesces refreshed setpoints and Next awaits exact settlement")
  func productionUICoalescingAndConfirmationOrdering() async throws {
    let admissionGate = PlotterPenInteractionSetpointAdmissionGate()
    let fixture = try makeProductionPenWorkspace(setpointAdmissionGate: admissionGate)
    try await preparePenQuestion(fixture.workspace, machine: fixture.machine)
    try requireStep(fixture.workspace, "answer-initially-up")
    #expect(await fixture.machine.requestedPenCommands.isEmpty)

    await admissionGate.holdNextAdmittedSetpoint()
    let request55 = try currentPenSetpointRequest(fixture.workspace, value: 55)
    let sink: any PlotterUIIntentSink = fixture.workspace
    let first = Task { await sink.submitPlotterUIRequest(request55) }
    await admissionGate.waitUntilHeld()

    let admitted55 = await fixture.runtime.snapshot(environment: .live)
    #expect(admitted55.projection.phase == .drainingSetpoint(.raise))
    #expect(admitted55.projection.profile.raisedSpindleValue == 55)
    #expect(admitted55.projection.lastRefusal == nil)
    #expect(await fixture.machine.requestedPenCommands.isEmpty)

    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let nextActionID = learningActionID(.choice(.yes), owner: owner)
    let preDrainSemantic = fixture.workspace.testPlotterUIProjection(
      selectedItemID: owner,
      includesLearningPath: true
    ).semantic
    #expect(preDrainSemantic.request(for: nextActionID) == nil)
    let preDrainStopRequest = try currentPenStopRequest(fixture.workspace)
    guard case .learningAction(let preDrainRequest) = preDrainStopRequest.intent,
      case .stopPenInteraction(let preDrainCapability) = preDrainRequest.action
    else {
      Issue.record("Expected exact Pen Stop while the accepted setpoint awaits its drain.")
      return
    }
    #expect(preDrainCapability == admitted55.projection.cancellationCapabilityID)

    let request57 = try currentPenSetpointRequest(fixture.workspace, value: 57)
    let second = Task { await sink.submitPlotterUIRequest(request57) }
    await admissionGate.waitUntilAdmissionCount(2)
    let queued57 = await fixture.runtime.snapshot(environment: .live)
    #expect(queued57.projection.phase == .drainingSetpoint(.raise))
    #expect(queued57.projection.profile.raisedSpindleValue == 57)
    #expect(await fixture.machine.requestedPenCommands.isEmpty)

    await admissionGate.release()
    await fixture.lowerGate.waitUntilHeld()

    let held57 = await fixture.runtime.snapshot(environment: .live)
    #expect(held57.projection.phase == .settling(.raise))
    #expect(held57.projection.profile.raisedSpindleValue == 57)
    #expect(held57.acceptedHistory.records.isEmpty)
    #expect(await fixture.machine.requestedPenCommands == [.raise])
    let heldProfiles = await fixture.machine.requestedPenProfiles
    #expect(heldProfiles.map(\.raisedSpindleValue) == [57])
    #expect(heldProfiles.allSatisfy {
      $0.raisedSpindleValue != 55
    })

    let heldSemantic = fixture.workspace.testPlotterUIProjection(
      selectedItemID: owner,
      includesLearningPath: true
    ).semantic
    #expect(heldSemantic.request(for: nextActionID) == nil)
    let heldStopRequest = try currentPenStopRequest(fixture.workspace)
    guard case .learningAction(let heldRequest) = heldStopRequest.intent,
      case .stopPenInteraction(let heldCapability) = heldRequest.action
    else {
      Issue.record("Expected exact Pen Stop while the coalesced setpoint is settling.")
      return
    }
    #expect(heldCapability == held57.projection.cancellationCapabilityID)
    try requireStep(fixture.workspace, "answer-initially-up")
    #expect((await fixture.runtime.snapshot(environment: .live)).acceptedHistory.records.isEmpty)

    await fixture.lowerGate.releaseFirstRequest()
    let firstDisposition = await first.value
    let secondDisposition = await second.value

    #expect(firstDisposition == .accepted(requestID: request55.id))
    #expect(secondDisposition == .accepted(requestID: request57.id))
    let published57 = await fixture.runtime.snapshot(environment: .live)
    #expect(published57.projection.phase == .awaitingConfirmation(.raise))
    #expect(published57.lastSettlement?.operationID == published57.projection.reference.operationID)
    #expect(published57.lastExecutionByCommand[.raise]?.profile.raisedSpindleValue == 57)
    await waitForObservedCondition {
      fixture.workspace.testPlotterUIProjection(
        selectedItemID: owner,
        includesLearningPath: true
      ).semantic.request(for: nextActionID) != nil
        || fixture.workspace.discoveryError != nil
    }
    let nextRequest = try currentPenChoiceRequest(fixture.workspace, choice: .yes)
    let nextDisposition = await sink.submitPlotterUIRequest(nextRequest)
    #expect(nextDisposition == .accepted(requestID: nextRequest.id))
    #expect(fixture.workspace.discoveryError == nil)
    await waitForObservedCondition {
      fixture.workspace.discoveryTransactions[.penInteraction]?.currentStep?.id
        == "answer-currently-down"
        || fixture.workspace.discoveryError != nil
    }
    try requireStep(fixture.workspace, "answer-currently-down")
    let settledProfiles = await fixture.machine.requestedPenProfiles
    #expect(settledProfiles.allSatisfy {
      $0.raisedSpindleValue != 55
    })
    #expect(await fixture.machine.requestedPenCommands == [.raise, .lower])
    await fixture.workspace.shutdown()
  }

  @MainActor
  @Test("production Stop during held Confirm records no physical confirmation or successor")
  func productionStopSupersedesHeldConfirmation() async throws {
    let gate = PlotterPenInteractionConfirmationAdmissionGate()
    let fixture = try makeProductionPenWorkspace(confirmationAdmissionGate: gate)
    try await preparePenQuestion(fixture.workspace, machine: fixture.machine)
    let sink: any PlotterUIIntentSink = fixture.workspace
    let setpoint = try currentPenSetpointRequest(fixture.workspace, value: 58)
    let setpointTask = Task { await sink.submitPlotterUIRequest(setpoint) }
    await fixture.lowerGate.waitUntilHeld()
    await fixture.lowerGate.releaseFirstRequest()
    #expect(await setpointTask.value == .accepted(requestID: setpoint.id))
    try requireStep(fixture.workspace, "answer-initially-up")
    let evidenceCount = fixture.workspace.discoveryTransactions[.penInteraction]?
      .evidenceSummaries.count

    let yes = try currentPenChoiceRequest(fixture.workspace, choice: .yes)
    let confirmation = Task { await sink.submitPlotterUIRequest(yes) }
    await gate.waitUntilHeld()
    #expect((await fixture.runtime.snapshot(environment: .live)).projection.phase
      == .confirming(.raise))

    let stop = try currentPenStopRequest(fixture.workspace)
    #expect(await sink.submitPlotterUIRequest(stop) == .accepted(requestID: stop.id))
    await gate.release()
    #expect(await confirmation.value == .accepted(requestID: yes.id))

    #expect(fixture.workspace.discoveryTransactions[.penInteraction]?.currentStep?.id
      != "answer-currently-down")
    #expect(fixture.workspace.discoveryTransactions[.penInteraction]?.evidenceSummaries.count
      == evidenceCount)
    let terminal = await fixture.runtime.snapshot(environment: .live)
    #expect(terminal.projection.evidenceCount == 0)
    #expect(terminal.acceptedHistory.attempts.first?.disposition == .cancelled)
    #expect(!terminal.projection.physicalEvidenceClaimed)
    await fixture.workspace.shutdown()
  }

  @MainActor
  @Test("root shutdown during held Confirm records no physical confirmation or successor")
  func productionShutdownSupersedesHeldConfirmation() async throws {
    let gate = PlotterPenInteractionConfirmationAdmissionGate()
    let fixture = try makeProductionPenWorkspace(confirmationAdmissionGate: gate)
    try await preparePenQuestion(fixture.workspace, machine: fixture.machine)
    let sink: any PlotterUIIntentSink = fixture.workspace
    let setpoint = try currentPenSetpointRequest(fixture.workspace, value: 58)
    let setpointTask = Task { await sink.submitPlotterUIRequest(setpoint) }
    await fixture.lowerGate.waitUntilHeld()
    await fixture.lowerGate.releaseFirstRequest()
    #expect(await setpointTask.value == .accepted(requestID: setpoint.id))
    let evidenceCount = fixture.workspace.discoveryTransactions[.penInteraction]?
      .evidenceSummaries.count
    let yes = try currentPenChoiceRequest(fixture.workspace, choice: .yes)
    let confirmation = Task { await sink.submitPlotterUIRequest(yes) }
    await gate.waitUntilHeld()

    let shutdown = Task { await fixture.workspace.shutdown() }
    var shutdownClaimedOwner = false
    for _ in 0..<200 {
      let projection = await fixture.runtime.snapshot(environment: .live).projection
      if projection.phase == .cancelling || projection.reference.operationID == nil {
        shutdownClaimedOwner = true
        break
      }
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    #expect(shutdownClaimedOwner)
    await gate.release()
    guard case .refused(let refusal) = await confirmation.value else {
      Issue.record("Shutdown must publish the exact outer Learning cancellation refusal.")
      return
    }
    #expect(refusal.reason == .retainedOwnerRefused)
    #expect(refusal.remedy.contains("cancelled"))
    guard case .learningAction(let learningRequest) = yes.intent else {
      Issue.record("The rendered confirmation lost its exact Learning request.")
      return
    }
    let episode = try #require(fixture.workspace.learningEpisodeRecord.entries.last)
    #expect(episode.request == .action(learningRequest))
    #expect(episode.postTransitionProjection.stateRevision == episode.postStateRevision)
    #expect(episode.postTransitionProjection.activeOwner == learningRequest.item)
    #expect(episode.stateChangePublished)
    guard case .refused(let reason, let owner, let remedy) = episode.result else {
      Issue.record("Shutdown cancellation must publish a typed Learning episode refusal.")
      return
    }
    #expect(reason == .ownerRefused)
    #expect(owner.rawValue == "PlotterApplicationRuntime")
    #expect(remedy == refusal.remedy)
    await shutdown.value

    #expect(fixture.workspace.discoveryTransactions[.penInteraction]?.currentStep?.id
      != "answer-currently-down")
    #expect(fixture.workspace.discoveryTransactions[.penInteraction]?.evidenceSummaries.count
      == evidenceCount)
    let terminal = await fixture.runtime.snapshot(environment: .live)
    #expect(terminal.projection.evidenceCount == 0)
    #expect(terminal.acceptedHistory.attempts.first?.disposition == .cancelled)
    #expect(!terminal.projection.physicalEvidenceClaimed)
  }

  @MainActor
  @Test("canonical Pen Stop and lower uncertainty remain exact UI truth")
  func productionUIStopRefusalAndAmbiguityTruth() async throws {
    let stopFixture = try makeProductionPenWorkspace()
    try await preparePenQuestion(stopFixture.workspace, machine: stopFixture.machine)
    let firstExactStop = try currentPenStopRequest(stopFixture.workspace)
    let foreignCapability = PlotterPenInteractionCancellationCapabilityID()
    let forged = PlotterUIRequest(
      id: PlotterUIRequestID(rawValue: UUID()),
      uiRevision: firstExactStop.uiRevision,
      runtimeRevisions: firstExactStop.runtimeRevisions,
      actionID: firstExactStop.actionID,
      intent: .penInteraction(.stop(foreignCapability))
    )
    let sink: any PlotterUIIntentSink = stopFixture.workspace
    guard case .refused(let foreignRefusal) = await sink.submitPlotterUIRequest(forged) else {
      Issue.record("Expected a foreign Pen Stop capability to be refused by exact UI binding.")
      return
    }
    #expect(foreignRefusal.reason == .mismatchedIntent)
    #expect(await stopFixture.machine.requestedPenCommands.isEmpty)

    let refreshedStop = try currentPenStopRequest(stopFixture.workspace)
    let stale = PlotterUIRequest(
      id: PlotterUIRequestID(rawValue: UUID()),
      uiRevision: PlotterUIRevision(rawValue: refreshedStop.uiRevision.rawValue &+ 1),
      runtimeRevisions: refreshedStop.runtimeRevisions,
      actionID: refreshedStop.actionID,
      intent: refreshedStop.intent
    )
    // Stop retains the exact active capability despite UI revision churn.
    let exactStop = stale
    guard case .learningAction(let exactRequest) = exactStop.intent,
      case .stopPenInteraction(let exactCapability) = exactRequest.action
    else {
      Issue.record("Expected the canonical action to carry the typed Pen Stop capability.")
      return
    }
    let exactDisposition = await sink.submitPlotterUIRequest(exactStop)
    #expect(exactDisposition == .accepted(requestID: exactStop.id))
    let stopped = await stopFixture.runtime.snapshot(environment: .live)
    #expect(stopped.projection.reference.operationID == nil)
    #expect(stopped.projection.cancellationCapabilityID == nil)
    #expect(stopped.acceptedHistory.attempts.first?.disposition == .cancelled)
    #expect(stopFixture.workspace.activeExerciseAttemptOwnerID == nil)
    #expect(await stopFixture.machine.requestedPenCommands.isEmpty)
    #expect(exactCapability.rawValue != foreignCapability.rawValue)
    await stopFixture.workspace.shutdown()

    let refusedFixture = try makeProductionPenWorkspace()
    await refusedFixture.machine.enqueuePenOutcome(.refused(.controllerRejected("fixture")))
    try await preparePenQuestion(refusedFixture.workspace, machine: refusedFixture.machine)
    await refusedFixture.lowerGate.releaseFirstRequest()
    let refusedRequest = try currentPenSetpointRequest(refusedFixture.workspace, value: 63)
    let refusedSink: any PlotterUIIntentSink = refusedFixture.workspace
    #expect(await refusedSink.submitPlotterUIRequest(refusedRequest)
      == .accepted(requestID: refusedRequest.id))
    let refused = await refusedFixture.runtime.snapshot(environment: .live)
    #expect(refused.projection.phase
      == .refused(.lowerRefused(PenRefusal.controllerRejected("fixture").actionableDescription)))
    #expect(!refused.projection.physicalEvidenceClaimed)
    #expect(await refusedFixture.machine.requestedPenCommands == [.raise])
    let refusedResend = try currentPenSetpointRequestIfAvailable(
      refusedFixture.workspace,
      value: 63
    )
    #expect(refusedResend == nil)
    #expect(await refusedFixture.machine.requestedPenCommands == [.raise])
    await refusedFixture.workspace.shutdown()

    let ambiguousFixture = try makeProductionPenWorkspace()
    await ambiguousFixture.machine.enqueuePenOutcome(
      .ambiguous(.transport("write acknowledgement lost"))
    )
    try await preparePenQuestion(ambiguousFixture.workspace, machine: ambiguousFixture.machine)
    await ambiguousFixture.lowerGate.releaseFirstRequest()
    let ambiguousRequest = try currentPenSetpointRequest(ambiguousFixture.workspace, value: 64)
    let ambiguousSink: any PlotterUIIntentSink = ambiguousFixture.workspace
    #expect(await ambiguousSink.submitPlotterUIRequest(ambiguousRequest)
      == .accepted(requestID: ambiguousRequest.id))
    let ambiguous = await ambiguousFixture.runtime.snapshot(environment: .live)
    guard case .possiblePhysicalChange(let detail) = ambiguous.projection.phase else {
      Issue.record("Expected possible-change truth after ambiguous production lower settlement.")
      return
    }
    #expect(detail.contains("write acknowledgement lost"))
    #expect(!ambiguous.projection.physicalEvidenceClaimed)
    #expect(await ambiguousFixture.machine.requestedPenCommands == [.raise])
    let ambiguousResend = try currentPenSetpointRequestIfAvailable(
      ambiguousFixture.workspace,
      value: 64
    )
    #expect(ambiguousResend == nil)
    #expect(await ambiguousFixture.machine.requestedPenCommands == [.raise])
    await ambiguousFixture.workspace.shutdown()
  }

  @MainActor
  @Test("re-entering SIMULATED starts fresh without changing LIVE Pen truth")
  func simulatedReentryStartsFreshAndPreservesLive() async throws {
    let fixture = makeCausalSimulatorAppFixture()
    let workspace = fixture.workspace
    let runtime = fixture.penInteractionRuntime
    let liveBefore = await runtime.snapshot(environment: .live)

    await submitObservationConfigurationForTest(workspace, .selectSource(.simulated, nil))
    await submitControllerSession(workspace, .toggleConnection)
    await submitControllerSession(workspace, .toggleMotionAuthorization)
    try await preparePenQuestion(workspace)
    let firstActive = await runtime.snapshot(environment: .simulated)
    let firstOperation = try #require(firstActive.projection.reference.operationID)
    let setpoint = try currentPenSetpointRequest(workspace, value: 73)
    let sink: any PlotterUIIntentSink = workspace
    #expect(await sink.submitPlotterUIRequest(setpoint) == .accepted(requestID: setpoint.id))
    let adjusted = await runtime.snapshot(environment: .simulated)
    #expect(adjusted.projection.profile.raisedSpindleValue == 73)
    #expect(adjusted.projection.reference.operationID == firstOperation)

    let firstStop = try currentPenStopRequest(workspace)
    #expect(await sink.submitPlotterUIRequest(firstStop) == .accepted(requestID: firstStop.id))
    let firstTerminal = await runtime.snapshot(environment: .simulated)
    #expect(firstTerminal.acceptedHistory.records.count == 1)
    #expect(firstTerminal.acceptedHistory.attempts.first?.disposition == .cancelled)
    #expect(!firstTerminal.projection.physicalEvidenceClaimed)

    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    let liveAfterFirstSession = await runtime.snapshot(environment: .live)
    #expect(liveAfterFirstSession.projection.phase == liveBefore.projection.phase)
    #expect(liveAfterFirstSession.profile == liveBefore.profile)
    #expect(liveAfterFirstSession.acceptedHistory.records.isEmpty)
    #expect(liveAfterFirstSession.projection.reference.operationID == nil)

    await submitObservationConfigurationForTest(workspace, .selectSource(.simulated, nil))
    let fresh = await runtime.snapshot(environment: .simulated)
    #expect(fresh.projection.phase == .idle)
    #expect(fresh.profile == .initialDefaults)
    #expect(fresh.acceptedHistory.records.isEmpty)
    #expect(fresh.projection.reference.operationID == nil)
    #expect(!fresh.projection.physicalEvidenceClaimed)

    try await preparePenQuestion(workspace)
    let secondActive = await runtime.snapshot(environment: .simulated)
    let secondOperation = try #require(secondActive.projection.reference.operationID)
    #expect(secondOperation != firstOperation)
    #expect(secondActive.profile == .initialDefaults)
    #expect(secondActive.acceptedHistory.records.isEmpty)
    let secondStop = try currentPenStopRequest(workspace)
    #expect(await sink.submitPlotterUIRequest(secondStop) == .accepted(requestID: secondStop.id))
    let liveAfterSecondSession = await runtime.snapshot(environment: .live)
    #expect(liveAfterSecondSession.projection.phase == liveBefore.projection.phase)
    #expect(liveAfterSecondSession.profile == liveBefore.profile)
    #expect(liveAfterSecondSession.acceptedHistory.records.isEmpty)
    await workspace.shutdown()
  }
}

private struct ProductionPenWorkspaceFixture {
  let workspace: PlotterApplicationRuntime
  let runtime: PlotterPenInteractionRuntime
  let machine: LowerMachineSessionFixture
  let lowerGate: PenRequestGate
}

@MainActor
private func makeProductionPenWorkspace(
  setpointAdmissionGate: PlotterPenInteractionSetpointAdmissionGate? = nil,
  confirmationAdmissionGate: PlotterPenInteractionConfirmationAdmissionGate? = nil,
  speechAnnouncer: (any SpeechAnnouncing)? = nil,
  speechOutputEnabled: Bool = true,
  workbenchVoiceListener: (any SpeechListening)? = nil
) throws -> ProductionPenWorkspaceFixture {
  let log = EventLog()
  let lowerGate = PenRequestGate()
  let machine = try LowerMachineSessionFixture(log: log, penRequestGate: lowerGate)
  let camera = try TestObservationCameraSession()
  var capturedRuntime: PlotterPenInteractionRuntime?
  let workspace = plotterApplicationRuntime(
    machine: machine,
    camera: camera,
    speechAnnouncer: speechAnnouncer, speechOutputEnabled: speechOutputEnabled,
    workbenchVoiceListener: workbenchVoiceListener,
    penInteractionRuntimeFactory: { machineSession, manualMotionComposition in
      let port = PlotterApplicationRuntimePenInteractionActuationPort(
        machineSession: machineSession,
        simulatedAdapter: manualMotionComposition.causalSimulatorEffectAdapter,
        clock: DeterministicRuntimeClock(startNanoseconds: 1)
      )
      let runtime: PlotterPenInteractionRuntime
      if let confirmationAdmissionGate {
        runtime = PlotterPenInteractionRuntime(
          port: port,
          confirmationAdmissionGate: confirmationAdmissionGate
        )
      } else if let setpointAdmissionGate {
        runtime = PlotterPenInteractionRuntime(
          port: port,
          setpointAdmissionGate: setpointAdmissionGate
        )
      } else {
        runtime = PlotterPenInteractionRuntime(port: port)
      }
      capturedRuntime = runtime
      return runtime
    },
    log: log
  )
  return ProductionPenWorkspaceFixture(
    workspace: workspace,
    runtime: try #require(capturedRuntime),
    machine: machine,
    lowerGate: lowerGate
  )
}

@MainActor
private func preparePenQuestion(
  _ workspace: PlotterApplicationRuntime,
  machine: LowerMachineSessionFixture? = nil
) async throws {
  if let machine {
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
  }
  let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
  let startID = learningActionID(.start, owner: owner)
  let startProjection = workspace.testPlotterUIProjection(
    selectedItemID: owner,
    includesLearningPath: true
  ).semantic
  let start = try #require(startProjection.request(for: startID))
  let sink: any PlotterUIIntentSink = workspace
  #expect(await sink.submitPlotterUIRequest(start) == .accepted(requestID: start.id))

  let request = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
  let frame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
  let fallback = try Point2<CameraPixelSpace>(
    x: Double(frame.frame.width - 1) / 2,
    y: Double(frame.frame.height - 1) / 2
  )
  let point = workspace.testActionSurfacePresentation.overlays.compactMap {
    overlay -> Point2<CameraPixelSpace>? in
    guard overlay.provenance.kind == .penCap, case .point(let point) = overlay.geometry else {
      return nil
    }
    return point
  }.first ?? fallback
  let submission = PlotterPointSelectionSubmission(
    selectionID: request.id,
    frame: request.frame,
    point: point,
    presentationTransformRevision: request.presentationTransformRevision,
    referenceRegion: testCapSelectionRegion(point: point, width: request.frame.width, height: request.frame.height)
  )
  let pointProjection = workspace.plotterUIProjection(
    selectedItemID: owner,
    manualDraft: ManualMotionDraft(),
    includesLearningPath: true,
    pendingPointSelection: submission
  ).semantic
  let pointRequest = try #require(
    pointProjection.request(for: PlotterAppUIActionID.pointSelection(submission))
  )
  #expect(await sink.submitPlotterUIRequest(pointRequest) == .accepted(requestID: pointRequest.id))
  await waitForObservedCondition {
    workspace.currentExerciseActionStripPresentation?.penSetpointAdjustment != nil
      || workspace.discoveryError != nil
  }
  try #require(workspace.discoveryError == nil)
  try #require(workspace.currentExerciseActionStripPresentation?.penSetpointAdjustment != nil)
}

@MainActor
private func currentPenSetpointRequest(
  _ workspace: PlotterApplicationRuntime,
  value: Int
) throws -> PlotterUIRequest {
  let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
  let command = try #require(
    workspace.currentExerciseActionStripPresentation?.penSetpointAdjustment?.command
  )
  let actionID = learningSetpointActionID(
    command,
    value: value,
    owner: owner
  )
  let projection = workspace.testPlotterUIProjection(
    selectedItemID: owner,
    includesLearningPath: true
  ).semantic
  return try #require(projection.request(for: actionID))
}

@MainActor
private func currentPenSetpointRequestIfAvailable(
  _ workspace: PlotterApplicationRuntime,
  value: Int
) throws -> PlotterUIRequest? {
  let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
  guard let command = workspace.currentExerciseActionStripPresentation?
    .penSetpointAdjustment?.command
  else { return nil }
  let actionID = learningSetpointActionID(
    command,
    value: value,
    owner: owner
  )
  return workspace.testPlotterUIProjection(
    selectedItemID: owner,
    includesLearningPath: true
  ).semantic.request(for: actionID)
}

@MainActor
private func currentPenChoiceRequest(
  _ workspace: PlotterApplicationRuntime,
  choice: OperatorChoice
) throws -> PlotterUIRequest {
  let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
  let actionID = learningActionID(.choice(
    choice == .yes ? .yes : .no
  ), owner: owner)
  let projection = workspace.testPlotterUIProjection(
    selectedItemID: owner,
    includesLearningPath: true
  ).semantic
  return try #require(projection.request(for: actionID))
}

@MainActor
private func currentPenStopRequest(
  _ workspace: PlotterApplicationRuntime
) throws -> PlotterUIRequest {
  let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
  let projection = workspace.testPlotterUIProjection(
    selectedItemID: owner,
    includesLearningPath: true
  ).semantic
  let action = try #require(projection.actions.first { action in
    guard case .learningAction(let request) = action.intent,
      case .stopPenInteraction = request.action
    else { return false }
    return true
  })
  #expect(action.isAvailable)
  return try #require(projection.request(for: action.id))
}

private func startReady(
  _ runtime: PlotterPenInteractionRuntime,
  environment: PlotterEnvironment = .live
) async throws {
  let started = await submit(
    runtime,
    .start(mode: .normal, attemptID: UUID()),
    environment: environment
  )
  guard case .applied = started else {
    Issue.record("Expected Pen Interaction admission.")
    return
  }
  let selected = await submit(runtime, .capSelectionAccepted, environment: environment)
  guard case .applied = selected else {
    Issue.record("Expected exact cap-selection prerequisite acceptance.")
    return
  }
}

private func submit(
  _ runtime: PlotterPenInteractionRuntime,
  _ intent: PlotterPenInteractionIntent,
  environment: PlotterEnvironment = .live
) async -> PlotterPenInteractionDisposition {
  let projection = await runtime.snapshot(environment: environment).projection.reference
  return await runtime.submit(submission(
    projection: projection,
    intent: intent,
    environment: environment
  ))
}

private func submission(
  projection: PlotterPenInteractionProjectionReference,
  intent: PlotterPenInteractionIntent,
  environment: PlotterEnvironment = .live
) -> PlotterPenInteractionSubmission {
  PlotterPenInteractionSubmission(
    projection: projection,
    facts: PlotterPenInteractionAdmissionFacts(
      environment: environment,
      learningEnabled: true,
      controllerSessionEstablished: true,
      motionAuthorized: true,
      lowerOperationInFlight: false,
      stickyAmbiguity: nil,
      capSelectionAvailable: true
    ),
    intent: intent
  )
}

private actor PenInteractionPortFixture: PlotterPenInteractionActuationPort {
  private var outcomes: [PenOutcome]
  private(set) var requests: [PlotterPenInteractionActuationRequest] = []
  private var holdArmed = false
  private var held = false
  private var heldWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  init(outcomes: [PenOutcome] = []) {
    self.outcomes = outcomes
  }

  func holdNext() {
    holdArmed = true
  }

  func waitUntilHeld() async {
    if held { return }
    await withCheckedContinuation { heldWaiters.append($0) }
  }

  func release() {
    holdArmed = false
    held = false
    releaseContinuation?.resume()
    releaseContinuation = nil
  }

  func settle(
    _ request: PlotterPenInteractionActuationRequest
  ) async -> PlotterPenInteractionActuationSettlement {
    requests.append(request)
    if holdArmed {
      holdArmed = false
      held = true
      let waiters = heldWaiters
      heldWaiters = []
      waiters.forEach { $0.resume() }
      await withCheckedContinuation { releaseContinuation = $0 }
      held = false
    }
    let outcome = outcomes.isEmpty
      ? PenOutcome.commandedAndSettled(
        command: request.command,
        commandedState: request.command.commandedState
      )
      : outcomes.removeFirst()
    return PlotterPenInteractionActuationSettlement(
      operationID: request.operationID,
      outcome: outcome,
      machineSnapshot: nil,
      simulatedTruth: nil,
      observedPosition: nil,
      timestamp: RuntimeTimestamp(monotonicNanoseconds: UInt64(requests.count))
    )
  }
}

@MainActor
private final class PenInteractionCancellationPublicationProbe:
  PlotterPenInteractionProjectionSink
{
  private var cancellingWasPublished = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func publishPenInteractionSnapshot(_ snapshot: PlotterPenInteractionRuntimeSnapshot) {
    guard snapshot.projection.phase == .cancelling else { return }
    cancellingWasPublished = true
    let ready = waiters
    waiters = []
    ready.forEach { $0.resume() }
  }

  func waitUntilCancelling() async {
    if cancellingWasPublished { return }
    await withCheckedContinuation { waiters.append($0) }
  }
}


extension PlotterPenInteractionEpisodeTests {
  @MainActor
  @Test("application Voice Stop reaches the exact held Pen owner while its cue is still playing")
  func productionVoiceStopDuringPenCue() async throws {
    let listener = TestVoiceListener()
    let speech = HeldSpeechAnnouncer()
    let fixture = try makeProductionPenWorkspace(speechAnnouncer: speech,
      speechOutputEnabled: false, workbenchVoiceListener: listener)
    let app = fixture.workspace
    var confirming: Task<PlotterUIRequestDisposition, Never>?
    do {
      try await preparePenQuestion(app, machine: fixture.machine)
      updateProductionPenVoiceContext(app)
      let voice = app.workbenchVoiceController
      voice.setEnabled(true)
      await speech.waitUntilStarted()
      await speech.releaseAll()
      try await waitUntil { voice.isListening }
      let yes = try currentPenChoiceRequest(app, choice: .yes)
      let task = Task { await app.submitPlotterUIRequest(yes) }
      confirming = task
      await fixture.lowerGate.waitUntilHeld()
      await speech.waitUntilStarted(2)
      let stop = try currentPenStopRequest(app)
      updateProductionPenVoiceContext(app)
      try await waitUntil { voice.isListening }
      #expect(!(await app.speechEffectRuntime.snapshot()).activeRequests.isEmpty)
      listener.send(.transcript("Stop", isFinal: false))
      try await waitUntilAsync {
        (await fixture.runtime.snapshot(environment: .live)).projection.phase == .cancelling
      }
      // Recognition has reached the actual Pen runtime before playback or the
      // finite lower actuation settles. Audio never supplies physical evidence.
      #expect(!(await app.speechEffectRuntime.snapshot()).activeRequests.isEmpty)
      #expect(!app.penInteractionCompleted)
      #expect(await fixture.machine.requestedPenCommands == [.lower])
      guard case .learningAction(let request) = stop.intent,
        case .stopPenInteraction = request.action else {
        Issue.record("Expected the current exact Pen Stop request.")
        await fixture.lowerGate.releaseFirstRequest()
        _ = await task.value
        await app.shutdown(); return
      }
      await fixture.lowerGate.releaseFirstRequest()
      _ = await task.value
      try await waitUntilAsync {
        (await fixture.runtime.snapshot(environment: .live)).acceptedHistory.attempts.first?.disposition == .cancelled
      }
      #expect(await fixture.machine.requestedPenCommands == [.lower])
      #expect(!app.penInteractionCompleted)
      await app.shutdown()
      #expect(!voice.isListening)
      #expect((await app.speechEffectRuntime.snapshot()).activeRequests.isEmpty)
    } catch {
      await fixture.lowerGate.releaseFirstRequest()
      await speech.releaseAll(.cancelled)
      _ = await confirming?.value
      await app.shutdown()
      throw error
    }
  }
}
