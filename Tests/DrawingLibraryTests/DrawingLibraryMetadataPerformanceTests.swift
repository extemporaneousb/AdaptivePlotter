import Darwin
import DrawingLibrary
import Foundation
import PlotterModel
import PortraitCore
import Testing

private extension DrawingLibrary {
  /// Synthetic SQL metadata scale only. These rows are not admitted wire records
  /// or 10,000 retained programs. The real selected drawing is published normally.
  func seedMetadataPerformanceRows(total: Int, real: DrawingRef, sameDate: Bool = false) throws {
    let catalog = try commonCatalog(), db = catalog.database
    let issuer = UUID(uuidString: "9de72f65-1d78-4f65-9e30-15201a987000")!
    let template = try db.rows("SELECT program_digest,stroke_count,point_count,min_x,min_y,max_x,max_y FROM dx_drawing_summary WHERE namespace=? AND identity=?", [real.issuer.uuidString.lowercased(), real.revision.uuidString.lowercased()])[0]
    try db.transaction {
      for index in 1..<total {
        let revision = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012llx", UInt64(index)))!
        let payload = Data("synthetic metadata fixture row \(index)".utf8)
        let digest = ExchangeDigest.hash(payload)
        let ref = DrawingRef(issuer: issuer, revision: revision, digest: digest)
        let key: [String?] = [issuer.uuidString.lowercased(), revision.uuidString.lowercased(), digest.description]
        try db.execute("INSERT INTO dx_object(digest,byte_length) VALUES(?,?)", [digest.description, String(payload.count)])
        try db.execute("INSERT INTO dx_record(kind,namespace,identity,digest) VALUES('drawing',?,?,?)", key)
        // Equal-date groups exercise identity tie breaks; actual timestamps are
        // numeric Unix seconds, not string ordering or fabricated unknown dates.
        try db.execute("INSERT INTO dx_drawing_summary(namespace,identity,digest,program_digest,created_at,stroke_count,point_count,min_x,min_y,max_x,max_y) VALUES(?,?,?,?,?,?,?,?,?,?,?)", key + [template[0], String(1_762_000_000 + (sameDate ? 0 : index / 3))] + Array(template[1...]))
        let metadata = LibraryExchangeMetadata(reference: .drawing(ref), title: "Named synthetic drawing \(index)", retentionReasons: ["synthetic-metadata-benchmark"])
        let json = String(decoding: try DrawingArtifactCoding.encoder().encode(metadata), as: UTF8.self)
        try db.execute("INSERT INTO dx_metadata(kind,namespace,identity,digest,payload,tombstoned) VALUES('drawing',?,?,?,?,0)", key + [json])
      }
      try db.bumpRevision()
    }
    try #require(try db.scalar("SELECT COUNT(*) FROM dx_record WHERE kind='drawing'") == String(total))
    refreshOwnership() // Only this owner's completed fixture transaction.
  }
  func metadataProbeCursor(offset: Int) throws -> DrawingLibraryCursor {
    let db = try libraryDatabase()
    let row = try db.rows("SELECT printf('%!.17g',created_at),namespace,identity FROM dx_drawing_summary ORDER BY created_at DESC,namespace,identity LIMIT 1 OFFSET ?", [String(offset)])[0]
    return .init(generation: try db.generation, date: row[0]!, issuer: row[1]!, revision: row[2]!)
  }
  func mixedDateExpectedOrder() throws -> [String] {
    let db = try libraryDatabase()
    let rows = try db.rows("SELECT namespace,identity FROM dx_drawing_summary ORDER BY namespace,identity")
    try db.transaction {
      for (index, row) in rows.enumerated() {
        try db.execute("UPDATE dx_drawing_summary SET created_at=? WHERE namespace=? AND identity=?",
          [String(1_762_000_000 + index / 7), row[0], row[1]])
        if index % 17 == 0 {
          try db.execute("UPDATE dx_metadata SET tombstoned=1 WHERE kind='drawing' AND namespace=? AND identity=?", row)
        }
      }
      try db.bumpRevision()
    }
    refreshOwnership()
    return try db.rows("SELECT s.namespace,s.identity FROM dx_drawing_summary s LEFT JOIN dx_metadata m ON m.kind='drawing' AND m.namespace=s.namespace AND m.identity=s.identity WHERE COALESCE(m.tombstoned,0)=0 ORDER BY s.created_at DESC,s.namespace,s.identity").map { $0[0]! + "/" + $0[1]! }
  }

}

@Suite("Current DrawingLibrary metadata performance", .serialized)
struct DrawingLibraryMetadataPerformanceTests {
  @Test("Bound cursor seeks stay bounded across a large date tie and preserve mixed-date/tombstone boundaries")
  func boundCursorWork() async throws {
    var work: [UInt64] = []
    for count in [100, 10_000] {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent("drawing-bound-keyset-" + UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let library = DrawingLibrary(directoryURL: root)
      do {
        let style = try StrokeStyle(nominalLineWidth: 0.8, penProfileID: PenProfileID(UUID()))
        let drawing = try Drawing(program: DrawingProgramCatalog.program(for: .line, style: style), input: .none, parent: .none,
          producer: DrawingProducerReceipt(id: "example.bound-keyset", version: "1", recordJSON: Data("{}".utf8)))
        let retained = try await library.retain(drawing, reason: "actual-control")
        try await library.seedMetadataPerformanceRows(total: count, real: retained.reference, sameDate: true)
        let cursor = try await library.metadataProbeCursor(offset: count - 41)
        let before = DrawingLibraryDiagnostics.shared.snapshot()
        let page = try await library.drawings(limit: 30, after: cursor)
        let after = DrawingLibraryDiagnostics.shared.snapshot()
        let steps = after["drawingPageVMSteps", default: 0] - before["drawingPageVMSteps", default: 0]
        let scans = after["drawingPageFullscanSteps", default: 0] - before["drawingPageFullscanSteps", default: 0]
        #expect(page.entries.count == 30 && page.next != nil)
        #expect(steps > 0 && steps < 2_000 && scans <= 31)
        work.append(steps)
        print("DRAWING_KEYSET_BOUND_WORK rows=\(count) tiedSyntheticRows=\(count - 1) vmSteps=\(steps) fullscanSteps=\(scans)")
        if count == 100 {
          let expected = try await library.mixedDateExpectedOrder()
          var actual: [String] = [], next: DrawingLibraryCursor?
          repeat {
            let page = try await library.drawings(limit: 11, after: next)
            actual += page.entries.map { $0.reference.issuer.uuidString.lowercased() + "/" + $0.reference.revision.uuidString.lowercased() }
            next = page.next
          } while next != nil && actual.count <= count
          #expect(actual == expected && Set(actual).count == actual.count && next == nil)
        }
        await library.closeLibrary()
      } catch { await library.closeLibrary(); throw error }
    }
    #expect(work[1] <= work[0] * 2)
  }

  @Test("100 versus 10k named metadata rows, 30 warm trials, with artwork unavailable",
    .enabled(if: ProcessInfo.processInfo.environment["DRAWING_LIBRARY_METADATA_PERF"] == "1"))
  func namedMetadataScale() async throws {
    let output = try #require(ProcessInfo.processInfo.environment["DRAWING_LIBRARY_METADATA_PERF_OUTPUT"])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("drawing-metadata-perf-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var results: [[String: Any]] = []
    for count in [100, 10_000] {
      let root = directory.appendingPathComponent(String(count))
      let library = DrawingLibrary(directoryURL: root)
      do {
        let style = try StrokeStyle(nominalLineWidth: 0.8, penProfileID: PenProfileID(UUID()))
        let program = try DrawingProgramCatalog.program(for: .line, style: style)
        let drawing = try Drawing(program: program, input: .none, parent: .none,
          producer: DrawingProducerReceipt(id: "example.metadata-performance", version: "1", recordJSON: Data("{}".utf8)))
        let retained = try await library.retain(drawing, title: "Actual retained control", reason: "benchmark-control")
        try await library.seedMetadataPerformanceRows(total: count, real: retained.reference)
        let artwork = root.appendingPathComponent("objects")
        let held = directory.appendingPathComponent("unavailable-artwork-\(count)")
        try FileManager.default.moveItem(at: artwork, to: held)
        await #expect(throws: (any Error).self) { try await library.drawing(retained.reference) }

        // Find a deep cursor by real keyset traversal, outside all timed regions.
        let first = try await library.drawings(limit: 30)
        var cursor = try #require(first.next)
        let walkPages = max(1, count / 30 - 2)
        var visited = Set(first.entries.map(\.reference))
        for _ in 0..<walkPages {
          let page = try await library.drawings(limit: 30, after: cursor)
          let uniquePage = page.entries.allSatisfy { visited.insert($0.reference).inserted }
          #expect(uniquePage)
          cursor = try #require(page.next)
        }
        let deep = cursor
        for _ in 0..<5 {
          #expect(try await library.drawings(limit: 30).entries.count == 30)
          #expect(try await library.drawings(limit: 30, after: deep).entries.count > 0)
        }
        var firstMS: [Double] = [], deepMS: [Double] = [], renameMS: [Double] = [], clearMS: [Double] = []
        let pageCountersBefore = DrawingLibraryDiagnostics.shared.snapshot()
        for _ in 0..<30 {
          var start = DispatchTime.now().uptimeNanoseconds
          let page = try await library.drawings(limit: 30)
          firstMS.append(Self.milliseconds(since: start))
          start = DispatchTime.now().uptimeNanoseconds
          let tail = try await library.drawings(limit: 30, after: deep)
          deepMS.append(Self.milliseconds(since: start))
          #expect(page.entries.count == 30 && !tail.entries.isEmpty)
          #expect(page.entries.allSatisfy { $0.title?.isEmpty == false })
        }
        let pageCountersAfter = DrawingLibraryDiagnostics.shared.snapshot()
        let pageCounters = pageCountersAfter.reduce(into: [String: UInt64]()) { result, pair in
          result[pair.key] = pair.value - (pageCountersBefore[pair.key] ?? 0)
        }
        for counter in ["storageObjectReads", "storageFileVerifications", "storageStreamHashBytes"] {
          #expect(pageCounters[counter, default: 0] == 0)
        }
        // Rename changes generation, so all cursor timing is already finished.
        for trial in 0..<35 {
          var start = DispatchTime.now().uptimeNanoseconds
          try await library.rename(retained.reference, title: "Renamed control \(trial)")
          let rename = Self.milliseconds(since: start)
          start = DispatchTime.now().uptimeNanoseconds
          try await library.rename(retained.reference, title: nil)
          let clear = Self.milliseconds(since: start)
          if trial >= 5 { renameMS.append(rename); clearMS.append(clear) }
        }
        let finalPage = try await library.drawings(limit: 30)
        let realEntry = try #require(finalPage.entries.first { $0.reference == retained.reference })
        #expect(realEntry.title == nil)
        #expect(!FileManager.default.fileExists(atPath: artwork.path))
        await #expect(throws: (any Error).self) { try await library.drawing(retained.reference) }
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        let databaseBytes = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("drawing-library.sqlite").path)[.size] as! NSNumber
        results.append(["metadataRows": count, "actualPubliclyRetainedDrawings": 1,
          "pageSize": 30, "warmups": 5, "trials": 30, "deepCursorWalkPages": walkPages,
          "firstPage": Self.statistics(firstMS), "deepPage": Self.statistics(deepMS),
          "rename": Self.statistics(renameMS), "clearTitle": Self.statistics(clearMS),
          "metadataPageCounters": pageCounters,
          "databaseBytes": databaseBytes, "processLifetimePeakRSSBytes": usage.ru_maxrss,
          "artworkDirectoryAbsentForAllMeasuredOperations": true,
          "selectedArtworkLoadRefused": true])
        await library.closeLibrary()
      } catch { await library.closeLibrary(); throw error }
    }
    let report: [String: Any] = ["format": "drawing-library-current-metadata-performance/1",
      "fixtureScope": "Synthetic current SQL metadata; one actual public retained drawing per scale. Additional rows have no admitted wire programs or CAS files.",
      "comparisonScope": "100 versus 10000 metadata rows under the same current binary; no historical performance comparison or Dojo CPU claim.",
      "memoryScope": "Darwin ru_maxrss process lifetime high-water bytes, including test startup, previous scales, and fixture seeding; not operation-local RSS.",
      "ioScope": "Artwork directory physically unavailable; metadata success and selected-load refusal are structural evidence. Library SQL/storage-seam counters cover measured pages; not universal filesystem or producer counters.",
      "results": results]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output), options: .atomic)
    print("DRAWING_LIBRARY_METADATA_PERF_REPORT=" + output)
  }
  private static func milliseconds(since start: UInt64) -> Double { Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000 }
  private static func statistics(_ samples: [Double]) -> [String: Any] {
    let ordered = samples.sorted()
    return ["milliseconds": samples, "p50MS": ordered[Int(ceil(Double(ordered.count) * 0.50)) - 1],
      "p95MS": ordered[Int(ceil(Double(ordered.count) * 0.95)) - 1]]
  }
}
