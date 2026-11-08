import Foundation
import PortraitCore
import Testing

@Suite("DX06 synthetic result admission")
struct DrawingLibraryResultFixtureTests {
  @Test("Fresh finite nonterminal chain admits its exact receipt, predecessors and media without native claims")
  func finiteChain() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("dx06-fixture-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryResultFixture()
    try fixture.write(to: root.appendingPathComponent("input"))
    try FileManager.default.createDirectory(at: root.appendingPathComponent("stage"), withIntermediateDirectories: true)
    let staged = try DrawingExchangeCarrier.stageDirectory(root.appendingPathComponent("input"), stagingParent: root.appendingPathComponent("stage"))
    let admitted = try ExchangeAdmission.validate(staged)
    #expect(admitted.integrityVerified)
    #expect(admitted.attempts.count == 3)
    #expect(Set(admitted.attempts.keys) == Set(fixture.snapshots))
    #expect(admitted.attempts.values.allSatisfy { !$0.sealed && $0.state == "running" && $0.drawing == fixture.frozen.reference && $0.job == fixture.job })
    #expect(try admitted.files.record(fixture.media.object) == fixture.payload["data/objects/sha256/" + fixture.media.object.description])
    #expect(!admitted.capabilities.supported.contains(.interpretResults))
    #expect(!admitted.capabilities.supported.contains(.physicalInterpretation))
    #expect(!admitted.capabilities.supported.contains(.train))
  }
}
