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
  @Test("open and close enforce typed prerequisites and exact remedies")
  func openClosePrerequisitesAndRemedies() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let incompleteFacts = fixture.facts(learningComplete: false)
    let initial = await runtime.synchronize(incompleteFacts)
    let refusedOpen = await runtime.submit(
      PlotterDrawingDraftSubmission(projection: initial.projection, intent: .open),
      facts: incompleteFacts
    )
    let learningRefusal = try refusal(refusedOpen)

    #expect(learningRefusal.owner.rawValue == "PlotterLearningAuthority")
    #expect(learningRefusal.reason == .learningIncomplete)
    #expect(learningRefusal.remedy == "Complete Drawing Border validation before opening Drawing Studio.")
    #expect(!refusedOpen.snapshot.isOpen)

    let readyFacts = fixture.facts()
    let synchronized = await runtime.synchronize(readyFacts)
    let opened = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(projection: synchronized.projection, intent: .open),
      facts: readyFacts
    ))
    #expect(opened.isOpen)

    let busyFacts = fixture.facts(runInProgress: true)
    let busy = await runtime.synchronize(busyFacts)
    let refusedClose = await runtime.submit(
      PlotterDrawingDraftSubmission(projection: busy.projection, intent: .close),
      facts: busyFacts
    )
    let runRefusal = try refusal(refusedClose)
    #expect(runRefusal.owner.rawValue == "PlotterDrawingRunAuthority")
    #expect(runRefusal.reason == .retainedRunOwnsMutation)
    #expect(runRefusal.remedy == "Wait for the current drawing run and evidence capture to settle.")
    #expect(refusedClose.snapshot.isOpen)

    let readyAgain = await runtime.synchronize(readyFacts)
    let closed = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(projection: readyAgain.projection, intent: .close),
      facts: readyFacts
    ))
    #expect(!closed.isOpen)

    let refusedEdit = await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: closed.projection,
        intent: .selectCatalogItem(.circle)
      ),
      facts: readyFacts
    )
    let closedRefusal = try refusal(refusedEdit)
    #expect(closedRefusal.owner.rawValue == "PlotterDrawingDraftRuntime")
    #expect(closedRefusal.reason == .studioClosed)
    #expect(closedRefusal.remedy == "Open Drawing Studio before changing its draft.")
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
        intent: .setEvidenceRole(.training)
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
        intent: .setEvidenceRole(.reservedHoldout)
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

  @Test("evidence roles are typed metadata and invalid transform parameters do not mutate")
  func evidenceRoleAndParameterValidation() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let facts = fixture.facts()
    var snapshot = try await open(runtime, facts: facts)
    let planID = try #require(snapshot.plan?.revisionID)

    for role in DrawingTrialEvidenceRole.allCases {
      snapshot = try applied(await runtime.submit(
        PlotterDrawingDraftSubmission(
          projection: snapshot.projection,
          intent: .setEvidenceRole(role)
        ),
        facts: facts
      ))
      #expect(snapshot.evidenceRole == role)
      #expect(snapshot.plan?.revisionID == planID)
    }

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
    #expect(!after.isOpen)
    #expect(after.lastSubmissionRefusal == nil)
  }

  @Test("preview is exact-frame bound and outside tip applicability remains diagnostic only")
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
    #expect(!presentationPreview.matches(newer))
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
          intent: .setEvidenceRole(.training)
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
      !(await runtime.synchronize(fixture.facts(displayedFrame: newConfigurationFrame)))
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
    try await completeSimulatedBoundariesAndCenter(
      workspace,
      simulator: harness.simulator,
      boundaryOrder: [.negativeX, .positiveX, .negativeY, .positiveY]
    )
    try await completeSimulatedSparseTipCalibration(workspace, simulator: harness.simulator)
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
      .setEvidenceRole(.ordinaryDrawing),
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
    let retainedRunSideEffect: Bool = switch workspace.drawingStudioPresentation.runState {
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
    PlotterDrawingDraftSubmission(projection: current.projection, intent: .open),
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
    try await completeSimulatedBoundariesAndCenter(
      harness.workspace,
      simulator: harness.simulator,
      boundaryOrder: [.negativeX, .positiveX, .negativeY, .positiveY]
    )
    try await completeSimulatedSparseTipCalibration(
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
  from workspace: OperatorWorkspace
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
