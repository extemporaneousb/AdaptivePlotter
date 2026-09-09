import EpisodeCore
import Foundation
import Observation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterTestSupport
import Testing
import os

@testable import PlotterApp
@testable import PlotterRuntime

extension PlotterApplicationRuntimeTests {
  @Test("LIVE possible-ink ambiguity disables effects until exact operator disposition")
  func liveManualAmbiguityDisposition() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("manual-live-ambiguity-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let counter = ManualMotionAmbiguousInvocationCounter()
    let actions = manualMotionWorkspaceActions(
      machine: machine,
      beginRelativeJog: { _ in
        counter.increment()
        return .admitted(RelativeJogOperation(id: UUID(), task: Task {
          .ambiguous(.transport("Controller settlement was ambiguous."))
        }))
      }
    )
    let simulatedLearning = SimulatedLearningRuntime()
    let composition = PlotterManualMotionComposition.makeRuntimeComposition(
      journalFileURL: directory.appendingPathComponent("journal.json"),
      machineSession: actions,
      simulatedRuntime: simulatedLearning,
      simulatedExecutionPacing: SimulatedLearningInteractivePacing(stepDelay: .zero)
    )
    let workspace = PlotterApplicationRuntime(
      machineSession: actions,
      manualMotionComposition: composition,
      penInteractionRuntime: nominalPenInteractionRuntime(
        machineSession: actions,
        manualMotionComposition: composition
      ),
      boundaryRuntime: nominalBoundaryRuntime(),
      drawingDraftRuntime: nominalDrawingDraftRuntime(),
      drawingRunComposition: nominalDrawingRunComposition(),
      incidentPackageUIService: nominalIncidentPackageUIService(),
      residualEffectPort: AuthorityTestResidualEffectPort(devices: [machine.descriptor]),
      serialDevices: [machine.descriptor],
      observationPreferences: TestObservationPreferencePort()
    )
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)

    let intent = try manualAmbiguityJog()
    await workspace.submitManualMotionIntent(intent)
    let pending = workspace.testManualMotionEpisodePresentation
    let evidence = try #require(pending.evidenceDisposition)
    #expect(evidence.action.environment == .live)
    #expect(evidence.action.disposition == .acknowledgePossibleInk)
    #expect(evidence.title == "Acknowledge Possible Ink")
    #expect(workspace.manualMotionEpisodeSnapshot?.projection.phase == .awaitingEvidence)
    #expect(pending.jogControlsUnavailableReason == evidence.remedy)
    #expect(pending.penUpUnavailableReason == evidence.remedy)
    #expect(pending.penDownUnavailableReason == evidence.remedy)
    #expect(workspace.motionRequestStatusPresentation == .needsAttention(evidence.remedy))
    let evidenceUI = workspace.testPlotterUIProjection()
    #expect(evidenceUI.controllerSession.controllerAttentionText == evidence.remedy)
    #expect(evidenceUI.manualMotion.controllerAlertText(
      evidenceUI.controllerSession.controllerAttentionText) == nil)
    let evidenceRequest = try #require(evidenceUI.semantic.request(for: PlotterAppUIActionID.manualEvidence))
    #expect(evidenceRequest.intent == .manualEvidenceDisposition(
      effectID: evidence.action.effectID.rawValue,
      environment: evidence.action.environment,
      observationID: evidence.action.observationID.rawValue,
      disposition: .acknowledgePossibleInk))
    #expect(counter.count == 1)

    await workspace.submitManualMotionIntent(intent)
    let blockedPen = try #require(
      workspace.testPlotterUIProjection().semantic.action(id: PlotterAppUIActionID.manualPenDown)
    )
    #expect(!blockedPen.isAvailable)
    #expect(workspace.testPlotterUIProjection().semantic.request(for: blockedPen.id) == nil)
    #expect(counter.count == 1)
    let stale = PlotterManualMotionEvidenceDispositionAction(
      effectID: evidence.action.effectID,
      environment: evidence.action.environment,
      observationID: PlotterObservationID(rawValue: UUID()),
      disposition: evidence.action.disposition,
      summary: evidence.action.summary
    )
    await workspace.resolveTestManualMotionEvidence(using: stale)
    #expect(workspace.manualMotionEpisodeSnapshot?.projection.phase == .awaitingEvidence)

    await workspace.resolveTestManualMotionEvidence(using: evidence.action)
    #expect(workspace.manualMotionEpisodeSnapshot?.projection.phase == .ready)
    #expect(workspace.testManualMotionEpisodePresentation.evidenceDisposition == nil)
    #expect(workspace.testManualMotionEpisodePresentation.jogControlsUnavailableReason == nil)
    #expect(workspace.motionRequestStatusPresentation == .ready)
    #expect(counter.count == 1)
    await workspace.shutdown()
  }

  @Test("SIMULATED ambiguity disables effects and records no automatic retry")
  func simulatedManualAmbiguityDisposition() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("manual-simulated-ambiguity-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let simulatedLearning = SimulatedLearningRuntime()
    let composition = PlotterManualMotionComposition.makeRuntimeComposition(
      journalFileURL: directory.appendingPathComponent("journal.json"),
      machineSession: nil,
      simulatedRuntime: simulatedLearning,
      simulatedExecutionPacing: SimulatedLearningInteractivePacing(stepDelay: .zero)
    )
    let workspace = PlotterApplicationRuntime(
      machineSession: nil,
      observationSession: CameraComposition.makeIsolatedObservationSessionForTesting(),
      manualMotionComposition: composition,
      penInteractionRuntime: nominalPenInteractionRuntime(
        manualMotionComposition: composition
      ),
      boundaryRuntime: nominalBoundaryRuntime(),
      drawingDraftRuntime: nominalDrawingDraftRuntime(),
      drawingRunComposition: nominalDrawingRunComposition(),
      incidentPackageUIService: nominalIncidentPackageUIService(),
      residualEffectPort: AuthorityTestResidualEffectPort(devices: []),
      serialDevices: [],
      observationPreferences: TestObservationPreferencePort()
    )
    await submitObservationConfigurationForTest(workspace, .selectSource(.simulated, nil))
    await submitControllerSession(workspace, .toggleConnection)
    await submitControllerSession(workspace, .toggleMotionAuthorization)

    let retainedOwner = EpisodeAuthorityID(rawValue: "test.simulatedAmbiguitySetup")
    await simulatedLearning.injectFault(.ambiguityBeforeNextBoundarySegment)
    let retainedAdmission = await composition.causalSimulatorEffectAdapter
      .admitRetainedWorkflowBoundary(
        direction: .positiveX,
        finiteSegmentLengthMM: 1,
        owner: retainedOwner
      )
    guard case let .admitted(retainedBoundary) = retainedAdmission else {
      Issue.record("Expected retained Boundary admission")
      return
    }
    #expect(retainedBoundary.attribution == .retainedWorkflow(owner: retainedOwner))
    let retainedOutcome = await composition.causalSimulatorEffectAdapter
      .executeBoundaryCooperatively(retainedBoundary)
    #expect(retainedOutcome.disposition == .failed)
    #expect(retainedOutcome.effectResult == nil)
    let causalTruthBeforeManualRefusal =
      await composition.causalSimulatorEffectAdapter.truthSnapshot()

    let intent = try manualAmbiguityJog()
    await workspace.submitManualMotionIntent(intent)
    let pending = workspace.testManualMotionEpisodePresentation
    let evidence = try #require(pending.evidenceDisposition)
    #expect(evidence.action.environment == .simulated)
    #expect(evidence.action.disposition == .acknowledgeAmbiguity)
    #expect(workspace.manualMotionEpisodeSnapshot?.projection.phase == .awaitingEvidence)
    #expect(pending.jogControlsUnavailableReason == evidence.remedy)
    #expect(pending.penUpUnavailableReason == evidence.remedy)
    #expect(pending.penDownUnavailableReason == evidence.remedy)
    #expect(workspace.manualMotionEpisodeSnapshot?.projection.lastTerminalEffect?.disposition
      == .ambiguous)
    let ambiguousEffectID = evidence.action.effectID

    await workspace.submitManualMotionIntent(intent)
    let blockedPen = try #require(
      workspace.testPlotterUIProjection().semantic.action(id: PlotterAppUIActionID.manualPenDown)
    )
    #expect(!blockedPen.isAvailable)
    #expect(workspace.testPlotterUIProjection().semantic.request(for: blockedPen.id) == nil)
    let causalTruthAfterBlockedActions =
      await composition.causalSimulatorEffectAdapter.truthSnapshot()
    #expect(causalTruthAfterBlockedActions == causalTruthBeforeManualRefusal)
    #expect(
      workspace.manualMotionEpisodeSnapshot?.projection.lastTerminalEffect?.result.context.effectID
        == ambiguousEffectID
    )
    await workspace.resolveTestManualMotionEvidence(using: evidence.action)
    #expect(workspace.manualMotionEpisodeSnapshot?.projection.phase == .ready)
    #expect(workspace.testManualMotionEpisodePresentation.evidenceDisposition == nil)
    #expect(workspace.testManualMotionEpisodePresentation.jogControlsUnavailableReason == nil)
    #expect((await simulatedLearning.snapshot()).currentOperation == nil)
    await workspace.shutdown()
  }

  @Test("workspace manual runtime and retained workflows share one causal adapter authority")
  func manualCompositionSharesCausalAdapterAuthority() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("manual-shared-causal-adapter-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let simulatedRuntime = SimulatedLearningRuntime()
    let pacing = FirstOperationSuspensionPacing()
    let composition = PlotterManualMotionComposition.makeRuntimeComposition(
      journalFileURL: directory.appendingPathComponent("journal.json"),
      machineSession: nil,
      simulatedRuntime: simulatedRuntime,
      simulatedExecutionPacing: pacing
    )
    let workspace = PlotterApplicationRuntime(
      machineSession: nil,
      observationSession: CameraComposition.makeIsolatedObservationSessionForTesting(),
      manualMotionComposition: composition,
      penInteractionRuntime: nominalPenInteractionRuntime(
        manualMotionComposition: composition
      ),
      boundaryRuntime: nominalBoundaryRuntime(),
      drawingDraftRuntime: nominalDrawingDraftRuntime(),
      drawingRunComposition: nominalDrawingRunComposition(),
      incidentPackageUIService: nominalIncidentPackageUIService(),
      residualEffectPort: AuthorityTestResidualEffectPort(devices: []),
      serialDevices: [],
      observationPreferences: TestObservationPreferencePort()
    )
    await submitObservationConfigurationForTest(workspace, .selectSource(.simulated, nil))
    await submitControllerSession(workspace, .toggleConnection)
    await submitControllerSession(workspace, .toggleMotionAuthorization)

    let manualOwner = Task { await workspace.submitTestManualJog(.xPositive) }
    await pacing.waitUntilSuspended()
    let retainedOwner = EpisodeAuthorityID(rawValue: "test.sharedCompositionRetainedTravel")
    let occupied = await composition.causalSimulatorEffectAdapter
      .admitRetainedWorkflowTravel(
        delta: try SimulatedLearningMotionVector(dxMM: 1, dyMM: 0),
        owner: retainedOwner
      )
    guard case let .refused(refusal) = occupied,
      case let .operationAlreadyActive(activeID) = refusal.refusal
    else {
      await pacing.resume()
      await manualOwner.value
      Issue.record("Expected the workspace manual owner to reserve the shared adapter")
      return
    }
    #expect(refusal.effectResult == nil)
    #expect(refusal.truth.controllerCommand?.id == activeID)

    await pacing.resume()
    await manualOwner.value
    let manualTruth = await composition.causalSimulatorEffectAdapter.truthSnapshot()
    #expect(manualTruth.controllerCommand == nil)
    #expect(manualTruth.plantPosition == (try SimulatedLearningMPos(xMM: 50, yMM: 0)))

    let successorAdmission = await composition.causalSimulatorEffectAdapter
      .admitRetainedWorkflowTravel(
        delta: try SimulatedLearningMotionVector(dxMM: 1, dyMM: 0),
        owner: retainedOwner
      )
    guard case let .admitted(successor) = successorAdmission else {
      Issue.record("Expected retained admission after the workspace manual owner settled")
      return
    }
    #expect(successor.attribution == .retainedWorkflow(owner: retainedOwner))
    let cancelled = await composition.causalSimulatorEffectAdapter.request(
      .cancel,
      for: successor
    )
    #expect(cancelled.effectResult == nil)
    await workspace.shutdown()
  }

  @Test("false applied local mode returns the native open receipt without transcript facts")
  func unrepresentableLocalModeOpenReceipt() async throws {
    try await assertUnrepresentableAppliedOpen(
      localModeEnabled: false,
      receiverEnabled: true
    )
  }

  @Test("false applied receiver mode returns the native open receipt without transcript facts")
  func unrepresentableReceiverOpenReceipt() async throws {
    try await assertUnrepresentableAppliedOpen(
      localModeEnabled: true,
      receiverEnabled: false
    )
  }

  private func assertUnrepresentableAppliedOpen(
    localModeEnabled: Bool,
    receiverEnabled: Bool
  ) async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("manual-motion-open-receipt-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try EpisodeRecordingStore.open(
      directoryURL: directory,
      recordingID: EpisodeRecordingID(rawValue: UUID()),
      schemaRevision: EpisodeRecordingSchemaRevision(rawValue: "manual-open-test-v1"),
      frameRetentionPolicy: EpisodeFrameRetentionPolicy(
        maximumUniqueFrameCount: 1,
        maximumTotalUniqueFrameBytes: 1
      )
    )
    let clock = SystemRuntimeClock()
    let baseLink = ManualMotionReceiptLink(
      clock: clock,
      localModeEnabled: localModeEnabled,
      receiverEnabled: receiverEnabled
    )
    let router = ManualMotionControllerRecordingRouter()
    let link = RecordingMachineLink(underlying: baseLink, router: router, clock: clock)
    let actions = manualMotionReceiptActions {
      let receipt = try? await link.open()
      guard case let .bsdSerial(applied)? = receipt?.appliedConfiguration else {
        Issue.record("Expected the unchanged native BSD open receipt")
        return
      }
      #expect(applied.localModeEnabled == localModeEnabled)
      #expect(applied.receiverEnabled == receiverEnabled)
    }
    let runtime = PlotterManualMotionComposition.makeRuntimeComposition(
      journalFileURL: directory.appendingPathComponent("manual-motion-journal.json"),
      machineSession: actions,
      simulatedRuntime: SimulatedLearningRuntime(),
      simulatedExecutionPacing: SimulatedLearningInteractivePacing(stepDelay: .zero),
      recordingStore: store,
      recordingRouter: router
    ).runtime
    _ = try await runtime.submit(
      .jog(try PlotterJogRequest(
        direction: .positiveX,
        distanceMM: 1,
        feedMMPerMinute: 100,
        routing: .relativeTravel
      )),
      capabilityFacts: liveManualMotionFacts(),
      environment: .live
    )
    try await waitUntilAsync { (await runtime.currentSnapshot()).activeOperation == nil }

    let runtimeSnapshot = await runtime.currentSnapshot()
    #expect(runtimeSnapshot.projection.lastTerminalEffect?.disposition == .completed)
    #expect(runtimeSnapshot.recordingDiagnostic?.contains("cannot be represented losslessly") == true)
    #expect((await store.snapshot()).entries.isEmpty)
  }

  @Test("workspace exposes exact terminal-publication recovery and cannot reissue an effect")
  func manualTerminalPublicationRecoveryPresentation() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("manual-workspace-recovery-\(UUID().uuidString)")
    let displaced = directory.appendingPathExtension("displaced")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: directory)
      try? FileManager.default.removeItem(at: displaced)
    }
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let actions = manualMotionWorkspaceActions(machine: machine)
    let simulated = SimulatedLearningRuntime()
    let composition = PlotterManualMotionComposition.makeRuntimeComposition(
      journalFileURL: directory.appendingPathComponent("manual-motion-journal.json"),
      machineSession: actions,
      simulatedRuntime: simulated,
      simulatedExecutionPacing: SimulatedLearningInteractivePacing(stepDelay: .zero)
    )
    let gate = PlotterManualMotionTerminalPublicationGate()
    await composition.runtime.installTerminalPublicationGateForTesting(gate)
    let workspace = PlotterApplicationRuntime(
      machineSession: actions,
      manualMotionComposition: composition,
      penInteractionRuntime: nominalPenInteractionRuntime(
        machineSession: actions,
        manualMotionComposition: composition
      ),
      boundaryRuntime: nominalBoundaryRuntime(),
      drawingDraftRuntime: nominalDrawingDraftRuntime(),
      drawingRunComposition: nominalDrawingRunComposition(),
      incidentPackageUIService: nominalIncidentPackageUIService(),
      residualEffectPort: AuthorityTestResidualEffectPort(devices: [machine.descriptor]),
      serialDevices: [machine.descriptor],
      observationPreferences: TestObservationPreferencePort()
    )
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    #expect(workspace.testManualMotionEpisodePresentation.jogControlsUnavailableReason == nil)

    let intent = PlotterManualMotionIntent.jog(try PlotterJogRequest(
      direction: .positiveX,
      distanceMM: 1,
      feedMMPerMinute: 100,
      routing: .relativeTravel
    ))
    let owner = Task { await workspace.submitManualMotionIntent(intent) }
    try await waitUntilAsync { await machine.relativeJogIsAwaitingSettlement }
    let originalEffectID = try #require(
      workspace.manualMotionEpisodeSnapshot?.activeOperation?.context.effectID
    )
    #expect(await machine.requestedFeeds.count == 1)
    await machine.settleRelativeJogNaturally()
    await gate.waitUntilPublicationIsHeld()
    try FileManager.default.moveItem(at: directory, to: displaced)
    gate.releasePublication()
    try await waitUntil {
      workspace.testManualMotionEpisodePresentation.publicationRecovery != nil
    }

    let pending = workspace.testManualMotionEpisodePresentation
    let recovery = try #require(pending.publicationRecovery)
    #expect(recovery.title == "Retry Manual Jog Publication")
    #expect(recovery.remedy.contains("jog command will not be issued again"))
    #expect(pending.stopAction == nil)
    #expect(pending.jogControlsUnavailableReason == recovery.remedy)
    #expect(pending.penUpUnavailableReason == recovery.remedy)
    #expect(pending.penDownUnavailableReason == recovery.remedy)
    #expect(workspace.motionRequestStatusPresentation == .needsAttention(recovery.remedy))
    let recoveryUI = workspace.testPlotterUIProjection()
    #expect(recoveryUI.controllerSession.controllerAttentionText == recovery.remedy)
    #expect(recoveryUI.manualMotion.controllerAlertText(
      recoveryUI.controllerSession.controllerAttentionText) == nil)
    let recoveryRequest = try #require(recoveryUI.semantic.request(for: PlotterAppUIActionID.manualRecovery))
    #expect(recoveryRequest.intent == .manualPublicationRecovery(capabilityID: recovery.capabilityID.rawValue))

    let blockedPen = try #require(
      workspace.testPlotterUIProjection().semantic.action(id: PlotterAppUIActionID.manualPenDown)
    )
    #expect(!blockedPen.isAvailable)
    #expect(workspace.testPlotterUIProjection().semantic.request(for: blockedPen.id) == nil)
    await workspace.submitManualMotionIntent(intent)
    #expect(await machine.requestedFeeds.count == 1)
    #expect(await machine.requestedPenCommands.isEmpty)
    #expect(workspace.manualMotionEpisodeSnapshot?.activeOperation?.context.effectID
      == originalEffectID)
    await workspace.recoverTestManualMotionPublication(
      capabilityID: PlotterManualMotionPublicationRecoveryCapabilityID()
    )
    #expect(workspace.testManualMotionEpisodePresentation.publicationRecovery?.capabilityID
      == recovery.capabilityID)

    try FileManager.default.moveItem(at: displaced, to: directory)
    await workspace.recoverTestManualMotionPublication(capabilityID: recovery.capabilityID)
    await owner.value

    let restored = workspace.testManualMotionEpisodePresentation
    #expect(restored.publicationRecovery == nil)
    #expect(restored.jogControlsUnavailableReason == nil)
    #expect(restored.penUpUnavailableReason == nil)
    #expect(restored.penDownUnavailableReason == nil)
    #expect(workspace.motionRequestStatusPresentation == .ready)
    #expect(await machine.requestedFeeds.count == 1)
    #expect(await machine.requestedPenCommands.isEmpty)
  }

  @Test("LIVE manual motion records exact MachineLink receipts only while operation-bound")
  func liveManualMotionReceiptRecording() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("manual-motion-receipts-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try EpisodeRecordingStore.open(
      directoryURL: directory,
      recordingID: EpisodeRecordingID(rawValue: UUID()),
      schemaRevision: EpisodeRecordingSchemaRevision(rawValue: "manual-motion-receipt-test-v1"),
      frameRetentionPolicy: EpisodeFrameRetentionPolicy(
        maximumUniqueFrameCount: 1,
        maximumTotalUniqueFrameBytes: 1
      )
    )
    let clock = SystemRuntimeClock()
    let baseLink = ManualMotionReceiptLink(clock: clock)
    let recordingRouter = ManualMotionControllerRecordingRouter()
    let link = RecordingMachineLink(
      underlying: baseLink,
      router: recordingRouter,
      clock: clock
    )
    let actions = ClosurePlotterMachineSession(
      select: { _ in throw ManualMotionReceiptTestError.unused },
      snapshot: { nil },
      requestPassiveProbe: { throw ManualMotionReceiptTestError.unused },
      requestControllerAlarmClear: { .refused(.noCurrentAlarmEvidence) },
      activateMotionGuard: { .refused(.notConnected) },
      deactivateMotionGuard: {},
      beginRelativeJog: { request in
        .admitted(RelativeJogOperation(id: UUID(), task: Task {
          do {
            _ = try await link.discardPendingInput()
            _ = try await link.write(MachineController.encodeRelativeJog(request))
            _ = try await link.read(maximumBytes: 64, timeoutNanoseconds: 250_000_000)
            return .acceptedThenCompleted(finalPosition: try! MachinePosition(x: 1, y: 0))
          } catch {
            return .ambiguous(.transport(String(describing: error)))
          }
        }))
      },
      beginDrawingStroke: { _ in .rejected(.refused(.notConnected)) },
      beginPenActuation: { _, _ in .rejected(.refused(.notConnected)) },
      beginBoundaryMotion: { request, _ in
        .rejected(.needsAttention(
          ownerID: request.ownerID,
          terminal: .refusal(.notConnected)
        ))
      },
      requestJogCancel: { _ in .refused(.noActiveJog) },
      disconnect: {}
    )
    let runtime = PlotterManualMotionComposition.makeRuntimeComposition(
      journalFileURL: directory.appendingPathComponent("manual-motion-journal.json"),
      machineSession: actions,
      simulatedRuntime: SimulatedLearningRuntime(),
      simulatedExecutionPacing: SimulatedLearningInteractivePacing(stepDelay: .zero),
      recordingStore: store,
      recordingRouter: recordingRouter
    ).runtime
    let intent = PlotterManualMotionIntent.jog(try PlotterJogRequest(
      direction: .positiveX,
      distanceMM: 1,
      feedMMPerMinute: 100,
      routing: .relativeTravel
    ))
    let submission = try await runtime.submit(
      intent,
      capabilityFacts: liveManualMotionFacts(),
      environment: .live
    )
    #expect(submission.disposition == .accepted)
    try await waitUntilAsync {
      let snapshot = await runtime.currentSnapshot()
      return snapshot.activeOperation == nil
    }

    let recorded = await store.snapshot()
    #expect(recorded.entries.count == 6)
    #expect(recorded.isComplete)
    #expect(recorded.entries.allSatisfy {
      $0.provenance.environment == .live
        && $0.provenance.episodeID != nil
        && $0.provenance.intentRequestID != nil
        && $0.provenance.effectID != nil
    })
    guard case let .controller(.invocation(discardInvocation)) = recorded.entries[0].record,
      case .discardInput = discardInvocation.operation
    else {
      Issue.record("expected exact discard invocation")
      return
    }
    guard case let .controller(.completion(discardCompletion)) = recorded.entries[1].record,
      case let .succeeded(.discardInput(discardedByteCount)) = discardCompletion.outcome
    else {
      Issue.record("expected exact discard receipt")
      return
    }
    #expect(discardCompletion.invocationID == discardInvocation.id)
    #expect(discardedByteCount == 2)
    guard case let .controller(.invocation(write)) = recorded.entries[2].record,
      case let .rawWrite(parameters) = write.operation,
      case let .controller(.completion(writeCompletion)) = recorded.entries[3].record,
      case let .succeeded(.rawWrite(writtenByteCount)) = writeCompletion.outcome
    else {
      Issue.record("expected exact write invocation and receipt")
      return
    }
    #expect(writtenByteCount == parameters.bytes.count)
    guard case let .controller(.invocation(read)) = recorded.entries[4].record,
      case let .timedRead(readParameters) = read.operation,
      case let .controller(.completion(readCompletion)) = recorded.entries[5].record,
      case let .succeeded(.timedRead(chunks, timedOut)) = readCompletion.outcome,
      let chunk = chunks.first
    else {
      Issue.record("expected exact timed-read invocation and receipt")
      return
    }
    #expect(readParameters.maximumByteCount == 64)
    #expect(readParameters.timeoutNanoseconds == 250_000_000)
    #expect(chunks.count == 1)
    #expect(chunk.bytes == Data("ok\n".utf8))
    #expect(!timedOut)
    #expect(chunk.monotonicOffsetNanoseconds >= recorded.entries[4].monotonicOffsetNanoseconds)
    #expect(chunk.monotonicOffsetNanoseconds <= recorded.entries[5].monotonicOffsetNanoseconds)

    _ = try await link.write(Data("?".utf8))
    #expect((await store.snapshot()).entries.count == 6)
  }

  @Test("LIVE recorder retains applied open and exact partial/close failures")
  func liveManualMotionFailureReceiptRecording() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("manual-motion-failure-receipts-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try EpisodeRecordingStore.open(
      directoryURL: directory,
      recordingID: EpisodeRecordingID(rawValue: UUID()),
      schemaRevision: EpisodeRecordingSchemaRevision(rawValue: "manual-motion-failure-test-v1"),
      frameRetentionPolicy: EpisodeFrameRetentionPolicy(
        maximumUniqueFrameCount: 1,
        maximumTotalUniqueFrameBytes: 1
      )
    )
    let clock = SystemRuntimeClock()
    let baseLink = ManualMotionFailureReceiptLink(clock: clock)
    let recordingRouter = ManualMotionControllerRecordingRouter()
    let link = RecordingMachineLink(
      underlying: baseLink,
      router: recordingRouter,
      clock: clock
    )
    let writeBytes = Data("G1 X1\n".utf8)
    let actions = manualMotionReceiptActions {
      _ = try? await link.open()
      try? await link.close()
      _ = try? await link.discardPendingInput()
      _ = try? await link.write(writeBytes)
      _ = try? await link.read(maximumBytes: 64, timeoutNanoseconds: 250_000_000)
    }
    let runtime = PlotterManualMotionComposition.makeRuntimeComposition(
      journalFileURL: directory.appendingPathComponent("manual-motion-journal.json"),
      machineSession: actions,
      simulatedRuntime: SimulatedLearningRuntime(),
      simulatedExecutionPacing: SimulatedLearningInteractivePacing(stepDelay: .zero),
      recordingStore: store,
      recordingRouter: recordingRouter
    ).runtime
    _ = try await runtime.submit(
      .jog(try PlotterJogRequest(
        direction: .positiveX,
        distanceMM: 1,
        feedMMPerMinute: 100,
        routing: .relativeTravel
      )),
      capabilityFacts: liveManualMotionFacts(),
      environment: .live
    )
    try await waitUntilAsync {
      (await runtime.currentSnapshot()).activeOperation == nil
    }

    let recorded = await store.snapshot()
    #expect(recorded.entries.count == 10)
    #expect(recorded.isComplete)

    guard case let .controller(.invocation(open)) = recorded.entries[0].record,
      case let .open(openParameters) = open.operation,
      case let .controller(.completion(openCompletion)) = recorded.entries[1].record,
      case .succeeded(.open) = openCompletion.outcome
    else {
      Issue.record("expected applied open receipt pair")
      return
    }
    #expect(openParameters.endpoint == "/dev/cu.manual-motion-failure")
    #expect(openParameters.baudRate == 115_200)
    #expect(openCompletion.invocationID == open.id)

    guard case let .controller(.invocation(close)) = recorded.entries[2].record,
      case .close = close.operation,
      case let .controller(.completion(closeCompletion)) = recorded.entries[3].record,
      case let .failed(closeFailure) = closeCompletion.outcome
    else {
      Issue.record("expected close failure receipt pair")
      return
    }
    #expect(closeFailure.kind == .inputOutput)
    #expect(closeFailure.systemCode == EIO)
    #expect(closeFailure.partialByteCount == 0)

    guard case let .controller(.completion(discardCompletion)) = recorded.entries[5].record,
      case let .failed(discardFailure) = discardCompletion.outcome
    else {
      Issue.record("expected partial discard failure")
      return
    }
    #expect(discardFailure.partialByteCount == 3)
    #expect(discardFailure.partialReadChunks.isEmpty)

    guard case let .controller(.invocation(write)) = recorded.entries[6].record,
      case let .rawWrite(writeParameters) = write.operation,
      case let .controller(.completion(writeCompletion)) = recorded.entries[7].record,
      case let .failed(writeFailure) = writeCompletion.outcome
    else {
      Issue.record("expected partial write failure")
      return
    }
    #expect(writeParameters.bytes == writeBytes)
    #expect(writeFailure.partialByteCount == 2)

    guard case let .controller(.completion(readCompletion)) = recorded.entries[9].record,
      case let .failed(readFailure) = readCompletion.outcome,
      let partialChunk = readFailure.partialReadChunks.first
    else {
      Issue.record("expected partial timed-read failure")
      return
    }
    #expect(readFailure.partialByteCount == 1)
    #expect(readFailure.partialReadChunks.count == 1)
    #expect(partialChunk.bytes == Data("o".utf8))
    #expect(partialChunk.monotonicOffsetNanoseconds
      >= recorded.entries[8].monotonicOffsetNanoseconds)
    #expect(partialChunk.monotonicOffsetNanoseconds
      <= recorded.entries[9].monotonicOffsetNanoseconds)
  }

  @Test("exact Stop remains inside the LIVE controller-recording lease")
  func liveManualMotionStopReceiptRecording() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("manual-motion-stop-receipt-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try EpisodeRecordingStore.open(
      directoryURL: directory,
      recordingID: EpisodeRecordingID(rawValue: UUID()),
      schemaRevision: EpisodeRecordingSchemaRevision(rawValue: "manual-motion-stop-test-v1"),
      frameRetentionPolicy: EpisodeFrameRetentionPolicy(
        maximumUniqueFrameCount: 1,
        maximumTotalUniqueFrameBytes: 1
      )
    )
    let clock = SystemRuntimeClock()
    let baseLink = ManualMotionReceiptLink(clock: clock)
    let recordingRouter = ManualMotionControllerRecordingRouter()
    let link = RecordingMachineLink(
      underlying: baseLink,
      router: recordingRouter,
      clock: clock
    )
    let operation = ManualMotionStopOperation()
    let actions = ClosurePlotterMachineSession(
      select: { _ in throw ManualMotionReceiptTestError.unused },
      snapshot: { nil },
      requestPassiveProbe: { throw ManualMotionReceiptTestError.unused },
      requestControllerAlarmClear: { .refused(.noCurrentAlarmEvidence) },
      activateMotionGuard: { .refused(.notConnected) },
      deactivateMotionGuard: {},
      beginRelativeJog: { _ in
        .admitted(RelativeJogOperation(id: UUID(), task: Task {
          await operation.waitForOutcome()
        }))
      },
      beginDrawingStroke: { _ in .rejected(.refused(.notConnected)) },
      beginPenActuation: { _, _ in .rejected(.refused(.notConnected)) },
      beginBoundaryMotion: { request, _ in
        .rejected(.needsAttention(
          ownerID: request.ownerID,
          terminal: .refusal(.notConnected)
        ))
      },
      requestJogCancel: { _ in
        do {
          _ = try await link.write(MachineController.encodeJogCancel)
          await operation.finishCancellation()
          return .completed(finalPosition: try! MachinePosition(x: 0, y: 0))
        } catch {
          return .ambiguous(.transport(String(describing: error)))
        }
      },
      disconnect: {}
    )
    let runtime = PlotterManualMotionComposition.makeRuntimeComposition(
      journalFileURL: directory.appendingPathComponent("manual-motion-journal.json"),
      machineSession: actions,
      simulatedRuntime: SimulatedLearningRuntime(),
      simulatedExecutionPacing: SimulatedLearningInteractivePacing(stepDelay: .zero),
      recordingStore: store,
      recordingRouter: recordingRouter
    ).runtime
    let submission = try await runtime.submit(
      .jog(try PlotterJogRequest(
        direction: .positiveX,
        distanceMM: 1,
        feedMMPerMinute: 100,
        routing: .relativeTravel
      )),
      capabilityFacts: liveManualMotionFacts(),
      environment: .live
    )
    let stopCapability = try #require(submission.snapshot.activeOperation?.stopCapabilityID)
    let stopped = await runtime.stop(using: stopCapability)
    #expect(stopped.disposition == .settled)

    let recorded = await store.snapshot()
    #expect(recorded.entries.count == 2)
    #expect(recorded.isComplete)
    guard case let .controller(.invocation(invocation)) = recorded.entries[0].record,
      case let .rawWrite(parameters) = invocation.operation,
      case let .controller(.completion(completion)) = recorded.entries[1].record,
      case let .succeeded(.rawWrite(writtenByteCount)) = completion.outcome
    else {
      Issue.record("expected exact Stop write receipt pair")
      return
    }
    #expect(parameters.bytes == MachineController.encodeJogCancel)
    #expect(writtenByteCount == MachineController.encodeJogCancel.count)
    #expect(completion.invocationID == invocation.id)

    _ = try await link.write(Data("?".utf8))
    #expect((await store.snapshot()).entries.count == 2)
  }

  @Test("Center arrival accepts reproduced controller quantization residual")
  func centerArrivalAcceptsQuantizedSettlement() async throws {
    let target = try MachinePosition(x: 0, y: 0)
    let reproduced = try MachinePosition(x: 0.012, y: 0.011)
    #expect(MachinePositionAcceptancePolicy.toleranceMM == 1.0)
    #expect(MachinePositionAcceptancePolicy.accepts(reproduced, target: target))

    let log = EventLog()
    let machine = try LowerMachineSessionFixture(
      log: log,
      relativeJogSettlementOffset: try Vector2(dx: 0.012, dy: 0.011)
    )
    let camera = try TestObservationCameraSession()
    let boundaryRuntimeAccess = TestBoundaryRuntimeAccess()
    let workspace = plotterApplicationRuntime(
      machine: machine,
      camera: camera,
      boundaryRuntimeAccess: boundaryRuntimeAccess,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    let prerequisitePenOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await workspace.performTestExerciseAction(.start, for: prerequisitePenOwner)
    let prerequisitePenRequest = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let prerequisitePenFrame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(workspace, request: prerequisitePenRequest, point: try Point2(
      x: Double(prerequisitePenFrame.frame.width - 1) / 2,
      y: Double(prerequisitePenFrame.frame.height - 1) / 2
    ))
    try await waitUntil { workspace.activeDiscoverySequenceID == .penInteraction }
    for _ in 0..<3 { await workspace.performTestExerciseAction(.choice(.yes), for: prerequisitePenOwner) }
    #expect(workspace.penInteractionCompleted)
    try await installAcceptedBoundaryTestProjection(
      runtime: try #require(boundaryRuntimeAccess.runtime),
      workspace: workspace,
      environment: .live,
      centerArrivalIsAccepted: false
    )
    try await machine.setPosition(x: 100, y: 50)
    await submitControllerSession(workspace, .requestPassiveProbe)

    let owner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    let automaticRequestsBeforeCenterTravel = camera.recordedAutomaticInspectionRequests
    try requireEnabledPublicAction(
      .boundary(.moveToEstimatedCenter(retry: false)),
      owner: owner,
      workspace: workspace
    )
    await workspace.performTestExerciseAction(
      .boundary(.moveToEstimatedCenter(retry: false)),
      for: owner
    )
    try await BoundaryCenterArrivalObservationWaiter(workspace: workspace).wait()

    #expect(camera.recordedAutomaticInspectionRequests == automaticRequestsBeforeCenterTravel)
    #expect(workspace.exactWorkflowVisionOwner == nil)
    #expect(workspace.testCenterArrivalPosition == reproduced)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .centerArrival) != nil)
    #expect(!workspace.testBoundaryCenterArrivalRetryRequired)
    #expect(
      workspace.testCurrentLearningPathItemID
        == .humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    )
  }

  @Test("Out-of-tolerance center settlement offers center-only retry")
  func centerArrivalRejectsOutsideToleranceWithoutBoundaryRestart() async throws {
    let target = try MachinePosition(x: 0, y: 0)
    let outside = try MachinePosition(x: 1.001, y: 0)
    #expect(!MachinePositionAcceptancePolicy.accepts(outside, target: target))

    let log = EventLog()
    let machine = try LowerMachineSessionFixture(
      log: log,
      relativeJogSettlementOffset: try Vector2(dx: 1.001, dy: 0)
    )
    let camera = try TestObservationCameraSession()
    let boundaryRuntimeAccess = TestBoundaryRuntimeAccess()
    let workspace = plotterApplicationRuntime(
      machine: machine,
      camera: camera,
      boundaryRuntimeAccess: boundaryRuntimeAccess,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    let prerequisitePenOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await workspace.performTestExerciseAction(.start, for: prerequisitePenOwner)
    let prerequisitePenRequest = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let prerequisitePenFrame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(workspace, request: prerequisitePenRequest, point: try Point2(
      x: Double(prerequisitePenFrame.frame.width - 1) / 2,
      y: Double(prerequisitePenFrame.frame.height - 1) / 2
    ))
    try await waitUntil { workspace.activeDiscoverySequenceID == .penInteraction }
    for _ in 0..<3 { await workspace.performTestExerciseAction(.choice(.yes), for: prerequisitePenOwner) }
    #expect(workspace.penInteractionCompleted)
    try await installAcceptedBoundaryTestProjection(
      runtime: try #require(boundaryRuntimeAccess.runtime),
      workspace: workspace,
      environment: .live,
      centerArrivalIsAccepted: false
    )
    try await machine.setPosition(x: 100, y: 50)
    await submitControllerSession(workspace, .requestPassiveProbe)
    let acceptedAggregates = workspace.testAcceptedBoundaryAggregates
    let acceptedCenter = workspace.testEstimatedMachineCenter

    let owner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    try requireEnabledPublicAction(
      .boundary(.moveToEstimatedCenter(retry: false)),
      owner: owner,
      workspace: workspace
    )
    await workspace.performTestExerciseAction(
      .boundary(.moveToEstimatedCenter(retry: false)),
      for: owner
    )
    try await BoundaryCenterArrivalObservationWaiter(
      workspace: workspace,
      goal: .retryRequired
    ).wait()

    #expect(workspace.testCenterArrivalPosition == nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .centerArrival) == nil)
    #expect(workspace.testAcceptedBoundaryAggregates == acceptedAggregates)
    #expect(workspace.testEstimatedMachineCenter == acceptedCenter)
    #expect(workspace.testBoundaryCenterArrivalRetryRequired)
    #expect(workspace.restartableExerciseItemID == nil)
    let recovery = try #require(workspace.currentExerciseActionStripPresentation)
    #expect(recovery.actions.map(\.kind) == [.boundary(.moveToEstimatedCenter(retry: true))])
    #expect(recovery.actions.map(\.title) == ["Retry Center Arrival"])
  }

  @Test("source-indexed sessions preserve LIVE and replace SIMULATED independently")
  func simulatedLearningDoesNotReplaceLiveAuthority() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let workspace = plotterApplicationRuntime(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    let prerequisitePenOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await workspace.performTestExerciseAction(.start, for: prerequisitePenOwner)
    let prerequisitePenRequest = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let prerequisitePenFrame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(workspace, request: prerequisitePenRequest, point: try Point2(
      x: Double(prerequisitePenFrame.frame.width - 1) / 2,
      y: Double(prerequisitePenFrame.frame.height - 1) / 2
    ))
    try await waitUntil { workspace.activeDiscoverySequenceID == .penInteraction }
    for _ in 0..<3 { await workspace.performTestExerciseAction(.choice(.yes), for: prerequisitePenOwner) }
    #expect(workspace.penInteractionCompleted)
    let boundaryOwner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    try await submitRenderedBoundaryAcquisition(
      .positiveY,
      owner: boundaryOwner,
      workspace: workspace
    )
    _ = await machine.waitForBoundaryRequest(count: 1)
    try await submitRenderedBoundaryStop(owner: boundaryOwner, workspace: workspace)

    let livePenRevisionID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id
    )
    let liveBoundaryRevisionID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveY))?.id
    )
    await submitObservationConfigurationForTest(workspace, .selectSource(.simulated, nil))
    #expect(workspace.learningArtifactGraph.currentRevision(for: .penInteraction) == nil)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveY))
        == nil
    )
    workspace.selectedDiscoverySequenceID = .boundaryNegativeX

    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id == livePenRevisionID
    )
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveY))?.id
        == liveBoundaryRevisionID
    )
    await submitObservationConfigurationForTest(workspace, .selectSource(.simulated, nil))
    #expect(workspace.learningArtifactGraph.currentRevision(for: .penInteraction) == nil)
    #expect(workspace.discoveryTransactions.isEmpty)
    #expect(workspace.selectedDiscoverySequenceID == .penInteraction)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id == livePenRevisionID
    )
    await workspace.shutdown()
  }

  @Test("logical boundary owner exposes Stop without a moving-state timer or natural success")
  func boundaryOwnerDoesNotAssumeMovingOrNaturalSuccess() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log, reportsBoundaryMoving: false)
    let camera = try TestObservationCameraSession()
    let workspace = plotterApplicationRuntime(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    let prerequisitePenOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await workspace.performTestExerciseAction(.start, for: prerequisitePenOwner)
    let prerequisitePenRequest = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let prerequisitePenFrame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(workspace, request: prerequisitePenRequest, point: try Point2(
      x: Double(prerequisitePenFrame.frame.width - 1) / 2,
      y: Double(prerequisitePenFrame.frame.height - 1) / 2
    ))
    try await waitUntil { workspace.activeDiscoverySequenceID == .penInteraction }
    for _ in 0..<3 { await workspace.performTestExerciseAction(.choice(.yes), for: prerequisitePenOwner) }
    #expect(workspace.penInteractionCompleted)

    let boundaryOwner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    try await submitRenderedBoundaryAcquisition(
      .negativeY,
      owner: boundaryOwner,
      workspace: workspace
    )
    _ = await machine.waitForBoundaryRequest(count: 1)

    #expect(workspace.machineSnapshot?.machine.connection == .connected)
    #expect(workspace.testAcceptedBoundaryEvidence.isEmpty)
    #expect(workspace.testAcceptedBoundaryAggregates.isEmpty)
    try await submitRenderedBoundaryStop(owner: boundaryOwner, workspace: workspace)
    #expect(workspace.testAcceptedBoundaryEvidence.count == 1)
    await workspace.shutdown()
  }

  @Test("invalid manual step text does not gate Boundary Discovery")
  func manualStepTextIsNotBoundaryAuthority() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let workspace = plotterApplicationRuntime(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    let prerequisitePenOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await workspace.performTestExerciseAction(.start, for: prerequisitePenOwner)
    let prerequisitePenRequest = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let prerequisitePenFrame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(workspace, request: prerequisitePenRequest, point: try Point2(
      x: Double(prerequisitePenFrame.frame.width - 1) / 2,
      y: Double(prerequisitePenFrame.frame.height - 1) / 2
    ))
    try await waitUntil { workspace.activeDiscoverySequenceID == .penInteraction }
    for _ in 0..<3 { await workspace.performTestExerciseAction(.choice(.yes), for: prerequisitePenOwner) }
    #expect(workspace.penInteractionCompleted)
    var manualDraft = ManualMotionDraft()
    manualDraft.xDistanceMM = "not-a-number"
    manualDraft.yDistanceMM = ""

    #expect(
      workspace.testPlotterUIProjection(manualDraft: manualDraft)
        .manualMotion.jogControlsUnavailableReason != nil
    )
    #expect(workspace.discoveryStartUnavailableReason(for: .boundaryPositiveX) == nil)
    let boundaryOwner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    try await submitRenderedBoundaryAcquisition(
      .positiveX,
      owner: boundaryOwner,
      workspace: workspace
    )
    _ = await machine.waitForBoundaryRequest(count: 1)
    try await submitRenderedBoundaryStop(owner: boundaryOwner, workspace: workspace)
    #expect(workspace.testAcceptedBoundaryEvidence.count == 1)
    await workspace.shutdown()
  }

  @Test("Boundary names connection and Motion as external dependencies")
  func boundaryExternalDependencyBlockers() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log, motionGuardInitiallyActive: false)
    let workspace = plotterApplicationRuntime(machine: machine, log: log)
    let connectionBlocker =
      "Blocked by controller connection. Use Connect for the selected plotter in the workbench toolbar; Enable Motion depends on a connected session."
    let motionBlocker =
      "Blocked by Motion authorization. Use Enable Motion in the workbench toolbar for this connected session."

    #expect(
      workspace.discoveryStartUnavailableReason(for: .boundaryPositiveX)
        == connectionBlocker
    )

    await submitControllerSession(
      workspace,
      .selectSerialDevice(controllerDevice(machine.descriptor))
    )
    await submitControllerSession(workspace, .toggleConnection)

    #expect(
      workspace.discoveryStartUnavailableReason(for: .boundaryPositiveX)
        == motionBlocker
    )

    await submitControllerSession(workspace, .toggleMotionAuthorization)

    #expect(workspace.discoveryStartUnavailableReason(for: .boundaryPositiveX) == nil)
    await workspace.shutdown()
  }

  @Test("shutdown stops an active boundary before draining and erasing its authority")
  func authorityClearingStopsBeforeErasure() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let workspace = plotterApplicationRuntime(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    let prerequisitePenOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await workspace.performTestExerciseAction(.start, for: prerequisitePenOwner)
    let prerequisitePenRequest = try #require(
      workspace.testActionSurfacePresentation.pointSelectionRequest)
    let prerequisitePenFrame = try #require(
      workspace.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(
      workspace,
      request: prerequisitePenRequest,
      point: try Point2(
        x: Double(prerequisitePenFrame.frame.width - 1) / 2,
        y: Double(prerequisitePenFrame.frame.height - 1) / 2
      )
    )
    try await waitUntil { workspace.activeDiscoverySequenceID == .penInteraction }
    for _ in 0..<3 {
      await workspace.performTestExerciseAction(.choice(.yes), for: prerequisitePenOwner)
    }
    #expect(workspace.penInteractionCompleted)
    let boundaryOwner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    try await submitRenderedBoundaryAcquisition(
      .negativeY,
      owner: boundaryOwner,
      workspace: workspace
    )
    _ = await machine.waitForBoundaryRequest(count: 1)
    await workspace.shutdown()

    #expect(await machine.cancelCount == 1)
    #expect(await machine.cancelIntents == [.shutdown])
    #expect(await machine.requestedFeeds.last == 500)
    #expect(workspace.discoveryTransactions[.penInteraction]?.state == .succeeded)
    #expect(workspace.discoveryTransactions.values.allSatisfy { $0.state != .active })
    #expect(
      [
        DiscoverySequenceID.boundaryNegativeX,
        .boundaryPositiveX,
        .boundaryNegativeY,
        .boundaryPositiveY,
      ].allSatisfy { workspace.discoveryTransactions[$0] == nil }
    )
    #expect(workspace.currentBoundarySnapshot?.projection.reference.operationID == nil)
    #expect(workspace.currentBoundarySnapshot?.projection.cancellationCapabilityID == nil)
    #expect(
      workspace.selectedOperatorActionPresentation(for: boundaryOwner).actionStrip?.actions
        .contains { if case .boundary(.stop(_)) = $0.kind { return true }; return false } == false
    )
    #expect(workspace.isShutdown)
  }

  @Test(
    "announcement failure is advisory and Exercise 1.1 preserves output-before-actuation order")
  func announcementFailureDoesNotGatePenInteraction() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let speechAnnouncer = ScriptedSpeechAnnouncer(
      log: log,
      outcomes: [.failed("output unavailable"), .completed]
    )
    let workspace = plotterApplicationRuntime(
      machine: machine,
      camera: camera,
      speechAnnouncer: speechAnnouncer,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    let prerequisitePenOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await workspace.performTestExerciseAction(.start, for: prerequisitePenOwner)
    let prerequisitePenRequest = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let prerequisitePenFrame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(workspace, request: prerequisitePenRequest, point: try Point2(
      x: Double(prerequisitePenFrame.frame.width - 1) / 2,
      y: Double(prerequisitePenFrame.frame.height - 1) / 2
    ))
    try await waitUntil { workspace.activeDiscoverySequenceID == .penInteraction }
    for _ in 0..<3 { await workspace.performTestExerciseAction(.choice(.yes), for: prerequisitePenOwner) }
    #expect(workspace.penInteractionCompleted)

    #expect(workspace.penInteractionCompleted)
    let events = await log.values
    #expect(
      events.firstIndex(of: "announce:Lowering the pen.")! < events.firstIndex(
        of: "machine:pen-lower")!)
    #expect(
      events.firstIndex(of: "announce:Raising the pen.")! < events.firstIndex(
        of: "machine:pen-raise")!)
    #expect(workspace.lastAnnouncementResultText.contains("Announcement dispatched"))
    await workspace.shutdown()
  }

  @Test("held speech playback does not delay the Pen command or next prompt")
  func heldSpeechDoesNotGatePenTransition() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let speech = HeldSpeechAnnouncer()
    let workspace = plotterApplicationRuntime(
      machine: machine,
      camera: camera,
      speechAnnouncer: speech,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await workspace.performTestExerciseAction(.start, for: owner)
    let request = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let frame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(workspace, request: request, point: try Point2(
      x: Double(frame.frame.width - 1) / 2,
      y: Double(frame.frame.height - 1) / 2
    ))
    try await waitUntil { workspace.activeDiscoverySequenceID == .penInteraction }

    let confirmed = Task {
      await workspace.performTestExerciseAction(.choice(.yes), for: owner)
    }
    await speech.waitUntilStarted()
    try await waitUntilAsync {
      await log.values.contains("machine:pen-lower")
    }
    _ = await confirmed.value

    #expect(
      workspace.discoveryTransactions[.penInteraction]?.currentStep?.action
        == .awaitPhysicalPenConfirmation(
          .down,
          question: DiscoverySequenceCatalog.definition(for: .penInteraction).questions[1]
        )
    )
    #expect(await speech.currentStartCount == 1)
    await speech.releaseAll()
    await workspace.shutdown()
  }

  @Test("review projections are inert and preserve the runtime current owner")
  func reviewProjectionIsInert() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let workspace = plotterApplicationRuntime(machine: machine, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)

    let current = workspace.testCurrentLearningPathItemID
    let transactionCount = workspace.discoveryTransactions.count
    let revisionCount = workspace.learningArtifactGraph.revisions.count
    let requestedFeedCount = await machine.requestedFeeds.count
    for itemID in LearningPathItemID.navigationOrder {
      _ = workspace.selectedOperatorActionPresentation(for: itemID)
    }

    #expect(workspace.testCurrentLearningPathItemID == current)
    #expect(workspace.discoveryTransactions.count == transactionCount)
    #expect(workspace.learningArtifactGraph.revisions.count == revisionCount)
    #expect(await machine.requestedFeeds.count == requestedFeedCount)
    #expect(await machine.cancelCount == 0)
    #expect(
      workspace.learningPathItemPresentations.first {
        $0.id == .stage(.humanGuidedDiscovery)
      }?.status == .current
    )
    #expect(
      workspace.learningPathItemPresentations.first {
        $0.id == .humanGuidedDiscovery(.penInteraction)
      }?.status == .current
    )
    #expect(!LearningPathItemID.navigationOrder.contains { $0.number == "5" })
    await workspace.shutdown()
  }

  @Test("Boundary Cancel is unavailable until its movement owner settles")
  func boundaryCancelUnavailableDuringMotion() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let workspace = plotterApplicationRuntime(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    let prerequisitePenOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await workspace.performTestExerciseAction(.start, for: prerequisitePenOwner)
    let prerequisitePenRequest = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let prerequisitePenFrame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(workspace, request: prerequisitePenRequest, point: try Point2(
      x: Double(prerequisitePenFrame.frame.width - 1) / 2,
      y: Double(prerequisitePenFrame.frame.height - 1) / 2
    ))
    try await waitUntil { workspace.activeDiscoverySequenceID == .penInteraction }
    for _ in 0..<3 { await workspace.performTestExerciseAction(.choice(.yes), for: prerequisitePenOwner) }
    #expect(workspace.penInteractionCompleted)

    let owner = LearningPathItemID.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    try await submitRenderedBoundaryAcquisition(
      .negativeX,
      owner: owner,
      workspace: workspace
    )
    _ = await machine.waitForBoundaryRequest(count: 1)
    #expect(
      workspace.currentExerciseActionStripPresentation?.actions.contains(where: {
        $0.kind == .cancel
      }) == false
    )
    let cancelID = learningActionID(.cancel, owner: owner)
    let activeProjection = workspace.testPlotterUIProjection(
      selectedItemID: owner,
      includesLearningPath: true
    ).semantic
    #expect(activeProjection.action(id: cancelID) == nil)
    #expect(activeProjection.request(for: cancelID) == nil)

    #expect(await machine.cancelIntents.isEmpty)
    #expect(workspace.testAcceptedBoundaryEvidence.isEmpty)
    #expect(workspace.testAcceptedBoundaryAggregates.isEmpty)
    #expect(workspace.currentBoundarySnapshot?.projection.reference.operationID != nil)
    try await submitRenderedBoundaryStop(owner: owner, workspace: workspace)
    await workspace.shutdown()
  }

}

private enum ManualMotionReceiptTestError: Error {
  case unused
}

private actor ManualMotionReceiptLink: MachineLink {
  nonisolated let descriptor = MachineLinkDescriptor(
    identifier: "manual-motion-receipt-link",
    displayName: "Manual Motion Receipt Link",
    bsdPath: "/dev/cu.manual-motion-receipt",
    transport: .bsdSerial
  )
  private let clock: any RuntimeClock
  private let localModeEnabled: Bool
  private let receiverEnabled: Bool

  init(
    clock: any RuntimeClock,
    localModeEnabled: Bool = true,
    receiverEnabled: Bool = true
  ) {
    self.clock = clock
    self.localModeEnabled = localModeEnabled
    self.receiverEnabled = receiverEnabled
  }

  func open() async throws -> MachineLinkOpenReceipt {
    MachineLinkOpenReceipt(appliedConfiguration: .bsdSerial(
      MachineLinkBSDSerialAppliedConfiguration(
        endpoint: descriptor.identifier,
        inputBaudRate: 115_200,
        outputBaudRate: 115_200,
        dataBits: 8,
        stopBits: 1,
        parity: .none,
        flowControl: .none,
        localModeEnabled: localModeEnabled,
        receiverEnabled: receiverEnabled
      )
    ))
  }

  func close() async throws {}

  func discardPendingInput() async throws -> MachineLinkDiscardReceipt {
    MachineLinkDiscardReceipt(discardedByteCount: 2)
  }

  func write(_ bytes: Data) async throws -> MachineLinkWriteReceipt {
    MachineLinkWriteReceipt(writtenByteCount: bytes.count)
  }

  func read(
    maximumBytes _: Int,
    timeoutNanoseconds _: UInt64
  ) async throws -> MachineLinkReadReceipt {
    MachineLinkReadReceipt(
      bytes: Data("ok\n".utf8),
      receivedAtMonotonicNanoseconds: clock.nowNanoseconds()
    )
  }
}

private actor ManualMotionFailureReceiptLink: MachineLink {
  nonisolated let descriptor = MachineLinkDescriptor(
    identifier: "manual-motion-failure-link",
    displayName: "Manual Motion Failure Link",
    bsdPath: "/dev/cu.manual-motion-failure",
    transport: .bsdSerial
  )
  private let clock: any RuntimeClock

  init(clock: any RuntimeClock) {
    self.clock = clock
  }

  func open() async throws -> MachineLinkOpenReceipt {
    MachineLinkOpenReceipt(appliedConfiguration: .bsdSerial(
      MachineLinkBSDSerialAppliedConfiguration(
        endpoint: descriptor.bsdPath!,
        inputBaudRate: 115_200,
        outputBaudRate: 115_200,
        dataBits: 8,
        stopBits: 1,
        parity: .none,
        flowControl: .none,
        localModeEnabled: true,
        receiverEnabled: true
      )
    ))
  }

  func close() async throws {
    throw MachineLinkError.operatingSystem(code: EIO, operation: "close")
  }

  func discardPendingInput() async throws -> MachineLinkDiscardReceipt {
    throw MachineLinkError.discardFailed(
      discarded: 3,
      total: 5,
      reason: .operatingSystem(code: EIO, operation: "discard input read")
    )
  }

  func write(_ bytes: Data) async throws -> MachineLinkWriteReceipt {
    throw MachineLinkError.writeFailed(
      bytesWritten: 2,
      totalBytes: bytes.count,
      reason: .operatingSystem(code: EIO, operation: "write")
    )
  }

  func read(
    maximumBytes: Int,
    timeoutNanoseconds _: UInt64
  ) async throws -> MachineLinkReadReceipt {
    throw MachineLinkError.readFailed(
      partialReceipts: [MachineLinkReadReceipt(
        bytes: Data("o".utf8),
        receivedAtMonotonicNanoseconds: clock.nowNanoseconds()
      )],
      maximumBytes: maximumBytes,
      reason: .timedOut
    )
  }
}

private func manualAmbiguityJog() throws -> PlotterManualMotionIntent {
  .jog(try PlotterJogRequest(
    direction: .positiveX,
    distanceMM: 1,
    feedMMPerMinute: 100,
    routing: .relativeTravel
  ))
}

private final class ManualMotionAmbiguousInvocationCounter: Sendable {
  private let state = OSAllocatedUnfairLock(initialState: 0)
  var count: Int { state.withLock { $0 } }
  func increment() { state.withLock { $0 += 1 } }
}

private actor ManualMotionStopOperation {
  private var outcome: MotionOutcome?
  private var waiters: [CheckedContinuation<MotionOutcome, Never>] = []

  func waitForOutcome() async -> MotionOutcome {
    if let outcome { return outcome }
    return await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func finishCancellation() {
    guard outcome == nil else { return }
    let value = MotionOutcome.cancelled(finalPosition: try! MachinePosition(x: 0, y: 0))
    outcome = value
    let current = waiters
    waiters.removeAll()
    current.forEach { $0.resume(returning: value) }
  }
}

private func manualMotionReceiptActions(
  operation: @escaping @Sendable () async -> Void
) -> (any PlotterMachineSession) {
  ClosurePlotterMachineSession(
    select: { _ in throw ManualMotionReceiptTestError.unused },
    snapshot: { nil },
    requestPassiveProbe: { throw ManualMotionReceiptTestError.unused },
    requestControllerAlarmClear: { .refused(.noCurrentAlarmEvidence) },
    activateMotionGuard: { .refused(.notConnected) },
    deactivateMotionGuard: {},
    beginRelativeJog: { _ in
      .admitted(RelativeJogOperation(id: UUID(), task: Task {
        await operation()
        return .acceptedThenCompleted(finalPosition: try! MachinePosition(x: 1, y: 0))
      }))
    },
    beginDrawingStroke: { _ in .rejected(.refused(.notConnected)) },
    beginPenActuation: { _, _ in .rejected(.refused(.notConnected)) },
    beginBoundaryMotion: { request, _ in
      .rejected(.needsAttention(
        ownerID: request.ownerID,
        terminal: .refusal(.notConnected)
      ))
    },
    requestJogCancel: { _ in .refused(.noActiveJog) },
    disconnect: {}
  )
}

@MainActor
private final class BoundaryCenterArrivalObservationWaiter {
  enum Goal {
    case accepted
    case retryRequired
  }

  private enum WaitError: Error {
    case timedOut
  }

  private let workspace: PlotterApplicationRuntime
  private let goal: Goal
  private var continuation: CheckedContinuation<Void, any Error>?
  private var deadlineTask: Task<Void, Never>?

  init(workspace: PlotterApplicationRuntime, goal: Goal = .accepted) {
    self.workspace = workspace
    self.goal = goal
  }

  func wait() async throws {
    try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      observe()
      deadlineTask = Task { @MainActor [weak self] in
        do {
          try await ContinuousClock().sleep(for: .seconds(2))
        } catch {
          return
        }
        self?.finish(.failure(WaitError.timedOut))
      }
    }
  }

  private func observe() {
    guard continuation != nil else { return }
    let arrived = withObservationTracking {
      _ = workspace.semanticPresentationRevision
      let projection = workspace.currentBoundarySnapshot?.projection
      switch goal {
      case .accepted:
        return workspace.testCenterArrivalPosition != nil
          && workspace.learningArtifactGraph.currentRevision(for: .centerArrival) != nil
      case .retryRequired:
        return projection?.terminal?.activity == .centerArrival
          && projection?.reference.operationID == nil
          && projection?.cancellationCapabilityID == nil
          && projection?.centerArrivalRetryRequired == true
      }
    } onChange: { [weak self] in
      Task { @MainActor in self?.observe() }
    }
    if arrived {
      finish(.success(()))
    }
  }

  private func finish(_ result: Result<Void, any Error>) {
    guard let continuation else { return }
    self.continuation = nil
    deadlineTask?.cancel()
    deadlineTask = nil
    continuation.resume(with: result)
  }
}

private func manualMotionWorkspaceActions(
  machine: LowerMachineSessionFixture,
  beginRelativeJog: (@Sendable (RelativeJogRequest) async -> RelativeJogAdmission)? = nil
) -> (any PlotterMachineSession) {
  ClosurePlotterMachineSession(
    select: { _ in await machine.snapshot() },
    snapshot: { await machine.snapshot() },
    requestPassiveProbe: { await machine.passiveProbeResult() },
    requestControllerAlarmClear: { .refused(.noCurrentAlarmEvidence) },
    activateMotionGuard: { await machine.activateMotionGuard() },
    deactivateMotionGuard: { await machine.deactivateMotionGuard() },
    beginRelativeJog: { request in
      if let beginRelativeJog { return await beginRelativeJog(request) }
      return .admitted(RelativeJogOperation(
        id: UUID(),
        task: Task { await machine.performRelativeMotion(request) }
      ))
    },
    beginDrawingStroke: { request in
      .admitted(DrawingStrokeOperation(
        id: UUID(),
        task: Task { await machine.requestDrawingStroke(request) }
      ))
    },
    beginPenActuation: { command, profile in
      .admitted(PenActuationOperation(
        id: UUID(),
        task: Task { await machine.requestPen(command, profile: profile) }
      ))
    },
    beginBoundaryMotion: { request, _ in
      .admitted(BoundaryMotionOperation(
        ownerID: request.ownerID,
        task: Task { await machine.requestBoundaryMotion(request) }
      ))
    },
    requestJogCancel: { await machine.cancel(intent: $0) },
    disconnect: {}
  )
}

private func liveManualMotionFacts() -> [PlotterCapabilityFact] {
  let owner = EpisodeAuthorityID(rawValue: "MachineController")
  let revision = CapabilityFactRevision(rawValue: 1)
  return [
    .connection(PlotterConnectionFact(
      owner: owner,
      revision: revision,
      environment: .live,
      isConnected: true
    )),
    .motion(PlotterMotionFact(
      owner: owner,
      revision: revision,
      environment: .live,
      isEnabled: true
    )),
    .pose(PlotterPoseFact(
      owner: owner,
      revision: revision,
      environment: .live,
      machinePosition: try? Point2(x: 0, y: 0),
      isSettled: true,
      settlementPolicyRevision: EpisodeRevisionIdentifier(
        rawValue: "manual-receipt-settlement-v1"
      )
    )),
    .manualController(PlotterManualControllerFact(
      owner: owner,
      revision: revision,
      environment: .live,
      penState: .raised,
      operationIsActive: false,
      penActuationProfileRevision: EpisodeRevisionIdentifier(
        rawValue: "manual-receipt-pen-profile-v1"
      )
    )),
  ]
}

private struct AuthorityTestResidualEffectPort: PlotterApplicationResidualEffectPort {
  let discovery: PlotterFixedSerialDeviceDiscoveryAdapter

  init(devices: [MachineLinkDescriptor]) {
    discovery = PlotterFixedSerialDeviceDiscoveryAdapter(devices: devices)
  }

  func discoverSerialDevices() -> [MachineLinkDescriptor] {
    discovery.discoverSerialDevices()
  }
}
