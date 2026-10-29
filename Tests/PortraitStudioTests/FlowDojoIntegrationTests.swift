import Foundation
import PlotterModel
import PortraitArtists
import PortraitCore
import PortraitLibrary
import PortraitStudioUI
import Testing

@Suite("Flow Edge dojo complete learning loop", .serialized)
@MainActor
struct FlowDojoIntegrationTests {
  @Test("Curate, rank, fit, deploy, reopen, generate learned proposals, correct and refit")
  func completeLoop() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let copied = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: copied) }
    let model = FlowDojoModel(directory: directory, purpose: .validationFixture, render: FlowDojoFixture.render)
    model.count = 3; await model.open()
    for index in 1...4 {
      await model.addPhoto(data: FlowDojoFixture.image(index), title: "TEST ORACLE source \(index)")
      await model.generate(refining: false)
      try await curateRound(model)
    }
    await model.fit(); #expect(model.error == nil)
    let fit = try #require(model.document?.fits.last)
    let report = try #require(model.fitReport)
    try #require(report.checkpoint != nil, "\(report.summary)")
    #expect(report.ranker.trainingCount > 0); #expect(report.deleter.trainingCount > 0)
    #expect(report.ranker.holdoutGroupCount > 0); #expect(report.deleter.holdoutGroupCount > 0)
    #expect(fit.hasCheckpoint)
    await model.activate(fit.id)
    let checkpointID = try #require(model.activeCheckpoint?.id)
    await model.generate(refining: false)
    #expect(model.error == nil)
    #expect(model.round?.modelID == checkpointID)
    #expect(model.round?.recommendedCandidateID != nil)
    let proposals = (model.document?.pruneRevisions ?? []).filter { $0.action == .modelProposal }
    #expect(proposals.count == model.roundCandidates.count)
    #expect(proposals.contains { !$0.removedIndices.isEmpty })
    let chosen = try #require(model.roundCandidates.first)
    await model.selectCandidate(chosen.id, prune: true)
    if let restoredID = model.removedIDs.first { await model.edit(.restore, ids: [restoredID]) }
    else if let id = model.program?.strokes.first?.id { await model.edit(.remove, ids: [id]) }
    await model.edit(.completeTarget)
    await model.presentRanking(scope: .candidate(chosen.id)); try await rankByOracle(model)
    await model.fit(); #expect(model.error == nil)
    let second = try #require(model.document?.fits.last)
    #expect(second.id != fit.id)
    await model.activate(second.id)
    let secondCheckpoint = try #require(model.activeCheckpoint?.id)
    #expect(secondCheckpoint != checkpointID)
    let revision = try #require(model.document?.revision)
    await model.shutdown()
    try FileManager.default.copyItem(at: directory, to: copied)
    let reopened = FlowDojoModel(directory: copied, render: FlowDojoFixture.render)
    await reopened.open(); #expect(reopened.error == nil)
    #expect(reopened.document?.revision == revision)
    #expect(reopened.activeCheckpoint?.id == secondCheckpoint)
    await reopened.activate(fit.id); #expect(reopened.activeCheckpoint?.id == checkpointID)
    await reopened.activate(nil); #expect(reopened.activeCheckpoint == nil)
    await reopened.shutdown()
  }

  @Test("Real Flow Edge renders through the same portfolio-training-deployment loop with declared test judgments",
    .enabled(if: ProcessInfo.processInfo.environment["FLOW_DOJO_TRIAL_ROOT"] != nil))
  func realPhotoTrial() async throws {
    let environment = ProcessInfo.processInfo.environment
    let root = URL(fileURLWithPath: try #require(environment["FLOW_DOJO_TRIAL_ROOT"]), isDirectory: true)
    let sourceURL = URL(fileURLWithPath: try #require(environment["FLOW_DOJO_REAL_SOURCE"]))
    let directory = root.appendingPathComponent("Validation.flowportfolio", isDirectory: true)
    guard !FileManager.default.fileExists(atPath: directory.path) else {
      throw FlowPortfolioError.conflict("Choose a fresh trial output; an existing validation portfolio is never overwritten.")
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let model = FlowDojoModel(directory: directory, purpose: .validationFixture)
    model.count = 4
    let started = Date()
    await model.open()
    await model.addPhoto(data: try Data(contentsOf: sourceURL), title: "REAL PHOTO / SYNTHETIC TEST JUDGMENTS")
    await model.generate(refining: false)
    #expect(model.error == nil)
    #expect(model.roundCandidates.count >= 2)
    try await curateRound(model)
    await model.generate(refining: true)
    #expect(model.error == nil)
    try await curateRound(model)
    await model.fit(); #expect(model.error == nil)
    let first = try #require(model.document?.fits.last), firstReport = try #require(model.fitReport)
    #expect(first.hasCheckpoint)
    await model.activate(first.id)
    let active = try #require(model.activeCheckpoint)
    model.count = 3
    await model.generate(refining: false)
    #expect(model.error == nil)
    #expect(model.round?.recommendedCandidateID != nil)
    let learned = (model.document?.pruneRevisions ?? []).filter { $0.action == .modelProposal }
    #expect(!learned.isEmpty)
    #expect(learned.contains { !$0.removedIndices.isEmpty })
    let chosen = try #require(model.roundCandidates.first)
    await model.selectCandidate(chosen.id, prune: true)
    let editStarted = Date()
    if let id = model.removedIDs.first { await model.edit(.restore, ids: [id]) }
    else if let id = model.program?.strokes.first?.id { await model.edit(.remove, ids: [id]) }
    let warmEditSeconds = Date().timeIntervalSince(editStarted)
    await model.edit(.completeTarget)
    await model.presentRanking(scope: .candidate(chosen.id)); try await rankByOracle(model)
    await model.fit(); #expect(model.error == nil)
    let second = try #require(model.document?.fits.last), secondReport = try #require(model.fitReport)
    await model.activate(second.id)
    let deployment = try #require(model.activeCheckpoint?.id)
    let document = try #require(model.document)
    let encoder = DrawingPackageCodec.encoder()
    struct Receipt: Encodable {
      let purpose: String; let sourceSHA256: String; let seconds: Double
      let firstCheckpointID: String; let secondCheckpointID: String
      let firstReport: FlowArtistFitReport; let secondReport: FlowArtistFitReport
      let sourceCount: Int; let roundCount: Int; let drawingCount: Int; let rankingCount: Int
      let learnedMasks: [[Int]]; let portfolioRevision: Int; let warmEditSeconds: Double; let outputPNGs: [String]
    }
    let receipt = Receipt(purpose: "validationFixture: synthetic length-based judgments on real photo; no human artistic-quality claim",
      sourceSHA256: DrawingPackageCodec.sha256(try Data(contentsOf: sourceURL)), seconds: Date().timeIntervalSince(started),
      firstCheckpointID: active.id, secondCheckpointID: deployment, firstReport: firstReport, secondReport: secondReport,
      sourceCount: document.sources.count, roundCount: document.rounds.count, drawingCount: document.candidates.count,
      rankingCount: document.latestRankings.count, learnedMasks: learned.map(\.removedIndices), portfolioRevision: document.revision,
      warmEditSeconds: warmEditSeconds, outputPNGs: model.roundCandidates.indices.map { root.appendingPathComponent("learned-\($0 + 1).png").path })
    try encoder.encode(receipt).write(to: root.appendingPathComponent("complete-loop-receipt.json"), options: .atomic)
    for (index, candidate) in model.roundCandidates.enumerated() {
      if let preview = model.previews[candidate.id] { try preview.write(to: root.appendingPathComponent("learned-\(index + 1).png"), options: .atomic) }
    }
    await model.shutdown()
    let reopened = FlowDojoModel(directory: directory)
    await reopened.open(); #expect(reopened.error == nil)
    #expect(reopened.activeCheckpoint?.id == deployment)
    await reopened.activate(first.id); #expect(reopened.activeCheckpoint?.id == active.id)
    await reopened.activate(second.id); #expect(reopened.activeCheckpoint?.id == deployment)
    await reopened.shutdown()
  }

  private func curateRound(_ model: FlowDojoModel) async throws {
    let candidates = model.roundCandidates
    #expect(candidates.count >= 2)
    for candidate in candidates {
      await model.selectCandidate(candidate.id)
      let program = try #require(model.program)
      let lengths = program.strokes.map { stroke in
        zip(stroke.path.points, stroke.path.points.dropFirst()).reduce(0.0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
      }
      let median = lengths.sorted()[lengths.count / 2]
      let ids = Set(program.strokes.enumerated().filter { lengths[$0.offset] < median }.map { $0.element.id })
      let visible = ids.subtracting(model.removedIDs)
      let wronglyRemoved = model.removedIDs.subtracting(ids)
      if !visible.isEmpty { await model.edit(.remove, ids: visible) }
      if !wronglyRemoved.isEmpty { await model.edit(.restore, ids: wronglyRemoved) }
      await model.edit(.completeTarget)
      #expect(model.error == nil)
    }
    await model.presentRanking(scope: .round(try #require(model.round?.id)))
    try await rankByOracle(model)
  }

  private func rankByOracle(_ model: FlowDojoModel) async throws {
    let presentation = try #require(model.presentation)
    let candidates = Dictionary(uniqueKeysWithValues: (model.document?.candidates ?? []).map { ($0.id, $0) })
    let ordered = presentation.items.sorted { a, b in
      let ca = candidates[a.candidateID]!, cb = candidates[b.candidateID]!
      // Declared deterministic test preference, not an invented human judgment.
      let av = ca.recipe.values[3] - Double(a.removedIndices.count) / Double(max(1, ca.strokeCount))
      let bv = cb.recipe.values[3] - Double(b.removedIndices.count) / Double(max(1, cb.strokeCount))
      return av == bv ? a.id.uuidString < b.id.uuidString : av < bv
    }
    for (rank, item) in ordered.enumerated() { await model.rank(item: item.id, position: rank + 1) }
    #expect(model.error == nil)
  }
}
