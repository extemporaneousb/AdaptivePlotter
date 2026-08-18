import Foundation
import PlotterModel
import Testing

@testable import PlotterRuntime

@Suite("Durable Learning Path checkpoint")
struct LearningPathCheckpointTests {
  @Test("atomic aggregate round-trips semantic identity without operational state")
  func roundTrip() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("accepted-learning-path.json")
    let store = AcceptedLearningPathCheckpointStore(fileURL: url)
    let checkpoint = try AcceptedLearningPathCheckpoint(
      semanticIdentity: semanticIdentity()
    )

    try store.save(checkpoint)
    guard case .loaded(let loaded) = store.load() else {
      Issue.record("Expected the aggregate checkpoint to load.")
      return
    }
    #expect(loaded == checkpoint)
    let encoded = String(decoding: try Data(contentsOf: url), as: UTF8.self)
    #expect(!encoded.contains("motionGuard"))
    #expect(!encoded.contains("activeStop"))
    #expect(!encoded.contains("currentPenState"))
  }

  @Test("integrity failure is rejected and explicit clear is idempotent")
  func integrityAndClear() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("accepted-learning-path.json")
    let store = AcceptedLearningPathCheckpointStore(fileURL: url)
    try store.save(try AcceptedLearningPathCheckpoint(semanticIdentity: semanticIdentity()))
    var bytes = try Data(contentsOf: url)
    bytes[bytes.count / 2] ^= 0x01
    try bytes.write(to: url)
    guard case .rejected = store.load() else {
      Issue.record("Expected tampered aggregate authority to be rejected.")
      return
    }
    try store.clear()
    try store.clear()
    guard case .absent = store.load() else {
      Issue.record("Expected explicit clear to remove aggregate authority.")
      return
    }
  }

  private func semanticIdentity() -> LearningPathSemanticIdentity {
    LearningPathSemanticIdentity(
      machineGeometry: MachineGeometryIdentity(),
      toolAssembly: ToolAssemblyRevision(),
      penContactProfile: PenContactProfileRevision(),
      paperInstance: PaperInstanceRevision(),
      paperContactPlane: PaperContactPlaneRevision(),
      cameraMountRevision: UUID(),
      cameraReframingRevision: UUID()
    )
  }
}
