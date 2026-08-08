import Foundation
import PlotterModel
import PlotterRuntime
import Testing

@Suite("Armature Guidance")
struct ArmatureGuidanceTests {
  @Test("clear partial and blocked labels record estimate agreement")
  func visibilityLabelsAndAgreement() throws {
    let camera = CameraConfigurationID()
    let context = guidanceContext(camera: camera)
    var state = ArmatureGuidanceState(context: context)
    let frame = try guidanceFrame(camera: camera)
    let clear = try state.record(
      frame: frame,
      controllerPosition: MachinePosition(x: 0, y: 0),
      armatureBounds: try AxisAlignedBounds(minX: 0, minY: 0, maxX: 4, maxY: 4),
      humanLabel: .clear,
      outcome: .continueInDirection(.positiveXOneMillimeter)
    )
    let partial = try state.record(
      frame: try guidanceFrame(sequence: 2, camera: camera),
      controllerPosition: MachinePosition(x: 1, y: 0),
      armatureBounds: try AxisAlignedBounds(minX: 8, minY: 8, maxX: 13, maxY: 13),
      humanLabel: .partial,
      outcome: .reverse
    )
    let blocked = try state.record(
      frame: try guidanceFrame(sequence: 3, camera: camera),
      controllerPosition: MachinePosition(x: 2, y: 0),
      armatureBounds: try AxisAlignedBounds(minX: 9, minY: 9, maxX: 20, maxY: 20),
      humanLabel: .blocked,
      outcome: .stopped
    )

    #expect(clear.overlapEstimate.visibility == .clear)
    #expect(partial.overlapEstimate.visibility == .partial)
    #expect(blocked.overlapEstimate.visibility == .blocked)
    let allEstimatesAgree = state.observations.allSatisfy { $0.estimateAgreedWithHuman }
    #expect(allEstimatesAgree)
    #expect(state.visibilityFit?.distinctPoseCount == 3)
  }

  @Test("visibility fit waits for multiple nonduplicate machine poses")
  func fitNeedsDistinctPoses() throws {
    let camera = CameraConfigurationID()
    var state = ArmatureGuidanceState(context: guidanceContext(camera: camera))
    let position = try MachinePosition(x: 1, y: 2)
    _ = try state.record(
      frame: guidanceFrame(camera: camera), controllerPosition: position,
      armatureBounds: nil, humanLabel: .blocked, outcome: .stopped)
    _ = try state.record(
      frame: guidanceFrame(sequence: 2, camera: camera), controllerPosition: position,
      armatureBounds: nil, humanLabel: .partial, outcome: .stopped)
    #expect(state.visibilityFit == nil)
    _ = try state.record(
      frame: guidanceFrame(sequence: 3, camera: camera),
      controllerPosition: MachinePosition(x: 2, y: 2),
      armatureBounds: nil, humanLabel: .clear, outcome: .acceptedPose)
    #expect(state.visibilityFit?.distinctPoseCount == 2)
  }

  @Test("accepted human-clear pose yields one finite pen-up return request")
  func acceptedPoseReturn() throws {
    let camera = CameraConfigurationID()
    let context = guidanceContext(camera: camera)
    var state = ArmatureGuidanceState(context: context)
    let observation = try state.record(
      frame: guidanceFrame(camera: camera),
      controllerPosition: MachinePosition(x: 4, y: -2),
      armatureBounds: try AxisAlignedBounds(minX: 0, minY: 0, maxX: 2, maxY: 2),
      humanLabel: .clear,
      outcome: .acceptedPose
    )
    try state.acceptClearPose(observationID: observation.id, returnFeedMMPerMinute: 80)
    let request = try state.penUpReturnRequest(
      from: MachinePosition(x: 1, y: 1),
      currentContext: context
    )
    #expect(request.delta == (try Vector2<MachineSpace>(dx: 3, dy: -3)))
    #expect(request.feedMMPerMinute == 80)
  }

  @Test("nearby proposals are finite, enumerated, and deterministic")
  func deterministicProposals() throws {
    let camera = CameraConfigurationID()
    var state = ArmatureGuidanceState(context: guidanceContext(camera: camera))
    _ = try state.record(
      frame: guidanceFrame(camera: camera),
      controllerPosition: MachinePosition(x: 0, y: 0),
      armatureBounds: nil,
      humanLabel: .blocked,
      outcome: .continueInDirection(.positiveYOneMillimeter)
    )
    let proposals = try state.proposedActions(
      from: MachinePosition(x: 0, y: 0), feedMMPerMinute: 50)
    #expect(proposals.map(\.action).first == .positiveYOneMillimeter)
    #expect(Set(proposals.map(\.action)) == Set(ArmatureGuidanceAction.allCases))
    #expect(proposals.allSatisfy { $0.request.delta.magnitude == 1 })
  }

  @Test("context changes invalidate automated return but never manual motion")
  func returnInvalidation() throws {
    let camera = CameraConfigurationID()
    let context = guidanceContext(camera: camera)
    var state = ArmatureGuidanceState(context: context)
    let observation = try state.record(
      frame: guidanceFrame(camera: camera),
      controllerPosition: MachinePosition(x: 1, y: 1),
      armatureBounds: nil,
      humanLabel: .clear,
      outcome: .acceptedPose
    )
    try state.acceptClearPose(observationID: observation.id, returnFeedMMPerMinute: 60)
    let changed = ArmatureGuidanceContext(
      controllerSessionID: context.controllerSessionID,
      coordinateRevision: context.coordinateRevision + 1,
      cameraConfigurationID: camera,
      observationRegion: context.observationRegion,
      toolPaperRevision: context.toolPaperRevision
    )
    state.updateContext(changed)
    #expect(state.automatedReturnInvalidation == .controllerCoordinateReset)
    #expect(state.acceptedClearPose == nil)
    #expect(state.manualMotionPermitted)
    #expect(throws: ArmatureGuidanceError.automatedReturnInvalidated(.controllerCoordinateReset)) {
      _ = try state.penUpReturnRequest(
        from: MachinePosition(x: 0, y: 0), currentContext: changed)
    }
  }

  @Test("every required scene identity change has a typed return invalidation")
  func allReturnInvalidations() {
    let camera = CameraConfigurationID()
    let original = guidanceContext(camera: camera)
    let cases: [(ArmatureGuidanceContext, ArmatureGuidanceInvalidationReason)] = [
      (
        ArmatureGuidanceContext(
          controllerSessionID: UUID(), coordinateRevision: original.coordinateRevision,
          cameraConfigurationID: camera, observationRegion: original.observationRegion,
          toolPaperRevision: original.toolPaperRevision),
        .controllerReconnect
      ),
      (
        ArmatureGuidanceContext(
          controllerSessionID: original.controllerSessionID,
          coordinateRevision: original.coordinateRevision + 1,
          cameraConfigurationID: camera, observationRegion: original.observationRegion,
          toolPaperRevision: original.toolPaperRevision),
        .controllerCoordinateReset
      ),
      (
        ArmatureGuidanceContext(
          controllerSessionID: original.controllerSessionID,
          coordinateRevision: original.coordinateRevision,
          cameraConfigurationID: CameraConfigurationID(),
          observationRegion: original.observationRegion,
          toolPaperRevision: original.toolPaperRevision),
        .cameraConfigurationChanged
      ),
      (
        ArmatureGuidanceContext(
          controllerSessionID: original.controllerSessionID,
          coordinateRevision: original.coordinateRevision,
          cameraConfigurationID: camera,
          observationRegion: PixelRect(x: 11, y: 10, width: 10, height: 10),
          toolPaperRevision: original.toolPaperRevision),
        .observationRegionChanged
      ),
      (
        ArmatureGuidanceContext(
          controllerSessionID: original.controllerSessionID,
          coordinateRevision: original.coordinateRevision,
          cameraConfigurationID: camera, observationRegion: original.observationRegion,
          toolPaperRevision: UUID()),
        .toolOrPaperChanged
      ),
    ]
    for (updated, expected) in cases {
      var state = ArmatureGuidanceState(context: original)
      state.updateContext(updated)
      #expect(state.automatedReturnInvalidation == expected)
      #expect(state.manualMotionPermitted)
    }
  }
}

private func guidanceContext(camera: CameraConfigurationID) -> ArmatureGuidanceContext {
  ArmatureGuidanceContext(
    controllerSessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    coordinateRevision: 1,
    cameraConfigurationID: camera,
    observationRegion: PixelRect(x: 10, y: 10, width: 10, height: 10),
    toolPaperRevision: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  )
}

private func guidanceFrame(
  sequence: UInt64 = 1,
  camera: CameraConfigurationID
) throws -> StampedFrame {
  try StampedFrame(
    sequence: sequence,
    captureNanoseconds: sequence,
    cameraConfigurationID: camera,
    width: 30,
    height: 30,
    rowBytes: 30,
    pixelFormat: .gray8,
    bytes: OwnedFrameBytes([UInt8](repeating: 255, count: 900))
  )
}
