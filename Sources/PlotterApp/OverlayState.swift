import Foundation
import PlotterModel
import PlotterRuntime

enum UserSceneOverlay: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case penCap
  case armatureEnvelope

  var id: Self { self }

  var title: String {
    switch self {
    case .penCap: "Pen cap"
    case .armatureEnvelope: "Armature envelope"
    }
  }

  var overlayKind: CameraOverlayKind {
    switch self {
    case .penCap: .penCap
    case .armatureEnvelope: .armatureEstimate
    }
  }
}

enum OverlayPreferenceMutationSource: String, Codable, Hashable, Sendable {
  case persistenceLoad
  case operatorAction
}

struct OverlayPreferenceState: Codable, Hashable, Sendable {
  private(set) var enabled: Set<UserSceneOverlay>
  private(set) var lastMutationSource: OverlayPreferenceMutationSource

  static func loaded(_ enabled: Set<UserSceneOverlay>?) -> Self {
    Self(
      enabled: enabled ?? Set(UserSceneOverlay.allCases),
      lastMutationSource: .persistenceLoad
    )
  }

  mutating func applyOperatorSelection(_ overlay: UserSceneOverlay, enabled isEnabled: Bool) {
    if isEnabled {
      enabled.insert(overlay)
    } else {
      enabled.remove(overlay)
    }
    lastMutationSource = .operatorAction
  }
}

enum OverlayRunState: String, CaseIterable, Codable, Hashable, Sendable {
  case off
  case waiting
  case analyzing
  case available
  case unavailable
  case ambiguous
  case failed
  case suspended
  case stale
}

extension SceneFeatureSet {
  init(preference: OverlayPreferenceState) {
    var requested: Self = []
    if preference.enabled.contains(.penCap) { requested.insert(.penCap) }
    if preference.enabled.contains(.armatureEnvelope) { requested.insert(.armatureEnvelope) }
    self = requested
  }
}

struct ExactFrameOverlayProvenance: Hashable, Sendable {
  let frameID: FrameID
  let frameSequence: UInt64
  let frameSHA256: String
  let source: FrameSourceIdentity
  let cameraConfigurationID: CameraConfigurationID
  let captureNanoseconds: UInt64
  let width: Int
  let height: Int
  let pixelFormat: FramePixelFormat

  init(_ displayedFrame: DisplayedFrame) {
    frameID = displayedFrame.frame.id
    frameSequence = displayedFrame.frame.sequence
    frameSHA256 = displayedFrame.frame.contentSHA256
    source = displayedFrame.source
    cameraConfigurationID = displayedFrame.frame.cameraConfigurationID
    captureNanoseconds = displayedFrame.frame.captureNanoseconds
    width = displayedFrame.frame.width
    height = displayedFrame.frame.height
    pixelFormat = displayedFrame.frame.pixelFormat
  }

  func matches(_ displayedFrame: DisplayedFrame) -> Bool {
    frameID == displayedFrame.frame.id
      && frameSHA256 == displayedFrame.frame.contentSHA256
      && source == displayedFrame.source
      && cameraConfigurationID == displayedFrame.frame.cameraConfigurationID
      && width == displayedFrame.frame.width
      && height == displayedFrame.frame.height
      && pixelFormat == displayedFrame.frame.pixelFormat
  }
}

struct OverlayLayerStatus: Hashable, Sendable {
  let state: OverlayRunState
  let message: String
  let provenance: ExactFrameOverlayProvenance?
}

enum OverlayStatusGrammar {
  static let waiting = "Waiting — no current exact camera frame."
  static func analyzing(frame: UInt64) -> String {
    "Analyzing — latest requested frame \(frame) …"
  }
  static let notFound =
    "Not found — no pixels passed the selected pen-cap color thresholds."
  static func candidateRejected(count: Int, reason: String) -> String {
    "Candidate rejected — \(count): \(reason)."
  }
  static func ambiguous(candidateSizes: [Int]) -> String {
    "Ambiguous — \(candidateSizes.map(String.init).joined(separator: ", ")); refusing to choose."
  }
  static func found(pixelCount: Int, confidence: Double, frame: UInt64) -> String {
    String(format: "Found — %d pixels, %.2f confidence, frame %llu.", pixelCount, confidence, frame)
  }
  static let stale = "Stale — result belongs to another frame or camera configuration."
  static let suspended = "Suspended — calibration owns exact-frame Vision; selection remains On."
  static func armatureUnavailable(reason: String) -> String {
    "Armature envelope unavailable because the pen cap was not found: \(reason)."
  }
  static let armatureAvailable =
    "Armature envelope available — inferred from cap; not independently segmented."

  static func simulatedPenCapAvailable(frame: UInt64) -> String {
    "Available — causal simulated pen-cap geometry, frame \(frame); pixel count and confidence are not applicable."
  }

  static func simulatedPenCapUnavailable(frame: UInt64) -> String {
    "Unavailable — no causal simulated pen-cap geometry for frame \(frame)."
  }

  static func simulatedArmatureAvailable(frame: UInt64) -> String {
    "Armature envelope available — inferred from simulated cap; not independently segmented, frame \(frame)."
  }

  static func simulatedArmatureUnavailable(frame: UInt64) -> String {
    "Armature envelope unavailable because causal simulated pen-cap geometry is unavailable for frame \(frame)."
  }
}

struct OverlayChannelResult: Hashable, Sendable {
  let provenance: ExactFrameOverlayProvenance
  let overlays: [CameraOverlayMeasurement]
  let statuses: [UserSceneOverlay: OverlayLayerStatus]

  init(
    displayedFrame: DisplayedFrame,
    overlays: [CameraOverlayMeasurement],
    statuses: [UserSceneOverlay: OverlayLayerStatus] = [:]
  ) {
    provenance = ExactFrameOverlayProvenance(displayedFrame)
    self.overlays = overlays
    self.statuses = statuses
  }
}

enum WorkflowOverlayOwner: Int, CaseIterable, Hashable, Sendable {
  case cameraCalibration
  case observedDrawingTrial
  case sparseTipCalibration
}

struct OverlayResultChannels: Hashable, Sendable {
  private(set) var scene: OverlayChannelResult?
  private(set) var workflow: [OperatorFrameMode: [WorkflowOverlayOwner: OverlayChannelResult]] = [:]
  private(set) var simulation: OverlayChannelResult?

  mutating func publishScene(_ result: OverlayChannelResult) {
    scene = result
  }

  mutating func publishWorkflow(
    _ result: OverlayChannelResult,
    source: OperatorFrameMode,
    owner: WorkflowOverlayOwner
  ) {
    workflow[source, default: [:]][owner] = result
  }

  mutating func clearWorkflow(source: OperatorFrameMode, owner: WorkflowOverlayOwner) {
    workflow[source]?[owner] = nil
  }

  mutating func clearWorkflow(source: OperatorFrameMode) {
    workflow[source] = nil
  }

  mutating func publishSimulation(_ result: OverlayChannelResult) {
    simulation = result
  }

  func workflowResults(for source: OperatorFrameMode) -> [OverlayChannelResult] {
    WorkflowOverlayOwner.allCases.compactMap { workflow[source]?[$0] }
  }
}

struct OverlayComposition: Hashable, Sendable {
  let overlays: [CameraOverlayMeasurement]
  let statuses: [UserSceneOverlay: OverlayLayerStatus]
  let analyzedFrame: ExactFrameOverlayProvenance?
}

enum OverlayStatusColorToken: String, CaseIterable, Hashable, Sendable {
  case affirmativeGreen
  case negativeRed
  case neutralGray
  case unavailableDarkGray
}

struct OverlayCardPresentation: Hashable, Identifiable, Sendable {
  let overlay: UserSceneOverlay
  let isOn: Bool
  let status: OverlayLayerStatus
  let colorToken: OverlayStatusColorToken
  let roiText: String
  let cadenceText: String
  let frameText: String
  let resultAgeText: String

  var id: UserSceneOverlay { overlay }
  var title: String { overlay.title }
  var selectionText: String { isOn ? "On" : "Off" }
  var statusText: String { status.message }
  var supportsMultilineText: Bool { true }
  var accessibilityLabel: String { "\(title) scene overlay" }
  var accessibilityValue: String {
    "\(selectionText). \(statusText) ROI: \(roiText). Cadence: \(cadenceText). Analyzed frame: \(frameText). Result age: \(resultAgeText)."
  }
  var helpText: String { accessibilityValue }

  init(
    overlay: UserSceneOverlay,
    isOn: Bool,
    status: OverlayLayerStatus,
    roiText: String,
    cadenceText: String,
    nowNanoseconds: UInt64
  ) {
    self.overlay = overlay
    self.isOn = isOn
    self.status = status
    self.roiText = roiText
    self.cadenceText = cadenceText
    colorToken = Self.colorToken(for: status.state)
    if let provenance = status.provenance {
      frameText = "Frame \(provenance.frameSequence) · \(provenance.frameID.rawValue)"
      resultAgeText =
        nowNanoseconds >= provenance.captureNanoseconds
        ? String(
          format: "%.2f s",
          Double(nowNanoseconds - provenance.captureNanoseconds) / 1_000_000_000
        )
        : "Clock mismatch"
    } else {
      frameText = "No exact analyzed frame"
      resultAgeText = "No result"
    }
  }

  private static func colorToken(for state: OverlayRunState) -> OverlayStatusColorToken {
    switch state {
    case .available:
      .affirmativeGreen
    case .unavailable, .ambiguous, .failed, .stale:
      .negativeRed
    case .waiting, .analyzing, .suspended:
      .neutralGray
    case .off:
      .unavailableDarkGray
    }
  }
}

struct OverlayPresentationComposer {
  static func compose(
    preference: OverlayPreferenceState,
    channels: OverlayResultChannels,
    displayedFrame: DisplayedFrame?,
    sceneState: PlotterSceneAnalysisSnapshot,
    sceneIsAvailable: Bool,
    workflowVisionIsExclusive: Bool
  ) -> OverlayComposition {
    var rendered: [CameraOverlayMeasurement] = []
    var statuses: [UserSceneOverlay: OverlayLayerStatus] = [:]

    let sourceMode: OperatorFrameMode? =
      switch displayedFrame?.source {
      case .live: .live
      case .simulated: .simulated
      case nil: nil
      }

    if let displayedFrame, let sourceMode {
      for workflow in channels.workflowResults(for: sourceMode)
      where workflow.provenance.matches(displayedFrame) {
        rendered.append(contentsOf: workflow.overlays)
      }
      if sourceMode == .simulated, let simulation = channels.simulation,
        simulation.provenance.matches(displayedFrame)
      {
        rendered.append(
          contentsOf: simulation.overlays.filter { measurement in
            preference.enabled.contains(where: { overlay in
              overlay.overlayKind == measurement.provenance.kind
            })
          })
      }
    }

    for overlay in UserSceneOverlay.allCases {
      guard preference.enabled.contains(overlay) else {
        statuses[overlay] = OverlayLayerStatus(state: .off, message: "Off", provenance: nil)
        continue
      }
      if workflowVisionIsExclusive, sourceMode == .live {
        statuses[overlay] = OverlayLayerStatus(
          state: .suspended,
          message: OverlayStatusGrammar.suspended,
          provenance: channels.scene?.provenance
        )
        continue
      }
      guard let displayedFrame else {
        statuses[overlay] = OverlayLayerStatus(
          state: .waiting, message: OverlayStatusGrammar.waiting, provenance: nil)
        continue
      }
      if case .simulated = displayedFrame.source {
        let simulation = channels.simulation
        guard let simulation else {
          statuses[overlay] = OverlayLayerStatus(
            state: .waiting, message: OverlayStatusGrammar.waiting, provenance: nil)
          continue
        }
        guard simulation.provenance.matches(displayedFrame) else {
          statuses[overlay] = OverlayLayerStatus(
            state: .stale, message: OverlayStatusGrammar.stale, provenance: simulation.provenance)
          continue
        }
        statuses[overlay] = simulation.statuses[overlay]
          ?? OverlayLayerStatus(
            state: .failed,
            message:
              "Failed — causal simulation omitted typed \(overlay.title) status for exact frame \(simulation.provenance.frameSequence).",
            provenance: simulation.provenance
          )
        continue
      }
      guard sceneIsAvailable else {
        statuses[overlay] = OverlayLayerStatus(
          state: .waiting,
          message: OverlayStatusGrammar.waiting,
          provenance: channels.scene?.provenance
        )
        continue
      }
      if let error = sceneState.lastError {
        statuses[overlay] = OverlayLayerStatus(
          state: .failed, message: "Failed — \(error)", provenance: channels.scene?.provenance)
        continue
      }
      if let active = sceneState.activeFrameSequence {
        let exactCompletedScene = channels.scene.flatMap { scene in
          scene.provenance.matches(displayedFrame) ? scene : nil
        }
        if let exactCompletedScene {
          rendered.append(
            contentsOf: exactCompletedScene.overlays.filter {
              $0.provenance.kind == overlay.overlayKind
            }
          )
          statuses[overlay] = exactCompletedScene.statuses[overlay]
            ?? OverlayLayerStatus(
              state: .failed,
              message:
                "Failed — measured Vision omitted typed \(overlay.title) status for exact frame \(exactCompletedScene.provenance.frameSequence).",
              provenance: exactCompletedScene.provenance
            )
          continue
        }
        statuses[overlay] = OverlayLayerStatus(
          state: .analyzing,
          message: OverlayStatusGrammar.analyzing(frame: active),
          provenance: channels.scene?.provenance
        )
        continue
      }
      guard let scene = channels.scene else {
        statuses[overlay] = OverlayLayerStatus(
          state: .waiting, message: OverlayStatusGrammar.waiting, provenance: nil)
        continue
      }
      guard scene.provenance.matches(displayedFrame) else {
        statuses[overlay] = OverlayLayerStatus(
          state: .stale, message: OverlayStatusGrammar.stale, provenance: scene.provenance)
        continue
      }
      let matching = scene.overlays.filter { $0.provenance.kind == overlay.overlayKind }
      rendered.append(contentsOf: matching)
      if let produced = scene.statuses[overlay] {
        statuses[overlay] = produced
      } else {
        statuses[overlay] = OverlayLayerStatus(
          state: .failed,
          message:
            "Failed — measured Vision omitted typed \(overlay.title) status for exact frame \(scene.provenance.frameSequence).",
          provenance: scene.provenance
        )
      }
    }

    return OverlayComposition(
      overlays: rendered,
      statuses: statuses,
      analyzedFrame: rendered.isEmpty ? nil : displayedFrame.map(ExactFrameOverlayProvenance.init)
    )
  }

}
