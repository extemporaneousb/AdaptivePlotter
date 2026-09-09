import Foundation
import PlotterModel
import Testing
@testable import PlotterRuntime

@Suite("Planned drawing exact association index")
struct PlannedDrawingAssociationIndexTests {
  @Test("full-pixel finalists resolve a coarse lattice that samples only one repeated column")
  func tiedCoarseSeedsUseAllPixels() async throws {
    let paths = try [20.0, 22.0].map { x in
      try Polyline<CameraPixelSpace>(points: [Point2(x: x, y: 20), Point2(x: x, y: 83)])
    }
    let ink = (20...83).flatMap { y in
      [VisionWorker.InkPixel(x: 22, y: y), .init(x: 24, y: y)]
    }
    let result = try await VisionWorker.cancellableCorrespondenceAssociation(ink, with: paths,
      region: PixelRect(x: 12, y: 12, width: 19, height: 80),
      observationShiftX: 0, observationShiftY: 0, ambiguityTolerance: 0.01,
      maximumEvaluationCount: 5_000_000, baseComputation: .zero, checkpointHandler: nil)
    #expect(result.matchingTranslationX == 2)
    #expect(result.matchingTranslationY == 0)
    #expect(result.matchingSquaredResidual == 0)
    #expect(result.association.byPolyline.map(\.count) == [64, 64])
    #expect(result.association.byPolyline[0].allSatisfy { $0.point.x == 22 })
    #expect(result.association.byPolyline[1].allSatisfy { $0.point.x == 24 })
    #expect(result.evaluationCount <= 5_000_000)
    // One unit less must fail even if every coarse seed already completed:
    // tied full-pixel verification is part of the same budget.
    do {
      _ = try await VisionWorker.cancellableCorrespondenceAssociation(ink, with: paths,
        region: PixelRect(x: 12, y: 12, width: 19, height: 80),
        observationShiftX: 0, observationShiftY: 0, ambiguityTolerance: 0.01,
        maximumEvaluationCount: result.evaluationCount - 1, baseComputation: .zero,
        checkpointHandler: nil)
      Issue.record("Tied-finalist verification exceeded its budget")
    } catch VisionWorker.PlannedAssociationError.evaluationBudgetExceeded { }
  }

  @Test("nonzero frame alignment shifts the correspondence ROI while retaining raw post-frame points")
  func correspondenceBoundsUsePostFrameCoordinates() async throws {
    let paths = try [20.0, 22.0, 24.0].map { x in
      try Polyline<CameraPixelSpace>(points: [Point2(x: x, y: 20), Point2(x: x, y: 83)])
    }
    // Extraction traverses baseline ROI coordinates and reads each at x+4.
    // Mechanical +8 and background +4 put the actual ink at 32,34,36.
    let ink = (20...83).flatMap { y in
      [VisionWorker.InkPixel(x: 28, y: y), .init(x: 30, y: y), .init(x: 32, y: y)]
    }
    let result = try await VisionWorker.cancellableCorrespondenceAssociation(ink, with: paths,
      region: PixelRect(x: 12, y: 12, width: 21, height: 80),
      observationShiftX: 4, observationShiftY: 0, ambiguityTolerance: 0.01,
      maximumEvaluationCount: 5_000_000, baseComputation: .zero, checkpointHandler: nil)
    #expect(result.matchingTranslationX == 12)
    #expect(result.matchingTranslationY == 0)
    #expect(result.association.byPolyline.map(\.count) == [64, 64, 64])
    for (index, expectedX) in [32.0, 34.0, 36.0].enumerated() {
      #expect(result.association.byPolyline[index].allSatisfy { $0.point.x == expectedX })
    }
    #expect(result.maximumEvaluationCountBetweenCancellationChecks <= 64)
  }

  @Test("a shifted correspondence reference preserves actual sparse and dense ink coordinates",
    arguments: [1, 4])
  func translatedReferencePreservesMeasuredPoints(pathCount: Int) async throws {
    let fixture = try translatedSquares(count: pathCount)
    let result = try await VisionWorker.cancellableCorrespondenceAssociation(fixture.ink,
      with: fixture.paths, region: PixelRect(x: 8, y: 8, width: 65, height: 65),
      observationShiftX: 0, observationShiftY: 0, ambiguityTolerance: 0.01,
      maximumEvaluationCount: 5_000_000, baseComputation: .zero, checkpointHandler: nil)
    #expect(result.matchingTranslationX == 3)
    #expect(result.matchingTranslationY == -2)
    #expect(result.matchingSquaredResidual == 0)
    #expect(result.association.ambiguousPixelCount == 0)
    let measured = Set(result.association.byPolyline.flatMap { $0.map(\.point) })
    let actualPixels = try Set(fixture.ink.map { try Point2<CameraPixelSpace>(x: Double($0.x), y: Double($0.y)) })
    #expect(measured == actualPixels)
    #expect(result.association.byPolyline.count == pathCount)
    #expect(result.association.byPolyline.allSatisfy { !$0.isEmpty })
    #expect(result.evaluationCount <= 5_000_000)
    #expect(result.maximumEvaluationCountBetweenCancellationChecks <= 64)
  }

  @Test("correspondence seeding preserves duplicate ambiguity and consumes the retained work budget")
  func translatedReferenceCannotInventDuplicateIdentityOrFreeSearch() async throws {
    let fixture = try translatedSquares(count: 1)
    let paths = [fixture.paths[0], fixture.paths[0]]
    let result = try await VisionWorker.cancellableCorrespondenceAssociation(fixture.ink,
      with: paths, region: PixelRect(x: 8, y: 8, width: 65, height: 65),
      observationShiftX: 0, observationShiftY: 0, ambiguityTolerance: 0.01,
      maximumEvaluationCount: 5_000_000, baseComputation: .zero, checkpointHandler: nil)
    #expect(result.association.ambiguousPixelCount == fixture.ink.count)
    #expect(result.association.byPolyline.allSatisfy { $0.isEmpty })
    do {
      _ = try await VisionWorker.cancellableCorrespondenceAssociation(fixture.ink,
        with: paths, region: PixelRect(x: 8, y: 8, width: 65, height: 65),
        observationShiftX: 0, observationShiftY: 0, ambiguityTolerance: 0.01,
        maximumEvaluationCount: 64, baseComputation: .zero, checkpointHandler: nil)
      Issue.record("Reference search must consume the same association budget")
    } catch VisionWorker.PlannedAssociationError.evaluationBudgetExceeded { }
  }

  @Test("indexed association preserves curved paths, crossing ties, duplicate paths, shifts and stray ink")
  func indexedAssociationMatchesExhaustive() async throws {
    var paths: [Polyline<CameraPixelSpace>] = []
    for row in 0..<12 {
      let points = try (0...16).map { column in
        try Point2<CameraPixelSpace>(x: Double(column * 8),
          y: Double(row * 17) + sin(Double(column) / 2) * 7)
      }
      paths.append(try Polyline(points: points))
    }
    let crossing = try Polyline<CameraPixelSpace>(points: [
      Point2(x: 64, y: -20), Point2(x: 64, y: 220)])
    paths.append(crossing)
    // A duplicate must remain ambiguous wherever it would win, even when the
    // duplicate's segments live in different index leaves.
    paths.append(paths[3])
    var ink: [VisionWorker.InkPixel] = []
    for y in stride(from: -12, through: 212, by: 7) {
      for x in stride(from: -16, through: 144, by: 5) {
        ink.append(.init(x: x, y: y))
      }
    }
    ink.append(.init(x: 100_000, y: -90_000))
    for shift in [-3, 0, 5] {
      for tolerance in [0.0, 0.75, 2.0] {
        let actual = try await VisionWorker.cancellableAssociation(ink, with: paths,
          observationShiftX: shift, observationShiftY: -shift,
          ambiguityTolerance: tolerance, maximumEvaluationCount: 5_000_000,
          baseComputation: .zero, checkpointHandler: nil)
        let expected = exhaustiveAssociation(ink, paths: paths,
          shiftX: shift, shiftY: -shift, tolerance: tolerance)
        #expect(actual.association == expected)
        #expect(actual.maximumEvaluationCountBetweenCancellationChecks <= 64)
        let exhaustiveCount = ink.count * paths.reduce(0) { $0 + $1.points.count - 1 }
        #expect(actual.evaluationCount < exhaustiveCount / 2)
      }
    }
  }

  @Test("actual association work, including bounds, obeys the retained budget")
  func actualWorkBudgetIsEnforced() async throws {
    let path = try Polyline<CameraPixelSpace>(points: [
      Point2(x: 0, y: 0), Point2(x: 20, y: 0), Point2(x: 20, y: 20)])
    let ink = [VisionWorker.InkPixel(x: 2, y: 1), .init(x: 20, y: 9)]
    let actual = try await VisionWorker.cancellableAssociation(ink, with: [path],
      observationShiftX: 0, observationShiftY: 0, ambiguityTolerance: 0.75,
      maximumEvaluationCount: 6, baseComputation: .zero, checkpointHandler: nil)
    #expect(actual.evaluationCount == 6) // two pixels × (one bound + two projections)
    #expect(actual.association.byPolyline[0].count == 2)
    do {
      _ = try await VisionWorker.cancellableAssociation(ink, with: [path],
        observationShiftX: 0, observationShiftY: 0, ambiguityTolerance: 0.75,
        maximumEvaluationCount: 5, baseComputation: .zero, checkpointHandler: nil)
      Issue.record("Association must stop at its actual work budget")
    } catch VisionWorker.PlannedAssociationError.evaluationBudgetExceeded {
      // The caller translates this into the existing typed algorithm result.
    }
  }
}

private func translatedSquares(count: Int) throws -> (
  paths: [Polyline<CameraPixelSpace>], ink: [VisionWorker.InkPixel]
) {
  var paths: [Polyline<CameraPixelSpace>] = []
  var ink: Set<VisionWorker.InkPixel> = []
  for index in 0..<count {
    let low = 16 + index * 2, high = 64 - index * 2
    paths.append(try Polyline(points: [Point2(x: Double(low), y: Double(low)),
      Point2(x: Double(high), y: Double(low)), Point2(x: Double(high), y: Double(high)),
      Point2(x: Double(low), y: Double(high)), Point2(x: Double(low), y: Double(low))]))
    for coordinate in low...high {
      ink.insert(.init(x: coordinate + 3, y: low - 2))
      ink.insert(.init(x: coordinate + 3, y: high - 2))
      ink.insert(.init(x: low + 3, y: coordinate - 2))
      ink.insert(.init(x: high + 3, y: coordinate - 2))
    }
  }
  return (paths, ink.sorted { ($0.y, $0.x) < ($1.y, $1.x) })
}

private func exhaustiveAssociation(
  _ ink: [VisionWorker.InkPixel], paths: [Polyline<CameraPixelSpace>],
  shiftX: Int, shiftY: Int, tolerance: Double
) -> VisionWorker.PlannedInkAssociation {
  var grouped = Array(repeating: [VisionWorker.PlannedAssociatedInkPixel](), count: paths.count)
  var ambiguous = 0
  for pixel in ink {
    let point = try! Point2<CameraPixelSpace>(x: Double(pixel.x + shiftX), y: Double(pixel.y + shiftY))
    let ranked = paths.enumerated().map { index, path in
      (index: index, projection: VisionWorker.nearestProjection(of: point, onto: path))
    }.sorted { lhs, rhs in
      if lhs.projection.distance != rhs.projection.distance {
        return lhs.projection.distance < rhs.projection.distance
      }
      return lhs.index < rhs.index
    }
    let first = ranked[0]
    if ranked.count > 1 && ranked[1].projection.distance - first.projection.distance <= tolerance {
      ambiguous += 1
    } else {
      grouped[first.index].append(.init(point: point, alongDistance: first.projection.alongDistance))
    }
  }
  return .init(byPolyline: grouped, ambiguousPixelCount: ambiguous)
}
