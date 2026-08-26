import EpisodeCore
@testable import EpisodeRuntime
import Foundation
import Testing

@Suite("PlotterOperationRegistry ownership and lifetime contract")
struct PlotterOperationRegistryTests {
  @Test("lane configuration is typed, distinct, and bounded")
  func laneConfigurationValidation() throws {
    #expect(throws: LaneConfigurationError.invalidBackgroundAnalysisLimit(0)) {
      try PlotterOperationLaneConfiguration(
        machine: TestLane.machine,
        exactWorkflowCaptureVision: .exactWorkflow,
        backgroundAnalysis: .analysis,
        durableAppend: .append,
        backgroundAnalysisLimit: 0
      )
    }
    #expect(throws: LaneConfigurationError.duplicateLane(.machine)) {
      try PlotterOperationLaneConfiguration(
        machine: TestLane.machine,
        exactWorkflowCaptureVision: .machine,
        backgroundAnalysis: .analysis,
        durableAppend: .append,
        backgroundAnalysisLimit: 2
      )
    }
  }

  @Test("exclusive lanes refuse overlap, analysis is bounded, and append is serialized")
  func laneAdmission() async throws {
    let registry = try makeRegistry(backgroundAnalysisLimit: 2)
    _ = try await register(1, lane: .machine, in: registry)
    await #expect(throws: AdmissionError.laneAtCapacity(lane: .machine, capacity: 1)) {
      try await register(2, lane: .machine, in: registry)
    }

    _ = try await register(3, lane: .exactWorkflow, in: registry)
    await #expect(
      throws: AdmissionError.laneAtCapacity(lane: .exactWorkflow, capacity: 1)
    ) {
      try await register(4, lane: .exactWorkflow, in: registry)
    }

    _ = try await register(5, lane: .analysis, in: registry)
    _ = try await register(6, lane: .analysis, in: registry)
    await #expect(throws: AdmissionError.laneAtCapacity(lane: .analysis, capacity: 2)) {
      try await register(7, lane: .analysis, in: registry)
    }

    _ = try await register(8, lane: .append, in: registry)
    await #expect(throws: AdmissionError.laneAtCapacity(lane: .append, capacity: 1)) {
      try await register(9, lane: .append, in: registry)
    }

    await #expect(throws: AdmissionError.unconfiguredLane(.other)) {
      try await register(10, lane: .other, in: registry)
    }

    let snapshot = await registry.snapshot()
    #expect(snapshot.active.count == 5)
    #expect(snapshot.active.filter { $0.laneRole == .machine }.count == 1)
    #expect(snapshot.active.filter { $0.laneRole == .exactWorkflowCaptureVision }.count == 1)
    #expect(snapshot.active.filter { $0.laneRole == .backgroundAnalysis }.count == 2)
    #expect(snapshot.active.filter { $0.laneRole == .durableAppend }.count == 1)
  }

  @Test("effect permits are structurally move-only and exact identity and revision bound")
  func effectPermitIsMoveOnlyAndExact() async throws {
    let registry = try makeRegistry()
    let mismatchIdentity = identity(11)
    let attributionRefusalIdentity = identity(12)
    let mismatch = try await registry.register(
      identity: mismatchIdentity,
      lane: .machine,
      context: context(11),
      handle: TestHandle(),
      cancellationAvailable: true,
      admittedAt: time(0)
    )
    let attributionRefusal = try await registry.register(
      identity: attributionRefusalIdentity,
      lane: .analysis,
      context: context(12),
      handle: TestHandle(),
      cancellationAvailable: true,
      admittedAt: time(0)
    )

    let staleRevisionIdentity = PlotterOperationIdentity(
      episodeID: mismatchIdentity.episodeID,
      requestID: mismatchIdentity.requestID,
      effectID: mismatchIdentity.effectID,
      effectRevision: EpisodeRevisionIdentifier(rawValue: "effect-stale")
    )

    let beforeIdentityRefusal = await registry.snapshot()
    let identityRefusal = await registry.start(
      mismatch.takePermit(),
      for: staleRevisionIdentity,
      attributedTo: attribution(
        110,
        for: mismatchIdentity,
        sequence: 1,
        preRevision: 0,
        at: time(1)
      )
    )
    let identityRetryPermit = try requireIdentityMismatchPermit(
      identityRefusal,
      expected: mismatchIdentity
    )
    let afterIdentityRefusal = await registry.snapshot()
    let identityBefore = try #require(
      beforeIdentityRefusal.active.first { $0.identity == mismatchIdentity }
    )
    let identityAfter = try #require(
      afterIdentityRefusal.active.first { $0.identity == mismatchIdentity }
    )
    #expect(afterIdentityRefusal.revision == beforeIdentityRefusal.revision)
    #expect(afterIdentityRefusal.active.count == beforeIdentityRefusal.active.count)
    #expect(identityAfter.lane == identityBefore.lane)
    #expect(identityAfter.phase == .waiting)
    #expect(identityAfter.startedAt == nil)
    #expect(identityAfter.lastAcceptedAttribution == nil)
    let mismatchStart = attribution(
      112,
      for: mismatchIdentity,
      sequence: 1,
      preRevision: 0,
      at: time(1)
    )
    try requireStartAccepted(
      await registry.start(
        identityRetryPermit,
        for: mismatchIdentity,
        attributedTo: mismatchStart
      )
    )

    let beforeAttributionRefusal = await registry.snapshot()
    let attributionRefusalOutcome = await registry.start(
      attributionRefusal.takePermit(),
      for: attributionRefusalIdentity,
      attributedTo: attribution(
        111,
        for: attributionRefusalIdentity,
        sequence: 1,
        preRevision: 0,
        at: time(-1)
      )
    )
    let attributionRetryPermit = try requireAttributionRefusalPermit(
      attributionRefusalOutcome,
      expected: .timestampRegression(previous: time(0), actual: time(-1))
    )
    let afterAttributionRefusal = await registry.snapshot()
    let attributionBefore = try #require(
      beforeAttributionRefusal.active.first { $0.identity == attributionRefusalIdentity }
    )
    let attributionAfter = try #require(
      afterAttributionRefusal.active.first { $0.identity == attributionRefusalIdentity }
    )
    #expect(afterAttributionRefusal.revision == beforeAttributionRefusal.revision)
    #expect(afterAttributionRefusal.active.count == beforeAttributionRefusal.active.count)
    #expect(attributionAfter.lane == attributionBefore.lane)
    #expect(attributionAfter.phase == .waiting)
    #expect(attributionAfter.startedAt == nil)
    #expect(attributionAfter.lastAcceptedAttribution == nil)
    let attributionStart = attribution(
      113,
      for: attributionRefusalIdentity,
      sequence: 1,
      preRevision: 0,
      at: time(1)
    )
    try requireStartAccepted(
      await registry.start(
        attributionRetryPermit,
        for: attributionRefusalIdentity,
        attributedTo: attributionStart
      )
    )

    let started = await registry.snapshot()
    #expect(started.active.allSatisfy { $0.phase == .progressing })
    #expect(
      started.active.first { $0.identity == mismatchIdentity }?.lastAcceptedAttribution
        == mismatchStart
    )
    #expect(
      started.active.first { $0.identity == attributionRefusalIdentity }?
        .lastAcceptedAttribution == attributionStart
    )
  }

  @Test(
    "one exact Stop latches cancellation, awaits the original handle, and cannot stop a successor"
  )
  func exactStopAndStaleSuccessorImmunity() async throws {
    let registry = try makeRegistry()
    let firstIdentity = identity(20)
    let firstHandle = TestHandle()
    let first = try await registry.register(
      identity: firstIdentity,
      lane: .machine,
      context: context(20),
      handle: firstHandle,
      cancellationAvailable: true,
      admittedAt: time(0)
    )
    let firstStopCapability = first.stopCapability
    let firstCapability = try #require(firstStopCapability)
    try requireStartAccepted(
      await registry.start(
        first.takePermit(),
        for: firstIdentity,
        attributedTo: attribution(
          120,
          for: firstIdentity,
          sequence: 1,
          preRevision: 0,
          at: time(1)
        )
      )
    )

    let stopTask = Task {
      await registry.stop(using: firstCapability, at: time(2))
    }
    #expect(await eventually {
      let metrics = await firstHandle.metrics()
      return metrics.cancelRequests == 1 && metrics.settlementWaits == 1
    })
    #expect(await registry.stop(using: firstCapability, at: time(3)) == .alreadyRequested)
    #expect(await firstHandle.metrics().cancelRequests == 1)

    let duringCancellation = await registry.snapshot()
    let cancelling = try #require(
      duringCancellation.active.first { $0.identity == firstIdentity }
    )
    #expect(cancelling.phase == .settling)
    #expect(cancelling.cancellationPhase == .settling)
    #expect(cancelling.cancellationReason == .stop)

    await firstHandle.finish(.cancelled)
    #expect(await stopTask.value == .settled(.cancelled))
    #expect(await firstHandle.metrics() == TestHandleMetrics(cancelRequests: 1, settlementWaits: 1))

    let successorIdentity = identity(21)
    let successorHandle = TestHandle()
    let successor = try await registry.register(
      identity: successorIdentity,
      lane: .machine,
      context: context(21),
      handle: successorHandle,
      cancellationAvailable: true,
      admittedAt: time(4)
    )
    try requireStartAccepted(
      await registry.start(
        successor.takePermit(),
        for: successorIdentity,
        attributedTo: attribution(
          121,
          for: successorIdentity,
          sequence: 2,
          preRevision: 1,
          at: time(5)
        )
      )
    )
    #expect(await registry.stop(using: firstCapability, at: time(6)) == .retiredCapability)
    #expect(await successorHandle.metrics().cancelRequests == 0)

    let snapshot = await registry.snapshot()
    #expect(snapshot.active.map(\.identity) == [successorIdentity])
    #expect(snapshot.terminal.count == 1)
    #expect(snapshot.terminal.first?.identity == firstIdentity)
    #expect(snapshot.terminal.first?.cancellationReason == .stop)
  }

  @Test("cancellation refuses racing results and releases its lane only after owner settlement")
  func cancellationSettlementOrdering() async throws {
    let registry = try makeRegistry()
    let operationIdentity = identity(30)
    let handle = TestHandle()
    let registration = try await registry.register(
      identity: operationIdentity,
      lane: .machine,
      context: context(30),
      handle: handle,
      cancellationAvailable: true,
      admittedAt: time(0)
    )
    let stopCapability = registration.stopCapability
    let capability = try #require(stopCapability)
    try requireStartAccepted(
      await registry.start(
        registration.takePermit(),
        for: operationIdentity,
        attributedTo: attribution(
          130,
          for: operationIdentity,
          sequence: 1,
          preRevision: 0,
          at: time(1)
        )
      )
    )

    let stopTask = Task {
      await registry.stop(using: capability, at: time(2))
    }
    #expect(await eventually { await handle.metrics().settlementWaits == 1 })
    #expect(
      await registry.settle(
        identity: operationIdentity,
        disposition: .completed,
        at: time(3)
      ) == .cancellationInProgress
    )
    await #expect(throws: AdmissionError.laneAtCapacity(lane: .machine, capacity: 1)) {
      try await register(31, lane: .machine, in: registry)
    }

    await handle.finish(.cancelled)
    #expect(await stopTask.value == .settled(.cancelled))
    _ = try await register(31, lane: .machine, in: registry, admittedAt: time(4))
  }

  @Test("duplicate and stale results are refused and terminal capability never revives")
  func terminalRefusalAndCapabilityRetirement() async throws {
    let registry = try makeRegistry()
    let operationIdentity = identity(40)
    let handle = TestHandle()
    let registration = try await registry.register(
      identity: operationIdentity,
      lane: .exactWorkflow,
      context: context(40),
      handle: handle,
      cancellationAvailable: true,
      admittedAt: time(0)
    )
    let stopCapability = registration.stopCapability
    let capability = try #require(stopCapability)
    try requireStartAccepted(
      await registry.start(
        registration.takePermit(),
        for: operationIdentity,
        attributedTo: attribution(
          140,
          for: operationIdentity,
          sequence: 1,
          preRevision: 0,
          at: time(1)
        )
      )
    )

    let staleIdentity = PlotterOperationIdentity(
      episodeID: operationIdentity.episodeID,
      requestID: operationIdentity.requestID,
      effectID: operationIdentity.effectID,
      effectRevision: EpisodeRevisionIdentifier(rawValue: "effect-stale")
    )
    #expect(
      await registry.settle(identity: staleIdentity, disposition: .failed, at: time(2))
        == .identityMismatch(expected: operationIdentity)
    )
    #expect(
      await registry.settle(identity: operationIdentity, disposition: .completed, at: time(3))
        == .accepted(.completed)
    )
    #expect(
      await registry.settle(identity: operationIdentity, disposition: .failed, at: time(4))
        == .duplicate(.completed)
    )
    #expect(
      await registry.recordProgress(
        for: operationIdentity,
        phase: .progressing,
        attributedTo: attribution(
          141,
          for: operationIdentity,
          sequence: 2,
          preRevision: 1,
          at: time(5)
        )
      ) == .alreadyTerminal
    )
    #expect(await registry.stop(using: capability, at: time(6)) == .retiredCapability)
    await #expect(throws: AdmissionError.effectAlreadyKnown(operationIdentity)) {
      _ = try await registry.register(
        identity: operationIdentity,
        lane: .exactWorkflow,
        context: context(40),
        handle: TestHandle(),
        cancellationAvailable: true,
        admittedAt: time(7)
      )
    }
    #expect(await handle.metrics() == TestHandleMetrics(cancelRequests: 0, settlementWaits: 0))
  }

  @Test("shutdown closes admission and requests every latched owner before awaiting settlement")
  func shutdownPriorityAndClosure() async throws {
    let registry = try makeRegistry()
    let machineIdentity = identity(50)
    let exactIdentity = identity(51)
    let cancellingIdentity = identity(52)
    let machineHandle = TestHandle(blockCancellationRequest: true)
    let exactHandle = TestHandle()
    let cancellingHandle = TestHandle()
    let machine = try await registry.register(
      identity: machineIdentity,
      lane: .machine,
      context: context(50),
      handle: machineHandle,
      cancellationAvailable: true,
      admittedAt: time(0)
    )
    let exact = try await registry.register(
      identity: exactIdentity,
      lane: .exactWorkflow,
      context: context(51),
      handle: exactHandle,
      cancellationAvailable: false,
      admittedAt: time(0)
    )
    let cancelling = try await registry.register(
      identity: cancellingIdentity,
      lane: .analysis,
      context: context(52),
      handle: cancellingHandle,
      cancellationAvailable: true,
      admittedAt: time(0)
    )
    try requireStartAccepted(
      await registry.start(
        machine.takePermit(),
        for: machineIdentity,
        attributedTo: attribution(
          150,
          for: machineIdentity,
          sequence: 1,
          preRevision: 0,
          at: time(1)
        )
      )
    )

    let shutdownTask = Task {
      await registry.shutdown(at: time(2))
    }
    #expect(await eventually {
      let machineMetrics = await machineHandle.metrics()
      let exactMetrics = await exactHandle.metrics()
      let cancellingMetrics = await cancellingHandle.metrics()
      return machineMetrics.cancelRequests == 1
        && exactMetrics.cancelRequests == 1
        && cancellingMetrics.cancelRequests == 1
    })

    let closing = await registry.snapshot()
    #expect(closing.admission == .closed)
    #expect(closing.active.count == 3)
    #expect(closing.active.allSatisfy { $0.phase == .cancelling })
    #expect(closing.active.allSatisfy { $0.cancellationReason == .shutdown })
    await #expect(throws: AdmissionError.admissionClosed) {
      try await register(53, lane: .append, in: registry)
    }
    try requireStartCancellationInProgress(
      await registry.start(
        cancelling.takePermit(),
        for: cancellingIdentity,
        attributedTo: attribution(
          151,
          for: cancellingIdentity,
          sequence: 2,
          preRevision: 1,
          at: time(3)
        )
      )
    )
    await machineHandle.releaseCancellationRequest()
    #expect(await eventually {
      await registry.snapshot().active.allSatisfy { $0.phase == .settling }
    })

    await machineHandle.finish(.cancelled)
    await exactHandle.finish(.cancelled)
    await cancellingHandle.finish(.cancelled)
    let report = await shutdownTask.value
    #expect(report.admissionWasAlreadyClosed == false)
    #expect(
      Set(report.settled.map(\.identity))
        == Set([machineIdentity, exactIdentity, cancellingIdentity])
    )
    #expect(await machineHandle.metrics() == TestHandleMetrics(cancelRequests: 1, settlementWaits: 1))
    #expect(await exactHandle.metrics() == TestHandleMetrics(cancelRequests: 1, settlementWaits: 1))
    #expect(
      await cancellingHandle.metrics()
        == TestHandleMetrics(cancelRequests: 1, settlementWaits: 1)
    )
    try requireStartRetired(
      await registry.start(
        exact.takePermit(),
        for: exactIdentity,
        attributedTo: attribution(
          152,
          for: exactIdentity,
          sequence: 2,
          preRevision: 1,
          at: time(4)
        )
      )
    )

    let repeated = await registry.shutdown(at: time(5))
    #expect(repeated.admissionWasAlreadyClosed)
    #expect(repeated.settled.isEmpty)
  }

  @Test("concurrent Stop and shutdown share one cancellation and one original-owner await")
  func concurrentStopAndShutdown() async throws {
    let registry = try makeRegistry()
    let operationIdentity = identity(60)
    let handle = TestHandle()
    let registration = try await registry.register(
      identity: operationIdentity,
      lane: .machine,
      context: context(60),
      handle: handle,
      cancellationAvailable: true,
      admittedAt: time(0)
    )
    let stopCapability = registration.stopCapability
    let capability = try #require(stopCapability)
    try requireStartAccepted(
      await registry.start(
        registration.takePermit(),
        for: operationIdentity,
        attributedTo: attribution(
          160,
          for: operationIdentity,
          sequence: 1,
          preRevision: 0,
          at: time(1)
        )
      )
    )

    let stopTask = Task { await registry.stop(using: capability, at: time(2)) }
    #expect(await eventually { await handle.metrics().settlementWaits == 1 })
    let shutdownTask = Task { await registry.shutdown(at: time(3)) }
    #expect(await eventually { await registry.snapshot().admission == .closed })
    #expect(await handle.metrics() == TestHandleMetrics(cancelRequests: 1, settlementWaits: 1))

    await handle.finish(.cancelled)
    #expect(await stopTask.value == .settled(.cancelled))
    let shutdown = await shutdownTask.value
    #expect(shutdown.settled.map(\.identity) == [operationIdentity])
    #expect(await handle.metrics() == TestHandleMetrics(cancelRequests: 1, settlementWaits: 1))
  }

  @Test("event attribution is exact, unique, monotonic, and refusal is nonmutating")
  func exactEventAttribution() async throws {
    let registry = try makeRegistry()
    let operationIdentity = identity(80)
    let registration = try await registry.register(
      identity: operationIdentity,
      lane: .machine,
      context: context(80),
      handle: TestHandle(),
      cancellationAvailable: true,
      admittedAt: time(1)
    )
    let startAttribution = attribution(
      180,
      for: operationIdentity,
      sequence: 10,
      preRevision: 20,
      at: time(2)
    )
    try requireStartAccepted(
      await registry.start(
        registration.takePermit(),
        for: operationIdentity,
        attributedTo: startAttribution
      )
    )
    let accepted = await registry.snapshot()
    let acceptedOperation = try #require(accepted.active.first)
    #expect(acceptedOperation.lastAcceptedAttribution == startAttribution)

    let foreignIdentity = identity(81)
    let foreignAttribution = attribution(
      181,
      for: foreignIdentity,
      sequence: 11,
      preRevision: 21,
      at: time(3)
    )
    #expect(
      await registry.recordProgress(
        for: operationIdentity,
        phase: .progressing,
        attributedTo: foreignAttribution
      ) == .attributionRefused(.identityMismatch(expected: operationIdentity))
    )

    let duplicateAttribution = PlotterOperationEventAttribution(
      identity: operationIdentity,
      eventID: startAttribution.eventID,
      sequence: EpisodeEventSequence(rawValue: 11),
      preStateRevision: EpisodeStateRevision(rawValue: 21),
      postStateRevision: EpisodeStateRevision(rawValue: 22),
      recordedAt: time(3)
    )
    #expect(
      await registry.recordProgress(
        for: operationIdentity,
        phase: .progressing,
        attributedTo: duplicateAttribution
      ) == .attributionRefused(.duplicateEventID(startAttribution.eventID))
    )

    let sequenceRegression = attribution(
      182,
      for: operationIdentity,
      sequence: 10,
      preRevision: 21,
      at: time(3)
    )
    #expect(
      await registry.recordProgress(
        for: operationIdentity,
        phase: .progressing,
        attributedTo: sequenceRegression
      ) == .attributionRefused(
        .eventSequenceRegression(
          previous: startAttribution.sequence,
          actual: sequenceRegression.sequence
        )
      )
    )

    let stateRegression = attribution(
      183,
      for: operationIdentity,
      sequence: 11,
      preRevision: 20,
      at: time(3)
    )
    #expect(
      await registry.recordProgress(
        for: operationIdentity,
        phase: .progressing,
        attributedTo: stateRegression
      ) == .attributionRefused(
        .stateRevisionRegression(
          previousPost: startAttribution.postStateRevision,
          actualPre: stateRegression.preStateRevision
        )
      )
    )

    let invalidTransition = PlotterOperationEventAttribution(
      identity: operationIdentity,
      eventID: EpisodeEventID(rawValue: uuid(value: 4_184)),
      sequence: EpisodeEventSequence(rawValue: 11),
      preStateRevision: EpisodeStateRevision(rawValue: 21),
      postStateRevision: EpisodeStateRevision(rawValue: 23),
      recordedAt: time(3)
    )
    #expect(
      await registry.recordProgress(
        for: operationIdentity,
        phase: .progressing,
        attributedTo: invalidTransition
      ) == .attributionRefused(
        .invalidStateRevisionTransition(
          pre: invalidTransition.preStateRevision,
          post: invalidTransition.postStateRevision
        )
      )
    )

    let timestampRegression = attribution(
      185,
      for: operationIdentity,
      sequence: 11,
      preRevision: 21,
      at: time(1)
    )
    #expect(
      await registry.recordProgress(
        for: operationIdentity,
        phase: .progressing,
        attributedTo: timestampRegression
      ) == .attributionRefused(
        .timestampRegression(previous: time(2), actual: time(1))
      )
    )

    let afterRefusals = await registry.snapshot()
    let unchangedOperation = try #require(afterRefusals.active.first)
    #expect(afterRefusals.revision == accepted.revision)
    #expect(unchangedOperation.phase == acceptedOperation.phase)
    #expect(unchangedOperation.lastAcceptedAttribution == startAttribution)
    #expect(unchangedOperation.lastAttributableProgressAt == time(2))

    let validProgress = attribution(
      186,
      for: operationIdentity,
      sequence: 11,
      preRevision: 21,
      at: time(3)
    )
    #expect(
      await registry.recordProgress(
        for: operationIdentity,
        phase: .waiting,
        attributedTo: validProgress
      ) == .accepted
    )
    let progressed = await registry.snapshot()
    #expect(progressed.revision == accepted.revision + 1)
    #expect(progressed.active.first?.lastAcceptedAttribution == validProgress)

    let foreignStartIdentity = identity(82)
    let foreignStart = try await registry.register(
      identity: foreignStartIdentity,
      lane: .analysis,
      context: context(82),
      handle: TestHandle(),
      cancellationAvailable: true,
      admittedAt: time(3)
    )
    let beforeForeignStart = await registry.snapshot()
    let foreignStartRefusal = await registry.start(
      foreignStart.takePermit(),
      for: foreignStartIdentity,
      attributedTo: attribution(
        187,
        for: operationIdentity,
        sequence: 12,
        preRevision: 22,
        at: time(4)
      )
    )
    let foreignRetryPermit = try requireAttributionRefusalPermit(
      foreignStartRefusal,
      expected: .identityMismatch(expected: foreignStartIdentity)
    )
    let afterForeignStart = await registry.snapshot()
    #expect(afterForeignStart.revision == beforeForeignStart.revision)
    #expect(
      afterForeignStart.active.first { $0.identity == foreignStartIdentity }?.phase == .waiting
    )
    try requireStartAccepted(
      await registry.start(
        foreignRetryPermit,
        for: foreignStartIdentity,
        attributedTo: attribution(
          188,
          for: foreignStartIdentity,
          sequence: 12,
          preRevision: 22,
          at: time(4)
        )
      )
    )

    let reusedEventIdentity = identity(83)
    let reusedEventRegistration = try await registry.register(
      identity: reusedEventIdentity,
      lane: .exactWorkflow,
      context: context(83),
      handle: TestHandle(),
      cancellationAvailable: true,
      admittedAt: time(3)
    )
    let reusedEvent = PlotterOperationEventAttribution(
      identity: reusedEventIdentity,
      eventID: validProgress.eventID,
      sequence: EpisodeEventSequence(rawValue: 12),
      preStateRevision: EpisodeStateRevision(rawValue: 22),
      postStateRevision: EpisodeStateRevision(rawValue: 23),
      recordedAt: time(4)
    )
    let reusedEventRefusal = await registry.start(
      reusedEventRegistration.takePermit(),
      for: reusedEventIdentity,
      attributedTo: reusedEvent
    )
    let reusedEventRetryPermit = try requireAttributionRefusalPermit(
      reusedEventRefusal,
      expected: .duplicateEventID(validProgress.eventID)
    )
    let afterReusedEvent = await registry.snapshot()
    #expect(afterReusedEvent.revision == afterForeignStart.revision + 2)
    #expect(
      afterReusedEvent.active.first { $0.identity == reusedEventIdentity }?.phase == .waiting
    )
    try requireStartAccepted(
      await registry.start(
        reusedEventRetryPermit,
        for: reusedEventIdentity,
        attributedTo: attribution(
          189,
          for: reusedEventIdentity,
          sequence: 12,
          preRevision: 22,
          at: time(4)
        )
      )
    )
  }

  @Test("snapshots expose revisioned waiting, progress, stall, cancellation, and terminal state")
  func observableLifecycleState() async throws {
    let registry = try makeRegistry()
    let initial = await registry.snapshot()
    #expect(initial.revision == 0)
    #expect(initial.admission == .open)
    #expect(initial.active.isEmpty)

    let operationIdentity = identity(70)
    let operationContext = context(70)
    let handle = TestHandle()
    let registration = try await registry.register(
      identity: operationIdentity,
      lane: .analysis,
      context: operationContext,
      handle: handle,
      cancellationAvailable: true,
      admittedAt: time(1),
      deadline: time(10)
    )
    let waiting = await registry.snapshot()
    let waitingOperation = try #require(waiting.active.first)
    #expect(waiting.revision == 1)
    #expect(waitingOperation.identity == operationIdentity)
    #expect(waitingOperation.context == operationContext)
    #expect(waitingOperation.intentIdentity == operationContext.intentIdentity)
    #expect(waitingOperation.environment == operationContext.environment)
    #expect(waitingOperation.owningSubsystem == operationContext.owningSubsystem)
    #expect(
      waitingOperation.resultCurrentlyAwaited == operationContext.resultCurrentlyAwaited
    )
    #expect(waitingOperation.phase == .waiting)
    #expect(waitingOperation.startedAt == nil)
    #expect(waitingOperation.deadline == time(10))
    #expect(waitingOperation.cancellationAvailable)
    #expect(waitingOperation.cancellationPhase == .notRequested)

    let startAttribution = attribution(
      170,
      for: operationIdentity,
      sequence: 10,
      preRevision: 10,
      at: time(2)
    )
    try requireStartAccepted(
      await registry.start(
        registration.takePermit(),
        for: operationIdentity,
        attributedTo: startAttribution
      )
    )
    let waitingAttribution = attribution(
      171,
      for: operationIdentity,
      sequence: 11,
      preRevision: 11,
      at: time(3)
    )
    #expect(
      await registry.recordProgress(
        for: operationIdentity,
        phase: .waiting,
        attributedTo: waitingAttribution
      ) == .accepted
    )
    let stalledAttribution = attribution(
      172,
      for: operationIdentity,
      sequence: 12,
      preRevision: 12,
      at: time(4)
    )
    #expect(
      await registry.recordProgress(
        for: operationIdentity,
        phase: .suspectedStall,
        attributedTo: stalledAttribution
      ) == .accepted
    )
    #expect(
      await registry.recordProgress(
        for: operationIdentity,
        phase: .progressing,
        attributedTo: attribution(
          173,
          for: operationIdentity,
          sequence: 13,
          preRevision: 13,
          at: time(3)
        )
      ) == .attributionRefused(.timestampRegression(previous: time(4), actual: time(3)))
    )
    #expect(
      await registry.recordProgress(
        for: operationIdentity,
        phase: .cancelling,
        attributedTo: attribution(
          174,
          for: operationIdentity,
          sequence: 13,
          preRevision: 13,
          at: time(5)
        )
      ) == .invalidLifecyclePhase
    )
    let stalled = await registry.snapshot()
    let stalledOperation = try #require(stalled.active.first)
    #expect(stalledOperation.startedAt == time(2))
    #expect(stalledOperation.lastAttributableProgressAt == time(4))
    #expect(stalledOperation.lastAcceptedAttribution == stalledAttribution)
    #expect(stalledOperation.phase == .suspectedStall)
    #expect(stalled.revision == 4)

    #expect(
      await registry.settle(identity: operationIdentity, disposition: .completed, at: time(6))
        == .accepted(.completed)
    )
    let terminal = await registry.snapshot()
    #expect(terminal.active.isEmpty)
    #expect(terminal.terminal.count == 1)
    #expect(terminal.terminal.first?.identity == operationIdentity)
    #expect(terminal.terminal.first?.context == operationContext)
    #expect(terminal.terminal.first?.intentIdentity == operationContext.intentIdentity)
    #expect(terminal.terminal.first?.environment == operationContext.environment)
    #expect(terminal.terminal.first?.owningSubsystem == operationContext.owningSubsystem)
    #expect(
      terminal.terminal.first?.resultCurrentlyAwaited
        == operationContext.resultCurrentlyAwaited
    )
    #expect(terminal.terminal.first?.lastAcceptedAttribution == stalledAttribution)
    #expect(terminal.terminal.first?.disposition == .completed)
    #expect(terminal.terminal.first?.cancellationReason == nil)
    #expect(terminal.lastChangedAt == time(6))
  }
}

private enum TestLane: Hashable, Sendable {
  case machine
  case exactWorkflow
  case analysis
  case append
  case other
}

private enum TestAwaitedResult: Hashable, Sendable {
  case ownerSettlement(Int)
}

private enum TestIntentIdentity: Hashable, Sendable {
  case operation(Int)
}

private enum TestEnvironment: Hashable, Sendable {
  case live
  case simulated
}

private struct TestContext: PlotterOperationContext {
  let intentIdentity: TestIntentIdentity
  let environment: TestEnvironment
  let owningSubsystem: EpisodeAuthorityID
  let resultCurrentlyAwaited: TestAwaitedResult
}

private enum TestDisposition: Hashable, Sendable {
  case completed
  case cancelled
  case failed
}

private struct TestHandleMetrics: Equatable, Sendable {
  let cancelRequests: Int
  let settlementWaits: Int
}

private actor TestHandle: PlotterOperationHandle {
  typealias TerminalDisposition = TestDisposition

  private let blockCancellationRequest: Bool
  private var cancelRequests = 0
  private var settlementWaits = 0
  private var disposition: TestDisposition?
  private var cancellationRequestWaiters: [CheckedContinuation<Void, Never>] = []
  private var waiters: [CheckedContinuation<TestDisposition, Never>] = []

  init(blockCancellationRequest: Bool = false) {
    self.blockCancellationRequest = blockCancellationRequest
  }

  func requestCancellation() async {
    cancelRequests += 1
    guard blockCancellationRequest else { return }
    await withCheckedContinuation { continuation in
      cancellationRequestWaiters.append(continuation)
    }
  }

  func releaseCancellationRequest() {
    let currentWaiters = cancellationRequestWaiters
    cancellationRequestWaiters.removeAll()
    for waiter in currentWaiters {
      waiter.resume()
    }
  }

  func waitForSettlement() async -> TestDisposition {
    settlementWaits += 1
    if let disposition { return disposition }
    return await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func finish(_ disposition: TestDisposition) {
    guard self.disposition == nil else { return }
    self.disposition = disposition
    let currentWaiters = waiters
    waiters.removeAll()
    for waiter in currentWaiters {
      waiter.resume(returning: disposition)
    }
  }

  func metrics() -> TestHandleMetrics {
    TestHandleMetrics(
      cancelRequests: cancelRequests,
      settlementWaits: settlementWaits
    )
  }
}

private typealias Registry = PlotterOperationRegistry<TestLane, TestContext, TestHandle>
private typealias AdmissionError = PlotterOperationAdmissionError<TestLane>
private typealias LaneConfigurationError = PlotterOperationLaneConfigurationError<TestLane>

private func makeRegistry(backgroundAnalysisLimit: Int = 2) throws -> Registry {
  let lanes = try PlotterOperationLaneConfiguration(
    machine: TestLane.machine,
    exactWorkflowCaptureVision: .exactWorkflow,
    backgroundAnalysis: .analysis,
    durableAppend: .append,
    backgroundAnalysisLimit: backgroundAnalysisLimit
  )
  return Registry(lanes: lanes, openedAt: time(0))
}

@discardableResult
private func register(
  _ value: Int,
  lane: TestLane,
  in registry: Registry,
  admittedAt: Date = time(0)
) async throws -> PlotterOperationRegistration {
  try await registry.register(
    identity: identity(value),
    lane: lane,
    context: context(value),
    handle: TestHandle(),
    cancellationAvailable: true,
    admittedAt: admittedAt
  )
}

private func identity(_ value: Int) -> PlotterOperationIdentity {
  PlotterOperationIdentity(
    episodeID: EpisodeID(rawValue: uuid(value: 1_000)),
    requestID: IntentRequestID(rawValue: uuid(value: 2_000 + value)),
    effectID: EpisodeEffectID(rawValue: uuid(value: 3_000 + value)),
    effectRevision: EpisodeRevisionIdentifier(rawValue: "effect-\(value)")
  )
}

private func context(_ value: Int) -> TestContext {
  TestContext(
    intentIdentity: .operation(value),
    environment: value.isMultiple(of: 2) ? .simulated : .live,
    owningSubsystem: EpisodeAuthorityID(rawValue: "owner-\(value)"),
    resultCurrentlyAwaited: .ownerSettlement(value)
  )
}

private func attribution(
  _ value: Int,
  for identity: PlotterOperationIdentity,
  sequence: UInt64,
  preRevision: UInt64,
  at recordedAt: Date
) -> PlotterOperationEventAttribution {
  PlotterOperationEventAttribution(
    identity: identity,
    eventID: EpisodeEventID(rawValue: uuid(value: 4_000 + value)),
    sequence: EpisodeEventSequence(rawValue: sequence),
    preStateRevision: EpisodeStateRevision(rawValue: preRevision),
    postStateRevision: EpisodeStateRevision(rawValue: preRevision + 1),
    recordedAt: recordedAt
  )
}

private func time(_ offset: TimeInterval) -> Date {
  Date(timeIntervalSince1970: 1_800_000_000 + offset)
}

private func uuid(value: Int) -> UUID {
  UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
}

private enum PermitOutcomeTestError: Error {
  case unexpectedOutcome
}

private func requireIdentityMismatchPermit(
  _ outcome: consuming EffectPermitConsumption,
  expected: PlotterOperationIdentity
) throws -> EffectPermit {
  switch consume outcome {
  case let .identityMismatch(actual, permit):
    #expect(actual == expected)
    return permit
  case .accepted:
    throw PermitOutcomeTestError.unexpectedOutcome
  case .attributionRefused(_, _):
    throw PermitOutcomeTestError.unexpectedOutcome
  case .retired:
    throw PermitOutcomeTestError.unexpectedOutcome
  case .cancellationInProgress:
    throw PermitOutcomeTestError.unexpectedOutcome
  }
}

private func requireAttributionRefusalPermit(
  _ outcome: consuming EffectPermitConsumption,
  expected: PlotterOperationAttributionRefusal
) throws -> EffectPermit {
  switch consume outcome {
  case let .attributionRefused(actual, permit):
    #expect(actual == expected)
    return permit
  case .accepted:
    throw PermitOutcomeTestError.unexpectedOutcome
  case .identityMismatch(_, _):
    throw PermitOutcomeTestError.unexpectedOutcome
  case .retired:
    throw PermitOutcomeTestError.unexpectedOutcome
  case .cancellationInProgress:
    throw PermitOutcomeTestError.unexpectedOutcome
  }
}

private func requireStartAccepted(
  _ outcome: consuming EffectPermitConsumption
) throws {
  switch consume outcome {
  case .accepted:
    return
  case .identityMismatch(_, _):
    throw PermitOutcomeTestError.unexpectedOutcome
  case .attributionRefused(_, _):
    throw PermitOutcomeTestError.unexpectedOutcome
  case .retired:
    throw PermitOutcomeTestError.unexpectedOutcome
  case .cancellationInProgress:
    throw PermitOutcomeTestError.unexpectedOutcome
  }
}

private func requireStartCancellationInProgress(
  _ outcome: consuming EffectPermitConsumption
) throws {
  switch consume outcome {
  case .cancellationInProgress:
    return
  case .accepted:
    throw PermitOutcomeTestError.unexpectedOutcome
  case .identityMismatch(_, _):
    throw PermitOutcomeTestError.unexpectedOutcome
  case .attributionRefused(_, _):
    throw PermitOutcomeTestError.unexpectedOutcome
  case .retired:
    throw PermitOutcomeTestError.unexpectedOutcome
  }
}

private func requireStartRetired(
  _ outcome: consuming EffectPermitConsumption
) throws {
  switch consume outcome {
  case .retired:
    return
  case .accepted:
    throw PermitOutcomeTestError.unexpectedOutcome
  case .identityMismatch(_, _):
    throw PermitOutcomeTestError.unexpectedOutcome
  case .attributionRefused(_, _):
    throw PermitOutcomeTestError.unexpectedOutcome
  case .cancellationInProgress:
    throw PermitOutcomeTestError.unexpectedOutcome
  }
}

private func eventually(
  _ predicate: @escaping @Sendable () async -> Bool
) async -> Bool {
  for _ in 0..<1_000 {
    if await predicate() { return true }
    await Task.yield()
  }
  return false
}
