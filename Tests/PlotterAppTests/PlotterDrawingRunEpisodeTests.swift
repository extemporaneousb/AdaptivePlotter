import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Drawing Studio run episode", .serialized)
@MainActor
struct PlotterDrawingRunEpisodeTests {
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
    #expect(await harness.events.values == ["normalize", "append"])
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
      "normalize", "capture-baseline", "execute", "capture-post", "observe", "append",
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
