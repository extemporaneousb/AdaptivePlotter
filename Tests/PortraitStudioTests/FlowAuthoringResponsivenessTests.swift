import Foundation
import CoreGraphics
import ImageIO
import PlotterModel
import PortraitArtists
import PortraitCore
import PortraitLibrary
import PortraitStudioUI
import Testing

/// Opt-in model-level evidence, separate from renderer-only phase timings. All
/// persisted output belongs to a disposable Library; no GUI/camera is opened.
@Suite("Flow authoring Release responsiveness", .serialized)
@MainActor
struct FlowAuthoringResponsivenessTests {
  @Test("Record MainActor heartbeats through actual generation and cancellation",
    .enabled(if: ProcessInfo.processInfo.environment["FLOW_PROFILE_SOURCE"] != nil))
  func actualGenerationAndCancellation() async throws {
    let env = ProcessInfo.processInfo.environment
    let source = URL(fileURLWithPath: try #require(env["FLOW_PROFILE_SOURCE"]))
    let output = URL(fileURLWithPath: try #require(env["FLOW_PROFILE_OUTPUT"]))
    let data = try Data(contentsOf: source)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("flow-model-profile-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let template = env["FLOW_PROFILE_LIBRARY_TEMPLATE"].map { URL(fileURLWithPath: $0) }
    if let template { try await Task.detached { try Self.copyIndependentTemplate(template, to: directory) }.value }
    let model = FlowAuthoringModel(directory: directory, purpose: template == nil ? .validationFixture : nil)
    model.count = 3
    let recorder = FlowAuthoringHeartbeatRecorder()
    let heartbeat = Task { @MainActor in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .milliseconds(10)) } catch { break }
        guard !Task.isCancelled else { break }
        recorder.sample(model)
      }
    }
    defer { heartbeat.cancel() }
    await model.open()
    let openingMS = Date().timeIntervalSince(recorder.phaseStart) * 1000
    #expect(model.error == nil && !model.needsRecovery)
    let initialCandidates = model.document?.candidates.count ?? 0, initialRounds = model.document?.rounds.count ?? 0
    let initialPrunes = model.document?.pruneRevisions.count ?? 0, initialPurpose = model.document?.purpose.rawValue ?? "unavailable"
    let modelScenario = env["FLOW_PROFILE_MODEL_SCENARIO"] ?? "inherited"
    if modelScenario == "none", model.activeCheckpoint != nil { await model.activate(nil) }
    if modelScenario == "latest", let fit = model.document?.fits.last(where: \.hasCheckpoint) { await model.activate(fit.id) }
    let checkpointDigest = model.activeCheckpoint?.id, checkpointIssue = model.activeModelIssue ?? model.error
    recorder.begin("source-admission")
    await model.addPhoto(data: data, title: "Disposable exact-input model profile")
    #expect(model.error == nil && !model.needsRecovery)
    recorder.begin("cold-generation")
    await model.generate(refining: false)
    let completeMS = Date().timeIntervalSince(recorder.phaseStart) * 1000
    #expect(model.error == nil && !model.needsRecovery && model.roundCandidates.count == 3)
    recorder.begin("warm-cancellation")
    let generating = Task { await model.generate(refining: false); recorder.generationFinished = true }
    // Cancel an actual render/admission worker, rather than only invalidating
    // an operation before it reaches preparation. A deadline bounds this probe.
    while !model.isRenderingGeneration && !recorder.generationFinished && Date().timeIntervalSince(recorder.phaseStart) < 30 {
      try await Task.sleep(for: .milliseconds(1))
    }
    let observedWorker = model.isRenderingGeneration
    let cancelStart = Date(); model.cancel()
    await generating.value
    let cancelToQuiescentMS = Date().timeIntervalSince(cancelStart) * 1000
    heartbeat.cancel(); await heartbeat.value
    #expect(observedWorker && !model.isBusy && !model.isRenderingGeneration && !model.isPreparingGeneration)
    #expect(!model.needsRecovery)
    let gaps = recorder.rows.compactMap { $0["gapMS"] as? Double }.sorted()
    #expect(!gaps.isEmpty && gaps.allSatisfy(\.isFinite))
    let report: [String: Any] = ["sourceSHA256": DrawingArtifactCoding.sha256(data), "candidateBudget": 3,
      "libraryTemplate": template?.path ?? "fresh-disposable", "initialCandidates": initialCandidates,
      "initialRounds": initialRounds, "initialPrunes": initialPrunes, "purpose": initialPurpose,
      "openingMS": openingMS, "requestedModelScenario": modelScenario,
      "actualModelScenario": model.activeCheckpoint == nil ? "none" : "loaded",
      "checkpointDigest": checkpointDigest.map { $0 as Any } ?? NSNull(),
      "checkpointIssue": checkpointIssue.map { $0 as Any } ?? NSNull(), "firstVisibleSampleMS": recorder.firstVisibleMS.map { $0 as Any } ?? NSNull(),
      "panelCompleteMS": completeMS, "heartbeatTargetMS": 10,
      "maximumObservedHeartbeatGapMS": gaps.last.map { $0 as Any } ?? NSNull(),
      "medianObservedHeartbeatGapMS": gaps.isEmpty ? 0 : gaps[gaps.count / 2],
      "cancelObservedActualWorker": observedWorker, "cancelToWorkerQuiescentMS": cancelToQuiescentMS,
      "cancelledRoundStatus": model.round?.status.rawValue ?? "none", "heartbeats": recorder.rows,
      "scope": "MainActor model projection; no native frame or AX event latency claim"]
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
      .write(to: output.appendingPathComponent("model-responsiveness.json"))
    #expect(await model.shutdown())
  }

  @Test("Export six real variants through broad and two contracting child pages",
    .enabled(if: ProcessInfo.processInfo.environment["FLOW_PROFILE_SOURCE"] != nil
      && ProcessInfo.processInfo.environment["FLOW_EXPLORATION_OUTPUT"] != nil))
  func actualExplorationArtifacts() async throws {
    let env = ProcessInfo.processInfo.environment
    let source = URL(fileURLWithPath: try #require(env["FLOW_PROFILE_SOURCE"]))
    let output = URL(fileURLWithPath: try #require(env["FLOW_EXPLORATION_OUTPUT"]))
    let bytes = try Data(contentsOf: source), sourceHash = DrawingArtifactCoding.sha256(bytes)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("flow-visual-exploration-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let model = FlowAuthoringModel(directory: directory, purpose: .validationFixture)
    model.count = 6
    await model.open(); await model.addPhoto(data: bytes, title: "Disposable real-source visual exploration")
    let photo = try #require(model.currentPhotoRef), store = try #require(model.store)
    try bytes.write(to: output.appendingPathComponent("source-original." + (model.selectedSource?.image.mediaType == "image/jpeg" ? "jpg" : "png")))
    var panels: [[String: Any]] = []
    func savePanel(_ name: String) async throws -> (FlowPortfolioRound, [FlowPortfolioCandidate]) {
      let round = try #require(model.round), candidates = model.roundCandidates
      #expect(model.error == nil && !model.needsRecovery && round.status == .completed && candidates.count == 6)
      let panelDirectory = output.appendingPathComponent(name)
      try FileManager.default.createDirectory(at: panelDirectory, withIntermediateDirectories: true)
      try DrawingArtifactCoding.encoder().encode(round).write(to: panelDirectory.appendingPathComponent("round.json"))
      var rows: [[String: Any]] = [], previews: [Data] = [], geometryHashes: [String] = []
      for (index, candidate) in candidates.enumerated() {
        let program = try await store.candidateProgram(candidate.id), preview = try #require(model.previews[candidate.id])
        let removed = Set(model.document?.latestPrune(candidateID: candidate.id)?.removedIndices ?? [])
        let strokes = program.strokes.enumerated().filter { !removed.contains($0.offset) }.map { $0.element }
        // Geometry identity excludes generated UUIDs, so duplicate counts cannot
        // be inflated by distinct candidate/program/stroke identities alone.
        let geometry: [String: Any] = ["extent": [program.fieldExtent.width, program.fieldExtent.height],
          "strokes": strokes.map { stroke in ["points": stroke.path.points.map { [$0.x, $0.y] },
            "width": stroke.style.nominalLineWidth, "ordering": Int(stroke.ordering), "role": Int(stroke.semanticRole.rawValue)] as [String: Any] }]
        let geometryBytes = try JSONSerialization.data(withJSONObject: geometry, options: [.sortedKeys])
        let geometryHash = DrawingArtifactCoding.sha256(geometryBytes)
        let prefix = String(format: "%02d", index)
        try preview.write(to: panelDirectory.appendingPathComponent(prefix + ".png"))
        try DrawingArtifactCoding.encoder().encode(program).write(to: panelDirectory.appendingPathComponent(prefix + ".program.json"))
        previews.append(preview); geometryHashes.append(geometryHash)
        rows.append(["index": index, "candidateID": candidate.id.uuidString, "slot": candidate.slot,
          "programHash": program.contentHash.description, "geometryHash": geometryHash,
          "previewHash": DrawingArtifactCoding.sha256(preview), "strokeCount": program.strokes.count,
          "removedIndices": removed.sorted(), "recipe": try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(candidate.recipe))])
      }
      try Self.visualContactSheet(previews).write(to: panelDirectory.appendingPathComponent("panel.png"))
      let panel: [String: Any] = ["name": name, "roundID": round.id.uuidString,
        "parentCandidateID": round.parentCandidateID.map { $0.uuidString as Any } ?? NSNull(),
        "depth": round.explorationDepth.map { $0 as Any } ?? NSNull(),
        "radius": round.refinementRadius.map { $0 as Any } ?? NSNull(), "seed": String(round.seed),
        "analysisOptions": try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(round.analysisOptions)),
        "distinctGeometryCount": Set(geometryHashes).count,
        "distinctGeometryPairCount": geometryHashes.indices.reduce(0) { total, i in
          total + geometryHashes.indices.filter { $0 > i && geometryHashes[$0] != geometryHashes[i] }.count
        },
        "identicalGeometryPairs": geometryHashes.indices.flatMap { i in
          geometryHashes.indices.filter { $0 > i && geometryHashes[$0] == geometryHashes[i] }.map { [i, $0] }
        },
        "distinctPreviewCount": Set(previews.map(DrawingArtifactCoding.sha256)).count,
        "choiceCount": model.document?.choices.count ?? 0, "candidates": rows]
      try JSONSerialization.data(withJSONObject: panel, options: [.sortedKeys, .prettyPrinted])
        .write(to: panelDirectory.appendingPathComponent("panel.json"))
      panels.append(panel); return (round, candidates)
    }
    await model.generate(refining: false)
    let (broad, first) = try await savePanel("00-broad")
    let startingChoices = model.document?.choices.count ?? 0
    // Scripted choice of the second visible tile avoids choosing a new anchor
    // by hidden score or adding strong ratings. All six offered outputs survive.
    await model.exploreCandidate(first[1].id)
    let (child, second) = try await savePanel("01-child-006")
    #expect(child.parentCandidateID == first[1].id && child.explorationDepth == 1 && child.refinementRadius == 0.06)
    #expect(model.document?.choices.count == startingChoices + 1)
    await model.exploreCandidate(second[1].id)
    let (grandchild, _) = try await savePanel("02-child-0051")
    #expect(grandchild.parentCandidateID == second[1].id && grandchild.explorationDepth == 2)
    #expect(abs(try #require(grandchild.refinementRadius) - 0.051) < 1e-10)
    let choices = model.document?.choices.count ?? 0
    #expect(choices == startingChoices + 2)
    await model.selectRound(child.id)
    #expect(model.round?.id == child.id && model.document?.choices.count == choices)
    await model.generate(refining: false)
    let (reset, _) = try await savePanel("03-broad-reset")
    #expect(reset.parentCandidateID == nil && reset.explorationDepth == 0 && reset.refinementRadius == nil)
    #expect(model.document?.choices.count == choices && model.currentPhotoRef == photo && model.sourceData == bytes)
    let report: [String: Any] = ["sourcePath": source.path, "sourceSHA256": sourceHash,
      "tileBudgetPerPanel": 6, "checkpoint": "none", "purpose": "validationFixture", "panels": panels,
      "broadRoundID": broad.id.uuidString, "choiceDelta": choices - startingChoices, "backWasNeutral": true,
      "scope": "Actual headless model/producer outputs; scripted weak choices only, no human preference or native click-latency claim"]
    try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
      .write(to: output.appendingPathComponent("exploration-manifest.json"))
    #expect(await model.shutdown())
  }

  private nonisolated static func visualContactSheet(_ previews: [Data]) throws -> Data {
    let width = 960, height = 640
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
    context.setFillColor(CGColor(gray: 0.86, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: Double(width), height: Double(height)))
    for (index, preview) in previews.enumerated() {
      guard let source = CGImageSourceCreateWithData(preview as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CocoaError(.fileReadCorruptFile) }
      let scale = min(308.0 / Double(image.width), 308.0 / Double(image.height))
      let w = Double(image.width) * scale, h = Double(image.height) * scale
      context.draw(image, in: CGRect(x: Double(index % 3) * 320 + (320 - w) / 2,
        y: Double(1 - index / 3) * 320 + (320 - h) / 2, width: w, height: h))
    }
    guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
    return try PortraitImageAnalyzer.encodedImage(image)
  }

  private nonisolated static func copyIndependentTemplate(_ template: URL, to destination: URL) throws {
    let allowed = URL(fileURLWithPath: "/tmp/portrait-studio-evidence").resolvingSymlinksInPath().path + "/"
    let exact = template.resolvingSymlinksInPath()
    let target = destination.standardizedFileURL.resolvingSymlinksInPath()
    guard exact.path.hasPrefix(allowed), exact.path != target.path,
      FileManager.default.fileExists(atPath: exact.appendingPathComponent("snapshot-manifest.json").path) else {
      throw CocoaError(.fileReadNoPermission)
    }
    let manager = FileManager.default
    guard let sourceFiles = manager.enumerator(at: exact, includingPropertiesForKeys: [.isSymbolicLinkKey]) else {
      throw CocoaError(.fileReadUnknown)
    }
    for case let file as URL in sourceFiles {
      if try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw CocoaError(.fileReadNoPermission) }
    }
    try manager.copyItem(at: exact, to: target)
    try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: target.path)
    guard let copiedFiles = manager.enumerator(atPath: target.path) else {
      throw CocoaError(.fileReadUnknown)
    }
    for case let relative as String in copiedFiles {
      let file = target.appendingPathComponent(relative)
      let original = exact.appendingPathComponent(relative)
      let originalAttributes = try manager.attributesOfItem(atPath: original.path)
      let attributes = try manager.attributesOfItem(atPath: file.path)
      if attributes[.systemFileNumber] as? NSNumber == originalAttributes[.systemFileNumber] as? NSNumber,
        attributes[.systemNumber] as? NSNumber == originalAttributes[.systemNumber] as? NSNumber {
        throw CocoaError(.fileWriteNoPermission)
      }
      let isDirectory = try file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
      if !isDirectory, (attributes[.referenceCount] as? NSNumber)?.intValue != 1 { throw CocoaError(.fileWriteNoPermission) }
      try manager.setAttributes([.posixPermissions: isDirectory ? 0o700 : 0o600], ofItemAtPath: file.path)
    }
  }

}


/// A let-captured MainActor owner keeps probe mutation out of Sendable closure
/// capture boxes; cancellation is the heartbeat task's only stop authority.
@MainActor
private final class FlowAuthoringHeartbeatRecorder {
  var rows: [[String: Any]] = []
  var phase = "opening-history"
  var phaseStart = Date()
  private var lastBeat = Date()
  var firstVisibleMS: Double?
  var generationFinished = false
  func begin(_ phase: String) {
    self.phase = phase; phaseStart = Date(); lastBeat = phaseStart
  }
  func sample(_ model: FlowAuthoringModel) {
    let now = Date(), gap = now.timeIntervalSince(lastBeat) * 1000
    rows.append(["phase": phase, "elapsedMS": now.timeIntervalSince(phaseStart) * 1000, "gapMS": gap,
      "preparing": model.isPreparingGeneration, "rendering": model.isRenderingGeneration,
      "completedCandidates": model.roundCandidates.count])
    if phase == "cold-generation", firstVisibleMS == nil,
      model.roundCandidates.contains(where: { model.previews[$0.id] != nil }) {
      firstVisibleMS = now.timeIntervalSince(phaseStart) * 1000
    }
    lastBeat = now
  }
}
