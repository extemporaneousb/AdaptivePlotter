import Foundation
import PortraitCore
import Testing
@testable import PortraitStudio

@Suite("Standalone Studio file boundaries")
struct PortraitStudioFileTests {
  @Test("Standalone default storage cannot select the AdaptivePlotter library")
  @MainActor
  func privateStorageRoot() {
    let expected = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/PortraitStudio/PortraitLibrary", isDirectory: true)
    #expect(PortraitStudioComposition.privateLibraryURL.standardizedFileURL == expected.standardizedFileURL)
    #expect(!PortraitStudioComposition.privateLibraryURL.pathComponents.contains("AdaptivePlotter"))
  }

  @Test("File reads accept the exact byte budget and refuse oversized or directory inputs")
  func boundedReads() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("drawing.json")
    let bytes = Data((0..<32).map(UInt8.init))
    try bytes.write(to: file)
    #expect(try PortraitStudioFiles.read(file, maximumBytes: bytes.count) == bytes)
    #expect(throws: DrawingTransferError.self) {
      _ = try PortraitStudioFiles.read(file, maximumBytes: bytes.count - 1)
    }
    #expect(throws: DrawingTransferError.self) {
      _ = try PortraitStudioFiles.read(directory, maximumBytes: 1024)
    }
    #expect(try Data(contentsOf: file) == bytes)
  }

  @Test("Export writes preserve exact supplied bytes through replacement")
  func exactWrites() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("drawing.json")
    try Data([9, 8, 7]).write(to: file)
    let payload = Data("{\"exact\":true}\n".utf8)
    try PortraitStudioFiles.write(payload, to: file)
    #expect(try Data(contentsOf: file) == payload)
  }
}
