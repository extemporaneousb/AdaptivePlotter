import Foundation
import PlotterModel
import Testing
@testable import PlotterRuntime

@Suite("Durable drawing attempt and original media ownership")
struct DrawingRunAttemptStoreTests {
  @Test("completion freshness round-trips independently of controller pose and rejects stale pixels")
  func completionCaptureBoundary() throws {
    let input = try fixture()
    let reference = DrawingRunMediaReference(frame: input.baseline, source: input.source,
      completionCaptureAfterNanoseconds: input.baseline.captureNanoseconds - 1)
    let restored = try JSONDecoder().decode(DrawingRunMediaReference.self,
      from: JSONEncoder().encode(reference))
    try restored.validate()
    #expect(restored == reference)
    #expect(restored.controllerPosition == nil && restored.captureAfterNanoseconds == nil)
    let stale = DrawingRunMediaReference(frame: input.baseline, source: input.source,
      completionCaptureAfterNanoseconds: input.baseline.captureNanoseconds)
    #expect(throws: DrawingRunEvidenceError.invalidMediaReference) { try stale.validate() }
  }

  @Test("Intent and raw baseline survive interruption before and after dispatch marker")
  func interruptionFrontiers() async throws {
    let fixture = try fixture()
    let url = temporaryArchive()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = DrawingRunEvidenceStore(fileURL: url)
    let prepared = try await store.stageIntent(fixture.intent)
    #expect(prepared.incompleteAttempts.first?.interruptionClassification == .preparedWithoutInkDispatch)
    #expect(prepared.revision == 0)
    await #expect(throws: (any Error).self) {
      try await store.markInkDispatchPossible(runID: fixture.intent.runID)
    }
    let baseline = try await store.installMedia(frame: fixture.baseline, source: fixture.source)
    let staged = try await store.stageBaseline(runID: fixture.intent.runID, media: baseline)
    #expect(staged.attempts.first?.baselines == [baseline])
    #expect(try await store.stageBaseline(runID: fixture.intent.runID, media: baseline) == staged)
    let armed = try await store.markInkDispatchPossible(runID: fixture.intent.runID)
    #expect(armed.incompleteAttempts.first?.interruptionClassification == .possibleInk)
    #expect(armed.revision == 0)
    let restarted = DrawingRunEvidenceStore(fileURL: url)
    guard case .loaded(let recovered) = await restarted.load() else {
      Issue.record("Interrupted attempt must remain recoverable"); return
    }
    #expect(recovered == armed)
    #expect(try await restarted.readMedia(baseline) == fixture.baseline)
  }

  @Test("Cancel seals full source and raw available frame without asserting a comparison")
  func cancelledTerminal() async throws {
    let fixture = try fixture()
    let url = temporaryArchive()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = DrawingRunEvidenceStore(fileURL: url)
    try await store.stageIntent(fixture.intent)
    let baseline = try await store.installMedia(frame: fixture.baseline, source: fixture.source)
    try await store.stageBaseline(runID: fixture.intent.runID, media: baseline)
    try await store.markInkDispatchPossible(runID: fixture.intent.runID)
    let terminal = try await store.installMedia(frame: fixture.terminal, source: fixture.source)
    let record = try terminalRecord(fixture.intent, baseline: baseline, terminal: terminal)
    let sealed = try await store.append(record)
    #expect(sealed.incompleteAttempts.isEmpty)
    #expect(sealed.revision == 1)
    #expect(record.schemaVersion == 4)
    #expect(record.attemptEvidence?.intent.context.program == fixture.intent.context.program)
    #expect(record.attemptEvidence?.intent.context.registration == fixture.intent.context.registration)
    #expect(record.attemptEvidence?.terminalFrames == [terminal])
    #expect(record.attemptEvidence?.missingCoverageReason == "Stopped; no photography repositioning")
    guard case .loaded(let recovered) = await DrawingRunEvidenceStore(fileURL: url).load() else {
      Issue.record("Sealed attempt must survive restart"); return
    }
    #expect(recovered == sealed)
    // An uncertain append acknowledgement can replay exact persistence only.
    let restarted = DrawingRunEvidenceStore(fileURL: url)
    #expect(try await restarted.stageIntent(fixture.intent) == sealed)
    #expect(try await restarted.stageBaseline(runID: fixture.intent.runID, media: baseline) == sealed)
    #expect(try await restarted.markInkDispatchPossible(runID: fixture.intent.runID) == sealed)
    #expect(try await restarted.append(record) == sealed)
    let conflicting = try terminalRecord(fixture.intent, baseline: baseline, terminal: terminal)
    await #expect(throws: (any Error).self) { try await restarted.append(conflicting) }
    await #expect(throws: (any Error).self) {
      try await store.stageBaseline(runID: fixture.intent.runID, media: terminal)
    }
  }

  @Test("Deleting a result persists its exclusion without changing execution facts or shared pixels")
  func reviewDeletionPreservesExecutionEvidence() async throws {
    let input = try fixture()
    let url = temporaryArchive()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = DrawingRunEvidenceStore(fileURL: url)
    try await store.stageIntent(input.intent)
    let baseline = try await store.installMedia(frame: input.baseline, source: input.source)
    try await store.stageBaseline(runID: input.intent.runID, media: baseline)
    try await store.markInkDispatchPossible(runID: input.intent.runID)
    let terminal = try await store.installMedia(frame: input.terminal, source: input.source)
    let record = try terminalRecord(input.intent, baseline: baseline, terminal: terminal)
    let sealed = try await store.append(record)
    #expect(sealed.reviewRecords == [record])

    let deleted = try await store.deleteReview(recordID: record.recordID)
    #expect(deleted.reviewRecords.isEmpty)
    #expect(deleted.deletedReviewRecordIDs == [record.recordID])
    #expect(deleted.records == sealed.records)
    #expect(deleted.attempts == sealed.attempts)
    #expect(deleted.attempts.first?.inkDispatchPossible == true)
    #expect(deleted.incompleteAttempts.isEmpty)
    #expect(deleted.revision == sealed.revision)
    #expect(try await store.deleteReview(recordID: record.recordID) == deleted)
    #expect(try await store.append(record) == deleted)

    let restarted = DrawingRunEvidenceStore(fileURL: url)
    guard case .loaded(let restored) = await restarted.load() else {
      Issue.record("A deleted review must still load its execution archive"); return
    }
    #expect(restored == deleted)
    // Other owners (including material measurements) can still read shared media.
    #expect(try await restarted.readMedia(baseline) == input.baseline)
    #expect(try await restarted.readMedia(terminal) == input.terminal)
    let next = try fixture()
    let updated = try await restarted.stageIntent(next.intent)
    #expect(updated.deletedReviewRecordIDs == [record.recordID])
    #expect(updated.reviewRecords.isEmpty)
    #expect(updated.records == sealed.records)
    await #expect(throws: (any Error).self) {
      try await restarted.deleteReview(recordID: DrawingEvidenceRecordID())
    }
  }

  @Test("Commanded terminal cannot bypass the durable dispatch marker")
  func noInventedDispatch() async throws {
    let fixture = try fixture()
    let url = temporaryArchive()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = DrawingRunEvidenceStore(fileURL: url)
    try await store.stageIntent(fixture.intent)
    let baseline = try await store.installMedia(frame: fixture.baseline, source: fixture.source)
    try await store.stageBaseline(runID: fixture.intent.runID, media: baseline)
    let terminal = try await store.installMedia(frame: fixture.terminal, source: fixture.source)
    let record = try terminalRecord(fixture.intent, baseline: baseline, terminal: terminal)
    await #expect(throws: (any Error).self) { try await store.append(record) }
    guard case .loaded(let recovered) = await store.load() else {
      Issue.record("Refused seal must preserve intent"); return
    }
    #expect(recovered.records.isEmpty)
    #expect(recovered.incompleteAttempts.first?.interruptionClassification == .preparedWithoutInkDispatch)
  }

  @Test("Missing and corrupted referenced pixels reject restart and cannot overwrite evidence")
  func mediaCorruption() async throws {
    for remove in [false, true] {
      let fixture = try fixture()
      let url = temporaryArchive()
      defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
      let store = DrawingRunEvidenceStore(fileURL: url)
      try await store.stageIntent(fixture.intent)
      let reference = try await store.installMedia(frame: fixture.baseline, source: fixture.source)
      try await store.stageBaseline(runID: fixture.intent.runID, media: reference)
      let originalIndex = try Data(contentsOf: url)
      let pixels = url.deletingLastPathComponent()
        .appendingPathComponent(url.lastPathComponent + ".media")
        .appendingPathComponent(reference.frame.frameSHA256 + ".pixels")
      if remove { try FileManager.default.removeItem(at: pixels) }
      else { try Data([0]).write(to: pixels, options: [.atomic]) }
      guard case .rejected(.invalidMedia) = await DrawingRunEvidenceStore(fileURL: url).load() else {
        Issue.record("Bad referenced asset must reject load"); continue
      }
      await #expect(throws: (any Error).self) { try await store.markInkDispatchPossible(runID: fixture.intent.runID) }
      #expect(try Data(contentsOf: url) == originalIndex)
    }
  }

  @Test("An uninstalled frame hash cannot be indexed as a baseline")
  func hashIsNotOwnership() async throws {
    let fixture = try fixture()
    let url = temporaryArchive()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = DrawingRunEvidenceStore(fileURL: url)
    try await store.stageIntent(fixture.intent)
    let reference = DrawingRunMediaReference(frame: fixture.baseline, source: fixture.source)
    await #expect(throws: (any Error).self) {
      try await store.stageBaseline(runID: fixture.intent.runID, media: reference)
    }
  }

  @Test("Frozen material frames can be installed and read independently of a drawing run")
  func measurementMedia() async throws {
    let fixture = try fixture()
    let url = temporaryArchive()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = DrawingRunEvidenceStore(fileURL: url)
    let reference = try await store.installMedia(frame: fixture.baseline, source: fixture.source)
    #expect(try await store.installMedia(frame: fixture.baseline, source: fixture.source) == reference)
    #expect(try await DrawingRunEvidenceStore(fileURL: url).readMedia(reference) == fixture.baseline)
    guard case .absent = await store.load() else {
      Issue.record("Installing measurement pixels must not manufacture a drawing run"); return
    }
  }

  @Test("Multi-session registration hashes survive enclosing intent archive decode")
  func canonicalRegistration() async throws {
    let fixture = try fixture(multipleSessions: true)
    let url = temporaryArchive()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let staged = try await DrawingRunEvidenceStore(fileURL: url).stageIntent(fixture.intent)
    guard case .loaded(let restored) = await DrawingRunEvidenceStore(fileURL: url).load() else {
      Issue.record("Set insertion order must not reject a valid intent"); return
    }
    #expect(restored == staged)
    #expect(try DrawingMaterialApplicability.registrationHash(restored.attempts[0].intent.context.registration)
      == fixture.intent.plan.provenance.registrationContentHash.description)
  }

  @Test("Legacy archive retains explicit hash-only limitations")
  func legacyArchive() throws {
    let old = Data("{\"schemaVersion\":1,\"archiveID\":\"00000000-0000-0000-0000-000000000001\",\"revision\":0,\"records\":[]}".utf8)
    let restored = try JSONDecoder().decode(DrawingRunEvidenceArchive.self, from: old)
    #expect(restored.records.isEmpty)
    #expect(restored.attempts.isEmpty)
  }

  @Test("Material identity pins selected provenance while preserving distinct actual conditions")
  func materialContextIdentity() throws {
    let original = try fixture()
    let profile = try DrawingMaterialProfileRevision(name: "Nominal fixture", nominalWidthMM: 0.5)
    let selected = try DrawingMaterialApplicability(registration: original.intent.context.registration,
      paperStock: "Earlier stock", drawingFeedMMPerMinute: 500, penActuationProfile: .initialDefaults)
    let hash = try DrawingRunAttemptContext.materialContextHash(profile: profile, applicability: selected)
    let context = try DrawingRunAttemptContext(program: original.intent.context.program,
      registration: original.intent.context.registration, materialProfile: profile, materialApplicability: selected,
      paperStock: "Current stock", drawingFeedMMPerMinute: 300, penActuationProfile: .initialDefaults,
      paper: original.intent.context.paper)
    #expect(context.materialApplicability?.drawingFeedMMPerMinute == 500)
    #expect(context.drawingFeedMMPerMinute == 300)
    #expect(context.materialApplicability?.paperStock != context.paperStock)
    let restored = try JSONDecoder().decode(DrawingRunAttemptContext.self, from: JSONEncoder().encode(context))
    #expect(try DrawingRunAttemptContext.materialContextHash(profile: #require(restored.materialProfile),
      applicability: restored.materialApplicability) == hash)
  }

  @Test("Candidate identity must own the exact source program and its C2 digest")
  func candidateIdentity() throws {
    let original = try fixture()
    let digest = try Digest(bytes: Array(repeating: 4, count: 32))
    let valid = DrawingRunCandidateReference(candidateID: digest.description, contentHash: digest,
      sourceProgram: original.intent.context.program)
    #expect(valid.matches(original.intent.context.program))
    #expect(!DrawingRunCandidateReference(candidateID: "wrong-id", contentHash: digest,
      sourceProgram: original.intent.context.program).matches(original.intent.context.program))
    let different = try DrawingProgramCatalog.program(for: .line,
      style: StrokeStyle(nominalLineWidth: 0.7, penProfileID: PenProfileID()))
    #expect(!valid.matches(different))
  }

  @Test("Camera border candidate matching accepts affine placement but rejects reflection and nonlinear edits")
  func cameraBorderCandidateIdentity() throws {
    let program = try DrawingProgramCatalog.program(for: .rectangle,
      style: StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID()))
    let reference = DrawingRunCandidateReference(candidateID: program.contentHash.description,
      contentHash: program.contentHash, sourceProgram: program)
    func composed(cameraMarker: Bool, reflected: Bool = false, distorted: Bool = false) throws -> DrawingProgram {
      var strokes = try program.strokes.map { source in
        let points = try source.path.points.enumerated().map { index, point in
          try Point2<FieldSpace>(x: 250 + (reflected ? -2 : 2) * point.x + 0.2 * point.y,
            y: 50 + point.y + (distorted && index == 2 ? 1 : 0))
        }
        return LogicalStroke(id: source.id, path: try Polyline(points: points), style: source.style,
          semanticRole: source.semanticRole, ordering: source.ordering)
      }
      strokes.append(LogicalStroke(id: StrokeID(), path: try Polyline(points: [Point2(x: 0, y: 0), Point2(x: 500, y: 500)]),
        style: program.strokes[0].style, ordering: UInt32(strokes.count)))
      let marker = cameraMarker ? "|camera-geometry-v1" : ""
      return try DrawingProgram(id: ProgramID(), fieldExtent: Size2(width: 500, height: 500), strokes: strokes,
        source: DrawingSourceProvenance(kind: program.source.kind,
          sourceIdentifier: "\(program.source.sourceIdentifier)\(marker)|draw-border-v1|artwork=\(program.contentHash)"))
    }
    #expect(try reference.matches(composed(cameraMarker: true)))
    #expect(try !reference.matches(composed(cameraMarker: false)))
    #expect(try !reference.matches(composed(cameraMarker: true, reflected: true)))
    #expect(try !reference.matches(composed(cameraMarker: true, distorted: true)))
  }

  @Test("Checksummed composite pixels must equal their retained raw provenance on restart")
  func derivedPixelIntegrity() async throws {
    let original = try fixture()
    let observationPlan = try DrawingRunObservationPlan(executionPlan: original.intent.plan,
      acceptedMovementBounds: AxisAlignedBounds(minX: 0, minY: 0, maxX: 200, maxY: 200),
      currentPosition: MachinePosition(x: 0, y: 0))
    let intent = try DrawingRunIntent(runID: original.intent.runID, requestID: original.intent.requestID,
      plan: original.intent.plan, placementID: original.intent.placementID, role: original.intent.role,
      context: original.intent.context, observationPlan: observationPlan, recordedAt: original.intent.recordedAt)
    let position = try #require(observationPlan.poses.first).position
    let before = SamePoseFrameSample(source: original.source, frame: original.baseline, controllerPosition: position)
    let after = SamePoseFrameSample(source: original.source, frame: original.terminal, controllerPosition: position)
    func visible(_ frame: StampedFrame) throws -> DrawingRunVisibilityMask {
      let identity = ExactFrameProvenance(frame: frame)
      return try DrawingRunVisibilityMask(frame: identity, source: original.source,
        pixels: Array(repeating: .visible, count: frame.width * frame.height),
        basis: .operatorInspection(DrawingMaterialVisibilityEvidence(inspectedFrames: [identity], source: original.source)))
    }
    let coverage = try await DrawingRunMediaCoverage.compose(views: [DrawingRunCoverageView(
      viewID: observationPlan.poses[0].id, baseline: before, result: after,
      registration: intent.context.registration, baselineVisibility: visible(original.baseline),
      resultVisibility: visible(original.terminal))], region: PixelRect(x: 100, y: 100, width: 4, height: 2),
      policy: DrawingRunMediaCoveragePolicy(alignmentSearchRadiusPixels: 0, maximumAlignmentShiftPixels: 0))
    #expect(coverage.coveredPixelCount == 8)
    let url = temporaryArchive()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = DrawingRunEvidenceStore(fileURL: url)
    try await store.stageIntent(intent)
    let baseline = try await store.installMedia(frame: original.baseline, source: original.source)
    let terminal = try await store.installMedia(frame: original.terminal, source: original.source)
    try await store.stageBaseline(runID: intent.runID, media: baseline)
    try await store.markInkDispatchPossible(runID: intent.runID)
    let base = try terminalRecord(intent, baseline: baseline, terminal: terminal)
    var recordObject = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any])
    var evidence = try #require(recordObject["attemptEvidence"] as? [String: Any])
    evidence["mediaCoverage"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(coverage))
    recordObject["attemptEvidence"] = evidence
    let record = try JSONDecoder().decode(DrawingRunEvidenceRecord.self,
      from: JSONSerialization.data(withJSONObject: recordObject))
    try await store.append(record)
    // Recompute the container checksum deliberately: semantic raw-pixel checks
    // must still reject a forged derivative with a structurally valid manifest.
    var envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let payloadString = try #require(envelope["payload"] as? String)
    let payload = try #require(Data(base64Encoded: payloadString))
    var archive = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
    var records = try #require(archive["records"] as? [[String: Any]])
    let reference = try #require(records.first)
    let oldHash = try #require(reference["sha256"] as? String)
    let components = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".records")
    var recordPayload = try #require(JSONSerialization.jsonObject(with:
      Data(contentsOf: components.appendingPathComponent(oldHash + ".json"))) as? [String: Any])
    var retained = try #require(recordPayload["attemptEvidence"] as? [String: Any])
    var derivative = try #require(retained["mediaCoverage"] as? [String: Any])
    var pixels = coverage.resultRGBA; pixels[0] ^= 1
    derivative["resultRGBA"] = pixels.base64EncodedString()
    retained["mediaCoverage"] = derivative; recordPayload["attemptEvidence"] = retained
    let recordBytes = try JSONSerialization.data(withJSONObject: recordPayload, options: [.sortedKeys])
    let newHash = RunLedger.sha256Hex(recordBytes)
    try recordBytes.write(to: components.appendingPathComponent(newHash + ".json"))
    records[0]["sha256"] = newHash; archive["records"] = records
    let changed = try JSONSerialization.data(withJSONObject: archive, options: [.sortedKeys])
    envelope["payload"] = changed.base64EncodedString()
    envelope["payloadSHA256"] = RunLedger.sha256Hex(changed)
    try JSONSerialization.data(withJSONObject: envelope).write(to: url, options: [.atomic])
    guard case .rejected(.invalidMedia) = await DrawingRunEvidenceStore(fileURL: url).load() else {
      Issue.record("A checksummed fabricated pixel must still reject startup"); return
    }
  }

  @Test("Baseline from another optical source cannot enter the staged attempt")
  func baselineSourceMismatch() async throws {
    let f = try fixture()
    let url = temporaryArchive()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = DrawingRunEvidenceStore(fileURL: url)
    try await store.stageIntent(f.intent)
    let reference = try await store.installMedia(frame: f.baseline,
      source: .live(CameraDeviceID(rawValue: "wrong-camera")))
    await #expect(throws: (any Error).self) {
      try await store.stageBaseline(runID: f.intent.runID, media: reference)
    }
    guard case .loaded(let archive) = await store.load() else { Issue.record("Original intent lost"); return }
    #expect(archive.attempts.first?.baselines.isEmpty == true)
    #expect(archive.attempts.first?.inkDispatchPossible == false)
  }

  @Test("Full owned registration must also reconstruct the planning model identity")
  func modelPayloadMismatch() throws {
    let f = try fixture(), old = f.intent.plan
    let unrelated = DrawingPlanningProvenance(modelRevisionID: DrawingModelRevisionID(),
      modelContentHash: try Digest(bytes: Array(repeating: 8, count: 32)),
      registrationRevisionID: old.provenance.registrationRevisionID,
      registrationContentHash: old.provenance.registrationContentHash)
    let plan = try DrawingPlanner.plan(program: f.intent.context.program,
      placement: old.placement, drawableRegion: old.drawableRegion, provenance: unrelated)
    #expect(throws: DrawingRunEvidenceError.invalidAttemptContext) {
      try DrawingRunIntent(runID: f.intent.runID, requestID: f.intent.requestID,
        plan: plan, placementID: f.intent.placementID, role: f.intent.role,
        context: f.intent.context, recordedAt: f.intent.recordedAt)
    }
  }

  @Test("Settled-pose media retains the strict monotonic acquisition boundary")
  func captureBoundaryRoundTrip() throws {
    let input = try fixture()
    let position = try MachinePosition(x: 2, y: 3)
    let reference = DrawingRunMediaReference(frame: input.baseline, source: input.source,
      controllerPosition: position, captureAfterNanoseconds: input.baseline.captureNanoseconds - 1)
    try reference.validate()
    let restored = try JSONDecoder().decode(DrawingRunMediaReference.self,
      from: JSONEncoder().encode(reference))
    try restored.validate()
    #expect(restored == reference)
    #expect(restored.captureAfterNanoseconds == input.baseline.captureNanoseconds - 1)
    #expect(restored.controllerPosition == position)
  }

  @Test("Legacy media omits the acquisition boundary and decodes without a freshness claim")
  func legacyCaptureBoundary() throws {
    let input = try fixture()
    let reference = DrawingRunMediaReference(frame: input.baseline, source: input.source)
    let encoded = try JSONEncoder().encode(reference)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(object["captureAfterNanoseconds"] == nil)
    let restored = try JSONDecoder().decode(DrawingRunMediaReference.self, from: encoded)
    try restored.validate()
    #expect(restored.captureAfterNanoseconds == nil)
    #expect(restored.controllerPosition == nil)
    #expect(restored == reference)
  }

  @Test("A capture at or before settlement and a missing controller pose fail validation")
  func staleCaptureBoundary() throws {
    let input = try fixture()
    let position = try MachinePosition(x: 2, y: 3)
    for boundary in [input.baseline.captureNanoseconds, input.baseline.captureNanoseconds + 1] {
      let reference = DrawingRunMediaReference(frame: input.baseline, source: input.source,
        controllerPosition: position, captureAfterNanoseconds: boundary)
      #expect(throws: DrawingRunEvidenceError.invalidMediaReference) { try reference.validate() }
      let restored = try JSONDecoder().decode(DrawingRunMediaReference.self,
        from: JSONEncoder().encode(reference))
      #expect(throws: DrawingRunEvidenceError.invalidMediaReference) { try restored.validate() }
    }
    let unbound = DrawingRunMediaReference(frame: input.baseline, source: input.source,
      captureAfterNanoseconds: input.baseline.captureNanoseconds - 1)
    #expect(throws: DrawingRunEvidenceError.invalidMediaReference) { try unbound.validate() }
  }

  @Test("Installed pixels cannot satisfy a stale settled-pose reference")
  func storeRejectsStaleCaptureBoundary() async throws {
    let input = try fixture()
    let url = temporaryArchive()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = DrawingRunEvidenceStore(fileURL: url)
    _ = try await store.installMedia(frame: input.baseline, source: input.source)
    let position = try MachinePosition(x: 2, y: 3)
    let valid = DrawingRunMediaReference(frame: input.baseline, source: input.source,
      controllerPosition: position, captureAfterNanoseconds: input.baseline.captureNanoseconds - 1)
    #expect(try await store.readMedia(valid) == input.baseline)
    let stale = DrawingRunMediaReference(frame: input.baseline, source: input.source,
      controllerPosition: position, captureAfterNanoseconds: input.baseline.captureNanoseconds)
    await #expect(throws: (any Error).self) { try await store.readMedia(stale) }
  }

  @Test("Warm startup stages only its own attempt and never rehashes unrelated historical pixels")
  func boundedStartupPersistence() async throws {
    let url = temporaryArchive()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = DrawingRunEvidenceStore(fileURL: url)
    for _ in 0..<12 {
      let input = try fixture()
      try await store.stageIntent(input.intent)
      let baseline = try await store.installMedia(frame: input.baseline, source: input.source)
      try await store.stageBaseline(runID: input.intent.runID, media: baseline)
      try await store.markInkDispatchPossible(runID: input.intent.runID)
    }
    let encoded = await store.componentBytesEncoded, verified = await store.mediaBytesVerified
    let input = try fixture()
    let intentSize = try JSONEncoder().encode(DrawingRunAttemptState(intent: input.intent)).count
    try await store.stageIntent(input.intent)
    #expect(await store.componentBytesEncoded - encoded == intentSize)
    #expect(await store.mediaBytesVerified == verified)
    let baseline = try await store.installMedia(frame: input.baseline, source: input.source)
    try await store.stageBaseline(runID: input.intent.runID, media: baseline)
    let beforeMarker = await store.mediaBytesVerified
    let armed = try await store.markInkDispatchPossible(runID: input.intent.runID)
    #expect(await store.mediaBytesVerified == beforeMarker)
    guard case .loaded(let recovered) = await DrawingRunEvidenceStore(fileURL: url).load() else {
      Issue.record("Incremental startup must survive restart"); return
    }
    #expect(recovered == armed && recovered.attempts.count == 13)
  }

  @Test("Legacy envelope upgrades before Draw and preserves exact possible-ink truth")
  func legacyStoreUpgrade() async throws {
    let url = temporaryArchive()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let input = try fixture()
    let store = DrawingRunEvidenceStore(fileURL: url)
    try await store.stageIntent(input.intent)
    let baseline = try await store.installMedia(frame: input.baseline, source: input.source)
    try await store.stageBaseline(runID: input.intent.runID, media: baseline)
    let armed = try await store.markInkDispatchPossible(runID: input.intent.runID)
    let payload = try JSONEncoder().encode(armed)
    let legacy = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1,
      "payload": payload.base64EncodedString(), "payloadSHA256": RunLedger.sha256Hex(payload)])
    try legacy.write(to: url, options: .atomic)
    let restarted = DrawingRunEvidenceStore(fileURL: url)
    guard case .loaded(let snapshot) = restarted.loadSnapshot() else { Issue.record("Legacy read failed"); return }
    #expect(snapshot == armed)
    #expect(try Data(contentsOf: url) == legacy) // synchronous Saved Learning read remains read-only
    guard case .loaded(let restored) = await restarted.load() else { Issue.record("Legacy upgrade failed"); return }
    #expect(restored == armed)
    let envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    #expect(envelope["schemaVersion"] as? Int == 2)
    let count = await restarted.componentBytesEncoded
    try await restarted.stageIntent(input.intent)
    #expect(await restarted.componentBytesEncoded == count)
  }

  @Test("A corrupt committed component rejects warm mutations; orphan components are not execution truth")
  func componentCorruption() async throws {
    let url = temporaryArchive()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let input = try fixture()
    let store = DrawingRunEvidenceStore(fileURL: url)
    try await store.stageIntent(input.intent)
    let records = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".records")
    let component = try #require(FileManager.default.contentsOfDirectory(at: records, includingPropertiesForKeys: nil).first)
    try Data("orphan".utf8).write(to: records.appendingPathComponent("orphan.json"))
    guard case .loaded(let restored) = await DrawingRunEvidenceStore(fileURL: url).load() else { Issue.record("Orphans changed truth"); return }
    #expect(restored.attempts.count == 1)
    let original = try Data(contentsOf: url)
    try Data("corrupt".utf8).write(to: component)
    let next = try fixture()
    await #expect(throws: (any Error).self) { try await store.stageIntent(next.intent) }
    #expect(try Data(contentsOf: url) == original)
  }

  @Test("Disposable accumulated drawing archive measures warm pre-ink persistence", .enabled(if: ProcessInfo.processInfo.environment["DRAW_EVIDENCE_BENCHMARK_FILE"] != nil))
  func accumulatedArchiveStartup() async throws {
    let url = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["DRAW_EVIDENCE_BENCHMARK_FILE"]))
    try #require(url.path.hasPrefix("/private/tmp/adaptiveplotter-draw-benchmark-") || url.path.hasPrefix("/tmp/adaptiveplotter-draw-benchmark-"))
    let store = DrawingRunEvidenceStore(fileURL: url)
    let loadStart = ProcessInfo.processInfo.systemUptime
    guard case .loaded(let loaded) = await store.load() else { Issue.record("Archive copy failed load"); return }
    let loadSeconds = ProcessInfo.processInfo.systemUptime - loadStart
    let encoded = await store.componentBytesEncoded, verified = await store.mediaBytesVerified
    let input = try fixture()
    let start = ProcessInfo.processInfo.systemUptime
    try await store.stageIntent(input.intent)
    let baseline = try await store.installMedia(frame: input.baseline, source: input.source)
    try await store.stageBaseline(runID: input.intent.runID, media: baseline)
    let beforeMarker = await store.mediaBytesVerified
    try await store.markInkDispatchPossible(runID: input.intent.runID)
    #expect(await store.mediaBytesVerified == beforeMarker)
    print("Draw evidence startup: historical_records=\(loaded.records.count) historical_attempts=\(loaded.attempts.count) cold_load_seconds=\(loadSeconds) warm_preink_seconds=\(ProcessInfo.processInfo.systemUptime - start) component_bytes_encoded=\(await store.componentBytesEncoded - encoded) media_bytes_verified=\(await store.mediaBytesVerified - verified)")
  }

  private func temporaryArchive() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("run-media-\(UUID())")
      .appendingPathComponent("runs.json")
  }

  private func fixture(multipleSessions: Bool = false) throws -> AttemptFixture {
    let authority = try TipAuthorityFixture()
    var registration = try authority.registration()
    if multipleSessions {
      var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(registration)) as? [String: Any])
      object["captureSessionIDs"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
        [CameraCaptureSessionID(), CameraCaptureSessionID(), CameraCaptureSessionID()]))
      registration = try JSONDecoder().decode(TipCameraRegistration.self,
        from: JSONSerialization.data(withJSONObject: object))
    }
    let program = try DrawingProgramCatalog.program(for: .line,
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
    let context = try DrawingRunAttemptContext(program: program, registration: registration,
      paperStock: "fixture stock", drawingFeedMMPerMinute: 300, penActuationProfile: .initialDefaults,
      paper: PaperRevisionContext(instance: PaperInstanceRevision(), contactPlane: authority.paper))
    let intent = try DrawingRunIntent(runID: RunID(), requestID: UUID(), plan: plan,
      placementID: UUID(), role: .ordinaryDrawing, context: context,
      recordedAt: RuntimeTimestamp(monotonicNanoseconds: 1))
    let baseline = try StampedFrame(sequence: 1, captureNanoseconds: 2,
      cameraConfigurationID: authority.cameraConfigurationID, width: 640, height: 480,
      rowBytes: 640, pixelFormat: .gray8, bytes: OwnedFrameBytes(Array(repeating: 240, count: 640 * 480)))
    let terminal = try StampedFrame(sequence: 2, captureNanoseconds: 3,
      cameraConfigurationID: authority.cameraConfigurationID, width: 640, height: 480,
      rowBytes: 640, pixelFormat: .gray8, bytes: OwnedFrameBytes(Array(repeating: 230, count: 640 * 480)))
    return AttemptFixture(intent: intent, baseline: baseline, terminal: terminal, source: authority.source)
  }

  private func terminalRecord(_ intent: DrawingRunIntent, baseline: DrawingRunMediaReference,
    terminal: DrawingRunMediaReference) throws -> DrawingRunEvidenceRecord {
    try DrawingRunEvidenceRecord(runID: intent.runID, requestID: intent.requestID,
      role: intent.role, evidenceDisposition: .cancelled, requestFrontier: .admitted,
      executionFrontiers: DrawingRunExecutionFrontiers(plannedStrokeCount: UInt32(intent.plan.strokes.count),
        commandedStrokeCount: 1, controllerCompletedStrokeCount: 0, inkVerifiedStrokeCount: 0),
      executionDisposition: .cancelled(reason: "Operator stop"),
      program: DrawingProgramEvidenceReference(program: intent.context.program),
      placement: DrawingPlacementEvidenceReference(placementID: intent.placementID, placement: intent.plan.placement),
      plan: DrawingExecutionPlanEvidenceReference(plan: intent.plan), planningProvenance: intent.plan.provenance,
      tipCalibration: DrawingTipCalibrationEvidenceReference(acceptedRevisionID: intent.context.registration.acceptedRevisionID,
        registrationEvidenceSHA256: DrawingMaterialApplicability.registrationHash(intent.context.registration),
        applicability: intent.context.registration.applicability, estimatorRevision: intent.context.registration.estimatorRevision),
      paper: intent.context.paper, observation: .notAttempted(.executionCancelledBeforeObservation),
      recordedAt: RuntimeTimestamp(monotonicNanoseconds: 4),
      attemptEvidence: DrawingRunAttemptEvidence(intent: intent, baselines: [baseline],
        terminalFrames: [terminal], missingCoverageReason: "Stopped; no photography repositioning"))
  }
}

private struct AttemptFixture {
  let intent: DrawingRunIntent
  let baseline: StampedFrame
  let terminal: StampedFrame
  let source: FrameSourceIdentity
}
