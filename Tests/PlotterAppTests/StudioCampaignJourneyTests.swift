@testable import PortraitArtists
@testable import PortraitLibrary
@testable import PortraitStudioUI
import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import Testing
@testable import PlotterApp

/// One production composition journey. All source labels, ruler-independent
/// material pixels, camera/controller effects and physical ratings are synthetic;
/// these assertions establish software linkage, not learned or attended quality.
@Suite("Trainable Drawing Studio campaign journey", .serialized)
@MainActor
struct StudioCampaignJourneyTests {
  @Test("attended targets select exact unit-scale plans at zero and ninety degrees without dispatch")
  func prepareExactMetricTargets() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make()
    defer { f.stores.remove() }
    let app = f.application
    do {
      let feeds = await f.machine.requestedFeeds
      let penCommands = await f.machine.requestedPenCommands
      for id in [DrawingCatalogEntryID.metricSquare40, .metricRectangle40x20] {
        try await f.submit(.selectCatalogItem(id))
        if !app.drawingTargetIsVisible { try await f.submit(.showTarget) }
        #expect(app.drawingTargetIsVisible)
        try await f.submit(.setUniformScale(1))
        for rotation in [0.0, 90.0] {
          try await f.submit(.setRotationDegrees(rotation))
          try await f.submit(.centerInDrawableRegion)
          let program = try #require(app.drawingDraftSnapshot.program)
          let plan = try #require(app.drawingDraftSnapshot.plan)
          #expect(plan.placement.uniformScale == 1)
          try assertStudioProportions(program: program, plan: plan)
          let points = try #require(plan.strokes.first?.path.points)
          #expect(points.count == 5)
          let edges = zip(points, points.dropFirst()).map { $0.distance(to: $1) }
          let expected = id == .metricSquare40 ? [40.0, 40, 40, 40] : [40.0, 20, 40, 20]
          #expect(zip(edges, expected).allSatisfy { abs($0 - $1) < 1e-8 })
          if id == .metricSquare40 {
            #expect(plan.strokes.count == 3)
            for diagonal in plan.strokes.dropFirst() {
              #expect(abs(diagonal.path.points[0].distance(to: diagonal.path.points[1]) - 40 * sqrt(2)) < 1e-8)
            }
          }
          #expect(!app.drawingDraftSnapshot.paperCoverageIsCurrent)
          #expect(await f.planGate.request == nil)
        }
      }
      #expect(await f.machine.requestedFeeds == feeds)
      #expect(await f.machine.requestedPenCommands == penCommands)
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }

}

private enum StudioJourneyFailure: Error { case missingArchive }

private func studioJourneyBytes<T: Encodable>(_ value: T) throws -> Data {
  let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
  return try encoder.encode(value)
}

private func studioJourneyChangedFields(_ expected: Data, _ actual: Data) throws -> [String] {
  var changes: [String] = []
  func compare(_ left: Any?, _ right: Any?, path: String) {
    guard changes.count < 32 else { return }
    if let left = left as? [String: Any], let right = right as? [String: Any] {
      for key in Set(left.keys).union(right.keys).sorted() { compare(left[key], right[key], path: path + "." + key) }
    } else if let left = left as? [Any], let right = right as? [Any] {
      if left.count != right.count { changes.append("\(path).count: \(left.count) -> \(right.count)") }
      for index in 0..<min(left.count, right.count) { compare(left[index], right[index], path: "\(path)[\(index)]") }
    } else if (left as? NSObject)?.isEqual(right) != true {
      func description(_ value: Any?) -> String {
        guard let value else { return "absent" }
        if let text = value as? String, text.count > 80 { return "string(\(text.count) characters)" }
        return String(describing: value).prefix(120).description
      }
      changes.append("\(path): \(description(left)) -> \(description(right))")
    }
  }
  compare(try JSONSerialization.jsonObject(with: expected), try JSONSerialization.jsonObject(with: actual), path: "archive")
  return changes
}

private func assertStudioProportions(program: DrawingProgram, plan: ExecutionPlanRevision) throws {
  #expect(program.strokes.count == plan.strokes.count)
  for (source, executed) in zip(program.strokes, plan.strokes) {
    #expect(source.id == executed.logicalStrokeID)
    #expect(source.path.points.count == executed.path.points.count)
    for index in source.path.points.indices.dropFirst() {
      let a = source.path.points[index - 1], b = source.path.points[index]
      let c = executed.path.points[index - 1], d = executed.path.points[index]
      let camera = plan.placement.cameraGeometry
      let expected = hypot(b.x - a.x, b.y - a.y) * plan.placement.uniformScale * (camera?.referencePixelsPerUnit ?? 1)
      let actual: Double
      if let camera {
        actual = try camera.cameraFromMachine.applying(to: c).distance(to: camera.cameraFromMachine.applying(to: d))
      } else { actual = c.distance(to: d) }
      #expect(abs(actual - expected) < 1e-8)
    }
  }
}

private func assertStudioCandidate(_ actual: PortraitCandidate?, equals expected: PortraitCandidate) throws {
  let candidate = try #require(actual)
  #expect(try studioJourneyBytes(candidate) == studioJourneyBytes(expected))
}
