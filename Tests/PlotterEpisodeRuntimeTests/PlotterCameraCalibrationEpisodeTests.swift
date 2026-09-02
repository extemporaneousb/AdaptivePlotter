import PlotterEpisodeRuntime
import Testing

@Suite("Camera-calibration episode runtime")
struct PlotterCameraCalibrationEpisodeTests {
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
