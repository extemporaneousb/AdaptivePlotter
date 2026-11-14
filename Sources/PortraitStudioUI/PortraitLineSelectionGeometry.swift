import CoreGraphics
import Foundation
import PlotterModel

/// Screen-space picking uses the exact displayed polyline, including segments
/// crossing a lasso whose vertices lie outside it. No raster tracing is involved.
package struct PortraitLineSelectionGeometry {
  package struct Line {
    package let id: StrokeID
    package let points: [CGPoint]
    package let bounds: CGRect
    package let width: CGFloat
  }
  package let lines: [Line]
  package let page: CGRect

  package init(program: DrawingProgram, size: CGSize) {
    let margin = 16.0 + (program.strokes.lazy.map { $0.style.nominalLineWidth }.max() ?? 0)
    let scale = max(0.001, min(max(1, size.width - margin * 2) / program.fieldExtent.width,
      max(1, size.height - margin * 2) / program.fieldExtent.height))
    let width = program.fieldExtent.width * scale, height = program.fieldExtent.height * scale
    page = CGRect(x: (size.width-width)/2, y: (size.height-height)/2, width: width, height: height)
    let origin = page.origin
    lines = program.strokes.map { stroke in
      var points: [CGPoint] = []
      points.reserveCapacity(stroke.path.points.count)
      var minX = CGFloat.infinity, minY = CGFloat.infinity
      var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
      for point in stroke.path.points {
        let transformed = CGPoint(x: origin.x + point.x * scale, y: origin.y + height - point.y * scale)
        points.append(transformed)
        minX = min(minX, transformed.x); minY = min(minY, transformed.y)
        maxX = max(maxX, transformed.x); maxY = max(maxY, transformed.y)
      }
      return Line(id: stroke.id, points: points,
        bounds: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
        width: stroke.style.nominalLineWidth * scale)
    }
  }

  package func hit(_ point: CGPoint, excluding: Set<StrokeID>, tolerance: CGFloat = 7) -> StrokeID? {
    var best: StrokeID?, distance = CGFloat.infinity
    for line in lines where !excluding.contains(line.id) {
      let radius = tolerance + line.width / 2
      guard line.bounds.insetBy(dx: -radius, dy: -radius).contains(point) else { continue }
      for (a,b) in zip(line.points, line.points.dropFirst()) {
        let d = Self.distance(point, a, b)
        if d <= radius, d < distance { best = line.id; distance = d }
      }
    }
    return best
  }

  package func lasso(_ polygon: [CGPoint], excluding: Set<StrokeID>) -> Set<StrokeID> {
    guard polygon.count >= 3, polygon.count <= 512, polygon.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return [] }
    let edges = Array(zip(polygon, Array(polygon.dropFirst()) + [polygon[0]]))
    let xs = polygon.map(\.x), ys = polygon.map(\.y)
    let bounds = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()!-xs.min()!, height: ys.max()!-ys.min()!).insetBy(dx: -0.01, dy: -0.01)
    var selected = Set<StrokeID>()
    for line in lines where !excluding.contains(line.id) {
      guard line.bounds.insetBy(dx: -0.01, dy: -0.01).intersects(bounds) else { continue }
      if line.points.contains(where: { Self.inside($0, edges) })
        || zip(line.points, line.points.dropFirst()).contains(where: { a,b in edges.contains { c,d in Self.intersects(a,b,c,d) } }) {
        selected.insert(line.id)
      }
    }
    return selected
  }

  private static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = b.x-a.x, dy = b.y-a.y, length = dx*dx+dy*dy
    let t = length > 0 ? min(1, max(0, ((p.x-a.x)*dx+(p.y-a.y)*dy)/length)) : 0
    return hypot(p.x-a.x-t*dx, p.y-a.y-t*dy)
  }
  private static func inside(_ p: CGPoint, _ edges: [(CGPoint, CGPoint)]) -> Bool {
    var inside = false
    for (a,b) in edges {
      if distance(p,a,b) < 0.01 { return true }
      if (a.y > p.y) != (b.y > p.y), p.x < (b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x { inside.toggle() }
    }
    return inside
  }
  private static func intersects(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
    func cross(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> CGFloat { (q.x-p.x)*(r.y-p.y)-(q.y-p.y)*(r.x-p.x) }
    let abC = cross(a,b,c), abD = cross(a,b,d), cdA = cross(c,d,a), cdB = cross(c,d,b)
    if abC * abD < 0 && cdA * cdB < 0 { return true }
    return distance(a,c,d) < 0.01 || distance(b,c,d) < 0.01 || distance(c,a,b) < 0.01 || distance(d,a,b) < 0.01
  }
}
