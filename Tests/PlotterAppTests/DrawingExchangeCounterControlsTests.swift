import Darwin
import Foundation
import PlotterModel
import Testing
@testable import PortraitLibrary

/// Public allocator snapshot: all malloc zones, outside any measured interval.
/// Live blocks are not cumulative allocation events; these are not RSS/VM bytes.
func dx01AllZoneMallocSnapshot() -> [String: UInt64] {
  var stats = malloc_statistics_t()
  malloc_zone_statistics(nil, &stats)
  return ["liveAllZoneMallocBlocks": UInt64(stats.blocks_in_use),
    "liveAllZoneMallocBytes": UInt64(stats.size_in_use),
    "sumZoneHighwaterTouchedBytes": UInt64(stats.max_size_in_use),
    "allZoneMallocReservedBytes": UInt64(stats.size_allocated)]
}

@Suite("Drawing Exchange coverage controls", .serialized)
struct DrawingExchangeCounterControlsTests {
  @Test("opt-in owner entry controls", .enabled(if:
    ProcessInfo.processInfo.environment["DX_COUNTER_CONTROL"] != nil))
  func control() throws {
    let env = ProcessInfo.processInfo.environment
    let selected = try #require(env["DX_COUNTER_CONTROL"])
    var result: [String: Any] = ["control": selected,
      "scope": "whole selected test process; not timed operation-only",
      "cumulativeAllocationEvents": NSNull()]
    switch selected {
    case "noop":
      // Deliberately no model/library construction or decoding.
      result["expectedOwnerEntries"] = 0
    case "program-decode":
      let program = try DrawingProgram(
        id: ProgramID(UUID(uuidString: "73010000-0000-0000-0000-000000000001")!),
        fieldExtent: Size2<FieldSpace>(width: 10, height: 10),
        strokes: [LogicalStroke(
          id: StrokeID(UUID(uuidString: "73010000-0000-0000-0000-000000000002")!),
          path: Polyline<FieldSpace>(points: [Point2(x: 1, y: 1), Point2(x: 2, y: 2)]),
          style: StrokeStyle(nominalLineWidth: 0.5,
            penProfileID: PenProfileID(UUID(uuidString: "73010000-0000-0000-0000-000000000003")!)),
          ordering: 0)],
        source: DrawingSourceProvenance(kind: "authored", sourceIdentifier: "dx01-counter-control"))
      let bytes = try JSONEncoder().encode(program)
      let decoded = try JSONDecoder().decode(DrawingProgram.self, from: bytes)
      #expect(decoded == program)
      #expect(decoded.contentHash == program.contentHash)
      result["programContentHash"] = decoded.contentHash.description
      result["expectedDrawingProgramDecodeEntries"] = 1
    case "db-positive":
      let root = URL(fileURLWithPath: try #require(env["DX_COUNTER_DATABASE_ROOT"])).standardizedFileURL
      try #require(root.path.hasPrefix("/tmp/adaptiveplotter-dx01-") ||
        root.path.hasPrefix("/private/tmp/adaptiveplotter-dx01-"))
      let database = try PortraitLibraryDatabase(url: root.appendingPathComponent("library-v1.sqlite"), readOnly: true)
      #expect(try database.scalar("SELECT 7301") == "7301")
      result["scope"] = "read-only constructor PRAGMAs plus one SELECT; scalar calls rows, rows calls prepare; execute without values uses sqlite3_exec and can contain compound SQL"
      result["expectedRowsEntries"] = 4
      result["expectedPrepareEntries"] = 4
      result["expectedExecuteEntries"] = 1
    default:
      Issue.record("unknown DX_COUNTER_CONTROL: \(selected)")
      return
    }
    result["allocatorSnapshot"] = dx01AllZoneMallocSnapshot()
    let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
    if let path = env["DX_BASELINE_OUTPUT"] {
      try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    print("DX01_COUNTER_CONTROL " + String(decoding: data, as: UTF8.self))
  }
}
