import EpisodeCore
import Foundation
import PlotterEpisodeModel
@testable import PlotterEpisodeRuntime
import PlotterRuntime
import Testing

@Suite("Plotter incident package assembler and exporter")
struct PlotterIncidentPackageTests {
  @Test("incident source references retain exact durable journal and recording completeness")
  func incidentSourceArtifactReferencesRoundTrip() throws {
    let journalURL = URL(fileURLWithPath: "/tmp/episode-journal.json")
    let recordingURL = URL(fileURLWithPath: "/tmp/controller-recording", isDirectory: true)
    let reference = PlotterIncidentSourceArtifactReferences(
      episodeID: IncidentFixture.episodeID,
      journal: EpisodeArtifactReference(
        id: EpisodeArtifactID(rawValue: "manual-motion-journal.json"),
        revision: EpisodeRevisionIdentifier(rawValue: "plotter-manual-motion-journal-v1"),
        digest: String(repeating: "a", count: 64)
      ),
      journalFileURL: journalURL,
      recordingID: IncidentFixture.recordingID,
      recordingDirectoryURL: recordingURL,
      recordingDurability: .uncertain(candidateWasObserved: true),
      recordingCompletenessIssues: [.controllerCompletionMissing(
        ControllerInvocationID(rawValue: uuid(90))
      )]
    )

    let encoded = try JSONEncoder().encode(reference)
    #expect(try JSONDecoder().decode(
      PlotterIncidentSourceArtifactReferences.self,
      from: encoded
    ) == reference)
    #expect(reference.recordingCompletenessIssues == [.controllerCompletionMissing(
      ControllerInvocationID(rawValue: uuid(90))
    )])
  }

  @Test("canonical export is deterministic, versioned, and integrity-verifiable")
  func deterministicVerifiedExport() throws {
    let source = try IncidentFixture.source()
    let reversedOwners = PlotterIncidentPackageSource(
      manifest: source.manifest,
      journal: source.journal,
      recording: source.recording,
      observations: source.observations,
      measurements: source.measurements,
      evidenceDecisions: source.evidenceDecisions,
      outcomes: source.outcomes,
      assessments: source.assessments,
      runtimeState: source.runtimeState,
      userInterfaceProjection: source.userInterfaceProjection,
      currentOwners: Array(source.currentOwners.reversed()),
      artifactStatuses: Array(source.artifactStatuses.reversed()),
      sensitiveFrameIDs: [],
      unresolvedAmbiguities: Array(source.unresolvedAmbiguities.reversed())
    )
    let assembler = PlotterIncidentPackageAssembler()
    let first = try assembled(assembler.assemble(source))
    let second = try assembled(assembler.assemble(reversedOwners))

    #expect(first == second)
    #expect(first.formatVersion == 1)
    #expect(first.encoding == .canonicalJSONV1)
    #expect(first.payloadByteCount == first.payload.count)
    #expect(first.payloadSHA256.count == 64)

    let package = try integrityConfirmed(assembler.verify(first))
    #expect(package.manifest == source.manifest)
    #expect(package.journal == source.journal)
    #expect(package.sourceReportedRecording == source.recording)
    #expect(package.boundedness.sourceCounts == package.boundedness.includedCounts)
    #expect(!package.boundedness.isTruncated)
    #expect(package.recordingSourceFacts == [.sourceSnapshotNotRevalidated])
    #expect(package.artifactStatuses.isEmpty)
    #expect(package.frameReferences.isEmpty)
    #expect(!package.hasUnresolvedAmbiguity)
  }

  @Test("tampered bytes and envelope counts fail integrity verification")
  func tamperedExportFailsClosed() throws {
    let assembler = PlotterIncidentPackageAssembler()
    let export = try assembled(assembler.assemble(IncidentFixture.source()))
    var tamperedPayload = export.payload
    tamperedPayload[tamperedPayload.startIndex] ^= 0x01
    let tampered = PlotterIncidentPackageExport(
      formatVersion: export.formatVersion,
      encoding: export.encoding,
      payloadByteCount: export.payloadByteCount,
      payloadSHA256: export.payloadSHA256,
      payload: tamperedPayload
    )
    #expect(refusal(assembler.verify(tampered)) == .payloadDigestMismatch)

    let wrongCount = PlotterIncidentPackageExport(
      formatVersion: export.formatVersion,
      encoding: export.encoding,
      payloadByteCount: export.payloadByteCount + 1,
      payloadSHA256: export.payloadSHA256,
      payload: export.payload
    )
    #expect(refusal(assembler.verify(wrongCount)) == .payloadByteCountMismatch(
      expected: export.payloadByteCount + 1,
      actual: export.payloadByteCount
    ))
  }

  @Test("manifest, journal, runtime, projection, and recording episode identity fail closed")
  func crossEpisodeRelationshipsFailClosed() throws {
    let source = try IncidentFixture.source()
    let otherEpisode = EpisodeID(rawValue: uuid(240))
    let otherJournal = try EpisodeJournal<PlotterEpisodeEventPayload>(
      manifestID: source.manifest.id,
      episodeID: otherEpisode
    )
    let mismatched = IncidentFixture.copy(source, journal: otherJournal)

    #expect(refusal(PlotterIncidentPackageAssembler().assemble(mismatched))
      == .relationshipMismatch(.manifestJournal))
  }

  @Test("duplicate semantic identifiers are rejected even in a valid journal sequence")
  func duplicateSemanticIdentifierFailsClosed() throws {
    let observation = IncidentFixture.observation(id: 30)
    let source = try IncidentFixture.source(
      payloads: [
        .observationRecorded(observation),
        .observationRecorded(observation),
      ],
      observations: [observation, observation]
    )

    #expect(refusal(PlotterIncidentPackageAssembler().assemble(source))
      == .duplicateIdentifier(.observation))
  }

  @Test("unattributed recording provenance exports as explicit non-authoritative facts")
  func unattributedRecordingProvenanceIsDiagnostic() throws {
    let entry = EpisodeRecordingEntry(
      sequence: 0,
      monotonicOffsetNanoseconds: 1,
      provenance: .unattributed,
      record: .runLedgerDiagnostic(RunLedgerDiagnosticReference(
        runID: LedgerRunID(uuid(31)),
        recordedRange: RunLedgerSequenceRange(first: 0, last: 0),
        integrity: .verified,
        completeness: .complete
      ))
    )
    let source = try IncidentFixture.source(recording: IncidentFixture.recording(
      entries: [entry],
      closeOffset: 2
    ))

    let package = try integrityConfirmed(PlotterIncidentPackageAssembler().verify(
      assembled(PlotterIncidentPackageAssembler().assemble(source))
    ))
    #expect(package.recordingSourceFacts.contains(.sourceSnapshotNotRevalidated))
    #expect(package.recordingSourceFacts.contains(.episodeProvenanceUnavailable(sequence: 0)))
    #expect(package.recordingSourceFacts.contains(.environmentProvenanceUnavailable(sequence: 0)))
  }

  @Test("explicit foreign recording provenance still refuses cross-episode mixing")
  func foreignRecordingEpisodeFailsClosed() throws {
    let entry = EpisodeRecordingEntry(
      sequence: 0,
      monotonicOffsetNanoseconds: 1,
      provenance: EpisodeRecordingProvenance(
        episodeID: EpisodeID(rawValue: uuid(34)),
        environment: .live
      ),
      record: .runLedgerDiagnostic(RunLedgerDiagnosticReference(
        runID: LedgerRunID(uuid(35)),
        recordedRange: RunLedgerSequenceRange(first: 0, last: 0),
        integrity: .verified,
        completeness: .complete
      ))
    )
    let source = try IncidentFixture.source(recording: IncidentFixture.recording(
      entries: [entry],
      closeOffset: 2
    ))

    #expect(refusal(PlotterIncidentPackageAssembler().assemble(source))
      == .relationshipMismatch(.recordingEpisode))
  }

  @Test("caller-built malformed recording snapshots are never certified by the incident service")
  func callerBuiltRecordingIsNotRevalidated() throws {
    let completion = ControllerCompletion(
      invocationID: ControllerInvocationID(rawValue: uuid(32)),
      outcome: .succeeded(.close)
    )
    let malformedEntry = EpisodeRecordingEntry(
      sequence: 999,
      monotonicOffsetNanoseconds: 5,
      provenance: .unattributed,
      record: .controller(.completion(completion))
    )
    let source = try IncidentFixture.source(recording: IncidentFixture.recording(
      entries: [malformedEntry],
      closeOffset: 1
    ))
    let package = try integrityConfirmed(PlotterIncidentPackageAssembler().verify(
      assembled(PlotterIncidentPackageAssembler().assemble(source))
    ))

    #expect(package.sourceReportedRecording.entries == [malformedEntry])
    #expect(package.recordingSourceFacts.contains(.sourceSnapshotNotRevalidated))
    #expect(package.recordingSourceFacts.contains(.episodeProvenanceUnavailable(sequence: 999)))
    #expect(package.recordingSourceFacts.contains(.environmentProvenanceUnavailable(sequence: 999)))
  }

  @Test("canonical envelope integrity does not promote source-reported recording completeness")
  func envelopeIntegrityDoesNotPromoteRecordingCompleteness() throws {
    let invocationID = ControllerInvocationID(rawValue: uuid(33))
    let source = try IncidentFixture.source(recording: IncidentFixture.recording(
      issues: [.controllerCompletionMissing(invocationID)]
    ))
    let package = try integrityConfirmed(PlotterIncidentPackageAssembler().verify(
      assembled(PlotterIncidentPackageAssembler().assemble(source))
    ))

    #expect(package.recordingSourceFacts == [
      .sourceSnapshotNotRevalidated,
      .sourceReportedIssue(.controllerCompletionMissing(invocationID)),
    ])
  }

  @Test("accepted evidence cannot reference a missing observation or measurement")
  func missingEvidenceSubjectFailsClosed() throws {
    let evidence = try PlotterEvidence(
      id: PlotterEvidenceID(rawValue: uuid(40)),
      episodeID: IncidentFixture.episodeID,
      subject: .measurement(PlotterMeasurementID(rawValue: uuid(41))),
      question: .drawingOutcome,
      inputEnvironment: .live,
      evidenceClass: .livePhysical,
      acceptedBy: EpisodeAuthorityID(rawValue: "evidence-owner"),
      acceptedAt: IncidentFixture.time,
      applicabilityRevision: revision("evidence-r1")
    )
    let decision = PlotterEvidenceDecision.accepted(evidence)
    let source = try IncidentFixture.source(
      payloads: [.evidenceDecided(decision)],
      evidenceDecisions: [decision]
    )

    #expect(refusal(PlotterIncidentPackageAssembler().assemble(source))
      == .relationshipMismatch(.evidenceSubject))
  }

  @Test("simulated observation evidence cannot be caller-labeled live physical")
  func simulatedObservationEvidenceCannotBecomeLivePhysical() throws {
    let observation = IncidentFixture.observation(id: 42, environment: .simulated)
    let mislabeledEvidence = try PlotterEvidence(
      id: PlotterEvidenceID(rawValue: uuid(43)),
      episodeID: IncidentFixture.episodeID,
      subject: .observation(observation.context.id),
      question: .drawingOutcome,
      inputEnvironment: .live,
      evidenceClass: .livePhysical,
      acceptedBy: EpisodeAuthorityID(rawValue: "evidence-owner"),
      acceptedAt: IncidentFixture.time,
      applicabilityRevision: revision("evidence-r1")
    )
    let mislabeledDecision = PlotterEvidenceDecision.accepted(mislabeledEvidence)
    let mislabeledSource = try IncidentFixture.source(
      payloads: [
        .observationRecorded(observation),
        .evidenceDecided(mislabeledDecision),
      ],
      observations: [observation],
      evidenceDecisions: [mislabeledDecision]
    )

    #expect(refusal(PlotterIncidentPackageAssembler().assemble(mislabeledSource))
      == .relationshipMismatch(.evidenceEnvironment))

    let matchingEvidence = try PlotterEvidence(
      id: PlotterEvidenceID(rawValue: uuid(44)),
      episodeID: IncidentFixture.episodeID,
      subject: .observation(observation.context.id),
      question: .drawingOutcome,
      inputEnvironment: .simulated,
      evidenceClass: .simulatedCausal,
      acceptedBy: EpisodeAuthorityID(rawValue: "evidence-owner"),
      acceptedAt: IncidentFixture.time,
      applicabilityRevision: revision("evidence-r1")
    )
    let matchingDecision = PlotterEvidenceDecision.accepted(matchingEvidence)
    let matchingSource = try IncidentFixture.source(
      payloads: [
        .observationRecorded(observation),
        .evidenceDecided(matchingDecision),
      ],
      observations: [observation],
      evidenceDecisions: [matchingDecision]
    )
    _ = try assembled(PlotterIncidentPackageAssembler().assemble(matchingSource))
  }

  @Test("measurement evidence inherits every source observation environment")
  func simulatedMeasurementEvidenceCannotBecomeLivePhysical() throws {
    let observation = IncidentFixture.observation(id: 45, environment: .simulated)
    let measurement = try IncidentFixture.inkMeasurement(
      id: 46,
      classification: .noInk,
      observation: observation
    )
    let mislabeledEvidence = try PlotterEvidence(
      id: PlotterEvidenceID(rawValue: uuid(47)),
      episodeID: IncidentFixture.episodeID,
      subject: .measurement(measurement.context.id),
      question: .drawingOutcome,
      inputEnvironment: .live,
      evidenceClass: .livePhysical,
      acceptedBy: EpisodeAuthorityID(rawValue: "evidence-owner"),
      acceptedAt: IncidentFixture.time,
      applicabilityRevision: revision("evidence-r1")
    )
    let mislabeledDecision = PlotterEvidenceDecision.accepted(mislabeledEvidence)
    let mislabeledSource = try IncidentFixture.source(
      payloads: [
        .observationRecorded(observation),
        .measurementRecorded(measurement),
        .evidenceDecided(mislabeledDecision),
      ],
      observations: [observation],
      measurements: [measurement],
      evidenceDecisions: [mislabeledDecision]
    )

    #expect(refusal(PlotterIncidentPackageAssembler().assemble(mislabeledSource))
      == .relationshipMismatch(.evidenceEnvironment))

    let matchingEvidence = try PlotterEvidence(
      id: PlotterEvidenceID(rawValue: uuid(48)),
      episodeID: IncidentFixture.episodeID,
      subject: .measurement(measurement.context.id),
      question: .drawingOutcome,
      inputEnvironment: .simulated,
      evidenceClass: .simulatedCausal,
      acceptedBy: EpisodeAuthorityID(rawValue: "evidence-owner"),
      acceptedAt: IncidentFixture.time,
      applicabilityRevision: revision("evidence-r1")
    )
    let matchingDecision = PlotterEvidenceDecision.accepted(matchingEvidence)
    let matchingSource = try IncidentFixture.source(
      payloads: [
        .observationRecorded(observation),
        .measurementRecorded(measurement),
        .evidenceDecided(matchingDecision),
      ],
      observations: [observation],
      measurements: [measurement],
      evidenceDecisions: [matchingDecision]
    )
    _ = try assembled(PlotterIncidentPackageAssembler().assemble(matchingSource))
  }

  @Test("outcomes and assessments require accepted evidence and exact outcome closure")
  func outcomeAndAssessmentRelationshipsFailClosed() throws {
    let missingEvidenceID = PlotterEvidenceID(rawValue: uuid(50))
    let outcome = PlotterEpisodeOutcome(
      id: PlotterOutcomeID(rawValue: uuid(51)),
      episodeID: IncidentFixture.episodeID,
      disposition: .ambiguous,
      acceptedEvidenceIDs: [missingEvidenceID],
      recordedAt: IncidentFixture.time,
      summary: "Evidence is not in the accepted set."
    )
    let invalidOutcome = try IncidentFixture.source(
      payloads: [.outcomeRecorded(outcome)],
      outcomes: [outcome]
    )
    #expect(refusal(PlotterIncidentPackageAssembler().assemble(invalidOutcome))
      == .relationshipMismatch(.outcomeEvidence))

    let assessment = PlotterAssessment(
      id: PlotterAssessmentID(rawValue: uuid(52)),
      episodeID: IncidentFixture.episodeID,
      outcomeID: PlotterOutcomeID(rawValue: uuid(53)),
      goalRevision: revision("goal-r1"),
      assessedAt: IncidentFixture.time,
      criteria: []
    )
    let invalidAssessment = try IncidentFixture.source(
      payloads: [.assessmentRecorded(assessment)],
      assessments: [assessment]
    )
    #expect(refusal(PlotterIncidentPackageAssembler().assemble(invalidAssessment))
      == .relationshipMismatch(.assessmentOutcome))
  }

  @Test("assessment criteria may use only evidence accepted by their referenced outcome")
  func assessmentEvidenceIsOutcomeScoped() throws {
    let observation = IncidentFixture.observation(id: 54)
    let firstEvidence = try IncidentFixture.evidence(id: 55, observation: observation)
    let secondEvidence = try IncidentFixture.evidence(id: 56, observation: observation)
    let firstDecision = PlotterEvidenceDecision.accepted(firstEvidence)
    let secondDecision = PlotterEvidenceDecision.accepted(secondEvidence)
    let outcome = PlotterEpisodeOutcome(
      id: PlotterOutcomeID(rawValue: uuid(57)),
      episodeID: IncidentFixture.episodeID,
      disposition: .completed,
      acceptedEvidenceIDs: [firstEvidence.id],
      recordedAt: IncidentFixture.time,
      summary: "Only the first evidence value belongs to this outcome."
    )
    let assessment = PlotterAssessment(
      id: PlotterAssessmentID(rawValue: uuid(58)),
      episodeID: IncidentFixture.episodeID,
      outcomeID: outcome.id,
      goalRevision: revision("goal-r1"),
      assessedAt: IncidentFixture.time,
      criteria: [PlotterCriterionAssessment(
        criterionID: EpisodeAssessmentCriterionID(rawValue: "criterion-1"),
        disposition: .satisfied,
        evidenceIDs: [secondEvidence.id],
        summary: "This evidence is episode-accepted but not outcome-accepted."
      )]
    )
    let source = try IncidentFixture.source(
      payloads: [
        .observationRecorded(observation),
        .evidenceDecided(firstDecision),
        .evidenceDecided(secondDecision),
        .outcomeRecorded(outcome),
        .assessmentRecorded(assessment),
      ],
      observations: [observation],
      evidenceDecisions: [firstDecision, secondDecision],
      outcomes: [outcome],
      assessments: [assessment]
    )

    #expect(refusal(PlotterIncidentPackageAssembler().assemble(source))
      == .relationshipMismatch(.assessmentEvidence))
  }

  @Test("every semantic artifact reference requires one exact typed availability fact")
  func artifactStatusClosureIsRequired() throws {
    let artifact = EpisodeArtifactReference(
      id: EpisodeArtifactID(rawValue: "camera-frame-artifact"),
      revision: revision("artifact-r1"),
      digest: sha256("a")
    )
    let observation = IncidentFixture.observation(id: 60, artifacts: [artifact])
    let missingStatus = try IncidentFixture.source(
      payloads: [.observationRecorded(observation)],
      observations: [observation]
    )
    #expect(refusal(PlotterIncidentPackageAssembler().assemble(missingStatus))
      == .missingArtifactStatus(artifact.id))

    let explicitMissing = try IncidentFixture.source(
      payloads: [.observationRecorded(observation)],
      observations: [observation],
      artifactStatuses: [PlotterIncidentArtifactStatus(
        reference: artifact,
        availability: .missing
      )]
    )
    let package = try integrityConfirmed(PlotterIncidentPackageAssembler().verify(
      assembled(PlotterIncidentPackageAssembler().assemble(explicitMissing))
    ))
    #expect(package.artifactStatuses.first?.availability == .missing)
  }

  @Test("frame bytes remain omitted, content-addressed, bounded, and explicitly sensitive")
  func referenceOnlyFrameBoundaryIsExplicit() throws {
    let frame = IncidentFixture.frameRecord()
    let entry = EpisodeRecordingEntry(
      sequence: 0,
      monotonicOffsetNanoseconds: 1,
      provenance: EpisodeRecordingProvenance(
        episodeID: IncidentFixture.episodeID,
        environment: .live
      ),
      record: .camera(.frameReference(frame))
    )
    let recording = IncidentFixture.recording(
      entries: [entry],
      closeOffset: 2,
      issues: [.frameBytesMissing(frame.artifact)]
    )
    let source = try IncidentFixture.source(
      recording: recording,
      sensitiveFrameIDs: [frame.descriptor.frameID]
    )
    let package = try integrityConfirmed(PlotterIncidentPackageAssembler().verify(
      assembled(PlotterIncidentPackageAssembler().assemble(source))
    ))

    #expect(package.frameReferences.count == 1)
    #expect(package.frameReferences[0].artifact == frame.artifact)
    #expect(package.frameReferences[0].retention == .sensitiveReferenceOnly)
    #expect(package.frameReferences[0].availability == [.missing])
    #expect(package.boundedness.omittedReferencedFrameCount == 1)
    #expect(package.boundedness.omittedReferencedFrameByteCount == frame.artifact.byteCount)
    #expect(package.recordingSourceFacts.contains(
      .sourceReportedIssue(.frameBytesMissing(frame.artifact))
    ))
    #expect(package.recordingSourceFacts.contains(.sourceSnapshotNotRevalidated))
  }

  @Test("runtime and UI revisions remain distinct so stale presentation is diagnostic")
  func stalePresentationRemainsExplicit() throws {
    let observation = IncidentFixture.observation(id: 70)
    let source = try IncidentFixture.source(
      payloads: [.observationRecorded(observation)],
      observations: [observation],
      projectedRuntimeRevision: .initial,
      projectedRuntimeDigest: EpisodeStateDigest(rawValue: "older-runtime-digest")
    )
    let package = try integrityConfirmed(PlotterIncidentPackageAssembler().verify(
      assembled(PlotterIncidentPackageAssembler().assemble(source))
    ))

    guard case let .userInterfaceStale(
      runtimeRevision,
      projectedRuntimeRevision,
      projectionRevision
    ) = package.runtimePresentationComparison else {
      Issue.record("Expected a typed stale user-interface diagnosis")
      return
    }
    #expect(runtimeRevision == EpisodeStateRevision(rawValue: 1))
    #expect(projectedRuntimeRevision == .initial)
    #expect(projectionRevision == PlotterProjectionRevision(rawValue: 1))
  }

  @Test("count, embedded-byte, and encoded-byte budgets refuse instead of truncating")
  func budgetsFailClosed() throws {
    let observation = IncidentFixture.observation(id: 80)
    let source = try IncidentFixture.source(
      payloads: [.observationRecorded(observation)],
      observations: [observation]
    )
    let countBudget = IncidentFixture.budget(maximumObservationCount: 0)
    #expect(refusal(PlotterIncidentPackageAssembler().assemble(
      source,
      budget: countBudget
    )) == .countLimitExceeded(section: .observations, maximum: 0, actual: 1))

    let exportBudget = IncidentFixture.budget(maximumExportByteCount: 1)
    guard let exportRefusal = refusal(
      PlotterIncidentPackageAssembler().assemble(source, budget: exportBudget)
    ), case let .countLimitExceeded(section, maximum, actual) = exportRefusal else {
      Issue.record("Expected a typed export byte limit refusal")
      return
    }
    #expect(section == .exportBytes)
    #expect(maximum == 1)
    #expect(actual > maximum)

    let invocation = ControllerInvocation(
      id: ControllerInvocationID(rawValue: uuid(81)),
      operation: .rawWrite(ControllerRawWriteParameters(bytes: Data([1, 2])))
    )
    let recordingEntry = EpisodeRecordingEntry(
      sequence: 0,
      monotonicOffsetNanoseconds: 1,
      provenance: EpisodeRecordingProvenance(
        episodeID: IncidentFixture.episodeID,
        environment: .live
      ),
      record: .controller(.invocation(invocation))
    )
    let byteBoundedSource = try IncidentFixture.source(recording: IncidentFixture.recording(
      entries: [recordingEntry],
      closeOffset: 2,
      issues: [.controllerCompletionMissing(invocation.id)]
    ))
    #expect(refusal(PlotterIncidentPackageAssembler().assemble(
      byteBoundedSource,
      budget: IncidentFixture.budget(maximumEmbeddedRecordingByteCount: 1)
    )) == .countLimitExceeded(section: .embeddedRecordingBytes, maximum: 1, actual: 2))
  }

  @Test("checked frame-byte accounting rejects integer overflow")
  func frameByteAccountingOverflowFailsClosed() throws {
    let first = IncidentFixture.frameRecord(
      id: "frame-overflow-1",
      byteCount: Int.max,
      digestCharacter: "b"
    )
    let second = IncidentFixture.frameRecord(
      id: "frame-overflow-2",
      byteCount: Int.max,
      digestCharacter: "c"
    )
    let entries = [first, second].enumerated().map { index, frame in
      EpisodeRecordingEntry(
        sequence: UInt64(index),
        monotonicOffsetNanoseconds: UInt64(index + 1),
        provenance: EpisodeRecordingProvenance(
          episodeID: IncidentFixture.episodeID,
          environment: .live
        ),
        record: .camera(.frameReference(frame))
      )
    }
    let source = try IncidentFixture.source(recording: IncidentFixture.recording(
      entries: entries,
      closeOffset: 3
    ))

    #expect(refusal(PlotterIncidentPackageAssembler().assemble(source))
      == .arithmeticOverflow(.referencedFrameBytes))
  }

  @Test("incident-level referenced-frame-byte budget is independent of store retention")
  func referencedFrameByteBudgetFailsClosed() throws {
    let frame = IncidentFixture.frameRecord(byteCount: 16)
    let entry = EpisodeRecordingEntry(
      sequence: 0,
      monotonicOffsetNanoseconds: 1,
      provenance: EpisodeRecordingProvenance(
        episodeID: IncidentFixture.episodeID,
        environment: .live
      ),
      record: .camera(.frameReference(frame))
    )
    let source = try IncidentFixture.source(recording: IncidentFixture.recording(
      entries: [entry],
      closeOffset: 2
    ))

    let exactBudget = IncidentFixture.budget(maximumReferencedFrameByteCount: 16)
    let package = try integrityConfirmed(PlotterIncidentPackageAssembler().verify(
      assembled(PlotterIncidentPackageAssembler().assemble(source, budget: exactBudget))
    ))
    #expect(package.boundedness.budget.maximumReferencedFrameByteCount == 16)
    #expect(package.boundedness.omittedReferencedFrameByteCount == 16)

    #expect(refusal(PlotterIncidentPackageAssembler().assemble(
      source,
      budget: IncidentFixture.budget(maximumReferencedFrameByteCount: 15)
    )) == .countLimitExceeded(section: .referencedFrameBytes, maximum: 15, actual: 16))
  }

  @Test("possible and unclear ink require one exact unresolved possible-ink link")
  func possibleInkClosureIsExact() throws {
    for (offset, classification) in [
      PlotterInkClassification.possibleInk,
      .unclear,
    ].enumerated() {
      let observation = IncidentFixture.observation(id: UInt8(93 + offset * 2))
      let measurement = try IncidentFixture.inkMeasurement(
        id: UInt8(94 + offset * 2),
        classification: classification,
        observation: observation
      )
      let ambiguity = PlotterIncidentUnresolvedAmbiguity(
        id: uuid(UInt8(200 + offset)),
        episodeID: IncidentFixture.episodeID,
        kind: .possibleInk,
        subject: .inkMeasurement(measurement.context.id),
        owner: EpisodeAuthorityID(rawValue: "operator-review"),
        observedAt: IncidentFixture.time,
        summary: "Ink remains unresolved and cannot trigger redraw."
      )
      let source = try IncidentFixture.source(
        payloads: [
          .observationRecorded(observation),
          .measurementRecorded(measurement),
        ],
        observations: [observation],
        measurements: [measurement],
        unresolvedAmbiguities: [ambiguity]
      )
      let package = try integrityConfirmed(PlotterIncidentPackageAssembler().verify(
        assembled(PlotterIncidentPackageAssembler().assemble(source))
      ))
      #expect(package.hasUnresolvedAmbiguity)
      #expect(package.unresolvedAmbiguities == [ambiguity])
    }
  }

  @Test("missing, duplicate, foreign, and spurious possible-ink links fail closed")
  func invalidPossibleInkClosureFailsClosed() throws {
    let observation = IncidentFixture.observation(id: 97)
    let measurement = try IncidentFixture.inkMeasurement(
      id: 98,
      classification: .possibleInk,
      observation: observation
    )
    let basePayloads: [PlotterEpisodeEventPayload] = [
      .observationRecorded(observation),
      .measurementRecorded(measurement),
    ]
    let missing = try IncidentFixture.source(
      payloads: basePayloads,
      observations: [observation],
      measurements: [measurement]
    )
    #expect(refusal(PlotterIncidentPackageAssembler().assemble(missing))
      == .relationshipMismatch(.possibleInkAmbiguity))

    let first = IncidentFixture.possibleInkAmbiguity(
      id: 201,
      measurementID: measurement.context.id
    )
    let second = IncidentFixture.possibleInkAmbiguity(
      id: 202,
      measurementID: measurement.context.id
    )
    let duplicate = try IncidentFixture.source(
      payloads: basePayloads,
      observations: [observation],
      measurements: [measurement],
      unresolvedAmbiguities: [first, second]
    )
    #expect(refusal(PlotterIncidentPackageAssembler().assemble(duplicate))
      == .relationshipMismatch(.possibleInkAmbiguity))

    let foreign = try IncidentFixture.source(
      payloads: basePayloads,
      observations: [observation],
      measurements: [measurement],
      unresolvedAmbiguities: [IncidentFixture.possibleInkAmbiguity(
        id: 203,
        measurementID: PlotterMeasurementID(rawValue: uuid(99))
      )]
    )
    #expect(refusal(PlotterIncidentPackageAssembler().assemble(foreign))
      == .relationshipMismatch(.possibleInkAmbiguity))

    let spurious = try IncidentFixture.source(
      unresolvedAmbiguities: [IncidentFixture.possibleInkAmbiguity(
        id: 204,
        measurementID: PlotterMeasurementID(rawValue: uuid(99))
      )]
    )
    #expect(refusal(PlotterIncidentPackageAssembler().assemble(spurious))
      == .relationshipMismatch(.possibleInkAmbiguity))
  }

  @Test("unresolved ambiguity is preserved and never promoted to completeness")
  func unresolvedAmbiguityRemainsDiagnostic() throws {
    let ambiguity = PlotterIncidentUnresolvedAmbiguity(
      id: uuid(90),
      episodeID: IncidentFixture.episodeID,
      kind: .possibleInk,
      subject: .inkMeasurement(PlotterMeasurementID(rawValue: uuid(91))),
      owner: EpisodeAuthorityID(rawValue: "operator-review"),
      observedAt: IncidentFixture.time,
      summary: "Possible ink still requires attended operator review."
    )
    let source = try IncidentFixture.source(unresolvedAmbiguities: [ambiguity])
    #expect(refusal(PlotterIncidentPackageAssembler().assemble(source))
      == .relationshipMismatch(.possibleInkAmbiguity))

    let diagnosticAmbiguity = PlotterIncidentUnresolvedAmbiguity(
      id: uuid(92),
      episodeID: IncidentFixture.episodeID,
      kind: .workflow,
      subject: .episode,
      owner: EpisodeAuthorityID(rawValue: "workflow-owner"),
      observedAt: IncidentFixture.time,
      summary: "Workflow state remains unresolved."
    )
    let validSource = try IncidentFixture.source(
      unresolvedAmbiguities: [diagnosticAmbiguity]
    )
    let package = try integrityConfirmed(PlotterIncidentPackageAssembler().verify(
      assembled(PlotterIncidentPackageAssembler().assemble(validSource))
    ))

    #expect(package.hasUnresolvedAmbiguity)
    #expect(package.unresolvedAmbiguities == [diagnosticAmbiguity])
  }

  @Test("source and package topology contain no storage, UI, device, replay, or effect owner")
  func forbiddenAuthorityBoundary() throws {
    let root = repositoryRoot()
    let sourceURL = root.appendingPathComponent(
      "Sources/PlotterEpisodeRuntime/PlotterIncidentPackage.swift"
    )
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    let forbidden = [
      "import SwiftUI",
      "import AppKit",
      "import AVFoundation",
      "FileManager",
      "@unchecked Sendable",
      "withCheckedContinuation",
      "withUnsafeContinuation",
      "Task {",
      " actor ",
      " Any",
      "Mirror(",
      "EffectPermit",
      "resume(",
      "retry(",
      "redraw(",
      "hasClosedVerifiedCompleteRecording",
      "recordingVerified",
      "case verified",
      "EpisodeStore(",
      "EpisodeRecordingStore(",
      "PlotterEpisodeReplayService(",
      "PlotterOperationRegistry(",
      "MachineController(",
      "CameraCapture(",
    ]
    for token in forbidden {
      #expect(!source.contains(token), "Forbidden incident authority token: \(token)")
    }

    let manifest = try String(
      contentsOf: root.appendingPathComponent("Package.swift"),
      encoding: .utf8
    )
    #expect(!manifest.contains(".library(name: \"PlotterEpisodeRuntime\""))
    let appDirectory = root.appendingPathComponent("Sources/PlotterApp", isDirectory: true)
    let appSource = try FileManager.default.contentsOfDirectory(
      at: appDirectory,
      includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "swift" }
      .map { try String(contentsOf: $0, encoding: .utf8) }
      .joined(separator: "\n")
    #expect(!appSource.contains("PlotterIncidentPackage"))
  }
}

private enum IncidentFixture {
  static let episodeID = EpisodeID(rawValue: uuid(1))
  static let manifestID = EpisodeManifestID(rawValue: uuid(2))
  static let definitionID = EpisodeDefinitionID(rawValue: uuid(3))
  static let recordingID = EpisodeRecordingID(rawValue: uuid(4))
  static let time = Date(timeIntervalSinceReferenceDate: 10_000)

  static func source(
    payloads: [PlotterEpisodeEventPayload] = [],
    observations: [PlotterObservation] = [],
    measurements: [PlotterMeasurement] = [],
    evidenceDecisions: [PlotterEvidenceDecision] = [],
    outcomes: [PlotterEpisodeOutcome] = [],
    assessments: [PlotterAssessment] = [],
    recording: EpisodeRecordingSnapshot? = nil,
    artifactStatuses: [PlotterIncidentArtifactStatus] = [],
    sensitiveFrameIDs: [CameraFrameIdentity] = [],
    unresolvedAmbiguities: [PlotterIncidentUnresolvedAmbiguity] = [],
    projectedRuntimeRevision: EpisodeStateRevision? = nil,
    projectedRuntimeDigest: EpisodeStateDigest? = nil
  ) throws -> PlotterIncidentPackageSource {
    let manifest = PlotterEpisodeManifest(
      id: manifestID,
      episodeID: episodeID,
      definitionID: definitionID,
      definitionRevision: revision("definition-r1"),
      domainRevision: revision("domain-r1"),
      evaluatorRevision: revision("evaluator-r1"),
      reducerRevision: revision("reducer-r1"),
      schemaRevisions: EpisodeSchemaRevisions(
        state: revision("state-r1"),
        event: revision("event-r1"),
        journal: revision("journal-r1")
      ),
      buildRevision: revision("build-r1"),
      deterministicSeed: 42,
      domainManifest: PlotterEpisodeDomainManifest(
        paperRevision: revision("paper-r1"),
        environmentRevision: revision("environment-r1")
      )
    )
    let finalRevision = EpisodeStateRevision(rawValue: UInt64(payloads.count))
    let provisional = PlotterEpisodeState(
      episodeID: episodeID,
      revision: finalRevision,
      canonicalDigest: EpisodeStateDigest(rawValue: "pending"),
      observationIDs: observations.map(\.context.id),
      measurementIDs: measurements.map(\.context.id),
      acceptedEvidenceIDs: evidenceDecisions.compactMap {
        if case let .accepted(evidence) = $0 { return evidence.id }
        return nil
      },
      outcome: outcomes.last,
      assessment: assessments.last,
      lastCommittedAt: payloads.isEmpty ? nil : time.addingTimeInterval(Double(payloads.count))
    )
    let digest = try PlotterEpisodeCanonicalDigestV1.digest(provisional)
    let runtimeState = PlotterEpisodeState(
      episodeID: episodeID,
      revision: provisional.revision,
      canonicalDigest: digest,
      phase: provisional.phase,
      permittedIntentFamilies: provisional.permittedIntentFamilies,
      currentPlanRevisionID: provisional.currentPlanRevisionID,
      activeDrawingModelRevisionID: provisional.activeDrawingModelRevisionID,
      selectedPoint: provisional.selectedPoint,
      activeRequestID: provisional.activeRequestID,
      activeIntent: provisional.activeIntent,
      pendingEffectID: provisional.pendingEffectID,
      activeEffectProgress: provisional.activeEffectProgress,
      lastTerminalEffect: provisional.lastTerminalEffect,
      observationIDs: provisional.observationIDs,
      measurementIDs: provisional.measurementIDs,
      acceptedEvidenceIDs: provisional.acceptedEvidenceIDs,
      outcome: provisional.outcome,
      assessment: provisional.assessment,
      lastRefusal: provisional.lastRefusal,
      lastCommittedAt: provisional.lastCommittedAt
    )
    var events: [PlotterEpisodeEvent] = []
    for (index, payload) in payloads.enumerated() {
      let sequence = UInt64(index)
      let postRevision = EpisodeStateRevision(rawValue: sequence + 1)
      events.append(PlotterEpisodeEvent(
        id: EpisodeEventID(rawValue: uuid(UInt8(100 + index))),
        episodeID: episodeID,
        sequence: EpisodeEventSequence(rawValue: sequence),
        recordedAt: time.addingTimeInterval(Double(index + 1)),
        actor: EpisodeEventActor(
          id: EpisodeActorID(rawValue: "fixture-runtime"),
          origin: .runtime
        ),
        correlationID: EpisodeCorrelationID(rawValue: uuid(UInt8(150 + index))),
        preStateRevision: EpisodeStateRevision(rawValue: sequence),
        postStateRevision: postRevision,
        payload: payload,
        artifactReferences: eventArtifactReferences(payload),
        postStateDigest: postRevision == finalRevision
          ? digest : EpisodeStateDigest(rawValue: "intermediate-\(index)")
      ))
    }
    let journal = try EpisodeJournal<PlotterEpisodeEventPayload>(
      manifestID: manifestID,
      episodeID: episodeID,
      events: events
    )
    let projection = PlotterEpisodeProjection(
      episodeID: episodeID,
      runtimeStateRevision: projectedRuntimeRevision ?? runtimeState.revision,
      runtimeStateDigest: projectedRuntimeDigest ?? runtimeState.canonicalDigest,
      runtimeLastCommittedAt: runtimeState.lastCommittedAt,
      projectionRevision: PlotterProjectionRevision(rawValue: 1),
      projectedAt: time.addingTimeInterval(100),
      phase: runtimeState.phase,
      selectedPoint: runtimeState.selectedPoint,
      activeEffectProgress: runtimeState.activeEffectProgress,
      lastTerminalEffect: runtimeState.lastTerminalEffect,
      currentReason: nil,
      authoritativeOwner: nil,
      remedy: nil,
      availabilities: []
    )
    return PlotterIncidentPackageSource(
      manifest: manifest,
      journal: journal,
      recording: recording ?? self.recording(),
      observations: observations,
      measurements: measurements,
      evidenceDecisions: evidenceDecisions,
      outcomes: outcomes,
      assessments: assessments,
      runtimeState: runtimeState,
      userInterfaceProjection: projection,
      currentOwners: owners(),
      artifactStatuses: artifactStatuses,
      sensitiveFrameIDs: sensitiveFrameIDs,
      unresolvedAmbiguities: unresolvedAmbiguities
    )
  }

  static func copy(
    _ source: PlotterIncidentPackageSource,
    journal: EpisodeJournal<PlotterEpisodeEventPayload>? = nil
  ) -> PlotterIncidentPackageSource {
    PlotterIncidentPackageSource(
      manifest: source.manifest,
      journal: journal ?? source.journal,
      recording: source.recording,
      observations: source.observations,
      measurements: source.measurements,
      evidenceDecisions: source.evidenceDecisions,
      outcomes: source.outcomes,
      assessments: source.assessments,
      runtimeState: source.runtimeState,
      userInterfaceProjection: source.userInterfaceProjection,
      currentOwners: source.currentOwners,
      artifactStatuses: source.artifactStatuses,
      sensitiveFrameIDs: source.sensitiveFrameIDs,
      unresolvedAmbiguities: source.unresolvedAmbiguities
    )
  }

  static func owners() -> [PlotterIncidentCurrentOwner] {
    PlotterIncidentOwnerDomain.allCases.map { domain in
      PlotterIncidentCurrentOwner(
        domain: domain,
        authorityID: EpisodeAuthorityID(rawValue: "owner-\(domain.rawValue)"),
        revision: revision("owner-r1"),
        observedAt: time
      )
    }
  }

  static func recording(
    entries: [EpisodeRecordingEntry] = [],
    closeOffset: UInt64 = 0,
    issues: [EpisodeRecordingCompletenessIssue] = []
  ) -> EpisodeRecordingSnapshot {
    EpisodeRecordingSnapshot(
      formatVersion: 1,
      recordingID: recordingID,
      schemaRevision: EpisodeRecordingSchemaRevision(rawValue: "recording-r1"),
      frameRetentionPolicy: EpisodeFrameRetentionPolicy(
        maximumUniqueFrameCount: 32,
        maximumTotalUniqueFrameBytes: 1_024 * 1_024
      ),
      entries: entries,
      close: EpisodeRecordingClose(monotonicOffsetNanoseconds: closeOffset),
      durability: .verified,
      completenessIssues: issues
    )
  }

  static func observation(
    id: UInt8,
    environment: PlotterEnvironment = .live,
    artifacts: [EpisodeArtifactReference] = []
  ) -> PlotterObservation {
    .controller(PlotterControllerObservation(
      context: PlotterObservationContext(
        id: PlotterObservationID(rawValue: uuid(id)),
        observedAt: time,
        environment: environment,
        source: .controller,
        sourceRevision: revision("controller-r1"),
        artifactReferences: artifacts
      ),
      status: .idle,
      machinePosition: nil,
      motionEnabled: false
    ))
  }

  static func evidence(
    id: UInt8,
    observation: PlotterObservation
  ) throws -> PlotterEvidence {
    try PlotterEvidence(
      id: PlotterEvidenceID(rawValue: uuid(id)),
      episodeID: episodeID,
      subject: .observation(observation.context.id),
      question: .drawingOutcome,
      inputEnvironment: observation.context.environment,
      evidenceClass: .livePhysical,
      acceptedBy: EpisodeAuthorityID(rawValue: "evidence-owner"),
      acceptedAt: time,
      applicabilityRevision: revision("evidence-r1")
    )
  }

  static func inkMeasurement(
    id: UInt8,
    classification: PlotterInkClassification,
    observation: PlotterObservation
  ) throws -> PlotterMeasurement {
    let context = try PlotterMeasurementContext(
      id: PlotterMeasurementID(rawValue: uuid(id)),
      computedAt: time,
      sourceObservationIDs: [observation.context.id],
      algorithmRevision: revision("ink-r1")
    )
    return .ink(try PlotterInkMeasurement(
      context: context,
      classification: classification,
      confidence: 0.5
    ))
  }

  static func possibleInkAmbiguity(
    id: UInt8,
    measurementID: PlotterMeasurementID
  ) -> PlotterIncidentUnresolvedAmbiguity {
    PlotterIncidentUnresolvedAmbiguity(
      id: uuid(id),
      episodeID: episodeID,
      kind: .possibleInk,
      subject: .inkMeasurement(measurementID),
      owner: EpisodeAuthorityID(rawValue: "operator-review"),
      observedAt: time,
      summary: "Possible ink requires operator review."
    )
  }

  static func frameRecord(
    id: String = "frame-1",
    byteCount: Int = 16,
    digestCharacter: Character = "b"
  ) -> CameraFrameRecord {
    CameraFrameRecord(
      descriptor: CameraFrameDescriptor(
        stream: CameraStreamIdentity(
          source: CameraSourceIdentity(rawValue: "camera-1"),
          configuration: CameraConfigurationIdentity(rawValue: uuid(91))
        ),
        frameID: CameraFrameIdentity(rawValue: id),
        sequence: 1,
        captureNanoseconds: 1_000,
        width: 2,
        height: 2,
        rowBytes: 8,
        pixelFormat: .bgra8
      ),
      artifact: ContentAddressedFrameReference(
        contentSHA256: sha256(digestCharacter),
        byteCount: byteCount,
        relativePath: "frames/\(id)-\(sha256(digestCharacter)).frame"
      )
    )
  }

  static func budget(
    maximumObservationCount: Int? = nil,
    maximumEmbeddedRecordingByteCount: Int? = nil,
    maximumReferencedFrameByteCount: Int? = nil,
    maximumExportByteCount: Int? = nil
  ) -> PlotterIncidentPackageBudget {
    let standard = PlotterIncidentPackageBudget.standard
    return PlotterIncidentPackageBudget(
      maximumJournalEventCount: standard.maximumJournalEventCount,
      maximumRecordingEntryCount: standard.maximumRecordingEntryCount,
      maximumFrameReferenceCount: standard.maximumFrameReferenceCount,
      maximumObservationCount: maximumObservationCount ?? standard.maximumObservationCount,
      maximumMeasurementCount: standard.maximumMeasurementCount,
      maximumEvidenceDecisionCount: standard.maximumEvidenceDecisionCount,
      maximumOutcomeCount: standard.maximumOutcomeCount,
      maximumAssessmentCount: standard.maximumAssessmentCount,
      maximumArtifactStatusCount: standard.maximumArtifactStatusCount,
      maximumOwnerCount: standard.maximumOwnerCount,
      maximumAmbiguityCount: standard.maximumAmbiguityCount,
      maximumTotalItemCount: standard.maximumTotalItemCount,
      maximumEmbeddedRecordingByteCount: maximumEmbeddedRecordingByteCount
        ?? standard.maximumEmbeddedRecordingByteCount,
      maximumReferencedFrameByteCount: maximumReferencedFrameByteCount
        ?? standard.maximumReferencedFrameByteCount,
      maximumExportByteCount: maximumExportByteCount ?? standard.maximumExportByteCount
    )
  }

  private static func eventArtifactReferences(
    _ payload: PlotterEpisodeEventPayload
  ) -> [EpisodeArtifactReference] {
    switch payload {
    case let .observationRecorded(observation):
      return observation.context.artifactReferences
    case let .evidenceDecided(.accepted(evidence)):
      return evidence.artifactReferences
    default:
      return []
    }
  }
}

private enum IncidentTestFailure: Error {
  case expectedAssembly
  case expectedVerification
  case expectedRefusal
}

private func assembled(
  _ outcome: PlotterIncidentPackageAssemblyOutcome
) throws -> PlotterIncidentPackageExport {
  guard case let .assembled(export) = outcome else { throw IncidentTestFailure.expectedAssembly }
  return export
}

private func integrityConfirmed(
  _ outcome: PlotterIncidentPackageVerificationOutcome
) throws -> PlotterIncidentPackage {
  guard case let .envelopeIntegrityConfirmed(package) = outcome else {
    throw IncidentTestFailure.expectedVerification
  }
  return package
}

private func refusal(
  _ outcome: PlotterIncidentPackageAssemblyOutcome
) -> PlotterIncidentPackageRefusal? {
  guard case let .refused(refusal) = outcome else { return nil }
  return refusal
}

private func refusal(
  _ outcome: PlotterIncidentPackageVerificationOutcome
) -> PlotterIncidentPackageRefusal? {
  guard case let .refused(refusal) = outcome else { return nil }
  return refusal
}

private func revision(_ value: String) -> EpisodeRevisionIdentifier {
  EpisodeRevisionIdentifier(rawValue: value)
}

private func sha256(_ character: Character) -> String {
  String(repeating: String(character), count: 64)
}

private func uuid(_ value: UInt8) -> UUID {
  UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
}

private func repositoryRoot() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}
