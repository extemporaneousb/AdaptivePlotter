import Foundation
import Testing

@Suite("Drawing value module dependency contract")
struct DrawingDependencyContractTests {
  @Test("The exported Drawing contract and artist dependency closure exclude machine runtime",
    .enabled(if: ProcessInfo.processInfo.environment["DRAWING_PACKAGE_MANIFEST"] != nil))
  func coreDependencyGraph() throws {
    // Manifest evaluation belongs to the architecture command, outside the unit
    // test process. This retains SwiftPM's evaluated graph, including transitive
    // dependencies, without launching a nested package manager in quick-test.
    let path = try #require(ProcessInfo.processInfo.environment["DRAWING_PACKAGE_MANIFEST"])
    let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
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
