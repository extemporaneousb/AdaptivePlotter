import Foundation
import PlotterEpisodeModel
@testable import PlotterEpisodeRuntime
import PlotterModel
import PlotterUI
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Drawing Studio run episode", .serialized)
@MainActor
struct PlotterDrawingRunEpisodeTests {
  @Test("unresolved terminal construction retains staged geometry instead of a later draft")
  func unresolvedAttemptRetainsStagedPlan() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let gate = DrawingRunPlanGate()
    let harness = await drawingRunHarness(fixture: fixture, planGate: gate)
    let ready = await harness.runtime.synchronize(environment: .live)
    #expect(ready.retainedExecutionPlan == nil)
    let run = Task { await harness.runtime.submit(.init(projection: ready.projection, intent: .start)) }
    await gate.waitUntilStarted()
    let request = try #require(await gate.request)
    // Inject a malformed lower frontier: self-consistent progress for a larger
    // plan must fail terminal construction against this run's sealed intent.
    let count = request.plan.strokes.count + 1
    let invalid = DrawingPlanProgressSnapshot(operationID: request.operationID,
      planRevisionID: request.plan.revisionID, plannedStrokeCount: count, plannedSegmentCount: count,
      commandedStrokeCount: count, controllerCompletedStrokeCount: 0,
      submittedSegmentCount: count, controllerCompletedSegmentCount: 0,
      completedStrokeIDs: [], completedCheckpointIDs: [], activeStrokeID: nil, activeSegmentIndex: nil)
    await harness.interpreter.overrideDrawingOutcome(.possibleInk(progress: invalid,
      reason: .strokeRefused(.controllerRejected("synthetic malformed frontier")),
      penRaiseOutcome: .commandedAndSettled(command: .raise, commandedState: .up)))
    await gate.release(.possibleInk)
    let failed = await run.value
    guard case .intentPublicationIncomplete(let runID, _) = failed.snapshot.evidencePersistence else {
      Issue.record("Malformed lower progress did not preserve an unresolved durable attempt")
      return
    }
    #expect(failed.snapshot.activeRunID == nil)
    #expect(failed.snapshot.terminal == nil)
    #expect(failed.snapshot.retainedExecutionPlan == request.plan)
    #expect(await harness.evidence.archive.incompleteAttempts.first?.intent.plan == request.plan)
    let newer = try fixture.makePlan(catalogItemID: .circle, role: .ordinaryDrawing)
    #expect(newer.plan != request.plan)
    await harness.facts.replace(fixture.facts(plan: newer))
    let synchronized = await harness.runtime.synchronize(environment: .live)
    #expect(synchronized.retainedExecutionPlan == request.plan)
    let handoff = await harness.runtime.submit(.init(projection: synchronized.projection,
      intent: .beginNewRun(runID)))
    #expect(try drawingRunRefusal(handoff).reason == .runIdentityMismatch)
    #expect(handoff.snapshot.retainedExecutionPlan == request.plan)
    #expect(handoff.snapshot.noRedraw == failed.snapshot.noRedraw)

    let appFixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { appFixture.stores.remove() }
    let app = appFixture.application
    await app.drawingDraftSynchronizationTask?.value
    #expect(app.drawingDraftSnapshot.plan != request.plan)
    app.installDrawingRunSnapshot(failed.snapshot)
    #expect(app.drawingRunSnapshot == failed.snapshot)
    let presentation = app.drawingStudioPresentation
    #expect(presentation.drawingPreview?.plan == request.plan)
    #expect(!presentation.authoringIsEnabled)
    #expect(presentation.runState.showsActiveRunStatus)
    let diagnostics = WorkbenchDebugSnapshot(application: app, projection: app.testPlotterUIProjection().semantic)
    #expect(diagnostics.drawing.runID == runID)
    #expect(diagnostics.drawing.runPlanContentHash == request.plan.contentHash.description)
    #expect(diagnostics.drawing.retainedExecutionPlan == request.plan)
    #expect(diagnostics.drawing.terminalDisposition == "publicationIncomplete")
    if case .publicationIncomplete = presentation.runState {} else {
      Issue.record("The unresolved attempt did not retain its visible status")
    }
    await app.shutdown()
  }

  @Test("unordered ink matching preserves duplicates and resolves ambiguous epsilon matches")
  func inkPathMultiplicity() throws {
    let style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID())
    func stroke(y: Double) throws -> PlannedMachineStroke {
      try PlannedMachineStroke(logicalStrokeID: StrokeID(),
        path: Polyline(points: [Point2(x: 0, y: y), Point2(x: 1, y: y)]),
        style: style, semanticRole: .drawing, ordering: 0, endingCheckpointID: PlanCheckpointID())
    }
    let original = try [stroke(y: 0), stroke(y: 0), stroke(y: 2)]
    let same = try [stroke(y: 2), stroke(y: 0), stroke(y: 0)]
    let differentMultiplicity = try [stroke(y: 0), stroke(y: 2), stroke(y: 2)]
    #expect(PlotterDrawingRunRuntime.equivalentInkPaths(original, same))
    #expect(!PlotterDrawingRunRuntime.equivalentInkPaths(original, differentMultiplicity))
    let epsilon = DrawingRegionContainmentPolicy.numericalEpsilonMM
    let ambiguous = try [stroke(y: 0), stroke(y: 0.9 * epsilon)]
    let resolvable = try [stroke(y: 0.9 * epsilon), stroke(y: -0.9 * epsilon)]
    #expect(PlotterDrawingRunRuntime.equivalentInkPaths(ambiguous, resolvable))
  }

  @Test("synthetic run fixture preserves registration pixel geometry and exact optical identity")
  func fixtureOpticalIdentityMatchesOwnedFrames() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let optical = fixture.registration.applicability.opticalConfiguration
    for frame in [fixture.previewFrame, fixture.baselineFrame, fixture.postFrame] {
      #expect(frame.source == optical.source)
      #expect(frame.frame.width == optical.width)
      #expect(frame.frame.height == optical.height)
      #expect(frame.frame.pixelFormat == optical.pixelFormat)
      #expect(frame.frame.bytes.count == frame.frame.rowBytes * optical.height)
    }
    #expect(fixture.plan.registration == fixture.registration)
    #expect(fixture.facts().acceptedMovementBounds == fixture.drawableRegion.bounds)
  }

  @Test("retained draft preflight refreshes dependency failures and remedies after recovery")
  func retainedDraftReadinessFollowsCurrentDependencies() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let harness = await drawingRunHarness(fixture: fixture)
    let ready = await harness.runtime.synchronize(environment: .live)
    #expect(ready.readiness == .ready)
    for facts in [fixture.facts(learningComplete: false), fixture.facts(paperCurrent: false)] {
      await harness.facts.replace(facts)
      let unavailable = await harness.runtime.synchronize(environment: .live)
      #expect(unavailable.planIdentity == ready.planIdentity)
      let result = await harness.runtime.submit(.init(projection: unavailable.projection, intent: .start))
      let refusal = try drawingRunRefusal(result)
      #expect(result.snapshot.projection.runRevision == unavailable.projection.runRevision)
      if case .unavailable(let issue) = unavailable.readiness {
        #expect(issue.reason == refusal.reason)
        #expect(issue.remedy == refusal.remedy)
        #expect(issue.detail == refusal.detail)
      } else { Issue.record("Changed dependency retained stale Ready") }
      await harness.facts.replace(fixture.facts())
      #expect((await harness.runtime.synchronize(environment: .live)).readiness == .ready)
    }
    #expect(await harness.events.values.isEmpty)
  }

  @Test("canonical preflight admits Unknown and Down, then settles Up before any travel",
    arguments: [PenState.unknown, .down])
  func restoredPenStateNormalizesBeforeTravel(_ penState: PenState) async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let gate = DrawingRunHoldGate()
    let harness = await drawingRunHarness(fixture: fixture, normalizationGate: gate)
    await harness.interpreter.setPenState(penState)
    // The usual fixture is already at the observation point and correctly
    // requires no travel. Start elsewhere to exercise normalization before XY.
    await harness.interpreter.setPosition(try MachinePosition(
      x: fixture.finalPosition.point.x + 5, y: fixture.finalPosition.point.y))
    let initialFacts = fixture.facts()
    await harness.facts.replace(PlotterDrawingRunExternalFacts(environment: .live,
      interactiveLearningIsComplete: true, plan: fixture.plan, paperCoverageIsCurrent: true,
      displayedFrame: fixture.previewFrame, interpreter: await harness.interpreter.snapshot(),
      penActuationProfile: initialFacts.penActuationProfile,
      acceptedMovementBounds: fixture.drawableRegion.bounds))
    let ready = await harness.runtime.synchronize(environment: .live)
    #expect(ready.readiness == .ready)
    #expect(ready.retainedExecutionPlan == nil)
    let run = Task { await harness.runtime.submit(.init(projection: ready.projection, intent: .start)) }
    await gate.waitUntilHeld()
    #expect(await harness.events.values == ["stage-intent", "normalize"])
    let active = await harness.runtime.snapshot(environment: .live)
    #expect(active.retainedExecutionPlan == fixture.plan.plan)
    if case .unavailable(let issue) = active.readiness { #expect(issue.reason == .activeRunOwnsWorkflow) }
    else { Issue.record("Active run retained stale Ready admission") }
    await gate.release()
    let result = await run.value
    #expect(result.snapshot.terminal?.disposition == .succeeded)
    #expect(result.snapshot.retainedExecutionPlan == fixture.plan.plan)
    #expect(result.snapshot.retainedExecutionPlan == result.snapshot.terminal?.record.plan.executionPlan)
    let events = await harness.events.values
    #expect(Array(events.prefix(3)) == ["stage-intent", "normalize", "travel"])
    if case .unavailable(let issue) = result.snapshot.readiness { #expect(issue.reason == .terminalRequiresNewRunHandoff) }
    else { Issue.record("Terminal run retained stale Ready admission") }
  }

  @Test("border-first plans cannot redraw retained border-last ink on the same sheet",
    arguments: [false, true], [false, true])
  func borderReorderingRetainsNoRedraw(restored: Bool, regenerated: Bool) async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let program = try DrawingProgramCatalog.program(for: .rectangle,
      style: StrokeStyle(nominalLineWidth: 0.4,
        penProfileID: PenProfileID(fixture.registration.applicability.toolAssembly.rawValue)))
    let built = PlotterDrawingPlanningAdapter.buildDraft(program: program, machineCenter: nil,
      uniformScale: 0.02, rotationDegrees: 0, drawableRegion: fixture.drawableRegion,
      registration: fixture.registration, drawBorder: true,
      drawingBorderBounds: fixture.registration.applicabilityRectangle)
    let borderFirstProgram = try #require(built.program)
    let borderFirstPlan = try #require(built.plan)
    let reordered = Array(borderFirstProgram.strokes.dropFirst()) + [borderFirstProgram.strokes[0]]
    let borderLastProgram = try DrawingProgram(id: ProgramID(), fieldExtent: borderFirstProgram.fieldExtent,
      strokes: reordered.enumerated().map { index, stroke in
        LogicalStroke(id: stroke.id, path: stroke.path, style: stroke.style,
          semanticRole: stroke.semanticRole, ordering: UInt32(index))
      }, source: borderFirstProgram.source)
    let borderLastPlan = try DrawingPlanner.plan(program: borderLastProgram,
      placement: borderFirstPlan.placement, drawableRegion: fixture.drawableRegion,
      provenance: borderFirstPlan.provenance)
    func owned(_ program: DrawingProgram, _ plan: ExecutionPlanRevision) -> PlotterDrawingRunPlan {
      PlotterDrawingRunPlan(draftRevision: PlotterDrawingDraftRevision(rawValue: 2), program: program,
        placementID: UUID(), plan: plan, evidenceRole: .ordinaryDrawing,
        paperCoverage: fixture.plan.paperCoverage, registration: fixture.registration)
    }
    let before = owned(borderLastProgram, borderLastPlan)
    let after: PlotterDrawingRunPlan
    if regenerated {
      let style = try StrokeStyle(nominalLineWidth: 0.8,
        penProfileID: PenProfileID(fixture.registration.applicability.toolAssembly.rawValue))
      let regeneratedProgram = try DrawingProgram(id: ProgramID(), fieldExtent: borderFirstProgram.fieldExtent,
        strokes: borderFirstProgram.strokes.map {
          LogicalStroke(id: StrokeID(), path: $0.path, style: style,
            semanticRole: $0.semanticRole, ordering: $0.ordering)
        }, source: borderFirstProgram.source)
      let regeneratedPlan = try DrawingPlanner.plan(program: regeneratedProgram,
        placement: borderFirstPlan.placement, drawableRegion: fixture.drawableRegion,
        provenance: borderFirstPlan.provenance)
      #expect(Set(regeneratedPlan.strokes.map(\.logicalStrokeID)).isDisjoint(with: before.plan.strokes.map(\.logicalStrokeID)))
      #expect(regeneratedPlan.strokes.allSatisfy { $0.style.nominalLineWidth == 0.8 })
      after = owned(regeneratedProgram, regeneratedPlan)
    } else {
      after = owned(borderFirstProgram, borderFirstPlan)
    }
    let harness = await drawingRunHarness(fixture: fixture, facts: fixture.facts(plan: before), outcome: .cancelled)
    let ready = await harness.runtime.synchronize(environment: .live)
    let run = await harness.runtime.submit(.init(projection: ready.projection, intent: .start))
    let terminal = try #require(run.snapshot.terminal)
    #expect(run.snapshot.retainedExecutionPlan == before.plan)
    if restored {
      let archive = await harness.evidence.archive
      let reopened = await drawingRunHarness(fixture: fixture, facts: fixture.facts(plan: after),
        archiveLoadResult: .loaded(archive))
      let blocked = await reopened.runtime.synchronize(environment: .live)
      let result = await reopened.runtime.submit(.init(projection: blocked.projection, intent: .start))
      #expect(try drawingRunRefusal(result).reason == .planMayAlreadyContainInk)
      #expect(await reopened.events.values.isEmpty)
    } else {
      await harness.facts.replace(fixture.facts(plan: after))
      let held = await harness.runtime.synchronize(environment: .live)
      #expect(held.retainedExecutionPlan == before.plan)
      let next = await harness.runtime.submit(.init(projection: held.projection, intent: .beginNewRun(terminal.runID)))
      #expect(next.snapshot.retainedExecutionPlan == nil)
      let blocked = await harness.runtime.synchronize(environment: .live)
      let result = await harness.runtime.submit(.init(projection: blocked.projection, intent: .start))
      #expect(try drawingRunRefusal(result).reason == .planMayAlreadyContainInk)
      #expect(await harness.interpreter.planRequests.count == 1)
    }
  }
  @Test("authored plans do not bypass Learning or paper prerequisites")
  func authoringDoesNotAuthorizeRun() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    for learningComplete in [false, true] {
      let harness = await drawingRunHarness(fixture: fixture,
        facts: fixture.facts(learningComplete: learningComplete, paperCurrent: false))
      let current = await harness.runtime.synchronize(environment: .live)
      let result = await harness.runtime.submit(
        PlotterDrawingRunSubmission(projection: current.projection, intent: .start))
      let refusal = try drawingRunRefusal(result)
      #expect(refusal.reason == (learningComplete ? .paperCoverageNotCurrent : .learningIncomplete))
      if case .unavailable(let issue) = current.readiness {
        #expect(issue.reason == refusal.reason)
        #expect(issue.remedy == refusal.remedy)
        #expect(issue.detail == refusal.detail)
      } else { Issue.record("UI preflight differed from runtime refusal") }
      #expect(await harness.events.values.isEmpty)
      #expect(await harness.interpreter.planRequests.isEmpty)
      #expect(await harness.camera.requests.isEmpty)
      #expect(await harness.evidence.attempts.isEmpty)
    }
  }

  @Test("portrait follows ordinary execution observation and evidence persistence", arguments: [false, true])
  func portraitExecution(drawBorder: Bool) async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let program = try PortraitVectorizer.program(
      from: portraitTestRaster(), pose: .front, style: .hatch,
      strokeStyle: StrokeStyle(nominalLineWidth: 0.4,
        penProfileID: PenProfileID(fixture.registration.applicability.toolAssembly.rawValue)))
    let built = PlotterDrawingPlanningAdapter.buildDraft(
      program: program, machineCenter: try Point2(
        x: (fixture.registration.applicabilityRectangle.minX + fixture.registration.applicabilityRectangle.maxX)/2,
        y: (fixture.registration.applicabilityRectangle.minY + fixture.registration.applicabilityRectangle.maxY)/2),
      uniformScale: 0.02, rotationDegrees: 0,
      drawableRegion: fixture.drawableRegion, registration: fixture.registration,
      drawBorder: drawBorder, drawingBorderBounds: fixture.registration.applicabilityRectangle)
    let plan = PlotterDrawingRunPlan(
      draftRevision: PlotterDrawingDraftRevision(rawValue: 2), program: try #require(built.program),
      placementID: UUID(), plan: try #require(built.plan), evidenceRole: .ordinaryDrawing,
      paperCoverage: fixture.plan.paperCoverage, registration: fixture.registration)
    let harness = await drawingRunHarness(fixture: fixture, facts: fixture.facts(plan: plan))
    let current = await harness.runtime.synchronize(environment: .live)
    let result = await harness.runtime.submit(PlotterDrawingRunSubmission(projection: current.projection, intent: .start))
    let recordedEvents = await harness.events.values
    #expect(recordedEvents == [
      "stage-intent", "normalize", "travel", "capture-baseline", "stage-baseline", "dispatch-marker",
      "execute", "travel", "capture-post", "observe", "append",
    ])
    #expect(try #require(await harness.interpreter.planRequests.first).plan == plan.plan)
    let terminal = try #require(result.snapshot.terminal)
    #expect(terminal.disposition == .succeeded)
    #expect(terminal.record.program.contentHash == plan.program.contentHash)
    #expect(terminal.record.program.source == plan.program.source)
    let decoded = try JSONDecoder().decode(DrawingProgramEvidenceReference.self, from: JSONEncoder().encode(terminal.record.program))
    #expect(decoded.source == plan.program.source)
    #expect(terminal.record.plan.executionPlan?.strokes.count == program.strokes.count + (drawBorder ? 1 : 0))
    guard case .persisted = result.snapshot.evidencePersistence else {
      Issue.record("Portrait run evidence was not persisted by the ordinary evidence owner.")
      return
    }
  }

  @Test("same-paper material provenance changes preserve no-redraw in memory and after staged restart",
    arguments: [false, true])
  func provenanceOnlyPlanChangeRetainsPossibleInk(_ interruptedArchive: Bool) async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let harness = await drawingRunHarness(fixture: fixture, outcome: .cancelled)
    let ready = await harness.runtime.synchronize(environment: .live)
    let original = await harness.runtime.submit(.init(projection: ready.projection, intent: .start))
    let terminal = try #require(original.snapshot.terminal)
    let material = try DrawingMaterialProfileRevision(name: "Different selected revision", nominalWidthMM: 0.8)
    let revised = try fixture.withMaterial(material)
    #expect(revised.plan.contentHash != fixture.plan.plan.contentHash)
    #expect(revised.plan.strokes.map(\.path) == fixture.plan.plan.strokes.map(\.path))
    #expect(revised.registration.derivation == .accepted)
    if interruptedArchive {
      let sealed = await harness.evidence.archive
      let staged = try DrawingRunEvidenceArchive(archiveID: sealed.archiveID, revision: 0,
        records: [], attempts: sealed.attempts)
      #expect(staged.incompleteAttempts.first?.inkDispatchPossible == true)
      let restored = await drawingRunHarness(fixture: fixture, facts: fixture.facts(plan: revised),
        archiveLoadResult: .loaded(staged))
      let projection = await restored.runtime.synchronize(environment: .live)
      let refused = await restored.runtime.submit(.init(projection: projection.projection, intent: .start))
      #expect(try drawingRunRefusal(refused).reason == .planMayAlreadyContainInk)
      #expect(await restored.events.values.isEmpty)
    } else {
      _ = await harness.runtime.submit(.init(projection: original.snapshot.projection,
        intent: .beginNewRun(terminal.runID)))
      await harness.facts.replace(fixture.facts(plan: revised))
      let projection = await harness.runtime.synchronize(environment: .live)
      let effectsBefore = await harness.events.values
      let refused = await harness.runtime.submit(.init(projection: projection.projection, intent: .start))
      #expect(try drawingRunRefusal(refused).reason == .planMayAlreadyContainInk)
      #expect(await harness.events.values == effectsBefore)
    }
  }

  @Test("staged same-coordinate ink survives changed generator style and optical provenance")
  func stagedGeometrySurvivesUnrelatedProvenanceChanges() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let harness = await drawingRunHarness(fixture: fixture, outcome: .cancelled)
    let ready = await harness.runtime.synchronize(environment: .live)
    _ = await harness.runtime.submit(.init(projection: ready.projection, intent: .start))
    let sealed = await harness.evidence.archive
    let staged = try DrawingRunEvidenceArchive(archiveID: sealed.archiveID, revision: 0,
      records: [], attempts: sealed.attempts)
    let revised = try fixture.withChangedSourceStyleAndOpticalIdentity()
    #expect(revised.plan.strokes.map(\.path) == fixture.plan.plan.strokes.map(\.path))
    #expect(revised.program.source != fixture.plan.program.source)
    #expect(revised.plan.strokes.map(\.style) != fixture.plan.plan.strokes.map(\.style))
    #expect(revised.registration.applicability.opticalConfiguration != fixture.registration.applicability.opticalConfiguration)
    #expect(revised.registration.acceptedRevisionID != fixture.registration.acceptedRevisionID)
    let restored = await drawingRunHarness(fixture: fixture, facts: fixture.facts(plan: revised),
      archiveLoadResult: .loaded(staged))
    let current = await restored.runtime.synchronize(environment: .live)
    let refused = await restored.runtime.submit(.init(projection: current.projection, intent: .start))
    #expect(try drawingRunRefusal(refused).reason == .planMayAlreadyContainInk)
    #expect(await restored.events.values.isEmpty)
  }

  @Test("axis geometry revision preserves old-sheet ink even after moving the target; exact new paper clears it",
    arguments: [false, true])
  func axisGeometryChangeRequiresNewPhysicalSheet(_ interruptedArchive: Bool) async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let original = await drawingRunHarness(fixture: fixture, outcome: .cancelled)
    let ready = await original.runtime.synchronize(environment: .live)
    let run = await original.runtime.submit(.init(projection: ready.projection, intent: .start))
    let record = try #require(run.snapshot.terminal?.record)
    let sealed = await original.evidence.archive
    let attempt = try #require(sealed.attempts.first)
    #expect(attempt.inkDispatchPossible)
    #expect(record.executionFrontiers.commandedStrokeCount > 0)
    let baseline = try #require(attempt.baselines.first)
    let baselineBytes = try await original.evidence.readMedia(baseline)
    let terminalMedia = try #require(record.attemptEvidence?.terminalFrames.first)
    let terminalBytes = try await original.evidence.readMedia(terminalMedia)
    let archive = interruptedArchive
      ? try DrawingRunEvidenceArchive(archiveID: sealed.archiveID, revision: 0,
          records: [], attempts: sealed.attempts)
      : sealed
    let archiveEncoder = JSONEncoder()
    archiveEncoder.outputFormatting = [.sortedKeys]
    let archiveBytes = try archiveEncoder.encode(archive)

    // Synthetic accepted registration and a rebuilt plan represent completed
    // relearning under a new controller metric. This asserts software admission
    // and does not infer a physical transform for the old ink.
    let registration = try drawingRunRegistrationWithNewMachineGeometry(fixture.registration)
    #expect(registration.applicability.machineGeometry != fixture.registration.applicability.machineGeometry)
    let revised = try drawingRunGeometryRevisionPlan(fixture: fixture, registration: registration, shifted: false)
    #expect(revised.plan.provenance.registrationRevisionID.rawValue == registration.acceptedRevisionID.rawValue)
    let restored = await drawingRunHarness(fixture: fixture, facts: fixture.facts(plan: revised),
      archiveLoadResult: .loaded(archive))
    let shifted = try drawingRunGeometryRevisionPlan(fixture: fixture, registration: registration, shifted: true)
    #expect(shifted.plan.strokes.map(\.path) != revised.plan.strokes.map(\.path))
    for plan in [revised, shifted] {
      await restored.facts.replace(fixture.facts(plan: plan))
      let state = await restored.runtime.synchronize(environment: .live)
      guard case .unavailable(let issue) = state.readiness else {
        Issue.record("Changed geometry made the previously marked sheet ready.")
        return
      }
      #expect(issue.reason == .planMayAlreadyContainInk)
      #expect(issue.remedy == .replaceMarkedPaper)
      let rejected = await restored.runtime.submit(.init(projection: state.projection, intent: .start))
      let refusal = try drawingRunRefusal(rejected)
      #expect(refusal.reason == .planMayAlreadyContainInk)
      #expect(refusal.remedy == .replaceMarkedPaper)
    }
    #expect(await restored.events.values.isEmpty)
    #expect(await restored.interpreter.planRequests.isEmpty)
    #expect(await restored.camera.requests.isEmpty)
    #expect(await restored.evidence.attempts.isEmpty)

    let newPaper = PaperRevisionContext(instance: PaperInstanceRevision(), contactPlane: fixture.paper.contactPlane)
    let newSheetPlan = try drawingRunPlan(shifted, replacingPaper: newPaper)
    #expect(newSheetPlan.plan == shifted.plan)
    #expect(newSheetPlan.registration == shifted.registration)
    await restored.facts.replace(fixture.facts(plan: newSheetPlan))
    // Changing the plan's paper alone does not erase retained no-redraw truth.
    let beforePaperRestore = await restored.runtime.synchronize(environment: .live)
    if case .unavailable(let issue) = beforePaperRestore.readiness {
      #expect(issue.remedy == .replaceMarkedPaper)
    } else { Issue.record("Paper was cleared without the current-paper archive restore.") }
    _ = await restored.runtime.restoreNoRedrawTruth(from: archive, paper: newPaper, environment: .live)
    #expect((await restored.runtime.synchronize(environment: .live)).readiness == .ready)
    #expect(await restored.events.values.isEmpty)

    // Recovery changes current-paper filtering, never the old immutable record,
    // staged attempt, its physical-paper association, or owned image bytes.
    #expect(await original.evidence.archive == sealed)
    #expect(try archiveEncoder.encode(archive) == archiveBytes)
    #expect(attempt.intent.context.paper == fixture.paper)
    #expect(record.paper == fixture.paper)
    #expect(try await original.evidence.readMedia(baseline) == baselineBytes)
    #expect(try await original.evidence.readMedia(terminalMedia) == terminalBytes)
  }

  @Test("buffered frames predating settled observation boundaries cannot acquire pose identity",
    arguments: [false, true])
  func bufferedFrameBeforeObservationSettlementIsRejected(_ staleResult: Bool) async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let timing = DrawingRunSequenceClock(staleResult ? [10, 15, 35, 40] : [10, 25, 40])
    let harness = await drawingRunHarness(fixture: fixture, clock: timing)
    let ready = await harness.runtime.synchronize(environment: .live)
    let result = await harness.runtime.submit(.init(projection: ready.projection, intent: .start))
    let attempt = try #require(result.snapshot.terminal?.record.attemptEvidence)
    #expect(await harness.camera.requests == (staleResult ? [15, 35] : [25]))
    #expect(await harness.vision.requests.isEmpty)
    #expect(!result.snapshot.physicalEvidenceClaimed)
    if staleResult {
      #expect(attempt.baselines.first?.captureAfterNanoseconds == 15)
      #expect(attempt.terminalFrames.first?.frame == ExactFrameProvenance(frame: fixture.postFrame.frame))
      #expect(attempt.terminalFrames.first?.controllerPosition == nil)
      #expect(attempt.terminalFrames.first?.captureAfterNanoseconds == nil)
    } else {
      #expect(await harness.interpreter.planRequests.isEmpty)
      #expect(attempt.baselines.isEmpty)
    }
    #expect(try #require(attempt.missingCoverageReason).isEmpty == false)
  }

  @Test("failed terminal media installation retries exact owned bytes before sealing",
    arguments: [DrawingRunOutcomeKind.completed, .cancelled])
  func terminalMediaFailureRetainsOriginalForPublicationRetry(_ outcome: DrawingRunOutcomeKind) async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let harness = await drawingRunHarness(fixture: fixture, outcome: outcome)
    let originalFrame = outcome == .completed ? fixture.postFrame : fixture.previewFrame
    await harness.evidence.rejectMediaFrames([originalFrame.frame.id])
    let ready = await harness.runtime.synchronize(environment: .live)
    let failed = await harness.runtime.submit(.init(projection: ready.projection, intent: .start))
    let terminal = try #require(failed.snapshot.terminal)
    #expect(terminal.disposition == .publicationIncomplete)
    #expect(failed.snapshot.postFrame == originalFrame)
    #expect(await harness.evidence.archive.records.isEmpty)
    guard case .failed(let recordID, let capability, let detail) = failed.snapshot.evidencePersistence else {
      Issue.record("Available bytes were sealed away despite failed media installation")
      return
    }
    #expect(detail.contains("mediaFailed"))
    let refusedHandoff = await harness.runtime.submit(.init(projection: failed.snapshot.projection,
      intent: .beginNewRun(terminal.runID)))
    #expect(try drawingRunRefusal(refusedHandoff).remedy == .retryEvidencePublication)
    let stillFailed = await harness.runtime.submit(.init(projection: refusedHandoff.snapshot.projection,
      intent: .recoverPublication(capability)))
    #expect(stillFailed.snapshot.terminal?.disposition == .publicationIncomplete)
    #expect(stillFailed.snapshot.terminal?.record == terminal.record)
    let cameraBefore = await harness.camera.requests
    let plansBefore = await harness.interpreter.planRequests
    let motionEventsBefore = await harness.events.values.filter { ["normalize", "travel", "execute"].contains($0) }
    await harness.evidence.rejectMediaFrames([])
    let recovered = await harness.runtime.submit(.init(projection: stillFailed.snapshot.projection,
      intent: .recoverPublication(capability)))
    guard case .persisted(let savedID, _) = recovered.snapshot.evidencePersistence else {
      Issue.record("Restored storage did not seal retained exact media")
      return
    }
    #expect(savedID == recordID)
    #expect(recovered.snapshot.terminal?.record == terminal.record)
    let media = try #require(terminal.record.attemptEvidence?.terminalFrames.first)
    #expect(try await harness.evidence.readMedia(media) == originalFrame.frame)
    #expect(await harness.camera.requests == cameraBefore)
    #expect(await harness.interpreter.planRequests == plansBefore)
    #expect(await harness.events.values.filter { ["normalize", "travel", "execute"].contains($0) } == motionEventsBefore)
  }

  @Test("Stop stays latched when the admitted operation races to completed")
  func stopRacingCompletedOutcomeDoesNotPhotograph() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let gate = DrawingRunPlanGate()
    let harness = await drawingRunHarness(fixture: fixture, planGate: gate, releasePlanOnStop: false)
    let ready = await harness.runtime.synchronize(environment: .live)
    let run = Task { await harness.runtime.submit(.init(projection: ready.projection, intent: .start)) }
    await gate.waitUntilStarted()
    let active = await harness.runtime.snapshot(environment: .live)
    let stop = try #require(active.stopCapabilityID)
    _ = await harness.runtime.submit(.init(projection: active.projection, intent: .stop(stop)))
    await gate.release(.completed)
    let result = await run.value
    #expect(result.snapshot.terminal?.disposition == .cancelled)
    #expect(await harness.camera.requests.count == 1)
    #expect(await harness.vision.requests.isEmpty)
    let events = await harness.events.values
    #expect(Array(events.suffix(from: try #require(events.firstIndex(of: "execute")))).filter { $0 == "travel" }.isEmpty)
    let evidence = try #require(result.snapshot.terminal?.record.attemptEvidence)
    #expect(evidence.terminalFrames.contains { $0.frame == ExactFrameProvenance(frame: fixture.previewFrame.frame) })
    #expect(try #require(evidence.missingCoverageReason).isEmpty == false)
    #expect(evidence.mediaCoverage == nil)
    #expect(evidence.terminalFrames.allSatisfy { $0.controllerPosition == nil })
  }

  @Test("Stop cancels the exact owned result positioning effect and joins publication")
  func stopDuringResultPositioning() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let gate = DrawingRunHoldGate()
    let harness = await drawingRunHarness(fixture: fixture)
    await harness.interpreter.holdTravel(ordinal: 2, at: gate)
    let ready = await harness.runtime.synchronize(environment: .live)
    let run = Task { await harness.runtime.submit(.init(projection: ready.projection, intent: .start)) }
    await gate.waitUntilHeld()
    let active = await harness.runtime.snapshot(environment: .live)
    #expect(active.phase == .positioningForPostObservation)
    let stop = try #require(active.stopCapabilityID)
    _ = await harness.runtime.submit(.init(projection: active.projection, intent: .stop(stop)))
    let result = await run.value
    #expect(await harness.interpreter.stopIntents == [.operatorStop])
    #expect(await harness.camera.requests.count == 1)
    #expect(result.snapshot.terminal?.disposition == .cancelled)
    let attempt = try #require(result.snapshot.terminal?.record.attemptEvidence)
    #expect(try #require(attempt.missingCoverageReason).isEmpty == false)
    #expect(attempt.mediaCoverage == nil)
    #expect(attempt.terminalFrames.allSatisfy { $0.controllerPosition == nil })
    if case .persisted = result.snapshot.evidencePersistence {} else { Issue.record("Stop did not seal exact terminal evidence") }
  }

  @Test("failed and ambiguous execution never moves for a terminal photograph",
    arguments: [DrawingRunOutcomeKind.refused, .cancelled, .ambiguous, .possibleInk])
  func failedOutcomeDoesNotReposition(_ outcome: DrawingRunOutcomeKind) async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let harness = await drawingRunHarness(fixture: fixture, outcome: outcome)
    let ready = await harness.runtime.synchronize(environment: .live)
    let result = await harness.runtime.submit(.init(projection: ready.projection, intent: .start))
    let events = await harness.events.values
    let execution = try #require(events.firstIndex(of: "execute"))
    #expect(!events.suffix(from: execution).contains("travel"))
    #expect(await harness.camera.requests.count == 1)
    #expect(await harness.vision.requests.isEmpty)
    let attempt = try #require(result.snapshot.terminal?.record.attemptEvidence)
    #expect(attempt.terminalFrames.count == 1)
    #expect(attempt.terminalFrames.first?.controllerPosition == nil)
    #expect(attempt.mediaCoverage == nil)
    #expect(try #require(attempt.missingCoverageReason).isEmpty == false)
  }

  @Test("staging failure prevents ink dispatch and keeps the exact failure recoverable", arguments: [false, true])
  func stagedPersistenceFailurePreventsInk(_ baselineFailure: Bool) async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let harness = await drawingRunHarness(fixture: fixture,
      stageFailures: baselineFailure ? 0 : 1, stageBaselineFailures: baselineFailure ? 1 : 0)
    let ready = await harness.runtime.synchronize(environment: .live)
    let result = await harness.runtime.submit(.init(projection: ready.projection, intent: .start))
    #expect(await harness.interpreter.planRequests.isEmpty)
    #expect(await harness.vision.requests.isEmpty)
    let events = await harness.events.values
    #expect(!events.contains("dispatch-marker"))
    if !baselineFailure { #expect(!events.contains("normalize")) }
    let record = try #require(result.snapshot.terminal?.record)
    #expect(record.executionFrontiers.commandedStrokeCount == 0)
    #expect(record.evidenceDisposition == .refused)
    #expect(record.attemptEvidence?.missingCoverageReason?.contains("stageFailed") == true)
    #expect(record.attemptEvidence?.baselines.count == (baselineFailure ? 1 : 0))
  }

  @Test("dispatch acknowledgement failure retains possible ink after terminal seal and restart")
  func markerAcknowledgementFailureRetainsNoRedraw() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let harness = await drawingRunHarness(fixture: fixture, failDispatchAcknowledgement: true)
    let ready = await harness.runtime.synchronize(environment: .live)
    let result = await harness.runtime.submit(.init(projection: ready.projection, intent: .start))
    #expect(await harness.interpreter.planRequests.isEmpty)
    #expect(result.snapshot.terminal?.record.executionFrontiers.commandedStrokeCount == 0)
    if case .planMayContainInk = result.snapshot.noRedraw {} else { Issue.record("Uncertain dispatch marker released no-redraw") }
    let archive = await harness.evidence.archive
    #expect(archive.records.count == 1)
    #expect(archive.incompleteAttempts.isEmpty)
    #expect(archive.attempts.first?.inkDispatchPossible == true)
    let restored = await drawingRunHarness(fixture: fixture, archiveLoadResult: .loaded(archive))
    let state = await restored.runtime.synchronize(environment: .live)
    let refused = await restored.runtime.submit(.init(projection: state.projection, intent: .start))
    #expect(try drawingRunRefusal(refused).reason == .planMayAlreadyContainInk)
    #expect(await restored.events.values.isEmpty)
  }

  @Test("restart retains marked incomplete attempts as possible ink without replay")
  func interruptedAttemptRestoresNoRedraw() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let gate = DrawingRunPlanGate()
    let harness = await drawingRunHarness(fixture: fixture, planGate: gate)
    let ready = await harness.runtime.synchronize(environment: .live)
    let run = Task { await harness.runtime.submit(.init(projection: ready.projection, intent: .start)) }
    await gate.waitUntilStarted()
    let archive = await harness.evidence.archive
    #expect(archive.incompleteAttempts.count == 1)
    #expect(archive.incompleteAttempts.first?.interruptionClassification == .possibleInk)
    let restored = await drawingRunHarness(fixture: fixture, archiveLoadResult: .loaded(archive))
    let restoredReady = await restored.runtime.synchronize(environment: .live)
    let refused = await restored.runtime.submit(.init(projection: restoredReady.projection, intent: .start))
    #expect(try drawingRunRefusal(refused).reason == .planMayAlreadyContainInk)
    #expect(await restored.events.values.isEmpty)
    await gate.release(.cancelled)
    _ = await run.value
  }

  @Test("exact projection and complete facts are revalidated before effects")
  func exactPlanAndFactRevalidation() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let staleHarness = await drawingRunHarness(fixture: fixture)
    let old = await staleHarness.runtime.synchronize(environment: .live)
    let replacement = try fixture.makePlan(catalogItemID: .triangle)
    await staleHarness.facts.replace(fixture.facts(plan: replacement))
    let requestID = PlotterDrawingRunRequestID()
    let stale = await staleHarness.runtime.submit(PlotterDrawingRunSubmission(
      requestID: requestID,
      projection: old.projection,
      intent: .start
    ))
    let staleRefusal = try drawingRunRefusal(stale)
    #expect(staleRefusal.requestID == requestID)
    #expect(staleRefusal.owner.rawValue == "PlotterDrawingRunRuntime")
    #expect(staleRefusal.reason == .staleProjection)
    #expect(staleRefusal.remedy == .useCurrentProjection)
    #expect(await staleHarness.interpreter.planRequests.isEmpty)

    let gate = DrawingRunHoldGate()
    let harness = await drawingRunHarness(fixture: fixture, normalizationGate: gate)
    let current = await harness.runtime.synchronize(environment: .live)
    let run = Task {
      await harness.runtime.submit(PlotterDrawingRunSubmission(
        projection: current.projection,
        intent: .start
      ))
    }
    await gate.waitUntilHeld()
    await harness.facts.replace(fixture.facts(paperCurrent: false))
    await gate.release()
    let result = await run.value

    #expect(result.snapshot.terminal?.disposition == .refused)
    #expect(result.snapshot.terminal?.record.requestFrontier == .validated)
    #expect(result.snapshot.terminal?.record.evidenceDisposition == .refused)
    #expect(await harness.interpreter.planRequests.isEmpty)
    #expect(await harness.camera.requests.isEmpty)
    #expect(await harness.vision.requests.isEmpty)
    #expect(await harness.events.values == ["stage-intent", "normalize", "append"])
  }

  @Test("Pen profile drift before the first effect is typed and effect-free")
  func penProfileDriftBeforeFirstEffect() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let factGate = DrawingRunHoldGate()
    let harness = await drawingRunHarness(fixture: fixture)
    let current = await harness.runtime.synchronize(environment: .live)
    await harness.facts.holdNextAcquisition(at: factGate)

    let start = Task {
      await harness.runtime.submit(PlotterDrawingRunSubmission(
        projection: current.projection,
        intent: .start
      ))
    }
    await factGate.waitUntilHeld()
    let changedProfile = PenActuationProfile(
      raisedSpindleValue: 75,
      loweredSpindleValue: 825,
      settleSeconds: 0.3
    )
    await harness.facts.replace(fixture.facts(penActuationProfile: changedProfile))
    await factGate.release()
    let result = await start.value

    let refusal = try drawingRunRefusal(result)
    #expect(refusal.owner.rawValue == "RunInterpreter")
    #expect(refusal.reason == .penActuationProfileChanged)
    #expect(refusal.remedy == .reviewPenActuationProfile)
    #expect(result.snapshot.activeRunID == nil)
    #expect(result.snapshot.terminal == nil)
    #expect(await harness.interpreter.planRequests.isEmpty)
    #expect(await harness.interpreter.stopIntents.isEmpty)
    #expect(await harness.camera.requests.isEmpty)
    #expect(await harness.vision.requests.isEmpty)
    #expect(await harness.evidence.attempts.isEmpty)
    #expect(await harness.events.values.isEmpty)
  }

  @Test("shutdown closes held start before any lower effect")
  func shutdownClosesHeldStartBeforeEffects() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let factGate = DrawingRunHoldGate()
    let harness = await drawingRunHarness(fixture: fixture)
    let current = await harness.runtime.synchronize(environment: .live)
    await harness.facts.holdNextAcquisition(at: factGate)

    let start = Task {
      await harness.runtime.submit(PlotterDrawingRunSubmission(
        projection: current.projection,
        intent: .start
      ))
    }
    await factGate.waitUntilHeld()
    _ = await harness.runtime.beginShutdown(environment: .live)
    await factGate.release()
    let result = await start.value

    let refusal = try drawingRunRefusal(result)
    #expect(refusal.owner.rawValue == "PlotterDrawingRunRuntime")
    #expect(refusal.reason == .admissionClosed)
    #expect(refusal.remedy == .restartApplication)
    #expect(result.snapshot.activeRunID == nil)
    #expect(result.snapshot.terminal == nil)
    #expect(await harness.interpreter.planRequests.isEmpty)
    #expect(await harness.interpreter.stopIntents.isEmpty)
    #expect(await harness.camera.requests.isEmpty)
    #expect(await harness.vision.requests.isEmpty)
    #expect(await harness.evidence.attempts.isEmpty)
    #expect(await harness.events.values.isEmpty)
  }

  @Test("shutdown owns admitted-run Stop and returns only after terminal publication")
  func shutdownAwaitsAdmittedRunQuiescence() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let planGate = DrawingRunPlanGate()
    let harness = await drawingRunHarness(fixture: fixture, planGate: planGate)
    let current = await harness.runtime.synchronize(environment: .live)

    let start = Task {
      await harness.runtime.submit(PlotterDrawingRunSubmission(
        projection: current.projection,
        intent: .start
      ))
    }
    await planGate.waitUntilStarted()

    let shutdown = Task {
      await harness.runtime.beginShutdown(environment: .live)
    }
    let shutdownSnapshot = await shutdown.value
    let submissionResult = await start.value

    #expect(await harness.interpreter.stopIntents == [.shutdown])
    #expect(await harness.interpreter.planRequests.count == 1)
    #expect(await harness.evidence.attempts.count == 1)
    #expect(shutdownSnapshot.activeRunID == nil)
    #expect(shutdownSnapshot.phase == .terminal)
    #expect(shutdownSnapshot.terminal?.disposition == .cancelled)
    #expect(
      shutdownSnapshot.terminal?.record.executionDisposition
        == .cancelled(reason: "Application shutdown")
    )
    #expect(submissionResult.snapshot == shutdownSnapshot)
  }

  @Test("baseline execute post observe and append retain exact identities in order")
  func completeRunOrderingAndIdentity() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let harness = await drawingRunHarness(fixture: fixture)
    let current = await harness.runtime.synchronize(environment: .live)
    let requestID = PlotterDrawingRunRequestID()
    let result = await harness.runtime.submit(PlotterDrawingRunSubmission(
      requestID: requestID,
      projection: current.projection,
      intent: .start
    ))

    #expect(await harness.events.values == [
      "stage-intent", "normalize", "travel", "capture-baseline", "stage-baseline", "dispatch-marker",
      "execute", "travel", "capture-post", "observe", "append",
    ])
    let request = try #require(await harness.interpreter.planRequests.first)
    let terminal = try #require(result.snapshot.terminal)
    #expect(request.operationID.rawValue == requestID.rawValue)
    #expect(request.plan == fixture.plan.plan)
    #expect(terminal.planIdentity == fixture.plan.identity)
    #expect(terminal.record.requestID == requestID.rawValue)
    #expect(terminal.record.runID == terminal.runID)
    #expect(terminal.record.role == .ordinaryDrawing)
    #expect(terminal.record.plan.contentHash == fixture.plan.plan.contentHash)
    #expect(terminal.record.requestFrontier == .admitted)
    #expect(terminal.record.evidenceDisposition == .attributable)
    #expect(terminal.disposition == .succeeded)
    #expect(result.snapshot.physicalEvidenceClaimed)
    #expect(result.snapshot.baselineFrame == fixture.baselineFrame)
    #expect(result.snapshot.postFrame == fixture.postFrame)
    let attempt = try #require(terminal.record.attemptEvidence)
    let observationPlan = try #require(attempt.intent.observationPlan)
    let pose = try #require(observationPlan.poses.first)
    let baselineMedia = try #require(attempt.baselines.first)
    let postMedia = try #require(attempt.terminalFrames.first)
    #expect(observationPlan.poses.count == 1)
    #expect(baselineMedia.frame == ExactFrameProvenance(frame: fixture.baselineFrame.frame))
    #expect(baselineMedia.captureAfterNanoseconds == 10)
    #expect(postMedia.captureAfterNanoseconds == fixture.baselineFrame.frame.captureNanoseconds)
    #expect(baselineMedia.frame.captureNanoseconds > (baselineMedia.captureAfterNanoseconds ?? .max))
    #expect(postMedia.frame.captureNanoseconds > (postMedia.captureAfterNanoseconds ?? .max))
    #expect(postMedia.frame == ExactFrameProvenance(frame: fixture.postFrame.frame))
    let baselinePosition = try #require(baselineMedia.controllerPosition)
    let postPosition = try #require(postMedia.controllerPosition)
    #expect(MachinePositionAcceptancePolicy.accepts(baselinePosition, target: pose.position))
    #expect(MachinePositionAcceptancePolicy.accepts(postPosition, target: pose.position))
    #expect(MachinePositionAcceptancePolicy.accepts(postPosition, target: baselinePosition))
    #expect(pose.position != fixture.finalPosition)
    #expect(try #require(attempt.missingCoverageReason).isEmpty == false)
    if let coverage = attempt.mediaCoverage {
      #expect(coverage.coveredPixelCount == 0)
      #expect(coverage.uncoveredMask.allSatisfy { $0 })
    }
    guard case .persisted(let recordID, let revision) = result.snapshot.evidencePersistence else {
      Issue.record("Expected durable evidence publication.")
      return
    }
    #expect(recordID == terminal.record.recordID)
    #expect(revision == 1)
  }

  @Test("outside applicability executes but invokes no Vision and records non-attribution")
  func outsideApplicabilityDoesNotInvokeVision() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let bounds = fixture.drawableRegion.effectiveBounds
    let center = try Point2<MachineSpace>(
      x: bounds.minX + 5,
      y: (bounds.minY + bounds.maxY) / 2
    )
    #expect(center.x < fixture.registration.applicabilityRectangle.minX)
    let outsidePlan = try fixture.makePlan(
      catalogItemID: .line,
      center: center,
      role: .evaluationHoldout
    )
    let harness = await drawingRunHarness(
      fixture: fixture,
      facts: fixture.facts(plan: outsidePlan)
    )
    let current = await harness.runtime.synchronize(environment: .live)
    let result = await harness.runtime.submit(PlotterDrawingRunSubmission(
      projection: current.projection,
      intent: .start
    ))

    #expect(await harness.vision.requests.isEmpty)
    #expect(!result.snapshot.physicalEvidenceClaimed)
    #expect(result.snapshot.terminal?.disposition == .nonAttributable)
    #expect(result.snapshot.terminal?.record.role == .evaluationHoldout)
    #expect(result.snapshot.terminal?.record.evidenceDisposition == .nonAttributable)
    #expect(
      result.snapshot.terminal?.record.observation
        == .notAttempted(.projectionOutsideTipApplicability)
    )
  }

  @Test("optional border is cancelled and retained as possible ink by the ordinary run owner")
  func optionalBorderCancellationAndEvidence() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let program = fixture.plan.program
    let built = PlotterDrawingPlanningAdapter.buildDraft(program: program, machineCenter: nil,
      uniformScale: 0.02, rotationDegrees: 0, drawableRegion: fixture.drawableRegion,
      registration: fixture.registration, drawBorder: true,
      drawingBorderBounds: fixture.registration.applicabilityRectangle)
    let plan = PlotterDrawingRunPlan(draftRevision: .init(rawValue: 2),
      program: try #require(built.program), placementID: UUID(), plan: try #require(built.plan),
      evidenceRole: .ordinaryDrawing, paperCoverage: fixture.plan.paperCoverage,
      registration: fixture.registration)
    let gate = DrawingRunPlanGate()
    let harness = await drawingRunHarness(fixture: fixture, facts: fixture.facts(plan: plan), planGate: gate)
    let ready = await harness.runtime.synchronize(environment: .live)
    let run = Task { await harness.runtime.submit(.init(projection: ready.projection, intent: .start)) }
    await gate.waitUntilStarted()
    let active = await harness.runtime.snapshot(environment: .live)
    let stop = try #require(active.stopCapabilityID)
    _ = await harness.runtime.submit(.init(projection: active.projection, intent: .stop(stop)))
    let result = await run.value
    #expect(result.snapshot.terminal?.disposition == .cancelled)
    #expect(await harness.interpreter.stopIntents == [.operatorStop])
    #expect(try #require(await harness.interpreter.planRequests.first).plan == plan.plan)
    let record = try #require(result.snapshot.terminal?.record)
    #expect(record.program.contentHash == plan.program.contentHash)
    #expect(record.plan.executionPlan?.strokes.count == program.strokes.count + 1)
    guard case .planMayContainInk(_, let identity) = result.snapshot.noRedraw else {
      Issue.record("The optional border must share its drawing's possible-ink identity.")
      return
    }
    #expect(identity == plan.identity)
    guard case .persisted = result.snapshot.evidencePersistence else {
      Issue.record("Cancelled drawing with optional border did not persist its evidence.")
      return
    }
  }

  @Test("one active start owns exact Stop and the possible-ink no-redraw boundary")
  func serializedStartStopAndNewPlanHandoff() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let planGate = DrawingRunPlanGate()
    let harness = await drawingRunHarness(fixture: fixture, planGate: planGate)
    let initial = await harness.runtime.synchronize(environment: .live)
    let first = Task {
      await harness.runtime.submit(PlotterDrawingRunSubmission(
        projection: initial.projection,
        intent: .start
      ))
    }
    await planGate.waitUntilStarted()

    let active = await harness.runtime.snapshot(environment: .live)
    let competitor = await harness.runtime.submit(PlotterDrawingRunSubmission(
      projection: active.projection,
      intent: .start
    ))
    #expect(try drawingRunRefusal(competitor).reason == .activeRunOwnsWorkflow)

    let wrongStop = await harness.runtime.submit(PlotterDrawingRunSubmission(
      projection: competitor.snapshot.projection,
      intent: .stop(PlotterDrawingRunStopCapabilityID())
    ))
    let wrongRefusal = try drawingRunRefusal(wrongStop)
    #expect(wrongRefusal.reason == .stopCapabilityMismatch)
    #expect(wrongRefusal.remedy == .useExactStopCapability)
    #expect(await harness.interpreter.stopIntents.isEmpty)

    let exactStop = try #require(active.stopCapabilityID)
    let stopIntent = PlotterDrawingRunIntent.stop(exactStop)
    let action = PlotterUIAction(id: PlotterAppUIActionID.drawingRun(stopIntent),
      title: "Stop Drawing", intent: .drawingRun(stopIntent))
    let projection = PlotterUIProjection(revision: .init(rawValue: 1), runtimeRevisions: [],
      actions: [action], learning: nil, incidentPackage: .unavailable(reason: "held runtime fixture"),
      diagnostics: [], visitedCandidateCount: 1)
    var layout = WorkbenchLayoutState()
    layout.setPresented(.motion, false)
    layout.setPresented(.portraitStudio, false)
    let visibleStop = try #require(WorkbenchStopPresentation.actions(in: projection).first)
    #expect(projection.request(for: visibleStop.id)?.intent == .drawingRun(stopIntent))
    let stopped = await harness.runtime.submit(PlotterDrawingRunSubmission(
      projection: wrongStop.snapshot.projection,
      intent: .stop(exactStop)
    ))
    #expect(stopped.disposition == .applied)
    let terminalResult = await first.value
    #expect(await harness.interpreter.stopIntents == [.operatorStop])
    #expect(await harness.vision.requests.isEmpty)
    #expect(await harness.camera.requests.count == 1)
    #expect(terminalResult.snapshot.terminal?.disposition == .cancelled)
    #expect(
      terminalResult.snapshot.terminal?.record.observation
        == .notAttempted(.executionCancelledBeforeObservation)
    )
    guard case .planMayContainInk(let runID, let identity) = terminalResult.snapshot.noRedraw else {
      Issue.record("A commanded cancelled plan must retain possible-ink no-redraw truth.")
      return
    }
    #expect(identity == fixture.plan.identity)

    let handedOff = await harness.runtime.submit(PlotterDrawingRunSubmission(
      projection: terminalResult.snapshot.projection,
      intent: .beginNewRun(runID)
    ))
    #expect(handedOff.disposition == .applied)
    #expect(handedOff.snapshot.readiness == .synchronizing)
    let samePlan = await harness.runtime.submit(PlotterDrawingRunSubmission(
      projection: handedOff.snapshot.projection,
      intent: .start
    ))
    let samePlanRefusal = try drawingRunRefusal(samePlan)
    #expect(samePlanRefusal.reason == .planMayAlreadyContainInk)
    #expect(samePlanRefusal.remedy == .movePlanAwayFromPossibleInk)

    let replacement = try fixture.makePlan(catalogItemID: .triangle)
    await harness.facts.replace(fixture.facts(plan: replacement))
    let replacementProjection = await harness.runtime.synchronize(environment: .live)
    let replacementRun = await harness.runtime.submit(PlotterDrawingRunSubmission(
      projection: replacementProjection.projection,
      intent: .start
    ))
    #expect(replacementRun.disposition == .applied)
    #expect(await harness.interpreter.planRequests.count == 2)
  }

  @Test(
    "ambiguity and possible ink retain distinct terminal frontiers",
    arguments: [DrawingRunOutcomeKind.ambiguous, .possibleInk]
  )
  func ambiguousTerminals(kind: DrawingRunOutcomeKind) async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let harness = await drawingRunHarness(fixture: fixture, outcome: kind)
    let current = await harness.runtime.synchronize(environment: .live)
    let result = await harness.runtime.submit(PlotterDrawingRunSubmission(
      projection: current.projection,
      intent: .start
    ))
    let terminal = try #require(result.snapshot.terminal)
    let expected: PlotterDrawingRunTerminalDisposition =
      kind == .ambiguous ? .ambiguous : .possibleInk
    #expect(terminal.disposition == expected)
    #expect(terminal.record.requestFrontier == .admitted)
    #expect(terminal.record.executionFrontiers.commandedStrokeCount > 0)
    #expect(terminal.record.executionFrontiers.inkVerifiedStrokeCount == 0)
    #expect(await harness.vision.requests.isEmpty)
    guard case .planMayContainInk = result.snapshot.noRedraw else {
      Issue.record("Ambiguous commanded execution must retain possible-ink no-redraw truth.")
      return
    }
  }

  @Test("append failure publishes no success and exact recovery enables frame review")
  func publicationRecoveryAndReview() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let training = try fixture.makePlan(catalogItemID: .line, role: .training)
    let harness = await drawingRunHarness(
      fixture: fixture,
      facts: fixture.facts(plan: training),
      evidenceFailures: 1
    )
    let current = await harness.runtime.synchronize(environment: .live)
    let requestID = PlotterDrawingRunRequestID()
    let failed = await harness.runtime.submit(PlotterDrawingRunSubmission(
      requestID: requestID,
      projection: current.projection,
      intent: .start
    ))
    let terminal = try #require(failed.snapshot.terminal)
    #expect(terminal.disposition == .publicationIncomplete)
    #expect(terminal.record.requestID == requestID.rawValue)
    #expect(terminal.record.role == .training)
    #expect(!failed.snapshot.physicalEvidenceClaimed)
    guard case .failed(let recordID, let recoveryID, _) = failed.snapshot.evidencePersistence else {
      Issue.record("Expected an exact publication recovery capability.")
      return
    }
    #expect(recordID == terminal.record.recordID)

    let prematureNewRun = await harness.runtime.submit(PlotterDrawingRunSubmission(
      projection: failed.snapshot.projection,
      intent: .beginNewRun(terminal.runID)
    ))
    let prematureRefusal = try drawingRunRefusal(prematureNewRun)
    #expect(prematureRefusal.owner.rawValue == "DrawingRunEvidenceStore")
    #expect(prematureRefusal.remedy == .retryEvidencePublication)

    let recovered = await harness.runtime.submit(PlotterDrawingRunSubmission(
      projection: prematureNewRun.snapshot.projection,
      intent: .recoverPublication(recoveryID)
    ))
    #expect(recovered.snapshot.terminal?.disposition == .succeeded)
    #expect(recovered.snapshot.physicalEvidenceClaimed)
    let attempts = await harness.evidence.attempts
    #expect(attempts.count == 2)
    #expect(attempts[0] == attempts[1])

    let pinned = await harness.runtime.submit(PlotterDrawingRunSubmission(
      projection: recovered.snapshot.projection,
      intent: .pinReview(terminal.runID)
    ))
    #expect(
      pinned.snapshot.review
        == .pinned(runID: terminal.runID, frame: fixture.postFrame.plotterExactFrameReference)
    )
    let unpinned = await harness.runtime.submit(PlotterDrawingRunSubmission(
      projection: pinned.snapshot.projection,
      intent: .unpinReview(terminal.runID)
    ))
    #expect(
      unpinned.snapshot.review
        == .available(runID: terminal.runID, frame: fixture.postFrame.plotterExactFrameReference)
    )
  }

  @Test("exact recovery owns publication until its append settles")
  func heldRecoveryBlocksNewRunAndReview() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let harness = await drawingRunHarness(fixture: fixture, evidenceFailures: 1)
    let current = await harness.runtime.synchronize(environment: .live)
    let failed = await harness.runtime.submit(PlotterDrawingRunSubmission(
      projection: current.projection,
      intent: .start
    ))
    let terminal = try #require(failed.snapshot.terminal)
    guard case .failed(let recordID, let recoveryID, _) = failed.snapshot.evidencePersistence else {
      Issue.record("Expected a publication recovery capability.")
      return
    }

    let wrongRecovery = await harness.runtime.submit(PlotterDrawingRunSubmission(
      projection: failed.snapshot.projection,
      intent: .recoverPublication(PlotterDrawingRunPublicationRecoveryCapabilityID())
    ))
    let wrongRefusal = try drawingRunRefusal(wrongRecovery)
    #expect(wrongRefusal.reason == .publicationRecoveryMismatch)
    #expect(wrongRefusal.remedy == .retryEvidencePublication)
    #expect(await harness.evidence.attempts.count == 1)

    let appendGate = DrawingRunHoldGate()
    await harness.evidence.holdNextAppend(at: appendGate)
    let recovery = Task {
      await harness.runtime.submit(PlotterDrawingRunSubmission(
        projection: wrongRecovery.snapshot.projection,
        intent: .recoverPublication(recoveryID)
      ))
    }
    await appendGate.waitUntilHeld()
    let appending = await harness.runtime.snapshot(environment: .live)
    #expect(appending.evidencePersistence == .appending(recordID))
    #expect(appending.terminal?.disposition == .publicationIncomplete)
    #expect(!appending.physicalEvidenceClaimed)

    let blockedNewRun = await harness.runtime.submit(PlotterDrawingRunSubmission(
      projection: appending.projection,
      intent: .beginNewRun(terminal.runID)
    ))
    let newRunRefusal = try drawingRunRefusal(blockedNewRun)
    #expect(newRunRefusal.owner.rawValue == "DrawingRunEvidenceStore")
    #expect(newRunRefusal.reason == .evidencePublicationInProgress)
    #expect(newRunRefusal.remedy == .waitForEvidencePublication)

    let blockedReview = await harness.runtime.submit(PlotterDrawingRunSubmission(
      projection: blockedNewRun.snapshot.projection,
      intent: .pinReview(terminal.runID)
    ))
    let reviewRefusal = try drawingRunRefusal(blockedReview)
    #expect(reviewRefusal.owner.rawValue == "DrawingRunEvidenceStore")
    #expect(reviewRefusal.reason == .evidencePublicationInProgress)
    #expect(reviewRefusal.remedy == .waitForEvidencePublication)
    #expect(await harness.evidence.attempts.count == 2)

    await appendGate.release()
    let recovered = await recovery.value
    #expect(recovered.snapshot.terminal?.disposition == .succeeded)
    #expect(recovered.snapshot.physicalEvidenceClaimed)
    guard case .persisted(let persistedID, _) = recovered.snapshot.evidencePersistence else {
      Issue.record("Exact recovery did not publish the retained record.")
      return
    }
    #expect(persistedID == recordID)
    let attempts = await harness.evidence.attempts
    #expect(attempts.count == 2)
    #expect(attempts[0] == attempts[1])
  }

  @Test("checksummed archive restore blocks only the same paper and plan")
  func archiveIntegrityAndNoRedrawRestore() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let completed = await drawingRunHarness(fixture: fixture)
    let projection = await completed.runtime.synchronize(environment: .live)
    let result = await completed.runtime.submit(PlotterDrawingRunSubmission(
      projection: projection.projection,
      intent: .start
    ))
    let record = try #require(result.snapshot.terminal?.record)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "drawing-run-episode-\(UUID().uuidString)", isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = DrawingRunEvidenceStore(
      fileURL: directory.appendingPathComponent("drawing-runs.json")
    )
    let owned = try #require(record.attemptEvidence)
    try await store.stageIntent(owned.intent)
    _ = try await store.installMedia(frame: fixture.baselineFrame.frame, source: fixture.baselineFrame.source)
    for baseline in owned.baselines { try await store.stageBaseline(runID: record.runID, media: baseline) }
    try await store.markInkDispatchPossible(runID: record.runID)
    _ = try await store.installMedia(frame: fixture.postFrame.frame, source: fixture.postFrame.source)
    let archive = try await store.append(record)
    guard case .loaded(let loaded) = await store.load() else {
      Issue.record("Expected the exact checksummed archive to load.")
      return
    }
    #expect(loaded == archive)

    let restored = await drawingRunHarness(fixture: fixture)
    _ = await restored.runtime.restoreNoRedrawTruth(
      from: loaded,
      paper: fixture.paper,
      environment: .live
    )
    let restoredProjection = await restored.runtime.synchronize(environment: .live)
    let blocked = await restored.runtime.submit(PlotterDrawingRunSubmission(
      projection: restoredProjection.projection,
      intent: .start
    ))
    #expect(try drawingRunRefusal(blocked).reason == .planMayAlreadyContainInk)

    var bytes = try Data(contentsOf: store.fileURL)
    bytes[bytes.count / 2] ^= 0x01
    try bytes.write(to: store.fileURL, options: [.atomic])
    guard case .rejected = await store.load() else {
      Issue.record("Tampered drawing-run evidence must fail closed.")
      return
    }
  }

  @Test("rejected startup archive closes run admission without LIVE effects")
  func rejectedStartupArchiveFailsClosed() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let harness = await drawingRunHarness(
      fixture: fixture,
      archiveLoadResult: .rejected(.integrityMismatch)
    )
    let current = await harness.runtime.synchronize(environment: .live)
    #expect(current.evidenceArchiveAvailability == .rejected(detail: "integrityMismatch"))
    #expect(current.noRedraw == .archiveUnavailable(detail: "integrityMismatch"))

    let result = await harness.runtime.submit(PlotterDrawingRunSubmission(
      projection: current.projection,
      intent: .start
    ))
    let refusal = try drawingRunRefusal(result)
    #expect(refusal.owner.rawValue == "DrawingRunEvidenceStore")
    #expect(refusal.reason == .evidenceArchiveUnavailable)
    #expect(refusal.remedy == .restoreEvidenceArchive)
    #expect(result.snapshot.activeRunID == nil)
    #expect(result.snapshot.terminal == nil)
    #expect(await harness.interpreter.planRequests.isEmpty)
    #expect(await harness.interpreter.stopIntents.isEmpty)
    #expect(await harness.camera.requests.isEmpty)
    #expect(await harness.vision.requests.isEmpty)
    #expect(await harness.evidence.attempts.isEmpty)
    #expect(await harness.events.values.isEmpty)
  }

  @Test("SIMULATED run refusal is typed nonphysical and invokes no LIVE port")
  func simulatedIsNonphysical() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let simulatedFacts = fixture.facts(environment: .simulated)
    let harness = await drawingRunHarness(fixture: fixture, facts: simulatedFacts)
    let current = await harness.runtime.synchronize(environment: .simulated)
    let result = await harness.runtime.submit(PlotterDrawingRunSubmission(
      projection: current.projection,
      intent: .start
    ))
    let refusal = try drawingRunRefusal(result)
    #expect(refusal.owner.rawValue == "PlotterDrawingRunRuntime")
    #expect(refusal.reason == .simulatedRunIsNonphysical)
    #expect(refusal.remedy == .switchToLiveSource)
    #expect(!result.snapshot.physicalEvidenceClaimed)
    #expect(result.snapshot.terminal == nil)
    #expect(await harness.interpreter.planRequests.isEmpty)
    #expect(await harness.camera.requests.isEmpty)
    #expect(await harness.vision.requests.isEmpty)
    #expect(await harness.evidence.attempts.isEmpty)
  }
}

private enum PlotterDrawingRunEpisodeTestError: Error {
  case expectedRefusal
}

private func drawingRunRefusal(
  _ result: PlotterDrawingRunSubmissionResult
) throws -> PlotterDrawingRunRefusal {
  guard case .refused(let refusal) = result.disposition else {
    Issue.record("Expected a typed Drawing Run refusal; got \(result.disposition).")
    throw PlotterDrawingRunEpisodeTestError.expectedRefusal
  }
  return refusal
}


/// Test-only Codable construction follows the existing synthetic registration
/// fixture seam. No production calibration, rebase, camera, or motion occurs.
private func drawingRunRegistrationWithNewMachineGeometry(
  _ registration: TipCameraRegistration
) throws -> TipCameraRegistration {
  let previous = registration.applicability
  let applicability = TipCalibrationApplicabilityContext(
    opticalConfiguration: previous.opticalConfiguration, machineGeometry: MachineGeometryIdentity(),
    machineCoordinateFrame: MachineCoordinateFrameRevision(rawValue: previous.machineCoordinateFrame.rawValue + 1),
    toolAssembly: previous.toolAssembly, penContactProfile: previous.penContactProfile,
    paperContactPlane: previous.paperContactPlane)
  let encoder = JSONEncoder()
  var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(registration)) as? [String: Any])
  object["applicability"] = try JSONSerialization.jsonObject(with: encoder.encode(applicability))
  object["acceptedRevisionID"] = try JSONSerialization.jsonObject(with: encoder.encode(LearningArtifactRevisionID()))
  object["machineCameraRegistrationRevisionID"] = try JSONSerialization.jsonObject(with: encoder.encode(LearningArtifactRevisionID()))
  object["estimatorRevision"] = registration.estimatorRevision + "-new-machine-metric-fixture"
  return try JSONDecoder().decode(TipCameraRegistration.self,
    from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
}

private func drawingRunGeometryRevisionPlan(
  fixture: DrawingRunEpisodeFixture, registration: TipCameraRegistration, shifted: Bool
) throws -> PlotterDrawingRunPlan {
  let anchor = fixture.plan.plan.placement.machineAnchor
  let deltaX = shifted ? (fixture.drawableRegion.bounds.maxX - anchor.x) / 4 : 0
  let built = PlotterDrawingPlanningAdapter.buildDraft(program: fixture.plan.program,
    machineCenter: try Point2(x: anchor.x + deltaX, y: anchor.y),
    uniformScale: fixture.plan.plan.placement.uniformScale, rotationDegrees: 0,
    drawableRegion: fixture.drawableRegion, registration: registration)
  return PlotterDrawingRunPlan(draftRevision: .init(rawValue: shifted ? 12 : 11),
    program: try #require(built.program), placementID: UUID(), plan: try #require(built.plan),
    evidenceRole: fixture.plan.evidenceRole, paperCoverage: fixture.plan.paperCoverage, registration: registration)
}

private func drawingRunPlan(
  _ plan: PlotterDrawingRunPlan, replacingPaper paper: PaperRevisionContext
) throws -> PlotterDrawingRunPlan {
  let prior = plan.paperCoverage
  let coverage = try PaperCoverageObservation(paper: paper, source: prior.source, frame: prior.frame,
    polygon: prior.polygon, method: prior.method, observedAt: prior.observedAt,
    algorithmRevision: prior.algorithmRevision, opticalConfiguration: prior.opticalConfiguration,
    drawableRegion: prior.drawableRegion)
  return PlotterDrawingRunPlan(draftRevision: plan.identity.draftRevision, program: plan.program,
    placementID: plan.placementID, plan: plan.plan, evidenceRole: plan.evidenceRole,
    paperCoverage: coverage, registration: plan.registration)
}
