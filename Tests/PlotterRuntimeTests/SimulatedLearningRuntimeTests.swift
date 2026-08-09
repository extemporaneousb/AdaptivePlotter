import Testing

@testable import PlotterRuntime

@Suite("Simulated Learning Runtime")
struct SimulatedLearningRuntimeTests {
  @Test("connect and Enable Motion are separate simulator admissions")
  func connectAndEnableMotion() async throws {
    let runtime = SimulatedLearningRuntime()

    var snapshot = await runtime.snapshot()
    #expect(snapshot.session == .disconnected)
    #expect(snapshot.motionAuthorization == .disabled)
    #expect(snapshot.penPose == .up)
    #expect(snapshot.mpos == .zero)
    #expect(
      snapshot.evidenceNotice.label
        == "SIMULATED — NOT PHYSICAL EVIDENCE"
    )

    let refusedEnable = await runtime.enableMotion()
    #expect(refusal(refusedEnable) == .sessionDisconnected)
    #expect(refusedEnable.evidenceNotice == .notPhysicalEvidence)
    snapshot = try accepted(await runtime.connect())
    #expect(snapshot.session == .connected)
    #expect(snapshot.motionAuthorization == .disabled)

    snapshot = try accepted(await runtime.enableMotion())
    #expect(snapshot.motionAuthorization == .enabled)
    #expect(
      snapshot.evidenceNotice == .notPhysicalEvidence
    )

    snapshot = try accepted(await runtime.disableMotion())
    #expect(snapshot.motionAuthorization == .disabled)
    snapshot = try accepted(await runtime.disconnect())
    #expect(snapshot.session == .disconnected)
    #expect(snapshot.motionAuthorization == .disabled)
  }

  @Test("manual Stop settles and wakes the original logical owner")
  func manualStopWaitsForOriginalOwner() async throws {
    let runtime = try await enabledRuntime()
    let operation = try accepted(
      await runtime.beginManualJog(
        delta: SimulatedLearningMotionVector(dxMM: 5, dyMM: 0)
      )
    )

    let waiter = Task {
      await runtime.waitForOutcome(of: operation.id)
    }
    let stopOutcome = try accepted(await runtime.stop(operation.id))
    let waitedOutcome = try accepted(await waiter.value)

    #expect(stopOutcome == waitedOutcome)
    #expect(stopOutcome.operation.id == operation.id)
    #expect(stopOutcome.disposition == .stopped)
    #expect(stopOutcome.finalMPos == .zero)
    #expect(stopOutcome.evidenceNotice == .notPhysicalEvidence)
    #expect(await runtime.snapshot().currentOperation == nil)
  }

  @Test("Boundary Stop and Cancel are distinct first-winning dispositions")
  func boundaryStopVersusCancel() async throws {
    let runtime = try await enabledRuntime()
    let stopped = try accepted(
      await runtime.beginBoundary(direction: .positiveX, finiteSegmentLengthMM: 10)
    )
    let stoppedOutcome = try accepted(await runtime.stop(stopped.id))
    #expect(stoppedOutcome.disposition == .stopped)
    #expect(
      refusal(await runtime.cancel(stopped.id))
        == .operationAlreadySettled(stopped.id, .stopped)
    )

    let cancelled = try accepted(
      await runtime.beginBoundary(direction: .negativeY, finiteSegmentLengthMM: 4)
    )
    #expect(cancelled.id != stopped.id)
    let cancelledOutcome = try accepted(await runtime.cancel(cancelled.id))
    #expect(cancelledOutcome.disposition == .cancelled)
    #expect(
      refusal(await runtime.stop(cancelled.id))
        == .operationAlreadySettled(cancelled.id, .cancelled)
    )
  }

  @Test("repeated and stale Stop cannot settle the active operation")
  func repeatedAndStaleStop() async throws {
    let runtime = try await enabledRuntime()
    let operation = try accepted(
      await runtime.beginManualJog(
        delta: SimulatedLearningMotionVector(dxMM: 0, dyMM: 2)
      )
    )
    let staleID = SimulatedLearningOperationID(sequence: operation.id.sequence + 100)

    #expect(
      refusal(await runtime.stop(staleID))
        == .staleOperation(requested: staleID, active: operation.id)
    )
    #expect(await runtime.snapshot().currentOperation?.id == operation.id)

    _ = try accepted(await runtime.stop(operation.id))
    #expect(
      refusal(await runtime.stop(operation.id))
        == .operationAlreadySettled(operation.id, .stopped)
    )
  }

  @Test("one current operation rejects a second owner")
  func oneCurrentOperation() async throws {
    let runtime = try await enabledRuntime()
    let manual = try accepted(
      await runtime.beginManualJog(
        delta: SimulatedLearningMotionVector(dxMM: 1, dyMM: 0)
      )
    )

    #expect(
      refusal(
        await runtime.beginBoundary(
          direction: .positiveY,
          finiteSegmentLengthMM: 2
        )
      ) == .operationAlreadyActive(manual.id)
    )
    _ = try accepted(await runtime.cancel(manual.id))
  }

  @Test("drawing naturally completes only with simulated pen down")
  func drawingCompletion() async throws {
    let runtime = try await enabledRuntime()
    let delta = try SimulatedLearningMotionVector(dxMM: 3, dyMM: -2)

    #expect(
      refusal(await runtime.beginDrawing(delta: delta)) == .penMustBeDown
    )
    _ = try accepted(await runtime.setPenPose(.down))
    let drawing = try accepted(await runtime.beginDrawing(delta: delta))
    let outcome = try accepted(await runtime.completeNaturally(drawing.id))

    #expect(outcome.operation.kind == .drawing(delta))
    #expect(outcome.disposition == .naturallyCompleted)
    #expect(outcome.finalMPos == (try SimulatedLearningMPos(xMM: 3, yMM: -2)))
    #expect(outcome.evidenceNotice.label == SimulatedLearningEvidenceNotice.evidenceLabel)
  }

  @Test("natural Boundary segment completion continues the same owner without success")
  func boundaryNeverNaturallySucceeds() async throws {
    let runtime = try await enabledRuntime()
    let boundary = try accepted(
      await runtime.beginBoundary(direction: .positiveX, finiteSegmentLengthMM: 10)
    )

    let first = try accepted(
      await runtime.recordBoundarySegmentCompletion(for: boundary.id)
    )
    let second = try accepted(
      await runtime.recordBoundarySegmentCompletion(for: boundary.id)
    )
    #expect(first.operationID == boundary.id)
    #expect(first.completedSegmentCount == 1)
    #expect(second.operationID == boundary.id)
    #expect(second.completedSegmentCount == 2)
    #expect(second.mpos == (try SimulatedLearningMPos(xMM: 20, yMM: 0)))

    #expect(
      refusal(await runtime.completeNaturally(boundary.id))
        == .boundaryRequiresStopOrCancel
    )
    #expect(await runtime.snapshot().currentOperation?.id == boundary.id)

    let waiter = Task {
      await runtime.waitForOutcome(of: boundary.id)
    }
    let stopOutcome = try accepted(await runtime.stop(boundary.id))
    #expect(stopOutcome.disposition == .stopped)
    #expect(stopOutcome.completedBoundarySegmentCount == 2)
    #expect(try accepted(await waiter.value) == stopOutcome)
  }
}

private func enabledRuntime() async throws -> SimulatedLearningRuntime {
  let runtime = SimulatedLearningRuntime()
  _ = try accepted(await runtime.connect())
  _ = try accepted(await runtime.enableMotion())
  return runtime
}

private func accepted<Value: Sendable>(
  _ response: SimulatedLearningResponse<Value>
) throws -> Value {
  try response.result.get()
}

private func refusal<Value: Sendable>(
  _ response: SimulatedLearningResponse<Value>
) -> SimulatedLearningRefusal? {
  guard case .failure(let refusal) = response.result else { return nil }
  return refusal
}
