import Foundation
import PlotterModel
import PlotterRuntime
import PlotterEpisodeRuntime
import Testing

@Suite("Camera-calibration episode runtime")
struct PlotterCameraCalibrationEpisodeTests {
  @Test("explicit camera replacement preserves fallback through failure, rejection, and cancellation")
  func replacementPreservesAcceptedFallback() async throws {
    let port = try SuccessfulCameraCalibrationPort()
    let runtime = await PlotterCameraCalibrationRuntime(effectPort: port)
    #expect(await runtime.submit(.buildFivePositionProposal) == .completed)
    #expect(await runtime.submit(.acceptProposal) == .completed)
    let original = try #require(await runtime.snapshot().acceptedRegistration)
    guard case .refused = await runtime.submit(.buildFivePositionProposal) else {
      Issue.record("Accepted calibration requires explicit replacement preparation"); return
    }
    let callsBefore = await port.callCount
    await runtime.prepareForNewAttempt()
    #expect(await port.callCount == callsBefore)
    #expect(await runtime.snapshot().acceptedRegistration == original)
    #expect(await runtime.submit(.buildFivePositionProposal) == .completed)
    #expect(await runtime.submit(.rejectProposal) == .completed)
    #expect(await runtime.snapshot().acceptedRegistration == original)
    #expect(await runtime.submit(.buildFivePositionProposal) == .completed)
    await runtime.cancelAttempt()
    #expect(await runtime.snapshot().proposedRegistration == nil)
    #expect(await runtime.snapshot().anchorFrame == nil)
    #expect(await runtime.snapshot().acceptedRegistration == original)
    guard case .refused = await runtime.submit(.acceptProposal) else {
      Issue.record("Cancelled proposal must not remain acceptable"); return
    }
    await port.setCaptureFailure(true)
    await runtime.prepareForNewAttempt()
    #expect(await runtime.submit(.buildFivePositionProposal) == .failed("Capture unavailable"))
    #expect(await runtime.snapshot().acceptedRegistration == original)
    await port.setCaptureFailure(false)
    #expect(await runtime.submit(.buildFivePositionProposal) == .completed)
    let replacement = try #require(await runtime.snapshot().proposedRegistration)
    #expect(replacement != original)
    #expect(await runtime.submit(.acceptProposal) == .completed)
    #expect(await runtime.snapshot().acceptedRegistration == replacement)
  }

  @Test("overlapping camera cancellation and shutdown join the exact effect and retain fallback")
  func replacementCancellationAndShutdown() async throws {
    let port = try SuccessfulCameraCalibrationPort()
    let runtime = await PlotterCameraCalibrationRuntime(effectPort: port)
    #expect(await runtime.submit(.buildFivePositionProposal) == .completed)
    #expect(await runtime.submit(.acceptProposal) == .completed)
    let original = try #require(await runtime.snapshot().acceptedRegistration)
    await runtime.prepareForNewAttempt()
    await port.suspendNextCapture()
    let build = Task { await runtime.submit(.buildFivePositionProposal) }
    while !(await port.captureIsSuspended) { await Task.yield() }
    let cancel = Task { await runtime.cancelAttempt() }
    while !(await runtime.snapshot().admissionClosed) { await Task.yield() }
    let shutdown = Task { await runtime.shutdown() }
    #expect(await runtime.submit(.captureReference) == .cancelled)
    await port.releaseCapture()
    await cancel.value
    await shutdown.value
    #expect(await build.value == .cancelled)
    #expect(await runtime.snapshot().acceptedRegistration == original)
    #expect(await runtime.snapshot().proposedRegistration == nil)
    #expect(await runtime.snapshot().activeOperationID == nil)
    await runtime.prepareForNewAttempt()
    await runtime.stop()
    await runtime.clearForReset()
    #expect(await runtime.snapshot().admissionClosed)
    #expect(await runtime.submit(.buildFivePositionProposal) == .cancelled)
  }

  @Test("synchronous camera invalidation suppresses a late in-flight reference")
  func resetSuppressesLateReference() async throws {
    let port = try SuccessfulCameraCalibrationPort()
    let runtime = await PlotterCameraCalibrationRuntime(effectPort: port)
    await port.suspendNextCapture()
    let build = Task { await runtime.submit(.buildFivePositionProposal) }
    while !(await port.captureIsSuspended) { await Task.yield() }
    await runtime.clearForReset()
    #expect(await runtime.snapshot().admissionClosed)
    await port.releaseCapture()
    #expect(await build.value == .cancelled)
    #expect(await runtime.snapshot().anchorFrame == nil)
    #expect(await runtime.snapshot().proposedRegistration == nil)
    #expect(!(await runtime.snapshot().admissionClosed))
  }

  @Test("a failed lower camera effect is terminally failed, never completed")
  func failureIsNotCompletion() async {
    let port = CameraCalibrationPortFixture()
    let runtime = await PlotterCameraCalibrationRuntime(effectPort: port)

    let outcome = await runtime.submit(.buildFivePositionProposal)
    let snapshot = await runtime.snapshot()

    #expect(outcome == .failed("Vision did not return five exact cap samples."))
    #expect(snapshot.failure?.detail == "Vision did not return five exact cap samples.")
    #expect(snapshot.terminalHistory.last?.outcome == outcome)
    #expect(await port.calls == [.capture])
  }

  @Test("retry after cap acquisition failure captures a new reference instead of reusing the old pose")
  func retryRefreshesReference() async throws {
    let port = try RetryCameraCalibrationPortFixture()
    let runtime = await PlotterCameraCalibrationRuntime(effectPort: port)
    #expect(await runtime.submit(.buildFivePositionProposal) == .failed("No pen cap detected."))
    #expect(await runtime.snapshot().referencePosition == (try MachinePosition(x: 0, y: 0)))
    #expect(await runtime.submit(.buildFivePositionProposal) == .failed("No pen cap detected."))
    #expect(await port.referenceCaptures == 2)
    #expect(await runtime.snapshot().referencePosition == (try MachinePosition(x: 24, y: 0)))
    #expect(await port.plannedReferences == [try MachinePosition(x: 0, y: 0), try MachinePosition(x: 24, y: 0)])
  }

  @Test("shutdown closes admission without invoking a lower effect")
  func shutdownClosesAdmission() async {
    let port = CameraCalibrationPortFixture()
    let runtime = await PlotterCameraCalibrationRuntime(effectPort: port)

    await runtime.shutdown()
    let outcome = await runtime.submit(.captureReference)
    let snapshot = await runtime.snapshot()

    #expect(outcome == .cancelled)
    #expect(snapshot.admissionClosed)
    #expect(await port.calls.isEmpty)
  }

  @Test("every admitted camera action becomes busy before the lower effect returns")
  func admittedActionPublishesBusyState() async {
    let port = CameraCalibrationPortFixture(blocking: true)
    let runtime = await PlotterCameraCalibrationRuntime(effectPort: port)
    let submission = Task { await runtime.submit(.captureReference) }

    while !(await port.started) { await Task.yield() }
    let active = await runtime.snapshot()
    #expect(active.revision > 0)
    #expect(active.phase == .preparing)
    #expect(active.activeIntent == .captureReference)

    let duplicate = await runtime.submit(.captureReference)
    guard case .refused = duplicate else {
      Issue.record("expected the still-visible predecessor action to be refused")
      await runtime.shutdown()
      _ = await submission.value
      return
    }
    #expect(await port.calls == [.capture])

    await runtime.shutdown()
    #expect(await submission.value == .cancelled)
  }

  @Test("shutdown cancels and settles an active build effect before clearing ownership")
  func shutdownSettlesActiveBuildEffect() async {
    let port = CameraCalibrationPortFixture(blocking: true)
    let runtime = await PlotterCameraCalibrationRuntime(effectPort: port)
    let submission = Task { await runtime.submit(.buildFivePositionProposal) }

    while !(await port.started) { await Task.yield() }
    await runtime.shutdown()

    #expect(await port.finished)
    #expect(await submission.value == .cancelled)
    let snapshot = await runtime.snapshot()
    #expect(snapshot.admissionClosed)
    #expect(snapshot.activeOperationID == nil)
    #expect(snapshot.activeIntent == nil)
    #expect(snapshot.phase == nil)
    #expect(await port.calls.count == 1)
  }
}

private actor CameraCalibrationPortFixture: PlotterCameraCalibrationEffectPort {
  enum Call: Equatable, Sendable { case capture, build, accept, reject }
  let blocking: Bool
  private(set) var calls: [Call] = []
  private(set) var started = false
  private(set) var finished = false

  init(blocking: Bool = false) { self.blocking = blocking }

  func execute(_ request: PlotterCameraCalibrationEffectRequest) async
    -> PlotterCameraCalibrationEffectResult
  {
    started = true
    switch request {
    case .returnToAcceptedCenter: return .completed(.returnedToAcceptedCenter)
    case .captureReference: calls.append(.capture)
    case .buildFivePositionProposal: calls.append(.build)
    case .acceptProposal: calls.append(.accept)
    case .rejectProposal: calls.append(.reject)
    case .fivePositionPlan, .captureSample, .moveAndCapture, .returnToReference:
      calls.append(.build)
    }
    if blocking { try? await Task.sleep(nanoseconds: 60_000_000_000) }
    finished = true
    return .failed(.init(
      code: .requiredStateMissing,
      detail: "Vision did not return five exact cap samples.",
      recovery: .resolveNamedFailure
    ))
  }
}

private actor RetryCameraCalibrationPortFixture: PlotterCameraCalibrationEffectPort {
  let frame: DisplayedFrame
  let cap: ToolCapAnchorEstimate
  private(set) var referenceCaptures = 0
  private(set) var plannedReferences: [MachinePosition] = []

  init() throws {
    let configuration = CameraConfigurationID()
    let frameID = FrameID(rawValue: "retry-reference")
    frame = DisplayedFrame(source: .simulated, frame: try StampedFrame(
      id: frameID, sequence: 1, captureNanoseconds: 10, cameraConfigurationID: configuration,
      width: 4, height: 4, rowBytes: 4, pixelFormat: .gray8,
      bytes: OwnedFrameBytes(Array(repeating: 0, count: 16))))
    cap = try ToolCapAnchorEstimate(
      componentCentroid: Point2(x: 2, y: 2),
      componentBounds: AxisAlignedBounds(minX: 1, minY: 1, maxX: 3, maxY: 3),
      confidence: 0.9, estimatorRevision: "retry-test", source: .simulated,
      frameID: frameID, cameraConfigurationID: configuration)
  }

  func execute(_ request: PlotterCameraCalibrationEffectRequest) async -> PlotterCameraCalibrationEffectResult {
    switch request {
    case .captureReference:
      let x = Double(referenceCaptures * 24)
      referenceCaptures += 1
      return .completed(.reference(frame: frame, position: try! MachinePosition(x: x, y: 0), capAnchor: cap))
    case .fivePositionPlan(_, let reference):
      plannedReferences.append(reference)
      return .failed(.init(code: .requiredStateMissing, detail: "No pen cap detected.", recovery: .resolveNamedFailure))
    default:
      Issue.record("Unexpected effect after failed acquisition")
      return .cancelled
    }
  }
}

private actor SuccessfulCameraCalibrationPort: PlotterCameraCalibrationEffectPort {
  let frame: DisplayedFrame
  let cap: ToolCapAnchorEstimate
  let plan: PlotterCameraCalibrationFivePositionPlan
  private var captureFailure = false
  private var shouldSuspendCapture = false
  private var captureContinuation: CheckedContinuation<Void, Never>?
  private(set) var captureIsSuspended = false
  private(set) var callCount = 0

  init() throws {
    // Independent immutable fixture values use the same exact source format.
    let config = CameraConfigurationID()
    let frameID = FrameID(rawValue: "replacement-reference")
    frame = DisplayedFrame(source: .simulated, frame: try StampedFrame(
      id: frameID, sequence: 1, captureNanoseconds: 10, cameraConfigurationID: config,
      width: 4, height: 4, rowBytes: 4, pixelFormat: .gray8,
      bytes: OwnedFrameBytes(Array(repeating: 0, count: 16))))
    cap = try ToolCapAnchorEstimate(componentCentroid: Point2(x: 2, y: 2),
      componentBounds: AxisAlignedBounds(minX: 1, minY: 1, maxX: 3, maxY: 3),
      confidence: 0.9, estimatorRevision: "replacement-test", source: .simulated,
      frameID: frameID, cameraConfigurationID: config)
    let positions = try [(0.0, 0.0), (-1, 0), (0, 1), (1, 0), (0, -1)].map {
      try MachinePosition(x: $0.0, y: $0.1)
    }
    let optical = try CameraOpticalConfigurationIdentity(source: .simulated,
      sensorFormat: "replacement-test", width: 4, height: 4, pixelFormat: .gray8,
      orientation: .up, mirrored: false, digitalZoomFactor: 1, lensIdentity: "test",
      focusConfiguration: "fixed", mountRevision: UUID(), reframingRevision: UUID())
    plan = PlotterCameraCalibrationFivePositionPlan(samplePositions: positions,
      motionDeltas: try zip(positions, Array(positions.dropFirst()) + [positions[0]]).map {
        try Vector2(dx: $0.1.point.x - $0.0.point.x, dy: $0.1.point.y - $0.0.point.y)
      }, applicabilityRectangle: try AxisAlignedBounds(minX: -2, minY: -2, maxX: 2, maxY: 2),
      opticalConfiguration: optical, machineGeometry: MachineGeometryIdentity(),
      controllerSessionID: UUID(), coordinateRevision: 1)
  }

  func setCaptureFailure(_ value: Bool) { captureFailure = value }
  func suspendNextCapture() { shouldSuspendCapture = true }
  func releaseCapture() { captureContinuation?.resume(); captureContinuation = nil; captureIsSuspended = false }

  func execute(_ request: PlotterCameraCalibrationEffectRequest) async -> PlotterCameraCalibrationEffectResult {
    callCount += 1
    switch request {
    case .captureReference:
      if shouldSuspendCapture {
        shouldSuspendCapture = false
        captureIsSuspended = true
        await withCheckedContinuation { captureContinuation = $0 }
      }
      if captureFailure {
        return .failed(.init(code: .requiredStateMissing, detail: "Capture unavailable", recovery: .resolveNamedFailure))
      }
      return .completed(.reference(frame: frame, position: plan.samplePositions[0], capAnchor: cap))
    case .fivePositionPlan: return .completed(.fivePositionPlan(plan))
    case .captureSample(_, let index, let expected), .moveAndCapture(_, let index, let expected, _):
      return .completed(.sample(MachineCameraCorrespondenceProvenance(
        machinePoint: expected.point, capAnchorPoint: try! Point2(x: expected.point.x + 2, y: expected.point.y + 2),
        source: .simulated, controllerSessionID: plan.controllerSessionID, coordinateRevision: plan.coordinateRevision,
        frameID: FrameID(rawValue: "sample-\(callCount)-\(index)"), frameSHA256: "sha-\(index)",
        captureNanoseconds: UInt64(100 + callCount), cameraConfigurationID: frame.frame.cameraConfigurationID,
        attemptID: ExerciseAttemptID(), capAnchorEstimatorRevision: "replacement-test",
        algorithmRevision: "replacement-test", capAnchorConfidence: 0.9, artifactRevisionID: LearningArtifactRevisionID())))
    case .returnToReference: return .completed(.returnedToReference)
    case .returnToAcceptedCenter: return .completed(.returnedToAcceptedCenter)
    case .acceptProposal(_, let registration): return .completed(.accepted(registration))
    case .rejectProposal: return .completed(.rejected)
    case .buildFivePositionProposal: return .cancelled
    }
  }
}
