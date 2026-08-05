import Foundation
import PlotterModel
import PlotterRuntime
import PlotterTestSupport
import Testing

@Suite("Deterministic model-mismatch simulator")
struct SimulatedModelOverlayTests {
  @Test("simulator emits deterministic pixels and every typed overlay layer")
  func deterministicOverlayOutput() throws {
    let simulator = PaperSceneSimulator(width: 240, height: 140)
    let cameraConfigurationID = CameraConfigurationID(
      UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
    )
    let scene = try modelMismatchScene()
    let fieldToCamera = try AffineTransform2<FieldSpace, CameraPixelSpace>(
      m11: 1, m12: 0, m21: 0, m22: 1, tx: 0, ty: 0
    )

    let first = try simulator.renderModelMismatch(
      scene: scene,
      fieldToCamera: fieldToCamera,
      sequence: 42,
      captureNanoseconds: 4_200,
      cameraConfigurationID: cameraConfigurationID
    )
    let second = try simulator.renderModelMismatch(
      scene: scene,
      fieldToCamera: fieldToCamera,
      sequence: 42,
      captureNanoseconds: 4_200,
      cameraConfigurationID: cameraConfigurationID
    )

    #expect(first == second)
    #expect(first.displayedFrame.source == .simulated)
    #expect(first.displayedFrame.frame.id.rawValue == "simulated-\(cameraConfigurationID)-42")
    #expect(first.layers.map(\.kind) == SimulatedOverlayLayerKind.allCases)
    #expect(first.penState == .down)
    #expect(!first.isPhysicalEvidence)
    #expect(SimulatedOverlaySceneContent.evidenceLabel == "SIMULATED — NOT PHYSICAL EVIDENCE")
    #expect(first.overlays.count == 8)
    #expect(first.overlays.allSatisfy { $0.matches(first.displayedFrame) })
    #expect(
      Set(first.overlays.map(\.provenance.operation))
        == Set(["logical", "predicted", "simulated-observed", "residual", "cap", "frame-side"])
    )
    #expect(
      first.overlays.allSatisfy {
        $0.provenance.algorithmRevision
          == "deterministic-model-mismatch-v1:overlay-test"
      }
    )

    let predicted = try #require(
      first.overlays.first(where: { $0.provenance.operation == "predicted" })
    )
    let observed = try #require(
      first.overlays.first(where: { $0.provenance.operation == "simulated-observed" })
    )
    #expect(predicted.geometry != observed.geometry)
  }
}

private func modelMismatchScene() throws -> SimulatedModelMismatchScene {
  let domain = try AxisAlignedBounds<MachineSpace>(
    minX: 0,
    minY: 0,
    maxX: 220,
    maxY: 120
  )
  let accepted = try AcceptedDrawingModelSnapshot(
    version: DrawingModelVersion(rawValue: 1),
    transform: DrawingTransform(
      machineToField: AffineTransform2(
        m11: 1, m12: 0, m21: 0, m22: 1, tx: 0, ty: 0
      ),
      machineDomain: domain
    ),
    provenance: DrawingModelSnapshotProvenance(origin: .prior(name: "overlay-test-prior"))
  )
  let simulatedGroundTruth = try DrawingTransform(
    machineToField: AffineTransform2(
      m11: 1.02, m12: 0.01, m21: -0.01, m22: 0.98, tx: 2, ty: 3
    ),
    machineDomain: domain
  )
  return try SimulatedModelMismatchScene(
    scenarioID: "overlay-test",
    logicalFieldPath: Polyline(points: [
      Point2(x: 20, y: 20),
      Point2(x: 100, y: 55),
      Point2(x: 180, y: 85),
    ]),
    commandedMachinePath: Polyline(points: [
      Point2(x: 20, y: 20),
      Point2(x: 100, y: 55),
      Point2(x: 180, y: 85),
    ]),
    acceptedModel: accepted,
    simulatedGroundTruthTransform: simulatedGroundTruth,
    capFieldPoint: Point2(x: 120, y: 30),
    frameFieldBounds: AxisAlignedBounds(minX: 5, minY: 5, maxX: 215, maxY: 115),
    penState: .down
  )
}
