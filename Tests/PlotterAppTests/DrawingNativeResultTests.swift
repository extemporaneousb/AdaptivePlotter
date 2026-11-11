import Foundation
@testable import DrawingLibrary
import PortraitCore
@testable import PortraitLibrary
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterUI
import Testing
@testable import PlotterRuntime
@testable import PlotterApp

@Suite("Drawing native result publication", .serialized)
@MainActor struct DrawingNativeResultTests {
  @Test("Accepted source-free terminal export is exact, replayable and cold-mountable")
  func acceptedTerminalReturn() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let h = await drawingRunHarness(fixture: fixture, outcome: .cancelled)
    let ready = await h.runtime.synchronize(environment: .live)
    _ = await h.submit(.init(projection: ready.projection, intent: .start))
    let settled = try await issuanceSettled(h.runtime)
    let rawRecord = try #require(settled.terminal?.record)
    let decision = try await decision(h)
    let events = await h.events.values, plans = await h.interpreter.planRequests.count
    let rawBytes = try Data(contentsOf: h.evidence.archiveURL)
    let artifact = try result(try await h.destination.service.handle(.exportResult(decision.job.handle)))
    let admitted = try admit(artifact, parent: h.destination.root)
    let ref = try #require(admitted.index.known?.attempts.first)
    let snapshot = try #require(admitted.attempts[ref])
    #expect(snapshot.sealed && snapshot.environment == "live")
    #expect(snapshot.drawing == decision.ticket.facts.drawing && snapshot.job == decision.job)
    #expect(admitted.capabilities.supported.contains(.interpretResults))
    let rawExport = try await h.evidence.exportAttempt(runID: rawRecord.runID)
    #expect(try admitted.files.record(try #require(snapshot.terminalRecord)) == rawExport.recordJSON)
    #expect(try result(try await h.destination.service.handle(.exportResult(decision.job.handle))) == artifact)
    #expect(try Data(contentsOf: h.evidence.archiveURL) == rawBytes)
    #expect(await h.events.values == events)
    #expect(await h.interpreter.planRequests.count == plans)
    let cold = DrawingLibrary(directoryURL: h.destination.root.appendingPathComponent("cold"), payloadValidators: DrawingDestinationResult.payloadValidators)
    let mounted = try await cold.mountResult(from: artifact)
    #expect(try await cold.result(mounted.reference).index.originalJSON == admitted.index.originalJSON)
    #expect(try await cold.attempts(for: snapshot.drawing).entries.map(\.snapshot) == [ref])
    #expect(try await cold.drawing(snapshot.drawing).reference == snapshot.drawing)
    let binding = try #require(rawRecord.attemptEvidence?.intent.issuance)
    let preparedReturn = try await DrawingRunResultExport.prepare(binding: binding, drawing: snapshot.drawing, destination: h.destination.service)
    let userCopy = h.destination.root.appendingPathComponent("explicit-result.zip")
    let cancellation = NativeResultCancellationProbe()
    do { try await preparedReturn.save(to: userCopy, cancelled: { cancellation.afterFirstCheck() }); Issue.record("Injected carrier cancellation did not fail") } catch {}
    #expect(!FileManager.default.fileExists(atPath: userCopy.path))
    try await preparedReturn.save(to: userCopy)
    let savedBytes = try Data(contentsOf: userCopy)
    do { try await preparedReturn.save(to: userCopy); Issue.record("Existing result target was overwritten") } catch {}
    #expect(try Data(contentsOf: userCopy) == savedBytes)
    preparedReturn.discard()
    #expect(try admit(userCopy, parent: h.destination.root).index.originalJSON == admitted.index.originalJSON)
    let wrongDrawing = DrawingRef(issuer: UUID(), revision: snapshot.drawing.revision, digest: snapshot.drawing.digest)
    do { _ = try await DrawingRunResultExport.prepare(binding: binding, drawing: wrongDrawing, destination: h.destination.service); Issue.record("Wrong Drawing opened a native result") } catch {}
    try preserve(artifact, name: "native-source-free-terminal.zip")
    await cold.closeLibrary(); await h.destination.close()
  }

  @Test("Actual native Photo/parent closure returns through the same public sink")
  func nativePhotoReturn() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make()
    defer { f.stores.remove() }
    let app = f.application, library = app.portraitStudio.sketches.library
    let pixels = try DrawingImageAsset.gray8(Data([0, 64, 128, 255]), width: 2, height: 2)
    let source = try DrawingImageRecords.photo(identity: .init(issuer: UUID()), original: pixels, width: 2, height: 2,
      acquired: .unknown(provenance: "synthetic native result fixture"), imported: .unknown(provenance: "synthetic native result fixture"), captureFactsJSON: Data("{}".utf8))
    let input = try DrawingImageRecords.input(identity: .init(issuer: UUID()), photo: source, raster: pixels,
      width: 2, height: 2, orientation: "up", sourceToInput: ExchangeTransform([1,0,0,0,1,0,0,0,1]),
      inputToField: ExchangeTransform([1,0,0,0,1,0,0,0,1]), mask: .none,
      operations: [DrawingImageOperation(kind: "identity", parametersJSON: Data("{}".utf8))],
      preparation: .init(id: "example.native-result", version: "1", recordJSON: Data("{}".utf8)))
    try await library.commitRecords([], closure: .init(input: input))
    let program = try #require(app.drawingDraftSnapshot.authoredProgram)
    let parent = try Drawing(program: program, input: .present(input.reference), parent: .none,
      producer: .init(id: "example.result-parent", version: "1", recordJSON: Data("{}".utf8)))
    let parentRef = try await library.retain(parent, reason: "native result parent").reference
    let child = try Drawing(program: program, input: .present(input.reference), parent: .present(parentRef),
      producer: .init(id: "example.result-child", version: "1", recordJSON: Data("{}".utf8)))
    let selected = try await app.portraitStudio.sketches.retain(child, reason: "native result")
    #expect(await app.projectDrawing(selected) == nil)
    try await f.submit(.fitInDrawableRegion); try await f.submit(.assertPaperCoverage)
    try await waitUntil { app.drawingRunSnapshot?.readiness == .ready }
    await f.planGate.release(.cancelled)
    let request = try #require(app.testPlotterUIProjection().semantic.request(matching: .drawingRun(.start)))
    #expect(await app.submitPlotterUIRequest(request) == .accepted(requestID: request.id))
    let terminal = try await issuanceSettled(f.runRuntime)
    let binding = try #require(terminal.terminal?.record.attemptEvidence?.intent.issuance)
    let artifact = try result(try await app.drawingDestination.handle(.exportResult(binding.job)))
    let staging = FileManager.default.temporaryDirectory.appendingPathComponent("native-photo-inspection-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: staging) }
    let admitted = try admit(artifact, parent: staging)
    #expect(admitted.index.known?.roots == [binding.drawing])
    guard case .materialized(let returned)? = admitted.drawings[binding.drawing] else { throw NativeResultTestError.missing }
    #expect(returned.drawing.input == .present(input.reference))
    #expect(returned.drawing.parent == .present(parentRef))
    try preserve(artifact, name: "native-photo-terminal.zip")
    await app.shutdown()
  }

  @Test("Known original-frame decoding has a media bound independent of JSON record size", arguments: [9, 65])
  func largeOriginalFrame(_ mebibytes: Int) async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let original = fixture.baselineFrame.frame
    // Valid padded original rows preserve the fixture's optical coordinate space.
    // The exact padding bytes are retained; no frame is truncated to fit JSON limits.
    let stride = max(original.rowBytes, (mebibytes * 1024 * 1024 + original.height - 1) / original.height)
    let frame = try StampedFrame(id: FrameID(rawValue: "large-native-original"), sequence: original.sequence,
      captureNanoseconds: original.captureNanoseconds, cameraConfigurationID: original.cameraConfigurationID,
      width: original.width, height: original.height, rowBytes: stride, pixelFormat: original.pixelFormat,
      bytes: OwnedFrameBytes(Array(repeating: 20, count: stride * original.height)))
    let h = await drawingRunHarness(fixture: fixture, outcome: .cancelled,
      cameraFrames: [DisplayedFrame(source: fixture.baselineFrame.source, frame: frame), fixture.completionFrame, fixture.postFrame])
    let ready = await h.runtime.synchronize(environment: .live)
    _ = await h.submit(.init(projection: ready.projection, intent: .start))
    let job = try await decision(h)
    if mebibytes <= 64 {
      let returned = try result(try await h.destination.service.handle(.exportResult(job.job.handle)))
      let accepted = try admit(returned, parent: h.destination.root)
      #expect(accepted.capabilities.supported.contains(.interpretResults))
      #expect(accepted.index.known?.assets.contains { $0.asset.object.description == frame.contentSHA256 && $0.asset.byteLength > UInt64(ExchangeJSON.maximumRecordBytes) } == true)
    } else {
      do { _ = try await h.destination.service.handle(.exportResult(job.job.handle)); Issue.record("Over-cap original frame was materialized by the owner codec") } catch {}
    }
    #expect(await h.interpreter.planRequests.count == 1)
    await h.destination.close()
  }

  @Test("Observation classification and derived composite availability follow the exact raw owner", arguments: ["observed", "rejected", "large"])
  func observationAvailability(_ mode: String) async throws {
    let base = try await DrawingRunEpisodeFixtureCache.load()
    let fixture = mode == "large" ? try enlargedFixture(base) : base
    let h = await drawingRunHarness(fixture: fixture, evidenceFailures: 1)
    let ready = await h.runtime.synchronize(environment: .live)
    _ = await h.submit(.init(projection: ready.projection, intent: .start))
    let original = try #require(try await issuanceSettled(h.runtime).terminal?.record)
    let attempt = try #require(original.attemptEvidence)
    guard case .observed(let observed) = original.observation else { throw NativeResultTestError.missing }
    let store = await h.evidence.rawStoreForResultTests()
    var coverage = attempt.mediaCoverage
    if mode == "large" {
      let before = try #require(attempt.baselines.first { $0.frame == observed.frames.baseline })
      let after = try #require(attempt.terminalFrames.first { $0.frame == observed.frames.post })
      let baseline = try await store.readMedia(before), post = try await store.readMedia(after)
      let position = try #require(before.controllerPosition)
      func visible(_ frame: StampedFrame) throws -> DrawingRunVisibilityMask {
        try .init(frame: ExactFrameProvenance(frame: frame), source: before.source,
          pixels: Array(repeating: .visible, count: frame.width * frame.height),
          basis: .independentClassification(.init(component: "synthetic-native-result-fixture", revision: "1")))
      }
      coverage = try await DrawingRunMediaCoverage.compose(views: [.init(
        viewID: try #require(attempt.intent.observationPlan?.poses.first?.id),
        baseline: .init(source: before.source, frame: baseline, controllerPosition: position),
        result: .init(source: after.source, frame: post, controllerPosition: position),
        registration: attempt.intent.context.registration, baselineVisibility: visible(baseline), resultVisibility: visible(post))],
        region: .init(x: 0, y: 0, width: 400, height: 240),
        policy: .init(alignmentSearchRadiusPixels: 0, maximumAlignmentShiftPixels: 0))
    }
    let observation: DrawingRunObservationOutcome = mode == "rejected"
      ? .rejected(try .init(frames: observed.frames, reason: .inkMissing, algorithmRevisions: observed.algorithmRevisions))
      : original.observation
    let f = original.executionFrontiers
    let terminal = try DrawingRunEvidenceRecord(recordID: original.recordID, runID: original.runID,
      requestID: original.requestID, role: original.role,
      evidenceDisposition: mode == "rejected" ? .visionUnclear : original.evidenceDisposition,
      requestFrontier: original.requestFrontier,
      executionFrontiers: .init(plannedStrokeCount: f.plannedStrokeCount, commandedStrokeCount: f.commandedStrokeCount,
        controllerCompletedStrokeCount: f.controllerCompletedStrokeCount, inkVerifiedStrokeCount: mode == "rejected" ? 0 : f.inkVerifiedStrokeCount),
      executionDisposition: original.executionDisposition, program: original.program, placement: original.placement,
      plan: original.plan, planningProvenance: original.planningProvenance, tipCalibration: original.tipCalibration,
      paper: original.paper, observation: observation, recordedAt: original.recordedAt,
      attemptEvidence: .init(intent: attempt.intent, baselines: attempt.baselines, terminalFrames: attempt.terminalFrames,
        mediaCoverage: coverage, missingCoverageReason: coverage == nil ? attempt.missingCoverageReason : nil,
        executionProgress: attempt.executionProgress, progressFrames: attempt.progressFrames))
    _ = try await store.append(terminal)
    try await h.destination.service.recoverPendingJobs()
    let job = try await decision(h)
    let artifact = try result(try await h.destination.service.handle(.exportResult(job.job.handle)))
    let admitted = try admit(artifact, parent: h.destination.root)
    let snapshot = try #require(admitted.attempts.values.first)
    let inventory = try ExchangeJSON.validate(admitted.files.record(snapshot.coverage))["entries"] as! [[String: Any]]
    #expect(inventory.first { $0["kind"] as? String == "adaptiveplotter.observation" }?["status"] as? String == "present")
    #expect(inventory.first { $0["kind"] as? String == "adaptiveplotter.observation" }?["classification"] as? String == (mode == "rejected" ? "rejected" : "accepted"))
    #expect(inventory.first { $0["kind"] as? String == "adaptiveplotter.observation-composite" }?["status"] as? String == (coverage == nil ? "unavailable" : "present"))
    let exact = try await store.exportAttempt(runID: terminal.runID)
    if mode == "large" {
      #expect(try #require(exact.recordJSON).count > ExchangeJSON.maximumRecordBytes)
      #expect(admitted.interpretableAttempts.contains(try #require(admitted.index.known?.attempts.first)))
      var bounded = ExchangeClosureLimits(); bounded.maximumMaterializedBytes = UInt64(ExchangeJSON.maximumRecordBytes)
      #expect(throws: (any Error).self) {
        _ = try ExchangeAdmission.validate(files: admitted.files, payloadValidators: DrawingDestinationResult.payloadValidators, limits: bounded)
      }
      try preserve(artifact, name: "native-large-terminal.zip")
    } else { try preserve(artifact, name: "native-" + mode + ".zip") }
    #expect(await h.interpreter.planRequests.count == 1)
    await h.destination.close()
  }

  @Test("Interrupted and later terminal boundaries form one cumulative chain without dispatch")
  func interruptedThenTerminal() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let h = await drawingRunHarness(fixture: fixture, uncertainStageAcknowledgement: true)
    let ready = await h.runtime.synchronize(environment: .live)
    _ = await h.runtime.submit(.init(projection: ready.projection, intent: .start))
    _ = try await issuanceSettled(h.runtime)
    try await h.destination.service.recoverPendingJobs()
    let decision = try await decision(h)
    let first = try result(try await h.destination.service.handle(.exportResult(decision.job.handle)))
    let a = try admit(first, parent: h.destination.root)
    let firstRef = try #require(a.index.known?.attempts.first)
    #expect(firstRef.sequence == 1 && a.attempts[firstRef]?.sealed == false)
    #expect(await h.interpreter.planRequests.isEmpty)
    let store = await h.evidence.rawStoreForResultTests()
    guard case .loaded(let stagedArchive) = await store.load() else { throw NativeResultTestError.missing }
    let intent = try #require(stagedArchive.attempts.first?.intent)
    let terminal = try cancelledWithoutDispatch(intent)
    do { _ = try await store.append(terminal) } catch {} // Original post-rename fault remains uncertain until verified lookup.
    guard case .loaded(let verified) = await store.load() else { Issue.record("Raw terminal did not verify"); await h.destination.close(); return }
    #expect(verified.records == [terminal])
    try await h.destination.service.recoverPendingJobs()
    let second = try result(try await h.destination.service.handle(.exportResult(decision.job.handle)))
    let b = try admit(second, parent: h.destination.root)
    let secondRef = try #require(b.index.known?.attempts.first)
    #expect(secondRef.sequence == 2 && b.attempts[secondRef]?.previous == firstRef.digest)
    #expect(b.attempts[firstRef]?.originalJSON == a.attempts[firstRef]?.originalJSON)
    #expect(b.attempts[secondRef]?.sealed == true && second != first)
    #expect(try result(try await h.destination.service.handle(.exportResult(decision.job.handle))) == second)
    #expect(await h.interpreter.planRequests.isEmpty)
    try preserve(first, name: "native-interrupted.zip"); try preserve(second, name: "native-sequence-two.zip")
    await h.destination.close()
  }

  @Test("Concurrent staged and sealed returns publish one coherent chain in either assembly order", arguments: [false, true])
  func competingRawBoundaries(_ newerFirst: Bool) async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let h = await drawingRunHarness(fixture: fixture, uncertainStageAcknowledgement: true)
    let ready = await h.runtime.synchronize(environment: .live)
    _ = await h.runtime.submit(.init(projection: ready.projection, intent: .start))
    _ = try await issuanceSettled(h.runtime)
    try await h.destination.service.recoverPendingJobs()
    let job = try await decision(h), gates = NativeBoundaryAssemblyProbe()
    DrawingDestinationArtifactObservation.shared.install { selected, boundary in
      if selected == job.job.handle, boundary == .assemblyStarted { gates.hold() }
    }
    defer { gates.older.release(); gates.newer.release(); DrawingDestinationArtifactObservation.shared.install(nil) }
    let older = Task { try await h.destination.service.handle(.exportResult(job.job.handle)) }
    try await gates.older.waitUntilEntered()
    let store = await h.evidence.rawStoreForResultTests()
    guard case .loaded(let staged) = await store.load() else { throw NativeResultTestError.missing }
    let intent = try #require(staged.attempts.first?.intent)
    do { _ = try await store.append(cancelledWithoutDispatch(intent)) } catch {} // The original raw writer retains its uncertain ACK boundary.
    guard case .loaded = await store.load() else { throw NativeResultTestError.missing }
    try await h.destination.service.recoverPendingJobs()
    let newer = Task { try await h.destination.service.handle(.exportResult(job.job.handle)) }
    try await gates.newer.waitUntilEntered()
    if newerFirst {
      gates.newer.release()
      _ = try await newer.value
      gates.older.release()
      do { _ = try await older.value } catch DrawingDestinationRefusal.alreadySettled {} // The older boundary cannot follow the chosen seal.
    } else {
      gates.older.release()
      _ = try await older.value
      gates.newer.release()
      _ = try await newer.value
    }
    let latest = try result(try await h.destination.service.handle(.exportResult(job.job.handle)))
    let admitted = try admit(latest, parent: h.destination.root)
    let ref = try #require(admitted.index.known?.attempts.first)
    #expect(admitted.attempts[ref]?.sealed == true)
    #expect(ref.sequence == (newerFirst ? 1 : 2))
    let visible = try FileManager.default.contentsOfDirectory(at: h.destination.root.appendingPathComponent("results"), includingPropertiesForKeys: nil)
      .filter { !$0.lastPathComponent.hasPrefix(".") && $0.pathExtension == "zip" }
    #expect(visible.count == (newerFirst ? 1 : 2))
    for file in visible {
      let package = try admit(file, parent: h.destination.root)
      let selected = try #require(package.index.known?.attempts.first)
      #expect(admitted.attempts[selected]?.originalJSON == package.attempts[selected]?.originalJSON)
    }
    #expect(await h.interpreter.planRequests.isEmpty)
    await h.destination.close()
  }

  @Test("Native media copying remains off the metadata lane and duplicate exports choose one result")
  func responsiveConcurrentExport() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let h = await drawingRunHarness(fixture: fixture, outcome: .cancelled)
    let ready = await h.runtime.synchronize(environment: .live)
    _ = await h.submit(.init(projection: ready.projection, intent: .start))
    let decision = try await decision(h), gate = DestinationArtifactGate()
    DrawingDestinationArtifactObservation.shared.install { job, boundary in
      if job == decision.job.handle, boundary == .copyingOriginal { gate.hold() }
    }
    defer { gate.release(); DrawingDestinationArtifactObservation.shared.install(nil) }
    let export = Task { try await h.destination.service.handle(.exportResult(decision.job.handle)) }
    try await gate.waitUntilEntered()
    #expect(!gate.snapshot().mainThread)
    #expect(try await h.destination.service.handle(.status(.request(decision.key))) == .decision(decision))
    #expect(try await h.destination.service.handle(.cancel(.job(decision.job.handle))) == .cancellation(acknowledged: false, settled: true))
    gate.release()
    let first = try result(try await export.value)
    async let duplicateA = h.destination.service.handle(.exportResult(decision.job.handle))
    async let duplicateB = h.destination.service.handle(.exportResult(decision.job.handle))
    let a = try await duplicateA, b = try await duplicateB
    #expect(try result(a) == first)
    #expect(try result(b) == first)
    await h.destination.close()
  }

  @Test("A lost result-link ACK reuses one persisted carrier across service reopen", arguments: [false, true])
  func resultLinkCrashCuts(_ afterCommit: Bool) async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let h = await drawingRunHarness(fixture: fixture, outcome: .cancelled)
    let ready = await h.runtime.synchronize(environment: .live)
    _ = await h.submit(.init(projection: ready.projection, intent: .start))
    let decision = try await decision(h), gate = DestinationArtifactGate()
    DrawingDestinationArtifactObservation.shared.install { job, boundary in
      if job == decision.job.handle, boundary == .beforeResultLink { gate.hold() }
    }
    defer { gate.release(); DrawingDestinationArtifactObservation.shared.install(nil) }
    let export = Task { try await h.destination.service.handle(.exportResult(decision.job.handle)) }
    try await gate.waitUntilEntered()
    try await h.destination.library.failNextNativeResultLink(afterCommit: afterCommit)
    gate.release()
    do { _ = try await export.value; Issue.record("Injected result-link ACK did not fail") } catch {}
    DrawingDestinationArtifactObservation.shared.install(nil)
    await h.destination.library.clearNativeResultFault()
    let chosenBefore = try await h.destination.library.nativeResultPublication(decision.key)
    let chosen = h.destination.root.appendingPathComponent("results").appendingPathComponent(chosenBefore.fileName)
    let chosenFiles = try FileManager.default.contentsOfDirectory(at: h.destination.root.appendingPathComponent("results"), includingPropertiesForKeys: nil)
      .filter { !$0.lastPathComponent.hasPrefix(".") && $0.pathExtension == "zip" }
    #expect(chosenFiles.count == 1)
    #expect(try #require(chosenFiles.first).standardizedFileURL.path == chosen.standardizedFileURL.path)
    let original = try Data(contentsOf: chosen)
    await h.destination.service.close()
    let reopened = DrawingDestinationService(library: h.destination.library,
      returnDirectory: h.destination.root.appendingPathComponent("results"), prepare: { _,_,_ in nil }, current: { $0 })
    try await reopened.recoverPendingJobs()
    #expect(try result(try await reopened.handle(.exportResult(decision.job.handle))) == chosen)
    #expect(try await h.destination.library.nativeResultPublication(decision.key) == chosenBefore)
    #expect(try Data(contentsOf: chosen) == original)
    #expect(await h.interpreter.planRequests.count == 1)
    await reopened.close(); await h.destination.close()
  }

  @Test("Concurrent first exports retain a stable candidate and both return one exact carrier")
  func concurrentFirstPublication() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let h = await drawingRunHarness(fixture: fixture, outcome: .cancelled)
    let ready = await h.runtime.synchronize(environment: .live)
    _ = await h.submit(.init(projection: ready.projection, intent: .start))
    let job = try await decision(h), gates = NativeBoundaryAssemblyProbe()
    DrawingDestinationArtifactObservation.shared.install { selected, boundary in
      if selected == job.job.handle, boundary == .assemblyStarted { gates.hold() }
    }
    defer { gates.older.release(); gates.newer.release(); DrawingDestinationArtifactObservation.shared.install(nil) }
    let first = Task { try await h.destination.service.handle(.exportResult(job.job.handle)) }
    try await gates.older.waitUntilEntered()
    let second = Task { try await h.destination.service.handle(.exportResult(job.job.handle)) }
    try await gates.newer.waitUntilEntered()
    gates.older.release(); gates.newer.release()
    let a = try result(try await first.value), b = try result(try await second.value)
    #expect(a == b)
    #expect(try admit(a, parent: h.destination.root).index.originalJSON == admit(b, parent: h.destination.root).index.originalJSON)
    let visible = try FileManager.default.contentsOfDirectory(at: h.destination.root.appendingPathComponent("results"), includingPropertiesForKeys: nil)
      .filter { !$0.lastPathComponent.hasPrefix(".") && $0.pathExtension == "zip" }
    #expect(visible.map { $0.standardizedFileURL.path } == [a.standardizedFileURL.path])
    #expect(await h.interpreter.planRequests.count == 1)
    await h.destination.close()
  }

  @Test("Native envelopes cannot clear dispatch, forge seal/frontiers or replace exact raw state", arguments: ["dispatch", "seal", "frontier", "raw-state", "media", "layout", "predecessor"])
  func semanticCorruption(_ kind: String) async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let h = await drawingRunHarness(fixture: fixture, outcome: .cancelled)
    let ready = await h.runtime.synchronize(environment: .live)
    _ = await h.submit(.init(projection: ready.projection, intent: .start))
    let job = try await decision(h)
    let artifact = try result(try await h.destination.service.handle(.exportResult(job.job.handle)))
    let original = try admit(artifact, parent: h.destination.root)
    let bag = h.destination.root.appendingPathComponent("mutation-" + kind)
    try DrawingExchangeCarrier.preserveDirectory(original.files, to: bag)
    var index = try ExchangeJSON.validate(Data(contentsOf: bag.appendingPathComponent("data/exchange.json")))
    let oldRef = try #require(original.index.known?.attempts.first)
    let oldSnapshot = try #require(original.attempts[oldRef])
    let path = bag.appendingPathComponent("data/attempts/" + oldRef.archive.uuidString.lowercased() + "/" + oldRef.run.uuidString.lowercased() + "/1/attempt.json")
    var snapshot = try ExchangeJSON.validate(Data(contentsOf: path))
    func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(value), options: .fragmentsAllowed) }
    func install(_ json: [String: Any], encoding: String) throws -> ExchangeAsset {
      let bytes = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes])
      let asset = try ExchangeAsset(bytes: bytes, mediaType: "application/json", encoding: encoding)
      try bytes.write(to: bag.appendingPathComponent("data/objects/sha256/" + asset.object.description))
      var assets = index["assets"] as! [Any]; assets.append(try object(ExchangeAssetDescriptor(asset: asset))); index["assets"] = assets
      return asset
    }
    switch kind {
    case "dispatch": snapshot["dispatch"] = "not-dispatched"
    case "seal": snapshot["sealed"] = false
    case "predecessor": snapshot["sequence"] = 2; snapshot["previous"] = String(repeating: "a", count: 64)
    case "media":
      let descriptor = try #require(original.index.known?.assets.first { $0.asset.encoding.hasPrefix("raw-") })
      try FileManager.default.removeItem(at: bag.appendingPathComponent("data/objects/sha256/" + descriptor.asset.object.description))
    case "layout":
      var descriptors = index["assets"] as! [[String: Any]]
      let position = try #require(descriptors.firstIndex { ($0["encoding"] as? String)?.hasPrefix("raw-") == true })
      var descriptor = descriptors[position]
      var dimensions = descriptor["dimensions"] as! [String: Any], layout = descriptor["pixelLayout"] as! [String: Any]
      let width = (dimensions["width"] as! NSNumber).intValue, height = (dimensions["height"] as! NSNumber).intValue
      let stride = (layout["rowStride"] as! NSNumber).intValue
      dimensions["width"] = width / 2; dimensions["height"] = height * 2
      layout["width"] = width / 2; layout["height"] = height * 2; layout["rowStride"] = stride / 2
      descriptor["dimensions"] = dimensions; descriptor["pixelLayout"] = layout; descriptors[position] = descriptor
      index["assets"] = descriptors
    default:
      var coverage = try ExchangeJSON.validate(original.files.record(oldSnapshot.coverage))
      if kind == "frontier" {
        var frontiers = coverage["frontiers"] as! [String: [String: Any]]
        var commanded = frontiers["commanded"]!; commanded["count"] = ((commanded["count"] as? NSNumber)?.uint64Value ?? 0) + 1
        frontiers["commanded"] = commanded; coverage["frontiers"] = frontiers
      } else {
        let asset: ExchangeAsset = try DrawingNativeResultCodec.decode(coverage["rawAttempt"])
        var raw = try ExchangeJSON.validate(original.files.record(asset.object))
        raw["inkDispatchPossible"] = false
        let changed = try install(raw, encoding: "adaptiveplotter.raw-attempt-state/1")
        coverage["rawAttempt"] = try object(changed)
        let terminal = try #require(oldSnapshot.terminalRecord)
        let record = try JSONDecoder().decode(DrawingRunEvidenceRecord.self, from: original.files.record(terminal))
        #expect(record.executionFrontiers.commandedStrokeCount > 0)
        let changedBytes = try Data(contentsOf: bag.appendingPathComponent("data/objects/sha256/" + changed.object.description))
        coverage["rawContent"] = try DrawingNativeResultCodec.content(proposal: oldSnapshot.intent,
          attempt: changedBytes, terminal: original.files.record(terminal)).description
        snapshot["dispatch"] = "not-dispatched"
      }
      snapshot["coverage"] = try install(coverage, encoding: "adaptiveplotter.native-coverage/1").object.description
    }
    let bytes = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys, .withoutEscapingSlashes])
    let sequence = kind == "predecessor" ? UInt64(2) : oldRef.sequence
    let replacement = try SnapshotRef(archive: oldRef.archive, run: oldRef.run, sequence: sequence, digest: .hash(bytes))
    let changedPath = kind == "predecessor" ? bag.appendingPathComponent("data/attempts/" + oldRef.archive.uuidString.lowercased() + "/" + oldRef.run.uuidString.lowercased() + "/2/attempt.json") : path
    try FileManager.default.createDirectory(at: changedPath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try bytes.write(to: changedPath, options: .atomic)
    index["attempts"] = try object([replacement])
    try JSONSerialization.data(withJSONObject: index, options: [.sortedKeys, .withoutEscapingSlashes]).write(to: bag.appendingPathComponent("data/exchange.json"), options: .atomic)
    try DrawingDestinationResult.seal(bag)
    #expect(throws: (any Error).self) {
      _ = try ExchangeAdmission.validate(DrawingExchangeCarrier.stageDirectory(bag, stagingParent: h.destination.root), payloadValidators: DrawingDestinationResult.payloadValidators)
    }
    await h.destination.close()
  }

  @Test("Selected raw export does not read an unrelated corrupt historical component")
  func selectedRawReadDoesNotScanHistory() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let h = await drawingRunHarness(fixture: fixture, outcome: .cancelled)
    let ready = await h.runtime.synchronize(environment: .live)
    _ = await h.submit(.init(projection: ready.projection, intent: .start))
    let terminal = try #require(try await issuanceSettled(h.runtime).terminal?.record)
    let store = await h.evidence.rawStoreForResultTests()
    let original = try await store.exportAttempt(runID: terminal.runID)
    let historical = try DrawingRunIntent(runID: RunID(), body: original.attempt.intent.body)
    _ = try await store.stageIntent(historical)
    let envelope = try ExchangeJSON.validate(Data(contentsOf: h.evidence.archiveURL))
    let payload = try #require(envelope["payload"] as? String)
    let manifest = try ExchangeJSON.validate(try #require(Data(base64Encoded: payload)))
    let attempts = try #require(manifest["attempts"] as? [[String: Any]])
    let historicalRef = try #require(attempts.first { ($0["id"] as? String)?.lowercased() == historical.runID.rawValue.uuidString.lowercased() })
    let hash = try #require(historicalRef["sha256"] as? String)
    let component = h.evidence.archiveURL.deletingLastPathComponent()
      .appendingPathComponent(h.evidence.archiveURL.lastPathComponent + ".records/" + hash + ".json")
    try Data("unrelated corrupt original".utf8).write(to: component)
    let selected = try await store.exportAttempt(runID: terminal.runID)
    #expect(selected.attemptJSON == original.attemptJSON && selected.recordJSON == original.recordJSON)
    let coldOwner = DrawingRunEvidenceStore(fileURL: h.evidence.archiveURL)
    guard case .rejected = await coldOwner.load() else {
      Issue.record("Full startup integrity validation accepted corrupt historical evidence")
      await h.destination.close(); return
    }
    do { _ = try await coldOwner.exportAttempt(runID: terminal.runID); Issue.record("Cold export scanned or bypassed the verified-owner requirement") } catch {}
    await h.destination.close()
  }

  @Test("Selected original verification releases the raw writer and rejects a changed captured boundary")
  func rawWriterResponsiveDuringSelectedVerification() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let h = await drawingRunHarness(fixture: fixture, outcome: .cancelled)
    let ready = await h.runtime.synchronize(environment: .live)
    _ = await h.submit(.init(projection: ready.projection, intent: .start))
    let terminal = try #require(try await issuanceSettled(h.runtime).terminal?.record)
    let store = await h.evidence.rawStoreForResultTests(), gate = DestinationArtifactGate()
    DrawingRunSelectedExportObservation.shared.install { run in if run == terminal.runID { gate.hold() } }
    defer { gate.release(); DrawingRunSelectedExportObservation.shared.install(nil) }
    let export = Task { try await store.exportAttempt(runID: terminal.runID) }
    try await gate.waitUntilEntered()
    #expect(!gate.snapshot().mainThread)
    let intent = try DrawingRunIntent(runID: RunID(), body: try #require(terminal.attemptEvidence?.intent.body))
    _ = try await store.stageIntent(intent)
    gate.release()
    do { _ = try await export.value; Issue.record("Selected export accepted a displaced captured index/cache") } catch {}
    #expect(await h.interpreter.planRequests.count == 1)
    await h.destination.close()
  }

  @Test("A missing chosen carrier keeps its original result reference until exact bytes are restored")
  func missingChosenCarrierKeepsIdentity() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let h = await drawingRunHarness(fixture: fixture, outcome: .cancelled)
    let ready = await h.runtime.synchronize(environment: .live)
    _ = await h.submit(.init(projection: ready.projection, intent: .start))
    let job = try await decision(h)
    let artifact = try result(try await h.destination.service.handle(.exportResult(job.job.handle)))
    let exact = try Data(contentsOf: artifact)
    try FileManager.default.removeItem(at: artifact)
    do { _ = try await h.destination.service.handle(.exportResult(job.job.handle)); Issue.record("Missing chosen result was silently replaced") } catch {}
    #expect(!FileManager.default.fileExists(atPath: artifact.path))
    #expect(try await h.destination.service.handle(.status(.request(job.key))) == .decision(job))
    try exact.write(to: artifact, options: .atomic)
    #expect(try result(try await h.destination.service.handle(.exportResult(job.job.handle))) == artifact)
    #expect(try Data(contentsOf: artifact) == exact)
    #expect(await h.interpreter.planRequests.count == 1)
    await h.destination.close()
  }

  @Test("Review deletion prevents new raw export and preserves an already published inert carrier", arguments: [false, true])
  func reviewDeletionPublicationBoundary(_ alreadyPublished: Bool) async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let h = await drawingRunHarness(fixture: fixture, outcome: .cancelled)
    let ready = await h.runtime.synchronize(environment: .live)
    _ = await h.submit(.init(projection: ready.projection, intent: .start))
    let terminal = try #require(try await issuanceSettled(h.runtime).terminal?.record)
    let job = try await decision(h)
    let published: URL?
    if alreadyPublished { published = try result(try await h.destination.service.handle(.exportResult(job.job.handle))) }
    else { published = nil }
    let original = try published.map { try Data(contentsOf: $0) }
    let store = await h.evidence.rawStoreForResultTests()
    let archive = try await store.deleteReview(recordID: terminal.recordID)
    #expect(archive.reviewRecords.isEmpty && archive.records.contains(terminal))
    do { _ = try await store.exportAttempt(runID: terminal.runID); Issue.record("Review-deleted record obtained new raw export") } catch {}
    if let published {
      #expect(try result(try await h.destination.service.handle(.exportResult(job.job.handle))) == published)
      #expect(try Data(contentsOf: published) == #require(original))
    } else {
      do { _ = try await h.destination.service.handle(.exportResult(job.job.handle)); Issue.record("Unpublished review-deleted record obtained a result") } catch {}
    }
    #expect(await h.interpreter.planRequests.count == 1)
    await h.destination.close()
  }

  private func decision(_ h: DrawingRunRuntimeHarness) async throws -> DrawingJobDecision {
    guard case .decision(let value) = try await h.destination.service.handle(.status(.request(try #require(h.destination.lastKey)))) else { throw NativeResultTestError.missing }
    return value
  }
  private func enlargedFixture(_ base: DrawingRunEpisodeFixture) throws -> DrawingRunEpisodeFixture {
    // A distinct synthetic optical fixture. The camera transform's original
    // calibrated coordinate area remains unchanged inside this larger buffer.
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(base.registration)) as! [String: Any]
    var applicability = json["applicability"] as! [String: Any]
    var optical = applicability["opticalConfiguration"] as! [String: Any]
    optical["width"] = 640; optical["height"] = 480
    applicability["opticalConfiguration"] = optical; json["applicability"] = applicability
    let registration = try JSONDecoder().decode(TipCameraRegistration.self,
      from: JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]))
    let source = base.previewFrame.source, configuration = base.previewFrame.frame.cameraConfigurationID
    func frame(_ name: String, _ sequence: UInt64) throws -> DisplayedFrame {
      try drawingRunFrame(id: name, sequence: sequence, source: source, configuration: configuration,
        width: 640, height: 480, pixelFormat: registration.applicability.opticalConfiguration.pixelFormat)
    }
    let preview = try frame("large-preview", 10)
    let oldCoverage = base.plan.paperCoverage
    let paperCoverage = try PaperCoverageObservation(paper: oldCoverage.paper, source: source,
      frame: ExactFrameProvenance(frame: preview.frame), polygon: oldCoverage.polygon, method: oldCoverage.method,
      observedAt: oldCoverage.observedAt, algorithmRevision: oldCoverage.algorithmRevision)
    let built = PlotterDrawingPlanningAdapter.buildDraft(program: base.plan.program, machineCenter: nil,
      uniformScale: 0.02, rotationDegrees: 0, drawableRegion: base.drawableRegion, registration: registration)
    let plan = PlotterDrawingRunPlan(draftRevision: .init(rawValue: 1), program: try #require(built.program),
      placementID: UUID(), plan: try #require(built.plan), evidenceRole: .ordinaryDrawing,
      paperCoverage: paperCoverage, registration: registration)
    return .init(registration: registration, drawableRegion: base.drawableRegion, paper: base.paper,
      previewFrame: preview, baselineFrame: try frame("large-baseline", 20),
      completionFrame: try frame("large-completion", 25), postFrame: try frame("large-post", 30), plan: plan)
  }
  private func result(_ reply: DrawingDestinationReply) throws -> URL {
    guard case .result(let value) = reply else { throw NativeResultTestError.missing }; return value
  }
  private func admit(_ source: URL, parent: URL) throws -> ValidatedExchangePackage {
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    return try ExchangeAdmission.validate(DrawingExchangeCarrier.stageZIP(source, stagingParent: parent), payloadValidators: DrawingDestinationResult.payloadValidators)
  }
  private func preserve(_ source: URL, name: String) throws {
    guard let directory = ProcessInfo.processInfo.environment["ADAPTIVEPLOTTER_RESULT_FIXTURE_OUTPUT"] else { return }
    let root = URL(fileURLWithPath: directory, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let target = root.appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: target.path) { throw CocoaError(.fileWriteFileExists) }
    try FileManager.default.copyItem(at: source, to: target)
  }
  private func cancelledWithoutDispatch(_ intent: DrawingRunIntent) throws -> DrawingRunEvidenceRecord {
    try .init(runID: intent.runID, requestID: intent.requestID, role: intent.role,
      evidenceDisposition: .cancelled, requestFrontier: .admitted,
      executionFrontiers: .init(plannedStrokeCount: UInt32(intent.plan.strokes.count), commandedStrokeCount: 0, controllerCompletedStrokeCount: 0, inkVerifiedStrokeCount: 0),
      executionDisposition: .cancelled(reason: "Interrupted before dispatch"), program: .init(program: intent.context.program),
      placement: .init(placementID: intent.placementID, placement: intent.plan.placement), plan: .init(plan: intent.plan),
      planningProvenance: intent.plan.provenance,
      tipCalibration: .init(acceptedRevisionID: intent.context.registration.acceptedRevisionID,
        registrationEvidenceSHA256: DrawingMaterialApplicability.registrationHash(intent.context.registration),
        applicability: intent.context.registration.applicability, estimatorRevision: intent.context.registration.estimatorRevision),
      paper: intent.context.paper, observation: .notAttempted(.executionCancelledBeforeObservation),
      recordedAt: .init(monotonicNanoseconds: intent.recordedAt.monotonicNanoseconds + 1),
      attemptEvidence: .init(intent: intent, baselines: [], terminalFrames: [], missingCoverageReason: "Interrupted before original capture"))
  }
}

private enum NativeResultTestError: Error { case missing }

private final class NativeResultCancellationProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var checks = 0
  func afterFirstCheck() -> Bool {
    lock.lock(); defer { lock.unlock() }; checks += 1
    return checks > 1
  }
}

private final class NativeBoundaryAssemblyProbe: @unchecked Sendable {
  let older = DestinationArtifactGate(), newer = DestinationArtifactGate()
  private let lock = NSLock()
  private var count = 0
  func hold() {
    lock.lock(); count += 1; let gate = count == 1 ? older : newer; lock.unlock()
    gate.hold()
  }
}

private extension DrawingLibrary {
  func nativeResultPublication(_ key: DrawingRequestKey) throws -> DrawingPublishedResult {
    guard let stored = try record(.init(kind: key.recordKind, id: key.request)),
      let json = try JSONSerialization.jsonObject(with: stored.payload) as? [String: Any],
      let selected = json["pendingResult"] ?? json["publishedResult"] else { throw NativeResultTestError.missing }
    return try JSONDecoder().decode(DrawingPublishedResult.self,
      from: JSONSerialization.data(withJSONObject: selected, options: [.sortedKeys]))
  }
  func failNextNativeResultLink(afterCommit: Bool) throws {
    let catalog = try commonCatalog()
    var armed = true
    catalog.injectFault = { boundary in
      guard armed, boundary == (afterCommit ? .afterSQLCommit : .beforeSQLCommit) else { return }
      for row in try catalog.database.rows("SELECT payload FROM domain_record WHERE kind LIKE 'adaptiveplotter.destination.request.%'") {
        guard let json = row[0], let record = try? JSONDecoder().decode(DrawingLibraryRecord.self, from: Data(json.utf8)),
          let payload = try? JSONSerialization.jsonObject(with: record.payload) as? [String: Any],
          payload["publishedResult"] != nil, payload["pendingResult"] == nil else { continue }
        armed = false; throw DrawingRunEvidenceProbeError.appendFailed
      }
    }
  }
  func clearNativeResultFault() { cachedExchangeCatalog?.injectFault = nil }
}
