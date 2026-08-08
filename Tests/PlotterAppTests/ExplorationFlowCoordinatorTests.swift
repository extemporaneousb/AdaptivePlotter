import Foundation
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Exploration app-level flow")
struct ExplorationFlowCoordinatorTests {
  @Test("full deterministic episode keeps session warm and cannot reach machine actions")
  @MainActor
  func fullSimulatorEpisodeIsMachineIsolated() async throws {
    let machine = ExplorationMachineIsolationProbe()
    let session = ExplorationSession(
      driver: ExplorationNullVoiceDriver(),
      speechOutput: ExplorationNullSpeechOutput()
    )
    let workspace = OperatorWorkspace(
      machineActions: machine.actions,
      cameraActions: CameraComposition.actions,
      explorationActions: explorationActions(session),
      nowNanoseconds: { 10_000 }
    )

    await workspace.switchFrameMode(.simulated)
    await workspace.startExploration()
    #expect(workspace.explorationIsActive)
    await workspace.runSimulatedExploration()

    #expect(workspace.explorationFlow.phase == .completed)
    #expect(workspace.lastInkObservation != nil)
    #expect(workspace.lastAnchorObservation != nil)
    #expect(workspace.armatureGuidanceState?.observations.count == 2)
    #expect(workspace.drawingFramePosterior?.observationCount == 1)
    #expect(workspace.drawingFramePosterior?.sidePosteriors.count == 1)
    #expect(workspace.completedExplorationEpisodes.count == 3)
    #expect(workspace.explorationSessionSnapshot?.state == .listening)
    #expect(await machine.invocationCount == 0)

    await workspace.endExploration()
    #expect(workspace.explorationSessionSnapshot?.state == .inactive)
  }

  @Test("simulated and live sources share the exact ordered coordinator")
  func sharedOrdering() throws {
    for authority in [
      ExplorationFlowCoordinator.Authority.simulated,
      .live,
    ] {
      let configurationID = CameraConfigurationID()
      var flow = ExplorationFlowCoordinator()
      flow.start(authority: authority)
      try flow.completeMotionPreflight()
      try flow.acceptClearPose(id: "clear-pose")
      try flow.recordCleanReference(
        try displayedFrame(authority: authority, sequence: 1, configurationID: configurationID)
      )
      try flow.recordLineStart(MachinePosition(x: 10, y: 20))
      try flow.recordAnchoredBaseline(
        try displayedFrame(authority: authority, sequence: 2, configurationID: configurationID),
        anchorCentroid: Point2(x: 22, y: 24)
      )
      try flow.beginIsolatedStroke()
      try flow.settleForPostLineObservation()
      try flow.recordPostLineFrame(
        try displayedFrame(authority: authority, sequence: 3, configurationID: configurationID)
      )
      try flow.acceptAssessment("line is visible and slightly low")

      let expectedPosition = try MachinePosition(x: 10, y: 20)
      let expectedAnchor: Point2<CameraPixelSpace> = try Point2(x: 22, y: 24)
      #expect(flow.phase == .completed)
      #expect(flow.lineStartPosition == expectedPosition)
      #expect(flow.anchorCentroid == expectedAnchor)
      #expect(flow.cleanReference?.frameID == FrameID(rawValue: "frame-1"))
      #expect(flow.anchoredBaseline?.frameID == FrameID(rawValue: "frame-2"))
      #expect(flow.postLineFrame?.frameID == FrameID(rawValue: "frame-3"))
    }
  }

  @Test("frame source, configuration, and strict recency are enforced")
  func frameIdentityIsClosed() throws {
    let configurationID = CameraConfigurationID()
    var flow = ExplorationFlowCoordinator()
    flow.start(authority: .simulated)
    try flow.completeMotionPreflight()
    try flow.acceptClearPose(id: "clear")

    #expect(throws: ExplorationFlowError.frameSourceMismatch) {
      try flow.recordCleanReference(
        try displayedFrame(authority: .live, sequence: 1, configurationID: configurationID)
      )
    }
    try flow.recordCleanReference(
      try displayedFrame(authority: .simulated, sequence: 1, configurationID: configurationID)
    )
    try flow.recordLineStart(MachinePosition(x: 0, y: 0))

    #expect(throws: ExplorationFlowError.cameraConfigurationChanged) {
      try flow.recordAnchoredBaseline(
        try displayedFrame(
          authority: .simulated,
          sequence: 2,
          configurationID: CameraConfigurationID()
        ),
        anchorCentroid: Point2(x: 4, y: 4)
      )
    }
    #expect(throws: ExplorationFlowError.frameNotStrictlyNewer) {
      try flow.recordAnchoredBaseline(
        try displayedFrame(
          authority: .simulated,
          sequence: 0,
          captureNanoseconds: 1,
          configurationID: configurationID
        ),
        anchorCentroid: Point2(x: 4, y: 4)
      )
    }
  }

  @Test("out-of-order transitions fail without advancing")
  func transitionsAreClosed() throws {
    var flow = ExplorationFlowCoordinator()
    flow.start(authority: .live)

    #expect(
      throws: ExplorationFlowError.unexpectedPhase(
        expected: .armatureGuidance,
        actual: .motionPreflight
      )
    ) {
      try flow.acceptClearPose(id: "clear")
    }
    #expect(flow.phase == .motionPreflight)
  }

  private func displayedFrame(
    authority: ExplorationFlowCoordinator.Authority,
    sequence: UInt64,
    captureNanoseconds: UInt64? = nil,
    configurationID: CameraConfigurationID
  ) throws -> DisplayedFrame {
    let source: FrameSourceIdentity =
      authority == .simulated ? .simulated : .live(CameraDeviceID(rawValue: "camera"))
    return DisplayedFrame(
      source: source,
      frame: try StampedFrame(
        id: FrameID(rawValue: "frame-\(sequence)"),
        sequence: sequence,
        captureNanoseconds: captureNanoseconds ?? sequence * 1_000,
        cameraConfigurationID: configurationID,
        width: 2,
        height: 2,
        rowBytes: 8,
        pixelFormat: .bgra8,
        bytes: OwnedFrameBytes([
          255, 255, 255, 255, 255, 255, 255, 255,
          255, 255, 255, 255, 255, 255, 255, 255,
        ])
      )
    )
  }
}

private actor ExplorationNullVoiceDriver: VoiceInteractionDriving {
  func snapshot() -> VoiceInteractionSnapshot {
    VoiceInteractionSnapshot(
      authorization: .authorized,
      listeningState: .stopped,
      recognitionPolicy: .onDeviceRequired,
      latestTranscript: nil
    )
  }

  func requestAuthorization() -> VoiceAuthorizationState { .authorized }
  func startListening() {}
  func stopListening() {}
  func transcripts() -> AsyncStream<VoiceTranscript> { AsyncStream { _ in } }
}

private actor ExplorationNullSpeechOutput: VoiceSpeechOutput {
  func speak(_: String) {}
  func stopSpeaking() {}
}

private func explorationActions(
  _ session: ExplorationSession
) -> OperatorWorkspace.ExplorationActions {
  OperatorWorkspace.ExplorationActions(
    start: { input, id in await session.start(input: input, id: id) },
    activateEpisode: { try await session.activateEpisode($0) },
    completeEpisode: { id, termination in
      try await session.completeEpisode(id, termination: termination)
    },
    ingest: { await session.ingest($0) },
    speakFeedback: { await session.speakFeedback($0) },
    end: { await session.end() },
    snapshot: { await session.snapshot() },
    events: { await session.events() }
  )
}

private actor ExplorationMachineIsolationProbe {
  private(set) var invocationCount = 0

  nonisolated var actions: OperatorWorkspace.MachineActions {
    OperatorWorkspace.MachineActions(
      select: { _ in fatalError("simulator reached controller selection") },
      snapshot: { nil },
      requestPassiveProbe: { fatalError("simulator reached passive probe") },
      activateMotionGuard: {
        await self.recordInvocation()
        return .refused(.noSerialDeviceSelected)
      },
      deactivateMotionGuard: { await self.recordInvocation() },
      requestRelativeJog: { _ in
        await self.recordInvocation()
        return .refused(.noSerialDeviceSelected)
      },
      requestDrawingStroke: { _ in
        await self.recordInvocation()
        return .refused(.noSerialDeviceSelected)
      },
      requestObservedJog: { _, _ in
        await self.recordInvocation()
        return .notRecorded(
          motionOutcome: nil,
          failure: .motionNotCompleted(.refused(.noSerialDeviceSelected))
        )
      },
      requestPenActuation: { _ in
        await self.recordInvocation()
        return .refused(.noSerialDeviceSelected)
      },
      requestJogCancel: {
        await self.recordInvocation()
        return .refused(.noSerialDeviceSelected)
      },
      disconnect: { await self.recordInvocation() }
    )
  }

  private func recordInvocation() { invocationCount += 1 }
}
