import Foundation
import PlotterRuntime
import Testing

@Suite("Canonical durable data locations")
struct AdaptivePlotterStoragePathsTests {
  @Test("a blocked canonical root refuses Learning writes without temporary diversion")
  func unavailableRoot() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let paths = AdaptivePlotterStoragePaths(applicationSupportDirectory: directory)
    try Data("blocked".utf8).write(to: paths.rootDirectory)
    let identity = LearningPathSemanticIdentity(machineGeometry: .init(), toolAssembly: .init(),
      penContactProfile: .init(), paperInstance: .init(), paperContactPlane: .init(),
      cameraMountRevision: UUID(), cameraReframingRevision: UUID())
    let store = AcceptedLearningPathCheckpointStore(fileURL: paths.acceptedLearningCheckpoint,
      historyDirectoryURL: paths.acceptedLearningHistoryDirectory)
    #expect(throws: (any Error).self) {
      try store.save(try AcceptedLearningPathCheckpoint(semanticIdentity: identity))
    }
    #expect(try Data(contentsOf: paths.rootDirectory) == Data("blocked".utf8))
    #expect(store.fileURL == directory.appendingPathComponent("AdaptivePlotter/AcceptedArtifacts/accepted-learning-path-v1.json"))
    #expect(paths.drawingEvidenceArchive == directory.appendingPathComponent("AdaptivePlotter/DrawingEvidence/drawing-run-evidence-v1.json"))
    #expect(paths.episodeRecordingDirectory(UUID()).deletingLastPathComponent() == paths.episodeRecordingsDirectory)
    #expect(paths.episodeArtifactDirectory(UUID()).deletingLastPathComponent() == paths.episodeArtifactsDirectory)
  }
}

