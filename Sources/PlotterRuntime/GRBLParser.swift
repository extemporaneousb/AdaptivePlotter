import Foundation

public struct ControllerField: Codable, Hashable, Sendable {
  public let name: String
  public let value: String

  public init(name: String, value: String) {
    self.name = name
    self.value = value
  }
}

public struct ControllerStatusReport: Codable, Hashable, Sendable {
  public let state: String
  public let fields: [ControllerField]
  public let pins: String?

  public init(state: String, fields: [ControllerField], pins: String?) {
    self.state = state
    self.fields = fields
    self.pins = pins
  }
}

public enum ControllerLineKind: Codable, Hashable, Sendable {
  case acknowledgement
  case error(code: String)
  case alarm(code: String)
  case status(ControllerStatusReport)
  case configuration(key: String, value: String)
  case bracketReport(name: String?, value: String)
  case greeting
  case message
  case unknown
}

public struct ParsedControllerLine: Codable, Hashable, Sendable {
  public let rawBytes: Data
  public let text: String
  public let kind: ControllerLineKind

  public init(rawBytes: Data, text: String, kind: ControllerLineKind) {
    self.rawBytes = Data(rawBytes)
    self.text = text
    self.kind = kind
  }
}

public struct GRBLParser: Sendable {
  private var bufferedBytes = Data()

  public init() {}

  public mutating func consume(_ bytes: Data) -> [ParsedControllerLine] {
    bufferedBytes.append(bytes)
    var lines: [ParsedControllerLine] = []

    while let newline = bufferedBytes.firstIndex(of: 0x0A) {
      var raw = Data(bufferedBytes[..<newline])
      bufferedBytes.removeSubrange(...newline)
      if raw.last == 0x0D { raw.removeLast() }
      guard !raw.isEmpty else { continue }
      lines.append(Self.parseLine(raw))
    }
    return lines
  }

  public mutating func finishUnterminatedLine() -> ParsedControllerLine? {
    guard !bufferedBytes.isEmpty else { return nil }
    let raw = bufferedBytes
    bufferedBytes.removeAll(keepingCapacity: true)
    return Self.parseLine(raw)
  }

  public static func parseLine(_ rawBytes: Data) -> ParsedControllerLine {
    let text = String(decoding: rawBytes, as: UTF8.self)
    return ParsedControllerLine(rawBytes: rawBytes, text: text, kind: classify(text))
  }

  private static func classify(_ text: String) -> ControllerLineKind {
    if text == "ok" { return .acknowledgement }
    if text.hasPrefix("error:") {
      return .error(code: String(text.dropFirst("error:".count)))
    }
    if text.hasPrefix("ALARM:") {
      return .alarm(code: String(text.dropFirst("ALARM:".count)))
    }
    if text.first == "<", text.last == ">" {
      return .status(parseStatus(String(text.dropFirst().dropLast())))
    }
    if text.first == "[", text.last == "]" {
      let body = String(text.dropFirst().dropLast())
      if let separator = body.firstIndex(of: ":") {
        return .bracketReport(
          name: String(body[..<separator]),
          value: String(body[body.index(after: separator)...])
        )
      }
      return .bracketReport(name: nil, value: body)
    }
    if text.first == "$", let separator = text.firstIndex(of: "=") {
      return .configuration(
        key: String(text[..<separator]),
        value: String(text[text.index(after: separator)...])
      )
    }
    if text.localizedCaseInsensitiveContains("grbl") { return .greeting }
    if text.first == "[" || text.first == "<" || text.first == "$" { return .message }
    return .unknown
  }

  private static func parseStatus(_ body: String) -> ControllerStatusReport {
    let components = body.split(separator: "|", omittingEmptySubsequences: false)
    let state = components.first.map(String.init) ?? ""
    var fields: [ControllerField] = []
    var pins: String?
    for component in components.dropFirst() {
      let value = String(component)
      if let separator = value.firstIndex(of: ":") {
        let name = String(value[..<separator])
        let fieldValue = String(value[value.index(after: separator)...])
        fields.append(ControllerField(name: name, value: fieldValue))
        if name == "Pn" { pins = fieldValue }
      } else {
        fields.append(ControllerField(name: value, value: ""))
      }
    }
    return ControllerStatusReport(state: state, fields: fields, pins: pins)
  }
}
