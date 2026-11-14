import CoreGraphics
import Foundation
import PlotterModel
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary
import PortraitStudioUI
import Testing

@Suite("Authoring presentation projections", .serialized)
struct FlowAuthoringProjectionTests {
  @Test("Indexed history preserves ordered names and latest masks across a large snapshot")
  func historyIndex() throws {
    let benchmark = ProcessInfo.processInfo.environment["STUDIO_PROJECTION_BENCHMARK"] == "1"
    let count = benchmark ? 4_000 : 200
    let sourceID = UUID(), roundID = UUID(), date = Date(timeIntervalSince1970: 1)
    let blob = FlowPortfolioBlob(sha256: String(repeating: "a", count: 64), byteCount: 1, mediaType: "image/png")
    var document = FlowPortfolioSnapshot.empty(purpose: .validationFixture)
    document.sources = [.init(id: sourceID, createdAt: date, title: "History fixture", image: blob)]
    document.candidates = (0..<count).map { slot in
      FlowPortfolioCandidate(id: UUID(), createdAt: date, sourceID: sourceID, roundID: roundID,
        slot: slot, parentCandidateID: nil, recipe: .standard, modelID: nil, raster: blob, preview: blob,
        programHash: String(repeating: "b", count: 64), strokeCount: 16)
    }
    let baselineStart = DispatchTime.now().uptimeNanoseconds
    let expected = document.candidates.map { candidate -> Int in
      let family = document.photoSourceIDs(for: candidate.sourceID)
      let siblings = document.candidates.filter { family.contains($0.sourceID) }
      return (siblings.firstIndex { $0.id == candidate.id } ?? 0) + 1
    }
    let baselineMS = Self.milliseconds(since: baselineStart)
    let indexedStart = DispatchTime.now().uptimeNanoseconds
    let index = FlowAuthoringPresentationIndex(document)
    let actual = document.candidates.map { index.drawingNumbers[$0.id] ?? 1 }
    let indexedMS = Self.milliseconds(since: indexedStart)
    #expect(actual == expected)
    #expect(index.candidates.count == count)
    if benchmark {
      print("STUDIO_PROJECTION_BENCHMARK rows=\(count) previousRowScanMS=\(baselineMS) indexBuildAndRowsMS=\(indexedMS)")
    }
  }

  @Test("Geometry bounds preserve repeated vertices and multisegment polylines")
  func geometryBounds() throws {
    let style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID())
    let coordinates: [[(Double, Double)]] = [
      [(10, 20), (10, 20), (10, 80)],
      [(10, 20), (10, 80)],
      [(20, 20), (80, 20)],
      [(5, 95), (90, 45), (30, 5)]
    ]
    let strokes = try coordinates.enumerated().map { index, points in
      LogicalStroke(id: StrokeID(), path: try Polyline(points: points.map { try Point2(x: $0.0, y: $0.1) }), style: style, ordering: UInt32(index))
    }
    let program = try DrawingProgram(id: ProgramID(), fieldExtent: .init(width: 100, height: 100),
      strokes: strokes, source: .init(kind: "test", sourceIdentifier: "geometry-bounds"))
    let geometry = PortraitLineSelectionGeometry(program: program, size: .init(width: 600, height: 420))
    for line in geometry.lines {
      let xs = line.points.map(\.x), ys = line.points.map(\.y)
      #expect(line.bounds == CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!))
    }
    #expect(geometry.lines[0].bounds == geometry.lines[1].bounds)
    #expect(geometry.lines[1].bounds.width == 0)
    #expect(geometry.lines[2].bounds.height == 0)
  }

  @Test("Large pruning mask remains exact through restore, undo, redo and cold reopen",
    .enabled(if: ProcessInfo.processInfo.environment["STUDIO_PROJECTION_BENCHMARK"] == "1"))
  @MainActor func largePruningProjection() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("studio-pruning-performance-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: { data, recipe, style in
      let base = try await FlowAuthoringFixture.render(data, recipe, style)
      let strokes = (0..<512).map { index in
        LogicalStroke(id: StrokeID(), path: base.program.strokes[index % base.program.strokes.count].path,
          style: style, ordering: UInt32(index))
      }
      let program = try DrawingProgram(id: ProgramID(), fieldExtent: base.program.fieldExtent,
        strokes: strokes, source: base.program.source)
      return PortraitRenderResult(raster: base.raster, program: program)
    })
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(3), title: "Large pruning fixture")
    model.count = 2; await model.generate(refining: false)
    let candidate = try #require(model.roundCandidates.first)
    await model.selectCandidate(candidate.id, prune: true)
    let program = try #require(model.program)
    let removed = Set(program.strokes.prefix(256).map(\.id))
    await model.edit(.remove, ids: removed)
    #expect(model.error == nil && model.removedIDs == removed)
    let restored = Set(program.strokes.prefix(32).map(\.id))
    await model.edit(.restore, ids: restored)
    #expect(model.removedIDs == removed.subtracting(restored))
    await model.edit(.undo); #expect(model.removedIDs == removed)
    await model.edit(.redo); #expect(model.removedIDs == removed.subtracting(restored))
    await model.edit(.completeTarget)
    let expected = removed.subtracting(restored)
    let start = DispatchTime.now().uptimeNanoseconds
    var baseline = Set<StrokeID>()
    for _ in 0..<20 {
      baseline = Set(program.strokes.enumerated().filter { model.removedIndices.contains($0.offset) }.map { $0.element.id })
    }
    let baselineMS = Self.milliseconds(since: start), optimizedStart = DispatchTime.now().uptimeNanoseconds
    var actual = Set<StrokeID>()
    for _ in 0..<20 { actual = model.removedIDs }
    let optimizedMS = Self.milliseconds(since: optimizedStart)
    #expect(actual == baseline && actual == expected)
    #expect(await model.shutdown())
    let cold = FlowAuthoringModel(directory: root)
    await cold.open()
    #expect(cold.error == nil && cold.candidate?.id == candidate.id && cold.program == program)
    #expect(cold.removedIDs == expected && cold.prune?.action == .completeTarget)
    #expect(await cold.shutdown())
    print("STUDIO_PRUNING_BENCHMARK strokes=512 removed=224 iterations=20 previousProjectionMS=\(baselineMS) currentProjectionMS=\(optimizedMS)")
  }

  private static func milliseconds(since start: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
  }
}
