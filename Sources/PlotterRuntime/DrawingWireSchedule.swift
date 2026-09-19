import PlotterModel

struct DrawingWireSegment: Sendable {
  /// Inclusive source segment range represented by this controller request.
  /// Collapsed vertices remain mapped, including residue at a stroke's end.
  let sourceSegmentRange: ClosedRange<Int>
  let delta: Vector2<MachineSpace>
  let intendedEndpoint: Point2<MachineSpace>
}

struct DrawingWireStroke: Sendable {
  let strokeID: StrokeID
  let segments: [DrawingWireSegment]
}

enum DrawingWireScheduleError: Error, Equatable, Sendable {
  case unrepresentableStroke(StrokeID)
  case invalidWireGeometry(StrokeID)

  var refusal: DrawingPlanRefusal {
    switch self {
    case .unrepresentableStroke(let id): .unrepresentableStroke(id)
    case .invalidWireGeometry(let id): .invalidWireGeometry(id)
    }
  }
}

/// A controller serialization schedule derived from the immutable intended
/// geometry. It does not mutate the plan, create checkpoints, or bridge strokes.
/// Cumulative offsets bound interior component error to half a wire unit.
/// At a non-grid boundary the nearest contained offset rounds inward by less
/// than one unit. Both use the admitted region's numerical epsilon, never pose
/// settlement tolerance or a rebase to measured MPos.
struct DrawingWireSchedule: Sendable {
  let strokes: [DrawingWireStroke]
  var segmentCount: Int { strokes.reduce(0) { $0 + $1.segments.count } }

  init(plan: ExecutionPlanRevision) throws(DrawingWireScheduleError) {
    var result: [DrawingWireStroke] = []
    result.reserveCapacity(plan.strokes.count)
    for stroke in plan.strokes {
      result.append(try Self.stroke(stroke, bounds: plan.drawableRegion.effectiveBounds))
    }
    strokes = result
  }

  private static func stroke(_ stroke: PlannedMachineStroke, bounds: AxisAlignedBounds<MachineSpace>)
    throws(DrawingWireScheduleError) -> DrawingWireStroke {
    let origin = stroke.path.start
    guard let xInterval = containedUnits(minimum: bounds.minX, maximum: bounds.maxX, origin: origin.x),
      let yInterval = containedUnits(minimum: bounds.minY, maximum: bounds.maxY, origin: origin.y) else {
      throw .invalidWireGeometry(stroke.logicalStrokeID)
    }
    var previousX: Int64 = 0
    var previousY: Int64 = 0
    var segments: [DrawingWireSegment] = []
    for (index, point) in stroke.path.points.dropFirst().enumerated() {
      let dx = point.x - origin.x
      let dy = point.y - origin.y
      guard let nearestX = MachineWirePrecision.units(dx), let nearestY = MachineWirePrecision.units(dy) else {
        throw .invalidWireGeometry(stroke.logicalStrokeID)
      }
      let x = min(xInterval.upperBound, max(xInterval.lowerBound, nearestX))
      let y = min(yInterval.upperBound, max(yInterval.lowerBound, nearestY))
      let roundedX = Double(x) / MachineWirePrecision.unitsPerMillimetre
      let roundedY = Double(y) / MachineWirePrecision.unitsPerMillimetre
      // The epsilon admits only floating-point subtraction residue. This is
      // independent of the much larger controller pose-settlement tolerance.
      let xBound = x == nearestX ? MachineWirePrecision.maximumComponentRoundingErrorMM
        : 1 / MachineWirePrecision.unitsPerMillimetre
      let yBound = y == nearestY ? MachineWirePrecision.maximumComponentRoundingErrorMM
        : 1 / MachineWirePrecision.unitsPerMillimetre
      guard abs(roundedX - dx) <= xBound + 1e-12, abs(roundedY - dy) <= yBound + 1e-12,
        let endpoint = try? Point2<MachineSpace>(x: origin.x + roundedX, y: origin.y + roundedY),
        DrawingRegionContainmentPolicy.contains(endpoint, in: bounds) else {
        throw .invalidWireGeometry(stroke.logicalStrokeID)
      }
      if x == previousX, y == previousY {
        if let previous = segments.last {
          segments[segments.count - 1] = DrawingWireSegment(
            sourceSegmentRange: previous.sourceSegmentRange.lowerBound...index,
            delta: previous.delta, intendedEndpoint: point)
        }
        continue
      }
      let (xUnits, xOverflow) = x.subtractingReportingOverflow(previousX)
      let (yUnits, yOverflow) = y.subtractingReportingOverflow(previousY)
      let wireX = Double(xUnits) / MachineWirePrecision.unitsPerMillimetre
      let wireY = Double(yUnits) / MachineWirePrecision.unitsPerMillimetre
      guard !xOverflow, !yOverflow,
        MachineWirePrecision.units(wireX) == xUnits, MachineWirePrecision.units(wireY) == yUnits,
        let delta = try? Vector2<MachineSpace>(dx: wireX, dy: wireY) else {
        throw .invalidWireGeometry(stroke.logicalStrokeID)
      }
      let sourceStart = segments.last.map { $0.sourceSegmentRange.upperBound + 1 } ?? 0
      segments.append(DrawingWireSegment(sourceSegmentRange: sourceStart...index,
        delta: delta, intendedEndpoint: point))
      previousX = x
      previousY = y
    }
    guard !segments.isEmpty else { throw .unrepresentableStroke(stroke.logicalStrokeID) }
    return DrawingWireStroke(strokeID: stroke.logicalStrokeID, segments: segments)
  }

  private static func containedUnits(minimum: Double, maximum: Double, origin: Double) -> ClosedRange<Int64>? {
    // The existing containment epsilon absorbs only roundoff in transformed
    // boundary points. It is not an extra physical movement allowance.
    let epsilon = DrawingRegionContainmentPolicy.numericalEpsilonMM
    let lower = ((minimum - origin - epsilon) * MachineWirePrecision.unitsPerMillimetre).rounded(.up)
    let upper = ((maximum - origin + epsilon) * MachineWirePrecision.unitsPerMillimetre).rounded(.down)
    guard let lower = Int64(exactly: lower), let upper = Int64(exactly: upper), lower <= upper else { return nil }
    return lower...upper
  }
}
