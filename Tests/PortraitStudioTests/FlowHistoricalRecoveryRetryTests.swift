import Foundation
import DrawingLibrary
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary
import Testing

@Suite("Exact archive recovery retry", .serialized)
struct FlowHistoricalRecoveryRetryTests {
  @Test("A recovery interrupted after fit reuses its pinned task and fit; changed supervision conflicts")
  func completedFitBeforeMarker() async throws {
    let root = DrawingExchangeFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try await DrawingExchangeFeedbackFixture.make(directory: root, candidateCount: 1)
    let candidate = fixture.candidates[0][0]
    try await fixture.store.chooseCandidate(candidate.id)
    _ = try await fixture.store.applyPrune(candidateID: candidate.id, action: .remove, indices: [0])
    _ = try await fixture.store.applyPrune(candidateID: candidate.id, action: .completeTarget)
    let history = await fixture.store.snapshot()
    let head = ExchangeDigest.hash(Data("explicit-synthetic-archive-head".utf8))
    let stableID = FlowHistoricalLearningRecovery.snapshotID(archiveID: history.id, head: head)
    #expect(stableID == FlowHistoricalLearningRecovery.snapshotID(archiveID: history.id, head: head))
    #expect(stableID != FlowHistoricalLearningRecovery.snapshotID(archiveID: history.id, head: .hash(Data("different-head".utf8))))
    let frozen = try await fixture.store.freezeTrainingSnapshot(id: stableID)
    let inputs = try await fixture.store.trainingInputs(snapshotID: stableID)
    let report = FlowArtistTraining.fit(examples: inputs.examples, rankings: inputs.rankings, seed: inputs.seed, configuration: inputs.configuration, frozenHoldoutGroupIDs: inputs.holdoutGroupIDs)
    let checkpoint = try #require(report.checkpoint)
    try checkpoint.validateArchive()
    let priorFit = try await fixture.store.installFit(checkpoint: report.checkpoint.map { try DrawingArtifactCoding.encoder().encode($0) }, report: DrawingArtifactCoding.encoder().encode(report), snapshotID: stableID)
    let blobs = root.appendingPathComponent("synthetic-recovery-inputs")
    try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: false)
    let program = try await fixture.store.candidateProgram(candidate.id)
    let raster = try await fixture.store.candidateRaster(candidate.id)
    let preview = try await fixture.store.candidatePreview(candidate.id)
    let programBytes = try DrawingArtifactCoding.encoder().encode(program), rasterBytes = try DrawingArtifactCoding.encoder().encode(raster)
    var artifacts: [[String: Any]] = []
    for (name, data) in [("program.json", programBytes), ("raster.json", rasterBytes), ("preview.png", preview)] {
      let file = blobs.appendingPathComponent(name); try data.write(to: file)
      artifacts.append(["path": file.path, "sha256": ExchangeDigest.hash(data).description])
    }
    let historicalCandidate = FlowHistoricalCandidate(id: candidate.id, program: .init(sha256: ExchangeDigest.hash(programBytes).description, byteCount: programBytes.count, mediaType: "application/json"), raster: candidate.raster, preview: candidate.preview)
    func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(value)) }
    let plan: [String: Any] = ["profile": "adaptiveplotter.personal-flow-recovery/1", "head": ["recordSHA256": head.description], "snapshot": try object(history), "artifacts": artifacts, "candidates": [try object(historicalCandidate)], "counts": ["sources": 1, "rounds": 1, "candidates": 1, "choices": 1, "pruneRevisions": 2, "rankings": 0, "fits": 0]]
    let planURL = root.appendingPathComponent("synthetic-recovery-plan.json")
    try JSONSerialization.data(withJSONObject: plan, options: [.sortedKeys]).write(to: planURL)
    let receipt = try await FlowHistoricalLearningRecovery.recover(planURL: planURL, library: fixture.library)
    #expect(!receipt.alreadyRecovered && receipt.trainingSnapshotID == frozen.id && receipt.fitID == priorFit.id)
    #expect(receipt.checkpointProduced)
    let repeated = try await FlowHistoricalLearningRecovery.recover(planURL: planURL, library: fixture.library)
    #expect(repeated.alreadyRecovered && repeated.trainingSnapshotID == stableID && repeated.fitID == priorFit.id)
    try await fixture.store.reloadCommittedState()
    let after = await fixture.store.snapshot()
    #expect(after.trainingSnapshots.count == 1 && after.fits.count == 1)
    let frozenBeforeMutation = try await fixture.store.trainingDocument(snapshotID: stableID)
    let fitBytesBeforeMutation = try await fixture.store.fitReportData(fitID: priorFit.id)
    try await fixture.library.commitRecords([], removing: [.init(kind: "adaptiveplotter.flow-historical-recovery/1", id: history.id)])
    try await fixture.library.updatePhotoMetadata(try #require(fixture.sources[0].photo), patch: .init(subjectID: .set("changed-frozen-scope")))
    do {
      _ = try await FlowHistoricalLearningRecovery.recover(planURL: planURL, library: fixture.library)
      Issue.record("Changed supervision reused the recovery task")
    } catch FlowPortfolioError.conflict(let reason) {
      #expect(reason.contains("different frozen supervision"))
    }
    try await fixture.store.reloadCommittedState()
    let refused = await fixture.store.snapshot()
    #expect(refused.trainingSnapshots.map(\.id) == [stableID])
    #expect(refused.fits.map(\.id) == [priorFit.id])
    #expect(try await fixture.store.trainingDocument(snapshotID: stableID) == frozenBeforeMutation)
    #expect(try await fixture.store.fitReportData(fitID: priorFit.id) == fitBytesBeforeMutation)
    await fixture.library.closeLibrary()
  }
}
