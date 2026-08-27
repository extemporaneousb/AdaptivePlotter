import EpisodeCore
import Foundation
import PlotterEpisodeModel
@testable import PlotterEpisodeRuntime
import PlotterRuntime
import PlotterTestSupport
import Testing

@Suite("Plotter episode recording replay")
struct PlotterRecordingReplayTests {
  @Test("every journal prefix is independently reduced and canonically verified")
  func everyPrefixIsReconstructed() throws {
    let fixture = try ReplayFixture.make(includeManualSettlement: true)
    let report = PlotterEpisodeReplayService().replay(
      definition: fixture.definition,
      manifest: fixture.manifest,
      recordedEffectRevisions: fixture.recordedEffectRevisions,
      initialState: fixture.initialState,
      journal: fixture.journal,
      decisionTimeline: fixture.timeline
    )

    #expect(report.isInAgreement)
    #expect(report.executableDescriptor == PlotterEpisodeReplayService.executableDescriptor)
    #expect(!report.executableDescriptor.consumesDeterministicSeed)
    #expect(report.recordedEffectRevisions.allSatisfy {
      $0.authority == .recordedIdentityOnlyNoExecutorValidation
    })
    #expect(report.prefixes.count == fixture.journal.events.count + 1)
    #expect(report.prefixes.map(\.eventCount) == Array(0...fixture.journal.events.count))
    #expect(report.prefixes.flatMap(\.eventVerifications).allSatisfy { verification in
      verification.isVerified
    })
    #expect(report.prefixes[0].intentAvailabilities.first?.disposition == .admitted)
    #expect(report.prefixes[2].intentAvailabilities.first?.disposition == .admitted)
    #expect(report.prefixes.last?.state.revision == EpisodeStateRevision(rawValue: 5))
    #expect(report.prefixes.last?.emittedEffects.count == 2)
    #expect(
      report.prefixes.last?.resumeDisposition
        == .neverResume(.unboundReplayNeverExecutesEffects)
    )
  }

  @Test("sealed executable facts reject a stale manifest before prefix reduction")
  func staleExecutableCannotBeSpoofedByCallerData() throws {
    let fixture = try ReplayFixture.make(includeManualSettlement: false)
    let staleManifest = PlotterEpisodeManifest(
      id: fixture.manifest.id,
      episodeID: fixture.manifest.episodeID,
      definitionID: fixture.manifest.definitionID,
      definitionRevision: fixture.manifest.definitionRevision,
      domainRevision: revision("stale-domain"),
      evaluatorRevision: revision("stale-evaluator"),
      reducerRevision: revision("stale-reducer"),
      schemaRevisions: EpisodeSchemaRevisions(
        state: revision("stale-state"),
        event: revision("stale-event"),
        journal: revision("stale-journal")
      ),
      buildRevision: revision("stale-build"),
      deterministicSeed: fixture.manifest.deterministicSeed + 1,
      domainManifest: fixture.manifest.domainManifest
    )
    let callerControlledRecordedIdentities = fixture.recordedEffectRevisions.map {
      PlotterEpisodeRecordedEffectRevision(
        effectID: $0.effectID,
        revision: revision("caller-supplied-spoof")
      )
    }
    let report = fixture.replay(
      manifest: staleManifest,
      recordedEffectRevisions: callerControlledRecordedIdentities
    )

    #expect(report.prefixes.isEmpty)
    #expect(report.executableDescriptor == PlotterEpisodeReplayService.executableDescriptor)
    #expect(
      report.executableDescriptor.canonicalDigestRevision
        == PlotterEpisodeCanonicalDigestV1.revision
    )
    for component in [
      PlotterEpisodeReplayRevisionComponent.domain,
      .evaluator, .reducer, .stateSchema, .eventSchema,
      .journalSchema, .build, .canonicalDigest,
    ] {
      if component == .canonicalDigest {
        #expect(!report.disagreements.contains { disagreement in
          guard case let .executableRevision(actualComponent, _, _) = disagreement else {
            return false
          }
          return actualComponent == component
        })
      } else {
        #expect(report.disagreements.contains { disagreement in
          guard case let .executableRevision(actualComponent, _, _) = disagreement else {
            return false
          }
          return actualComponent == component
        })
      }
    }
  }

  @Test("each manifest executable pin independently blocks prefix publication")
  func eachManifestExecutablePinIsRequired() throws {
    let fixture = try ReplayFixture.make(includeManualSettlement: false)
    let staleSchema = { (component: PlotterEpisodeReplayRevisionComponent) in
      EpisodeSchemaRevisions(
        state: component == .stateSchema
          ? revision("stale-state") : fixture.manifest.schemaRevisions.state,
        event: component == .eventSchema
          ? revision("stale-event") : fixture.manifest.schemaRevisions.event,
        journal: component == .journalSchema
          ? revision("stale-journal") : fixture.manifest.schemaRevisions.journal
      )
    }
    let cases: [(PlotterEpisodeReplayRevisionComponent, PlotterEpisodeManifest)] = [
      (.domain, fixture.manifestWith(domainRevision: revision("stale-domain"))),
      (.evaluator, fixture.manifestWith(evaluatorRevision: revision("stale-evaluator"))),
      (.reducer, fixture.manifestWith(reducerRevision: revision("stale-reducer"))),
      (.stateSchema, fixture.manifestWith(schemaRevisions: staleSchema(.stateSchema))),
      (.eventSchema, fixture.manifestWith(schemaRevisions: staleSchema(.eventSchema))),
      (.journalSchema, fixture.manifestWith(schemaRevisions: staleSchema(.journalSchema))),
      (.build, fixture.manifestWith(buildRevision: revision("stale-build"))),
    ]

    for (component, manifest) in cases {
      let report = fixture.replay(manifest: manifest)
      #expect(report.prefixes.isEmpty)
      #expect(report.disagreements.contains { disagreement in
        guard case let .executableRevision(actualComponent, _, _) = disagreement else {
          return false
        }
        return actualComponent == component
      })
    }
    #expect(
      PlotterEpisodeReplayService.executableDescriptor.canonicalDigestRevision
        == PlotterEpisodeCanonicalDigestV1.revision
    )
  }

  @Test("progress without settlement is possible physical effect and cannot resume")
  func possiblePhysicalEffectNeverResumes() throws {
    let fixture = try ReplayFixture.make(includeManualSettlement: false)
    let report = fixture.replay()
    let prefix = try #require(report.prefixes.last)

    guard case let .possiblePhysicalEffect(effects) = prefix.physicalEffectClassification
    else {
      Issue.record("expected possible physical effect")
      return
    }
    #expect(effects.count == 1)
    #expect(effects.first?.effect.context.effectID == fixture.manualEffectID)
    #expect(effects.first?.startEvidence.count == 1)
    #expect(
      prefix.resumeDisposition
        == .neverResume(.possiblePhysicalEffect([fixture.manualEffectID]))
    )
  }

  @Test("availability timeline is mandatory and never inferred from current facts")
  func missingDecisionTimelineRefusesReplay() throws {
    let fixture = try ReplayFixture.make(includeManualSettlement: false)
    let report = PlotterEpisodeReplayService().replay(
      definition: fixture.definition,
      manifest: fixture.manifest,
      recordedEffectRevisions: fixture.recordedEffectRevisions,
      initialState: fixture.initialState,
      journal: fixture.journal,
      decisionTimeline: []
    )

    #expect(report.prefixes.isEmpty)
    #expect(report.disagreements.contains(
      .missingDecisionFrame(prefixEventCount: 0)
    ))
  }

  @Test("independent canonical digest rejects a self-consistent copied digest")
  func copiedDigestDoesNotVerifyItself() throws {
    let fixture = try ReplayFixture.make(includeManualSettlement: false)
    let original = try #require(fixture.journal.events.first)
    let corrupt = PlotterEpisodeEvent(
      id: original.id,
      episodeID: original.episodeID,
      sequence: original.sequence,
      recordedAt: original.recordedAt,
      actor: original.actor,
      causation: original.causation,
      correlationID: original.correlationID,
      preStateRevision: original.preStateRevision,
      postStateRevision: original.postStateRevision,
      payload: original.payload,
      artifactReferences: original.artifactReferences,
      postStateDigest: EpisodeStateDigest(rawValue: "recorded-but-not-canonical")
    )
    let journal = try EpisodeJournal(
      manifestID: fixture.manifest.id,
      episodeID: fixture.manifest.episodeID,
      events: [corrupt]
    )
    let report = PlotterEpisodeReplayService().replay(
      definition: fixture.definition,
      manifest: fixture.manifest,
      recordedEffectRevisions: fixture.recordedEffectRevisions,
      initialState: fixture.initialState,
      journal: journal,
      decisionTimeline: Array(fixture.timeline.prefix(2))
    )

    #expect(report.prefixes.count == 2)
    #expect(report.prefixes.last?.eventVerifications.first?.isVerified == false)
    #expect(report.disagreements.contains { disagreement in
      guard case let .reducerOutputDigest(index, _, _) = disagreement else { return false }
      return index == 0
    })
  }

  @Test("effect identity rejects stale revisions and preserves first terminal settlement")
  func effectIdentityAndTerminalOrderingAreStrict() throws {
    let fixture = try ReplayFixture.make(includeManualSettlement: true)
    let progress = try #require(fixture.manualProgress)
    let result = try #require(fixture.manualResult)
    let staleProgress = try PlotterEffectProgress(
      episodeID: progress.episodeID,
      requestID: progress.requestID,
      intent: progress.intent,
      effectID: progress.effectID,
      effectRevision: revision("stale-effect"),
      environment: progress.environment,
      lane: progress.lane,
      owningSubsystem: progress.owningSubsystem,
      phase: progress.phase,
      startedAt: progress.startedAt,
      lastAttributableProgressAt: progress.lastAttributableProgressAt,
      resultCurrentlyAwaited: progress.resultCurrentlyAwaited,
      deadline: progress.deadline,
      cancellation: progress.cancellation
    )
    let staleContext = PlotterEffectResultContext(
      episodeID: result.episodeID,
      requestID: result.requestID,
      intent: result.intent,
      effectID: result.effectID,
      environment: result.environment,
      effectRevision: revision("stale-effect")
    )
    var stalePayloads = fixture.journal.events.map(\.payload)
    stalePayloads[3] = .effectProgressed(staleProgress)
    stalePayloads[4] = .effectResult(.cancelled(context: staleContext))
    let staleJournal = try fixture.journal(payloads: stalePayloads)
    let staleReport = fixture.replay(
      journal: staleJournal,
      timeline: fixture.timeline(forEventCount: staleJournal.events.count)
    )
    #expect(staleReport.disagreements.contains(
      .effectProgressIdentityMismatch(index: 3, effectID: fixture.manualEffectID)
    ))
    #expect(staleReport.disagreements.contains(
      .effectResultIdentityMismatch(index: 4, effectID: fixture.manualEffectID)
    ))
    #expect(staleReport.prefixes.map(\.eventCount) == Array(0...3))
    #expect(staleReport.disagreements.contains(
      .journalPrefixRejected(prefixEventCount: 4)
    ))
    #expect(staleReport.disagreements.contains(
      .journalPrefixRejected(prefixEventCount: 5)
    ))

    var repeatedPayloads = fixture.journal.events.map(\.payload)
    repeatedPayloads.append(.effectProgressed(progress))
    repeatedPayloads.append(.effectResult(.cancelled(context: result)))
    let repeatedJournal = try fixture.journal(payloads: repeatedPayloads)
    let repeatedReport = fixture.replay(
      journal: repeatedJournal,
      timeline: fixture.timeline(forEventCount: repeatedJournal.events.count)
    )
    let firstTerminal = fixture.journal.events[4].id
    #expect(repeatedReport.disagreements.contains(
      .effectProgressAfterSettlement(
        index: 5,
        effectID: fixture.manualEffectID,
        settledByEventID: firstTerminal
      )
    ))
    #expect(repeatedReport.disagreements.contains(
      .multipleEffectResults(
        index: 6,
        effectID: fixture.manualEffectID,
        firstSettledByEventID: firstTerminal
      )
    ))
    #expect(repeatedReport.prefixes.map(\.eventCount) == Array(0...5))
    #expect(repeatedReport.disagreements.contains(
      .journalPrefixRejected(prefixEventCount: 6)
    ))
    #expect(repeatedReport.disagreements.contains(
      .journalPrefixRejected(prefixEventCount: 7)
    ))
    #expect(
      repeatedReport.prefixes.last?.emittedEffects.last?.settledByEventID == firstTerminal
    )

    var duplicatePayloads = fixture.journal.events.map(\.payload)
    duplicatePayloads.append(fixture.journal.events[2].payload)
    let duplicateJournal = try fixture.journal(payloads: duplicatePayloads)
    let duplicateReport = fixture.replay(
      journal: duplicateJournal,
      timeline: fixture.timeline(forEventCount: duplicateJournal.events.count)
    )
    #expect(duplicateReport.disagreements.contains(
      .duplicateEffectEmission(fixture.manualEffectID)
    ))
    #expect(duplicateReport.prefixes.map(\.eventCount) == Array(0...5))
    #expect(duplicateReport.disagreements.contains(
      .journalPrefixRejected(prefixEventCount: 6)
    ))
  }

  @Test("recording provenance and channel completeness remain separately inspectable")
  func provenanceAndCompletenessRemainTyped() throws {
    let fixture = try ReplayFixture.make(includeManualSettlement: false)
    let recording = fixture.controllerRecording(
      completenessIssues: fixture.completenessIssues
    )
    let report = fixture.replay(recording: recording)
    let inspection = try #require(report.recording)

    #expect(inspection.entries.map(\.provenance).allSatisfy {
      $0.effectID == fixture.manualEffectID
    })
    #expect(inspection.completeness.controller.count == 1)
    #expect(inspection.completeness.camera.count == 1)
    #expect(inspection.completeness.runLedger.count == 1)
    #expect(inspection.completeness.globalDiagnostics == [.frameRetentionAccountingOverflow])
    #expect(!inspection.completeness.isComplete)
  }

  @Test("recording starts require one exact operation-bound provenance tuple")
  func foreignProvenanceCannotEstablishStartEvidence() throws {
    let fixture = try ReplayFixture.make(includeManualSettlement: false)
    let report = fixture.replay(recording: fixture.recordingWithForeignCameraStart())
    let effect = try #require(report.prefixes.last?.emittedEffects.last)

    #expect(effect.operationBinding.effectRevision == revision("manual-effect-v1"))
    #expect(effect.startEvidence.contains(.controllerInvocation(recordingSequence: 0)))
    #expect(!effect.startEvidence.contains(.cameraLifecycleRequest(recordingSequence: 2)))
    #expect(report.disagreements.contains { disagreement in
      guard case let .recordingOperationBindingMismatch(sequence, expected, actual)
        = disagreement else { return false }
      return sequence == 2
        && expected.effectID == fixture.manualEffectID
        && actual.correlationID != expected.correlationID
    })
    #expect(report.disagreements.contains(.recordingStartUnattributed(
      recordingSequence: 2
    )))

    let mixed = fixture.replay(recording: fixture.recordingWithMixedValidCameraStart())
    let mixedEffect = try #require(mixed.prefixes.last?.emittedEffects.last)
    #expect(!mixedEffect.startEvidence.contains(.cameraLifecycleRequest(recordingSequence: 2)))
    #expect(mixed.disagreements.contains { disagreement in
      guard case let .recordingOperationBindingMismatch(sequence, expected, actual)
        = disagreement else { return false }
      return sequence == 2
        && expected.effectID == fixture.manualEffectID
        && actual.intentRequestID != expected.requestID
        && actual.correlationID != expected.correlationID
    })
    #expect(mixed.disagreements.contains(.recordingStartUnattributed(
      recordingSequence: 2
    )))
  }

  @Test("fragmentation and delay preserve bytes, order, writes, and provenance")
  func bytePreservingPerturbations() throws {
    let fixture = try ReplayFixture.make(includeManualSettlement: false)
    let scenario = ControllerReplayScenario(
      id: ControllerReplayScenarioID(rawValue: "fragment-delay"),
      perturbations: [
        .legalReadFragmentation(maximumChunkByteCount: 2),
        .completionDelay(invocationID: fixture.controllerInvocationID, additionalNanoseconds: 5),
      ]
    )
    let sourceRecording = fixture.controllerRecording(includeDownstreamController: true)
    let report = fixture.replay(
      recording: sourceRecording,
      scenarios: [scenario]
    )
    let result = try #require(report.controllerScenarios.first)

    #expect(result.disposition == .applied)
    #expect(result.steps.map(\.sourceRecordingSequence) == [0, 1, 2])
    #expect(result.steps.map(\.provenance).allSatisfy {
      $0.effectID == fixture.manualEffectID
    })
    guard case let .completion(completion) = result.steps[1].record,
          case let .succeeded(.timedRead(chunks, timedOut)) = completion.outcome else {
      Issue.record("expected perturbed timed-read completion")
      return
    }
    #expect(!timedOut)
    #expect(chunks.count == 4)
    #expect(
      chunks.reduce(into: Data()) { $0.append(contentsOf: $1.bytes) }
        == Data("abcdefgh".utf8)
    )
    #expect(chunks.map(\.monotonicOffsetNanoseconds) == [20, 20, 20, 30])
    #expect(result.steps[1].replayOffsetNanoseconds == 35)
    let sourceSteps = fixture.controllerReplaySteps(from: sourceRecording)
    #expect(result.steps[2].replayOffsetNanoseconds == 55)
    #expect(result.steps[2].sourceRecordingSequence == sourceSteps[2].sourceRecordingSequence)
    #expect(result.steps[2].provenance == sourceSteps[2].provenance)
    #expect(result.steps[2].record == sourceSteps[2].record)
  }

  @Test("timeout and cancellation retain only bytes before their declared boundary")
  func terminalPerturbationBoundaries() throws {
    let fixture = try ReplayFixture.make(includeManualSettlement: false)
    let scenarios = [
      ControllerReplayScenario(
        id: ControllerReplayScenarioID(rawValue: "timeout"),
        perturbations: [.timeout(
          invocationID: fixture.controllerInvocationID,
          atNanosecondsAfterInvocation: 10
        )]
      ),
      ControllerReplayScenario(
        id: ControllerReplayScenarioID(rawValue: "cancel"),
        perturbations: [.cancellation(
          invocationID: fixture.controllerInvocationID,
          atNanosecondsAfterInvocation: 0
        )]
      ),
      ControllerReplayScenario(
        id: ControllerReplayScenarioID(rawValue: "conflict"),
        perturbations: [
          .timeout(
            invocationID: fixture.controllerInvocationID,
            atNanosecondsAfterInvocation: 10
          ),
          .cancellation(
            invocationID: fixture.controllerInvocationID,
            atNanosecondsAfterInvocation: 10
          ),
        ]
      ),
    ]
    let report = fixture.replay(
      recording: fixture.controllerRecording(),
      scenarios: scenarios
    )

    let timeout = try failure(in: report.controllerScenarios[0])
    #expect(timeout.kind == .timeout)
    #expect(timeout.partialReadChunks.map(\.bytes) == [Data("abcdef".utf8)])
    #expect(timeout.partialByteCount == 6)
    #expect(report.controllerScenarios[0].steps[1].replayOffsetNanoseconds == 20)
    let cancellation = try failure(in: report.controllerScenarios[1])
    #expect(cancellation.kind == .cancelled)
    #expect(cancellation.partialReadChunks.isEmpty)
    #expect(report.controllerScenarios[1].steps[1].replayOffsetNanoseconds == 10)
    #expect(
      report.controllerScenarios[2].disposition
        == .refused([.conflictingTerminalPerturbations(fixture.controllerInvocationID)])
    )
    #expect(report.controllerScenarios[2].steps == fixture.controllerReplaySteps)
  }

  @Test("controller perturbations refuse absent or deadline-breaking traffic")
  func controllerPerturbationsPreserveCausality() throws {
    let fixture = try ReplayFixture.make(includeManualSettlement: false)
    let exactScenario = ControllerReplayScenario(
      id: ControllerReplayScenarioID(rawValue: "exact-without-source"),
      perturbations: []
    )
    let exactWithoutRecording = fixture.replay(scenarios: [exactScenario])
    #expect(exactWithoutRecording.controllerScenarios.first?.disposition == .refused([
      .controllerSourceAbsent,
    ]))
    let exactWithEmptyController = fixture.replay(
      recording: fixture.emptyControllerRecording(),
      scenarios: [exactScenario]
    )
    #expect(exactWithEmptyController.controllerScenarios.first?.disposition == .refused([
      .controllerSourceAbsent,
    ]))

    let absentScenario = ControllerReplayScenario(
      id: ControllerReplayScenarioID(rawValue: "absent"),
      perturbations: [.legalReadFragmentation(maximumChunkByteCount: 2)]
    )
    let absent = fixture.replay(scenarios: [absentScenario])
    #expect(absent.controllerScenarios.first?.disposition == .refused([
      .controllerSourceAbsent,
    ]))

    let writeOnlyRecording = fixture.writeOnlyControllerRecording()
    let noRead = fixture.replay(
      recording: writeOnlyRecording,
      scenarios: [absentScenario]
    )
    #expect(noRead.controllerScenarios.first?.disposition == .refused([
      .readTrafficAbsent,
    ]))
    guard case let .controller(.invocation(writeInvocation))
      = writeOnlyRecording.entries[0].record else {
      Issue.record("expected write-only invocation")
      return
    }
    let nonReadDelay = fixture.replay(
      recording: writeOnlyRecording,
      scenarios: [ControllerReplayScenario(
        id: ControllerReplayScenarioID(rawValue: "non-read-delay"),
        perturbations: [.completionDelay(
          invocationID: writeInvocation.id,
          additionalNanoseconds: 1
        )]
      )]
    )
    #expect(nonReadDelay.controllerScenarios.first?.disposition == .refused([
      .operationIsNotTimedRead(writeInvocation.id),
    ]))

    let delayScenario = ControllerReplayScenario(
      id: ControllerReplayScenarioID(rawValue: "past-timeout"),
      perturbations: [.completionDelay(
        invocationID: fixture.controllerInvocationID,
        additionalNanoseconds: 81
      )]
    )
    let delay = fixture.replay(
      recording: fixture.controllerRecording(),
      scenarios: [delayScenario]
    )
    #expect(delay.controllerScenarios.first?.disposition == .refused([
      .delayedCompletionExceedsReadTimeout(fixture.controllerInvocationID),
    ]))
    #expect(delay.controllerScenarios.first?.steps == fixture.controllerReplaySteps)

    let retimedDelay = fixture.replay(
      recording: fixture.controllerRecording(includeDownstreamController: true),
      scenarios: [ControllerReplayScenario(
        id: ControllerReplayScenarioID(rawValue: "delay-past-downstream"),
        perturbations: [.completionDelay(
          invocationID: fixture.controllerInvocationID,
          additionalNanoseconds: 25
        )]
      )]
    )
    let retimedSteps = try #require(retimedDelay.controllerScenarios.first?.steps)
    #expect(retimedDelay.controllerScenarios.first?.disposition == .applied)
    #expect(retimedSteps.map(\.replayOffsetNanoseconds) == [10, 55, 75])
    guard case let .completion(retimedCompletion) = retimedSteps[1].record,
          case let .succeeded(.timedRead(retimedChunks, _)) = retimedCompletion.outcome else {
      Issue.record("expected causally retimed read completion")
      return
    }
    #expect(retimedChunks.map(\.monotonicOffsetNanoseconds) == [40, 50])

    let failedDelay = fixture.replay(
      recording: fixture.failedControllerRecording(),
      scenarios: [delayScenario]
    )
    #expect(failedDelay.controllerScenarios.first?.disposition == .refused([
      .delayedCompletionExceedsReadTimeout(fixture.controllerInvocationID),
    ]))

    let timingOrders = [
      ControllerReplayScenario(
        id: ControllerReplayScenarioID(rawValue: "delay-then-timeout"),
        perturbations: [
          .completionDelay(
            invocationID: fixture.controllerInvocationID,
            additionalNanoseconds: 5
          ),
          .timeout(
            invocationID: fixture.controllerInvocationID,
            atNanosecondsAfterInvocation: 10
          ),
        ]
      ),
      ControllerReplayScenario(
        id: ControllerReplayScenarioID(rawValue: "timeout-then-delay"),
        perturbations: [
          .timeout(
            invocationID: fixture.controllerInvocationID,
            atNanosecondsAfterInvocation: 10
          ),
          .completionDelay(
            invocationID: fixture.controllerInvocationID,
            additionalNanoseconds: 5
          ),
        ]
      ),
    ]
    let timingConflicts = fixture.replay(
      recording: fixture.controllerRecording(),
      scenarios: timingOrders
    )
    for result in timingConflicts.controllerScenarios {
      #expect(result.disposition == .refused([
        .conflictingTimingPerturbations(fixture.controllerInvocationID),
      ]))
      #expect(result.steps == fixture.controllerReplaySteps)
    }

    let boundaryScenario = ControllerReplayScenario(
      id: ControllerReplayScenarioID(rawValue: "boundary-and-downstream"),
      perturbations: [.timeout(
        invocationID: fixture.controllerInvocationID,
        atNanosecondsAfterInvocation: 10
      )]
    )
    let adjusted = fixture.replay(
      recording: fixture.controllerRecording(includeDownstreamController: true),
      scenarios: [boundaryScenario]
    )
    #expect(adjusted.controllerScenarios.first?.disposition == .applied)
    let steps = try #require(adjusted.controllerScenarios.first?.steps)
    #expect(steps.map(\.replayOffsetNanoseconds) == [10, 20, 40])
    #expect(steps.map(\.sourceRecordingSequence) == [0, 1, 2])
    let sourceDownstream = fixture.controllerReplaySteps(
      from: fixture.controllerRecording(includeDownstreamController: true)
    )[2]
    #expect(steps[2].record == sourceDownstream.record)
    #expect(steps[2].provenance == sourceDownstream.provenance)
  }

  @Test("global controller schedule validation preserves exact overlapping traffic")
  func overlappingControllerInvocationsRemainCausal() throws {
    let fixture = try ReplayFixture.make(includeManualSettlement: false)
    let overlappingID = fixture.overlappingControllerInvocationID

    let delayRecording = fixture.overlappingControllerRecording(
      firstCompletionOffsetNanoseconds: 30,
      secondCompletionOffsetNanoseconds: 35,
      secondChunkOffsetNanoseconds: 25,
      secondTimeoutNanoseconds: 20
    )
    let delayed = fixture.replay(
      recording: delayRecording,
      scenarios: [ControllerReplayScenario(
        id: ControllerReplayScenarioID(rawValue: "overlap-delay"),
        perturbations: [.completionDelay(
          invocationID: fixture.controllerInvocationID,
          additionalNanoseconds: 10
        )]
      )]
    )
    #expect(delayed.controllerScenarios.first?.disposition == .refused([
      .invalidTransformedSchedule(.timedReadDeadlineExceeded(overlappingID)),
    ]))
    #expect(
      delayed.controllerScenarios.first?.steps
        == fixture.controllerReplaySteps(from: delayRecording)
    )

    let boundaryRecording = fixture.overlappingControllerRecording(
      firstCompletionOffsetNanoseconds: 50,
      secondCompletionOffsetNanoseconds: 55,
      secondChunkOffsetNanoseconds: 35,
      secondTimeoutNanoseconds: 100
    )
    let advanced = fixture.replay(
      recording: boundaryRecording,
      scenarios: [ControllerReplayScenario(
        id: ControllerReplayScenarioID(rawValue: "overlap-boundary"),
        perturbations: [.timeout(
          invocationID: fixture.controllerInvocationID,
          atNanosecondsAfterInvocation: 10
        )]
      )]
    )
    #expect(advanced.controllerScenarios.first?.disposition == .refused([
      .invalidTransformedSchedule(.readChunkPrecedesInvocation(overlappingID)),
    ]))
    #expect(
      advanced.controllerScenarios.first?.steps
        == fixture.controllerReplaySteps(from: boundaryRecording)
    )
  }

  @Test("retained FIX-010 fixtures remain a deterministic transcript consumer")
  func retainedControllerFixturesRemainConsumed() async throws {
    let exchanges = ControllerTranscriptFixtures.successfulPassiveProbe(
      fragmented: true,
      delayNanoseconds: 17
    )
    let exchange = try #require(exchanges.first)
    let clock = DeterministicRuntimeClock(startNanoseconds: 1_000)
    let link = SimulatedGRBLLink(exchanges: [exchange], clock: clock)

    try await link.open()
    try await link.write(exchange.expectedWrite)
    let first = try await link.read(maximumBytes: 4_096, timeoutNanoseconds: 100)
    let second = try await link.read(maximumBytes: 4_096, timeoutNanoseconds: 100)
    await link.close()

    var combined = first
    combined.append(contentsOf: second)
    #expect(combined == Data(
      "[VER:1.1h.20240101:]\r\n[OPT:VN,15,128]\r\nok\r\n".utf8
    ))
    #expect(clock.nowNanoseconds() == 1_034)
    #expect(link.completedWriteCount == 1)
  }
}

private struct ReplayFixture {
  let definition: PlotterEpisodeDefinition
  let manifest: PlotterEpisodeManifest
  let recordedEffectRevisions: [PlotterEpisodeRecordedEffectRevision]
  let initialState: PlotterEpisodeState
  let journal: EpisodeJournal<PlotterEpisodeEventPayload>
  let timeline: [PlotterEpisodeReplayDecisionFrame]
  let manualEffectID: EpisodeEffectID
  let manualRequestID: IntentRequestID
  let controllerInvocationID: ControllerInvocationID

  static func make(includeManualSettlement: Bool) throws -> ReplayFixture {
    let episodeID = EpisodeID(rawValue: uuid(1))
    let definitionID = EpisodeDefinitionID(rawValue: uuid(2))
    let manifestID = EpisodeManifestID(rawValue: uuid(3))
    let grammar = PlotterIntentGrammar(permittedFamilies: PlotterIntentFamily.allCases)
    let initialPrototype = PlotterEpisodeState(
      episodeID: episodeID,
      canonicalDigest: EpisodeStateDigest(rawValue: "excluded-from-canonical-form"),
      permittedIntentFamilies: grammar.permittedFamilies
    )
    let initialDigest = try PlotterEpisodeCanonicalDigestV1.digest(initialPrototype)
    let initialContext = PlotterEpisodeInitialContext(
      initialStateDigest: initialDigest,
      paperRevision: revision("paper-v1"),
      environmentRevision: revision("environment-v1")
    )
    let definition = PlotterEpisodeDefinition(
      id: definitionID,
      revision: revision("definition-v1"),
      goal: EpisodeGoal(
        terminalConstraints: [],
        assessmentCriteria: [],
        terminationConditions: []
      ),
      initialContext: initialContext,
      permittedIntentGrammar: grammar,
      budgets: EpisodeBudgets(maximumExternalEffectCount: 4),
      assessmentRules: []
    )
    let executable = PlotterEpisodeReplayService.executableDescriptor
    let manifest = PlotterEpisodeManifest(
      id: manifestID,
      episodeID: episodeID,
      definitionID: definitionID,
      definitionRevision: definition.revision,
      domainRevision: executable.domainRevision,
      evaluatorRevision: executable.evaluatorRevision,
      reducerRevision: executable.reducerRevision,
      schemaRevisions: executable.schemaRevisions,
      buildRevision: executable.buildRevision,
      deterministicSeed: 91,
      domainManifest: PlotterEpisodeDomainManifest(
        paperRevision: initialContext.paperRevision,
        environmentRevision: initialContext.environmentRevision
      )
    )

    let sessionRequestID = IntentRequestID(rawValue: uuid(4))
    let sessionEffectID = EpisodeEffectID(rawValue: uuid(5))
    let manualRequestID = IntentRequestID(rawValue: uuid(6))
    let manualEffectID = EpisodeEffectID(rawValue: uuid(7))
    let sessionEffectRevision = revision("session-effect-v1")
    let manualEffectRevision = revision("manual-effect-v1")
    let recordedEffectRevisions = [
      PlotterEpisodeRecordedEffectRevision(
        effectID: sessionEffectID,
        revision: sessionEffectRevision
      ),
      PlotterEpisodeRecordedEffectRevision(
        effectID: manualEffectID,
        revision: manualEffectRevision
      ),
    ]
    let manualIntent = PlotterIntent.manualMotion(
      .jog(try PlotterJogRequest(direction: .positiveX, distanceMM: 4))
    )
    let manualFacts = readyControllerFacts()
    var state = PlotterEpisodeState(
      episodeID: episodeID,
      canonicalDigest: initialDigest,
      permittedIntentFamilies: grammar.permittedFamilies
    )
    var events: [PlotterEpisodeEvent] = []

    let sessionIntent = PlotterIntent.session(.begin)
    let sessionAccepted = try accepted(
      requestID: sessionRequestID,
      intent: sessionIntent,
      effectID: sessionEffectID,
      state: state,
      facts: []
    )
    state = try append(
      .intentAccepted(sessionAccepted),
      to: &events,
      state: state,
      episodeID: episodeID
    )
    let sessionContext = PlotterEffectResultContext(
      episodeID: episodeID,
      requestID: sessionRequestID,
      intent: sessionIntent,
      effectID: sessionEffectID,
      environment: .live,
      effectRevision: sessionEffectRevision
    )
    state = try append(
      .effectResult(.completed(context: sessionContext, output: .sessionPrepared)),
      to: &events,
      state: state,
      episodeID: episodeID
    )
    let manualAccepted = try accepted(
      requestID: manualRequestID,
      intent: manualIntent,
      effectID: manualEffectID,
      state: state,
      facts: manualFacts
    )
    state = try append(
      .intentAccepted(manualAccepted),
      to: &events,
      state: state,
      episodeID: episodeID
    )
    let progress = try PlotterEffectProgress(
      episodeID: episodeID,
      requestID: manualRequestID,
      intent: manualIntent,
      effectID: manualEffectID,
      effectRevision: manualEffectRevision,
      environment: .live,
      lane: .machine,
      owningSubsystem: .machineController,
      phase: .progressing,
      startedAt: Date(timeIntervalSince1970: 103),
      lastAttributableProgressAt: Date(timeIntervalSince1970: 104),
      resultCurrentlyAwaited: .controllerSettlement,
      deadline: Date(timeIntervalSince1970: 120),
      cancellation: PlotterEffectCancellationStatus(
        availability: .available,
        phase: .notRequested
      )
    )
    state = try append(
      .effectProgressed(progress),
      to: &events,
      state: state,
      episodeID: episodeID
    )
    if includeManualSettlement {
      let manualContext = PlotterEffectResultContext(
        episodeID: episodeID,
        requestID: manualRequestID,
        intent: manualIntent,
        effectID: manualEffectID,
        environment: .live,
        effectRevision: manualEffectRevision
      )
      state = try append(
        .effectResult(.cancelled(context: manualContext)),
        to: &events,
        state: state,
        episodeID: episodeID
      )
    }
    _ = state

    var timeline = (0...events.count).map {
      PlotterEpisodeReplayDecisionFrame(
        prefixEventCount: $0,
        candidates: [],
        capabilityFacts: []
      )
    }
    timeline[0] = PlotterEpisodeReplayDecisionFrame(
      prefixEventCount: 0,
      candidates: [PlotterEpisodeReplayIntentCandidate(
        requestID: sessionRequestID,
        intent: sessionIntent
      )],
      capabilityFacts: []
    )
    timeline[2] = PlotterEpisodeReplayDecisionFrame(
      prefixEventCount: 2,
      candidates: [PlotterEpisodeReplayIntentCandidate(
        requestID: manualRequestID,
        intent: manualIntent
      )],
      capabilityFacts: manualFacts
    )

    return ReplayFixture(
      definition: definition,
      manifest: manifest,
      recordedEffectRevisions: recordedEffectRevisions,
      initialState: PlotterEpisodeState(
        episodeID: episodeID,
        canonicalDigest: initialDigest,
        permittedIntentFamilies: grammar.permittedFamilies
      ),
      journal: try EpisodeJournal(
        manifestID: manifestID,
        episodeID: episodeID,
        events: events
      ),
      timeline: timeline,
      manualEffectID: manualEffectID,
      manualRequestID: manualRequestID,
      controllerInvocationID: ControllerInvocationID(rawValue: uuid(20))
    )
  }

  func replay(
    manifest replayManifest: PlotterEpisodeManifest? = nil,
    recordedEffectRevisions replayEffectRevisions: [PlotterEpisodeRecordedEffectRevision]? = nil,
    journal replayJournal: EpisodeJournal<PlotterEpisodeEventPayload>? = nil,
    timeline replayTimeline: [PlotterEpisodeReplayDecisionFrame]? = nil,
    recording: EpisodeRecordingSnapshot? = nil,
    scenarios: [ControllerReplayScenario] = []
  ) -> PlotterEpisodeReplayReport {
    PlotterEpisodeReplayService().replay(
      definition: definition,
      manifest: replayManifest ?? manifest,
      recordedEffectRevisions: replayEffectRevisions ?? recordedEffectRevisions,
      initialState: initialState,
      journal: replayJournal ?? journal,
      decisionTimeline: replayTimeline ?? timeline,
      recording: recording,
      controllerScenarios: scenarios
    )
  }

  func manifestWith(
    domainRevision: EpisodeRevisionIdentifier? = nil,
    evaluatorRevision: EpisodeRevisionIdentifier? = nil,
    reducerRevision: EpisodeRevisionIdentifier? = nil,
    schemaRevisions: EpisodeSchemaRevisions? = nil,
    buildRevision: EpisodeRevisionIdentifier? = nil
  ) -> PlotterEpisodeManifest {
    PlotterEpisodeManifest(
      id: manifest.id,
      episodeID: manifest.episodeID,
      definitionID: manifest.definitionID,
      definitionRevision: manifest.definitionRevision,
      domainRevision: domainRevision ?? manifest.domainRevision,
      evaluatorRevision: evaluatorRevision ?? manifest.evaluatorRevision,
      reducerRevision: reducerRevision ?? manifest.reducerRevision,
      schemaRevisions: schemaRevisions ?? manifest.schemaRevisions,
      buildRevision: buildRevision ?? manifest.buildRevision,
      deterministicSeed: manifest.deterministicSeed,
      domainManifest: manifest.domainManifest
    )
  }

  var manualProgress: PlotterEffectProgress? {
    for event in journal.events {
      guard case let .effectProgressed(progress) = event.payload,
            progress.effectID == manualEffectID else { continue }
      return progress
    }
    return nil
  }

  var manualResult: PlotterEffectResultContext? {
    for event in journal.events {
      guard case let .effectResult(result) = event.payload,
            result.context.effectID == manualEffectID else { continue }
      return result.context
    }
    return nil
  }

  func journal(
    payloads: [PlotterEpisodeEventPayload]
  ) throws -> EpisodeJournal<PlotterEpisodeEventPayload> {
    var state = initialState
    var events: [PlotterEpisodeEvent] = []
    for payload in payloads {
      state = try append(
        payload,
        to: &events,
        state: state,
        episodeID: manifest.episodeID
      )
    }
    return try EpisodeJournal(
      manifestID: manifest.id,
      episodeID: manifest.episodeID,
      events: events
    )
  }

  func timeline(forEventCount eventCount: Int) -> [PlotterEpisodeReplayDecisionFrame] {
    (0...eventCount).map { index in
      timeline.first(where: { $0.prefixEventCount == index })
        ?? PlotterEpisodeReplayDecisionFrame(
          prefixEventCount: index,
          candidates: [],
          capabilityFacts: []
        )
    }
  }

  var controllerReplaySteps: [ControllerReplayStep] {
    controllerReplaySteps(from: controllerRecording())
  }

  var overlappingControllerInvocationID: ControllerInvocationID {
    ControllerInvocationID(rawValue: uuid(22))
  }

  func controllerReplaySteps(
    from recording: EpisodeRecordingSnapshot
  ) -> [ControllerReplayStep] {
    recording.entries.compactMap { entry in
      guard case let .controller(record) = entry.record else { return nil }
      return ControllerReplayStep(
        sourceRecordingSequence: entry.sequence,
        replayOffsetNanoseconds: entry.monotonicOffsetNanoseconds,
        provenance: entry.provenance,
        record: record
      )
    }
  }

  var completenessIssues: [EpisodeRecordingCompletenessIssue] {
    let missingController = ControllerInvocationID(rawValue: uuid(30))
    let stream = CameraStreamIdentity(
      source: CameraSourceIdentity(rawValue: "camera"),
      configuration: CameraConfigurationIdentity(rawValue: uuid(31))
    )
    return [
      .controllerCompletionMissing(missingController),
      .cameraStartIncomplete(stream),
      .runLedgerIntegrityIncomplete(LedgerRunID(uuid(32))),
      .frameRetentionAccountingOverflow,
    ]
  }

  func controllerRecording(
    completenessIssues: [EpisodeRecordingCompletenessIssue] = [],
    includeDownstreamController: Bool = false
  ) -> EpisodeRecordingSnapshot {
    let manualEvent = journal.events[2]
    let provenance = EpisodeRecordingProvenance(
      episodeID: manifest.episodeID,
      intentRequestID: manualRequestID,
      effectID: manualEffectID,
      correlationID: manualEvent.correlationID,
      environment: .live
    )
    let invocation = ControllerInvocation(
      id: controllerInvocationID,
      operation: .timedRead(ControllerTimedReadParameters(
        maximumByteCount: 64,
        timeoutNanoseconds: 100
      ))
    )
    let completion = ControllerCompletion(
      invocationID: controllerInvocationID,
      outcome: .succeeded(.timedRead(
        chunks: [
          ControllerReadChunk(
            bytes: Data("abcdef".utf8),
            monotonicOffsetNanoseconds: 15
          ),
          ControllerReadChunk(
            bytes: Data("gh".utf8),
            monotonicOffsetNanoseconds: 25
          ),
        ],
        timedOut: false
      ))
    )
    var entries = [
      EpisodeRecordingEntry(
        sequence: 0,
        monotonicOffsetNanoseconds: 10,
        provenance: provenance,
        record: .controller(.invocation(invocation))
      ),
      EpisodeRecordingEntry(
        sequence: 1,
        monotonicOffsetNanoseconds: 30,
        provenance: provenance,
        record: .controller(.completion(completion))
      ),
    ]
    if includeDownstreamController {
      entries.append(EpisodeRecordingEntry(
        sequence: 2,
        monotonicOffsetNanoseconds: 50,
        provenance: provenance,
        record: .controller(.invocation(ControllerInvocation(
          id: ControllerInvocationID(rawValue: uuid(21)),
          operation: .rawWrite(ControllerRawWriteParameters(bytes: Data("?".utf8)))
        )))
      ))
    }
    return EpisodeRecordingSnapshot(
      formatVersion: EpisodeRecordingStore.currentFormatVersion,
      recordingID: EpisodeRecordingID(rawValue: uuid(40)),
      schemaRevision: EpisodeRecordingSchemaRevision(rawValue: "recording-v1"),
      frameRetentionPolicy: EpisodeFrameRetentionPolicy(
        maximumUniqueFrameCount: 4,
        maximumTotalUniqueFrameBytes: 4_096
      ),
      entries: entries,
      close: EpisodeRecordingClose(
        monotonicOffsetNanoseconds: includeDownstreamController ? 51 : 31
      ),
      durability: .verified,
      completenessIssues: completenessIssues
    )
  }

  func recordingWithForeignCameraStart() -> EpisodeRecordingSnapshot {
    let source = controllerRecording()
    let exact = source.entries[0].provenance
    let foreign = EpisodeRecordingProvenance(
      episodeID: exact.episodeID,
      intentRequestID: exact.intentRequestID,
      effectID: exact.effectID,
      correlationID: EpisodeCorrelationID(rawValue: uuid(99)),
      environment: exact.environment
    )
    let stream = CameraStreamIdentity(
      source: CameraSourceIdentity(rawValue: "foreign-camera"),
      configuration: CameraConfigurationIdentity(rawValue: uuid(98))
    )
    return EpisodeRecordingSnapshot(
      formatVersion: source.formatVersion,
      recordingID: source.recordingID,
      schemaRevision: source.schemaRevision,
      frameRetentionPolicy: source.frameRetentionPolicy,
      entries: source.entries + [EpisodeRecordingEntry(
        sequence: 2,
        monotonicOffsetNanoseconds: 35,
        provenance: foreign,
        record: .camera(.lifecycle(.startRequested(stream)))
      )],
      close: EpisodeRecordingClose(monotonicOffsetNanoseconds: 36),
      durability: source.durability,
      completenessIssues: source.completenessIssues
    )
  }

  func recordingWithMixedValidCameraStart() -> EpisodeRecordingSnapshot {
    let source = controllerRecording()
    let sessionEvent = journal.events[0]
    guard case let .intentAccepted(sessionAccepted) = sessionEvent.payload else {
      return source
    }
    let mixed = EpisodeRecordingProvenance(
      episodeID: source.entries[0].provenance.episodeID,
      intentRequestID: sessionAccepted.requestID,
      effectID: manualEffectID,
      correlationID: sessionEvent.correlationID,
      environment: source.entries[0].provenance.environment
    )
    let stream = CameraStreamIdentity(
      source: CameraSourceIdentity(rawValue: "mixed-valid-camera"),
      configuration: CameraConfigurationIdentity(rawValue: uuid(97))
    )
    return EpisodeRecordingSnapshot(
      formatVersion: source.formatVersion,
      recordingID: source.recordingID,
      schemaRevision: source.schemaRevision,
      frameRetentionPolicy: source.frameRetentionPolicy,
      entries: source.entries + [EpisodeRecordingEntry(
        sequence: 2,
        monotonicOffsetNanoseconds: 35,
        provenance: mixed,
        record: .camera(.lifecycle(.startRequested(stream)))
      )],
      close: EpisodeRecordingClose(monotonicOffsetNanoseconds: 36),
      durability: source.durability,
      completenessIssues: source.completenessIssues
    )
  }

  func emptyControllerRecording() -> EpisodeRecordingSnapshot {
    let source = controllerRecording()
    return EpisodeRecordingSnapshot(
      formatVersion: source.formatVersion,
      recordingID: source.recordingID,
      schemaRevision: source.schemaRevision,
      frameRetentionPolicy: source.frameRetentionPolicy,
      entries: [],
      close: EpisodeRecordingClose(monotonicOffsetNanoseconds: 0),
      durability: source.durability,
      completenessIssues: source.completenessIssues
    )
  }

  func writeOnlyControllerRecording() -> EpisodeRecordingSnapshot {
    let source = controllerRecording()
    let provenance = source.entries[0].provenance
    let invocationID = ControllerInvocationID(rawValue: uuid(23))
    let bytes = Data("?".utf8)
    return EpisodeRecordingSnapshot(
      formatVersion: source.formatVersion,
      recordingID: source.recordingID,
      schemaRevision: source.schemaRevision,
      frameRetentionPolicy: source.frameRetentionPolicy,
      entries: [
        EpisodeRecordingEntry(
          sequence: 0,
          monotonicOffsetNanoseconds: 10,
          provenance: provenance,
          record: .controller(.invocation(ControllerInvocation(
            id: invocationID,
            operation: .rawWrite(ControllerRawWriteParameters(bytes: bytes))
          )))
        ),
        EpisodeRecordingEntry(
          sequence: 1,
          monotonicOffsetNanoseconds: 20,
          provenance: provenance,
          record: .controller(.completion(ControllerCompletion(
            invocationID: invocationID,
            outcome: .succeeded(.rawWrite(writtenByteCount: bytes.count))
          )))
        ),
      ],
      close: EpisodeRecordingClose(monotonicOffsetNanoseconds: 21),
      durability: source.durability,
      completenessIssues: source.completenessIssues
    )
  }

  func failedControllerRecording() -> EpisodeRecordingSnapshot {
    let source = controllerRecording()
    let completionEntry = source.entries[1]
    let failedCompletion = ControllerCompletion(
      invocationID: controllerInvocationID,
      outcome: .failed(ControllerOperationFailure(
        kind: .inputOutput,
        partialByteCount: 6,
        partialReadChunks: [ControllerReadChunk(
          bytes: Data("abcdef".utf8),
          monotonicOffsetNanoseconds: 15
        )]
      ))
    )
    return EpisodeRecordingSnapshot(
      formatVersion: source.formatVersion,
      recordingID: source.recordingID,
      schemaRevision: source.schemaRevision,
      frameRetentionPolicy: source.frameRetentionPolicy,
      entries: [
        source.entries[0],
        EpisodeRecordingEntry(
          sequence: completionEntry.sequence,
          monotonicOffsetNanoseconds: completionEntry.monotonicOffsetNanoseconds,
          provenance: completionEntry.provenance,
          record: .controller(.completion(failedCompletion))
        ),
      ],
      close: source.close,
      durability: source.durability,
      completenessIssues: source.completenessIssues
    )
  }

  func overlappingControllerRecording(
    firstCompletionOffsetNanoseconds: UInt64,
    secondCompletionOffsetNanoseconds: UInt64,
    secondChunkOffsetNanoseconds: UInt64,
    secondTimeoutNanoseconds: UInt64
  ) -> EpisodeRecordingSnapshot {
    let manualEvent = journal.events[2]
    let provenance = EpisodeRecordingProvenance(
      episodeID: manifest.episodeID,
      intentRequestID: manualRequestID,
      effectID: manualEffectID,
      correlationID: manualEvent.correlationID,
      environment: .live
    )
    let firstInvocation = ControllerInvocation(
      id: controllerInvocationID,
      operation: .timedRead(ControllerTimedReadParameters(
        maximumByteCount: 64,
        timeoutNanoseconds: 100
      ))
    )
    let secondInvocation = ControllerInvocation(
      id: overlappingControllerInvocationID,
      operation: .timedRead(ControllerTimedReadParameters(
        maximumByteCount: 64,
        timeoutNanoseconds: secondTimeoutNanoseconds
      ))
    )
    let firstCompletion = ControllerCompletion(
      invocationID: controllerInvocationID,
      outcome: .succeeded(.timedRead(
        chunks: [ControllerReadChunk(
          bytes: Data("a".utf8),
          monotonicOffsetNanoseconds: 15
        )],
        timedOut: false
      ))
    )
    let secondCompletion = ControllerCompletion(
      invocationID: overlappingControllerInvocationID,
      outcome: .succeeded(.timedRead(
        chunks: [ControllerReadChunk(
          bytes: Data("b".utf8),
          monotonicOffsetNanoseconds: secondChunkOffsetNanoseconds
        )],
        timedOut: false
      ))
    )
    return EpisodeRecordingSnapshot(
      formatVersion: EpisodeRecordingStore.currentFormatVersion,
      recordingID: EpisodeRecordingID(rawValue: uuid(41)),
      schemaRevision: EpisodeRecordingSchemaRevision(rawValue: "recording-v1"),
      frameRetentionPolicy: EpisodeFrameRetentionPolicy(
        maximumUniqueFrameCount: 4,
        maximumTotalUniqueFrameBytes: 4_096
      ),
      entries: [
        EpisodeRecordingEntry(
          sequence: 0,
          monotonicOffsetNanoseconds: 10,
          provenance: provenance,
          record: .controller(.invocation(firstInvocation))
        ),
        EpisodeRecordingEntry(
          sequence: 1,
          monotonicOffsetNanoseconds: 20,
          provenance: provenance,
          record: .controller(.invocation(secondInvocation))
        ),
        EpisodeRecordingEntry(
          sequence: 2,
          monotonicOffsetNanoseconds: firstCompletionOffsetNanoseconds,
          provenance: provenance,
          record: .controller(.completion(firstCompletion))
        ),
        EpisodeRecordingEntry(
          sequence: 3,
          monotonicOffsetNanoseconds: secondCompletionOffsetNanoseconds,
          provenance: provenance,
          record: .controller(.completion(secondCompletion))
        ),
      ],
      close: EpisodeRecordingClose(
        monotonicOffsetNanoseconds: secondCompletionOffsetNanoseconds + 1
      ),
      durability: .verified,
      completenessIssues: []
    )
  }
}

private func accepted(
  requestID: IntentRequestID,
  intent: PlotterIntent,
  effectID: EpisodeEffectID,
  state: PlotterEpisodeState,
  facts: [PlotterCapabilityFact]
) throws -> PlotterAcceptedIntent {
  let decision = PlotterIntentEvaluator().evaluate(
    requestID: requestID,
    intent: intent,
    state: state,
    capabilityFacts: facts
  )
  guard case let .admitted(context, requirements) = decision else {
    throw ReplayFixtureError.intentWasNotAdmitted
  }
  return try PlotterAcceptedIntent(
    requestID: requestID,
    intent: intent,
    comparedStateRevision: context.comparedStateRevision,
    comparedCapabilityFacts: context.comparedCapabilityFacts,
    satisfiedRequirements: requirements,
    execution: .externalEffect(effectID: effectID, environment: .live)
  )
}

private func append(
  _ payload: PlotterEpisodeEventPayload,
  to events: inout [PlotterEpisodeEvent],
  state: PlotterEpisodeState,
  episodeID: EpisodeID
) throws -> PlotterEpisodeState {
  let index = events.count
  let eventID = EpisodeEventID(rawValue: uuid(UInt8(50 + index)))
  let correlationID = EpisodeCorrelationID(rawValue: uuid(UInt8(70 + index)))
  let postRevision = EpisodeStateRevision(rawValue: state.revision.rawValue + 1)
  func event(digest: EpisodeStateDigest) -> PlotterEpisodeEvent {
    PlotterEpisodeEvent(
      id: eventID,
      episodeID: episodeID,
      sequence: EpisodeEventSequence(rawValue: UInt64(index)),
      recordedAt: Date(timeIntervalSince1970: TimeInterval(100 + index)),
      actor: EpisodeEventActor(
        id: EpisodeActorID(rawValue: "replay-fixture"),
        origin: .runtime
      ),
      correlationID: correlationID,
      preStateRevision: state.revision,
      postStateRevision: postRevision,
      payload: payload,
      postStateDigest: digest
    )
  }
  let provisional = PlotterEpisodeReducer().reduce(
    state: state,
    event: event(digest: EpisodeStateDigest(rawValue: "excluded"))
  ).state
  let canonical = try PlotterEpisodeCanonicalDigestV1.digest(provisional)
  let committed = event(digest: canonical)
  events.append(committed)
  return PlotterEpisodeReducer().reduce(state: state, event: committed).state
}

private func readyControllerFacts() -> [PlotterCapabilityFact] {
  let owner = EpisodeAuthorityID(rawValue: "MachineController")
  return [
    .connection(PlotterConnectionFact(
      owner: owner,
      revision: CapabilityFactRevision(rawValue: 1),
      environment: .live,
      isConnected: true
    )),
    .motion(PlotterMotionFact(
      owner: owner,
      revision: CapabilityFactRevision(rawValue: 2),
      isEnabled: true
    )),
    .pose(PlotterPoseFact(
      owner: owner,
      revision: CapabilityFactRevision(rawValue: 3),
      machinePosition: nil,
      isSettled: true,
      settlementPolicyRevision: revision("controller-settlement-v1")
    )),
  ]
}

private func failure(
  in scenario: ControllerReplayScenarioResult
) throws -> ControllerOperationFailure {
  guard case let .completion(completion) = scenario.steps[1].record,
        case let .failed(failure) = completion.outcome else {
    throw ReplayFixtureError.expectedControllerFailure
  }
  return failure
}

private enum ReplayFixtureError: Error {
  case intentWasNotAdmitted
  case expectedControllerFailure
}

private func revision(_ value: String) -> EpisodeRevisionIdentifier {
  EpisodeRevisionIdentifier(rawValue: value)
}

private func uuid(_ value: UInt8) -> UUID {
  UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
}
