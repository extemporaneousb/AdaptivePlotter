import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterRuntime
import Testing

@Suite("Artifact/reset episode runtime")
struct PlotterArtifactResetEpisodeTests {
  @Test("Saved Learning decisions are explicit and preserve state until selected")
  func explicitSavedLearningDecisions() async throws {
    let checkpoint = try makeCheckpoint()
    let port = ArtifactResetPortFixture(responses: [
      .completed(.savedLearningCompared(checkpoint, opticalComparison: "advisory")),
      .completed(.savedLearningRetained(checkpoint)),
    ])
    let runtime = await PlotterArtifactResetRuntime(effectPort: port, persistencePort: port)

    #expect(await runtime.submit(
      .compareSavedLearning(checkpoint, comparisonIdentity: "frame-1"),
      facts: .init(environment: .live)
    ))
    #expect((await runtime.snapshot()).savedLearning.candidate?.opticalComparison == "advisory")
    #expect(await runtime.submit(.retainSavedLearning, facts: .init(environment: .live)))
    #expect((await runtime.snapshot()).savedLearning == .retainedForLater(checkpoint))
    #expect(await port.calls.map(kind) == [.compare, .retain])
  }

  @Test("one task owns admission and shutdown cancels later starts")
  func oneTaskAndShutdownAdmission() async throws {
    let checkpoint = try makeCheckpoint()
    let port = ArtifactResetPortFixture(
      responses: [.completed(.savedLearningCompared(checkpoint, opticalComparison: "advisory"))],
      suspendsFirstRequest: true
    )
    let runtime = await PlotterArtifactResetRuntime(effectPort: port, persistencePort: port)

    let first = Task {
      await runtime.submit(
        .compareSavedLearning(checkpoint, comparisonIdentity: "frame-1"),
        facts: .init(environment: .live)
      )
    }
    await port.waitForCallCount(1)
    #expect(!(await runtime.submit(
      .compareSavedLearning(checkpoint, comparisonIdentity: "frame-2"),
      facts: .init(environment: .live)
    )))
    await runtime.shutdown()
    await port.releaseSuspendedRequest()
    #expect(!(await first.value))
    #expect(!(await runtime.submit(
      .compareSavedLearning(checkpoint, comparisonIdentity: "frame-3"),
      facts: .init(environment: .live)
    )))
    #expect((await runtime.snapshot()).admissionClosed)
  }

  @Test("reset orders durable work before in-memory projection")
  func resetDurableBeforeProjection() async {
    let plan = makePlan()
    let port = ArtifactResetPortFixture(responses: [
      .completed(.resetSettled(plan)),
      .completed(.inMemoryResetApplied(plan)),
    ], persistenceResponses: [
      .completed(.resetPersisted(plan, savedLearning: .absent))
    ])
    let runtime = await PlotterArtifactResetRuntime(effectPort: port, persistencePort: port)

    #expect(await runtime.submit(.reset(plan), facts: .init(environment: .live)))
    #expect(await port.calls.map(kind) == [.settle, .applyMemory])
    #expect(await port.persistenceCalls.count == 1)
    #expect((await runtime.snapshot()).lastResetPlan == plan)
  }

  @Test("persistence failure leaves prior authority")
  func persistenceFailureLeavesPriorAuthority() async throws {
    let checkpoint = try makeCheckpoint()
    let plan = makePlan()
    let port = ArtifactResetPortFixture(
      responses: [.completed(.resetSettled(plan))],
      persistenceResponses: [.failed("durable clear failed")]
    )
    let runtime = await PlotterArtifactResetRuntime(effectPort: port, persistencePort: port)
    await runtime.installSavedLearningFact(.applied(checkpoint, opticalComparison: "prior"))

    #expect(!(await runtime.submit(.reset(plan), facts: .init(environment: .live))))
    #expect((await runtime.snapshot()).savedLearning == .applied(checkpoint, opticalComparison: "prior"))
    #expect(await port.calls.map(kind) == [.settle])
    #expect(await port.persistenceCalls.count == 1)
  }

  @Test("paper replacement orders persistence before projection")
  func paperReplacementDurableBeforeProjection() async {
    let plan = makePlan()
    let port = ArtifactResetPortFixture(
      responses: [
        .completed(.paperReplacementSettled(plan)),
        .completed(.inMemoryPaperReplacementApplied(plan)),
      ],
      persistenceResponses: [.completed(.paperReplacementPersisted(plan))]
    )
    let runtime = await PlotterArtifactResetRuntime(effectPort: port, persistencePort: port)

    #expect(await runtime.submit(.paperReplaced(plan), facts: .init(environment: .live)))
    #expect(await port.calls.map(kind) == [.settlePaper, .applyPaper])
    #expect(await port.persistenceCalls.count == 1)
    #expect((await runtime.snapshot()).lastResetPlan == plan)
  }

  @Test("paper persistence failure does not apply projection")
  func paperReplacementPersistenceFailureIsAtomic() async {
    let plan = makePlan()
    let port = ArtifactResetPortFixture(
      responses: [.completed(.paperReplacementSettled(plan))],
      persistenceResponses: [.failed("paper durable write failed")]
    )
    let runtime = await PlotterArtifactResetRuntime(effectPort: port, persistencePort: port)

    #expect(!(await runtime.submit(.paperReplaced(plan), facts: .init(environment: .live))))
    #expect(await port.calls.map(kind) == [.settlePaper])
    #expect(await port.persistenceCalls.count == 1)
    #expect((await runtime.snapshot()).lastResetPlan == nil)
  }

  @Test("SIM cannot apply Saved Learning into LIVE durable authority")
  func simulatedApplyCannotWriteLive() async throws {
    let checkpoint = try makeCheckpoint()
    let runtime = await PlotterArtifactResetRuntime(
      effectPort: ArtifactResetPortFixture(responses: []),
      persistencePort: ArtifactResetPortFixture(responses: [])
    )
    await runtime.installSavedLearningFact(.awaitingOperatorDecision(
      checkpoint,
      opticalComparison: "advisory"
    ))

    #expect(!(await runtime.submit(.applySavedLearning, facts: .init(environment: .simulated))))
    let snapshot = await runtime.snapshot()
    #expect(snapshot.savedLearning.candidate?.checkpoint == checkpoint)
    #expect(snapshot.phase == .refused("SIMULATED Saved Learning cannot write LIVE durable authority."))
  }

  @Test("possible ink and active Stop block artifact mutation")
  func possibleInkAndStopBlockMutation() async {
    let runtime = await PlotterArtifactResetRuntime(
      effectPort: ArtifactResetPortFixture(responses: []),
      persistencePort: ArtifactResetPortFixture(responses: [])
    )
    let plan = makePlan()

    #expect(!(await runtime.submit(
      .paperReplaced(plan),
      facts: .init(environment: .live, possibleInkBlocked: true)
    )))
    #expect(!(await runtime.submit(
      .paperReplaced(plan),
      facts: .init(environment: .live, activeStopBlocked: true)
    )))
    #expect(!(await runtime.submit(
      .reset(plan),
      facts: .init(environment: .live, possibleInkBlocked: true)
    )))
    #expect((await runtime.snapshot()).terminalHistory.count == 3)
  }

  @Test("reset admits settleable Learning Stop and motion facts")
  func resetAdmitsLearningSettlement() async {
    let plan = makePlan()
    let port = ArtifactResetPortFixture(
      responses: [
        .completed(.resetSettled(plan)),
        .completed(.inMemoryResetApplied(plan)),
      ],
      persistenceResponses: [
        .completed(.resetPersisted(plan, savedLearning: .absent))
      ]
    )
    let runtime = await PlotterArtifactResetRuntime(effectPort: port, persistencePort: port)

    #expect(await runtime.submit(
      .reset(plan),
      facts: .init(
        environment: .live,
        activeStopBlocked: true,
        motionSettlementBlocked: true
      )
    ))
    #expect(await port.calls.map(kind) == [.settle, .applyMemory])
    #expect(await port.persistenceCalls.count == 1)
  }

  @Test("terminal history is bounded")
  func terminalHistoryIsBounded() async {
    let runtime = await PlotterArtifactResetRuntime(
      effectPort: ArtifactResetPortFixture(responses: []),
      persistencePort: ArtifactResetPortFixture(responses: [])
    )
    let plan = makePlan()

    for _ in 0..<19 {
      #expect(!(await runtime.submit(.reset(plan), facts: .init(
        environment: .live,
        motionSettlementBlocked: true
      ))))
    }

    #expect((await runtime.snapshot()).terminalHistory.count == 16)
  }

  @Test("canonical checkpoint remains decodeable")
  func canonicalCheckpointDecode() throws {
    let checkpoint = try makeCheckpoint()
    let data = try JSONEncoder().encode(checkpoint)
    let decoded = try JSONDecoder().decode(AcceptedLearningPathCheckpoint.self, from: data)

    #expect(decoded == checkpoint)
    try decoded.validate()
  }
}

private actor ArtifactResetPortFixture:
  PlotterArtifactResetEffectPort,
  PlotterArtifactResetPersistencePort
{
  private var responses: [PlotterArtifactResetEffectResult]
  private var persistenceResponses: [PlotterArtifactResetPersistenceResult]
  private let suspendsFirstRequest: Bool
  private var suspended = false
  private var suspendedResponse: PlotterArtifactResetEffectResult?
  private var continuation: CheckedContinuation<PlotterArtifactResetEffectResult, Never>?
  private(set) var calls: [PlotterArtifactResetEffectRequest] = []
  private(set) var persistenceCalls: [PlotterArtifactResetPersistenceRequest] = []

  init(
    responses: [PlotterArtifactResetEffectResult],
    persistenceResponses: [PlotterArtifactResetPersistenceResult] = [],
    suspendsFirstRequest: Bool = false
  ) {
    self.responses = responses
    self.persistenceResponses = persistenceResponses
    self.suspendsFirstRequest = suspendsFirstRequest
  }

  func persist(_ request: PlotterArtifactResetPersistenceRequest) async
    -> PlotterArtifactResetPersistenceResult
  {
    persistenceCalls.append(request)
    return persistenceResponses.isEmpty
      ? .failed("Unexpected artifact/reset persistence.")
      : persistenceResponses.removeFirst()
  }

  func execute(_ request: PlotterArtifactResetEffectRequest) async
    -> PlotterArtifactResetEffectResult
  {
    calls.append(request)
    let response = responses.isEmpty ? .failed("Unexpected artifact/reset effect.") : responses.removeFirst()
    if suspendsFirstRequest && !suspended {
      suspended = true
      suspendedResponse = response
      return await withCheckedContinuation { continuation = $0 }
    }
    return response
  }

  func waitForCallCount(_ count: Int) async {
    while calls.count < count { await Task.yield() }
  }

  func releaseSuspendedRequest() {
    guard let continuation else { return }
    self.continuation = nil
    continuation.resume(returning: suspendedResponse ?? .cancelled("cancelled"))
    suspendedResponse = nil
  }
}

private enum ArtifactResetCallKind: Equatable {
  case compare
  case applySaved
  case retain
  case reject
  case redo
  case additional
  case settlePaper
  case applyPaper
  case settle
  case applyMemory
}

private func kind(_ request: PlotterArtifactResetEffectRequest) -> ArtifactResetCallKind {
  switch request {
  case .compareSavedLearning: .compare
  case .applySavedLearning: .applySaved
  case .retainSavedLearning: .retain
  case .rejectSavedLearning: .reject
  case .redoStep: .redo
  case .recordAnotherAttempt: .additional
  case .settleForPaperReplacement: .settlePaper
  case .applyInMemoryPaperReplacement: .applyPaper
  case .settleForReset: .settle
  case .applyInMemoryReset: .applyMemory
  }
}

private func makePlan() -> PlotterArtifactResetPlan {
  PlotterArtifactResetPlan(
    id: "reset-all",
    sourceIsSimulated: false,
    resetAll: true,
    removesDurableMachineCheckpoint: true,
    removesDurableTipCheckpoint: true,
    physicalInkMayRemain: true
  )
}

private func makeCheckpoint() throws -> AcceptedLearningPathCheckpoint {
  try AcceptedLearningPathCheckpoint(
    semanticIdentity: LearningPathSemanticIdentity(
      machineGeometry: MachineGeometryIdentity(),
      toolAssembly: ToolAssemblyRevision(),
      penContactProfile: PenContactProfileRevision(),
      paperInstance: PaperInstanceRevision(),
      paperContactPlane: PaperContactPlaneRevision(),
      cameraMountRevision: UUID(),
      cameraReframingRevision: UUID()
    )
  )
}
