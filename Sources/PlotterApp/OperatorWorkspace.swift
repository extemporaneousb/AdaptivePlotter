import Foundation
import Observation
import PlotterModel
import PlotterRuntime

enum WorkspaceSelection: Hashable {
  case device(String)
  case stroke(StrokeID)
}

enum CanvasLayer: String, CaseIterable, Identifiable {
  case logical = "Logical"
  case predicted = "Predicted"
  case observed = "Simulated observed"
  case residuals = "Residuals"

  var id: Self { self }
}

struct PassiveProbeRunReceipt: Sendable {
  let probe: PassiveProbeResult
  let ledgerURL: URL?
}

@MainActor
@Observable
final class OperatorWorkspace {
  typealias PassiveProbeRunner = @Sendable (MachineLinkDescriptor) async throws ->
    PassiveProbeRunReceipt

  var selection: WorkspaceSelection?
  var visibleLayers = Set(CanvasLayer.allCases)

  private(set) var program: DrawingProgram
  private(set) var correspondence: CorrespondedGeometry
  private(set) var serialDevices: [MachineLinkDescriptor] = []
  private(set) var selectedSerialDevice: MachineLinkDescriptor?
  private(set) var passiveProbeReceipt: PassiveProbeRunReceipt?
  private(set) var passiveProbeFailure: String?
  private(set) var passiveProbeInProgress = false

  private let passiveProbeRunner: PassiveProbeRunner?

  init(
    prototype: DeterministicOfflinePrototype = .standard,
    passiveProbeRunner: PassiveProbeRunner? = nil,
    serialDevices: [MachineLinkDescriptor] = []
  ) {
    self.passiveProbeRunner = passiveProbeRunner
    program = prototype.program
    correspondence = prototype.correspondence
    self.serialDevices = serialDevices
  }

  var passiveProbeResult: PassiveProbeResult? { passiveProbeReceipt?.probe }

  var passiveProbeUnavailableReason: String? {
    if passiveProbeInProgress {
      return "A passive probe is already in progress."
    }
    if passiveProbeRunner == nil {
      return "Native passive-probe composition is unavailable in this build."
    }
    if selectedSerialDevice == nil {
      return "Select one serial device before requesting the passive probe."
    }
    return nil
  }

  func setLayer(_ layer: CanvasLayer, visible: Bool) {
    if visible {
      visibleLayers.insert(layer)
    } else {
      visibleLayers.remove(layer)
    }
  }

  func refreshSerialDevices() {
    guard !passiveProbeInProgress else { return }
    serialDevices = SerialPortDiscovery.discover()
    if let selectedSerialDevice,
      !serialDevices.contains(where: { $0.identifier == selectedSerialDevice.identifier })
    {
      self.selectedSerialDevice = nil
      if case .device = selection { selection = nil }
    }
  }

  func selectSerialDevice(_ descriptor: MachineLinkDescriptor) {
    guard !passiveProbeInProgress else { return }
    guard serialDevices.contains(where: { $0.identifier == descriptor.identifier }) else { return }
    selectedSerialDevice = descriptor
    selection = .device(descriptor.identifier)
    passiveProbeReceipt = nil
    passiveProbeFailure = nil
  }

  func requestPassiveProbe() async {
    guard !passiveProbeInProgress else { return }
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
    passiveProbeInProgress = true
    defer { passiveProbeInProgress = false }
    do {
      let receipt = try await passiveProbeRunner(descriptor)
      passiveProbeReceipt = receipt
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

/// Static simulated geometry used only to exercise preview rendering while the
/// live camera and drawing path are under construction.
struct DeterministicOfflinePrototype {
  let program: DrawingProgram
  let correspondence: CorrespondedGeometry

  static let standard: Self = {
    do {
      let programID = ProgramID(uuid("00000000-0000-0000-0000-000000000102"))
      let strokeID = StrokeID(uuid("00000000-0000-0000-0000-000000000103"))
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
      return Self(
        program: program,
        correspondence: try CorrespondedGeometry(
          intended: logical,
          predicted: predicted,
          observed: observed
        )
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
