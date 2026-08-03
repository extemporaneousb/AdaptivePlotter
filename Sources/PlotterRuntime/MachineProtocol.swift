import Foundation

public protocol MachineLink: Sendable {
  var descriptor: MachineLinkDescriptor { get }
  func open() async throws
  func close() async
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
