import Foundation
import Observation
import PlotterModel
import PlotterRuntime

enum WorkspaceSelection: Hashable {
  case device(String)
  case event(UInt64)
  case stroke(StrokeID)
}

enum WorkspacePane: String, CaseIterable, Identifiable {
  case devices = "Devices"
  case facts = "Execution Facts"
  case timeline = "Timeline"

  var id: Self { self }
}

enum CanvasLayer: String, CaseIterable, Identifiable {
  case logical = "Logical"
  case predicted = "Predicted"
  case observed = "Simulated observed"
  case residuals = "Residuals"

  var id: Self { self }
}

enum SimulatorUITaskState: Equatable {
  case idle
  case running
  case complete(sequence: UInt64)
  case failed(String)
}

struct PassiveProbeRunReceipt: Sendable {
  let probe: PassiveProbeResult
  /// Interpreter-owned authority at probe completion. The one-shot
  /// composition disconnects immediately after capturing this receipt.
  let completionAuthority: RuntimeAuthoritySnapshot
  let ledgerURL: URL
}

@MainActor
@Observable
final class OperatorWorkspace {
  typealias PassiveProbeRunner = @Sendable (MachineLinkDescriptor) async throws ->
    PassiveProbeRunReceipt

  var selection: WorkspaceSelection?
  var visiblePanes = Set(WorkspacePane.allCases)
  var visibleLayers = Set(CanvasLayer.allCases)
  private(set) var simulatorTaskState: SimulatorUITaskState = .idle

  private(set) var program: DrawingProgram
  private(set) var correspondence: CorrespondedGeometry
  private(set) var replayEvents: [SequencedRunEvent]
  private(set) var replayState: RecordedRunState
  private(set) var serialDevices: [MachineLinkDescriptor] = []
  private(set) var selectedSerialDevice: MachineLinkDescriptor?
  private(set) var passiveProbeReceipt: PassiveProbeRunReceipt?
  private(set) var passiveProbeFailure: String?
  private(set) var passiveProbeInProgress = false
  private(set) var passiveProbeAttempted = false

  private let prototype: DeterministicOfflinePrototype
  private let passiveProbeRunner: PassiveProbeRunner?

  init(
    prototype: DeterministicOfflinePrototype = .standard,
    passiveProbeRunner: PassiveProbeRunner? = nil,
    serialDevices: [MachineLinkDescriptor] = []
  ) {
    self.prototype = prototype
    self.passiveProbeRunner = passiveProbeRunner
    program = prototype.program
    correspondence = prototype.correspondence
    replayEvents = prototype.events
    replayState = prototype.initialReplayState
    self.serialDevices = serialDevices
  }

  var authority: ExecutionAuthority { replayState.authority }
  var frontiers: ExecutionFrontiers { replayState.frontiers }
  var passiveProbeResult: PassiveProbeResult? { passiveProbeReceipt?.probe }
  var passiveProbeAuthority: RuntimeAuthoritySnapshot? { passiveProbeReceipt?.completionAuthority }

  var passiveProbeUnavailableReason: String? {
    if passiveProbeInProgress {
      return "A passive probe is already in progress."
    }
    if passiveProbeAttempted {
      return "This one-shot session is complete. Restart the app before another powered attempt."
    }
    if passiveProbeRunner == nil {
      return "Native passive-probe composition is unavailable in this build."
    }
    if selectedSerialDevice == nil {
      return "Select one serial device before requesting the passive probe."
    }
    return nil
  }

  func setPane(_ pane: WorkspacePane, visible: Bool) {
    if visible {
      visiblePanes.insert(pane)
    } else {
      visiblePanes.remove(pane)
    }
  }

  func setLayer(_ layer: CanvasLayer, visible: Bool) {
    if visible {
      visibleLayers.insert(layer)
    } else {
      visibleLayers.remove(layer)
    }
  }

  func runOfflinePrototype() async {
    simulatorTaskState = .running
    await Task.yield()
    do {
      let replayed = try RecordedRunReducer.replay(prototype.events)
      program = prototype.program
      correspondence = prototype.correspondence
      replayEvents = prototype.events
      replayState = replayed
      simulatorTaskState = .complete(sequence: replayed.lastSequence)
    } catch {
      simulatorTaskState = .failed(String(describing: error))
    }
  }

  func refreshSerialDevices() {
    guard !passiveProbeInProgress, !passiveProbeAttempted else { return }
    serialDevices = SerialPortDiscovery.discover()
    if let selectedSerialDevice,
      !serialDevices.contains(where: { $0.identifier == selectedSerialDevice.identifier })
    {
      self.selectedSerialDevice = nil
      if case .device = selection { selection = nil }
    }
  }

  func selectSerialDevice(_ descriptor: MachineLinkDescriptor) {
    guard !passiveProbeInProgress, !passiveProbeAttempted else { return }
    guard serialDevices.contains(where: { $0.identifier == descriptor.identifier }) else { return }
    selectedSerialDevice = descriptor
    selection = .device(descriptor.identifier)
    passiveProbeReceipt = nil
    passiveProbeFailure = nil
  }

  func requestPassiveProbe() async {
    guard !passiveProbeInProgress, !passiveProbeAttempted else { return }
    guard let descriptor = selectedSerialDevice else {
      passiveProbeFailure = "Select one serial device before requesting the passive probe."
      return
    }
    guard let passiveProbeRunner else {
      passiveProbeFailure = "Native passive-probe composition is unavailable in this build."
      return
    }
    passiveProbeFailure = nil
    passiveProbeReceipt = nil
    passiveProbeAttempted = true
    passiveProbeInProgress = true
    defer { passiveProbeInProgress = false }
    do {
      passiveProbeReceipt = try await passiveProbeRunner(descriptor)
    } catch {
      if let localized = error as? LocalizedError,
        let description = localized.errorDescription
      {
        passiveProbeFailure = description
      } else {
        passiveProbeFailure = String(describing: error)
      }
    }
  }
}

/// A deterministic recorded-decision replay used to exercise the operator
/// projection without hardware. Its geometry and frontiers are simulated facts,
/// never physical evidence or drawing authority.
struct DeterministicOfflinePrototype {
  let program: DrawingProgram
  let correspondence: CorrespondedGeometry
  let events: [SequencedRunEvent]
  let initialReplayState: RecordedRunState

  static let standard: Self = {
    do {
      let runID = RunID(uuid("00000000-0000-0000-0000-000000000101"))
      let programID = ProgramID(uuid("00000000-0000-0000-0000-000000000102"))
      let strokeID = StrokeID(uuid("00000000-0000-0000-0000-000000000103"))
      let sliceID = StrokeSliceID(uuid("00000000-0000-0000-0000-000000000104"))
      let planID = PlanID(uuid("00000000-0000-0000-0000-000000000105"))
      let modelID = ModelID(uuid("00000000-0000-0000-0000-000000000106"))
      let stateID = StateEstimateID(uuid("00000000-0000-0000-0000-000000000107"))
      let safetyID = SafetyPolicyID(uuid("00000000-0000-0000-0000-000000000108"))
      let penID = PenProfileID(uuid("00000000-0000-0000-0000-000000000109"))

      let logical = try Polyline<FieldSpace>(points: [
        try Point2(x: 18, y: 25),
        try Point2(x: 72, y: 82),
        try Point2(x: 146, y: 42),
        try Point2(x: 182, y: 92),
      ])
      let predicted = try Polyline<FieldSpace>(points: [
        try Point2(x: 20, y: 24),
        try Point2(x: 74, y: 80),
        try Point2(x: 148, y: 41),
        try Point2(x: 184, y: 90),
      ])
      let observed = try Polyline<FieldSpace>(points: [
        try Point2(x: 21, y: 26),
        try Point2(x: 76, y: 79),
        try Point2(x: 149, y: 44),
        try Point2(x: 183, y: 93),
      ])
      let program = try DrawingProgram(
        id: programID,
        fieldExtent: try Size2(width: 200, height: 120),
        strokes: [
          LogicalStroke(
            id: strokeID,
            path: logical,
            style: try StrokeStyle(nominalLineWidth: 1.2, penProfileID: penID),
            semanticRole: .trainingProbe,
            ordering: 0
          )
        ],
        source: try DrawingSourceProvenance(
          kind: "deterministic-offline-prototype",
          sourceIdentifier: "built-in-v1"
        )
      )
      let correspondence = try CorrespondedGeometry(
        intended: logical,
        predicted: predicted,
        observed: observed
      )
      let blocker = try RunBlocker(
        code: "offline_simulation_only",
        summary: "Simulated geometry is not physical ink evidence."
      )
      let authority = try ExecutionAuthority(
        allowed: false,
        operation: nil,
        planID: planID,
        modelID: modelID,
        stateEstimateID: stateID,
        fixedSafetyPolicyID: safetyID,
        evidence: [],
        limits: try AuthorityLimits(
          maximumFeed: 0,
          maximumDistance: 0,
          maximumCommandHorizonNanoseconds: 0
        ),
        blockers: [blocker]
      )
      let emptyFrontiers = try ExecutionFrontiers(
        planID: planID,
        commandedThrough: nil,
        controllerCompletedThrough: nil,
        inkBySlice: [:]
      )
      let drawCursor = PlanCursor(planID: planID, instructionIndex: 2)
      let commandedFrontiers = try ExecutionFrontiers(
        planID: planID,
        commandedThrough: drawCursor,
        controllerCompletedThrough: nil,
        inkBySlice: [:]
      )
      let ambiguousFrontiers = try ExecutionFrontiers(
        planID: planID,
        commandedThrough: drawCursor,
        controllerCompletedThrough: drawCursor,
        inkBySlice: [
          sliceID: SliceExecutionFact(
            drawCursor: drawCursor,
            disposition: .ambiguous(
              reasons: ["Offline simulation cannot verify physical ink."]
            )
          )
        ]
      )
      let events = [
        SequencedRunEvent(
          runID: runID,
          sequence: 0,
          event: .runStarted(
            programID: programID,
            planID: planID,
            modelID: modelID,
            authority: authority,
            frontiers: emptyFrontiers
          )
        ),
        SequencedRunEvent(
          runID: runID,
          sequence: 1,
          event: .instructionAdvanced(drawCursor)
        ),
        SequencedRunEvent(
          runID: runID,
          sequence: 2,
          event: .frontiersChanged(commandedFrontiers)
        ),
        SequencedRunEvent(
          runID: runID,
          sequence: 3,
          event: .frontiersChanged(ambiguousFrontiers)
        ),
        SequencedRunEvent(
          runID: runID,
          sequence: 4,
          event: .paused([blocker])
        ),
      ]
      return Self(
        program: program,
        correspondence: correspondence,
        events: events,
        initialReplayState: try RecordedRunReducer.replay([events[0]])
      )
    } catch {
      preconditionFailure("Invalid built-in offline prototype: \(error)")
    }
  }()

  private static func uuid(_ value: String) -> UUID {
    guard let value = UUID(uuidString: value) else {
      preconditionFailure("Invalid deterministic UUID")
    }
    return value
  }
}
