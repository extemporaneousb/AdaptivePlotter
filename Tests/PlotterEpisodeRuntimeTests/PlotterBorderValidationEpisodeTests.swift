@testable import PlotterEpisodeRuntime
import Testing

@Suite("Border-validation episode runtime")
struct PlotterBorderValidationEpisodeTests {
  @Test("one admitted validation step owns one operation identity")
  func serializesActiveStep() async {
    let port = BorderValidationPortFixture(
      responses: [.completed(.comparisonAccepted(.predictionObserved, histories: [:]))],
      suspendsFirstRequest: true
    )
    let runtime = await PlotterBorderValidationRuntime(
      sourceIsSimulated: true,
      effectPort: port
    )
    await installComparisonReview(on: runtime)

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
      .completed(.comparisonAccepted(.predictionObserved, histories: [:]))
    ])
    let runtime = await PlotterBorderValidationRuntime(
      sourceIsSimulated: true,
      effectPort: port
    )
    await installComparisonReview(on: runtime)

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
      .completed(.comparisonRejected("operator rejected observed border", histories: [:]))
    ])
    let runtime = await PlotterBorderValidationRuntime(
      sourceIsSimulated: true,
      effectPort: port
    )
    await installComparisonReview(on: runtime)

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

  @Test("shutdown joins suspended acceptance and rejects its late completion")
  func shutdownRejectsLateAcceptance() async {
    let port = BorderValidationPortFixture(
      responses: [.completed(.comparisonAccepted(.predictionObserved, histories: [:]))],
      suspendsFirstRequest: true
    )
    let runtime = await PlotterBorderValidationRuntime(
      sourceIsSimulated: false,
      effectPort: port
    )
    await installComparisonReview(on: runtime)
    let accepted = Task { await runtime.submitAcceptComparison(.predictionObserved) }
    await port.waitForCallCount(1)
    let close = Task { await runtime.closeAdmissionAndCancel() }
    while !(await runtime.snapshot()).admissionClosed {
      await Task.yield()
    }
    await port.releaseSuspendedRequest()
    await close.value

    #expect(!(await accepted.value))
    let snapshot = await runtime.snapshot()
    #expect(snapshot.admissionClosed)
    #expect(snapshot.assessment == nil)
    #expect(snapshot.activeOperationID == nil)
    #expect(snapshot.phase == .cancelled("Admission closed by shutdown/cancel."))
  }

  @Test("shutdown joins suspended rejection and rejects its late completion")
  func shutdownRejectsLateRejection() async {
    let port = BorderValidationPortFixture(
      responses: [.completed(.comparisonRejected("late rejection", histories: [:]))],
      suspendsFirstRequest: true
    )
    let runtime = await PlotterBorderValidationRuntime(
      sourceIsSimulated: true,
      effectPort: port
    )
    await installComparisonReview(on: runtime)
    let rejected = Task { await runtime.submitReject("operator rejection") }
    await port.waitForCallCount(1)
    let close = Task { await runtime.closeAdmissionAndCancel() }
    while !(await runtime.snapshot()).admissionClosed {
      await Task.yield()
    }
    await port.releaseSuspendedRequest()
    await close.value

    #expect(!(await rejected.value))
    let snapshot = await runtime.snapshot()
    #expect(snapshot.admissionClosed)
    #expect(snapshot.comparisonAttemptHistories.isEmpty)
    #expect(snapshot.phase == .cancelled("Admission closed by shutdown/cancel."))
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

  @Test("typed state intents own review refusal, rewind, and source-indexed reset")
  func typedStateIntentsOwnLocalMutation() async {
    let runtime = await PlotterBorderValidationRuntime(
      sourceIsSimulated: true,
      effectPort: BorderValidationPortFixture(responses: [])
    )
    let initialGroup = await runtime.snapshot().group

    let unavailableReview = await runtime.apply(.setComparisonReviewPinned(true))
    #expect(unavailableReview.disposition == .refused(
      reason: "No completed Border comparison is available for review.",
      remedy: "Complete and accept the current Border comparison first."
    ))

    _ = await runtime.apply(.restoreAcceptedAssessment(.predictionObserved))
    let rewound = await runtime.apply(.rewind(.captureLocalPreFrameBaseline))
    #expect(rewound.disposition == .applied)
    #expect(rewound.snapshot.assessment == nil)
    #expect(rewound.snapshot.step == .captureLocalPreFrameBaseline)

    await runtime.advanceAfterSuccess(.captureLocalPreFrameBaseline)
    await runtime.advanceAfterSuccess(.moveToDrawingBorderStart)
    await runtime.advanceAfterSuccess(.drawDrawingBorder)
    await runtime.advanceAfterSuccess(.revealAndObserveNewInk)
    let comparisonRewind = await runtime.apply(
      .rewind(.compareIntendedAndObservedGeometry)
    )
    guard case .reviewingComparison = comparisonRewind.snapshot.phase else {
      Issue.record("Comparison rewind must restore explicit operator review admission.")
      return
    }

    let reset = await runtime.apply(.reset)
    #expect(reset.disposition == .applied)
    #expect(reset.snapshot.step == .chooseDrawingBorderPlan)
    #expect(reset.snapshot.group != initialGroup)
    #expect(reset.snapshot.group.rawValue.hasPrefix("simulated-"))
  }
}

@MainActor
private func installComparisonReview(
  on runtime: PlotterBorderValidationRuntime
) {
  runtime.advanceAfterSuccess(.chooseDrawingBorderPlan)
  runtime.advanceAfterSuccess(.captureLocalPreFrameBaseline)
  runtime.advanceAfterSuccess(.moveToDrawingBorderStart)
  runtime.advanceAfterSuccess(.drawDrawingBorder)
  runtime.advanceAfterSuccess(.revealAndObserveNewInk)
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
