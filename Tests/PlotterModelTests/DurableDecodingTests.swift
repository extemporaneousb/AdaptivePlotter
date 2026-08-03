import Foundation
import Testing

@testable import PlotterModel

private func decodeFails<T: Decodable>(_ type: T.Type, from data: Data) -> Bool {
  do {
    _ = try JSONDecoder().decode(type, from: data)
    return false
  } catch {
    return true
  }
}

@Suite("Value decoding")
struct DurableDecodingTests {
  @Test("Digest rejects a non-SHA-256 byte count")
  func digestLength() {
    let malicious = Data(#"{"bytes":[1,2,3]}"#.utf8)
    #expect(decodeFails(Digest.self, from: malicious))
  }
}
