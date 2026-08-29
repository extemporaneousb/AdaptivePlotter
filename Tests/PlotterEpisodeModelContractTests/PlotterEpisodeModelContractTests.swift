import EpisodeCore
import Foundation
import PlotterEpisodeModel
import PlotterModel
import Testing

@Suite("PlotterEpisodeModel specification bindings")
struct PlotterEpisodeSpecificationContractTests {
  @Test("definition and manifest bind PlotterModel revisions into EpisodeCore")
  func definitionAndManifestBindings() throws {
    let initialContext = PlotterEpisodeInitialContext(
      initialStateDigest: digest("initial"),
      drawing: PlotterDrawingRevisionReference(
        programID: Fixtures.programID,
        contentHash: try plotterDigest(1)
      ),
      executionPlan: PlotterExecutionPlanReference(
        revisionID: Fixtures.planRevisionID,
        contentHash: try plotterDigest(2)
      ),
      calibration: PlotterCalibrationReference(
        revisionID: Fixtures.calibrationRevisionID,
        contentHash: try plotterDigest(3)
      ),
      paperRevision: revision("paper-v4"),
      environmentRevision: revision("environment-v2")
    )
    let definition = PlotterEpisodeDefinition(
      id: Fixtures.definitionID,
      revision: revision("definition-v1"),
      goal: EpisodeGoal(
        terminalConstraints: [
          EpisodeGoalConstraint(
            id: EpisodeGoalConstraintID(rawValue: "drawing-terminal"),
            summary: "The requested drawing reaches a declared terminal disposition."
          )
        ],
        assessmentCriteria: [
          EpisodeAssessmentCriterion(
            id: Fixtures.criterionID,
            summary: "Accepted evidence supports the declared outcome."
          )
        ],
        terminationConditions: [
          EpisodeTerminationCondition(
            id: EpisodeTerminationConditionID(rawValue: "outcome-recorded"),
            summary: "Stop after assessment of the terminal outcome."
          )
        ]
      ),
      initialContext: initialContext,
      permittedIntentGrammar: PlotterIntentGrammar(
        permittedFamilies: PlotterIntentFamily.allCases
      ),
      budgets: EpisodeBudgets(maximumExternalEffectCount: 12),
      assessmentRules: [
        PlotterAssessmentRule(
          id: EpisodeAssessmentRuleID(rawValue: "evidence-comparison-v1"),
          criterionIDs: [Fixtures.criterionID],
          summary: "Compare the outcome only with accepted evidence."
        )
      ]
    )
    let domainManifest = PlotterEpisodeDomainManifest(
      drawing: initialContext.drawing,
      executionPlan: initialContext.executionPlan,
      calibration: initialContext.calibration,
      paperRevision: initialContext.paperRevision,
      environmentRevision: initialContext.environmentRevision,
      drawingModel: PlotterDrawingModelReference(
        revisionID: Fixtures.modelRevisionID,
        contentHash: try plotterDigest(4)
      ),
      cameraConfigurationID: Fixtures.cameraConfigurationID,
      cameraConfigurationRevision: revision("camera-config-v5")
    )
    let manifest = PlotterEpisodeManifest(
      id: Fixtures.manifestID,
      episodeID: Fixtures.episodeID,
      definitionID: definition.id,
      definitionRevision: definition.revision,
      domainRevision: revision("plotter-domain-v1"),
      evaluatorRevision: revision("plotter-evaluator-v1"),
      reducerRevision: revision("plotter-reducer-v1"),
      schemaRevisions: EpisodeSchemaRevisions(
        state: revision("plotter-state-v1"),
        event: revision("plotter-event-v1"),
        journal: revision("episode-journal-v1")
      ),
      buildRevision: revision("build-test"),
      deterministicSeed: 91,
      domainManifest: domainManifest
    )

    requireValueContract(definition)
    requireValueContract(manifest)
    #expect(
      try JSONDecoder().decode(
        PlotterEpisodeDefinition.self,
        from: JSONEncoder().encode(definition)
      ) == definition
    )
    #expect(
      try JSONDecoder().decode(
        PlotterEpisodeManifest.self,
        from: JSONEncoder().encode(manifest)
      ) == manifest
    )
    #expect(manifest.domainManifest.executionPlan?.revisionID == Fixtures.planRevisionID)
    #expect(manifest.domainManifest.drawingModel?.revisionID == Fixtures.modelRevisionID)
    #expect(manifest.domainManifest.paperRevision == revision("paper-v4"))
  }

  @Test("root intent exhaustively exposes every canonical Plotter family")
  func exhaustiveIntentFamilies() throws {
    let intents: [PlotterIntent] = [
      .session(.begin),
      .observation(.captureExactFrame(configurationID: Fixtures.cameraConfigurationID)),
      .pointSelection(.stage(selectionRequest())),
      .manualMotion(.jog(try PlotterJogRequest(direction: .positiveX, distanceMM: 5))),
      .drawing(.execute(planRevisionID: Fixtures.planRevisionID)),
      .learning(.acceptModel(revisionID: Fixtures.modelRevisionID)),
      .evidence(.accept(
        subject: .observation(Fixtures.observationID),
        question: .pointIdentity
      )),
    ]

    #expect(Set(intents.map(\.family)) == Set(PlotterIntentFamily.allCases))
    #expect(intents.filter(\.requiresExternalEffect).count == 5)
    #expect(!intents[2].requiresExternalEffect)
    #expect(!intents[6].requiresExternalEffect)
  }
}

@Suite("PlotterEpisodeModel pure evaluation")
struct PlotterIntentEvaluatorContractTests {
  @Test("scoped manual-motion evaluation is deterministic and revision-bound")
  func deterministicAdmission() throws {
    let state = readyState()
    let facts = try readyFacts()
    let intent = PlotterIntent.manualMotion(
      .jog(try PlotterJogRequest(direction: .negativeY, distanceMM: 10))
    )

    let first = PlotterIntentEvaluator().evaluate(
      requestID: Fixtures.requestID,
      intent: intent,
      state: state,
      capabilityFacts: facts
    )
    let second = PlotterIntentEvaluator().evaluate(
      requestID: Fixtures.requestID,
      intent: intent,
      state: state,
      capabilityFacts: Array(facts.reversed())
    )

    #expect(first == second)
    #expect(first.isAdmitted)
    #expect(first.context.requestID == Fixtures.requestID)
    #expect(first.context.comparedStateRevision == state.revision)
    #expect(first.context.comparedCapabilityFacts.count == facts.count)
    #expect(first.requirementResults.count == 8)
  }

  @Test("manual jog routing is revision-bound to Down, Up, and Unknown Pen facts")
  func manualJogRouting() throws {
    let cases: [(PlotterControllerPenState, PlotterManualJogRouting)] = [
      (.lowered, .drawingStroke),
      (.raised, .relativeTravel),
      (.unknown, .possibleInk),
    ]
    for (penState, routing) in cases {
      var facts = try readyFacts()
      facts.removeAll { $0.kind == .manualController }
      facts.append(.manualController(PlotterManualControllerFact(
        owner: EpisodeAuthorityID(rawValue: "controller-owner"),
        revision: CapabilityFactRevision(rawValue: 81),
        environment: .live,
        penState: penState,
        operationIsActive: false,
        penActuationProfileRevision: revision("pen-profile-v1")
      )))
      let request = try PlotterJogRequest(
        direction: .positiveX,
        distanceMM: 50,
        feedMMPerMinute: 500,
        routing: routing
      )
      let decision = PlotterIntentEvaluator().evaluate(
        requestID: Fixtures.requestID,
        intent: .manualMotion(.jog(request)),
        state: readyState(),
        capabilityFacts: facts
      )
      #expect(decision.isAdmitted)
      #expect(try roundTrip(request) == request)
    }

    var mismatchedFacts = try readyFacts()
    mismatchedFacts.removeAll { $0.kind == .manualController }
    mismatchedFacts.append(.manualController(PlotterManualControllerFact(
      owner: EpisodeAuthorityID(rawValue: "controller-owner"),
      revision: CapabilityFactRevision(rawValue: 82),
      environment: .live,
      penState: .unknown,
      operationIsActive: false,
      penActuationProfileRevision: revision("pen-profile-v1")
    )))
    let mismatch = PlotterIntentEvaluator().evaluate(
      requestID: Fixtures.requestID,
      intent: .manualMotion(.jog(try PlotterJogRequest(
        direction: .negativeY,
        distanceMM: 4,
        feedMMPerMinute: 250,
        routing: .relativeTravel
      ))),
      state: readyState(),
      capabilityFacts: mismatchedFacts
    )
    #expect(mismatch.disposition == .refused)
    #expect(mismatch.requirementResults.contains { result in
      guard case let .refused(refusal) = result else { return false }
      return refusal.requirementID == PlotterIntentRequirement.jogRoutingCurrent.id
        && refusal.comparedCapabilityFacts.map(\.revision)
          == [CapabilityFactRevision(rawValue: 82)]
    })
  }

  @Test("direct Pen admission requires the exact current profile and inactive controller")
  func directPenAdmission() throws {
    let request = PlotterPenActuationRequest(
      position: .lowered,
      profile: try PlotterManualPenActuationProfile(
        raisedSpindleValue: 40,
        loweredSpindleValue: 760,
        settleSeconds: 0.3,
        revision: revision("pen-profile-v1")
      )
    )
    let admitted = PlotterIntentEvaluator().evaluate(
      requestID: Fixtures.requestID,
      intent: .manualMotion(.setPen(request)),
      state: readyState(),
      capabilityFacts: try readyFacts()
    )
    #expect(admitted.isAdmitted)
    #expect(try roundTrip(request) == request)

    var staleFacts = try readyFacts()
    staleFacts.removeAll { $0.kind == .manualController }
    staleFacts.append(.manualController(PlotterManualControllerFact(
      owner: EpisodeAuthorityID(rawValue: "controller-owner"),
      revision: CapabilityFactRevision(rawValue: 83),
      environment: .live,
      penState: .raised,
      operationIsActive: true,
      penActuationProfileRevision: revision("pen-profile-v2")
    )))
    let refused = PlotterIntentEvaluator().evaluate(
      requestID: Fixtures.requestID,
      intent: .manualMotion(.setPen(request)),
      state: readyState(),
      capabilityFacts: staleFacts
    )
    #expect(refused.disposition == .refused)
    #expect(refused.requirementResults.contains { result in
      guard case let .refused(value) = result else { return false }
      return value.requirementID == PlotterIntentRequirement.controllerOperationInactive.id
    })
    #expect(refused.requirementResults.contains { result in
      guard case let .refused(value) = result else { return false }
      return value.requirementID == PlotterIntentRequirement.penActuationProfileCurrent.id
        && value.comparedCapabilityFacts.map(\.revision)
          == [CapabilityFactRevision(rawValue: 83)]
    })
  }

  @Test("refusal exposes typed requirement, authoritative owner, fact revision, and remedy")
  func refusalMetadata() throws {
    let controllerOwner = EpisodeAuthorityID(rawValue: "controller-owner")
    var facts = try readyFacts()
    facts.removeAll { $0.kind == .motion }
    facts.append(.motion(PlotterMotionFact(
      owner: controllerOwner,
      revision: CapabilityFactRevision(rawValue: 41),
      environment: .live,
      isEnabled: false
    )))
    let decision = PlotterIntentEvaluator().evaluate(
      requestID: Fixtures.requestID,
      intent: .manualMotion(
        .jog(try PlotterJogRequest(direction: .positiveY, distanceMM: 1))
      ),
      state: readyState(),
      capabilityFacts: facts
    )

    guard case let .refused(context, failures) = decision else {
      Issue.record("Expected a typed motion refusal")
      return
    }
    let failure = try #require(
      failures.first { $0.requirementID == PlotterIntentRequirement.motionEnabled.id }
    )
    #expect(context.requestID == Fixtures.requestID)
    #expect(context.comparedStateRevision == EpisodeStateRevision(rawValue: 7))
    #expect(failure.owner == controllerOwner)
    #expect(failure.comparedCapabilityFacts.map(\.revision) == [
      CapabilityFactRevision(rawValue: 41)
    ])
    #expect(failure.remedy == "Enable Motion before requesting movement.")

    let availability = PlotterIntentAvailability(
      intent: .manualMotion(
        .jog(try PlotterJogRequest(direction: .positiveY, distanceMM: 1))
      ),
      decision: decision
    )
    #expect(availability.disposition == .refused)
    #expect(availability.comparedCapabilityFacts == context.comparedCapabilityFacts)
  }

  @Test("direct Pen motion retains an intent-specific Motion remedy")
  func directPenMotionRemedy() throws {
    var facts = try readyFacts()
    facts.removeAll { $0.kind == .motion }
    facts.append(.motion(PlotterMotionFact(
      owner: EpisodeAuthorityID(rawValue: "controller-owner"),
      revision: CapabilityFactRevision(rawValue: 42),
      environment: .live,
      isEnabled: false
    )))
    let request = PlotterPenActuationRequest(
      position: .lowered,
      profile: try PlotterManualPenActuationProfile(
        raisedSpindleValue: 45,
        loweredSpindleValue: 755,
        settleSeconds: 0.25,
        revision: revision("pen-profile-v1")
      )
    )
    let decision = PlotterIntentEvaluator().evaluate(
      requestID: Fixtures.requestID,
      intent: .manualMotion(.setPen(request)),
      state: readyState(),
      capabilityFacts: facts
    )

    guard case let .refused(_, failures) = decision else {
      Issue.record("Expected direct Pen motion to be refused while Motion is disabled")
      return
    }
    let failure = try #require(
      failures.first { $0.requirementID == PlotterIntentRequirement.motionEnabled.id }
    )
    #expect(failure.remedy == "Enable Motion before actuating the pen.")
  }

  @Test("scoped drawing rule refuses a stale plan under the plan owner's revision")
  func stalePlanRefusal() throws {
    let otherPlan = ExecutionPlanRevisionID(try plotterDigest(8))
    let decision = PlotterIntentEvaluator().evaluate(
      requestID: Fixtures.requestID,
      intent: .drawing(.execute(planRevisionID: otherPlan)),
      state: readyState(),
      capabilityFacts: try readyFacts()
    )

    #expect(decision.disposition == .refused)
    #expect(decision.requirementResults.contains { result in
      guard case let .refused(refusal) = result else { return false }
      return refusal.requirementID == PlotterIntentRequirement.executionPlanCurrent.id
        && refusal.owner == EpisodeAuthorityID(rawValue: "plan-owner")
    })
  }
}

@Suite("PlotterEpisodeModel pure reduction")
struct PlotterEpisodeReducerContractTests {
  @Test("accepted intent deterministically emits one typed external request")
  func acceptedIntentEmitsEffect() throws {
    let intent = PlotterIntent.manualMotion(
      .jog(try PlotterJogRequest(direction: .positiveX, distanceMM: 4))
    )
    let accepted = try PlotterAcceptedIntent(
      requestID: Fixtures.requestID,
      intent: intent,
      comparedStateRevision: EpisodeStateRevision(rawValue: 7),
      comparedCapabilityFacts: try readyFacts().map(CapabilityFactReference.init),
      satisfiedRequirements: [],
      execution: .externalEffect(
        effectID: Fixtures.effectID,
        environment: .live
      )
    )
    let event = makeEvent(
      preRevision: EpisodeStateRevision(rawValue: 7),
      postRevision: EpisodeStateRevision(rawValue: 8),
      payload: .intentAccepted(accepted),
      digest: "state-8"
    )

    let first = PlotterEpisodeReducer().reduce(state: readyState(), event: event)
    let second = PlotterEpisodeReducer().reduce(state: readyState(), event: event)

    #expect(first.state == second.state)
    #expect(first.effects == second.effects)
    #expect(first.state.phase == .executing)
    #expect(first.state.pendingEffectID == Fixtures.effectID)
    #expect(first.state.revision == EpisodeStateRevision(rawValue: 8))
    #expect(first.state.canonicalDigest == digest("state-8"))
    #expect(first.effects == [
      .performManualMotion(
        context: PlotterEffectContext(
          episodeID: Fixtures.episodeID,
          requestID: Fixtures.requestID,
          effectID: Fixtures.effectID,
          environment: .live
        ),
        request: try PlotterJogRequest(direction: .positiveX, distanceMM: 4)
      )
    ])
  }

  @Test("state-only exact-frame point selection cannot embed an executable effect")
  func stateOnlyIntentHasNoEffect() throws {
    let request = selectionRequest()
    let accepted = try PlotterAcceptedIntent(
      requestID: Fixtures.requestID,
      intent: .pointSelection(.stage(request)),
      comparedStateRevision: EpisodeStateRevision(rawValue: 7),
      comparedCapabilityFacts: [],
      satisfiedRequirements: [],
      execution: .stateOnly
    )
    let reduction = PlotterEpisodeReducer().reduce(
      state: readyState(observationIDs: [Fixtures.observationID]),
      event: makeEvent(
        preRevision: EpisodeStateRevision(rawValue: 7),
        postRevision: EpisodeStateRevision(rawValue: 8),
        payload: .intentAccepted(accepted),
        digest: "state-8-selection"
      )
    )

    #expect(reduction.effects.isEmpty)
    #expect(reduction.state.exactPointSelection.request == request)
    #expect(reduction.state.exactPointSelection.phase == .collecting)
    #expect(reduction.state.pendingEffectID == nil)
    #expect(reduction.state.phase == .ready)
    #expect(throws: PlotterAcceptedIntentError.stateOnlyRequired) {
      _ = try PlotterAcceptedIntent(
        requestID: Fixtures.requestID,
        intent: accepted.intent,
        comparedStateRevision: EpisodeStateRevision(rawValue: 7),
        comparedCapabilityFacts: [],
        satisfiedRequirements: [],
        execution: .externalEffect(effectID: Fixtures.effectID, environment: .live)
      )
    }
  }

  @Test("committed refusal advances revision without emitting or changing physical state")
  func refusalEmitsNoEffect() {
    let refusal = PlotterIntentRefusalRecord(
      requestID: Fixtures.requestID,
      intent: .session(.finish),
      comparedStateRevision: EpisodeStateRevision(rawValue: 7),
      comparedCapabilityFacts: [],
      failedRequirements: [
        IntentRequirementRefusal(
          requirementID: PlotterIntentRequirement.sessionReady.id,
          owner: EpisodeAuthorityID(rawValue: "PlotterEpisodeModel"),
          comparedCapabilityFacts: [],
          remedy: "Wait for session preparation to commit a ready state."
        )
      ]
    )
    let state = readyState()
    let reduction = PlotterEpisodeReducer().reduce(
      state: state,
      event: makeEvent(
        preRevision: EpisodeStateRevision(rawValue: 7),
        postRevision: EpisodeStateRevision(rawValue: 8),
        payload: .intentRefused(refusal),
        digest: "state-8-refused"
      )
    )

    #expect(reduction.effects.isEmpty)
    #expect(reduction.state.phase == state.phase)
    #expect(reduction.state.lastRefusal == refusal)
    #expect(reduction.state.revision == EpisodeStateRevision(rawValue: 8))
  }

  @Test("result references cannot satisfy point selection until an observation commits")
  func resultReferenceIsNotObservationAuthority() throws {
    let intent = PlotterIntent.manualMotion(
      .jog(try PlotterJogRequest(direction: .positiveX, distanceMM: 4))
    )
    let running = PlotterEpisodeState(
      episodeID: Fixtures.episodeID,
      revision: EpisodeStateRevision(rawValue: 8),
      canonicalDigest: digest("state-8"),
      phase: .executing,
      currentPlanRevisionID: Fixtures.planRevisionID,
      activeRequestID: Fixtures.requestID,
      activeIntent: intent,
      pendingEffectID: Fixtures.effectID
    )
    let resultContext = PlotterEffectResultContext(
      episodeID: Fixtures.episodeID,
      requestID: Fixtures.requestID,
      intent: intent,
      effectID: Fixtures.effectID,
      environment: .live,
      effectRevision: revision("manual-motion-effect-v1")
    )
    let reduction = PlotterEpisodeReducer().reduce(
      state: running,
      event: makeEvent(
        preRevision: EpisodeStateRevision(rawValue: 8),
        postRevision: EpisodeStateRevision(rawValue: 9),
        payload: .effectResult(.completed(
          context: resultContext,
          output: .motionSettled(Fixtures.observationID)
        )),
        digest: "state-9"
      )
    )

    #expect(reduction.effects.isEmpty)
    #expect(reduction.state.phase == .ready)
    #expect(reduction.state.pendingEffectID == nil)
    #expect(reduction.state.activeRequestID == nil)
    #expect(reduction.state.observationIDs.isEmpty)
    #expect(reduction.state.lastTerminalEffect?.result == .completed(
      context: resultContext,
      output: .motionSettled(Fixtures.observationID)
    ))

    let selection = PlotterIntent.pointSelection(.stage(selectionRequest()))
    let beforeObservation = PlotterIntentEvaluator().evaluate(
      requestID: IntentRequestID(rawValue: uuid(18)),
      intent: selection,
      state: reduction.state,
      capabilityFacts: []
    )
    #expect(beforeObservation.disposition == .refused)
    #expect(beforeObservation.requirementResults.contains { result in
      guard case let .refused(refusal) = result else { return false }
      return refusal.requirementID == PlotterIntentRequirement.sourceObservationRecorded.id
        && refusal.remedy
          == "Capture and commit the exact source observation before selecting its point."
    })

    let observation = PlotterObservation.controller(PlotterControllerObservation(
      context: PlotterObservationContext(
        id: Fixtures.observationID,
        observedAt: Date(timeIntervalSince1970: 101),
        environment: .live,
        source: .controller,
        sourceRevision: revision("controller-observation-v1")
      ),
      status: .idle,
      machinePosition: try Point2(x: 2, y: 3),
      motionEnabled: true
    ))
    let observationReduction = PlotterEpisodeReducer().reduce(
      state: reduction.state,
      event: makeEvent(
        preRevision: EpisodeStateRevision(rawValue: 9),
        postRevision: EpisodeStateRevision(rawValue: 10),
        payload: .observationRecorded(observation),
        digest: "state-10-observation"
      )
    )
    let afterObservation = PlotterIntentEvaluator().evaluate(
      requestID: IntentRequestID(rawValue: uuid(19)),
      intent: selection,
      state: observationReduction.state,
      capabilityFacts: []
    )

    #expect(observationReduction.state.observationIDs == [Fixtures.observationID])
    #expect(afterObservation.disposition == .admitted)
  }

  @Test("only committed attributable progress updates state and projection before terminal result")
  func progressAndTerminalReduction() throws {
    let intent = PlotterIntent.manualMotion(
      .jog(try PlotterJogRequest(direction: .positiveX, distanceMM: 4))
    )
    let running = PlotterEpisodeState(
      episodeID: Fixtures.episodeID,
      revision: EpisodeStateRevision(rawValue: 8),
      canonicalDigest: digest("state-8"),
      phase: .executing,
      currentPlanRevisionID: Fixtures.planRevisionID,
      activeRequestID: Fixtures.requestID,
      activeIntent: intent,
      pendingEffectID: Fixtures.effectID
    )
    let progress = try PlotterEffectProgress(
      episodeID: Fixtures.episodeID,
      requestID: Fixtures.requestID,
      intent: intent,
      effectID: Fixtures.effectID,
      effectRevision: revision("manual-motion-effect-v1"),
      environment: .live,
      lane: .machine,
      owningSubsystem: .machineController,
      phase: .progressing,
      startedAt: Date(timeIntervalSince1970: 10),
      lastAttributableProgressAt: Date(timeIntervalSince1970: 12),
      resultCurrentlyAwaited: .controllerSettlement,
      deadline: Date(timeIntervalSince1970: 20),
      cancellation: PlotterEffectCancellationStatus(
        availability: .available,
        phase: .notRequested
      )
    )

    #expect(running.activeEffectProgress == nil)
    let progressed = PlotterEpisodeReducer().reduce(
      state: running,
      event: makeEvent(
        preRevision: EpisodeStateRevision(rawValue: 8),
        postRevision: EpisodeStateRevision(rawValue: 9),
        payload: .effectProgressed(progress),
        digest: "state-9-progress"
      )
    )
    let activeProjection = PlotterEpisodeProjector.project(
      state: progressed.state,
      availabilities: [],
      revision: PlotterProjectionRevision(rawValue: 4),
      projectedAt: Date(timeIntervalSince1970: 13)
    )

    requireValueContract(progress)
    #expect(try roundTrip(progress) == progress)
    #expect(progressed.state.activeEffectProgress == progress)
    #expect(activeProjection.activeEffectProgress == progress)
    #expect(activeProjection.lastTerminalEffect == nil)

    let resultContext = PlotterEffectResultContext(
      episodeID: Fixtures.episodeID,
      requestID: Fixtures.requestID,
      intent: intent,
      effectID: Fixtures.effectID,
      environment: .live,
      effectRevision: revision("manual-motion-effect-v1")
    )
    let settled = PlotterEpisodeReducer().reduce(
      state: progressed.state,
      event: makeEvent(
        preRevision: EpisodeStateRevision(rawValue: 9),
        postRevision: EpisodeStateRevision(rawValue: 10),
        payload: .effectResult(.cancelled(context: resultContext)),
        digest: "state-10-cancelled"
      )
    )
    let terminalProjection = PlotterEpisodeProjector.project(
      state: settled.state,
      availabilities: [],
      revision: PlotterProjectionRevision(rawValue: 5),
      projectedAt: Date(timeIntervalSince1970: 101)
    )

    #expect(settled.state.activeEffectProgress == nil)
    #expect(settled.state.lastTerminalEffect?.disposition == .cancelled)
    #expect(settled.state.lastTerminalEffect?.result == .cancelled(context: resultContext))
    #expect(terminalProjection.activeEffectProgress == nil)
    #expect(terminalProjection.lastTerminalEffect == settled.state.lastTerminalEffect)
    let terminal = try #require(settled.state.lastTerminalEffect)
    #expect(try roundTrip(terminal) == terminal)
  }
}

@Suite("PlotterEpisodeModel provenance and outcome contracts")
struct PlotterEvidenceContractTests {
  @Test("simulated provenance can never be promoted to live physical evidence")
  func simulatedEvidenceBoundary() {
    #expect(throws: PlotterEvidenceBoundaryError.simulatedInputCannotBecomeLivePhysicalEvidence) {
      _ = try PlotterEvidence(
        id: Fixtures.evidenceID,
        episodeID: Fixtures.episodeID,
        subject: .observation(Fixtures.observationID),
        question: .drawingOutcome,
        inputEnvironment: .simulated,
        evidenceClass: .livePhysical,
        acceptedBy: EpisodeAuthorityID(rawValue: "evidence-owner"),
        acceptedAt: Date(timeIntervalSince1970: 30),
        applicabilityRevision: revision("applicability-v1")
      )
    }
  }

  @Test("observation, measurement, evidence, outcome, and assessment preserve provenance")
  func provenanceRoundTrips() throws {
    let observationContext = PlotterObservationContext(
      id: Fixtures.observationID,
      observedAt: Date(timeIntervalSince1970: 10),
      environment: .live,
      source: .camera,
      sourceRevision: revision("camera-source-v1"),
      configurationRevision: revision("camera-config-v5"),
      artifactReferences: [Fixtures.frameArtifact]
    )
    let observation = PlotterObservation.cameraFrame(try PlotterCameraFrameObservation(
      context: observationContext,
      configurationID: Fixtures.cameraConfigurationID,
      pixelWidth: 1920,
      pixelHeight: 1080
    ))
    let measurement = PlotterMeasurement.projectedPoint(try PlotterProjectedPointMeasurement(
      context: try PlotterMeasurementContext(
        id: Fixtures.measurementID,
        computedAt: Date(timeIntervalSince1970: 20),
        sourceObservationIDs: [Fixtures.observationID],
        algorithmRevision: revision("projection-v2"),
        modelRevision: revision("model-v3"),
        diagnosticQualifications: ["inside accepted applicability"]
      ),
      machinePoint: try Point2(x: 4, y: 5),
      uncertaintyRadiusMM: 0.2
    ))
    let evidence = try PlotterEvidence(
      id: Fixtures.evidenceID,
      episodeID: Fixtures.episodeID,
      subject: .measurement(Fixtures.measurementID),
      question: .pointIdentity,
      inputEnvironment: .live,
      evidenceClass: .livePhysical,
      acceptedBy: EpisodeAuthorityID(rawValue: "evidence-owner"),
      acceptedAt: Date(timeIntervalSince1970: 30),
      applicabilityRevision: revision("applicability-v1"),
      artifactReferences: [Fixtures.frameArtifact]
    )
    let outcome = PlotterEpisodeOutcome(
      id: Fixtures.outcomeID,
      episodeID: Fixtures.episodeID,
      disposition: .completed,
      acceptedEvidenceIDs: [Fixtures.evidenceID],
      recordedAt: Date(timeIntervalSince1970: 40),
      summary: "The declared episode outcome completed."
    )
    let assessment = PlotterAssessment(
      id: Fixtures.assessmentID,
      episodeID: Fixtures.episodeID,
      outcomeID: Fixtures.outcomeID,
      goalRevision: revision("goal-v1"),
      assessedAt: Date(timeIntervalSince1970: 50),
      criteria: [
        PlotterCriterionAssessment(
          criterionID: Fixtures.criterionID,
          disposition: .satisfied,
          evidenceIDs: [Fixtures.evidenceID],
          summary: "Accepted evidence satisfies the criterion."
        )
      ]
    )

    requireValueContract(observation)
    requireValueContract(measurement)
    requireValueContract(evidence)
    requireValueContract(outcome)
    requireValueContract(assessment)
    #expect(try roundTrip(observation) == observation)
    #expect(try roundTrip(measurement) == measurement)
    #expect(try roundTrip(evidence) == evidence)
    #expect(try roundTrip(outcome) == outcome)
    #expect(try roundTrip(assessment) == assessment)
    #expect(observation.context.artifactReferences == [Fixtures.frameArtifact])
    #expect(measurement.context.sourceObservationIDs == [Fixtures.observationID])
    #expect(evidence.subject == .measurement(Fixtures.measurementID))
    #expect(outcome.acceptedEvidenceIDs == [Fixtures.evidenceID])
    #expect(assessment.criteria[0].evidenceIDs == [Fixtures.evidenceID])
  }

  @Test("effect result vocabulary is typed across every terminal disposition")
  func typedEffectResults() {
    let context = PlotterEffectResultContext(
      episodeID: Fixtures.episodeID,
      requestID: Fixtures.requestID,
      intent: .session(.begin),
      effectID: Fixtures.effectID,
      environment: .live,
      effectRevision: revision("effect-v1")
    )
    let results: [PlotterEffectResult] = [
      .completed(context: context, output: .sessionPrepared),
      .refused(context: context, refusal: PlotterEffectRefusal(
        requirementID: PlotterIntentRequirement.motionEnabled.id,
        owner: EpisodeAuthorityID(rawValue: "controller-owner"),
        comparedRevision: revision("motion-v2"),
        remedy: "Enable Motion."
      )),
      .cancelled(context: context),
      .ambiguous(context: context, ambiguity: PlotterEffectAmbiguity(
        summary: "Possible ink remains unresolved.",
        observationIDs: [Fixtures.observationID],
        possibleInk: true
      )),
      .timedOut(context: context, deadline: Date(timeIntervalSince1970: 60)),
      .evidenceUnavailable(context: context, reason: "Exact frame bytes are missing."),
      .failed(context: context, failure: PlotterEffectFailure(
        code: .environmentFailure,
        owner: EpisodeAuthorityID(rawValue: "environment-owner"),
        summary: "The environment failed."
      )),
    ]

    #expect(results.count == 7)
    #expect(results.allSatisfy { $0.context == context })
    #expect(results.map(\.disposition) == PlotterEffectTerminalDisposition.allCases)
  }

  @Test("progress vocabulary round-trips complete attributable observability fields")
  func progressVocabulary() throws {
    let intent = PlotterIntent.drawing(.execute(planRevisionID: Fixtures.planRevisionID))
    let phases = PlotterEffectProgressPhase.allCases
    let cancellationPhases = PlotterEffectCancellationPhase.allCases
    let values = try phases.enumerated().map { index, phase in
      try PlotterEffectProgress(
        episodeID: Fixtures.episodeID,
        requestID: Fixtures.requestID,
        intent: intent,
        effectID: Fixtures.effectID,
        effectRevision: revision("drawing-effect-v3"),
        environment: .simulated,
        lane: .machine,
        owningSubsystem: .machineController,
        phase: phase,
        startedAt: Date(timeIntervalSince1970: 20),
        lastAttributableProgressAt: Date(timeIntervalSince1970: 20 + Double(index)),
        resultCurrentlyAwaited: .drawingCompletion,
        deadline: Date(timeIntervalSince1970: 40),
        cancellation: PlotterEffectCancellationStatus(
          availability: index == 0 ? .unavailable : .available,
          phase: cancellationPhases[min(index, cancellationPhases.count - 1)]
        )
      )
    }

    #expect(phases == [.waiting, .progressing, .cancelling, .settling, .suspectedStall])
    #expect(PlotterEffectCancellationAvailability.allCases == [.unavailable, .available])
    #expect(cancellationPhases == [.notRequested, .requested, .observed, .settling])
    #expect(values.allSatisfy { $0.episodeID == Fixtures.episodeID })
    #expect(values.allSatisfy { $0.requestID == Fixtures.requestID })
    #expect(values.allSatisfy { $0.intent == intent })
    #expect(values.allSatisfy { $0.effectID == Fixtures.effectID })
    #expect(values.allSatisfy { $0.effectRevision == revision("drawing-effect-v3") })
    #expect(values.allSatisfy { $0.environment == .simulated })
    #expect(values.allSatisfy { $0.lane == .machine })
    #expect(values.allSatisfy { $0.owningSubsystem == .machineController })
    #expect(values.allSatisfy { $0.resultCurrentlyAwaited == .drawingCompletion })
    #expect(values.allSatisfy { $0.deadline == Date(timeIntervalSince1970: 40) })
    for value in values {
      requireValueContract(value)
      #expect(try roundTrip(value) == value)
    }
    #expect(throws: PlotterEffectProgressValidationError.progressPrecedesStart) {
      _ = try PlotterEffectProgress(
        episodeID: Fixtures.episodeID,
        requestID: Fixtures.requestID,
        intent: intent,
        effectID: Fixtures.effectID,
        effectRevision: revision("drawing-effect-v3"),
        environment: .live,
        lane: .machine,
        owningSubsystem: .machineController,
        phase: .progressing,
        startedAt: Date(timeIntervalSince1970: 20),
        lastAttributableProgressAt: Date(timeIntervalSince1970: 19),
        resultCurrentlyAwaited: .drawingCompletion,
        cancellation: PlotterEffectCancellationStatus(
          availability: .unavailable,
          phase: .notRequested
        )
      )
    }
  }

  @Test("projection is an immutable copied view with comparable runtime and UI revisions")
  func immutableProjection() {
    let refusal = PlotterIntentRefusalRecord(
      requestID: Fixtures.requestID,
      intent: .session(.begin),
      comparedStateRevision: EpisodeStateRevision(rawValue: 7),
      comparedCapabilityFacts: [],
      failedRequirements: [
        IntentRequirementRefusal(
          requirementID: PlotterIntentRequirement.sessionIdle.id,
          owner: EpisodeAuthorityID(rawValue: "PlotterEpisodeModel"),
          comparedCapabilityFacts: [],
          remedy: "Finish the current session."
        )
      ]
    )
    let state = PlotterEpisodeState(
      episodeID: Fixtures.episodeID,
      revision: EpisodeStateRevision(rawValue: 7),
      canonicalDigest: digest("state-7"),
      phase: .ready,
      lastRefusal: refusal,
      lastCommittedAt: Date(timeIntervalSince1970: 70)
    )
    let projection = PlotterEpisodeProjector.project(
      state: state,
      availabilities: [],
      revision: PlotterProjectionRevision(rawValue: 3),
      projectedAt: Date(timeIntervalSince1970: 80)
    )

    #expect(projection.runtimeStateRevision == EpisodeStateRevision(rawValue: 7))
    #expect(projection.projectionRevision == PlotterProjectionRevision(rawValue: 3))
    #expect(projection.currentReason == PlotterIntentRequirement.sessionIdle.id.rawValue)
    #expect(projection.authoritativeOwner == EpisodeAuthorityID(rawValue: "PlotterEpisodeModel"))
    #expect(projection.remedy == "Finish the current session.")
  }
}

@Suite("PlotterEpisodeModel package boundary")
struct PlotterEpisodePackageBoundaryTests {
  @Test("target is internal and depends inward only on EpisodeCore and PlotterModel")
  func internalDependencyTopology() throws {
    let root = repositoryRoot()
    let manifest = try String(
      contentsOf: root.appendingPathComponent("Package.swift"),
      encoding: .utf8
    )
    #expect(manifest.contains(
      ".target(\n      name: \"PlotterEpisodeModel\",\n      dependencies: [\"EpisodeCore\", \"PlotterModel\"]\n    )"
    ))
    #expect(!manifest.contains(".library(name: \"PlotterEpisodeModel\""))
    #expect(manifest.contains(
      ".testTarget(\n      name: \"PlotterEpisodeModelContractTests\""
    ))
  }

  @Test("source contains values and pure functions, not executable authority")
  func noEmbeddedExecutableAuthority() throws {
    let sourceDirectory = repositoryRoot()
      .appendingPathComponent("Sources/PlotterEpisodeModel", isDirectory: true)
    let files = try FileManager.default.contentsOfDirectory(
      at: sourceDirectory,
      includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "swift" }
    let source = try files.sorted { $0.lastPathComponent < $1.lastPathComponent }
      .map { try String(contentsOf: $0, encoding: .utf8) }
      .joined(separator: "\n")
    let forbidden = [
      "import PlotterRuntime",
      "import PlotterApp",
      "import SwiftUI",
      "import AppKit",
      "import AVFoundation",
      "EffectPermit",
      "@unchecked Sendable",
      "withCheckedContinuation",
      "withUnsafeContinuation",
      "Task {",
      "public actor ",
      "public protocol PlotterEffectPort",
    ]

    for token in forbidden {
      #expect(!source.contains(token), "Forbidden executable authority token: \(token)")
    }
    let imports = source.split(separator: "\n")
      .filter { $0.hasPrefix("import ") }
      .map(String.init)
    #expect(Set(imports).isSubset(of: Set([
      "import EpisodeCore",
      "import Foundation",
      "import PlotterModel",
    ])))
  }
}

private enum Fixtures {
  static let episodeID = EpisodeID(rawValue: uuid(1))
  static let definitionID = EpisodeDefinitionID(rawValue: uuid(2))
  static let manifestID = EpisodeManifestID(rawValue: uuid(3))
  static let requestID = IntentRequestID(rawValue: uuid(4))
  static let effectID = EpisodeEffectID(rawValue: uuid(5))
  static let eventID = EpisodeEventID(rawValue: uuid(6))
  static let correlationID = EpisodeCorrelationID(rawValue: uuid(7))
  static let observationID = PlotterObservationID(rawValue: uuid(8))
  static let measurementID = PlotterMeasurementID(rawValue: uuid(9))
  static let evidenceID = PlotterEvidenceID(rawValue: uuid(10))
  static let outcomeID = PlotterOutcomeID(rawValue: uuid(11))
  static let assessmentID = PlotterAssessmentID(rawValue: uuid(12))
  static let programID = ProgramID(uuid(13))
  static let cameraConfigurationID = CameraConfigurationID(uuid(14))
  static let calibrationRevisionID = DrawingRegistrationRevisionID(uuid(15))
  static let modelRevisionID = DrawingModelRevisionID(uuid(16))
  static let planRevisionID = ExecutionPlanRevisionID(try! plotterDigest(17))
  static let criterionID = EpisodeAssessmentCriterionID(rawValue: "accepted-outcome")
  static let frameArtifact = EpisodeArtifactReference(
    id: EpisodeArtifactID(rawValue: "frame-artifact"),
    revision: revision("frame-v1"),
    digest: "frame-digest"
  )
}

private func readyState(
  observationIDs: [PlotterObservationID] = []
) -> PlotterEpisodeState {
  PlotterEpisodeState(
    episodeID: Fixtures.episodeID,
    revision: EpisodeStateRevision(rawValue: 7),
    canonicalDigest: digest("state-7"),
    phase: .ready,
    currentPlanRevisionID: Fixtures.planRevisionID,
    observationIDs: observationIDs
  )
}

private func selectionRequest() -> PlotterPointSelectionRequest {
  PlotterPointSelectionRequest(
    id: PlotterPointSelectionID(rawValue: uuid(20)),
    frame: PlotterExactFrameReference(
      frameID: "frame-20",
      frameSHA256: String(repeating: "a", count: 64),
      source: .live(deviceID: "camera-1"),
      cameraConfigurationID: Fixtures.cameraConfigurationID,
      captureNanoseconds: 20,
      sequence: 1,
      width: 640,
      height: 480,
      rowBytes: 2_560,
      pixelFormat: .rgba8
    ),
    sourceObservationID: Fixtures.observationID,
    presentationTransformRevision: PlotterPresentationTransformRevision(rawValue: uuid(21)),
    prompt: "Select the exact-frame point.",
    purpose: .toolContact,
    requiredPointCount: 4
  )
}

private func readyFacts() throws -> [PlotterCapabilityFact] {
  let controller = EpisodeAuthorityID(rawValue: "controller-owner")
  return [
    .connection(PlotterConnectionFact(
      owner: controller,
      revision: CapabilityFactRevision(rawValue: 31),
      environment: .live,
      isConnected: true
    )),
    .motion(PlotterMotionFact(
      owner: controller,
      revision: CapabilityFactRevision(rawValue: 32),
      environment: .live,
      isEnabled: true
    )),
    .pose(PlotterPoseFact(
      owner: controller,
      revision: CapabilityFactRevision(rawValue: 33),
      environment: .live,
      machinePosition: try Point2(x: 1, y: 1),
      isSettled: true,
      settlementPolicyRevision: revision("pose-settlement-v1")
    )),
    .manualController(PlotterManualControllerFact(
      owner: controller,
      revision: CapabilityFactRevision(rawValue: 38),
      environment: .live,
      penState: .raised,
      operationIsActive: false,
      penActuationProfileRevision: revision("pen-profile-v1")
    )),
    .camera(PlotterCameraFact(
      owner: EpisodeAuthorityID(rawValue: "camera-owner"),
      revision: CapabilityFactRevision(rawValue: 34),
      configurationID: Fixtures.cameraConfigurationID,
      configurationRevision: revision("camera-config-v5"),
      isAvailable: true,
      exactFrameAvailable: true
    )),
    .executionPlan(PlotterExecutionPlanFact(
      owner: EpisodeAuthorityID(rawValue: "plan-owner"),
      revision: CapabilityFactRevision(rawValue: 35),
      currentRevisionID: Fixtures.planRevisionID
    )),
    .evidence(PlotterEvidenceFact(
      owner: EpisodeAuthorityID(rawValue: "evidence-owner"),
      revision: CapabilityFactRevision(rawValue: 36),
      authorityRevision: revision("evidence-v2"),
      availableQuestions: PlotterEvidenceQuestion.allCases
    )),
    .outcome(PlotterOutcomeFact(
      owner: EpisodeAuthorityID(rawValue: "outcome-owner"),
      revision: CapabilityFactRevision(rawValue: 37),
      availableOutcomeIDs: [Fixtures.outcomeID]
    )),
  ]
}

private func makeEvent(
  preRevision: EpisodeStateRevision,
  postRevision: EpisodeStateRevision,
  payload: PlotterEpisodeEventPayload,
  digest digestValue: String
) -> PlotterEpisodeEvent {
  PlotterEpisodeEvent(
    id: Fixtures.eventID,
    episodeID: Fixtures.episodeID,
    sequence: EpisodeEventSequence(rawValue: preRevision.rawValue),
    recordedAt: Date(timeIntervalSince1970: 100),
    actor: EpisodeEventActor(
      id: EpisodeActorID(rawValue: "plotter-test"),
      origin: .system
    ),
    correlationID: Fixtures.correlationID,
    preStateRevision: preRevision,
    postStateRevision: postRevision,
    payload: payload,
    postStateDigest: digest(digestValue)
  )
}

private func revision(_ value: String) -> EpisodeRevisionIdentifier {
  EpisodeRevisionIdentifier(rawValue: value)
}

private func digest(_ value: String) -> EpisodeStateDigest {
  EpisodeStateDigest(rawValue: value)
}

private func plotterDigest(_ byte: UInt8) throws -> Digest {
  try Digest(bytes: Array(repeating: byte, count: Digest.byteCount))
}

private func uuid(_ value: UInt8) -> UUID {
  UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
}

private func roundTrip<Value>(_ value: Value) throws -> Value
where Value: Codable {
  try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
}

private func requireValueContract<Value>(_ value: Value)
where Value: Codable & Hashable & Sendable {
  _ = value
}

private func repositoryRoot() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}
