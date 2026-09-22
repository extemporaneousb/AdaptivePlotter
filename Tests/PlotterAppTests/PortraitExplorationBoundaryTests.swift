import Foundation
import PlotterModel
import Testing
@testable import PlotterApp

@Suite("Portrait exploration footprint boundaries")
struct PortraitExplorationBoundaryTests {
  @Test("Bitset footprint matches the historical Set rasterization at word and image boundaries",
    arguments: [0.4, 1.8, 4.0, 6.0, 14.0])
  func referenceParity(penWidth: Double) throws {
    let paths: [[CGPoint]] = [
      [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 127)],
      [CGPoint(x: 63, y: 0), CGPoint(x: 63, y: 127)],
      [CGPoint(x: 64, y: 0), CGPoint(x: 64, y: 127)],
      [CGPoint(x: 127, y: 0), CGPoint(x: 127, y: 127)],
      [CGPoint(x: 0, y: 0), CGPoint(x: 127, y: 127)],
      [CGPoint(x: 0, y: 127), CGPoint(x: 127, y: 0)],
      [CGPoint(x: 60.49, y: 0), CGPoint(x: 65.51, y: 3), CGPoint(x: 127, y: 3)],
    ]
    // Isolated paths catch spurious carries that a dense composite could hide.
    for path in paths {
      let program = try footprintProgram([path], penWidth: penWidth)
      let actual = PortraitExplorationPolicy.VisibleGeometry(program)
      let reference = SetFootprintReference(program)
      #expect(footprintCells(actual.ink) == reference.ink)
      #expect(footprintCells(actual.nearbyInk) == reference.nearbyInk)
      #expect(actual.inkCount == reference.ink.count)
    }
    for extent in [CGSize(width: 127, height: 127), CGSize(width: 254, height: 127)] {
      let program = try footprintProgram(paths, penWidth: penWidth, extent: extent)
      let actual = PortraitExplorationPolicy.VisibleGeometry(program)
      let reference = SetFootprintReference(program)
      #expect(footprintCells(actual.ink) == reference.ink)
      #expect(footprintCells(actual.nearbyInk) == reference.nearbyInk)
      #expect(actual.inkCount == reference.ink.count)
    }
  }

  @Test("One-pixel dilation crosses the 63/64 word seam without wrapping image rows")
  func wordCarriesAndClipping() throws {
    for x in [0, 63, 64, 127] {
      let program = try footprintProgram([[CGPoint(x: x, y: 50), CGPoint(x: x, y: 51)]])
      let actual = PortraitExplorationPolicy.VisibleGeometry(program)
      let cells = footprintCells(actual.nearbyInk)
      let expected = Set((49...52).flatMap { y in
        (max(0, x - 1)...min(127, x + 1)).map { y * 128 + $0 }
      })
      #expect(cells == expected)
      #expect(actual.inkCount == 2)
      if x == 63 { #expect(cells.contains(50 * 128 + 64)) }
      if x == 64 { #expect(cells.contains(50 * 128 + 63)) }
      if x == 127 { #expect(!cells.contains(51 * 128)) }
      if x == 0 { #expect(!cells.contains(49 * 128 + 127)) }
    }
  }

  @Test("Bitset visual-distance decisions retain the six-sample and relative-ink floors")
  func decisionParity() throws {
    var programs: [DrawingProgram] = []
    for width in [0.4, 4.0, 14.0] {
      for offset in [0.0, 0.01, 1.0, 2.0, 8.0] {
        programs.append(try footprintProgram([
          [CGPoint(x: 63 + offset, y: 15), CGPoint(x: 63 + offset, y: 95)],
          [CGPoint(x: 50 + offset, y: 50), CGPoint(x: 90 + offset, y: 50)],
        ], penWidth: width))
      }
    }
    let actual = programs.map(PortraitExplorationPolicy.VisibleGeometry.init)
    let reference = programs.map(SetFootprintReference.init)
    for a in programs.indices {
      for b in programs.indices {
        #expect(actual[a].isMeaningfullyDifferent(from: actual[b])
          == reference[a].isMeaningfullyDifferent(from: reference[b]))
      }
    }
    for length in [1, 2] {
      let left = try footprintProgram([[CGPoint(x: 30, y: 40), CGPoint(x: 30, y: 40 + length)]])
      let right = try footprintProgram([[CGPoint(x: 32, y: 40), CGPoint(x: 32, y: 40 + length)]])
      let a = PortraitExplorationPolicy.VisibleGeometry(left), b = PortraitExplorationPolicy.VisibleGeometry(right)
      #expect(a.isMeaningfullyDifferent(from: b) == (length == 2))
    }
  }
}

private func footprintProgram(_ paths: [[CGPoint]], penWidth: Double = 0.4,
  extent: CGSize = CGSize(width: 127, height: 127)) throws -> DrawingProgram {
  let style = try StrokeStyle(nominalLineWidth: penWidth, penProfileID: PenProfileID())
  let strokes = try paths.enumerated().map { index, path in
    try LogicalStroke(id: StrokeID(), path: Polyline(points: path.map {
      try Point2<FieldSpace>(x: $0.x, y: $0.y)
    }), style: style, ordering: UInt32(index))
  }
  return try DrawingProgram(id: ProgramID(), fieldExtent: .init(width: extent.width, height: extent.height),
    strokes: strokes, source: .init(kind: "fixture", sourceIdentifier: "footprint-boundaries"))
}

private func footprintCells(_ words: [UInt64]) -> Set<Int> {
  var cells = Set<Int>()
  for (index, word) in words.enumerated() {
    for bit in 0..<64 where word & (UInt64(1) << bit) != 0 { cells.insert(index * 64 + bit) }
  }
  return cells
}

/// The pre-bitset implementation is retained here as an independent Set oracle.
/// In particular, neighborhood expansion never uses word shifts or bit carries.
private struct SetFootprintReference {
  let ink: Set<Int>
  let nearbyInk: Set<Int>
  private static let side = 128

  init(_ program: DrawingProgram) {
    let scale = Double(Self.side - 1) / max(program.fieldExtent.width, program.fieldExtent.height)
    var ink = Set<Int>()
    for stroke in program.strokes {
      let radius = min(3, max(0, Int((stroke.style.nominalLineWidth * scale / 2).rounded())))
      for (a, b) in zip(stroke.path.points, stroke.path.points.dropFirst()) {
        let ax = a.x * scale, ay = a.y * scale, bx = b.x * scale, by = b.y * scale
        let count = min(256, max(1, Int(ceil(max(abs(bx - ax), abs(by - ay))))))
        for step in 0...count {
          let t = Double(step) / Double(count)
          let x = Int((ax + (bx - ax) * t).rounded()), y = Int((ay + (by - ay) * t).rounded())
          for dy in -radius...radius { for dx in -radius...radius {
            let px = x + dx, py = y + dy
            if (0..<Self.side).contains(px), (0..<Self.side).contains(py) {
              ink.insert(py * Self.side + px)
            }
          } }
        }
      }
    }
    self.ink = ink
    var nearby = ink
    for cell in ink {
      let x = cell % Self.side, y = cell / Self.side
      for dy in -1...1 { for dx in -1...1 {
        let px = x + dx, py = y + dy
        if (0..<Self.side).contains(px), (0..<Self.side).contains(py) {
          nearby.insert(py * Self.side + px)
        }
      } }
    }
    nearbyInk = nearby
  }

  func isMeaningfullyDifferent(from other: Self) -> Bool {
    let changed = ink.subtracting(other.nearbyInk).count + other.ink.subtracting(nearbyInk).count
    return changed >= max(6, Int(ceil(Double(ink.count + other.ink.count) * 0.03)))
  }
}
