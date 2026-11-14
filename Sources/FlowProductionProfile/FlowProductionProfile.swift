import Foundation
import PlotterModel
import PortraitArtists
import PortraitCore
import PortraitLibrary
import PortraitStudioUI

/// Bounded headless production workload. Every write is disposable; no GUI,
/// camera, personal Library, or controller is opened.
@main
struct FlowProductionProfile {
  static func require<T>(_ value: T?) throws -> T {
    guard let value else { throw ProfileError.missingConfiguration }
    return value
  }
  enum ProfileError: Error { case missingConfiguration, reopenMismatch, feedbackChanged }
  static func main() async throws {
    let env = ProcessInfo.processInfo.environment
    let source = URL(fileURLWithPath: try require(env["FLOW_PROFILE_SOURCE"]))
    let output = URL(fileURLWithPath: try require(env["FLOW_PROFILE_OUTPUT"]))
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let clonePath = env["FLOW_PROFILE_LIBRARY_CLONE"]
    if let clonePath {
      guard clonePath.hasPrefix("/tmp/portrait-studio-evidence/")
        || clonePath.hasPrefix("/private/tmp/portrait-studio-evidence/") else { throw ProfileError.missingConfiguration }
    }
    let directory = clonePath.map { URL(fileURLWithPath: $0) }
      ?? output.appendingPathComponent("disposable-" + UUID().uuidString)
    defer { if clonePath == nil { try? FileManager.default.removeItem(at: directory) } }
    let data = try Data(contentsOf: source), renderer = FlowAuthoringRenderer()
    let checkpointBytes = try env["FLOW_PROFILE_CHECKPOINT"].map { try Data(contentsOf: URL(fileURLWithPath: $0)) }
    let checkpoint = try checkpointBytes.map { try JSONDecoder().decode(FlowArtistCheckpoint.self, from: $0) }
    try checkpoint?.validateForInference()
    let style = try StrokeStyle(nominalLineWidth: 0.4,
      penProfileID: PenProfileID(UUID(uuidString: "BE74CA88-CA42-4BA1-8520-F2DE242E01FF")!))
    let openBegan = Date()
    let store = FlowPortfolioStore(directory: directory, purpose: clonePath == nil ? .validationFixture : nil)
    let fullDecoder = env["FLOW_PROFILE_FULL_DECODE"] == "1"
    try await store.loadRecords(reusingEncodedStrokeBasis: !fullDecoder)
    let openMS = Date().timeIntervalSince(openBegan) * 1000
    let initial = await store.snapshot()
    let feedbackBefore = try await store.feedbackProjectionDigest()
    let loaderStatistics = await store.lastFeedbackReadStatistics
    if env["FLOW_PROFILE_PROJECTION_ONLY"] == "1" {
      let projection: [String: Any] = ["scope": "Diagnostic projection only; no candidate or feedback writes",
        "fullNumericDecoder": fullDecoder, "openMS": openMS, "feedbackProjection": feedbackBefore,
        "candidates": initial.candidates.count, "rounds": initial.rounds.count,
        "choices": initial.choices.count, "prunes": initial.pruneRevisions.count, "rankings": initial.rankings.count,
        "activeFitID": initial.activeFitID?.uuidString ?? "none",
        "loaderStatistics": try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(loaderStatistics))]
      try JSONSerialization.data(withJSONObject: projection, options: [.prettyPrinted, .sortedKeys])
        .write(to: output.appendingPathComponent("projection-profile.json"), options: .atomic)
      await store.closeLibrary()
      print(output.appendingPathComponent("projection-profile.json").path)
      return
    }
    let retained = try await store.addSource(data: data, title: "Disposable profiling fixture")
    let photo = try await store.sourcePhoto(retained.id)
    let recipes: [FlowArtistRecipe] = [.standard,
      .init(nativeValues: [4, 5, 0.18, 1.15, 2.6, 0.014, 0, 0.25, 0.25, 0.45, 0.3, 0]),
      .init(nativeValues: [4, 4, 0.15, 1.1, 1.4, 0.014, 0, 0.15, 0.15, 0.4, 0.4, 0.1], marks: .init(wave: 1, scale: 0.45))]
    var rows: [[String: Any]] = []
    for roundIndex in 0..<3 {
      let began = Date()
      let round = try await store.beginRound(sourceID: retained.id, recipes: recipes, modelID: checkpoint?.id, seed: 731,
        analysisOptions: FlowAuthoringRenderer.analysisOptions)
      for (slot, recipe) in recipes.enumerated() {
        let start = Date()
        let production = try await renderer.produce(data: data, recipe: recipe, strokeStyle: style,
          nominalPenWidthMM: 0.4, photo: photo)
        let rendered = Date()
        let preview = try FlowAuthoringRenderer.preview(production.artifacts.program)
        let previewed = Date()
        let strokeFeatures = checkpoint == nil ? [] : FlowArtistFeatures.strokes(recipe: recipe,
          program: production.artifacts.program, raster: production.artifacts.raster)
        let probabilities = try checkpoint?.deletionProbabilities(strokeFeatures: strokeFeatures)
        let removed = try checkpoint?.removedIndices(strokeFeatures: strokeFeatures) ?? []
        let features = checkpoint == nil ? [] : FlowArtistFeatures.drawing(recipe: recipe,
          program: production.artifacts.program, raster: production.artifacts.raster, removedIndices: removed)
        let score = try checkpoint?.score(features: features) ?? 0
        let scored = Date()
        let candidate = try await store.completeCandidate(roundID: round.id, slot: slot,
          production: production, previewPNG: preview)
        if let probabilities, let checkpoint {
          _ = try await store.applyPrune(candidateID: candidate.id, action: .modelProposal,
            indices: removed.sorted(), modelID: checkpoint.id, probabilities: probabilities,
            threshold: 0.65, policy: "threshold-keep-one-v1")
        }
        let committed = Date()
        _ = try await store.candidateProgram(candidate.id)
        let end = Date(), t = production.artifacts.timings ?? .init()
        let d = production.artifacts.flowWorkspace?.diagnostics ?? .init()
        let sourcePhases = t.sourceCacheHit ? PortraitSourcePhaseTimings() : (production.artifacts.preparedSource?.phaseTimings ?? .init())
        rows.append(["round": roundIndex, "slot": slot, "productionMS": rendered.timeIntervalSince(start)*1000,
          "previewMS": previewed.timeIntervalSince(rendered)*1000,
          "featuresMS": scored.timeIntervalSince(previewed)*1000,
          "commitMS": committed.timeIntervalSince(scored)*1000, "reloadMS": end.timeIntervalSince(committed)*1000,
          "firstOrPanelMS": end.timeIntervalSince(began)*1000,
          "decodeMS": sourcePhases.decodeMS, "faceVisionMS": sourcePhases.faceVisionMS,
          "personVisionMS": sourcePhases.personVisionMS, "pyramidMS": sourcePhases.pyramidMS,
          "sourceDigestMS": sourcePhases.digestMS,
          "sourceMS": t.sourceMS, "cropMS": t.cropMS, "flowMS": t.flowMS, "vectorMS": t.vectorMS,
          "sourceHit": t.sourceCacheHit, "rasterHit": t.rasterCacheHit,
          "flowSourceHit": d.sourceCacheHit, "flowSourceBuilds": d.sourceBuilds,
          "orientationBuilds": d.orientationBuilds, "supportLevelBuilds": d.supportLevelBuilds,
          "tracingMS": d.tracingMS, "flowRetainedBytes": production.artifacts.flowWorkspace?.retainedByteCount ?? 0,
          "hash": production.artifacts.program.contentHash.description,
          "previewHash": DrawingArtifactCoding.sha256(preview),
          "rasterHash": DrawingArtifactCoding.sha256(try DrawingArtifactCoding.encoder().encode(production.artifacts.raster)),
          "featureHash": DrawingArtifactCoding.sha256(try DrawingArtifactCoding.encoder().encode(features)),
          "score": score, "removedIndices": removed.sorted(),
          "probabilityHash": DrawingArtifactCoding.sha256(try DrawingArtifactCoding.encoder().encode(probabilities)),
          "strokeFeatureCount": strokeFeatures.count, "strokes": production.artifacts.program.strokes.count])
        try preview.write(to: output.appendingPathComponent("round-\(roundIndex)-slot-\(slot).png"))
      }
      try await store.finishRound(round.id)
    }
    let feedbackAfter = try await store.feedbackProjectionDigest(matching: initial)
    guard feedbackAfter == feedbackBefore else { throw ProfileError.feedbackChanged }
    await store.closeLibrary()
    let reopenBegan = Date()
    let reopened = FlowPortfolioStore(directory: directory, purpose: clonePath == nil ? .validationFixture : nil)
    try await reopened.loadRecords(reusingEncodedStrokeBasis: !fullDecoder)
    guard await reopened.snapshot().rounds.count == initial.rounds.count + 3 else { throw ProfileError.reopenMismatch }
    let reopenMS = Date().timeIntervalSince(reopenBegan) * 1000
    let reopenedStatistics = await reopened.lastFeedbackReadStatistics
    let feedbackReopened = try await reopened.feedbackProjectionDigest(matching: initial)
    guard feedbackReopened == feedbackBefore else { throw ProfileError.feedbackChanged }
    await reopened.closeLibrary()
    let receipt: [String: Any] = ["sourceSHA256": DrawingArtifactCoding.sha256(data),
      "os": ProcessInfo.processInfo.operatingSystemVersionString, "processors": ProcessInfo.processInfo.activeProcessorCount,
      "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory,
      "historyClone": clonePath != nil, "openMS": openMS, "reopenMS": reopenMS,
      "initialCandidates": initial.candidates.count, "initialRounds": initial.rounds.count,
      "initialPruneRevisions": initial.pruneRevisions.count,
      "initialActiveFitID": initial.activeFitID?.uuidString ?? "none",
      "feedbackProjectionBefore": feedbackBefore, "feedbackProjectionAfter": feedbackAfter,
      "feedbackProjectionReopened": feedbackReopened,
      "loaderStatistics": try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(loaderStatistics)),
      "reopenedLoaderStatistics": try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(reopenedStatistics)),
      "sourceRevision": env["FLOW_PROFILE_REVISION"] ?? "unspecified",
      "configuration": "Release required by invocation; harness itself does not force compiler flags",
      "fixtureBytes": data.count, "checkpointID": checkpoint?.id ?? "none",
      "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
      "checkpointSHA256": checkpointBytes.map { DrawingArtifactCoding.sha256($0) } ?? "none",
      "scope": "headless production rendering/admission/preview/features/inference/disposable persistence; no UI timing; optional archived checkpoint",
      "recipes": try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(recipes)), "rows": rows]
    try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
      .write(to: output.appendingPathComponent("production-profile.json"), options: .atomic)
    print(output.appendingPathComponent("production-profile.json").path)
  }
}
