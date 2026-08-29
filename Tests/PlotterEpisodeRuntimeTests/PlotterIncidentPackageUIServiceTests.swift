import EpisodeCore
import Foundation
import PlotterEpisodeModel
@testable import PlotterEpisodeRuntime
import PlotterRuntime
import Testing

@Suite("Plotter incident package UI service")
struct PlotterIncidentPackageUIServiceTests {
  @Test("App observes unavailable lifecycle without manufacturing source identity")
  func unavailableSourceRefusesTruthfully() async {
    let request = PlotterIncidentPackageUINoSourceRequest(
      id: PlotterIncidentPackageUIRequestID(rawValue: testUUID(10))
    )
    let provider = RecordingUnavailableIncidentUISourceProvider()
    let service = PlotterIncidentPackageUIService(sourceProvider: provider)
    let admission = await service.startUnavailable(request)
    guard case .accepted(let stream) = admission else {
      Issue.record("expected unavailable source request to be admitted")
      return
    }
    let updates = await collect(stream)
    let loadCallCount = await provider.loadCallCount()

    #expect(updates == [
      .checkingAvailability(requestID: request.id),
      .terminal(PlotterIncidentPackageUINoSourceRefusal(
        requestID: request.id,
        reason: .noCompleteSourceProvider,
        remedy: .provideCompleteSource
      )),
    ])
    #expect(loadCallCount == 0)
    #expect(
      updates.count <= PlotterIncidentPackageUIService.maximumBufferedNoSourceUpdateCount
    )
  }

  @Test("held exact source retains terminal identity without a waiting consumer")
  func heldSourceProgressAndMetadata() async throws {
    let source = try IncidentUIFixture.source()
    let provider = HeldIncidentUISourceProvider()
    let service = PlotterIncidentPackageUIService(sourceProvider: provider)
    let request = PlotterIncidentPackageUIRequest(
      id: PlotterIncidentPackageUIRequestID(rawValue: testUUID(11)),
      sourceIdentity: PlotterIncidentPackageUISourceIdentity(source: source)
    )
    let admission = await service.start(request)
    guard case .accepted(let stream) = admission else {
      Issue.record("expected exact source request to be admitted")
      return
    }

    await provider.waitUntilLoadIsHeld()
    let competingRequest = PlotterIncidentPackageUIRequest(
      id: PlotterIncidentPackageUIRequestID(rawValue: testUUID(12)),
      sourceIdentity: request.sourceIdentity
    )
    let competingAdmission = await service.start(competingRequest)
    let expectedCompetingRefusal = PlotterIncidentPackageUIRefusal(
      requestID: competingRequest.id,
      sourceIdentity: competingRequest.sourceIdentity,
      reason: .requestInProgress(activeRequestID: request.id),
      remedy: .waitForActiveRequest(request.id)
    )
    guard case .refused(let competingRefusal) = competingAdmission else {
      Issue.record("expected concurrent request to be refused")
      return
    }
    #expect(competingRefusal == expectedCompetingRefusal)

    await provider.release(.available(PlotterIncidentPackageUIExactSource(source: source)))
    // Deliberately begin consuming only after release. The request-owned buffer
    // must retain the exact terminal identity without polling or sleeps.
    let updates = await collect(stream)
    guard let terminalResult = terminalResults(updates).first,
      case let .completed(metadata) = terminalResult
    else {
      Issue.record("expected completed incident package terminal result")
      return
    }
    #expect(metadata.requestID == request.id)
    #expect(metadata.sourceIdentity == request.sourceIdentity)
    #expect(metadata.formatVersion == 1)
    #expect(metadata.encoding == .canonicalJSONV1)
    #expect(metadata.exactByteCount > 0)
    #expect(metadata.payloadSHA256.count == 64)
    #expect(metadata.integrityScope == .canonicalEnvelopeOnly)
    #expect(!metadata.physicalEvidenceClaimed)

    let progress = progressValues(updates)
    #expect(progress.map(\.requestID) == [request.id, request.id, request.id])
    #expect(progress.map(\.sourceIdentity) == [
      request.sourceIdentity,
      request.sourceIdentity,
      request.sourceIdentity,
    ])
    #expect(progress.map(\.phase) == [
      .loadingExactSource,
      .assemblingCanonicalEnvelope,
      .terminal,
    ])
    #expect(progress.map(\.completedUnitCount) == [0, 1, 2])
    #expect(progress.allSatisfy {
      $0.totalUnitCount == PlotterIncidentPackageUIProgress.totalUnitCount
    })
    #expect(terminalResults(updates).count == 1)
    #expect(updates.count == PlotterIncidentPackageUIService.maximumBufferedUpdateCount)
  }
}

private actor HeldIncidentUISourceProvider: PlotterIncidentPackageUISourceProvider {
  private var loadContinuation:
    CheckedContinuation<PlotterIncidentPackageUISourceLoadOutcome, Never>?
  private var heldWaiters: [CheckedContinuation<Void, Never>] = []
  private var isHeld = false

  func loadExactSource(
    for _: PlotterIncidentPackageUIRequest
  ) async -> PlotterIncidentPackageUISourceLoadOutcome {
    isHeld = true
    let waiters = heldWaiters
    heldWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }
    return await withCheckedContinuation { continuation in
      loadContinuation = continuation
    }
  }

  func waitUntilLoadIsHeld() async {
    guard !isHeld else { return }
    await withCheckedContinuation { continuation in
      heldWaiters.append(continuation)
    }
  }

  func release(_ outcome: PlotterIncidentPackageUISourceLoadOutcome) {
    let continuation = loadContinuation
    loadContinuation = nil
    continuation?.resume(returning: outcome)
  }
}

private actor RecordingUnavailableIncidentUISourceProvider:
  PlotterIncidentPackageUISourceProvider
{
  private var sourceLoadCallCount = 0

  func loadExactSource(
    for _: PlotterIncidentPackageUIRequest
  ) async -> PlotterIncidentPackageUISourceLoadOutcome {
    sourceLoadCallCount += 1
    return .unavailable(.noCompleteSourceProvider)
  }

  func loadCallCount() -> Int { sourceLoadCallCount }
}

private func collect(
  _ stream: AsyncStream<PlotterIncidentPackageUINoSourceRequestUpdate>
) async -> [PlotterIncidentPackageUINoSourceRequestUpdate] {
  var values: [PlotterIncidentPackageUINoSourceRequestUpdate] = []
  for await value in stream {
    values.append(value)
  }
  return values
}

private func collect(
  _ stream: AsyncStream<PlotterIncidentPackageUIRequestUpdate>
) async -> [PlotterIncidentPackageUIRequestUpdate] {
  var values: [PlotterIncidentPackageUIRequestUpdate] = []
  for await value in stream {
    values.append(value)
  }
  return values
}

private func progressValues(
  _ updates: [PlotterIncidentPackageUIRequestUpdate]
) -> [PlotterIncidentPackageUIProgress] {
  updates.map { update in
    switch update {
    case .progress(let progress), .terminal(let progress, _): progress
    }
  }
}

private func terminalResults(
  _ updates: [PlotterIncidentPackageUIRequestUpdate]
) -> [PlotterIncidentPackageUIResult] {
  updates.compactMap { update in
    guard case .terminal(_, let result) = update else { return nil }
    return result
  }
}

private enum IncidentUIFixture {
  static let episodeID = EpisodeID(rawValue: testUUID(1))
  static let manifestID = EpisodeManifestID(rawValue: testUUID(2))
  static let definitionID = EpisodeDefinitionID(rawValue: testUUID(3))
  static let recordingID = EpisodeRecordingID(rawValue: testUUID(4))
  static let time = Date(timeIntervalSinceReferenceDate: 10_000)

  static func source() throws -> PlotterIncidentPackageSource {
    let manifest = PlotterEpisodeManifest(
      id: manifestID,
      episodeID: episodeID,
      definitionID: definitionID,
      definitionRevision: testRevision("definition-r1"),
      domainRevision: testRevision("domain-r1"),
      evaluatorRevision: testRevision("evaluator-r1"),
      reducerRevision: testRevision("reducer-r1"),
      schemaRevisions: EpisodeSchemaRevisions(
        state: testRevision("state-r1"),
        event: testRevision("event-r1"),
        journal: testRevision("journal-r1")
      ),
      buildRevision: testRevision("build-r1"),
      deterministicSeed: 42,
      domainManifest: PlotterEpisodeDomainManifest(
        paperRevision: testRevision("paper-r1"),
        environmentRevision: testRevision("environment-r1")
      )
    )
    let provisionalState = PlotterEpisodeState(
      episodeID: episodeID,
      canonicalDigest: EpisodeStateDigest(rawValue: "pending")
    )
    let runtimeState = PlotterEpisodeState(
      episodeID: episodeID,
      canonicalDigest: try PlotterEpisodeCanonicalDigestV1.digest(provisionalState)
    )
    let journal = try EpisodeJournal<PlotterEpisodeEventPayload>(
      manifestID: manifestID,
      episodeID: episodeID
    )
    let projection = PlotterEpisodeProjection(
      episodeID: episodeID,
      runtimeStateRevision: runtimeState.revision,
      runtimeStateDigest: runtimeState.canonicalDigest,
      runtimeLastCommittedAt: runtimeState.lastCommittedAt,
      projectionRevision: PlotterProjectionRevision(rawValue: 1),
      projectedAt: time,
      phase: runtimeState.phase,
      selectedPoint: runtimeState.selectedPoint,
      activeEffectProgress: runtimeState.activeEffectProgress,
      lastTerminalEffect: runtimeState.lastTerminalEffect,
      currentReason: nil,
      authoritativeOwner: nil,
      remedy: nil,
      availabilities: []
    )
    let recording = EpisodeRecordingSnapshot(
      formatVersion: 1,
      recordingID: recordingID,
      schemaRevision: EpisodeRecordingSchemaRevision(rawValue: "recording-r1"),
      frameRetentionPolicy: EpisodeFrameRetentionPolicy(
        maximumUniqueFrameCount: 32,
        maximumTotalUniqueFrameBytes: 1_024 * 1_024
      ),
      entries: [],
      close: EpisodeRecordingClose(monotonicOffsetNanoseconds: 0),
      durability: .verified,
      completenessIssues: []
    )
    let owners = PlotterIncidentOwnerDomain.allCases.map { domain in
      PlotterIncidentCurrentOwner(
        domain: domain,
        authorityID: EpisodeAuthorityID(rawValue: "owner-\(domain.rawValue)"),
        revision: testRevision("owner-r1"),
        observedAt: time
      )
    }
    return PlotterIncidentPackageSource(
      manifest: manifest,
      journal: journal,
      recording: recording,
      observations: [],
      measurements: [],
      evidenceDecisions: [],
      outcomes: [],
      assessments: [],
      runtimeState: runtimeState,
      userInterfaceProjection: projection,
      currentOwners: owners,
      artifactStatuses: [],
      sensitiveFrameIDs: [],
      unresolvedAmbiguities: []
    )
  }
}

private func testRevision(_ value: String) -> EpisodeRevisionIdentifier {
  EpisodeRevisionIdentifier(rawValue: value)
}

private func testUUID(_ value: UInt8) -> UUID {
  UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
}
