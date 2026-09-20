import Foundation
import PlotterModel
import Testing
@testable import PlotterRuntime

@Suite("Drawing motion recipe retained evidence")
struct DrawingMotionRecipeEvidenceTests {
  @Test("Attempt archive round trips captured recipe; legacy omission stays unknown")
  func archiveRoundTrip() throws {
    let intent = try fixture()
    let archive = try DrawingRunEvidenceArchive(revision: 0, records: [],
      attempts: [DrawingRunAttemptState(intent: intent)])
    let bytes = try JSONEncoder().encode(archive)
    let restored = try JSONDecoder().decode(DrawingRunEvidenceArchive.self, from: bytes)
    #expect(restored.attempts.first?.intent.context.motionRecipe == intent.context.motionRecipe)
    var json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    var attempts = try #require(json["attempts"] as? [[String: Any]])
    var oldIntent = try #require(attempts[0]["intent"] as? [String: Any])
    var context = try #require(oldIntent["context"] as? [String: Any])
    context.removeValue(forKey: "motionRecipe"); oldIntent["context"] = context
    attempts[0]["intent"] = oldIntent; json["attempts"] = attempts
    let legacy = try JSONDecoder().decode(DrawingRunEvidenceArchive.self,
      from: JSONSerialization.data(withJSONObject: json))
    #expect(legacy.attempts.first?.intent.context.motionRecipe == nil)
    #expect(legacy.attempts.first?.intent.plan == intent.plan)
  }

  @Test("Request refuses changed feeds or pen settings against captured recipe")
  func requestMismatch() throws {
    let intent = try fixture()
    let recipe = try #require(intent.context.motionRecipe)
    #expect(throws: (any Error).self) {
      try DrawingPlanRequest(plan: intent.plan, travelFeedMMPerMinute: 301,
        drawingFeedMMPerMinute: 300, penActuationProfile: .initialDefaults, motionRecipe: recipe)
    }
    #expect(throws: (any Error).self) {
      try DrawingPlanRequest(plan: intent.plan, travelFeedMMPerMinute: 300,
        drawingFeedMMPerMinute: 300, penActuationProfile: PenActuationProfile(raisedSpindleValue: 41,
          loweredSpindleValue: 760, settleSeconds: 0.3), motionRecipe: recipe)
    }
  }

  @Test("Unsupported execution revision is retained but cannot execute as the current strategy")
  func unsupportedStrategy() throws {
    let intent = try fixture()
    let original = try #require(intent.context.motionRecipe).policy
    let policy = try DrawingMotionPolicy(continuity: original.continuity,
      drawingFeedMMPerMinute: original.drawingFeedMMPerMinute,
      travelFeedMMPerMinute: original.travelFeedMMPerMinute, pen: original.pen,
      controllerLimits: original.controllerLimits, executionStrategyRevision: "future-strategy-v2")
    let recipe = try DrawingPlanner.motionRecipe(for: intent.plan, policy: policy)
    #expect(try JSONDecoder().decode(DrawingMotionRecipe.self,
      from: JSONEncoder().encode(recipe)) == recipe)
    #expect(throws: (any Error).self) {
      try DrawingPlanRequest(plan: intent.plan, travelFeedMMPerMinute: 300,
        drawingFeedMMPerMinute: 300, penActuationProfile: .initialDefaults, motionRecipe: recipe)
    }
  }

  @Test("Unknown controller settings remain absent and policy is not fabricated on legacy decode")
  func unknownLimits() throws {
    let intent = try fixture()
    let recipe = try #require(intent.context.motionRecipe)
    #expect(recipe.policy.controllerLimits.maximumXFeedMMPerMinute == nil)
    #expect(recipe.policy.controllerLimits.junctionDeviationMM == nil)
    let attempt = DrawingRunAttemptEvidence(intent: intent, baselines: [], terminalFrames: [])
    #expect(try JSONDecoder().decode(DrawingRunAttemptEvidence.self,
      from: JSONEncoder().encode(attempt)).executionProgress == nil)
  }

  @Test("Terminal archive retains partial execution progress and rejects mismatched frontiers")
  func retainedProgress() throws {
    let intent = try fixture()
    let progress = DrawingPlanProgressSnapshot(operationID: DrawingPlanOperationID(rawValue: intent.requestID),
      planRevisionID: intent.plan.revisionID, plannedStrokeCount: intent.plan.strokes.count,
      plannedSegmentCount: 1, commandedStrokeCount: 1, controllerCompletedStrokeCount: 0,
      submittedSegmentCount: 1, controllerCompletedSegmentCount: 0, completedStrokeIDs: [],
      completedCheckpointIDs: [], activeStrokeID: intent.plan.strokes.first?.logicalStrokeID,
      activeSegmentIndex: 0, acknowledgedSegmentCount: 1,
      operationSpans: [DrawingOperationSpan(kind: .drawing, strokeID: intent.plan.strokes.first?.logicalStrokeID,
        startedNanoseconds: 2, endedNanoseconds: 3, disposition: .cancelled)],
      wireStrokeMappings: try DrawingWireSchedule(plan: intent.plan).strokes.map {
        DrawingWireStrokeMapping(strokeID: $0.strokeID, sourceSegmentRanges: $0.segments.map(\.sourceSegmentRange))
      })
    let optical = intent.context.registration.applicability.opticalConfiguration
    let rowBytes = optical.width * optical.pixelFormat.bytesPerPixel
    let frame = try StampedFrame(sequence: 1, captureNanoseconds: 2,
      cameraConfigurationID: CameraConfigurationID(), width: optical.width, height: optical.height,
      rowBytes: rowBytes, pixelFormat: optical.pixelFormat,
      bytes: OwnedFrameBytes(Array(repeating: 240, count: rowBytes * optical.height)))
    let baseline = DrawingRunMediaReference(frame: frame, source: optical.source)
    let record = try terminalRecord(intent, progress: progress, baselines: [baseline])
    // Commanded ink requires the journal's durable dispatch marker and retained baseline.
    #expect(throws: (any Error).self) {
      try DrawingRunEvidenceArchive(revision: 1, records: [record])
    }
    #expect(throws: (any Error).self) {
      try DrawingRunEvidenceArchive(revision: 1, records: [record],
        attempts: [DrawingRunAttemptState(intent: intent, baselines: [baseline])])
    }
    let archive = try DrawingRunEvidenceArchive(revision: 1, records: [record],
      attempts: [DrawingRunAttemptState(intent: intent, baselines: [baseline], inkDispatchPossible: true)])
    let restored = try JSONDecoder().decode(DrawingRunEvidenceArchive.self,
      from: JSONEncoder().encode(archive))
    #expect(restored.records.first?.attemptEvidence?.executionProgress == progress)
    #expect(restored.records.first?.attemptEvidence?.intent.context.motionRecipe == intent.context.motionRecipe)
    let wrongProgress = DrawingPlanProgressSnapshot(operationID: DrawingPlanOperationID(),
      planRevisionID: intent.plan.revisionID, plannedStrokeCount: intent.plan.strokes.count,
      plannedSegmentCount: 1, commandedStrokeCount: 1, controllerCompletedStrokeCount: 0,
      submittedSegmentCount: 1, controllerCompletedSegmentCount: 0, completedStrokeIDs: [],
      completedCheckpointIDs: [], activeStrokeID: nil, activeSegmentIndex: nil)
    #expect(throws: (any Error).self) { try terminalRecord(intent, progress: wrongProgress) }
  }

  @Test("Retained mapping totals, source identities and active indices reject JSON tampering")
  func mappingTampering() throws {
    let intent = try fixture(catalog: .polyline)
    let record = try terminalRecord(intent, progress: progress(intent))
    for mutation in ["count", "mapping", "activeStroke", "activeIndex"] {
      var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
      var attempt = try #require(json["attemptEvidence"] as? [String: Any])
      var value = try #require(attempt["executionProgress"] as? [String: Any])
      switch mutation {
      case "count": value["plannedSegmentCount"] = 999
      case "mapping":
        let wrong = [DrawingWireStrokeMapping(strokeID: intent.plan.strokes[0].logicalStrokeID,
          sourceSegmentRanges: [0...(intent.plan.strokes[0].path.points.count - 2)])]
        value["wireStrokeMappings"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(wrong))
        value["plannedSegmentCount"] = 1
      case "activeStroke":
        value["activeStrokeID"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(StrokeID()))
      default: value["activeSegmentIndex"] = -1
      }
      attempt["executionProgress"] = value; json["attemptEvidence"] = attempt
      #expect(throws: (any Error).self) {
        try JSONDecoder().decode(DrawingRunEvidenceRecord.self,
          from: JSONSerialization.data(withJSONObject: json))
      }
    }
  }

  @Test("Continuous completion requires whole strokes; isolated partial segments and pre-checkpoint completion remain valid")
  func completionTopology() throws {
    let continuous = try fixture(catalog: .polyline)
    #expect(throws: (any Error).self) {
      try terminalRecord(continuous, progress: progress(continuous, completedSegments: 1))
    }
    let isolated = try fixture(catalog: .polyline, continuity: .isolatedSegments)
    _ = try terminalRecord(isolated, progress: progress(isolated, completedSegments: 1))
    let line = try fixture()
    let completedBeforePen = try progress(line, completedSegments: 1, completedStrokes: 1)
    #expect(completedBeforePen.completedCheckpointIDs.isEmpty)
    _ = try terminalRecord(line, progress: completedBeforePen)
    #expect(throws: (any Error).self) {
      try terminalRecord(continuous, progress: progress(continuous, completedSegments: 1, completedStrokes: 1))
    }
  }

  @Test("Retained spans must be ordered inside the attempt; adjacent zero length spans are valid")
  func timingBoundaries() throws {
    let intent = try fixture()
    func span(_ start: UInt64, _ end: UInt64) -> DrawingOperationSpan {
      DrawingOperationSpan(kind: .drawing, strokeID: intent.plan.strokes[0].logicalStrokeID,
        startedNanoseconds: start, endedNanoseconds: end, disposition: .cancelled)
    }
    for invalid in [[span(2, 3), span(2, 3)], [span(3, 4), span(2, 3)],
      [span(0, 3)], [span(2, 5)]] {
      #expect(throws: (any Error).self) {
        try terminalRecord(intent, progress: progress(intent, spans: invalid))
      }
    }
    _ = try terminalRecord(intent, progress: progress(intent, spans: [span(2, 2), span(2, 3)]))
  }

  private func progress(_ intent: DrawingRunIntent, completedSegments: Int = 0,
    completedStrokes: Int = 0, spans: [DrawingOperationSpan]? = nil) throws -> DrawingPlanProgressSnapshot {
    let schedule = try DrawingWireSchedule(plan: intent.plan)
    return DrawingPlanProgressSnapshot(operationID: DrawingPlanOperationID(rawValue: intent.requestID),
      planRevisionID: intent.plan.revisionID, plannedStrokeCount: intent.plan.strokes.count,
      plannedSegmentCount: schedule.segmentCount, commandedStrokeCount: 1,
      controllerCompletedStrokeCount: completedStrokes, submittedSegmentCount: 1,
      controllerCompletedSegmentCount: completedSegments, completedStrokeIDs: [], completedCheckpointIDs: [],
      activeStrokeID: intent.plan.strokes[0].logicalStrokeID,
      activeSegmentIndex: schedule.strokes[0].segments[0].sourceSegmentRange.upperBound,
      acknowledgedSegmentCount: 1, operationSpans: spans,
      wireStrokeMappings: schedule.strokes.map { DrawingWireStrokeMapping(strokeID: $0.strokeID,
        sourceSegmentRanges: $0.segments.map(\.sourceSegmentRange)) })
  }

  private func terminalRecord(_ intent: DrawingRunIntent,
    progress: DrawingPlanProgressSnapshot, baselines: [DrawingRunMediaReference] = []) throws -> DrawingRunEvidenceRecord {
    try DrawingRunEvidenceRecord(runID: intent.runID, requestID: intent.requestID,
      role: intent.role, evidenceDisposition: .cancelled, requestFrontier: .admitted,
      executionFrontiers: DrawingRunExecutionFrontiers(plannedStrokeCount: UInt32(intent.plan.strokes.count),
        commandedStrokeCount: UInt32(progress.commandedStrokeCount),
        controllerCompletedStrokeCount: UInt32(progress.controllerCompletedStrokeCount), inkVerifiedStrokeCount: 0),
      executionDisposition: .cancelled(reason: "Operator stop"),
      program: DrawingProgramEvidenceReference(program: intent.context.program),
      placement: DrawingPlacementEvidenceReference(placementID: intent.placementID, placement: intent.plan.placement),
      plan: DrawingExecutionPlanEvidenceReference(plan: intent.plan), planningProvenance: intent.plan.provenance,
      tipCalibration: DrawingTipCalibrationEvidenceReference(acceptedRevisionID: intent.context.registration.acceptedRevisionID,
        registrationEvidenceSHA256: DrawingMaterialApplicability.registrationHash(intent.context.registration),
        applicability: intent.context.registration.applicability, estimatorRevision: intent.context.registration.estimatorRevision),
      paper: intent.context.paper, observation: .notAttempted(.executionCancelledBeforeObservation),
      recordedAt: RuntimeTimestamp(monotonicNanoseconds: 4),
      attemptEvidence: DrawingRunAttemptEvidence(intent: intent, baselines: baselines,
        terminalFrames: [], missingCoverageReason: "Stopped before observation", executionProgress: progress))
  }

  private func fixture(catalog: DrawingCatalogEntryID = .line,
    continuity: DrawingMotionPolicy.Continuity = .continuousWithinStroke) throws -> DrawingRunIntent {
    let authority = try TipAuthorityFixture()
    let registration = try authority.registration()
    let program = try DrawingProgramCatalog.program(for: catalog,
      style: StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID()))
    let placement = try DrawingPlacement(fieldAnchor: Point2(x: 0, y: 0),
      machineAnchor: Point2(x: 0, y: 0), uniformScale: 1)
    let hash = try DrawingMaterialApplicability.registrationHash(registration)
    let bytes = stride(from: 0, to: hash.count, by: 2).map { index in
      UInt8(hash.dropFirst(index).prefix(2), radix: 16)!
    }
    let provenance = DrawingPlanningProvenance(modelRevisionID: DrawingModelRevisionID(registration.acceptedRevisionID.rawValue),
      modelContentHash: try Digest(bytes: bytes),
      registrationRevisionID: DrawingRegistrationRevisionID(registration.acceptedRevisionID.rawValue),
      registrationContentHash: try Digest(bytes: bytes))
    let plan = try DrawingPlanner.plan(program: program, placement: placement,
      drawableRegion: DrawableMachineRegion(bounds: AxisAlignedBounds(minX: 0, minY: 0, maxX: 200, maxY: 200)),
      provenance: provenance)
    let recipe = try DrawingMotionPolicyContext.makeRecipe(plan: plan, travelFeedMMPerMinute: 300,
      drawingFeedMMPerMinute: 300, penActuationProfile: .initialDefaults, probe: nil,
      continuity: continuity)
    let context = try DrawingRunAttemptContext(program: program, registration: registration,
      drawingFeedMMPerMinute: 300, penActuationProfile: .initialDefaults,
      paper: PaperRevisionContext(instance: PaperInstanceRevision(), contactPlane: authority.paper), motionRecipe: recipe)
    return try DrawingRunIntent(runID: RunID(), requestID: UUID(), plan: plan,
      placementID: UUID(), role: .ordinaryDrawing, context: context,
      recordedAt: RuntimeTimestamp(monotonicNanoseconds: 1))
  }
}
