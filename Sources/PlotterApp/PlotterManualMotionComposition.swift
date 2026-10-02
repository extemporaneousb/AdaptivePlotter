import Darwin
import EpisodeCore
import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime

struct PlotterManualMotionRuntimeComposition: Sendable {
  let runtime: PlotterManualMotionRuntime
  let simulatedRuntime: SimulatedLearningRuntime
  let causalSimulatorEffectAdapter: PlotterCausalSimulatorEffectAdapter

  fileprivate init(
    runtime: PlotterManualMotionRuntime,
    simulatedRuntime: SimulatedLearningRuntime,
    causalSimulatorEffectAdapter: PlotterCausalSimulatorEffectAdapter
  ) {
    self.runtime = runtime
    self.simulatedRuntime = simulatedRuntime
    self.causalSimulatorEffectAdapter = causalSimulatorEffectAdapter
  }
}

enum PlotterManualMotionComposition {
  static let production = makeProduction()
  static let controllerRecordingRouter = ManualMotionControllerRecordingRouter()

  /// Neutral native-controller ports retained for existing Learning, Drawing,
  /// and supervised-travel owners. These functions do not admit episode
  /// intents or transfer semantic ownership; each caller retains its existing
  /// lifecycle while direct controller calls remain centralized here.
  static func beginNativeRelativeMotion(
    using actions: (any PlotterMachineSession),
    request: RelativeJogRequest
  ) async -> RelativeJogAdmission {
    await actions.beginRelativeJog(request)
  }

  static func beginNativePenCommand(
    using actions: (any PlotterMachineSession),
    command: PenCommand,
    profile: PenActuationProfile
  ) async -> PenActuationAdmission {
    await actions.beginPenActuation(command, profile: profile)
  }

  static func settleNativePenCommand(
    using actions: (any PlotterMachineSession),
    command: PenCommand,
    profile: PenActuationProfile
  ) async -> PenOutcome {
    switch await beginNativePenCommand(using: actions, command: command, profile: profile) {
    case let .admitted(operation): return await operation.outcome()
    case let .rejected(outcome): return outcome
    }
  }

  static func makeRuntimeComposition(
    journalFileURL: URL,
    machineSession: (any PlotterMachineSession)?,
    simulatedRuntime: SimulatedLearningRuntime,
    simulatedExecutionPacing: any SimulatedLearningExecutionPacing,
    recordingStore: EpisodeRecordingStore? = nil,
    recordingDirectoryURL: URL? = nil,
    recordingUnavailableDiagnostic: String? = nil,
    recordingRouter: ManualMotionControllerRecordingRouter? = nil
  ) -> PlotterManualMotionRuntimeComposition {
    let simulatedAdapter = PlotterCausalSimulatorEffectAdapter(
      runtime: simulatedRuntime,
      pacing: simulatedExecutionPacing
    )
    let runtime = try! PlotterManualMotionRuntime(
      journalFileURL: journalFileURL,
      liveAdapter: LiveManualMotionAdapter(
        actions: machineSession,
        recordingRouter: recordingRouter ?? controllerRecordingRouter
      ),
      simulatedAdapter: simulatedAdapter,
      recordingStore: recordingStore,
      recordingDirectoryURL: recordingDirectoryURL,
      recordingUnavailableDiagnostic: recordingUnavailableDiagnostic
    )
    return PlotterManualMotionRuntimeComposition(
      runtime: runtime,
      simulatedRuntime: simulatedRuntime,
      causalSimulatorEffectAdapter: simulatedAdapter
    )
  }

  private static func makeProduction(
    applicationSupportDirectory: () throws -> URL = {
      AdaptivePlotterStoragePaths.production.rootDirectory.deletingLastPathComponent()
    }
  ) -> PlotterManualMotionRuntimeComposition {
    let simulatedRuntime = SimulatedLearningRuntime()
    let pacing = SimulatedLearningInteractivePacing()
    let artifactDirectory: URL
    do {
      artifactDirectory = AdaptivePlotterStoragePaths(applicationSupportDirectory: try applicationSupportDirectory())
        .episodeArtifactDirectory(UUID())
      try FileManager.default.createDirectory(
        at: artifactDirectory,
        withIntermediateDirectories: true
      )
    } catch {
      preconditionFailure("Manual-motion durable journal authority is unavailable: \(error)")
    }
    let recordingDirectory = artifactDirectory.appendingPathComponent(
      "controller-recording",
      isDirectory: true
    )
    let recordingStore: EpisodeRecordingStore?
    let recordingDiagnostic: String?
    do {
      try FileManager.default.createDirectory(
        at: recordingDirectory,
        withIntermediateDirectories: true
      )
      recordingStore = try EpisodeRecordingStore.open(
        directoryURL: recordingDirectory,
        recordingID: EpisodeRecordingID(rawValue: UUID()),
        schemaRevision: EpisodeRecordingSchemaRevision(
          rawValue: "adaptive-plotter-manual-motion-v1"
        ),
        frameRetentionPolicy: EpisodeFrameRetentionPolicy(
          maximumUniqueFrameCount: 1,
          maximumTotalUniqueFrameBytes: 1
        )
      )
      recordingDiagnostic = nil
    } catch {
      recordingStore = nil
      recordingDiagnostic = "Controller recording is unavailable: \(error)"
    }
    return makeRuntimeComposition(
      journalFileURL: artifactDirectory.appendingPathComponent("manual-motion-journal.json"),
      machineSession: MachineSessionComposition.session,
      simulatedRuntime: simulatedRuntime,
      simulatedExecutionPacing: pacing,
      recordingStore: recordingStore,
      recordingDirectoryURL: recordingDirectory,
      recordingUnavailableDiagnostic: recordingDiagnostic
    )
  }
}

struct ManualMotionControllerRecordingLease: Hashable, Sendable {
  fileprivate let rawValue: UUID
}

/// Holds only the recorder for the exact active EA-06 LIVE operation. It owns
/// no controller admission, transport, persistence, or settlement decision.
actor ManualMotionControllerRecordingRouter {
  private var active: (
    lease: ManualMotionControllerRecordingLease,
    recorder: PlotterManualMotionControllerRecorder
  )?

  func attach(
    _ recorder: PlotterManualMotionControllerRecorder
  ) -> ManualMotionControllerRecordingLease? {
    guard active == nil else { return nil }
    let lease = ManualMotionControllerRecordingLease(rawValue: UUID())
    active = (lease, recorder)
    return lease
  }

  func detach(_ lease: ManualMotionControllerRecordingLease) {
    guard active?.lease == lease else { return }
    active = nil
  }

  func currentRecorder() -> PlotterManualMotionControllerRecorder? {
    active?.recorder
  }
}

/// Transparent decorator over the sole production `MachineLink`. It records
/// the FIX-02 invocation/receipt boundary and never interprets controller
/// protocol, admits motion, retries traffic, or changes returned values/errors.
struct RecordingMachineLink: MachineLink, Sendable {
  let descriptor: MachineLinkDescriptor
  private let underlying: any MachineLink
  private let router: ManualMotionControllerRecordingRouter
  private let clock: any RuntimeClock

  init(
    underlying: any MachineLink,
    router: ManualMotionControllerRecordingRouter,
    clock: any RuntimeClock
  ) {
    descriptor = underlying.descriptor
    self.underlying = underlying
    self.router = router
    self.clock = clock
  }

  func open() async throws -> MachineLinkOpenReceipt {
    guard let recorder = await router.currentRecorder() else {
      return try await underlying.open()
    }
    let invokedAt = clock.nowNanoseconds()
    do {
      let receipt = try await underlying.open()
      guard let parameters = controllerOpenParameters(from: receipt.appliedConfiguration) else {
        await recorder.reportDiagnostic(
          "Controller open applied configuration cannot be represented losslessly by EA-05A; no open transcript facts were fabricated."
        )
        return receipt
      }
      let invocation = ControllerInvocation(
        id: ControllerInvocationID(rawValue: UUID()),
        operation: .open(parameters)
      )
      await recorder.recordMachineLinkInvocation(
        invocation,
        atSourceMonotonicNanoseconds: invokedAt
      )
      await recorder.recordMachineLinkCompletion(
        ControllerCompletion(invocationID: invocation.id, outcome: .succeeded(.open)),
        atSourceMonotonicNanoseconds: clock.nowNanoseconds()
      )
      return receipt
    } catch {
      // The existing EA-05A open invocation requires configuration parameters.
      // A failed open has no applied FIX-02 receipt, so operation-bound manual
      // recording must remain incomplete rather than inventing settings.
      await recorder.reportDiagnostic(
        "Controller open failed before applied configuration was available; no open transcript facts were fabricated: \(error)"
      )
      throw error
    }
  }

  func close() async throws {
    guard let recorder = await router.currentRecorder() else {
      try await underlying.close()
      return
    }
    let invocation = ControllerInvocation(
      id: ControllerInvocationID(rawValue: UUID()),
      operation: .close
    )
    await recorder.recordMachineLinkInvocation(
      invocation,
      atSourceMonotonicNanoseconds: clock.nowNanoseconds()
    )
    do {
      try await underlying.close()
      await recorder.recordMachineLinkCompletion(
        ControllerCompletion(invocationID: invocation.id, outcome: .succeeded(.close)),
        atSourceMonotonicNanoseconds: clock.nowNanoseconds()
      )
    } catch {
      await recordFailure(error, for: invocation.id, recorder: recorder)
      throw error
    }
  }

  func discardPendingInput() async throws -> MachineLinkDiscardReceipt {
    guard let recorder = await router.currentRecorder() else {
      return try await underlying.discardPendingInput()
    }
    let invocation = ControllerInvocation(
      id: ControllerInvocationID(rawValue: UUID()),
      operation: .discardInput(ControllerDiscardParameters())
    )
    await recorder.recordMachineLinkInvocation(
      invocation,
      atSourceMonotonicNanoseconds: clock.nowNanoseconds()
    )
    do {
      let receipt = try await underlying.discardPendingInput()
      await recorder.recordMachineLinkCompletion(
        ControllerCompletion(
          invocationID: invocation.id,
          outcome: .succeeded(.discardInput(
            discardedByteCount: receipt.discardedByteCount
          ))
        ),
        atSourceMonotonicNanoseconds: clock.nowNanoseconds()
      )
      return receipt
    } catch {
      await recordFailure(error, for: invocation.id, recorder: recorder)
      throw error
    }
  }

  func write(_ bytes: Data) async throws -> MachineLinkWriteReceipt {
    guard let recorder = await router.currentRecorder() else {
      return try await underlying.write(bytes)
    }
    let invocation = ControllerInvocation(
      id: ControllerInvocationID(rawValue: UUID()),
      operation: .rawWrite(ControllerRawWriteParameters(bytes: bytes))
    )
    await recorder.recordMachineLinkInvocation(
      invocation,
      atSourceMonotonicNanoseconds: clock.nowNanoseconds()
    )
    do {
      let receipt = try await underlying.write(bytes)
      await recorder.recordMachineLinkCompletion(
        ControllerCompletion(
          invocationID: invocation.id,
          outcome: .succeeded(.rawWrite(writtenByteCount: receipt.writtenByteCount))
        ),
        atSourceMonotonicNanoseconds: clock.nowNanoseconds()
      )
      return receipt
    } catch {
      await recordFailure(error, for: invocation.id, recorder: recorder)
      throw error
    }
  }

  func read(
    maximumBytes: Int,
    timeoutNanoseconds: UInt64
  ) async throws -> MachineLinkReadReceipt {
    guard let recorder = await router.currentRecorder() else {
      return try await underlying.read(
        maximumBytes: maximumBytes,
        timeoutNanoseconds: timeoutNanoseconds
      )
    }
    let invocation = ControllerInvocation(
      id: ControllerInvocationID(rawValue: UUID()),
      operation: .timedRead(ControllerTimedReadParameters(
        maximumByteCount: maximumBytes,
        timeoutNanoseconds: timeoutNanoseconds
      ))
    )
    await recorder.recordMachineLinkInvocation(
      invocation,
      atSourceMonotonicNanoseconds: clock.nowNanoseconds()
    )
    do {
      let receipt = try await underlying.read(
        maximumBytes: maximumBytes,
        timeoutNanoseconds: timeoutNanoseconds
      )
      guard let chunk = await recorder.controllerReadChunk(from: receipt) else {
        return receipt
      }
      await recorder.recordMachineLinkCompletion(
        ControllerCompletion(
          invocationID: invocation.id,
          outcome: .succeeded(.timedRead(chunks: [chunk], timedOut: false))
        ),
        atSourceMonotonicNanoseconds: clock.nowNanoseconds()
      )
      return receipt
    } catch {
      await recordFailure(error, for: invocation.id, recorder: recorder)
      throw error
    }
  }

  private func recordFailure(
    _ error: any Error,
    for invocationID: ControllerInvocationID,
    recorder: PlotterManualMotionControllerRecorder
  ) async {
    guard let failure = await controllerFailure(error, recorder: recorder) else { return }
    await recorder.recordMachineLinkCompletion(
      ControllerCompletion(invocationID: invocationID, outcome: .failed(failure)),
      atSourceMonotonicNanoseconds: clock.nowNanoseconds()
    )
  }

  private func controllerFailure(
    _ error: any Error,
    recorder: PlotterManualMotionControllerRecorder
  ) async -> ControllerOperationFailure? {
    guard let error = error as? MachineLinkError else {
      return ControllerOperationFailure(
        kind: .unknown,
        diagnostic: String(describing: error)
      )
    }
    switch error {
    case .notOpen:
      return ControllerOperationFailure(kind: .notOpen)
    case .alreadyOpen:
      return ControllerOperationFailure(kind: .alreadyOpen)
    case .timedOut:
      return ControllerOperationFailure(kind: .timeout)
    case let .writeTimedOut(written, total):
      return ControllerOperationFailure(
        kind: .timeout,
        diagnostic: "write timed out after \(written) of \(total) bytes",
        partialByteCount: written
      )
    case let .writeCancelled(written, total):
      return ControllerOperationFailure(
        kind: .cancelled,
        diagnostic: "write cancelled after \(written) of \(total) bytes",
        partialByteCount: written
      )
    case let .discardFailed(discarded, total, reason):
      return controllerTransferFailure(
        reason,
        diagnosticPrefix: total.map {
          "discard failed after \(discarded) of \($0) observed bytes"
        } ?? "discard snapshot acquisition failed",
        partialByteCount: discarded
      )
    case let .writeFailed(written, total, reason):
      return controllerTransferFailure(
        reason,
        diagnosticPrefix: "write failed after \(written) of \(total) bytes",
        partialByteCount: written
      )
    case let .readFailed(receipts, maximumBytes, reason):
      var chunks: [ControllerReadChunk] = []
      var partialByteCount = 0
      for receipt in receipts {
        guard let chunk = await recorder.controllerReadChunk(from: receipt) else { return nil }
        let (next, overflow) = partialByteCount.addingReportingOverflow(receipt.bytes.count)
        guard !overflow else {
          await recorder.reportDiagnostic(
            "Controller partial-read byte count overflowed; no completion was fabricated."
          )
          return nil
        }
        partialByteCount = next
        chunks.append(chunk)
      }
      return controllerTransferFailure(
        reason,
        diagnosticPrefix: "timed read failed after \(partialByteCount) of \(maximumBytes) bytes",
        partialByteCount: partialByteCount,
        partialReadChunks: chunks
      )
    case let .readExceededMaximum(expected, actual):
      return ControllerOperationFailure(
        kind: .protocolViolation,
        diagnostic: "read exceeded maximum: expected \(expected), actual \(actual)"
      )
    case .disconnected:
      return ControllerOperationFailure(kind: .inputOutput, diagnostic: "disconnected")
    case let .unexpectedWrite(expected, actual):
      return ControllerOperationFailure(
        kind: .protocolViolation,
        diagnostic: "unexpected write: expected \(expected.count), actual \(actual.count) bytes"
      )
    case let .invalidPath(path):
      return ControllerOperationFailure(
        kind: .endpointNotFound,
        diagnostic: "invalid controller path: \(path)"
      )
    case let .operatingSystem(code, operation):
      return controllerOperatingSystemFailure(code: code, operation: operation)
    }
  }
}

private func controllerOpenParameters(
  from configuration: MachineLinkAppliedConfiguration
) -> ControllerOpenParameters? {
  guard case let .bsdSerial(value) = configuration,
    value.inputBaudRate == value.outputBaudRate,
    value.localModeEnabled,
    value.receiverEnabled
  else { return nil }
  let parity: ControllerParity = switch value.parity {
  case .none: .none
  case .even: .even
  case .odd: .odd
  }
  let flowControl: ControllerFlowControl
  switch value.flowControl {
  case .none: flowControl = .none
  case .hardware: flowControl = .hardware
  case .software: flowControl = .software
  case .hardwareAndSoftware: return nil
  }
  return ControllerOpenParameters(
    endpoint: value.endpoint,
    baudRate: value.inputBaudRate,
    dataBits: value.dataBits,
    stopBits: value.stopBits,
    parity: parity,
    flowControl: flowControl
  )
}

private func controllerTransferFailure(
  _ reason: MachineLinkTransferFailureReason,
  diagnosticPrefix: String,
  partialByteCount: Int,
  partialReadChunks: [ControllerReadChunk] = []
) -> ControllerOperationFailure {
  switch reason {
  case .timedOut:
    return ControllerOperationFailure(
      kind: .timeout,
      diagnostic: diagnosticPrefix,
      partialByteCount: partialByteCount,
      partialReadChunks: partialReadChunks
    )
  case .cancelled:
    return ControllerOperationFailure(
      kind: .cancelled,
      diagnostic: diagnosticPrefix,
      partialByteCount: partialByteCount,
      partialReadChunks: partialReadChunks
    )
  case .disconnected:
    return ControllerOperationFailure(
      kind: .inputOutput,
      diagnostic: "\(diagnosticPrefix): disconnected",
      partialByteCount: partialByteCount,
      partialReadChunks: partialReadChunks
    )
  case let .operatingSystem(code, operation):
    let base = controllerOperatingSystemFailure(code: code, operation: operation)
    return ControllerOperationFailure(
      kind: base.kind,
      systemCode: base.systemCode,
      diagnostic: "\(diagnosticPrefix): \(operation)",
      partialByteCount: partialByteCount,
      partialReadChunks: partialReadChunks
    )
  }
}

private func controllerOperatingSystemFailure(
  code: Int32,
  operation: String
) -> ControllerOperationFailure {
  let kind: ControllerErrorKind
  switch code {
  case EACCES, EPERM: kind = .permissionDenied
  case ENOENT, ENXIO: kind = .endpointNotFound
  default: kind = .inputOutput
  }
  return ControllerOperationFailure(
    kind: kind,
    systemCode: code,
    diagnostic: operation
  )
}

private enum LiveNativeManualMotionHandle: Sendable {
  case relativeJog(RelativeJogOperation)
  case drawingStroke(DrawingStrokeOperation)
  case penActuation(PenActuationOperation, command: PenCommand)
}

private actor LiveManualMotionOperation: PlotterManualMotionOperation {
  private let request: PlotterManualMotionEffectRequest
  private let actions: (any PlotterMachineSession)?
  private let recordingRouter: ManualMotionControllerRecordingRouter
  private let controllerRecorder: PlotterManualMotionControllerRecorder?
  private var didStart = false
  private var cancellationRequested = false
  private var cancellationIssued = false
  private var nativeHandle: LiveNativeManualMotionHandle?
  private var recordingLease: ManualMotionControllerRecordingLease?
  private var result: PlotterManualMotionOperationResult?
  private var waiters: [CheckedContinuation<PlotterManualMotionOperationResult, Never>] = []

  init(
    request: PlotterManualMotionEffectRequest,
    actions: (any PlotterMachineSession)?,
    recordingRouter: ManualMotionControllerRecordingRouter,
    controllerRecorder: PlotterManualMotionControllerRecorder?
  ) {
    self.request = request
    self.actions = actions
    self.recordingRouter = recordingRouter
    self.controllerRecorder = controllerRecorder
  }

  func start() async {
    guard !didStart else { return }
    didStart = true
    guard let actions else {
      publish(.failed(PlotterEffectFailure(
        code: .environmentFailure,
        owner: EpisodeAuthorityID(rawValue: "(any PlotterMachineSession)"),
        summary: "Native machine composition is unavailable."
      )))
      return
    }
    if let controllerRecorder {
      if let lease = await recordingRouter.attach(controllerRecorder) {
        recordingLease = lease
      } else {
        await controllerRecorder.reportDiagnostic(
          "Manual-motion controller recorder was already attached; controller behavior continued without reattribution."
        )
      }
    }

    let handle: LiveNativeManualMotionHandle
    switch request.intent {
    case let .jog(jog):
      let delta: Vector2<MachineSpace>
      do {
        delta = try jog.machineDelta
      } catch {
        await detachRecorder()
        publish(.failed(environmentFailure("Invalid manual jog vector: \(error)")))
        return
      }
      switch jog.routing {
      case .relativeTravel, .possibleInk:
        let nativeRequest = RelativeJogRequest(
          delta: delta,
          feedMMPerMinute: jog.feedMMPerMinute,
          permitsUnknownPenStateAsPossibleInk: jog.routing == .possibleInk
        )
        switch await actions.beginRelativeJog(nativeRequest) {
        case let .admitted(operation): handle = .relativeJog(operation)
        case let .rejected(outcome):
          await detachRecorder()
          publish(await liveJogDisposition(outcome, actions: actions))
          return
        }
      case .drawingStroke:
        switch await actions.beginDrawingStroke(DrawingStrokeRequest(
          delta: delta,
          feedMMPerMinute: jog.feedMMPerMinute
        )) {
        case let .admitted(operation): handle = .drawingStroke(operation)
        case let .rejected(outcome):
          await detachRecorder()
          publish(await liveDrawingDisposition(outcome, actions: actions))
          return
        }
      }
    case let .setPen(pen):
      let command: PenCommand = pen.position == .raised ? .raise : .lower
      let profile = PenActuationProfile(
        raisedSpindleValue: pen.profile.raisedSpindleValue,
        loweredSpindleValue: pen.profile.loweredSpindleValue,
        settleSeconds: pen.profile.settleSeconds
      )
      switch await PlotterManualMotionComposition.beginNativePenCommand(
        using: actions,
        command: command,
        profile: profile
      ) {
      case let .admitted(operation): handle = .penActuation(operation, command: command)
      case let .rejected(outcome):
        await detachRecorder()
        publish(await livePenDisposition(outcome, command: command, actions: actions))
        return
      }
    }
    nativeHandle = handle
    if cancellationRequested { await issueCancellationIfAvailable() }
    Task { [weak self] in await self?.settle(handle, actions: actions) }
  }

  func requestCancellation() async {
    guard !cancellationRequested else { return }
    cancellationRequested = true
    await issueCancellationIfAvailable()
  }

  func waitForSettlement() async -> PlotterManualMotionOperationResult {
    if let result { return result }
    return await withCheckedContinuation { waiters.append($0) }
  }

  private func issueCancellationIfAvailable() async {
    guard !cancellationIssued, let actions else { return }
    switch nativeHandle {
    case .relativeJog, .drawingStroke:
      cancellationIssued = true
      _ = await actions.requestJogCancel(.operatorStop)
    case .penActuation, nil:
      break
    }
  }

  private func settle(
    _ handle: LiveNativeManualMotionHandle,
    actions: (any PlotterMachineSession)
  ) async {
    let disposition: PlotterManualMotionOperationDisposition
    switch handle {
    case let .relativeJog(operation):
      disposition = await liveJogDisposition(await operation.outcome(), actions: actions)
    case let .drawingStroke(operation):
      disposition = await liveDrawingDisposition(await operation.outcome(), actions: actions)
    case let .penActuation(operation, command):
      disposition = await livePenDisposition(
        await operation.outcome(),
        command: command,
        actions: actions
      )
    }
    await detachRecorder()
    publish(disposition)
  }

  private func detachRecorder() async {
    guard let recordingLease else { return }
    self.recordingLease = nil
    await recordingRouter.detach(recordingLease)
  }

  private func publish(_ disposition: PlotterManualMotionOperationDisposition) {
    guard result == nil else { return }
    let value = PlotterManualMotionOperationResult(
      identity: PlotterManualMotionOperationIdentity(request: request),
      disposition: disposition
    )
    result = value
    let continuations = waiters
    waiters.removeAll()
    continuations.forEach { $0.resume(returning: value) }
  }
}

private struct LiveManualMotionAdapter: PlotterManualMotionEffectAdapter, Sendable {
  let environment = PlotterEnvironment.live
  let actions: (any PlotterMachineSession)?
  let recordingRouter: ManualMotionControllerRecordingRouter

  func makeOperation(
    for request: PlotterManualMotionEffectRequest,
    controllerRecorder: PlotterManualMotionControllerRecorder?
  ) -> any PlotterManualMotionOperation {
    LiveManualMotionOperation(
      request: request,
      actions: actions,
      recordingRouter: recordingRouter,
      controllerRecorder: controllerRecorder
    )
  }
}

private func livePenDisposition(
  _ outcome: PenOutcome,
  command: PenCommand,
  actions: (any PlotterMachineSession)
) async -> PlotterManualMotionOperationDisposition {
  let observation = liveObservation(await actions.snapshot())
  switch outcome {
  case .commandedAndSettled:
    return .completed(observation: observation)
  case .refused(let refusal):
    return .refused(effectRefusal(refusal.actionableDescription))
  case .ambiguous(let ambiguity):
    return .ambiguous(
      PlotterEffectAmbiguity(
        summary: ambiguity.actionableDescription,
        observationIDs: [observation.context.id],
        possibleInk: command == .lower
      ),
      observations: [observation]
    )
  }
}

private func liveJogDisposition(
  _ outcome: MotionOutcome,
  actions: (any PlotterMachineSession)
) async -> PlotterManualMotionOperationDisposition {
  let observation = liveObservation(await actions.snapshot())
  switch outcome {
  case .acceptedThenCompleted:
    return .completed(observation: observation)
  case .cancelled:
    return .cancelled(
      settlement: .controllerSettled(
        observationID: observation.context.id,
        possibleInk: true
      ),
      observation: observation
    )
  case .refused(let refusal):
    return .refused(effectRefusal(refusal.actionableDescription))
  case .ambiguous(let ambiguity):
    return .ambiguous(
      PlotterEffectAmbiguity(
        summary: ambiguity.actionableDescription,
        observationIDs: [observation.context.id],
        possibleInk: true
      ),
      observations: [observation]
    )
  }
}

private func liveDrawingDisposition(
  _ outcome: DrawingStrokeOutcome,
  actions: (any PlotterMachineSession)
) async -> PlotterManualMotionOperationDisposition {
  let observation = liveObservation(await actions.snapshot())
  switch outcome {
  case .completed:
    return .completed(observation: observation)
  case .cancelled(_, let penRaiseOutcome):
    guard case .commandedAndSettled(command: .raise, commandedState: .up) = penRaiseOutcome
    else {
      return .ambiguous(
        PlotterEffectAmbiguity(
          summary: "Manual drawing stopped without controller-settled Pen Up.",
          observationIDs: [observation.context.id],
          possibleInk: true
        ),
        observations: [observation]
      )
    }
    return .cancelled(
      settlement: .drawingStoppedWithPenRaised(
        observationID: observation.context.id,
        possibleInk: true
      ),
      observation: observation
    )
  case .refused(let refusal):
    return .refused(effectRefusal(refusal.actionableDescription))
  case .ambiguous(let ambiguity):
    return .ambiguous(
      PlotterEffectAmbiguity(
        summary: ambiguity.actionableDescription,
        observationIDs: [observation.context.id],
        possibleInk: true
      ),
      observations: [observation]
    )
  }
}

private extension PlotterJogRequest {
  var machineDelta: Vector2<MachineSpace> {
    get throws {
      switch direction {
      case .positiveX: try Vector2(dx: distanceMM, dy: 0)
      case .negativeX: try Vector2(dx: -distanceMM, dy: 0)
      case .positiveY: try Vector2(dx: 0, dy: distanceMM)
      case .negativeY: try Vector2(dx: 0, dy: -distanceMM)
      }
    }
  }
}

private func liveObservation(_ snapshot: RunInterpreterSnapshot?) -> PlotterObservation {
  let machine = snapshot?.machine
  let status: PlotterControllerStatus = switch machine?.controllerState {
  case .idle: .idle
  case .run, .jog: .running
  case .hold: .hold
  case .alarm: .alarm
  case nil: .disconnected
  default: .unknown
  }
  return .controller(PlotterControllerObservation(
    context: PlotterObservationContext(
      id: PlotterObservationID(rawValue: UUID()),
      observedAt: Date(),
      environment: .live,
      source: .controller,
      sourceRevision: EpisodeRevisionIdentifier(rawValue: "native-controller-v1")
    ),
    status: status,
    machinePosition: machine?.position?.point,
    motionEnabled: machine?.motionGuardState == .active
  ))
}

private func effectRefusal(_ remedy: String) -> PlotterEffectRefusal {
  PlotterEffectRefusal(
    requirementID: EpisodeRequirementID(rawValue: "plotter.nativeControllerAdmission"),
    owner: EpisodeAuthorityID(rawValue: "MachineController"),
    comparedRevision: EpisodeRevisionIdentifier(rawValue: "native-controller-v1"),
    remedy: remedy
  )
}

private func environmentFailure(_ summary: String) -> PlotterEffectFailure {
  PlotterEffectFailure(
    code: .environmentFailure,
    owner: EpisodeAuthorityID(rawValue: "PlotterManualMotionEffectAdapter"),
    summary: summary
  )
}
