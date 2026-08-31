import PlotterEpisodeRuntime
import Testing

@Suite("Border-validation episode runtime")
struct PlotterBorderValidationEpisodeTests {
  @Test("one admitted validation step owns one operation identity")
  func serializesActiveStep() async {
    let port = BorderValidationPortFixture(
      responses: [.completed(.comparisonAccepted(.predictionObserved))],
      suspendsFirstRequest: true
    )
    let runtime = await PlotterBorderValidationRuntime(
      sourceIsSimulated: true,
      effectPort: port
    )
    await installComparisonReview(on: runtime, sourceIsSimulated: true)

    let first = Task {
      await runtime.submitAcceptComparison(.predictionObserved)
    }
    await port.waitForCallCount(1)
    let active = await runtime.snapshot()
    let second = await runtime.submitAcceptComparison(.predictionObserved)

    #expect(active.activeOperationID != nil)
    #expect(active.activeStep == .compareIntendedAndObservedGeometry)
    #expect(await port.calls.count == 1)
    #expect(!second)

    await port.releaseSuspendedRequest()
    #expect(await first.value)
    #expect((await runtime.snapshot()).activeOperationID == nil)
  }

  @Test("possible ink is terminal and not a redraw token")
  func possibleInkHasNoAutomaticRetry() async {
    let port = BorderValidationPortFixture(responses: [
      .completed(.possibleInk("controller stopped with possible ink", outcome: nil))
    ])
    let runtime = await PlotterBorderValidationRuntime(
      sourceIsSimulated: false,
      effectPort: port
    )

    #expect(await runtime.submitStep(.drawDrawingBorder))
    let snapshot = await runtime.snapshot()
    #expect(snapshot.phase == .possibleInk("controller stopped with possible ink"))
    #expect(snapshot.executionState == .possibleInk)
    #expect(snapshot.step == .revealAndObserveNewInk)
    #expect(snapshot.terminalHistory.count == 1)
    #expect(await port.calls.count == 1)
  }

  @Test("operator acceptance is explicit and terminal")
  func explicitAccept() async {
    let port = BorderValidationPortFixture(responses: [
      .completed(.comparisonAccepted(.predictionObserved))
    ])
    let runtime = await PlotterBorderValidationRuntime(
      sourceIsSimulated: true,
      effectPort: port
    )
    await installComparisonReview(on: runtime, sourceIsSimulated: true)

    #expect(await runtime.submitAcceptComparison(.predictionObserved))
    let snapshot = await runtime.snapshot()
    #expect(snapshot.assessment == .predictionObserved)
    #expect(snapshot.comparisonReviewIsPinned)
    #expect(snapshot.phase == .accepted)
    #expect(snapshot.terminalHistory.last?.phase == .accepted)
    #expect(await port.calls.map(callKind) == [.accept])
  }

  @Test("operator rejection is explicit, terminal, and sends no redraw step")
  func explicitRejectHasNoRedraw() async {
    let port = BorderValidationPortFixture(responses: [
      .completed(.comparisonRejected("operator rejected observed border"))
    ])
    let runtime = await PlotterBorderValidationRuntime(
      sourceIsSimulated: true,
      effectPort: port
    )
    await installComparisonReview(on: runtime, sourceIsSimulated: true)

    #expect(await runtime.submitReject("operator rejected observed border"))
    let snapshot = await runtime.snapshot()
    #expect(snapshot.assessment == nil)
    #expect(snapshot.phase == .rejected("operator rejected observed border"))
    #expect(snapshot.terminalHistory.last?.phase
      == .rejected("operator rejected observed border"))
    #expect(await port.calls.map(callKind) == [.reject])
  }

  @Test("shutdown closes admission without starting later work")
  func shutdownClosesAdmission() async {
    let port = BorderValidationPortFixture(responses: [])
    let runtime = await PlotterBorderValidationRuntime(
      sourceIsSimulated: false,
      effectPort: port
    )

    await runtime.closeAdmissionAndCancel()
    #expect(!(await runtime.submitStep(.chooseDrawingBorderPlan)))
    #expect((await runtime.snapshot()).admissionClosed)
    #expect(await port.calls.isEmpty)
  }

  @Test("terminal history is bounded")
  func terminalHistoryIsBounded() async {
    let limit = 16
    let runtime = await PlotterBorderValidationRuntime(
      sourceIsSimulated: false,
      effectPort: BorderValidationPortFixture(
        responses: Array(
          repeating: .failed("lower effect failed"),
          count: limit + 3
        )
      )
    )

    for _ in 0..<(limit + 3) {
      #expect(!(await runtime.submitStep(.captureLocalPreFrameBaseline)))
    }

    #expect((await runtime.snapshot()).terminalHistory.count == limit)
  }
}

@MainActor
private func installComparisonReview(
  on runtime: PlotterBorderValidationRuntime,
  sourceIsSimulated: Bool
) {
  runtime.replaceSnapshot(PlotterBorderValidationSnapshot(
    sourceIsSimulated: sourceIsSimulated,
    phase: .reviewingComparison(PlotterBorderValidationOperationID()),
    step: .compareIntendedAndObservedGeometry
  ))
}

private actor BorderValidationPortFixture: PlotterBorderValidationEffectPort {
  private var responses: [PlotterBorderValidationEffectResult]
  private let suspendsFirstRequest: Bool
  private var suspended = false
  private var suspendedResponse: PlotterBorderValidationEffectResult?
  private var continuation: CheckedContinuation<PlotterBorderValidationEffectResult, Never>?
  private(set) var calls: [PlotterBorderValidationEffectRequest] = []

  init(
    responses: [PlotterBorderValidationEffectResult],
    suspendsFirstRequest: Bool = false
  ) {
    self.responses = responses
    self.suspendsFirstRequest = suspendsFirstRequest
  }

  func execute(_ request: PlotterBorderValidationEffectRequest) async
    -> PlotterBorderValidationEffectResult
  {
    calls.append(request)
    let response = responses.isEmpty ? .failed("Unexpected lower effect.") : responses.removeFirst()
    if suspendsFirstRequest && !suspended {
      suspended = true
      suspendedResponse = response
      return await withCheckedContinuation { continuation = $0 }
    }
    return response
  }

  func waitForCallCount(_ count: Int) async {
    while calls.count < count { await Task.yield() }
  }

  func releaseSuspendedRequest() {
    guard let continuation else { return }
    self.continuation = nil
    continuation.resume(returning: suspendedResponse ?? .cancelled("cancelled"))
    suspendedResponse = nil
  }
}

private enum BorderValidationCallKind: Equatable {
  case step(BorderValidationStep)
  case accept
  case reject
}

private func callKind(_ request: PlotterBorderValidationEffectRequest)
  -> BorderValidationCallKind
{
  switch request {
  case .runStep(_, let step): .step(step)
  case .acceptComparison: .accept
  case .rejectComparison: .reject
  }
}
