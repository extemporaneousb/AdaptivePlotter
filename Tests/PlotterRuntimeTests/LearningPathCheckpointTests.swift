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
