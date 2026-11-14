import Foundation
import DrawingLibrary
import PlotterModel
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary
import Testing

@Suite("Authoring backend performance and equivalence", .serialized)
struct BackendPerformanceTests {
  @Test("Source connectivity includes excluded bridges and is independent of input order")
  func connectedSources() {
    var document = fixtureSources(count: 16)
    document.sources[1].excluded = true
    document.sources[0].sessionID = "bridge"
    document.sources[4].sessionID = "bridge"
    let expected = referenceGroups(document.sources)
    #expect(FlowPortfolioSupervision.plan(document).sourceGroups == expected)
    document.sources.reverse()
    #expect(FlowPortfolioSupervision.plan(document).sourceGroups == expected)
  }

  @Test("Temporary artifact byte accounting handles deduplication, eviction and repeated publication")
  func artifactAccounting() throws {
    let library = DrawingLibrary(directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    let artifacts = FlowAuthoringArtifacts(library: library)
    let firstBytes = Data(repeating: 1, count: 100), secondBytes = Data(repeating: 2, count: 150)
    let first = try artifacts.retain(firstBytes, mediaType: "application/octet-stream")
    let second = try artifacts.retain(secondBytes, mediaType: "application/octet-stream")
    _ = try artifacts.retain(firstBytes, mediaType: "application/octet-stream")
    #expect(artifacts.count == 2 && artifacts.byteCount == 250)
    artifacts.keepUnpublished([first.sha256])
    #expect(artifacts.count == 1 && artifacts.byteCount == 100)
    artifacts.markPublished([first, first, second])
    #expect(artifacts.count == 0 && artifacts.byteCount == 0)
    _ = try artifacts.retain(firstBytes, mediaType: "application/octet-stream")
    #expect(artifacts.count == 0 && artifacts.byteCount == 0)
  }

  @Test("Repeatable supervision and feature extraction benchmark", .enabled(if: ProcessInfo.processInfo.environment["FLOW_BACKEND_BENCHMARK"] == "1"))
  func benchmark() throws {
    let document = fixtureSources(count: 800)
    let history = fixtureHistory(roundCount: 2000)
    let program = try fixtureProgram(strokes: 1200, points: 120)
    let raster = PortraitRaster(width: 128, height: 128,
      luminance: (0..<(128 * 128)).map { Double($0 % 128) / 127 },
      provenance: "synthetic-backend-benchmark", analysisSummary: "Software performance fixture")
    let mask = Set(stride(from: 0, to: program.strokes.count, by: 5))
    var groupCount = 0, drawing: [Double] = [], strokes: [[Double]] = []
    try measure("history-validation") { try FlowPortfolioValidation.validate(history) }
    measure("source-connectivity") { groupCount = FlowPortfolioSupervision.plan(document).sourceGroups.count }
    measure("drawing-features") { drawing = FlowArtistFeatures.drawing(recipe: .standard, program: program, raster: raster, removedIndices: mask) }
    measure("stroke-features") { strokes = FlowArtistFeatures.strokes(recipe: .standard, program: program, raster: raster) }
    #expect(groupCount == 800 && drawing.count == FlowArtistFeatures.drawingCount)
    #expect(strokes.count == 1200 && strokes.allSatisfy { $0.count == FlowArtistFeatures.strokeCount })
    #expect(try digest(drawing) == "544b85b4e9daeb7c1c2dc9f77f82a66fe2bedc990d915ef6ffd032fbee6a34cf")
    #expect(try digest(strokes) == "2e18348871b1329a4188009df7c0534fbe948e0916166f9431ff34b6dc8b4c6b")
    print("FLOW_BACKEND_FEATURE_DIGEST drawing=\(try digest(drawing)) strokes=\(try digest(strokes))")
  }

  private func measure(_ label: String, operation: () throws -> Void) rethrows {
    try operation()
    let samples = try (0..<7).map { _ -> Double in
      let start = ContinuousClock.now
      try operation()
      let duration = start.duration(to: .now)
      return Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }.sorted()
    print("FLOW_BACKEND_BENCHMARK \(label) median_ms=\(samples[3]) samples_ms=\(samples)")
  }

  private func digest<T: Encodable>(_ value: T) throws -> String {
    ExchangeDigest.hash(try DrawingArtifactCoding.encoder().encode(value)).description
  }

  private func fixtureSources(count: Int) -> FlowPortfolioSnapshot {
    var document = FlowPortfolioSnapshot.empty(purpose: .validationFixture)
    document.sources = (0..<count).map { index in
      FlowPortfolioSource(id: UUID(), createdAt: Date(timeIntervalSince1970: 0), title: "Source \(index)",
        image: .init(sha256: String(format: "%064x", index), byteCount: 1, mediaType: "image/png"),
        subjectID: "subject-\(index / 4)", sessionID: index % 4 == 0 ? "session-\(index / 8)" : nil)
    }
    return document
  }

  private func fixtureHistory(roundCount: Int) -> FlowPortfolioSnapshot {
    var document = fixtureSources(count: 1)
    let source = document.sources[0], timestamp = Date(timeIntervalSince1970: 1)
    let blob = FlowPortfolioBlob(sha256: String(repeating: "1", count: 64), byteCount: 32, mediaType: "image/png")
    for _ in 0..<roundCount {
      let roundID = UUID(), ids = (0..<4).map { _ in UUID() }
      document.rounds.append(.init(id: roundID, createdAt: timestamp, sourceID: source.id, parentCandidateID: nil,
        recipes: Array(repeating: .standard, count: 4), analysisOptions: .init(), seed: 1, modelID: nil,
        status: .completed, candidateIDs: ids, displayedCandidateIDs: ids, recommendedCandidateID: nil, failures: []))
      for (slot, id) in ids.enumerated() {
        document.candidates.append(.init(id: id, createdAt: timestamp, sourceID: source.id, roundID: roundID,
          slot: slot, parentCandidateID: nil, recipe: .standard, modelID: nil, raster: blob, preview: blob,
          programHash: blob.sha256, strokeCount: 100))
      }
    }
    return document
  }

  private func fixtureProgram(strokes: Int, points: Int) throws -> DrawingProgram {
    let style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID())
    let geometry = try (0..<strokes).map { index -> LogicalStroke in
      let centerX = Double(index % 40) * 2.4 + 2, centerY = Double(index / 40) * 3 + 2
      let coordinates = try (0..<points).map { offset -> Point2<FieldSpace> in
        let angle = Double(offset) / Double(points - 1) * 5
        return try Point2(x: centerX + cos(angle), y: centerY + sin(angle))
      }
      return LogicalStroke(id: StrokeID(), path: try Polyline(points: coordinates), style: style, ordering: UInt32(index))
    }
    return try DrawingProgram(id: ProgramID(), fieldExtent: .init(width: 100, height: 100), strokes: geometry,
      source: .init(kind: "portrait", sourceIdentifier: "backend-performance"))
  }

  private func referenceGroups(_ sources: [FlowPortfolioSource]) -> [UUID: String] {
    var groups = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, Set($0.groupKeys)) })
    var changed = true
    while changed {
      changed = false
      for source in sources {
        var merged = groups[source.id] ?? []
        for other in sources where !(groups[other.id] ?? []).isDisjoint(with: merged) { merged.formUnion(groups[other.id] ?? []) }
        if merged != groups[source.id] { groups[source.id] = merged; changed = true }
      }
    }
    return groups.mapValues { $0.sorted().joined(separator: "|") }
  }
}
