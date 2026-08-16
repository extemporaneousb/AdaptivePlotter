import Foundation
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

private enum NoticeInspectionDisposition {
  case available
  case unavailable
  case failure
}

private enum NoticeCameraError: Error {
  case inspectionFailure
  case captureFailure
}

private func noticeCameraActions(
  _ fixture: CameraFixture,
  inspection: NoticeInspectionDisposition,
  captureFails: Bool = false
) -> OperatorWorkspace.CameraActions {
  .init(
    discover: { fixture.discoverResponse() },
    select: { _ in fixture.selectResponse() },
    start: { fixture.startResponse() },
    stop: { fixture.stopResponse() },
    restart: { fixture.snapshot },
    snapshot: { fixture.snapshot },
    frames: { AsyncStream { $0.finish() } },
    inspectWorkflowScene: { boundary, features, region in
      switch inspection {
      case .available:
        return try fixture.inspection(
          after: boundary,
          features: features,
          analysisRegion: region
        )
      case .unavailable:
        return nil
      case .failure:
        throw NoticeCameraError.inspectionFailure
      }
    },
    captureFrame: { boundary in
      if captureFails { throw NoticeCameraError.captureFailure }
      return try fixture.inspection(after: boundary).displayedFrame
    },
    setSceneAnalysisRegion: { fixture.setSceneAnalysisRegion($0) },
    setPenCapColor: { fixture.setPenCapColor($0) },
    setAutomaticInspection: { fixture.setAutomaticInspection($0, features: $1) },
    analysisUpdates: { AsyncStream { $0.finish() } },
    observeIsolatedInk: { _ in fatalError("unused") }
  )
}

@MainActor
@Suite("Current operator notice routing")
struct OperatorNoticeRoutingTests {
  @Test("LIVE discovery failure reaches the sole notice")
  func liveDiscoveryFailureIsCurrent() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(
      machine: machine,
      cameraActionsOverride: noticeCameraActions(
        camera,
        inspection: .unavailable,
        captureFails: true
      ),
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()

    await workspace.beginPenInteraction()

    let failure = try #require(workspace.discoveryError)
    #expect(workspace.currentOperatorNoticeMessage == failure)
    await workspace.shutdown()
  }

  @Test("successful exact-frame fallback clears optional Vision failure")
  func exactFrameFallbackClearsVisionNotice() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(
      machine: machine,
      cameraActionsOverride: noticeCameraActions(camera, inspection: .failure),
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()

    await workspace.beginPenInteraction()

    #expect(workspace.actionSurfacePresentation.pointSelectionRequest != nil)
    #expect(workspace.visionError == nil)
    #expect(workspace.discoveryError == nil)
    #expect(workspace.currentOperatorNoticeMessage == nil)
    await workspace.shutdown()
  }

  @Test("historical Pen refusal remains Diagnostics history, not a current notice")
  func historicalPenRefusalIsNotCurrent() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    await machine.enqueuePenOutcome(.refused(.controllerRejected("historical refusal")))
    _ = await machine.requestPen(.raise)
    let workspace = workspace(machine: machine, log: log)

    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()

    #expect(workspace.machineError == nil)
    #expect(workspace.lastPenOutcomeText.contains("historical refusal"))
    #expect(workspace.currentOperatorNoticeMessage == nil)
    await workspace.shutdown()
  }

  @Test("successful simulator refresh clears the prior capture notice")
  func simulatorRefreshClearsRecoveredFailure() async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    await workspace.switchFrameMode(.simulated)
    let firstCapture = try #require(
      workspace.actionSurfacePresentation.displayedFrame?.frame.captureNanoseconds
    )
    await harness.runtime.injectFault(.refuseNextSceneFrame)

    await workspace.refreshVideoSources()
    #expect(workspace.cameraError != nil)
    #expect(workspace.currentOperatorNoticeMessage == workspace.cameraError)

    await workspace.refreshVideoSources()
    #expect(workspace.cameraError == nil)
    #expect(workspace.currentOperatorNoticeMessage == nil)
    #expect(
      workspace.actionSurfacePresentation.displayedFrame?.frame.captureNanoseconds
        ?? 0 > firstCapture
    )
    await workspace.shutdown()
  }
}
