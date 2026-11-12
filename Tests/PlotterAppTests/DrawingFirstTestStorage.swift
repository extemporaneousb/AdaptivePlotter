import DrawingLibrary
import Foundation
import PortraitCore
import PlotterModel
import PortraitStudioUI
@testable import PlotterApp

/// Every application test owner is injected before startup can open a catalog.
/// The root exists only beneath the process temporary directory, never App Support.
@MainActor
enum DrawingFirstTestStorage {
  private static let root: URL = {
    let value = FileManager.default.temporaryDirectory
      .appendingPathComponent("drawing-first-test-process-" + UUID().uuidString, isDirectory: true)
    FileHandle.standardError.write(Data(("DRAWING_FIRST_TEST_ROOT=" + value.path + "\n").utf8))
    return value
  }()
  static func library() -> DrawingLibrary {
    DrawingLibrary(directoryURL: root.appendingPathComponent(UUID().uuidString, isDirectory: true))
  }
  static func studio() -> PortraitStudioModel { PortraitStudioModel(library: library()) }
  static func received() -> ReceivedDrawingStore { ReceivedDrawingStore(library: library()) }
}

func drawingTestValue(program: DrawingProgram) throws -> Drawing {
  let receipt = try DrawingProducerReceipt(id: "example.physical-fixture", version: "1",
    recordJSON: Data("{\"meaning\":\"synthetic geometry fixture\"}".utf8))
  return try Drawing(program: program,
    input: .unavailable(reason: "Synthetic geometry fixture does not model a source image", knownRef: nil),
    parent: .none, producer: receipt)
}
