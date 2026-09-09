import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Drawing Studio draft episode", .serialized)
@MainActor
struct PlotterDrawingDraftEpisodeTests {
  @Test("automatic fit keeps upright when it wins or the orientations tie", arguments: [false, true])
  func uprightAndTieFit(square: Bool) async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let opened = try await open(runtime, facts: fixture.facts())
    let style = try #require(opened.program?.strokes.first?.style)
    let bounds = fixture.drawableRegion.effectiveBounds
    let isWide = bounds.maxX - bounds.minX > bounds.maxY - bounds.minY
    let width = square || isWide ? 100.0 : 20.0
    let height = square || !isWide ? 100.0 : 20.0
    let program = try DrawingProgram(id: ProgramID(), fieldExtent: Size2(width: width, height: height),
      strokes: [LogicalStroke(id: StrokeID(), path: Polyline(points: [
        Point2(x: 0, y: 0), Point2(x: width, y: 0), Point2(x: width, y: height),
        Point2(x: 0, y: height), Point2(x: 0, y: 0)]), style: style, ordering: 0)],
      source: DrawingSourceProvenance(kind: "portrait-fit-test", sourceIdentifier: square ? "tie" : "upright"))
    let selected = try applied(await runtime.submit(.init(projection: opened.projection,
      intent: .selectProgram(program)), facts: fixture.facts()))
    let fitted = try applied(await runtime.submit(.init(projection: selected.projection,
      intent: .fitInDrawableRegion), facts: fixture.facts()))
    #expect(fitted.rotationDegrees == 0)
    #expect(fitted.uniformScale == fitted.allowedScale.upperBound)
    #expect(try #require(fitted.plan).strokes.allSatisfy { fixture.drawableRegion.contains($0.path) })
  }

  @Test("panel visibility survives preview advancement without admitting stale draft edits")
  func panelVisibilitySurvivesPreviewAdvancement() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let initial = await runtime.synchronize(fixture.facts())
    let next = try replacingFrame(fixture.frame, id: "open-preview", sequenceDelta: 1)
    let opened = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(projection: initial.projection, intent: .showTarget),
      facts: fixture.facts(displayedFrame: next)))
    #expect(opened.isTargetVisible)
    let latest = try replacingFrame(fixture.frame, id: "close-preview", sequenceDelta: 2)
    let latestFacts = fixture.facts(displayedFrame: latest)
    let edit = await runtime.submit(
      PlotterDrawingDraftSubmission(projection: opened.projection, intent: .assertPaperCoverage),
      facts: latestFacts)
    #expect(try refusal(edit).reason == .staleProjection)
    let closed = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(projection: opened.projection, intent: .hideTarget),
      facts: latestFacts))
    #expect(!closed.isTargetVisible)
    let stale = await runtime.submit(
      PlotterDrawingDraftSubmission(projection: initial.projection, intent: .showTarget),
      facts: latestFacts)
    #expect(try applied(stale).isTargetVisible)
    #expect(stale.snapshot.projection.draftRevision == initial.projection.draftRevision)
  }

  @Test("cancelled draft edits leave a held paper save promptly without cancelling its owner")
  func cancelledQueuedEditDoesNotWaitForPersistence() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let persistence = DraftPaperPersistenceProbe(blocksSave: true)
    let runtime = PlotterDrawingDraftRuntime(paperPersistence: persistence,
      clock: DraftRuntimeClock(now: fixture.frame.frame.captureNanoseconds + 100))
    let facts = fixture.facts(environment: .live)
    let opened = try await open(runtime, facts: facts)
    let owner = Task { await runtime.submit(.init(projection: opened.projection,
      intent: .assertPaperCoverage), facts: facts) }
    await persistence.waitUntilSaveStarted()
    let completion = DraftSubmissionInterleavingProbe()
    let waiter = Task {
      let result = await runtime.submit(.init(projection: opened.projection,
        intent: .setRotationDegrees(15)), facts: facts)
      await completion.markCompleted()
      return result
    }
    do { try await waitUntilAsync { await runtime.pendingMutationCount == 1 } }
    catch { await persistence.releaseSave(); _ = await owner.value; _ = await waiter.value; throw error }
    waiter.cancel()
    do { try await waitUntilAsync { await completion.completed } }
    catch { await persistence.releaseSave(); _ = await owner.value; throw error }
    #expect(try refusal(await waiter.value).reason == .cancelled)
    #expect(await runtime.pendingMutationCount == 0)
    #expect(await persistence.storedObservation == nil)
    await persistence.releaseSave()
    let saved = try applied(await owner.value)
    let edited = try applied(await runtime.submit(.init(projection: saved.projection,
      intent: .setRotationDegrees(15)), facts: facts))
    #expect(edited.rotationDegrees == 15)
    #expect(edited.paperCoverageObservation == saved.paperCoverageObservation)
  }

  @Test("automatic portrait fit chooses the larger contained orientation and survives camera restart")
  func portraitFitAndCameraRestart() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime(clock: DraftRuntimeClock(now: fixture.frame.frame.captureNanoseconds + 100))
    let opened = try await open(runtime, facts: fixture.facts())
    let style = try #require(opened.program?.strokes.first?.style)
    let bounds = fixture.drawableRegion.effectiveBounds
    let isWide = bounds.maxX - bounds.minX >= bounds.maxY - bounds.minY
    let width = isWide ? 20.0 : 100.0, height = isWide ? 100.0 : 20.0
    let program = try DrawingProgram(id: ProgramID(), fieldExtent: Size2(width: width, height: height),
      strokes: [LogicalStroke(id: StrokeID(), path: Polyline(points: [Point2(x: 0, y: 0),
        Point2(x: width, y: height)]), style: style, ordering: 0)],
      source: DrawingSourceProvenance(kind: "portrait-fit-test", sourceIdentifier: "opposite-aspect"))
    let selected = try applied(await runtime.submit(.init(projection: opened.projection,
      intent: .selectProgram(program)), facts: fixture.facts()))
    let fitted = try applied(await runtime.submit(.init(projection: selected.projection,
      intent: .fitInDrawableRegion), facts: fixture.facts()))
    #expect(fitted.rotationDegrees == 90)
    #expect(fitted.uniformScale == fitted.allowedScale.upperBound)
    #expect(try #require(fitted.plan).strokes.allSatisfy { fixture.drawableRegion.contains($0.path) })
    let asserted = try applied(await runtime.submit(.init(projection: fitted.projection,
      intent: .assertPaperCoverage), facts: fixture.facts()))
    let restartedFrame = try replacingFrame(fixture.frame, id: "new-capture-session",
      sequenceDelta: 10, cameraConfigurationID: CameraConfigurationID())
    let resumed = await runtime.synchronize(fixture.facts(displayedFrame: restartedFrame))
    #expect(resumed.paperCoverageIsCurrent)
    #expect(resumed.paperCoverageObservation == asserted.paperCoverageObservation)
    #expect(resumed.plan?.revisionID == asserted.plan?.revisionID)
    #expect(resumed.preview?.displayedFrame == restartedFrame)
    #expect(resumed.paperCoverageDisplay == nil)
    let newPaper = await runtime.synchronize(fixture.facts(paper: PaperRevisionContext(
      instance: PaperInstanceRevision(), contactPlane: fixture.paper.contactPlane)))
    #expect(!newPaper.paperCoverageIsCurrent)
  }

  @Test("ordinary authoring uses current facts across Learning and camera publication while retained runs keep their authority")
  func authoringSurvivesPreviewOnlyChanges() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let next = try replacingFrame(fixture.frame, id: "authoring-preview", sequenceDelta: 1)
    for intent: PlotterDrawingDraftIntent in [
      .selectCatalogItem(.circle), .setUniformScale(0.5), .setRotationDegrees(10),
      .setRotationDegrees(15), .centerInDrawableRegion,
    ] {
      let runtime = PlotterDrawingDraftRuntime()
      let opened = try await open(runtime, facts: fixture.facts())
      _ = try applied(await runtime.submit(
        PlotterDrawingDraftSubmission(projection: opened.projection, intent: intent),
        facts: fixture.facts(displayedFrame: next)))
    }

    let changedCamera = try replacingFrame(fixture.frame, id: "changed-camera",
      sequenceDelta: 2, cameraConfigurationID: CameraConfigurationID())
    for facts in [fixture.facts(displayedFrame: changedCamera), fixture.facts(learningComplete: false)] {
      let runtime = PlotterDrawingDraftRuntime()
      let opened = try await open(runtime, facts: fixture.facts())
      let result = try applied(await runtime.submit(
        PlotterDrawingDraftSubmission(projection: opened.projection, intent: .setUniformScale(0.5)),
        facts: facts))
      #expect(result.uniformScale == 0.5)
      #expect(result.projection.externalFacts == facts.revisions)
    }
    let runtime = PlotterDrawingDraftRuntime()
    let opened = try await open(runtime, facts: fixture.facts())
    let running = await runtime.submit(
      PlotterDrawingDraftSubmission(projection: opened.projection, intent: .setUniformScale(0.5)),
      facts: fixture.facts(runInProgress: true))
    #expect(try refusal(running).reason == .retainedRunOwnsMutation)
    #expect(running.snapshot.uniformScale == opened.uniformScale)
  }

  @Test("large drawing geometry is derived once across preview and status changes")
  func unchangedGeometryIsNotReplanned() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let opened = try await open(runtime, facts: fixture.facts())
    let style = try #require(opened.program?.strokes.first?.style)
    let points: [Point2<FieldSpace>] = try (0...2_000).map { index in
      let angle = Double(index) * 2 * Double.pi / 2_000
      return try Point2(x: 50 + 40 * cos(angle), y: 50 + 40 * sin(angle))
    }
    let program = try DrawingProgram(id: ProgramID(), fieldExtent: Size2(width: 100, height: 100),
      strokes: [LogicalStroke(id: StrokeID(), path: Polyline(points: points), style: style, ordering: 0)],
      source: DrawingSourceProvenance(kind: "geometry-reuse-test", sourceIdentifier: "2001-point-circle"))
    let selected = try applied(await runtime.submit(
      .init(projection: opened.projection, intent: .selectProgram(program)), facts: fixture.facts()))
    let planID = try #require(selected.plan?.revisionID)
    let derivations = await runtime.derivationBuildCount
    for index in 1...120 {
      let nextFrame = try replacingFrame(fixture.frame, id: "cached-preview-\(index)",
        sequenceDelta: UInt64(index))
      let snapshot = await runtime.synchronize(fixture.facts(displayedFrame: nextFrame))
      #expect(snapshot.plan?.revisionID == planID)
      #expect(snapshot.preview?.displayedFrame.frame.id == nextFrame.frame.id)
      #expect(snapshot.preview?.strokes.first?.points.count == points.count)
    }
    _ = await runtime.synchronize(fixture.facts(learningComplete: false, runInProgress: true))
    let ready = await runtime.synchronize(fixture.facts())
    #expect(await runtime.derivationBuildCount == derivations)
    let resized = try applied(await runtime.submit(
      .init(projection: ready.projection, intent: .setUniformScale(0.2)), facts: fixture.facts()))
    #expect(resized.plan?.revisionID != planID)
    #expect(await runtime.derivationBuildCount == derivations + 1)
    let oldPreview = try #require(ready.preview)
    #expect(oldPreview.strokes != resized.preview?.strokes)
    // Unavailable derivations remain unavailable on cache hits; restoring the
    // exact authority must rebuild even if the artwork has not changed.
    let missingRegion = fixture.facts(displayedFrame: fixture.frame,
      opticalConfiguration: fixture.opticalConfiguration,
      registration: fixture.registration, drawableRegion: nil)
    let unavailable = await runtime.synchronize(missingRegion)
    let repeated = await runtime.synchronize(missingRegion)
    #expect(unavailable.plan == nil && unavailable.preview == nil)
    #expect(repeated.plan == nil && repeated.preview == nil)
    let restored = await runtime.synchronize(fixture.facts())
    #expect(restored.plan?.revisionID == resized.plan?.revisionID)
    #expect(restored.preview != nil)

  }

  @Test("wide artwork retains a reachable exact fractional maximum scale in the production UI")
  func fractionalMaximumScaleRemainsReachable() async throws {
    let harness = makeCausalSimulatorAppFixture()
    let workspace = harness.workspace
    try await completeSimulatedPenInteractionPrerequisite(workspace)
    try await installAcceptedBoundaryTestProjection(runtime: harness.boundaryRuntime,
      workspace: workspace, environment: .simulated)
    try await completeSimulatedTipCalibration(workspace, simulator: harness.simulator)
    _ = await workspace.currentDrawingRunFacts(for: .simulated)
    let item = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let initial = workspace.testPlotterUIProjection(selectedItemID: item, includesLearningPath: true)
    let openRequest = try #require(initial.semantic.request(for: PlotterAppUIActionID.drawingDraft(.showTarget)))
    #expect(await workspace.submitPlotterUIRequest(openRequest) == .accepted(requestID: openRequest.id))
    let base = try #require(workspace.drawingDraftSnapshot.program)
    let program = try DrawingProgram(id: ProgramID(), fieldExtent: Size2(width: 1003, height: 100),
      strokes: base.strokes, source: DrawingSourceProvenance(kind: "wide-artwork-test", sourceIdentifier: "fractional-scale-regression"))
    let selection = workspace.plotterUIProjection(selectedItemID: item, manualDraft: ManualMotionDraft(),
      includesLearningPath: true, pendingDrawingProgram: program)
    let selectRequest = try #require(selection.semantic.request(matching: .drawingDraft(.selectProgram(program))))
    #expect(await workspace.submitPlotterUIRequest(selectRequest) == .accepted(requestID: selectRequest.id))
    let projection = workspace.testPlotterUIProjection(selectedItemID: item, includesLearningPath: true)
    let placement = projection.drawingStudio.canvas.placement
    #expect(placement.uniformScale == placement.allowedScale.upperBound)
    #expect(placement.uniformScale != (placement.uniformScale * 100).rounded() / 100)
    let resize = try #require(projection.semantic.request(matching: .drawingDraft(.setUniformScale(placement.allowedScale.upperBound))))
    #expect(await workspace.submitPlotterUIRequest(resize) == .accepted(requestID: resize.id))
    #expect(workspace.drawingDraftSnapshot.program == program)
    await workspace.shutdown()
  }

  @Test("portrait authoring survives unavailable calibration and builds the same program after Learning")
  func portraitBeforeCalibration() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let unavailable = PlotterDrawingDraftExternalFacts(
      environment: .simulated, interactiveLearningIsComplete: false,
      displayedFrame: nil, opticalConfiguration: nil, registration: nil,
      drawableRegion: nil, toolAssemblyRevision: fixture.registration.applicability.toolAssembly,
      paper: fixture.paper, runInProgress: false, terminalRequiresNewPlan: false)
    var snapshot = try await open(runtime, facts: unavailable)
    let style = try #require(snapshot.program?.strokes.first?.style)
    let portrait = try PortraitVectorizer.program(
      from: portraitTestRaster(), pose: .front, style: .contours, strokeStyle: style)
    snapshot = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(projection: snapshot.projection, intent: .selectProgram(portrait)),
      facts: unavailable))
    #expect(snapshot.program == portrait)
    #expect(snapshot.plan == nil)
    #expect(snapshot.planningRefusal?.reason == .registrationUnavailable)
    #expect(!snapshot.paperCoverageIsCurrent)

    let ready = await runtime.synchronize(fixture.facts())
    #expect(ready.program == portrait)
    #expect(ready.plan?.sourceProgramContentHash == portrait.contentHash)
    #expect(ready.plan?.strokes.count == portrait.strokes.count)
    let lostCalibration = await runtime.synchronize(unavailable)
    #expect(lostCalibration.program == portrait)
    #expect(lostCalibration.plan == nil)
    let restored = await runtime.synchronize(fixture.facts())
    #expect(restored.plan == ready.plan)
  }

  @Test("portrait vectors retain exact identity through placement and the ordinary drawing plan")
  func portraitProgramIntegration() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let facts = fixture.facts()
    var snapshot = try await open(runtime, facts: facts)
    let program = try PortraitVectorizer.program(
      from: portraitTestRaster(), pose: .right, style: .hatch,
      strokeStyle: StrokeStyle(nominalLineWidth: 0.4,
        penProfileID: PenProfileID(fixture.registration.applicability.toolAssembly.rawValue)))
    snapshot = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(projection: snapshot.projection, intent: .selectProgram(program)),
      facts: facts))
    #expect(snapshot.selectedCatalogItemID == nil)
    #expect(snapshot.program == program)
    let plan = try #require(snapshot.plan)
    #expect(plan.strokes.count == program.strokes.count)
    #expect(snapshot.preview?.programContentHash == program.contentHash)
    snapshot = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(projection: snapshot.projection, intent: .setUniformScale(0.1)), facts: facts))
    #expect(snapshot.program == program)
    #expect(snapshot.plan?.contentHash != plan.contentHash)
    let roundTrip = try JSONDecoder().decode(ExecutionPlanRevision.self, from: JSONEncoder().encode(try #require(snapshot.plan)))
    #expect(roundTrip == snapshot.plan)
    snapshot = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(projection: snapshot.projection, intent: .selectCatalogItem(.circle)), facts: facts))
    #expect(snapshot.selectedCatalogItemID == .circle)
    #expect(snapshot.program?.source.kind != "portrait")
    #expect(snapshot.program?.contentHash != program.contentHash)
  }

  @Test("target visibility is independent of Learning and active drawing identity")
  func targetVisibilityDoesNotMutateDrawingAuthority() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let incompleteFacts = fixture.facts(learningComplete: false)
    let initial = await runtime.synchronize(incompleteFacts)
    let opened = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(projection: initial.projection, intent: .showTarget),
      facts: incompleteFacts
    ))
    #expect(opened.isTargetVisible)
    let readyFacts = fixture.facts()

    let busyFacts = fixture.facts(runInProgress: true)
    let busy = await runtime.synchronize(busyFacts)
    let refusedClose = await runtime.submit(
      PlotterDrawingDraftSubmission(projection: busy.projection, intent: .hideTarget),
      facts: busyFacts
    )
    #expect(!((try applied(refusedClose)).isTargetVisible))
    #expect(refusedClose.snapshot.projection.draftRevision == busy.projection.draftRevision)
    #expect(refusedClose.snapshot.plan?.revisionID == busy.plan?.revisionID)

    let readyAgain = await runtime.synchronize(readyFacts)
    let closed = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(projection: readyAgain.projection, intent: .hideTarget),
      facts: readyFacts
    ))
    #expect(!closed.isTargetVisible)

    let refusedEdit = await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: closed.projection,
        intent: .selectCatalogItem(.circle)
      ),
      facts: readyFacts
    )
    let hiddenEdit = try applied(refusedEdit)
    #expect(hiddenEdit.selectedCatalogItemID == .circle)
    #expect(!hiddenEdit.isTargetVisible)
  }

  @Test("request identity and both draft and external fact revisions reject stale submissions")
  func requestAndProjectionStaleness() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let facts = fixture.facts()
    let opened = try await open(runtime, facts: facts)
    let staleProjection = opened.projection
    let selected = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: staleProjection,
        intent: .selectCatalogItem(.elephant)
      ),
      facts: facts
    ))
    let staleRequestID = PlotterDrawingDraftRequestID(
      rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
    )
    let staleDraft = await runtime.submit(
      PlotterDrawingDraftSubmission(
        requestID: staleRequestID,
        projection: staleProjection,
        intent: .setRotationDegrees(15)
      ),
      facts: facts
    )
    let draftRefusal = try refusal(staleDraft)

    #expect(draftRefusal.requestID == staleRequestID)
    #expect(draftRefusal.reason == .staleProjection)
    #expect(draftRefusal.comparedDraftRevision == selected.projection.draftRevision)
    #expect(staleDraft.snapshot.selectedCatalogItemID == .elephant)

    let newerFrame = try replacingFrame(fixture.frame, id: "draft-newer", sequenceDelta: 1)
    let newerFacts = fixture.facts(displayedFrame: newerFrame)
    let externalRequestID = PlotterDrawingDraftRequestID(
      rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!
    )
    let staleExternal = await runtime.submit(
      PlotterDrawingDraftSubmission(
        requestID: externalRequestID,
        projection: selected.projection,
        intent: .assertPaperCoverage
      ),
      facts: newerFacts
    )
    let externalRefusal = try refusal(staleExternal)
    #expect(externalRefusal.requestID == externalRequestID)
    #expect(externalRefusal.reason == .staleProjection)
    #expect(externalRefusal.comparedExternalFacts.displayedFrame == newerFrame.plotterExactFrameReference)
  }

  @Test("catalog program placement and plan identities are deterministic")
  func deterministicContentIdentity() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let facts = fixture.facts()
    let firstRuntime = PlotterDrawingDraftRuntime()
    let secondRuntime = PlotterDrawingDraftRuntime()
    let first = await firstRuntime.synchronize(facts)
    let second = await secondRuntime.synchronize(facts)

    #expect(first.catalog == DrawingProgramCatalog.entries)
    #expect(first.catalog.map(\.id) == DrawingCatalogEntryID.allCases)
    #expect(first.program == second.program)
    #expect(first.program?.contentHash == second.program?.contentHash)
    #expect(first.plan?.placement == second.plan?.placement)
    #expect(first.plan?.revisionID == second.plan?.revisionID)
    #expect(first.plan?.contentHash == second.plan?.contentHash)

    let opened = try await open(firstRuntime, facts: facts)
    let priorPlacementID = opened.placementID
    let selected = try applied(await firstRuntime.submit(
      PlotterDrawingDraftSubmission(
        projection: opened.projection,
        intent: .selectCatalogItem(.circle)
      ),
      facts: facts
    ))
    let expectedCircle = try DrawingProgramCatalog.program(
      for: .circle,
      style: StrokeStyle(
        nominalLineWidth: 0.4,
        penProfileID: PenProfileID(fixture.registration.applicability.toolAssembly.rawValue)
      )
    )
    #expect(selected.placementID != priorPlacementID)
    #expect(selected.program?.id == expectedCircle.id)
    #expect(selected.plan?.sourceProgramContentHash == selected.program?.contentHash)
  }

  @Test("ordinary drawing needs no pre-run role choice and invalid transforms do not mutate")
  func ordinaryRoleAndParameterValidation() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let facts = fixture.facts()
    let snapshot = try await open(runtime, facts: facts)
    #expect(snapshot.evidenceRole == .ordinaryDrawing)

    let revisionBeforeInvalid = snapshot.projection.draftRevision
    let placementBeforeInvalid = snapshot.placementID
    let invalidScale = await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: snapshot.projection,
        intent: .setUniformScale(.nan)
      ),
      facts: facts
    )
    let invalidScaleRefusal = try refusal(invalidScale)
    #expect(invalidScaleRefusal.reason == .invalidScale)
    #expect(invalidScale.snapshot.projection.draftRevision == revisionBeforeInvalid)
    #expect(invalidScale.snapshot.placementID == placementBeforeInvalid)

    let invalidRotation = await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: invalidScale.snapshot.projection,
        intent: .setRotationDegrees(.infinity)
      ),
      facts: facts
    )
    let invalidRotationRefusal = try refusal(invalidRotation)
    #expect(invalidRotationRefusal.reason == .invalidRotation)
    #expect(invalidRotation.snapshot.projection.draftRevision == revisionBeforeInvalid)
    #expect(invalidRotation.snapshot.placementID == placementBeforeInvalid)
  }

  @Test("camera placement requires the current exact frame and accepted registration")
  func exactFrameAndRegistrationPlacementRefusals() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let facts = fixture.facts()
    let opened = try await open(runtime, facts: facts)
    let staleFrame = try replacingFrame(fixture.frame, id: "stale-placement", sequenceDelta: 1)
    let point = try Point2<CameraPixelSpace>(x: 100, y: 100)
    let stalePlacement = await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: opened.projection,
        intent: .placeAtCameraPoint(PlotterDrawingDraftCameraPlacement(
          frame: staleFrame.plotterExactFrameReference,
          point: point
        ))
      ),
      facts: facts
    )
    let frameRefusal = try refusal(stalePlacement)
    #expect(frameRefusal.owner.rawValue == "CameraEvidenceAuthority")
    #expect(frameRefusal.reason == .exactFrameMismatch)
    #expect(frameRefusal.remedy == "Place the target from the currently displayed exact frame.")

    let missingRegistrationFacts = fixture.facts(
      displayedFrame: fixture.frame,
      opticalConfiguration: fixture.opticalConfiguration,
      registration: nil,
      drawableRegion: fixture.drawableRegion
    )
    let missing = await runtime.synchronize(missingRegistrationFacts)
    let registrationPlacement = await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: missing.projection,
        intent: .placeAtCameraPoint(PlotterDrawingDraftCameraPlacement(
          frame: fixture.frame.plotterExactFrameReference,
          point: point
        ))
      ),
      facts: missingRegistrationFacts
    )
    let registrationRefusal = try refusal(registrationPlacement)
    #expect(registrationRefusal.owner.rawValue == "TipCameraRegistration")
    #expect(registrationRefusal.reason == .registrationUnavailable)
    #expect(
      registrationRefusal.remedy
        == "Restore a current accepted pen-tip registration before placing the target."
    )
  }

  @Test("scale rotation and center rebuild one immutable planned placement")
  func scaleRotationAndCenterPlanning() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let facts = fixture.facts()
    var snapshot = try await open(runtime, facts: facts)
    let requestedScale = snapshot.allowedScale.upperBound + 1
    let beforeInvalidScale = snapshot
    let invalidScale = await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: snapshot.projection,
        intent: .setUniformScale(requestedScale)
      ),
      facts: facts
    )
    let scaleRefusal = try refusal(invalidScale)
    #expect(scaleRefusal.owner.rawValue == "PlotterModel.ExecutionPlanRevision")
    #expect(scaleRefusal.reason == .invalidScale)
    #expect(
      scaleRefusal.remedy
        == "Choose a positive finite scale within the published allowed range."
    )
    #expect(invalidScale.snapshot.projection.draftRevision == beforeInvalidScale.projection.draftRevision)
    #expect(invalidScale.snapshot.placementID == beforeInvalidScale.placementID)
    #expect(invalidScale.snapshot.uniformScale == beforeInvalidScale.uniformScale)
    #expect(invalidScale.snapshot.program == beforeInvalidScale.program)
    #expect(invalidScale.snapshot.plan == beforeInvalidScale.plan)

    snapshot = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: invalidScale.snapshot.projection,
        intent: .setUniformScale(invalidScale.snapshot.allowedScale.upperBound)
      ),
      facts: facts
    ))
    #expect(snapshot.uniformScale == snapshot.allowedScale.upperBound)

    snapshot = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: snapshot.projection,
        intent: .setRotationDegrees(450)
      ),
      facts: facts
    ))
    #expect(snapshot.rotationDegrees == 90)

    snapshot = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: snapshot.projection,
        intent: .centerInDrawableRegion
      ),
      facts: facts
    ))
    let bounds = fixture.drawableRegion.effectiveBounds
    let expectedCenter = try Point2<MachineSpace>(
      x: (bounds.minX + bounds.maxX) / 2,
      y: (bounds.minY + bounds.maxY) / 2
    )
    let plan = try #require(snapshot.plan)
    #expect(snapshot.machineCenter == expectedCenter)
    #expect(plan.placement.machineAnchor == expectedCenter)
    #expect(plan.placement.uniformScale == snapshot.allowedScale.upperBound)
    #expect(abs(plan.placement.rotationRadians - .pi / 2) < 1e-12)
  }

  @Test("outside-region planning refuses the complete plan without clipping strokes")
  func outsideRegionRefusesWithoutClipping() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let facts = fixture.facts()
    var snapshot = try await open(runtime, facts: facts)
    snapshot = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: snapshot.projection,
        intent: .setUniformScale(0.02)
      ),
      facts: facts
    ))
    let bounds = fixture.drawableRegion.effectiveBounds
    let outsideCenter = try Point2<MachineSpace>(
      x: bounds.minX,
      y: (bounds.minY + bounds.maxY) / 2
    )
    let cameraPoint = try fixture.registration.cameraFromMachine.applying(to: outsideCenter)
    snapshot = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: snapshot.projection,
        intent: .placeAtCameraPoint(PlotterDrawingDraftCameraPlacement(
          frame: fixture.frame.plotterExactFrameReference,
          point: cameraPoint
        ))
      ),
      facts: facts
    ))

    let preservedCenter = try #require(snapshot.machineCenter)
    #expect(preservedCenter.x.isFinite)
    #expect(preservedCenter.y.isFinite)
    #expect(abs(preservedCenter.x - outsideCenter.x) <= 1e-9)
    #expect(abs(preservedCenter.y - outsideCenter.y) <= 1e-9)
    #expect(snapshot.program != nil)
    #expect(snapshot.plan == nil)
    guard let planningReason = snapshot.planningRefusal?.reason,
      case .planningFailed = planningReason
    else {
      Issue.record("Expected typed planningFailed refusal for the unclipped plan.")
      return
    }
    guard let previewStatus = snapshot.preview?.status,
      case .outsideDrawableRegion = previewStatus
    else {
      Issue.record("Expected an outside-region diagnostic preview.")
      return
    }
    #expect(snapshot.preview?.strokes.isEmpty == true)
  }

  @Test("retained Drawing Border planning uses the adapter without draft mutation authority")
  func retainedBorderPlanningDoesNotMutateDraft() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let facts = fixture.facts()
    let before = await runtime.synchronize(facts)
    let program = try #require(before.program)
    let draftPlan = try #require(before.plan)

    let retained = try PlotterDrawingPlanningAdapter.planRetainedDrawingBorder(
      program: program,
      placement: draftPlan.placement,
      drawableRegion: fixture.drawableRegion,
      provenance: draftPlan.provenance
    )
    let after = await runtime.synchronize(facts)

    #expect(retained == draftPlan)
    #expect(after.projection == before.projection)
    #expect(after.placementID == before.placementID)
    #expect(!after.isTargetVisible)
    #expect(after.lastSubmissionRefusal == nil)
  }

  @Test("target persists on compatible frames and outside tip applicability remains diagnostic only")
  func previewExactFrameAndDiagnosticApplicability() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let facts = fixture.facts()
    var snapshot = try await open(runtime, facts: facts)
    snapshot = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: snapshot.projection,
        intent: .setUniformScale(0.02)
      ),
      facts: facts
    ))
    let bounds = fixture.drawableRegion.effectiveBounds
    let diagnosticCenter = try Point2<MachineSpace>(
      x: bounds.minX + 5,
      y: (bounds.minY + bounds.maxY) / 2
    )
    #expect(diagnosticCenter.x < fixture.registration.applicabilityRectangle.minX)
    let cameraPoint = try fixture.registration.cameraFromMachine.applying(to: diagnosticCenter)
    snapshot = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: snapshot.projection,
        intent: .placeAtCameraPoint(PlotterDrawingDraftCameraPlacement(
          frame: fixture.frame.plotterExactFrameReference,
          point: cameraPoint
        ))
      ),
      facts: facts
    ))
    let preview = try #require(snapshot.preview)
    guard case .diagnosticOnly(let limitation) = preview.status else {
      Issue.record("Expected a diagnostic-only tip-applicability preview.")
      return
    }
    #expect(limitation.registrationRevisionID == fixture.registration.acceptedRevisionID)
    #expect(preview.planRevisionID == snapshot.plan?.revisionID)
    #expect(preview.programContentHash == snapshot.program?.contentHash)
    #expect(preview.displayedFrame == fixture.frame)
    #expect(facts.revisions.environment == .simulated)

    let presentationPreview = DrawingStudioTargetPreview(
      provenance: ExactFrameOverlayProvenance(preview.displayedFrame),
      strokes: preview.strokes,
      bounds: preview.bounds,
      programContentHash: preview.programContentHash.description,
      executionPlanContentHash: preview.planRevisionID?.description,
      status: .diagnosticOnly(reason: "SIMULATED diagnostic projection; not physical evidence.")
    )
    let newer = try replacingFrame(fixture.frame, id: "preview-newer", sequenceDelta: 1)
    #expect(presentationPreview.matches(fixture.frame))
    #expect(presentationPreview.matches(newer))
  }

  @Test("nominal paper save completes before the accepted snapshot is published")
  func paperPersistenceSaveBeforePublish() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let persistence = DraftPaperPersistenceProbe(blocksSave: true)
    let runtime = PlotterDrawingDraftRuntime(
      paperPersistence: persistence,
      clock: DraftRuntimeClock(now: fixture.frame.frame.captureNanoseconds + 100)
    )
    let facts = fixture.facts(environment: .live)
    let opened = try await open(runtime, facts: facts)
    let completion = DraftSubmissionCompletionProbe()
    let task = Task {
      let result = await runtime.submit(
        PlotterDrawingDraftSubmission(
          projection: opened.projection,
          intent: .assertPaperCoverage
        ),
        facts: facts
      )
      await completion.markCompleted()
      return result
    }

    await persistence.waitUntilSaveStarted()
    let completedBeforeSave = await completion.completed
    #expect(!completedBeforeSave)
    await persistence.releaseSave()
    let result = await task.value
    let published = try applied(result)
    let saved = await persistence.storedObservation
    let saveCount = await persistence.saveCount

    #expect(saved?.id == published.paperCoverageObservation?.id)
    #expect(published.paperCoverageObservation != nil)
    #expect(published.paperCoverageIsCurrent)
    #expect(saveCount == 1)
    #expect(fixture.frame.source == .simulated)
  }

  @Test("paper save serializes a queued same-projection edit through the runtime FIFO")
  func paperPersistenceSerializesQueuedEdit() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let persistence = DraftPaperPersistenceProbe(blocksSave: true)
    let runtime = PlotterDrawingDraftRuntime(
      paperPersistence: persistence,
      clock: DraftRuntimeClock(now: fixture.frame.frame.captureNanoseconds + 100)
    )
    let facts = fixture.facts(environment: .live)
    let opened = try await open(runtime, facts: facts)
    let assertionCompletion = DraftSubmissionCompletionProbe()
    let assertionTask = Task {
      let result = await runtime.submit(
        PlotterDrawingDraftSubmission(
          projection: opened.projection,
          intent: .assertPaperCoverage
        ),
        facts: facts
      )
      await assertionCompletion.markCompleted()
      return result
    }

    await persistence.waitUntilSaveStarted()
    let queuedEdit = DraftSubmissionInterleavingProbe()
    let editTask = Task {
      await queuedEdit.markStarted()
      let result = await runtime.submit(
        PlotterDrawingDraftSubmission(
          projection: opened.projection,
          intent: .setRotationDegrees(15)
        ),
        facts: facts
      )
      await queuedEdit.markCompleted()
      return result
    }
    await queuedEdit.waitUntilStarted()

    #expect(!(await assertionCompletion.completed))
    #expect(!(await queuedEdit.completed))
    #expect(await persistence.storedObservation == nil)
    #expect(await persistence.saveCount == 1)

    await persistence.releaseSave()
    let asserted = try applied(await assertionTask.value)
    let staleEditResult = await editTask.value
    let staleEdit = try refusal(staleEditResult)
    let final = await runtime.synchronize(facts)

    #expect(staleEdit.owner.rawValue == "PlotterDrawingDraftRuntime")
    #expect(staleEdit.reason == .staleProjection)
    #expect(staleEdit.comparedDraftRevision == asserted.projection.draftRevision)
    #expect(
      staleEdit.remedy
        == "Use the current Drawing Studio projection and retry the requested edit."
    )
    #expect(staleEditResult.snapshot.evidenceRole == opened.evidenceRole)
    #expect(staleEditResult.snapshot.paperCoverageObservation == asserted.paperCoverageObservation)
    #expect(staleEditResult.snapshot.projection.draftRevision == asserted.projection.draftRevision)
    #expect(final.evidenceRole == opened.evidenceRole)
    #expect(final.paperCoverageObservation == asserted.paperCoverageObservation)
    #expect(final.paperCoverageIsCurrent)
    #expect(await persistence.storedObservation == asserted.paperCoverageObservation)
  }

  @Test("paper persistence failure refuses without publishing an assertion")
  func paperPersistenceFailureDoesNotPublish() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let persistence = DraftPaperPersistenceProbe(failsSave: true)
    let runtime = PlotterDrawingDraftRuntime(paperPersistence: persistence)
    let facts = fixture.facts(environment: .live)
    let opened = try await open(runtime, facts: facts)
    let result = await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: opened.projection,
        intent: .assertPaperCoverage
      ),
      facts: facts
    )
    let persistenceRefusal = try refusal(result)

    #expect(persistenceRefusal.owner.rawValue == "PlotterPaperCoverageAuthority")
    guard case .paperPersistenceFailed = persistenceRefusal.reason else {
      Issue.record("Expected typed paperPersistenceFailed refusal.")
      return
    }
    #expect(result.snapshot.paperCoverageObservation == nil)
    #expect(result.snapshot.projection.draftRevision == opened.projection.draftRevision)
    let storedObservation = await persistence.storedObservation
    #expect(storedObservation == nil)
  }

  @Test("paper polygon displays only on its exact frame but remains current on a newer frame")
  func paperExactFrameDisplayAndNewerFrameCurrentness() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime(clock: DraftRuntimeClock(
      now: fixture.frame.frame.captureNanoseconds + 100
    ))
    let facts = fixture.facts()
    let opened = try await open(runtime, facts: facts)
    let accepted = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: opened.projection,
        intent: .assertPaperCoverage
      ),
      facts: facts
    ))
    let exactDisplay = try #require(accepted.paperCoverageDisplay)
    #expect(accepted.paperCoverageIsCurrent)
    #expect(exactDisplay.frame == ExactFrameProvenance(frame: fixture.frame.frame))
    #expect(exactDisplay.polygon.count == 4)

    let newerFrame = try replacingFrame(fixture.frame, id: "paper-newer", sequenceDelta: 1)
    let newer = await runtime.synchronize(fixture.facts(displayedFrame: newerFrame))
    #expect(newer.paperCoverageObservation?.id == accepted.paperCoverageObservation?.id)
    #expect(newer.paperCoverageIsCurrent)
    #expect(newer.paperCoverageDisplay == nil)
  }

  @Test("paper currentness rejects paper source configuration and contact-plane changes")
  func paperCurrentnessInvalidations() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime(clock: DraftRuntimeClock(
      now: fixture.frame.frame.captureNanoseconds + 100
    ))
    let facts = fixture.facts()
    let opened = try await open(runtime, facts: facts)
    _ = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: opened.projection,
        intent: .assertPaperCoverage
      ),
      facts: facts
    ))

    let newPaper = PaperRevisionContext(
      instance: PaperInstanceRevision(),
      contactPlane: fixture.paper.contactPlane
    )
    #expect(!(await runtime.synchronize(fixture.facts(paper: newPaper))).paperCoverageIsCurrent)

    let newPlane = PaperRevisionContext(
      instance: fixture.paper.instance,
      contactPlane: PaperContactPlaneRevision()
    )
    #expect(!(await runtime.synchronize(fixture.facts(paper: newPlane))).paperCoverageIsCurrent)

    let newSourceFrame = try replacingFrame(
      fixture.frame,
      id: "paper-source",
      sequenceDelta: 1,
      source: .live(CameraDeviceID(rawValue: "different-source"))
    )
    #expect(
      !(await runtime.synchronize(fixture.facts(displayedFrame: newSourceFrame)))
        .paperCoverageIsCurrent
    )

    let newConfigurationFrame = try replacingFrame(
      fixture.frame,
      id: "paper-configuration",
      sequenceDelta: 2,
      cameraConfigurationID: CameraConfigurationID()
    )
    #expect(
      (await runtime.synchronize(fixture.facts(displayedFrame: newConfigurationFrame)))
        .paperCoverageIsCurrent
    )
  }

  @Test("retained terminal requires an EA-08B-authorized new-plan handoff")
  func retainedTerminalNewPlanHandoff() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let normalFacts = fixture.facts()
    let opened = try await open(runtime, facts: normalFacts)
    let terminalFacts = fixture.facts(terminalRequiresNewPlan: true)
    let terminal = await runtime.synchronize(terminalFacts)

    let editResult = await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: terminal.projection,
        intent: .selectCatalogItem(.star)
      ),
      facts: terminalFacts
    )
    let editRefusal = try refusal(editResult)
    #expect(editRefusal.owner.rawValue == "PlotterDrawingRunAuthority")
    #expect(editRefusal.reason == .terminalRunRequiresHandoff)
    #expect(
      editRefusal.remedy
        == "Use New Drawing to clear the retained terminal before editing a new plan."
    )

    let directNewPlan = await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: terminal.projection,
        intent: .beginNewPlan
      ),
      facts: terminalFacts
    )
    let directNewPlanRefusal = try refusal(directNewPlan)
    #expect(directNewPlanRefusal.reason == .terminalRunRequiresHandoff)

    let authorizedFacts = fixture.facts(terminalRequiresNewPlan: false)
    let authorized = await runtime.synchronize(authorizedFacts)
    let handedOff = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: authorized.projection,
        intent: .beginNewPlan
      ),
      facts: authorizedFacts
    ))
    #expect(handedOff.placementID != opened.placementID)
    #expect(handedOff.lastSubmissionRefusal == nil)
    #expect(handedOff.plan?.revisionID == authorized.plan?.revisionID)
  }

  @Test("draft actions invoke no machine Stop camera Vision run evidence or physical effect")
  func draftActionsHaveNoPhysicalOrEvidenceEffects() async throws {
    let draftRuntime = PlotterDrawingDraftRuntime()
    let harness = makeCausalSimulatorAppFixture(drawingDraftRuntime: draftRuntime)
    let workspace = harness.workspace
    try await completeSimulatedPenInteractionPrerequisite(workspace)
    try await installAcceptedBoundaryTestProjection(
      runtime: harness.boundaryRuntime,
      workspace: workspace,
      environment: .simulated
    )
    try await completeSimulatedTipCalibration(workspace, simulator: harness.simulator)
    let fixture = try draftAuthorityFixture(from: workspace)
    let facts = fixture.facts()
    let simulatorBefore = await harness.simulator.snapshot()
    let inkBefore = await harness.simulator.persistentInk()
    let visionBefore = workspace.visionAnalysisSnapshot
    let drawingEvidenceErrorBefore = workspace.drawingEvidenceError
    let comparisonAvailableBefore = workspace.completedDrawingComparisonReviewIsAvailable
    let comparisonPinnedBefore = workspace.completedDrawingComparisonReviewIsPinned
    let stopMutationsBefore =
      workspace.computationDiagnosticsForTesting.stoppableOperationMutationCount

    var snapshot = try await open(draftRuntime, facts: facts)
    let intents: [PlotterDrawingDraftIntent] = [
      .selectCatalogItem(.triangle),
      .setUniformScale(0.03),
      .setRotationDegrees(15),
      .centerInDrawableRegion,
      .assertPaperCoverage,
    ]
    for intent in intents {
      snapshot = try applied(await draftRuntime.submit(
        PlotterDrawingDraftSubmission(projection: snapshot.projection, intent: intent),
        facts: facts
      ))
    }

    #expect(await harness.simulator.snapshot() == simulatorBefore)
    #expect(await harness.simulator.persistentInk() == inkBefore)
    #expect(workspace.visionAnalysisSnapshot == visionBefore)
    let retainedRunSideEffect: Bool = switch workspace.testDrawingStudioPresentation.runState {
    case .running, .processing, .terminal, .publicationFailed, .reviewAvailable, .reviewing: true
    case .unavailable, .ready: false
    }
    #expect(!retainedRunSideEffect)
    #expect(workspace.drawingEvidenceError == drawingEvidenceErrorBefore)
    #expect(workspace.completedDrawingComparisonReviewIsAvailable == comparisonAvailableBefore)
    #expect(workspace.completedDrawingComparisonReviewIsPinned == comparisonPinnedBefore)
    #expect(
      workspace.computationDiagnosticsForTesting.stoppableOperationMutationCount
        == stopMutationsBefore
    )
    #expect(workspace.contextualStopPresentation == nil)
    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.frameMode == .simulated)
    #expect(facts.revisions.environment == .simulated)
    #expect(snapshot.paperCoverageObservation?.source == .simulated)
    await workspace.shutdown()
  }
}

private enum DrawingDraftEpisodeTestError: Error {
  case expectedApplied
  case expectedRefusal
}

private func applied(
  _ result: PlotterDrawingDraftSubmissionResult
) throws -> PlotterDrawingDraftSnapshot {
  guard case .applied = result.disposition else {
    Issue.record("Expected an applied drawing-draft submission; got \(result.disposition).")
    throw DrawingDraftEpisodeTestError.expectedApplied
  }
  return result.snapshot
}

private func refusal(
  _ result: PlotterDrawingDraftSubmissionResult
) throws -> PlotterDrawingDraftRefusal {
  guard case .refused(let refusal) = result.disposition else {
    Issue.record("Expected a refused drawing-draft submission; got \(result.disposition).")
    throw DrawingDraftEpisodeTestError.expectedRefusal
  }
  return refusal
}

private func open(
  _ runtime: PlotterDrawingDraftRuntime,
  facts: PlotterDrawingDraftExternalFacts
) async throws -> PlotterDrawingDraftSnapshot {
  let current = await runtime.synchronize(facts)
  return try applied(await runtime.submit(
    PlotterDrawingDraftSubmission(projection: current.projection, intent: .showTarget),
    facts: facts
  ))
}

private struct DrawingDraftAuthorityFixture: Sendable {
  let frame: DisplayedFrame
  let opticalConfiguration: CameraOpticalConfigurationIdentity
  let registration: TipCameraRegistration
  let drawableRegion: DrawableMachineRegion
  let paper: PaperRevisionContext

  func facts(
    environment: PlotterEnvironment = .simulated,
    learningComplete: Bool = true,
    runInProgress: Bool = false,
    terminalRequiresNewPlan: Bool = false,
    paper: PaperRevisionContext? = nil
  ) -> PlotterDrawingDraftExternalFacts {
    facts(
      environment: environment,
      learningComplete: learningComplete,
      displayedFrame: frame,
      opticalConfiguration: opticalConfiguration,
      registration: registration,
      drawableRegion: drawableRegion,
      runInProgress: runInProgress,
      terminalRequiresNewPlan: terminalRequiresNewPlan,
      paper: paper ?? self.paper
    )
  }

  func facts(
    displayedFrame: DisplayedFrame
  ) -> PlotterDrawingDraftExternalFacts {
    facts(
      environment: .simulated,
      learningComplete: true,
      displayedFrame: displayedFrame,
      opticalConfiguration: opticalConfiguration,
      registration: registration,
      drawableRegion: drawableRegion,
      runInProgress: false,
      terminalRequiresNewPlan: false,
      paper: paper
    )
  }

  func facts(
    displayedFrame: DisplayedFrame,
    opticalConfiguration: CameraOpticalConfigurationIdentity?,
    registration: TipCameraRegistration?,
    drawableRegion: DrawableMachineRegion?
  ) -> PlotterDrawingDraftExternalFacts {
    facts(
      environment: .simulated,
      learningComplete: true,
      displayedFrame: displayedFrame,
      opticalConfiguration: opticalConfiguration,
      registration: registration,
      drawableRegion: drawableRegion,
      runInProgress: false,
      terminalRequiresNewPlan: false,
      paper: paper
    )
  }

  private func facts(
    environment: PlotterEnvironment,
    learningComplete: Bool,
    displayedFrame: DisplayedFrame?,
    opticalConfiguration: CameraOpticalConfigurationIdentity?,
    registration: TipCameraRegistration?,
    drawableRegion: DrawableMachineRegion?,
    runInProgress: Bool,
    terminalRequiresNewPlan: Bool,
    paper: PaperRevisionContext
  ) -> PlotterDrawingDraftExternalFacts {
    PlotterDrawingDraftExternalFacts(
      environment: environment,
      interactiveLearningIsComplete: learningComplete,
      displayedFrame: displayedFrame,
      opticalConfiguration: opticalConfiguration,
      registration: registration,
      drawableRegion: drawableRegion,
      toolAssemblyRevision: self.registration.applicability.toolAssembly,
      paper: paper,
      runInProgress: runInProgress,
      terminalRequiresNewPlan: terminalRequiresNewPlan
    )
  }
}

@MainActor
private enum DrawingDraftAuthorityFixtureCache {
  private static var cached: DrawingDraftAuthorityFixture?

  static func load() async throws -> DrawingDraftAuthorityFixture {
    if let cached { return cached }
    let harness = makeCausalSimulatorAppFixture()
    try await completeSimulatedPenInteractionPrerequisite(harness.workspace)
    try await installAcceptedBoundaryTestProjection(
      runtime: harness.boundaryRuntime,
      workspace: harness.workspace,
      environment: .simulated
    )
    try await completeSimulatedTipCalibration(
      harness.workspace,
      simulator: harness.simulator
    )
    let fixture = try draftAuthorityFixture(from: harness.workspace)
    await harness.workspace.shutdown()
    cached = fixture
    return fixture
  }
}

@MainActor
private func draftAuthorityFixture(
  from workspace: PlotterApplicationRuntime
) throws -> DrawingDraftAuthorityFixture {
  let registration = try #require(workspace.tipCameraRegistration)
  return DrawingDraftAuthorityFixture(
    frame: try #require(workspace.displayedFrame),
    opticalConfiguration: registration.applicability.opticalConfiguration,
    registration: registration,
    drawableRegion: try #require(workspace.currentDrawableMachineRegion),
    paper: workspace.currentPaperRevisionContext
  )
}

private func replacingFrame(
  _ frame: DisplayedFrame,
  id: String,
  sequenceDelta: UInt64,
  source: FrameSourceIdentity? = nil,
  cameraConfigurationID: CameraConfigurationID? = nil
) throws -> DisplayedFrame {
  DisplayedFrame(
    source: source ?? frame.source,
    frame: try StampedFrame(
      id: FrameID(rawValue: id),
      sequence: frame.frame.sequence + sequenceDelta,
      captureNanoseconds: frame.frame.captureNanoseconds + sequenceDelta,
      cameraConfigurationID: cameraConfigurationID ?? frame.frame.cameraConfigurationID,
      width: frame.frame.width,
      height: frame.frame.height,
      rowBytes: frame.frame.rowBytes,
      pixelFormat: frame.frame.pixelFormat,
      bytes: frame.frame.bytes
    )
  )
}

private struct DraftRuntimeClock: RuntimeClock {
  let now: UInt64

  func nowNanoseconds() -> UInt64 { now }

  func sleep(nanoseconds: UInt64) async throws {
    try await Task.sleep(nanoseconds: nanoseconds)
  }
}

private enum DraftPaperPersistenceError: Error {
  case saveFailed
}

private actor DraftPaperPersistenceProbe: PlotterDrawingDraftPaperPersistence {
  private let blocksSave: Bool
  private let failsSave: Bool
  private var saveStarted = false
  private var saveStartedWaiters: [CheckedContinuation<Void, Never>] = []
  private var saveRelease: CheckedContinuation<Void, Never>?
  private var saveWasReleased = false
  private(set) var storedObservation: PaperCoverageObservation?
  private(set) var saveCount = 0

  init(blocksSave: Bool = false, failsSave: Bool = false) {
    self.blocksSave = blocksSave
    self.failsSave = failsSave
  }

  func load() -> PaperCoverageObservation? { storedObservation }

  func save(_ observation: PaperCoverageObservation) async throws {
    saveCount += 1
    saveStarted = true
    let waiters = saveStartedWaiters
    saveStartedWaiters.removeAll()
    waiters.forEach { $0.resume() }
    if blocksSave, !saveWasReleased {
      await withCheckedContinuation { continuation in
        saveRelease = continuation
      }
    }
    if failsSave { throw DraftPaperPersistenceError.saveFailed }
    storedObservation = observation
  }

  func clear() {
    storedObservation = nil
  }

  func waitUntilSaveStarted() async {
    if saveStarted { return }
    await withCheckedContinuation { continuation in
      saveStartedWaiters.append(continuation)
    }
  }

  func releaseSave() {
    saveWasReleased = true
    saveRelease?.resume()
    saveRelease = nil
  }
}

private actor DraftSubmissionCompletionProbe {
  private(set) var completed = false

  func markCompleted() {
    completed = true
  }
}

private actor DraftSubmissionInterleavingProbe {
  private var started = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private(set) var completed = false

  func markStarted() {
    started = true
    let waiters = startWaiters
    startWaiters.removeAll()
    waiters.forEach { $0.resume() }
  }

  func waitUntilStarted() async {
    if started { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }

  func markCompleted() {
    completed = true
  }
}
