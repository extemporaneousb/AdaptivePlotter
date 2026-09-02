import Foundation
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("PlotterObservationConfigurationEpisodeTests")
struct PlotterObservationConfigurationEpisodeTests {
  @Test("stale projection cannot start a camera effect")
  func staleProjectionIsRefusedBeforeEffect() async throws {
    let fixture = try TestObservationCameraSession()
    let runtime = PlotterObservationConfigurationRuntime(
      lower: resolvedObservationSession(fixture)
    )
    let reference = await runtime.reference()
    let first = await runtime.submit(.init(reference: reference, intent: .refreshSources))
    guard case .applied = first else {
      Issue.record("Expected the current refresh request to apply.")
      return
    }
    let stale = await runtime.submit(.init(reference: reference, intent: .startLiveSource))
    #expect(stale == .stale)
    #expect(fixture.startupActionCounts.discover == 1)
    #expect(fixture.startupActionCounts.start == 0)
  }

  @Test("explicit automatic-analysis request preserves cadence, features, and exact region")
  func automaticAnalysisConfigurationIsTyped() async throws {
    let fixture = try TestObservationCameraSession()
    let runtime = PlotterObservationConfigurationRuntime(
      lower: resolvedObservationSession(fixture)
    )
    let frame = try #require(fixture.snapshot.latestFrame)
    let region = PixelRect(x: 1, y: 1, width: 3, height: 3)
    let result = await runtime.submit(.init(
      reference: await runtime.reference(),
      intent: .configureAutomaticAnalysis(
        cadence: .fiveFPS,
        features: [.penCap],
        region: region,
        penCapColor: .green
      )
    ))
    guard case .applied = result else {
      Issue.record("Expected typed automatic-analysis configuration to apply.")
      return
    }
    #expect(fixture.recordedAutomaticCadences == [.fiveFPS])
    #expect(fixture.recordedAutomaticFeatureRequests == [[.penCap]])
    #expect(fixture.recordedSceneAnalysisRegionRequests == [region])
    #expect(frame.frame.cameraConfigurationID == fixture.snapshot.latestFrame?.frame.cameraConfigurationID)
  }

  @Test("automatic-analysis reconfiguration replaces its semantic subscription")
  func automaticAnalysisReconfigurationResubscribes() async throws {
    let fixture = try TestObservationCameraSession()
    let traffic = TestAnalysisUpdateSource()
    let runtime = PlotterObservationConfigurationRuntime(
      lower: resolvedObservationSession(
        fixture,
        analysisUpdates: { traffic.updates() }
      )
    )

    let first = await runtime.submit(.init(
      reference: await runtime.reference(),
      intent: .configureAutomaticAnalysis(
        cadence: .fiveFPS,
        features: [.penCap],
        region: nil,
        penCapColor: .green
      )
    ))
    guard case .applied = first else {
      Issue.record("Expected the first automatic-analysis configuration to apply.")
      return
    }
    try await waitForExecutorTurns { traffic.subscriptionCount == 1 }

    let second = await runtime.submit(.init(
      reference: await runtime.reference(),
      intent: .configureAutomaticAnalysis(
        cadence: .twoFPS,
        features: [.penCap, .armatureEnvelope],
        region: nil,
        penCapColor: .green
      )
    ))
    guard case .applied = second else {
      Issue.record("Expected the replacement automatic-analysis configuration to apply.")
      return
    }
    try await waitForExecutorTurns { traffic.subscriptionCount == 2 }

    traffic.finish()
    await runtime.shutdown()
  }

  @Test("shutdown closes admission before any later camera request")
  func shutdownClosesAdmission() async throws {
    let fixture = try TestObservationCameraSession()
    let runtime = PlotterObservationConfigurationRuntime(
      lower: resolvedObservationSession(fixture)
    )
    await runtime.shutdown()
    let refused = await runtime.submit(.init(
      reference: await runtime.reference(),
      intent: .startLiveSource
    ))
    guard case .refused = refused else {
      Issue.record("Expected post-shutdown camera admission to be refused.")
      return
    }
    #expect(fixture.startupActionCounts.start == 0)
  }

  @Test("shutdown joins an in-flight restart without starting capture afterward")
  func shutdownCancelsInFlightRestartBeforeStartBoundary() async throws {
    let fixture = try TestObservationCameraSession()
    let probe = ObservationLifecycleProbe(blocksFirstStop: true)
    let port = ObservationLifecycleProbePort(
      base: resolvedObservationSession(fixture),
      probe: probe,
      startResult: .exactFrameBacked(fixture.snapshot)
    )
    let runtime = PlotterObservationConfigurationRuntime(lower: port)
    let originalReference = await runtime.reference()
    let restart = Task {
      await runtime.submit(.init(
        reference: originalReference,
        intent: .restartLiveSource
      ))
    }

    await probe.waitUntilFirstStopEntered()
    let shutdown = Task { await runtime.shutdown() }
    try await waitUntilAsync {
      (await runtime.reference()).revision == originalReference.revision &+ 1
    }
    await probe.releaseFirstStop()
    await shutdown.value

    #expect(await restart.value == .refused("Observation configuration was cancelled."))
    #expect(await probe.startEffectCount() == 0)
    #expect(await probe.stopEffectCount() == 2)
  }

  @Test("camera start recording requires exact requested and settled stream identity")
  func startRecordingRequiresExactStreamIdentity() async throws {
    let fixture = try TestObservationCameraSession()
    let stream = try #require(observationStream(fixture.snapshot.latestFrame))
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("observation-exact-start-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try observationRecordingStore(in: directory)
    let runtime = PlotterObservationConfigurationRuntime(
      lower: ObservationLifecycleProbePort(
        base: resolvedObservationSession(fixture),
        probe: ObservationLifecycleProbe(),
        startResult: .init(
          snapshot: fixture.snapshot,
          requestedStream: stream,
          settledStream: stream
        )
      ),
      recordingStore: store
    )

    let disposition = await runtime.submit(.init(
      reference: await runtime.reference(),
      intent: .startLiveSource
    ))
    guard case .applied = disposition else {
      Issue.record("Expected the exact lower lifecycle identity to settle.")
      return
    }
    #expect((await store.snapshot()).entries.map(\.record) == [
      .camera(.lifecycle(.startRequested(stream))),
      .camera(.lifecycle(.started(stream))),
    ])
    await runtime.shutdown()
  }

  @Test("nil or mismatched settled stream identity never records camera started")
  func startRecordingRejectsNilAndMismatchedSettlement() async throws {
    let fixture = try TestObservationCameraSession()
    let requested = try #require(observationStream(fixture.snapshot.latestFrame))
    let firstMismatch = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let fallbackMismatch = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let mismatch = requested.configuration.rawValue == firstMismatch
      ? fallbackMismatch : firstMismatch
    let mismatched = CameraStreamIdentity(
      source: requested.source,
      configuration: CameraConfigurationIdentity(rawValue: mismatch)
    )
    let settlements: [CameraStreamIdentity?] = [nil, mismatched]

    for (index, settled) in settlements.enumerated() {
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("observation-rejected-start-\(index)-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      let store = try observationRecordingStore(in: directory)
      let runtime = PlotterObservationConfigurationRuntime(
        lower: ObservationLifecycleProbePort(
          base: resolvedObservationSession(fixture),
          probe: ObservationLifecycleProbe(),
          startResult: .init(
            snapshot: fixture.snapshot,
            requestedStream: requested,
            settledStream: settled
          )
        ),
        recordingStore: store
      )

      let disposition = await runtime.submit(.init(
        reference: await runtime.reference(),
        intent: .startLiveSource
      ))
      guard case .applied = disposition else {
        Issue.record("Expected the lower lifecycle failure to be recorded without relabeling it.")
        continue
      }
      #expect((await store.snapshot()).entries.map(\.record) == [
        .camera(.lifecycle(.startRequested(requested))),
        .camera(.lifecycle(.failed(.init(
          operation: .start(requested),
          kind: .sourceUnavailable
        )))),
      ])
      await runtime.shutdown()
    }
  }

  @Test("workspace operator sink requires the immutable projection reference")
  @MainActor
  func workspaceProjectionBindsCapabilityAndRevision() async throws {
    let machine = try LowerMachineSessionFixture(log: EventLog())
    let workspace = plotterApplicationRuntime(
      machine: machine,
      camera: try TestObservationCameraSession(),
      log: EventLog()
    )
    let projection = workspace.observationConfigurationProjection
    await workspace.submitObservationConfiguration(projection.request(.setCadence(
      framesPerSecond: VisionAnalysisCadence.fiveFPS.rawValue
    )))
    #expect(workspace.observationConfigurationProjection.cadence == .fiveFPS)

    await workspace.submitObservationConfiguration(projection.request(.setCadence(
      framesPerSecond: VisionAnalysisCadence.twoFPS.rawValue
    )))
    #expect(workspace.observationConfigurationProjection.cadence == .fiveFPS)
    await workspace.shutdown()
  }
}

private actor ObservationLifecycleProbe {
  private let blocksFirstStop: Bool
  private var stopCount = 0
  private var startCount = 0
  private var firstStopEntered = false
  private var firstStopReleased = false
  private var entryWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiter: CheckedContinuation<Void, Never>?

  init(blocksFirstStop: Bool = false) {
    self.blocksFirstStop = blocksFirstStop
  }

  func enterStopEffect() async {
    stopCount += 1
    guard blocksFirstStop, stopCount == 1 else { return }
    firstStopEntered = true
    let waiters = entryWaiters
    entryWaiters.removeAll()
    waiters.forEach { $0.resume() }
    guard !firstStopReleased else { return }
    await withCheckedContinuation { continuation in
      releaseWaiter = continuation
    }
  }

  func enterStartEffect() {
    startCount += 1
  }

  func waitUntilFirstStopEntered() async {
    guard !firstStopEntered else { return }
    await withCheckedContinuation { continuation in
      entryWaiters.append(continuation)
    }
  }

  func releaseFirstStop() {
    firstStopReleased = true
    let continuation = releaseWaiter
    releaseWaiter = nil
    continuation?.resume()
  }

  func startEffectCount() -> Int { startCount }
  func stopEffectCount() -> Int { stopCount }
}

private struct ObservationLifecycleProbePort: PlotterObservationCameraSessionPort {
  let base: any PlotterObservationCameraSessionPort
  let probe: ObservationLifecycleProbe
  let startResult: PlotterObservationCameraLifecycleResult

  func discover() async -> CameraCaptureSnapshot { await base.discover() }

  func select(_ id: CameraDeviceID) async throws -> CameraCaptureSnapshot {
    try await base.select(id)
  }

  func start() async -> CameraCaptureSnapshot {
    await probe.enterStartEffect()
    return startResult.snapshot
  }

  func startLifecycle() async -> PlotterObservationCameraLifecycleResult {
    await probe.enterStartEffect()
    return startResult
  }

  func stop() async -> CameraCaptureSnapshot {
    await probe.enterStopEffect()
    return await base.snapshot()
  }

  func restart() async -> CameraCaptureSnapshot { await base.restart() }
  func snapshot() async -> CameraCaptureSnapshot { await base.snapshot() }
  func frames() async -> AsyncStream<DisplayedFrame> { await base.frames() }

  func inspectWorkflowScene(
    newerThanNanoseconds boundary: UInt64,
    requestedFeatures: SceneFeatureSet,
    analysisRegion: PixelRect?
  ) async throws -> LiveSceneInspection? {
    try await base.inspectWorkflowScene(
      newerThanNanoseconds: boundary,
      requestedFeatures: requestedFeatures,
      analysisRegion: analysisRegion
    )
  }

  func captureFrame(newerThanNanoseconds boundary: UInt64) async throws -> DisplayedFrame? {
    try await base.captureFrame(newerThanNanoseconds: boundary)
  }

  func captureStableWorkflowCap(
    _ request: StableWorkflowCapCaptureRequest
  ) async throws -> StableWorkflowCapInspection {
    try await base.captureStableWorkflowCap(request)
  }

  func setSceneAnalysisRegion(_ region: PixelRect?) async {
    await base.setSceneAnalysisRegion(region)
  }

  func setPenCapColor(_ color: PenCapColor) async {
    await base.setPenCapColor(color)
  }

  func setAutomaticInspection(
    _ cadence: VisionAnalysisCadence?,
    requestedFeatures: SceneFeatureSet
  ) async -> PlotterSceneAnalysisSnapshot {
    await base.setAutomaticInspection(cadence, requestedFeatures: requestedFeatures)
  }

  func analysisUpdates() async -> AsyncStream<PlotterSceneAnalysisSnapshot> {
    await base.analysisUpdates()
  }

  func visionDiagnostics() async -> CameraSourceSessionVisionDiagnostics {
    await base.visionDiagnostics()
  }

  func observePlannedDrawingInk(
    _ request: PlannedDrawingObservationRequest
  ) async -> PlannedDrawingObservationOutcome {
    await base.observePlannedDrawingInk(request)
  }
}

private func observationStream(_ frame: DisplayedFrame?) -> CameraStreamIdentity? {
  frame.map {
    CameraStreamIdentity(
      source: CameraSourceIdentity(rawValue: String(describing: $0.source)),
      configuration: CameraConfigurationIdentity(
        rawValue: $0.frame.cameraConfigurationID.rawValue
      )
    )
  }
}

private func observationRecordingStore(
  in directory: URL
) throws -> EpisodeRecordingStore {
  try EpisodeRecordingStore.open(
    directoryURL: directory,
    recordingID: EpisodeRecordingID(rawValue: UUID()),
    schemaRevision: EpisodeRecordingSchemaRevision(
      rawValue: "observation-configuration-red-line-v1"
    ),
    frameRetentionPolicy: EpisodeFrameRetentionPolicy(
      maximumUniqueFrameCount: 4,
      maximumTotalUniqueFrameBytes: 1_024
    )
  )
}
