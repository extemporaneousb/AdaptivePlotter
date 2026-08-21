import Foundation
import Testing

@testable import PlotterApp

@Suite("Machine-session diagnostic retention")
struct MachineSessionRetentionPolicyTests {
  @Test("retention keeps only the newest complete session groups within count")
  func countBoundKeepsNewestGroups() throws {
    let fixture = try RetentionFixture()
    defer { fixture.remove() }
    try fixture.writeSession("old", bytes: 4, modifiedAt: Date(timeIntervalSince1970: 1))
    try fixture.writeSession("middle", bytes: 4, modifiedAt: Date(timeIntervalSince1970: 2))
    try fixture.writeSession(
      "new",
      bytes: 4,
      sidecarBytes: 2,
      modifiedAt: Date(timeIntervalSince1970: 3)
    )
    try Data("preserve".utf8).write(to: fixture.root.appendingPathComponent("operator-note.json"))

    let policy = MachineSessionRetentionPolicy(
      maximumSessionCount: 2,
      maximumTotalBytes: 1_000
    )
    try policy.enforce(in: fixture.root)

    #expect(!fixture.exists("session-old.sqlite"))
    #expect(fixture.exists("session-middle.sqlite"))
    #expect(fixture.exists("session-new.sqlite"))
    #expect(fixture.exists("session-new.sqlite-wal"))
    #expect(fixture.exists("operator-note.json"))
  }

  @Test("retention applies its byte cap to whole SQLite session groups")
  func byteBoundRemovesWholeGroups() throws {
    let fixture = try RetentionFixture()
    defer { fixture.remove() }
    try fixture.writeSession("old", bytes: 6, modifiedAt: Date(timeIntervalSince1970: 1))
    try fixture.writeSession(
      "new",
      bytes: 6,
      sidecarBytes: 3,
      modifiedAt: Date(timeIntervalSince1970: 2)
    )

    let policy = MachineSessionRetentionPolicy(
      maximumSessionCount: 10,
      maximumTotalBytes: 9
    )
    let removals = try policy.urlsToRemove(in: fixture.root).map(\.lastPathComponent)

    #expect(removals == ["session-old.sqlite"])
  }
}

private struct RetentionFixture {
  let root: URL

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "AdaptivePlotter-machine-session-retention-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  func writeSession(
    _ id: String,
    bytes: Int,
    sidecarBytes: Int = 0,
    modifiedAt: Date
  ) throws {
    let database = root.appendingPathComponent("session-\(id).sqlite")
    try Data(repeating: 1, count: bytes).write(to: database)
    try FileManager.default.setAttributes(
      [.modificationDate: modifiedAt],
      ofItemAtPath: database.path
    )
    if sidecarBytes > 0 {
      let sidecar = root.appendingPathComponent("session-\(id).sqlite-wal")
      try Data(repeating: 2, count: sidecarBytes).write(to: sidecar)
      try FileManager.default.setAttributes(
        [.modificationDate: modifiedAt],
        ofItemAtPath: sidecar.path
      )
    }
  }

  func exists(_ filename: String) -> Bool {
    FileManager.default.fileExists(atPath: root.appendingPathComponent(filename).path)
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }
}
