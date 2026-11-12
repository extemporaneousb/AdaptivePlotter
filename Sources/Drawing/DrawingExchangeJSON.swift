import Foundation

/// Strict bounded JSON preflight before Foundation decoding. Original bytes are never normalized.
public enum ExchangeJSON {
  public static let maximumRecordBytes = 8 * 1024 * 1024
  public static func validate(_ bytes: Data, maximumBytes: Int = maximumRecordBytes) throws -> [String: Any] {
    guard !bytes.isEmpty, bytes.count <= maximumBytes else { throw DrawingExchangeError.limit("Record bytes") }
    guard String(data: bytes, encoding: .utf8) != nil, !bytes.starts(with: [0xef, 0xbb, 0xbf]) else {
      throw DrawingExchangeError.malformed("Expected UTF-8 without BOM")
    }
    var parser = Scanner(bytes: Array(bytes)); try parser.value(depth: 0); parser.space()
    guard parser.index == parser.bytes.count,
      let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
      throw DrawingExchangeError.malformed("Expected JSON object")
    }
    return object
  }
  private struct Scanner {
    let bytes: [UInt8]
    var index = 0
    mutating func space() { while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
    mutating func take(_ byte: UInt8) -> Bool { space(); if index < bytes.count && bytes[index] == byte { index += 1; return true }; return false }
    mutating func string() throws -> String {
      space(); let start = index
      guard take(34) else { throw DrawingExchangeError.malformed("Expected JSON string") }
      var escaped = false
      while index < bytes.count {
        let b = bytes[index]; index += 1
        if b < 32 { throw DrawingExchangeError.malformed("JSON control character") }
        if escaped { escaped = false; continue }
        if b == 92 { escaped = true; continue }
        if b == 34 {
          let data = Data(bytes[start..<index])
          guard let value = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String else { throw DrawingExchangeError.malformed("Invalid JSON string") }
          return value
        }
      }
      throw DrawingExchangeError.malformed("Unterminated JSON string")
    }
    mutating func value(depth: Int) throws {
      guard depth <= 64 else { throw DrawingExchangeError.limit("JSON depth") }; space()
      guard index < bytes.count else { throw DrawingExchangeError.malformed("Truncated JSON") }
      switch bytes[index] {
      case 123:
        index += 1; if take(125) { return }; var keys = Set<String>()
        repeat {
          let key = try string()
          guard keys.insert(key).inserted else { throw DrawingExchangeError.malformed("Duplicate JSON key: \(key)") }
          guard take(58) else { throw DrawingExchangeError.malformed("Expected colon") }
          try value(depth: depth + 1)
          if take(125) { return }
          guard take(44) else { throw DrawingExchangeError.malformed("Expected comma") }
        } while true
      case 91:
        index += 1; if take(93) { return }
        repeat {
          try value(depth: depth + 1); if take(93) { return }
          guard take(44) else { throw DrawingExchangeError.malformed("Expected comma") }
        } while true
      case 34: _ = try string()
      default:
        let start = index
        while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
        let token = String(decoding: bytes[start..<index], as: UTF8.self)
        if ["true", "false", "null"].contains(token) { return }
        guard !token.isEmpty, let number = Double(token), number.isFinite else {
          throw DrawingExchangeError.malformed("Invalid or nonfinite JSON number")
        }
      }
    }
  }
}

/// RFC 3339 permits fractional seconds; Foundation's default ISO formatter does not.
func exchangeDate(_ text: String) -> Date? {
  guard text.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt][0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?(?:[Zz]|[+-][0-9]{2}:[0-9]{2})$"#, options: .regularExpression) != nil else { return nil }
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  if let date = formatter.date(from: text) { return date }
  formatter.formatOptions = [.withInternetDateTime]
  return formatter.date(from: text)
}

func exchangeNamespacedID(_ value: String) -> Bool {
  value.range(of: #"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)+(?:[/:][A-Za-z0-9._/-]+)?$"#, options: .regularExpression) != nil
}
func exchangeMIMEType(_ value: String) -> Bool {
  value.range(of: #"^[^\s/]+/[^\s/]+$"#, options: .regularExpression) != nil
}
