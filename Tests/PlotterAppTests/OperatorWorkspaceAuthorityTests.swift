import EpisodeCore
import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterTestSupport
import Testing
import os

@testable import PlotterApp
@testable import PlotterRuntime

extension OperatorWorkspaceTests {
  @Test("LIVE possible-ink ambiguity disables effects until exact operator disposition")
  func liveManualAmbiguityDisposition() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("manual-live-ambiguity-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let log = EventLog()
    let machine = try MachineFixture(log: log)
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
      machineActions: actions,
      simulatedRuntime: simulatedLearning,
      simulatedExecutionPacing: SimulatedLearningInteractivePacing(stepDelay: .zero)
    )
    let workspace = OperatorWorkspace(
      machineActions: actions,
      manualMotionComposition: composition,
      drawingDraftRuntime: nominalDrawingDraftRuntime(),
      drawingRunComposition: nominalDrawingRunComposition(),
      serialDevices: [machine.descriptor],
      serialDeviceDiscovery: { [machine.descriptor] },
      loadSelectedSerialIdentifier: { nil },
      persistSelectedSerialIdentifier: { _ in },
      loadPenCapAppearanceSelection: { nil },
      persistPenCapAppearanceSelection: { _ in },
      loadOverlayPreference: { nil },
      persistOverlayPreference: { _ in }
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()

    let intent = try manualAmbiguityJog()
    await workspace.submitManualMotionIntent(intent)
    let pending = workspace.manualMotionEpisodePresentation
    let evidence = try #require(pending.evidenceDisposition)
    #expect(evidence.action.environment == .live)
    #expect(evidence.action.disposition == .acknowledgePossibleInk)
    #expect(evidence.title == "Acknowledge Possible Ink")
    #expect(workspace.manualMotionEpisodeSnapshot?.projection.phase == .awaitingEvidence)
    #expect(pending.jogControlsUnavailableReason == evidence.remedy)
    #expect(pending.penUpUnavailableReason == evidence.remedy)
    #expect(pending.penDownUnavailableReason == evidence.remedy)
    #expect(workspace.motionRequestStatusPresentation == .needsAttention(evidence.remedy))
    #expect(counter.count == 1)

    await workspace.submitManualMotionIntent(intent)
    await workspace.submitManualPen(.lower)
    #expect(counter.count == 1)
    let stale = PlotterManualMotionEvidenceDispositionAction(
      effectID: evidence.action.effectID,
      environment: evidence.action.environment,
      observationID: PlotterObservationID(rawValue: UUID()),
      disposition: evidence.action.disposition,
      summary: evidence.action.summary
    )
    await workspace.resolveManualMotionEvidence(using: stale)
    #expect(workspace.manualMotionEpisodeSnapshot?.projection.phase == .awaitingEvidence)

    await workspace.resolveManualMotionEvidence(using: evidence.action)
    #expect(workspace.manualMotionEpisodeSnapshot?.projection.phase == .ready)
    #expect(workspace.manualMotionEpisodePresentation.evidenceDisposition == nil)
    #expect(workspace.manualMotionEpisodePresentation.jogControlsUnavailableReason == nil)
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
      machineActions: nil,
      simulatedRuntime: simulatedLearning,
      simulatedExecutionPacing: SimulatedLearningInteractivePacing(stepDelay: .zero)
    )
    let workspace = OperatorWorkspace(
      machineActions: nil,
      cameraActions: CameraComposition.makeIsolatedActionsForTesting(),
      manualMotionComposition: composition,
      drawingDraftRuntime: nominalDrawingDraftRuntime(),
      drawingRunComposition: nominalDrawingRunComposition(),
      serialDevices: [],
      serialDeviceDiscovery: { [] },
      loadSelectedSerialIdentifier: { nil },
      persistSelectedSerialIdentifier: { _ in },
      loadPenCapAppearanceSelection: { nil },
      persistPenCapAppearanceSelection: { _ in },
      loadOverlayPreference: { nil },
      persistOverlayPreference: { _ in }
    )
    await workspace.switchFrameMode(.simulated)
    await workspace.performControllerConnectionAction()
    await workspace.activateMotionGuard()

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
    let pending = workspace.manualMotionEpisodePresentation
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
    await workspace.submitManualPen(.lower)
    let causalTruthAfterBlockedActions =
      await composition.causalSimulatorEffectAdapter.truthSnapshot()
    #expect(causalTruthAfterBlockedActions == causalTruthBeforeManualRefusal)
    #expect(
      workspace.manualMotionEpisodeSnapshot?.projection.lastTerminalEffect?.result.context.effectID
        == ambiguousEffectID
    )
    await workspace.resolveManualMotionEvidence(using: evidence.action)
    #expect(workspace.manualMotionEpisodeSnapshot?.projection.phase == .ready)
    #expect(workspace.manualMotionEpisodePresentation.evidenceDisposition == nil)
    #expect(workspace.manualMotionEpisodePresentation.jogControlsUnavailableReason == nil)
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
      machineActions: nil,
      simulatedRuntime: simulatedRuntime,
      simulatedExecutionPacing: pacing
    )
    let workspace = OperatorWorkspace(
      machineActions: nil,
      cameraActions: CameraComposition.makeIsolatedActionsForTesting(),
      manualMotionComposition: composition,
      drawingDraftRuntime: nominalDrawingDraftRuntime(),
      drawingRunComposition: nominalDrawingRunComposition(),
      serialDevices: [],
      serialDeviceDiscovery: { [] },
      loadSelectedSerialIdentifier: { nil },
      persistSelectedSerialIdentifier: { _ in },
      loadPenCapAppearanceSelection: { nil },
      persistPenCapAppearanceSelection: { _ in },
      loadOverlayPreference: { nil },
      persistOverlayPreference: { _ in }
    )
    await workspace.switchFrameMode(.simulated)
    await workspace.performControllerConnectionAction()
    await workspace.activateMotionGuard()

    let manualOwner = Task { await workspace.submitManualJog(.xPositive) }
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
      machineActions: actions,
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
    let machine = try MachineFixture(log: log)
    let actions = manualMotionWorkspaceActions(machine: machine)
    let simulated = SimulatedLearningRuntime()
    let composition = PlotterManualMotionComposition.makeRuntimeComposition(
      journalFileURL: directory.appendingPathComponent("manual-motion-journal.json"),
      machineActions: actions,
      simulatedRuntime: simulated,
      simulatedExecutionPacing: SimulatedLearningInteractivePacing(stepDelay: .zero)
    )
    let gate = PlotterManualMotionTerminalPublicationGate()
    await composition.runtime.installTerminalPublicationGateForTesting(gate)
    let workspace = OperatorWorkspace(
      machineActions: actions,
      manualMotionComposition: composition,
      drawingDraftRuntime: nominalDrawingDraftRuntime(),
      drawingRunComposition: nominalDrawingRunComposition(),
      serialDevices: [machine.descriptor],
      serialDeviceDiscovery: { [machine.descriptor] },
      loadSelectedSerialIdentifier: { nil },
      persistSelectedSerialIdentifier: { _ in },
      loadPenCapAppearanceSelection: { nil },
      persistPenCapAppearanceSelection: { _ in },
      loadOverlayPreference: { nil },
      persistOverlayPreference: { _ in }
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    #expect(workspace.manualMotionEpisodePresentation.jogControlsUnavailableReason == nil)

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
      workspace.manualMotionEpisodePresentation.publicationRecovery != nil
    }

    let pending = workspace.manualMotionEpisodePresentation
    let recovery = try #require(pending.publicationRecovery)
    #expect(recovery.title == "Retry Manual Jog Publication")
    #expect(recovery.remedy.contains("jog command will not be issued again"))
    #expect(pending.stopAction == nil)
    #expect(pending.jogControlsUnavailableReason == recovery.remedy)
    #expect(pending.penUpUnavailableReason == recovery.remedy)
    #expect(pending.penDownUnavailableReason == recovery.remedy)
    #expect(workspace.motionRequestStatusPresentation == .needsAttention(recovery.remedy))

    await workspace.submitManualPen(.lower)
    await workspace.submitManualMotionIntent(intent)
    #expect(await machine.requestedFeeds.count == 1)
    #expect(await machine.requestedPenCommands.isEmpty)
    #expect(workspace.manualMotionEpisodeSnapshot?.activeOperation?.context.effectID
      == originalEffectID)
    await workspace.recoverManualMotionPublication(
      capabilityID: PlotterManualMotionPublicationRecoveryCapabilityID()
    )
    #expect(workspace.manualMotionEpisodePresentation.publicationRecovery?.capabilityID
      == recovery.capabilityID)

    try FileManager.default.moveItem(at: displaced, to: directory)
    await workspace.recoverManualMotionPublication(capabilityID: recovery.capabilityID)
    await owner.value

    let restored = workspace.manualMotionEpisodePresentation
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
    let actions = OperatorWorkspace.MachineActions(
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
      machineActions: actions,
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
      machineActions: actions,
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
    let actions = OperatorWorkspace.MachineActions(
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
      machineActions: actions,
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
    let target = try MachinePosition(x: -51.975, y: -73.684)
    let reproduced = try MachinePosition(x: -51.963, y: -73.673)
    #expect(MachinePositionAcceptancePolicy.toleranceMM == 0.5)
    #expect(MachinePositionAcceptancePolicy.accepts(reproduced, target: target))

    let log = EventLog()
    let machine = try MachineFixture(
      log: log,
      relativeJogSettlementOffset: try Vector2(dx: 0.012, dy: 0.011)
    )
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    try await completeLiveBoundaries(workspace, machine: machine)

    let owner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    let automaticRequestsBeforeCenterTravel = camera.recordedAutomaticInspectionRequests
    try requireEnabledPublicAction(.moveToEstimatedCenter, owner: owner, workspace: workspace)
    await workspace.performExerciseAction(.moveToEstimatedCenter, for: owner)

    let expectedCenter = try MachinePosition(x: 0, y: 0)
    #expect(camera.recordedAutomaticInspectionRequests == automaticRequestsBeforeCenterTravel)
    #expect(workspace.exactWorkflowVisionOwner == nil)
    #expect(workspace.centerArrivalPosition == expectedCenter)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .centerArrival) != nil)
    #expect(!workspace.centerArrivalRetryRequired)
    #expect(
      workspace.currentLearningPathItemID
        == .humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    )
  }

  @Test("Out-of-tolerance center settlement offers center-only retry")
  func centerArrivalRejectsOutsideToleranceWithoutBoundaryRestart() async throws {
    let target = try MachinePosition(x: 0, y: 0)
    let outside = try MachinePosition(x: 0.501, y: 0)
    #expect(!MachinePositionAcceptancePolicy.accepts(outside, target: target))

    let log = EventLog()
    let machine = try MachineFixture(
      log: log,
      relativeJogSettlementOffset: try Vector2(dx: 0.501, dy: 0)
    )
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    try await completeLiveBoundaries(workspace, machine: machine)
    let acceptedAggregates = workspace.boundarySideAggregates
    let acceptedCenter = workspace.estimatedMachineCenter

    let owner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    try requireEnabledPublicAction(.moveToEstimatedCenter, owner: owner, workspace: workspace)
    await workspace.performExerciseAction(.moveToEstimatedCenter, for: owner)

    #expect(workspace.centerArrivalPosition == nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .centerArrival) == nil)
    #expect(workspace.boundarySideAggregates == acceptedAggregates)
    #expect(workspace.estimatedMachineCenter == acceptedCenter)
    #expect(workspace.centerArrivalRetryRequired)
    #expect(workspace.restartableExerciseItemID == nil)
    let recovery = try #require(workspace.currentExerciseActionStripPresentation)
    #expect(recovery.actions.map(\.kind) == [.moveToEstimatedCenter])
    #expect(recovery.actions.map(\.title) == ["Retry Center Arrival"])
    let activity = workspace.selectedOperatorActionPresentation(for: owner).activity
    #expect(activity?.action == "Move to Estimated Center")
    #expect(
      activity?.detail.accessibilityText.contains("outside the 0.500 mm tolerance") == true
    )
    #expect(
      activity?.acceptedResult.accessibilityText.contains("four accepted Boundary") == true
    )
  }

  @Test("source-indexed sessions preserve LIVE and replace SIMULATED independently")
  func simulatedLearningDoesNotReplaceLiveAuthority() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    await workspace.beginPairedBoundarySide(.positiveY)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)

    let livePenRevisionID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id
    )
    let liveBoundaryRevisionID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveY))?.id
    )
    await workspace.switchFrameMode(.simulated)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .penInteraction) == nil)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveY))
        == nil
    )
    workspace.selectedDiscoverySequenceID = .boundaryNegativeX

    await workspace.switchFrameMode(.live)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id == livePenRevisionID
    )
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveY))?.id
        == liveBoundaryRevisionID
    )
    await workspace.switchFrameMode(.simulated)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .penInteraction) == nil)
    #expect(workspace.discoveryTransactions.isEmpty)
    #expect(workspace.selectedDiscoverySequenceID == .penInteraction)
    await workspace.switchFrameMode(.live)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id == livePenRevisionID
    )
    await workspace.shutdown()
  }

  @Test("logical boundary owner exposes Stop without a moving-state timer or natural success")
  func boundaryOwnerDoesNotAssumeMovingOrNaturalSuccess() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log, reportsBoundaryMoving: false)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)

    await workspace.beginPairedBoundarySide(.negativeY)
    try await waitUntil { workspace.contextualStopPresentation != nil }

    #expect(workspace.machineSnapshot?.machine.connection == .connected)
    #expect(workspace.relevantBoundaryObservationCount == 0)
    #expect(workspace.boundarySideAggregates.isEmpty)
    try await stopActiveOperation(workspace)
    #expect(workspace.relevantBoundaryObservationCount == 1)
    await workspace.shutdown()
  }

  @Test("invalid manual step text does not gate Boundary Discovery")
  func manualStepTextIsNotBoundaryAuthority() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    workspace.manualMotionDraft.xDistanceMM = "not-a-number"
    workspace.manualMotionDraft.yDistanceMM = ""

    #expect(workspace.manualMotionEpisodePresentation.jogControlsUnavailableReason != nil)
    #expect(workspace.discoveryStartUnavailableReason(for: .boundaryPositiveX) == nil)
    await workspace.beginPairedBoundarySide(.positiveX)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)
    #expect(workspace.relevantBoundaryObservationCount == 1)
    await workspace.shutdown()
  }

  @Test("Boundary names connection and Motion as external dependencies")
  func boundaryExternalDependencyBlockers() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log, motionGuardInitiallyActive: false)
    let workspace = workspace(machine: machine, log: log)
    let connectionBlocker =
      "Blocked by controller connection. Use Connect for the selected plotter in the workbench toolbar; Enable Motion depends on a connected session."
    let motionBlocker =
      "Blocked by Motion authorization. Use Enable Motion in the workbench toolbar for this connected session."

    #expect(
      workspace.discoveryStartUnavailableReason(for: .boundaryPositiveX)
        == connectionBlocker
    )

    await workspace.selectSerialDevice(machine.descriptor)
    await workspace.performControllerConnectionAction()

    #expect(
      workspace.discoveryStartUnavailableReason(for: .boundaryPositiveX)
        == motionBlocker
    )

    await workspace.activateMotionGuard()

    #expect(workspace.discoveryStartUnavailableReason(for: .boundaryPositiveX) == nil)
    await workspace.shutdown()
  }

  @Test("shutdown stops an active boundary before draining and erasing its authority")
  func authorityClearingStopsBeforeErasure() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()

    await workspace.beginPairedBoundarySide(.negativeY)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    await workspace.shutdown()

    #expect(await machine.cancelCount == 1)
    #expect(await machine.cancelIntents == [.shutdown])
    #expect(await machine.requestedFeeds.last == 500)
    #expect(workspace.discoveryTransactions.isEmpty)
    #expect(workspace.contextualStopPresentation == nil)
    #expect(workspace.isShutdown)
  }

  @Test(
    "announcement failure is advisory and Exercise 1.1 preserves output-before-actuation order")
  func announcementFailureDoesNotGatePenInteraction() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let announcements = AnnouncementFixture(
      log: log,
      outcomes: [.failed("output unavailable"), .completed]
    )
    let workspace = workspace(
      machine: machine,
      camera: camera,
      announcements: announcements,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)

    #expect(workspace.penInteractionCompleted)
    let events = await log.values
    #expect(
      events.firstIndex(of: "announce:Lowering the pen.")! < events.firstIndex(
        of: "machine:pen-lower")!)
    #expect(
      events.firstIndex(of: "announce:Raising the pen.")! < events.firstIndex(
        of: "machine:pen-raise")!)
    #expect(workspace.lastAnnouncementResultText == "Announcement completed.")
    await workspace.shutdown()
  }

  @Test("review projections are inert and preserve the runtime current owner")
  func reviewProjectionIsInert() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let workspace = workspace(machine: machine, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()

    let current = workspace.currentLearningPathItemID
    let transactionCount = workspace.discoveryTransactions.count
    let revisionCount = workspace.learningArtifactGraph.revisions.count
    let requestedFeedCount = await machine.requestedFeeds.count
    for itemID in LearningPathItemID.navigationOrder {
      _ = workspace.selectedOperatorActionPresentation(for: itemID)
    }

    #expect(workspace.currentLearningPathItemID == current)
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

  @Test("pen setup exposes a physical-position confirmation and Cancel, then settles to Restart")
  func exerciseActionTransitions() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)

    #expect(workspace.currentExerciseActionStripPresentation?.actions.map(\.kind) == [.start])
    await workspace.performExerciseAction(.start, for: owner)
    #expect(
      workspace.actionSurfacePresentation.pointSelectionRequest?.prompt
        == "Click the pen cap body—not the tip—on the current camera frame."
    )
    #expect(workspace.currentExerciseActionStripPresentation?.actions.map(\.kind) == [.cancel])
    try await identifyPenCap(workspace)
    let liveActions = workspace.currentExerciseActionStripPresentation?.actions.map(\.kind) ?? []
    #expect(liveActions.contains(.choice(.yes)))
    #expect(!liveActions.contains(.choice(.no)))
    #expect(liveActions.contains(.cancel))
    #expect(!liveActions.contains(.start))

    await workspace.performExerciseAction(.cancel, for: owner)
    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.currentLearningPathItemID == owner)
    #expect(workspace.currentExerciseActionStripPresentation?.actions.map(\.kind) == [.restart])
    await workspace.shutdown()
  }

  @Test("Boundary Cancel is unavailable until its movement owner settles")
  func boundaryCancelUnavailableDuringMotion() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)

    let owner = LearningPathItemID.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    await workspace.beginPairedBoundarySide(.negativeX)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    #expect(
      workspace.currentExerciseActionStripPresentation?.actions.contains(where: {
        $0.kind == .cancel
      }) == false
    )
    await workspace.performExerciseAction(.cancel, for: owner)

    #expect(await machine.cancelIntents.isEmpty)
    #expect(workspace.relevantBoundaryObservationCount == 0)
    #expect(workspace.boundarySideAggregates.isEmpty)
    #expect(workspace.discoveryTransactions[.boundaryNegativeX]?.state == .active)
    try await stopActiveOperation(workspace)
    await workspace.shutdown()
  }

  @Test("Boundary repeat actions aggregate and replace the accepted set atomically")
  func boundaryRepeatActionsAggregateAndReplaceAcceptedSet() async throws {
    let harness = makeCausalSimulatorAppFixture()
    let workspace = harness.workspace
    try await completeSimulatedBoundariesAndCenter(
      workspace,
      simulator: harness.simulator,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY]
    )

    let owner = LearningPathItemID.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    let attemptsBeforeReview = workspace.boundaryAttemptHistories[.positiveX]?
      .values.first?.attempts.count
    let revisionsBeforeReview = workspace.learningArtifactGraph.revisions.count
    let simulatorBeforeReview = await harness.simulator.snapshot()
    let repeatActions = try #require(
      workspace.selectedOperatorActionPresentation(for: owner).actionStrip
    ).actions.map(\.kind)
    #expect(repeatActions.contains(.redoBoundary(.positiveX)))
    #expect(repeatActions.contains(.recordAnotherBoundaryAttempt(.positiveX)))
    #expect(
      attemptsBeforeReview
        == workspace.boundaryAttemptHistories[.positiveX]?
        .values.first?.attempts.count)
    #expect(revisionsBeforeReview == workspace.learningArtifactGraph.revisions.count)
    let simulatorAfterReview = await harness.simulator.snapshot()
    #expect(simulatorBeforeReview == simulatorAfterReview)

    for _ in 0..<2 {
      await workspace.performExerciseAction(.recordAnotherBoundaryAttempt(.positiveX), for: owner)
      try await waitUntil { workspace.contextualStopPresentation != nil }
      try await stopActiveOperation(workspace)
    }

    let histories = try #require(workspace.boundaryAttemptHistories[.positiveX])
    let history = try #require(histories.values.first)
    let aggregate = try #require(workspace.boundarySideAggregates[.positiveX])
    #expect(histories.count == 1)
    #expect(aggregate.validSampleCount == 3)
    #expect(aggregate.includedAttemptIDs.count == 3)
    #expect(aggregate.estimator.revision == "boundary-machine-coordinate-v1")
    #expect(history.includedSuccessfulAttempts.count == 3)
    let oldAttemptIDs = aggregate.includedAttemptIDs
    #expect(oldAttemptIDs.count == 3)

    await harness.simulator.injectFault(.cameraConfigurationChangeBeforeNextFrame)
    await workspace.performExerciseAction(.redoBoundary(.positiveX), for: owner)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)

    let finalHistories = try #require(workspace.boundaryAttemptHistories[.positiveX])
    let finalHistory = try #require(finalHistories.values.first)
    let finalAggregate = try #require(workspace.boundarySideAggregates[.positiveX])
    let replacementID = try #require(finalHistory.attempts.last?.id)
    #expect(finalHistories.count == 1)
    #expect(finalHistory.records.count == 4)
    #expect(
      finalHistory.records.filter { oldAttemptIDs.contains($0.attempt.id) }
        .allSatisfy { $0.inclusionState == .superseded(by: replacementID) }
    )
    #expect(finalHistory.records.last?.inclusionState == .included)
    #expect(finalHistory.includedSuccessfulAttempts.map(\.id) == [replacementID])
    #expect(finalAggregate.validSampleCount == 1)
    #expect(finalAggregate.includedAttemptIDs == [replacementID])
    #expect(Set(finalAggregate.supersededAttempts.map(\.attemptID)) == Set(oldAttemptIDs))
    #expect(oldAttemptIDs.allSatisfy { workspace.boundaryAttemptEvidenceByAttemptID[$0] != nil })
    #expect(workspace.boundaryAttemptEvidenceByAttemptID[replacementID] != nil)
    #expect((await harness.simulator.snapshot()).currentOperation == nil)
  }

  @Test("every injected Boundary commit failure preserves all accepted current authority")
  func boundaryAtomicFailurePreservesAcceptedAuthority() async throws {
    let harness = makeCausalSimulatorAppFixture()
    let workspace = harness.workspace
    try await completeSimulatedBoundariesAndCenter(
      workspace,
      simulator: harness.simulator,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY],
      moveToCenter: false
    )
    let aggregates = workspace.boundarySideAggregates
    let progress = workspace.pairedBoundaryProgress
    let center = workspace.estimatedMachineCenter
    let localFrame = workspace.learnedLocalCoordinateFrame
    let graphRevisions = Set(workspace.learningArtifactGraph.revisions)
    let boundaryEvidence = workspace.boundaryAttemptEvidenceByAttemptID
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )

    for failurePoint in BoundaryAtomicCommitFailurePoint.allCases {
      workspace.replaceBoundaryAtomicCommitFailurePointsForTesting([failurePoint])
      let snapshot = await harness.simulator.snapshot()
      let setupDeltaX = snapshot.boundaryTruth.positiveXMM - snapshot.mpos.xMM
      if setupDeltaX != 0 {
        await workspace.submitManualMotionIntent(try manualEpisodeJog(
          RelativeJogRequest(
            delta: try Vector2(dx: setupDeltaX, dy: 0),
            feedMMPerMinute: 1_000
          )
        ))
      }

      await workspace.performExerciseAction(.redoBoundary(.positiveX), for: owner)
      try await waitUntil { workspace.contextualStopPresentation != nil }
      try await stopActiveOperation(workspace)

      #expect(workspace.boundarySideAggregates == aggregates)
      #expect(workspace.pairedBoundaryProgress == progress)
      #expect(workspace.estimatedMachineCenter == center)
      #expect(workspace.learnedLocalCoordinateFrame == localFrame)
      #expect(workspace.centerArrivalPosition == nil)
      #expect(Set(workspace.learningArtifactGraph.revisions) == graphRevisions)
      #expect(workspace.boundaryAttemptEvidenceByAttemptID == boundaryEvidence)
      #expect(workspace.restartableExerciseItemID == nil)
      let recoveryActions =
        workspace.selectedOperatorActionPresentation(for: owner)
        .actionStrip?.actions.map(\.kind) ?? []
      #expect(recoveryActions.first == .moveToEstimatedCenter)
      #expect(recoveryActions.contains(.redoBoundary(.positiveX)))
      #expect(!recoveryActions.contains(.restart))
      #expect(!recoveryActions.contains(.cancel))
      #expect((await harness.simulator.snapshot()).currentOperation == nil)
    }
  }

  @Test("Redo Exercise 1.1 replaces only its revision and retains independent boundary evidence")
  func redoPenRetainsBoundary() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    await workspace.beginPairedBoundarySide(.positiveY)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)

    let oldPen = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)
    )
    let oldBoundary = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveY))
    )
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await workspace.performExerciseAction(.redoThisStep, for: owner)
    try await identifyPenCap(workspace)
    try await finishPenInteraction(workspace)

    let newPen = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)
    )
    let retainedBoundary = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveY))
    )
    #expect(newPen.id != oldPen.id)
    #expect(workspace.learningArtifactGraph.revision(id: oldPen.id)?.state == .superseded)
    #expect(retainedBoundary.id == oldBoundary.id)
    #expect(workspace.relevantBoundaryObservationCount == 1)
    await workspace.shutdown()
  }

  @Test("cancelled replacement leaves the accepted artifact current")
  func cancelledReplacementKeepsAcceptedArtifact() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    let accepted = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)
    )
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)

    await workspace.performExerciseAction(.redoThisStep, for: owner)
    let pointRequest = try #require(workspace.actionSurfacePresentation.pointSelectionRequest)
    let displayedFrame = try #require(workspace.actionSurfacePresentation.displayedFrame)
    submitPointSelection(
      workspace,
      request: pointRequest,
      point: try Point2(
        x: Double(displayedFrame.frame.width - 1) / 2,
        y: Double(displayedFrame.frame.height - 1) / 2
      )
    )
    try await waitUntil { workspace.penCapAppearanceSelection != nil }
    await workspace.performExerciseAction(.cancel, for: owner)

    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id == accepted.id
    )
    #expect(workspace.learningArtifactGraph.revision(id: accepted.id)?.state == .current)
    #expect(workspace.penAttemptHistory.attempts.last?.disposition == .cancelled)
    #expect(workspace.penAttemptHistory.records.first?.inclusionState == .included)
    #expect(workspace.penAttemptHistory.records.last?.inclusionState == .excludedUnsuccessful)
    #expect(workspace.currentPenInteractionAggregate?.validSampleCount == 1)
    #expect(workspace.currentPenInteractionAggregate?.includedAttemptIDs == [accepted.attemptID])
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
) -> OperatorWorkspace.MachineActions {
  OperatorWorkspace.MachineActions(
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

private func manualMotionWorkspaceActions(
  machine: MachineFixture,
  beginRelativeJog: (@Sendable (RelativeJogRequest) async -> RelativeJogAdmission)? = nil
) -> OperatorWorkspace.MachineActions {
  OperatorWorkspace.MachineActions(
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
