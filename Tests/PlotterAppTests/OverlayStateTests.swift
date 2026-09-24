import Foundation
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Overlay ownership and state")
@MainActor
struct OverlayStateTests {
  @Test("frozen selection never claims the ambient matcher is analyzing its pixels")
  func frozenSelectionDoesNotBorrowAmbientProgress() throws {
    let frame = try displayedFrame(id: "frozen", source: .live(CameraDeviceID(rawValue: "camera")),
      configuration: CameraConfigurationID())
    let running = PlotterSceneAnalysisSnapshot(revision: 1,
      phase: PlotterSceneAnalysisPhase(state: .running(.twoFPS), requestedFeatures: [.penCap],
        analysisRegion: nil, penCapColor: .green), latestResult: nil, lastError: nil)
    let composition = OverlayPresentationComposer.compose(preference: .loaded([.penCap]),
      channels: OverlayResultChannels(), displayedFrame: frame, sceneState: running,
      sceneIsAvailable: true, workflowVisionIsExclusive: false, frozenSelectionIsActive: true)
    #expect(composition.statuses[.penCap]?.state == .waiting)
    #expect(composition.statuses[.penCap]?.message.contains("landmark click") == true)
    #expect(composition.overlays.isEmpty)
  }

  @Test("missing-cap diagnostics retain their analyzed frame and reject another camera")
  func missingCapDiagnosticIsFrameQualified() throws {
    let configuration = CameraConfigurationID()
    let analyzed = try displayedFrame(id: "analyzed", source: .simulated, configuration: configuration)
    let current = try displayedFrame(id: "newer", source: .simulated, configuration: configuration, sequence: 2)
    let result = OverlayChannelResult(displayedFrame: analyzed, overlays: [], statuses: [
      .penCap: OverlayLayerStatus(state: .unavailable, message: OverlayStatusGrammar.notFound,
        provenance: ExactFrameOverlayProvenance(analyzed))
    ])
    #expect(result.diagnosticStatus(for: .penCap, displayedFrame: current)?.message
      == "Last analyzed frame 1: No pen cap detected — no pixels matched the selected cap color.")
    let other = try displayedFrame(id: "other", source: .simulated, configuration: CameraConfigurationID())
    #expect(result.diagnosticStatus(for: .penCap, displayedFrame: other) == nil)
  }

  @Test("exactly two operator overlay preferences are retained without result cards")
  func exactGlobalControls() {
    #expect(UserSceneOverlay.allCases == [.penCap, .armatureEnvelope])
    #expect(UserSceneOverlay.allCases.map(\.title) == ["Tracking reference", "Armature envelope"])
  }

  @Test("frozen armature language never claims independent segmentation")
  func armatureGrammar() {
    #expect(
      OverlayStatusGrammar.armatureUnavailable(reason: "no threshold pixels")
        == "Armature envelope unavailable because the tracking landmark was not found: no threshold pixels."
    )
    #expect(
      OverlayStatusGrammar.armatureAvailable
        == "Armature envelope available — inferred from the tracking landmark; not independently segmented."
    )
  }

  @Test("preference mutations identify persistence load and explicit operator action")
  func preferenceMutationProvenance() {
    var state = OverlayPreferenceState.loaded([.penCap])
    #expect(state.enabled == [.penCap])
    #expect(state.lastMutationSource == .persistenceLoad)

    state.applyOperatorSelection(.armatureEnvelope, enabled: true)
    #expect(state.enabled == Set(UserSceneOverlay.allCases))
    #expect(state.lastMutationSource == .operatorAction)
    #expect(SceneFeatureSet(preference: state) == [.penCap, .armatureEnvelope])
    #expect(
      Set(OverlayRunState.allCases) == [
        .off, .waiting, .analyzing, .available, .unavailable, .ambiguous, .failed,
        .suspended, .stale,
      ])
  }

  @Test("operator preference persists across camera and source lifecycle")
  func preferenceSurvivesLifecycle() async throws {
    let preference = OverlayPreferenceRecorder(loaded: [.penCap])
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let workspace = plotterApplicationRuntime(
      machine: machine,
      camera: camera,
      loadOverlayPreference: { preference.load() },
      persistOverlayPreference: { preference.save($0) },
      log: log
    )

    #expect(workspace.overlayPreferenceState.enabled == [.penCap])
    #expect(workspace.overlayPreferenceState.lastMutationSource == .persistenceLoad)
    await submitObservationConfigurationForTest(workspace, .setOverlay(.armatureEnvelope, enabled: true))
    #expect(preference.saved == [Set(UserSceneOverlay.allCases)])

    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    await submitObservationConfigurationForTest(workspace, .stopLiveSource)
    await submitObservationConfigurationForTest(workspace, .restartLiveSource)
    await submitObservationConfigurationForTest(workspace, .selectSource(.simulated, nil))
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))

    #expect(workspace.overlayPreferenceState.enabled == Set(UserSceneOverlay.allCases))
    #expect(workspace.overlayPreferenceState.lastMutationSource == .operatorAction)
    #expect(preference.saved == [Set(UserSceneOverlay.allCases)])
    await workspace.shutdown()
  }

  @Test("entering and leaving Learning preserves the current overlay presentation context")
  func learningVisibilityDoesNotResetOverlays() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession(
      providesInspectionOverlay: true,
      providesAutomaticAnalysisResult: true
    )
    let workspace = plotterApplicationRuntime(machine: machine, camera: camera, log: log)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    try await waitUntil {
      let presentation = workspace.testActionSurfacePresentation
      guard let frame = presentation.displayedFrame else { return false }
      return presentation.overlays.map(\.provenance.kind) == [.penCap]
        && presentation.overlays.allSatisfy { $0.matches(frame) }
    }
    let before = workspace.testActionSurfacePresentation
    #expect(before.overlays.map(\.provenance.kind) == [.penCap])

    await workspace.submitTestPlotterUIAction(PlotterAppUIActionID.learningMode)
    try await waitUntil { !workspace.testLearningIsEnabled }
    #expect(!workspace.testLearningIsEnabled)
    await workspace.submitTestPlotterUIAction(PlotterAppUIActionID.learningMode)
    try await waitUntil { workspace.testLearningIsEnabled }

    let after = workspace.testActionSurfacePresentation
    #expect(workspace.testLearningIsEnabled)
    #expect(after.viewportContext == before.viewportContext)
    #expect(after.displayedFrame == before.displayedFrame)
    #expect(after.overlays == before.overlays)
    await workspace.shutdown()
  }

  @Test("scene workflow and simulation producers cannot replace each other")
  func channelsDoNotOverwrite() throws {
    let configuration = CameraConfigurationID()
    let live = try displayedFrame(
      id: "live", source: .live(CameraDeviceID(rawValue: "camera")), configuration: configuration)
    let simulated = try displayedFrame(
      id: "simulated", source: .simulated, configuration: configuration)
    let scene = OverlayChannelResult(
      displayedFrame: live,
      overlays: [try overlay(.penCap, frame: live)]
    )
    let workflow = OverlayChannelResult(
      displayedFrame: live,
      overlays: [try overlay(.observedInk, frame: live)]
    )
    let simulation = OverlayChannelResult(
      displayedFrame: simulated,
      overlays: [try overlay(.armatureEstimate, frame: simulated)]
    )
    var channels = OverlayResultChannels()

    channels.publishScene(scene)
    channels.publishWorkflow(workflow, source: .live, owner: .borderValidation)
    channels.publishSimulation(simulation)

    #expect(channels.scene == scene)
    #expect(channels.workflowResults(for: .live) == [workflow])
    #expect(channels.simulation == simulation)

    channels.publishScene(
      OverlayChannelResult(displayedFrame: live, overlays: [try overlay(.penCap, frame: live)])
    )
    #expect(channels.workflowResults(for: .live) == [workflow])
    #expect(channels.simulation == simulation)
  }

  @Test("stale geometry is hidden while its typed diagnostic status is retained")
  func staleGeometryIsNonRenderable() throws {
    let configuration = CameraConfigurationID()
    let analyzed = try displayedFrame(
      id: "analyzed", source: .live(CameraDeviceID(rawValue: "camera")),
      configuration: configuration)
    let current = try displayedFrame(
      id: "current", source: analyzed.source, configuration: configuration)
    var channels = OverlayResultChannels()
    channels.publishScene(
      OverlayChannelResult(
        displayedFrame: analyzed,
        overlays: [try overlay(.penCap, frame: analyzed)]
      )
    )

    let composition = OverlayPresentationComposer.compose(
      preference: .loaded([.penCap]),
      channels: channels,
      displayedFrame: current,
      sceneState: .stopped,
      sceneIsAvailable: true,
      workflowVisionIsExclusive: false
    )

    #expect(composition.overlays.isEmpty)
    #expect(composition.statuses[.penCap]?.state == .stale)
    #expect(composition.statuses[.penCap]?.message == OverlayStatusGrammar.stale)
  }

  @Test("next-frame analysis retains completed geometry for the displayed exact frame")
  func analyzingRetainsMatchingCompletedGeometry() throws {
    let configuration = CameraConfigurationID()
    let displayed = try displayedFrame(
      id: "completed", source: .live(CameraDeviceID(rawValue: "camera")),
      configuration: configuration, sequence: 40)
    let stale = try displayedFrame(
      id: "stale", source: displayed.source, configuration: configuration, sequence: 39)
    var matchingChannels = OverlayResultChannels()
    let completedStatus = OverlayLayerStatus(
      state: .available,
      message: OverlayStatusGrammar.found(pixelCount: 20, confidence: 0.9, frame: 40),
      provenance: ExactFrameOverlayProvenance(displayed)
    )
    matchingChannels.publishScene(
      OverlayChannelResult(
        displayedFrame: displayed,
        overlays: [try overlay(.penCap, frame: displayed)],
        statuses: [.penCap: completedStatus]
      )
    )
    let analyzing = PlotterSceneAnalysisSnapshot(
      revision: 1,
      phase: PlotterSceneAnalysisPhase(
        state: .running(.twoFPS),
        requestedFeatures: [.penCap],
        analysisRegion: nil,
        penCapColor: .green
      ),
      latestResult: nil,
      lastError: nil
    )

    let matching = OverlayPresentationComposer.compose(
      preference: .loaded([.penCap]),
      channels: matchingChannels,
      displayedFrame: displayed,
      sceneState: analyzing,
      sceneIsAvailable: true,
      workflowVisionIsExclusive: false
    )
    #expect(matching.overlays.map(\.provenance.kind) == [.penCap])
    #expect(matching.statuses[.penCap] == completedStatus)
    #expect(matching.statuses[.penCap]?.provenance?.frameID == displayed.frame.id)

    var staleChannels = OverlayResultChannels()
    staleChannels.publishScene(
      OverlayChannelResult(
        displayedFrame: stale,
        overlays: [try overlay(.penCap, frame: stale)]
      )
    )
    let mismatched = OverlayPresentationComposer.compose(
      preference: .loaded([.penCap]),
      channels: staleChannels,
      displayedFrame: displayed,
      sceneState: analyzing,
      sceneIsAvailable: true,
      workflowVisionIsExclusive: false
    )
    #expect(mismatched.overlays.isEmpty)
    #expect(mismatched.statuses[.penCap]?.state == .analyzing)
  }

  @Test("camera unavailability hides retained scene geometry and reports waiting")
  func stoppedCameraDoesNotRenderRetainedSceneResult() throws {
    let configuration = CameraConfigurationID()
    let frame = try displayedFrame(
      id: "retained", source: .live(CameraDeviceID(rawValue: "camera")),
      configuration: configuration)
    var channels = OverlayResultChannels()
    channels.publishScene(
      OverlayChannelResult(
        displayedFrame: frame,
        overlays: [try overlay(.penCap, frame: frame)]
      )
    )

    let composition = OverlayPresentationComposer.compose(
      preference: .loaded([.penCap]),
      channels: channels,
      displayedFrame: frame,
      sceneState: .stopped,
      sceneIsAvailable: false,
      workflowVisionIsExclusive: false
    )

    #expect(composition.overlays.isEmpty)
    #expect(composition.statuses[.penCap]?.state == .waiting)
    #expect(composition.statuses[.penCap]?.message == OverlayStatusGrammar.waiting)
  }

  @Test("contextual workflow evidence ignores global preference and sources stay isolated")
  func contextualEvidenceAndSourceIsolation() throws {
    let configuration = CameraConfigurationID()
    let live = try displayedFrame(
      id: "shared", source: .live(CameraDeviceID(rawValue: "camera")),
      configuration: configuration)
    let simulated = try displayedFrame(
      id: "shared", source: .simulated, configuration: configuration)
    var channels = OverlayResultChannels()
    channels.publishWorkflow(
      OverlayChannelResult(
        displayedFrame: live,
        overlays: [
          try overlay(.intendedPath, frame: live),
          try overlay(.observedInk, frame: live),
          try overlay(.residual, frame: live),
        ]
      ),
      source: .live,
      owner: .borderValidation
    )
    channels.publishSimulation(
      OverlayChannelResult(
        displayedFrame: simulated,
        overlays: [try overlay(.penCap, frame: simulated)],
        statuses: [
          .penCap: OverlayLayerStatus(
            state: .available,
            message: OverlayStatusGrammar.simulatedPenCapAvailable(
              frame: simulated.frame.sequence),
            provenance: ExactFrameOverlayProvenance(simulated)
          ),
          .armatureEnvelope: OverlayLayerStatus(
            state: .unavailable,
            message: OverlayStatusGrammar.simulatedArmatureUnavailable(
              frame: simulated.frame.sequence),
            provenance: ExactFrameOverlayProvenance(simulated)
          ),
        ]
      )
    )

    let liveComposition = OverlayPresentationComposer.compose(
      preference: .loaded([]),
      channels: channels,
      displayedFrame: live,
      sceneState: .stopped,
      sceneIsAvailable: true,
      workflowVisionIsExclusive: false
    )
    #expect(
      liveComposition.overlays.map(\.provenance.kind)
        == [.intendedPath, .observedInk, .residual]
    )
    #expect(liveComposition.statuses.values.allSatisfy { $0.state == .off })
    #expect(liveComposition.analyzedFrame?.frameID == live.frame.id)

    let simulatedComposition = OverlayPresentationComposer.compose(
      preference: .loaded(Set(UserSceneOverlay.allCases)),
      channels: channels,
      displayedFrame: simulated,
      sceneState: .stopped,
      sceneIsAvailable: false,
      workflowVisionIsExclusive: true
    )
    #expect(simulatedComposition.overlays.map(\.provenance.kind) == [.penCap])
    #expect(simulatedComposition.statuses[.penCap]?.state == .available)
    #expect(
      simulatedComposition.statuses[.penCap]?.message
        == OverlayStatusGrammar.simulatedPenCapAvailable(frame: simulated.frame.sequence)
    )
    #expect(simulatedComposition.statuses[.armatureEnvelope]?.state == .unavailable)
    #expect(
      simulatedComposition.statuses[.armatureEnvelope]?.message
        == OverlayStatusGrammar.simulatedArmatureUnavailable(frame: simulated.frame.sequence)
    )

    let suspendedLiveComposition = OverlayPresentationComposer.compose(
      preference: .loaded([.penCap]),
      channels: channels,
      displayedFrame: live,
      sceneState: .stopped,
      sceneIsAvailable: true,
      workflowVisionIsExclusive: true
    )
    #expect(
      suspendedLiveComposition.overlays.map(\.provenance.kind)
        == [.intendedPath, .observedInk, .residual]
    )
    #expect(suspendedLiveComposition.statuses[.penCap]?.state == .suspended)
    #expect(suspendedLiveComposition.statuses[.penCap]?.message == OverlayStatusGrammar.suspended)
  }

  @Test("simulation consumes typed unavailable statuses without geometry inference")
  func simulatedUnavailableStatusIsProducerOwned() throws {
    let simulated = try displayedFrame(
      id: "simulated-unavailable",
      source: .simulated,
      configuration: CameraConfigurationID(),
      sequence: 44
    )
    let provenance = ExactFrameOverlayProvenance(simulated)
    var channels = OverlayResultChannels()
    channels.publishSimulation(
      OverlayChannelResult(
        displayedFrame: simulated,
        overlays: [],
        statuses: [
          .penCap: OverlayLayerStatus(
            state: .unavailable,
            message: OverlayStatusGrammar.simulatedPenCapUnavailable(frame: 44),
            provenance: provenance
          ),
          .armatureEnvelope: OverlayLayerStatus(
            state: .unavailable,
            message: OverlayStatusGrammar.simulatedArmatureUnavailable(frame: 44),
            provenance: provenance
          ),
        ]
      )
    )

    let composition = OverlayPresentationComposer.compose(
      preference: .loaded(Set(UserSceneOverlay.allCases)),
      channels: channels,
      displayedFrame: simulated,
      sceneState: .stopped,
      sceneIsAvailable: false,
      workflowVisionIsExclusive: false
    )

    #expect(composition.overlays.isEmpty)
    #expect(composition.statuses[.penCap]?.state == .unavailable)
    #expect(
      composition.statuses[.penCap]?.message
        == "Unavailable — no causal simulated pen-cap geometry for frame 44."
    )
    #expect(composition.statuses[.armatureEnvelope]?.state == .unavailable)
    #expect(
      composition.statuses[.armatureEnvelope]?.message
        == "Armature envelope unavailable because causal simulated pen-cap geometry is unavailable for frame 44."
    )
  }

  @Test("ActionSurface identifies only an exact matching analyzed overlay frame")
  func explicitAnalyzedFramePresentation() throws {
    let configuration = CameraConfigurationID()
    let analyzed = try displayedFrame(
      id: "analyzed", source: .live(CameraDeviceID(rawValue: "camera")),
      configuration: configuration)
    let other = try displayedFrame(
      id: "other", source: analyzed.source, configuration: configuration)

    let exact = ActionSurfacePresentation(
      displayedFrame: analyzed,
      overlays: [try overlay(.penCap, frame: analyzed)],
      analyzedOverlayFrame: ExactFrameOverlayProvenance(analyzed)
    )
    #expect(exact.analyzedOverlayFrame?.frameID == analyzed.frame.id)
    #expect(exact.analyzedOverlayFrame?.frameSequence == analyzed.frame.sequence)

    let mismatched = ActionSurfacePresentation(
      displayedFrame: other,
      overlays: [try overlay(.penCap, frame: analyzed)],
      analyzedOverlayFrame: ExactFrameOverlayProvenance(analyzed)
    )
    #expect(mismatched.overlays.isEmpty)
    #expect(mismatched.analyzedOverlayFrame == nil)
  }

  @Test("overlay matching never hashes passive preview and reuses one analysis promotion")
  func overlayMatchingUsesExplicitCachedHash() throws {
    let source = FrameSourceIdentity.live(CameraDeviceID(rawValue: "camera"))
    let configuration = CameraConfigurationID()
    let bytes = OwnedFrameBytes(Array(repeating: 17, count: 16))
    let analyzed = DisplayedFrame(
      source: source,
      frame: try StampedFrame(
        id: FrameID(rawValue: "shared-frame"),
        sequence: 7,
        captureNanoseconds: 70,
        cameraConfigurationID: configuration,
        width: 4,
        height: 4,
        rowBytes: 4,
        pixelFormat: .gray8,
        bytes: bytes,
        eagerlyMaterializeContentHash: false
      ).materializingContentHash(for: .analysis)
    )
    let passiveMetrics = FrameContentHashMetrics()
    let passive = DisplayedFrame(
      source: source,
      frame: try StampedFrame(
        id: analyzed.frame.id,
        sequence: analyzed.frame.sequence,
        captureNanoseconds: analyzed.frame.captureNanoseconds,
        cameraConfigurationID: configuration,
        width: 4,
        height: 4,
        rowBytes: 4,
        pixelFormat: .gray8,
        bytes: bytes,
        eagerlyMaterializeContentHash: false,
        contentHashMetrics: passiveMetrics
      )
    )
    let provenance = ExactFrameOverlayProvenance(analyzed)

    #expect(!provenance.matches(passive))
    #expect(passive.frame.materializedContentSHA256 == nil)
    #expect(passiveMetrics.snapshot.totalComputationCount == 0)

    let promoted = DisplayedFrame(
      source: passive.source,
      frame: passive.frame.materializingContentHash(for: .analysis)
    )
    #expect(provenance.matches(promoted))
    #expect(provenance.matches(promoted))
    #expect(passiveMetrics.snapshot.analysisComputationCount == 1)
    #expect(passiveMetrics.snapshot.totalComputationCount == 1)
  }
}

private final class OverlayPreferenceRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private let loaded: Set<UserSceneOverlay>?
  private var savedValues: [Set<UserSceneOverlay>] = []

  init(loaded: Set<UserSceneOverlay>?) {
    self.loaded = loaded
  }

  func load() -> Set<UserSceneOverlay>? { loaded }

  func save(_ value: Set<UserSceneOverlay>) {
    lock.lock()
    savedValues.append(value)
    lock.unlock()
  }

  var saved: [Set<UserSceneOverlay>] {
    lock.lock()
    defer { lock.unlock() }
    return savedValues
  }
}

private func displayedFrame(
  id: String,
  source: FrameSourceIdentity,
  configuration: CameraConfigurationID,
  sequence: UInt64 = 1,
  captureNanoseconds: UInt64 = 10
) throws -> DisplayedFrame {
  DisplayedFrame(
    source: source,
    frame: try StampedFrame(
      id: FrameID(rawValue: id),
      sequence: sequence,
      captureNanoseconds: captureNanoseconds,
      cameraConfigurationID: configuration,
      width: 4,
      height: 4,
      rowBytes: 4,
      pixelFormat: .gray8,
      bytes: OwnedFrameBytes(Array(repeating: 0, count: 16))
    )
  )
}

private func overlay(
  _ kind: CameraOverlayKind,
  frame: DisplayedFrame
) throws -> CameraOverlayMeasurement {
  CameraOverlayMeasurement(
    frameID: frame.frame.id,
    cameraConfigurationID: frame.frame.cameraConfigurationID,
    geometry: .point(try Point2(x: 1, y: 1)),
    provenance: CameraMeasurementProvenance(
      kind: kind,
      source: kind == .observedInk ? .measured : .inferred,
      algorithmRevision: "overlay-state-test-v1"
    )
  )
}
