import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import Testing
@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Sparse durable drawing progress photographs", .serialized)
struct DrawingProgressCaptureTests {
  @Test("quarter-run schedule is bounded and never includes the final stroke")
  func boundedSchedule() {
    for count in [0, 1, 2, 3] { #expect(DrawingRunProgressFrame.checkpointCounts(plannedStrokeCount: count).isEmpty) }
    #expect(DrawingRunProgressFrame.checkpointCounts(plannedStrokeCount: 122) == [31, 61, 92])
    #expect(DrawingRunProgressFrame.checkpointCounts(plannedStrokeCount: 10_000) == [2500, 5000, 7500])
  }

  @Test("stages persist before completion and survive reopening without a terminal record")
  func durableStages() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let plan = try fixture.makePlan(catalogItemID: .pyramid)
    let frames = try stageFrames(fixture)
    let harness = await drawingRunHarness(fixture: fixture, facts: fixture.facts(plan: plan),
      cameraFrames: [fixture.baselineFrame] + frames + [fixture.completionFrame, fixture.postFrame])
    await harness.interpreter.enableProgressCheckpoints()
    let gate = DrawingRunHoldGate()
    await harness.camera.holdCapture(ordinal: 5, at: gate)
    let ready = await harness.runtime.synchronize(environment: .live)
    let updates = await harness.runtime.snapshots(environment: .live)
    let publications = Task { () -> [PlotterDrawingRunSnapshot] in
      var values: [PlotterDrawingRunSnapshot] = []
      for await value in updates {
        values.append(value)
        if value.terminal != nil { break }
      }
      return values
    }
    let running = Task { await harness.runtime.submit(.init(projection: ready.projection, intent: .start)) }
    await gate.waitUntilHeld()
    let capturing = await harness.runtime.snapshot(environment: .live)
    let status = DrawingStudioExecutionPresentation(snapshot: capturing, phaseDetail: "Capturing final photo")
    #expect(status.drawingIsDone)
    #expect(status.fraction == 1)
    #expect(!status.finalPhotoIsSaved)
    let reopened = try #require(await harness.evidence.reopenedArchive())
    #expect(reopened.records.isEmpty)
    let attempt = try #require(reopened.incompleteAttempts.first)
    #expect(attempt.progressFrames.map { $0.progress.completedStrokeIDs.count } == [1, 2, 3])
    #expect(attempt.interruptionClassification == .possibleInk)
    for (index, stage) in attempt.progressFrames.enumerated() {
      #expect(try await harness.evidence.readMedia(stage.media) == frames[index].frame)
      #expect(stage.media.controllerPosition == MachinePosition(point: plan.plan.strokes[index].path.end))
      #expect(stage.progress.completedCheckpointIDs == plan.plan.strokes.prefix(index + 1).map(\.endingCheckpointID))
    }
    #expect(throws: DrawingRunEvidenceError.invalidAttemptContext) {
      try DrawingRunProgressFrame.validate(Array(attempt.progressFrames.reversed()), intent: attempt.intent, baselines: attempt.baselines)
    }
    #expect(throws: DrawingRunEvidenceError.invalidAttemptContext) {
      try DrawingRunProgressFrame.validate([attempt.progressFrames[0], attempt.progressFrames[0]], intent: attempt.intent, baselines: attempt.baselines)
    }
    let stageGeometry = try #require(DrawingReviewGeometry.resolve(plan: plan.plan, sourceProgram: plan.program, completedStrokeCount: 2))
    #expect(stageGeometry.preview.plannedStrokes == Array(plan.plan.strokes.prefix(2)))
    #expect(stageGeometry.preview.evidence?.planContentHash == plan.plan.contentHash.description)
    await gate.release()
    let result = await running.value
    let published = await publications.value
    // Final stroke is not a photo checkpoint; it must still publish while executing.
    #expect(published.contains { $0.phase == .executingPlan && $0.progress?.controllerCompletedStrokeCount == 4 })
    let done = DrawingStudioExecutionPresentation(snapshot: result.snapshot, phaseDetail: "")
    #expect(done.drawingIsDone)
    #expect(done.finalPhotoIsSaved)
    #expect(done.detail == "Final photo saved · Review Run")
    let record = try #require(result.snapshot.terminal?.record)
    let retained = try #require(record.attemptEvidence)
    #expect(retained.progressFrames == attempt.progressFrames)
    #expect(retained.terminalFrames.count == 2)
    #expect(DrawingReviewPhotographs.stageLabels(retained).prefix(3) == ["1/4 strokes", "2/4 strokes", "3/4 strokes"])
    #expect(DrawingReviewPhotographs.preferredStageIndex(retained) == 4)
    #expect(await harness.camera.requests.count == 6)
    let events = await harness.events.values
    let between = Array(events[(try #require(events.firstIndex(of: "execute")))...])
    #expect(between.filter { $0 == "travel" }.count <= 1) // only the existing final reveal
    #expect(await harness.evidence.reopenedArchive()?.records.last == record)
    // Older archives lack this optional extension; decoding invents no stages.
    var old = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(attempt)) as? [String: Any])
    old.removeValue(forKey: "progressFrames")
    let legacy = try JSONDecoder().decode(DrawingRunAttemptState.self, from: JSONSerialization.data(withJSONObject: old))
    #expect(legacy.progressFrames.isEmpty)
    var oldEvidence = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(retained)) as? [String: Any])
    oldEvidence.removeValue(forKey: "progressFrames")
    #expect(try JSONDecoder().decode(DrawingRunAttemptEvidence.self,
      from: JSONSerialization.data(withJSONObject: oldEvidence)).progressFrames.isEmpty)
    try await harness.evidence.removeMediaForCorruptionTest(attempt.progressFrames[0].media)
    #expect(await harness.evidence.reopenedArchive() == nil)
    #expect(try await harness.evidence.readMedia(attempt.baselines[0]) == fixture.baselineFrame.frame)
  }

  @Test("Stop during a stage retains that frame, publishes partial progress, and never captures a later stage")
  func stopDuringStage() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let plan = try fixture.makePlan(catalogItemID: .pyramid)
    let frame = try stageFrames(fixture)[0]
    let harness = await drawingRunHarness(fixture: fixture, facts: fixture.facts(plan: plan),
      cameraFrames: [fixture.baselineFrame, frame])
    await harness.interpreter.enableProgressCheckpoints()
    let gate = DrawingRunHoldGate()
    await harness.camera.holdCapture(ordinal: 2, at: gate)
    let ready = await harness.runtime.synchronize(environment: .live)
    let running = Task { await harness.runtime.submit(.init(projection: ready.projection, intent: .start)) }
    await gate.waitUntilHeld()
    let active = await harness.runtime.snapshot(environment: .live)
    _ = await harness.runtime.submit(.init(projection: active.projection,
      intent: .stop(try #require(active.stopCapabilityID))))
    await gate.release()
    let result = await running.value
    #expect(result.snapshot.terminal?.disposition == .cancelled)
    #expect(result.snapshot.terminal?.record.attemptEvidence?.progressFrames.count == 1)
    #expect(result.snapshot.terminal?.record.executionFrontiers.controllerCompletedStrokeCount == 1)
    #expect(await harness.interpreter.stopIntents == [.operatorStop])
    #expect(await harness.camera.requests.count == 2)
    #expect(await harness.vision.requests.isEmpty)
  }

  @Test("stale or different-camera stage pixels are rejected while later stages remain available", arguments: [0, 1, 2])
  func invalidStage(_ variant: Int) async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let plan = try fixture.makePlan(catalogItemID: .pyramid)
    var stages = try stageFrames(fixture)
    stages[0] = variant == 0 ? fixture.baselineFrame : try drawingRunFrame(id: "bad-progress", sequence: 21,
      source: variant == 1 ? .live(CameraDeviceID(rawValue: "other-camera")) : fixture.baselineFrame.source,
      configuration: variant == 2 ? CameraConfigurationID() : fixture.baselineFrame.frame.cameraConfigurationID,
      width: fixture.baselineFrame.frame.width, height: fixture.baselineFrame.frame.height,
      pixelFormat: fixture.baselineFrame.frame.pixelFormat)
    let harness = await drawingRunHarness(fixture: fixture, facts: fixture.facts(plan: plan),
      cameraFrames: [fixture.baselineFrame] + stages + [fixture.completionFrame, fixture.postFrame])
    await harness.interpreter.enableProgressCheckpoints()
    let ready = await harness.runtime.synchronize(environment: .live)
    let result = await harness.runtime.submit(.init(projection: ready.projection, intent: .start))
    let attempt = try #require(result.snapshot.terminal?.record.attemptEvidence)
    #expect(attempt.progressFrames.map { $0.progress.completedStrokeIDs.count } == [2, 3])
    #expect(attempt.missingCoverageReason?.contains("Progress photo after 1 strokes") == true)
    #expect(attempt.terminalFrames.count == 2)
  }

  @Test("a stage media failure recovers the original sequence with no recapture or movement")
  func exactStageRecovery() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let plan = try fixture.makePlan(catalogItemID: .pyramid)
    let stages = try stageFrames(fixture)
    let harness = await drawingRunHarness(fixture: fixture, facts: fixture.facts(plan: plan),
      cameraFrames: [fixture.baselineFrame] + stages + [fixture.completionFrame, fixture.postFrame])
    await harness.interpreter.enableProgressCheckpoints()
    await harness.evidence.rejectMediaFrames([stages[0].frame.id])
    let ready = await harness.runtime.synchronize(environment: .live)
    let failed = await harness.runtime.submit(.init(projection: ready.projection, intent: .start))
    let terminal = try #require(failed.snapshot.terminal)
    #expect(terminal.disposition == .publicationIncomplete)
    #expect(terminal.record.attemptEvidence?.progressFrames.count == 3)
    guard case .failed(_, let capability, _) = failed.snapshot.evidencePersistence else { Issue.record("Missing recovery"); return }
    let before = await harness.camera.requests
    await harness.evidence.rejectMediaFrames([])
    let recovered = await harness.runtime.submit(.init(projection: failed.snapshot.projection, intent: .recoverPublication(capability)))
    #expect(recovered.snapshot.terminal?.record == terminal.record)
    #expect(await harness.camera.requests == before)
    let durable = try #require(await harness.evidence.reopenedArchive())
    #expect(durable.records.last == terminal.record)
    #expect(durable.attempts.last?.progressFrames.count == 3)
  }

  private func stageFrames(_ fixture: DrawingRunEpisodeFixture) throws -> [DisplayedFrame] {
    try (21...23).map { sequence in
      try drawingRunFrame(id: "progress-\(sequence)", sequence: UInt64(sequence),
        source: fixture.baselineFrame.source, configuration: fixture.baselineFrame.frame.cameraConfigurationID,
        width: fixture.baselineFrame.frame.width, height: fixture.baselineFrame.frame.height,
        pixelFormat: fixture.baselineFrame.frame.pixelFormat)
    }
  }
}
