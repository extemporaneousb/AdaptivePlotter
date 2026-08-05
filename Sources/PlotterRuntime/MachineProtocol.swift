import Foundation
import PlotterModel

public protocol MachineLink: Sendable {
  var descriptor: MachineLinkDescriptor { get }
  func open() async throws
  func close() async
  func discardPendingInput() async throws
  func write(_ bytes: Data) async throws
  func read(maximumBytes: Int, timeoutNanoseconds: UInt64) async throws -> Data
}

public struct MachineLinkDescriptor: Codable, Hashable, Sendable {
  public let identifier: String
  public let displayName: String
  public let bsdPath: String?
  public let transport: Transport

  public enum Transport: String, Codable, Hashable, Sendable {
    case bsdSerial
    case simulated
    case transcriptReplay
  }

  public init(identifier: String, displayName: String, bsdPath: String?, transport: Transport) {
    self.identifier = identifier
    self.displayName = displayName
    self.bsdPath = bsdPath
    self.transport = transport
  }
}

public enum MachineLinkError: Error, Equatable, Sendable {
  case notOpen
  case alreadyOpen
  case timedOut
  case writeTimedOut(bytesWritten: Int, totalBytes: Int)
  case writeCancelled(bytesWritten: Int, totalBytes: Int)
  case readExceededMaximum(expected: Int, actual: Int)
  case disconnected
  case unexpectedWrite(expected: Data, actual: Data)
  case invalidPath(String)
  case operatingSystem(code: Int32, operation: String)
}

public struct RelativeJogRequest: Codable, Hashable, Sendable {
  public let delta: Vector2<MachineSpace>
  public let feedMMPerMinute: Double

  public init(delta: Vector2<MachineSpace>, feedMMPerMinute: Double) {
    self.delta = delta
    self.feedMMPerMinute = feedMMPerMinute
  }
}

public enum MotionLimitsError: Error, Equatable, Sendable {
  case invalidMaximumDistance
  case invalidMaximumFeed
}

public struct MotionLimits: Codable, Hashable, Sendable {
  public let bounds: AxisAlignedBounds<MachineSpace>
  public let maximumDistanceMM: Double
  public let maximumFeedMMPerMinute: Double

  public init(
    bounds: AxisAlignedBounds<MachineSpace>,
    maximumDistanceMM: Double,
    maximumFeedMMPerMinute: Double
  ) throws {
    guard maximumDistanceMM.isFinite, maximumDistanceMM > 0 else {
      throw MotionLimitsError.invalidMaximumDistance
    }
    guard maximumFeedMMPerMinute.isFinite, maximumFeedMMPerMinute > 0 else {
      throw MotionLimitsError.invalidMaximumFeed
    }
    self.bounds = bounds
    self.maximumDistanceMM = maximumDistanceMM
    self.maximumFeedMMPerMinute = maximumFeedMMPerMinute
  }
}

public struct MachinePosition: Codable, Hashable, Sendable {
  public let point: Point2<MachineSpace>

  public init(point: Point2<MachineSpace>) {
    self.point = point
  }

  public init(x: Double, y: Double) throws {
    point = try Point2(x: x, y: y)
  }
}

public enum PenState: String, Codable, Hashable, Sendable {
  case unknown
  case up
  case down
}

public enum ControllerState: String, Codable, Hashable, Sendable {
  case idle
  case run
  case hold
  case jog
  case alarm
  case door
  case check
  case home
  case sleep
  case tool
  case unknown

  public init(statusText: String) {
    let base = statusText.split(separator: ":", maxSplits: 1).first?.lowercased() ?? ""
    self = Self(rawValue: base) ?? .unknown
  }

  public var isRecognized: Bool { self != .unknown }
  public var isAlarm: Bool { self == .alarm }
}

public struct ControllerPins: Codable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public var xLimitAsserted: Bool { rawValue.uppercased().contains("X") }
  public var yLimitAsserted: Bool { rawValue.uppercased().contains("Y") }
  public var hasRelevantLimitAsserted: Bool { xLimitAsserted || yLimitAsserted }
}

public enum MotionRefusal: Codable, Hashable, Sendable {
  case noSerialDeviceSelected
  case notConnected
  case motionLimitsMissing
  case controllerStateUnknown
  case controllerNotIdle(ControllerState)
  case controllerAlarm(String)
  case relevantLimitAsserted(String)
  case machinePositionUnknown
  case nonFiniteDelta
  case zeroDelta
  case nonPositiveFeed(Double)
  case feedExceedsMaximum(requested: Double, maximum: Double)
  case distanceExceedsMaximum(requested: Double, maximum: Double)
  case destinationOutsideBounds(MachinePosition)
  case penNotUp(PenState)
  case operationInFlight
  case stickyAmbiguity(MotionAmbiguity)
  case controllerRejected(String)
  case freshStatusUnavailable(String)
}

public enum MotionAmbiguity: Codable, Hashable, Sendable {
  case partialWrite(bytesWritten: Int, totalBytes: Int)
  case writeTimedOut(bytesWritten: Int, totalBytes: Int)
  case writeCancelled(bytesWritten: Int, totalBytes: Int)
  case acceptanceTimedOut
  case completionTimedOut(deadlineNanoseconds: UInt64)
  case disconnected
  case malformedReply(String)
  case controllerAlarm(String)
  case controllerHold
  case unexpectedControllerState(ControllerState)
  case transport(String)
}

public enum MotionOutcome: Codable, Hashable, Sendable {
  case refused(MotionRefusal)
  case acceptedThenCompleted(finalPosition: MachinePosition)
  case ambiguous(MotionAmbiguity)
}

extension MotionRefusal {
  public var actionableDescription: String {
    switch self {
    case .noSerialDeviceSelected:
      return "Select one serial controller before moving."
    case .notConnected:
      return "Connect and run the passive controller probe before moving."
    case .motionLimitsMissing:
      return "Apply finite local bounds, maximum distance, and maximum feed before moving."
    case .controllerStateUnknown:
      return "Query the controller until its current state is known."
    case .controllerNotIdle(let state):
      return "Wait for controller Idle; current state is \(state.rawValue)."
    case .controllerAlarm(let detail):
      return "Controller alarm: \(detail). Clear it physically, then reconnect and probe."
    case .relevantLimitAsserted(let pins):
      return "A motion limit is asserted (Pn:\(pins)); inspect the machine before retrying."
    case .machinePositionUnknown:
      return "Probe the controller until a valid MPos is available."
    case .nonFiniteDelta:
      return "Enter finite X and Y move values."
    case .zeroDelta:
      return "Enter a nonzero X or Y move."
    case .nonPositiveFeed(let feed):
      return "Feed must be positive and finite; received \(feed)."
    case .feedExceedsMaximum(let requested, let maximum):
      return "Feed \(requested) mm/min exceeds the configured maximum \(maximum)."
    case .distanceExceedsMaximum(let requested, let maximum):
      return "Move distance \(requested) mm exceeds the configured maximum \(maximum)."
    case .destinationOutsideBounds(let destination):
      return "Destination (\(destination.point.x), \(destination.point.y)) is outside configured bounds."
    case .penNotUp:
      return "Confirm that the pen is physically up before moving."
    case .operationInFlight:
      return "Wait for the current controller operation to finish."
    case .stickyAmbiguity(let ambiguity):
      return "Motion is disabled after an ambiguous command: \(ambiguity.actionableDescription)"
    case .controllerRejected(let detail):
      return "Controller rejected the jog (\(detail)); correct the request and retry."
    case .freshStatusUnavailable(let detail):
      return "Fresh pre-move controller status was unavailable (\(detail)); reconnect and probe before retrying."
    }
  }
}

extension MotionAmbiguity {
  public var actionableDescription: String {
    switch self {
    case .partialWrite(let written, let total):
      return "Only \(written) of \(total) command bytes were written; inspect and reconnect."
    case .writeTimedOut(let written, let total):
      return "The write timed out after \(written) of \(total) bytes; inspect and reconnect."
    case .writeCancelled(let written, let total):
      return "The write was cancelled after \(written) of \(total) bytes; inspect and reconnect."
    case .acceptanceTimedOut:
      return "No bounded jog acknowledgement arrived; inspect and reconnect."
    case .completionTimedOut:
      return "The accepted jog did not reach a known Idle state before its deadline; inspect and reconnect."
    case .disconnected:
      return "The controller disconnected during a physical command; inspect and reconnect."
    case .malformedReply(let detail):
      return "The controller reply was not trustworthy (\(detail)); inspect and reconnect."
    case .controllerAlarm(let detail):
      return "The controller alarmed after transmission (\(detail)); inspect and reconnect."
    case .controllerHold:
      return "The controller entered Hold after accepting the jog; inspect before reconnecting."
    case .unexpectedControllerState(let state):
      return "The controller entered unexpected state \(state.rawValue); inspect and reconnect."
    case .transport(let detail):
      return "The transport failed after a physical command may have started (\(detail)); inspect and reconnect."
    }
  }
}

public struct MotionDiagnosticRecord: Codable, Hashable, Sendable {
  public let request: RelativeJogRequest
  public let outcome: MotionOutcome
  public let timestamp: RuntimeTimestamp

  public init(
    request: RelativeJogRequest,
    outcome: MotionOutcome,
    timestamp: RuntimeTimestamp
  ) {
    self.request = request
    self.outcome = outcome
    self.timestamp = timestamp
  }
}

public enum PassiveQuery: String, Codable, CaseIterable, Hashable, Sendable {
  case buildInfo
  case parserState
  case status
  case configuration
  case coordinateOffsets

  public var wireBytes: Data {
    switch self {
    case .buildInfo: Data("$I\n".utf8)
    case .parserState: Data("$G\n".utf8)
    case .status: Data("?".utf8)
    case .configuration: Data("$$\n".utf8)
    case .coordinateOffsets: Data("$#\n".utf8)
    }
  }

  var terminatesOnStatus: Bool { self == .status }
}

public enum MachineIODirection: String, Codable, Hashable, Sendable {
  case transmit
  case receive
}

public struct RawMachineIO: Codable, Hashable, Sendable {
  public let direction: MachineIODirection
  public let bytes: Data
  public let timestamp: RuntimeTimestamp

  public init(direction: MachineIODirection, bytes: Data, timestamp: RuntimeTimestamp) {
    self.direction = direction
    self.bytes = bytes
    self.timestamp = timestamp
  }
}

public struct PassiveProbeExchange: Codable, Hashable, Sendable {
  public let query: PassiveQuery
  public let commandID: UUID
  public let rawIO: [RawMachineIO]
  public let lines: [ParsedControllerLine]
  public let completed: Bool
  public let blocker: MachineBlocker?

  public init(
    query: PassiveQuery,
    commandID: UUID,
    rawIO: [RawMachineIO],
    lines: [ParsedControllerLine],
    completed: Bool,
    blocker: MachineBlocker?
  ) {
    self.query = query
    self.commandID = commandID
    self.rawIO = rawIO
    self.lines = lines
    self.completed = completed
    self.blocker = blocker
  }
}

public enum MachineBlocker: Codable, Hashable, Sendable {
  case noSerialDevice
  case multipleSerialDevices([MachineLinkDescriptor])
  case transport(String)
  case timeout(PassiveQuery)
  case invalidReply(PassiveQuery, reason: String)
  case responseLimitExceeded(PassiveQuery, maximumBytes: Int, maximumChunks: Int)
  case controllerAlarm(String)
  case controllerError(String)
}

public struct ParsedControllerRecord: Codable, Hashable, Sendable {
  public let text: String
  public let kind: ControllerLineKind

  public init(text: String, kind: ControllerLineKind) {
    self.text = text
    self.kind = kind
  }
}

public struct PassiveProbeExchangeRecord: Codable, Hashable, Sendable {
  public let query: PassiveQuery
  public let commandID: UUID
  public let parsedLines: [ParsedControllerRecord]
  public let completed: Bool
  public let blocker: MachineBlocker?

  public init(exchange: PassiveProbeExchange) {
    query = exchange.query
    commandID = exchange.commandID
    parsedLines = exchange.lines.map { ParsedControllerRecord(text: $0.text, kind: $0.kind) }
    completed = exchange.completed
    blocker = exchange.blocker
  }
}

public struct PassiveProbeStartedRecord: Codable, Hashable, Sendable {
  public let probeID: UUID
  public let link: MachineLinkDescriptor
  public let startedAt: RuntimeTimestamp
  public let queries: [PassiveQuery]

  public init(
    probeID: UUID,
    link: MachineLinkDescriptor,
    startedAt: RuntimeTimestamp,
    queries: [PassiveQuery]
  ) {
    self.probeID = probeID
    self.link = link
    self.startedAt = startedAt
    self.queries = queries
  }
}

public struct PassiveProbeFinishedRecord: Codable, Hashable, Sendable {
  public let probeID: UUID
  public let link: MachineLinkDescriptor
  public let startedAt: RuntimeTimestamp
  public let completedAt: RuntimeTimestamp
  public let exchanges: [PassiveProbeExchangeRecord]
  public let blockers: [MachineBlocker]

  public init(probeID: UUID, result: PassiveProbeResult) {
    self.probeID = probeID
    link = result.link
    startedAt = result.startedAt
    completedAt = result.completedAt
    exchanges = result.exchanges.map(PassiveProbeExchangeRecord.init)
    blockers = result.blockers
  }
}

public struct PassiveProbeResult: Codable, Hashable, Sendable {
  public let link: MachineLinkDescriptor
  public let startedAt: RuntimeTimestamp
  public let completedAt: RuntimeTimestamp
  public let exchanges: [PassiveProbeExchange]
  public let blockers: [MachineBlocker]

  public init(
    link: MachineLinkDescriptor,
    startedAt: RuntimeTimestamp,
    completedAt: RuntimeTimestamp,
    exchanges: [PassiveProbeExchange],
    blockers: [MachineBlocker]
  ) {
    self.link = link
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.exchanges = exchanges
    self.blockers = blockers
  }
}
