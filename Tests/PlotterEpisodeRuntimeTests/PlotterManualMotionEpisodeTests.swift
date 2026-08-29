import EpisodeCore
import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import Testing
import os

@Suite("Plotter manual-motion episode runtime")
struct PlotterManualMotionEpisodeTests {
  @Test("shutdown retires dormant LIVE and SIMULATED operations without native invocation")
  func prestartShutdown() async throws {
    for environment in [PlotterEnvironment.live, .simulated] {
      for boundary in [
        PlotterManualMotionPrestartBoundary.registered,
        .registryStarted,
      ] {
        let live = ManualMotionAdapterProbe(environment: .live)
        let simulated = ManualMotionAdapterProbe(environment: .simulated)
        let runtime = try PlotterManualMotionRuntime(
          journalFileURL: manualMotionJournalFileURL(),
          liveAdapter: live,
          simulatedAdapter: simulated
        )
        let gate = PlotterManualMotionPrestartGate(boundary: boundary)
        await runtime.installPrestartGateForTesting(gate)
        let adapter = environment == .live ? live : simulated
        let submit = Task {
          try await runtime.submit(
            .jog(try PlotterJogRequest(
              direction: .positiveX,
              distanceMM: 1,
              feedMMPerMinute: 100,
              routing: .relativeTravel
            )),
            capabilityFacts: controllerFacts(environment: environment, penState: .raised),
            environment: environment
          )
        }
        #expect(await completesBeforeManualMotionTestDeadline {
          await gate.waitUntilBoundaryIsHeld()
        })
        let operation = try #require(adapter.operation(at: 0))
        let shutdownCompletion = ManualMotionCompletionSignal()
        let shutdown = Task {
          await runtime.shutdown()
          await shutdownCompletion.finish()
        }
        #expect(await completesBeforeManualMotionTestDeadline {
          await shutdownCompletion.waitUntilFinished()
        })
        #expect(await operation.startCount == 0)
        #expect(await operation.cancellationRequestCount == 0)
        gate.releaseBoundary()
        let result = try await submit.value
        await shutdown.value
        #expect(await operation.startCount == 0)
        #expect(await operation.cancellationRequestCount == 0)
        #expect(result.snapshot.activeOperation == nil)
        if boundary == .registered {
          #expect(result.disposition == .refused)
          #expect(result.snapshot.journal.journal.events.isEmpty)
        } else {
          #expect(result.disposition == .accepted)
          #expect(result.snapshot.projection.lastTerminalEffect?.disposition == .cancelled)
          let payloads = result.snapshot.journal.journal.events.map(\.payload)
          #expect(payloads.count == 2)
          #expect(payloads.contains { if case .intentAccepted = $0 { true } else { false } })
          #expect(payloads.contains { if case .effectResult = $0 { true } else { false } })
        }
      }
    }
  }

  @Test("post-progress shutdown latch retires the owner before runtime activation")
  func postProgressShutdownLatch() async throws {
    for environment in [PlotterEnvironment.live, .simulated] {
      let live = ManualMotionAdapterProbe(environment: .live)
      let simulated = ManualMotionAdapterProbe(environment: .simulated)
      let runtime = try PlotterManualMotionRuntime(
        journalFileURL: manualMotionJournalFileURL(),
        liveAdapter: live,
        simulatedAdapter: simulated
      )
      let gate = PlotterManualMotionPrestartGate(boundary: .progressRecorded)
      await runtime.installPrestartGateForTesting(gate)
      let adapter = environment == .live ? live : simulated
      let submit = Task {
        try await runtime.submit(
          .jog(try PlotterJogRequest(
            direction: .positiveX,
            distanceMM: 1,
            feedMMPerMinute: 100,
            routing: .relativeTravel
          )),
          capabilityFacts: controllerFacts(environment: environment, penState: .raised),
          environment: environment
        )
      }
      #expect(await completesBeforeManualMotionTestDeadline {
        await gate.waitUntilBoundaryIsHeld()
      })
      let operation = try #require(adapter.operation(at: 0))
      let registered = await runtime.registryOwnershipForTesting()
      let effectID = try #require(registered.activeEffectIDs.first)
      #expect(registered.activeEffectIDs == [effectID])
      #expect(registered.terminalEffectIDs.isEmpty)

      let shutdownCompletion = ManualMotionCompletionSignal()
      let shutdown = Task {
        await runtime.shutdown()
        await shutdownCompletion.finish()
      }
      #expect(await completesBeforeManualMotionTestDeadline {
        await shutdownCompletion.waitUntilFinished()
      })
      let retired = await runtime.registryOwnershipForTesting()
      #expect(retired.activeEffectIDs.isEmpty)
      #expect(retired.terminalEffectIDs == [effectID])
      #expect(await operation.startCount == 0)
      #expect(await operation.cancellationRequestCount == 0)

      gate.releaseBoundary()
      let result = try await submit.value
      await shutdown.value
      #expect(result.disposition == .accepted)
      #expect(result.snapshot.activeOperation == nil)
      #expect(result.snapshot.projection.lastTerminalEffect?.disposition == .cancelled)
      #expect(result.snapshot.projection.lastTerminalEffect?.result.context.effectID == effectID)
      let terminalEvents = result.snapshot.journal.journal.events.filter { event in
        if case .effectResult = event.payload { return true }
        return false
      }
      #expect(terminalEvents.count == 1)
      #expect(await operation.startCount == 0)
      #expect(await operation.cancellationRequestCount == 0)
    }
  }

  @Test("LIVE and SIMULATED use one typed grammar without sharing provenance")
  func environmentAdapters() async throws {
    let live = ManualMotionAdapterProbe(environment: .live)
    let simulated = ManualMotionAdapterProbe(environment: .simulated)
    let runtime = try PlotterManualMotionRuntime(
      journalFileURL: manualMotionJournalFileURL(),
      liveAdapter: live,
      simulatedAdapter: simulated
    )
    let request = try PlotterJogRequest(
      direction: .negativeY,
      distanceMM: 50,
      feedMMPerMinute: 500,
      routing: .possibleInk
    )
    let submission = try await runtime.submit(
      .jog(request),
      capabilityFacts: controllerFacts(environment: .simulated, penState: .unknown),
      environment: .simulated
    )

    #expect(submission.disposition == .accepted)
    #expect(submission.snapshot.activeOperation?.intent == .jog(request))
    #expect(submission.snapshot.projection.activeEffectProgress?.environment == .simulated)
    #expect(submission.snapshot.projection.activeEffectProgress?.lane == .machine)
    #expect(live.operationCount == 0)
    #expect(simulated.operationCount == 1)
    #expect(simulated.receivedControllerRecorder == false)
    await simulated.operation(at: 0)?.complete()
  }

  @Test("exact concurrent Stop settles one owner and cannot stop its successor")
  func exactStop() async throws {
    let live = ManualMotionAdapterProbe(environment: .live)
    let simulated = ManualMotionAdapterProbe(environment: .simulated)
    let runtime = try PlotterManualMotionRuntime(
      journalFileURL: manualMotionJournalFileURL(),
      liveAdapter: live,
      simulatedAdapter: simulated
    )
    let first = try await runtime.submit(
      .jog(try PlotterJogRequest(
        direction: .positiveX,
        distanceMM: 10,
        feedMMPerMinute: 300,
        routing: .drawingStroke
      )),
      capabilityFacts: controllerFacts(environment: .live, penState: .lowered),
      environment: .live
    )
    let firstStop = try #require(first.snapshot.activeOperation?.stopCapabilityID)
    async let stopA = runtime.stop(using: firstStop)
    async let stopB = runtime.stop(using: firstStop)
    let (resultA, resultB) = await (stopA, stopB)

    #expect(resultA.disposition == .settled)
    #expect(resultB.disposition == .settled)
    #expect(await live.operation(at: 0)?.cancellationRequestCount == 1)
    #expect(resultA.snapshot.projection.lastTerminalEffect?.disposition == .cancelled)
    let cancellationPhases: [PlotterEffectCancellationPhase] =
      resultA.snapshot.journal.journal.events.compactMap { event in
      guard case let .effectProgressed(progress) = event.payload,
            progress.cancellation.phase != .notRequested else { return nil }
      return progress.cancellation.phase
    }
    #expect(cancellationPhases == [.requested, .observed, .settling])
    guard case let .cancelledAfterSettlement(_, settlement)? =
      resultA.snapshot.projection.lastTerminalEffect?.result
    else {
      Issue.record("Expected typed cancellation settlement")
      return
    }
    guard case .drawingStoppedWithPenRaised = settlement else {
      Issue.record("Stopped drawing did not retain Pen-Up settlement")
      return
    }
    #expect((await runtime.stop(using: firstStop)).disposition == .settled)

    let second = try await runtime.submit(
      .jog(try PlotterJogRequest(
        direction: .positiveY,
        distanceMM: 5,
        feedMMPerMinute: 250,
        routing: .relativeTravel
      )),
      capabilityFacts: controllerFacts(environment: .live, penState: .raised),
      environment: .live
    )
    #expect(second.disposition == .accepted)
    let stale = await runtime.stop(using: firstStop)
    #expect(stale.disposition == .stale)
    #expect(await live.operation(at: 1)?.cancellationRequestCount == 0)
    #expect(stale.snapshot.activeOperation?.context.effectID
      == second.snapshot.activeOperation?.context.effectID)
    let secondStop = try #require(second.snapshot.activeOperation?.stopCapabilityID)
    _ = await runtime.stop(using: secondStop)
  }

  @Test("duplicate Stop joins one terminal publication and returns one complete snapshot")
  func stopPublicationSingleFlight() async throws {
    let live = ManualMotionAdapterProbe(environment: .live)
    let simulated = ManualMotionAdapterProbe(environment: .simulated)
    let runtime = try PlotterManualMotionRuntime(
      journalFileURL: manualMotionJournalFileURL(),
      liveAdapter: live,
      simulatedAdapter: simulated
    )
    let publicationGate = PlotterManualMotionTerminalPublicationGate()
    await runtime.installTerminalPublicationGateForTesting(publicationGate)
    let first = try await runtime.submit(
      .jog(try PlotterJogRequest(
        direction: .negativeX,
        distanceMM: 4,
        feedMMPerMinute: 200,
        routing: .drawingStroke
      )),
      capabilityFacts: controllerFacts(environment: .live, penState: .lowered),
      environment: .live
    )
    let capability = try #require(first.snapshot.activeOperation?.stopCapabilityID)

    let firstStop = Task { await runtime.stop(using: capability) }
    await publicationGate.waitUntilPublicationIsHeld()
    let duplicateStop = Task { await runtime.stop(using: capability) }
    await publicationGate.waitUntilDuplicateHasJoined()
    publicationGate.releasePublication()
    let firstResult = await firstStop.value
    let duplicateResult = await duplicateStop.value

    #expect(firstResult.disposition == .settled)
    #expect(duplicateResult.disposition == .settled)
    #expect(firstResult.snapshot.activeOperation == nil)
    #expect(duplicateResult.snapshot.activeOperation == nil)
    #expect(firstResult.snapshot.projection.projectionRevision
      == duplicateResult.snapshot.projection.projectionRevision)
    #expect(firstResult.snapshot.projection.runtimeStateRevision
      == duplicateResult.snapshot.projection.runtimeStateRevision)
    #expect(firstResult.snapshot.projection.lastTerminalEffect
      == duplicateResult.snapshot.projection.lastTerminalEffect)
    #expect(firstResult.snapshot.projection.lastTerminalEffect?.disposition == .cancelled)
    #expect(await live.operation(at: 0)?.cancellationRequestCount == 1)

    let successor = try await runtime.submit(
      .jog(try PlotterJogRequest(
        direction: .positiveY,
        distanceMM: 2,
        feedMMPerMinute: 200,
        routing: .relativeTravel
      )),
      capabilityFacts: controllerFacts(environment: .live, penState: .raised),
      environment: .live
    )
    #expect(successor.disposition == .accepted)
    #expect((await runtime.stop(using: capability)).disposition == .stale)
    #expect(await live.operation(at: 1)?.cancellationRequestCount == 0)
    let successorStop = try #require(successor.snapshot.activeOperation?.stopCapabilityID)
    _ = await runtime.stop(using: successorStop)
  }

  @Test("direct Pen carries its exact profile and exposes no jog Stop token")
  func directPen() async throws {
    let live = ManualMotionAdapterProbe(environment: .live)
    let simulated = ManualMotionAdapterProbe(environment: .simulated)
    let runtime = try PlotterManualMotionRuntime(
      journalFileURL: manualMotionJournalFileURL(),
      liveAdapter: live,
      simulatedAdapter: simulated
    )
    let profile = try PlotterManualPenActuationProfile(
      raisedSpindleValue: 45,
      loweredSpindleValue: 755,
      settleSeconds: 0.25,
      revision: revision("pen-profile-current")
    )
    let request = PlotterPenActuationRequest(position: .lowered, profile: profile)
    let submission = try await runtime.submit(
      .setPen(request),
      capabilityFacts: controllerFacts(
        environment: .live,
        penState: .raised,
        profileRevision: profile.revision
      ),
      environment: .live
    )

    #expect(submission.disposition == .accepted)
    #expect(submission.snapshot.activeOperation?.intent == .setPen(request))
    #expect(submission.snapshot.activeOperation?.stopCapabilityID == nil)
    #expect(submission.snapshot.projection.activeEffectProgress?.resultCurrentlyAwaited
      == .penSettlement)
    await live.operation(at: 0)?.complete()
  }

  @Test("LIVE records only actual adapter-supplied controller records")
  func liveControllerRecording() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("plotter-manual-motion-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let recording = try EpisodeRecordingStore.open(
      directoryURL: directory,
      recordingID: EpisodeRecordingID(rawValue: UUID()),
      schemaRevision: EpisodeRecordingSchemaRevision(rawValue: "manual-motion-test-v1"),
      frameRetentionPolicy: EpisodeFrameRetentionPolicy(
        maximumUniqueFrameCount: 1,
        maximumTotalUniqueFrameBytes: 1
      )
    )
    let live = ManualMotionAdapterProbe(
      environment: .live,
      recordsControllerPairOnStart: true
    )
    let simulated = ManualMotionAdapterProbe(environment: .simulated)
    let runtime = try PlotterManualMotionRuntime(
      journalFileURL: directory.appendingPathComponent("manual-motion-journal.json"),
      liveAdapter: live,
      simulatedAdapter: simulated,
      recordingStore: recording
    )
    _ = try await runtime.submit(
      .jog(try PlotterJogRequest(
        direction: .negativeX,
        distanceMM: 2,
        feedMMPerMinute: 100,
        routing: .relativeTravel
      )),
      capabilityFacts: controllerFacts(environment: .live, penState: .raised),
      environment: .live
    )
    let snapshot = await recording.snapshot()

    #expect(live.receivedControllerRecorder)
    #expect(snapshot.entries.count == 2)
    #expect(snapshot.entries.allSatisfy { entry in
      entry.provenance.episodeID != nil
        && entry.provenance.intentRequestID != nil
        && entry.provenance.effectID != nil
        && entry.provenance.environment == .live
    })
    await live.operation(at: 0)?.complete()
  }

  @Test("routing and current-profile mismatches remain typed refusals")
  func typedRefusals() async throws {
    let live = ManualMotionAdapterProbe(environment: .live)
    let simulated = ManualMotionAdapterProbe(environment: .simulated)
    let runtime = try PlotterManualMotionRuntime(
      journalFileURL: manualMotionJournalFileURL(),
      liveAdapter: live,
      simulatedAdapter: simulated
    )
    let submission = try await runtime.submit(
      .jog(try PlotterJogRequest(
        direction: .positiveX,
        distanceMM: 1,
        feedMMPerMinute: 100,
        routing: .relativeTravel
      )),
      capabilityFacts: controllerFacts(environment: .live, penState: .unknown),
      environment: .live
    )

    #expect(submission.disposition == .refused)
    #expect(submission.snapshot.activeOperation == nil)
    #expect(submission.snapshot.projection.authoritativeOwner
      == EpisodeAuthorityID(rawValue: "MachineController"))
    #expect(submission.snapshot.projection.remedy
      == "Refresh controller Pen state and rebuild the manual jog request.")
    #expect(live.operationCount == 0)
  }

  @Test("requested environment refuses capability facts from the other gateway")
  func environmentFactsFailClosed() async throws {
    let live = ManualMotionAdapterProbe(environment: .live)
    let simulated = ManualMotionAdapterProbe(environment: .simulated)
    let runtime = try PlotterManualMotionRuntime(
      journalFileURL: manualMotionJournalFileURL(),
      liveAdapter: live,
      simulatedAdapter: simulated
    )
    let submission = try await runtime.submit(
      .jog(try PlotterJogRequest(
        direction: .positiveX,
        distanceMM: 1,
        feedMMPerMinute: 100,
        routing: .relativeTravel
      )),
      capabilityFacts: controllerFacts(environment: .simulated, penState: .raised),
      environment: .live
    )

    #expect(submission.disposition == .refused)
    #expect(submission.snapshot.activeOperation == nil)
    #expect(live.operationCount == 0)
  }

  @Test("terminal append failure retains its owner and resumes the same publication cursor")
  func terminalPublicationRecovery() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("plotter-manual-recovery-\(UUID().uuidString)")
    let displaced = directory.appendingPathExtension("displaced")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: directory)
      try? FileManager.default.removeItem(at: displaced)
    }
    let live = ManualMotionAdapterProbe(environment: .live)
    let runtime = try PlotterManualMotionRuntime(
      journalFileURL: directory.appendingPathComponent("journal.json"),
      liveAdapter: live,
      simulatedAdapter: ManualMotionAdapterProbe(environment: .simulated)
    )
    let gate = PlotterManualMotionTerminalPublicationGate()
    await runtime.installTerminalPublicationGateForTesting(gate)
    let submission = try await runtime.submit(
      .jog(try PlotterJogRequest(
        direction: .positiveX,
        distanceMM: 1,
        feedMMPerMinute: 100,
        routing: .relativeTravel
      )),
      capabilityFacts: controllerFacts(environment: .live, penState: .raised),
      environment: .live
    )
    await live.operation(at: 0)?.complete()
    await gate.waitUntilPublicationIsHeld()
    try FileManager.default.moveItem(at: directory, to: displaced)
    gate.releasePublication()

    let incomplete = await runtime.currentSnapshot()
    let issue = try #require(incomplete.terminalPublicationIssue)
    #expect(incomplete.activeOperation?.context.effectID
      == submission.snapshot.activeOperation?.context.effectID)
    #expect(incomplete.projection.lastTerminalEffect == nil)

    try FileManager.default.moveItem(at: displaced, to: directory)
    let recovered = await runtime.recoverTerminalPublication(
      using: issue.recoveryCapabilityID
    )
    #expect(recovered.disposition == .published)
    #expect(recovered.snapshot.activeOperation == nil)
    #expect(recovered.snapshot.projection.lastTerminalEffect?.disposition == .completed)
    #expect(recovered.snapshot.terminalPublicationIssue == nil)
  }

  @Test("shutdown takes over a Stop blocked at requested journal publication")
  func shutdownTakeoverAfterRequestedPublicationFailure() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("plotter-manual-shutdown-recovery-\(UUID().uuidString)")
    let displaced = directory.appendingPathExtension("displaced")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: directory)
      try? FileManager.default.removeItem(at: displaced)
    }
    let cancellationGate = ManualMotionCancellationRequestGate()
    let live = ManualMotionAdapterProbe(
      environment: .live,
      cancellationRequestGate: cancellationGate
    )
    let runtime = try PlotterManualMotionRuntime(
      journalFileURL: directory.appendingPathComponent("journal.json"),
      liveAdapter: live,
      simulatedAdapter: ManualMotionAdapterProbe(environment: .simulated)
    )
    let submission = try await runtime.submit(
      .jog(try PlotterJogRequest(
        direction: .positiveX,
        distanceMM: 3,
        feedMMPerMinute: 100,
        routing: .relativeTravel
      )),
      capabilityFacts: controllerFacts(environment: .live, penState: .raised),
      environment: .live
    )
    let capability = try #require(submission.snapshot.activeOperation?.stopCapabilityID)
    try FileManager.default.moveItem(at: directory, to: displaced)

    let stopped = await runtime.stop(using: capability)
    let requestedIssue = try #require(stopped.snapshot.terminalPublicationIssue)
    #expect(stopped.disposition == .publicationPending)
    #expect(requestedIssue.stage == .cancellationRequested)
    #expect(await live.operation(at: 0)?.cancellationRequestCount == 0)

    let shutdownCompletion = ManualMotionCompletionSignal()
    let shutdown = Task {
      await runtime.shutdown()
      await shutdownCompletion.finish()
    }
    #expect(await completesBeforeManualMotionTestDeadline {
      await cancellationGate.waitUntilCancellationIsHeld()
    })
    #expect(await live.operation(at: 0)?.cancellationRequestCount == 1)
    #expect(await shutdownCompletion.isFinished == false)

    await cancellationGate.releaseCancellation()
    #expect(await completesBeforeManualMotionTestDeadline {
      await shutdownCompletion.waitUntilFinished()
    })
    await shutdown.value

    let incomplete = await runtime.currentSnapshot()
    let shutdownIssue = try #require(incomplete.terminalPublicationIssue)
    #expect(await live.operation(at: 0)?.cancellationRequestCount == 1)
    #expect(incomplete.activeOperation?.context.effectID
      == submission.snapshot.activeOperation?.context.effectID)
    #expect(incomplete.projection.lastTerminalEffect == nil)
    #expect(shutdownIssue.recoveryCapabilityID == requestedIssue.recoveryCapabilityID)
  }

  @Test("observed and settling Stop publishers converge with duplicate Stop and shutdown")
  func shutdownConvergesWithStagedStopPublisher() async throws {
    for phase in [PlotterEffectCancellationPhase.observed, .settling] {
      let live = ManualMotionAdapterProbe(environment: .live)
      let runtime = try PlotterManualMotionRuntime(
        journalFileURL: manualMotionJournalFileURL(),
        liveAdapter: live,
        simulatedAdapter: ManualMotionAdapterProbe(environment: .simulated)
      )
      let stageGate = PlotterManualMotionCancellationPublicationGate(targetPhase: phase)
      let terminalGate = PlotterManualMotionTerminalPublicationGate()
      await runtime.installCancellationPublicationGateForTesting(stageGate)
      await runtime.installTerminalPublicationGateForTesting(terminalGate)
      let submission = try await runtime.submit(
        .jog(try PlotterJogRequest(
          direction: .positiveX,
          distanceMM: 3,
          feedMMPerMinute: 100,
          routing: .relativeTravel
        )),
        capabilityFacts: controllerFacts(environment: .live, penState: .raised),
        environment: .live
      )
      let capability = try #require(submission.snapshot.activeOperation?.stopCapabilityID)

      let owner = Task { await runtime.stop(using: capability) }
      #expect(await completesBeforeManualMotionTestDeadline {
        await stageGate.waitUntilPreStateIsHeld()
      })
      let duplicate = Task { await runtime.stop(using: capability) }
      #expect(await completesBeforeManualMotionTestDeadline {
        await terminalGate.waitUntilDuplicateHasJoined()
      })
      let shutdownCompletion = ManualMotionCompletionSignal()
      let shutdown = Task {
        await runtime.shutdown()
        await shutdownCompletion.finish()
      }
      #expect(await completesBeforeManualMotionTestDeadline {
        await shutdownCompletion.waitUntilFinished()
      })
      #expect(await live.operation(at: 0)?.cancellationRequestCount == 1)

      stageGate.releasePreState()
      #expect(await completesBeforeManualMotionTestDeadline {
        await terminalGate.waitUntilPublicationIsHeld()
      })
      terminalGate.releasePublication()
      let ownerResult = await owner.value
      let duplicateResult = await duplicate.value
      await shutdown.value

      #expect(ownerResult.disposition == .settled)
      #expect(duplicateResult.disposition == .settled)
      #expect(ownerResult.snapshot.activeOperation == nil)
      #expect(duplicateResult.snapshot.activeOperation == nil)
      #expect(ownerResult.snapshot.projection.runtimeStateRevision
        == duplicateResult.snapshot.projection.runtimeStateRevision)
      #expect(ownerResult.snapshot.projection.lastTerminalEffect
        == duplicateResult.snapshot.projection.lastTerminalEffect)
      let phases: [PlotterEffectCancellationPhase] =
        ownerResult.snapshot.journal.journal.events.compactMap { event in
        guard case let .effectProgressed(progress) = event.payload,
              progress.cancellation.phase != .notRequested else { return nil }
        return progress.cancellation.phase
      }
      #expect(phases == [.requested, .observed, .settling])
      #expect(await live.operation(at: 0)?.cancellationRequestCount == 1)
    }
  }

  @Test("staged Stop append failure retains the original cursor after shutdown settlement")
  func stagedStopFailureRetainsCursor() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("plotter-manual-staged-recovery-\(UUID().uuidString)")
    let displaced = directory.appendingPathExtension("displaced")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: directory)
      try? FileManager.default.removeItem(at: displaced)
    }
    let live = ManualMotionAdapterProbe(environment: .live)
    let runtime = try PlotterManualMotionRuntime(
      journalFileURL: directory.appendingPathComponent("journal.json"),
      liveAdapter: live,
      simulatedAdapter: ManualMotionAdapterProbe(environment: .simulated)
    )
    let stageGate = PlotterManualMotionCancellationPublicationGate(targetPhase: .observed)
    let terminalGate = PlotterManualMotionTerminalPublicationGate()
    await runtime.installCancellationPublicationGateForTesting(stageGate)
    await runtime.installTerminalPublicationGateForTesting(terminalGate)
    let submission = try await runtime.submit(
      .jog(try PlotterJogRequest(
        direction: .positiveX,
        distanceMM: 3,
        feedMMPerMinute: 100,
        routing: .relativeTravel
      )),
      capabilityFacts: controllerFacts(environment: .live, penState: .raised),
      environment: .live
    )
    let capability = try #require(submission.snapshot.activeOperation?.stopCapabilityID)
    let owner = Task { await runtime.stop(using: capability) }
    #expect(await completesBeforeManualMotionTestDeadline {
      await stageGate.waitUntilPreStateIsHeld()
    })
    let duplicate = Task { await runtime.stop(using: capability) }
    #expect(await completesBeforeManualMotionTestDeadline {
      await terminalGate.waitUntilDuplicateHasJoined()
    })
    let shutdown = Task { await runtime.shutdown() }
    try FileManager.default.moveItem(at: directory, to: displaced)
    stageGate.releasePreState()
    let incompleteOwner = await owner.value
    let incompleteDuplicate = await duplicate.value
    await shutdown.value
    let issue = try #require(incompleteOwner.snapshot.terminalPublicationIssue)
    #expect(incompleteOwner.disposition == .publicationPending)
    #expect(incompleteDuplicate.disposition == .publicationPending)
    #expect(incompleteDuplicate.snapshot.terminalPublicationIssue?.recoveryCapabilityID
      == issue.recoveryCapabilityID)
    #expect(incompleteOwner.snapshot.activeOperation != nil)
    #expect(await live.operation(at: 0)?.cancellationRequestCount == 1)

    try FileManager.default.moveItem(at: displaced, to: directory)
    let recovery = Task {
      await runtime.recoverTerminalPublication(using: issue.recoveryCapabilityID)
    }
    #expect(await completesBeforeManualMotionTestDeadline {
      await terminalGate.waitUntilPublicationIsHeld()
    })
    terminalGate.releasePublication()
    let recovered = await recovery.value
    #expect(recovered.disposition == .published)
    #expect(recovered.snapshot.activeOperation == nil)
    #expect(recovered.snapshot.terminalPublicationIssue == nil)
    #expect(await live.operation(at: 0)?.cancellationRequestCount == 1)
    let phases: [PlotterEffectCancellationPhase] =
      recovered.snapshot.journal.journal.events.compactMap { event in
      guard case let .effectProgressed(progress) = event.payload,
            progress.cancellation.phase != .notRequested else { return nil }
      return progress.cancellation.phase
    }
    #expect(phases == [.requested, .observed, .settling])
  }

  @Test("Stop publication FIFO isolates a concurrent submission revision")
  func cancellationPublicationFIFO() async throws {
    let cancellationGate = ManualMotionCancellationRequestGate()
    let live = ManualMotionAdapterProbe(
      environment: .live,
      cancellationRequestGate: cancellationGate
    )
    let runtime = try PlotterManualMotionRuntime(
      journalFileURL: manualMotionJournalFileURL(),
      liveAdapter: live,
      simulatedAdapter: ManualMotionAdapterProbe(environment: .simulated)
    )
    let publicationGate = PlotterManualMotionCancellationPublicationGate()
    await runtime.installCancellationPublicationGateForTesting(publicationGate)
    let first = try await runtime.submit(
      .jog(try PlotterJogRequest(
        direction: .positiveX,
        distanceMM: 3,
        feedMMPerMinute: 100,
        routing: .relativeTravel
      )),
      capabilityFacts: controllerFacts(environment: .live, penState: .raised),
      environment: .live
    )
    let capability = try #require(first.snapshot.activeOperation?.stopCapabilityID)

    let stopCompletion = ManualMotionCompletionSignal()
    let stop = Task {
      let result = await runtime.stop(using: capability)
      await stopCompletion.finish()
      return result
    }
    #expect(await completesBeforeManualMotionTestDeadline {
      await publicationGate.waitUntilPreStateIsHeld()
    })

    let submitCompletion = ManualMotionCompletionSignal()
    let concurrentSubmit = Task {
      let result = try await runtime.submit(
        .jog(try PlotterJogRequest(
          direction: .positiveY,
          distanceMM: 1,
          feedMMPerMinute: 100,
          routing: .relativeTravel
        )),
        capabilityFacts: controllerFacts(environment: .live, penState: .raised),
        environment: .live
      )
      await submitCompletion.finish()
      return result
    }
    #expect(await completesBeforeManualMotionTestDeadline {
      await publicationGate.waitUntilMutationWaiterIsObserved()
    })
    #expect(live.operationCount == 1)
    #expect(await submitCompletion.isFinished == false)

    publicationGate.releasePreState()
    #expect(await completesBeforeManualMotionTestDeadline {
      await cancellationGate.waitUntilCancellationIsHeld()
    })
    #expect(await completesBeforeManualMotionTestDeadline {
      await submitCompletion.waitUntilFinished()
    })
    let refused = try await concurrentSubmit.value
    #expect(refused.disposition == .refused)
    #expect(refused.snapshot.terminalPublicationIssue == nil)
    #expect(refused.snapshot.activeOperation?.context.effectID
      == first.snapshot.activeOperation?.context.effectID)
    #expect(live.operationCount == 1)

    let events = refused.snapshot.journal.journal.events
    let requested = try #require(events.last { event in
      guard case let .effectProgressed(progress) = event.payload else { return false }
      return progress.cancellation.phase == .requested
    })
    #expect(events.last?.id == requested.id)
    #expect(events.allSatisfy { event in
      if case .intentRefused = event.payload { return false }
      return true
    })

    await cancellationGate.releaseCancellation()
    #expect(await completesBeforeManualMotionTestDeadline {
      await stopCompletion.waitUntilFinished()
    })
    let settled = await stop.value
    #expect(settled.disposition == .settled)
    #expect(settled.snapshot.terminalPublicationIssue == nil)
    #expect(await live.operation(at: 0)?.cancellationRequestCount == 1)
  }

  @Test("manual operation implementation owns no arbitrary launch closures or unchecked state")
  func nominalOperationSourceContract() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let runtime = try String(contentsOf: root.appendingPathComponent(
      "Sources/PlotterEpisodeRuntime/PlotterManualMotionRuntime.swift"
    ))
    let composition = try String(contentsOf: root.appendingPathComponent(
      "Sources/PlotterApp/PlotterManualMotionComposition.swift"
    ))
    let tests = try String(contentsOf: URL(fileURLWithPath: #filePath))

    let uncheckedConformance = "@unchecked" + " Sendable"
    #expect(!runtime.contains(uncheckedConformance))
    #expect(!composition.contains(uncheckedConformance))
    #expect(!tests.contains(uncheckedConformance))
    #expect(!composition.contains("ManualMotionLaunch"))
    #expect(!composition.contains("cancel: @Sendable"))
    #expect(!composition.contains("settle: @Sendable"))
  }
}

private final class ManualMotionAdapterProbe: PlotterManualMotionEffectAdapter, Sendable
{
  let environment: PlotterEnvironment
  private let recordsControllerPairOnStart: Bool
  private let cancellationRequestGate: ManualMotionCancellationRequestGate?
  private let state = OSAllocatedUnfairLock(
    initialState: (operations: [ManualMotionOperationProbe](), recorder: false)
  )

  init(
    environment: PlotterEnvironment,
    recordsControllerPairOnStart: Bool = false,
    cancellationRequestGate: ManualMotionCancellationRequestGate? = nil
  ) {
    self.environment = environment
    self.recordsControllerPairOnStart = recordsControllerPairOnStart
    self.cancellationRequestGate = cancellationRequestGate
  }

  var operationCount: Int {
    state.withLock { $0.operations.count }
  }

  var receivedControllerRecorder: Bool {
    state.withLock { $0.recorder }
  }

  func operation(at index: Int) -> ManualMotionOperationProbe? {
    state.withLock { value in
      value.operations.indices.contains(index) ? value.operations[index] : nil
    }
  }

  func makeOperation(
    for request: PlotterManualMotionEffectRequest,
    controllerRecorder: PlotterManualMotionControllerRecorder?
  ) -> any PlotterManualMotionOperation {
    let operation = ManualMotionOperationProbe(
      request: request,
      recorder: controllerRecorder,
      recordsControllerPairOnStart: recordsControllerPairOnStart,
      cancellationRequestGate: cancellationRequestGate
    )
    state.withLock { value in
      value.operations.append(operation)
      value.recorder = controllerRecorder != nil
    }
    return operation
  }
}

private actor ManualMotionOperationProbe: PlotterManualMotionOperation {
  private let request: PlotterManualMotionEffectRequest
  private let recorder: PlotterManualMotionControllerRecorder?
  private let recordsControllerPairOnStart: Bool
  private let cancellationRequestGate: ManualMotionCancellationRequestGate?
  private var result: PlotterManualMotionOperationResult?
  private var waiters: [CheckedContinuation<PlotterManualMotionOperationResult, Never>] = []
  private(set) var startCount = 0
  private(set) var cancellationRequestCount = 0

  init(
    request: PlotterManualMotionEffectRequest,
    recorder: PlotterManualMotionControllerRecorder?,
    recordsControllerPairOnStart: Bool,
    cancellationRequestGate: ManualMotionCancellationRequestGate?
  ) {
    self.request = request
    self.recorder = recorder
    self.recordsControllerPairOnStart = recordsControllerPairOnStart
    self.cancellationRequestGate = cancellationRequestGate
  }

  func start() async {
    startCount += 1
    guard recordsControllerPairOnStart, let recorder else { return }
    let invocationID = ControllerInvocationID(rawValue: UUID())
    let bytes = Data("$J=G91 X-2 F100\n".utf8)
    await recorder.recordInvocation(
      ControllerInvocation(
        id: invocationID,
        operation: .rawWrite(ControllerRawWriteParameters(bytes: bytes))
      ),
      at: 10
    )
    await recorder.recordCompletion(
      ControllerCompletion(
        invocationID: invocationID,
        outcome: .succeeded(.rawWrite(writtenByteCount: bytes.count))
      ),
      at: 11
    )
  }

  func requestCancellation() async {
    cancellationRequestCount += 1
    await cancellationRequestGate?.holdCancellation()
    guard result == nil else { return }
    let observation = controllerObservation(environment: request.context.environment)
    let settlement: PlotterEffectCancellationSettlement
    if case let .jog(jog) = request.intent, jog.routing == .drawingStroke {
      settlement = .drawingStoppedWithPenRaised(
        observationID: observation.context.id,
        possibleInk: true
      )
    } else {
      settlement = .controllerSettled(
        observationID: observation.context.id,
        possibleInk: request.context.environment == .live
      )
    }
    publish(.cancelled(settlement: settlement, observation: observation))
  }

  func complete() {
    publish(.completed(observation: controllerObservation(
      environment: request.context.environment
    )))
  }

  func waitForSettlement() async -> PlotterManualMotionOperationResult {
    if let result { return result }
    return await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  private func publish(_ value: PlotterManualMotionOperationDisposition) {
    guard result == nil else { return }
    let bound = PlotterManualMotionOperationResult(
      identity: PlotterManualMotionOperationIdentity(request: request),
      disposition: value
    )
    result = bound
    let current = waiters
    waiters.removeAll()
    current.forEach { $0.resume(returning: bound) }
  }
}

private actor ManualMotionCancellationRequestGate {
  private var cancellationIsHeld = false
  private var isReleased = false
  private var heldWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  func holdCancellation() async {
    cancellationIsHeld = true
    let current = heldWaiters
    heldWaiters.removeAll()
    current.forEach { $0.resume() }
    guard !isReleased else { return }
    await withCheckedContinuation { continuation in
      releaseWaiters.append(continuation)
    }
  }

  func waitUntilCancellationIsHeld() async {
    guard !cancellationIsHeld else { return }
    await withCheckedContinuation { continuation in
      heldWaiters.append(continuation)
    }
  }

  func releaseCancellation() {
    isReleased = true
    let current = releaseWaiters
    releaseWaiters.removeAll()
    current.forEach { $0.resume() }
  }
}

private actor ManualMotionCompletionSignal {
  private(set) var isFinished = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func finish() {
    guard !isFinished else { return }
    isFinished = true
    let current = waiters
    waiters.removeAll()
    current.forEach { $0.resume() }
  }

  func waitUntilFinished() async {
    guard !isFinished else { return }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }
}

private actor ManualMotionTestDeadlineRace {
  private var result: Bool?
  private var waiters: [CheckedContinuation<Bool, Never>] = []

  func resolve(_ value: Bool) {
    guard result == nil else { return }
    result = value
    let current = waiters
    waiters.removeAll()
    current.forEach { $0.resume(returning: value) }
  }

  func value() async -> Bool {
    if let result { return result }
    return await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }
}

private func completesBeforeManualMotionTestDeadline(
  _ operation: @escaping @Sendable () async -> Void
) async -> Bool {
  let race = ManualMotionTestDeadlineRace()
  Task {
    await operation()
    await race.resolve(true)
  }
  Task {
    try? await ContinuousClock().sleep(for: .seconds(2))
    await race.resolve(false)
  }
  return await race.value()
}

private func manualMotionJournalFileURL() -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("plotter-manual-journal-\(UUID().uuidString)")
  try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("journal.json")
}

private func controllerFacts(
  environment: PlotterEnvironment,
  penState: PlotterControllerPenState,
  profileRevision: EpisodeRevisionIdentifier = revision("pen-profile-current")
) -> [PlotterCapabilityFact] {
  let owner = EpisodeAuthorityID(rawValue: "MachineController")
  return [
    .connection(PlotterConnectionFact(
      owner: owner,
      revision: CapabilityFactRevision(rawValue: 1),
      environment: environment,
      isConnected: true
    )),
    .motion(PlotterMotionFact(
      owner: owner,
      revision: CapabilityFactRevision(rawValue: 2),
      environment: environment,
      isEnabled: true
    )),
    .pose(PlotterPoseFact(
      owner: owner,
      revision: CapabilityFactRevision(rawValue: 3),
      environment: environment,
      machinePosition: nil,
      isSettled: true,
      settlementPolicyRevision: revision("manual-settlement-v1")
    )),
    .manualController(PlotterManualControllerFact(
      owner: owner,
      revision: CapabilityFactRevision(rawValue: 4),
      environment: environment,
      penState: penState,
      operationIsActive: false,
      penActuationProfileRevision: profileRevision
    )),
  ]
}

private func controllerObservation(environment: PlotterEnvironment) -> PlotterObservation {
  .controller(PlotterControllerObservation(
    context: PlotterObservationContext(
      id: PlotterObservationID(rawValue: UUID()),
      observedAt: Date(),
      environment: environment,
      source: environment == .live ? .controller : .causalSimulator,
      sourceRevision: revision("manual-controller-observation-v1")
    ),
    status: .idle,
    machinePosition: nil,
    motionEnabled: true
  ))
}

private func revision(_ value: String) -> EpisodeRevisionIdentifier {
  EpisodeRevisionIdentifier(rawValue: value)
}
