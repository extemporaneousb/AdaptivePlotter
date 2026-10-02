import Foundation
import PlotterModel
import Testing

@testable import PlotterRuntime

@Suite("Durable Learning Path checkpoint")
struct LearningPathCheckpointTests {
  @Test("replacement and clear preserve exact envelopes without automatic history restoration")
  func versionHistory() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AcceptedLearningPathCheckpointStore(fileURL: directory.appendingPathComponent("accepted.json"))
    let first = try AcceptedLearningPathCheckpoint(semanticIdentity: semanticIdentity(),
      penCapAppearance: penCapAppearance())
    try store.save(first)
    let before = try Data(contentsOf: store.fileURL)
    let second = try AcceptedLearningPathCheckpoint(semanticIdentity: first.semanticIdentity)
    try store.save(second)
    let after = try Data(contentsOf: store.fileURL)
    let history = try FileManager.default.contentsOfDirectory(at: store.historyDirectoryURL,
      includingPropertiesForKeys: nil)
    #expect(history.count == 1)
    #expect(try Data(contentsOf: history[0]) == before)
    guard case .loaded(let previous) = AcceptedLearningPathCheckpointStore(fileURL: history[0]).load() else {
      Issue.record("The retained predecessor must pass the production loader"); return
    }
    #expect(previous == first)
    try store.clear()
    try store.clear()
    guard case .absent = store.load() else {
      Issue.record("History must not become current Learning automatically"); return
    }
    let retained = try FileManager.default.contentsOfDirectory(at: store.historyDirectoryURL,
      includingPropertiesForKeys: nil).map { try Data(contentsOf: $0) }
    #expect(retained.count == 2)
    #expect(retained.contains(before))
    #expect(retained.contains(after))
  }

  @Test("history write failure refuses replacement and reset before changing canonical bytes")
  func historyFailureIsAtomic() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AcceptedLearningPathCheckpointStore(fileURL: directory.appendingPathComponent("accepted.json"))
    try store.save(try AcceptedLearningPathCheckpoint(semanticIdentity: semanticIdentity()))
    let original = try Data(contentsOf: store.fileURL)
    try Data("blocked".utf8).write(to: store.historyDirectoryURL)
    #expect(throws: (any Error).self) {
      try store.save(try AcceptedLearningPathCheckpoint(semanticIdentity: semanticIdentity()))
    }
    #expect(try Data(contentsOf: store.fileURL) == original)
    #expect(throws: (any Error).self) { try store.clear() }
    #expect(try Data(contentsOf: store.fileURL) == original)
  }

  @Test("atomic aggregate round-trips semantic identity without operational state")
  func roundTrip() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("accepted-learning-path.json")
    let store = AcceptedLearningPathCheckpointStore(fileURL: url)
    let identity = semanticIdentity()
    let optical = try opticalIdentity(for: identity)
    let reference = try AcceptedLearningReferenceFrame(
      opticalConfiguration: optical,
      frame: frame(sequence: 1)
    )
    let checkpoint = try AcceptedLearningPathCheckpoint(
      semanticIdentity: identity,
      penCapAppearance: penCapAppearance(),
      referenceFrame: reference
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
    #expect(loaded.penCapAppearance == checkpoint.penCapAppearance)
    #expect(loaded.referenceFrame == reference)
  }

  @Test("legacy payloads decode absent package additions as unavailable")
  func legacyPayloadDecode() throws {
    let checkpoint = try AcceptedLearningPathCheckpoint(
      semanticIdentity: semanticIdentity()
    )
    var object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(checkpoint)) as? [String: Any]
    )
    object.removeValue(forKey: "penCapAppearance")
    object.removeValue(forKey: "referenceFrame")

    let restored = try JSONDecoder().decode(
      AcceptedLearningPathCheckpoint.self,
      from: JSONSerialization.data(withJSONObject: object)
    )

    #expect(restored.penCapAppearance == nil)
    #expect(restored.referenceFrame == nil)
    try restored.validate()
  }

  @Test("saved graph reconstruction preserves exact accepted revision identity")
  func restoredLearningGraph() throws {
    let attemptID = ExerciseAttemptID()
    let revision = LearningArtifactRevision(
      kind: .penInteraction,
      attemptID: attemptID,
      disposition: .succeeded,
      state: .current
    )
    let evidence = PenInteractionAttemptEvidence(
      actuationProfile: .initialDefaults,
      confirmedUpPositions: [],
      confirmedUpSpindleValues: [],
      confirmedUpControllerOutcomes: [],
      confirmedUpTimestamps: [],
      confirmedDownPositions: [],
      confirmedDownSpindleValues: [],
      confirmedDownControllerOutcomes: [],
      confirmedDownTimestamps: []
    )
    let checkpoint = try AcceptedLearningPathCheckpoint(
      semanticIdentity: semanticIdentity(),
      penInteraction: AcceptedPenInteractionCheckpoint(
        revision: revision,
        acceptedSequence: 1,
        evidence: evidence
      )
    )

    let graph = try checkpoint.restoredLearningGraph()

    #expect(graph.currentRevision(for: .penInteraction)?.id == revision.id)
    #expect(graph.currentRevision(for: .penInteraction)?.attemptID == attemptID)
  }

  @Test("reference comparison reports advisory shift and MAD without a gate")
  func advisoryReferenceComparison() throws {
    let identity = semanticIdentity()
    let optical = try opticalIdentity(for: identity)
    let reference = try AcceptedLearningReferenceFrame(
      opticalConfiguration: optical,
      frame: frame(sequence: 1)
    )
    let current = DisplayedFrame(
      source: .live(CameraDeviceID(rawValue: "checkpoint-test-camera")),
      frame: frame(sequence: 2)
    )

    guard
      case .compared(let report) = reference.compare(
        with: current,
        opticalConfiguration: optical
      )
    else {
      Issue.record("compatible reference pixels should produce an advisory report")
      return
    }
    #expect(report.shiftX == 0)
    #expect(report.shiftY == 0)
    #expect(report.backgroundMeanAbsoluteDifference == 0)
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
    let history = try FileManager.default.contentsOfDirectory(at: store.historyDirectoryURL,
      includingPropertiesForKeys: nil)
    #expect(history.count == 1)
    #expect(try Data(contentsOf: history[0]) == bytes)
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

  private func opticalIdentity(
    for identity: LearningPathSemanticIdentity
  ) throws -> CameraOpticalConfigurationIdentity {
    try CameraOpticalConfigurationIdentity(
      source: .live(CameraDeviceID(rawValue: "checkpoint-test-camera")),
      sensorFormat: "checkpoint-test",
      width: 4,
      height: 3,
      pixelFormat: .bgra8,
      orientation: .up,
      mirrored: false,
      digitalZoomFactor: 1,
      lensIdentity: "simulated-lens",
      focusConfiguration: "fixed",
      mountRevision: identity.cameraMountRevision,
      reframingRevision: identity.cameraReframingRevision
    )
  }

  private func frame(sequence: UInt64) -> StampedFrame {
    try! StampedFrame(
      sequence: sequence,
      captureNanoseconds: sequence,
      cameraConfigurationID: CameraConfigurationID(),
      width: 4,
      height: 3,
      rowBytes: 16,
      pixelFormat: .bgra8,
      bytes: OwnedFrameBytes(Array(repeating: 127, count: 48))
    )
  }

  private func penCapAppearance() -> AcceptedPenCapAppearance {
    try! AcceptedPenCapAppearance(
      color: .green,
      frameID: FrameID(rawValue: "pen-cap-appearance"),
      frameSHA256: String(repeating: "a", count: 64),
      source: .live(CameraDeviceID(rawValue: "checkpoint-test-camera")),
      cameraConfigurationID: CameraConfigurationID(),
      width: 4,
      height: 3,
      pixelFormat: .bgra8,
      clickPoint: Point2(x: 1, y: 1),
      usableSampleCount: 9,
      totalSampleCount: 9,
      algorithmRevision: AcceptedPenCapAppearance.algorithmRevision
    )
  }
}
