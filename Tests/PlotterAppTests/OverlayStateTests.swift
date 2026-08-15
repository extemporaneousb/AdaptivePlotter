import Foundation
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Overlay ownership and state")
@MainActor
struct OverlayStateTests {
  @Test("exactly two global controls use one-column layout at every supported inspector width")
  func exactGlobalControlsAndResponsiveLayout() {
    #expect(UserSceneOverlay.allCases == [.penCap, .armatureEnvelope])
    #expect(UserSceneOverlay.allCases.map(\.title) == ["Pen cap", "Armature envelope"])
    for width in OverlayCardLayoutPolicy.supportedInspectorWidths {
      #expect(OverlayCardLayoutPolicy.columnCount(availableWidth: width) == 1)
      #expect(
        OverlayCardLayoutPolicy.contentWidth(availableWidth: width)
          >= OverlayCardLayoutPolicy.minimumCardWidth
      )
    }
  }

  @Test("every run state has deterministic text color and accessibility presentation")
  func exhaustiveStatusPresentation() {
    let messages: [OverlayRunState: String] = [
      .off: "Off",
      .waiting: OverlayStatusGrammar.waiting,
      .analyzing: OverlayStatusGrammar.analyzing(frame: 41),
      .available: OverlayStatusGrammar.found(pixelCount: 120, confidence: 0.91, frame: 40),
      .unavailable: OverlayStatusGrammar.notFound,
      .ambiguous: OverlayStatusGrammar.ambiguous(candidateSizes: [120, 118]),
      .failed: "Failed — camera bytes were unavailable",
      .suspended: OverlayStatusGrammar.suspended,
      .stale: OverlayStatusGrammar.stale,
    ]
    let colors: [OverlayRunState: OverlayStatusColorToken] = [
      .off: .unavailableDarkGray,
      .waiting: .neutralGray,
      .analyzing: .neutralGray,
      .available: .affirmativeGreen,
      .unavailable: .negativeRed,
      .ambiguous: .negativeRed,
      .failed: .negativeRed,
      .suspended: .neutralGray,
      .stale: .negativeRed,
    ]

    #expect(Set(messages.keys) == Set(OverlayRunState.allCases))
    for state in OverlayRunState.allCases {
      let card = OverlayCardPresentation(
        overlay: .penCap,
        isOn: state != .off,
        status: OverlayLayerStatus(state: state, message: messages[state]!, provenance: nil),
        roiText: "Full frame · unlocked/default analysis",
        cadenceText: "2 frames per second",
        nowNanoseconds: 100
      )
      #expect(card.statusText == messages[state])
      #expect(card.colorToken == colors[state])
      #expect(card.accessibilityLabel == "Pen cap scene overlay")
      #expect(card.accessibilityValue.contains(messages[state]!))
      #expect(card.accessibilityValue.contains("No exact analyzed frame"))
    }
  }

  @Test("long failures remain complete multiline content and status does not mutate selection")
  func longFailureAndSelectionIndependence() {
    let longReason =
      "Failed — the newest exact camera frame could not be decoded after the camera configuration changed; select a current source and wait for a new exact frame before retrying."
    let preference = OverlayPreferenceState.loaded([.penCap])
    let card = OverlayCardPresentation(
      overlay: .penCap,
      isOn: preference.enabled.contains(.penCap),
      status: OverlayLayerStatus(state: .failed, message: longReason, provenance: nil),
      roiText: "Full frame · unlocked/default analysis",
      cadenceText: "2 frames per second",
      nowNanoseconds: 100
    )

    #expect(card.supportsMultilineText)
    #expect(card.statusText == longReason)
    #expect(card.helpText.contains(longReason))
    #expect(card.isOn)
    #expect(preference.enabled == [.penCap])
    #expect(preference.lastMutationSource == .persistenceLoad)
  }

  @Test("overlay cards expose exact-frame ROI cadence and result age")
  func exactFrameCardMetadata() throws {
    let frame = try displayedFrame(
      id: "card-frame",
      source: .live(CameraDeviceID(rawValue: "camera")),
      configuration: CameraConfigurationID(),
      sequence: 27,
      captureNanoseconds: 1_000_000_000
    )
    let provenance = ExactFrameOverlayProvenance(frame)
    let status = OverlayLayerStatus(
      state: .available,
      message: OverlayStatusGrammar.found(pixelCount: 86, confidence: 0.92, frame: 27),
      provenance: provenance
    )
    let card = OverlayCardPresentation(
      overlay: .penCap,
      isOn: true,
      status: status,
      roiText: "x 12, y 18, 120 × 90 px",
      cadenceText: "2 frames per second",
      nowNanoseconds: 2_500_000_000
    )

    #expect(card.frameText == "Frame 27 · card-frame")
    #expect(card.resultAgeText == "1.50 s")
    #expect(card.accessibilityValue.contains("x 12, y 18, 120 × 90 px"))
    #expect(card.accessibilityValue.contains("2 frames per second"))
    #expect(card.accessibilityValue.contains("Frame 27 · card-frame"))
    #expect(card.accessibilityValue.contains("1.50 s"))
  }

  @Test("frozen armature language never claims independent segmentation")
  func armatureGrammar() {
    #expect(
      OverlayStatusGrammar.armatureUnavailable(reason: "no threshold pixels")
        == "Armature envelope unavailable because the pen cap was not found: no threshold pixels."
    )
    #expect(
      OverlayStatusGrammar.armatureAvailable
        == "Armature envelope available — inferred from cap; not independently segmented."
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
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(
      machine: machine,
      camera: camera,
      loadOverlayPreference: { preference.load() },
      persistOverlayPreference: { preference.save($0) },
      log: log
    )

    #expect(workspace.overlayPreferenceState.enabled == [.penCap])
    #expect(workspace.overlayPreferenceState.lastMutationSource == .persistenceLoad)
    workspace.setOverlay(.armatureEnvelope, enabled: true)
    #expect(preference.saved == [Set(UserSceneOverlay.allCases)])

    await workspace.startCamera()
    await workspace.stopCamera()
    await workspace.restartCamera()
    await workspace.switchFrameMode(.simulated)
    await workspace.switchFrameMode(.live)

    #expect(workspace.overlayPreferenceState.enabled == Set(UserSceneOverlay.allCases))
    #expect(workspace.overlayPreferenceState.lastMutationSource == .operatorAction)
    #expect(preference.saved == [Set(UserSceneOverlay.allCases)])
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
    channels.publishWorkflow(workflow, source: .live, owner: .observedDrawingTrial)
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

  @Test("stale geometry is hidden while stale status remains visible")
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
      owner: .observedDrawingTrial
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
