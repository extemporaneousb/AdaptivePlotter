import Darwin
import Dispatch
import Foundation
import Testing

@Suite("Drawing value module dependency contract")
struct DrawingDependencyContractTests {
  @Test("The exported Drawing contract and artist dependency closure exclude machine runtime")
  func coreDependencyGraph() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let outputURL = temporary.appendingPathComponent("manifest.json")
    let errorsURL = temporary.appendingPathComponent("diagnostics.txt")
    #expect(FileManager.default.createFile(atPath: outputURL.path, contents: nil))
    #expect(FileManager.default.createFile(atPath: errorsURL.path, contents: nil))
    let output = try FileHandle(forWritingTo: outputURL), errors = try FileHandle(forWritingTo: errorsURL)
    defer { try? output.close(); try? errors.close() }
    let process = Process(), completed = DispatchSemaphore(value: 0)
    process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
    process.arguments = ["package", "--package-path", root.path,
      "--scratch-path", temporary.appendingPathComponent("scratch").path, "dump-package"]
    process.standardOutput = output; process.standardError = errors
    process.terminationHandler = { _ in completed.signal() }
    try process.run()
    defer { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
    let finished = completed.wait(timeout: .now() + 30)
    if finished == .timedOut {
      process.terminate()
      if completed.wait(timeout: .now() + 5) == .timedOut {
        kill(process.processIdentifier, SIGKILL)
        _ = completed.wait(timeout: .now() + 5)
      }
    }
    try #require(finished == .success, "SwiftPM manifest evaluation exceeded 30 seconds")
    let bytes = try Data(contentsOf: outputURL)
    let diagnostics = try Data(contentsOf: errorsURL)
    try #require(process.terminationStatus == 0,
      "SwiftPM manifest evaluation: \(String(decoding: diagnostics.suffix(4096), as: UTF8.self))")
    let manifest = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    let targets = try #require(manifest["targets"] as? [[String: Any]])
    var graph: [String: [String]] = [:]
    for target in targets {
      let name = try #require(target["name"] as? String)
      let dependencies = try #require(target["dependencies"] as? [[String: Any]])
      graph[name] = try dependencies.map { dependency in
        let encoded = try #require((dependency["byName"] ?? dependency["target"] ?? dependency["product"]) as? [Any])
        return try #require(encoded.first as? String)
      }
    }
    func closure(of root: String) -> Set<String> {
      var visited = Set<String>(), pending = [root]
      while let target = pending.popLast() {
        guard visited.insert(target).inserted else { continue }
        pending.append(contentsOf: graph[target] ?? [])
      }
      return visited
    }
    let products = try #require(manifest["products"] as? [[String: Any]])
    let drawingProduct = try #require(products.first { $0["name"] as? String == "Drawing" })
    #expect(drawingProduct["targets"] as? [String] == ["Drawing"])
    #expect(graph["Drawing"] == ["PlotterModel"])
    #expect(closure(of: "Drawing") == ["Drawing", "PlotterModel"])
    #expect(graph["PortraitCore"] == ["Drawing"])
    #expect(closure(of: "PortraitCore") == ["PortraitCore", "Drawing", "PlotterModel"])
    #expect(Set(graph["DrawingLibrary"] ?? []) == ["PortraitCore", "PlotterModel", "CSQLite"])
    #expect(closure(of: "DrawingLibrary") == ["DrawingLibrary", "PortraitCore", "Drawing", "PlotterModel", "CSQLite"])
    let artistClosure = closure(of: "PortraitArtists")
    #expect(artistClosure.contains("Drawing"))
    #expect(!artistClosure.contains("PlotterRuntime"))
    #expect(graph["PortraitStudioUI"]?.contains("PortraitCore") == true)
    #expect(graph["PortraitStudio"]?.contains("PortraitStudioUI") == true)
    #expect(graph["PlotterApp"]?.contains("PortraitStudioUI") == true)
  }
}
