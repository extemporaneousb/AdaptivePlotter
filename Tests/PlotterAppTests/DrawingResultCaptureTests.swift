import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import Testing
@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Automatic drawing result photographs", .serialized)
struct DrawingResultCaptureTests {
  @Test("completion photograph survives unavailable draft facts without authorizing reveal travel")
  func photographSurvivesChangedFacts() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let gate = DrawingRunPlanGate()
    let harness = await drawingRunHarness(fixture: fixture, planGate: gate)
    let ready = await harness.runtime.synchronize(environment: .live)
    let run = Task { await harness.runtime.submit(.init(projection: ready.projection, intent: .start)) }
    await gate.waitUntilStarted()
    await harness.facts.replace(unavailableFacts(fixture))
    await gate.release(.completed)
    let result = await run.value
    let record = try #require(result.snapshot.terminal?.record)
    let attempt = try #require(record.attemptEvidence)
    #expect(record.executionDisposition == .completed)
    #expect(record.observation == .notAttempted(.frameEvidenceUnavailable))
    #expect(!result.snapshot.physicalEvidenceClaimed)
    #expect(attempt.terminalFrames.count == 1)
    let photo = try #require(attempt.terminalFrames.first)
    #expect(photo.frame == ExactFrameProvenance(frame: fixture.completionFrame.frame))
    #expect(photo.controllerPosition == nil && photo.captureAfterNanoseconds == nil)
    #expect(photo.completionCaptureAfterNanoseconds == fixture.baselineFrame.frame.captureNanoseconds)
    #expect(try await harness.evidence.readMedia(photo) == fixture.completionFrame.frame)
    #expect(await harness.evidence.archive.records.last == record)
    #expect(await harness.camera.requests.count == 2)
    #expect(await harness.vision.requests.isEmpty)
    let events = await harness.events.values
    #expect(!events.suffix(from: try #require(events.firstIndex(of: "execute"))).contains("travel"))
    #expect(attempt.missingCoverageReason?.contains("drawing plan or accepted movement bounds changed") == true)
    #expect(DrawingReviewPhotographs.status(record)?.contains("Photo retained") == true)
  }

  @Test("unavailable completion camera records a visible reason and never substitutes geometry")
  func cameraFailureIsVisible() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let gate = DrawingRunPlanGate()
    let harness = await drawingRunHarness(fixture: fixture, planGate: gate,
      cameraFrames: [fixture.baselineFrame])
    let ready = await harness.runtime.synchronize(environment: .live)
    let run = Task { await harness.runtime.submit(.init(projection: ready.projection, intent: .start)) }
    await gate.waitUntilStarted()
    await harness.facts.replace(unavailableFacts(fixture))
    await gate.release(.completed)
    let result = await run.value
    let record = try #require(result.snapshot.terminal?.record)
    #expect(record.attemptEvidence?.terminalFrames.isEmpty == true)
    #expect(DrawingReviewPhotographs.status(record)?.contains("Result photo unavailable") == true)
    #expect(DrawingReviewPhotographs.status(record)?.contains("Completion photo") == true)
    #expect(!result.snapshot.physicalEvidenceClaimed)
  }

  @Test("completion photo rejects stale or different-camera frames and still attempts matched capture",
    arguments: [0, 1, 2])
  func rejectsInvalidCompletionFrame(_ variant: Int) async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let original = fixture.completionFrame
    let rejected = variant == 0 ? fixture.baselineFrame : try DisplayedFrame(
      source: variant == 1 ? .live(CameraDeviceID(rawValue: "another-camera")) : original.source,
      frame: StampedFrame(id: FrameID(), sequence: original.frame.sequence,
        captureNanoseconds: original.frame.captureNanoseconds,
        cameraConfigurationID: variant == 2 ? CameraConfigurationID() : original.frame.cameraConfigurationID,
        width: original.frame.width, height: original.frame.height, rowBytes: original.frame.rowBytes,
        pixelFormat: original.frame.pixelFormat, bytes: original.frame.bytes))
    let harness = await drawingRunHarness(fixture: fixture,
      cameraFrames: [fixture.baselineFrame, rejected, fixture.postFrame])
    let ready = await harness.runtime.synchronize(environment: .live)
    let result = await harness.runtime.submit(.init(projection: ready.projection, intent: .start))
    let attempt = try #require(result.snapshot.terminal?.record.attemptEvidence)
    #expect(attempt.terminalFrames.count == 1)
    #expect(attempt.terminalFrames.first?.frame == ExactFrameProvenance(frame: fixture.postFrame.frame))
    #expect(result.snapshot.physicalEvidenceClaimed)
  }

  @Test("Stop retains an unsealed preview without camera acquisition or movement")
  func stopRetainsUnsealedPreview() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let original = fixture.completionFrame
    let unsealed = try DisplayedFrame(source: original.source,
      frame: StampedFrame(id: FrameID(), sequence: original.frame.sequence,
        captureNanoseconds: original.frame.captureNanoseconds,
        cameraConfigurationID: original.frame.cameraConfigurationID,
        width: original.frame.width, height: original.frame.height, rowBytes: original.frame.rowBytes,
        pixelFormat: original.frame.pixelFormat, bytes: original.frame.bytes,
        eagerlyMaterializeContentHash: false))
    let gate = DrawingRunPlanGate()
    let harness = await drawingRunHarness(fixture: fixture, planGate: gate)
    let ready = await harness.runtime.synchronize(environment: .live)
    let run = Task { await harness.runtime.submit(.init(projection: ready.projection, intent: .start)) }
    await gate.waitUntilStarted()
    #expect(!unsealed.frame.contentHashIsMaterialized)
    await harness.facts.replace(unavailableFacts(fixture, displayedFrame: unsealed))
    await gate.release(.cancelled)
    let result = await run.value
    let attempt = try #require(result.snapshot.terminal?.record.attemptEvidence)
    #expect(attempt.terminalFrames.first?.frame.frameID == unsealed.frame.id)
    #expect(attempt.terminalFrames.first?.controllerPosition == nil)
    let record = try #require(result.snapshot.terminal?.record)
    #expect(!DrawingReviewPhotographs.hasResultPhoto(record))
    #expect(DrawingReviewPhotographs.status(record)?.contains("may predate completion") == true)
    #expect(unsealed.frame.contentHashMaterializationPurpose == .exactEvidence)
    #expect(await harness.camera.requests.count == 1)
    #expect(await harness.vision.requests.isEmpty)
  }

  @Test("Stop during completion acquisition retains returned bytes but prevents reveal travel")
  func stopDuringCompletionCapture() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let gate = DrawingRunHoldGate()
    let harness = await drawingRunHarness(fixture: fixture)
    await harness.camera.holdCapture(ordinal: 2, at: gate)
    let ready = await harness.runtime.synchronize(environment: .live)
    let run = Task { await harness.runtime.submit(.init(projection: ready.projection, intent: .start)) }
    await gate.waitUntilHeld()
    let active = await harness.runtime.snapshot(environment: .live)
    let stop = try #require(active.stopCapabilityID)
    _ = await harness.runtime.submit(.init(projection: active.projection, intent: .stop(stop)))
    await gate.release()
    let result = await run.value
    #expect(result.snapshot.terminal?.disposition == .cancelled)
    #expect(await harness.camera.requests.count == 2)
    #expect(await harness.vision.requests.isEmpty)
    let events = await harness.events.values
    #expect(!events.suffix(from: try #require(events.firstIndex(of: "execute"))).contains("travel"))
    #expect(result.snapshot.terminal?.record.attemptEvidence?.terminalFrames.first?.frame
      == ExactFrameProvenance(frame: fixture.completionFrame.frame))
  }

  @Test("completion photo save failure retains exact bytes for publication-only recovery")
  func completionMediaRecovery() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let harness = await drawingRunHarness(fixture: fixture)
    await harness.evidence.rejectMediaFrames([fixture.completionFrame.frame.id])
    let ready = await harness.runtime.synchronize(environment: .live)
    let failed = await harness.runtime.submit(.init(projection: ready.projection, intent: .start))
    let terminal = try #require(failed.snapshot.terminal)
    #expect(terminal.disposition == .publicationIncomplete)
    let photo = try #require(terminal.record.attemptEvidence?.terminalFrames.first)
    #expect(photo.frame == ExactFrameProvenance(frame: fixture.completionFrame.frame))
    guard case .failed(_, let capability, _) = failed.snapshot.evidencePersistence else {
      Issue.record("Missing exact publication recovery"); return
    }
    let captures = await harness.camera.requests
    let events = await harness.events.values
    await harness.evidence.rejectMediaFrames([])
    let recovered = await harness.runtime.submit(.init(projection: failed.snapshot.projection,
      intent: .recoverPublication(capability)))
    #expect(recovered.snapshot.terminal?.record == terminal.record)
    #expect(try await harness.evidence.readMedia(photo) == fixture.completionFrame.frame)
    #expect(await harness.camera.requests == captures)
    #expect(await harness.events.values.filter { $0 == "travel" || $0 == "execute" }
      == events.filter { $0 == "travel" || $0 == "execute" })
    if case .persisted = recovered.snapshot.evidencePersistence {} else { Issue.record("Photo was not saved") }
  }

  private func unavailableFacts(_ fixture: DrawingRunEpisodeFixture,
    displayedFrame: DisplayedFrame? = nil) -> PlotterDrawingRunExternalFacts {
    .init(environment: .live, interactiveLearningIsComplete: true, plan: nil,
      paperCoverageIsCurrent: false, displayedFrame: displayedFrame,
      interpreter: drawingRunReadySnapshot(position: fixture.finalPosition),
      penActuationProfile: .initialDefaults, acceptedMovementBounds: fixture.drawableRegion.bounds)
  }
}
