import Foundation
import Observation
import PlotterModel

struct PortraitSavedSketch: Identifiable {
  let id: UUID
  let program: DrawingProgram
  let title: String
  var rating: Int
}

/// Session-only comparisons retain immutable vectors, never extra raw photos.
@Observable @MainActor
final class PortraitSketchCollection {
  static let maximumCount = 8
  static let maximumPointCount = 200_000
  private(set) var sketches: [PortraitSavedSketch] = []
  var selectedID: UUID?
  var selected: PortraitSavedSketch? { sketches.first { $0.id == selectedID } }

  @discardableResult
  func keep(_ program: DrawingProgram, title: String) -> String? {
    if let existing = sketches.first(where: { $0.program.contentHash == program.contentHash }) {
      selectedID = existing.id
      return nil
    }
    let points = program.strokes.reduce(0) { $0 + $1.path.points.count }
    guard points <= Self.maximumPointCount else {
      return "This sketch is too detailed to keep. Increase simplification or reduce tonal levels."
    }
    let sketch = PortraitSavedSketch(id: UUID(), program: program, title: title, rating: 0)
    sketches.append(sketch)
    while sketches.count > Self.maximumCount || sketches.reduce(0, { total, item in
      total + item.program.strokes.reduce(0) { $0 + $1.path.points.count }
    }) > Self.maximumPointCount {
      sketches.removeFirst()
    }
    selectedID = sketch.id
    return nil
  }

  func rate(_ id: UUID, rating: Int) {
    guard let index = sketches.firstIndex(where: { $0.id == id }) else { return }
    sketches[index].rating = min(5, max(0, rating))
  }

  func remove(_ id: UUID) {
    sketches.removeAll { $0.id == id }
    if selectedID == id { selectedID = nil }
  }
}
