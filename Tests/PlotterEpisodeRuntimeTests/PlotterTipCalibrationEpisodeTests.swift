import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import Testing

@Suite("Tip-calibration episode runtime scaffold")
struct PlotterTipCalibrationEpisodeTests {
  @Test("one admitted calibration intent owns one operation identity")
  func serializesActiveIntent() async throws {
    let expected = try makeExpectedSelection()
    let port = TipPortFixture(
      responses: [.completed(.markBatch(.init(
        expectedSelection: expected,
        controllerEvidenceIDs: ["controller-1"],
        captureEvidenceIDs: ["capture-1"]
      )))],
      suspendsFirstRequest: true
    )
    let runtime = await PlotterTipCalibrationRuntime(effectPort: port)

    let first = Task { await runtime.submit(.beginFourMarkBatch) }
    await port.waitForCallCount(1)
    let active = await runtime.snapshot()
    let second = await runtime.submit(.beginFourMarkBatch)

    #expect(active.activeOperationID != nil)
    #expect(active.activeIntent == .beginFourMarkBatch)
    #expect(second == .refused("Pen-tip calibration already has an active operation."))
    #expect(await port.calls.count == 1)

    await port.releaseSuspendedRequest()
    #expect(await first.value == .completed)
    #expect((await runtime.snapshot()).activeOperationID == nil)
  }

  @Test("completed point selection is consumed without point mutation authority")
  func consumesCompletedSelection() async throws {
    let expected = try makeExpectedSelection()
    let retained = PlotterTipCalibrationRetainedDomainEvidence(
      acceptedObservations: [],
      modelSelection: nil,
      proposedRegistration: nil,
      retainedEvidenceIDs: ["observation-artifact-1", "fit-evidence-1"]
    )
    let port = TipPortFixture(responses: [
      .completed(.markBatch(.init(
        expectedSelection: expected,
        controllerEvidenceIDs: ["controller-1"],
        captureEvidenceIDs: ["capture-1"]
      ))),
      .completed(.proposal(retained)),
    ])
    let runtime = await PlotterTipCalibrationRuntime(effectPort: port)
    let batch = try completedBatch(from: expected)

    #expect(await runtime.submit(.beginFourMarkBatch) == .completed)
    #expect(await runtime.submit(.consumeCompletedPointSelection(batch)) == .completed)

    let snapshot = await runtime.snapshot()
    #expect(snapshot.completedSelection == batch)
    #expect(snapshot.retainedDomainEvidence == retained)
    #expect(snapshot.phase == .reviewingProposal)
    #expect(await port.calls.map(callKind) == [.mark, .fit])
  }

  @Test("selection admission rejects stale exact frames and non-four-point batches")
  func rejectsInvalidCompletedSelection() async throws {
    let expected = try makeExpectedSelection()
    let port = TipPortFixture(responses: [.completed(.markBatch(.init(
      expectedSelection: expected,
      controllerEvidenceIDs: [],
      captureEvidenceIDs: []
    )))])
    let runtime = await PlotterTipCalibrationRuntime(effectPort: port)
    #expect(await runtime.submit(.beginFourMarkBatch) == .completed)

    var stale = try completedBatch(from: expected)
    stale = .init(
      selectionID: stale.selectionID,
      exactFrame: try makeFrame(frameID: "different-frame"),
      presentationTransformRevision: stale.presentationTransformRevision,
      points: stale.points
    )
    let short = PlotterTipCalibrationCompletedPointSelection(
      selectionID: expected.selectionID,
      exactFrame: expected.exactFrame,
      presentationTransformRevision: expected.presentationTransformRevision,
      points: Array(try completedBatch(from: expected).points.dropLast())
    )

    #expect(await runtime.submit(.consumeCompletedPointSelection(stale)).isRefused)
    #expect(await runtime.submit(.consumeCompletedPointSelection(short)).isRefused)
    #expect(await port.calls.count == 1)
  }

  @Test("click-frame replacement requires zero retained points and preserves the prior request on failure")
  func replacesClickFrameOnlyFromEmptySelection() async throws {
    let initial = try makeExpectedSelection()
    let replacement = PlotterTipCalibrationExpectedPointSelection(
      selectionID: PlotterPointSelectionID(),
      exactFrame: try makeFrame(frameID: "frame-2", captureNanoseconds: 43),
      presentationTransformRevision: PlotterPresentationTransformRevision()
    )
    let port = TipPortFixture(responses: [
      .completed(.markBatch(.init(
        expectedSelection: initial,
        controllerEvidenceIDs: [],
        captureEvidenceIDs: []
      ))),
      .failed("replacement capture unavailable"),
      .completed(.clickFrameReplaced(replacement)),
    ])
    let runtime = await PlotterTipCalibrationRuntime(effectPort: port)

    #expect(await runtime.submit(.beginFourMarkBatch) == .completed)
    #expect(
      await runtime.submit(.captureNewClickFrame(retainedPointCount: 1))
        == .refused("Clear every retained click before capturing a new click frame.")
    )
    #expect(
      await runtime.submit(.captureNewClickFrame(retainedPointCount: 0))
        == .failed("replacement capture unavailable")
    )
    var snapshot = await runtime.snapshot()
    #expect(snapshot.expectedSelection == initial)
    #expect(snapshot.phase == .awaitingCompletedPointSelection(initial))

    #expect(
      await runtime.submit(.captureNewClickFrame(retainedPointCount: 0)) == .completed
    )
    snapshot = await runtime.snapshot()
    #expect(snapshot.expectedSelection == replacement)
    #expect(snapshot.phase == .awaitingCompletedPointSelection(replacement))
    #expect(await port.calls.map(callKind) == [.mark, .replace, .replace])
  }

  @Test("stop closes admission until settlement, ignores a late effect, then permits explicit recovery")
  func stopClosesAdmissionBeforeCancellation() async throws {
    let expected = try makeExpectedSelection()
    let port = TipPortFixture(
      responses: [.completed(.markBatch(.init(
        expectedSelection: expected,
        controllerEvidenceIDs: [],
        captureEvidenceIDs: []
      )))],
      suspendsFirstRequest: true
    )
    let runtime = await PlotterTipCalibrationRuntime(effectPort: port)
    let active = Task { await runtime.submit(.beginFourMarkBatch) }
    await port.waitForCallCount(1)

    let stopCompletion = CompletionProbe()
    let stop = Task {
      await runtime.stop()
      await stopCompletion.markCompleted()
    }
    while !(await runtime.snapshot()).admissionClosed { await Task.yield() }
    #expect(!(await stopCompletion.completed))
    #expect((await runtime.snapshot()).activeOperationID != nil)
    #expect(await runtime.submit(.beginFourMarkBatch) == .cancelled)
    await port.releaseSuspendedRequest()
    await stop.value
    #expect(await stopCompletion.completed)
    #expect(await active.value == .cancelled)

    let snapshot = await runtime.snapshot()
    #expect(!snapshot.admissionClosed)
    #expect(snapshot.phase == .idle)
    #expect(snapshot.expectedSelection == nil)
    #expect(await port.calls.count == 1)
  }

  @Test("cancel after a completed batch discards stale clicks and requires explicit retry")
  func cancelCompletedBatchBeforeRetry() async throws {
    let expected = try makeExpectedSelection()
    let completed: PlotterTipCalibrationEffectResult = .completed(.markBatch(.init(
      expectedSelection: expected, controllerEvidenceIDs: ["retained-motion"], captureEvidenceIDs: [])))
    let port = TipPortFixture(responses: [completed, completed])
    let runtime = await PlotterTipCalibrationRuntime(effectPort: port)
    #expect(await runtime.submit(.beginFourMarkBatch) == .completed)
    await runtime.cancelAttempt()
    let cancelled = await runtime.snapshot()
    #expect(cancelled.expectedSelection == nil)
    #expect(cancelled.completedSelection == nil)
    #expect(cancelled.retainedDomainEvidence == nil)
    #expect(cancelled.terminalHistory.count == 1)
    #expect(await port.calls.count == 1)
    #expect(await runtime.submit(.consumeCompletedPointSelection(try completedBatch(from: expected))).isRefused)
    await runtime.prepareForNewAttempt()
    #expect(await runtime.submit(.beginFourMarkBatch) == .completed)
    #expect(await port.calls.count == 2)
  }

  @Test("dependency invalidation during a batch suppresses late selection and respects terminal shutdown", arguments: [false, true])
  func activeDependencyInvalidationSuppressesLateEffects(shutdown: Bool) async throws {
    let expected = try makeExpectedSelection()
    let port = TipPortFixture(responses: [.completed(.markBatch(.init(
      expectedSelection: expected, controllerEvidenceIDs: [], captureEvidenceIDs: [])))],
      suspendsFirstRequest: true)
    let runtime = await PlotterTipCalibrationRuntime(effectPort: port)
    let active = Task { await runtime.submit(.beginFourMarkBatch) }
    await port.waitForCallCount(1)
    await runtime.resetForPaper(PaperInstanceRevision())
    #expect((await runtime.snapshot()).admissionClosed)
    #expect((await runtime.snapshot()).activeOperationID != nil)
    let terminal = Task { if shutdown { await runtime.shutdown() } }
    await port.releaseSuspendedRequest()
    await terminal.value
    #expect(await active.value == .cancelled)
    let settled = await runtime.snapshot()
    #expect(settled.activeOperationID == nil)
    #expect(settled.expectedSelection == nil)
    #expect(settled.acceptedRegistration == nil)
    #expect(settled.phase == .idle)
    #expect(settled.admissionClosed == shutdown)
  }

  @Test("overlapping cancellation and paper reset keep admission closed until every canceller settles")
  func overlappingCancellationKeepsAdmissionClosed() async throws {
    let expected = try makeExpectedSelection()
    let port = TipPortFixture(responses: [.completed(.markBatch(.init(
      expectedSelection: expected, controllerEvidenceIDs: [], captureEvidenceIDs: [])))],
      suspendsFirstRequest: true)
    let runtime = await PlotterTipCalibrationRuntime(effectPort: port)
    let active = Task { await runtime.submit(.beginFourMarkBatch) }
    await port.waitForCallCount(1)
    let probe = CancellationEntryProbe()
    let first = Task { @MainActor in
      probe.count += 1
      await runtime.cancelAttempt()
      let closed = runtime.snapshot().admissionClosed
      if closed { #expect(await runtime.submit(.beginFourMarkBatch) == .cancelled) }
      return closed
    }
    let second = Task { @MainActor in
      probe.count += 1
      await runtime.prepareForNewAttempt()
      let closed = runtime.snapshot().admissionClosed
      if closed { #expect(await runtime.submit(.beginFourMarkBatch) == .cancelled) }
      return closed
    }
    while await probe.count < 2 { await Task.yield() }
    // Both owner methods increment their settlement depth before suspending.
    await runtime.resetForPaper(PaperInstanceRevision())
    await port.releaseSuspendedRequest()
    let closedOnReturn = [await first.value, await second.value]
    #expect(closedOnReturn.filter { $0 }.count == 1)
    #expect(await active.value == .cancelled)
    #expect((await runtime.snapshot()).expectedSelection == nil)
    #expect(!(await runtime.snapshot()).admissionClosed)
    #expect(await port.calls.count == 1)
  }

  @Test("shutdown remains terminal through cancellation, retry preparation, reset, and paper replacement")
  func shutdownCannotBeReopened() async throws {
    let port = TipPortFixture(responses: [])
    let runtime = await PlotterTipCalibrationRuntime(effectPort: port)
    await runtime.shutdown()
    await runtime.stop()
    await runtime.cancelAttempt()
    await runtime.prepareForNewAttempt()
    await runtime.clearPaperTransients(PaperInstanceRevision())
    await runtime.resetForPaper(PaperInstanceRevision())
    #expect((await runtime.snapshot()).admissionClosed)
    #expect(await runtime.submit(.beginFourMarkBatch) == .cancelled)
    #expect(await port.calls.isEmpty)
  }

  @Test("same-sheet cancellation and reset retain possible ink; a new sheet permits explicit retry")
  func recoveryRetainsPossibleInkUntilPaperReplacement() async throws {
    let paper = PaperInstanceRevision()
    let location = BlacklistedToolContactLocation(
      calibrationPosition: .negativeX,
      machinePosition: try MachinePosition(x: 12, y: 34),
      markRadiusMM: 1.5, paperInstance: paper)
    let port = TipPortFixture(responses: [.failed("No marks requested")])
    let runtime = await PlotterTipCalibrationRuntime(effectPort: port)
    await runtime.replaceBlacklistedLocations([location])
    await runtime.cancelAttempt()
    await runtime.resetForPaper(paper)
    await runtime.prepareForNewAttempt()
    #expect((await runtime.snapshot()).blacklistedLocations == [location])
    #expect(await runtime.submit(.beginFourMarkBatch).isRefused)
    #expect(await port.calls.isEmpty)
    await runtime.clearPaperTransients(PaperInstanceRevision())
    #expect((await runtime.snapshot()).blacklistedLocations.isEmpty)
    #expect(await port.calls.isEmpty)
    await runtime.prepareForNewAttempt()
    #expect(await runtime.submit(.beginFourMarkBatch) == .failed("No marks requested"))
  }

  @Test("Stop retains late possible-ink evidence without accepting authority or replaying motion")
  func stopRetainsLatePossibleInk() async throws {
    let location = BlacklistedToolContactLocation(calibrationPosition: .negativeX,
      machinePosition: try MachinePosition(x: 12, y: 34), markRadiusMM: 2,
      paperInstance: PaperInstanceRevision())
    let port = TipPortFixture(responses: [.completed(.possibleInk(.init(
      location: location, reason: "Contact may have occurred", persistenceEvidenceID: "late-ink")))],
      suspendsFirstRequest: true)
    let runtime = await PlotterTipCalibrationRuntime(effectPort: port)
    let active = Task { await runtime.submit(.beginFourMarkBatch) }
    await port.waitForCallCount(1)
    let stopping = Task { await runtime.stop() }
    while !(await runtime.snapshot()).admissionClosed { await Task.yield() }
    await port.releaseSuspendedRequest()
    await stopping.value
    #expect(await active.value == .cancelled)
    #expect((await runtime.snapshot()).blacklistedLocations == [location])
    #expect((await runtime.snapshot()).expectedSelection == nil)
    #expect((await runtime.snapshot()).acceptedRegistration == nil)
    await runtime.prepareForNewAttempt()
    #expect(await runtime.submit(.beginFourMarkBatch).isRefused)
    #expect(await port.calls.count == 1)
  }

  @Test("possible ink persists a blacklist disposition and offers no redraw")
  func possibleInkDoesNotRetryOrRedraw() async throws {
    let location = BlacklistedToolContactLocation(
      calibrationPosition: .negativeX,
      machinePosition: try MachinePosition(x: 12, y: 34),
      markRadiusMM: 1.5,
      paperInstance: PaperInstanceRevision()
    )
    let port = TipPortFixture(responses: [.completed(.possibleInk(.init(
      location: location,
      reason: "Pen state could not be confirmed after the mark.",
      persistenceEvidenceID: "possible-ink-1"
    )))])
    let runtime = await PlotterTipCalibrationRuntime(effectPort: port)

    #expect(await runtime.submit(.beginFourMarkBatch) == .completed)
    #expect(await runtime.submit(.beginFourMarkBatch).isRefused)
    #expect(await runtime.submit(.retryCommit).isRefused)

    let snapshot = await runtime.snapshot()
    #expect(snapshot.blacklistedLocations == [location])
    #expect(snapshot.phase == .possibleInkBlacklisted(location, "Pen state could not be confirmed after the mark."))
    #expect(await port.calls.count == 1)
  }

  @Test("review, rejection, revalidation, and retry-commit require explicit operator admission")
  func operatorReviewActionsAreExplicit() async throws {
    let expected = try makeExpectedSelection()
    let retained = PlotterTipCalibrationRetainedDomainEvidence(
      acceptedObservations: [], modelSelection: nil, proposedRegistration: nil, retainedEvidenceIDs: ["fit-1"]
    )
    let port = TipPortFixture(responses: [
      .completed(.markBatch(.init(expectedSelection: expected, controllerEvidenceIDs: [], captureEvidenceIDs: []))),
      .completed(.proposal(retained)),
      .completed(.proposalRejected),
    ])
    let runtime = await PlotterTipCalibrationRuntime(effectPort: port)

    #expect(await runtime.submit(.beginFourMarkBatch) == .completed)
    #expect(await runtime.submit(.consumeCompletedPointSelection(try completedBatch(from: expected))) == .completed)
    #expect(await runtime.submit(.revalidateCheckpoint).isRefused)
    #expect(await runtime.submit(.acceptProposal).isRefused)
    #expect(await runtime.submit(.retryCommit).isRefused)
    #expect(await runtime.submit(.rejectProposal) == .completed)
    #expect(await port.calls.map(callKind) == [.mark, .fit, .reject])
    #expect((await runtime.snapshot()).phase == .rejected)
  }

  @Test("terminal history is bounded")
  func terminalHistoryIsBounded() async {
    let port = TipPortFixture(responses: [])
    let runtime = await PlotterTipCalibrationRuntime(effectPort: port)

    let terminalHistoryLimit = 16
    for _ in 0..<(terminalHistoryLimit + 3) {
      #expect(await runtime.submit(.rejectProposal).isRefused)
    }

    let history = (await runtime.snapshot()).terminalHistory
    #expect(history.count == terminalHistoryLimit)
    #expect(history.allSatisfy { $0.operationID == nil })
  }
}

private actor TipPortFixture: PlotterTipCalibrationEffectPort {
  private var responses: [PlotterTipCalibrationEffectResult]
  private let suspendsFirstRequest: Bool
  private var suspended = false
  private var suspendedResponse: PlotterTipCalibrationEffectResult?
  private var continuation: CheckedContinuation<PlotterTipCalibrationEffectResult, Never>?
  private(set) var calls: [PlotterTipCalibrationEffectRequest] = []

  init(responses: [PlotterTipCalibrationEffectResult], suspendsFirstRequest: Bool = false) {
    self.responses = responses
    self.suspendsFirstRequest = suspendsFirstRequest
  }

  func execute(_ request: PlotterTipCalibrationEffectRequest) async -> PlotterTipCalibrationEffectResult {
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
    continuation.resume(returning: suspendedResponse ?? .cancelled)
    suspendedResponse = nil
  }
}

private actor CompletionProbe {
  private(set) var completed = false

  func markCompleted() { completed = true }
}

private func callKind(_ request: PlotterTipCalibrationEffectRequest) -> TipCallKind {
  switch request {
  case .runFourMarkBatch: .mark
  case .captureNewClickFrame: .replace
  case .fitProposal: .fit
  case .revalidateCheckpoint: .revalidate
  case .commitProposal(_, let isRetry): isRetry ? .retryCommit : .commit
  case .rejectProposal: .reject
  }
}

private enum TipCallKind: Equatable {
  case mark, replace, fit, revalidate, commit, retryCommit, reject
}

private extension PlotterTipCalibrationSubmissionOutcome {
  var isRefused: Bool {
    if case .refused = self { return true }
    return false
  }
}

private func makeExpectedSelection() throws -> PlotterTipCalibrationExpectedPointSelection {
  .init(
    selectionID: PlotterPointSelectionID(),
    exactFrame: try makeFrame(frameID: "frame-1"),
    presentationTransformRevision: PlotterPresentationTransformRevision()
  )
}

private func makeFrame(
  frameID: String,
  captureNanoseconds: UInt64 = 42
) throws -> PlotterExactFrameReference {
  .init(
    frameID: frameID,
    frameSHA256: String(repeating: "a", count: 64),
    source: .simulated,
    cameraConfigurationID: CameraConfigurationID(),
    captureNanoseconds: captureNanoseconds,
    sequence: 7,
    width: 640,
    height: 480,
    rowBytes: 2_560,
    pixelFormat: .bgra8
  )
}

private func completedBatch(
  from expected: PlotterTipCalibrationExpectedPointSelection
) throws -> PlotterTipCalibrationCompletedPointSelection {
  .init(
    selectionID: expected.selectionID,
    exactFrame: expected.exactFrame,
    presentationTransformRevision: expected.presentationTransformRevision,
    points: [
      try Point2(x: 10, y: 10), try Point2(x: 20, y: 10),
      try Point2(x: 20, y: 20), try Point2(x: 10, y: 20),
    ]
  )
}

@MainActor
private final class CancellationEntryProbe {
  var count = 0
}
