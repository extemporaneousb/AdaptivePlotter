import EpisodeCore
import Foundation
import Testing

@Suite("EpisodeCore domain-generic contracts")
struct EpisodeCoreValueContractTests {
  @Test("definition preserves the bounded goal, grammar, context, budgets, and assessment rules")
  func definitionRoundTrip() throws {
    let definition = EpisodeDefinition<TestIntent>(
      id: Fixtures.definitionID,
      revision: revision("definition-v3"),
      goal: EpisodeGoal(
        terminalConstraints: [
          EpisodeGoalConstraint(
            id: EpisodeGoalConstraintID(rawValue: "counter-at-target"),
            summary: "Counter reaches the requested target."
          )
        ],
        intermediateConstraints: [
          EpisodeGoalConstraint(
            id: EpisodeGoalConstraintID(rawValue: "counter-monotonic"),
            summary: "Counter never decreases."
          )
        ],
        assessmentCriteria: [
          EpisodeAssessmentCriterion(
            id: EpisodeAssessmentCriterionID(rawValue: "exact-target"),
            summary: "The terminal count equals the requested target."
          )
        ],
        terminationConditions: [
          EpisodeTerminationCondition(
            id: EpisodeTerminationConditionID(rawValue: "target-reached"),
            summary: "Stop when the target is reached."
          )
        ]
      ),
      initialContext: TestInitialContext(
        stateRevision: EpisodeStateRevision(rawValue: 4),
        capabilityFacts: [Fixtures.capabilityReference],
        artifactReferences: [Fixtures.artifactReference]
      ),
      permittedIntentGrammar: TestIntentGrammar(permittedIntents: [.advance, .finish]),
      budgets: EpisodeBudgets(
        maximumCommittedEventCount: 12,
        maximumElapsedNanoseconds: 5_000,
        maximumExternalEffectCount: 3
      ),
      assessmentRules: [
        TestAssessmentRule(
          id: "terminal-count-v1",
          criterionIDs: [EpisodeAssessmentCriterionID(rawValue: "exact-target")],
          summary: "Compare the terminal counter with the target."
        )
      ]
    )

    requireFoundationValueContract(definition)
    let decoded = try JSONDecoder().decode(
      EpisodeDefinition<TestIntent>.self,
      from: JSONEncoder().encode(definition)
    )

    #expect(decoded == definition)
    #expect(decoded.permittedIntentGrammar.permittedIntents == [.advance, .finish])
    #expect(decoded.initialContext.stateRevision == EpisodeStateRevision(rawValue: 4))
    #expect(decoded.budgets.maximumExternalEffectCount == 3)
    #expect(decoded.goal.intermediateConstraints.map(\.id) == [
      EpisodeGoalConstraintID(rawValue: "counter-monotonic")
    ])
  }

  @Test("manifest independently pins every generic and domain revision axis")
  func manifestRevisionEnvelope() throws {
    let manifest = EpisodeManifest<TestDomainManifest>(
      id: Fixtures.manifestID,
      episodeID: Fixtures.episodeID,
      definitionID: Fixtures.definitionID,
      definitionRevision: revision("definition-v3"),
      domainRevision: revision("domain-v7"),
      evaluatorRevision: revision("evaluator-v2"),
      reducerRevision: revision("reducer-v5"),
      schemaRevisions: EpisodeSchemaRevisions(
        state: revision("state-schema-v4"),
        event: revision("event-schema-v6"),
        journal: revision("journal-schema-v2")
      ),
      buildRevision: revision("build-abc123"),
      deterministicSeed: 42,
      domainManifest: TestDomainManifest(
        vocabularyRevision: "counter-domain-v1",
        target: 2
      )
    )

    requireFoundationValueContract(manifest)
    let decoded = try JSONDecoder().decode(
      EpisodeManifest<TestDomainManifest>.self,
      from: JSONEncoder().encode(manifest)
    )

    #expect(decoded == manifest)
    #expect(decoded.definitionRevision != decoded.domainRevision)
    #expect(decoded.evaluatorRevision != decoded.reducerRevision)
    #expect(decoded.schemaRevisions.state == revision("state-schema-v4"))
    #expect(decoded.schemaRevisions.event == revision("event-schema-v6"))
    #expect(decoded.schemaRevisions.journal == revision("journal-schema-v2"))
    #expect(decoded.domainManifest.target == 2)
  }
}

@Suite("EpisodeCore pure intent and reduction contracts")
struct EpisodeCorePureContractTests {
  @Test("evaluator admission is deterministic and bound to exact state and fact revisions")
  func deterministicAdmission() {
    let evaluator = TestEvaluator()
    let state = TestState(
      episodeID: Fixtures.episodeID,
      revision: EpisodeStateRevision(rawValue: 8),
      canonicalDigest: EpisodeStateDigest(rawValue: "state-8"),
      count: 1,
      isTerminal: false
    )
    let fact = TestCapabilityFact(
      capabilityID: Fixtures.capabilityID,
      owner: Fixtures.authorityID,
      revision: CapabilityFactRevision(rawValue: 13),
      isAvailable: true
    )

    let first = evaluator.evaluate(
      requestID: Fixtures.requestID,
      intent: .advance,
      state: state,
      capabilityFacts: [fact]
    )
    let second = evaluator.evaluate(
      requestID: Fixtures.requestID,
      intent: .advance,
      state: state,
      capabilityFacts: [fact]
    )

    #expect(first == second)
    #expect(first.disposition == .admitted)
    #expect(first.isAdmitted)
    #expect(first.context.comparedStateRevision == EpisodeStateRevision(rawValue: 8))
    #expect(first.context.comparedCapabilityFacts == [CapabilityFactReference(fact)])
    #expect(first.requirementResults == [
      .satisfied(IntentRequirementSatisfaction(
        requirementID: Fixtures.requirementID,
        owner: Fixtures.authorityID,
        comparedCapabilityFacts: [CapabilityFactReference(fact)]
      ))
    ])
  }

  @Test("refusal retains the typed requirement, owner, compared revisions, and exact remedy")
  func typedRefusal() {
    let state = TestState(
      episodeID: Fixtures.episodeID,
      revision: EpisodeStateRevision(rawValue: 9),
      canonicalDigest: EpisodeStateDigest(rawValue: "state-9"),
      count: 1,
      isTerminal: false
    )
    let unavailable = TestCapabilityFact(
      capabilityID: Fixtures.capabilityID,
      owner: Fixtures.authorityID,
      revision: CapabilityFactRevision(rawValue: 14),
      isAvailable: false
    )

    let decision = TestEvaluator().evaluate(
      requestID: Fixtures.requestID,
      intent: .advance,
      state: state,
      capabilityFacts: [unavailable]
    )

    #expect(decision.disposition == .refused)
    #expect(!decision.isAdmitted)
    #expect(decision.context.requestID == Fixtures.requestID)
    #expect(decision.context.episodeID == Fixtures.episodeID)
    #expect(decision.context.comparedStateRevision == EpisodeStateRevision(rawValue: 9))
    #expect(decision.context.comparedCapabilityFacts == [CapabilityFactReference(unavailable)])
    #expect(decision.requirementResults == [
      .refused(IntentRequirementRefusal(
        requirementID: Fixtures.requirementID,
        owner: Fixtures.authorityID,
        comparedCapabilityFacts: [CapabilityFactReference(unavailable)],
        remedy: TestEvaluator.remedy
      ))
    ])
  }

  @Test("reducer deterministically derives state and effects from one committed event")
  func deterministicReduction() {
    let state = TestState(
      episodeID: Fixtures.episodeID,
      revision: .initial,
      canonicalDigest: EpisodeStateDigest(rawValue: "state-0"),
      count: 0,
      isTerminal: false
    )
    let event = makeEvent(
      id: Fixtures.firstEventID,
      sequence: .first,
      preRevision: .initial,
      postRevision: EpisodeStateRevision(rawValue: 1),
      payload: .intentAccepted(.advance),
      digest: "state-1"
    )

    let first = TestReducer().reduce(state: state, event: event)
    let second = TestReducer().reduce(state: state, event: event)

    #expect(first.state == second.state)
    #expect(first.effects == second.effects)
    #expect(first.state.revision == event.postStateRevision)
    #expect(first.state.canonicalDigest == event.postStateDigest)
    #expect(first.state.count == 1)
    #expect(first.effects == [.recordIncrement(1)])
  }

  @Test("a committed refusal advances journal state without manufacturing an effect")
  func refusedEventEmitsNoEffect() {
    let state = TestState(
      episodeID: Fixtures.episodeID,
      revision: EpisodeStateRevision(rawValue: 1),
      canonicalDigest: EpisodeStateDigest(rawValue: "state-1"),
      count: 1,
      isTerminal: false
    )
    let event = makeEvent(
      id: Fixtures.secondEventID,
      sequence: EpisodeEventSequence(rawValue: 1),
      preRevision: EpisodeStateRevision(rawValue: 1),
      postRevision: EpisodeStateRevision(rawValue: 2),
      payload: .intentRefused(.finish),
      digest: "state-2-refused"
    )

    let reduction = TestReducer().reduce(state: state, event: event)

    #expect(reduction.state.count == state.count)
    #expect(reduction.state.revision == EpisodeStateRevision(rawValue: 2))
    #expect(reduction.effects.isEmpty)
  }
}

@Suite("EpisodeCore event and journal schema contracts")
struct EpisodeCoreJournalContractTests {
  @Test("event retains identity, order, provenance, causation, typed payload, artifacts, and digest")
  func eventSchema() throws {
    let event = EpisodeEvent<TestEventPayload>(
      id: Fixtures.secondEventID,
      episodeID: Fixtures.episodeID,
      sequence: EpisodeEventSequence(rawValue: 1),
      recordedAt: Date(timeIntervalSince1970: 20),
      actor: EpisodeEventActor(
        id: EpisodeActorID(rawValue: "counter-environment"),
        origin: .environment
      ),
      causation: EpisodeEventCausation(
        eventID: Fixtures.firstEventID,
        intentRequestID: Fixtures.requestID,
        effectID: Fixtures.effectID
      ),
      correlationID: Fixtures.correlationID,
      preStateRevision: EpisodeStateRevision(rawValue: 1),
      postStateRevision: EpisodeStateRevision(rawValue: 2),
      payload: .intentAccepted(.finish),
      artifactReferences: [Fixtures.artifactReference],
      postStateDigest: EpisodeStateDigest(rawValue: "state-2")
    )

    requireFoundationValueContract(event)
    let decoded = try JSONDecoder().decode(
      EpisodeEvent<TestEventPayload>.self,
      from: JSONEncoder().encode(event)
    )

    #expect(decoded == event)
    #expect(decoded.actor.origin == .environment)
    #expect(decoded.causation?.eventID == Fixtures.firstEventID)
    #expect(decoded.causation?.intentRequestID == Fixtures.requestID)
    #expect(decoded.causation?.effectID == Fixtures.effectID)
    #expect(decoded.artifactReferences == [Fixtures.artifactReference])
  }

  @Test("journal accepts an ordered contiguous event and revision chain")
  func orderedJournalRoundTrip() throws {
    let events = validEvents()
    let journal = try EpisodeJournal(
      manifestID: Fixtures.manifestID,
      episodeID: Fixtures.episodeID,
      events: events
    )

    requireFoundationValueContract(journal)
    let decoded = try JSONDecoder().decode(
      EpisodeJournal<TestEventPayload>.self,
      from: JSONEncoder().encode(journal)
    )

    #expect(decoded == journal)
    #expect(decoded.events.map(\.id) == [Fixtures.firstEventID, Fixtures.secondEventID])
    #expect(decoded.events.map(\.sequence) == [
      EpisodeEventSequence(rawValue: 0),
      EpisodeEventSequence(rawValue: 1)
    ])
    #expect(decoded.events[1].causation?.eventID == decoded.events[0].id)
  }

  @Test("journal refuses an event from another episode")
  func refusesEpisodeMismatch() {
    var events = validEvents()
    events[1] = makeEvent(
      id: Fixtures.secondEventID,
      episodeID: Fixtures.otherEpisodeID,
      sequence: EpisodeEventSequence(rawValue: 1),
      preRevision: EpisodeStateRevision(rawValue: 1),
      postRevision: EpisodeStateRevision(rawValue: 2),
      payload: .intentAccepted(.finish),
      digest: "state-2"
    )

    #expect(throws: EpisodeJournalValidationError.episodeMismatch(
      index: 1,
      expected: Fixtures.episodeID,
      actual: Fixtures.otherEpisodeID
    )) {
      _ = try EpisodeJournal(
        manifestID: Fixtures.manifestID,
        episodeID: Fixtures.episodeID,
        events: events
      )
    }
  }

  @Test("journal refuses gaps or reordering in the episode sequence")
  func refusesSequenceGap() {
    var events = validEvents()
    events[1] = makeEvent(
      id: Fixtures.secondEventID,
      sequence: EpisodeEventSequence(rawValue: 2),
      preRevision: EpisodeStateRevision(rawValue: 1),
      postRevision: EpisodeStateRevision(rawValue: 2),
      payload: .intentAccepted(.finish),
      digest: "state-2"
    )

    #expect(throws: EpisodeJournalValidationError.sequenceMismatch(
      index: 1,
      expected: EpisodeEventSequence(rawValue: 1),
      actual: EpisodeEventSequence(rawValue: 2)
    )) {
      _ = try EpisodeJournal(
        manifestID: Fixtures.manifestID,
        episodeID: Fixtures.episodeID,
        events: events
      )
    }
  }

  @Test("journal decoding revalidates ordering instead of trusting serialized bytes")
  func decodingRefusesSequenceGap() throws {
    var events = validEvents()
    events[1] = makeEvent(
      id: Fixtures.secondEventID,
      sequence: EpisodeEventSequence(rawValue: 2),
      preRevision: EpisodeStateRevision(rawValue: 1),
      postRevision: EpisodeStateRevision(rawValue: 2),
      payload: .intentAccepted(.finish),
      digest: "state-2"
    )
    let encoded = try JSONEncoder().encode(
      UncheckedJournalEnvelope(
        manifestID: Fixtures.manifestID,
        episodeID: Fixtures.episodeID,
        initialStateRevision: .initial,
        events: events
      )
    )

    #expect(throws: EpisodeJournalValidationError.sequenceMismatch(
      index: 1,
      expected: EpisodeEventSequence(rawValue: 1),
      actual: EpisodeEventSequence(rawValue: 2)
    )) {
      _ = try JSONDecoder().decode(EpisodeJournal<TestEventPayload>.self, from: encoded)
    }
  }

  @Test("journal refuses a noncontiguous pre-state revision")
  func refusesPreStateRevisionGap() {
    var events = validEvents()
    events[1] = makeEvent(
      id: Fixtures.secondEventID,
      sequence: EpisodeEventSequence(rawValue: 1),
      preRevision: EpisodeStateRevision(rawValue: 7),
      postRevision: EpisodeStateRevision(rawValue: 8),
      payload: .intentAccepted(.finish),
      digest: "state-8"
    )

    #expect(throws: EpisodeJournalValidationError.preStateRevisionMismatch(
      index: 1,
      expected: EpisodeStateRevision(rawValue: 1),
      actual: EpisodeStateRevision(rawValue: 7)
    )) {
      _ = try EpisodeJournal(
        manifestID: Fixtures.manifestID,
        episodeID: Fixtures.episodeID,
        events: events
      )
    }
  }

  @Test("journal refuses an event that does not advance exactly one state revision")
  func refusesPostStateRevisionGap() {
    let event = makeEvent(
      id: Fixtures.firstEventID,
      sequence: .first,
      preRevision: .initial,
      postRevision: EpisodeStateRevision(rawValue: 2),
      payload: .intentAccepted(.advance),
      digest: "state-2"
    )

    #expect(throws: EpisodeJournalValidationError.postStateRevisionMismatch(
      index: 0,
      expected: EpisodeStateRevision(rawValue: 1),
      actual: EpisodeStateRevision(rawValue: 2)
    )) {
      _ = try EpisodeJournal(
        manifestID: Fixtures.manifestID,
        episodeID: Fixtures.episodeID,
        events: [event]
      )
    }
  }

  @Test("journal refuses duplicate event identity")
  func refusesDuplicateEventIdentity() {
    var events = validEvents()
    events[1] = makeEvent(
      id: Fixtures.firstEventID,
      sequence: EpisodeEventSequence(rawValue: 1),
      preRevision: EpisodeStateRevision(rawValue: 1),
      postRevision: EpisodeStateRevision(rawValue: 2),
      payload: .intentAccepted(.finish),
      digest: "state-2"
    )

    #expect(throws: EpisodeJournalValidationError.duplicateEventID(Fixtures.firstEventID)) {
      _ = try EpisodeJournal(
        manifestID: Fixtures.manifestID,
        episodeID: Fixtures.episodeID,
        events: events
      )
    }
  }

  @Test("journal causation can reference only an earlier committed event")
  func refusesUnknownCausation() {
    let unknownEventID = EpisodeEventID(
      rawValue: uuid("00000000-0000-0000-0000-000000000099")
    )
    let event = makeEvent(
      id: Fixtures.firstEventID,
      sequence: .first,
      preRevision: .initial,
      postRevision: EpisodeStateRevision(rawValue: 1),
      payload: .intentAccepted(.advance),
      digest: "state-1",
      causation: EpisodeEventCausation(eventID: unknownEventID)
    )

    #expect(throws: EpisodeJournalValidationError.unknownCausation(
      index: 0,
      eventID: unknownEventID
    )) {
      _ = try EpisodeJournal(
        manifestID: Fixtures.manifestID,
        episodeID: Fixtures.episodeID,
        events: [event]
      )
    }
  }
}

private enum TestIntent: String, EpisodeIntent {
  case advance
  case finish

  typealias InitialContext = TestInitialContext
  typealias Grammar = TestIntentGrammar
  typealias AssessmentRule = TestAssessmentRule
}

private struct TestInitialContext: Codable, Hashable, Sendable {
  let stateRevision: EpisodeStateRevision
  let capabilityFacts: [CapabilityFactReference]
  let artifactReferences: [EpisodeArtifactReference]
}

private struct TestIntentGrammar: Codable, Hashable, Sendable {
  let permittedIntents: [TestIntent]
}

private struct TestAssessmentRule: Codable, Hashable, Sendable {
  let id: String
  let criterionIDs: [EpisodeAssessmentCriterionID]
  let summary: String
}

private struct TestDomainManifest: Codable, Hashable, Sendable {
  let vocabularyRevision: String
  let target: Int
}

private struct TestState: EpisodeState {
  let episodeID: EpisodeID
  let revision: EpisodeStateRevision
  let canonicalDigest: EpisodeStateDigest
  let count: Int
  let isTerminal: Bool
}

private struct TestCapabilityFact: CapabilityFact {
  let capabilityID: EpisodeCapabilityID
  let owner: EpisodeAuthorityID
  let revision: CapabilityFactRevision
  let isAvailable: Bool
}

private struct TestEvaluator: EpisodeIntentEvaluating {
  static let remedy = "Restore the counter capability and submit a fresh request."

  func evaluate(
    requestID: IntentRequestID,
    intent: TestIntent,
    state: TestState,
    capabilityFacts: [TestCapabilityFact]
  ) -> IntentDecision {
    let references = capabilityFacts.map(CapabilityFactReference.init)
    let available = capabilityFacts.count == 1 && capabilityFacts[0].isAvailable
    let context = IntentDecisionContext(
      requestID: requestID,
      episodeID: state.episodeID,
      comparedStateRevision: state.revision,
      comparedCapabilityFacts: references
    )
    if available {
      return .admitted(
        context: context,
        satisfiedRequirements: [
          IntentRequirementSatisfaction(
            requirementID: Fixtures.requirementID,
            owner: Fixtures.authorityID,
            comparedCapabilityFacts: references
          )
        ]
      )
    }
    return .refused(
      context: context,
      failedRequirements: [
        IntentRequirementRefusal(
          requirementID: Fixtures.requirementID,
          owner: Fixtures.authorityID,
          comparedCapabilityFacts: references,
          remedy: Self.remedy
        )
      ]
    )
  }
}

private enum TestEventPayload: Codable, Hashable, Sendable {
  case intentAccepted(TestIntent)
  case intentRefused(TestIntent)
}

private enum TestEffect: Codable, Hashable, Sendable {
  case recordIncrement(Int)
}

private struct UncheckedJournalEnvelope<Payload>: Encodable
where Payload: Codable & Hashable & Sendable {
  let manifestID: EpisodeManifestID
  let episodeID: EpisodeID
  let initialStateRevision: EpisodeStateRevision
  let events: [EpisodeEvent<Payload>]
}

private struct TestReducer: EpisodeReducing {
  func reduce(
    state: TestState,
    event: EpisodeEvent<TestEventPayload>
  ) -> EpisodeReduction<TestState, TestEffect> {
    switch event.payload {
    case .intentAccepted(.advance):
      return EpisodeReduction(
        state: TestState(
          episodeID: state.episodeID,
          revision: event.postStateRevision,
          canonicalDigest: event.postStateDigest,
          count: state.count + 1,
          isTerminal: false
        ),
        effects: [.recordIncrement(1)]
      )
    case .intentAccepted(.finish):
      return EpisodeReduction(
        state: TestState(
          episodeID: state.episodeID,
          revision: event.postStateRevision,
          canonicalDigest: event.postStateDigest,
          count: state.count,
          isTerminal: true
        )
      )
    case .intentRefused:
      return EpisodeReduction(
        state: TestState(
          episodeID: state.episodeID,
          revision: event.postStateRevision,
          canonicalDigest: event.postStateDigest,
          count: state.count,
          isTerminal: state.isTerminal
        )
      )
    }
  }
}

private enum Fixtures {
  static let episodeID = EpisodeID(
    rawValue: uuid("00000000-0000-0000-0000-000000000001")
  )
  static let otherEpisodeID = EpisodeID(
    rawValue: uuid("00000000-0000-0000-0000-000000000002")
  )
  static let definitionID = EpisodeDefinitionID(
    rawValue: uuid("00000000-0000-0000-0000-000000000010")
  )
  static let manifestID = EpisodeManifestID(
    rawValue: uuid("00000000-0000-0000-0000-000000000020")
  )
  static let requestID = IntentRequestID(
    rawValue: uuid("00000000-0000-0000-0000-000000000030")
  )
  static let firstEventID = EpisodeEventID(
    rawValue: uuid("00000000-0000-0000-0000-000000000040")
  )
  static let secondEventID = EpisodeEventID(
    rawValue: uuid("00000000-0000-0000-0000-000000000041")
  )
  static let effectID = EpisodeEffectID(
    rawValue: uuid("00000000-0000-0000-0000-000000000050")
  )
  static let correlationID = EpisodeCorrelationID(
    rawValue: uuid("00000000-0000-0000-0000-000000000060")
  )
  static let capabilityID = EpisodeCapabilityID(rawValue: "counter-available")
  static let authorityID = EpisodeAuthorityID(rawValue: "counter-environment")
  static let requirementID = EpisodeRequirementID(rawValue: "counter-capability-ready")
  static let capabilityReference = CapabilityFactReference(
    capabilityID: capabilityID,
    owner: authorityID,
    revision: CapabilityFactRevision(rawValue: 13)
  )
  static let artifactReference = EpisodeArtifactReference(
    id: EpisodeArtifactID(rawValue: "counter-input"),
    revision: revision("counter-input-v2"),
    digest: "sha256:counter-input"
  )
}

private func validEvents() -> [EpisodeEvent<TestEventPayload>] {
  [
    makeEvent(
      id: Fixtures.firstEventID,
      sequence: .first,
      preRevision: .initial,
      postRevision: EpisodeStateRevision(rawValue: 1),
      payload: .intentAccepted(.advance),
      digest: "state-1"
    ),
    makeEvent(
      id: Fixtures.secondEventID,
      sequence: EpisodeEventSequence(rawValue: 1),
      preRevision: EpisodeStateRevision(rawValue: 1),
      postRevision: EpisodeStateRevision(rawValue: 2),
      payload: .intentAccepted(.finish),
      digest: "state-2",
      causation: EpisodeEventCausation(eventID: Fixtures.firstEventID)
    )
  ]
}

private func makeEvent(
  id: EpisodeEventID,
  episodeID: EpisodeID = Fixtures.episodeID,
  sequence: EpisodeEventSequence,
  preRevision: EpisodeStateRevision,
  postRevision: EpisodeStateRevision,
  payload: TestEventPayload,
  digest: String,
  causation: EpisodeEventCausation? = nil
) -> EpisodeEvent<TestEventPayload> {
  EpisodeEvent(
    id: id,
    episodeID: episodeID,
    sequence: sequence,
    recordedAt: Date(timeIntervalSince1970: TimeInterval(sequence.rawValue)),
    actor: EpisodeEventActor(
      id: EpisodeActorID(rawValue: "counter-policy"),
      origin: .policy
    ),
    causation: causation,
    correlationID: Fixtures.correlationID,
    preStateRevision: preRevision,
    postStateRevision: postRevision,
    payload: payload,
    postStateDigest: EpisodeStateDigest(rawValue: digest)
  )
}

private func revision(_ rawValue: String) -> EpisodeRevisionIdentifier {
  EpisodeRevisionIdentifier(rawValue: rawValue)
}

private func uuid(_ value: String) -> UUID {
  guard let id = UUID(uuidString: value) else {
    preconditionFailure("invalid UUID fixture: \(value)")
  }
  return id
}

private func requireFoundationValueContract<Value>(_: Value)
where Value: Codable & Hashable & Sendable {}
