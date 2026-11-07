import Darwin
import Foundation
import PlotterModel
import PlotterRuntime
import PortraitArtists
import PortraitCore
import PortraitLibrary
@testable import PortraitStudioUI
import Testing

/// DX-01 current-path evidence, not a future-contract assertion or artistic evaluation.
/// All judgments and vector geometry below are explicitly synthetic test oracles.
@Suite("Drawing Exchange Flow UI-model baseline", .serialized,
  .enabled(if: ProcessInfo.processInfo.environment["DX_FLOW_ROOT"] != nil))
@MainActor
struct DrawingExchangeFlowBaselineTests {
  @Test("Disposable FlowDojoModel baseline")
  func run() async throws {
    let env = ProcessInfo.processInfo.environment
    let root = URL(fileURLWithPath: try #require(env["DX_FLOW_ROOT"]), isDirectory: true).standardizedFileURL
    // Admit one disposable child of the actual /tmp directory, including its
    // host-specific canonical alias; the child itself must never be a symlink.
    let tempParent = URL(fileURLWithPath: "/tmp", isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
    try #require(root.lastPathComponent.hasPrefix("adaptiveplotter-dx01-"))
    try #require(root.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL == tempParent)
    if let attributes = try? FileManager.default.attributesOfItem(atPath: root.path) {
      try #require(attributes[.type] as? FileAttributeType == .typeDirectory, "DX_FLOW_ROOT must be a directory, never a symlink.")
    }
    try #require(root.resolvingSymlinksInPath().standardizedFileURL == tempParent.appendingPathComponent(root.lastPathComponent, isDirectory: true))
    let phase = try #require(env["DX_FLOW_PHASE"])
    let frozen = root.appendingPathComponent("flow-frozen.flowportfolio")
    if phase == "prepare" {
      try #require(!FileManager.default.fileExists(atPath: frozen.path), "Prepare requires a new baseline corpus.")
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      try await prepare(frozen, root: root)
      return
    }
    try #require(phase == "measure")
    let operation = try #require(env["DX_FLOW_OPERATION"])
    let operations = ["reopen", "view", "select", "choose", "refine", "prune", "rename", "rank", "generate", "failed-rank", "equal-byte-capture", "real-generate", "producer-replay"]
    try #require(operations.contains(operation))
    let warmTrials = try #require(Int(env["DX_FLOW_WARM_TRIALS"] ?? "30"), "DX_FLOW_WARM_TRIALS must be an integer.")
    try #require(warmTrials >= 0, "DX_FLOW_WARM_TRIALS must be nonnegative; zero records only the first operation.")
    let originalHead = try Data(contentsOf: frozen.appendingPathComponent("portfolio.json"))
    let copy = root.appendingPathComponent("flow-work-" + UUID().uuidString + ".flowportfolio")
    try FileManager.default.copyItem(at: frozen, to: copy)
    defer { try? FileManager.default.removeItem(at: copy) }
    let counter = DXFlowRenderCounter()
    let model = makeModel(copy, counter: counter, real: operation == "real-generate")
    model.count = 3
    if operation == "producer-replay" {
      await model.open(); try healthy(model)
      try await producerReplay(model: model, root: root, warmTrials: warmTrials, environment: env,
        baselineHeadSHA256: DrawingPackageCodec.sha256(originalHead))
      #expect(await model.shutdown())
      #expect(try Data(contentsOf: frozen.appendingPathComponent("portfolio.json")) == originalHead)
      return
    }
    var trials = [[String: Any]]()
    var firstOperationSeconds: Double?
    var firstOperationGeneration: [String: Any]?
    if operation == "reopen" {
      // One process-cold sample per invocation. Copying happens before the timer;
      // OS filesystem cache is uncontrolled, never described as disk-cold.
      let started = DispatchTime.now().uptimeNanoseconds
      await model.open(); try healthy(model)
      trials.append(["seconds": seconds(since: started), "condition": "process-cold; filesystem cache uncontrolled"])
    } else {
      await model.open(); try healthy(model)
      for trial in -1..<warmTrials {
        let revision = try #require(model.document?.revision)
        let candidates = model.document?.candidates.count ?? 0
        let beforeRenders = await counter.snapshot()
        let started = DispatchTime.now().uptimeNanoseconds
        try await perform(operation, model: model, directory: copy, trial: trial)
        let elapsed = seconds(since: started)
        let afterRenders = await counter.snapshot()
        let generation: [String: Any]?
        if ["generate", "real-generate", "refine"].contains(operation) {
          generation = try generationObservation(model: model, operation: operation,
            overrideCalls: afterRenders.0 - beforeRenders.0)
        } else { generation = nil }
        if trial == -1 { firstOperationSeconds = elapsed; firstOperationGeneration = generation }
        if trial >= 0 {
          trials.append(["generation": generation.map { $0 as Any } ?? NSNull(), "seconds": elapsed, "revisionBefore": revision,
            "revisionAfter": model.document?.revision ?? -1,
            "retainedCandidatesDelta": (model.document?.candidates.count ?? 0) - candidates,
            "rendererOverrideCalls": operation == "real-generate" ? NSNull() : afterRenders.0 - beforeRenders.0,
            "rendererOverrideSeconds": operation == "real-generate" ? NSNull() : afterRenders.1 - beforeRenders.1])
        }
      }
    }
    let final = try #require(model.document)
    var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
    let mallocSnapshot = allZoneMallocSnapshot()
    var receipt: [String: Any] = [
      "schemaVersion": 1, "operation": operation, "phase": phase,
      "boundary": "FlowDojoModel operation through awaited persistence and refresh; rank retains current comparison, no automatic next comparison exists",
      "operationCaveat": operation == "view" ? "view measures model property projection only; excludes native paint, layout and user-visible presentation" : operation == "failed-rank" ? "failed-rank measures fault injection plus recovery cycle, not failure-only rank latency" : "awaited UI-model method; excludes native paint and hardware",
      "renderer": operation == "real-generate" ? "production FlowDojoRenderer including proposals; valid synthetic 40x40 PNG" : "FlowDojoFixture.render override: synthetic 16-stroke vectors; measured renderer override cost separately; production proposals bypassed",
      "generationInputCondition": ["generate", "real-generate", "refine"].contains(operation) ? "stochastic: production generate chooses a fresh random UInt64 seed each call; actual seeds/recipes/slot outcomes captured after timer; frozen starting corpus does not imply identical generated inputs" : "not a generation operation",
      "historyCondition": operation == "reopen" ? "one process-cold model open; no warmup or warm operations" : "one initial operation then \(warmTrials) measured warm operations on evolving disposable history; frozen starting corpus shared across operations",
      "initialOperationCount": operation == "reopen" ? 0 : 1,
      "measuredWarmOperationCount": operation == "reopen" ? 0 : warmTrials,
      "sourceCorpus": "small synthetic validation portfolio; no 10k-scale Dojo, real-archive, artistic, signed-app, camera or physical claim",
      "baselineHeadSHA256": DrawingPackageCodec.sha256(originalHead),
      "finalRevision": final.revision, "finalCandidates": final.candidates.count,
      "activeCheckpointID": model.activeCheckpoint?.id ?? "unavailable",
      "samples": trials, "firstOperationGeneration": firstOperationGeneration.map { $0 as Any } ?? NSNull(),
      "firstOperationAfterOpenSeconds": firstOperationSeconds.map { $0 as Any } ?? NSNull(),
      "firstOperationCondition": "first operation in fresh process after model open; open preloads assets; filesystem cache uncontrolled",
      "processLifetimePeakRSSBytes": usage.ru_maxrss,
      "peakRSSScope": "Darwin ru_maxrss process lifetime; includes test startup, copy, open and setup; not operation-local",
      "allocationCount": NSNull(), "queryCount": NSNull(), "decodeCount": NSNull(),
      "bytesRead": NSNull(), "bytesWritten": NSNull(),
      "unavailableMetricsReason": "no production read/query/decode/cumulative-allocation-event instrumentation; filesystem deltas cannot establish IO counts",
      "futureContract": "generation currently retains candidates; measured positive retainedCandidatesDelta is baseline behavior, not zero-write acceptance"
    ]
    receipt.merge(mallocSnapshot) { _, snapshot in snapshot }
    // Failed-rank deliberately leaves recovery pending until after its assertions.
    if model.needsRecovery { await model.recoverAutosave() }
    #expect(await model.shutdown())
    #expect(try Data(contentsOf: frozen.appendingPathComponent("portfolio.json")) == originalHead)
    try write(receipt, to: root.appendingPathComponent("flow-" + operation + "-" + UUID().uuidString + ".json"))
  }

  /// Metadata only: no program, raster or preview payload read after the timer.
  private func generationObservation(model: FlowDojoModel, operation: String, overrideCalls: Int) throws -> [String: Any] {
    let round = try #require(model.round), document = try #require(model.document)
    let candidates = document.candidates.filter { $0.roundID == round.id }
    let slots: [[String: Any]] = round.recipes.indices.map { slot in
      if let candidate = candidates.first(where: { $0.slot == slot }) {
        return ["slot": slot, "outcome": "success", "candidateID": candidate.id.uuidString,
          "programObjectSHA256": candidate.program.sha256, "programContentHash": candidate.programHash,
          "rasterObjectSHA256": candidate.raster.sha256, "previewObjectSHA256": candidate.preview.sha256,
          "strokeCount": candidate.strokeCount]
      }
      if let failure = round.failures.last(where: { $0.slot == slot }) {
        return ["slot": slot, "outcome": "failure", "message": failure.message]
      }
      return ["slot": slot, "outcome": "missing"]
    }
    let complete = candidates.count == round.recipes.count && round.failures.isEmpty
    let source = try #require(document.sources.first { $0.id == round.sourceID })
    return ["roundID": round.id.uuidString, "seedUInt64Decimal": String(round.seed),
      "sourceID": source.id.uuidString, "sourceObjectSHA256": source.image.sha256,
      "modelProgressAfterOperation": model.progress,
      "recipeRevision": FlowArtistRecipe.revision, "recipes": try jsonValue(round.recipes),
      "analysisOptions": try jsonValue(round.analysisOptions), "strokeStyle": try jsonValue(model.strokeStyle),
      "parentCandidateID": round.parentCandidateID.map { $0.uuidString as Any } ?? NSNull(),
      "modelID": round.modelID.map { $0 as Any } ?? NSNull(), "roundStatus": round.status.rawValue,
      "generationOutcome": complete ? "complete" : candidates.isEmpty ? "failed" : "partial",
      "requestedSlotCount": round.recipes.count, "successfulSlotCount": candidates.count,
      "failedSlotCount": round.failures.count, "slots": slots,
      "expectedSyntheticSuccessfulSlots": operation == "real-generate" ? NSNull() : 3,
      "expectedSyntheticRendererCalls": operation == "real-generate" ? NSNull() : operation == "refine" ? 2 : 3,
      "observedRendererOverrideCalls": operation == "real-generate" ? NSNull() : overrideCalls,
      "syntheticExpectedCountsMatch": operation == "real-generate" ? NSNull() : candidates.count == 3 && overrideCalls == (operation == "refine" ? 2 : 3)]
  }

  /// Deterministic producer boundary. Inputs are loaded outside the timer from
  /// the exact frozen portfolio; no proposals, preferences or UI generation run.
  private func producerReplay(model: FlowDojoModel, root: URL, warmTrials: Int,
    environment: [String: String], baselineHeadSHA256: String) async throws {
    let document = try #require(model.document), store = try #require(model.store)
    let candidate: FlowPortfolioCandidate
    if let selected = environment["DX_FLOW_REPLAY_CANDIDATE_ID"] {
      candidate = try #require(document.candidates.first { $0.id.uuidString.lowercased() == selected.lowercased() })
    } else { candidate = try #require(document.candidates.first) }
    let source = try #require(document.sources.first { $0.id == candidate.sourceID })
    let data = try await store.sourceData(source.id)
    let frozenProgram = try await store.candidateProgram(candidate.id)
    let style = try #require(frozenProgram.strokes.first?.style), recipe = candidate.recipe
    let expected = environment["DX_FLOW_REPLAY_EXPECTED_HASH"]
    try #require(expected != nil || warmTrials == 0, "Pin the first validated actual renderer result externally before measuring warm replay.")
    let renderer = FlowDojoRenderer()
    var samples = [[String: Any]](), firstSeconds = 0.0
    var firstProgram: DrawingProgram?
    var anchor = expected
    for trial in -1..<warmTrials {
      let started = DispatchTime.now().uptimeNanoseconds
      let result = try await renderer.render(data: data, recipe: recipe, strokeStyle: style)
      let elapsed = seconds(since: started)
      // Result validation/hash checks deliberately excluded from render latency.
      let hash = result.program.contentHash.description
      if firstProgram == nil { firstProgram = result.program; firstSeconds = elapsed }
      if anchor == nil { anchor = hash }
      #expect(hash == anchor, "Exact producer replay must preserve the externally pinned program hash.")
      if trial >= 0 { samples.append(["seconds": elapsed, "programContentHash": hash,
        "matchesExpectedHash": hash == anchor, "strokes": result.program.strokes.count]) }
    }
    let first = try #require(firstProgram)
    let programBytes = try DrawingPackageCodec.encoder().encode(first)
    let validated = try JSONDecoder().decode(DrawingProgram.self, from: programBytes)
    #expect(validated.contentHash == first.contentHash)
    let identity = UUID().uuidString, programName = "flow-producer-replay-program-" + identity + ".json"
    try programBytes.write(to: root.appendingPathComponent(programName), options: .atomic)
    let input: [String: Any] = ["candidateID": candidate.id.uuidString, "sourceID": source.id.uuidString,
      "sourceSHA256": DrawingPackageCodec.sha256(data), "sourceBytes": data.count,
      "recipeRevision": FlowArtistRecipe.revision, "recipe": try jsonValue(recipe),
      "strokeStyle": try jsonValue(style), "analysisOptions": try jsonValue(FlowDojoRenderer.analysisOptions)]
    let inputHash = DrawingPackageCodec.sha256(try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]))
    var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
    let mallocSnapshot = allZoneMallocSnapshot()
    var receipt: [String: Any] = ["schemaVersion": 1, "operation": "producer-replay", "phase": "measure",
      "boundary": "production FlowDojoRenderer.render only; exact source/recipe/style preloaded before timer; proposals, UI refresh, persistence, post-timer validation and hashing excluded",
      "inputCondition": "identical frozen input for every call; actual renderer program hash never compared to synthetic fixture output",
      "historyCondition": "one initial render then \(warmTrials) warm renders with the same renderer actor and inputs",
      "initialOperationCount": 1, "measuredWarmOperationCount": warmTrials,
      "baselineHeadSHA256": baselineHeadSHA256, "input": input, "inputReceiptSHA256": inputHash,
      "expectedProgramHash": expected.map { $0 as Any } ?? NSNull(),
      "oracleCondition": expected == nil ? "initial actual result validated and emitted for external pinning; not yet an externally frozen oracle" : "compared against externally pinned actual producer result",
      "firstOperationProgramHash": first.contentHash.description,
      "firstOperationProgramObjectSHA256": DrawingPackageCodec.sha256(programBytes), "firstOperationProgramFile": programName,
      "firstOperationAfterOpenSeconds": firstSeconds,
      "firstOperationCondition": "fresh renderer after model open and input preload; source analysis inside renderer; filesystem cache uncontrolled; not native or disk-cold",
      "samples": samples, "processLifetimePeakRSSBytes": usage.ru_maxrss,
      "peakRSSScope": "Darwin ru_maxrss process lifetime including test startup/model setup/input preload/validation",
      "allocationCount": NSNull(), "queryCount": NSNull(), "decodeCount": NSNull(), "bytesRead": NSNull(), "bytesWritten": NSNull(),
      "sourceCorpus": "synthetic 40x40 PNG; no artistic, camera, signed-app, physical or large-scale claim"]
    receipt.merge(mallocSnapshot) { _, snapshot in snapshot }
    try write(receipt, to: root.appendingPathComponent("flow-producer-replay-" + identity + ".json"))
  }

  /// Public Darwin malloc API: nil explicitly aggregates all allocator zones.
  /// This is a post-timer process snapshot, not cumulative allocation events,
  /// process RSS, retained page/cache memory or an operation-local allocation delta.
  private func allZoneMallocSnapshot() -> [String: Any] {
    var statistics = malloc_statistics_t()
    malloc_zone_statistics(nil, &statistics)
    return ["liveAllZoneMallocBlocks": statistics.blocks_in_use,
      "liveAllZoneMallocBytes": statistics.size_in_use,
      "sumZoneHighwaterTouchedBytes": statistics.max_size_in_use,
      "allZoneMallocReservedBytes": statistics.size_allocated,
      "mallocSnapshotScope": "public malloc_zone_statistics(nil): all-zone process snapshot after timers and before report JSON; zone high-water touched sums are not a simultaneous process peak; cumulative allocation events unavailable"]
  }

  private func jsonValue<T: Encodable>(_ value: T) throws -> Any {
    try JSONSerialization.jsonObject(with: DrawingPackageCodec.encoder().encode(value))
  }

  private func prepare(_ directory: URL, root: URL) async throws {
    let counter = DXFlowRenderCounter(), model = makeModel(directory, counter: counter)
    model.count = 3; await model.open(); try healthy(model)
    for source in 1...4 {
      await model.addPhoto(data: FlowDojoFixture.image(source), title: "DX01 synthetic source \(source)")
      await model.generate(refining: false); try healthy(model)
      try #require(model.roundCandidates.count >= 2)
      for candidate in model.roundCandidates {
        await model.selectCandidate(candidate.id, prune: true)
        let program = try #require(model.program)
        await model.edit(.remove, ids: Set(program.strokes.prefix(4).map(\.id)))
        await model.edit(.completeTarget); try healthy(model)
      }
      await model.rankCurrentSet()
      for (index, item) in try #require(model.presentation).items.enumerated() {
        await model.rank(item: item.id, position: index + 1)
      }
      try healthy(model)
    }
    await model.generate(refining: true); try healthy(model)
    // Parent geometry and its committed human-oracle mask are shared into slot 0.
    try #require(model.round?.parentCandidateID != nil)
    try #require(model.document?.pruneRevisions.contains { $0.action == .inheritedSelection } == true)
    await model.rankCurrentSet(); try healthy(model)
    await model.fit(); try healthy(model)
    let fit = try #require(model.document?.fits.last)
    try #require(fit.hasCheckpoint, "Synthetic feedback must exercise the active checkpoint refresh/decode path.")
    await model.activate(fit.id); try healthy(model)
    try #require(model.activeCheckpoint != nil)
    let document = try #require(model.document), store = try #require(model.store)
    var sourceReceipts = [[String: Any]](), programReceipts = [[String: Any]]()
    for source in document.sources {
      let data = try await store.sourceData(source.id)
      sourceReceipts.append(["id": source.id.uuidString, "sha256": DrawingPackageCodec.sha256(data), "bytes": data.count])
    }
    for candidate in document.candidates {
      let program = try await store.candidateProgram(candidate.id)
      let data = try DrawingPackageCodec.encoder().encode(program)
      programReceipts.append(["id": candidate.id.uuidString, "sha256": DrawingPackageCodec.sha256(data), "encodedBytes": data.count, "strokes": program.strokes.count])
    }
    #expect(await model.shutdown())
    try write(["schemaVersion": 1, "purpose": "validationFixture; all judgments and vector rendering synthetic",
      "revision": document.revision, "sources": sourceReceipts, "programs": programReceipts,
      "rounds": document.rounds.count, "pruneRevisions": document.pruneRevisions.count,
      "rankings": document.rankings.count, "choices": document.choices.count,
      "parentedRounds": document.rounds.filter { $0.parentCandidateID != nil }.count,
      "inheritedMasks": document.pruneRevisions.filter { $0.action == .inheritedSelection }.count,
      "completedMasks": document.pruneRevisions.filter { $0.action == .completeTarget }.count,
      "activeFitID": fit.id.uuidString,
      "sourceDimensionsPixels": [40, 40], "strokesPerSyntheticDrawing": 16,
      "headSHA256": DrawingPackageCodec.sha256(try Data(contentsOf: directory.appendingPathComponent("portfolio.json")))],
      to: root.appendingPathComponent("flow-prepare.json"))
  }

  private func perform(_ operation: String, model: FlowDojoModel, directory: URL, trial: Int) async throws {
    let candidate = model.roundCandidates.first
    switch operation {
    case "view":
      // Actual visible model projection, no made-up store query counters.
      _ = model.roundCandidates; _ = model.previews; _ = model.program; _ = model.trainingProgress
    case "select": await model.browseCandidate(model.roundCandidates[(trial + 1) % model.roundCandidates.count].id)
    case "choose": await model.selectCandidate(try #require(candidate).id)
    case "generate", "real-generate": await model.generate(refining: false)
    case "refine":
      if model.candidate == nil { await model.browseCandidate(try #require(candidate).id) }
      await model.generate(refining: true)
    case "prune":
      if model.candidate == nil { await model.browseCandidate(try #require(candidate).id) }
      let stroke = try #require(model.program?.strokes.first?.id)
      if trial == -1 { try #require(model.removedIDs.contains(stroke), "Warmup restore requires an actually removed inherited stroke.") }
      await model.edit(trial % 2 == 0 ? .remove : .restore, ids: [stroke])
    case "rename": await model.renameCandidate(try #require(candidate).id, title: "DX01 synthetic rename \(trial)")
    case "rank":
      let presentation = try #require(model.presentation), item = try #require(presentation.items.first)
      await model.rank(item: item.id, position: trial % 2 == 0 ? 1 : 2)
      #expect(model.presentation?.id == presentation.id)
    case "failed-rank":
      let presentation = try #require(model.presentation), item = try #require(presentation.items.first)
      let before = try #require(model.document), ranks = model.ranks
      let records = directory.appendingPathComponent("records"), retained = directory.appendingPathComponent("records-paused")
      try FileManager.default.moveItem(at: records, to: retained)
      try Data([0]).write(to: records)
      await model.rank(item: item.id, position: 1)
      #expect(model.needsRecovery)
      #expect(model.presentation?.id == presentation.id && model.ranks == ranks)
      #expect(model.document?.rankings == before.rankings && model.document?.revision == before.revision)
      let durable = try #require(model.store)
      #expect(await durable.snapshot().rankings == before.rankings)
      try FileManager.default.removeItem(at: records)
      try FileManager.default.moveItem(at: retained, to: records)
      // Recovery is part of this fault-injection cycle, explicitly not rank latency.
      await model.recoverAutosave()
    case "equal-byte-capture":
      let data = FlowDojoFixture.image(1), before = try #require(model.document?.sources.count)
      for offset in 0..<2 {
        let photo = PortraitPhoto(id: UUID(), data: data, label: "DX01 equal bytes",
          capturedAt: Date(timeIntervalSince1970: Double(1000 + (trial + 1) * 2 + offset)), frameID: FrameID(),
          captureNanoseconds: UInt64(1000 + (trial + 1) * 2 + offset), pose: .front,
          sourcePixelExtent: try .init(widthPixels: 40, heightPixels: 40), captureSessionID: UUID())
        await model.addCapturedPhoto(photo, title: "DX01 capture occurrence")
      }
      let last = Array(try #require(model.document).sources.suffix(2))
      #expect(model.document?.sources.count == before + 2)
      #expect(last[0].id != last[1].id && last[0].image.sha256 == last[1].image.sha256)
    default: throw FlowPortfolioError.invalid("Unsupported baseline operation")
    }
    try healthy(model)
  }

  private func makeModel(_ directory: URL, counter: DXFlowRenderCounter, real: Bool = false) -> FlowDojoModel {
    if real { return FlowDojoModel(directory: directory, purpose: .validationFixture) }
    return FlowDojoModel(directory: directory, purpose: .validationFixture, render: { data, recipe, style in
      let started = DispatchTime.now().uptimeNanoseconds
      let result = try await FlowDojoFixture.render(data, recipe, style)
      await counter.record(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000)
      return result
    })
  }
  private func healthy(_ model: FlowDojoModel) throws {
    try #require(model.error == nil, "\(model.error ?? "")")
    try #require(!model.needsRecovery)
  }
  private func seconds(since started: UInt64) -> Double { Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000 }
  private func write(_ value: [String: Any], to url: URL) throws {
    try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
  }
}

private actor DXFlowRenderCounter {
  private var calls = 0
  private var seconds = 0.0
  func record(_ elapsed: Double) { calls += 1; seconds += elapsed }
  func snapshot() -> (Int, Double) { (calls, seconds) }
}
